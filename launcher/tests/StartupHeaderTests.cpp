#include "doctest.h"
#include "StartupHeader.h"

#include <algorithm>
#include <string>

namespace
{
    StartupHeader::Facts MakeFacts()
    {
        StartupHeader::Facts F;
        F.szLauncherVersion = L"1.2.3";
        F.szExePath = L"C:\\Games\\DeusEx\\System\\DeusEx.exe";
        F.szCommandLine = L"\"DeusEx.exe\" -changevideo";
        F.szOsBuild = L"10.0.22631";
        F.szSdlVersion = L"3.2.4";
        F.bSdlLoaded = true;
        F.szRenderDevice = L"D3DDrv.D3DRenderDevice";
        F.iViewportSizeX = 1920;
        F.iViewportSizeY = 1080;
        F.bFullscreen = true;
        F.bBorderless = false;
        F.fEffectiveFpsCap = 120.0;
        F.fMaxTickRate = 200.0f;
        F.szPadName = L"Xbox Wireless Controller";
        F.szPadGuid = L"030000005E040000E002000003090000";
        F.szPadFamily = L"XboxOne";
        F.bRawInput = true;
        F.bUseAutoFov = true;
        F.bBorderlessFullscreenWindow = false;
        F.bBorderlessFullscreenWindowAllMonitors = false;
        F.bUseSingleCPU = false;
        F.iFpsLimitIni = 120;
        return F;
    }
}

TEST_CASE("StartupHeader wraps the block in the delimiter lines")
{
    const auto Lines = StartupHeader::Build(MakeFacts());
    REQUIRE(Lines.size() >= 2);
    CHECK(Lines.front() == L"=== DXController startup ===");
    CHECK(Lines.back() == L"=== end startup ===");
}

TEST_CASE("StartupHeader emits version, exe path and command line")
{
    const auto Lines = StartupHeader::Build(MakeFacts());
    CHECK(std::find(Lines.begin(), Lines.end(), L"Launcher version: 1.2.3") != Lines.end());
    CHECK(std::find(Lines.begin(), Lines.end(), L"Exe path: C:\\Games\\DeusEx\\System\\DeusEx.exe") != Lines.end());
    CHECK(std::find(Lines.begin(), Lines.end(), L"Command line: \"DeusEx.exe\" -changevideo") != Lines.end());
}

TEST_CASE("StartupHeader emits OS build and SDL runtime with load status")
{
    const auto Lines = StartupHeader::Build(MakeFacts());
    CHECK(std::find(Lines.begin(), Lines.end(), L"OS build: 10.0.22631") != Lines.end());
    CHECK(std::find(Lines.begin(), Lines.end(), L"SDL runtime: 3.2.4 (SDL3.dll loaded=yes)") != Lines.end());
}

TEST_CASE("StartupHeader reports SDL as not loaded when unavailable")
{
    StartupHeader::Facts F = MakeFacts();
    F.bSdlLoaded = false;
    F.szSdlVersion = L"unavailable";
    const auto Lines = StartupHeader::Build(F);
    CHECK(std::find(Lines.begin(), Lines.end(), L"SDL runtime: unavailable (SDL3.dll loaded=no)") != Lines.end());
}

TEST_CASE("StartupHeader emits renderer, viewport size, fullscreen and borderless flags")
{
    const auto Lines = StartupHeader::Build(MakeFacts());
    CHECK(std::find(Lines.begin(), Lines.end(), L"Renderer: D3DDrv.D3DRenderDevice") != Lines.end());
    CHECK(std::find(Lines.begin(), Lines.end(), L"Viewport: 1920x1080 fullscreen=yes borderless=no") != Lines.end());
}

TEST_CASE("StartupHeader reports the effective FPS cap and engine max tick rate")
{
    const auto Lines = StartupHeader::Build(MakeFacts());
    CHECK(std::find(Lines.begin(), Lines.end(), L"FPS cap: effective=120.00 engine-max=200.00") != Lines.end());
}

TEST_CASE("StartupHeader reports the FPS cap as unlimited when zero or negative")
{
    StartupHeader::Facts F = MakeFacts();
    F.fEffectiveFpsCap = 0.0;
    const auto Lines = StartupHeader::Build(F);
    CHECK(std::find(Lines.begin(), Lines.end(), L"FPS cap: effective=unlimited engine-max=200.00") != Lines.end());
}

TEST_CASE("StartupHeader emits pad name, GUID and family token")
{
    const auto Lines = StartupHeader::Build(MakeFacts());
    CHECK(std::find(Lines.begin(), Lines.end(),
        L"Gamepad: Xbox Wireless Controller guid=030000005E040000E002000003090000 family=XboxOne") != Lines.end());
}

TEST_CASE("StartupHeader emits \"none\" pad facts unchanged, without special-casing")
{
    StartupHeader::Facts F = MakeFacts();
    F.szPadName = L"None";
    F.szPadGuid = L"none";
    F.szPadFamily = L"None";
    const auto Lines = StartupHeader::Build(F);
    CHECK(std::find(Lines.begin(), Lines.end(), L"Gamepad: None guid=none family=None") != Lines.end());
}

TEST_CASE("StartupHeader emits one line per WinDrvPatch site outcome, in order")
{
    StartupHeader::Facts F = MakeFacts();
    F.PatchOutcomes.push_back({ L"joy-loop press-branch bitmap index (Bug 1)", L"patched" });
    F.PatchOutcomes.push_back({ L"joy-loop release-branch bitmap index (Bug 1)", L"patched" });
    F.PatchOutcomes.push_back({ L"trailer outer-loop bound (Bug 2)", L"mismatch" });
    F.PatchOutcomes.push_back({ L"a site whose VirtualProtect failed", L"failed" });
    F.PatchOutcomes.push_back({ L"a site never attempted", L"skipped" });
    const auto Lines = StartupHeader::Build(F);
    CHECK(std::find(Lines.begin(), Lines.end(), L"WinDrvPatch: joy-loop press-branch bitmap index (Bug 1) - patched") != Lines.end());
    CHECK(std::find(Lines.begin(), Lines.end(), L"WinDrvPatch: joy-loop release-branch bitmap index (Bug 1) - patched") != Lines.end());
    CHECK(std::find(Lines.begin(), Lines.end(), L"WinDrvPatch: trailer outer-loop bound (Bug 2) - mismatch") != Lines.end());
    CHECK(std::find(Lines.begin(), Lines.end(), L"WinDrvPatch: a site whose VirtualProtect failed - failed") != Lines.end());
    CHECK(std::find(Lines.begin(), Lines.end(), L"WinDrvPatch: a site never attempted - skipped") != Lines.end());
}

TEST_CASE("StartupHeader emits no WinDrvPatch lines when the outcome list is empty")
{
    StartupHeader::Facts F = MakeFacts();
    F.PatchOutcomes.clear();
    const auto Lines = StartupHeader::Build(F);
    for (const std::wstring& Line : Lines)
    {
        CHECK(Line.find(L"WinDrvPatch:") == std::wstring::npos);
    }
}

TEST_CASE("StartupHeader emits the behavior-changing ini values")
{
    const auto Lines = StartupHeader::Build(MakeFacts());
    CHECK(std::find(Lines.begin(), Lines.end(),
        L"Ini: RawInput=yes UseAutoFOV=yes BorderlessFullscreenWindow=no(AllMonitors=no) UseSingleCPU=no FPSLimit=120") != Lines.end());
}

TEST_CASE("StartupHeader reflects BorderlessFullscreenWindow and its AllMonitors sub-flag independently")
{
    StartupHeader::Facts F = MakeFacts();
    F.bBorderlessFullscreenWindow = true;
    F.bBorderlessFullscreenWindowAllMonitors = true;
    F.bUseSingleCPU = true;
    F.iFpsLimitIni = 0;
    const auto Lines = StartupHeader::Build(F);
    CHECK(std::find(Lines.begin(), Lines.end(),
        L"Ini: RawInput=yes UseAutoFOV=yes BorderlessFullscreenWindow=yes(AllMonitors=yes) UseSingleCPU=yes FPSLimit=0") != Lines.end());
}
