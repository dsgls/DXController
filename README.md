# Gamepad support for Deus Ex (2000)

DXController is a mod that implements broad gamepad support for the
original *Deus Ex* (2000, GOTY edition), covering Xbox, PlayStation,
Switch, and other SDL-recognized controllers. The game should feel as if
it was designed to be played with a controller, with context-dependent
controls and new UI elements. Gameplay is fully vanilla.

DXController adds much better controller feel, a weapon and augmentation
equipping wheel, an on-screen keyboard for terminals, and complete controller
navigation for every menu, conversation, and in-world device (keypads,
ATMs, computers, security terminals), so the game is playable end to
end without a mouse or keyboard.

## Download

Get the latest release from the
[releases page](https://github.com/dsgls/DXController/releases).

The release `.zip` contains everything you need:

| File                | What it is                                             |
|---------------------|--------------------------------------------------------|
| `DeusEx.exe`        | Launcher with the built-in controller driver           |
| `SDL3.dll`          | Controller backend the launcher loads (SDL3)           |
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

Copy `DeusEx.exe`, `SDL3.dll`, `DeusEx.u`, and `DXController.u` from the
   release `.zip` into the game's `System` folder (e.g.
   `C:\GOG Games\Deus Ex GOTY\System\`), overwriting the existing
   `DeusEx.exe` and `DeusEx.u`. `SDL3.dll` can be swapped for a newer
   official x86 build (from [libsdl.org](https://github.com/libsdl-org/SDL/releases))
   to pick up controller-support updates without waiting for a new
   DXController release. If your controller isn't recognized, drop a
   [`gamecontrollerdb.txt`](https://github.com/mdqinc/SDL_GameControllerDB)
   next to `DeusEx.exe`; the launcher loads it automatically if present.

Install a modern renderer. I recommend [Kentie's D3D10 renderer](https://www.kentie.net/article/d3d10drv/).
For some reason the main menu won't come up with the default one, don't
know why. But the modern one is way better anyway.

I highly recommend enabling "Toggle Crouch" in the control settings.

In the game, go to Settings -> Controller and configure at least your
controller's deadzone. The mod does not apply the comically large deadzone
used by most games, so if your controller sticks are not in good condition
you will need to increase them. The same screen has a right-stick
sensitivity setting (default 1.00) — lower it if turning at full stick
deflection is too fast.

The mod also autosaves periodically during play. Writing each save can cause
a brief stutter — if it bothers you, make autosaves less frequent or turn
them off entirely in Settings → Autosave.

If you have any other mods installed, start with a fresh game install
and install only DXController. Compatibility with other mods has not
been tested.

## Steam Deck

A user reported that the mod did not work on the Steam Deck with the
D3D10 renderer, but was able to get it working with the
[D3D11 renderer](https://www.kentie.net/article/d3d10drv/). They also
needed to set proton compatibility options to "Proton Experimental".

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
| Y              | Change ammo                     |
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

## Extra buttons and analog sources

Controllers with buttons beyond the standard layout — DualSense Edge
paddles, the DualSense/DS4 touchpad click, Switch capture, Series X
share, 8BitDo/Flydigi/HORI back buttons — get bindable slots
automatically: `paddle1`-`paddle4`, `misc1`, and `touchpad` map to
`Joy11`-`Joy16`. Bind them like any other gamepad button, in
`[Extension.InputExt]` in `User.ini`, e.g. `Joy16=Button bFire`.

Two `DeusEx.ini` sections give finer control, read at launcher startup
and on `GamepadReload` (Settings → Controller triggers a reload after
any change). UE1 ini files have no comment syntax — don't add `;`
comments to these sections.

### `[DXController.GamepadButtonMap]` — remap or add buttons

```ini
[DXController.GamepadButtonMap]
misc2=UnknownD8
y=Joy16
touchpad=Joy4
guide=None
```

The left side is one of SDL's button names: `a b x y back guide start
leftstick rightstick leftshoulder rightshoulder dpup dpdown dpleft
dpright misc1 paddle1 paddle2 paddle3 paddle4 touchpad misc2 misc3
misc4 misc5 misc6`. The right side is an engine key name (without the
`IK_` prefix) — the same names usable in `[Extension.InputExt]`
bindings, including `UnknownXX` slots — or `None` to unmap. Above:
`misc2` gets bound to a spare slot, `y` and `touchpad` swap their
default slots, and `guide` is explicitly unmapped.

Two buttons can't share a destination slot. Remapping a button onto a
slot another button already holds (by default or by an earlier line)
needs the displaced button remapped too — the two-line swap above is
the idiom — or set to `None`; otherwise the remap is rejected and
logged, and the button falls back to its default slot. A button moved
outside the `Joy1..16` range (e.g. onto `UnknownD8`) still works as a
binding but won't register as gamepad activity for cursor-mode
switching.

### `[DXController.GamepadAxisMap]` — extra analog sources

```ini
[DXController.GamepadAxisMap]
gyro.yaw=UnknownEA Scale=120 Deadzone=0.02
gyro.pitch=UnknownEB Scale=120 Deadzone=0.02
touchpad.x=UnknownDF
joyaxis.6=UnknownD8 Deadzone=0.1
```

Sources: `gyro.pitch|yaw|roll` (rad/s), `accel.x|y|z` (m/s²),
`touchpad.x|y` (`-1..1` while the pad is touched), and `joyaxis.N`
(the underlying joystick's Nth raw axis, normalized `-1..1`). The
right side is an engine key name as above, followed by optional
`Scale=` (default 1000) and `Deadzone=` (default 0, in the source's
own units). Bind the resulting axis in `[Extension.InputExt]`, e.g.
`UnknownEA=Axis aExtra0 Speed=1`.

**`gyro.*` and `accel.*` entries need an explicit `Scale`** — their
natural units (rad/s, m/s²) are far below 1, so without one the axis
never leaves the deadzone. **A `joyaxis.N` entry needs a `Deadzone`
if that axis doesn't rest at zero** — some sticks report a non-zero
floor at rest, and without a deadzone the axis reads as permanently
active, which pins the controller as the active input source and
keeps the mouse cursor from reappearing.

Free engine-key slots for these maps: `UnknownD8`, `UnknownD9`,
`UnknownDA`, `UnknownDF`, `UnknownEA`, `UnknownEB`, `UnknownF4`,
`UnknownF5`, `UnknownA4`-`UnknownB9`, and `UnknownC1`-`UnknownC7`.

Axis-map slots aren't visible to the mod's own cursor-mode and
menu-navigation logic (only `JoyX/Y/U/V` and the `Joy1..16`/D-pad
range are) — they drive bindings only, not menu/UI input.

### Xbox Elite paddle troubleshooting

Stock SDL (the controller library the launcher uses) cannot see Elite
paddle presses on Windows — this is an SDL/Windows limitation, not
something DXController can fix. Remap the paddles to standard buttons
using Microsoft's Xbox Accessories app, or use Steam Input (which
presents the pad to the game as a virtual Xbox controller with paddle
presses arriving as ordinary buttons). Paddles on DualSense Edge,
8BitDo, Flydigi, and similar pads work natively with no workaround.

The pre-game launcher and "FixApp" dialogs are navigable with an
Xbox-compatible (XInput) controller only; other controllers can still
navigate in-game.

## Auto-save

The mod autosaves during play. Change the settings in-game via
Settings → Autosave (enable/disable, interval, and how many autosaves to
keep). They are also stored in the `[DXController.AutoSaveManager]` section of
`DeusEx.ini` and can be edited there:

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
