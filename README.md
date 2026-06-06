# DXController

Full Xbox-controller support for the original *Deus Ex* (2000, GOTY
edition). DXController adds gamepad-driven movement and aiming, a weapon
and augmentation wheel, an on-screen keyboard, and complete controller
navigation for every menu, conversation, and in-world device (keypads,
ATMs, computers, security terminals) — so the game is playable end to
end without a mouse or keyboard.

The mod is intended to feel like the game was made to be played on
a controller. This means context-dependent controls and new UI elements
like weapon/aug wheels for equipping, and an onscreen keyboard for
entering usernames and passwords.

## Download

Get the latest release from the
[releases page](https://github.com/dsgls/DXController/releases).

The release `.zip` contains everything you need:

| File                | What it is                                             |
|---------------------|--------------------------------------------------------|
| `DeusEx.exe`       | Launcher with the built-in XInput controller driver    |
| `DeusEx.u`          | Stock package with small controller hooks added        |
| `DeusExe.u`         | Launcher support package                               |
| `DXController.u`    | The mod                                                |

## Requirements

*Deus Ex: Game of the Year Edition* — the standard GOG or Steam release.

## Screenshots

![weapon wheel](/screenshots/weaponwheel.webp)
![inventory screen](/screenshots/inventory.webp)
![security terminal](/screenshots/securityterminal.webp)

## Install

1. Copy all four files from the release `.zip` into the game's `System`
   folder (e.g. `C:\GOG Games\Deus Ex GOTY\System\`), overwriting
   `DeusEx.u`.

2. Apply the `.ini` edits below.

4. Launch the game with **`DeusEx.exe`** (not the stock `DeusEx.exe`).
   Controller input is only delivered through this launcher.

### `System\DeusEx.ini`

Under `[Engine.Engine]`, replace the existing `Console=` and `Root=`
lines with:

```ini
Console=DXController.ControllerConsole
Root=DXController.ControllerRootWindow
```

Under `[DeusEx.DeusExPlayer]`:

```ini
bToggleCrouch=True
```

Under `[WinDrv.WindowsClient]`:

```ini
UseDirectInput=False
UseJoystick=False
```

By default, the controller sticks use a linear curve. I recommend the following settings for exponential curves with better feel. In `[DeusExe]`:

```ini
XInputLeftStickExponent=2
XInputRightStickExponent=5
```

### `System\User.ini`

Paste the block below into `[Extension.InputExt]` section, replacing any
existing `Joy*` lines:

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

## Controls

| Button         | Action                          |
|----------------|---------------------------------|
| Left stick     | Move                            |
| Right stick    | Look                            |
| RT             | Fire                            |
| LT             | Toggle scope / laser            |
| A              | Jump                            |
| B              | Reload                          |
| X              | Use / interact                  |
| Y              | unbound                         |
| LB             | Inventory / weapon wheel        |
| RB             | Augmentation wheel              |
| Back           | Toggle inventory / persona menu |
| Start          | Main menu                       |
| L-stick click  | Crouch                          |
| R-stick click  | unbound                         |
| D-pad up       | Belt slot 1                     |
| D-pad left     | Belt slot 2                     |
| D-pad right    | Belt slot 3                     |
| D-pad down     | Belt slot 4                     |

In menus, conversations, and devices the D-pad moves the selection, A
confirms, and B cancels. **LB / RB** cycle between tabs in the
inventory and persona screens.

## Troubleshooting

- Verify that you replaced the original .ini file settings, and didn't
  duplicate the existing key.
- Make sure `UseDirectInput` and `UseJoystick` are both `False`.
- If you have any other mods installed, start with a fresh game install
  and install only DXController. Compatibility with other mods has not
  been tested.

## Development

See [`development.md`](development.md) for the repo layout, build
instructions, and architecture notes.

## License

GPLv3+

Files modified from the original game are copyright Ion Storm and no
license claim is made for them.

This project uses a modified version of Deus Exe by kentie. I did not
find any license information for it, but copyright of the original
Deus Exe is held by the original author. My modifications are licensed
GPLv3 or any license the original author chooses.
