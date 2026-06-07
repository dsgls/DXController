#!/usr/bin/env python3
"""Convert a directory of PNGs to 8-bit PCX for UE1 #exec Texture Import.

Two modes:
  masked (default) — square PCX, palette index 0 = magenta key (255,0,255)
    for masked/transparent import. Used for the button glyphs and the
    wheel plate.
  grey            — PCX with an explicit linear grey palette (index i ->
    (i,i,i)), no key, for non-masked additive textures (the wheel's
    slice-highlight wedges).

Usage: png-to-pcx.py [SRC_DIR] [DST_DIR] [--size SIZE|native] [--mode masked|grey]

SRC_DIR and DST_DIR are optional and default to the XboxSeries/ and
XboxSeries-pcx/ directories next to this script. SIZE is the output edge
length in pixels — square (default: 64), or pass 'native' to preserve
each PNG's natural dimensions (used by the menu-bg tile set, which has
mixed 256x256 and 32x256 tiles)."""

import argparse
from pathlib import Path
from PIL import Image

KEY = (255, 0, 255)  # UE1 magenta transparency key at palette index 0
ALPHA_THRESHOLD = 128
DEFAULT_SRC_DIR = Path(__file__).parent / "XboxSeries"
DEFAULT_DST_DIR = Path(__file__).parent / "XboxSeries-pcx"
DEFAULT_SIZE = 64


def convert_masked(src: Path, dst: Path, size: tuple) -> None:
    img = Image.open(src).convert("RGBA").resize(size, Image.LANCZOS)

    # Binarize alpha: anything below threshold becomes the key; everything
    # else keeps its RGB (alpha discarded). Replace masked pixels with black
    # for the quantizer — black is already plentiful in the source so it
    # adds no extra cluster — then we remap them to the key index afterwards.
    rgb = Image.new("RGB", size)
    mask = bytearray(size[0] * size[1])
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
    new_indices = bytearray(size[0] * size[1])
    for i in range(len(new_indices)):
        new_indices[i] = 0 if mask[i] else src_indices[i] + 1

    out = Image.frombytes("P", size, bytes(new_indices))
    out.putpalette(bytes(new_palette))
    out.save(dst, format="PCX")


def convert_grey(src: Path, dst: Path, size: tuple) -> None:
    """Convert a greyscale PNG to 8-bit PCX with an explicit linear grey
    palette (index i -> (i, i, i)). No magenta key: the result is imported
    non-masked, so its black background stays drawn and adds nothing under
    the additive DSTY_Translucent blend the wheel highlight uses. Index 0
    is true black; the full 0..255 ramp is preserved."""
    img = Image.open(src).convert("L").resize(size, Image.LANCZOS)

    # Reinterpret the L pixel buffer as palette indices (one byte/pixel),
    # then attach a linear grey palette so index == grey level. Building
    # the palette explicitly (not relying on PIL's L->PCX default) keeps
    # the output deterministic across Pillow versions.
    out = Image.frombytes("P", size, img.tobytes())
    palette = bytearray(768)
    for i in range(256):
        palette[i * 3 + 0] = i
        palette[i * 3 + 1] = i
        palette[i * 3 + 2] = i
    out.putpalette(bytes(palette))
    out.save(dst, format="PCX")


def main() -> None:
    parser = argparse.ArgumentParser(
        description="Convert a directory of PNGs to UE1 masked-texture PCX files."
    )
    parser.add_argument(
        "src_dir", nargs="?", type=Path, default=DEFAULT_SRC_DIR,
        help="directory of source .png files (default: XboxSeries/)",
    )
    parser.add_argument(
        "dst_dir", nargs="?", type=Path, default=DEFAULT_DST_DIR,
        help="directory for output .pcx files (default: XboxSeries-pcx/)",
    )
    parser.add_argument(
        "--size", default=str(DEFAULT_SIZE),
        help=f"output edge length in pixels (square), or 'native' to use "
             f"each PNG's natural dimensions (default: {DEFAULT_SIZE})",
    )
    parser.add_argument(
        "--mode", choices=["masked", "grey"], default="masked",
        help="masked = magenta-key transparency (default); grey = linear "
             "greyscale, no key, for additive textures",
    )
    args = parser.parse_args()

    if not args.src_dir.is_dir():
        parser.error(f"source directory does not exist: {args.src_dir}")

    native = args.size.lower() == "native"
    sq = 0
    if not native:
        try:
            sq = int(args.size)
        except ValueError:
            parser.error(f"--size must be an integer or 'native', got {args.size!r}")

    args.dst_dir.mkdir(parents=True, exist_ok=True)
    pngs = sorted(args.src_dir.glob("*.png"))
    convert = convert_masked if args.mode == "masked" else convert_grey
    for src in pngs:
        dst = args.dst_dir / (src.stem + ".pcx")
        size = Image.open(src).size if native else (sq, sq)
        convert(src, dst, size)
        print(f"{src.name} -> {dst.name}")
    print(f"\n{len(pngs)} files converted to {args.dst_dir}")


if __name__ == "__main__":
    main()
