#include "StartupHeader.h"

namespace
{
    const wchar_t* YesNo(const bool b) { return b ? L"yes" : L"no"; }

    //Hand-rolled rather than sprintf-family, to keep this unit free of any CRT
    //formatting dependency - same reasoning as LogTime's/LogPath's FWriter.
    std::wstring FormatInt(long long iValue)
    {
        const bool bNeg = iValue < 0;
        unsigned long long iAbs = bNeg ? static_cast<unsigned long long>(-iValue) : static_cast<unsigned long long>(iValue);
        wchar_t Digits[24];
        int iDigitCount = 0;
        do
        {
            Digits[iDigitCount++] = static_cast<wchar_t>(L'0' + (iAbs % 10));
            iAbs /= 10;
        } while (iAbs > 0);

        std::wstring sz;
        if (bNeg) sz += L'-';
        while (iDigitCount > 0) sz += Digits[--iDigitCount];
        return sz;
    }

    //Fixed two decimal places, half-up rounded on the third digit - plenty for
    //a diagnostic line (frame rates, not measurements needing exact rounding).
    std::wstring FormatFixed2(const double f)
    {
        const bool bNeg = f < 0.0;
        const double fAbs = bNeg ? -f : f;
        long long iWhole = static_cast<long long>(fAbs);
        long long iFrac = static_cast<long long>((fAbs - static_cast<double>(iWhole)) * 100.0 + 0.5);
        if (iFrac >= 100)
        {
            iFrac -= 100;
            iWhole += 1;
        }

        std::wstring sz;
        if (bNeg) sz += L'-';
        sz += FormatInt(iWhole);
        sz += L'.';
        if (iFrac < 10) sz += L'0';
        sz += FormatInt(iFrac);
        return sz;
    }
}

std::vector<std::wstring> StartupHeader::Build(const Facts& F)
{
    std::vector<std::wstring> Lines;

    Lines.push_back(L"=== DXController startup ===");

    Lines.push_back(L"Launcher version: " + F.szLauncherVersion);
    Lines.push_back(L"Exe path: " + F.szExePath);
    Lines.push_back(L"Command line: " + F.szCommandLine);
    Lines.push_back(L"OS build: " + F.szOsBuild);

    {
        std::wstring sz = L"SDL runtime: ";
        sz += F.szSdlVersion;
        sz += L" (SDL3.dll loaded=";
        sz += YesNo(F.bSdlLoaded);
        sz += L")";
        Lines.push_back(sz);
    }

    Lines.push_back(L"Renderer: " + F.szRenderDevice);

    {
        std::wstring sz = L"Viewport: ";
        sz += FormatInt(F.iViewportSizeX);
        sz += L"x";
        sz += FormatInt(F.iViewportSizeY);
        sz += L" fullscreen=";
        sz += YesNo(F.bFullscreen);
        sz += L" borderless=";
        sz += YesNo(F.bBorderless);
        Lines.push_back(sz);
    }

    {
        std::wstring sz = L"FPS cap: effective=";
        sz += (F.fEffectiveFpsCap > 0.0) ? FormatFixed2(F.fEffectiveFpsCap) : std::wstring(L"unlimited");
        sz += L" engine-max=";
        sz += FormatFixed2(F.fMaxTickRate);
        Lines.push_back(sz);
    }

    {
        std::wstring sz = L"Gamepad: ";
        sz += F.szPadName;
        sz += L" guid=";
        sz += F.szPadGuid;
        sz += L" family=";
        sz += F.szPadFamily;
        Lines.push_back(sz);
    }

    for (const SPatchSiteOutcome& Site : F.PatchOutcomes)
    {
        std::wstring sz = L"WinDrvPatch: ";
        sz += Site.szDescription;
        sz += L" - ";
        sz += Site.szOutcome;
        Lines.push_back(sz);
    }

    {
        std::wstring sz = L"Ini: RawInput=";
        sz += YesNo(F.bRawInput);
        sz += L" UseAutoFOV=";
        sz += YesNo(F.bUseAutoFov);
        sz += L" BorderlessFullscreenWindow=";
        sz += YesNo(F.bBorderlessFullscreenWindow);
        sz += L"(AllMonitors=";
        sz += YesNo(F.bBorderlessFullscreenWindowAllMonitors);
        sz += L") UseSingleCPU=";
        sz += YesNo(F.bUseSingleCPU);
        sz += L" FPSLimit=";
        sz += FormatInt(F.iFpsLimitIni);
        Lines.push_back(sz);
    }

    Lines.push_back(L"=== end startup ===");

    return Lines;
}
