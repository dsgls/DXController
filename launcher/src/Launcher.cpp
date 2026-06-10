#include "stdafx.h"
#include "ConfigOverride.h"
#include "FileManagerDeusExe.h"
#include "Misc.h"
#include "RawInput.h"
#include "LauncherDialog.h"
#include "Fixapp.h"
#include "ExecHook.h"
#include "NativeHooks.h"
#include "WinDrvPatch.h"
#include "OutputDeviceFileFlush.h"
#include "Launcher.h"

//Do not put before stdafx.h
#pragma comment(linker,"/manifestdependency:\"type='win32' name='Microsoft.Windows.Common-Controls' version='6.0.0.0' processorArchitecture='*' publicKeyToken='6595b64144ccf1df' language='*'\"")

extern "C" {wchar_t GPackage[64] = L"Launch"; } //Will be set to exe name later

INT WINAPI WinMain(HINSTANCE /*hInInstance*/, HINSTANCE /*hPrevInstance*/, LPSTR /*lpCmdLine*/, INT /*nCmdShow*/)
{
    INITCOMMONCONTROLSEX CommonControlsInfo;
    CommonControlsInfo.dwSize = sizeof(INITCOMMONCONTROLSEX);
    CommonControlsInfo.dwICC = ICC_TREEVIEW_CLASSES | ICC_LINK_CLASS;
    if (InitCommonControlsEx(&CommonControlsInfo) != TRUE)
    {
        return EXIT_FAILURE;
    }

    appStrcpy(GPackage, appPackage());

    //Init core
    FMallocWindows Malloc;
    FOutputDeviceFileFlush Log;
    FOutputDeviceWindowsError Error;
    FFeedbackContextWindows Warn;

    //If -localdata command line option present, don't use user documents for data; can't use appCmdLine() yet.
    std::unique_ptr<FFileManagerDeusExe> pFileManager(wcswcs(GetCommandLine(), L" -localdata") == nullptr ? new FFileManagerDeusExeUserDocs : new FFileManagerDeusExe);

    appInit(GPackage, GetCommandLine(), &Malloc, &Log, &Error, &Warn, pFileManager.get(), FConfigCacheIni::Factory, 1);
    GLog->Logf(L"Deus Exe: version %s.", Misc::GetVersion());

    pFileManager->AfterCoreInit();

    GIsStarted = 1;
    GIsServer = 1;
    GIsClient = !ParseParam(appCmdLine(), L"SERVER");
    GIsEditor = 0;
    GIsScriptable = 1;
    GLazyLoad = !GIsClient;

    {
        CLauncher Launcher;
    }

    //Uninit
    appPreExit();
    appExit();
    GIsStarted = 0;

    return EXIT_SUCCESS;
}

CLauncher::CLauncher()
{
    if (!Misc::SetDEP(0)) //Disable DEP for process (also need NXCOMPAT=NO); needed for Galaxy.dll
    {
        GLog->Log(L"Failed to set process DEP flags.");
    }
    if (QueryPerformanceFrequency(&m_iPerfCounterFreq) == FALSE)
    {
        GError->Log(L"Failed to query performance counter.");
    }

    int iFirstRun = 0;
    GConfig->GetInt(L"FirstRun", L"FirstRun", iFirstRun);
    const bool bFirstRun = iFirstRun < ENGINE_VERSION;
    if (bFirstRun) //Select better default options
    {
        GConfig->SetString(L"Engine.Engine", L"GameRenderDevice", L"D3DDrv.D3DRenderDevice");
        GConfig->SetString(L"WinDrv.WindowsClient", L"FullscreenColorBits", L"32");
        wchar_t szTemp[1024];
        _itow_s(GetSystemMetrics(SM_CXSCREEN), szTemp, 10);
        GConfig->SetString(L"WinDrv.WindowsClient", L"FullscreenViewportX", szTemp);
        _itow_s(GetSystemMetrics(SM_CYSCREEN), szTemp, 10);
        GConfig->SetString(L"WinDrv.WindowsClient", L"FullscreenViewportY", szTemp);
    }

    //Show options dialog
    if (ParseParam(appCmdLine(), L"changevideo") || bFirstRun)
    {
        CFixApp FixApp;
        FixApp.Show(NULL);
        if (bFirstRun)
        {
            GConfig->SetInt(L"FirstRun", L"FirstRun", ENGINE_VERSION);
        }
    }

    //Show launcher dialog
    HMONITOR hMonitor = NULL;

    const auto DoLauncherDialog = [&hMonitor]
    {
        CLauncherDialog LD;
        const auto bRet = LD.Show(NULL);
        hMonitor = LD.GetChildWindowMonitor();
        return bRet;
    };

    if (!GIsClient || ParseParam(appCmdLine(), TEXT("skipdialog")) || DoLauncherDialog()) //Here the game actually starts
    {
        LoadSettings();

        static_cast<FFileManagerDeusExe*>(GFileManager)->OnGameStart();

        if (m_bUseSingleCPU)
        {
            if (SetProcessAffinityMask(GetCurrentProcess(), 0x1) == FALSE) //Force on single CPU
            {
                GLog->Log(L"Failed to set process affinity.");
            }
        }

        //Override ini-driven engine settings without persisting them to the
        //user's DeusEx.ini / User.ini. CConfigOverride snapshots each key
        //(value, present-or-absent, file's Dirty flag) on construction and
        //restores it on destruction, so a drop-in binary + .u install needs no
        //manual ini edits. The list outlives pEngine->Init() and is torn down
        //before appExit() flushes the config cache to disk.
        std::list<CConfigOverride> ConfigOverrides;
        ConfigOverrides.emplace_back(L"Engine.Engine",        L"Console",      L"DXController.ControllerConsole");
        ConfigOverrides.emplace_back(L"Engine.Engine",        L"Root",         L"DXController.ControllerRootWindow");
        ConfigOverrides.emplace_back(L"WinDrv.WindowsClient", L"UseJoystick",  L"False");
        if (m_bRawInput) //If raw input is enabled, disable DirectInput
        {
            ConfigOverrides.emplace_back(L"WinDrv.WindowsClient", L"UseDirectInput", L"False");
        }
        if (m_bBorderlessFullscreenWindow) //In borderless mode, disable normal full screen
        {
            ConfigOverrides.emplace_back(L"WinDrv.WindowsClient", L"StartupFullscreen", L"False");
        }

        //Gamepad bindings, in User.ini. XInputExt synthesizes Joy* events from
        //the launcher's XInput shim; UseJoystick=False above just suppresses
        //DirectInput's joystick enumeration so it doesn't double up.
        const wchar_t* const pszUserIni = *static_cast<FConfigCacheIni*>(GConfig)->UserIni;
        ConfigOverrides.emplace_back(L"Extension.InputExt", L"Joy1",        L"Jump",                   pszUserIni);
        ConfigOverrides.emplace_back(L"Extension.InputExt", L"Joy2",        L"ReloadWeapon",           pszUserIni);
        ConfigOverrides.emplace_back(L"Extension.InputExt", L"Joy3",        L"ParseRightClick",        pszUserIni);
        ConfigOverrides.emplace_back(L"Extension.InputExt", L"Joy4",        L"",                       pszUserIni);
        ConfigOverrides.emplace_back(L"Extension.InputExt", L"Joy5",        L"",                       pszUserIni);
        ConfigOverrides.emplace_back(L"Extension.InputExt", L"Joy6",        L"",                       pszUserIni);
        ConfigOverrides.emplace_back(L"Extension.InputExt", L"Joy7",        L"TogglePlayerMenuWindow", pszUserIni);
        ConfigOverrides.emplace_back(L"Extension.InputExt", L"Joy8",        L"ShowMainMenu",           pszUserIni);
        ConfigOverrides.emplace_back(L"Extension.InputExt", L"Joy9",        L"",                       pszUserIni);
        ConfigOverrides.emplace_back(L"Extension.InputExt", L"Joy10",       L"",                       pszUserIni);
        ConfigOverrides.emplace_back(L"Extension.InputExt", L"Joy15",       L"",                       pszUserIni);
        ConfigOverrides.emplace_back(L"Extension.InputExt", L"Joy16",       L"",                       pszUserIni);
        ConfigOverrides.emplace_back(L"Extension.InputExt", L"JoyPovUp",    L"ActivateBelt 1",         pszUserIni);
        ConfigOverrides.emplace_back(L"Extension.InputExt", L"JoyPovLeft",  L"ActivateBelt 2",         pszUserIni);
        ConfigOverrides.emplace_back(L"Extension.InputExt", L"JoyPovRight", L"ActivateBelt 3",         pszUserIni);
        ConfigOverrides.emplace_back(L"Extension.InputExt", L"JoyPovDown",  L"ActivateBelt 4",         pszUserIni);
        ConfigOverrides.emplace_back(L"Extension.InputExt", L"JoyX",        L"Axis aStrafe",           pszUserIni);
        ConfigOverrides.emplace_back(L"Extension.InputExt", L"JoyY",        L"Axis aBaseY",            pszUserIni);
        ConfigOverrides.emplace_back(L"Extension.InputExt", L"JoyU",        L"Axis aTurn",             pszUserIni);
        ConfigOverrides.emplace_back(L"Extension.InputExt", L"JoyV",        L"Axis aLookUp",           pszUserIni);
        ConfigOverrides.emplace_back(L"Extension.InputExt", L"JoyZ",        L"",                       pszUserIni);
        ConfigOverrides.emplace_back(L"Extension.InputExt", L"JoyR",        L"",                       pszUserIni);

        //Init windowing
        InitWindowing();

        //Create log window
        const std::unique_ptr<WLog> LogWindowPtr = std::make_unique<WLog>(static_cast<FOutputDeviceFile*>(GLog)->Filename, static_cast<FOutputDeviceFile*>(GLog)->LogAr, L"GameLog");
        GLogWindow = LogWindowPtr.get(); //Yup...
        GLogWindow->OpenWindow(!GIsClient, 0);
        GLogWindow->Log(NAME_Title, LocalizeGeneral("Start"));

        GExec = this;

        //Init engine
        UClass* const pEngineClass = LoadClass<UGameEngine>(nullptr, L"ini:Engine.Engine.GameEngine", nullptr, LOAD_NoFail, nullptr);
        assert(pEngineClass);
        UEngine* const pEngine = ConstructObject<UEngine>(pEngineClass);
        assert(pEngine);
        if (!pEngine)
        {
            GError->Log(L"Engine initialization failed.");
        }

        pEngine->Init();

        GLogWindow->SetExec(pEngine); //If we directly set GExec, only our custom commands work
        GLogWindow->Log(NAME_Title, LocalizeGeneral("Run"));

        //Find window handle
        if (GIsClient)
        {
            if (pEngine->Client && pEngine->Client->Viewports.Num() > 0)
            {
                m_pViewPort = pEngine->Client->Viewports(0);
                m_hWnd = static_cast<const HWND>(m_pViewPort->GetWindow());
            }
            else
            {
                GLog->Log(L"Unable to get viewport.");
            }
        }

        //Move window to launcher's monitor
        if (hMonitor != NULL && m_hWnd)
        {
            Misc::CenterWindowOnMonitor(m_hWnd, hMonitor);
        }

        if (m_bBorderlessFullscreenWindow)
        {
            ToggleBorderlessWindowedFullscreen();
        }

        //Initialize raw input
        if (m_bRawInput && m_hWnd)
        {
            if (!RegisterRawInput(m_hWnd))
            {
                GError->Log(L"Raw input: Failed to register raw input device.");
            }
        }

        if (GIsClient && m_bAutoFov)
        {
            RECT r;
            GetClientRect(m_hWnd, &r);
            int iSizeX = r.right - r.left;
            int iSizeY = r.bottom - r.top;
            ApplyAutoFOV(iSizeX, iSizeY);
        }

        //Apply WinDrv binary patches BEFORE creating CNativeHooks so that any
        //mismatch dialog runs before we start mutating GNatives[]. m_hWnd is
        //assigned earlier in this constructor (right after pEngine->Init); it
        //will be NULL on a dedicated server, which the dialog tolerates.
        CWinDrvPatch WinDrvPatch(m_hWnd);

        //Initialize native hooks
        CNativeHooks NativeHooks(PROJECTNAME);

        //Main loop
        GIsRunning = 1;
        if (!GIsRequestingExit)
        {
            MainLoop(pEngine);
        }
        GIsRunning = 0;

        if (GIsClient) //Restore the global cursor state the main loop mutated (ClipCursor/ShowCursor)
        {
            //Windows reclaims per-process cursor state on process exit, but a fullscreen
            //DX app that exits while the cursor is clipped/hidden can leave the session's
            //cursor wedged (clipped to the old rect, or hidden until reboot), so release it
            //explicitly here.
            ClipCursor(NULL); //Drop any clip rect set in the loop; never set elsewhere
            while (ShowCursor(TRUE) < 0) {} //Undo any net ShowCursor(FALSE) so the cursor is visible
        }

        GLogWindow->Log(NAME_Title, LocalizeGeneral("Exit"));
    }

}

void CLauncher::ApplyAutoFOV(const size_t iSizeX, const size_t iSizeY)
{
    assert(m_iSizeX != iSizeX || m_iSizeY != iSizeY);
    assert(m_pViewPort);
    const float fFOV = Misc::CalcFOV(iSizeX, iSizeY);
    wchar_t szCmd[12];
    swprintf_s(szCmd, L"fov %6.3f", fFOV);

    m_pViewPort->Exec(szCmd);
    m_iSizeX = iSizeX;
    m_iSizeY = iSizeY;
}

void CLauncher::MainLoop(UEngine* const pEngine)
{
    assert(pEngine);

    LARGE_INTEGER iOldTime;
    if(!QueryPerformanceCounter(&iOldTime)) //Initial time
    {
        return;
    }

    while (GIsRunning && !GIsRequestingExit)
    {
        LARGE_INTEGER iTime;
        QueryPerformanceCounter(&iTime);
        const float fDeltaTime = (iTime.QuadPart - iOldTime.QuadPart) / static_cast<float>(m_iPerfCounterFreq.QuadPart);

        //Lock game update speed to fps limit
        const bool bTickThisIteration =
            (m_fFPSLimit == 0.0f || fDeltaTime >= 1.0f / m_fFPSLimit) &&
            (pEngine->GetMaxTickRate() == 0.0f || fDeltaTime >= 1.0f / pEngine->GetMaxTickRate());
        if(bTickThisIteration)
        {
            pEngine->Tick(fDeltaTime);
            if(GWindowManager)
            {
                GWindowManager->Tick(fDeltaTime);
            }
            iOldTime = iTime;
        }

        if(pEngine->Client->Viewports.Num() == 0) //If user closes window, viewport disappears before we get WM_QUIT
        {
            m_pViewPort = nullptr;
        }

        POINT CursorPos;
        GetCursorPos(&CursorPos);
        const bool bMouseOverWindow = WindowFromPoint(CursorPos) == m_hWnd;
        const bool bHasFocus = GetFocus() == m_hWnd;
        //Poll at tick rate, not main-loop rate: the engine accumulates IST_Axis events
        //between ticks (same as mouse WM_INPUT deltas below), so emitting the absolute
        //stick value many times per tick produced per-tick turn = value * polls_per_tick.
        //Scheduling jitter in polls_per_tick caused jerky right-stick look.
        if(bTickThisIteration)
        {
            m_XInput.Poll(pEngine, m_pViewPort, bHasFocus);
        }
        if(m_pViewPort)
        {
            assert(m_hWnd);

            RECT rClientArea;
            GetClientRect(m_hWnd, &rClientArea);
            std::array<POINT, 2> ClientPoints = { { {rClientArea.left, rClientArea.top}, {rClientArea.right, rClientArea.bottom} } };
            MapWindowPoints(m_hWnd, NULL, ClientPoints.data(), ClientPoints.size());
            const RECT rClientScreen = { ClientPoints[0].x, ClientPoints[0].y, ClientPoints[1].x, ClientPoints[1].y };

            RECT rr;
            GetWindowRect(m_hWnd, &rr);

            //PeekMessage() doesn't get WM_SIZE
            //Default/desired FOV check is so we don't change FOV while zoomed in
            if (m_bAutoFov && m_pViewPort->Actor->DesiredFOV == m_pViewPort->Actor->DefaultFOV)
            {
                const size_t iSizeX = static_cast<size_t>(m_pViewPort->SizeX);
                const size_t iSizeY = static_cast<size_t>(m_pViewPort->SizeY);

                //Handle auto FOV
                if(m_iSizeX != iSizeX  || m_iSizeY != iSizeY)
                {
                    ApplyAutoFOV(iSizeX, iSizeY);
                }
            }
            
            //pEngine->Client->Viewports(0)->SetMouseCapture()'s cursor centering doesn't work with raw input.
            //Why doesn't it work? Because we block WM_MOUSEMOVE messages, which the game apparently uses to center the cursor.
            //SetCursorPos() still works, though, which I'd assume the game uses; ClipCursor() didn't exist until Win2000.
            //Also, if you force the game to turn off mouse centering, the camera doesn't work; does it use the WM_MOUSEMOVE messages generated by SetCursorPos() to actually move the camera?

            //Issue: using raw input, in full-screen mode you can move the cursor around while controlling the camera, if you then open the menu and slightly move the mouse
            //The game's cursor will snap to the Windows mouse cursor position.
            //Theory as to why: SetMouseCapture() without clipping resets the mouse position to previous (looking at headers / UT X driver code).
            //In full-screen mode this is not done when going to the menu (observed in Windows Input mode, cursor keeps being centered).
            //Because the game uses relative messages for menu mouse input (MouseDelta(), not MousePosition()) this doesn't matter.

            //Other observed behavior in Windows Input mode, running windowed: mouse is clipped to window dimensions + centered in menu mode (like in camera mode)
            //Until alt+tab or mission start, at which point it's not clipped and window can be resized

            //Forcing mouse to be centered in menu mode makes it feel weird, doesn't match Windows mouse cursor movements

            /* Tests
            1. Does menu cursor track Windows cursor nicely
            2. Can cursor immediately leave window when menu first pops up (who cares)
            3. Does resize cursor pop up on window edges
            4. When alt+tabbing while not in a menu, make sure mouse isn't clipped to game window area
            5. Both windowed and full screen: when having controlled the camera and then entering a menu, the mouse should either be centered or in the position where it last was.
               When touching the mouse, it should not teleport due to having been moved in camera mode.
            5a. Still happens in raw input + windowed mode when entering menu without having first moved mouse, acceptable.
            6. When alt+tabbing and not in a menu, make sure camera isn't controlled by mouse movements until the window is clicked
            7. Make sure Windows mouse cursor is not visible (other than during testing)
            8. Make sure preferences window is usable (no hidden cursor) and that it doesn't pop up a phantom cursor in menu mode
            9. When looking around with preferences window on top, cursor doesn't appear
            10. In fullscreen mode, when rapidly clicking, window isn't minimized
            11. In two-monitor fullscreen make sure mouse can't move outside of monitor
            */

            const APlayerPawnExt* const pPlayer = static_cast<APlayerPawnExt*>(m_pViewPort->Actor);
            assert(pPlayer);
            XRootWindow* const pRoot = static_cast<XRootWindow*>(pPlayer->rootWindow);
            assert(pRoot);

            const bool bInMenu = pRoot->IsMouseGrabbed()!=0;

            if (m_bRawInput && m_pViewPort && m_pViewPort->IsFullscreen())
            {
                if (bInMenu && !m_bPrevInMenu) //Fixes that in fullscreen mode, windows mouse cursor pos isn't matched to DX menu cursor
                {
                    float fX, fY;
                    pRoot->GetRootCursorPos(&fX, &fY);
                    POINT p{static_cast<int>(fX), static_cast<int>(fY)};
                    ClientToScreen(m_hWnd, &p);
                    SetCursorPos(p.x, p.y);
                }
                ClipCursor(&rClientScreen); //Fixed being able to move cursor outside of fullscreen game on dual monitor systems
            }
            m_bPrevInMenu = bInMenu;

            const bool bMouseInClientRect = PtInRect(&rClientScreen, CursorPos)!=0; //This makes sure resize cursor isn't hidden
            const bool bCaptured = GetCapture() == m_hWnd;
            const bool bHideForPad = m_XInput.IsPadActive();
            if (bHideForPad || (bMouseInClientRect && (bMouseOverWindow || bCaptured))) //Want to show cursor when over preferences window when we don't have focus, but not when it's under the window if we do; force-hide while pad-active
            {
                while(ShowCursor(FALSE) > 0); //Get rid of double mouse cursors when game doesn't clip it
            }
            else
            {
                while(ShowCursor(TRUE) <= 0);
            }
        }

        MSG Msg;
        while (PeekMessage(&Msg, NULL, 0, 0, PM_REMOVE))
        {
            bool bSkipMessage = false;

            switch (Msg.message)
            {
            case WM_QUIT:
                GIsRequestingExit = 1;
                break;

            case WM_MOUSEMOVE:
                if (m_pViewPort && m_bRawInput)
                {
                    //Mouse-activity detection deliberately does NOT live here: WM_MOUSEMOVE
                    //also fires for synthetic cursor moves (WinDrv's capture-release position
                    //restore on menu open, ClipCursor clamps, our fullscreen SetCursorPos
                    //sync). Treating those as user activity flipped IsPadActive() false and
                    //fed the move below, briefly unhiding the cursor and stealing menu focus
                    //on gameplay->menu transitions. Physical motion is detected from raw
                    //WM_INPUT deltas instead (NotifyMouseActivity in the WM_INPUT branch).
                    const int iXPos = GET_X_LPARAM(Msg.lParam);
                    const int iYPos = GET_Y_LPARAM(Msg.lParam);
                    if (bMouseOverWindow && !m_XInput.IsPadActive()) //Because preferences window defers mousemove calls to us, somehow
                    {
                        //Use WM_MOUSEMOVE to control menu cursor
                        pEngine->MousePosition(m_pViewPort, 0, static_cast<float>(iXPos), static_cast<float>(iYPos));
                    }
                    bSkipMessage = true;
                }
                break;

            case WM_KEYDOWN:
            case WM_SYSKEYDOWN:
                if (m_bBorderlessFullscreenWindow && Msg.wParam == VK_RETURN && (HIWORD(Msg.lParam) & KF_ALTDOWN)) //User hits alt+enter
                {
                    ToggleBorderlessWindowedFullscreen();
                    bSkipMessage = true;
                }
                break;


            case WM_INPUT:
            {
                //Use raw input to control camera
                if (m_pViewPort && bHasFocus)
                {
                    RAWINPUT raw;
                    UINT rawSize = sizeof(raw);
                    GetRawInputData(reinterpret_cast<HRAWINPUT>(Msg.lParam), RID_INPUT, &raw, &rawSize, sizeof(RAWINPUTHEADER));

                    //Raw deltas are physical-motion ground truth (synthetic SetCursorPos
                    //moves never generate WM_INPUT), so this is where mouse activity is
                    //detected for the pad-vs-mouse active-source signal.
                    m_XInput.NotifyMouseActivity(raw.data.mouse.lLastX, raw.data.mouse.lLastY);

                    const float fDeltaX = static_cast<float>(raw.data.mouse.lLastX);
                    const float fDeltaY = static_cast<float>(raw.data.mouse.lLastY);
                    if(fDeltaX != 0.0f)
                    {
                        pEngine->InputEvent(m_pViewPort, EInputKey::IK_MouseX, EInputAction::IST_Axis, fDeltaX);
                    }
                    if(fDeltaY != 0.0f)
                    {
                        pEngine->InputEvent(m_pViewPort, EInputKey::IK_MouseY, EInputAction::IST_Axis, -fDeltaY);
                    }

                    if (raw.data.mouse.ulButtons & RI_MOUSE_BUTTON_4_UP)
                    {
                        pEngine->InputEvent(m_pViewPort, EInputKey::IK_Unknown05, EInputAction::IST_Release);
                    }
                    else if (raw.data.mouse.ulButtons & RI_MOUSE_BUTTON_4_DOWN)
                    {
                        pEngine->InputEvent(m_pViewPort, EInputKey::IK_Unknown05, EInputAction::IST_Press);
                    }

                    if (raw.data.mouse.ulButtons & RI_MOUSE_BUTTON_5_UP)
                    {
                        pEngine->InputEvent(m_pViewPort, EInputKey::IK_Unknown06, EInputAction::IST_Release);
                    }
                    else if (raw.data.mouse.ulButtons & RI_MOUSE_BUTTON_5_DOWN)
                    {
                        pEngine->InputEvent(m_pViewPort, EInputKey::IK_Unknown06, EInputAction::IST_Press);
                    }

                    bSkipMessage = true;
                }
            }
                break;
            }

            if(!bSkipMessage)
            {
                TranslateMessage(&Msg);
                DispatchMessage(&Msg);
            }
        }
    }

}

void CLauncher::LoadSettings()
{
    assert(GConfig);
    int iFPSLimit = static_cast<int>(m_fFPSLimit);
    GConfig->GetInt(PROJECTNAME, L"FPSLimit", iFPSLimit);
    m_fFPSLimit = static_cast<float>(iFPSLimit);

    GConfig->GetBool(PROJECTNAME, L"RawInput", m_bRawInput);
    GConfig->GetBool(PROJECTNAME, L"UseAutoFOV", m_bAutoFov);
    GConfig->GetBool(PROJECTNAME, L"BorderlessFullscreenWindow", m_bBorderlessFullscreenWindow);
    GConfig->GetBool(PROJECTNAME, L"BorderlessFullscreenWindowAllMonitors", m_bBorderlessFullscreenWindowUseAllMonitors);
    GConfig->GetBool(PROJECTNAME, L"UseSingleCPU", m_bUseSingleCPU);
}

void CLauncher::ToggleBorderlessWindowedFullscreen()
{
    Misc::SetBorderlessFullscreen(m_hWnd, m_bInBorderlessFullscreenWindow ? Misc::BorderlessFullscreenMode::NONE : m_bBorderlessFullscreenWindowUseAllMonitors ? Misc::BorderlessFullscreenMode::ALL_MONITORS : Misc::BorderlessFullscreenMode::CURRENT_MONITOR);
    m_bInBorderlessFullscreenWindow = !m_bInBorderlessFullscreenWindow;
}

UBOOL CLauncher::Exec(const TCHAR * Cmd, FOutputDevice & Ar)
{
    if (ParseCommand(&Cmd, TEXT("ToggleFullScreen")))
    {
        assert(m_pViewPort);
        if (m_bBorderlessFullscreenWindow) //In borderless mode, prevent switch to 'real' fullscreen
        {
            ToggleBorderlessWindowedFullscreen();

            return TRUE;
        }

        return FALSE;
    }
    else if (ParseCommand(&Cmd, TEXT("SetRes")))
    {
        if (m_bInBorderlessFullscreenWindow) //Block resolution changes in borderless fullscreen mode
        {
            return TRUE;
        }
        return FALSE;
    }
    else if (ParseCommand(&Cmd, TEXT("XInputReload")))
    {
        m_XInput.Reload();
        Ar.Logf(TEXT("XInput: settings reloaded from [DXController.ControllerSettings]"));
        return TRUE;
    }
    else if (ParseCommand(&Cmd, TEXT("XInputSampleCurve")))
    {
        wchar_t szSide[8] = {};
        if (!ParseToken(Cmd, szSide, _countof(szSide), 0))
        {
            return TRUE;
        }
        CXInput::EStick eStick;
        if      (_wcsicmp(szSide, L"Left")  == 0) eStick = CXInput::EStick::Left;
        else if (_wcsicmp(szSide, L"Right") == 0) eStick = CXInput::EStick::Right;
        else                                      return TRUE;

        const int iCount = appAtoi(Cmd);
        m_XInput.SampleCurve(eStick, iCount, Ar);
        return TRUE;
    }
    else if (ParseCommand(&Cmd, TEXT("XInputGetRawMag")))
    {
        m_XInput.GetRawStickMags(Ar);
        return TRUE;
    }
    else
    {
        return FExecHook::Exec(Cmd, Ar);
    }
}
