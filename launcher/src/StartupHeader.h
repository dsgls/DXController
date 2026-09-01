#pragma once

#include <string>
#include <vector>

// Pure assembly of the startup diagnostic block (design doc sec3.4): a plain
// facts struct in, the header's log lines out, delimited "=== DXController
// startup ===" ... "=== end startup ===". CLauncher's constructor gathers the
// facts (Win32 queries, GConfig reads, the CGamepad/CWinDrvPatch accessors)
// and logs each returned line via GLog - no syscalls, no engine headers here.
// See development.md's pure-unit-layer entry.
namespace StartupHeader
{
    //One CWinDrvPatch site: its description (matches the at-patch-time log
    //line) and its outcome ("patched" / "mismatch" / "skipped" / "dll-absent").
    struct SPatchSiteOutcome
    {
        std::wstring szDescription;
        std::wstring szOutcome;
    };

    struct Facts
    {
        std::wstring szLauncherVersion; //Misc::GetVersion()
        std::wstring szExePath;         //GetModuleFileNameW
        std::wstring szCommandLine;     //GetCommandLineW

        std::wstring szOsBuild;    //"<major>.<minor>.<build>" from RtlGetVersion (GetVersionExW lies under compatibility shims)
        std::wstring szSdlVersion; //SDL_GetVersion(), formatted "<major>.<minor>.<micro>"; caller's placeholder when SDL never loaded
        bool bSdlLoaded = false;   //Whether SDL3.dll loaded at all (CGamepad::IsSdlAvailable())

        std::wstring szRenderDevice; //GConfig Engine.Engine GameRenderDevice
        int  iViewportSizeX = 0;
        int  iViewportSizeY = 0;
        bool bFullscreen = false;
        bool bBorderless = false;    //Current borderless-fullscreen-window state, not the ini setting (see below)

        double fEffectiveFpsCap = 0.0; //The loop's effective cap this frame; <= 0 means unlimited
        float  fMaxTickRate = 0.0f;    //pEngine->GetMaxTickRate() at the same moment

        std::wstring szPadName;   //CGamepad's active-pad query; "None" when no pad is active
        std::wstring szPadGuid;   //"none" when no pad is active
        std::wstring szPadFamily; //CGamepad::GetInfo()

        std::vector<SPatchSiteOutcome> PatchOutcomes; //CWinDrvPatch::GetSiteOutcomes(), in site order; may be empty

        //Behavior-changing ini values (design doc sec3.4).
        bool bRawInput = false;
        bool bUseAutoFov = false;
        bool bBorderlessFullscreenWindow = false;
        bool bBorderlessFullscreenWindowAllMonitors = false;
        bool bUseSingleCPU = false;
        int  iFpsLimitIni = 0;
    };

    //One line per fact (plus the two delimiter lines); WinDrvPatch lines repeat
    //once per PatchOutcomes entry, in order, and are omitted entirely when that
    //list is empty. Caller logs each returned line (e.g. GLog->Logf(L"%s", ...)).
    std::vector<std::wstring> Build(const Facts& F);
}
