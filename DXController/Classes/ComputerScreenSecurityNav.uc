//=============================================================================
// ComputerScreenSecurityNav — sub-controller for ComputerScreenSecurity,
// the network-terminal surveillance screen.
//
// Navigation: a 5-row vertical wrap cycle —
//   row 0  Camera Status choice   (choiceWindows[0])
//   row 1  Door Access choice     (choiceWindows[1])
//   row 2  Door Status choice     (choiceWindows[2])
//   row 3  Turret Status choice   (choiceWindows[3])
//   row 4  Camera row             (winCameras[0..2], D-pad left/right)
// D-pad up/down wraps end-to-end. On row 4, moving focus onto a camera
// auto-selects it (SelectCamera) so the choice rows retarget and the
// R-stick / triggers drive it.
//
// A on a choice row cycles that choice (vanilla btnAction.PressButton).
// A on the camera row is a no-op. B (logout) and LB/RB (pane cycling)
// are handled by the NetworkTerminalNavController dispatcher.
//
// R-stick pans / triggers zoom the selected camera — see Task 6 methods.
//
// See docs/superpowers/specs/2026-05-17-network-terminal-nav-phase2-security-design.md
//=============================================================================
class ComputerScreenSecurityNav extends ComputerScreenNavSub;

const NUM_ROWS   = 5;
const ROW_CAMERA = 4;   // row index of the 3-camera row

var int rowIndex;       // 0..4 current row
var int cameraIndex;    // 0..2 selected camera within row 4

// Analog input cache (used by Task 6's pan/zoom integration). Raw axis
// values: rx/ry in -1000..1000, lt/rt in 0..1000.
var float rx, ry, lt, rt;

// Tuning constants (rotator-units / fov-degrees per second at full
// deflection). Hardcoded — not config knobs. Tuned during playtest.
var const float panSpeed;
var const float zoomSpeed;

// ---- Helpers ---------------------------------------------------------------

// Index of `cam` within winCameras[], or -1.
function int CameraIndexOf(ComputerScreenSecurity sec, ComputerSecurityCameraWindow cam)
{
    local int i;

    if (cam == None)
        return -1;
    for (i = 0; i < 3; i++)   // winCameras[3]
    {
        if (sec.winCameras[i] == cam)
            return i;
    }
    return -1;
}

// True if D-pad navigation may land on `row`. The camera row is always
// navigable — any of the 3 slots may be selected, since even a
// no-signal slot can still control a door. A choice row is navigable
// only while it is usable (a disabled choice has no focus cue, so
// landing on it reads as broken).
//
// The two vanilla disable paths touch different windows, so both are
// checked: SetCameraView (the selected camera lacks a camera / door /
// turret) calls DisableWindow() on the choice window itself; a
// low-skill hack's DisableChoice() instead disables btnAction. Testing
// btnAction.bIsSensitive alone misses the first — and most common —
// case. IsSensitive() reads each window's own sensitivity natively.
function bool RowNavigable(ComputerScreenSecurity sec, int row)
{
    local ComputerCameraUIChoice choice;

    if (row == ROW_CAMERA)
        return true;
    choice = sec.choiceWindows[row];
    return choice != None
        && choice.btnAction != None
        && choice.IsSensitive()
        && choice.btnAction.IsSensitive();
}

// First navigable row, top-to-bottom: the first sensitive choice row,
// or the camera row when no choice is sensitive.
function int FirstNavigableRow(ComputerScreenSecurity sec)
{
    local int i;

    for (i = 0; i < ROW_CAMERA; i++)
    {
        if (RowNavigable(sec, i))
            return i;
    }
    return ROW_CAMERA;
}

// Land focus on the current rowIndex. Choice rows: focus btnAction and
// sync engine focus for the vanilla yellow-text cue. Camera row:
// auto-select winCameras[cameraIndex].
function FocusRow(ComputerScreenSecurity sec)
{
    focusIndex = rowIndex;

    if (rowIndex == ROW_CAMERA)
    {
        // Move BOTH controller focus and engine focus directly onto the
        // camera viewport. The A4 attempt of parking engine focus on
        // `screen` via ClearFocus was visibly NOT detaching the yellow-
        // text cue from the previously focused choice btnAction —
        // SetFocusWindow(screen) didn't seem to move IsFocusWindow off
        // the button. Focusing a real, distinct widget (the camera
        // window) forces a genuine focus transition that the button's
        // per-frame `IsFocusWindow()` check picks up: next draw, its
        // SetButtonMetrics returns textColorIndex=0 (normal) instead of
        // 1 (focus). The camera window has no stock cue, so the
        // MenuFocusOverlay frame still draws around it via the
        // GetFocusedRect override below.
        if (sec.winCameras[cameraIndex] != None)
        {
            sec.SelectCamera(sec.winCameras[cameraIndex]);
            SetFocus(sec.winCameras[cameraIndex]);
            class'DXControllerDebug'.static.DebugLog(
                "DXC-TERM SEC-CAMERA idx=" $ string(cameraIndex));
        }
        else
        {
            // No camera at this slot — fall back to ClearFocus to
            // release any prior engine focus.
            ClearFocus();
        }
        return;
    }

    if (sec.choiceWindows[rowIndex] != None
        && sec.choiceWindows[rowIndex].btnAction != None)
    {
        SetFocus(sec.choiceWindows[rowIndex].btnAction);
    }
}

// ---- Lifecycle -------------------------------------------------------------

function OnEnter(ComputerUIWindow s)
{
    local ComputerScreenSecurity sec;

    Super.OnEnter(s);   // screen = s; focused = None; focusIndex = -1

    rx = 0; ry = 0; lt = 0; rt = 0;

    sec = ComputerScreenSecurity(s);
    if (sec == None)
        return;
    // Children not populated yet — the dispatcher's NavTick retries
    // OnEnter while focused == None.
    if (sec.choiceWindows[0] == None || sec.winCameras[0] == None)
        return;

    rowIndex = FirstNavigableRow(sec);   // first sensitive row, else camera row
    cameraIndex = CameraIndexOf(sec, sec.selectedCamera);
    if (cameraIndex < 0)
        cameraIndex = 0;

    FocusRow(sec);
    class'DXControllerDebug'.static.DebugLog("DXC-TERM SEC-ENTER");
}

// ---- D-pad -----------------------------------------------------------------

function bool HandleDPad(int dx, int dy)
{
    local ComputerScreenSecurity sec;
    local int newRow, steps;

    sec = ComputerScreenSecurity(screen);
    if (sec == None)
        return true;

    if (dy != 0)
    {
        // Step in the dy direction, skipping choice rows whose action
        // button is insensitive. The camera row is always navigable, so
        // a navigable row is always found within NUM_ROWS steps — no
        // infinite loop. If only the current row is navigable, newRow
        // lands back on it (D-pad up/down then has nowhere to go).
        newRow = rowIndex;
        for (steps = 0; steps < NUM_ROWS; steps++)
        {
            newRow = (newRow + dy + NUM_ROWS) % NUM_ROWS;
            if (RowNavigable(sec, newRow))
                break;
        }
        rowIndex = newRow;

        // Entering the camera row: read the live selection fresh so a
        // mouse click on a camera is honoured and re-entry never snaps
        // the player's aim away.
        if (rowIndex == ROW_CAMERA)
        {
            cameraIndex = CameraIndexOf(sec, sec.selectedCamera);
            if (cameraIndex < 0)
                cameraIndex = 0;
        }
        FocusRow(sec);
        class'DXControllerDebug'.static.DebugLog(
            "DXC-TERM SEC-DPAD row=" $ string(rowIndex));
        return true;
    }

    if (dx != 0 && rowIndex == ROW_CAMERA)
    {
        cameraIndex = Clamp(cameraIndex + dx, 0, 2);
        FocusRow(sec);
        return true;
    }

    // D-pad left/right on a choice row: consumed no-op.
    return true;
}

// ---- Activate (A) ----------------------------------------------------------

function bool HandleActivate(byte button)
{
    local ComputerScreenSecurity sec;
    local MenuUIChoiceButton btn;

    if (button != 200)   // only A
        return true;

    sec = ComputerScreenSecurity(screen);
    if (sec == None)
        return true;

    if (rowIndex == ROW_CAMERA)
        return true;   // camera row: A is a no-op

    if (sec.choiceWindows[rowIndex] != None)
        btn = sec.choiceWindows[rowIndex].btnAction;

    // RowNavigable is the single source of truth for "this choice is
    // usable" — see the comment there for why btnAction.bIsSensitive
    // alone is insufficient.
    if (RowNavigable(sec, rowIndex) && btn != None)
    {
        btn.PressButton();
        class'DXControllerDebug'.static.DebugLog(
            "DXC-TERM SEC-CHOICE idx=" $ string(rowIndex) $ " sensitive=True");
    }
    else
    {
        class'DXControllerDebug'.static.DebugLog(
            "DXC-TERM SEC-CHOICE idx=" $ string(rowIndex) $ " sensitive=False");
    }
    return true;
}

// ---- Focus rect ------------------------------------------------------------
//
// Choice rows: focused is a btnAction (button class) — suppress the
// frame, vanilla yellow focus-text is the cue. Camera row: draw the
// frame around the focused camera window.

function bool GetFocusedRect(out float x, out float y, out float w, out float h)
{
    local Window root;
    local float lx, ly;

    if (rowIndex != ROW_CAMERA || focused == None)
        return false;

    root = focused.GetRootWindow();
    if (root == None)
        return false;
    lx = 0;
    ly = 0;
    focused.ConvertCoordinates(focused, lx, ly, root, x, y);
    w = focused.width;
    h = focused.height;
    return true;
}

// ---- Analog input: cache + per-frame integration ---------------------------
//
// R-stick / trigger axis events only cache the current deflection. The
// dispatcher delegates these only while the Computer pane is active.

function bool HandleScroll(float v)    // R-stick Y → camera pitch
{
    ry = v;
    return true;
}

function bool HandleScrollX(float v)   // R-stick X → camera yaw
{
    rx = v;
    return true;
}

function bool HandleTrigger(int side, float value)
{
    if (side == 0)
        lt = value;   // LT → zoom out
    else
        rt = value;   // RT → zoom in
    return true;
}

// Zeroed by the dispatcher when the active pane leaves Computer / on
// teardown, so a stick held during an LB/RB pane switch can't keep
// panning the camera.
function ClearAxisCache()
{
    rx = 0;
    ry = 0;
    lt = 0;
    rt = 0;
}

// Per-frame analog integration. rx/ry are -1000..1000; lt/rt 0..1000.
// dFov negative zooms in (RT), positive zooms out (LT). The overlay
// helpers no-op when there is no live camera, so a no-signal selection
// is harmless here.
function OnTick(float deltaSeconds)
{
    local ComputerScreenSecurity sec;
    local float dYaw, dPitch, dFov;

    sec = ComputerScreenSecurity(screen);
    if (sec == None)
        return;

    dYaw   = (rx / 1000.0) * panSpeed * deltaSeconds;
    dPitch = (ry / 1000.0) * panSpeed * deltaSeconds;
    if (dYaw != 0.0 || dPitch != 0.0)
        sec.GamepadPan(dYaw, dPitch);

    dFov = ((lt - rt) / 1000.0) * zoomSpeed * deltaSeconds;
    if (dFov != 0.0)
        sec.GamepadZoom(dFov);
}

// ---- Button legend ---------------------------------------------------------

function bool BuildHints(MenuNavController nav)
{
    local NetworkTerminalNavController term;

    if (rowIndex != ROW_CAMERA)
        nav.AddHint("a", "Toggle");
    nav.AddHint("rs", "Pan");
    nav.AddHint("lt", "Zoom out");
    nav.AddHint("rt", "Zoom in");

    term = NetworkTerminalNavController(nav);
    if (term != None && (term.IsPanePresent(1)   // PANE_HACK
                      || term.IsPanePresent(2))) // PANE_HACKACCOUNTS
    {
        nav.AddHint("lb", "Prev pane");
        nav.AddHint("rb", "Next pane");
    }
    nav.AddHint("b", "Logout");
    return true;
}

defaultproperties
{
    panSpeed=22000.000000
    zoomSpeed=45.000000
}
