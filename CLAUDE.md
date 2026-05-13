# DXController — Deus Ex controller mod

## Layout

This repo holds **only the mod source**. All new classes belong to a single
package, `DXController`, under `DXController/Classes/*.uc`. The compiler emits
`DXController.u` from this package.

- Mod source: this repo
- Original game scripts (read-only reference): `../deusex-scripts/` (sibling
  repo — exported `.uc` files for every stock package)
- Build dir (game install): `./gamedir/` (gitignored symlink pointing at the
  local Deus Ex install; create with
  `ln -s "/path/to/Deus Ex" gamedir`)

The repo and the build dir are **not** linked by rsync alone — edits do not
propagate until you run `./sync-and-build.sh`. The `gamedir/` symlink only
gives the script a stable path to point at; it doesn't sync anything by
itself.

### Working with the original scripts

`../deusex-scripts/` is an export of the stock game's `.uc` files. Treat it as
read-only — **do not edit anything there**. To change base-game behavior, add
a new class to `DXController/Classes/` that extends or shadows the original,
and route the engine to it (ini swap, subclass + repoint, etc. — see
"Overriding base-game classes" below).

When you need to read a stock class, look it up under
`../deusex-scripts/<Pkg>/Classes/<File>.uc`.

## Building

From WSL:

```bash
./sync-and-build.sh   # rsyncs DXController/, deletes DXController.u, runs UCC.exe make
```

The script does three things in order: rsync `DXController/` to
`$BUILD_DIR/DXController/`, delete `$BUILD_DIR/System/DXController.u`, run
`UCC.exe make` from `$BUILD_DIR/System`. Pass `-n` for a dry run (rsync
preview only, no build). Override the build dir with `BUILD_DIR=/path`.

`UCC.exe` lives in `…/System/`. The compiler walks every package in
`EditPackages` and emits `<Pkg>.u` next to it. If a `.u` already exists it is
**not** rebuilt, which is why the script deletes `DXController.u` on every run.

`DeusEx.ini` needs `EditPackages=DXController` appended to the `EditPackages`
block for the compiler to see this package, plus whatever ini rebindings the
mod needs (e.g. `[Engine.Engine] Console=DXController.<YourConsole>`).

## Documenting findings

Every non-obvious quirk, ini change, build-dir mutation, or compiler
constraint encountered during development gets written down
**immediately** in the appropriate file:

- **UnrealScript / build / engine-quirk findings** → the "UnrealScript
  quirks" section of this file. Each entry stands alone with at least
  one concrete file reference or example so future-you can re-derive it
  without re-debugging. Reference original-script paths as
  `../deusex-scripts/<Pkg>/Classes/<File>.uc`.
- **Anything an end user has to do to install or run the mod** →
  `README.md`. Goal: `README.md` doubles as the install document and
  needs no forensic reconstruction of what we changed in the build dir
  during development. If a game-file change is required for the mod to
  work (.ini edit, .u placement, file deletion, etc.), it lives there.

If a finding belongs in both, document concisely in both — the quirk
form in this file, the user-facing form in `README.md`.

## UnrealScript quirks (this is UE1-era UScript — newer references will mislead)

- **Enums are bytes, but `int(enumValue)` doesn't compile.** The conventional
  idiom for getting the textual name of an enum value is in
  `../deusex-scripts/DeusEx/Classes/MenuScreenCustomizeKeys.uc`:
  ```uc
  Mid(string(GetEnum(enum'EInputKey', Key)), 3)   // "IK_JoyPovUp" -> "JoyPovUp"
  ```
- **`case` clauses must each be on their own line.** Stacking
  `case A: case B:` on one line fails with "Bad or missing expression in 'Case'".
  Empty fall-through (one case per line, no body) is fine — see
  `../deusex-scripts/DeusEx/Classes/DeusExPlayer.uc` around the
  `FloorMaterial` switch.
- **`case` labels must match the switch expression's type.** A
  `const NAME = 0xF0;` is `int`-typed; using it as a case label against
  an `EInputKey` (byte) switch fails with "Type mismatch in 'Case'".
  Workarounds: switch on an existing enum value that already occupies
  that byte slot (e.g. `case IK_UnknownF0:` for 0xF0 in Console's stale
  enum), or rewrite as `if`/`else if`. Casting `int(Key)` is not an
  option; `int(enumValue)` does not compile (see bullet above).
- **`Engine/Classes/Console.uc` carries its own local copy of `EInputKey`**
  that's out of date relative to `Engine/Classes/Actor.uc` (e.g. 0xF0–0xF3
  are `IK_UnknownF0..F3` instead of `IK_JoyPov{Up,Down,Left,Right}`).
  `Console extends Object`, so Actor's enum is not in scope here at
  all — the stale copy is what the compiler resolves in `Console` and
  its subclasses. Since we don't rebuild `Engine.u` (see "Overriding
  base-game classes" below), reach the missing slots by their
  `IK_UnknownXX` names instead (e.g. `case IK_UnknownF0:` for D-pad up).
- See `scripting-reference.txt` at the repo root for a fuller language
  rundown — much of the modern UScript material online does not apply here.
- **Unary `+` on a constant on the RHS of an assignment fails to parse.**
  `x = +SomeConst;` errors with `Bad or missing expression in '='`. The
  matching unary `-` (`x = -SomeConst;`) is fine — the parser only chokes
  on the redundant `+`. Just drop it: `x = SomeConst;`.
- **`DefaultPlayerClass` on `DeusExGameInfo` is silently bypassed unless
  `ApproveClass` is overridden.** `../deusex-scripts/DeusEx/Classes/DeusExGameInfo.uc:25-28`
  forces `SpawnClass=class'JCDentonMale'` whenever `ApproveClass(SpawnClass)`
  returns false, and stock `ApproveClass` (line 76-79) returns `false`
  unconditionally. So a subclass that only sets `DefaultPlayerClass` in
  `defaultproperties` will appear to be routed but the engine will spawn
  JCDentonMale instead. Override `ApproveClass` on the subclass to
  approve your player class:
  ```uc
  function bool ApproveClass(class<PlayerPawn> SpawnClass)
  {
      return ClassIsChildOf(SpawnClass, Class'YourPkg.YourPlayer');
  }
  ```
  See `DXController/Classes/ControllerGameInfo.uc` for a working example.
  A corollary: the custom player class typically wants to extend
  `JCDentonMale` (not `DeusExPlayer` directly) so it inherits the
  protagonist's mesh, multi-skins, and `TravelPostAccept` skin-switch
  logic from `../deusex-scripts/DeusEx/Classes/JCDentonMale.uc`.
- **All `var` declarations must appear before any `function` / `event` /
  `state` body in the class.** UE1 UnrealScript is strict about declaration
  order: a `var` placed after the first function compiles to
  `Error, 'Var' is not allowed here`. Move vars to the top of the class body
  (just below the `class ... extends ...;` line); the order of *functions*
  themselves is unconstrained.
- **`Joy*`/`JoyPov*` bindings live in `[Extension.InputExt]` in `User.ini`,
  not `[Engine.Input]`.** Per the "Input flow" section above, the active
  `UInput` is `Extension.InputExt` (set via `[Engine.Engine] Input=Extension.InputExt`
  in `DeusEx.ini`), and `UInput::Exec` reads `Bindings[Key]` keyed off its
  own class identity. Bindings written under `[Engine.Input]` are ignored
  by the active dispatcher. A stock `User.ini` ships with both sections
  populated (often with divergent values from accumulated edits); set the
  values you care about in `[Extension.InputExt]` (and optionally mirror
  in `[Engine.Input]` for belt-and-suspenders).

## Overriding base-game classes without rebuilding their package

`ucc batchexport` only recovers scripts, textures, and sounds. Packages
containing fonts or meshes (`Engine`, most DeusEx-side packages) can't be
reproduced from a stock install, so we can't ship edited versions of
them. **This is why the originals in `../deusex-scripts/` are read-only** —
even if we edited them, we couldn't rebuild their `.u`. Instead, override
the class via subclass + ini swap from `DXController`:

- **Most engine plug-points are ini-bound.** `DeusEx.ini` line 22 has
  `[Engine.Engine] Console=Engine.Console`; repoint it at
  `DXController.<YourConsole>` and the engine spawns your class instead.
  Same hook for `GameEngine=`, `DefaultGame=`, `ViewportManager=`,
  `RenderDevice=`, `AudioDevice=`, `NetworkDevice=`. Classes that are
  referenced as defaults on `DeusExGameInfo` (`HUDType=`,
  `DefaultPlayerClass=`, etc.) are reachable by subclassing
  `DeusExGameInfo` and pointing `DefaultGame=` at the subclass.
- **Recipe**: add `DXController/Classes/DXControllerConsole.uc` containing
  `class DXControllerConsole extends Console;`, ensure
  `EditPackages=DXController` is at the end of the `EditPackages` block in
  `DeusEx.ini`, swap the ini binding to
  `Console=DXController.DXControllerConsole`. `Engine.u` stays untouched.

### State-scoped dispatch

UScript `state` blocks can redeclare a function. The actor is in exactly
one state at a time; calls dispatch to the current state's version if it
exists, else to the global one. A subclass that only overrides
`global KeyEvent` therefore intercepts:

- global / gameplay state — yes.
- a parent state that falls through to `global.KeyEvent` — yes (e.g.
  `Console.state Typing` at line 747).
- a parent state that handles the event itself — **no** (e.g. `Menuing`,
  `EndMenuing`, `MenuTyping`, `KeyMenuing` on Console).

To hook every path, redeclare the state on the subclass and override the
function there too. `Super.X` inside a state block resolves to the
parent's same-state body, not parent's global — exactly what a pre/post
hook wants. Use `state Foo extends Foo` to inherit the parent state body
and replace only specific methods (preserves labels, latent code, and
sibling state-scoped functions).

### Limits

- **Hardcoded `class'X'` / `Spawn(class'X')` literals** inside an
  unrebuildable package can't be diverted. Mitigation: override the
  *caller* if it lives in a package you can rebuild.
- **`final function`s** can't be overridden in a subclass at all — grep
  for `final` on anything you plan to hook.
- **`var config` section identity** changes with class identity:
  `Engine.Console` reads `[Engine.Console]`,
  `DXController.DXControllerConsole` reads
  `[DXController.DXControllerConsole]`. Migrate or duplicate keys if
  existing user settings need to apply to the subclass.

## Input flow (for the XInput work)

The engine's first script-side entry point for any key/axis event is
`Console.KeyEvent(EInputKey Key, EInputAction Action, float Delta)` in
`../deusex-scripts/Engine/Classes/Console.uc`. Axes arrive there with
`Action == IST_Axis` and the raw axis value in `Delta`. Buttons/POV
arrive with `IST_Press` / `IST_Release`. State-scoped overrides exist
(`Typing`, `Menuing`, etc.); the `Typing` override forwards to
`global.KeyEvent`, the menu states do not. To hook the stream without
rebuilding `Engine.u`, subclass `Console` per the override section above.

### Native input handler: `Extension.InputExt`

The active `UInput` is `Extension.InputExt` (native, in `Extension.dll`),
wired via `[Engine.Engine] Input=Extension.InputExt` in `DeusEx.ini`.
It is *not* stock UE1 `UInput`; its `Process` override changes what
reaches the binding system:

1. **UI gets first refusal.** If the current pawn is an
   `Extension.PlayerPawnExt` with a non-null `rootWindow`, every event
   (key *and* axis) is offered to the C++ window system first via
   `rootWindow.Process(Key, Action, Delta)`. If the UI consumes it,
   InputExt synthesises an `IST_Release` for every currently-held bound
   key (so movement/aim doesn't stick when a menu, conversation,
   datacube, or computer terminal grabs focus) and returns without
   dispatching the binding. This is why look/move freeze the instant a
   UI surface appears — the axis stream is silently swallowed upstream
   of `Bindings[]`.
2. **Press/release de-duplication.** For `IST_Press`/`IST_Release`
   InputExt tracks a per-key pressed bit and drops duplicate presses or
   stray releases before dispatch. `IST_Axis` skips this entirely.
3. **Binding dispatch.** Whatever survives goes through the normal
   `UInput::Exec` path against `Bindings[Key]` from
   `[Extension.InputExt]` in `User.ini` — same shape as stock.

It also:

- **Stubs out `PreProcess` (returns true, no-op).** Stock UE1
  `UInput::PreProcess` handles button-alias state-change synthesis;
  that machinery is dead here. Pure axis bindings (`KeyAxis aBaseX
  SpeedBase=…`) are unaffected, since axes go through `Process`/`Exec`,
  not `PreProcess`.
- **Adds a `Key(iKey)` member** for character/typing input, invoked from
  `Extension.GameEngineExt.Key` when `UEngine::Key` doesn't consume the
  event. Routes the keystroke into `rootWindow.Key` so UI text controls
  get a typing channel that is separate from the binding system.

**Implication for the XInput work:** axis events from the C++ shim flow
through the standard binding path unchanged *unless* a UI surface is
open, in which case `rootWindow.Process` swallows them and gameplay
never sees the deltas. Button press/release events (`IK_Joy1`–
`IK_Joy16`, D-pad slots) are already de-duplicated by InputExt, so the
shim doesn't need its own edge filter.

### XInput → UE event mapping

The C++-side XInput shim feeds these `EInputKey` slots into
`Console.KeyEvent`:

| XInput source   | UE `EInputKey`        | Byte        | Action          |
|-----------------|-----------------------|-------------|-----------------|
| Left stick X    | `IK_JoyX`             | 0xE0        | `IST_Axis`      |
| Left stick Y    | `IK_JoyY`             | 0xE1        | `IST_Axis`      |
| Left trigger    | `IK_JoyZ`             | 0xE2        | `IST_Axis`      |
| Right trigger   | `IK_JoyR`             | 0xE3        | `IST_Axis`      |
| Right stick X   | `IK_JoyU`             | 0xE8        | `IST_Axis`      |
| Right stick Y   | `IK_JoyV`             | 0xE9        | `IST_Axis`      |
| D-pad Up        | `IK_JoyPovUp`†        | 0xF0        | Press / Release |
| D-pad Down      | `IK_JoyPovDown`†      | 0xF1        | Press / Release |
| D-pad Left      | `IK_JoyPovLeft`†      | 0xF2        | Press / Release |
| D-pad Right     | `IK_JoyPovRight`†     | 0xF3        | Press / Release |
| Face / shoulder / stick-click buttons | `IK_Joy1`–`IK_Joy16` | 0xC8–0xD7 | Press / Release |

† Modern names from `Actor.uc`. In `Console`-scope these slots are
`IK_UnknownF0..F3` (Console.uc's stale enum) — see quirk above.

The 10 XInput controller buttons (A / B / X / Y, LB / RB, Back / Start,
LStickBtn / RStickBtn) are assigned into `IK_Joy1`..`IK_Joy16` by the
C++ shim; the specific button-to-slot mapping is owned by that side.
Axes are delivered as a continuous stream.

#### Joy button event quirk: auto-release per press

For Joy* buttons the shim sends `IST_Press` followed by an `IST_Release`
within the same script tick on every physical press, regardless of how
long the button is actually held down. The user's real release arrives
*later*, as a **second** `IST_Release` event when they physically let go
(observed: ~1.8s of silence between the auto-release and the real one
during a held button test).

Implication for any state that needs "is the button currently held":
- Exec functions called on press are fine — the action fires once and the
  release is irrelevant.
- Continuous actions (lean while held, crouch while held, etc.) can't use
  a naive "true on press, false on release" because the auto-release ends
  the action immediately. Count releases per press cycle and treat the
  **second** release as the user's real one (`ControllerConsole.uc` does
  this for Joy5/Joy6/Joy9). Pair with a long safety timeout (≥10s) so a
  dropped second release doesn't strand the action.
