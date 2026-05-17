//=============================================================================
// ImagesNavController — gamepad navigation for PersonaScreenImages.
//
// PersonaScreenImages presents a PersonaListWindow (lstImages) containing one
// row per DataVaultImage the player carries. Selecting a row fires the screen's
// ListSelectionChanged event, which calls SetImage() to display the chosen
// image on the right panel. No per-row button children exist; all selection
// state is managed by the ListWindow's native row API.
//
// D-pad up/down walks lstImages one row at a time with wrap-around. A (and the
// other confirm buttons) are consumed as no-ops: the auto-display on row focus
// already shows the image, so a separate "confirm" action is redundant.
//=============================================================================
class ImagesNavController extends MenuNavController;

// ----------------------------------------------------------------------
// InitFocus — select the first image row on attach.
//
// SetRow fires ListSelectionChanged → SetImage, so the right panel
// immediately shows the first image without requiring an extra button press.
// ----------------------------------------------------------------------

function InitFocus()
{
    local PersonaScreenImages s;
    local int firstRowId;

    focused = None;
    focusIndex = 0;

    s = PersonaScreenImages(screen);
    if (s == None || s.lstImages == None)
        return;
    if (s.lstImages.GetNumRows() <= 0)
        return;

    firstRowId = s.lstImages.IndexToRowId(0);
    // bSelect=True, bClearRows=True → selects and scrolls into view.
    // Fires ListSelectionChanged → SetImage on the screen.
    s.lstImages.SetRow(firstRowId, True, True);
}

// ----------------------------------------------------------------------
// HandleDPad — move list focus up or down, with wrap.
//
// MoveRow(MOVELIST_Down) does nothing when already on the last row, so
// we detect wrap by comparing focusIndex before and after and jumping to
// the opposite end when no movement occurred.
// ----------------------------------------------------------------------

function bool HandleDPad(int dx, int dy)
{
    local PersonaScreenImages s;
    local int prevRowId, newRowId, newIndex, numRows;

    if (dy == 0)
        return true;

    s = PersonaScreenImages(screen);
    if (s == None || s.lstImages == None)
        return true;

    numRows = s.lstImages.GetNumRows();
    if (numRows <= 0)
        return true;

    prevRowId = s.lstImages.GetFocusRow();

    if (dy > 0)
        s.lstImages.MoveRow(MOVELIST_Down, True, True);
    else
        s.lstImages.MoveRow(MOVELIST_Up, True, True);

    newRowId = s.lstImages.GetFocusRow();

    // If focus didn't move, we're at an edge — wrap to the other end.
    if (newRowId == prevRowId)
    {
        if (dy > 0)
            s.lstImages.MoveRow(MOVELIST_Home, True, True);
        else
            s.lstImages.MoveRow(MOVELIST_End, True, True);

        newRowId = s.lstImages.GetFocusRow();
    }

    newIndex = s.lstImages.RowIdToIndex(newRowId);
    focusIndex = newIndex;
    // focused is not a Window child in this screen; keep it None so
    // GetFocusedRect returns false and the overlay doesn't draw a frame.
    focused = None;

    class'DXControllerDebug'.static.DebugLog("DXC-NAV FOCUS images row=" $ string(focusIndex));
    return true;
}

// ----------------------------------------------------------------------
// GetFocusedRect — no window-level focus overlay on this screen.
//
// lstImages is a native ListWindow; its rows are not Window objects and
// have no screen rect we can easily surface to MenuFocusOverlay. The list
// renders its own focus highlight, so no overlay frame is needed.
// ----------------------------------------------------------------------

function bool GetFocusedRect(out float x, out float y, out float w, out float h)
{
    return false;
}

// ----------------------------------------------------------------------
// HandleActivate — consumed no-op.
//
// A button (200 = IK_Joy1 = 0xC8), X, Y, and R-stick-click are all
// redundant here: selecting a row via D-pad already displays the image.
// Consuming them prevents accidental button-press sounds or fallthrough.
// ----------------------------------------------------------------------

function bool HandleActivate(byte button)
{
    return true;   // consume A / X / Y / R-stick-click — all no-ops
}

// PersonaScreenImages has no per-row activation — A is a no-op, and
// selecting a row with the D-pad already displays the image. So the
// legend advertises only the persona-common controls (tab cycling and
// menu close) that ControllerRootWindow handles for every persona
// screen.
function BuildHints()
{
    AddHint("lb", "Prev tab");
    AddHint("rb", "Next tab");
    AddHint("back", "Close");
}

defaultproperties
{
    bAllowRepeat=True
}
