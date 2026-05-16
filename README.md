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

The mod modifies `DeusEx.u`, so `gamedir/DeusEx/Classes/` must contain
the stock package source. One-time setup from `gamedir/System/`:

```cmd
ucc.exe batchexport DeusEx.u Class uc ..\DeusEx\Classes
```

## Build

```bash
./sync-and-build.sh        # rsync DXController/ and DeusEx/ → gamedir/, two-pass UCC build
./sync-and-build.sh -n     # dry-run rsync, skip build
```

Output: `gamedir/System/DeusEx.u` and `gamedir/System/DXController.u`.

`DXControllerBtn.u` — a pre-built controller-button texture package
committed at the repo root — is also required at runtime. `sync-and-build.sh`
copies it into `gamedir/System/` automatically; it must sit alongside the
built `.u` files there for the mod to load.

## Configuration (one-time)

### `gamedir/System/DeusEx.ini`

Append to the `EditPackages` block:

```ini
EditPackages=DXController
```

Replace the two stock lines in `[Engine.Engine]` with:

```ini
Console=DXController.ControllerConsole
Root=DXController.ControllerRootWindow
```

In `[DeusEx.DeusExPlayer]`:

```ini
bToggleCrouch=True
```

In `[WinDrv.WindowsClient]`:

```ini
UseDirectInput=False
UseJoystick=False
```

### `gamedir/System/User.ini`

**Back up `User.ini` before editing** — the snippet overwrites existing
`Joy*` / `JoyPov*` bindings.

```bash
cp "/path/to/Deus Ex/System/User.ini" "/path/to/Deus Ex/System/User.ini.bak"
```

Paste the block below into **both** `[Engine.Input]` and
`[Extension.InputExt]`:

```ini
Joy1=Jump
Joy2=ReloadWeapon
Joy3=ParseRightClick
Joy4=
Joy5=
Joy6=
Joy7=TogglePlayerMenuWindow
Joy8=ShowMainMenu
Joy9=
Joy10=
Joy15=
Joy16=
JoyPovUp=ActivateBelt 1
JoyPovLeft=ActivateBelt 2
JoyPovRight=ActivateBelt 3
JoyPovDown=ActivateBelt 4
JoyX=Axis aStrafe
JoyY=Axis aBaseY
JoyU=Axis aTurn
JoyV=Axis aLookUp
JoyZ=
JoyR=
```

## Button mappings

| Button         | Action                          |
|----------------|---------------------------------|
| A              | Jump                            |
| B              | Reload                          |
| X              | Use / interact                  |
| Y              | unbound                         |
| LB             | Inventory equip wheel           |
| RB             | Augmentation equip wheelt        |
| Back           | Toggle inventory / persona menu |
| Start          | Main menu                       |
| L-stick click  | Crouch                          |
| R-stick click  | unbound                         |
| D-pad up       | Belt slot 1                     |
| D-pad left     | Belt slot 2                     |
| D-pad right    | Belt slot 3                     |
| D-pad down     | Belt slot 4                     |
| LT             | Toggle scope / laser            |
| RT             | Fire                            |
| Left stick     | Move                            |
| Right stick    | Look                            |

Inside the inventory / persona menu, LB and RB cycle between tabs.

## Debugging

DXController emits diagnostic log lines (prefixed `DXC-`) describing
gamepad navigation, cursor-mode transitions, and wheel events. They
are off by default. To enable, add the following to `DeusEx.ini`:

```ini
[DXController.DXControllerDebug]
bGamepadDebugLog=True
```

Logs go to `…/System/DeusEx.log`.

## Known incompatibilities

- DXController overrides `[Engine.Engine]` `Console=` and `Root=`. Any other
  mod that overrides one of those will conflict — last one wins.
- DXController modifies `DeusEx.u`. Any other mod that ships its own
  `DeusEx.u` will conflict — last-installed wins.
- Multiplayer rejects non-stock root windows server-side. Single-player
  only; do not load the mod for an MP session.
- The XInput shim that delivers `IK_Joy*` and `IK_JoyPov*` events is
  external to this repo (typically a separate `Extension.dll` build). If
  the shim isn't installed, bindings will silently misfire.
