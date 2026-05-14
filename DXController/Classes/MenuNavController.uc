//=============================================================================
// MenuNavController — abstract base for per-screen gamepad navigation.
//
// One instance per persona-screen class (or one shared instance for the
// main-menu family). Owned by ControllerRootWindow's class→controller
// registry. The root window attaches the controller when its screen is
// pushed to the top of the window stack, detaches when the screen leaves.
//
// All HandleX methods return true if they consumed the event (root window
// suppresses further routing) and false to let vanilla handling run.
//=============================================================================
class MenuNavController extends Object;

var Window screen;          // the persona/menu screen window we operate on
var Window focused;         // currently-focused child element (may be None)
var int    focusIndex;      // index into the screen's primary array, if relevant
var name   subDialogActive; // None | 'WheelAssign' | 'AugInstall' | …
var bool   bAllowRepeat;    // true = HandleDPad accepts engine bRepeat=true presses (list/scroll screens)
                            // false = single-press only (grid screens — Inv, Augs)

function Attach(Window s)
{
    screen = s;
    focused = None;
    focusIndex = -1;
    subDialogActive = '';
    InitFocus();
    class'DXControllerDebug'.static.DebugLog("DXC-NAV ATTACH screen=" $ string(screen.Class));
}

function Detach()
{
    if (screen != None)
        class'DXControllerDebug'.static.DebugLog("DXC-NAV DETACH screen=" $ string(screen.Class));
    screen = None;
    focused = None;
    focusIndex = -1;
    subDialogActive = '';
}

// Override in subclasses: set focused/focusIndex to the "first focusable"
// element for this screen.
function InitFocus()
{
}

// dx/dy in {-1, 0, +1}. Return true to consume.
function bool HandleDPad(int dx, int dy)
{
    return false;
}

// `button` is the gamepad button: IK_Joy1 (A), IK_Joy3 (X), IK_Joy4 (Y),
// IK_Joy10 (R-stick click). Return true to consume.
// EInputKey is not resolvable from Object scope (it is not declared here
// nor inherited); callers cast: HandleActivate(byte(Key)).
function bool HandleActivate(byte button)
{
    return false;
}

// R-stick Y-axis scroll. ry is the raw axis value, -1000..1000.
// Return true to consume.
function bool HandleScroll(float ry)
{
    return false;
}

// Out-params: focused element's screen rectangle, for MenuFocusOverlay
// to draw a tinted frame around. Return false if no focused element
// (overlay should not draw).
//
// ConvertCoordinates converts the focused window's local (0,0) origin to
// root-window coordinates, giving the top-left corner in screen space.
// Width/height are the Window member vars (not function calls).
function bool GetFocusedRect(out float x, out float y, out float w, out float h)
{
    local Window root;
    local float lx, ly;

    if (focused == None)
        return false;

    root = focused.GetRootWindow();
    lx = 0;
    ly = 0;
    focused.ConvertCoordinates(focused, lx, ly, root, x, y);
    w = focused.width;
    h = focused.height;
    return true;
}

defaultproperties
{
    bAllowRepeat=True
}
