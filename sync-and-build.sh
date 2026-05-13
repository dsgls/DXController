#!/usr/bin/env bash
# Sync DXController/ to the game build dir, then build DXController.u.
#
# Steps:
#   1. rsync DXController/ to $BUILD_DIR/DXController/
#   2. delete $BUILD_DIR/System/DXController.u (ucc skips packages whose .u exists)
#   3. run UCC.exe make from $BUILD_DIR/System
#
# Root-level files (CLAUDE.md, scripting-reference.txt, batch-export.ps1,
# this script, .git/) are intentionally not synced.
#
# Files in the build dir that aren't in the repo (compiled .u outputs,
# extracted .pcx/.wav assets, etc.) are left alone — no --delete.
#
# DeusEx.ini must have `EditPackages=DXController` appended to the
# EditPackages block for ucc to pick up this package.
#
# Usage:
#   ./sync-and-build.sh          # sync + build
#   ./sync-and-build.sh -n       # dry run (rsync --dry-run, skip build)
#   BUILD_DIR=/path ./sync-and-build.sh
#
# BUILD_DIR defaults to ./gamedir, which is a gitignored symlink in this
# repo pointing at the actual game install. Set up once with:
#   ln -s "/path/to/Deus Ex" gamedir

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

if (( DRY_RUN )); then
    echo "sync-and-build: dry run — skipping .u delete and build"
    exit 0
fi

rm -f "$BUILD_DIR/System/DXController.u"

cd "$BUILD_DIR/System"
cmd.exe /c "UCC.exe make"
