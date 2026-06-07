#!/bin/sh
MSBUILD="/mnt/c/Program Files/Microsoft Visual Studio/18/Community/MSBuild/Current/Bin/MSBuild.exe"
"$MSBUILD" "$(wslpath -w DeusExe.sln)" -p:Configuration=Release -p:Platform=Win32 -m -verbosity:minimal -nologo
