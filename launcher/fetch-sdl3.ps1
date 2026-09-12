# Fetches the official prebuilt SDL3 Windows VC package for the launcher
# build. Downloads the release pinned in sdl3.version once, verifies its
# SHA-256, and extracts it to launcher\external\SDL3\ so headers land at
# external\SDL3\include\SDL3\*.h and libs at external\SDL3\lib\x86\.
# Idempotent: skips the download/extract if the pinned version is already
# present. Run from build.ps1; fetch-sdl3.sh is the bash twin.
#
# Written for Windows PowerShell 5.1 (also runs under pwsh 7).
$ErrorActionPreference = 'Stop'

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$pin = [IO.File]::ReadAllLines((Join-Path $scriptDir 'sdl3.version'))
$sdlVersion = $pin[0].Trim()
$sdlSha256 = $pin[1].Trim()
$sdlZip = "SDL3-devel-$sdlVersion-VC.zip"
$sdlUrl = "https://github.com/libsdl-org/SDL/releases/download/release-$sdlVersion/$sdlZip"

$externalDir = Join-Path $scriptDir 'external'
$sdlDir = Join-Path $externalDir 'SDL3'
$versionFile = Join-Path $sdlDir '.fetched-version'

if ((Test-Path $versionFile) -and ([IO.File]::ReadAllText($versionFile).Trim() -eq $sdlVersion)) {
    exit 0
}

New-Item -ItemType Directory -Force -Path $externalDir | Out-Null
$tmpZip = Join-Path $externalDir $sdlZip
Write-Host "fetch-sdl3: downloading SDL3 $sdlVersion..."
# 5.1: progress rendering makes -OutFile downloads very slow, TLS 1.2 is not
# negotiated by default, and -UseBasicParsing avoids the IE dependency.
$ProgressPreference = 'SilentlyContinue'
[Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
Invoke-WebRequest -UseBasicParsing -Uri $sdlUrl -OutFile $tmpZip

$actual = (Get-FileHash -Algorithm SHA256 -Path $tmpZip).Hash
if ($actual -ne $sdlSha256) {
    Remove-Item -Force $tmpZip
    throw "fetch-sdl3: SHA-256 mismatch for $sdlZip`nexpected $sdlSha256`ngot      $actual"
}

$tmpExtract = Join-Path $externalDir '.sdl3-extract-tmp'
if (Test-Path $tmpExtract) { Remove-Item -Recurse -Force $tmpExtract }
Expand-Archive -Path $tmpZip -DestinationPath $tmpExtract
# The zip's single top-level dir (SDL3-<ver>\) becomes SDL3\ directly.
if (Test-Path $sdlDir) { Remove-Item -Recurse -Force $sdlDir }
Move-Item -Path (Join-Path $tmpExtract "SDL3-$sdlVersion") -Destination $sdlDir
Remove-Item -Recurse -Force $tmpExtract
Remove-Item -Force $tmpZip

[IO.File]::WriteAllText($versionFile, "$sdlVersion`n")
Write-Host "fetch-sdl3: extracted SDL3 $sdlVersion to $sdlDir"
