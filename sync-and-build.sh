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
#   1. rsync DXController/ -> $BUILD_DIR/DXController/
#   2. rsync DeusEx/       -> $BUILD_DIR/DeusEx/
#   3. delete DeusEx.u; `echo n | UCC.exe make`. UCC prompts to overwrite
#      DeusEx/Inc/DeusExClasses.h; we answer 'n'. UCC subsequently GPFs
#      while loading the freshly-rebuilt package to build DXController.
#      DeusEx.u is written before the crash. `|| true` swallows the exit
#      code; the `-f` check is the real success signal.
#   4. delete DXController.u; fresh `UCC.exe make`. No native header, no
#      prompt; the fresh UCC process side-steps the load-time GPF.
#
# Usage:
#   ./sync-and-build.sh          # sync + build
#   ./sync-and-build.sh -n       # dry run (rsync --dry-run, skip build)
#   BUILD_DIR=/path ./sync-and-build.sh

set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BUILD_DIR="${BUILD_DIR:-$REPO_DIR/gamedir}"

DRY_RUN=0
RSYNC_FLAGS=(-rtv)
if [[ "${1:-}" == "-n" || "${1:-}" == "--dry-run" ]]; then
    DRY_RUN=1
    RSYNC_FLAGS+=(--dry-run)
fi

if [[ ! -d "$BUILD_DIR" ]]; then
    echo "sync-and-build: build dir not found: $BUILD_DIR" >&2
    exit 1
fi

rsync "${RSYNC_FLAGS[@]}" "$REPO_DIR/DXController/" "$BUILD_DIR/DXController/"
rsync "${RSYNC_FLAGS[@]}" "$REPO_DIR/DeusEx/"       "$BUILD_DIR/DeusEx/"

if (( DRY_RUN )); then
    echo "sync-and-build: dry run — skipping .u delete and build"
    exit 0
fi

cd "$BUILD_DIR/System"

# Pass 1: rebuild DeusEx.u (tolerate the GPF; verify .u landed)
rm -f "$BUILD_DIR/System/DeusEx.u"
cmd.exe /c "echo n | UCC.exe make" || true
if [[ ! -f "$BUILD_DIR/System/DeusEx.u" ]]; then
    echo "sync-and-build: DeusEx.u was not produced" >&2
    exit 1
fi

# Pass 2: rebuild DXController.u in a fresh UCC process
rm -f "$BUILD_DIR/System/DXController.u"
cmd.exe /c "UCC.exe make"
if [[ ! -f "$BUILD_DIR/System/DXController.u" ]]; then
    echo "sync-and-build: DXController.u was not produced" >&2
    exit 1
fi

echo "sync-and-build: ok"
