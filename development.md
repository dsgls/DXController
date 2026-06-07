# Developing DXController

This is the script-side mod for the DXController project. It builds the
`DXController.u` package and a small overlay of edits to the stock
`DeusEx.u`.

## Repo layout

```
DXController/Classes/*.uc   the mod — one package, compiles to DXController.u
DeusEx/Classes/*.uc         overlay edits to stock DeusEx classes (rebuilds DeusEx.u)
DeusExe/Classes/*.uc        launcher overlay classes (now empty; pending removal)
launcher/                   launcher source (fork of Deus Exe, builds DeusEx.exe)
assets/                     source art + generators for the DXController textures
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

The other two repos are sibling working trees (`cd ../<name>`):

- `../deusex-native-re/` — Ghidra RE notes for the stock `.dll` binaries;
  read-only reference.
- `../deusex-scripts/` — batch-exported `.uc` files for every stock
  package; read-only reference.

The launcher is in-tree under `launcher/`; there is no external launcher
sibling repo.

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
EditPackages=DXController
```

The script adds this automatically.

### Build

The dev env is set up to run in WSL. Symlink your game directory to
`gamedir/` at the repository root.

```bash
nix run .#sync-and-build         # generate textures, sync overlays, two-pass UCC build
nix run .#sync-and-build -- -n   # dry run (list actions, skip the build)
BUILD_DIR=/path nix run .#sync-and-build
```

The `sync-and-build` flake app puts python3 + Pillow + numpy and dos2unix
on PATH; the script generates the texture PCX into
`gamedir/DXController/Textures/` before the compile, and the `#exec` lines
in `DXControllerTextures.uc` fold them into `DXController.u`.

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
`README.md`, and `DeusExe.exe` built from `launcher/` via
`launcher/build.sh` (MSBuild).

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

All DXController textures are generated at build time and compiled into
`DXController.u` via `#exec Texture Import` in
`DXController/Classes/DXControllerTextures.uc` — there is no separate
texture package. `sync-and-build.sh` (and CI) produce the PCX the imports
expect:

- `assets/gen-wheel.py` renders the weapon-wheel plate
  (`WheelPlate.png`) and the ten slice-highlight wedges
  (`wedges/wedge0..9.png`). It is parametric — tuning knobs at the top of
  the file; same inputs give byte-identical output.
- `assets/png-to-pcx.py` converts PNG → 8-bit PCX in two modes: `masked`
  (magenta key at palette index 0, for the glyphs and the plate) and
  `grey` (linear grey palette, no key, for the additive wedges).
- The button glyphs are hand-authored PNGs under `assets/XboxSeries/`.

The build writes the PCX into `<gamedir>/DXController/Textures/`; the
`#exec FILE=Textures\<name>.pcx` paths are relative to the package dir.
CI mirrors the same generation steps. python3 + Pillow + numpy are
provided by the `sync-and-build` flake app and `nix develop`.

