#include "stdafx.h"
#include "BytePatch.h"
#include "BytePatchSites.h"

namespace
{
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

CBytePatch::CBytePatch(const HWND hWndForDialog)
{
    //Marks every site from (iFromModule, iFromSite) to the end of the table
    //"skipped". Called after a mismatch or a VirtualProtect failure has already
    //recorded the site that actually stopped us.
    const auto SkipRest = [this](const size_t iFromModule, const size_t iFromSite)
    {
        for (size_t iM = iFromModule; iM < _countof(kPatchModules); ++iM)
        {
            const size_t iStart = (iM == iFromModule) ? iFromSite : 0;
            for (size_t iS = iStart; iS < kPatchModules[iM].iSiteCount; ++iS)
            {
                m_SiteOutcomes.push_back({ kPatchModules[iM].pszModule,
                                           kPatchModules[iM].pSites[iS].pszDescription,
                                           L"skipped" });
            }
        }
    };

    for (size_t iModuleIndex = 0; iModuleIndex < _countof(kPatchModules); ++iModuleIndex)
    {
        const SPatchModule& Module = kPatchModules[iModuleIndex];

        const HMODULE hModule = GetModuleHandleW(Module.pszModule);
        if (hModule == nullptr)
        {
            GLog->Logf(L"BytePatch: %s not loaded; its fixes remain unapplied.", Module.pszModule);
            m_SiteOutcomes.push_back({ Module.pszModule, nullptr, L"dll-absent" });
            continue;
        }

        BYTE* const pActualBase = reinterpret_cast<BYTE*>(hModule);
        const ptrdiff_t iDelta = pActualBase - reinterpret_cast<BYTE*>(static_cast<INT_PTR>(Module.iPreferredBase));
        GLog->Logf(L"BytePatch: %s @ 0x%p (delta %d bytes).",
                   Module.pszModule, pActualBase, static_cast<int>(iDelta));

        for (size_t iSiteIndex = 0; iSiteIndex < Module.iSiteCount; ++iSiteIndex)
        {
            const SPatchSite& Site = Module.pSites[iSiteIndex];
            BYTE* const pSite = reinterpret_cast<BYTE*>(static_cast<INT_PTR>(Site.iPreferredVA) + iDelta);
            if (memcmp(pSite, Site.pExpected, Site.iLen) != 0)
            {
                wchar_t szExpected[128];
                wchar_t szActual[128];
                FormatBytesHex(szExpected, _countof(szExpected), Site.pExpected, Site.iLen);
                FormatBytesHex(szActual,   _countof(szActual),   pSite,          Site.iLen);

                GLog->Logf(L"BytePatch: fingerprint MISMATCH at 0x%p (%s: %s).",
                           pSite, Module.pszModule, Site.pszDescription);
                GLog->Logf(L"BytePatch:   expected: %s", szExpected);
                GLog->Logf(L"BytePatch:   actual:   %s", szActual);

                wchar_t szTitle[128];
                swprintf_s(szTitle, L"DeusExe — %s mismatch", Module.pszModule);

                wchar_t szMessage[1024];
                swprintf_s(szMessage,
                    L"%s does not match the expected build for this patch.\n\n"
                    L"Site:     %s\n"
                    L"Address:  0x%p\n"
                    L"Expected: %s\n"
                    L"Actual:   %s\n\n"
                    L"If this patch is skipped: %s.\n\n"
                    L"Press OK to continue without this fix, or Cancel to exit.",
                    Module.pszModule, Site.pszDescription, pSite, szExpected, szActual,
                    Site.pszConsequence);

                const int iResult = MessageBoxW(hWndForDialog, szMessage, szTitle,
                                                MB_OKCANCEL | MB_ICONWARNING | MB_TOPMOST | MB_SETFOREGROUND);
                if (iResult == IDCANCEL)
                {
                    GLog->Log(L"BytePatch: user chose abort; exiting.");
                    GIsRequestingExit = 1;
                }
                else
                {
                    GLog->Log(L"BytePatch: user chose continue; skipping remaining patches.");
                }
                m_SiteOutcomes.push_back({ Module.pszModule, Site.pszDescription, L"mismatch" });
                SkipRest(iModuleIndex, iSiteIndex + 1);
                return;
            }

            DWORD iOldProt = 0;
            if (VirtualProtect(pSite, Site.iLen, PAGE_EXECUTE_READWRITE, &iOldProt) == FALSE)
            {
                const DWORD iErr = GetLastError();
                GLog->Logf(L"BytePatch: VirtualProtect failed at 0x%p (GLE=%lu); stopping.",
                           pSite, iErr);
                //"failed" only for the site that actually failed; the sites after it
                //were never attempted, which is a different thing in a bug report.
                m_SiteOutcomes.push_back({ Module.pszModule, Site.pszDescription, L"failed" });
                SkipRest(iModuleIndex, iSiteIndex + 1);
                return;
            }

            memcpy(pSite, Site.pReplacement, Site.iLen);

            DWORD iScratch = 0;
            if (VirtualProtect(pSite, Site.iLen, iOldProt, &iScratch) == FALSE)
            {
                const DWORD iErr = GetLastError();
                GLog->Logf(L"BytePatch: VirtualProtect restore failed at 0x%p (GLE=%lu); page remains writable.",
                           pSite, iErr);
                //Continue; the patch is in place, only the protection restore failed.
            }

            FlushInstructionCache(GetCurrentProcess(), pSite, Site.iLen);
            GLog->Logf(L"BytePatch: patched %s at 0x%p (%s).",
                       Site.pszDescription, pSite, Module.pszModule);
            m_SiteOutcomes.push_back({ Module.pszModule, Site.pszDescription, L"patched" });
        }
    }
}
