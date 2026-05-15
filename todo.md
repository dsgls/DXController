# Tasks remaining

## New functionality

### In-game UI screens

Everything other than the persona screens still needs implementing. Hacking, datacubes, keypads etc.

### Scrolling for goals and notes persona screen

Need to play the game enough to go beyond the text area size to test.

### Controller button legend in UI contexts

Show xbox controller button pictures with their mapping in UI contexts. For menus where a controller button activates an UI button, show the controller button picture on the UI button. In other cases (e.g., inventory screen A=use,X=equip wheel) show buttons and their effect below the dialog.

Button pictures have been added to assets/DXControllerBtn.utx (group XboxSeries, texture names match the base names of the source pictures in assets/xbox-buttons-png/).

## Bug to fix

### Inventory screen B button

The B button does not work on the persona inventory screen. On other persona screens it correctly exits the screen.

### Main menu controller/mouse focus fighting

When the mouse is moved in main menu, the controller selection highlight disappears as it should. But then it starts flickering in and out, as if the mouse and controller focus are fighting. There should be a clear mode switch, mouse moved -> controller mode disabled, no focus highlight drawn. On controller input, controller mode enabled, mouse cursor hidden and controller focus highlight restored to previous selection.

## Nitpicks

These items don't really matter, just listing for completion. Don't work on them unless everything else is done.

### Settings screens with incomplete controller support

Colors and bindings ("keyboard/mouse") settings sections.

