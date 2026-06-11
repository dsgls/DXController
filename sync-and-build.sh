#!/usr/bin/env bash
# Sync DXController/ and DeusEx/ overlays to the game build dir, then
# build DeusEx.u and DXController.u.
#
# Layout:
#   $REPO_DIR/DXController/Classes/*.uc   — our package's sources
#   $REPO_DIR/DeusEx/Classes/*.uc         — overlay edits to stock DeusEx
#
# The DeusEx overlay assumes $BUILD_DIR/DeusEx/Classes/ already contains
# the full stock source (from a one-time
# `ucc batchexport DeusEx.u Class uc ..\DeusEx\Classes` run). Our overlay
# just replaces specific files; the rest of the stock tree stays as-is.
#
# Build flow:
#   1-2. convert the overlay .uc sources (DXController/, DeusEx/) into
#        the build dir, LF -> CRLF. The repo stores .uc as LF; the
#        ancient UCC.exe wants CRLF-terminated source, so each file is
#        passed through `unix2dos -n` on the way in.
#   3. wipe+recreate $BUILD_DIR/DXController, sync overlay .uc, then
#      generate textures (gen-wheel.py + png-to-pcx.py) into
#      DXController/Textures/ for the #exec imports in DXControllerTextures.uc
#   4. delete DeusEx.u; `echo n | UCC.exe make`. UCC prompts to overwrite
#      DeusEx/Inc/DeusExClasses.h; we answer 'n'. UCC subsequently GPFs
#      while loading the freshly-rebuilt DeusEx.u (the load happens before
#      DXController compiles). DeusEx.u is written before the crash.
#      `|| true` swallows the exit code; the `-f` check is the real
#      success signal.
#   5. delete DXController.u; fresh `UCC.exe make`. DeusEx.u exists
#      (no rebuild, no GPF), then DXController.u is built against it.
#
# Requires `unix2dos` (from the dos2unix package) on PATH — run under
# `nix develop`, which provides it, or install dos2unix.
#
# Usage:
#   ./sync-and-build.sh          # sync + build
#   ./sync-and-build.sh -n       # dry run (list files, skip build)
#   BUILD_DIR=/path ./sync-and-build.sh

set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BUILD_DIR="${BUILD_DIR:-$REPO_DIR/gamedir}"

DRY_RUN=0
if [[ "${1:-}" == "-n" || "${1:-}" == "--dry-run" ]]; then
    DRY_RUN=1
fi

if [[ ! -d "$BUILD_DIR" ]]; then
    echo "sync-and-build: build dir not found: $BUILD_DIR" >&2
    exit 1
fi

# Wipe and recreate the DXController package dir so obsolete scripts or
# textures from a prior build can't linger. Scoped to DXController/ only —
# DeusEx/ (the full stock-source overlay, which we do not reconstruct here)
# is left untouched. Done before the overlay sync and the texture generation
# below, both of which write into this tree.
if (( DRY_RUN )); then
    echo "sync-and-build: (dry-run) would wipe and recreate $BUILD_DIR/DXController"
else
    rm -rf "$BUILD_DIR/DXController"
    mkdir -p "$BUILD_DIR/DXController/Classes"
fi

# Sync the overlay .uc sources into the build dir, converting LF -> CRLF
# on the way. The repo stores .uc as LF, but the ancient UCC.exe expects
# CRLF-terminated source. `unix2dos -n` reads the LF source and writes a
# CRLF copy straight to the destination — no rsync, no post-pass over the
# build dir, so the full stock DeusEx/Classes/ tree is never touched.
for pkg in DXController DeusEx; do
    src="$REPO_DIR/$pkg/Classes"
    dst="$BUILD_DIR/$pkg/Classes"
    (( DRY_RUN )) || mkdir -p "$dst"
    for f in "$src"/*.uc; do
        [[ -e "$f" ]] || continue
        if (( DRY_RUN )); then
            echo "sync-and-build: (dry-run) would convert $f -> $dst/$(basename "$f")"
        else
            unix2dos -n "$f" "$dst/$(basename "$f")"
        fi
    done
done

# Generate the texture set and convert to the 8-bit PCX the package import
# expects, writing into DXController/Textures/. The #exec lines in
# DXControllerTextures.uc reference FILE=Textures\<name>.pcx (relative to
# the package dir). The wheel art is generated fresh by gen-wheel.py; the
# button glyphs are committed PNGs under assets/XboxSeries/.
TEXDIR="$BUILD_DIR/DXController/Textures"
if (( DRY_RUN )); then
    echo "sync-and-build: (dry-run) would generate textures into $TEXDIR"
else
    WHEELSRC="$(mktemp -d)"
    MENUBGSRC="$(mktemp -d)"
    trap 'rm -rf "$WHEELSRC" "$MENUBGSRC"' EXIT
    mkdir -p "$TEXDIR"
    python3 "$REPO_DIR/assets/gen-wheel.py" "$WHEELSRC"
    python3 "$REPO_DIR/assets/gen-menu-bg.py" "$MENUBGSRC"
    python3 "$REPO_DIR/assets/png-to-pcx.py" "$REPO_DIR/assets/XboxSeries" "$TEXDIR" --size 64     --mode masked
    python3 "$REPO_DIR/assets/png-to-pcx.py" "$WHEELSRC"         "$TEXDIR" --size 1024   --mode masked --key black
    python3 "$REPO_DIR/assets/png-to-pcx.py" "$WHEELSRC/wedges"  "$TEXDIR" --size 1024   --mode grey
    # Menu-bg tiles are six 256x256 PNGs; preserve native dims so png-to-pcx
    # doesn't square-resize them against the default --size 64.
    python3 "$REPO_DIR/assets/png-to-pcx.py" "$MENUBGSRC"        "$TEXDIR" --size native --mode grey
    echo "sync-and-build: generated textures into $TEXDIR"
fi

# Register DXController in DeusEx.ini's EditPackages list. UCC walks
# this list to decide what to build; without this entry, `UCC make`
# doesn't pick up DXController.uc. Insert directly after
# `EditPackages=DeusEx` so DXController compiles after the overlay
# rebuild. The ini ships CRLF; the sed pattern anchors on `\r$` so
# `EditPackages=DeusExUI` etc. don't match, and the replacement
# preserves CRLF on both lines.
DEUSEX_INI="$BUILD_DIR/System/DeusEx.ini"
if (( DRY_RUN )); then
    echo "sync-and-build: (dry-run) would ensure EditPackages=DXController is registered in $DEUSEX_INI"
else
    if [[ ! -f "$DEUSEX_INI" ]]; then
        echo "sync-and-build: DeusEx.ini not found at $DEUSEX_INI" >&2
        exit 1
    fi
    if ! grep -q '^EditPackages=DXController' "$DEUSEX_INI"; then
        sed -i 's/^EditPackages=DeusEx\r$/EditPackages=DeusEx\r\nEditPackages=DXController\r/' "$DEUSEX_INI"
        if ! grep -q '^EditPackages=DXController' "$DEUSEX_INI"; then
            echo "sync-and-build: failed to insert EditPackages=DXController into $DEUSEX_INI" >&2
            exit 1
        fi
        echo "sync-and-build: registered EditPackages=DXController in DeusEx.ini"
    fi
fi

# Build the native launcher (msbuild via WSL → Windows-side VS).
# find-msbuild.sh hard-fails if no MSBuild reachable; that's the right
# behaviour — sync-and-build is the canonical install path and partial
# installs (stale .exe + fresh .u) hide which side broke.
MSBUILD="$("$REPO_DIR/launcher/find-msbuild.sh")"
if (( DRY_RUN )); then
    echo "sync-and-build: (dry-run) would run msbuild via $MSBUILD"
    echo "sync-and-build: (dry-run) would install DeusEx.exe + DeusEx.pdb to $BUILD_DIR/System/"
else
    "$MSBUILD" "$(wslpath -w "$REPO_DIR/launcher/launcher.sln")" \
        -p:Configuration=Release -p:Platform=Win32 \
        -m -verbosity:minimal -nologo
    cp "$REPO_DIR/launcher/Release/DeusEx.exe" "$BUILD_DIR/System/DeusEx.exe"
    cp "$REPO_DIR/launcher/Release/DeusEx.pdb" "$BUILD_DIR/System/DeusEx.pdb"
    echo "sync-and-build: installed DeusEx.exe + DeusEx.pdb to $BUILD_DIR/System/"
fi

if (( DRY_RUN )); then
    echo "sync-and-build: dry run — skipping .u delete and build"
    exit 0
fi

cd "$BUILD_DIR/System"

# Pass 1: rebuild DeusEx.u (tolerate the GPF; verify .u landed).
rm -f "$BUILD_DIR/System/DeusEx.u"
cmd.exe /c "echo n | UCC.exe make" || true
if [[ ! -f "$BUILD_DIR/System/DeusEx.u" ]]; then
    echo "sync-and-build: DeusEx.u was not produced" >&2
    exit 1
fi

# Pass 2: rebuild DXController.u in a fresh UCC process. UCC walks
# EditPackages, skips DeusEx.u (present), builds DXController.u.
rm -f "$BUILD_DIR/System/DXController.u"
cmd.exe /c "UCC.exe make"
if [[ ! -f "$BUILD_DIR/System/DXController.u" ]]; then
    echo "sync-and-build: DXController.u was not produced" >&2
    exit 1
fi

echo "sync-and-build: ok"
