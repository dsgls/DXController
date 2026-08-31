# Writing native code extensions

UE1 lets a script package call into C++ you ship yourself: a
`MyMod.u` + `MyMod.dll` pair in `System/`. The engine loads and binds
the DLL on its own, so a native extension needs no launcher, no
injection, and no patching of stock binaries. It is the supported
extension point for "I need script to call native code", and the right
answer for third-party mods that want to integrate with DXController
without depending on our launcher.

It does **not** help you change stock native behaviour — nothing here
hooks existing `Engine.dll` / `WinDrv.dll` code. That is what the
launcher's runtime patches are for.

## The model

The two halves carry different things:

- **`MyMod.u`** — declarations. Class hierarchy, property layout and
  offsets, function signatures, the `FUNC_Native` flag and the
  `iNative` opcode number. No bodies for native functions.
- **`MyMod.dll`** — the bodies, plus a few exported symbols the engine
  looks up by name.

Both derive from the same `.uc` sources, so the layout `ucc` bakes into
the `.u` and the layout the DLL compiles against cannot drift.

## How the engine binds them

Three lookups, all by string, all lazy:

| Step | What happens |
|------|--------------|
| Find the DLL | `UPackage::BindPackage` calls `appGetDllHandle("<BaseDir><PackageName>.dll")` on first native lookup, caching the handle |
| Bind the class | `UClass::Bind` resolves `autoclass<CppName>` and takes the C++ constructor from it |
| Bind each function | `UFunction::Bind` — see below |

**The DLL name is the package name.** `MyMod.u` ⇒ `MyMod.dll`, both in
`System/`. There is nothing else to register.

`<CppName>` is `A` + script name for `Actor` descendants, `U` + script
name otherwise.

`UFunction::Bind` branches on `iNative`:

- not native → the bytecode interpreter (`UObject::ProcessInternal`)
- `iNative != 0` → `Func = GNatives[iNative]`
- `iNative == 0` → `GetDllExport("int" + CppName + "exec" + FuncName)`,
  *checked* — a missing export is a fatal load-time error

Once bound, `Func` is a plain pointer-to-member; `UObject::CallFunction`
calls straight through it. A script→native call costs the same as any
stock engine native.

Instruction-level detail for all of this is in
`../deusex-native-re/docs/core-reflection-containers.md` (`UFunction::Bind`)
and `docs/core-vm.md` (`GNatives` / `GRegisterNative`).

## Prefer name-bound natives over opcode numbers

`GNatives` is a single global 4096-slot table shared by every loaded
package, and `GRegisterNative` lets a collision through:

```c
if (iNative != -1) {
    if (iNative < 0 || iNative > 0x1000 || GNatives[iNative] != &execUndefined)
        GNativeDuplicate = iNative;   /* collision merely recorded... */
    GNatives[iNative] = Func;         /* ...last registrant wins */
}
```

Nothing reads `GNativeDuplicate`. Two packages claiming the same opcode
silently steal it from each other, and there is no registry of which
numbers mods have taken. Stock already scatters itself across the range
(Extension 1024–1844, DeusEx 1099 / 2100–2109 / 3001–3017 / 3075).

Declare natives **without** a number. `iNative == 0` takes the
name-bound path, which cannot collide. Core, Engine and Editor all use
it for real functions (`Locale.GetLanguage`, `BrushBuilder.*`,
`Decal.AttachDecal`). The cost is a byte or two of bytecode per call
site.

## Writing one

### 1. Declare in `.uc`

No C++ appears in a `.uc` file — a native function is just a
declaration with a `;` instead of a body. (UE2's `cpptext { ... }`
block does not exist in this engine.)

```unrealscript
class MyThing extends Object
    native;

var int Counter;                                 // C++ sees this at the same offset

native final function int Frobnicate(string s);  // implemented in the DLL
function int Helper(int a)                       // ordinary script bytecode
{
    return a * 2;
}
```

Class modifiers that matter:

- **`native`** (legacy spelling `intrinsic`, still accepted) — `ucc`
  generates the C++ class definition for you.
- **`native noexport`** — `ucc` generates nothing for the class; you
  hand-write the whole C++ class. Stock uses this for `DumpLocation`
  and `LaserIterator`.

### 2. Let `ucc make` generate the header

For any package containing native classes, the make commandlet writes
`MyMod/Inc/MyModClasses.h` alongside the `.u`. It contains the C++
mirror of every native class:

```cpp
class MYMOD_API UMyThing : public UObject
{
public:
    INT Counter;
    DECLARE_FUNCTION(execFrobnicate);
    DECLARE_CLASS(UMyThing,UObject,0)
    #include "UMyThing.h"        // only when you supply this file
};
...
AUTOGENERATE_FUNCTION(UMyThing,-1,execFrobnicate);
```

`-1` is `GRegisterNative`'s "no opcode, name-bound" sentinel — the
toolchain wires that up from the unnumbered declaration.

The generated header also emits `event*_Parms` structs and `eventFoo()`
wrappers, so C++ can call *into* script through `ProcessEvent`.

The SDK's `DeusEx-SDK/Headers/DxHeaders/*/Inc/*Classes.h` files are
exactly this output for the stock packages — useful as worked examples.

### 3. Add C++-only members

The `#include "<CppName>.h"` line lands *inside* the generated class
body, so the file it names is a fragment, not a standalone header — no
include guard, no `class`, just members. Stock
`DxHeaders/DeusEx/Inc/ADeusExPlayer.h` is the whole file:

```cpp
	// Constructor
	ADeusExPlayer();
	void Destroy(void);
	void ConBindEvents(void);
	const TCHAR *GetDeusExVersion(void);
```

Omit the file entirely if the class needs no extra members; the
`#include` is then not emitted.

### 4. Write the C++ and register it

Bodies use the `P_GET_*` / `P_FINISH` marshalling macros from
`Core/Inc/UnScript.h` to pull arguments off the script stack:

```cpp
void UMyThing::execFrobnicate( FFrame& Stack, RESULT_DECL )
{
    P_GET_STR(S);
    P_FINISH;
    *(INT*)Result = S.Len() + Counter;
}
```

One translation unit carries the package-level registrations. Rather
than hand-listing every native, redefine `AUTOGENERATE_FUNCTION` and
re-include the generated header:

```cpp
#include "MyModClasses.h"       // class definitions

IMPLEMENT_PACKAGE(MyMod);       // exports GPackage[] = "MyMod"
IMPLEMENT_CLASS(UMyThing);      // exports autoclassUMyThing

#define NAMES_ONLY
#define AUTOGENERATE_NAME(name)
#define AUTOGENERATE_FUNCTION(cls,idx,name) IMPLEMENT_FUNCTION(cls,idx,name)
#include "MyModClasses.h"
#undef AUTOGENERATE_FUNCTION
#undef AUTOGENERATE_NAME
#undef NAMES_ONLY
```

**`NAMES_ONLY` is load-bearing.** Without it the header defines
`AUTOGENERATE_FUNCTION` to nothing itself, so the re-include registers
nothing at all — it compiles clean and every native then fails to bind
at load. With it, the header skips the class definitions and hands your
macro the list.

The same re-include trick with `AUTOGENERATE_NAME` defines the
package's `FName` globals (one pass at file scope for storage, a second
inside an init function assigning `FName(TEXT(#name), FNAME_Intrinsic)`).
`../deusex-native-re/Extension/src/ExtensionCore.cpp` is a worked
example of both passes.

`IMPLEMENT_FUNCTION` exports `int<CppName>exec<FuncName>` and calls
`GRegisterNative`. Verify the resulting export table with `dumpbin
/exports` — the names must match what `UFunction::Bind` will ask for.

## Build order

```
MyMod/Classes/*.uc
      │  ucc make            (EditPackages entry in DeusEx.ini)
      ├──────────────► System/MyMod.u
      └──────────────► MyMod/Inc/MyModClasses.h
                              │  MSVC, linking Core.lib + Engine.lib
                              └──► System/MyMod.dll
```

Script first, then C++ — the header is an output of the make step, so
it does not exist before the first run.

**Any `.uc` change touching a native class's properties means re-running
make *and* rebuilding the DLL.** Skipping the rebuild leaves two
disagreeing memory layouts and corrupts silently.

Ship the `.u` and `.dll` as a unit. A mismatched pair is a load-time
fatal, not a graceful degrade.

## Toolchain and ABI

`ucc` contains no C++ compiler. The stock DLLs were built with MSVC 6.0
(PE linker version 6.0 in `Core.dll` / `DeusEx.dll` / `Extension.dll`).
Modern MSVC links against the 2001-era import libs in
`DeusEx-SDK/Headers/DXLibs/` — `../deusex-native-re/Extension/` builds a
full `Extension.dll` replacement on toolset v145 — provided the ABI
matches:

- `/Zp4` struct packing (`EngineClasses.h` does `#pragma pack(push,4)`)
- `UNICODE` **and** `_UNICODE` defined — `TCHAR` is 2 bytes
- `/EHsc` — `UnVcWin32.h` `#error`s without `_CPPUNWIND`
- no `/J` — `UnVcWin32.h` `#error`s on `_CHAR_UNSIGNED`
- Win32 only; inline `__asm` paths require `_M_IX86`

`../deusex-native-re/Extension/README.md` documents these with their
witness lines, and its `verify/` directory has export-table diffing
tooling.
