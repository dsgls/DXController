#pragma once

#include "Gamepad.h"
#include "FrameStats.h"

class CLauncher : private FExecHook
{
public:
    explicit CLauncher();
    CLauncher(const CLauncher&) = delete;
    CLauncher& operator=(const CLauncher&) = delete;

private:
    void ApplyAutoFOV(const size_t iSizeX, const size_t iSizeY);
    void MainLoop(UEngine * const pEngine);
    void LoadSettings();
    void ToggleBorderlessWindowedFullscreen();
    void PumpMessages(UEngine* const pEngine, const bool bMouseOverWindow, const bool bHasFocus);
    void RecordFrameStats(const double fFrameTimeMs, const double fOvershootMs);
    void LogAndResetFrameStats(FOutputDevice& Ar);

    HWND m_hWnd = NULL;

    LARGE_INTEGER m_iPerfCounterFreq = {};
    size_t m_iSizeX = 0;
    size_t m_iSizeY = 0;
    UViewport* m_pViewPort = nullptr; //If user closes window, viewport disappears before we get WM_QUIT
    UEngine* m_pEngine = nullptr; //Set once in the constructor; used by Exec() (GamepadReload) which has no other route to it
    bool m_bPrevInMenu = false;
    bool m_bPrevHasFocus = false;
    bool m_bInBorderlessFullscreenWindow = false;
    bool m_bClipHeld = false; //Whether the loop currently holds a ClipCursor rect
    CGamepad m_Gamepad;

    //Frame-stats diagnostic ring buffer (GetFrameStats exec command). Frame
    //duration is tick-to-tick time; overshoot is how far past its deadline the
    //paced wait actually woke. Reset (count back to 0) whenever GetFrameStats is run.
    static constexpr size_t kiFrameStatsRingCapacity = 1024;
    std::array<double, kiFrameStatsRingCapacity> m_FrameStatsFrameTimeMs = {};
    std::array<double, kiFrameStatsRingCapacity> m_FrameStatsOvershootMs = {};
    size_t m_iFrameStatsWriteIndex = 0;
    size_t m_iFrameStatsCount = 0; //Valid entries, caps at kiFrameStatsRingCapacity

    //Settings
    float m_fFPSLimit = 120.0f; //Because GetMaxTickRate() is float
    UBOOL m_bRawInput = TRUE;
    UBOOL m_bAutoFov = TRUE;
    UBOOL m_bBorderlessFullscreenWindow = TRUE;
    UBOOL m_bBorderlessFullscreenWindowUseAllMonitors = FALSE;
    UBOOL m_bUseSingleCPU = FALSE;

//From FExec
private:
    UBOOL Exec(const TCHAR* Cmd, FOutputDevice& Ar);

};
