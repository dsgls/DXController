#!/usr/bin/env bash
# Sync DXController/, DeusEx/, and DeusExe/ overlays to the game build
# dir, then build DeusEx.u, DeusExe.u, and DXController.u.
#
# Layout:
#   $REPO_DIR/DXController/Classes/*.uc   — our package's sources
#   $REPO_DIR/DeusEx/Classes/*.uc         — overlay edits to stock DeusEx
#   $REPO_DIR/DeusExe/Classes/*.uc        — vendored from the
#                                           ../DeusExe-XInput/ sister repo
#                                           (currently just
#                                           ConWindowActive2.uc, which
#                                           subclasses ConWindowActive for
#                                           the widescreen subtitle fix
#                                           and is swapped in by the
#                                           launcher's native NewChild
#                                           hook). DXController references
#                                           Class'DeusExe.ConWindowActive2'
#                                           so DeusExe must be compiled
#                                           alongside.
#
# The DeusEx overlay assumes $BUILD_DIR/DeusEx/Classes/ already contains
# the full stock source (from a one-time
# `ucc batchexport DeusEx.u Class uc ..\DeusEx\Classes` run). Our overlay
# just replaces specific files; the rest of the stock tree stays as-is.
#
# Build flow:
#   1. rsync DXController/ -> $BUILD_DIR/DXController/
#   2. rsync DeusEx/       -> $BUILD_DIR/DeusEx/
#   3. rsync DeusExe/      -> $BUILD_DIR/DeusExe/
#   4. copy DXControllerBtn.u (pre-built texture package) into
#      $BUILD_DIR/System/
#   5. insert EditPackages=DeusExe into DeusEx.ini (idempotent)
#   6. delete DeusEx.u + DeusExe.u; `echo n | UCC.exe make`. UCC prompts
#      to overwrite DeusEx/Inc/DeusExClasses.h; we answer 'n'. UCC
#      subsequently GPFs while loading the freshly-rebuilt DeusEx.u (the
#      load happens before DeusExe and DXController compile). DeusEx.u
#      is written before the crash. `|| true` swallows the exit code;
#      the `-f` check is the real success signal.
#   7. delete DXController.u; fresh `UCC.exe make`. DeusEx.u exists
#      (no rebuild, no GPF), DeusExe.u is built from the synced source,
#      then DXController.u is built against both.
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
rsync "${RSYNC_FLAGS[@]}" "$REPO_DIR/DeusExe/"      "$BUILD_DIR/DeusExe/"

# Stage the pre-built controller-button texture package. It is a
# binary package committed at the repo root (not compiled from
# source); DXController references Texture'DXControllerBtn.*' so it
# must be in System/ before the pass-2 compile and at runtime.
if (( DRY_RUN )); then
    echo "sync-and-build: (dry-run) would copy DXControllerBtn.u -> $BUILD_DIR/System/"
else
    cp "$REPO_DIR/DXControllerBtn.u" "$BUILD_DIR/System/DXControllerBtn.u"
    echo "sync-and-build: copied DXControllerBtn.u -> $BUILD_DIR/System/"
fi

# Insert EditPackages=DeusExe between DeusEx and DXController in
# DeusEx.ini (idempotent). The ini ships with CRLF line endings, so
# anchor on [[:space:]]*$ to absorb the trailing \r — same pattern the
# CI workflow uses for EditPackages=DXController.
INI="$BUILD_DIR/System/DeusEx.ini"
if [[ ! -f "$INI" ]]; then
    echo "sync-and-build: DeusEx.ini not found at $INI" >&2
    exit 1
fi
if ! grep -qE '^EditPackages=DeusExe[[:space:]]*$' "$INI"; then
    sed -i -E '/^EditPackages=DeusEx[[:space:]]*$/a EditPackages=DeusExe' "$INI"
    echo "sync-and-build: inserted EditPackages=DeusExe into $INI"
fi

# Insert EditPackages=DXControllerBtn before DXController so UCC can
# resolve Texture'DXControllerBtn.*' literals during the pass-2 compile.
# DXControllerBtn is a pre-built texture-only package; it has no UScript
# source and is never rebuilt by UCC (it's already on disk in System/).
if ! grep -qE '^EditPackages=DXControllerBtn[[:space:]]*$' "$INI"; then
    sed -i -E '/^EditPackages=DXController[[:space:]]*$/i EditPackages=DXControllerBtn' "$INI"
    echo "sync-and-build: inserted EditPackages=DXControllerBtn into $INI"
fi

if (( DRY_RUN )); then
    echo "sync-and-build: dry run — skipping .u delete and build"
    exit 0
fi

cd "$BUILD_DIR/System"

# Pass 1: rebuild DeusEx.u (tolerate the GPF; verify .u landed). Also
# delete DeusExe.u so pass 2 rebuilds it from the synced .uc source —
# the launcher distribution may ship a different binary than what our
# source produces. Class identity is by name so either works at runtime,
# but rebuilding from our source keeps the build reproducible.
rm -f "$BUILD_DIR/System/DeusEx.u" "$BUILD_DIR/System/DeusExe.u"
cmd.exe /c "echo n | UCC.exe make" || true
if [[ ! -f "$BUILD_DIR/System/DeusEx.u" ]]; then
    echo "sync-and-build: DeusEx.u was not produced" >&2
    exit 1
fi

# Pass 2: rebuild DeusExe.u (pass-1 GPF prevents it) and DXController.u
# in a fresh UCC process. UCC walks EditPackages, skips DeusEx.u
# (present), builds DeusExe.u from the synced source, then DXController.u.
rm -f "$BUILD_DIR/System/DXController.u"
cmd.exe /c "UCC.exe make"
if [[ ! -f "$BUILD_DIR/System/DeusExe.u" ]]; then
    echo "sync-and-build: DeusExe.u was not produced" >&2
    exit 1
fi
if [[ ! -f "$BUILD_DIR/System/DXController.u" ]]; then
    echo "sync-and-build: DXController.u was not produced" >&2
    exit 1
fi

echo "sync-and-build: ok"
