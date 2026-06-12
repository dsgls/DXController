#!/usr/bin/env python3
"""Generate the DXController controller-settings menu-background tile sets.

The controller settings page (MenuScreenController) shows a variable
number of option rows depending on the selected stick response curves.
Each stick contributes 2 rows (Linear), 3 (Power/Expo), or 5 (Sigmoid),
plus one always-visible sensitivity row for the right stick, and the page
packs them contiguously from the top, so the panel only ever needs
recesses for the *total* visible-row count. We render one tile set per
possible total (ROW_COUNTS below) and the menu swaps to the matching set
at runtime.

For each row count N, the composite is a 768x512 image cut into a 2x3
grid of 256x256 tiles so MenuUIClientWindow's hardcoded 256-grid
placement (texturePosX/Y[i] = col*256, row*256) drops each tile in the
right place:

  MenuControllerBackground_N_1.png  256x256  at (  0,   0)
  MenuControllerBackground_N_2.png  256x256  at (256,   0)
  MenuControllerBackground_N_3.png  256x256  at (512,   0)  [right 48 px clipped]
  MenuControllerBackground_N_4.png  256x256  at (  0, 256)
  MenuControllerBackground_N_5.png  256x256  at (256, 256)
  MenuControllerBackground_N_6.png  256x256  at (512, 256)  [right 48/bottom 32 clipped]

MenuScreenController has ClientWidth=720, ClientHeight=480, so the
composite right-edge 48 px and bottom 32 px fall outside the visible
client area and need no special content. The visible border lives at
x=719 and y=479 in texture space.

Each visible row is an [action-button | value-button] recess pair; the
layout mirrors MenuUIScreenWindow + MenuUIChoice. Dimensions taken from:

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

# Visible-row totals the controller settings page can show. Each stick
# contributes 2 rows (Linear), 3 (Power/Expo), or 5 (Sigmoid); the right
# stick adds one always-visible sensitivity row; the page shows the sum.
# 10 is unreachable (no l in {2,3,5}, r in {3,4,6} sum to 10). One tile
# set is rendered per total -> [5, 6, 7, 8, 9, 11].
ROW_COUNTS = sorted({l + r for l in (2, 3, 5) for r in (3, 4, 6)})

# Row layout — mirrors MenuUIScreenWindow + MenuUIChoice. Every visible
# row is an [action-button | value-button] recess pair.
ROW_X     = 7
ROW_Y0    = 27
ROW_GAP   = 36
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

# Crop rectangles (left, top, right, bottom) for the six 256x256 tiles of
# the 768x512 composite. Tile index (1..6) is the list position + 1.
TILE_RECTS = [
    (0,   0,   256, 256),
    (256, 0,   512, 256),
    (512, 0,   768, 256),
    (0,   256, 256, 512),
    (256, 256, 512, 512),
    (512, 256, 768, 512),
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


def compose(num_rows):
    """Build the full 768x512 composite for a `num_rows`-row layout.

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

    # Row recesses: an [action button | value button] pair per visible
    # row. Every row has a value-cycling control, so both columns are
    # stamped for all rows.
    for n in range(num_rows):
        y = ROW_Y0 + n * ROW_GAP
        stamp_row_recess(img, ROW_X, y, BTN_W, BTN_H, all_interiors, halo_seeds)
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
    for num_rows in ROW_COUNTS:
        full = compose(num_rows)
        for idx, (x0, y0, x1, y1) in enumerate(TILE_RECTS, start=1):
            tile = full.crop((x0, y0, x1, y1))
            tile.save(out_dir / f"MenuControllerBackground_{num_rows}_{idx}.png")
        # The composites are a visual sanity check for standalone runs;
        # suppress them from the build so png-to-pcx doesn't ship stray
        # *_full.pcx files alongside the real tiles.
        if standalone:
            full.save(out_dir / f"MenuControllerBackground_{num_rows}_full.png")
    n_tiles = len(ROW_COUNTS) * len(TILE_RECTS)
    print(f"wrote {n_tiles} tiles{' + composites' if standalone else ''} to {out_dir}")


if __name__ == "__main__":
    main()
