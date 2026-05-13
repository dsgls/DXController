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

DXController plugs into the engine via two `[Engine.Engine]` ini lines, the
`EditPackages` block, and a binding snippet. Apply all of them before running
the mod.

### `gamedir/System/DeusEx.ini`

In the `EditPackages` block, append:

```ini
EditPackages=DXController
```

In the `[Engine.Engine]` block, replace the two stock lines with:

```ini
Console=DXController.ControllerConsole
Root=DXController.ControllerRootWindow
```

The stock values being replaced are `Engine.Console` and
`DeusEx.DeusExRootWindow`. `DefaultGame=DeusEx.DeusExGameInfo` is left
untouched — overriding it has no effect for single-player because
`GameInfo.Login` matches the level's pre-placed `JCDentonMale` rather
than spawning `DefaultPlayerClass`.

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
Joy4=                           ; Y — intentionally unbound
Joy5=                           ; LB — see "Held-state actions" note
Joy6=                           ; RB — see "Held-state actions" note
Joy7=TogglePlayerMenuWindow     ; Back — toggles the F1 menu; remembers the last persona screen
Joy8=ShowMainMenu               ; Start — main menu
Joy9=                           ; L-stick click — see "Held-state actions" note
Joy10=                          ; R-stick click — intentionally unbound
JoyPovUp=ActivateBelt 1         ; D-pad slot 1 (slot 0 is the keyring)
JoyPovLeft=ActivateBelt 2       ; D-pad slot 2
JoyPovRight=ActivateBelt 3      ; D-pad slot 3
JoyPovDown=ActivateBelt 4       ; D-pad slot 4
Joy15=                          ; RT — Fire is dispatched in-engine from IK_JoyR axis
Joy16=                          ; LT — ToggleScopeOrLaser is dispatched in-engine from IK_JoyZ axis
```

Triggers don't go through the binding system. The press/release synthesis
from the axis stream can't be injected into the binding dispatcher from
script, so `ControllerConsole` watches `IK_JoyZ`/`IK_JoyR` directly and
dispatches to the pawn. The `Joy15=` / `Joy16=` lines stay blank so the
in-game Customize Keys UI doesn't show a misleading stale binding.

#### Held-state actions (lean, crouch) are not bindable to gamepad buttons

Anything that needs "is the button currently held" — lean, crouch, run —
can't be hooked to a Joy* button on this install. Two compounding issues:

1. `Extension.InputExt` stubs `UInput::PreProcess`, killing button-alias
   state synthesis. `LeanLeft = "Axis aExtra0 Speed=-0.05"` and
   `Duck = "Button bDuck | …"` don't produce the per-tick writes they
   depend on.
2. The XInput shim auto-fires an `IST_Release` immediately after every
   `IST_Press` regardless of physical hold state — the user's real
   release arrives later as a *second* release event. So even bypassing
   PreProcess by tracking presses in script can't distinguish "held" from
   "tapped" reliably (see CLAUDE.md "Joy button event quirk").

One-shot actions are fine — Joy7 / Joy8 / Joy1–3 above all fire on press,
release is irrelevant. Continuous actions stay on the keyboard (Q/E for
lean, X for crouch by default).

#### Stick / look axes — strip `Speed=`

Stock `User.ini` ships with `Speed=` multipliers on the stick / look axis
bindings (`JoyX=Axis aStrafe speed=2`, etc.) to compensate for an
upstream native-input bug that delivered axis values in the wrong range.
The XInput shim now sends raw values in the engine's expected
`-1000..1000` range, so those multipliers over-amplify and need to come
off. Apply this to **both** `[Engine.Input]` and `[Extension.InputExt]`:

```ini
JoyX=Axis aStrafe              ; was: Axis aStrafe speed=2
JoyY=Axis aBaseY INVERT=-1     ; was: Axis aBaseY speed=2 INVERT=-1
JoyU=Axis aTurn                ; was: Axis aTurn speed=5.9
JoyV=Axis aLookUp              ; was: Axis aLookUp speed=-3 (drop = uninverted Y; re-add INVERT=-1 to invert)
JoyZ=                          ; LT — left blank; ControllerConsole consumes the axis directly
JoyR=                          ; RT — left blank; ControllerConsole consumes the axis directly
```

The negative-`speed` on stock `JoyV` was the install's way of inverting
look-Y. Stripping `Speed=` removes that inversion; add `INVERT=-1` back
if you want inverted look.

Axis bindings (left stick → `aBaseX`/`aBaseY`, right stick → `aMouseX`/`aMouseY`,
etc.) are inherited from stock `User.ini`. Tuning is a later phase.

## Known incompatibilities

- DXController overrides `[Engine.Engine]` `Console=` and `Root=`. Any other
  mod that overrides one of those will conflict — last one wins.
- Multiplayer rejects non-stock root windows server-side (per `DeusExMPGame.uc`).
  Phase 1 is single-player-only; do not load the mod for an MP session.
- The XInput shim that delivers `IK_Joy*` and `IK_JoyPov*` events is external
  to this repo (typically a separate `Extension.dll` build). If the shim
  isn't installed or its slot mapping diverges from the table in `CLAUDE.md`,
  bindings will silently misfire.
