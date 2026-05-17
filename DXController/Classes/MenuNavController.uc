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

// ---- Button-legend hints ----
// The active screen's controller-button legend, as parallel arrays:
// hintIds[i] is a ControllerButtonHint logical id ("a", "b", "x",
// "lb", ...), hintLabels[i] its effect text. ControllerHintOverlay
// calls ResetHints() then BuildHints() each frame, then reads
// entries 0..hintCount-1.
//
// Parallel arrays rather than an array-of-struct: a struct of two
// UE1 strings is 384 bytes, and indexing a field of a >255-byte
// struct array element ("nav.hints[i].id") trips UCC's 255-byte
// context-expression limit. See the CLAUDE.md quirk.
var string hintIds[16];     // 16 is more than any screen needs; AddHint drops past this
var string hintLabels[16];  // parallel to hintIds
var int    hintCount;       // number of populated hints; valid indices 0..hintCount-1

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

// Returns true if Start/Back may toggle the persona menu while this
// controller is active. Override to false in in-world modal
// controllers (conversation, keypad, computer, etc.) so accidental
// Start/Back presses don't stack the persona menu on top.
//
// Also consulted by ControllerRootWindow's B (Joy2) routing: when
// false, B is offered to HandleActivate instead of being synthesised
// as Escape on the PushWindow stack (which doesn't see NewChild'd
// in-world modals like ConWindowActive anyway).
function bool AllowsMenuToggle()
{
    return true;
}

// Per-frame hook, pumped manually by ControllerRootWindow.Tick on the
// active controller. MenuNavController is Object-scoped, so the engine
// never ticks it directly — this is the substitute. Default no-op;
// only controllers that need per-frame work (e.g.
// NetworkTerminalNavController's winComputer screen-swap detection)
// override it.
function NavTick(float deltaSeconds)
{
}

// ---- Button-legend hints ----

// Clear the hint accumulator. Called by ControllerHintOverlay each
// frame before BuildHints.
function ResetHints()
{
    hintCount = 0;
}

// Append one legend hint. id is a ControllerButtonHint logical id
// ("a", "b", "x", "lb", ...); label is the effect text. Append order
// is left-to-right draw order in the strip. Silently drops appends
// past the array bound — same defensive idiom as
// ControllerRootWindow.RegisterNav.
function AddHint(string id, string label)
{
    if (hintCount >= ArrayCount(hintIds))
        return;
    hintIds[hintCount] = id;
    hintLabels[hintCount] = label;
    hintCount++;
}

// Override in subclasses: call AddHint once per button this screen
// uses. Invoked fresh every frame against live state, so a controller
// branches here on subDialogActive / focused / etc. to produce a
// context-dependent legend. Default: no legend (the overlay then
// draws nothing).
function BuildHints()
{
}

defaultproperties
{
    bAllowRepeat=True
}
