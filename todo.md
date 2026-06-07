# Tasks remaining

## New functionality

## Bugs to fix

### Controller settings page background does not match dialog layout

`MenuScreenController` uses the stock `MenuGameOptionsBackground_*` tiles but
the 720x480 client area doesn't line up with the tile grid the way stock
screens (~540x408) do, so the background looks misaligned behind the rows
and curve previews. Authoring our own tile set, or adjusting client size to
match a clean tile multiple, would fix it.

## Nitpicks

These items don't really matter, just listing for completion. Don't work on them unless everything else is done.

### Settings screens with incomplete controller support

Colors and bindings ("keyboard/mouse") settings sections.

