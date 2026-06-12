#pragma once

//One nav-table row: a control and its four spatial neighbours, indexed by
//CDialogPadNav's direction order up/down/left/right. 0 = no move.
struct SPadNavEntry
{
    int iControl;
    int iNeighbour[4];
};

//XInput navigation for one native dialog. Create in WM_INITDIALOG, destroy in
//WM_DESTROY, and forward WM_TIMER events carrying sm_iTimerId to OnTimer().
//Adds pad input on top of normal mouse/keyboard handling; never replaces it.
class CDialogPadNav
{
public:
    static constexpr UINT_PTR sm_iTimerId = 0xDC11;

    //pEntries may be nullptr with iEntryCount 0 (B-button/hints only).
    //iCancelCtrl: control BM_CLICKed by B in Navigate mode (0 = none).
    //iConfirmCtrl: control BM_CLICKed by Start in Navigate mode (0 = none).
    //iHomeCtrl: focus target when the pad navigates while focus is outside
    //the nav table (0 = none).
    //pszNavigateHint: hint-line text for Navigate mode; must outlive this
    //object (pass a string literal).
    CDialogPadNav(HWND hDlg, const SPadNavEntry* pEntries, size_t iEntryCount,
                  int iCancelCtrl, int iConfirmCtrl, int iHomeCtrl,
                  const wchar_t* pszNavigateHint);
    ~CDialogPadNav();

    CDialogPadNav(const CDialogPadNav&) = delete;
    CDialogPadNav& operator=(const CDialogPadNav&) = delete;

    void OnTimer();

private:
    enum class EMode { Navigate, EditActive, ComboActive };

    struct SRepeatState
    {
        bool      bDown;
        ULONGLONG iNextFireMs;
    };

    bool ReadPad(WORD& iButtons);
    HWND ResolveFocus() const;
    const SPadNavEntry* FindEntry(int iControl) const;
    void Move(int iDirection);
    void PressA();
    void PressB();
    void PressStart();
    void AdjustEdit(int iDelta);
    void StepCombo(int iStep);
    void NotifyComboSelChange() const;
    void EnterNavigate();
    void ClearRepeats();
    void SetHint(const wchar_t* pszText) const;
    void ShowHint(bool bShow) const;

    HWND                m_hDlg;
    const SPadNavEntry* m_pEntries;
    size_t              m_iEntryCount;
    int                 m_iCancelCtrl;
    int                 m_iConfirmCtrl;
    int                 m_iHomeCtrl;
    const wchar_t*      m_pszNavigateHint;

    DWORD               m_iSlot;
    bool                m_bConnected;
    bool                m_bFocusVisualsEnabled;
    WORD                m_iPrevButtons;
    ULONGLONG           m_iLastScanMs;
    SRepeatState        m_aRepeat[4];

    EMode               m_eMode;
    HWND                m_hActiveCtrl;
    int                 m_iActiveCtrlId;
    UINT                m_iEditSnapshot;
    int                 m_iComboSnapshot;
};
