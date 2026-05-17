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
    for (i = 0; i < ArrayCount(m.winButtons); i++)
    {
        if (m.winButtons[i] != None && m.winButtons[i].bIsSensitive)
        {
            focused = m.winButtons[i];
            focusIndex = i;
            return;
        }
    }
}

function bool HandleDPad(int dx, int dy)
{
    local MenuUIMenuWindow m;
    local int step, newIdx, i, count;

    if (dy == 0)
        return true;        // L/R consumed, no-op

    m = MenuUIMenuWindow(screen);
    if (m == None)
        return true;

    count = ArrayCount(m.winButtons);
    if (count == 0)
        return true;

    if (dy > 0) step = 1; else step = -1;
    newIdx = focusIndex;
    for (i = 0; i < count; i++)
    {
        newIdx = (newIdx + step + count) % count;
        if (m.winButtons[newIdx] != None && m.winButtons[newIdx].bIsSensitive)
        {
            focusIndex = newIdx;
            focused = m.winButtons[newIdx];
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
