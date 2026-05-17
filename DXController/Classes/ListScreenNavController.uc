//=============================================================================
// ListScreenNavController — abstract base for list-shape menu screens.
//
// Shared by MenuScreenLoadGame, MenuScreenSaveGame, MenuScreenThemesLoad,
// MenuScreenThemesSave. All four have:
//   - One MenuUIListWindow.
//   - A bottom action button bar with at least one AB_Other-keyed
//     button ("LOAD" or "SAVE"). Load/Save games additionally have
//     a "DELETE" button.
//
// Subclasses override InitListAndButtons() to populate `lst`,
// `primaryBtn`, and (optionally) `secondaryBtn` from their screen-
// specific field names.
//
// D-pad up/down: walk rows via MenuUIListWindow.MoveRow with edge wrap.
// A button:      press primaryBtn  (e.g. Load / Save / Apply Theme).
// X button:      press secondaryBtn if bound (Load/Save Game: Delete).
// Y / R-stick:   consumed, no-op.
//=============================================================================
class ListScreenNavController extends MenuNavController
    abstract;

var MenuUIListWindow         lst;
var MenuUIActionButtonWindow primaryBtn;
var MenuUIActionButtonWindow secondaryBtn;

// Legend labels, set per subclass in defaultproperties. primaryHintLabel
// is the A-button effect; secondaryHintLabel is the X-button effect, or
// "" when the subclass has no secondaryBtn (Themes Load/Save).
var string primaryHintLabel;
var string secondaryHintLabel;

// Subclasses override to populate lst, primaryBtn, secondaryBtn from
// `screen`. The base class never names a concrete screen type.
function InitListAndButtons();

// InitFocus selects row 0 only if the list is non-empty AND the list
// wasn't already pointed at a row by the screen (e.g., MenuScreenLoadGame
// calls SetFocusWindow(lstGames) but doesn't choose a row — GetFocusRow
// can return -1). We mark `focused = lst` as a sentinel once selection
// succeeds: that stops ControllerRootWindow.Tick from re-calling
// InitFocus every frame (Tick gates on `focused == None`). Without the
// sentinel, Tick would reset the row to 0 on every frame, making D-pad
// navigation appear dead — every press would advance one row, then the
// next Tick would slam it back to 0.
function InitFocus()
{
    InitListAndButtons();
    if (lst == None || lst.GetNumRows() <= 0)
        return;     // not ready yet — Tick will retry

    // Only seed selection if no row is currently focused. If the user
    // (or the screen's own InitWindow) already chose a row, leave it.
    if (lst.GetFocusRow() < 0)
        lst.SetRow(lst.IndexToRowId(0), True, True);

    focused = lst;
    focusIndex = lst.RowIdToIndex(lst.GetFocusRow());
}

function bool HandleDPad(int dx, int dy)
{
    local int prev, cur;

    if (dy == 0 || lst == None || lst.GetNumRows() <= 0)
        return true;

    prev = lst.GetFocusRow();
    if (dy > 0)
        lst.MoveRow(MOVELIST_Down, True, True);
    else
        lst.MoveRow(MOVELIST_Up, True, True);
    cur = lst.GetFocusRow();

    if (cur == prev)        // edge — wrap to the other end
    {
        if (dy > 0)
            lst.MoveRow(MOVELIST_Home, True, True);
        else
            lst.MoveRow(MOVELIST_End, True, True);
    }

    focusIndex = lst.RowIdToIndex(lst.GetFocusRow());
    // Leave `focused` as the sentinel (lst) so Tick doesn't reset us.
    class'DXControllerDebug'.static.DebugLog(
        "DXC-NAV FOCUS list row=" $ string(focusIndex));
    return true;
}

function bool HandleActivate(byte button)
{
    // A = IK_Joy1 = 200; X = IK_Joy3 = 202. Literal byte values
    // because EInputKey isn't in scope from Object subclasses
    // (CLAUDE.md "EInputKey is not in scope from controllers").
    if (button == 200 && primaryBtn != None && primaryBtn.bIsSensitive)
    {
        primaryBtn.PressButton();
        return true;
    }
    if (button == 202 && secondaryBtn != None && secondaryBtn.bIsSensitive)
    {
        secondaryBtn.PressButton();
        return true;
    }
    return true;            // consume Y / R-stick
}

// Rows aren't Window objects, so the focus overlay can't draw a frame
// around them — the native list draws its own highlight.
function bool GetFocusedRect(out float x, out float y, out float w, out float h)
{
    return false;
}

// A presses primaryBtn, X presses secondaryBtn (when bound). B backs out
// of the menu screen via the root window's Escape synthesis. Labels come
// from the per-subclass defaultproperties.
function BuildHints()
{
    AddHint("a", primaryHintLabel);
    if (secondaryHintLabel != "")
        AddHint("x", secondaryHintLabel);
    AddHint("b", "Back");
}

defaultproperties
{
    bAllowRepeat=True
}
