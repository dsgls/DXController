#!/usr/bin/env python3
"""Generate the DXController weapon-wheel textures.

Outputs into OUT_DIR (default: a 'wheel-gen' dir next to this script), all
TEX_SIZE square:
  WheelPlate.png        RGBA, transparent outside the disc -> masked import
  wedges/wedge0..9.png  mode-L greyscale on black -> non-masked additive import

Deterministic: identical PARAMETERS produce byte-identical output. All
tuning knobs live in the PARAMETERS block below — edit them to change the
look, then rebuild. Geometry is expressed as a fraction of the disc radius
R = TEX_SIZE/2, so it is resolution-independent.

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

# Colours (RGB 0-255)
DISC_COLOR           = (20, 22, 28)     # dark cool-grey disc
HUB_COLOR            = (12, 12, 12)     # #0c0c0c — darker inset hub
STEEL_COLOR          = (150, 165, 180)  # neutral steel: rim, spokes, hub ring

# Plate geometry (fraction of radius R)
DISC_RADIUS_FRAC     = 0.985
RIM_WIDTH_FRAC       = 0.016            # ~3px at the ~360px final draw size
HUB_RADIUS_FRAC      = 0.66             # doubled from the original ~0.33
HUB_RING_WIDTH_FRAC  = 0.012
SPOKE_WIDTH_FRAC     = 0.016            # ~3px final

# Wedge highlight geometry
WEDGE_INNER_FRAC     = 0.68             # just outside the hub
WEDGE_OUTER_FRAC     = 0.92             # just inside the rim
WEDGE_HALF_DEG       = 16.0             # ±16° of the 18° half-wedge (spoke shows)
WEDGE_EDGE_SOFT_DEG  = 3.0             # angular AA / glow softness
WEDGE_EDGE_SOFT_FRAC = 0.02            # radial AA / glow softness
WEDGE_FALLOFF        = 0.45            # 0 = flat white, 1 = strong inward dim
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


def _band(x, center, halfw, aa):
    """Soft-edged coverage 1 within [center-halfw, center+halfw]."""
    inner = _smoothstep(center - halfw - aa, center - halfw + aa, x)
    outer = 1.0 - _smoothstep(center + halfw - aa, center + halfw + aa, x)
    return np.clip(np.minimum(inner, outer), 0.0, 1.0)


def _between(x, lo, hi, aa):
    """Soft-edged coverage 1 for lo <= x <= hi."""
    return np.clip(np.minimum(_smoothstep(lo - aa, lo + aa, x),
                              1.0 - _smoothstep(hi - aa, hi + aa, x)), 0.0, 1.0)


def _over(base, color, cov):
    """Alpha-composite a flat colour over an RGB float field by coverage."""
    c = np.array(color, np.float64).reshape((1, 1, 3))
    a = cov[..., None]
    return base * (1.0 - a) + c * a


def render_plate():
    n = TEX_SIZE
    rad, ang = _coords(n)
    aa = 1.0 / (n / 2.0)                         # ~1px in frac-of-R units

    rgb = np.empty((n, n, 3), np.float64)
    rgb[:] = DISC_COLOR

    # Hub fill
    hub = 1.0 - _smoothstep(HUB_RADIUS_FRAC - aa, HUB_RADIUS_FRAC + aa, rad)
    rgb = _over(rgb, HUB_COLOR, hub)

    # Hub ring (steel) on the hub boundary
    ring = _band(rad, HUB_RADIUS_FRAC, HUB_RING_WIDTH_FRAC / 2.0, aa)
    rgb = _over(rgb, STEEL_COLOR, ring)

    # Disc coverage (alpha) with an AA edge
    disc = 1.0 - _smoothstep(DISC_RADIUS_FRAC - aa, DISC_RADIUS_FRAC + aa, rad)

    # Rim (steel) just inside the disc edge
    rim_c = DISC_RADIUS_FRAC - RIM_WIDTH_FRAC
    rim = _band(rad, rim_c, RIM_WIDTH_FRAC / 2.0, aa)
    rgb = _over(rgb, STEEL_COLOR, rim * disc)

    # Spokes: SLOT_COUNT constant-width dividers at the wedge boundaries
    # (18°, 54°, ...), spanning from the hub ring out to the rim.
    gate = _between(rad, HUB_RADIUS_FRAC, rim_c, aa)
    spoke = np.zeros((n, n), np.float64)
    halfw = SPOKE_WIDTH_FRAC / 2.0
    for i in range(SLOT_COUNT):
        tb = (i * 360.0 / SLOT_COUNT) + (180.0 / SLOT_COUNT)
        d = np.radians(((ang - tb + 180.0) % 360.0) - 180.0)
        dist = rad * np.abs(np.sin(d))           # perpendicular dist to the ray
        line = 1.0 - _smoothstep(halfw - aa, halfw + aa, dist)
        spoke = np.maximum(spoke, line * gate)
    rgb = _over(rgb, STEEL_COLOR, spoke)

    arr = np.empty((n, n, 4), np.uint8)
    arr[..., :3] = np.clip(rgb, 0, 255).round().astype(np.uint8)
    arr[..., 3] = np.clip(disc * 255.0, 0, 255).round().astype(np.uint8)
    return Image.fromarray(arr, "RGBA")


def render_wedge(i):
    n = TEX_SIZE
    rad, ang = _coords(n)
    aa = 1.0 / (n / 2.0)

    tb = i * 360.0 / SLOT_COUNT                   # slot centre, i*36° from top
    ad = np.abs(((ang - tb + 180.0) % 360.0) - 180.0)

    ang_cov = 1.0 - _smoothstep(WEDGE_HALF_DEG - WEDGE_EDGE_SOFT_DEG,
                                WEDGE_HALF_DEG + WEDGE_EDGE_SOFT_DEG, ad)
    rad_cov = _between(rad, WEDGE_INNER_FRAC, WEDGE_OUTER_FRAC,
                       WEDGE_EDGE_SOFT_FRAC)
    cov = ang_cov * rad_cov

    # Gentle inward falloff: brighter toward the outer edge for a soft glow.
    t = np.clip((rad - WEDGE_INNER_FRAC)
                / (WEDGE_OUTER_FRAC - WEDGE_INNER_FRAC), 0.0, 1.0)
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
