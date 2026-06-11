//=============================================================================
// ComputerScreenBulletinsNav — sub-controller for ComputerScreenBulletins.
//
// Focus lives on lstBulletins; the action bar is reached by d-pad only
// via the empty-list fallback. Logout = B (escapeAction "EXIT"),
// Special Options = X shortcut (when present).
//
// winBulletin (side panel) is read-only and auto-updated by vanilla
// ListSelectionChanged — no script-side display call needed.
//
// D-pad inside list: edge-detect via GetFocusRow() before/after MoveRow.
// At edge, selection wraps to the opposite end of the list.
// A on list row: consumed no-op (selection drives auto-display).
// R-stick Y scrolls winBulletin's MenuUIScrollAreaWindow.
//=============================================================================
class ComputerScreenBulletinsNav extends ComputerScreenNavSub;

const ROW_LIST       = 0;
const ROW_ACTIONBAR  = 1;

// R-stick smooth scroll of the bulletin body (matches ComputerScreenEmailNav).
const ScrollDeadzone  = 10.0;
const ScrollThreshold = 500.0;

var int rowIndex;
var int actionBarIndex;
var MenuUIActionButtonWindow barBtns[5];
var int barCount;
var float scrollAccum;

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
            SetFocus(barBtns[actionBarIndex]);
        }
        focusIndex = ROW_ACTIONBAR;
    }
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
            SetFocus(barBtns[actionBarIndex]);
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
            // At edge — wrap selection to the opposite end of the list.
            if (dy > 0)
                newRowId = bScr.lstBulletins.IndexToRowId(0);
            else
                newRowId = bScr.lstBulletins.IndexToRowId(
                    bScr.lstBulletins.GetNumRows() - 1);
            bScr.lstBulletins.SetRow(newRowId, True, True);
        }
        return true;
    }

    // Action bar is focused only via the empty-list fallback; with no
    // list rows to move to, vertical d-pad is a consumed no-op.
    return true;
}

function bool HandleActivate(byte button)
{
    local ComputerScreenBulletins bScr;

    // X — Special Options shortcut (the button exists only when the
    // terminal has special options).
    if (button == 202)
    {
        bScr = ComputerScreenBulletins(screen);
        if (bScr != None && bScr.btnSpecial != None && bScr.btnSpecial.bIsSensitive)
            bScr.btnSpecial.PressButton();
        return true;
    }

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
// suppress per the inherited MenuNavController.HasStockFocusCue policy.
function bool GetFocusedRect(out float x, out float y, out float w, out float h)
{
    if (rowIndex == ROW_LIST && focused != None)
        return Super(ComputerScreenNavSub).GetFocusedRect(x, y, w, h);
    if (rowIndex == ROW_ACTIONBAR)
        return false;  // buttons suppressed
    return false;
}

// R-stick Y scrolls winBulletin's MenuUIScrollAreaWindow (parent's-parent
// of the text window — see CreateBulletinViewWindow). Positive ry = stick
// up = content scrolls toward the top = StepUp.
function bool HandleScroll(float ry)
{
    local ComputerScreenBulletins bScr;
    local MenuUIScrollAreaWindow winScroll;

    bScr = ComputerScreenBulletins(screen);
    if (bScr == None || bScr.winBulletin == None)
        return false;

    if (Abs(ry) < ScrollDeadzone)
    {
        scrollAccum = 0.0;
        return false;
    }

    scrollAccum += ry;
    if (Abs(scrollAccum) < ScrollThreshold)
        return true;

    winScroll = MenuUIScrollAreaWindow(bScr.winBulletin.GetParent().GetParent());
    if (winScroll == None || winScroll.vScale == None)
    {
        scrollAccum = 0.0;
        return false;
    }

    if (scrollAccum > 0.0)
        winScroll.vScale.MoveThumb(MOVETHUMB_StepUp);
    else
        winScroll.vScale.MoveThumb(MOVETHUMB_StepDown);

    scrollAccum = 0.0;
    return true;
}

function ClearAxisCache()
{
    scrollAccum = 0.0;
}

function bool BuildHints(MenuNavController nav)
{
    local ComputerScreenBulletins bScr;

    bScr = ComputerScreenBulletins(screen);
    if (bScr != None && bScr.btnSpecial != None)
        nav.AddHint("x", "Special");
    nav.AddHint("rs", "Scroll text");
    return false;   // fall through to dispatcher's default strip
}
