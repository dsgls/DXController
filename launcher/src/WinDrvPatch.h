#pragma once

#include <vector>

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

    //One site's fate, for the startup header (design doc sec3.4).
    struct SSiteOutcome
    {
        const wchar_t* pszDescription; //Matches the at-patch-time log line
        const wchar_t* pszOutcome;     //"patched" / "mismatch" / "skipped" / "dll-absent"
    };

    //In kSites order. A single "dll-absent" entry when WinDrv.dll itself
    //wasn't loaded, rather than one per site -- there is nothing per-site to
    //report in that case. A site after a mismatch (patching stops there; the
    //user is asked whether to continue) or after a VirtualProtect failure is
    //"skipped".
    const std::vector<SSiteOutcome>& GetSiteOutcomes() const { return m_SiteOutcomes; }

private:
    std::vector<SSiteOutcome> m_SiteOutcomes;
};
