# Developing DXController

This is the script-side mod for the DXController project. It builds the
`DXController.u` package and a small overlay of edits to the stock
`DeusEx.u`.

## Repo layout

```
DXController/Classes/*.uc   the mod — one package, compiles to DXController.u
DeusEx/Classes/*.uc         overlay edits to stock DeusEx classes (rebuilds DeusEx.u)
DeusExe/Classes/*.uc        classes vendored from the DeusExe-XInput launcher repo
DXControllerTex.u           pre-built texture package (button glyphs, wheel backplate)
assets/                     source art for DXControllerTex.u + conversion tooling
sync-and-build.sh           rsync + two-pass UCC build
.github/workflows/build.yml CI build and release packaging
CLAUDE.md                   authoritative engine-quirk and convention notes
scripting-reference.txt     UE1-era UnrealScript language reference
```

`DeusEx.u` is rebuildable, so base-game behaviour is changed by placing
an edited copy of a stock class under `DeusEx/Classes/` — the build
overlays it on the stock tree. Stock files we don't touch stay stock.
Unrebuildable packages (`Engine.u` and friends) are diverted by
subclassing and repointing an `.ini` binding instead.

## Sister repos

The other three repos are sibling working trees (`cd ../<name>`):

- [DeusExe-XInput](https://github.com/dsgls/DeusExe-XInput) — fork of
  [Deus Exe](https://kentie.net/article/dxguide/) that adds XIpnut
  support, and also applies some runtime binary patches to Extension.dll
  to fix engine bugs. This builds DeusEx.exe.

CI also clones a private `deusex-buildtools` repo that holds a stock
game tree (engine `.u` files, `UCC.exe`, base `.ini`s) so the build can
run without a game install.

## Building

### Prerequisites

- A Deus Ex GOTY install with `UCC.exe` in `System/`.
- WSL, or bash with `rsync` and access to `cmd.exe`.

### One-time setup

Symlink `gamedir/` at your install (it's gitignored; the build script
reads it as `BUILD_DIR`):

```bash
ln -s "/path/to/Deus Ex" gamedir
```

The overlay rebuilds `DeusEx.u`, so the build dir needs the stock
`DeusEx` source. Export it once, from `gamedir/System/`:

```cmd
ucc.exe batchexport DeusEx.u Class uc ..\DeusEx\Classes
```

`DeusEx.ini` must have:
```ini
EditPackages=DXControllerTex
EditPackages=DXController
```

The script adds these automatically.

### Build

The dev env is set up to run in WSL. Symlink your game directory to
`gamedir/` at the repository root.

```bash
./sync-and-build.sh        # rsync overlays → gamedir, two-pass UCC build
./sync-and-build.sh -n     # dry-run rsync, skip the build
BUILD_DIR=/path ./sync-and-build.sh   # override the build dir
```

The build runs `UCC.exe make` twice: pass 1 rebuilds `DeusEx.u`
(tolerating a known UCC GPF), pass 2 builds `DeusExe.u` and
`DXController.u` in a fresh process. The header comment in
`sync-and-build.sh` explains the two-pass dance in detail; `CLAUDE.md`
covers the GPF.

Output lands in `gamedir/System/`: `DeusEx.u`, `DeusExe.u`,
`DXController.u`.

## Releases

`.github/workflows/build.yml` builds on every push to `master` and, on
a `v*` tag, assembles the release `.zip`: the three built `.u` files,
the pre-built `DXControllerTex.u`, `README.md`, and the matching
`DeusExe.exe` downloaded from the
[DeusExe-XInput releases](https://github.com/dsgls/DeusExe-XInput/releases).
The bundled launcher version is pinned by `DEUSEXE_XINPUT_VERSION` in
the workflow — bump it when cutting a release that needs a newer
launcher.

To cut a release, push a `v*` tag.

## Architecture

The mod hooks the input stream and the UI by repointing two engine
bindings (`CLAUDE.md` → *Packages that can't be rebuilt*):

- ControllerConsole (`Console=`) is the first script-side entry
  point for every input event. It interprets axes and buttons during
  gameplay and forwards stick axes through the menu state.
- ControllerRootWindow (`Root=`) owns the UI side: cursor-mode
  transitions, the weapon/aug wheel, the on-screen keyboard, and a
  registry of per-screen navigation controllers.

**Menu navigation** is one `MenuNavController` subclass per screen
(`DXController/Classes/<Screen>NavController.uc`).
`ControllerRootWindow` attaches a controller when its screen appears in
the window tree and detaches when it leaves. To support a new screen,
write the controller and add one `RegisterNav(...)` line — see
*Menu nav controllers* in `CLAUDE.md` for the controller patterns
(list, grid, scroll) and their canonical templates.

The input pipeline — XInput shim → engine → `Console.KeyEvent` →
`InputExt` — is documented in `CLAUDE.md` (*Input flow*) and, at the
native level, in `../deusex-native-re/docs/input-chain.md`.

### Debug logging

Gamepad debug logs go through
`class'DXControllerDebug'.static.DebugLog("DXC-...")`, prefixed by area
(`DXC-WHEEL`, `DXC-NAV`, `DXC-CURSOR`, …). They are off by default;
enable them in `DeusEx.ini`:

```ini
[DXController.DXControllerDebug]
bGamepadDebugLog=True
```

Output goes to `System/DeusEx.log`.

## Conventions

`CLAUDE.md` is the authoritative reference for this codebase: the
source-overlay model, UE1-era UnrealScript quirks, the build dance, the
input pipeline, and the navigation-controller patterns. Read it before
making changes — much of the modern UnrealScript material online does
not apply to this UE1-era engine. `scripting-reference.txt` is a
fuller language rundown.

## Asset tooling

`DXControllerTex.u` is a binary texture package committed at the repo
root. Its source art lives in `assets/`; `assets/png-to-pcx.py`
converts PNGs to the 8-bit PCX format the package import expects. The
`flake.nix` provides a Python + Pillow environment for it:

```bash
nix run .#png-to-pcx -- [SRC_DIR] [DST_DIR] [--size N]
nix develop          # shell with python3 + Pillow
```

Building the DXControllerTex.u needs to be done in UnrealEd.

