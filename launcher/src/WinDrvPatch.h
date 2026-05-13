#pragma once

//Runtime byte patches for two bugs in WinDrv.dll's UWindowsViewport::UpdateInput.
//See docs/superpowers/specs/2026-05-13-windrv-runtime-patch-design.md and
//../deusex-native-re/docs/windrv-input.md for the bugs being fixed.
class CWinDrvPatch
{
public:
    //hWndForDialog is used as the owner for any mismatch MessageBox.
    //May be NULL (e.g. dedicated server / pre-window startup); the dialog still works,
    //it just isn't parented.
    explicit CWinDrvPatch(HWND hWndForDialog);
    ~CWinDrvPatch() = default;

    CWinDrvPatch(const CWinDrvPatch&) = delete;
    CWinDrvPatch& operator=(const CWinDrvPatch&) = delete;
};
