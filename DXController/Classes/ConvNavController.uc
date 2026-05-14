//=============================================================================
// ConvNavController — gamepad navigation for PersonaScreenConversations.
//
// PersonaScreenConversations presents:
//   lstCons   — PersonaListWindow (inside winScroll's clipWindow) listing all
//               conversation history entries.
//   conWindow — TileWindow (inside a PersonaScrollAreaWindow created by
//               CreateScrollTileWindow) displaying the selected conversation's
//               full text in the lower panel.
//
// Selecting a row in lstCons automatically fires the screen's own
// ListSelectionChanged event, which calls DisplayHistory() and populates
// conWindow. No explicit call is needed here.
//
// D-pad up/down walks lstCons one row at a time with wrap-around.
// R-stick Y scrolls the conWindow scroll area (the lower conversation text).
// A/X/Y/R-stick-click are consumed as no-ops (row highlight is automatic).
//
// conWindow scroll path: TileWindow.GetParent() -> clipWindow ->
//                        GetParent() -> PersonaScrollAreaWindow -> vScale
//=============================================================================
class ConvNavController extends MenuNavController;

// Accumulator for R-stick smooth scroll.
const ScrollDeadzone  = 200.0;   // raw axis units; ignore small stick deflections
const ScrollThreshold = 500.0;   // accumulated units before one MoveThumb step

var float scrollAccum;

// ----------------------------------------------------------------------
// InitFocus — select the first conversation row on attach.
//
// SetRow fires the native selection machinery, highlighting the first row
// and triggering ListSelectionChanged on the screen, which populates
// conWindow via DisplayHistory().
// ----------------------------------------------------------------------

function InitFocus()
{
    local PersonaScreenConversations s;
    local int firstRowId;

    focused = None;
    focusIndex = 0;
    scrollAccum = 0.0;

    s = PersonaScreenConversations(screen);
    if (s == None || s.lstCons == None)
        return;
    if (s.lstCons.GetNumRows() <= 0)
        return;

    firstRowId = s.lstCons.IndexToRowId(0);
    // bSelect=True, bClearRows=True → selects and scrolls into view.
    // Also fires ListSelectionChanged, populating conWindow automatically.
    s.lstCons.SetRow(firstRowId, True, True);
}

// ----------------------------------------------------------------------
// HandleDPad — move list focus up or down, with wrap.
//
// MoveRow fires ListSelectionChanged on the screen, so conWindow is
// updated automatically after each move.
// ----------------------------------------------------------------------

function bool HandleDPad(int dx, int dy)
{
    local PersonaScreenConversations s;
    local int prevRowId, newRowId, newIndex, numRows;

    if (dy == 0)
        return true;

    s = PersonaScreenConversations(screen);
    if (s == None || s.lstCons == None)
        return true;

    numRows = s.lstCons.GetNumRows();
    if (numRows <= 0)
        return true;

    prevRowId = s.lstCons.GetFocusRow();

    if (dy > 0)
        s.lstCons.MoveRow(MOVELIST_Down, True, True);
    else
        s.lstCons.MoveRow(MOVELIST_Up, True, True);

    newRowId = s.lstCons.GetFocusRow();

    // If focus didn't move, we're at an edge — wrap to the other end.
    if (newRowId == prevRowId)
    {
        if (dy > 0)
            s.lstCons.MoveRow(MOVELIST_Home, True, True);
        else
            s.lstCons.MoveRow(MOVELIST_End, True, True);

        newRowId = s.lstCons.GetFocusRow();
    }

    newIndex = s.lstCons.RowIdToIndex(newRowId);
    focusIndex = newIndex;
    focused = None;

    class'DXControllerDebug'.static.DebugLog("DXC-NAV FOCUS conv row=" $ string(focusIndex));
    return true;
}

// ----------------------------------------------------------------------
// HandleScroll — R-stick Y scrolls the lower conversation text panel.
//
// conWindow is a TileWindow returned by CreateScrollTileWindow, which
// wraps it in a PersonaScrollAreaWindow internally. Walk up two levels
// to reach that scroll area: TileWindow -> clipWindow -> PersonaScrollAreaWindow.
// Positive ry = stick pushed up = scroll content up = StepUp.
// ----------------------------------------------------------------------

function bool HandleScroll(float ry)
{
    local PersonaScreenConversations s;
    local PersonaScrollAreaWindow winConScroll;

    s = PersonaScreenConversations(screen);
    if (s == None || s.conWindow == None)
        return false;

    if (Abs(ry) < ScrollDeadzone)
    {
        scrollAccum = 0.0;
        return false;
    }

    scrollAccum += ry;

    if (Abs(scrollAccum) < ScrollThreshold)
        return true;

    // TileWindow -> clipWindow -> PersonaScrollAreaWindow
    winConScroll = PersonaScrollAreaWindow(s.conWindow.GetParent().GetParent());
    if (winConScroll == None || winConScroll.vScale == None)
    {
        scrollAccum = 0.0;
        return false;
    }

    if (scrollAccum > 0.0)
        winConScroll.vScale.MoveThumb(MOVETHUMB_StepUp);
    else
        winConScroll.vScale.MoveThumb(MOVETHUMB_StepDown);

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
// Selecting a row via D-pad already highlights it and populates conWindow
// via ListSelectionChanged; A/X/Y/R-stick-click are redundant and are
// consumed to prevent fallthrough.
// ----------------------------------------------------------------------

function bool HandleActivate(byte button)
{
    return true;
}

defaultproperties
{
    bAllowRepeat=True
}
