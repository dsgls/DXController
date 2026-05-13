# DXController

XInput controller support for Deus Ex (UE1-era / GOTY).

## Requirements

- A Deus Ex install with `UCC.exe` in `System/`
- WSL, or bash with `rsync` and access to `cmd.exe`

## Setup

Create a symlink pointing at your local game install:

```bash
ln -s "/path/to/Deus Ex" gamedir   # e.g. "/mnt/c/leikir/Deus Ex GOTY - hax"
```

`gamedir/` is gitignored. The build script reads it as `BUILD_DIR`; override
with `BUILD_DIR=/path ./sync-and-build.sh` if you'd rather not symlink.

In `gamedir/System/DeusEx.ini`, append `EditPackages=DXController` to the
`EditPackages` block so the compiler picks up this package.

## Build

```bash
./sync-and-build.sh        # rsync DXController/ → gamedir/, delete DXController.u, UCC.exe make
./sync-and-build.sh -n     # dry-run rsync, skip build
```

Output: `gamedir/System/DXController.u`.

## Configuration (one-time)

DXController plugs into the engine via three `[Engine.Engine]` ini lines, the
`EditPackages` block, and a binding snippet. Apply all of them before running
the mod.

### `gamedir/System/DeusEx.ini`

In the `EditPackages` block, append:

```ini
EditPackages=DXController
```

In the `[Engine.Engine]` block, replace the three stock lines with:

```ini
Console=DXController.ControllerConsole
DefaultGame=DXController.ControllerGameInfo
Root=DXController.ControllerRootWindow
```

The stock values being replaced are `Engine.Console`, `DeusEx.DeusExGameInfo`,
and `DeusEx.DeusExRootWindow`.

### `gamedir/System/User.ini`

**Back up `User.ini` before editing.** The snippet overwrites any existing
`Joy*` and `JoyPov*` bindings; reverting requires the backup.

```bash
cp "/path/to/Deus Ex/System/User.ini" "/path/to/Deus Ex/System/User.ini.bak"
```

Apply the bindings to **both** `[Engine.Input]` and `[Extension.InputExt]`
sections. `[Extension.InputExt]` is the active binding section in this
install (the Extension.dll native input handler reads from it; see
`CLAUDE.md` § "Native input handler: Extension.InputExt"). `[Engine.Input]`
is the stock UE1 fallback. Duplicating the snippet across both sections is
the safest approach.

```ini
Joy1=Jump                       ; A
Joy2=ReloadWeapon               ; B
Joy3=ParseRightClick            ; X — use object in world
Joy4=                           ; Y — intentionally unbound (reserved for the radial wheel)
Joy5=LeanLeft                   ; LB
Joy6=LeanRight                  ; RB
Joy7=TogglePlayerMenuWindow     ; Back — toggles the F1 menu; remembers the last persona screen
Joy8=ShowMainMenu               ; Start — main menu
Joy9=Duck                       ; L-stick click — crouch (toggle vs hold per bToggleCrouch)
Joy10=                          ; R-stick click — intentionally unbound
JoyPovUp=ActivateBelt 0         ; D-pad slot 1
JoyPovLeft=ActivateBelt 1       ; D-pad slot 2
JoyPovRight=ActivateBelt 2      ; D-pad slot 3
JoyPovDown=ActivateBelt 3       ; D-pad slot 4
Joy15=Fire                      ; RT — synthesised from IK_JoyR axis by ControllerConsole
Joy16=ToggleScopeOrLaser        ; LT — synthesised from IK_JoyZ axis
```

Axis bindings (left stick → `aBaseX`/`aBaseY`, right stick → `aMouseX`/`aMouseY`,
etc.) are inherited from stock `User.ini`. Tuning is a later phase.

## Known incompatibilities

- DXController overrides `[Engine.Engine]` `Console=`, `DefaultGame=`, and
  `Root=`, and sets `DefaultPlayerClass` on the new GameInfo. Any other mod
  that overrides one of those will conflict — last one wins.
- `ControllerGameInfo` overrides `ApproveClass` (which stock `DeusExGameInfo`
  returns `false` from unconditionally) so that `ControllerPlayer` actually
  spawns. Mods that also override `ApproveClass` may conflict.
- Multiplayer rejects non-stock root windows server-side (per `DeusExMPGame.uc`).
  Phase 1 is single-player-only; do not load the mod for an MP session.
- The XInput shim that delivers `IK_Joy*` and `IK_JoyPov*` events is external
  to this repo (typically a separate `Extension.dll` build). If the shim
  isn't installed or its slot mapping diverges from the table in `CLAUDE.md`,
  bindings will silently misfire.
