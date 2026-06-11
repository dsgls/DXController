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
// D-pad navigation follows the silhouette's row layout (screen order,
// mirrored — the right arm/leg draw on the left):
//
//                Head
//     R-Arm      Torso      L-Arm
//          R-Leg      L-Leg
//               Heal All
//
// Left/right moves within a row, wrapping. Up/down moves between rows,
// keeping the horizontal side (R-Arm <-> R-Leg, L-Arm <-> L-Leg; Torso
// goes down to R-Leg), and cycles vertically through Heal All back to
// Head. Encoded as static per-direction target tables below.
// On each focus change the matching body-part icon is selected so the
// region highlight and description panel track gamepad focus.
//
// SetFocus drives the vanilla yellow-text cue on the focused heal
// button (PersonaActionButtonWindow inherits the engine-focus cue
// from PersonaBorderButtonWindow). The body-region silhouette
// highlight (driven by partButtons[focusIndex].PressButton) remains
// the primary cue. Overlay frame is suppressed by the base
// GetFocusedRect via HasStockFocusCue.
//=============================================================================
class HealthNavController extends MenuNavController;

// Static per-direction nav tables, indexed by focusIndex (0=Head,
// 1=Torso, 2=R-Arm, 3=L-Arm, 4=R-Leg, 5=L-Leg, 6=Heal All). A node
// mapping to itself means "no move in that direction".
var byte upTarget[7];
var byte downTarget[7];
var byte leftTarget[7];
var byte rightTarget[7];

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
        SetFocus(s.btnHealAll);
        return;
    }

    if (s.regionWindows[focusIndex] != None)
        SetFocus(s.regionWindows[focusIndex].btnHeal);

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
    local int target;

    if (PersonaScreenHealth(screen) == None)
        return true;
    if (focusIndex < 0 || focusIndex > 6)
        return true;

    target = focusIndex;
    if (dy > 0)
        target = downTarget[focusIndex];
    else if (dy < 0)
        target = upTarget[focusIndex];
    else if (dx > 0)
        target = rightTarget[focusIndex];
    else if (dx < 0)
        target = leftTarget[focusIndex];

    if (target == focusIndex)
        return true;

    focusIndex = target;
    ApplyFocus();
    class'DXControllerDebug'.static.DebugLog("DXC-NAV FOCUS heal=" $ string(focusIndex));
    return true;
}

function bool HandleActivate(byte button)
{
    local PersonaScreenHealth s;

    if (button == 202)   // X: Heal All from anywhere on the screen.
    {
        s = PersonaScreenHealth(screen);
        if (s != None && s.btnHealAll != None && s.btnHealAll.bIsSensitive)
            s.btnHealAll.PressButton();
        return true;
    }

    if (button != 200)   // IK_Joy1 (A) = 0xC8 = 200 — enum not reachable from Object scope
        return true;
    if (focused != None && ButtonWindow(focused) != None && focused.bIsSensitive)
        ButtonWindow(focused).PressButton();
    return true;
}

function BuildHints()
{
    AddHint("a", "Heal");
    AddHint("x", "Heal All");
    AddHint("lb", "Prev tab");
    AddHint("rb", "Next tab");
    AddHint("b", "Close");
}

defaultproperties
{
    // Index: 0=Head, 1=Torso, 2=R-Arm, 3=L-Arm, 4=R-Leg, 5=L-Leg, 6=Heal All
    upTarget(0)=6
    upTarget(1)=0
    upTarget(2)=0
    upTarget(3)=0
    upTarget(4)=2
    upTarget(5)=3
    upTarget(6)=4
    downTarget(0)=1
    downTarget(1)=4
    downTarget(2)=4
    downTarget(3)=5
    downTarget(4)=6
    downTarget(5)=6
    downTarget(6)=0
    leftTarget(0)=0
    leftTarget(1)=2
    leftTarget(2)=3
    leftTarget(3)=1
    leftTarget(4)=5
    leftTarget(5)=4
    leftTarget(6)=6
    rightTarget(0)=0
    rightTarget(1)=3
    rightTarget(2)=1
    rightTarget(3)=2
    rightTarget(4)=5
    rightTarget(5)=4
    rightTarget(6)=6
}
