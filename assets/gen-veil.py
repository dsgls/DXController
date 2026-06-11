#!/usr/bin/env python3
"""Generate the flat modulation-veil texture (Veil.png).

A DSTY_Modulated draw multiplies the framebuffer by texel/128 (texel
128 = identity) and IGNORES the GC tile colour — UE1 render devices
force the poly colour to identity for modulated polys, so a darkening
veil must carry its strength in the texture itself (stock does the
same: ConWindowBackground is flat 64 = x0.5 for the conversation
letterbox). Texel 32 gives scene x0.25 — the on-screen keyboard's
backdrop dim, also used by the hint overlay.

Deterministic. Run via the build (sync-and-build.sh), or standalone:
  python3 gen-veil.py [OUT_DIR]
"""
import sys
from pathlib import Path

from PIL import Image

VEIL_VALUE = 32   # texel/128 = x0.25 scene multiplier
SIZE = 8          # tiny and tiled, like Extension's Solid


def main():
    out = Path(sys.argv[1]) if len(sys.argv) > 1 else (Path(__file__).parent / "veil-gen")
    out.mkdir(parents=True, exist_ok=True)
    p = out / "Veil.png"
    Image.new("L", (SIZE, SIZE), VEIL_VALUE).save(p)
    print(f"Veil.png -> {p}")


if __name__ == "__main__":
    main()
