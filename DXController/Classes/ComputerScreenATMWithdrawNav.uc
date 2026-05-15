//=============================================================================
// ComputerScreenATMWithdrawNav — sub-controller for ComputerScreenATMWithdraw.
//
// Rows (top-to-bottom):
//   0: editWithdraw  (text field)
//   1: ActionBarRow  [btnWithdraw, btnClose], primary btnWithdraw
//
// editBalance is read-only (vanilla SetSensitivity(False)) — excluded from
// tab order.
//
// D-pad up/down moves between rows with end-to-end wrap. D-pad left/right
// walks the action-bar row (no-op on the text field row and at row edges).
//
// A on editWithdraw: consumed no-op (reserved for future on-screen keyboard
// per feedback-text-field-a-reserved memory). Form commit requires D-pad to
// btnWithdraw + A.
//
// No OnTick needed: vanilla doesn't reset engine focus after a withdrawal in
// a way that would desync the gamepad cursor.
//=============================================================================
class ComputerScreenATMWithdrawNav extends ComputerScreenNavSub;

const ROW_WITHDRAW  = 0;
const ROW_ACTIONBAR = 1;
const NUM_ROWS      = 2;

var int rowIndex;       // current row, 0..NUM_ROWS-1
var int actionBarIndex; // index within action-bar btns[] when rowIndex == ROW_ACTIONBAR
var MenuUIActionButtonWindow barBtns[5];
var int barCount;

// ---- OnEnter / OnLeave -----------------------------------------------------

function OnEnter(ComputerUIWindow s)
{
    local ComputerScreenATMWithdraw wScr;

    Super.OnEnter(s);

    wScr = ComputerScreenATMWithdraw(s);
    if (wScr == None)
        return;
    if (wScr.editWithdraw == None || wScr.winButtonBar == None)
        return;  // children not populated yet — Tick will retry

    class'ComputerButtonBarNav'.static.CollectButtons(
        wScr.winButtonBar, barBtns, barCount);

    rowIndex = ROW_WITHDRAW;
    actionBarIndex = class'ComputerButtonBarNav'.static.FindPrimaryIndex(
        wScr.winButtonBar, barBtns, barCount, wScr.ButtonLabelWithdraw);
    if (actionBarIndex < 0)
        actionBarIndex = 0;

    focused = wScr.editWithdraw;
    focusIndex = 0;

    // Sync engine focus so keyboard typing lands here.
    s.SetFocusWindow(wScr.editWithdraw);

    class'DXControllerDebug'.static.DebugLog(
        "DXC-TERM ATM-WITHDRAW-INIT row=" $ string(rowIndex)
        $ " barCount=" $ string(barCount));
}

// ---- Row helpers -----------------------------------------------------------

function Window GetRowWindow(int row)
{
    local ComputerScreenATMWithdraw wScr;

    wScr = ComputerScreenATMWithdraw(screen);
    if (wScr == None)
        return None;

    if (row == ROW_WITHDRAW)
        return wScr.editWithdraw;
    if (row == ROW_ACTIONBAR && actionBarIndex >= 0 && actionBarIndex < barCount)
        return barBtns[actionBarIndex];
    return None;
}

// Land focus on `row`. For ACTIONBAR, anchor at primary.
function MoveToRow(int newRow)
{
    local ComputerScreenATMWithdraw wScr;
    local Window w;

    wScr = ComputerScreenATMWithdraw(screen);
    if (wScr == None)
        return;

    if (newRow == ROW_ACTIONBAR)
    {
        // Re-collect — bIsSensitive may have flipped since OnEnter.
        class'ComputerButtonBarNav'.static.CollectButtons(
            wScr.winButtonBar, barBtns, barCount);
        actionBarIndex = class'ComputerButtonBarNav'.static.FindPrimaryIndex(
            wScr.winButtonBar, barBtns, barCount, wScr.ButtonLabelWithdraw);
        if (actionBarIndex < 0)
            actionBarIndex = 0;
    }

    rowIndex = newRow;
    focusIndex = newRow;
    w = GetRowWindow(newRow);
    focused = w;

    // Engine-focus sync: text fields and buttons receive SetFocusWindow
    // so keyboard typing routes correctly and the vanilla focus-text-color
    // indicator paints on buttons.
    if (w != None && (IsButtonClass(w) || MenuUIEditWindow(w) != None))
        screen.SetFocusWindow(w);

    class'DXControllerDebug'.static.DebugLog(
        "DXC-TERM SUB-DPAD screen=" $ string(screen.Class)
        $ " row=" $ string(newRow) $ " barIdx=" $ string(actionBarIndex));
}

// ---- D-pad -----------------------------------------------------------------

function bool HandleDPad(int dx, int dy)
{
    local int newIdx;

    if (dy != 0)
    {
        // End-to-end wrap.
        newIdx = (rowIndex + dy + NUM_ROWS) % NUM_ROWS;
        MoveToRow(newIdx);
        return true;
    }

    if (dx != 0 && rowIndex == ROW_ACTIONBAR)
    {
        if (dx < 0)
            actionBarIndex = class'ComputerButtonBarNav'.static.MoveLeft(
                barBtns, barCount, actionBarIndex);
        else
            actionBarIndex = class'ComputerButtonBarNav'.static.MoveRight(
                barBtns, barCount, actionBarIndex);
        focused = barBtns[actionBarIndex];
        if (focused != None)
            screen.SetFocusWindow(focused);
        class'DXControllerDebug'.static.DebugLog(
            "DXC-TERM SUB-DPAD screen=" $ string(screen.Class)
            $ " row=" $ string(rowIndex) $ " barIdx=" $ string(actionBarIndex));
        return true;
    }

    // Text-field row L/R: consumed no-op.
    return true;
}

// ---- Activate (A / X / Y / R-stick click) ---------------------------------

function bool HandleActivate(byte button)
{
    // Only A (200) does anything; X/Y/R-stick click are consumed.
    if (button != 200)
        return true;

    // A on a text field: reserved for future on-screen keyboard (no-op).
    if (rowIndex == ROW_WITHDRAW)
    {
        class'DXControllerDebug'.static.DebugLog("DXC-TERM A-TEXTFIELD-NOOP");
        return true;
    }

    // A on an action-bar button: press it.
    if (rowIndex == ROW_ACTIONBAR
        && focused != None
        && MenuUIActionButtonWindow(focused) != None
        && focused.bIsSensitive)
    {
        class'DXControllerDebug'.static.DebugLog(
            "DXC-TERM SUB-ACTIVATE press=" $ MenuUIActionButtonWindow(focused).buttonText);
        MenuUIActionButtonWindow(focused).PressButton();
    }
    return true;
}
