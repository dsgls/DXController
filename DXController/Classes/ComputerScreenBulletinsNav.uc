//=============================================================================
// ComputerScreenBulletinsNav — sub-controller for ComputerScreenBulletins.
//
// Rows: [lstBulletins, ActionBarRow(btnSpecial?, btnLogout)],
//       primary btnLogout.
//
// winBulletin (side panel) is read-only and auto-updated by vanilla
// ListSelectionChanged — no script-side display call needed.
//
// D-pad inside list: edge-detect via GetFocusRow() before/after MoveRow.
// At edge, wrap to ActionBarRow @ primary.
// A on list row: consumed no-op (selection drives auto-display).
//=============================================================================
class ComputerScreenBulletinsNav extends ComputerScreenNavSub;

const ROW_LIST       = 0;
const ROW_ACTIONBAR  = 1;
const NUM_ROWS       = 2;

var int rowIndex;
var int actionBarIndex;
var MenuUIActionButtonWindow barBtns[5];
var int barCount;

function OnEnter(ComputerUIWindow s)
{
    local ComputerScreenBulletins bScr;
    local int firstRowId;

    Super.OnEnter(s);

    bScr = ComputerScreenBulletins(s);
    if (bScr == None)
        return;
    if (bScr.lstBulletins == None || bScr.winButtonBar == None)
        return;

    class'ComputerButtonBarNav'.static.CollectButtons(
        bScr.winButtonBar, barBtns, barCount);

    if (bScr.lstBulletins.GetNumRows() > 0)
    {
        rowIndex = ROW_LIST;
        focusIndex = 0;
        focused = bScr.lstBulletins;
        firstRowId = bScr.lstBulletins.IndexToRowId(0);
        bScr.lstBulletins.SetRow(firstRowId, True, True);
    }
    else
    {
        // Empty-list fallback: land on the action bar primary.
        rowIndex = ROW_ACTIONBAR;
        actionBarIndex = class'ComputerButtonBarNav'.static.FindPrimaryIndex(
            bScr.winButtonBar, barBtns, barCount, bScr.ButtonLabelLogout);
        if (actionBarIndex < 0)
            actionBarIndex = 0;
        if (actionBarIndex < barCount)
        {
            focused = barBtns[actionBarIndex];
            screen.SetFocusWindow(focused);
        }
        focusIndex = ROW_ACTIONBAR;
    }
}

function MoveToActionBar()
{
    local ComputerScreenBulletins bScr;

    bScr = ComputerScreenBulletins(screen);
    if (bScr == None)
        return;

    class'ComputerButtonBarNav'.static.CollectButtons(
        bScr.winButtonBar, barBtns, barCount);
    actionBarIndex = class'ComputerButtonBarNav'.static.FindPrimaryIndex(
        bScr.winButtonBar, barBtns, barCount, bScr.ButtonLabelLogout);
    if (actionBarIndex < 0)
        actionBarIndex = 0;

    rowIndex = ROW_ACTIONBAR;
    focusIndex = ROW_ACTIONBAR;
    if (actionBarIndex < barCount)
    {
        focused = barBtns[actionBarIndex];
        screen.SetFocusWindow(focused);
    }
}

function MoveToList()
{
    local ComputerScreenBulletins bScr;
    local int firstRowId;

    bScr = ComputerScreenBulletins(screen);
    if (bScr == None || bScr.lstBulletins == None || bScr.lstBulletins.GetNumRows() <= 0)
        return;
    rowIndex = ROW_LIST;
    focusIndex = 0;
    focused = bScr.lstBulletins;
    firstRowId = bScr.lstBulletins.IndexToRowId(0);
    bScr.lstBulletins.SetRow(firstRowId, True, True);
}

function bool HandleDPad(int dx, int dy)
{
    local ComputerScreenBulletins bScr;
    local int prevRowId, newRowId;

    bScr = ComputerScreenBulletins(screen);
    if (bScr == None)
        return true;

    if (dy == 0 && rowIndex == ROW_ACTIONBAR && dx != 0)
    {
        if (dx < 0)
            actionBarIndex = class'ComputerButtonBarNav'.static.MoveLeft(
                barBtns, barCount, actionBarIndex);
        else
            actionBarIndex = class'ComputerButtonBarNav'.static.MoveRight(
                barBtns, barCount, actionBarIndex);
        if (actionBarIndex < barCount)
        {
            focused = barBtns[actionBarIndex];
            screen.SetFocusWindow(focused);
        }
        return true;
    }

    if (dy == 0)
        return true;  // L/R on list row: no-op

    if (rowIndex == ROW_LIST && bScr.lstBulletins != None)
    {
        prevRowId = bScr.lstBulletins.GetFocusRow();
        if (dy > 0)
            bScr.lstBulletins.MoveRow(MOVELIST_Down, True, True);
        else
            bScr.lstBulletins.MoveRow(MOVELIST_Up, True, True);
        newRowId = bScr.lstBulletins.GetFocusRow();
        if (newRowId == prevRowId)
        {
            // At edge — wrap to action bar (primary).
            MoveToActionBar();
        }
        return true;
    }

    // From ActionBarRow: dy down wraps to list row 0; dy up wraps to list (also row 0).
    if (rowIndex == ROW_ACTIONBAR)
    {
        MoveToList();
        return true;
    }
    return true;
}

function bool HandleActivate(byte button)
{
    if (button != 200)
        return true;

    if (rowIndex == ROW_LIST)
        return true;  // A on list row consumed no-op

    if (rowIndex == ROW_ACTIONBAR
        && focused != None
        && MenuUIActionButtonWindow(focused) != None
        && focused.bIsSensitive)
    {
        MenuUIActionButtonWindow(focused).PressButton();
    }
    return true;
}

// Lists keep the frame (it tells the player which list is the focused
// tab-stop, distinct from the intra-list per-row highlight). Buttons
// suppress per the inherited IsButtonClass policy.
function bool GetFocusedRect(out float x, out float y, out float w, out float h)
{
    if (rowIndex == ROW_LIST && focused != None)
        return Super(ComputerScreenNavSub).GetFocusedRect(x, y, w, h);
    if (rowIndex == ROW_ACTIONBAR)
        return false;  // buttons suppressed
    return false;
}
