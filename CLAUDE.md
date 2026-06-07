# Notes for Claude

Read `development.md` first — it's the authoritative reference for the
codebase, and much of the modern UnrealScript material online does not
apply to this UE1-era engine. `scripting-reference.txt` at the repo
root is the fuller language rundown.

This file holds rules and pointers that only matter when working in
the user's environment.

## Sister repos

Two sibling working trees, both read-only references:

- `../deusex-scripts/` — batch-exported `.uc` files for every stock
  package. Look up stock classes here when overlaying.
- `../deusex-native-re/` — Ghidra RE notes for the stock `System/*.dll`
  binaries. The authoritative source for "but why does the engine do
  X?" questions. Most relevant docs:
  - `docs/input-chain.md` — end-to-end event flow from the OS through
    to player exec functions.
  - `docs/windrv-input.md` — `WinDrv.dll`'s per-frame input poll and
    the byte-patch fixes the launcher applies.
  - `docs/extension-classes.md` — `Extension.dll` class catalog
    (`XInputExt`, `XRootWindow`, `XGameEngineExt`, `APlayerPawnExt`,
    `XViewportWindow`).

## Ownership map

| Component                          | Where                       | Modifiable? |
|------------------------------------|-----------------------------|-------------|
| `DeusEx.exe` launcher / XInput shim / WinDrv runtime patches | `launcher/` | yes |
| `DXController.u` (the mod)         | `DXController/Classes/`     | yes |
| Edits to `DeusEx.u` classes        | `DeusEx/Classes/` (overlay) | yes (rebuilt) |
| `Engine.dll`, `Core.dll`, `Extension.dll`, `WinDrv.dll`, `Render.dll`, stock `.u` packages | stock game install | no (in-memory patches only, via the launcher) |
| Stock `.uc` exports                | `../deusex-scripts/`        | no (reference only) |

## Vendoring stock files

When adding a stock file to `DeusEx/Classes/` for the first time, copy
it from `../deusex-scripts/`, convert CRLF→LF (`dos2unix`), and commit
that as the verbatim vendor commit (message: "Vendor stock
DeusEx/Classes/<File>.uc (unmodified)"). Make edits in a follow-up
commit. The line-ending conversion is the one allowed deviation from
"verbatim" — it keeps the diff against upstream showing exactly our
delta.

## Keep the documentation current

Three files document this project; each has a specific scope. Update
the relevant one **as you learn things** — not "eventually". Knowledge
you re-derive the hard way and don't write down gets re-derived again
next session.

- `development.md` — human-developer reference for this codebase. Repo
  layout, build process, architecture (source overlay model, input
  pipeline, menu navigation), debug logging, asset tooling, and the
  UnrealScript quirks list. Update when you discover a new UE1-era
  language quirk, build-script behaviour, engine quirk, or
  architectural pattern. Each new UnrealScript-quirks entry stands
  alone with at least one concrete file reference or example.
- `CLAUDE.md` — this file. Agent-discipline rules and pointers that
  only matter when working in the user's environment: sister repos,
  ownership map, vendoring procedure, this rule, the
  flag-don't-compensate rule. Update when a process rule changes or a
  new ownership boundary / sister repo appears. Do **not** add
  human-developer content here — it goes in `development.md`.
- `README.md` — end-user install and run instructions. Update when an
  install step, ini edit, or troubleshooting note becomes necessary
  for the mod to work. No forensic reconstruction of what was changed
  in the build dir.

If a finding belongs in two files, document concisely in both — the
quirk form in `development.md`, the user-facing form in `README.md`.

For `development.md` and `CLAUDE.md`, only document **high-level
information** (what someone getting up to speed on the project would
want) or **things that are not obvious and not easily discoverable by
reading the code**. "To build the project, run
`nix run .#sync-and-build`" is relevant; "the build script does X then
Y then waits for Z then frobs the fizz" is useless verbosity.

## Flag, don't compensate

**User-owned native code:** the launcher executable and its XInput shim
in `launcher/`, plus the runtime byte patches it applies to
`WinDrv.dll` at startup (`launcher/src/WinDrvPatch.cpp`). Fixed at the
source.

**Stock native code:** `Engine.dll`, `Core.dll`, `Extension.dll`
(including `XInputExt` aka `Extension.InputExt`), `WinDrv.dll`,
`Render.dll`. Not user-owned — but `../deusex-native-re/` documents
their behaviour, and the launcher can ship more in-memory patches if a
stock-side fix is needed.

If a behaviour looks like a bug in *either* category — events that
shouldn't fire, events that should fire but don't, values in the wrong
range, missing edges — **do not build a UScript workaround.** Surface
the observation: what the script-side sees (with concrete sequences /
values from `DeusEx.log` if available), which native component is the
likely owner, what the expected behaviour would be. Then stop. For
user-owned code the user fixes it directly; for stock code the user
decides whether to add a runtime patch. A UScript band-aid hides the
real defect and can mask further changes on the native side.
