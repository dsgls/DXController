#!/usr/bin/env python3
"""Generate the DXController weapon-wheel textures (belt-style open ring).

Outputs into OUT_DIR (default: a 'wheel-gen' dir next to this script), all
TEX_SIZE square:
  WheelPlate.png        RGBA greyscale-on-alpha -> masked import
  wedges/wedge0..9.png  mode-L greyscale on black -> non-masked additive import

The plate uses the stock item bar's "luminance = opacity" vocabulary:
ten framed wedge cells in an outer band plus a centre readout plate,
cell interiors at LUM_FILL and frames at LUM_FRAME, alpha everywhere
else. At draw time the engine tints it with the HUD theme's background
colour and renders it DSTY_Translucent (additive) — exactly how the
stock object belt gets its translucent themed look. Each wedge texture
is the matching per-slot highlight glow.

Deterministic: identical PARAMETERS produce byte-identical output.
Geometry is expressed as a fraction of the disc radius R = TEX_SIZE/2,
so it is resolution-independent.

Run via the build (sync-and-build.sh / CI), or standalone:
  python3 gen-wheel.py [OUT_DIR]
"""
import sys
from pathlib import Path

import numpy as np
from PIL import Image

# ===== PARAMETERS (dev-time tuning knobs) ====================================
TEX_SIZE             = 1024
SLOT_COUNT           = 10

# Belt-derived luminances ("luminance = opacity" under DSTY_Translucent)
LUM_FILL             = 50    # cell interior (matches stock belt cells)
LUM_FRAME            = 75    # cell frames (matches the belt bar)

# Ring geometry (fraction of radius R)
BAND_INNER_FRAC      = 0.44  # cells' inner edge
BAND_OUTER_FRAC      = 0.90  # cells' outer edge
CELL_GAP_FRAC        = 0.035 # tangential gap between cells (~6px at 360px draw)
FRAME_WIDTH_FRAC     = 0.011 # cell frame thickness (~2px at 360px draw)

# Centre readout plate (half-extents, fraction of R)
READOUT_HALF_W_FRAC  = 0.28
READOUT_HALF_H_FRAC  = 0.12

# Wedge highlight glow
WEDGE_EDGE_SOFT_FRAC = 0.02  # spatial glow softness (must be > 0)
WEDGE_FALLOFF        = 0.45  # 0 = flat, 1 = strong inward dim
# ============================================================================


def _coords(n):
    """Return (rad, ang): radius in fractions of R (0 at centre, 1 at edge)
    and angle in degrees measured clockwise from the top (0..360)."""
    r = n / 2.0
    ys, xs = np.mgrid[0:n, 0:n].astype(np.float64)
    c = (n - 1) / 2.0
    dx = xs - c
    dy = ys - c
    rad = np.sqrt(dx * dx + dy * dy) / r
    ang = np.degrees(np.arctan2(dx, -dy)) % 360.0   # 0 at top, clockwise
    return rad, ang


def _smoothstep(e0, e1, x):
    t = np.clip((x - e0) / (e1 - e0), 0.0, 1.0)
    return t * t * (3.0 - 2.0 * t)


def _cell_inside(rad, ang):
    """Signed inside-distance (frac-of-R units) to the nearest cell edge:
    positive inside a cell, negative in the gaps and outside the band.
    Gaps have constant tangential width (perpendicular distance to the
    boundary rays at 18deg + k*36deg, minus half the gap)."""
    half_seg = 180.0 / SLOT_COUNT                      # 18 deg
    delta = (ang - half_seg) % (2.0 * half_seg)        # 0..36 past a boundary
    bdist_deg = np.minimum(delta, 2.0 * half_seg - delta)
    d_side = rad * np.sin(np.radians(bdist_deg)) - CELL_GAP_FRAC / 2.0
    d_rad = np.minimum(rad - BAND_INNER_FRAC, BAND_OUTER_FRAC - rad)
    return np.minimum(d_side, d_rad)


def _readout_inside(n):
    """Signed inside-distance to the centre readout plate's edge."""
    r = n / 2.0
    ys, xs = np.mgrid[0:n, 0:n].astype(np.float64)
    c = (n - 1) / 2.0
    dx = np.abs(xs - c) / r
    dy = np.abs(ys - c) / r
    return np.minimum(READOUT_HALF_W_FRAC - dx, READOUT_HALF_H_FRAC - dy)


def _lum_cov(inside, aa):
    """Map a signed inside-distance field to (luminance, coverage):
    frame luminance within FRAME_WIDTH_FRAC of the edge, fill further in."""
    cov = _smoothstep(-aa, aa, inside)
    t = _smoothstep(FRAME_WIDTH_FRAC - aa, FRAME_WIDTH_FRAC + aa, inside)
    val = LUM_FRAME * (1.0 - t) + LUM_FILL * t
    return val, cov


def render_plate():
    n = TEX_SIZE
    rad, ang = _coords(n)
    aa = 1.0 / (n / 2.0)                              # ~1px in frac-of-R units

    cell_val, cell_cov = _lum_cov(_cell_inside(rad, ang), aa)
    ro_val, ro_cov = _lum_cov(_readout_inside(n), aa)

    # Cells (outer band) and the readout plate (centre) are disjoint, so
    # pick whichever field covers this pixel. Luminance is stored
    # straight (NOT premultiplied by coverage) — the masked PCX import
    # binarizes alpha and keeps surviving pixels' RGB as-is.
    val = np.where(cell_cov >= ro_cov, cell_val, ro_val)
    cov = np.maximum(cell_cov, ro_cov)

    arr = np.empty((n, n, 4), np.uint8)
    g = np.clip(val, 0, 255).round().astype(np.uint8)
    arr[..., 0] = g
    arr[..., 1] = g
    arr[..., 2] = g
    arr[..., 3] = np.clip(cov * 255.0, 0, 255).round().astype(np.uint8)
    return Image.fromarray(arr, "RGBA")


def render_wedge(i):
    """Soft additive glow shaped like cell i (band-limited, gap-inset),
    brighter toward the outer edge."""
    n = TEX_SIZE
    rad, ang = _coords(n)

    tb = i * 360.0 / SLOT_COUNT                       # slot centre angle
    ad = np.abs(((ang - tb + 180.0) % 360.0) - 180.0) # deg from slot centre
    half_seg = 180.0 / SLOT_COUNT

    inside = _cell_inside(rad, ang)
    gated = np.where(ad <= half_seg, inside, -1.0)    # this slot's cell only
    cov = _smoothstep(0.0, WEDGE_EDGE_SOFT_FRAC, gated)

    t = np.clip((rad - BAND_INNER_FRAC)
                / (BAND_OUTER_FRAC - BAND_INNER_FRAC), 0.0, 1.0)
    glow = (1.0 - WEDGE_FALLOFF) + WEDGE_FALLOFF * t

    val = np.clip(cov * glow * 255.0, 0, 255).round().astype(np.uint8)
    return Image.fromarray(val, "L")


def main():
    out = Path(sys.argv[1]) if len(sys.argv) > 1 else (Path(__file__).parent / "wheel-gen")
    wedges = out / "wedges"
    out.mkdir(parents=True, exist_ok=True)
    wedges.mkdir(parents=True, exist_ok=True)

    plate_path = out / "WheelPlate.png"
    render_plate().save(plate_path)
    print(f"WheelPlate.png -> {plate_path}")

    for i in range(SLOT_COUNT):
        p = wedges / f"wedge{i}.png"
        render_wedge(i).save(p)
        print(f"wedge{i}.png -> {p}")

    print(f"\n1 plate + {SLOT_COUNT} wedges written to {out}")


if __name__ == "__main__":
    main()
