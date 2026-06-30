#!/usr/bin/env python3
"""Generate DXController menu-background tile sets for multiple page specs.

Drives a list of page specs (controller settings + autosave) and produces
one tile set per page × row-count combination. The controller settings page
uses one tile set per possible total row count (the menu swaps sets at
runtime); the autosave page has a fixed 3-row layout so it emits a single
tile set with no _N_ infix.

For each composite the image is cut into 256×256 tiles so
MenuUIClientWindow's hardcoded 256-grid placement (texturePosX/Y[i] =
col*256, row*256) drops each tile in the right place.

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
# Per-page specs. Each page's recesses are positioned from client_w/client_h/
# help_y, which MUST match the screen class's defaultproperties exactly:
#   MenuControllerBackground -> MenuScreenController.uc
#   MenuAutoSaveBackground   -> MenuScreenAutoSave.uc
#
# 10 rows is unreachable for the controller page (no l in {2,3,5}, r in
# {3,4,6} sum to 10); its row-count set is [5,6,7,8,9,11]. The autosave page
# has a fixed 3-row layout -> a single tile set with no _N_ infix.
PAGES = [
    dict(
        prefix="MenuControllerBackground",
        client_w=720, client_h=480, help_y=438,
        row_counts=sorted({l + r for l in (2, 3, 5) for r in (3, 4, 6)}),
        single_set=False,
    ),
    dict(
        prefix="MenuAutoSaveBackground",
        client_w=400, client_h=200, help_y=160,
        row_counts=[3],
        single_set=True,
    ),
]

# Shared row layout — mirrors MenuUIScreenWindow + MenuUIChoice. Every visible
# row is an [action-button | value-button] recess pair. Identical for any
# options screen, so it is page-independent.
ROW_X     = 7
ROW_Y0    = 27
ROW_GAP   = 36
BTN_W     = 243
BTN_H     = 19
VAL_X     = ROW_X + 270   # row pos + MenuUIChoiceEnum.defaultInfoPosX
VAL_W     = 77
VAL_H     = 19

# Help/info bar geometry shared except for its Y (per-page help_y).
HELP_X = 7
HELP_H = 27               # defaultHelpHeight

PANEL_HI = (37, 37, 37)
PANEL_LO = (33, 33, 33)

INSET_HI = (22, 22, 22)
INSET_LO = (18, 18, 18)

# Halo luma boost by distance from element edge (idx 0 unused).
HALO_BOOST = [0, 48, 38, 30, 22, 16, 11, 7, 4, 2]

BLACK = (0, 0, 0)
# ============================================================================


def tile_grid(client_w, client_h):
    """Composite size and 256-px tile crop rects covering the client area.
    Width/height round up to whole 256-px tiles; the engine's
    MenuUIClientWindow places tile i at (col*256, row*256)."""
    cols = (client_w + 255) // 256
    rows = (client_h + 255) // 256
    W, H = cols * 256, rows * 256
    rects = []
    for r in range(rows):
        for c in range(cols):
            rects.append((c * 256, r * 256, c * 256 + 256, r * 256 + 256))
    return W, H, rects


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


def edge_pixels(interior, W, H):
    edges = set()
    for x, y in interior:
        for nx, ny in ((x + 1, y), (x - 1, y), (x, y + 1), (x, y - 1)):
            if (nx, ny) not in interior and 0 <= nx < W and 0 <= ny < H:
                edges.add((nx, ny))
    return edges


def stamp_element(img, interior, face_hi, face_lo, all_interiors, halo_seeds, W, H):
    """Fill element face, draw 1-px black rim outside, and grow `halo_seeds`."""
    px = img.load()
    for (x, y) in interior:
        px[x, y] = face_hi if (y % 2 == 0) else face_lo
    rim = edge_pixels(interior, W, H)
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


def paint_halo(img, halo_seeds, all_interiors, W, H):
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


def stamp_row_recess(img, x, y, w, h, all_interiors, halo_seeds, W, H,
                     notch_tl=3, notch_br=6):
    interior = element_interior(x, y, x + w, y + h, notch_tl, notch_br)
    stamp_element(img, interior, INSET_HI, INSET_LO, all_interiors, halo_seeds, W, H)


def compose(page, num_rows):
    """Build the composite for a `num_rows`-row layout of `page`."""
    client_w, client_h, help_y = page["client_w"], page["client_h"], page["help_y"]
    W, H, _ = tile_grid(client_w, client_h)

    img = Image.new("RGB", (W, H), PANEL_HI)
    fill_scanlines(img, 0, 0, W, H, PANEL_HI, PANEL_LO)

    # Outer 1-px black border around the visible client area.
    hline(img, 0, client_w, 0, BLACK)
    hline(img, 0, client_w, client_h - 1, BLACK)
    vline(img, 0, 0, client_h, BLACK)
    vline(img, client_w - 1, 0, client_h, BLACK)

    all_interiors = set()
    halo_seeds = set()

    for n in range(num_rows):
        y = ROW_Y0 + n * ROW_GAP
        stamp_row_recess(img, ROW_X, y, BTN_W, BTN_H, all_interiors, halo_seeds, W, H)
        stamp_row_recess(img, VAL_X, y, VAL_W, VAL_H, all_interiors, halo_seeds, W, H)

    help_w = client_w - 21    # client_w - defaultHelpClientDiffY
    help_interior = element_interior(
        HELP_X, help_y, HELP_X + help_w, help_y + HELP_H,
        notch_tl=3, notch_br=6,
    )
    stamp_element(img, help_interior, INSET_HI, INSET_LO, all_interiors, halo_seeds, W, H)

    paint_halo(img, halo_seeds, all_interiors, W, H)
    return img


def main():
    standalone = len(sys.argv) <= 1
    out_dir = Path(sys.argv[1]) if not standalone else Path(__file__).parent / "menu-bg-gen"
    out_dir.mkdir(parents=True, exist_ok=True)
    n_tiles = 0
    for page in PAGES:
        _, _, rects = tile_grid(page["client_w"], page["client_h"])
        for num_rows in page["row_counts"]:
            full = compose(page, num_rows)
            for idx, (x0, y0, x1, y1) in enumerate(rects, start=1):
                tile = full.crop((x0, y0, x1, y1))
                if page["single_set"]:
                    name = f"{page['prefix']}_{idx}.png"
                else:
                    name = f"{page['prefix']}_{num_rows}_{idx}.png"
                tile.save(out_dir / name)
                n_tiles += 1
            if standalone:
                if page["single_set"]:
                    full.save(out_dir / f"{page['prefix']}_full.png")
                else:
                    full.save(out_dir / f"{page['prefix']}_{num_rows}_full.png")
    print(f"wrote {n_tiles} tiles{' + composites' if standalone else ''} to {out_dir}")


if __name__ == "__main__":
    main()
