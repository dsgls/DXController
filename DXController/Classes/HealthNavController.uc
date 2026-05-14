//=============================================================================
// HealthNavController — body-region buttons + Heal All.
//
// partButtons[6] indices (from PersonaScreenHealth.uc):
//   0: Head
//   1: Torso
//   2: Right Arm
//   3: Left Arm
//   4: Right Leg
//   5: Left Leg
//
// D-pad up/down walks an anatomical order:
//   head → torso → arms → legs.
// D-pad left/right moves between paired regions (right/left arm, right/left leg).
//=============================================================================
class HealthNavController extends MenuNavController;

// Order used for D-pad up/down traversal (top to bottom of the body).
var int vOrder[6];

function InitFocus()
{
    local PersonaScreenHealth s;
    s = PersonaScreenHealth(screen);
    if (s == None)
        return;
    vOrder[0] = 0;  // Head
    vOrder[1] = 1;  // Torso
    vOrder[2] = 2;  // Right Arm
    vOrder[3] = 3;  // Left Arm
    vOrder[4] = 4;  // Right Leg
    vOrder[5] = 5;  // Left Leg
    focusIndex = 0;
    focused = s.partButtons[vOrder[0]];
}

function bool HandleDPad(int dx, int dy)
{
    local PersonaScreenHealth s;
    local int newIdx, step;

    s = PersonaScreenHealth(screen);
    if (s == None)
        return true;

    if (dy != 0)
    {
        if (dy > 0)
            step = 1;
        else
            step = -1;
        newIdx = (focusIndex + step + 6) % 6;
        focusIndex = newIdx;
        focused = s.partButtons[vOrder[newIdx]];
        class'DXControllerDebug'.static.DebugLog("DXC-NAV FOCUS body=" $ string(vOrder[newIdx]));
        return true;
    }

    if (dx != 0 && s != None)
    {
        // Pair toggle: leave vOrder intact, just swap focused between paired sides.
        // Identify the current side from `focused` directly, not vOrder.
        if (focused == s.partButtons[2])
            focused = s.partButtons[3];
        else if (focused == s.partButtons[3])
            focused = s.partButtons[2];
        else if (focused == s.partButtons[4])
            focused = s.partButtons[5];
        else if (focused == s.partButtons[5])
            focused = s.partButtons[4];
        // head/torso (partButtons[0]/[1]): no pair, fall through to no-op.
        return true;
    }
    return true;
}

function bool HandleActivate(byte button)
{
    if (button != 200)   // IK_Joy1 (A) = 0xC8 = 200 — enum not reachable from Object scope
        return true;
    if (focused != None && ButtonWindow(focused) != None && focused.bIsSensitive)
        ButtonWindow(focused).PressButton();
    return true;
}
