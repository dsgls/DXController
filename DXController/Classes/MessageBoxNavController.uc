//=============================================================================
// MessageBoxNavController — gamepad nav for MenuUIMessageBoxWindow.
//
// MenuUIMessageBoxWindow has up to three button slots — btnYes, btnNo,
// btnOK — but only two are populated at once:
//   - YesNo mode (mbMode=0): btnNo + btnYes. Engine SetMode focuses btnYes.
//   - OK mode    (mbMode=1): btnOK alone.   Engine SetMode focuses btnOK.
//
// D-pad L/R cycles between btnYes and btnNo in YesNo mode.
// A activates the focused button (PressButton fires the engine's
// ButtonActivated → PostResult pipeline).
//
// No special B handling needed: ControllerRootWindow's IK_Joy2 →
// synthetic-IK_Escape forwarder (Task 8) hits
// MenuUIMessageBoxWindow.VirtualKeyPressed, which already maps Escape
// to PostResult(1) for YesNo (the "No" path) and PostResult(0) for OK.
//=============================================================================
class MessageBoxNavController extends MenuNavController;

function InitFocus()
{
    local MenuUIMessageBoxWindow s;

    s = MenuUIMessageBoxWindow(screen);
    if (s == None)
        return;

    // Match the engine's SetFocusWindow choice in SetMode.
    if (s.btnYes != None)
        focused = s.btnYes;
    else if (s.btnOK != None)
        focused = s.btnOK;
}

function bool HandleDPad(int dx, int dy)
{
    local MenuUIMessageBoxWindow s;
    local string side;

    if (dx == 0)
        return true;        // up/down: consume, no-op

    s = MenuUIMessageBoxWindow(screen);
    if (s == None || s.btnNo == None || s.btnYes == None)
        return true;        // OK-only mode: nothing to cycle between

    // Two-button cycle. Left → No, right → Yes — natural reading order.
    if (dx < 0)
    {
        focused = s.btnNo;
        side = "no";
    }
    else
    {
        focused = s.btnYes;
        side = "yes";
    }
    class'DXControllerDebug'.static.DebugLog("DXC-NAV FOCUS msgbox=" $ side);
    return true;
}

function bool HandleActivate(byte button)
{
    // A = IK_Joy1 = 200. Other buttons (X/Y/R-stick): consume, no-op.
    if (button != 200)
        return true;

    if (focused == None || !focused.bIsSensitive)
        return true;

    MenuUIActionButtonWindow(focused).PressButton();
    return true;
}

function BuildHints()
{
    AddHint("a", "Select");
    AddHint("b", "Cancel");
}

defaultproperties
{
    bAllowRepeat=False
}
