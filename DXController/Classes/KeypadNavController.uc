//=============================================================================
// KeypadNavController — gamepad nav for HUDKeypadWindow's 4x3 numeric keypad.
//
// btnKeys[0..11] is row-major:
//   0  1  2     ("1" "2" "3")
//   3  4  5     ("4" "5" "6")
//   6  7  8     ("7" "8" "9")
//   9 10 11     ("*" "0" "#")
//
// D-pad wraps on both axes. A presses the focused key (vanilla
// PressButton path: tone, append digit, validate on full length).
// B closes the window via root.PopWindow() — HUDKeypadWindow doesn't
// handle Escape, so the root's Escape-synthesis path is a dead end;
// AllowsMenuToggle=false sends B to HandleActivate instead.
//
// Verification (2026-06-02 focus-indicator migration): HUDKeypadButton
// has no engine-focus or selection stock cue — its DrawWindow does not
// consult IsFocusWindow. The MenuFocusOverlay frame is therefore the
// only indicator, which is correct per the policy. This controller
// stays out of HasStockFocusCue.
//=============================================================================
class KeypadNavController extends MenuNavController;

const COLS = 3;
const ROWS = 4;

function InitFocus()
{
    local HUDKeypadWindow s;

    s = HUDKeypadWindow(screen);
    if (s == None)
        return;
    focusIndex = 0;
    focused = s.btnKeys[0];
}

function bool HandleDPad(int dx, int dy)
{
    local HUDKeypadWindow s;
    local int col, row;

    s = HUDKeypadWindow(screen);
    if (s == None)
        return true;

    col = focusIndex % COLS;
    row = focusIndex / COLS;

    if (dx != 0)
        col = (col + dx + COLS) % COLS;
    if (dy != 0)
        row = (row + dy + ROWS) % ROWS;

    focusIndex = row * COLS + col;
    focused = s.btnKeys[focusIndex];

    class'DXControllerDebug'.static.DebugLog(
        "DXC-NAV FOCUS keypad=" $ string(focusIndex));
    return true;
}

function bool HandleActivate(byte button)
{
    local HUDKeypadWindow s;
    local Window root;

    // B (201): close the window.
    if (button == 201)
    {
        s = HUDKeypadWindow(screen);
        if (s != None)
        {
            root = s.GetRootWindow();
            if (root != None)
                DeusExRootWindow(root).PopWindow();
        }
        return true;
    }

    // A (200): press focused key. Other buttons consumed.
    if (button != 200)
        return true;

    if (focused != None && ButtonWindow(focused) != None && focused.bIsSensitive)
        ButtonWindow(focused).PressButton();
    return true;
}

function bool AllowsMenuToggle()
{
    return false;
}

function BuildHints()
{
    AddHint("a", "Press");
    AddHint("b", "Cancel");
}

defaultproperties
{
    bAllowRepeat=False
}
