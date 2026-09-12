#pragma once

#include <vector>

//Runtime byte patches applied to stock game DLLs at startup. Each site is a
//whole-instruction fingerprint plus its replacement; a site is written only
//when the live bytes match the fingerprint exactly, so an unrecognised build
//is refused rather than corrupted.
//
//Sites live in kModules in BytePatch.cpp. For the bugs being fixed see
//docs/superpowers/specs/2026-05-13-windrv-runtime-patch-design.md,
//../deusex-native-re/docs/windrv-input.md and
//../deusex-native-re/docs/deusex-savegame-model.md.
class CBytePatch
{
public:
    //hWndForDialog is used as the owner for any mismatch MessageBox.
    //May be NULL (e.g. dedicated server / pre-window startup); the dialog still works,
    //it just isn't parented.
    explicit CBytePatch(HWND hWndForDialog);
    ~CBytePatch() = default;

    CBytePatch(const CBytePatch&) = delete;
    CBytePatch& operator=(const CBytePatch&) = delete;

    //One site's fate, for the startup header (design doc sec3.4).
    struct SSiteOutcome
    {
        const wchar_t* pszModule;      //Owning DLL, e.g. L"WinDrv.dll"
        const wchar_t* pszDescription; //Matches the at-patch-time log line; NULL for a whole-module row
        const wchar_t* pszOutcome;     //"patched" / "mismatch" / "failed" / "skipped" / "dll-absent"
    };

    //In kModules order, sites in table order. A module that isn't loaded
    //contributes a single "dll-absent" row with a NULL description rather than
    //one per site -- there is nothing per-site to report in that case. Every
    //site after a mismatch (patching stops there; the user is asked whether to
    //continue) or after a VirtualProtect failure is "skipped", including sites
    //in later modules: a fingerprint mismatch means this isn't the build the
    //patches were authored against, so patching a different DLL on it is a guess.
    const std::vector<SSiteOutcome>& GetSiteOutcomes() const { return m_SiteOutcomes; }

private:
    std::vector<SSiteOutcome> m_SiteOutcomes;
};
