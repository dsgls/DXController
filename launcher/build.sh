#!/bin/sh
# Build the launcher locally. Run from the launcher/ dir.
set -e
"$(dirname "$0")/fetch-sdl3.sh"
MSBUILD="$("$(dirname "$0")/find-msbuild.sh")"
"$MSBUILD" "$(wslpath -w launcher.sln)" \
    -p:Configuration=Release -p:Platform=Win32 -m -verbosity:minimal -nologo
# The solution build also compiles tests.vcxproj, but msbuild does not run it.
./tests/Release/tests.exe
