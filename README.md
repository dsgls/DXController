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

All development of this mod has been done with an Xbox One controller. It
should work with every other controller supported by SDL (which is basically
all of them), but all the on-screen button hints use Xbox controller icons.

[Trigger warning: LLM assisted with parts of this project](#llm-usage-in-this-project)

## Requirements

- *Deus Ex: Game of the Year Edition* — the standard GOG or Steam release.

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

## Screenshots

![weapon wheel](/screenshots/weaponwheel.webp)
![controller settings screen](/screenshots/controllersettings.webp)
![security terminal](/screenshots/securityterminal.webp)
![on-screen keyboard](/screenshots/keyboard.webp)

## Install

1. Copy `DeusEx.exe`, `SDL3.dll`, `DeusEx.u`, and `DXController.u` from
   the release `.zip` into the game's `System` folder (e.g.
   `C:\GOG Games\Deus Ex GOTY\System\`), overwriting the existing
   `DeusEx.exe` and `DeusEx.u`.

If you have any other mods installed, start with a fresh game install
and install only DXController. Compatibility with other mods has not
been tested.

## Recommended settings

I highly recommend enabling "Toggle Crouch" in the control settings.

In the game, go to Settings -> Controller and configure at least your
controller's deadzone. The mod does not apply the comically large deadzone
used by most games, so if your controller sticks are not in good condition
you will need to increase them. The same screen has a right-stick
sensitivity setting — lower it if turning at full stick deflection is too
fast, and an "Invert look Y-axis" toggle that flips the right stick's up/down
direction for gameplay look and the security camera. The launcher applies the
inversion to the right-stick Y axis it emits, so if you rebind that axis away
from `aLookUp` in `User.ini` the inversion follows whatever you bound it to.

The mod also autosaves periodically during play. Writing each save can cause
a brief stutter — if it bothers you, make autosaves less frequent or turn
them off entirely in Settings → Autosave.

## Linux and Steam Deck

The mod works on Linux and the Steam Deck under Proton. Some users have
reported that they needed to set the Proton compatibility option to
"Proton Experimental".

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

On the "Start New Game" screen, A on the Real Name field opens the
on-screen keyboard so you can set your name without a keyboard — it types
in capitals only. Start begins the game from anywhere on that screen, or
jumps to the name field and opens the keyboard if you haven't entered a
name yet.

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

## Renderer

While not required for the mod, I highly recommend installing a modern
renderer. They work better with todays machines, and they improve the
look of the graphics.

I have tested these renderers and can recommend them:
[D3D10 renderer](https://www.kentie.net/article/d3d11drv/)
[D3D11 renderer](https://www.kentie.net/article/d3d11drv/)
[enhanced OpenGL renderer](https://www.cwdohnal.com/utglr/)

The D3D10 renderer is better than the D3D11 renderer, so pick it unless
you have a good reason not to.

## Extra buttons and analog sources

Controllers with buttons beyond the standard layout — DualSense Edge
paddles, the DualSense/DS4 touchpad click, Switch capture, Series X
share, 8BitDo/Flydigi/HORI back buttons — get bindable slots
automatically: `paddle1`-`paddle4`, `misc1`, and `touchpad` map to
`Joy11`-`Joy16`. Bind them like any other gamepad button, in
`[Extension.InputExt]` in `User.ini`, e.g. `Joy16=Button bFire`.

WARNING: Unlike the rest of the mod, I have **not tested** any of the
features described in this section, because I only have a regular Xbox
One controller. I added this due to user requests, I think it should
work but can't guarantee anything. If you do try it, let me know how
it goes.

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

The pre-game launcher and "FixApp" dialogs use the same SDL gamepad
support as the game, so any supported controller can navigate them.

## Unrecognized controllers and SDL3 updates

If your controller isn't recognized, drop a
[`gamecontrollerdb.txt`](https://github.com/mdqinc/SDL_GameControllerDB)
next to `DeusEx.exe`; the launcher loads it automatically if present.

`SDL3.dll` can be swapped for a newer official x86 build (from
[libsdl.org](https://github.com/libsdl-org/SDL/releases)) to pick up
controller-support updates without waiting for a new DXController
release.

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

## LLM usage in this project

An LLM was used to assist in the creation of this mod. I have been programming
for a couple of decades now, and I used that background to make every technical
and design decision in this project. I find the slop generators quite useful
for the menial implementation tasks when I've already prepared a detailed
specification, but they can't be trusted to make any real decisions or
you'll end up with code that nobody understands. I have also personally
done extensive playtesting with the mod. This is not some low-effort vibecoded
project where someone just asked claude to make a thing and called it a day.

It's sad that I have to write this section, but I can't deny that there is
a ridiculous amount of slopware being pushed out these days. These projects
look very professional, but as soon as you try them you find obvious bugs
that make you question whether anyone even tried to use the thing. Well, this
is not one of those projects.

The other reason for writing this is that some people have a strong, visceral
reaction to anything even tangentially related to LLMs. They do not accept
that it is possible to write useful software if an LLM came anywhere near
it, no matter how it was used. I disagree with this, but I respect their
opinion, and much as I would tell a vegan if there were meat in a sandwich,
here I am telling those with inflexible opinions on LLMs that their time
is better spent elsewhere.

## License

GPLv3+

Files modified from the original game are copyright Ion Storm and no
license claim is made for them.

This project uses a modified version of Deus Exe by kentie. I did not
find any license information for it, but copyright of the original
Deus Exe is held by the original author. My modifications are licensed
GPLv3 or any license the original author chooses.
