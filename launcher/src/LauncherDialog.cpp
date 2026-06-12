#include "stdafx.h"
#include "LauncherDialog.h"
#include "DialogPadNav.h"
#include "DataDirDialog.h"
#include "FixApp.h"
#include "Misc.h"
#include "FileManagerDeusExe.h"
#include "resource.h"

namespace
{
    //Single vertical button chain; the SysLinks are deliberately not
    //pad-reachable. Order: control, up, down, left, right (0 = no move).
    constexpr SPadNavEntry kLauncherNavTable[] =
    {
        { IDC_PLAY,     0,            IDC_CONFIG,   0, 0 },
        { IDC_CONFIG,   IDC_PLAY,     IDC_DATADIRS, 0, 0 },
        { IDC_DATADIRS, IDC_CONFIG,   IDC_EXIT,     0, 0 },
        { IDC_EXIT,     IDC_DATADIRS, 0,            0, 0 },
    };
}

CLauncherDialog::CLauncherDialog()
{

}

CLauncherDialog::~CLauncherDialog()
{

}

bool CLauncherDialog::Show(const HWND hWndParent) const
{
    return DialogBoxParam(GetModuleHandle(0),MAKEINTRESOURCE(IDD_DIALOG1),hWndParent,LauncherDialogProc,reinterpret_cast<LPARAM>(this)) == 1;
}

void CLauncherDialog::FillLinkControl(const HWND hWndLinkControl, const wchar_t* const pszIniFilePath)
{
    wchar_t szIni[MAX_PATH];
    wchar_t szLink[2 * MAX_PATH];

	static_cast<FFileManagerDeusExe*>(GFileManager)->ToModernFileName(szIni, pszIniFilePath);

    swprintf_s(szLink, L"<a href=\"%s\">%s</a>", szIni, PathFindFileName(pszIniFilePath));
    SetWindowText(hWndLinkControl, szLink);
}

INT_PTR CALLBACK CLauncherDialog::LauncherDialogProc(HWND hwndDlg,UINT uMsg,WPARAM wParam,LPARAM lParam)
{
    CLauncherDialog* pThis = reinterpret_cast<CLauncherDialog*>(GetProp(hwndDlg, L"this"));
    switch (uMsg)
    {
    case WM_INITDIALOG:
        {
            SetProp(hwndDlg, L"this", reinterpret_cast<HANDLE>(lParam));
            pThis = reinterpret_cast<CLauncherDialog*>(lParam);

            SendMessage(hwndDlg, WM_SETICON, ICON_BIG, reinterpret_cast<LPARAM>(LoadIcon(reinterpret_cast<HINSTANCE>(GetWindowLong(hwndDlg,GWL_HINSTANCE)), MAKEINTRESOURCE(IDI_ICON))));

            pThis->m_hWndWebsite = GetDlgItem(hwndDlg, IDC_WEBSITE);

            wchar_t buffer[128];
            swprintf_s(buffer, L"Version %s", Misc::GetVersion());
            SetDlgItemText(hwndDlg,IDC_VERSION,buffer);

            //Show ini files
            pThis->m_hWndIniFile1 = GetDlgItem(hwndDlg, IDC_INIFILES1);
            pThis->m_hWndIniFile2 = GetDlgItem(hwndDlg, IDC_INIFILES2);

            assert(GConfig);
            FConfigCacheIni* pCI = static_cast<FConfigCacheIni*>(GConfig);

            pThis->FillLinkControl(pThis->m_hWndIniFile1, *pCI->SystemIni);
            pThis->FillLinkControl(pThis->m_hWndIniFile2, *pCI->UserIni);

            pThis->m_pPadNav = std::make_unique<CDialogPadNav>(
                hwndDlg, kLauncherNavTable, _countof(kLauncherNavTable),
                IDC_EXIT, IDC_PLAY, IDC_PLAY,
                L"D-pad: navigate   A: select   B: exit   Start: play");
        }

        return TRUE;


    case WM_COMMAND:
        switch (HIWORD(wParam))
        {
        case BN_CLICKED:
            switch (LOWORD(wParam))
            {
            case BN_CLICKED:
            case IDC_PLAY:
                pThis->m_hMonitor = MonitorFromWindow(hwndDlg, MONITOR_DEFAULTTONEAREST); //Track on which monitor we were closed, so we can move game to there
                EndDialog(hwndDlg, 1);
                return TRUE;
            case IDC_EXIT:
                EndDialog(hwndDlg, 0);
                return TRUE;
            case IDC_DATADIRS:
            {
                CDataDirDialog DataDirDialog;
                DataDirDialog.Show(hwndDlg);
            }
            return TRUE;
            case IDC_CONFIG:
            {
                CFixApp FixApp;
                FixApp.Show(hwndDlg);
            }
            return TRUE;
            }
            break;
        }
        break;
    case WM_NOTIFY:
    {
        const NMHDR* const pNMH = reinterpret_cast<NMHDR*>(lParam);
        assert(pNMH);
        switch(pNMH->code)
        {
        case NM_CLICK:
        {
            if(pNMH->hwndFrom == pThis->m_hWndWebsite || pNMH->hwndFrom == pThis->m_hWndIniFile1 || pNMH->hwndFrom == pThis->m_hWndIniFile2)
            {
                GConfig->Flush(FALSE);
                const NMLINK* const pLink = reinterpret_cast<NMLINK*>(lParam);
                assert(pLink);
                ShellExecute(hwndDlg, L"open", pLink->item.szUrl, nullptr, nullptr, SW_SHOWNORMAL);
                return TRUE;
            }
        }
        }
        break;
    }

    case WM_TIMER:
        if (wParam == CDialogPadNav::sm_iTimerId && pThis && pThis->m_pPadNav)
        {
            pThis->m_pPadNav->OnTimer();
            return TRUE;
        }
        break;

    case WM_DESTROY:
        if (pThis)
        {
            pThis->m_pPadNav.reset();
        }
        break;

    case WM_CLOSE:
        EndDialog(hwndDlg,0);
        return TRUE;

    }

    return FALSE;
}
