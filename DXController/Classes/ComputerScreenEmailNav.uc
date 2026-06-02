//=============================================================================
// ComputerScreenEmailNav — sub-controller for ComputerScreenEmail.
//
// Rows: [SortHeaderRow(btnHeaderFrom, btnHeaderSubject), lstEmail,
//        ActionBarRow(btnSpecial?, btnLogout)].
// SortHeaderRow primary: btnHeaderFrom. ActionBarRow primary: btnLogout.
//
// btnHeaderFrom/btnHeaderSubject are MenuUIListHeaderButtonWindow which
// inherits MenuUIBorderButtonWindow → ButtonWindow, so PressButton is
// the standard route and MenuNavController.HasStockFocusCue returns
// true for them (frame suppressed).
//
// winEmail (side panel) auto-updates via vanilla ListSelectionChanged.
//=============================================================================
class ComputerScreenEmailNav extends ComputerScreenNavSub;

const ROW_HEADERS    = 0;
const ROW_LIST       = 1;
const ROW_ACTIONBAR  = 2;
const NUM_ROWS       = 3;

const HEADER_FROM    = 0;
const HEADER_SUBJECT = 1;

var int rowIndex;
var int headerIndex;        // 0 = btnHeaderFrom, 1 = btnHeaderSubject
var int actionBarIndex;
var MenuUIActionButtonWindow barBtns[5];
var int barCount;

function OnEnter(ComputerUIWindow s)
{
    local ComputerScreenEmail eScr;
    local int firstRowId;

    Super.OnEnter(s);

    eScr = ComputerScreenEmail(s);
    if (eScr == None)
        return;
    if (eScr.btnHeaderFrom == None || eScr.lstEmail == None || eScr.winButtonBar == None)
        return;

    class'ComputerButtonBarNav'.static.CollectButtons(
        eScr.winButtonBar, barBtns, barCount);

    if (eScr.lstEmail.GetNumRows() > 0)
    {
        rowIndex = ROW_LIST;
        focusIndex = 0;
        focused = eScr.lstEmail;
        firstRowId = eScr.lstEmail.IndexToRowId(0);
        eScr.lstEmail.SetRow(firstRowId, True, True);
    }
    else
    {
        // Empty list — land on SortHeaderRow primary (sort headers
        // stay interactable even with nothing to sort).
        rowIndex = ROW_HEADERS;
        headerIndex = HEADER_FROM;
        SetFocus(eScr.btnHeaderFrom);
        focusIndex = ROW_HEADERS;
    }
}

function MoveToHeaders()
{
    local ComputerScreenEmail eScr;
    eScr = ComputerScreenEmail(screen);
    if (eScr == None || eScr.btnHeaderFrom == None)
        return;
    rowIndex = ROW_HEADERS;
    focusIndex = ROW_HEADERS;
    headerIndex = HEADER_FROM;
    SetFocus(eScr.btnHeaderFrom);
}

function MoveToList()
{
    local ComputerScreenEmail eScr;
    local int firstRowId;
    eScr = ComputerScreenEmail(screen);
    if (eScr == None || eScr.lstEmail == None || eScr.lstEmail.GetNumRows() <= 0)
    {
        MoveToActionBar();
        return;
    }
    rowIndex = ROW_LIST;
    focusIndex = 0;
    focused = eScr.lstEmail;
    firstRowId = eScr.lstEmail.IndexToRowId(0);
    eScr.lstEmail.SetRow(firstRowId, True, True);
}

function MoveToActionBar()
{
    local ComputerScreenEmail eScr;
    eScr = ComputerScreenEmail(screen);
    if (eScr == None)
        return;

    class'ComputerButtonBarNav'.static.CollectButtons(
        eScr.winButtonBar, barBtns, barCount);
    actionBarIndex = class'ComputerButtonBarNav'.static.FindPrimaryIndex(
        eScr.winButtonBar, barBtns, barCount, eScr.ButtonLabelLogout);
    if (actionBarIndex < 0)
        actionBarIndex = 0;
    rowIndex = ROW_ACTIONBAR;
    focusIndex = ROW_ACTIONBAR;
    if (actionBarIndex < barCount)
    {
        SetFocus(barBtns[actionBarIndex]);
    }
}

function bool HandleDPad(int dx, int dy)
{
    local ComputerScreenEmail eScr;
    local int prevRowId, newRowId;

    eScr = ComputerScreenEmail(screen);
    if (eScr == None)
        return true;

    if (dy == 0)
    {
        if (rowIndex == ROW_HEADERS && dx != 0)
        {
            if (dx > 0 && headerIndex == HEADER_FROM)
            {
                headerIndex = HEADER_SUBJECT;
                SetFocus(eScr.btnHeaderSubject);
            }
            else if (dx < 0 && headerIndex == HEADER_SUBJECT)
            {
                headerIndex = HEADER_FROM;
                SetFocus(eScr.btnHeaderFrom);
            }
            return true;
        }
        if (rowIndex == ROW_ACTIONBAR && dx != 0)
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
        return true;  // list L/R: no-op
    }

    // Vertical movement.
    if (rowIndex == ROW_HEADERS)
    {
        if (dy > 0)
            MoveToList();
        else
            MoveToActionBar();  // wrap up
        return true;
    }

    if (rowIndex == ROW_LIST && eScr.lstEmail != None)
    {
        prevRowId = eScr.lstEmail.GetFocusRow();
        if (dy > 0)
            eScr.lstEmail.MoveRow(MOVELIST_Down, True, True);
        else
            eScr.lstEmail.MoveRow(MOVELIST_Up, True, True);
        newRowId = eScr.lstEmail.GetFocusRow();
        if (newRowId == prevRowId)
        {
            if (dy > 0)
                MoveToActionBar();
            else
                MoveToHeaders();
        }
        return true;
    }

    if (rowIndex == ROW_ACTIONBAR)
    {
        if (dy < 0)
            MoveToList();
        else
            MoveToHeaders();  // wrap down
        return true;
    }
    return true;
}

function bool HandleActivate(byte button)
{
    if (button != 200)
        return true;

    if (rowIndex == ROW_LIST)
        return true;  // list-row A: consumed no-op

    // Headers + action bar are both button rows: press whatever's focused.
    if (focused != None
        && MenuUIBorderButtonWindow(focused) != None
        && focused.bIsSensitive)
    {
        MenuUIBorderButtonWindow(focused).PressButton();
    }
    return true;
}

function bool GetFocusedRect(out float x, out float y, out float w, out float h)
{
    if (rowIndex == ROW_LIST && focused != None)
        return Super(ComputerScreenNavSub).GetFocusedRect(x, y, w, h);
    return false;  // headers + action bar: buttons — suppress frame
}
