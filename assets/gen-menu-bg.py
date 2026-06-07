#!/usr/bin/env python3
"""Generate the DXController menu-background tile set.

Outputs 6 PNGs into OUT_DIR (default: 'menu-bg-gen' next to this script),
sized and positioned to match the vanilla MenuGameOptionsBackground tiles
so MenuUIClientWindow's hardcoded 256x256 grid (texturePosX/Y[i] =
col*256, row*256) renders them in the right place:

  MenuBg_1.png  256x256  at (  0,   0)
  MenuBg_2.png  256x256  at (256,   0)
  MenuBg_3.png   32x256  at (512,   0)
  MenuBg_4.png  256x256  at (  0, 256)
  MenuBg_5.png  256x256  at (256, 256)
  MenuBg_6.png   32x256  at (512, 256)

Style sampled from MenuGameOptionsBackground_{1..6}.pcx:
  - Lighter neutral-grey panel base with a 2-px faux scanline.
  - Every element (button, recess) wrapped in a 1-px black rim, with a
    bright "halo" glow on the panel side that peaks at L~85 right outside
    the rim and fades over ~8 px.
  - Asymmetric shapes — small top-left notch, larger bottom-right notch.
  - 1-px schematic traces between elements; 2x2 junction dots at corners.

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
PANEL_HI = (37, 37, 37)
PANEL_LO = (33, 33, 33)

BTN_HI = (60, 60, 60)
BTN_LO = (55, 55, 55)

INSET_HI = (22, 22, 22)
INSET_LO = (18, 18, 18)

# Halo luma boost by distance from element edge (idx 0 unused). Tuned to
# match the vanilla decay profile sampled near button rims.
HALO_BOOST = [0, 48, 38, 30, 22, 16, 11, 7, 4, 2]

BLACK = (0, 0, 0)

# Composite covers the same 544x512 area as the vanilla tile set.
W, H = 544, 512

# Tile slice rects (x0, y0, x1, y1) — match vanilla's tile dimensions and
# positions exactly so MenuUIClientWindow's hardcoded 256-grid puts each
# tile where we want it.
TILES = [
    ("MenuBg_1", (0, 0, 256, 256)),
    ("MenuBg_2", (256, 0, 512, 256)),
    ("MenuBg_3", (512, 0, 544, 256)),
    ("MenuBg_4", (0, 256, 256, 512)),
    ("MenuBg_5", (256, 256, 512, 512)),
    ("MenuBg_6", (512, 256, 544, 512)),
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


def draw_trace(img, points):
    """Draw a 1-px black polyline; segments must be axis-aligned."""
    px = img.load()
    for i in range(len(points) - 1):
        x0, y0 = points[i]
        x1, y1 = points[i + 1]
        if x0 == x1:
            for y in range(min(y0, y1), max(y0, y1) + 1):
                px[x0, y] = BLACK
        elif y0 == y1:
            for x in range(min(x0, x1), max(x0, x1) + 1):
                px[x, y0] = BLACK
        else:
            raise ValueError("traces must be axis-aligned")


def junction_dot(img, x, y):
    """2x2 black square at a trace intersection."""
    for dy in range(2):
        for dx in range(2):
            img.putpixel((x + dx, y + dy), BLACK)


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


def compose():
    """Build the full 544x512 dialog image.

    Layout is row-count-agnostic: no per-setting-row structure is baked
    in (the actual buttons/recesses come from the screen's child windows
    drawn on top). What's baked in is the surrounding chrome — title
    block at top, message bar at bottom, scanlined panel everywhere
    else, plus a few decorative traces.
    """
    img = Image.new("RGB", (W, H), PANEL_HI)
    fill_scanlines(img, 0, 0, W, H, PANEL_HI, PANEL_LO)

    # Outer 1-px black border around the whole panel
    hline(img, 0, W, 0, BLACK)
    hline(img, 0, W, H - 1, BLACK)
    vline(img, 0, 0, H, BLACK)
    vline(img, W - 1, 0, H, BLACK)

    all_interiors = set()
    halo_seeds = set()

    # Title block — recess at the top-left of the header strip
    title = element_interior(22, 16, 240, 40, notch_tl=3, notch_br=6)
    stamp_element(img, title, INSET_HI, INSET_LO, all_interiors, halo_seeds)

    # 3-px black band under the header
    for y in range(48, 51):
        hline(img, 4, W - 4, y, BLACK)

    # 3-px black band above the footer
    for y in range(H - 50, H - 47):
        hline(img, 4, W - 4, y, BLACK)

    # Message/info bar — wide recess in the footer strip
    msg = element_interior(22, H - 36, W - 22, H - 14, notch_tl=3, notch_br=6)
    stamp_element(img, msg, INSET_HI, INSET_LO, all_interiors, halo_seeds)

    # Decorative traces wiring corners together (1-px black + junction dots)
    draw_trace(img, [(170, 95), (200, 95), (200, 110)])
    junction_dot(img, 199, 94)
    draw_trace(img, [(W - 80, 200), (W - 30, 200), (W - 30, 240)])
    junction_dot(img, W - 31, 239)
    draw_trace(img, [(40, H - 90), (40, H - 60), (90, H - 60)])
    junction_dot(img, 39, H - 91)

    paint_halo(img, halo_seeds, all_interiors)
    return img


def main():
    out_dir = Path(sys.argv[1]) if len(sys.argv) > 1 else Path(__file__).parent / "menu-bg-gen"
    out_dir.mkdir(parents=True, exist_ok=True)
    full = compose()
    for name, (x0, y0, x1, y1) in TILES:
        tile = full.crop((x0, y0, x1, y1))
        tile.save(out_dir / f"{name}.png")
    full.save(out_dir / "MenuBg_full.png")  # composite for visual sanity check
    print(f"wrote 6 tiles + composite to {out_dir}")


if __name__ == "__main__":
    main()
