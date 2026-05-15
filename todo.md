# Tasks remaining

## New functionality

### In-game UI screens

In-world (non-persona) menu screens needing gamepad navigation, grouped
by natural scope. Scope 1 is being designed/implemented now; the rest
remain for later sessions.

#### Scope 1 — Conversation family (in progress)

- `ConWindowActive` — interactive third-person conversations: choice
  list + speech-advance.
- `ConWindow` — non-interactive first-person speech (advance-only).
- Datacubes — ride on the conversation flow (`ConPlay` plays their
  `Conversation` asset), so come along with the above.
- `DataLinkPlay` infolinks: intentionally out of scope. They're a
  non-blocking corner UI during gameplay and we don't want to sacrifice
  an in-game button just for a skip binding.

#### Scope 2 — Standalone modal devices (later session)

- `HUDKeypadWindow` — 4×3 button grid (1-9, *, 0, #).
- `HUDMedBotHealthScreen` — extends `PersonaScreenHealth` but has a
  distinct class identity, so the existing `HealthNavController`
  registry entry doesn't pick it up. Needs registry entry plus
  "Heal All" action button hookup.
- `RepairBot` screen (if it has a discrete UI — verify during design).

#### Scope 3 — Network terminals (later session)

- `NetworkTerminal` and its `ComputerUIWindow` family: Login,
  Bulletins, Email, Security (cameras / doors / turrets), Hack
  Accounts, ATM (read balance + withdraw), Special Options.
- Multi-screen tabbed nav, text-entry fields (Login), camera viewing,
  hack progress UI — fundamentally different shape from the
  single-screen modals of Scope 2.

### Scrolling for goals and notes persona screen

Need to play the game enough to go beyond the text area size to test.

### Controller button legend in UI contexts

Show xbox controller button pictures with their mapping in UI contexts. For menus where a controller button activates an UI button, show the controller button picture on the UI button. In other cases (e.g., inventory screen A=use,X=equip wheel) show buttons and their effect below the dialog.

Button pictures have been added to assets/DXControllerBtn.utx (group XboxSeries, texture names match the base names of the source pictures in assets/xbox-buttons-png/).

## Bug to fix

### Skills screen B button

The B button does not work on the persona skills screen. On other persona screens it correctly exits the screen.

### Main menu controller/mouse focus fighting

When the mouse is moved in main menu, the controller selection highlight disappears as it should. But then it starts flickering in and out, as if the mouse and controller focus are fighting. There should be a clear mode switch, mouse moved -> controller mode disabled, no focus highlight drawn. On controller input, controller mode enabled, mouse cursor hidden and controller focus highlight restored to previous selection.

## Nitpicks

These items don't really matter, just listing for completion. Don't work on them unless everything else is done.

### Settings screens with incomplete controller support

Colors and bindings ("keyboard/mouse") settings sections.

