#include "stdafx.h"
#include "DialogPadNav.h"
#include "resource.h"

#include <Xinput.h>

namespace
{
    constexpr UINT      kPollIntervalMs   = 30;
    //Keyboard-style auto-repeat for held d-pad directions.
    constexpr ULONGLONG kRepeatDelayMs    = 400;
    constexpr ULONGLONG kRepeatIntervalMs = 100;
    //Probing empty XInput slots is slow (documented multi-ms stalls), so
    //rescan for a hotplugged pad at most once a second -- same rationale as
    //CXInput::m_iHotplugScanMs.
    constexpr ULONGLONG kHotplugScanMs    = 1000;

    //Direction order matches SPadNavEntry::iNeighbour: up/down/left/right.
    constexpr WORD kDirBits[4] =
    {
        XINPUT_GAMEPAD_DPAD_UP,
        XINPUT_GAMEPAD_DPAD_DOWN,
        XINPUT_GAMEPAD_DPAD_LEFT,
        XINPUT_GAMEPAD_DPAD_RIGHT,
    };

    const wchar_t* const kEditHint  = L"Up/Down: +/-1   Left/Right: +/-10   A: confirm   B: revert";
    const wchar_t* const kComboHint = L"Up/Down: choose   A: confirm   B: revert";
}

CDialogPadNav::CDialogPadNav(const HWND hDlg, const SPadNavEntry* const pEntries,
                             const size_t iEntryCount, const int iCancelCtrl,
                             const int iConfirmCtrl, const int iHomeCtrl,
                             const wchar_t* const pszNavigateHint)
:m_hDlg(hDlg),
 m_pEntries(pEntries),
 m_iEntryCount(iEntryCount),
 m_iCancelCtrl(iCancelCtrl),
 m_iConfirmCtrl(iConfirmCtrl),
 m_iHomeCtrl(iHomeCtrl),
 m_pszNavigateHint(pszNavigateHint),
 m_iSlot(static_cast<DWORD>(-1)),
 m_bConnected(false),
 m_bFocusVisualsEnabled(false),
 m_iPrevButtons(0),
 m_iLastScanMs(0),
 m_aRepeat{},
 m_eMode(EMode::Navigate),
 m_hActiveCtrl(nullptr),
 m_iActiveCtrlId(0),
 m_iEditSnapshot(0),
 m_iComboSnapshot(CB_ERR)
{
    //Snapshot buttons held at creation so e.g. the A press that opened this
    //dialog from its parent doesn't produce a phantom press edge here.
    WORD iButtons = 0;
    m_bConnected = ReadPad(iButtons);
    m_iPrevButtons = iButtons;
    //Set the Navigate hint unconditionally: the template's LTEXT is empty, and
    //a hotplug connect later only shows the control -- it must already hold text.
    SetHint(m_pszNavigateHint);
    ShowHint(m_bConnected);
    SetTimer(m_hDlg, sm_iTimerId, kPollIntervalMs, nullptr);
}

CDialogPadNav::~CDialogPadNav()
{
    KillTimer(m_hDlg, sm_iTimerId);
}

bool CDialogPadNav::ReadPad(WORD& iButtons)
{
    iButtons = 0;
    XINPUT_STATE State = {};
    if (m_iSlot != static_cast<DWORD>(-1))
    {
        if (XInputGetState(m_iSlot, &State) == ERROR_SUCCESS)
        {
            iButtons = State.Gamepad.wButtons;
            return true;
        }
        m_iSlot = static_cast<DWORD>(-1);
    }

    const ULONGLONG iNowMs = GetTickCount64();
    if (m_iLastScanMs != 0 && iNowMs - m_iLastScanMs < kHotplugScanMs)
    {
        return false;
    }
    m_iLastScanMs = iNowMs;

    for (DWORD i = 0; i < XUSER_MAX_COUNT; ++i)
    {
        if (XInputGetState(i, &State) == ERROR_SUCCESS)
        {
            m_iSlot = i;
            iButtons = State.Gamepad.wButtons;
            return true;
        }
    }
    return false;
}

void CDialogPadNav::OnTimer()
{
    WORD iButtons = 0;
    const bool bConnected = ReadPad(iButtons);
    if (bConnected != m_bConnected)
    {
        m_bConnected = bConnected;
        ShowHint(bConnected);
        if (bConnected)
        {
            //No phantom edge from buttons already held at connect time.
            m_iPrevButtons = iButtons;
        }
    }
    if (!bConnected)
    {
        return;
    }

    if (GetForegroundWindow() != m_hDlg)
    {
        //Inert while a child modal or another app is foreground. Re-snapshot
        //every tick so buttons held across the transition produce no phantom
        //edge when we become foreground again.
        m_iPrevButtons = iButtons;
        ClearRepeats();
        return;
    }

    //If a control was activated and the user clicked elsewhere (or closed the
    //dropdown) with the mouse, treat it as confirm: value stands.
    if (m_eMode != EMode::Navigate)
    {
        const bool bFocusLost = ResolveFocus() != m_hActiveCtrl;
        const bool bDropClosed = m_eMode == EMode::ComboActive &&
            SendMessage(m_hActiveCtrl, CB_GETDROPPEDSTATE, 0, 0) == 0;
        if (bFocusLost || bDropClosed)
        {
            EnterNavigate();
        }
    }

    const WORD iPressed = static_cast<WORD>(iButtons & ~m_iPrevButtons);
    m_iPrevButtons = iButtons;

    const ULONGLONG iNowMs = GetTickCount64();
    for (int i = 0; i < 4; ++i)
    {
        SRepeatState& Repeat = m_aRepeat[i];
        if ((iButtons & kDirBits[i]) == 0)
        {
            Repeat = {};
        }
        else if (iPressed & kDirBits[i])
        {
            Repeat.bDown = true;
            Repeat.iNextFireMs = iNowMs + kRepeatDelayMs;
            Move(i);
        }
        else if (Repeat.bDown && iNowMs >= Repeat.iNextFireMs)
        {
            Repeat.iNextFireMs = iNowMs + kRepeatIntervalMs;
            Move(i);
        }
    }

    //Single-shot buttons. Return immediately after dispatch: BM_CLICK can run
    //EndDialog via the dialog's own WM_COMMAND handler.
    if (iPressed & XINPUT_GAMEPAD_A)
    {
        PressA();
        return;
    }
    if (iPressed & XINPUT_GAMEPAD_B)
    {
        PressB();
        return;
    }
    if (iPressed & XINPUT_GAMEPAD_START)
    {
        PressStart();
        return;
    }
}

HWND CDialogPadNav::ResolveFocus() const
{
    //Combo boxes put focus on their embedded edit child; walk up to the
    //dialog's direct child so nav-table lookups see the combo itself.
    HWND hFocus = GetFocus();
    while (hFocus)
    {
        const HWND hParent = GetParent(hFocus);
        if (hParent == m_hDlg)
        {
            return hFocus;
        }
        if (!hParent)
        {
            return nullptr;
        }
        hFocus = hParent;
    }
    return nullptr;
}

const SPadNavEntry* CDialogPadNav::FindEntry(const int iControl) const
{
    for (size_t i = 0; i < m_iEntryCount; ++i)
    {
        if (m_pEntries[i].iControl == iControl)
        {
            return &m_pEntries[i];
        }
    }
    return nullptr;
}

void CDialogPadNav::Move(const int iDirection)
{
    if (m_eMode == EMode::EditActive)
    {
        //up/down: +-1, left/right: +-10
        static constexpr int kDeltas[4] = { 1, -1, -10, 10 };
        AdjustEdit(kDeltas[iDirection]);
        return;
    }
    if (m_eMode == EMode::ComboActive)
    {
        if (iDirection == 0)
        {
            StepCombo(-1);
        }
        else if (iDirection == 1)
        {
            StepCombo(1);
        }
        return;
    }

    if (m_iEntryCount == 0)
    {
        return;
    }

    //Dialogs hide focus rectangles until keyboard use; make them visible from
    //the first pad navigation so the user can see where they are.
    if (!m_bFocusVisualsEnabled)
    {
        SendMessage(m_hDlg, WM_CHANGEUISTATE, MAKEWPARAM(UIS_CLEAR, UISF_HIDEFOCUS), 0);
        m_bFocusVisualsEnabled = true;
    }

    const HWND hFocus = ResolveFocus();
    const SPadNavEntry* const pEntry = hFocus ? FindEntry(GetDlgCtrlID(hFocus)) : nullptr;

    int iTarget;
    if (!pEntry)
    {
        //Focus is outside the nav graph (e.g. the user Tabbed onto a SysLink,
        //which pads can't reach) -- snap back to the home control.
        iTarget = m_iHomeCtrl;
    }
    else
    {
        iTarget = pEntry->iNeighbour[iDirection];
        //Skip disabled controls by following the same direction onward. The
        //iteration cap guards against an all-disabled directional cycle.
        for (size_t iGuard = 0; iTarget != 0 && iGuard < m_iEntryCount; ++iGuard)
        {
            const HWND hCandidate = GetDlgItem(m_hDlg, iTarget);
            if (hCandidate && IsWindowEnabled(hCandidate))
            {
                break;
            }
            const SPadNavEntry* const pNext = FindEntry(iTarget);
            iTarget = pNext ? pNext->iNeighbour[iDirection] : 0;
        }
    }
    if (iTarget == 0)
    {
        return;
    }

    const HWND hTarget = GetDlgItem(m_hDlg, iTarget);
    if (!hTarget || !IsWindowEnabled(hTarget))
    {
        return;
    }
    wchar_t szClass[16];
    if (GetClassName(hTarget, szClass, _countof(szClass)) == 0)
    {
        szClass[0] = L'\0';
    }

    //Auto radio buttons generate BN_CLICKED at the dialog when they receive
    //focus, so a bare focus move would run the dialog's selection handlers
    //(e.g. FixApp's enable/disable logic) on mere navigation. BM_SETDONTCLICK
    //suppresses exactly that; restore it afterwards so keyboard arrow
    //navigation keeps the stock select-on-focus behaviour.
    const bool bIsAutoRadio = _wcsicmp(szClass, L"Button") == 0 &&
        (GetWindowLong(hTarget, GWL_STYLE) & BS_TYPEMASK) == BS_AUTORADIOBUTTON;
    if (bIsAutoRadio)
    {
        SendMessage(hTarget, BM_SETDONTCLICK, TRUE, 0);
    }
    //WM_NEXTDLGCTL (not raw SetFocus) keeps the dialog manager's default-
    //button bookkeeping correct.
    SendMessage(m_hDlg, WM_NEXTDLGCTL, reinterpret_cast<WPARAM>(hTarget), TRUE);
    if (bIsAutoRadio)
    {
        SendMessage(hTarget, BM_SETDONTCLICK, FALSE, 0);
    }

    //WM_NEXTDLGCTL select-alls edit controls on focus; clear that so the
    //select-all highlight remains the "activated" indicator.
    if (_wcsicmp(szClass, L"Edit") == 0)
    {
        SendMessage(hTarget, EM_SETSEL, static_cast<WPARAM>(-1), 0);
    }
}

void CDialogPadNav::PressA()
{
    if (m_eMode != EMode::Navigate)
    {
        //Confirm: keep the current value/selection.
        if (m_eMode == EMode::ComboActive)
        {
            SendMessage(m_hActiveCtrl, CB_SHOWDROPDOWN, FALSE, 0);
        }
        else
        {
            SendMessage(m_hActiveCtrl, EM_SETSEL, static_cast<WPARAM>(-1), 0);
        }
        EnterNavigate();
        return;
    }

    if (m_iEntryCount == 0)
    {
        return;
    }
    const HWND hFocus = ResolveFocus();
    if (!hFocus || !FindEntry(GetDlgCtrlID(hFocus)))
    {
        return;
    }

    wchar_t szClass[16];
    if (GetClassName(hFocus, szClass, _countof(szClass)) == 0)
    {
        return;
    }

    if (_wcsicmp(szClass, L"Button") == 0)
    {
        //Push buttons, checkboxes and radio buttons all take BM_CLICK; it runs
        //the exact same notification path as a mouse click, so the dialog's
        //existing BN_CLICKED handlers (enable/disable logic, EndDialog) fire.
        SendMessage(hFocus, BM_CLICK, 0, 0);
    }
    else if (_wcsicmp(szClass, L"ComboBox") == 0)
    {
        m_eMode = EMode::ComboActive;
        m_hActiveCtrl = hFocus;
        m_iActiveCtrlId = GetDlgCtrlID(hFocus);
        m_iComboSnapshot = static_cast<int>(SendMessage(hFocus, CB_GETCURSEL, 0, 0));
        SendMessage(hFocus, CB_SHOWDROPDOWN, TRUE, 0);
        ClearRepeats();
        SetHint(kComboHint);
    }
    else if (_wcsicmp(szClass, L"Edit") == 0)
    {
        m_eMode = EMode::EditActive;
        m_hActiveCtrl = hFocus;
        m_iActiveCtrlId = GetDlgCtrlID(hFocus);
        m_iEditSnapshot = GetDlgItemInt(m_hDlg, m_iActiveCtrlId, nullptr, FALSE);
        SendMessage(hFocus, EM_SETSEL, 0, static_cast<LPARAM>(-1));
        ClearRepeats();
        SetHint(kEditHint);
    }
}

void CDialogPadNav::PressB()
{
    if (m_eMode == EMode::EditActive)
    {
        //Revert to the pre-activation value.
        SetDlgItemInt(m_hDlg, m_iActiveCtrlId, m_iEditSnapshot, FALSE);
        SendMessage(m_hActiveCtrl, EM_SETSEL, static_cast<WPARAM>(-1), 0);
        EnterNavigate();
        return;
    }
    if (m_eMode == EMode::ComboActive)
    {
        //Close first, then restore: avoids the listbox re-committing the
        //highlighted item over the restored selection.
        SendMessage(m_hActiveCtrl, CB_SHOWDROPDOWN, FALSE, 0);
        SendMessage(m_hActiveCtrl, CB_SETCURSEL, m_iComboSnapshot, 0);
        NotifyComboSelChange();
        EnterNavigate();
        return;
    }
    if (m_iCancelCtrl != 0)
    {
        const HWND hCancel = GetDlgItem(m_hDlg, m_iCancelCtrl);
        if (hCancel)
        {
            SendMessage(hCancel, BM_CLICK, 0, 0);
        }
    }
}

void CDialogPadNav::PressStart()
{
    if (m_eMode != EMode::Navigate || m_iConfirmCtrl == 0)
    {
        return;
    }
    const HWND hConfirm = GetDlgItem(m_hDlg, m_iConfirmCtrl);
    if (hConfirm)
    {
        SendMessage(hConfirm, BM_CLICK, 0, 0);
    }
}

void CDialogPadNav::AdjustEdit(const int iDelta)
{
    UINT iValue = GetDlgItemInt(m_hDlg, m_iActiveCtrlId, nullptr, FALSE);
    if (iDelta < 0 && iValue < static_cast<UINT>(-iDelta))
    {
        iValue = 0; //Fields are ES_NUMBER; floor at 0. Range checks stay in ApplySettings.
    }
    else
    {
        iValue += iDelta;
    }
    SetDlgItemInt(m_hDlg, m_iActiveCtrlId, iValue, FALSE);
    //Keep the whole text selected -- it's the "activated" indicator.
    SendMessage(m_hActiveCtrl, EM_SETSEL, 0, static_cast<LPARAM>(-1));
}

void CDialogPadNav::StepCombo(const int iStep)
{
    const int iCount = static_cast<int>(SendMessage(m_hActiveCtrl, CB_GETCOUNT, 0, 0));
    if (iCount <= 0)
    {
        return;
    }
    int iSel = static_cast<int>(SendMessage(m_hActiveCtrl, CB_GETCURSEL, 0, 0));
    iSel = (iSel == CB_ERR) ? 0 : iSel + iStep;
    iSel = std::min(iCount - 1, std::max(0, iSel));
    SendMessage(m_hActiveCtrl, CB_SETCURSEL, iSel, 0);
    NotifyComboSelChange();
}

void CDialogPadNav::NotifyComboSelChange() const
{
    //CB_SETCURSEL doesn't notify the parent; emit the CBN_SELCHANGE a keyboard
    //selection would have produced so the dialog reacts identically.
    SendMessage(m_hDlg, WM_COMMAND,
                MAKEWPARAM(m_iActiveCtrlId, CBN_SELCHANGE),
                reinterpret_cast<LPARAM>(m_hActiveCtrl));
}

void CDialogPadNav::EnterNavigate()
{
    m_eMode = EMode::Navigate;
    m_hActiveCtrl = nullptr;
    m_iActiveCtrlId = 0;
    ClearRepeats();
    SetHint(m_pszNavigateHint);
}

void CDialogPadNav::ClearRepeats()
{
    for (SRepeatState& Repeat : m_aRepeat)
    {
        Repeat = {};
    }
}

void CDialogPadNav::SetHint(const wchar_t* const pszText) const
{
    const HWND hHint = GetDlgItem(m_hDlg, IDC_PADHINTS);
    if (hHint)
    {
        SetWindowText(hHint, pszText);
    }
}

void CDialogPadNav::ShowHint(const bool bShow) const
{
    const HWND hHint = GetDlgItem(m_hDlg, IDC_PADHINTS);
    if (hHint)
    {
        ShowWindow(hHint, bShow ? SW_SHOWNOACTIVATE : SW_HIDE);
    }
}
