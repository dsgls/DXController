//=============================================================================
// MenuMainNavController — D-pad navigation for MenuMain (the title screen /
// pause-menu root).
//
// MenuMain extends MenuUIMenuWindow (not MenuUIScreenWindow). Its
// children are MenuUIMenuButtonWindow instances stored in the typed
// winButtons[10] array, populated by MenuUIMenuWindow.CreateMenuButtons
// in declaration order (which matches visual top-to-bottom Y).
//
// A button:      presses the focused button — fires
//                MenuUIMenuWindow.ButtonActivated → ProcessMenuAction
//                (MA_MenuScreen / MA_NewGame / MA_Quit / etc.).
// D-pad up/down: moves focus to the next sensitive winButtons[i] slot,
//                wrapping at edges.
// D-pad L/R:     consumed, no-op (MenuUIMenuButtonWindow has no cycle).
// X / Y / R-stick: consumed, no-op.
//
// SetFocus on each focus update drives the vanilla yellow-text cue on
// the focused MenuUIMenuButtonWindow (engine-focus-driven via
// MenuUIBorderButtonWindow's SetButtonMetrics). The overlay frame is
// suppressed by the base GetFocusedRect via HasStockFocusCue.
//=============================================================================
class MenuMainNavController extends MenuNavController;

function InitFocus()
{
    local MenuUIMenuWindow m;
    local int i;

    m = MenuUIMenuWindow(screen);
    if (m == None)
        return;

    focused = None;
    focusIndex = -1;

    // Prefer whichever button vanilla InitWindow already gave engine
    // focus to (MenuSelectDifficulty.InitWindow calls
    // SetFocusWindow(winButtons[1]) so "Medium" is the default). Without
    // this our cursor would seed on winButtons[0] (the first sensitive
    // slot) while the visible yellow-text cue stayed on vanilla's
    // choice — leaving gamepad nav out of sync with the visible cue.
    for (i = 0; i < ArrayCount(m.winButtons); i++)
    {
        if (m.winButtons[i] != None
            && m.winButtons[i].bIsSensitive
            && m.winButtons[i].IsFocusWindow())
        {
            focusIndex = i;
            SetFocus(m.winButtons[i]);
            return;
        }
    }

    // No engine-focused button — fall back to first sensitive slot.
    for (i = 0; i < ArrayCount(m.winButtons); i++)
    {
        if (m.winButtons[i] != None && m.winButtons[i].bIsSensitive)
        {
            focusIndex = i;
            SetFocus(m.winButtons[i]);
            return;
        }
    }
}

function bool HandleDPad(int dx, int dy)
{
    local MenuUIMenuWindow m;
    local int step, newIdx, i, count, curIdx;

    if (dy == 0)
        return true;        // L/R consumed, no-op

    m = MenuUIMenuWindow(screen);
    if (m == None)
        return true;

    count = ArrayCount(m.winButtons);
    if (count == 0)
        return true;

    // Re-derive the current position from engine focus, not from our
    // cached focusIndex. Vanilla SetFocusWindow calls from the screen's
    // own InitWindow can land AFTER our InitFocus runs (notably
    // MenuSelectDifficulty.InitWindow → SetFocusWindow(winButtons[1])
    // for the "Medium" default), so our focusIndex may have been seeded
    // on Easy while the visible yellow text is on Medium. Reading
    // IsFocusWindow here lets the first press step relative to whatever
    // is actually focused. Falls through to focusIndex if no button is
    // engine-focused.
    curIdx = focusIndex;
    for (i = 0; i < count; i++)
    {
        if (m.winButtons[i] != None && m.winButtons[i].IsFocusWindow())
        {
            curIdx = i;
            break;
        }
    }

    if (dy > 0) step = 1; else step = -1;
    newIdx = curIdx;
    for (i = 0; i < count; i++)
    {
        newIdx = (newIdx + step + count) % count;
        if (m.winButtons[newIdx] != None && m.winButtons[newIdx].bIsSensitive)
        {
            focusIndex = newIdx;
            SetFocus(m.winButtons[newIdx]);
            class'DXControllerDebug'.static.DebugLog(
                "DXC-NAV FOCUS menumain idx=" $ string(focusIndex));
            return true;
        }
    }
    return true;            // no sensitive slot found — consume anyway
}

function bool HandleActivate(byte button)
{
    // A button — IK_Joy1 = 0xC8 = 200. EInputKey is not reachable from
    // Object scope, so compare against the literal byte value. See
    // CLAUDE.md "EInputKey is not in scope from controllers".
    if (button != 200)
        return true;        // consume X/Y/R-stick

    if (focused == None || !focused.bIsSensitive)
        return true;

    // PressButton() is on ButtonWindow; firing it triggers
    // MenuUIMenuWindow.ButtonActivated upstream, which routes to
    // ProcessMenuAction (MA_MenuScreen / MA_NewGame / MA_Quit / etc.).
    ButtonWindow(focused).PressButton();
    return true;
}

function BuildHints()
{
    AddHint("a", "Select");
    AddHint("b", "Back");
}

defaultproperties
{
    bAllowRepeat=True
}
