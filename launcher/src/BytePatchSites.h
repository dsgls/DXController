#pragma once

//Pushed to warning level 0 the way stdafx.h does it: this header is also
//compiled into the test project, which builds at /W4 /WX.
#pragma warning(push, 0)
#pragma warning(disable: 4324) //SDK structs padded by the launcher project's /Zp4
#include <windows.h>
#include <stdlib.h> //_countof; the launcher gets it via stdafx.h, the test TU does not
#pragma warning(pop)

//The byte-patch site tables, in a header so BytePatchSitesTests can check the
//real data. CBytePatch (BytePatch.cpp) is the only other consumer; it owns the
//Win32 side -- locating each module, comparing, writing.

//One patch site: the whole-instruction fingerprint that must match, and the
//bytes written in its place. The whole run is written, not just the bytes that
//differ -- unchanged bytes are rewritten with their existing values, which
//keeps a site with non-contiguous changes a single table entry.
struct SPatchSite
{
    DWORD          iPreferredVA;   //Address against the owning module's preferred image base
    const BYTE*    pExpected;      //Fingerprint
    const BYTE*    pReplacement;   //Same length, enforced by MakeSite
    size_t         iLen;
    const wchar_t* pszDescription; //For log + mismatch dialog
    const wchar_t* pszConsequence; //What goes wrong if the patch is skipped
};

//Deducing both array lengths as one N makes a fingerprint/replacement length
//mismatch a compile error instead of a runtime surprise.
template <size_t N>
constexpr SPatchSite MakeSite(const DWORD iPreferredVA,
                              const BYTE (&aExpected)[N], const BYTE (&aReplacement)[N],
                              const wchar_t* const pszDescription,
                              const wchar_t* const pszConsequence)
{
    return { iPreferredVA, aExpected, aReplacement, N, pszDescription, pszConsequence };
}

struct SPatchModule
{
    const wchar_t*    pszModule;
    DWORD             iPreferredBase;
    const SPatchSite* pSites;
    size_t            iSiteCount;
};

// --- WinDrv.dll -----------------------------------------------------------
// UWindowsViewport::UpdateInput. See ../deusex-native-re/docs/windrv-input.md.

//Bug 1 -- joy loop bitmap index. CMP byte [ECX+EAX+0xeb0], BL -> [ECX+EAX+0xf78], BL.
static constexpr BYTE kJoyBitmapExpected[]    = { 0x38, 0x9C, 0x01, 0xB0, 0x0E, 0x00, 0x00 };
static constexpr BYTE kJoyBitmapReplacement[] = { 0x38, 0x9C, 0x01, 0x78, 0x0F, 0x00, 0x00 };

//Bug 2 -- trailer outer-loop bound. CMP EDI, 0x100 -> CMP EDI, 0xC8.
static constexpr BYTE kTrailerBoundExpected[]    = { 0x81, 0xFF, 0x00, 0x01, 0x00, 0x00 };
static constexpr BYTE kTrailerBoundReplacement[] = { 0x81, 0xFF, 0xC8, 0x00, 0x00, 0x00 };

static constexpr SPatchSite kWinDrvSites[] =
{
    MakeSite(0x11109341, kJoyBitmapExpected, kJoyBitmapReplacement,
             L"joy-loop press-branch bitmap index (Bug 1)",
             L"joystick buttons may cause spurious script-side key events"),
    MakeSite(0x11109372, kJoyBitmapExpected, kJoyBitmapReplacement,
             L"joy-loop release-branch bitmap index (Bug 1)",
             L"joystick buttons may cause spurious script-side key events"),
    MakeSite(0x11109881, kTrailerBoundExpected, kTrailerBoundReplacement,
             L"trailer outer-loop bound (Bug 2)",
             L"controller buttons may release spuriously every frame"),
};

// --- DeusEx.dll -----------------------------------------------------------
// XGameDirectory::GetNewSaveFileIndex. See
// ../deusex-native-re/docs/deusex-savegame-model.md.
//
// The scan reads each "SaveNNNN" directory name to find the highest index in
// use, but NUL-terminates at the first digit and starts appAtoi at the second,
// so it only ever sees the low three digits. The running max therefore cannot
// exceed 999 and the function returns 1000 forever once any Save?999 exists --
// every subsequent save overwrites Save1000, wiping the previous one first
// (SaveGame calls DeleteSaveGameFiles(destDir)).
//
//   66 c7 40 08 00 00   MOV word [EAX+8], 0   -> six NOPs: keep all four digits
//   83 c0 0a            ADD EAX, 0xa          -> ADD EAX, 8: parse from the first
//
// Patching the whole nine-byte run rather than the six changed bytes plus the
// one displacement keeps this a single site (bytes 6-7 are unchanged in
// between). Since "%04d" is a minimum width, the fixed scan keeps working past
// Save9999 -- there is no ceiling left.
static constexpr BYTE kSaveIndexExpected[]    = { 0x66, 0xC7, 0x40, 0x08, 0x00, 0x00, 0x83, 0xC0, 0x0A };
static constexpr BYTE kSaveIndexReplacement[] = { 0x90, 0x90, 0x90, 0x90, 0x90, 0x90, 0x83, 0xC0, 0x08 };

static constexpr SPatchSite kDeusExSites[] =
{
    MakeSite(0x10017D13, kSaveIndexExpected, kSaveIndexReplacement,
             L"save-index scan digit truncation",
             L"saves past the 1000th silently overwrite each other"),
};

static constexpr SPatchModule kPatchModules[] =
{
    { L"WinDrv.dll", 0x11100000, kWinDrvSites, _countof(kWinDrvSites) },
    { L"DeusEx.dll", 0x10000000, kDeusExSites, _countof(kDeusExSites) },
};
