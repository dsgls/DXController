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
| `DXController.u`    | The mod                                                |

## Requirements

*Deus Ex: Game of the Year Edition* — the standard GOG or Steam release.

## Screenshots

![weapon wheel](/screenshots/weaponwheel.webp)
![inventory screen](/screenshots/inventory.webp)
![security terminal](/screenshots/securityterminal.webp)

## Install

Copy `DeusEx.exe`, `DeusEx.u`, and `DXController.u` from the release
   `.zip` into the game's `System` folder (e.g.
   `C:\GOG Games\Deus Ex GOTY\System\`), overwriting the existing
   `DeusEx.exe` and `DeusEx.u`.

I highly recommend enabling "Toggle Crouch" in the control settings.

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
