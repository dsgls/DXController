#include "stdafx.h"
#include "WinDrvPatch.h"

namespace
{
    constexpr DWORD kPreferredImageBase = 0x11100000;

    struct WinDrvPatchSite
    {
        DWORD          iPreferredVA;          // Address against image base 0x11100000.
        BYTE           aExpectedBytes[8];     // Whole-instruction fingerprint (length = iFingerprintLen).
        BYTE           aReplacementBytes[8];  // Same length as fingerprint.
        BYTE           iFingerprintLen;       // 7 for sites 1-2, 6 for site 3.
        BYTE           iPatchOff;             // Offset of imm/disp inside fingerprint.
        BYTE           iPatchLen;             // 4 for all three sites.
        const wchar_t* pszDescription;        // For log + mismatch dialog.
        const wchar_t* pszConsequence;        // What goes wrong if the patch is skipped.
    };

    constexpr WinDrvPatchSite kSites[] =
    {
        //Bug 1 -- joy loop press-branch bitmap index. CMP byte [ECX+EAX+0xeb0], BL -> [ECX+EAX+0xf78], BL.
        {
            0x11109341,
            { 0x38, 0x9C, 0x01, 0xB0, 0x0E, 0x00, 0x00, 0x00 },
            { 0x38, 0x9C, 0x01, 0x78, 0x0F, 0x00, 0x00, 0x00 },
            7, 3, 4,
            L"joy-loop press-branch bitmap index (Bug 1)",
            L"joystick buttons may cause spurious script-side key events"
        },
        //Bug 1 -- joy loop release-branch bitmap index. Same fix.
        {
            0x11109372,
            { 0x38, 0x9C, 0x01, 0xB0, 0x0E, 0x00, 0x00, 0x00 },
            { 0x38, 0x9C, 0x01, 0x78, 0x0F, 0x00, 0x00, 0x00 },
            7, 3, 4,
            L"joy-loop release-branch bitmap index (Bug 1)",
            L"joystick buttons may cause spurious script-side key events"
        },
        //Bug 2 -- trailer outer-loop bound. CMP EDI, 0x100 -> CMP EDI, 0xC8.
        {
            0x11109881,
            { 0x81, 0xFF, 0x00, 0x01, 0x00, 0x00, 0x00, 0x00 },
            { 0x81, 0xFF, 0xC8, 0x00, 0x00, 0x00, 0x00, 0x00 },
            6, 2, 4,
            L"trailer outer-loop bound (Bug 2)",
            L"controller buttons may release spuriously every frame"
        },
    };

    void FormatBytesHex(wchar_t* const pszDst, const size_t iDstCap,
                        const BYTE* const pSrc, const size_t iLen)
    {
        if (iDstCap == 0) return;
        pszDst[0] = L'\0';
        wchar_t* p = pszDst;
        wchar_t* const pEnd = pszDst + iDstCap;
        for (size_t i = 0; i < iLen && (pEnd - p) >= 4; ++i)
        {
            const int iWritten = swprintf_s(p, pEnd - p, L"%02X ", pSrc[i]);
            if (iWritten <= 0) break;
            p += iWritten;
        }
        if (p != pszDst && *(p - 1) == L' ') *(p - 1) = L'\0';
    }
}

CWinDrvPatch::CWinDrvPatch(const HWND hWndForDialog)
{
    HMODULE hWinDrv = GetModuleHandleW(L"WinDrv.dll");
    if (hWinDrv == nullptr)
    {
        GLog->Log(L"WinDrvPatch: WinDrv.dll not loaded; controller release bug remains.");
        return;
    }

    BYTE* const pActualBase = reinterpret_cast<BYTE*>(hWinDrv);
    const ptrdiff_t iDelta = pActualBase - reinterpret_cast<BYTE*>(static_cast<INT_PTR>(kPreferredImageBase));
    GLog->Logf(L"WinDrvPatch: WinDrv.dll @ 0x%p (delta %d bytes).",
               pActualBase, static_cast<int>(iDelta));

    for (const WinDrvPatchSite& Site : kSites)
    {
        BYTE* const pSite = reinterpret_cast<BYTE*>(static_cast<INT_PTR>(Site.iPreferredVA) + iDelta);
        if (memcmp(pSite, Site.aExpectedBytes, Site.iFingerprintLen) != 0)
        {
            wchar_t szExpected[64];
            wchar_t szActual[64];
            FormatBytesHex(szExpected, _countof(szExpected), Site.aExpectedBytes, Site.iFingerprintLen);
            FormatBytesHex(szActual,   _countof(szActual),   pSite,                Site.iFingerprintLen);

            GLog->Logf(L"WinDrvPatch: fingerprint MISMATCH at 0x%p (%s).", pSite, Site.pszDescription);
            GLog->Logf(L"WinDrvPatch:   expected: %s", szExpected);
            GLog->Logf(L"WinDrvPatch:   actual:   %s", szActual);

            wchar_t szMessage[1024];
            swprintf_s(szMessage,
                L"WinDrv.dll does not match the expected build for this patch.\n\n"
                L"Site:     %s\n"
                L"Address:  0x%p\n"
                L"Expected: %s\n"
                L"Actual:   %s\n\n"
                L"If this patch is skipped: %s.\n\n"
                L"Press OK to continue without this fix, or Cancel to exit.",
                Site.pszDescription, pSite, szExpected, szActual, Site.pszConsequence);

            const int iResult = MessageBoxW(hWndForDialog, szMessage,
                                            L"DeusExe \u2014 WinDrv.dll mismatch",
                                            MB_OKCANCEL | MB_ICONWARNING | MB_TOPMOST | MB_SETFOREGROUND);
            if (iResult == IDCANCEL)
            {
                GLog->Log(L"WinDrvPatch: user chose abort; exiting.");
                GIsRequestingExit = 1;
            }
            else
            {
                GLog->Log(L"WinDrvPatch: user chose continue; skipping remaining patches.");
            }
            return;
        }

        BYTE* const pTarget = pSite + Site.iPatchOff;
        DWORD iOldProt = 0;
        if (VirtualProtect(pTarget, Site.iPatchLen, PAGE_EXECUTE_READWRITE, &iOldProt) == FALSE)
        {
            const DWORD iErr = GetLastError();
            GLog->Logf(L"WinDrvPatch: VirtualProtect failed at 0x%p (GLE=%lu); stopping.",
                       pTarget, iErr);
            return;
        }

        memcpy(pTarget, Site.aReplacementBytes + Site.iPatchOff, Site.iPatchLen);

        DWORD iScratch = 0;
        if (VirtualProtect(pTarget, Site.iPatchLen, iOldProt, &iScratch) == FALSE)
        {
            const DWORD iErr = GetLastError();
            GLog->Logf(L"WinDrvPatch: VirtualProtect restore failed at 0x%p (GLE=%lu); page remains writable.",
                       pTarget, iErr);
            //Continue; the patch is in place, only the protection restore failed.
        }

        FlushInstructionCache(GetCurrentProcess(), pTarget, Site.iPatchLen);
        GLog->Logf(L"WinDrvPatch: patched %s at 0x%p.", Site.pszDescription, pTarget);
    }
}
