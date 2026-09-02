#include "stdafx.h"
#include "Misc.h"

bool Misc::SetDEP(const DWORD dwFlags)
{
        const HMODULE hMod = GetModuleHandleW(L"Kernel32.dll");
        if(!hMod)
        {
            return false;
        }

        const auto procSet = reinterpret_cast<BOOL(WINAPI * const)(DWORD)>(GetProcAddress(hMod, "SetProcessDEPPolicy"));
        if(!procSet)
        {
            return false;
        }

        return procSet(dwFlags)!=FALSE;
}

/**
Returns game directory in user documents directory
*/
void Misc::GetUserDocsDir(wchar_t(&pszBuf)[MAX_PATH])
{
    SHGetFolderPath(NULL,CSIDL_PERSONAL,NULL,NULL,pszBuf);
    PathAppend(pszBuf, L"Deus Ex");
}

/**
Returns System directory in game directory
*/
void Misc::GetGameSystemDir(wchar_t(&pszBuf)[MAX_PATH])
{
    GetModuleFileName(NULL,pszBuf,MAX_PATH);
    PathRemoveFileSpec(pszBuf);
}

float Misc::GetDefaultFOV()
{
    float fFOV = 75.0;
    GConfig->GetFloat(L"Engine.PlayerPawn", L"DesiredFOV", fFOV, L"DefUser.ini");
    return fFOV;
}

float Misc::CalcFOV(const size_t iResX, const size_t iResY)
{
    constexpr float fDeg2Rad = static_cast<float>(M_PI) / 180.0f;
    constexpr float fDefaultAspect = 4.0f / 3.0f;
    const float fAspect = static_cast<float>(iResX) / iResY;

    const float fFov = atanf(tanf(0.5f*GetDefaultFOV()*fDeg2Rad)*(fAspect / fDefaultAspect)) / fDeg2Rad*2.0f;
    return fFov;
}

void Misc::CenterWindowOnMonitor(const HWND hWnd, const HMONITOR hMonitor)
{
    //hWnd is the engine's viewport window and hMonitor comes from the launcher
    //dialog, so neither is ours to assume. Both structs stay uninitialized when
    //their query fails, which would move the window to garbage coordinates.
    MONITORINFO mi;
    mi.cbSize = sizeof(mi);
    RECT r;
    if(!hWnd || !hMonitor || !GetMonitorInfo(hMonitor, &mi) || !GetWindowRect(hWnd, &r))
    {
        GLog->Log(L"Unable to center window on monitor.");
        return;
    }

    const int iW = r.right - r.left;
    const int iH = r.bottom - r.top;

    //Center window on monitor
    const int iX = (mi.rcMonitor.left + mi.rcMonitor.right - iW) / 2;
    const int iY = (mi.rcMonitor.top + mi.rcMonitor.bottom - iH) / 2;
    MoveWindow(hWnd, iX, iY, iW, iH, FALSE);
#ifdef _DEBUG
    //Check window is still same size
    RECT r2;
    GetWindowRect(hWnd, &r2);
    assert(r.right - r.left == r2.right - r2.left);
    assert(r.bottom - r.top == r2.bottom - r2.top);
#endif
}

void Misc::SetBorderlessFullscreen(const HWND hWnd, const BorderlessFullscreenMode Mode)
{
    if(!hWnd)
    {
        //Reachable: the toggle runs off m_hWnd, which stays null when the engine
        //never handed the launcher a viewport window.
        GLog->Log(L"Unable to toggle borderless fullscreen: no window.");
        return;
    }

    LONG_PTR Style = GetWindowLongPtr(hWnd, GWL_STYLE);

    if (Mode != BorderlessFullscreenMode::NONE)
    {
        Style &= ~(WS_CAPTION | WS_THICKFRAME);
        SetWindowLongPtr(hWnd, GWL_STYLE, Style);

        //The whole virtual screen, also the fallback for CURRENT_MONITOR:
        //MonitorFromWindow's flag 0 is MONITOR_DEFAULTTONULL, so an off-screen
        //window yields no monitor and leaves the MONITORINFO uninitialized.
        int iX = GetSystemMetrics(SM_XVIRTUALSCREEN);
        int iY = GetSystemMetrics(SM_YVIRTUALSCREEN);
        int iW = GetSystemMetrics(SM_CXVIRTUALSCREEN);
        int iH = GetSystemMetrics(SM_CYVIRTUALSCREEN);

        if (Mode == BorderlessFullscreenMode::CURRENT_MONITOR)
        {
            MONITORINFO mi;
            mi.cbSize = sizeof(mi);
            if (GetMonitorInfo(MonitorFromWindow(hWnd, 0), &mi))
            {
                iX = mi.rcMonitor.left;
                iY = mi.rcMonitor.top;
                iW = mi.rcMonitor.right - mi.rcMonitor.left;
                iH = mi.rcMonitor.bottom - mi.rcMonitor.top;
            }
            else
            {
                GLog->Log(L"Borderless fullscreen: window is on no monitor, using the whole virtual screen.");
            }
        }

        SetWindowPos(hWnd, NULL, iX, iY, iW, iH, SWP_FRAMECHANGED);
    }
    else
    {
        Style |= (WS_CAPTION | WS_THICKFRAME);
        SetWindowLongPtr(hWnd, GWL_STYLE, Style);
        SetWindowPos(hWnd, NULL, 0, 0, 0, 0, SWP_NOSIZE | SWP_NOMOVE | SWP_FRAMECHANGED);
    }
}
