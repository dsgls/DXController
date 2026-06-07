#!/bin/sh
# Resolve MSBuild.exe for the launcher build. Echoes WSL path to stdout.
# Resolution order: $MSBUILD env -> vswhere.exe -> fail with clear message.
set -e
if [ -n "${MSBUILD:-}" ]; then
    [ -x "$MSBUILD" ] || { echo "find-msbuild: \$MSBUILD set to non-executable: $MSBUILD" >&2; exit 1; }
    printf '%s\n' "$MSBUILD"
    exit 0
fi
VSWHERE='/mnt/c/Program Files (x86)/Microsoft Visual Studio/Installer/vswhere.exe'
if [ -x "$VSWHERE" ]; then
    WIN_PATH="$("$VSWHERE" -latest -requires Microsoft.Component.MSBuild \
                          -find 'MSBuild\**\Bin\MSBuild.exe' | head -n1 | tr -d '\r')"
    if [ -n "$WIN_PATH" ]; then
        wslpath -u "$WIN_PATH"
        exit 0
    fi
fi
echo "find-msbuild: no MSBuild found. Set \$MSBUILD or install Visual Studio / Build Tools." >&2
exit 1
