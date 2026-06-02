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
var name   subDialogActive; // None | 'WheelAssign' | 'ModApply' | …
var bool   bAllowRepeat;    // true = HandleDPad accepts engine bRepeat=true presses (list/scroll screens)
                            // false = single-press only (grid screens — Inv, Augs)

// Set true once InitFocus has completed its one-time setup. Gates the
// ControllerRootWindow.Tick deferred-focus-init retry: the retry re-runs
// InitFocus while this is false, and stops once it is true. Grid/menu
// controllers get this set automatically when `focused` becomes non-None
// (see Attach below and ControllerRootWindow.Tick). List/scroll
// controllers, which keep `focused == None` by design, must set it
// themselves once their content is ready.
var bool bFocusInitDone;

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

// Legend placement, read each frame by ControllerHintOverlay:
//   'BottomCenter'   — centred strip at the active screen's bottom edge (default).
//   'ScreenTopRight' — strip pinned to the viewport's top-right corner,
//                      ignoring the active screen's bounds. Used by
//                      ConversationNavController so the legend never
//                      overlaps choice options that reach the screen edge.
var name hintPlacement;

function Attach(Window s)
{
    screen = s;
    focused = None;
    focusIndex = -1;
    subDialogActive = '';
    bFocusInitDone = false;
    InitFocus();
    // Grid/menu controllers set `focused` to a real window in InitFocus;
    // when they do, init is done. List/scroll controllers keep
    // `focused == None` and set bFocusInitDone themselves.
    if (focused != None)
        bFocusInitDone = true;
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
    bFocusInitDone = false;
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

// R-stick X-axis. rx is the raw axis value, -1000..1000. Return true to
// consume. Pairs with HandleScroll (R-stick Y). ControllerConsole
// forwards IK_JoyU here when a nav controller is active.
function bool HandleScrollX(float rx)
{
    return false;
}

// Analog trigger. side: 0 = LT (IK_JoyZ), 1 = RT (IK_JoyR). value is the
// raw axis value. Return true to consume — ControllerConsole then skips
// its UI-foreground force-zero and suppresses binding dispatch.
function bool HandleTrigger(int side, float value)
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

    // A focused child window can be Destroyed out from under us (an
    // inventory item dropped or used up); UE1 does not null the reference,
    // so guard the dereference with a live-descendant check.
    if (!IsFocusedLive())
        return false;

    // Suppress the overlay frame for widgets that paint their own focus
    // or selection cue — the frame would be a redundant second indicator.
    // The widget-class registry lives on HasStockFocusCue. Subclasses
    // that focus a sentinel (lists, scroll viewports) keep their explicit
    // GetFocusedRect overrides on top of this.
    if (HasStockFocusCue(focused))
        return false;

    root = focused.GetRootWindow();
    lx = 0;
    ly = 0;
    focused.ConvertCoordinates(focused, lx, ly, root, x, y);
    w = focused.width;
    h = focused.height;
    return true;
}

// True if `target` is somewhere in `parent`'s live descendant tree.
// Pointer-equality compares only — it never dereferences `target`, so it
// is safe to pass a stale/dangling Window pointer. (UE1 does not null
// Object references when the object is Destroyed, and reuses the freed
// slot.) Always walk DOWN from a known-live `parent`; never call
// GetParent() on a possibly-dead target — that would dereference freed
// memory. Static so ComputerScreenNavSub (a separate Object-rooted
// hierarchy) could reuse it too.
static function bool IsDescendantOf(Window parent, Window target)
{
    local Window c;

    if (parent == None || target == None)
        return false;

    c = parent.GetTopChild();
    while (c != None)
    {
        if (c == target)
            return true;
        if (IsDescendantOf(c, target))
            return true;
        c = c.GetLowerSibling();
    }
    return false;
}

// True if `focused` still points at a live descendant of `screen`. The
// screen is always live while a controller is active — DescendantRemoved
// clears activeNav when the screen itself is torn down — so the walk
// roots at a valid window. Detects a focused child window Destroyed out
// from under us (e.g. an inventory item dropped or used up).
function bool IsFocusedLive()
{
    return focused != None && IsDescendantOf(screen, focused);
}

// Called from ControllerRootWindow.Tick when `focused` has been Destroyed
// underneath the active controller. Default: forget focus and clear
// bFocusInitDone so the deferred-init retry reseeds from scratch. Override
// to re-home focus to a neighbour instead of restarting (see
// InvNavController).
function OnFocusedDestroyed()
{
    focused = None;
    bFocusInitDone = false;
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

// True for widget classes that paint their own focus or selection
// highlight, where the MenuFocusOverlay frame would be a redundant
// second indicator. The check is by widget class identity — a property
// of the class, not of the controller pointing at it. Two kinds of cue
// belong here:
//   (a) Engine-focus driven — vanilla yellow text on a button when
//       SetFocusWindow puts engine focus on it (e.g.
//       MenuUIBorderButtonWindow.SetButtonMetrics uses IsFocusWindow()
//       to pick colText[1] over colText[0]).
//   (b) Selection-state driven — a vanilla SelectX method on the
//       screen paints a per-button bSelected highlight that lives
//       independently of engine focus (e.g.
//       PersonaScreenSkills.SelectSkillButton → SelectButton(True)).
// Controllers that focus widgets in this list either drive (a) via
// SetFocus/SetFocusWindow or (b) via the corresponding SelectX call;
// either way the overlay frame stays off. Static so
// ComputerScreenNavSub (a separate Object-rooted hierarchy) can call
// it cross-class.
static function bool HasStockFocusCue(Window w)
{
    if (w == None)
        return false;
    return MenuUIBorderButtonWindow(w) != None
        || PersonaBorderButtonWindow(w) != None
        || PersonaSkillButtonWindow(w) != None;
}

// Atomically write `focused` and sync engine focus to it. Use this
// helper for every focus update that targets a widget whose stock cue
// is engine-focus-driven, so the controller's focus state and the
// engine's can never drift apart (and so the stock yellow text never
// gets stuck on a stale widget — that's the security-terminal class
// of bug). Passing `w == None` is treated the same as `ClearFocus`.
function SetFocus(Window w)
{
    focused = w;
    if (w != None && screen != None)
        screen.SetFocusWindow(w);
    else if (screen != None)
        screen.SetFocusWindow(screen);
}

// Drop `focused` and detach engine focus from any button. The screen
// window itself has no focus-driven cue, so engine focus parked there
// removes the yellow-text cue from whichever button last held it. Use
// this on transitions to non-stock-cued targets (e.g. moving onto a
// camera viewport from a choice row in the security terminal).
function ClearFocus()
{
    focused = None;
    if (screen != None)
        screen.SetFocusWindow(screen);
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
    hintPlacement=BottomCenter
}
