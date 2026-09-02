#include "stdafx.h"
#include "DialogHost.h"
#include "DialogPadNav.h"
#include "resource.h"

namespace
{
    const wchar_t* const kpszSelfProp = L"this";
}

CDialogHost::CDialogHost() = default;
CDialogHost::~CDialogHost() = default;

void CDialogHost::BindSelf(const HWND hwndDlg, CDialogHost* const pThis)
{
    SetProp(hwndDlg, kpszSelfProp, reinterpret_cast<HANDLE>(pThis));
    SendMessage(hwndDlg, WM_SETICON, ICON_BIG, reinterpret_cast<LPARAM>(LoadIcon(reinterpret_cast<HINSTANCE>(GetWindowLong(hwndDlg, GWL_HINSTANCE)), MAKEINTRESOURCE(IDI_ICON))));
}

CDialogHost* CDialogHost::FindSelf(const HWND hwndDlg)
{
    return static_cast<CDialogHost*>(GetProp(hwndDlg, kpszSelfProp));
}

bool CDialogHost::HandleCommonMessage(const HWND hwndDlg, const UINT uMsg, const WPARAM wParam, CDialogHost* const pThis, INT_PTR& iResult)
{
    iResult = FALSE;

    switch (uMsg)
    {
    case WM_TIMER:
        if (wParam == CDialogPadNav::sm_iTimerId && pThis && pThis->m_pPadNav)
        {
            pThis->m_pPadNav->OnTimer();
            iResult = TRUE;
            return true;
        }
        break;

    case WM_DESTROY:
        if (pThis)
        {
            pThis->m_pPadNav.reset();
        }
        //Property lists outlive the window if never removed.
        RemoveProp(hwndDlg, kpszSelfProp);
        break;

    case WM_CLOSE:
        EndDialog(hwndDlg, 0);
        iResult = TRUE;
        return true;
    }

    return false;
}
