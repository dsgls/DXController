#!/bin/sh
# Fetches the official prebuilt SDL3 Windows VC package for the launcher
# build. Downloads a pinned release once, verifies its SHA-256, and
# extracts it to launcher/external/SDL3/ so headers land at
# external/SDL3/include/SDL3/*.h and libs at external/SDL3/lib/x86/.
# Idempotent: skips the download/extract if the pinned version is already
# present. Run from launcher/build.sh and from CI; the pinned version
# lives only here.
set -e

SDL_VERSION="3.4.14"
SDL_SHA256="2fe279e70d426e9c644b625acb3083eb3cfb263a92f2c5718aff18d24a8b6e96"
SDL_ZIP="SDL3-devel-${SDL_VERSION}-VC.zip"
SDL_URL="https://github.com/libsdl-org/SDL/releases/download/release-${SDL_VERSION}/${SDL_ZIP}"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
EXTERNAL_DIR="$SCRIPT_DIR/external"
SDL_DIR="$EXTERNAL_DIR/SDL3"
VERSION_FILE="$SDL_DIR/.fetched-version"

if [ -f "$VERSION_FILE" ] && [ "$(cat "$VERSION_FILE")" = "$SDL_VERSION" ]; then
    exit 0
fi

mkdir -p "$EXTERNAL_DIR"
TMP_ZIP="$EXTERNAL_DIR/$SDL_ZIP"
echo "fetch-sdl3: downloading SDL3 $SDL_VERSION..." >&2
curl -sL -o "$TMP_ZIP" "$SDL_URL"

ACTUAL_SHA256="$(sha256sum "$TMP_ZIP" | cut -d' ' -f1)"
if [ "$ACTUAL_SHA256" != "$SDL_SHA256" ]; then
    echo "fetch-sdl3: SHA-256 mismatch for $SDL_ZIP" >&2
    echo "fetch-sdl3: expected $SDL_SHA256" >&2
    echo "fetch-sdl3: got      $ACTUAL_SHA256" >&2
    rm -f "$TMP_ZIP"
    exit 1
fi

rm -rf "$SDL_DIR"
TMP_EXTRACT="$EXTERNAL_DIR/.sdl3-extract-tmp"
rm -rf "$TMP_EXTRACT"
mkdir -p "$TMP_EXTRACT"
unzip -q "$TMP_ZIP" -d "$TMP_EXTRACT"
# The zip's single top-level dir (SDL3-<ver>/) becomes SDL3/ directly.
mv "$TMP_EXTRACT/SDL3-$SDL_VERSION" "$SDL_DIR"
rm -rf "$TMP_EXTRACT" "$TMP_ZIP"

echo "$SDL_VERSION" > "$VERSION_FILE"
echo "fetch-sdl3: extracted SDL3 $SDL_VERSION to $SDL_DIR" >&2
