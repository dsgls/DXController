//=============================================================================
// ComputerScreenNavSub — abstract base for per-screen network-terminal
// sub-controllers. NOT registered with ControllerRootWindow; owned by
// NetworkTerminalNavController, instantiated lazily on first encounter
// of each ComputerScreenX class and cached for the dispatcher's lifetime.
//
// Narrower than MenuNavController: no Attach/Detach (the dispatcher's
// own Attach/Detach lifecycle handles registry concerns), no
// bAllowRepeat / subDialogActive (the dispatcher owns those), no
// HandleScroll/HandleScrollX/HandleTrigger (R-stick + triggers, used by
// the Security screen for analog camera pan/zoom; no-op elsewhere).
//
// IsButtonClass / GetFocusedRect implement the suppress-frame-on-button
// policy from the design doc: vanilla colText[1] (yellow) on a focused
// button is enough cue; the MenuFocusOverlay frame would be a redundant
// second indicator. Lists keep the frame (it tells the player which
// list owns the gamepad tab-stop, distinct from the intra-list per-row
// highlight). Edit fields keep the frame (the in-field blinking
// insertion point is intra-field; the around-field frame is visually
// distinct).
//=============================================================================
class ComputerScreenNavSub extends Object abstract;

var ComputerUIWindow screen;
var Window focused;
var int    focusIndex;

function OnEnter(ComputerUIWindow s)
{
    screen = s;
    focused = None;
    focusIndex = -1;
}

function OnLeave()
{
    screen = None;
    focused = None;
    focusIndex = -1;
}

// Open the gamepad on-screen keyboard for a text field on this screen.
// Called from sub-controllers' A-on-text-field handlers; `label` is the
// keyboard panel's prompt text (e.g. "ENTER USERNAME").
function OpenKeyboardFor(MenuUIEditWindow field, string label)
{
    local ControllerRootWindow root;

    if (field == None || screen == None)
        return;
    root = ControllerRootWindow(screen.GetRootWindow());
    if (root != None)
        root.OpenKeyboard(field, screen, label);
}

// dx/dy in {-1, 0, +1}. Return true to consume.
function bool HandleDPad(int dx, int dy)
{
    return false;
}

// button is the gamepad byte. Sub-controllers see 200 (A), 202 (X),
// 203 (Y), 209 (R-stick click). The dispatcher intercepts 201 (B),
// 204 (LB), 205 (RB) before delegation.
function bool HandleActivate(byte button)
{
    return false;
}

// Per-frame work, pumped by NetworkTerminalNavController.NavTick with
// the frame delta. Default: nothing. Sub-controllers that need
// per-frame work (failed-login re-sync, analog camera integration)
// override.
function OnTick(float deltaSeconds)
{
}

// R-stick Y-axis (camera pitch on the Security screen). Return true to
// consume. No-op default.
function bool HandleScroll(float v)
{
    return false;
}

// R-stick X-axis (camera yaw on the Security screen). Return true to
// consume. No-op default.
function bool HandleScrollX(float v)
{
    return false;
}

// Analog trigger (camera zoom on the Security screen). side: 0 = LT,
// 1 = RT. Return true to consume. No-op default.
function bool HandleTrigger(int side, float value)
{
    return false;
}

// Zero any cached analog deflection. Called by the dispatcher when the
// active pane leaves Computer and on teardown, so a stale stick value
// can't keep driving the camera. No-op default.
function ClearAxisCache()
{
}

// Contribute screen-specific button-legend hints by calling
// nav.AddHint(...). Return true if hints were added (the dispatcher
// then skips its generic legend), false to fall through. No-op default.
function bool BuildHints(MenuNavController nav)
{
    return false;
}

// True for widgets whose own focus cue (yellow text on buttons) is
// sufficient and the MenuFocusOverlay frame would double up.
static function bool IsButtonClass(Window w)
{
    return MenuUIBorderButtonWindow(w) != None
        || PersonaBorderButtonWindow(w) != None;
}

// Per the design's focus-indicator policy: return false (no frame)
// when focused is a widget whose own focus/selection cue is visible.
// The class registry lives on MenuNavController.HasStockFocusCue —
// called as a cross-class static here because ComputerScreenNavSub
// doesn't inherit from MenuNavController.
function bool GetFocusedRect(out float x, out float y, out float w, out float h)
{
    local Window root;
    local float lx, ly;

    if (focused == None || class'MenuNavController'.static.HasStockFocusCue(focused))
        return false;

    root = focused.GetRootWindow();
    lx = 0;
    ly = 0;
    focused.ConvertCoordinates(focused, lx, ly, root, x, y);
    w = focused.width;
    h = focused.height;
    return true;
}

// Atomically write `focused` and sync engine focus to it. Parallel
// to MenuNavController.SetFocus — same body, but lives here because
// ComputerScreenNavSub doesn't inherit from MenuNavController.
function SetFocus(Window w)
{
    focused = w;
    if (w != None && screen != None)
        screen.SetFocusWindow(w);
    else if (screen != None)
        screen.SetFocusWindow(screen);
}

// Drop `focused` and detach engine focus from any button. Use this
// on transitions to non-stock-cued targets (e.g. moving onto a
// camera viewport from a choice row in the security terminal).
function ClearFocus()
{
    focused = None;
    if (screen != None)
        screen.SetFocusWindow(screen);
}
