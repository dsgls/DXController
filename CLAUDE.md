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
"Source overlay model" below).

When you need to read a stock class, look it up under
`../deusex-scripts/<Pkg>/Classes/<File>.uc`.

## Building

From WSL:

```bash
./sync-and-build.sh   # rsyncs DXController/ and DeusEx/, two-pass UCC build
```

The script rsyncs `DXController/` and `DeusEx/` onto `$BUILD_DIR/`, then
runs `UCC.exe make` twice: pass 1 deletes and rebuilds `DeusEx.u`
(tolerating a known UCC GPF — see below); pass 2 deletes and rebuilds
`DXController.u` in a fresh UCC process. Pass `-n` for a dry run (rsync
preview only, no build). Override the build dir with `BUILD_DIR=/path`.

`UCC.exe` lives in `…/System/`. The compiler walks every package in
`EditPackages` and emits `<Pkg>.u` next to it. If a `.u` already exists it is
**not** rebuilt, which is why the script deletes both `.u` files on every run.

`DeusEx.ini` needs `EditPackages=DXController` appended to the `EditPackages`
block for the compiler to see this package, plus whatever ini rebindings the
mod needs (e.g. `[Engine.Engine] Console=DXController.<YourConsole>`).

UCC prompts interactively to overwrite `DeusEx/Inc/DeusExClasses.h` when
rebuilding `DeusEx.u`; answering 'y' fails the build, answering 'n'
lets it proceed but UCC then GPFs while loading the freshly-rebuilt
package. `DeusEx.u` is on disk before the crash. `sync-and-build.sh`
handles this by piping `n` to UCC's stdin and tolerating the non-zero
exit code, then verifying the `.u` was produced. `DXController.u` is
built in a second `UCC.exe make` invocation against the now-stable
`DeusEx.u`; the fresh UCC process side-steps the load-time GPF.

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

### Suspected bugs in user-owned native code: flag, don't compensate

The XInput shim and `Extension.InputDrv` are code the user owns and can
fix at the source. If a behaviour looks like a bug there (events that
shouldn't fire, events that should fire but don't, values in the wrong
range, missing edges, etc.), **do not build a UScript workaround.**
Surface the observation explicitly:

- What the script-side sees, with concrete event sequences / values
  from `DeusEx.log` if available.
- Which native component is the likely owner (shim DLL, `Extension.dll`,
  `InputDrv`, etc.) so the user knows where to look.
- What the *expected* behaviour would be.

Then stop and let the user fix it natively. A UScript band-aid hides
the real defect, accumulates compensating complexity in the mod, and
can mask further changes the user makes on the native side.

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
  its subclasses. Since we don't rebuild `Engine.u` (see "Packages
  that can't be rebuilt" below), reach the missing slots by their
  `IK_UnknownXX` names instead (e.g. `case IK_UnknownF0:` for D-pad up).
- See `scripting-reference.txt` at the repo root for a fuller language
  rundown — much of the modern UScript material online does not apply here.
- **Unary `+` on a constant on the RHS of an assignment fails to parse.**
  `x = +SomeConst;` errors with `Bad or missing expression in '='`. The
  matching unary `-` (`x = -SomeConst;`) is fine — the parser only chokes
  on the redundant `+`. Just drop it: `x = SomeConst;`.
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

## Source overlay model

`DeusEx.u` is rebuildable (the user has batch-exported its source into
`$BUILD_DIR/DeusEx/Classes/`). To change a class in `DeusEx`, place an
edited copy under `DeusEx/Classes/<File>.uc` in this repo; the build
script rsyncs it on top of the stock tree and rebuilds the package.
Stock files we don't touch stay stock. Discipline: when adding a stock
file to `DeusEx/Classes/` for the first time, commit it verbatim first
(message: "Vendor stock DeusEx/Classes/<File>.uc (unmodified)"), then
make edits in a follow-up commit. `git diff <vendor>..<edit>` then shows
exactly our delta against upstream.

Within each modified file, additions live in a banner-delimited block:

```
// === DXController additions: BEGIN ===
...
// === DXController additions: END ===
```

No edits to stock function bodies — pure additions. See
`DeusEx/Classes/DeusExPlayer.uc` for the canonical example.

### `DeusEx` can't reference `DXController` types

`sync-and-build.sh` builds `DeusEx.u` in pass 1, then `DXController.u`
in pass 2. So any UScript source under `DeusEx/Classes/` is compiled
before `DXController` exists — code there cannot name a `DXController`
type (e.g. `ControllerRootWindow`, `RadialMenuWindow`) without the
compiler emitting `Unrecognized type 'X'`.

Pattern when a `DeusEx`-side addition needs to interact with a
`DXController` UI/orchestration object: keep the `DeusEx`-side code
**state-only** (vars and pure setters/getters), and do all cross-class
orchestration from `DXController` code (typically `ControllerConsole`
or `ControllerRootWindow`), reaching into the pawn via the pawn
methods/vars. The crouch pair is the simplest precedent —
`OnGamepadCrouchPress/Release` just write `bDuck`; the
`ControllerConsole` side knows how to call them. The weapon-wheel LB
handler (commit `22a7876`) follows the same split intentionally.

### Packages that can't be rebuilt

`ucc batchexport` recovers scripts, textures, and sounds — not fonts or
meshes. `Engine.u` contains both, so it cannot be reproduced from a
stock install and we cannot ship an edited version. For classes in
unrebuildable packages, use the subclass-and-ini-swap fallback:

- **Most engine plug-points are ini-bound.** `DeusEx.ini` line 22 has
  `[Engine.Engine] Console=Engine.Console`; repoint it at
  `DXController.<YourConsole>` and the engine spawns your class instead.
  Same hook for `GameEngine=`, `DefaultGame=`, `ViewportManager=`,
  `RenderDevice=`, `AudioDevice=`, `NetworkDevice=`.
- **Recipe**: add `DXController/Classes/DXControllerConsole.uc` containing
  `class DXControllerConsole extends Console;`, ensure
  `EditPackages=DXController` is at the end of the `EditPackages` block in
  `DeusEx.ini`, swap the ini binding to
  `Console=DXController.DXControllerConsole`. `Engine.u` stays untouched.
  See `DXController/Classes/ControllerConsole.uc` for a working example.

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
rebuilding `Engine.u`, subclass `Console` per the "Packages that can't
be rebuilt" section above.

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

| XInput source              | UE `EInputKey`        | Byte        | Action          |
|----------------------------|-----------------------|-------------|-----------------|
| Left stick X               | `IK_JoyX`             | 0xE0        | `IST_Axis`      |
| Left stick Y               | `IK_JoyY`             | 0xE1        | `IST_Axis`      |
| Left trigger               | `IK_JoyZ`             | 0xE2        | `IST_Axis`      |
| Right trigger              | `IK_JoyR`             | 0xE3        | `IST_Axis`      |
| Right stick X              | `IK_JoyU`             | 0xE8        | `IST_Axis`      |
| Right stick Y              | `IK_JoyV`             | 0xE9        | `IST_Axis`      |
| A button                   | `IK_Joy1`             | 0xC8        | Press / Release |
| B button                   | `IK_Joy2`             | 0xC9        | Press / Release |
| X button                   | `IK_Joy3`             | 0xCA        | Press / Release |
| Y button                   | `IK_Joy4`             | 0xCB        | Press / Release |
| Left shoulder (LB)         | `IK_Joy5`             | 0xCC        | Press / Release |
| Right shoulder (RB)        | `IK_Joy6`             | 0xCD        | Press / Release |
| Back button                | `IK_Joy7`             | 0xCE        | Press / Release |
| Start button               | `IK_Joy8`             | 0xCF        | Press / Release |
| Left stick click           | `IK_Joy9`             | 0xD0        | Press / Release |
| Right stick click          | `IK_Joy10`            | 0xD1        | Press / Release |
| D-pad Up                   | `IK_JoyPovUp`†        | 0xF0        | Press / Release |
| D-pad Down                 | `IK_JoyPovDown`†      | 0xF1        | Press / Release |
| D-pad Left                 | `IK_JoyPovLeft`†      | 0xF2        | Press / Release |
| D-pad Right                | `IK_JoyPovRight`†     | 0xF3        | Press / Release |

† Modern names from `Actor.uc`. In `Console`-scope these slots are
`IK_UnknownF0..F3` (Console.uc's stale enum) — see quirk above.

Axes are delivered as a continuous stream. The button-to-slot mapping
is owned by the C++ shim and the table above mirrors its current
assignments; if the shim's mapping changes, update the table to match.

#### Axis value range: `-1000..1000`

`IST_Axis` events arrive at `Console.KeyEvent` with `Delta` in
`-1000..1000`, *not* `-1..1`. The shim sends raw `-1000..1000`; the
engine passes it through to scripts unchanged. Verified by logging
(2026-05-13):

```
ScriptLog: DXC-AXIS Key=JoyX Delta=-1000.000000
ScriptLog: DXC-AXIS Key=JoyY Delta=141.846161
```

Don't normalize at the shim. UE's binding system (`Axis aBaseY Speed=…`
etc.) assumes the `-1000..1000` scale that DirectInput sends — that's
why default `Speed=` values without a multiplier feel responsive.
Normalizing to `-1..1` would make movement unusably slow and force a
compensating `Speed=` scalar, which puts the scale right back where it
started by the time the value reaches `aForward`/`aStrafe`.

Implication for script-side thresholds: scale them against the
`-1000..1000` range. `ControllerConsole.uc`'s existing
`TriggerThreshold = 0.3` works because 0.3 is effectively zero on
the `-1000..1000` scale — anything past the shim's deadzone clears
it trivially. The threshold is doing "any value at all" duty; the
shim's deadzone is what really decides held-state.
