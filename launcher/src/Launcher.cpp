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
#include "CursorPolicy.h"
#include "CrashRecord.h"
#include "FramePacing.h"
#include "LogPath.h"
#include "StartupHeader.h"
#include "Launcher.h"

#include <SDL3/SDL.h> //Guarded by CGamepad::IsSdlAvailable() everywhere below -- see Gamepad.cpp's InitSdl() comment on why an unguarded call can fault

//Do not put before stdafx.h
#pragma comment(linker,"/manifestdependency:\"type='win32' name='Microsoft.Windows.Common-Controls' version='6.0.0.0' processorArchitecture='*' publicKeyToken='6595b64144ccf1df' language='*'\"")
#pragma comment(lib, "winmm.lib") //timeBeginPeriod, for the fallback timer path only

//Only in the Win10 1803 and newer SDKs; older kernels reject the flag at
//runtime, which is what the fallback path below handles.
#ifndef CREATE_WAITABLE_TIMER_HIGH_RESOLUTION
#define CREATE_WAITABLE_TIMER_HIGH_RESOLUTION 0x00000002
#endif

extern "C" {wchar_t GPackage[64] = L"Launch"; } //Will be set to exe name later

namespace
{
    //Owns every ClipCursor/ShowCursor change the loop makes, so the process can
    //never leave the desktop's cursor clipped to a dead window or hidden until
    //reboot - Windows reclaims per-process cursor state on exit, but a fullscreen
    //app that dies mid-clip can wedge the session's cursor first.
    //
    //ShowCursor moves a per-process display counter by +-1 per call, so the state
    //that has to be undone is the NET delta this process applied, not a boolean.
    //The state is static and the release is a static function because the
    //unhandled-exception filter has to run it from a crashed context where no
    //destructor will.
    class CCursorGuard
    {
    public:
        CCursorGuard() { assert(!s_bLive); s_bLive = true; }
        ~CCursorGuard() { Release(); s_bLive = false; }

        CCursorGuard(const CCursorGuard&) = delete;
        CCursorGuard& operator=(const CCursorGuard&) = delete;

        void SetClip(const RECT& rClip) { s_bClipHeld = ClipCursor(&rClip) != FALSE; }
        void ReleaseClip() { ClipCursor(NULL); s_bClipHeld = false; }
        void Show() { ShowCursor(TRUE); ++s_iShowDelta; }
        void Hide() { ShowCursor(FALSE); --s_iShowDelta; }

        //GetClipCursor cannot answer this: an unclipped cursor reports the whole
        //virtual screen, so releasing needs our own last-applied state.
        bool IsClipHeld() const { return s_bClipHeld; }

        //Idempotent, and safe with no guard alive: state is cleared as it is undone.
        //Best effort against a fault on another thread mid-apply - one stale step is
        //better than leaving the cursor wedged.
        static void Release()
        {
            if (s_bClipHeld)
            {
                ClipCursor(NULL);
                s_bClipHeld = false;
            }
            while (s_iShowDelta < 0)
            {
                ShowCursor(TRUE);
                ++s_iShowDelta;
            }
            while (s_iShowDelta > 0)
            {
                ShowCursor(FALSE);
                --s_iShowDelta;
            }
        }

    private:
        static bool s_bLive;
        static bool s_bClipHeld;
        static int s_iShowDelta;
    };

    bool CCursorGuard::s_bLive = false;
    bool CCursorGuard::s_bClipHeld = false;
    int CCursorGuard::s_iShowDelta = 0;

    //Frame deadline timer plus the message-aware wait on it. Three paths, best
    //first: a high-resolution waitable timer (~0.5 ms, no global timer period), a
    //plain waitable timer with timeBeginPeriod(1), or no timer at all - the
    //message wait's own millisecond timeout, which always works.
    class CFrameTimer
    {
    public:
        enum class EWake { Message, Deadline };

        CFrameTimer()
        {
            m_hTimer = CreateWaitableTimerExW(NULL, NULL,
                CREATE_WAITABLE_TIMER_MANUAL_RESET | CREATE_WAITABLE_TIMER_HIGH_RESOLUTION,
                TIMER_MODIFY_STATE | SYNCHRONIZE); //Narrow mask; TIMER_ALL_ACCESS can fail under a restricted token
            if (m_hTimer)
            {
                m_pszPathName = L"high-resolution waitable timer";
                return;
            }

            m_hTimer = CreateWaitableTimerExW(NULL, NULL, CREATE_WAITABLE_TIMER_MANUAL_RESET, TIMER_MODIFY_STATE | SYNCHRONIZE);
            if (m_hTimer)
            {
                m_bTimePeriodSet = timeBeginPeriod(1) == TIMERR_NOERROR;
                m_pszPathName = m_bTimePeriodSet ? L"waitable timer with a 1 ms system timer period" : L"waitable timer at the default system timer period";
                return;
            }

            m_pszPathName = L"message-wait timeout (no waitable timer available)";
        }

        ~CFrameTimer()
        {
            if (m_hTimer)
            {
                CloseHandle(m_hTimer);
            }
            if (m_bTimePeriodSet)
            {
                timeEndPeriod(1);
            }
        }

        CFrameTimer(const CFrameTimer&) = delete;
        CFrameTimer& operator=(const CFrameTimer&) = delete;

        const wchar_t* GetPathName() const { return m_pszPathName; }

        //Relative due time, in 100 ns units. Manual reset, so one arm per frame.
        void Arm(const long long i100nsFromNow) const
        {
            if (!m_hTimer || i100nsFromNow <= 0)
            {
                return;
            }
            LARGE_INTEGER liDueTime;
            liDueTime.QuadPart = -i100nsFromNow;
            SetWaitableTimer(m_hTimer, &liDueTime, 0, NULL, NULL, FALSE);
        }

        //QS_ALLINPUT: any queued message wakes the wait so the window stays
        //responsive at any cap. dwTimeoutMs bounds the wait even without a timer.
        EWake Wait(const DWORD dwTimeoutMs) const
        {
            const HANDLE hTimer = m_hTimer;
            const DWORD dwHandleCount = m_hTimer ? 1 : 0;
            DWORD dwResult = MsgWaitForMultipleObjects(dwHandleCount, dwHandleCount ? &hTimer : NULL, FALSE, dwTimeoutMs, QS_ALLINPUT);
            if (dwResult == WAIT_FAILED)
            {
                //A wait that fails (a bad timer handle, say) must not be read as a
                //deadline wake: that returns immediately every frame and restores
                //the busy loop this exists to remove. Retry without the timer, and
                //if even that fails degrade to coarse Sleep pacing.
                dwResult = MsgWaitForMultipleObjects(0, NULL, FALSE, dwTimeoutMs, QS_ALLINPUT);
                if (dwResult == WAIT_FAILED)
                {
                    Sleep(dwTimeoutMs);
                    return EWake::Deadline;
                }
                return (dwResult == WAIT_OBJECT_0) ? EWake::Message : EWake::Deadline;
            }
            return (dwResult == WAIT_OBJECT_0 + dwHandleCount) ? EWake::Message : EWake::Deadline;
        }

    private:
        HANDLE m_hTimer = NULL;
        bool m_bTimePeriodSet = false;
        const wchar_t* m_pszPathName = L"";
    };

    //Last stop for a hardware fault: /EHsc catch(...) never sees SEH, so a null
    //dereference inside the engine bypasses the guarded loop entirely and lands
    //here. Everything runs against static buffers, allocates nothing, and walks no
    //stacks. The step order is load-bearing (see the design's crash-handling
    //section): release the cursor and get the diagnosis into the log BEFORE the
    //module lookup, which takes the loader lock and can deadlock when the fault
    //happened under it.
    LONG WINAPI UnhandledExceptionLogger(EXCEPTION_POINTERS* const pExceptionInfo)
    {
        static LONG lEntered = 0;
        if (InterlockedExchange(&lEntered, 1) != 0)
        {
            return EXCEPTION_CONTINUE_SEARCH; //A second thread faulted; the first entry owns the log
        }

        CCursorGuard::Release(); //No destructor will run for a fault; a fullscreen crash must not wedge the desktop cursor

        GLogHook = NULL; //Never dispatch into the WLog window code from a crashed context, as HandleError also does

        if (!GLog) //Nothing left to report through; the cursor is already released
        {
            return EXCEPTION_CONTINUE_SEARCH;
        }

        const EXCEPTION_RECORD* const pRecord = pExceptionInfo ? pExceptionInfo->ExceptionRecord : nullptr;
        const DWORD dwCode = pRecord ? pRecord->ExceptionCode : 0;
        const void* const pFault = pRecord ? pRecord->ExceptionAddress : nullptr;

        static wchar_t szLine[512];
        CrashRecord::FormatException(dwCode, pFault, szLine, _countof(szLine));
        GLog->Log(NAME_Critical, szLine);

        //Log, not Logf: the history is up to 4096 chars and would overflow Core's
        //format buffer. Whether an SEH fault leaves any history behind at all
        //depends on the VC6 guard chain, so the empty case is expected.
        GLog->Log(NAME_Critical, GErrorHist[0] ? GErrorHist : L"(GErrorHist empty)");

        //Last, for the loader lock. Best effort: an unresolvable address still
        //logged the code and the raw pointer above.
        HMODULE hModule = NULL;
        static wchar_t szModulePath[MAX_PATH];
        szModulePath[0] = L'\0';
        if (GetModuleHandleExW(GET_MODULE_HANDLE_EX_FLAG_FROM_ADDRESS | GET_MODULE_HANDLE_EX_FLAG_UNCHANGED_REFCOUNT, static_cast<LPCWSTR>(pFault), &hModule))
        {
            GetModuleFileNameW(hModule, szModulePath, static_cast<DWORD>(_countof(szModulePath)));
            szModulePath[_countof(szModulePath) - 1] = L'\0'; //A path longer than the buffer truncates without terminating on XP
        }
        CrashRecord::FormatModuleOffset(pFault, hModule, szModulePath, szLine, _countof(szLine));
        GLog->Log(NAME_Critical, szLine);

        return EXCEPTION_CONTINUE_SEARCH; //Let Windows error reporting run as it would have
    }

    //Mirrors OSVERSIONINFOW's layout (winternl.h's RTL_OSVERSIONINFOW) without
    //pulling that header in, since RtlGetVersion is resolved dynamically anyway.
    struct SOsVersionInfoW
    {
        DWORD dwOSVersionInfoSize;
        DWORD dwMajorVersion;
        DWORD dwMinorVersion;
        DWORD dwBuildNumber;
        DWORD dwPlatformId;
        WCHAR szCSDVersion[128];
    };

    //"<major>.<minor>.<build>" for the startup header. GetVersionExW lies
    //under an app compatibility shim; RtlGetVersion does not. ntdll.dll is
    //always already loaded, so GetModuleHandle (not LoadLibrary) suffices.
    std::wstring GetOsBuildString()
    {
        const HMODULE hNtDll = GetModuleHandleW(L"ntdll.dll");
        using RtlGetVersionFn = LONG(WINAPI*)(SOsVersionInfoW*);
        const auto pfnRtlGetVersion = hNtDll ? reinterpret_cast<RtlGetVersionFn>(GetProcAddress(hNtDll, "RtlGetVersion")) : nullptr;

        SOsVersionInfoW Info = {};
        Info.dwOSVersionInfoSize = sizeof(Info);
        if (!pfnRtlGetVersion || pfnRtlGetVersion(&Info) != 0 /*STATUS_SUCCESS*/)
        {
            return L"unknown";
        }
        wchar_t sz[64];
        swprintf_s(sz, L"%lu.%lu.%lu", Info.dwMajorVersion, Info.dwMinorVersion, Info.dwBuildNumber);
        return sz;
    }

    //"<major>.<minor>.<micro>" from SDL_GetVersion()'s encoded int
    //(SDL_VERSIONNUM(X,Y,Z) = X*1000000 + Y*1000 + Z). Caller must not call
    //this -- or anything else in <SDL3/SDL.h> -- unless CGamepad::IsSdlAvailable().
    std::wstring FormatSdlVersion(const int iVersion)
    {
        wchar_t sz[32];
        swprintf_s(sz, L"%d.%d.%d", iVersion / 1000000, (iVersion / 1000) % 1000, iVersion % 1000);
        return sz;
    }
}

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

    //Rotate the previous run's log before appInit's first Serialize() call
    //lazily opens (and overwrites) a fresh one. Must run here: before
    //appInit, but after the file manager exists so the rename target takes
    //the same redirect the log's own write will (FFileManagerDeusExeUserDocs
    //rebases into Documents).
    {
        wchar_t szExeDir[MAX_PATH];
        Misc::GetGameSystemDir(szExeDir);
        const LogPath::Result LogPathResult = LogPath::Parse(GetCommandLine(), szExeDir, GPackage);
        if (LogPathResult.bFound)
        {
            wchar_t szModernPath[MAX_PATH];
            wchar_t szModernRotatedPath[MAX_PATH];
            const bool bModernPath = pFileManager->ToModernFileName(szModernPath, LogPathResult.szPath, 'w');
            const bool bModernRotated = pFileManager->ToModernFileName(szModernRotatedPath, LogPathResult.szRotatedPath, 'w');
            //Failure (file in use, missing) is silently ignored - the engine overwrites as today.
            MoveFileExW(
                bModernPath ? szModernPath : LogPathResult.szPath,
                bModernRotated ? szModernRotatedPath : LogPathResult.szRotatedPath,
                MOVEFILE_REPLACE_EXISTING);
        }
    }

    appInit(GPackage, GetCommandLine(), &Malloc, &Log, &Error, &Warn, pFileManager.get(), FConfigCacheIni::Factory, 1);

    //Installed here because the handler logs through GLog, which appInit sets up.
    //Not a guaranteed backstop (a debugger takes precedence, and some window-proc
    //faults never reach it), which is why the cursor guard also releases on the
    //normal return and C++ unwind paths.
    SetUnhandledExceptionFilter(UnhandledExceptionLogger);

    GLog->Logf(L"Deus Exe: version %s.", WIDEN(LAUNCHER_PRODUCTVERSION_STR));

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
    //Starts SDL's gamepad subsystem ahead of the pre-game launcher/FixApp
    //dialogs below, which navigate via CDialogPadNav polling SDL directly.
    //The rest of gamepad setup (button/axis maps, opening connected pads)
    //waits for m_Gamepad.Init() further down, after the engine and viewport
    //exist.
    m_Gamepad.InitSdl();

    if (!Misc::SetDEP(0)) //Disable DEP for process (also need NXCOMPAT=NO); needed for Galaxy.dll
    {
        GLog->Log(L"Failed to set process DEP flags.");
    }
    if (QueryPerformanceFrequency(&m_iPerfCounterFreq) == FALSE)
    {
        GError->Log(L"Failed to query performance counter.");
    }

    HMONITOR hMonitor = NULL;
    if (!RunPreGameDialogs(hMonitor)) //Everything below is the game actually starting
    {
        return;
    }

    LoadSettings();

    static_cast<FFileManagerDeusExe*>(GFileManager)->OnGameStart();

    if (m_bUseSingleCPU)
    {
        if (SetProcessAffinityMask(GetCurrentProcess(), 0x1) == FALSE) //Force on single CPU
        {
            GLog->Log(L"Failed to set process affinity.");
        }
    }

    //Owned here, not by ApplyConfigOverrides: each CConfigOverride restores the
    //stock ini value in its destructor, so the list has to outlive
    //pEngine->Init() and be torn down before appExit() flushes the config cache.
    std::list<CConfigOverride> ConfigOverrides;
    ApplyConfigOverrides(ConfigOverrides);

    //Owned here because GLogWindow points at it for the whole run.
    std::unique_ptr<WLog> LogWindowPtr;
    UEngine* const pEngine = InitEngineAndViewport(hMonitor, LogWindowPtr);

    //Apply WinDrv binary patches BEFORE creating CNativeHooks so that any
    //mismatch dialog runs before we start mutating GNatives[]. m_hWnd is
    //assigned by InitEngineAndViewport above; it will be NULL on a dedicated
    //server, which the dialog tolerates.
    CWinDrvPatch WinDrvPatch(m_hWnd);

    //Initialize native hooks
    CNativeHooks NativeHooks(PROJECTNAME);

    LogStartupHeader(pEngine, WinDrvPatch);

    //Main loop. GIsGuarded makes appError append the engine's guard-chain
    //history to GErrorHist and throw instead of showing its message box on the
    //spot, so the throw unwinds through the VC6 DLLs' guard macros (which name
    //each frame via appUnwindf) and arrives here with a call history.
    GIsRunning = 1;
    if (!GIsRequestingExit)
    {
        try
        {
            GIsGuarded = 1;
            MainLoop(pEngine);
            GIsGuarded = 0;
        }
        catch (...)
        {
            //Log before HandleError, which shows the stock message box. Log, not
            //Logf - the history is up to 4096 chars and would overflow Core's
            //format buffer. A throw from anywhere but appError leaves no history.
            GLog->Log(NAME_Critical, GErrorHist[0] ? GErrorHist : L"(GErrorHist empty)");
            GError->HandleError();
            //Force exit, as an unguarded appError does today: appRequestExit(1)
            //ends the process here. Nothing below may run - LocalizeGeneral,
            //~CNativeHooks, ~CConfigOverride and appPreExit/appExit all work
            //against an object system StaticShutdownAfterError has already torn
            //down, and a secondary fault there would bury the original error.
            appRequestExit(1);
            return;
        }
    }
    GIsRunning = 0;

    GLogWindow->Log(NAME_Title, LocalizeGeneral("Exit"));
}

//Pre-game dialogs: first-run defaults, the video-options dialog and the
//launcher dialog. Returns false when the launcher dialog asks to quit; on
//success hMonitorOut carries the monitor the launcher dialog ended up on.
bool CLauncher::RunPreGameDialogs(HMONITOR& hMonitorOut)
{
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
    hMonitorOut = NULL;

    const auto DoLauncherDialog = [&hMonitorOut]
    {
        CLauncherDialog LD;
        const auto bRet = LD.Show(NULL);
        hMonitorOut = LD.GetChildWindowMonitor();
        return bRet;
    };

    return !GIsClient || ParseParam(appCmdLine(), TEXT("skipdialog")) || DoLauncherDialog();
}

//Override ini-driven engine settings without persisting them to the user's
//DeusEx.ini / User.ini. CConfigOverride snapshots each key (value,
//present-or-absent, file's Dirty flag) on construction and restores it on
//destruction, so a drop-in binary + .u install needs no manual ini edits. The
//list belongs to the caller: see the lifetime note in Launcher.h.
void CLauncher::ApplyConfigOverrides(std::list<CConfigOverride>& ConfigOverrides)
{
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
    //the launcher's gamepad shim; UseJoystick=False above just suppresses
    //DirectInput's joystick enumeration so it doesn't double up.
    struct SJoyBinding { const wchar_t* pszKey; const wchar_t* pszCommand; };
    static constexpr SJoyBinding kJoyBindings[] =
    {
        { L"Joy1",        L"Jump"                   },
        { L"Joy2",        L"ReloadWeapon"           },
        { L"Joy3",        L"ParseRightClick"        },
        { L"Joy4",        L"SwitchAmmo"             },
        { L"Joy5",        L""                       },
        { L"Joy6",        L""                       },
        { L"Joy7",        L"TogglePlayerMenuWindow" },
        { L"Joy8",        L"ShowMainMenu"           },
        { L"Joy9",        L""                       },
        { L"Joy10",       L""                       },
        { L"Joy11",       L""                       },
        { L"Joy12",       L""                       },
        { L"Joy13",       L""                       },
        { L"Joy14",       L""                       },
        { L"Joy15",       L""                       },
        { L"Joy16",       L""                       },
        { L"JoyPovUp",    L"ActivateBelt 1"         },
        { L"JoyPovLeft",  L"ActivateBelt 2"         },
        { L"JoyPovRight", L"ActivateBelt 3"         },
        { L"JoyPovDown",  L"ActivateBelt 4"         },
        { L"JoyX",        L"Axis aStrafe"           },
        { L"JoyY",        L"Axis aBaseY"            },
        { L"JoyU",        L"Axis aTurn"             },
        { L"JoyV",        L"Axis aLookUp"           },
        { L"JoyZ",        L""                       },
        { L"JoyR",        L""                       },
    };

    const wchar_t* const pszUserIni = *static_cast<FConfigCacheIni*>(GConfig)->UserIni;
    for (const SJoyBinding& Binding : kJoyBindings)
    {
        ConfigOverrides.emplace_back(L"Extension.InputExt", Binding.pszKey, Binding.pszCommand, pszUserIni);
    }
}

//Windowing, log window, engine construction and the viewport-dependent setup
//(gamepad maps, monitor placement, borderless, raw input, auto-FOV). Returns
//the constructed engine; LogWindowPtr takes ownership of the log window.
UEngine* CLauncher::InitEngineAndViewport(const HMONITOR hMonitor, std::unique_ptr<WLog>& LogWindowPtr)
{
    //Init windowing
    InitWindowing();

    //Create log window
    LogWindowPtr = std::make_unique<WLog>(static_cast<FOutputDeviceFile*>(GLog)->Filename, static_cast<FOutputDeviceFile*>(GLog)->LogAr, L"GameLog");
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
    m_pEngine = pEngine;

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

    //Button/axis maps and open-pad enumeration wait until here, after the
    //engine and viewport exist; SDL itself was already started by
    //m_Gamepad.InitSdl() at the top of the constructor, ahead of the
    //launcher/FixApp dialogs.
    m_Gamepad.Init(m_pViewPort);

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

    return pEngine;
}

//Startup diagnostic block (design doc sec3.4) -- called from the latest point
//where every fact it reports exists (viewport, WinDrvPatch outcomes, gamepad).
//StartupHeader::Build is the pure assembly; everything here is plumbing that
//gathers facts and logs the resulting lines.
void CLauncher::LogStartupHeader(UEngine* const pEngine, const CWinDrvPatch& WinDrvPatch)
{
    StartupHeader::Facts Facts;

    Facts.szLauncherVersion = WIDEN(LAUNCHER_PRODUCTVERSION_STR);

    wchar_t szExePath[MAX_PATH] = {};
    GetModuleFileNameW(NULL, szExePath, static_cast<DWORD>(_countof(szExePath)));
    Facts.szExePath = szExePath;
    Facts.szCommandLine = GetCommandLineW();

    Facts.szOsBuild = GetOsBuildString();

    Facts.bSdlLoaded = CGamepad::IsSdlAvailable();
    if (Facts.bSdlLoaded) //Never call into <SDL3/SDL.h> when SDL3.dll isn't loaded -- see the include comment above
    {
        Facts.szSdlVersion = FormatSdlVersion(SDL_GetVersion());
    }
    else
    {
        Facts.szSdlVersion = L"unavailable";
    }

    wchar_t szRenderDevice[256] = {};
    GConfig->GetString(L"Engine.Engine", L"GameRenderDevice", szRenderDevice, static_cast<INT>(_countof(szRenderDevice)));
    Facts.szRenderDevice = szRenderDevice;

    if (m_pViewPort)
    {
        Facts.iViewportSizeX = static_cast<int>(m_pViewPort->SizeX);
        Facts.iViewportSizeY = static_cast<int>(m_pViewPort->SizeY);
        Facts.bFullscreen = m_pViewPort->IsFullscreen() != 0;
    }
    Facts.bBorderless = m_bInBorderlessFullscreenWindow;

    Facts.fEffectiveFpsCap = FramePacing::EffectiveRate(m_fFPSLimit, pEngine->GetMaxTickRate());
    Facts.fMaxTickRate = pEngine->GetMaxTickRate();

    wchar_t szPadName[64] = {};
    wchar_t szPadGuid[40] = {};
    m_Gamepad.GetActivePadNameAndGuid(szPadName, _countof(szPadName), szPadGuid, _countof(szPadGuid));
    Facts.szPadName = szPadName;
    Facts.szPadGuid = szPadGuid;
    Facts.szPadFamily = m_Gamepad.GetInfo();

    for (const CWinDrvPatch::SSiteOutcome& Site : WinDrvPatch.GetSiteOutcomes())
    {
        Facts.PatchOutcomes.push_back({ Site.pszDescription, Site.pszOutcome });
    }

    Facts.bRawInput = m_bRawInput != 0;
    Facts.bUseAutoFov = m_bAutoFov != 0;
    Facts.bBorderlessFullscreenWindow = m_bBorderlessFullscreenWindow != 0;
    Facts.bBorderlessFullscreenWindowAllMonitors = m_bBorderlessFullscreenWindowUseAllMonitors != 0;
    Facts.bUseSingleCPU = m_bUseSingleCPU != 0;
    Facts.iFpsLimitIni = static_cast<int>(m_fFPSLimit);

    for (const std::wstring& Line : StartupHeader::Build(Facts))
    {
        GLog->Logf(L"%s", Line.c_str());
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

void CLauncher::RecordFrameStats(const double fFrameTimeMs, const double fOvershootMs)
{
    m_FrameStatsFrameTimeMs[m_iFrameStatsWriteIndex] = fFrameTimeMs;
    m_FrameStatsOvershootMs[m_iFrameStatsWriteIndex] = fOvershootMs;
    m_iFrameStatsWriteIndex = (m_iFrameStatsWriteIndex + 1) % kiFrameStatsRingCapacity;
    m_iFrameStatsCount = std::min(m_iFrameStatsCount + 1, kiFrameStatsRingCapacity);
}

void CLauncher::LogAndResetFrameStats(FOutputDevice& Ar)
{
    const FrameStats::Stats FrameTime = FrameStats::Compute(m_FrameStatsFrameTimeMs.data(), m_iFrameStatsCount);
    const FrameStats::Stats Overshoot = FrameStats::Compute(m_FrameStatsOvershootMs.data(), m_iFrameStatsCount);

    Ar.Logf(TEXT("FrameStats: samples=%u"), static_cast<unsigned int>(FrameTime.iCount));
    Ar.Logf(TEXT("FrameStats: frame time (ms) avg=%.3f p50=%.3f p99=%.3f max=%.3f stdev=%.3f"),
        FrameTime.fAvg, FrameTime.fP50, FrameTime.fP99, FrameTime.fMax, FrameTime.fStdDev);
    Ar.Logf(TEXT("FrameStats: deadline overshoot (ms) avg=%.3f p99=%.3f max=%.3f"),
        Overshoot.fAvg, Overshoot.fP99, Overshoot.fMax);

    m_iFrameStatsWriteIndex = 0;
    m_iFrameStatsCount = 0;
}

void CLauncher::PumpMessages(UEngine* const pEngine, const bool bMouseOverWindow, const bool bHasFocus)
{
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
                //Gate on positive physical-mouse evidence (IsMouseActive), not merely
                //pad inactivity: with the pad idle past the grace window, !IsPadActive()
                //let synthetic moves through, warping the game cursor onto whatever the
                //OS cursor was over (menu focus steal, conversation cursor flash).
                const int iXPos = GET_X_LPARAM(Msg.lParam);
                const int iYPos = GET_Y_LPARAM(Msg.lParam);
                if (bMouseOverWindow && m_Gamepad.IsMouseActive()) //Because preferences window defers mousemove calls to us, somehow
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
                if (GetRawInputData(reinterpret_cast<HRAWINPUT>(Msg.lParam), RID_INPUT, &raw, &rawSize, sizeof(RAWINPUTHEADER)) == static_cast<UINT>(-1))
                {
                    break; //Packet unreadable (too large for the buffer, or already consumed); nothing to feed the engine
                }

                //We only register for mouse usage, but SDL's joystick RawInput
                //driver can be turned on by hint, and then every packet lands
                //here too -- reading raw.data.mouse out of a HID packet would
                //be garbage.
                if (raw.header.dwType != RIM_TYPEMOUSE)
                {
                    break;
                }

                //Raw deltas are physical-motion ground truth (synthetic SetCursorPos
                //moves never generate WM_INPUT), so this is where mouse activity is
                //detected for the pad-vs-mouse active-source signal.
                m_Gamepad.NotifyMouseActivity(raw.data.mouse.lLastX, raw.data.mouse.lLastY);

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

void CLauncher::MainLoop(UEngine* const pEngine)
{
    assert(pEngine);

    LARGE_INTEGER liNow;
    if(!QueryPerformanceCounter(&liNow)) //Initial time
    {
        return;
    }

    const long long iQpcFrequency = m_iPerfCounterFreq.QuadPart;
    long long iLastTickQpc = liNow.QuadPart;
    long long iPeriodQpc = 0;
    long long iDeadlineQpc = liNow.QuadPart; //Frame 1 ticks immediately, with a near-zero delta

    //Deliberately NOT MMCSS-registered. MMCSS budgets threads that wait each
    //cycle; at FPSLimit=0 this loop never waits, blows the budget, and gets
    //periodically demoted to near-idle priority. Observed (bisect-confirmed):
    //stuttering menu animation, and permanent lockups inside the NVIDIA
    //driver's texture-creation critical section - the demoted thread loses
    //the unfair-lock race against driver worker threads indefinitely, and the
    //hung window then stalls every SendMessage(HWND_BROADCAST) sender on the
    //desktop.
    const CFrameTimer FrameTimer;
    CCursorGuard CursorGuard; //Releases clip and ShowCursor delta on return and on unwind
    GLog->Logf(L"Main loop: frame pacing via %s.", FrameTimer.GetPathName());

    while (GIsRunning && !GIsRequestingExit)
    {
        //Pre-tick facts, gathered once per frame. They feed the message pump
        //(including the pumps that run mid-wait, so a dispatched message sees facts
        //at most one frame old), the modifier-release edge check and the pad poll.
        //Everything that dereferences m_pViewPort waits until after Tick, below --
        //Tick is what destroys the viewport when the user closes the window.
        POINT CursorPos = {};
        GetCursorPos(&CursorPos);
        const bool bMouseOverWindow = WindowFromPoint(CursorPos) == m_hWnd;
        const bool bHasFocus = GetFocus() == m_hWnd;
        //Clipping keys off foreground, not focus: the clip must follow the window
        //the user is actually working in, so it is dropped the moment another
        //top-level window (including our own log window) takes over. GetFocus() is
        //thread-queue focus and answers a different question, which is why it keeps
        //its separate roles below.
        const HWND hForeground = GetForegroundWindow();
        const bool bForeground = m_hWnd != NULL && (hForeground == m_hWnd || IsChild(m_hWnd, hForeground) != FALSE);
        RECT rClientScreen = {};
        RECT rClientArea = {};
        //Fails once the window is gone, which this block outlives by a frame; the
        //zeroed rect is never consumed, since every consumer is inside if(m_pViewPort).
        if (m_hWnd && GetClientRect(m_hWnd, &rClientArea))
        {
            std::array<POINT, 2> ClientPoints = { { {rClientArea.left, rClientArea.top}, {rClientArea.right, rClientArea.bottom} } };
            MapWindowPoints(m_hWnd, NULL, ClientPoints.data(), static_cast<UINT>(ClientPoints.size()));
            rClientScreen = { ClientPoints[0].x, ClientPoints[0].y, ClientPoints[1].x, ClientPoints[1].y };
        }

        //Wait out the rest of the frame period without spinning, staying responsive:
        //any message wakes the wait, is pumped, and the wait re-arms for what is left
        //of the period. An unlimited cap (period 0) skips the wait entirely.
        while (iPeriodQpc > 0 && !GIsRequestingExit)
        {
            QueryPerformanceCounter(&liNow);
            const DWORD dwRemainingMs = FramePacing::RemainingMs(liNow.QuadPart, iDeadlineQpc, iQpcFrequency);
            if (dwRemainingMs == 0 || FrameTimer.Wait(dwRemainingMs) != CFrameTimer::EWake::Message)
            {
                break;
            }
            PumpMessages(pEngine, bMouseOverWindow, bHasFocus);
        }

        //A message dispatched inside the wait can have torn the viewport down, and
        //the modifier check and Poll below both use it. Client is null on a
        //dedicated server.
        if(!pEngine->Client || pEngine->Client->Viewports.Num() == 0)
        {
            m_pViewPort = nullptr;
        }

        QueryPerformanceCounter(&liNow);
        const float fDeltaTime = FramePacing::ClampedDelta(iLastTickQpc, liNow.QuadPart, iQpcFrequency);
        const double fFrameTimeMs = FramePacing::ElapsedMs(iLastTickQpc, liNow.QuadPart, iQpcFrequency);
        //At an unlimited cap the deadline is "now", so measuring against it would
        //just restate the frame time.
        const double fOvershootMs = (iPeriodQpc > 0) ? FramePacing::OvershootMs(liNow.QuadPart, iDeadlineQpc, iQpcFrequency) : 0.0;

        //One GetMaxTickRate() call per frame; the engine can change it between frames.
        const float fMaxTickRate = pEngine->GetMaxTickRate();
        iPeriodQpc = FramePacing::EffectivePeriodTicks(m_fFPSLimit, fMaxTickRate, iQpcFrequency);
        iDeadlineQpc = FramePacing::NextDeadline(liNow.QuadPart, iPeriodQpc);
        FrameTimer.Arm(FramePacing::TicksTo100ns(iPeriodQpc, iQpcFrequency));

        //Release stuck modifier keys when focus returns. Alt-tabbing away eats the
        //modifier's keyup (it's delivered to the newly focused window), so every
        //engine-side key-state table — WinDrv's pressedBitmap, XInputExt's bitmap and
        //XRootWindow's keyDownMap (what UnrealScript IsKeyDown() reads) — keeps the
        //modifier held. Stock UI handlers gate on exactly that: MenuUIWindow and
        //PersonaScreenBaseWindow VirtualKeyPressed reject EVERY key (incl. Escape, and
        //the mod's B-button Escape synthesis) while IsKeyDown(Alt|Shift|Ctrl), so menus
        //can't be closed after an alt-tab. WinDrv's own per-frame GetKeyState
        //reconciliation can't heal this: GetKeyState is thread-message-queue state and
        //is just as stale as the bitmaps until the missed keyup arrives (it never
        //does). GetAsyncKeyState is live hardware state, so on the focus rising edge
        //release any modifier the OS says is up. Injecting at UEngine::InputEvent is
        //the same entry point the gamepad shim uses for synthesized buttons; the
        //release flows Console::Key -> XInputExt::Process -> XRootWindow::Process and
        //heals all the tables consistently. A release for a key the engine never
        //thought was down is harmless (same thing WinDrv's trailer emits routinely).
        if(m_pViewPort && bHasFocus && !m_bPrevHasFocus)
        {
            static const struct { int iVirtualKey; EInputKey eKey; } kModifiers[] = {
                { VK_MENU,    IK_Alt   },
                { VK_SHIFT,   IK_Shift },
                { VK_CONTROL, IK_Ctrl  },
            };
            for (const auto& Mod : kModifiers)
            {
                if ((GetAsyncKeyState(Mod.iVirtualKey) & 0x8000) == 0)
                {
                    pEngine->InputEvent(m_pViewPort, Mod.eKey, EInputAction::IST_Release);
                }
            }
        }
        m_bPrevHasFocus = bHasFocus;

        //Poll and the final pump sit immediately before Tick so pad and mouse input
        //are equally fresh. Poll runs exactly once per tick: the engine accumulates
        //IST_Axis events between ticks, so emitting the absolute stick value several
        //times per tick scaled the resulting turn by the poll count (jerky look).
        m_Gamepad.Poll(pEngine, m_pViewPort, bHasFocus);
        PumpMessages(pEngine, bMouseOverWindow, bHasFocus);

        if(GIsRequestingExit) //WM_QUIT reached us this frame; nothing left to tick
        {
            break;
        }

        pEngine->Tick(fDeltaTime);
        if(GWindowManager)
        {
            GWindowManager->Tick(fDeltaTime);
        }
        iLastTickQpc = liNow.QuadPart;
        RecordFrameStats(fFrameTimeMs, fOvershootMs);

        //Post-tick re-validation: the viewport also dies inside Tick when the user
        //closes the window, before any WM_QUIT reaches us. Client is null on a
        //dedicated server.
        if(!pEngine->Client || pEngine->Client->Viewports.Num() == 0)
        {
            m_pViewPort = nullptr;
        }

        if(m_pViewPort)
        {
            assert(m_hWnd);

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

            CursorPolicy::Facts Frame;
            Frame.bForeground = bForeground;
            Frame.bFullscreen = m_pViewPort->IsFullscreen()!=0;
            Frame.bRawInput = m_bRawInput!=0;
            Frame.bInMenu = bInMenu;
            Frame.bPrevInMenu = m_bPrevInMenu;
            Frame.bPadActive = m_Gamepad.IsPadActive();
            Frame.bMouseOverWindow = bMouseOverWindow;
            Frame.bMouseInClientRect = PtInRect(&rClientScreen, CursorPos)!=0; //This makes sure resize cursor isn't hidden
            Frame.bCaptured = GetCapture() == m_hWnd;
            Frame.rClientScreen = rClientScreen;

            const CursorPolicy::Desired Want = CursorPolicy::Decide(Frame);
            m_bPrevInMenu = bInMenu;

            if (Want.bSyncCursorToRootPos) //Fixes that in fullscreen mode, windows mouse cursor pos isn't matched to DX menu cursor
            {
                float fX, fY;
                pRoot->GetRootCursorPos(&fX, &fY);
                POINT p{static_cast<int>(fX), static_cast<int>(fY)};
                ClientToScreen(m_hWnd, &p);
                SetCursorPos(p.x, p.y);
            }

            //Diff the desired state against what the OS actually reports, so an
            //externally cleared clip or a foreign ShowCursor heals within a frame while
            //a steady state costs two cheap reads. Each transition applies exactly one
            //ShowCursor call, because it moves a display counter by +-1 per call and
            //re-asserting a state every frame would run that counter away.
            RECT rActualClip = {};
            const bool bClipMatchesDesired = Want.bClip && GetClipCursor(&rActualClip) && EqualRect(&rActualClip, &Want.rClip)!=FALSE;
            CURSORINFO CursorInfo = {};
            CursorInfo.cbSize = sizeof(CursorInfo);
            const bool bCursorShowing = GetCursorInfo(&CursorInfo) ? (CursorInfo.flags & CURSOR_SHOWING)!=0 : true;

            const CursorPolicy::Actions Act = CursorPolicy::Diff(Want, bClipMatchesDesired, CursorGuard.IsClipHeld(), bCursorShowing);
            if (Act.bSetClip) //Fixed being able to move cursor outside of fullscreen game on dual monitor systems
            {
                CursorGuard.SetClip(Want.rClip);
            }
            if (Act.bReleaseClip)
            {
                CursorGuard.ReleaseClip();
            }
            if (Act.bHideOneStep) //Get rid of double mouse cursors when game doesn't clip it
            {
                CursorGuard.Hide();
            }
            if (Act.bShowOneStep)
            {
                CursorGuard.Show();
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
    else if (ParseCommand(&Cmd, TEXT("GamepadReload")))
    {
        m_Gamepad.Reload(m_pEngine, m_pViewPort);
        Ar.Logf(TEXT("Gamepad: settings reloaded from [DXController.ControllerSettings] and [DXController.GamepadButtonMap]"));
        return TRUE;
    }
    else if (ParseCommand(&Cmd, TEXT("GamepadSampleCurve")))
    {
        wchar_t szSide[8] = {};
        if (!ParseToken(Cmd, szSide, _countof(szSide), 0))
        {
            return TRUE;
        }
        CGamepad::EStick eStick;
        if      (_wcsicmp(szSide, L"Left")  == 0) eStick = CGamepad::EStick::Left;
        else if (_wcsicmp(szSide, L"Right") == 0) eStick = CGamepad::EStick::Right;
        else                                      return TRUE;

        const int iCount = appAtoi(Cmd);
        m_Gamepad.SampleCurve(eStick, iCount, Ar);
        return TRUE;
    }
    else if (ParseCommand(&Cmd, TEXT("GamepadGetRawMag")))
    {
        m_Gamepad.GetRawStickMags(Ar);
        return TRUE;
    }
    else if (ParseCommand(&Cmd, TEXT("GamepadGetInfo")))
    {
        Ar.Logf(TEXT("%s"), m_Gamepad.GetInfo());
        return TRUE;
    }
    else if (ParseCommand(&Cmd, TEXT("GetFrameStats")))
    {
        LogAndResetFrameStats(Ar);
        return TRUE;
    }
    else
    {
        return FExecHook::Exec(Cmd, Ar);
    }
}
