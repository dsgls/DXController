//=============================================================================
// GoalsNavController — scroll-only controller for the Goals/Notes screen.
//
// The Goals screen has two TileWindows (winGoals and winNotes) each wrapped
// in a PersonaScrollAreaWindow. There are no focusable list items for gamepad
// navigation; this controller just exposes scroll control:
//
//   D-pad up/down  → scroll winGoals one step
//   R-stick Y      → smooth-scroll winGoals (accumulator-based)
//
// Scroll API path: TileWindow → GetParent() → clipWindow →
//                  GetParent() → PersonaScrollAreaWindow → vScale
// MoveThumb direction: MOVETHUMB_StepUp = scroll content up (higher).
// R-stick: positive ry = stick pushed up = MOVETHUMB_StepUp.
//=============================================================================
class GoalsNavController extends MenuNavController;

// Accumulator for R-stick smooth scroll. One step fires per ScrollThreshold
// units of accumulated axis input.
const ScrollDeadzone  = 200.0;   // raw axis units; ignore small stick deflections
const ScrollThreshold = 500.0;   // accumulated units before one MoveThumb step

var float scrollAccum;

function InitFocus()
{
    focused = None;
    scrollAccum = 0.0;
}

function bool GetFocusedRect(out float x, out float y, out float w, out float h)
{
    return false;   // no overlay frame on this screen
}

function bool HandleDPad(int dx, int dy)
{
    local PersonaScreenGoals s;
    local PersonaScrollAreaWindow winScroll;

    if (dy == 0)
        return true;

    s = PersonaScreenGoals(screen);
    if (s == None || s.winGoals == None)
        return true;

    // winGoals is a TileWindow inside clipWindow inside PersonaScrollAreaWindow.
    // GetParent() twice walks: TileWindow -> clipWindow -> PersonaScrollAreaWindow.
    winScroll = PersonaScrollAreaWindow(s.winGoals.GetParent().GetParent());
    if (winScroll == None || winScroll.vScale == None)
        return true;

    if (dy < 0)
        winScroll.vScale.MoveThumb(MOVETHUMB_StepUp);
    else
        winScroll.vScale.MoveThumb(MOVETHUMB_StepDown);

    return true;
}

function bool HandleScroll(float ry)
{
    local PersonaScreenGoals s;
    local PersonaScrollAreaWindow winScroll;

    s = PersonaScreenGoals(screen);
    if (s == None || s.winGoals == None)
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

    winScroll = PersonaScrollAreaWindow(s.winGoals.GetParent().GetParent());
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

function BuildHints()
{
    AddHint("rs", "Scroll");
    AddHint("lb", "Prev tab");
    AddHint("rb", "Next tab");
    AddHint("b", "Close");
}

defaultproperties
{
    bAllowRepeat=True
}
