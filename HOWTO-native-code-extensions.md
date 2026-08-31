# Writing native code extensions

UE1 lets a script package call into C++ you ship yourself: a
`MyMod.u` + `MyMod.dll` pair in `System/`. The engine loads and binds
the DLL itself, so a native extension needs no launcher, no injection,
and no patching of stock binaries.

**The DLL's base name must match the package's.** `MyMod.u` ⇒
`MyMod.dll`, both in `System/`. There is nothing else to register.

This does not help you change stock native behaviour — nothing here
hooks existing `Engine.dll` / `WinDrv.dll` code. That is what the
launcher's runtime patches are for.

Worked example below: a `MyMod` package exposing one native function on
one native class.

## 1. Declare the function in UnrealScript

`MyMod/Classes/MyThing.uc`. A native function is a declaration with a
`;` where the body would be — no C++ appears in a `.uc` file.

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

**Declare natives without an opcode number.** The `native(1234)` form
indexes a single global 4096-slot table shared by every loaded package.
Nothing arbitrates it, collisions are silent, and the last package to
load wins. Stock already scatters itself across the range (Extension
1024–1844, DeusEx 1099 / 2100–2109 / 3001–3017 / 3075). Unnumbered
natives resolve by DLL export name instead and cannot collide; Core,
Engine and Editor all use them for real functions.

Class modifiers that matter:

- **`native`** (legacy spelling `intrinsic`, still accepted) — `ucc`
  generates the C++ class definition for you.
- **`native noexport`** — `ucc` generates nothing for the class and you
  hand-write the whole C++ class. Stock uses this for `DumpLocation`
  and `LaserIterator`.

## 2. Run `ucc make`

With `MyMod` in `EditPackages`, the make step produces two outputs:

```
MyMod/Classes/*.uc  ──►  System/MyMod.u
                    └─►  MyMod/Inc/MyModClasses.h
```

The header is a C++ mirror of every native class — properties in the
exact order and at the exact offsets baked into the `.u`, plus a
`DECLARE_FUNCTION` line per native:

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

Never edit it. Regenerate it.

The generated header also emits `event*_Parms` structs and `eventFoo()`
wrappers, so C++ can call *into* script.

The class name gains a prefix: `A` for `Actor` descendants, `U` for
everything else. That prefixed name is what every C++ macro below
wants.

The SDK's `Headers/DxHeaders/*/Inc/*Classes.h` files are this same
output for the stock packages — useful as worked examples.

## 3. Add C++-only members

Optional. The `#include "<CppName>.h"` line lands *inside* the
generated class body, so the file it names is a fragment, not a
standalone header — no include guard, no `class`, just members. The
stock `ADeusExPlayer.h` is the whole file:

```cpp
	// Constructor
	ADeusExPlayer();
	void Destroy(void);
	void ConBindEvents(void);
	const TCHAR *GetDeusExVersion(void);
```

Omit the file and the `#include` is not emitted.

## 4. Write the body

Arguments come off the script stack with the `P_GET_*` / `P_FINISH`
macros from `Core/Inc/UnScript.h`, in declaration order. The return
value goes to `Result`.

```cpp
void UMyThing::execFrobnicate( FFrame& Stack, RESULT_DECL )
{
    P_GET_STR(S);
    P_FINISH;

    *(INT*)Result = S.Len() + Counter;
}
```

`P_FINISH` is not optional — it steps the bytecode pointer past the
end-of-parameters token. Use the `_OPTX` variants for `optional`
parameters and the `_REF` variants for `out` ones.

## 5. Register the package

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
nothing at all — it compiles clean, and every native then fails to bind
at load. With it, the header skips the class definitions and hands your
macro the list.

The same re-include trick with `AUTOGENERATE_NAME` defines the
package's `FName` globals: one pass at file scope for storage, a second
inside an init function assigning `FName(TEXT(#name), FNAME_Intrinsic)`.

`IMPLEMENT_FUNCTION` exports `int<CppName>exec<FuncName>` — here,
`intUMyThingexecFrobnicate` — and that name is what the engine looks up
at load. `dumpbin /exports` is the way to check you got it.

## 6. Build the DLL

MSVC, linking `Core.lib` and `Engine.lib` from the SDK's
`Headers/DXLibs/`. Modern toolsets link against those 2001-era import
libs fine, provided the ABI matches:

- `/Zp4` struct packing (`EngineClasses.h` does `#pragma pack(push,4)`)
- `UNICODE` **and** `_UNICODE` defined — `TCHAR` is 2 bytes
- `/EHsc` — `UnVcWin32.h` `#error`s without `_CPPUNWIND`
- no `/J` — `UnVcWin32.h` `#error`s on `_CHAR_UNSIGNED`
- Win32 only; inline `__asm` paths require `_M_IX86`

## Rebuild discipline

Script first, then C++ — the header is an output of the make step, so
it does not exist before the first run.

**Any `.uc` change touching a native class's properties means re-running
make *and* rebuilding the DLL.** Skipping the rebuild leaves two
disagreeing memory layouts and corrupts silently.

Ship the `.u` and `.dll` as a unit. A mismatched pair is a load-time
fatal, not a graceful degrade.

## Reference

<https://git.dsg.is/dsg/deusex-native-re/> reverse-engineers the stock
native DLLs. Most relevant here:

- `Extension/src/ExtensionCore.cpp` — a full package registration TU,
  including both `AUTOGENERATE_NAME` passes.
- `Extension/README.md` — the ABI knobs above, each with the SDK header
  line that forces it.
- `Extension/verify/` — export-table diffing tooling.
