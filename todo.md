# Tasks remaining

## New functionality

### In-game UI screens

In-world (non-persona) menu screens needing gamepad navigation, grouped
by natural scope. Scope 1 is being designed/implemented now; the rest
remain for later sessions.

#### Network terminals

Split into two phases. Phase 1 covers the terminal shell, the pane
model (LB/RB cycling between `winComputer` / `winHack` /
`winHackAccounts`), and every screen except Security. Phase 2 covers
the Security screen, which is dense enough to warrant its own design
pass.

##### Phase 1 — terminal foundation + non-Security screens — IN PROGRESS

Designed at
`docs/superpowers/specs/2026-05-15-network-terminal-nav-phase1-design.md`,
implemented per
`docs/superpowers/plans/2026-05-15-network-terminal-nav-phase1.md`.
All 12 nav classes build clean. Three bugs found and fixed: the
nav-registry array overflowed at [32] (dropping terminal registrations);
the ATM pushes `ATMWindow` (a subclass of `NetworkTerminalATM`) which
exact-match registration missed; and LB/RB pane switching never worked
because `ControllerConsole.KeyEvent`'s class-scoped `IK_Joy5`/`IK_Joy6`
branches `return true` unconditionally — terminals are pushed
`bNoPause=True` so the console stays out of `state Menuing`, leaving
that class-scoped wheel handler active, and it consumed LB/RB before
the window system / `NetworkTerminalNavController.HandleActivate` ever
saw them. Fixed: under `IsAnyUIForeground()` the LB/RB branches now
fall through to `Super.KeyEvent` (same path A/D-pad already take).
A fourth bug: after hacking a terminal from the Hack pane the
Computer-pane screen swaps (login → post-login), but `activePane`
stayed `PANE_HACK` — a successful hack keeps `winHack` alive as a
"Return" button so the `IsPanePresent` auto-fallback never fired, and
the new screen was unreachable. Fixed: `NavTick`'s screen-swap
detection now resets `activePane` to `PANE_COMPUTER`.
ATM login-screen + LB/RB pane switching verified working; ATM withdraw
screen after hack-login pending re-playtest. Personal/Public/Security
terminals pending playtest (wiring audited OK; Security's post-login
screen is the Phase 2 unknown-screen fallback).

- `NetworkTerminal` + `NetworkTerminalPersonal` / `Public` / `ATM` /
  `Security` shell (Security's per-screen sub-controller comes in
  Phase 2; Phase 1 covers the shell and the unknown-screen fallback).
- `ComputerScreenLogin`, `ComputerScreenATM`,
  `ComputerScreenATMWithdraw`, `ComputerScreenATMDisabled` —
  text-entry forms; gamepad navigates around text fields but can't
  type into them (on-screen keyboard deferred).
- `ComputerScreenBulletins`, `ComputerScreenEmail` — list-and-detail
  screens with auto-display side panel.
- `ComputerScreenSpecialOptions` — dynamic 1–4 choice buttons.
- `ComputerScreenHack` overlay pane (`btnHack` only).
- `ComputerScreenHackAccounts` side pane (account list + change
  button).

##### Phase 2 — `ComputerScreenSecurity`

Densest screen in the terminal family. Builds on Phase 1's pane
model and dispatcher; only adds the Security-screen-specific
sub-controller.

- Three internal regions: camera-selector row (3 cameras), choice
  rows (4 vertical action choices for Camera/Door Access/Door
  Open/Turret), pan/zoom button cluster (6 buttons) + pan/zoom-speed
  slider.
- Probably maps R-stick → continuous camera pan, triggers → zoom
  (instead of D-pad on the 6-button cluster). D-pad → choice rows.
  Camera selection mechanism TBD (numeric hotkey, Y-cycles, or
  in-row).
- Pan/zoom-speed slider intentionally left mouse/keyboard-only.
- Tick-driven camera/door/turret status updates (vanilla
  `NetworkRefreshTimer` / `DoorRefreshTimer`); controller is
  read-only with respect to these.

### Scrolling for goals and notes persona screen

Need to play the game enough to go beyond the text area size to test.

### Controller button legend in UI contexts - implemented, needs testing

Show xbox controller button pictures with their mapping in UI contexts. For menus where a controller button activates an UI button, show the controller button picture on the UI button. In other cases (e.g., inventory screen A=use,X=equip wheel) show buttons and their effect below the dialog.

Button pictures have been added to DXControllerBtn.utx (group XboxSeries, texture names match the base names of the source pictures in assets/xbox-buttons-png/). Helper functions have been written to implement this in ControllerButtonHint.uc. The on screen keyboard currently implements this, other contexts remain.

Implemented as a `ControllerHintOverlay` window owned by
`ControllerRootWindow`, which each frame pulls the active nav
controller's hints via `MenuNavController.BuildHints()` and draws a
centred bottom legend strip. Per-button anchored glyphs were
deliberately dropped in favour of a single uniform bottom legend
(per-button placement needs per-button special-casing and many UI
buttons are too small). Designed at
`docs/superpowers/specs/2026-05-17-controller-button-legend-design.md`,
plan at `docs/superpowers/plans/2026-05-17-controller-button-legend.md`.
All nav controllers wired: the content pass added `BuildHints` to the
remaining 18 registered controllers, plus a `ScreenTopRight`
`hintPlacement` option used by ConversationNavController. Designed at
`docs/superpowers/specs/2026-05-17-controller-button-legend-completion-design.md`,
plan at
`docs/superpowers/plans/2026-05-17-controller-button-legend-completion.md`.
Needs playtest.

### Implement a way to apply weapon mods through inventory screen - implemented, needs testing

Vanilla applies a mod by mouse-dragging the mod tile onto a weapon;
gamepad had no path (A = equip/use, both disabled for mods).

Implemented a `'ModApply'` sub-dialog in `InvNavController` (commits
`4f6c071`..`ea53256`). A on a selected weapon mod enters the mode: D-pad
roams the focus frame over all inventory tiles (mod stays selected so
its green compatible-weapon highlights persist), A applies the mod to a
focused eligible weapon, B cancels. Zero compatible weapons -> status
message, no mode entry; exactly one -> auto-focused. Apply mirrors the
vanilla `FinishButtonDrag` block (`ApplyMod` / `RemoveObjectFromBelt` /
status / `DestroyMod` / reselect weapon).

Designed at
`docs/superpowers/specs/2026-05-16-weapon-mod-apply-inventory-design.md`,
plan at
`docs/superpowers/plans/2026-05-17-weapon-mod-apply-inventory.md`
(Task 3 = the 11-step playtest checklist). Builds clean; not yet
playtested (needs a save with a weapon mod + mixed compatible/
incompatible weapons in inventory).

Known limitation, carried from the spec: `focused` / `modSourceButton`
can go stale across `PersonaScreenInventory`'s ~0.25s tile rebuild —
the same pre-existing limitation `InvNavController.focused` already has.

## Bug to fix

### Can't use lockpicks - fix applied, needs testing

RT with lockpick doesn't do anything, even though the mouse LB works. Are we sending a different event? Probably applies to multitools as well.

### Can't heal through heal menu - fix applied, needs testing

The focus spots are on the body parts themselves, they only show a description of the bodypart when activated. Need to focus the actual heal buttons.

### ATM screens (and probably other devices) don't suppress gameplay actions

Pulling RT fires while interacting with terminal.

### Main menu controller/mouse focus fighting - fix applied, needs testing

When the mouse is moved in main menu, the controller selection highlight disappears as it should. But then it starts flickering in and out, as if the mouse and controller focus are fighting. There should be a clear mode switch, mouse moved -> controller mode disabled, no focus highlight drawn. On controller input, controller mode enabled, mouse cursor hidden and controller focus highlight restored to previous selection.

Root cause: `ControllerConsole.KeyEvent` called `NoticeGamepadActivity()`
for every event, including the `IK_MouseX/Y` axis events that mouse
motion generates. On the title-screen menu the console isn't in
`state Menuing` (`UIPauseGame` skips `ShowMenu` on the intro map), so
those mouse axes reached the hook and flipped the cursor back to
`CM_Gamepad` while `MouseMoved` flipped it to `CM_Mouse` — oscillation.
Fix: `ControllerConsole.IsGamepadKey` whitelist gates the hook to real
gamepad slots only.

## Nitpicks

These items don't really matter, just listing for completion. Don't work on them unless everything else is done.

### Settings screens with incomplete controller support

Colors and bindings ("keyboard/mouse") settings sections.

