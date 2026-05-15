#!/usr/bin/env python3
"""Convert PNGs in assets/xbox-buttons-png/ to 64x64 8-bit PCX with palette
index 0 = magenta key for UE1 masked-texture import."""

from pathlib import Path
from PIL import Image

KEY = (255, 0, 255)  # UE1 magenta transparency key at palette index 0
ALPHA_THRESHOLD = 128
SRC_DIR = Path(__file__).parent / "xbox-buttons-png"
DST_DIR = Path(__file__).parent / "xbox-buttons-pcx"
SIZE = (64, 64)


def convert(src: Path, dst: Path) -> None:
    img = Image.open(src).convert("RGBA").resize(SIZE, Image.LANCZOS)

    # Binarize alpha: anything below threshold becomes the key; everything
    # else keeps its RGB (alpha discarded). Replace masked pixels with black
    # for the quantizer — black is already plentiful in the source so it
    # adds no extra cluster — then we remap them to the key index afterwards.
    rgb = Image.new("RGB", SIZE)
    mask = bytearray(SIZE[0] * SIZE[1])
    rgb_pixels = []
    for i, (r, g, b, a) in enumerate(img.getdata()):
        if a < ALPHA_THRESHOLD:
            mask[i] = 1
            rgb_pixels.append((0, 0, 0))
        else:
            mask[i] = 0
            rgb_pixels.append((r, g, b))
    rgb.putdata(rgb_pixels)

    # Quantize the opaque RGB image to 255 colors (indices 0..254). We will
    # shift these to 1..255 to reserve index 0 for the magenta key.
    quant = rgb.quantize(colors=255, method=Image.Quantize.MEDIANCUT, dither=Image.Dither.NONE)
    src_palette = quant.getpalette()[: 255 * 3]
    src_indices = quant.tobytes()

    # Build final palette: magenta at 0, original 0..254 shifted to 1..255.
    new_palette = bytearray(768)
    new_palette[0:3] = bytes(KEY)
    new_palette[3 : 3 + 255 * 3] = bytes(src_palette)

    # Build final index buffer: masked pixels -> 0, opaque -> old_index + 1.
    new_indices = bytearray(SIZE[0] * SIZE[1])
    for i in range(len(new_indices)):
        new_indices[i] = 0 if mask[i] else src_indices[i] + 1

    out = Image.frombytes("P", SIZE, bytes(new_indices))
    out.putpalette(bytes(new_palette))
    out.save(dst, format="PCX")


def main() -> None:
    DST_DIR.mkdir(parents=True, exist_ok=True)
    pngs = sorted(SRC_DIR.glob("*.png"))
    for src in pngs:
        dst = DST_DIR / (src.stem + ".pcx")
        convert(src, dst)
        print(f"{src.name} -> {dst.name}")
    print(f"\n{len(pngs)} files converted to {DST_DIR}")


if __name__ == "__main__":
    main()
