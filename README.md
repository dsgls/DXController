# xInput controller support for Deus Ex (1999)

DXController is a mod that implements Xbox controller support for the
original *Deus Ex* (2000, GOTY edition). The game should feel as if
it was designed to be played with a controller, with context-dependent
controls and new UI elements. Gameplay is fully vanilla.

DXController adds much better controller feel, a weapon and augmentation
equipping wheel, an on-screen keyboard for terminals, and complete controller
navigation for every menu, conversation, and in-world device (keypads,
ATMs, computers, security terminals) — so the game is playable end to
end without a mouse or keyboard.

## Download

Get the latest release from the
[releases page](https://github.com/dsgls/DXController/releases).

The release `.zip` contains everything you need:

| File                | What it is                                             |
|---------------------|--------------------------------------------------------|
| `DeusEx.exe`        | Launcher with the built-in XInput controller driver    |
| `DeusEx.u`          | Stock package with small controller hooks added        |
| `DXController.u`    | The mod                                                |

## Requirements

*Deus Ex: Game of the Year Edition* — the standard GOG or Steam release.

## Screenshots

![weapon wheel](/screenshots/weaponwheel.webp)
![controller settings screen](/screenshots/controllersettings.webp)
![security terminal](/screenshots/securityterminal.webp)
![on-screen keyboard](/screenshots/keyboard.webp)

## Install

Copy `DeusEx.exe`, `DeusEx.u`, and `DXController.u` from the release
   `.zip` into the game's `System` folder (e.g.
   `C:\GOG Games\Deus Ex GOTY\System\`), overwriting the existing
   `DeusEx.exe` and `DeusEx.u`.

Install a modern renderer. I recommend [Kentie's D3D10 renderer](https://www.kentie.net/article/d3d10drv/).
For some reason the main menu won't come up with the default one, don't
know why. But the modern one is way better anyway.

I highly recommend enabling "Toggle Crouch" in the control settings.

In the game, go to Settings -> Controller and configure at least your
controller's deadzone. The mod does not apply the comically large deadzone
used by most games, so if your controller sticks are not in good condition
you will need to increase them.

If you have any other mods installed, start with a fresh game install
and install only DXController. Compatibility with other mods has not
been tested.

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
confirms, and B cancels. LB/RB cycle between tabs in the
inventory and persona screens.

On-screen button hints show what each button does for the selected item.
In the inventory screen the controller-specific actions are:

| Button         | Action                                                       |
|----------------|--------------------------------------------------------------|
| A              | Equip — or Use, for medkits, biocells, and armour/camo (Ballistic Armor, Thermoptic Camo, HazMat Suit, Rebreather, Tech Goggles) |
| Y              | Move item — then D-pad to position, A to place, B to cancel  |
| L-stick click  | Change ammo (weapons that can load more than one ammo type)  |
| X              | Assign item to a belt slot                                   |
| R-stick click  | Drop item                                                    |

When moving an item, it glows green where it fits and red where it would
overlap another item; A only places it on a green spot.

## Auto-save

The mod autosaves during play. It works out of the box with the defaults
below; to change them, add a `[DXController.AutoSaveManager]` section to
`DeusEx.ini` (the keys are not written there automatically):

| Key | Default | Meaning |
|-----|---------|---------|
| `bEnabled` | `True` | Turn autosave on/off |
| `IntervalSeconds` | `60` | Seconds of play between autosaves (floored at 10) |
| `MaxSaves` | `40` | How many autosaves to keep (1–100); oldest is discarded |

Autosaves appear in the normal Load Game list, named `Auto Save - <map>`,
and load like any other save. The interval counts play time only — it does
not advance while paused or in a menu — and a due autosave waits until you
leave any conversation, menu, or cutscene before it fires. Each save shows a
brief "Auto Saving..." note in the bottom-left corner.

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
