//=============================================================================
// GoalsNavController — gamepad navigation for PersonaScreenGoals.
//
// Three gamepad-focusable targets, cycled D-pad up/down with wrap-around:
//
//   focusIndex 0 — winGoals : the goals text area (a TileWindow inside a
//                             PersonaScrollAreaWindow). RS scrolls it.
//   focusIndex 1 — chkShowCompletedGoals : the "Display completed goals"
//                             checkbox. A toggles it.
//   focusIndex 2 — winNotes : the notes text area (same shape as
//                             winGoals). RS scrolls it.
//
// `focused` is set to the Window of the active target — the scroll area
// for the text targets, the checkbox itself — so the inherited
// GetFocusedRect draws the MenuFocusOverlay frame around it. Because
// `focused` becomes non-None, the base Attach / Tick deferred-init logic
// sets bFocusInitDone automatically; this controller does not set it.
//
// Note action buttons (btnAddNote / btnDeleteNote) and the
// confirm-deletion checkbox are skipped — note editing needs text entry
// the gamepad has no path for.
//
// Scroll path: TileWindow.GetParent().GetParent() -> PersonaScrollAreaWindow.
// MoveThumb direction: MOVETHUMB_StepUp = scroll content up; positive ry
// = stick pushed up = StepUp.
//
// See docs/superpowers/specs/2026-05-17-persona-screen-nav-fixes-design.md
//=============================================================================
class GoalsNavController extends MenuNavController;

// Accumulator for R-stick smooth scroll. One step fires per
// ScrollThreshold units of accumulated axis input.
const ScrollDeadzone  = 10.0;    // raw axis units; ignore small deflections
const ScrollThreshold = 500.0;   // accumulated units before one MoveThumb step

var float scrollAccum;

// ----------------------------------------------------------------------
// TargetWindow — the Window for a focusIndex: the scroll area for the
// text targets (0, 2), the checkbox for target 1. Returns None if the
// screen or the target window is not built yet.
// ----------------------------------------------------------------------

function Window TargetWindow(int idx)
{
    local PersonaScreenGoals s;

    s = PersonaScreenGoals(screen);
    if (s == None)
        return None;

    if (idx == 0)
    {
        if (s.winGoals == None)
            return None;
        return s.winGoals.GetParent().GetParent();   // PersonaScrollAreaWindow
    }
    if (idx == 1)
        return s.chkShowCompletedGoals;
    if (idx == 2)
    {
        if (s.winNotes == None)
            return None;
        return s.winNotes.GetParent().GetParent();    // PersonaScrollAreaWindow
    }
    return None;
}

// ----------------------------------------------------------------------
// InitFocus — start on the goals text area.
//
// Leaves `focused` None if the goals scroll area is not built yet, so
// the Tick deferred-init retry runs again next frame; once `focused` is
// set, the base marks bFocusInitDone and the retry stops.
// ----------------------------------------------------------------------

function InitFocus()
{
    scrollAccum = 0.0;
    focusIndex = 0;
    focused = TargetWindow(0);
}

// ----------------------------------------------------------------------
// HandleDPad — cycle focus through the three targets with wrap-around.
// ----------------------------------------------------------------------

function bool HandleDPad(int dx, int dy)
{
    local Window w;

    if (dy == 0)
        return true;

    // Three targets, wrap-around. UScript % keeps the sign of the
    // dividend, so add 3 before the mod to handle dy = -1.
    focusIndex = (focusIndex + dy + 3) % 3;
    scrollAccum = 0.0;   // reset accumulator when switching targets

    w = TargetWindow(focusIndex);
    if (w != None)
        focused = w;
    // else: target window not in the tree yet — focusIndex advanced but
    // `focused` is left on the previous target. TargetWindow returns None
    // only before the screen is fully built; PersonaScreenGoals populates
    // winGoals/winNotes in InitWindow before this controller attaches, so
    // this branch is not expected to be reached during normal navigation.

    class'DXControllerDebug'.static.DebugLog(
        "DXC-NAV FOCUS goals idx=" $ string(focusIndex));
    return true;
}

// ----------------------------------------------------------------------
// HandleScroll — R-stick Y scrolls the focused text area only.
// ----------------------------------------------------------------------

function bool HandleScroll(float ry)
{
    local PersonaScreenGoals s;
    local PersonaScrollAreaWindow winScroll;
    local TileWindow target;

    s = PersonaScreenGoals(screen);
    if (s == None)
        return false;

    // Only the text areas scroll; the checkbox (focusIndex 1) does not.
    if (focusIndex == 0)
        target = s.winGoals;
    else if (focusIndex == 2)
        target = s.winNotes;
    else
        return false;

    if (target == None)
        return false;

    if (Abs(ry) < ScrollDeadzone)
    {
        scrollAccum = 0.0;
        return false;
    }

    // Positive ry = stick pushed up = scroll content up = StepUp.
    scrollAccum += ry;
    if (Abs(scrollAccum) < ScrollThreshold)
        return true;

    winScroll = PersonaScrollAreaWindow(target.GetParent().GetParent());
    if (winScroll == None || winScroll.vScale == None)
    {
        scrollAccum = 0.0;
        return false;
    }

    if (scrollAccum > 0.0)
        winScroll.vScale.MoveThumb(MOVETHUMB_StepUp);
    else
        winScroll.vScale.MoveThumb(MOVETHUMB_StepDown);

    scrollAccum = 0.0;
    return true;
}

// ----------------------------------------------------------------------
// HandleActivate — A toggles the checkbox when it is focused.
//
// 200 = IK_Joy1 (A). PressButton() is the same path the keyboard uses
// (CLAUDE.md "Button activation idiom"); on a ToggleWindow it flips the
// toggle and fires the screen's ToggleChanged -> PopulateGoals(). Other
// buttons, and A on a text area, are consumed no-ops.
// ----------------------------------------------------------------------

function bool HandleActivate(byte button)
{
    local PersonaScreenGoals s;

    if (button == 200 && focusIndex == 1)
    {
        s = PersonaScreenGoals(screen);
        if (s != None && s.chkShowCompletedGoals != None
            && s.chkShowCompletedGoals.bIsSensitive)
            s.chkShowCompletedGoals.PressButton();
    }
    return true;
}

// ----------------------------------------------------------------------
// BuildHints — context-dependent legend, rebuilt each frame.
// ----------------------------------------------------------------------

function BuildHints()
{
    AddHint("dpad", "Switch area");
    if (focusIndex == 1)
        AddHint("a", "Toggle");
    else
        AddHint("rs", "Scroll");
    AddHint("lb", "Prev tab");
    AddHint("rb", "Next tab");
    AddHint("b", "Close");
}

defaultproperties
{
    // Three-item focus cycler, not a list — single-press only, so a held
    // D-pad does not spin through targets at the engine key-repeat rate.
    bAllowRepeat=False
}
