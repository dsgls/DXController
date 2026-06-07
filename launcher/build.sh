#!/bin/sh
# Build the launcher locally. Run from the launcher/ dir.
set -e
MSBUILD="$("$(dirname "$0")/find-msbuild.sh")"
"$MSBUILD" "$(wslpath -w launcher.sln)" \
    -p:Configuration=Release -p:Platform=Win32 -m -verbosity:minimal -nologo
