# Developing DXController

Script-side mod for the DXController project, plus the launcher source it
ships alongside. Builds `DXController.u` (the mod), an overlay on stock
`DeusEx.u` (a few hooks into base-game classes), and `DeusEx.exe` (the
launcher with the XInput shim).

## Repo layout

```
DXController/Classes/*.uc   the mod — one package, compiles to DXController.u
DeusEx/Classes/*.uc         overlay edits to stock DeusEx classes (rebuilds DeusEx.u)
launcher/                   launcher source (fork of Deus Exe — builds DeusEx.exe)
assets/                     source art + generators for the DXController textures
sync-and-build.sh           rsync + two-pass UCC build
.github/workflows/build.yml CI build and release packaging
scripting-reference.txt     UE1-era UnrealScript language reference
```

Base-game behaviour is changed by placing an edited copy of a stock class
under `DeusEx/Classes/` — the build overlays it on the stock tree.
Unrebuildable packages (`Engine.u` and friends) are diverted by
subclassing and repointing an `.ini` binding instead. See
[Source overlay model](#source-overlay-model).

CI clones a private `deusex-buildtools` repo holding a stock game tree
(engine `.u` files, `UCC.exe`, base `.ini`s) so the build can run
without a game install.

## Building

Prerequisites: a Deus Ex GOTY install with `UCC.exe` in `System/`, plus
WSL (or bash with rsync and `cmd.exe` access).

One-time setup — symlink `gamedir/` at your install (gitignored) and
export the stock `DeusEx` source once so the overlay has something to
sit on top of:

```bash
ln -s "/path/to/Deus Ex" gamedir
```

```cmd
ucc.exe batchexport DeusEx.u Class uc ..\DeusEx\Classes
```

Then build:

```bash
nix run .#sync-and-build         # generate textures, sync overlays, two-pass UCC build
nix run .#sync-and-build -- -n   # dry run
BUILD_DIR=/path nix run .#sync-and-build
```

The flake app puts python3 + Pillow + numpy and `dos2unix` on PATH; the
header comment in `sync-and-build.sh` explains the two-pass UCC dance
and the GPF it tolerates. Output lands in `gamedir/System/`: `DeusEx.u`
and `DXController.u`.

### Build details worth knowing

- **The repo is LF; UCC wants CRLF.** `.editorconfig` and
  `.gitattributes` pin every text file to LF. The build script
  converts each overlay `.uc` with `unix2dos -n` on the way into the
  build dir, so only our overlay files are converted — stock files
  stay verbatim. Never let git check out the tree under a config that
  would re-CRLF it.
- **`DeusEx.ini` needs `EditPackages=DXController`** at the end of the
  `EditPackages` block. The build script adds it automatically.
- **Two-pass, with a GPF.** Pass 1 rebuilds `DeusEx.u`; UCC GPFs while
  loading the freshly-rebuilt package, but the `.u` is on disk before
  the crash. The script pipes `n` to stdin (to skip a header overwrite
  prompt), tolerates the non-zero exit, and verifies the `.u` is
  present. Pass 2 builds `DXController.u` in a fresh UCC process to
  side-step the load-time GPF.

## Releases

CI builds on every push to `master`; on a `v*` tag it assembles a
release `.zip` containing `DeusEx.u`, `DXController.u`, `README.md`,
and `DeusEx.exe` (built from `launcher/` via `launcher/build.sh`).

To cut a release, push a `v*` tag.

## Source overlay model

`DeusEx.u` is rebuildable, so additions live in `DeusEx/Classes/<File>.uc`
banner-delimited like:

```
// === DXController additions: BEGIN ===
...
// === DXController additions: END ===
```

See `DeusEx/Classes/DeusExPlayer.uc` for the canonical example.

**In-place gates are acceptable when surgical.** When a vanilla call
inside a stock function body needs to be suppressed based on
controller-side state, wrap the call in a one-line `if (!bSomeFlag)`
gate tagged with an inline `// DXController gate` comment. See
`DeusEx/Classes/ConWindowActive.uc` for the canonical example. Don't
restructure function bodies, change control flow beyond the gate, or
add new function-internal logic — at that point the change has outgrown
the overlay pattern.

### `DeusEx` can't reference `DXController` types

`DeusEx.u` builds in pass 1 before `DXController` exists. Code under
`DeusEx/Classes/` cannot name a `DXController` type (e.g.
`ControllerRootWindow`, `RadialMenuWindow`).

Pattern when a `DeusEx`-side addition needs to interact with a
`DXController` object: keep the `DeusEx`-side code **state-only** (vars
and pure setters/getters), and orchestrate from `DXController` code
(typically `ControllerConsole` or `ControllerRootWindow`). The crouch
pair is the simplest precedent — `OnGamepadCrouchPress/Release` just
write `bDuck`; the `ControllerConsole` side knows when to call them.

### Packages that can't be rebuilt

`ucc batchexport` recovers scripts, textures, and sounds — not fonts or
meshes. `Engine.u` contains both, so we can't ship an edited version.

Most engine plug-points are ini-bound: `DeusEx.ini`'s `[Engine.Engine]
Console=`, `GameEngine=`, `DefaultGame=`, `ViewportManager=`,
`RenderDevice=`, `AudioDevice=`, `NetworkDevice=`. Subclass the stock
class in `DXController/Classes/` and repoint the binding. See
`DXController/Classes/ControllerConsole.uc` for a working example.

Limits:
- Hardcoded `class'X'` / `Spawn(class'X')` literals inside an
  unrebuildable package can't be diverted. Mitigation: override the
  *caller* if it lives in a package you can rebuild.
- `final function`s can't be overridden in a subclass at all.
- `var config` section identity changes with class identity:
  `Engine.Console` reads `[Engine.Console]`; the subclass reads
  `[DXController.<Name>]`. Migrate keys if existing user settings need
  to apply.

### State-scoped dispatch

UScript `state` blocks can redeclare a function. The actor is in
exactly one state at a time; calls dispatch to the current state's
version if it exists, else to the global one. A subclass that only
overrides `global KeyEvent` therefore intercepts:

- global / gameplay state — yes.
- a parent state that falls through to `global.KeyEvent` — yes (e.g.
  `Console.state Typing`).
- a parent state that handles the event itself — **no** (e.g.
  `Menuing`, `EndMenuing`, `MenuTyping`, `KeyMenuing` on `Console`).

To hook every path, redeclare the state on the subclass and override
the function there too. `Super.X` inside a state block resolves to the
parent's same-state body, not parent's global.

Canonical example: `ControllerConsole.state Menuing`. Stock
`Console.state Menuing.KeyEvent` short-circuits on `Action != IST_Press`
and drops every axis event. The override forwards stick axes
(X/Y/U/V) to `global.KeyEvent` so the class-scoped handler's axis
branch runs in menu mode; triggers stay on `Super` so they don't fire
weapons mid-menu.

## Input flow

```
[OS / XInput pad]
       │
       ▼
[XInput shim in launcher/src/XInput.cpp]
   per-tick poll, deadzone + response curve, edge dedup,
   focus-loss synthetic releases
       │  IK_Joy*/IK_JoyPov*/IK_JoyX/Y/U/V/Z/R + IST_Press/Release/Axis
       ▼
UEngine::InputEvent (Engine.dll)
       ├──► Console::Key  ─►  Console.KeyEvent (script — first chance)
       │                          ↑ this is where DXController hooks
       └──► XInputExt::Process (Extension.dll, == Extension.InputExt)
              ├──► XRootWindow::Process (UI capture? if yes, swallow + sweep releases)
              └──► binding dispatch via Bindings[Key] in [Extension.InputExt]
```

Authoritative reference for stage-by-stage native behaviour:
`../deusex-native-re/docs/input-chain.md`.

The engine's first script-side entry point for any key/axis event is
`Console.KeyEvent(EInputKey Key, EInputAction Action, float Delta)`.
Axes arrive with `IST_Axis` and the raw axis value in `Delta`;
buttons/POV arrive with `IST_Press` / `IST_Release`. State-scoped
overrides exist — see [State-scoped dispatch](#state-scoped-dispatch).

### Native input pipeline

`UseJoystick=False` in `[Engine.Engine]`. This disables `WinDrv.dll`'s
legacy `joyGetPosEx` poll path entirely — the XInput shim is the *only*
source of joystick events. Don't re-enable `UseJoystick`: the legacy
path has known bugs (see `../deusex-native-re/docs/windrv-input.md`)
and would race the shim for the same `IK_Joy*` slots.

The launcher also patches `WinDrv.dll` at startup (see
`launcher/src/WinDrvPatch.cpp` and `windrv-input.md`) to fix two
joystick bugs in the stock binary. The patches are defence-in-depth
given `UseJoystick=False`. `WinDrvPatch: fingerprint MISMATCH` in the
launcher log means the patcher refused to write into an unrecognised
`WinDrv.dll` — confirm against the GOG / Steam build the patch was
authored for.

### Script-visible input handler: `Extension.InputExt`

The active `UInput` is `Extension.InputExt` (native class `XInputExt`,
wired via `[Engine.Engine] Input=Extension.InputExt`). It is *not*
stock UE1 `UInput`; its `Process` override changes what reaches the
binding system:

1. **UI gets first refusal.** If the current pawn is an
   `Extension.PlayerPawnExt` with a non-null `rootWindow`, every event
   (key *and* axis) is offered to the C++ window system first. If the
   UI consumes it, InputExt synthesises an `IST_Release` for every
   currently-held bound key (so movement/aim doesn't stick when a menu
   takes focus) and returns without dispatching the binding. This is
   why look/move freeze the instant a UI surface appears.
2. **Press/release de-duplication.** `IST_Press`/`IST_Release` get
   per-key pressed-bit tracking; duplicates and stray releases are
   dropped. `IST_Axis` skips this entirely.
3. **Binding dispatch.** Whatever survives goes through the normal
   `UInput::Exec` path against `Bindings[Key]` from `[Extension.InputExt]`
   in `User.ini`.

Also: `PreProcess` is stubbed to return true (button-alias state-change
synthesis is dead here; pure axis bindings are unaffected). `Key(iKey)`
routes typing into `rootWindow.Key` for UI text controls.

**Implication for the mod:** `Console.KeyEvent` runs *upstream* of
`InputExt::Process`, so axis events reach the script-side hook on
every frame regardless of UI state. What can make axes appear dead in
script is the `state Menuing` short-circuit covered above.

### XInput → UE event mapping

The C++ shim (`launcher/src/XInput.cpp`, see `kButtonMap`) feeds these
`EInputKey` slots into `Console.KeyEvent`:

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
`IK_UnknownF0..F3` (Console.uc's stale enum) — see UnrealScript quirks.

Active-controller selection is also shim-side: whichever XInput slot
most recently produced input becomes the active slot, and only its
events are forwarded.

### Axis value range: `-1000..1000`, not `-1..1`

`IST_Axis` events arrive at `Console.KeyEvent` with `Delta` in
`-1000..1000`. The shim sends raw `-1000..1000`; the engine passes it
through unchanged. UE's binding system (`Axis aBaseY Speed=…`) assumes
this scale — that's why default `Speed=` values feel responsive without
a multiplier. Don't normalise at the shim.

Implication for script-side thresholds: scale against `-1000..1000`.
`ControllerConsole.uc`'s `TriggerThreshold = 0.3` effectively does "any
value at all" duty; the shim's deadzone is what actually decides
held-state.

### Deadzone, response curve, edge events: all done in the shim

The shim already applies a configurable radial deadzone, a power-curve
response shape (`XInputLeftStickExponent` / `XInputRightStickExponent`,
default `2.0`), and edge-emits `IST_Axis(0.0)` exactly once when an axis
crosses from non-zero to zero. It also synthesises releases (button
`IST_Release` / axis `IST_Axis(0.0)`) on focus loss and controller
disconnect.

- **Don't add a script-side deadzone or response curve** — re-tune the
  shim's ini settings instead. Two stacked deadzones interact
  non-linearly.
- **Don't add a "stuck input on alt-tab" workaround in script.** If you
  see one, flag it as a shim/focus defect per [Flag, don't compensate](#flag-dont-compensate).
- **Trust the zero-edge `IST_Axis`.** When the stick re-enters the
  deadzone the shim emits one final `IST_Axis(0.0)` and stops sending —
  script can rely on "received `0.0` means the player let go" and clear
  accumulators on that edge.

### Mid-game launcher state via `ConsoleCommand` exec hooks

The launcher exposes exec commands consumed from script:

- `XInputReload` — re-reads `[DXController.ControllerSettings]` and
  re-applies clamps. Called by `MenuChoice_*` after `SaveConfig()` so
  stick-feel changes take effect without restart.
- `XInputSampleCurve <Left|Right> <N>` — returns N comma-separated
  curve outputs sampled at `x = i/(N-1)`. The settings UI uses this to
  render the curve without re-implementing the shape script-side.
- `XInputGetRawMag` — returns `"L=<f> R=<f>"` (per-stick raw magnitude
  in `[0,1]`). Polled per Tick by the preview windows.

Canonical pattern when a native runtime component owns state that
script-side UI needs to read or react to: add exec commands on the
native side; parse the string return from script.

## Menu navigation

Per-screen gamepad navigation lives in `DXController/Classes/<Screen>NavController.uc`,
each extending `MenuNavController`. `ControllerRootWindow` keeps a
class→controller registry and attaches when a registered screen class is
added to the root via `DescendantAdded`, detaches when it leaves via
`DescendantRemoved`. To add a new screen: write the controller, then add
one `RegisterNav(Class'DeusEx.X', Class'XNavController')` line in
`ControllerRootWindow.RegisterNavControllers()`.

### Window-stack observation: use engine events, never polling

Attach/detach is driven by `ControllerRootWindow.DescendantAdded(Window)`
and `DescendantRemoved(Window)`. By the time `DescendantRemoved` fires
the descendant is still a valid `Window` pointer (vanilla
`HUDBarkDisplay.DescendantRemoved` calls `descendant.IsA(...)` on it),
so detach can safely log `descendant.Class` and clear refs *before* the
C++ object is freed.

Why this matters: `InvokeUIScreen`-style screen swaps destroy the old
screen and push the new one synchronously inside one event handler.
A "did the top window change?" check that runs *after* the swap
inspects a dangling pointer and crashes. Engine events fire *during*
the swap, against a live pointer.

Use this pattern for everything "react to a window appearing or
leaving the stack" — nav attach/detach, the radial wheel's UI-takeover
cancel (`RadialMenuWindow.OnTopWindowPushed`), and anything similar in
future. Don't use `RefreshDisplay`, `RefreshHUDDisplay`, or any polling
loop for window-stack observation.

### `InitFocus` and the deferred-init retry

`ControllerRootWindow.Tick` re-calls `activeNav.InitFocus()` every
frame until `activeNav.bFocusInitDone` is true. Some screens (e.g.
`PersonaScreenInventory`) populate child windows *after* the controller
attaches, so the first `InitFocus()` finds an empty screen.

Contract:
- `InitFocus()` may be called many times before the screen is fully
  built. Make it idempotent.
- Grid/menu controllers that set `focused` to a real `Window` get
  `bFocusInitDone` set for free (by `Attach` and the Tick retry).
- List/scroll controllers keep `focused == None` by design (rows aren't
  `Window` objects). They MUST set `bFocusInitDone = True` themselves
  once their content is ready. If they don't, the retry re-runs
  `InitFocus()` every frame and undoes navigation.

### `EInputKey` is not in scope from controllers

`MenuNavController extends Object`. `EInputKey` is on `Engine.Actor`
and isn't reachable from `Object` scope, so `HandleActivate` takes
`byte`, not `EInputKey`. Compare against literal byte values, each
with a comment:

- `200` = `IK_Joy1` (A)
- `201` = `IK_Joy2` (B)
- `202` = `IK_Joy3` (X)
- `203` = `IK_Joy4` (Y)
- `209` = `IK_Joy10` (R-stick click)

`ControllerRootWindow.VirtualKeyPressed` is in `Window` scope and *can*
see `EInputKey`, but UE1 rejects implicit `EInputKey`→`byte` coercion
in function args. Use a local: `local byte bkey; bkey = key;` before
`activeNav.HandleActivate(bkey)`.

### Button activation idiom

Use `btn.PressButton()` (no args) — same path the keyboard uses, fires
`ButtonActivated` upstream. `btn.ActivateButton(IK_LeftMouse)` also
works but mixes in right-click semantics. Always gate on
`btn.bIsSensitive` before pressing.

Note: `bIsSensitive` lives on `Window`, not on `ButtonWindow`. The
intuitive `ButtonWindow.bSensitive` does not exist — reference the
typed action-button field directly (e.g. `s.btnEquip.bIsSensitive`).

### Controller patterns

Three patterns, by screen kind:

- **List screens (`PersonaListWindow`).** For native list-backed
  screens (Images, Logs, Conversations, Load/Save, Themes), use the
  row API on `Extension.ListWindow`:
  `SetRow(IndexToRowId(0), True, True)` to select first,
  `MoveRow(MOVELIST_Up/Down, True, True)` to navigate, read
  `GetFocusRow()` before/after `MoveRow` to detect edges. The screen's
  `ListSelectionChanged` callback usually drives side-panel updates
  automatically. `GetFocusedRect` returns `false` (rows aren't `Window`
  objects). Canonical: `ImagesNavController.uc`.

- **Uniform single-cell grids (Augs, AugInstall).** Buttons all the
  same size, occupying one cell. Get each button's centre via
  `ConvertCoordinates(btn, 0.5*btn.width, 0.5*btn.height, root, cx, cy)`,
  filter candidates by direction with a `bSkip` boolean (UE1 has no
  `goto`/`continue`), rank by squared Euclidean distance. Canonical:
  `AugsNavController.uc`.

  **Do not** use centre-distance when buttons can span multiple cells —
  a multi-slot item collapsed to its geometric centre mis-picks
  neighbours (see git history of `InvNavController.uc`).

- **Tile-cursor grids (Inventory).** Track a logical cursor cell
  `(cursorX, cursorY)` kept inside the focused item's tile rectangle;
  the perpendicular coordinate is the **lane**, preserved across
  straight-line travel so leaving a multi-slot item exits under the
  cell it was entered on. A candidate is in-direction when its near
  edge is strictly past the focused item's far edge along the pressed
  axis (rectangle edges, not centres). Wrap within the lane when
  nothing is in-direction. Canonical: `InvNavController.uc`.

- **Text scrolling (`PersonaScrollAreaWindow`).** No pixel-granularity
  API — only `vScale.MoveThumb(MOVETHUMB_StepUp/Down)`. For R-stick
  smooth scroll: ~200 deadzone on the `-1000..1000` axis scale, fire
  one step per ~500 accumulated units, reset on stick re-entering
  deadzone. R-stick up sends positive `ry` → `StepUp`. Two access
  patterns: direct field (e.g. `PersonaScreenLogs.winScroll`) or
  parent-chain walk via `CreateScrollTileWindow` (e.g.
  `PersonaScreenGoals.winGoals.GetParent().GetParent()`). Canonical:
  `LogsNavController.uc` (direct), `GoalsNavController.uc` (chain).

### Verify field names against stock source before coding

UE1 enforces typed field access at compile time but does not validate
`IsA('Name')` strings — a wrong field name fails the build (good), a
wrong `IsA` only fails silently at runtime (bad). Before writing a new
controller, read the stock screen class and confirm the exact field
names, types, and any `Select*`/`ListSelectionChanged` callbacks that
drive auto-display. For action buttons, follow the inheritance chain
to `ButtonWindow` to confirm `PressButton()` is available without a
cast. If the screen is a subclass of another, register the subclass
separately if it needs different navigation — registry key match is
exact.

### Swapping menu background tiles at runtime

`MenuUIClientWindow` holds its own `clientTextures[6]`, positions each
tile at a fixed `(col*256, row*256)`, and redraws all of them every
frame in `DrawWindow`. A screen can therefore change its background
mid-display by calling `winClient.SetClientTexture(i, tex)` for each
slot — the next `DrawWindow` picks them up, with no re-init or
reposition. `MenuScreenController` uses this to switch the
controller-settings panel among per-visible-row-count background
variants (`SelectBackground`), so the painted recesses always match the
rows currently shown. The variant tile sets are generated by
`assets/gen-menu-bg.py` (see Asset tooling).

## UnrealScript quirks (this is UE1-era UScript — newer references will mislead)

- **The repo is LF; `UCC.exe` wants CRLF.** Covered above under
  [Building](#build-details-worth-knowing). When vendoring stock scripts,
  convert CRLF→LF before the verbatim commit.

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
  its subclasses. Since we don't rebuild `Engine.u`, reach the missing
  slots by their `IK_UnknownXX` names instead (e.g. `case IK_UnknownF0:`
  for D-pad up).
- See `scripting-reference.txt` at the repo root for a fuller language
  rundown — much of the modern UScript material online does not apply here.
- **Unary `+` on a constant on the RHS of an assignment fails to parse.**
  `x = +SomeConst;` errors with `Bad or missing expression in '='`. The
  matching unary `-` (`x = -SomeConst;`) is fine — the parser only chokes
  on the redundant `+`. Just drop it: `x = SomeConst;`.
- **All `var` declarations must appear before any `function` / `event` /
  `state` body in the class.** A `var` placed after the first function
  compiles to `Error, 'Var' is not allowed here`. Move vars to the top
  of the class body; function order itself is unconstrained.
- **`const` initializers must be literals, not expressions referencing
  other consts.** `const A = 28; const B = A + 4;` fails to compile with
  `Error, const B: Value is not constant` — UCC evaluates const initializers
  before const-symbol resolution. Same applies to compound expressions
  on plain literals: `const X = 150 + 16;` is rejected. Precompute the
  dependent value as a literal and document the formula in a comment.
- **UE1 has no cross-class `const` access syntax.** `Class'X'.const.NAME`,
  `Class'X'.NAME`, and `X.NAME` (from another class) all fail. Consts are
  class-scoped only. `Class'X'.Default.varName` works for `var`s but not
  for `const`s. Workaround: re-declare or hardcode the value at the call
  site with a back-reference comment naming the source const.
- **`var travel class<X>` is not supported — compiles fine, crashes on
  next level transition.** UE1's travel serializer cannot round-trip
  a `UClass` reference. Stock code documents the same limitation in
  `../deusex-scripts/DeusEx/Classes/DeusExWeapon.uc:283` and works around
  it by saving the class **name** in a `travel name` alongside a
  parallel `class<X>[]` lookup table. If you need to persist a class ref
  across travel, follow that pattern; otherwise drop `travel` and accept
  that the value resets on map change.
- **`Joy*`/`JoyPov*` bindings live in `[Extension.InputExt]` in `User.ini`,
  not `[Engine.Input]`.** The active `UInput` is `Extension.InputExt` and
  `UInput::Exec` reads `Bindings[Key]` keyed off its own class identity.
  Bindings written under `[Engine.Input]` are ignored. A stock `User.ini`
  ships with both sections populated (often with divergent values from
  accumulated edits); set the values you care about in
  `[Extension.InputExt]`.
- **`DeusExRootWindow.RefreshDisplay` is dead code in single-player.**
  `DeusExPlayer.RefreshSystems` is the only per-tick caller and it
  short-circuits on `Level.NetMode == NM_Standalone`. Don't put logic
  there. For per-tick mutation hooks, use `Tick(float)` on
  `Extension.RootWindow` (line 164) — verified to fire on
  `ControllerRootWindow` and to safely call `AskParentForReconfigure`-
  triggering methods like `PersonaScreenInventory.SelectInventory`
  (Tick runs between frames, not during draw). For per-frame *read-only*
  state queries, `DrawWindow` on a child window is fine; never trigger
  attach/select/`PressButton` from `DrawWindow` (calls
  `AskParentForReconfigure`, which UE1 forbids during draw — crashes the
  game). For "react to a window appearing or leaving the stack", use
  `DescendantAdded`/`DescendantRemoved` instead.
- **`DeusExRootWindow.GetTopWindow()` reflects the `PushWindow` stack
  only.** It returns `winStack[winCount-1]`. Windows added via direct
  `NewChild` on the root — notably conversation windows
  (`ConPlay.uc:84` does `rootWindow.NewChild(Class'ConWindowActive', False)`)
  and the HUD-side children — never enter `winStack`. So
  `GetTopWindow() == None` is **not** a reliable "no UI is foregrounded"
  test. To check whether any UI screen owns the foreground (e.g. "should
  the wheel open?"), walk `root.GetTopChild()` siblings looking for a
  `DeusExBaseWindow` match — same predicate `DescendantAdded` uses to
  drive the radial cancel-on-UI-takeover.
- **`RootWindow.ShowCursor(False)` hides the cursor sprite AND suppresses
  script-level `MouseMoved` dispatch.** The native (index 1522, used by
  vanilla `MenuScreenCustomizeKeys` / `ConWindowActive`) does both. To
  detect "user grabbed the mouse" while the cursor is hidden, poll
  `GetCursorPos(out x, out y)` in `Tick` and compare to a baseline
  captured at hide time. See `ControllerRootWindow.HideCursorAndClearHover`
  (baseline capture) and the cursor-poll block at the top of
  `ControllerRootWindow.Tick`. Corollary: the `event MouseMoved` override
  on the root window is reached only in `CM_Mouse`; the
  `CM_Gamepad → CM_Mouse` transition runs from the `Tick` poll.
- **`Console.KeyEvent` is the first script entry point for *all*
  input — mouse and keyboard included, not just the gamepad.** Mouse
  motion arrives as `IK_MouseX`/`IK_MouseY` `IST_Axis` events; mouse
  buttons as `IK_LeftMouse` etc. Any cursor-mode / "gamepad is active"
  signal driven from `KeyEvent` MUST whitelist the gamepad key slots
  (buttons `0xC8-0xD7`, D-pad `0xF0-0xF3`, axes `0xE0-0xE3`+`0xE8/E9`)
  first — see `ControllerConsole.IsGamepadKey`. An unfiltered hook
  misreads the mouse's own `IK_MouseX/Y` stream as gamepad activity
  and the cursor mode oscillates every frame. Title-screen specific:
  `UIPauseGame` skips `ShowMenu()` when `AtIntroMap()` is true, so the
  console never enters `state Menuing` there — every event reaches the
  class-scoped `KeyEvent`. The in-game pause menu *is* in `Menuing`,
  where the state override forwards only `JoyX/Y/U/V` to
  `global.KeyEvent`, so mouse axes don't reach the hook and the bug
  doesn't show.
- **Vanilla `VirtualKeyPressed` overrides may silently swallow
  unrecognised keys.** UE1 event dispatch bubbles `VirtualKeyPressed`
  up the window tree only while each handler returns `false`. The
  persona/menu pattern is
  `bHandled = True; switch (key) { case …; default: bHandled = False; }
  if (!bHandled) return Super.VirtualKeyPressed(...);` — but **older /
  less-trafficked window classes lack the `default:` case** and just
  return `True`. Vanilla never needed gamepad routing so the bug was
  never visible. Concrete instance: stock `ConWindowActive.VirtualKeyPressed`
  consumes every gamepad slot unless the overlay adds
  `default: bHandled = False;` to its inner switch. When adding a
  gamepad controller for any new in-world window (keypad, medbot,
  computer, ATM, hack…), **read its `VirtualKeyPressed` first** and
  check whether unrecognised keys reach root. If not, add a
  default-bubble in the overlay; otherwise the root-window intercept is
  dead code.
- **`Window.SetFocusWindow(w)` does not make a HUD-style root child the
  first key handler.** Setting engine focus to a persistent child of
  the root (a `HUDBaseWindow` such as `OnScreenKeyboardWindow` or
  `RadialMenuWindow`) does *not* route `VirtualKeyPressed` to it first
  — keys still bubble up the window tree to root as normal. To make a
  drawn overlay window modal-capture input, intercept in
  `ControllerRootWindow.VirtualKeyPressed` (gate on a flag and route to
  the window). Caveat: a physical-keyboard key that a *lower* window
  consumes before it can bubble — notably `IK_Escape`, eaten by
  `ComputerUIWindow.VirtualKeyPressed` — never reaches that intercept.
  Such keys need a separate path: a gated overlay of the consuming
  class calling back up via a virtual hook declared on the rebuildable
  `DeusEx`-side base (the on-screen keyboard routes Esc via
  `DeusExRootWindow.CloseGamepadKeyboard`, overridden in
  `ControllerRootWindow` — a DeusEx-side class can't name a
  `DXController` type).
- **No `GC` blend style gives a uniform translucent fill — combine two.**
  `GC` has only `DSTY_None/Normal/Masked/Translucent/Modulated`; there
  is no alpha blend. `DSTY_Translucent` over `Texture'Solid'` is purely
  *additive* (`framebuffer += texel * tileColor`, ignores tile alpha),
  so a near-black tint adds ~nothing — the panel reads as fully
  transparent. `DSTY_Modulated` is purely *multiplicative*
  (`dest * 2 * tileColor`, tile colour `128` = identity) — a dark tint
  darkens lit areas but leaves black areas pure black. For an *even*
  dark veil, draw the fill twice: `DSTY_Modulated` pass to pull the
  scene down toward black, then `DSTY_Translucent` pass to add a flat
  dark floor back. See `OnScreenKeyboardWindow.DrawWindow`.
- **For a translucent-tinted glow over arbitrary geometry, use
  `DSTY_Translucent` over a greyscale-on-black texture.** UE1's
  additive blend makes black texels add nothing, so the visible shape
  is the texture's lit pixels and the brightness/colour is the tile
  colour at draw time. Useful for shapes `GC` has no primitive for
  (non-axis-aligned arcs, pie slices, soft falloffs) and when the shape
  needs to track a theme accent. **Background must be pure black, NOT
  magenta-keyed** — masked-import textures rendered through
  `DSTY_Translucent` show the magenta as hot pink. See
  `RadialMenuWindow.DrawHighlightSlice` and the `Wedge0..Wedge9`
  non-masked imports in `DXControllerTextures.uc`.
- **`GC.SetTextColorRGB` / `SetTileColorRGB` leave `Color.A == 0`.**
  Both helpers build a `Color` from R/G/B only and never touch the
  alpha byte. Under `DSTY_Masked` the *text* renderer honours that
  alpha — text set via `SetTextColorRGB` draws fully transparent.
  Masked tile/texture draws ignore tile-colour alpha, which is why
  `SetTileColorRGB(255,255,255)` works for icons but `SetTextColorRGB`
  silently eats labels. Build the `Color` with an explicit `A = 255`
  and use `SetTextColor` / `SetTileColor` instead. Vanilla gets away
  with `SetTextColorRGB` only because it pairs it with `DSTY_Normal`.
- **`GC.DrawTexture` is a 1:1 blit — it does not scale.** Its signature
  is `DrawTexture(destX, destY, destWidth, destHeight, srcX, srcY, tx)` —
  it takes a source *origin* but no source *size*, so destination
  width/height only **clip** the blit. A 64×64 texture drawn into a
  16×16 box shows only the top-left 16×16 texels. To scale, use
  `DrawStretchedTexture(destX, destY, destW, destH, srcX, srcY,
  srcWidth, srcHeight, tx)`. Note `RadialMenuWindow` draws inventory/aug
  icons with `DrawTexture` at `IconSize` (~48) — fine only as long as
  those icons are ≤ that size; larger stock icons would be silently
  cropped.
- **A `struct` of two `string`s is 384 bytes and cannot be indexed as
  an array element through a context expression.** UE1 stores each
  `string` as a fixed 192-byte buffer. Accessing a field of such a
  struct held in an array on another object — `nav.hints[i].id` —
  makes UCC materialise the 384-byte element as a context-expression
  intermediate and fails with `Context expression: Variable is too
  large (384 bytes, 255 max)`. Mitigation: use parallel arrays of the
  scalar fields instead of an array-of-struct (`var string
  hintIds[16]; var string hintLabels[16];`). The 255-byte ceiling is
  on the context-expression *intermediate*, not the `var` itself.
- **`GC` has no line primitive.** Draw natives are `DrawText`,
  `DrawIcon`, `DrawTexture`, `DrawPattern`, `DrawBox`,
  `DrawStretchedTexture`, `DrawActor`, `DrawBorders`. Draw an
  axis-aligned line as a 1–2 px `DrawPattern` rectangle on
  `Texture'Solid'` (a degenerate filled rect). Non-axis-aligned lines
  (e.g. radial spokes) have no primitive at all and must be baked into
  a texture.
- **UE1 does NOT null `Object`/`Window` references when the target is
  `Destroy()`ed — a stored child-window pointer dangles (and the freed
  slot is reused).** Only `Actor` references get swept to `None` on
  destruction; `Window` extends `Object`, not `Actor`, so a held
  pointer stays non-`None` and points at freed (or recycled) memory.
  Bit the menu focus overlay: `MenuNavController.focused` = a screen
  child button, and vanilla can free that button while the controller
  stays attached (dropping or using up an inventory item runs
  `RemoveSelectedItem → selectedItem.Destroy()`). `focused` then
  dangles and `MenuFocusOverlay.DrawWindow → GetFocusedRect`
  dereferences freed memory on the next frame, crashing *inside*
  `DrawWindow`. You cannot null-check your way out — the pointer is
  non-`None`, and the slot may be reused by a different live window.
  Detect staleness with a **downward** live-descendant walk from the
  (always-live) `screen` — `MenuNavController.IsDescendantOf` /
  `IsFocusedLive`, pointer-compares only. Never call
  `focused.GetParent()` (or cast/`IsA` it) on a possibly dead pointer.
  Recovery runs from `ControllerRootWindow.Tick` via the
  `OnFocusedDestroyed` hook, never from the draw path.
- **`PersonaScreenInventory.CleanBelt()` empties the *real* HUD belt
  and only repopulates the screen's local copy — never call it to
  "refresh" the belt.** The belt has three views over one source of
  truth (per-item `bInObjectBelt`/`beltPos`): `root.hud.belt` (the
  gameplay item bar, and what `RadialMenuWindow` reads),
  `invBelt.hudBelt` (an *alias pointer* to `root.hud.belt`), and
  `invBelt.objBelt` (the inventory screen's private `HUDObjectBelt`).
  `CleanBelt` nulls every slot of the real HUD belt and repopulates
  *only* `objBelt`. Result: gameplay item bar and weapon wheel go
  permanently empty; the inventory screen's own bar self-heals on
  reopen — which masks the breakage as "looks fine in the menu, broken
  in gameplay." `CleanBelt` is non-destructive in stock only because
  its sole SP caller (`RefreshWindow`) is dead under `NM_Standalone`.
  To assign an item to a belt slot from a controller, use
  `PersonaScreenInventory.invBelt.AddObject(inv, slot)` (the same call
  the drag-and-drop drop handler uses) — it updates the player's real
  belt and the local `objBelt` together, non-destructively, and no-ops
  on slot 0 (the NanoKeyRing slot).
- **Textures compile into `DXController.u` via an `#exec` holder, not a
  separate package.** `DXController/Classes/DXControllerTextures.uc`
  (`class … extends Object;`, no runtime code) carries the
  `#exec TEXTURE IMPORT` lines: masked button glyphs + `WheelPlate`
  (`FLAGS=2` = PF_Masked, keys palette index 0 = magenta), and
  non-masked greyscale wedges (`Wedge0..Wedge9`, no FLAGS — for
  additive `DSTY_Translucent` draws). `MIPS=Off` on all (mip blending
  corrupts a masked key). `FILE=` paths are **relative to the package
  dir** (`DXController/`); the build script generates the PCX into
  `<gamedir>/DXController/Textures/` before the pass-2 compile.
  Reference textures as `Texture'DXController.<name>'`.
- **Index-by-int arrays of Texture refs can be initialised from
  `defaultproperties` with `arr(i)=Texture'Pkg.Name'`.** UE1 resolves
  the texture literal at link time, so as long as the package
  containing the texture is built in the same pass (or earlier), the
  array slots are populated before any draw call. Avoids a per-frame
  switch on integer-keyed texture lookups. The wheel's `wedgeTex[10]`
  uses this.
- **UE1 `var config` writes to `[Package.ClassName]`, not arbitrary
  section names — coordinate with the native side if it also reads.**
  A `class Foo extends Object config(Bar);` writes to `[Pkg.Foo]` in
  `Bar.ini`. If a native component reads the same keys, it must name
  the section `[Pkg.Foo]` too — the launcher does this for
  `[DXController.ControllerSettings]` via
  `GConfig->GetInt(L"DXController.ControllerSettings", ...)`. A naked
  `[DXController]` section is invisible to script's `var config` and an
  `[DXController.SomeOtherClass]` write is invisible to the launcher.

## Debug logging

All gamepad-domain debug logs go through the static helper
`class'DXControllerDebug'.static.DebugLog("DXC-…")`. Gating: the helper
itself checks `bGamepadDebugLog` config var, so call sites are
unconditional. Do **not** create new ad-hoc `Log(...)` calls in
controller code or per-class config bools. If a new debug category
needs its own toggle, add a sibling `var config bool` to
`DXControllerDebug.uc` plus a parallel helper.

Prefix all such logs with `DXC-<area>`: `DXC-WHEEL`, `DXC-NAV`,
`DXC-CURSOR`, etc. Enable via `DeusEx.ini`:

```ini
[DXController.DXControllerDebug]
bGamepadDebugLog=True
```

Output goes to `System/DeusEx.log`.

## Asset tooling

All DXController textures are generated at build time and compiled into
`DXController.u` via `#exec Texture Import` in
`DXController/Classes/DXControllerTextures.uc` — there is no separate
texture package.

- `assets/gen-wheel.py` — renders the weapon-wheel plate
  (`WheelPlate.png`) and the ten slice-highlight wedges
  (`wedges/wedge0..9.png`). Parametric; same inputs give byte-identical
  output.
- `assets/gen-menu-bg.py` — renders the controller-settings menu
  background. The page shows a variable number of option rows depending
  on the selected stick curves, so it emits one 2×3 tile set per possible
  visible-row total (`MenuControllerBackground_<N>_<tile>`, N in
  {4,5,6,7,8,10}); the menu swaps to the matching set at runtime.
- `assets/png-to-pcx.py` — PNG → 8-bit PCX, two modes: `masked`
  (magenta key at palette index 0) and `grey` (linear grey palette, no
  key, for the additive wedges).
- Button glyphs are hand-authored PNGs under `assets/XboxSeries/`.

`sync-and-build.sh` (and CI) call both generators and place PCX into
`<gamedir>/DXController/Textures/`. python3 + Pillow + numpy are
provided by the `sync-and-build` flake app and `nix develop`.
