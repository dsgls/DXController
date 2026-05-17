//=============================================================================
// ComputerScreenLoginNav — sub-controller for ComputerScreenLogin.
//
// Rows (top-to-bottom):
//   0: editUserName (text field)
//   1: editPassword (text field)
//   2: ActionBarRow [btnLogin, btnCancel], primary btnLogin
//
// D-pad up/down moves between rows with end-to-end wrap. D-pad left/right
// walks the action-bar row (no-op on text fields and at row edges).
//
// A on a text field: opens the gamepad on-screen keyboard for that
// field. Form commit still requires D-pad to btnLogin + A.
//
// SetFocusWindow is called for text fields and action-bar buttons so
// keyboard typing reaches the gamepad-focused field and the vanilla
// yellow-text indicator paints on the focused button.
//
// OnTick re-syncs gamepad focus after a failed login: vanilla resets
// engine focus to editUserName, leaving gamepad focused on btnLogin
// with no visible cue. Re-anchor to whichever element has engine focus.
//=============================================================================
class ComputerScreenLoginNav extends ComputerScreenNavSub;

// Row kinds. Row 0 = editUserName, Row 1 = editPassword, Row 2 = ActionBar.
const ROW_USERNAME  = 0;
const ROW_PASSWORD  = 1;
const ROW_ACTIONBAR = 2;
const NUM_ROWS      = 3;

var int rowIndex;                      // current row, 0..NUM_ROWS-1
var int actionBarIndex;                // index within action-bar btns[] when rowIndex == ROW_ACTIONBAR
var MenuUIActionButtonWindow barBtns[5];
var int barCount;

// ---- OnEnter / OnLeave -----------------------------------------------------

function OnEnter(ComputerUIWindow s)
{
    local ComputerScreenLogin loginScr;

    Super.OnEnter(s);

    loginScr = ComputerScreenLogin(s);
    if (loginScr == None)
        return;
    if (loginScr.editUserName == None || loginScr.winButtonBar == None)
        return;  // children not populated yet — Tick will retry

    class'ComputerButtonBarNav'.static.CollectButtons(
        loginScr.winButtonBar, barBtns, barCount);

    rowIndex = ROW_USERNAME;
    actionBarIndex = class'ComputerButtonBarNav'.static.FindPrimaryIndex(
        loginScr.winButtonBar, barBtns, barCount, loginScr.ButtonLabelLogin);
    if (actionBarIndex < 0)
        actionBarIndex = 0;

    focused = loginScr.editUserName;
    focusIndex = 0;

    // Sync engine focus so keyboard typing lands here.
    s.SetFocusWindow(loginScr.editUserName);

    class'DXControllerDebug'.static.DebugLog(
        "DXC-TERM LOGIN-INIT row=" $ string(rowIndex)
        $ " barCount=" $ string(barCount));
}

// ---- Row helpers -----------------------------------------------------------

function Window GetRowWindow(int row)
{
    local ComputerScreenLogin loginScr;

    loginScr = ComputerScreenLogin(screen);
    if (loginScr == None)
        return None;

    if (row == ROW_USERNAME)
        return loginScr.editUserName;
    if (row == ROW_PASSWORD)
        return loginScr.editPassword;
    if (row == ROW_ACTIONBAR && actionBarIndex >= 0 && actionBarIndex < barCount)
        return barBtns[actionBarIndex];
    return None;
}

// Land focus on `row`. For ACTIONBAR, anchor at primary; sub-controllers
// don't remember the previous within-bar selection per the design.
function MoveToRow(int newRow)
{
    local ComputerScreenLogin loginScr;
    local Window w;

    loginScr = ComputerScreenLogin(screen);
    if (loginScr == None)
        return;

    if (newRow == ROW_ACTIONBAR)
    {
        // Re-collect — bIsSensitive may have flipped since OnEnter.
        class'ComputerButtonBarNav'.static.CollectButtons(
            loginScr.winButtonBar, barBtns, barCount);
        actionBarIndex = class'ComputerButtonBarNav'.static.FindPrimaryIndex(
            loginScr.winButtonBar, barBtns, barCount, loginScr.ButtonLabelLogin);
        if (actionBarIndex < 0)
            actionBarIndex = 0;
    }

    rowIndex = newRow;
    focusIndex = newRow;
    w = GetRowWindow(newRow);
    focused = w;

    // Engine-focus sync (per design's "Sync rule"): text fields and
    // buttons receive SetFocusWindow so keyboard typing routes correctly
    // and the vanilla focus-text-color indicator paints on buttons.
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

    // A on a text field: open the gamepad on-screen keyboard.
    if (rowIndex == ROW_USERNAME)
    {
        OpenKeyboardFor(ComputerScreenLogin(screen).editUserName, "ENTER USERNAME");
        return true;
    }
    if (rowIndex == ROW_PASSWORD)
    {
        OpenKeyboardFor(ComputerScreenLogin(screen).editPassword, "ENTER PASSWORD");
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

// ---- OnTick: re-sync gamepad focus after vanilla failed-login reset --------

function OnTick(float deltaSeconds)
{
    local ComputerScreenLogin loginScr;

    loginScr = ComputerScreenLogin(screen);
    if (loginScr == None || focused == None)
        return;

    // Vanilla failed-login path resets engine focus to editUserName
    // (ComputerScreenLogin.uc:225). If gamepad still tracks btnLogin
    // but engine focus has moved, re-anchor to wherever engine moved
    // it — typically editUserName — so the player sees the cue cleanly.
    if (rowIndex == ROW_ACTIONBAR
        && loginScr.editUserName != None
        && loginScr.editUserName.IsFocusWindow())
    {
        rowIndex = ROW_USERNAME;
        focusIndex = ROW_USERNAME;
        focused = loginScr.editUserName;
        class'DXControllerDebug'.static.DebugLog(
            "DXC-TERM LOGIN-RESYNC row=USERNAME (vanilla reset detected)");
    }
}
