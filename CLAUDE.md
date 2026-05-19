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

### Sister repos and their roles

The full project spans four repos. This one is the script-side mod; the
others are sibling working trees you can `cd ../<name>` to:

- **`../DeusExe-XInput/`** — fork of [Deus Exe](https://kentie.net/article/dxguide/)
  that builds the launcher executable (`DeusEx.exe`) used to run the
  game. This is **the only user-owned native code in the project**. It
  loads the stock engine DLLs, polls XInput once per engine tick, and
  feeds events as `EInputKey` / `EInputAction` / float-delta tuples
  through `UEngine::InputEvent` (so as far as the engine is concerned
  they came from `WinDrv`). It also runs two in-memory byte patches
  against `WinDrv.dll` at startup to fix joystick bugs in the stock
  binary — see "Native input pipeline" below.
- **`../deusex-native-re/`** — Ghidra reverse-engineering notes for the
  stock `System/*.dll` binaries. Documentation only; nothing built or
  shipped from here. **Read this whenever a "but why does the engine do
  X?" question comes up** — it is the authoritative source for native
  behaviour. Most relevant docs:
  - `docs/input-chain.md` — end-to-end event flow from the OS through
    to player exec functions; what each native stage does, what it
    drops, what it synthesises.
  - `docs/windrv-input.md` — `WinDrv.dll`'s per-frame input poll, the
    two joystick bugs, and the byte-patch fixes the launcher applies.
  - `docs/extension-classes.md` — `Extension.dll` class catalog
    (`XInputExt`, `XRootWindow`, `XGameEngineExt`, `APlayerPawnExt`,
    `XViewportWindow`) with addresses, mangled symbols, field offsets.
- **`../deusex-scripts/`** — exported `.uc` files for every stock
  package. Read-only reference — see "Working with the original
  scripts" below.

**Ownership map** (matters for the "flag, don't compensate" rule):

| Component                          | Repo                       | Modifiable? |
|------------------------------------|----------------------------|-------------|
| `DeusEx.exe` launcher / XInput shim / WinDrv runtime patches | `../DeusExe-XInput/` | yes |
| `DXController.u` (this mod)        | this repo                  | yes |
| Edits to `DeusEx.u` classes (overlay) | `DeusEx/Classes/` here  | yes (rebuilt) |
| `Engine.dll`, `Core.dll`, `Extension.dll`, `WinDrv.dll`, `Render.dll`, `*.u` packages other than `DeusEx.u` | stock game install | **no** (in-memory patches only, via the launcher) |
| Stock `.uc` exports                | `../deusex-scripts/`       | **no** (reference only) |

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
./sync-and-build.sh   # sync overlay .uc into build dir, two-pass UCC build
```

The script copies the overlay `.uc` sources (`DXController/`, `DeusEx/`,
`DeusExe/`) into `$BUILD_DIR/`, then runs `UCC.exe make` twice: pass 1
deletes and rebuilds `DeusEx.u` (tolerating a known UCC GPF — see below);
pass 2 deletes and rebuilds `DXController.u` in a fresh UCC process. Pass
`-n` for a dry run (lists files, no build). Override the build dir with
`BUILD_DIR=/path`.

The repo stores `.uc` source as LF, but the ancient `UCC.exe` wants
CRLF-terminated source. The sync step passes each overlay file through
`unix2dos -n` on the way into the build dir, so only our overlay files
are converted — the full stock `DeusEx/Classes/` tree is left untouched.
`unix2dos` (from the `dos2unix` package) is therefore a build
prerequisite: run `sync-and-build.sh` under `nix develop` (the flake dev
shell provides it) or install `dos2unix`. The CI workflow installs it
via `apt`.

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

### Suspected native-side bugs: flag, don't compensate

**User-owned native code:** the launcher executable and its XInput shim
in `../DeusExe-XInput/`, plus the runtime byte patches it applies to
`WinDrv.dll` at startup (`DeusExe/WinDrvPatch.cpp`). These can be fixed
at the source.

**Stock native code:** `Engine.dll`, `Core.dll`, `Extension.dll`
(including `XInputExt` aka `Extension.InputExt`), `WinDrv.dll`,
`Render.dll`. Not user-owned — but `../deusex-native-re/` documents
their behaviour from RE, and the launcher can ship more in-memory
patches if a stock-side fix is needed.

If a behaviour looks like a bug in *either* category — events that
shouldn't fire, events that should fire but don't, values in the wrong
range, missing edges, etc. — **do not build a UScript workaround.**
Surface the observation explicitly:

- What the script-side sees, with concrete event sequences / values
  from `DeusEx.log` if available.
- Which native component is the likely owner (XInput shim, WinDrv
  runtime patch, `Extension.dll`'s `XInputExt`, stock `WinDrv.dll`,
  etc.) so the right repo can be opened. When in doubt about which
  stage drops or transforms an event, check
  `../deusex-native-re/docs/input-chain.md` — it traces every stage
  from the OS to the player exec function.
- What the *expected* behaviour would be.

Then stop. For user-owned code the user fixes it directly; for stock
code the user decides whether to add a runtime patch. A UScript
band-aid hides the real defect, accumulates compensating complexity in
the mod, and can mask further changes on the native side.

### Debug logging

All gamepad-domain debug logs go through the static helper
`class'DXControllerDebug'.static.DebugLog("DXC-…")`. Gating: the helper
itself checks `bGamepadDebugLog` config var, so call sites are
unconditional. Do **not** create new ad-hoc `Log(...)` calls in
controller code, and do **not** add per-class config bools. If a new
debug category needs its own toggle, add a sibling `var config bool`
to `DXControllerDebug.uc` plus a parallel helper.

Prefix all such logs with `DXC-<area>`: `DXC-WHEEL`, `DXC-NAV`,
`DXC-CURSOR`, etc.

## UnrealScript quirks (this is UE1-era UScript — newer references will mislead)

- **The repo is LF-standardized; `UCC.exe` wants CRLF.** All text files
  (including every `.uc`) are stored with LF line endings — enforced by
  `.editorconfig` (`end_of_line = lf`) and `.gitattributes`
  (`* text=auto eol=lf`); history was rewritten once (via `jj fix`) to
  normalise it. The ancient `UCC.exe` expects CRLF-terminated source, so
  `sync-and-build.sh` and the CI workflow convert each overlay `.uc`
  with `unix2dos -n` when writing it into the build dir (see "Building").
  Consequence: never let raw `git` check out the working tree under a
  config that would re-CRLF it — jj never does, and `.gitattributes`
  pins `eol=lf` for git too. When vendoring stock scripts, convert
  CRLF→LF before the verbatim commit (see "Source overlay model").

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
- **`DeusExRootWindow.RefreshDisplay` is dead code in single-player.**
  `DeusExPlayer.RefreshSystems`
  (`../deusex-scripts/DeusEx/Classes/DeusExPlayer.uc:1614`) is the only
  per-tick caller and it short-circuits on
  `Level.NetMode == NM_Standalone`. Don't put logic there. For per-tick
  mutation hooks, use `Tick(float)` on `Extension.RootWindow` (line 164)
  — verified to fire on `ControllerRootWindow` (subclass) and to safely
  call `AskParentForReconfigure`-triggering methods like
  `PersonaScreenInventory.SelectInventory` (Tick runs between frames,
  not during draw). For per-frame *read-only* state queries,
  `DrawWindow` on a child window is fine; never trigger
  attach/select/`PressButton` from `DrawWindow` (that path calls
  `AskParentForReconfigure` which UE1 forbids during draw — the
  cascade crashes the game). For "react to a window appearing or
  leaving the stack", use `DescendantAdded`/`DescendantRemoved`
  instead — see "Menu nav controllers".
- **`DeusExRootWindow.GetTopWindow()` reflects the `PushWindow` stack
  only.** It returns `winStack[winCount-1]`, which is populated by
  `PushWindow` and emptied by `PopWindow`. Windows added via direct
  `NewChild` on the root — notably conversation windows
  (`../deusex-scripts/DeusEx/Classes/ConPlay.uc:84` does
  `rootWindow.NewChild(Class'ConWindowActive', False)`) and the HUD-side
  children — never enter `winStack` and so don't show up in
  `GetTopWindow()`. Implication: `GetTopWindow() == None` is **not** a
  reliable "no UI is foregrounded" test. To check whether any UI screen
  owns the foreground (for purposes like "should the wheel open?"),
  walk `root.GetTopChild()` siblings looking for a `DeusExBaseWindow`
  match — that's the same predicate `DescendantAdded` uses to drive
  the radial cancel-on-UI-takeover.
- **`RootWindow.ShowCursor(False)` hides the cursor sprite AND
  suppresses script-level `MouseMoved` dispatch.** The native (index
  1522, used by vanilla `MenuScreenCustomizeKeys` /
  `ConWindowActive`) does both. To detect "user grabbed the mouse"
  while the cursor is hidden, poll `GetCursorPos(out x, out y)` in
  `Tick` and compare to a baseline captured at hide time. See
  `ControllerRootWindow.HideCursorAndClearHover` (baseline capture)
  and the cursor-poll block at the top of `ControllerRootWindow.Tick`.
  Corollary: the `event MouseMoved` override on the root window is
  reached only in `CM_Mouse` (cursor visible); the `CM_Gamepad → CM_Mouse`
  transition runs from the `Tick` poll, not the event.
- **`Console.KeyEvent` is the first script entry point for *all*
  input — mouse and keyboard included, not just the gamepad.** Mouse
  motion arrives as `IK_MouseX`/`IK_MouseY` `IST_Axis` events; mouse
  buttons as `IK_LeftMouse` etc. Any cursor-mode / "gamepad is active"
  signal driven from `KeyEvent` MUST whitelist the gamepad key slots
  (buttons `0xC8-0xD7`, D-pad `0xF0-0xF3`, axes `0xE0-0xE3`+`0xE8/E9`)
  first — see `ControllerConsole.IsGamepadKey`. An unfiltered hook
  misreads the mouse's own `IK_MouseX/Y` stream as gamepad activity:
  one mouse motion fires both `MouseMoved` (→`CM_Mouse`) and the axis
  events (→`CM_Gamepad`), so the cursor mode oscillates every frame
  and the focus highlight flickers. This bites on the **title-screen**
  main menu specifically: `DeusExRootWindow.UIPauseGame` skips
  `parentPawn.ShowMenu()` when `AtIntroMap()` is true, so the console
  never enters `state Menuing` there — every event (mouse axes
  included) reaches the class-scoped `ControllerConsole.KeyEvent`. The
  in-game pause menu *is* in `Menuing`, where the state override
  forwards only `JoyX/Y/U/V` to `global.KeyEvent`, so mouse axes never
  reach the hook and the bug doesn't show.
- **Vanilla `VirtualKeyPressed` overrides may silently swallow
  unrecognised keys.** UE1 event dispatch bubbles `VirtualKeyPressed`
  up the *window* tree only while each window's handler returns
  `false`. The persona/menu screen pattern is
  `bHandled = True; switch (key) { case …; default: bHandled = False; }
  if (!bHandled) return Super.VirtualKeyPressed(...);` —
  see `PersonaScreenBaseWindow.uc:95-118`, `MenuUIScreenWindow.uc:174-212`.
  But **older / less-trafficked window classes lack the `default:` case
  and just return `True`** — vanilla never needed gamepad routing so
  the bug was never visible. Concrete instance: stock
  `ConWindowActive.VirtualKeyPressed` (vendored at
  `DeusEx/Classes/ConWindowActive.uc`) consumes every gamepad slot
  unless the overlay adds `default: bHandled = False;` to its inner
  switch (commit `56914c2`). When adding a gamepad controller for any
  new in-world window (keypad, medbot, computer, ATM, hack…),
  **always read its `VirtualKeyPressed` first** and check whether
  unrecognised keys reach root. If not, add a default-bubble in the
  overlay; otherwise `ControllerRootWindow.VirtualKeyPressed` is dead
  code and no `DXC-*` log will fire from any gamepad press in that
  window. Same trap likely applies to `ConWindow`, `HUDKeypadWindow`,
  `ComputerUIWindow`, etc. — verify per-class before designing.
- **`Window.SetFocusWindow(w)` does not make a HUD-style root child the
  first key handler.** Setting engine focus to a persistent child of
  the root (a `HUDBaseWindow` such as `OnScreenKeyboardWindow` or
  `RadialMenuWindow`) does *not* route `VirtualKeyPressed` to it first —
  keys still bubble up the window tree to
  `ControllerRootWindow.VirtualKeyPressed` as normal. Verified by
  play-test: `OnScreenKeyboardWindow.Open` called
  `GetRootWindow().SetFocusWindow(Self)` and D-pad/A still reached the
  terminal nav underneath. To make a drawn overlay window modal-capture
  input, intercept in `ControllerRootWindow.VirtualKeyPressed` — gate on
  a flag and route to the window (see the `keyboard.bOpen` block, which
  calls `OnScreenKeyboardWindow.HandleKey`). Caveat: a physical-keyboard
  key that a *lower* window consumes before it can bubble to root —
  notably `IK_Escape`, eaten by `ComputerUIWindow.VirtualKeyPressed` —
  never reaches that intercept. Such keys need a separate path: a gated
  overlay of the consuming class calling back up. The on-screen keyboard
  routes Esc via a `// DXController gate` in `ComputerUIWindow` that
  calls the `DeusExRootWindow.CloseGamepadKeyboard` virtual hook
  (overridden in `ControllerRootWindow`) — a DeusEx-side class can't
  name a `DXController` type, so the hook is declared on the rebuildable
  `DeusExRootWindow` base.
- **No GC blend style gives a uniform translucent fill — combine two.**
  `GC` has only `DSTY_None/Normal/Masked/Translucent/Modulated`
  (`../deusex-scripts/Extension/Classes/ExtensionObject.uc:202`); there
  is no alpha blend. `DSTY_Translucent` over `Texture'Solid'` is purely
  *additive* — it *adds* `texel * tileColor` into the framebuffer and
  ignores the tile-colour alpha entirely, so a near-black tint (the
  obvious "dark translucent panel") adds ~nothing and the panel reads as
  fully transparent. `DSTY_Modulated` is purely *multiplicative*
  (`dest * 2 * tileColor`, so tile colour `128` is identity) — a dark
  tint darkens lit areas but leaves black areas pure black, so a panel
  over mixed content looks blotchy. For an *even* dark veil, draw the
  fill twice: a `DSTY_Modulated` pass to pull the scene down toward
  black, then a `DSTY_Translucent` pass to add a flat dark floor back.
  `OnScreenKeyboardWindow.DrawWindow` does this for its panel (the echo
  field stays single-pass `DSTY_Modulated` black — an inset is meant to
  be the darkest element). The same additive-`DSTY_Translucent`-over-
  `Solid` pattern is still present in `RadialMenuWindow.uc` (empty-slot
  placeholder ~472, panel dim ~613) — likely also drawing ~nothing;
  unverified, not yet changed.
- **`GC.SetTextColorRGB` / `SetTileColorRGB` leave `Color.A == 0`.**
  Both helpers (`../deusex-scripts/Extension/Classes/GC.uc:157,172`)
  build a `Color` from R/G/B only and never touch the alpha byte, so it
  defaults to 0. Under `DSTY_Masked` the *text* renderer honours that
  alpha — text set via `SetTextColorRGB` draws fully transparent
  (masked *tile/texture* draws ignore tile-colour alpha, which is why
  `SetTileColorRGB(255,255,255)` works for icons but `SetTextColorRGB`
  silently eats labels). This bit `ControllerButtonHint.DrawHint` (the
  on-screen-keyboard footer hints rendered with no visible text). Build
  the `Color` with an explicit `A = 255` and use `SetTextColor` /
  `SetTileColor` instead. Vanilla code gets away with `SetTextColorRGB`
  only because it pairs it with `DSTY_Normal`, which draws text opaque.
- **`GC.DrawTexture` is a 1:1 blit — it does not scale.** Its signature
  (`../deusex-scripts/Extension/Classes/GC.uc:114`) is
  `DrawTexture(destX, destY, destWidth, destHeight, srcX, srcY, tx)` —
  it takes a source *origin* (`srcX/srcY`) but no source *size*, so
  `destWidth/destHeight` only **clip** the blit; the texture is drawn at
  native pixel scale. Drawing a 64×64 texture into a 16×16 box shows
  only the top-left 16×16 texels (for the masked button glyphs, that
  corner is the transparent key colour — i.e. nothing). To scale a
  texture, use `DrawStretchedTexture(destX, destY, destW, destH, srcX,
  srcY, srcWidth, srcHeight, tx)` (`GC.uc:129`), which takes a source
  *rect* and maps it onto the destination rect. This bit
  `ControllerButtonHint.DrawHint` (the 64×64 DXControllerTex glyphs
  drew invisibly at 16px until switched to `DrawStretchedTexture`). Note
  `RadialMenuWindow` draws inventory/aug icons with `DrawTexture` at
  `IconSize` (~48) — fine only as long as those icons are ≤ that size;
  larger stock icons would be silently cropped.
- **A `struct` of two `string`s is 384 bytes and cannot be indexed as
  an array element through a context expression.** UE1 stores each
  `string` as a fixed 192-byte buffer, so
  `struct { var string a; var string b; }` is 384 bytes. Accessing a
  field of such a struct held in an array on another object —
  `nav.hints[i].id` — makes UCC materialise the 384-byte element as a
  context-expression intermediate and fails with
  `Error, Context expression: Variable is too large (384 bytes, 255
  max)`. Mitigation: use parallel arrays of the scalar fields instead
  of an array-of-struct (`var string hintIds[16]; var string
  hintLabels[16];`) — each indexed element is then a 192-byte string,
  under the limit. This bit the button-legend hint model
  (`MenuNavController.hintIds` / `hintLabels`, read by
  `ControllerHintOverlay`). The 255-byte ceiling is on the
  context-expression *intermediate*, not the `var` itself — a large
  array as a plain `var` is fine; it is `obj.arr[i].field` chains that
  trip it.
- **`GC` has no line primitive.** The draw natives are `DrawText`,
  `DrawIcon`, `DrawTexture`, `DrawPattern`, `DrawBox`,
  `DrawStretchedTexture`, `DrawActor`, `DrawBorders`
  (`../deusex-scripts/Extension/Classes/GC.uc:108-140`) — there is no
  `DrawLine`. Draw an axis-aligned line as a 1–2 px `DrawPattern`
  rectangle on `Texture'Solid'` — a degenerate filled rect.
  Non-axis-aligned lines (e.g. the radial spokes on the weapon wheel)
  have no primitive at all and must be baked into a texture.
  `RadialMenuWindow.DrawEmptyMark` draws its `+` as two thin
  `DrawPattern` rects for exactly this reason.

## Source overlay model

`DeusEx.u` is rebuildable (the user has batch-exported its source into
`$BUILD_DIR/DeusEx/Classes/`). To change a class in `DeusEx`, place an
edited copy under `DeusEx/Classes/<File>.uc` in this repo; the build
script rsyncs it on top of the stock tree and rebuilds the package.
Stock files we don't touch stay stock. Discipline: when adding a stock
file to `DeusEx/Classes/` for the first time, copy it from
`../deusex-scripts/`, **convert CRLF→LF** (`dos2unix`), and commit that
as the verbatim vendor commit (message: "Vendor stock
DeusEx/Classes/<File>.uc (unmodified)"); then make edits in a follow-up
commit. The repo is LF-standardized but `ucc batchexport` emits CRLF, so
the line-ending conversion is the one allowed deviation from "verbatim"
— it changes no code, and it keeps `git diff <vendor>..<edit>` showing
exactly our delta against upstream rather than whole-file line-ending
noise. The same applies when vendoring into `DeusExe/Classes/` from
`../DeusExe-XInput/`.

Within each modified file, additions live in a banner-delimited block:

```
// === DXController additions: BEGIN ===
...
// === DXController additions: END ===
```

Pure additions are the default. See `DeusEx/Classes/DeusExPlayer.uc`
for the canonical example.

**In-place gates are acceptable when surgical.** When a vanilla call
inside a stock function body needs to be suppressed based on
controller-side state — and the class can't subclass itself, so the
method body can't simply be overridden — wrap the offending call in a
one-line `if (!bSomeFlag)` gate and tag it with an inline
`// DXController gate` comment. See `DeusEx/Classes/ConWindowActive.uc`
for the canonical example (four `root.ShowCursor(...)` calls gated on
`bGamepadMode`). The `git diff <vendor>..<edit>` will still show
exactly the gate delta. Do **not** restructure function bodies, change
control flow beyond the gate, or add new function-internal logic — at
that point the change has outgrown the overlay pattern and should be
either a subclass-and-ini-swap or a discussion about whether the
DeusEx side really needs to host the logic.

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
hook wants. The redeclared state inherits the parent's other state-scoped
functions, labels, and latent code unless explicitly overridden, so the
override is a partial replacement, not a full reimplementation.

**Canonical example in this codebase:** `ControllerConsole.state Menuing`
(`DXController/Classes/ControllerConsole.uc`, bottom of file). Stock
`Console.state Menuing.KeyEvent` short-circuits on `Action != IST_Press`
and so drops every axis event. The override forwards stick axes (X/Y/U/V)
to `global.KeyEvent` so the class-scoped handler's axis branch — radial
`UpdateStick`, nav-controller `HandleScroll` — runs in menu mode.
Triggers stay on `Super` so they don't fire weapons mid-menu. Mirrors
stock `Console.state Typing.KeyEvent`'s use of `global.KeyEvent` at
`Engine/Classes/Console.uc:635`.

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

```
[OS / XInput pad]
       │
       ▼
[XInput shim in ../DeusExe-XInput/DeusExe/XInput.cpp]
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
`../deusex-native-re/docs/input-chain.md`. The summary below is what
script authors need to know; chase that doc when something doesn't
match expectations.

The engine's first script-side entry point for any key/axis event is
`Console.KeyEvent(EInputKey Key, EInputAction Action, float Delta)` in
`../deusex-scripts/Engine/Classes/Console.uc`. Axes arrive there with
`Action == IST_Axis` and the raw axis value in `Delta`. Buttons/POV
arrive with `IST_Press` / `IST_Release`. State-scoped overrides exist
(`Typing`, `Menuing`, etc.); the `Typing` override forwards to
`global.KeyEvent`, the menu states do not. To hook the stream without
rebuilding `Engine.u`, subclass `Console` per the "Packages that can't
be rebuilt" section above.

### Native input pipeline (legacy joystick path is OFF)

`UseJoystick=False` in `[Engine.Engine]` of `DeusEx.ini`. This disables
`WinDrv.dll`'s legacy `joyGetPosEx` poll path entirely — the XInput
shim is the *only* source of joystick events in this build. Don't
re-enable `UseJoystick`: the legacy path has known bugs (see
`../deusex-native-re/docs/windrv-input.md`) and would race the shim for
the same `IK_Joy*` slots.

The launcher (`../DeusExe-XInput/`) also applies in-memory byte
patches to `WinDrv.dll` at startup that fix two stock bugs:

- **Bug 1**: `joyGetPosEx`-loop bitmap-index off-by-`0xc8`, which would
  otherwise produce a press storm at frame rate on `Console.KeyEvent`
  for any held joy button.
- **Bug 2**: trailer reconciliation pass synthesises an `IST_Release`
  every frame for joy buttons whose `IK_Joy*` keycode falls in the
  reserved-VK range (all of them, in practice). Without the patch, any
  press injected through `WM_KEYDOWN` (which is how some virtual-pad
  wrappers — though *not* this project's XInput shim — surface
  buttons) would be released the same tick.

Both fixes are documented in `../deusex-native-re/docs/windrv-input.md`
("Bug 1" and "Bug 2") and applied by `DeusExe/WinDrvPatch.cpp`. With
`UseJoystick=False` the joy-loop path is dead anyway, so Bug 1 is moot
for current behaviour, but the patches are present for defence in
depth (and for the case where someone flips the ini back). If you see
`WinDrvPatch: fingerprint MISMATCH` in the launcher log, that's the
patcher refusing to write into a `WinDrv.dll` it doesn't recognise —
ask the user to confirm their `WinDrv.dll` matches the GOG / Steam
build the patch was authored against.

### Script-visible input handler: `Extension.InputExt`

The active `UInput` is `Extension.InputExt` (native class `XInputExt`
in `Extension.dll`, wired via `[Engine.Engine] Input=Extension.InputExt`
in `DeusEx.ini`). It is *not* stock UE1 `UInput`; its `Process`
override changes what reaches the binding system:

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

**Implication for the XInput work:** axis events from the C++ shim
reach `Console.KeyEvent` on every frame regardless of UI state —
`Console.KeyEvent` runs upstream of `InputExt::Process`, so InputExt's
"UI gets first refusal" only affects the *binding-dispatch* path
downstream. What can make axes appear dead in script is a separate
quirk in stock `Console`: `state Menuing.KeyEvent` short-circuits
`Action != IST_Press`, so once `PushWindow` → `UIPauseGame` →
`ShowMenu` puts the console in `Menuing`, axis events never reach
`global.KeyEvent`. The fix is a subclass-side state override (see
"State-scoped dispatch → Canonical example"), not anything on the
native side. Button press/release events (`IK_Joy1`–`IK_Joy16`, D-pad
slots) are already de-duplicated by InputExt, so the shim doesn't need
its own edge filter.

### XInput → UE event mapping

The C++-side XInput shim
(`../DeusExe-XInput/DeusExe/XInput.cpp`, see `kButtonMap` at the top of
the file for the source of truth) feeds these `EInputKey` slots into
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

#### Deadzone, response curve, edge events: all done in the shim

The shim already applies a configurable radial deadzone, a power-curve
response shape (`XInputLeftStickExponent` / `XInputRightStickExponent`,
default `2.0`), and edge-emits `IST_Axis(0.0)` exactly once when an
axis crosses from non-zero to zero. It also synthesises `IST_Release`
for held buttons / `IST_Axis(0.0)` for held axes on focus loss and on
controller disconnect (`CXInput::FlushHeldAxes` /
`ReleaseHeldButtons`). Implications:

- **Don't add a script-side deadzone or response curve.** Re-tune the
  shim's ini settings (`XInputLeftStickDeadzone`, `*Exponent`) instead.
  Stacking a second deadzone in script means the user has two knobs
  that interact non-linearly.
- **Don't add a "stuck input on alt-tab" workaround in script.** The
  shim already flushes held state on `bHasFocus == false`. If you
  observe a stuck axis after focus loss, that's a defect in the shim
  or in the focus-detection path — flag it (per "flag, don't
  compensate") rather than building a per-tick zero-write loop in
  UScript.
- **Trust the zero-edge `IST_Axis`.** When the stick re-enters the
  deadzone the shim emits one final `IST_Axis(0.0)` for that channel
  and stops sending. Script-side code can rely on "received `0.0`
  means the player let go" and clear accumulators on that edge — see
  the R-stick scroll accumulator in `LogsNavController.uc`.

Active-controller selection is also shim-side: whichever XInput slot
most recently produced input becomes the active slot, and only that
slot's events are forwarded. Script code does not need to demux pads.

## Menu nav controllers

Per-screen gamepad navigation lives in `DXController/Classes/<Screen>NavController.uc`,
each extending `MenuNavController`. `ControllerRootWindow` keeps a
class→controller registry and attaches when a registered screen class is
added to the root via `DescendantAdded`, detaches when its screen is
removed via `DescendantRemoved`. To add a new screen: write the
controller, then add one
`RegisterNav(Class'DeusEx.X', Class'XNavController')` line in
`ControllerRootWindow.RegisterNavControllers()`. No other plumbing needed.

### Window-stack observation: use engine events, never polling

Attach/detach of nav controllers is driven by
`ControllerRootWindow.DescendantAdded(Window)` and
`DescendantRemoved(Window)` — UE1 native events that fire on every
ancestor when a child enters or leaves the window tree. By the time
`DescendantRemoved` fires the descendant is still a valid Window pointer
(vanilla `HUDBarkDisplay.DescendantRemoved`
(`../deusex-scripts/DeusEx/Classes/HUDBarkDisplay.uc:84`) calls
`descendant.IsA(...)` on it), so detach can safely log
`descendant.Class` and clear refs *before* the C++ object is freed.

Why this matters: `InvokeUIScreen`-style screen swaps destroy the old
screen and push the new one synchronously inside one event handler. Any
"did the top window change?" check that runs *after* the swap (per-frame
poll, lazy `MaybeAttachNav`-style detection) inspects a dangling pointer
and crashes when it dereferences `screen.Class`. Engine events fire
*during* the swap, so the detach happens against a live pointer.

Use this pattern for any "react to a window appearing or leaving the
stack" need — nav attach/detach, the radial wheel's UI-takeover cancel
(`RadialMenuWindow.OnTopWindowPushed`), and anything similar in future.
Don't use `RefreshDisplay`, `RefreshHUDDisplay`, or any polling loop for
window-stack observation.

### `InitFocus` and the deferred-init retry

`ControllerRootWindow.Tick` re-calls `activeNav.InitFocus()` every frame
until `activeNav.bFocusInitDone` is true. This exists because some
screens (e.g. `PersonaScreenInventory`) populate child windows *after*
the controller attaches, so the first `InitFocus()` finds an empty
screen.

Contract for `InitFocus()`:

- It may be called many times before the screen is fully built. Make it
  idempotent — re-running it on a ready screen must not disturb player
  state.
- Grid/menu controllers that set `focused` to a real `Window` get
  `bFocusInitDone` set for free (by `Attach` and the Tick retry).
- List/scroll controllers keep `focused == None` by design (rows are not
  `Window` objects). They MUST set `bFocusInitDone = True` themselves
  once their content is ready (e.g. `GetNumRows() > 0` and the first row
  selected). If they don't, the retry re-runs `InitFocus()` every frame
  and undoes navigation — this was the Logs/Conversations/Images
  scroll-dead bug (commit history: persona-screen-nav-fixes).

### EInputKey is not in scope from controllers

`MenuNavController extends Object`. `EInputKey` is on `Engine.Actor` and
isn't reachable from `Object` scope, so `HandleActivate` takes `byte`, not
`EInputKey`. Compare against literal byte values, each with a comment:

- `200` = `IK_Joy1` (A)
- `201` = `IK_Joy2` (B)
- `202` = `IK_Joy3` (X)
- `203` = `IK_Joy4` (Y)
- `209` = `IK_Joy10` (R-stick click)

`ControllerRootWindow.VirtualKeyPressed` is in `Window` scope and *can* see
`EInputKey`, but UE1 rejects implicit `EInputKey`→`byte` coercion in function
args. Use a local: `local byte bkey; bkey = key;` before
`activeNav.HandleActivate(bkey)`. See `ControllerRootWindow.uc` for the
pattern.

### Button activation idiom

Use `btn.PressButton()` (no args) — same path the keyboard uses,
`ButtonActivated` fires upstream. `btn.ActivateButton(IK_LeftMouse)` also
works but mixes in right-click semantics. Always gate on `btn.bIsSensitive`
before pressing.

Note: `bIsSensitive` lives on `Window` (`../deusex-scripts/Extension/Classes/Window.uc`),
not on `ButtonWindow`. The intuitive `ButtonWindow.bSensitive` does not exist
— the field is named `bIsSensitive` and inherited from `Window`. Reference
the typed action-button field directly (e.g. `s.btnEquip.bIsSensitive`).

### Vanilla list screens (`PersonaListWindow`)

For native list-backed screens (Images, Logs, Conversations, Load/Save,
Themes), use the row API on `Extension.ListWindow`:

- Select first: `lst.SetRow(lst.IndexToRowId(0), True, True)`.
- Navigate: `lst.MoveRow(MOVELIST_Up/Down, True, True)`.
- Edge detection: read `lst.GetFocusRow()` before and after `MoveRow`; if
  unchanged, you're at an edge. Fall through to `MOVELIST_Home`/`End` to
  wrap, or halt if no wrap.
- `EMoveList` constants live on `ExtensionObject`.

The screen's `ListSelectionChanged` callback usually fires automatically on
row change and drives any side-panel display update — no explicit re-display
call needed from the controller. Verify per screen.

`GetFocusedRect` should return `false` on list screens (rows aren't `Window`
objects, so the focus overlay can't draw a frame around them). `bAllowRepeat=True`.

Canonical template: `DXController/Classes/ImagesNavController.uc`.

### Spatial nearest-neighbour (grid screens)

For non-list screens with absolutely-positioned buttons (Inventory, Augs,
AugInstall):

- Get each button's centre via `ConvertCoordinates(btn, 0.5*btn.width, 0.5*btn.height, root, cx, cy)`.
- Filter candidates by direction with a `bSkip` boolean (UE1 has no `goto`
  or `continue`).
- Compare squared Euclidean distance; pick the nearest.
- For wrap behaviour: see `InvNavController.FindWrapTarget` (same-row
  preference for horizontal wrap, then nearest column for vertical).
- `bAllowRepeat=False` — grid nav should be single-press.

Canonical templates: `DXController/Classes/InvNavController.uc` (with wrap),
`DXController/Classes/AugsNavController.uc` (no wrap).

### Text scrolling (`PersonaScrollAreaWindow`)

The native scroll-area class exposes only `vScale.MoveThumb(MOVETHUMB_StepUp)`
and `vScale.MoveThumb(MOVETHUMB_StepDown)` — there is no pixel-granularity
API. For R-stick smooth scroll:

- Deadzone: ~200 on the -1000..1000 axis scale.
- Accumulate raw deflection; fire one step per ~500 accumulated units;
  reset accumulator when stick re-enters deadzone.
- R-stick up sends positive `ry` → `StepUp` (content moves toward top).

Two access patterns depending on the screen:

- **Direct field** (e.g. `PersonaScreenLogs.winScroll` is the
  `PersonaScrollAreaWindow` itself): use `s.winScroll.vScale.MoveThumb(...)`.
- **Indirect via `CreateScrollTileWindow`** (e.g. `PersonaScreenGoals.winGoals`
  is the *inner* `TileWindow`, not the scroll area): walk
  `winGoals.GetParent().GetParent()` to reach the `PersonaScrollAreaWindow`.
  See `PersonaScreenBaseWindow.CreateScrollTileWindow` for why.

Canonical templates: `DXController/Classes/LogsNavController.uc` (direct),
`DXController/Classes/GoalsNavController.uc` (parent-chain walk).

### Verify field names against `../deusex-scripts/` before coding

UE1 enforces typed field access at compile time and does not validate `IsA('Name')`
strings, so a wrong field name fails at build (good) but a wrong `IsA` only
fails silently at runtime (bad). Before writing a new controller:

1. Open `../deusex-scripts/DeusEx/Classes/<Screen>.uc` and confirm the exact
   field names, types, and any `Select*`/`ListSelectionChanged` callbacks
   that drive auto-display.
2. For action buttons, follow the inheritance chain to `ButtonWindow` to
   confirm `PressButton()` is available without a cast.
3. If the screen is a subclass of another (e.g. `HUDMedBotAddAugsScreen
   expands PersonaScreenAugmentations`), the registry key match is exact —
   register the subclass separately if it needs different navigation.
