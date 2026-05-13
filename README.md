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
