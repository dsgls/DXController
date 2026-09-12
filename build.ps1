<#
.SYNOPSIS
Build DXController.u, the DeusEx.u overlay and the launcher, and install
them into a Deus Ex GOTY install.

.DESCRIPTION
    .\build.ps1 -GameDir "C:\Games\Deus Ex" [-SkipScripts] [-SkipLauncher]

-GameDir must contain System\UCC.exe, System\DeusEx.ini and a stock
DeusEx source export at DeusEx\Classes\ (one-time:
`ucc batchexport DeusEx.u Class uc ..\DeusEx\Classes` from System\).

-SkipScripts leaves the .u packages alone and only builds and installs
the launcher. -SkipLauncher does the opposite.

The same steps exist in bash form in sync-and-build.sh; keep the two in
step when changing either.

Written for Windows PowerShell 5.1; also runs under pwsh 7, which CI
uses. Two rules keep the shells behaving alike:
  - Native exit codes are checked by hand via $LASTEXITCODE. pwsh 7.4+
    would otherwise turn any non-zero native exit into a terminating
    error, and UCC pass 1 is expected to exit non-zero.
  - Never use Get-Content/Set-Content without an encoding (ANSI on 5.1,
    UTF-8 on 7). File contents are read and written via Latin-1, which
    round-trips every byte unchanged.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$GameDir,
    [switch]$SkipScripts,
    [switch]$SkipLauncher
)

$ErrorActionPreference = 'Stop'
if (Get-Variable PSNativeCommandUseErrorActionPreference -ErrorAction SilentlyContinue) {
    $PSNativeCommandUseErrorActionPreference = $false
}

$repoDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$latin1 = [Text.Encoding]::GetEncoding(28591)

function Fail([string]$Message) {
    if ($env:GITHUB_ACTIONS) { Write-Host "::error::$Message" }
    throw "build: $Message"
}

function Invoke-Native([string]$What, [scriptblock]$Call) {
    & $Call
    if ($LASTEXITCODE -ne 0) { Fail "$What failed with exit code $LASTEXITCODE" }
}

function New-TempDir {
    $dir = Join-Path ([IO.Path]::GetTempPath()) ('dxc-' + [IO.Path]::GetRandomFileName())
    New-Item -ItemType Directory -Path $dir | Out-Null
    return $dir
}

if ($SkipScripts -and $SkipLauncher) { Fail 'nothing to do: both -SkipScripts and -SkipLauncher given' }
if (-not (Test-Path -PathType Container $GameDir)) { Fail "game dir not found: $GameDir" }
$GameDir = (Resolve-Path $GameDir).Path
$systemDir = Join-Path $GameDir 'System'

# ---- Prerequisites -------------------------------------------------------

if (-not $SkipScripts) {
    if (-not (Get-Command uv -ErrorAction SilentlyContinue)) {
        Fail 'uv not found on PATH. Install it (winget install astral-sh.uv) and open a new terminal.'
    }
    foreach ($f in 'UCC.exe', 'DeusEx.ini') {
        if (-not (Test-Path (Join-Path $systemDir $f))) { Fail "$f not found in $systemDir" }
    }
    if (-not (Get-ChildItem -ErrorAction SilentlyContinue (Join-Path $GameDir 'DeusEx\Classes\*.uc'))) {
        Fail "no stock DeusEx source at $GameDir\DeusEx\Classes. Export it once from $systemDir with: ucc batchexport DeusEx.u Class uc ..\DeusEx\Classes"
    }
}

$msbuild = $null
if (-not $SkipLauncher) {
    if ($env:MSBUILD) {
        $msbuild = $env:MSBUILD
    } elseif ($cmd = Get-Command msbuild -ErrorAction SilentlyContinue) {
        $msbuild = $cmd.Source
    } else {
        $vswhere = Join-Path ${env:ProgramFiles(x86)} 'Microsoft Visual Studio\Installer\vswhere.exe'
        if (Test-Path $vswhere) {
            $found = @(& $vswhere -latest -requires Microsoft.Component.MSBuild -find 'MSBuild\**\Bin\MSBuild.exe')
            if ($found.Count -gt 0) { $msbuild = $found[0].Trim() }
        }
    }
    if (-not $msbuild -or -not (Test-Path $msbuild)) {
        Fail 'MSBuild not found. Install Visual Studio Build Tools with the "Desktop development with C++" workload, or set $env:MSBUILD.'
    }
}

# ---- Script packages -----------------------------------------------------

if (-not $SkipScripts) {
    # Wipe the DXController package dir so scripts or textures removed from
    # the repo can't linger. DeusEx\ is the full stock export and is only
    # ever overlaid, never reconstructed.
    $dxcDir = Join-Path $GameDir 'DXController'
    if (Test-Path $dxcDir) { Remove-Item -Recurse -Force $dxcDir }
    New-Item -ItemType Directory -Path (Join-Path $dxcDir 'Classes') | Out-Null

    # The repo stores .uc as LF (.gitattributes); UCC.exe wants CRLF. Convert
    # on the way in via Latin-1, which round-trips every byte unchanged.
    foreach ($pkg in 'DXController', 'DeusEx') {
        $dst = Join-Path $GameDir "$pkg\Classes"
        New-Item -ItemType Directory -Force -Path $dst | Out-Null
        foreach ($f in Get-ChildItem -File (Join-Path $repoDir "$pkg\Classes\*.uc")) {
            $text = $latin1.GetString([IO.File]::ReadAllBytes($f.FullName)) -replace "`r", "" -replace "`n", "`r`n"
            [IO.File]::WriteAllBytes((Join-Path $dst $f.Name), $latin1.GetBytes($text))
        }
    }

    # A DeusEx overlay file removed from the repo would otherwise stay in
    # the game dir with its old edits and keep compiling into DeusEx.u. The
    # manifest of what was overlaid last time catches that. No automatic
    # restore here (sync-and-build.sh restores from the maintainer's stock
    # export); the user re-exports the stock file.
    $deusExDst = Join-Path $GameDir 'DeusEx\Classes'
    $manifest = Join-Path $deusExDst '.dxc-overlay-files'
    if (Test-Path $manifest) {
        foreach ($name in ($latin1.GetString([IO.File]::ReadAllBytes($manifest)) -split "`n")) {
            $name = $name.Trim()
            if ($name -and -not (Test-Path (Join-Path $repoDir "DeusEx\Classes\$name"))) {
                Fail "$name was overlaid by a previous build but is gone from DeusEx\Classes. Restore the stock copy into $deusExDst (re-run ucc batchexport against a stock DeusEx.u) before building."
            }
        }
    }
    $names = @(Get-ChildItem -File (Join-Path $repoDir 'DeusEx\Classes\*.uc') | ForEach-Object { $_.Name })
    [IO.File]::WriteAllBytes($manifest, $latin1.GetBytes((($names + '') -join "`n")))

    # Generate the texture set and convert to the 8-bit PCX that the #exec
    # imports in DXControllerTextures.uc expect (FILE=Textures\<name>.pcx,
    # relative to the package dir). Button glyphs are committed PNGs.
    $texDir = Join-Path $dxcDir 'Textures'
    New-Item -ItemType Directory -Path $texDir | Out-Null
    $wheelSrc = New-TempDir; $menuBgSrc = New-TempDir; $veilSrc = New-TempDir
    try {
        $assets = Join-Path $repoDir 'assets'
        $pcx = Join-Path $assets 'png-to-pcx.py'
        Invoke-Native 'gen-wheel'   { uv run (Join-Path $assets 'gen-wheel.py') $wheelSrc }
        Invoke-Native 'gen-menu-bg' { uv run (Join-Path $assets 'gen-menu-bg.py') $menuBgSrc }
        Invoke-Native 'gen-veil'    { uv run (Join-Path $assets 'gen-veil.py') $veilSrc }
        Invoke-Native 'png-to-pcx' { uv run $pcx (Join-Path $assets 'XboxSeries') $texDir --size 64 --mode masked }
        # --key black: the wheel plate is drawn DSTY_Translucent, which adds
        # the palette-index-0 key colour to the scene.
        Invoke-Native 'png-to-pcx' { uv run $pcx $wheelSrc $texDir --size 1024 --mode masked --key black }
        Invoke-Native 'png-to-pcx' { uv run $pcx (Join-Path $wheelSrc 'wedges') $texDir --size 1024 --mode grey }
        Invoke-Native 'png-to-pcx' { uv run $pcx (Join-Path $wheelSrc 'veil') $texDir --size 1024 --mode grey }
        # Menu-bg tiles are 256x256; --size native keeps them from being
        # square-resized against the default.
        Invoke-Native 'png-to-pcx' { uv run $pcx $menuBgSrc $texDir --size native --mode grey }
        Invoke-Native 'png-to-pcx' { uv run $pcx $veilSrc $texDir --size native --mode grey }
    } finally {
        Remove-Item -Recurse -Force $wheelSrc, $menuBgSrc, $veilSrc -ErrorAction SilentlyContinue
    }

    # UCC builds what DeusEx.ini's EditPackages lists. Insert DXController
    # right after DeusEx so it compiles against the rebuilt overlay.
    $ini = Join-Path $systemDir 'DeusEx.ini'
    $content = $latin1.GetString([IO.File]::ReadAllBytes($ini))
    if ($content -notmatch '(?m)^EditPackages=DXController\r?$') {
        $content = $content -replace "EditPackages=DeusEx`r`n", "EditPackages=DeusEx`r`nEditPackages=DXController`r`n"
        if ($content -notmatch '(?m)^EditPackages=DXController\r?$') {
            Fail "could not insert EditPackages=DXController into $ini (no EditPackages=DeusEx line?)"
        }
        [IO.File]::WriteAllBytes($ini, $latin1.GetBytes($content))
        Write-Host 'build: registered EditPackages=DXController in DeusEx.ini'
    }

    Push-Location $systemDir
    try {
        # Pass 1: rebuild DeusEx.u. UCC prompts to overwrite
        # DeusEx\Inc\DeusExClasses.h ('n' lets it continue), then crashes
        # while loading the package it just wrote. The .u is complete on
        # disk before the crash, so the exit code is ignored and the file
        # is the success signal.
        Remove-Item -ErrorAction SilentlyContinue 'DeusEx.u'
        'n' | & .\UCC.exe make
        $global:LASTEXITCODE = 0
        Write-Host 'build: the UCC error above is expected: a stock game bug makes UCC crash after writing DeusEx.u'
        if (-not (Test-Path 'DeusEx.u')) { Fail 'DeusEx.u was not produced' }
        $size = (Get-Item 'DeusEx.u').Length
        if ($size -lt 1MB) { Fail "DeusEx.u is $size bytes (< 1 MiB): UCC silent failure" }
        Write-Host "build: DeusEx.u OK ($size bytes)"

        # Pass 2: a fresh UCC process finds DeusEx.u present, skips it, and
        # builds DXController.u without hitting the load-time crash.
        Remove-Item -ErrorAction SilentlyContinue 'DXController.u'
        Invoke-Native 'UCC make (DXController)' { & .\UCC.exe make }
        if (-not (Test-Path 'DXController.u')) { Fail 'DXController.u was not produced' }
        $size = (Get-Item 'DXController.u').Length
        if ($size -lt 100KB) { Fail "DXController.u is $size bytes (< 100 KiB): UCC silent failure" }
        Write-Host "build: DXController.u OK ($size bytes)"
    } finally {
        Pop-Location
    }
}

# ---- Launcher ------------------------------------------------------------

if (-not $SkipLauncher) {
    $launcherDir = Join-Path $repoDir 'launcher'
    & (Join-Path $launcherDir 'fetch-sdl3.ps1')
    Invoke-Native 'msbuild' {
        & $msbuild (Join-Path $launcherDir 'launcher.sln') /p:Configuration=Release /p:Platform=Win32 /m -verbosity:minimal -nologo
    }
    $exe = Join-Path $launcherDir 'Release\DeusEx.exe'
    if (-not (Test-Path $exe)) { Fail 'launcher build did not produce DeusEx.exe' }
    # The solution build compiles tests.vcxproj but never runs it. Run it
    # before installing so a red test can't leave a fresh exe in the game dir.
    Invoke-Native 'launcher tests' { & (Join-Path $launcherDir 'tests\Release\tests.exe') }
    foreach ($f in $exe, (Join-Path $launcherDir 'Release\DeusEx.pdb'), (Join-Path $launcherDir 'external\SDL3\lib\x86\SDL3.dll')) {
        Copy-Item -Force $f $systemDir
    }
    Write-Host "build: installed DeusEx.exe, DeusEx.pdb and SDL3.dll to $systemDir"
}

Write-Host 'build: ok'
