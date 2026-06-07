#!/usr/bin/env python3
"""Generate the DXController menu-background tile set.

Outputs 6 PNGs into OUT_DIR (default: 'menu-bg-gen' next to this script).
The composite is a 768x512 image cut into a 2x3 grid of 256x256 tiles so
MenuUIClientWindow's hardcoded 256-grid placement (texturePosX/Y[i] =
col*256, row*256) drops each tile in the right place:

  MenuBg_1.png  256x256  at (  0,   0)
  MenuBg_2.png  256x256  at (256,   0)
  MenuBg_3.png  256x256  at (512,   0)  [right 48 px clipped]
  MenuBg_4.png  256x256  at (  0, 256)
  MenuBg_5.png  256x256  at (256, 256)
  MenuBg_6.png  256x256  at (512, 256)  [right 48 px and bottom 32 px clipped]

MenuScreenController has ClientWidth=720, ClientHeight=480, so the
composite right-edge 48 px and bottom 32 px fall outside the visible
client area and need no special content. The visible border lives at
x=719 and y=479 in texture space.

Layout drawn into the visible 720x480 area mirrors the worst-case
(sigmoid+sigmoid) row count: 11 rows of [action-button | value-button]
recesses plus the help-text bar. Dimensions taken from:

  MenuScreenController.uc       (ClientWidth/Height, helpPosY)
  MenuUIScreenWindow.uc         (choiceStartX/Y, choiceVerticalGap)
  MenuUIChoice.uc               (choiceControlPosX=270)
  MenuUIChoiceEnum.uc           (defaultInfoWidth=77, defaultInfoPosX=270)
  MenuUIChoiceButton.uc         (SetWidth(243))
  MenuUIActionButtonWindow.uc   (buttonHeight=19)
  MenuUIWindow.uc               (defaultHelpHeight=27,
                                 defaultHelpLeftOffset=7,
                                 defaultHelpClientDiffY=21)

Style sampled from MenuGameOptionsBackground_{1..6}.pcx:
  - Lighter neutral-grey panel base with a 2-px faux scanline.
  - Every recess wrapped in a 1-px black rim, with a bright "halo" glow
    on the panel side that peaks at L~85 right outside the rim and fades
    over ~8 px.
  - Asymmetric shapes — small top-left notch, larger bottom-right notch.

Deterministic: identical PARAMETERS produce byte-identical output. All
tuning knobs live in the PARAMETERS block below — edit them to change
the look, then rebuild.

Run via the build (sync-and-build.sh), or standalone:
  python3 gen-menu-bg.py [OUT_DIR]
"""
import sys
from collections import deque
from pathlib import Path

from PIL import Image

# ===== PARAMETERS ============================================================
# Visible client area (MenuScreenController.ClientWidth/Height). Pixels
# outside this rectangle are clipped by the client window — content
# placed there is harmless but invisible.
CLIENT_W = 720
CLIENT_H = 480

# Composite dimensions — 2 rows x 3 cols of 256x256 tiles. The engine's
# hardcoded 256-grid forces this shape; we just pay the right-edge and
# bottom-edge waste in exchange for the visible area we need.
W, H = 768, 512

# Row layout — mirrors MenuUIScreenWindow + MenuUIChoice. NUM_ROWS is the
# sigmoid+sigmoid maximum: 1 Apply + 5 left-stick (deadzone, curve type,
# 3 sigmoid params) + 5 right-stick (same). Other curve combinations
# show fewer rows but the recesses we render still line up with rows
# 0..N-1.
ROW_X     = 7
ROW_Y0    = 27
ROW_GAP   = 36
NUM_ROWS  = 11
BTN_W     = 243
BTN_H     = 19
VAL_X     = ROW_X + 270   # row pos + MenuUIChoiceEnum.defaultInfoPosX
VAL_W     = 77
VAL_H     = 19

# Help/info bar (MenuUIWindow.ConfigurationChanged geometry).
HELP_X = 7
HELP_Y = 438              # MenuScreenController.helpPosY
HELP_W = CLIENT_W - 21    # CLIENT_W - defaultHelpClientDiffY
HELP_H = 27               # defaultHelpHeight

PANEL_HI = (37, 37, 37)
PANEL_LO = (33, 33, 33)

INSET_HI = (22, 22, 22)
INSET_LO = (18, 18, 18)

# Halo luma boost by distance from element edge (idx 0 unused). Tuned to
# match the vanilla decay profile sampled near button rims.
HALO_BOOST = [0, 48, 38, 30, 22, 16, 11, 7, 4, 2]

BLACK = (0, 0, 0)

TILES = [
    ("MenuBg_1", (0,   0,   256, 256)),
    ("MenuBg_2", (256, 0,   512, 256)),
    ("MenuBg_3", (512, 0,   768, 256)),
    ("MenuBg_4", (0,   256, 256, 512)),
    ("MenuBg_5", (256, 256, 512, 512)),
    ("MenuBg_6", (512, 256, 768, 512)),
]
# ============================================================================


def panel_color(y):
    return PANEL_HI if (y % 2 == 0) else PANEL_LO


def clamp(v):
    return 0 if v < 0 else (255 if v > 255 else v)


def fill_scanlines(img, x0, y0, x1, y1, hi, lo):
    px = img.load()
    for y in range(y0, y1):
        c = hi if (y % 2 == 0) else lo
        for x in range(x0, x1):
            px[x, y] = c


def hline(img, x0, x1, y, color):
    px = img.load()
    for x in range(x0, x1):
        px[x, y] = color


def vline(img, x, y0, y1, color):
    px = img.load()
    for y in range(y0, y1):
        px[x, y] = color


def element_interior(x0, y0, x1, y1, notch_tl, notch_br):
    """Pixel set for a UI element with asymmetric chamfered corners."""
    interior = set()
    for y in range(y0, y1):
        if y - y0 < notch_tl:
            dy = notch_tl - (y - y0)
            lx = x0 + dy
        else:
            lx = x0
        if y1 - 1 - y < notch_br:
            dy = notch_br - (y1 - 1 - y)
            rx = x1 - dy
        else:
            rx = x1
        for x in range(lx, rx):
            interior.add((x, y))
    return interior


def edge_pixels(interior):
    edges = set()
    for x, y in interior:
        for nx, ny in ((x + 1, y), (x - 1, y), (x, y + 1), (x, y - 1)):
            if (nx, ny) not in interior and 0 <= nx < W and 0 <= ny < H:
                edges.add((nx, ny))
    return edges


def stamp_element(img, interior, face_hi, face_lo, all_interiors, halo_seeds):
    """Fill element face, draw 1-px black rim outside, and grow `halo_seeds`
    with the next ring out (where the halo glow will be painted)."""
    px = img.load()
    for (x, y) in interior:
        px[x, y] = face_hi if (y % 2 == 0) else face_lo
    rim = edge_pixels(interior)
    for (x, y) in rim:
        px[x, y] = BLACK
    for x, y in rim:
        for nx, ny in ((x + 1, y), (x - 1, y), (x, y + 1), (x, y - 1)):
            if (nx, ny) in interior or (nx, ny) in rim:
                continue
            if not (0 <= nx < W and 0 <= ny < H):
                continue
            halo_seeds.add((nx, ny))
    all_interiors |= interior


def paint_halo(img, halo_seeds, all_interiors):
    """BFS outward from halo_seeds and brighten panel pixels per HALO_BOOST."""
    px = img.load()
    blend_len = len(HALO_BOOST) - 1
    dist = {p: 1 for p in halo_seeds}
    q = deque(halo_seeds)
    while q:
        x, y = q.popleft()
        d = dist[(x, y)]
        if d > blend_len:
            continue
        if px[x, y] != BLACK and (x, y) not in all_interiors:
            base = panel_color(y)[0]
            v = clamp(base + HALO_BOOST[d])
            px[x, y] = (v, v, v)
        if d == blend_len:
            continue
        for nx, ny in ((x + 1, y), (x - 1, y), (x, y + 1), (x, y - 1)):
            if not (0 <= nx < W and 0 <= ny < H):
                continue
            if (nx, ny) in all_interiors or (nx, ny) in dist:
                continue
            if px[nx, ny] == BLACK:
                continue
            dist[(nx, ny)] = d + 1
            q.append((nx, ny))


def stamp_row_recess(img, x, y, w, h, all_interiors, halo_seeds,
                     notch_tl=3, notch_br=6):
    """Recess sized exactly to a row button (the button border textures
    sit on top of this dark fill). Notch depths mirror the vanilla
    button border art (MenuActionButtonNormal_Left has a ~3-px top-left
    chamfer; MenuActionButtonNormal_Right has a ~6x6 bottom-right
    chamfer) so the recess corners line up with the button corners."""
    interior = element_interior(x, y, x + w, y + h, notch_tl, notch_br)
    stamp_element(img, interior, INSET_HI, INSET_LO, all_interiors, halo_seeds)


def compose():
    """Build the full 768x512 composite.

    Content sits inside the visible 720x480 client area. The 48-px right
    and 32-px bottom strips outside that rectangle hold only scanlined
    panel — they're clipped before reaching the screen.
    """
    img = Image.new("RGB", (W, H), PANEL_HI)
    fill_scanlines(img, 0, 0, W, H, PANEL_HI, PANEL_LO)

    # Outer 1-px black border around the visible client area. The texture
    # extends past the client; pixels past the border would be clipped.
    hline(img, 0, CLIENT_W, 0, BLACK)
    hline(img, 0, CLIENT_W, CLIENT_H - 1, BLACK)
    vline(img, 0, 0, CLIENT_H, BLACK)
    vline(img, CLIENT_W - 1, 0, CLIENT_H, BLACK)

    all_interiors = set()
    halo_seeds = set()

    # Row recesses: [action button | value button] for the max-case
    # 11-row layout. Rows beyond what the active curve combination
    # displays are still drawn — the texture is static, but the empty
    # recesses read as part of the panel layout rather than noise.
    # Row 0 (Apply Recommended) has no value-cycling control, so its
    # value-column slot stays empty.
    for n in range(NUM_ROWS):
        y = ROW_Y0 + n * ROW_GAP
        stamp_row_recess(img, ROW_X, y, BTN_W, BTN_H, all_interiors, halo_seeds)
        if n != 0:
            stamp_row_recess(img, VAL_X, y, VAL_W, VAL_H, all_interiors, halo_seeds)

    # Help/info bar — wider, taller, larger corner notches than the row
    # recesses to give it visual weight as a separate region.
    help_interior = element_interior(
        HELP_X, HELP_Y, HELP_X + HELP_W, HELP_Y + HELP_H,
        notch_tl=3, notch_br=6,
    )
    stamp_element(img, help_interior, INSET_HI, INSET_LO, all_interiors, halo_seeds)

    paint_halo(img, halo_seeds, all_interiors)
    return img


def main():
    standalone = len(sys.argv) <= 1
    out_dir = Path(sys.argv[1]) if not standalone else Path(__file__).parent / "menu-bg-gen"
    out_dir.mkdir(parents=True, exist_ok=True)
    full = compose()
    for name, (x0, y0, x1, y1) in TILES:
        tile = full.crop((x0, y0, x1, y1))
        tile.save(out_dir / f"{name}.png")
    # The composite is a visual sanity check for standalone runs; suppress
    # it when invoked from the build so png-to-pcx doesn't ship a stray
    # MenuBg_full.pcx alongside the real tiles.
    if standalone:
        full.save(out_dir / "MenuBg_full.png")
    print(f"wrote 6 tiles{' + composite' if standalone else ''} to {out_dir}")


if __name__ == "__main__":
    main()
