//=============================================================================
// LogsNavController — gamepad navigation for PersonaScreenLogs.
//
// PersonaScreenLogs presents a PersonaListWindow (lstLogs) inside a
// PersonaScrollAreaWindow (winScroll). Each row contains a plain-text log
// entry; selecting a row just highlights it — there is no secondary display
// panel (unlike Images). The winScroll scrollbar scrolls the list itself.
//
// D-pad up/down walks lstLogs one row at a time with wrap-around.
// R-stick Y scrolls winScroll (the scroll area that wraps lstLogs).
// A/X/Y/R-stick-click are consumed as no-ops (row highlight is automatic).
//=============================================================================
class LogsNavController extends MenuNavController;

// Accumulator for R-stick smooth scroll.
const ScrollDeadzone  = 10.0;    // raw axis units; ignore small stick deflections
const ScrollThreshold = 500.0;   // accumulated units before one MoveThumb step

var float scrollAccum;

// ----------------------------------------------------------------------
// InitFocus — select the first log row on attach.
//
// SetRow fires the native selection machinery, highlighting the first row.
// There is no ListSelectionChanged on this screen; the row text is the
// content, so selecting it is sufficient.
// ----------------------------------------------------------------------

function InitFocus()
{
    local PersonaScreenLogs s;
    local int firstRowId;

    focused = None;
    focusIndex = 0;
    scrollAccum = 0.0;

    s = PersonaScreenLogs(screen);
    if (s == None || s.lstLogs == None)
        return;                       // screen not built yet — retry next frame
    if (s.lstLogs.GetNumRows() <= 0)
        return;                       // list not populated yet — retry next frame

    firstRowId = s.lstLogs.IndexToRowId(0);
    // bSelect=True, bClearRows=True → selects and scrolls into view.
    s.lstLogs.SetRow(firstRowId, True, True);

    // List is populated and the first row selected; one-time init done.
    // Without this the Tick retry would re-run InitFocus every frame
    // (focused stays None on list screens) and snap selection to row 0.
    bFocusInitDone = True;
}

// ----------------------------------------------------------------------
// HandleDPad — move list focus up or down, with wrap.
// ----------------------------------------------------------------------

function bool HandleDPad(int dx, int dy)
{
    local PersonaScreenLogs s;
    local int prevRowId, newRowId, newIndex, numRows;

    if (dy == 0)
        return true;

    s = PersonaScreenLogs(screen);
    if (s == None || s.lstLogs == None)
        return true;

    numRows = s.lstLogs.GetNumRows();
    if (numRows <= 0)
        return true;

    prevRowId = s.lstLogs.GetFocusRow();

    if (dy > 0)
        s.lstLogs.MoveRow(MOVELIST_Down, True, True);
    else
        s.lstLogs.MoveRow(MOVELIST_Up, True, True);

    newRowId = s.lstLogs.GetFocusRow();

    // If focus didn't move, we're at an edge — wrap to the other end.
    if (newRowId == prevRowId)
    {
        if (dy > 0)
            s.lstLogs.MoveRow(MOVELIST_Home, True, True);
        else
            s.lstLogs.MoveRow(MOVELIST_End, True, True);

        newRowId = s.lstLogs.GetFocusRow();
    }

    newIndex = s.lstLogs.RowIdToIndex(newRowId);
    focusIndex = newIndex;
    focused = None;

    class'DXControllerDebug'.static.DebugLog("DXC-NAV FOCUS logs row=" $ string(focusIndex));
    return true;
}

// ----------------------------------------------------------------------
// HandleScroll — R-stick Y scrolls the log list's scroll area.
//
// winScroll is a direct field on PersonaScreenLogs; no parent-chain walk
// needed. Positive ry = stick pushed up = scroll content up = StepUp.
// ----------------------------------------------------------------------

function bool HandleScroll(float ry)
{
    local PersonaScreenLogs s;

    s = PersonaScreenLogs(screen);
    if (s == None || s.winScroll == None)
        return false;

    if (Abs(ry) < ScrollDeadzone)
    {
        scrollAccum = 0.0;
        return false;
    }

    scrollAccum += ry;

    if (Abs(scrollAccum) < ScrollThreshold)
        return true;

    if (s.winScroll.vScale == None)
    {
        scrollAccum = 0.0;
        return false;
    }

    if (scrollAccum > 0.0)
        s.winScroll.vScale.MoveThumb(MOVETHUMB_StepUp);
    else
        s.winScroll.vScale.MoveThumb(MOVETHUMB_StepDown);

    scrollAccum = 0.0;
    return true;
}

// ----------------------------------------------------------------------
// GetFocusedRect — no overlay frame on this screen.
// ----------------------------------------------------------------------

function bool GetFocusedRect(out float x, out float y, out float w, out float h)
{
    return false;
}

// ----------------------------------------------------------------------
// HandleActivate — consumed no-op.
//
// Selecting a row via D-pad already highlights it; A/X/Y/R-stick-click
// are redundant and are consumed to prevent fallthrough.
// ----------------------------------------------------------------------

function bool HandleActivate(byte button)
{
    return true;
}

function BuildHints()
{
    AddHint("rs", "Scroll");
    AddHint("lb", "Prev tab");
    AddHint("rb", "Next tab");
    AddHint("b", "Close");
}

defaultproperties
{
    bAllowRepeat=True
}
