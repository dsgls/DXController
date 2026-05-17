//=============================================================================
// HealthNavController — per-region Heal buttons + Heal All.
//
// Targets the actual heal buttons, NOT the body-part description icons
// (partButtons[], whose only effect is to show body-part lore in winInfo):
//   regionWindows[0..5].btnHeal  (Head, Torso, R-Arm, L-Arm, R-Leg, L-Leg)
//   btnHealAll
//
// focusIndex 0..5 = body region (= partButtons / regionWindows index),
// focusIndex 6    = Heal All.
//
// D-pad up/down walks head -> torso -> arms -> legs -> Heal All (cyclic).
// D-pad left/right toggles between paired regions (R/L arm, R/L leg).
// On each focus change the matching body-part icon is selected so the
// region highlight and description panel track gamepad focus.
//=============================================================================
class HealthNavController extends MenuNavController;

// Sets `focused` from the current focusIndex and drives the region
// selection so the highlight + description panel follow gamepad focus.
function ApplyFocus()
{
    local PersonaScreenHealth s;

    s = PersonaScreenHealth(screen);
    if (s == None)
        return;

    if (focusIndex == 6)   // Heal All
    {
        focused = s.btnHealAll;
        return;
    }

    if (s.regionWindows[focusIndex] != None)
        focused = s.regionWindows[focusIndex].btnHeal;

    if (s.partButtons[focusIndex] != None && s.partButtons[focusIndex].bIsSensitive)
        s.partButtons[focusIndex].PressButton();
}

function InitFocus()
{
    if (PersonaScreenHealth(screen) == None)
        return;
    focusIndex = 0;
    ApplyFocus();
}

function bool HandleDPad(int dx, int dy)
{
    if (PersonaScreenHealth(screen) == None)
        return true;

    if (dy != 0)
    {
        if (dy > 0)
            focusIndex = (focusIndex + 1) % 7;   // down the body, toward legs
        else
            focusIndex = (focusIndex + 6) % 7;
        ApplyFocus();
        class'DXControllerDebug'.static.DebugLog("DXC-NAV FOCUS heal=" $ string(focusIndex));
        return true;
    }

    if (dx != 0)
    {
        // Pair toggle between paired sides; head/torso/Heal All have no pair.
        if (focusIndex == 2)
            focusIndex = 3;
        else if (focusIndex == 3)
            focusIndex = 2;
        else if (focusIndex == 4)
            focusIndex = 5;
        else if (focusIndex == 5)
            focusIndex = 4;
        else
            return true;
        ApplyFocus();
        class'DXControllerDebug'.static.DebugLog("DXC-NAV FOCUS heal=" $ string(focusIndex));
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

function BuildHints()
{
    AddHint("a", "Heal");
    AddHint("lb", "Prev tab");
    AddHint("rb", "Next tab");
    AddHint("b", "Close");
}
