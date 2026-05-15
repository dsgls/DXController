//=============================================================================
// MenuFocusOverlay — draws a tinted frame around the currently-focused
// element on whichever menu screen is on top. Hidden when the root
// window is in CM_Mouse mode.
//
// Owned as a child of ControllerRootWindow. Each frame, the overlay
// pulls state directly from the root (active nav + cursor mode) and
// renders the focus highlight. Attach-time side effects (selecting
// items, pressing buttons) are NOT triggered from this draw path —
// reconfigure during draw is forbidden in UE1's window system. Attach
// happens only from event hooks (VirtualKeyPressed, NoticeGamepadActivity).
//=============================================================================
class MenuFocusOverlay extends HUDBaseWindow;

const FramePadding = 4.0;
const FrameThickness = 2;

// Diagnostic: last rect seen by DrawWindow, used to log only on change.
var float lastDiagX, lastDiagY, lastDiagW, lastDiagH;

event DrawWindow(GC gc)
{
    local ControllerRootWindow root;
    local MenuNavController nav;
    local float rx, ry, rw, rh;
    local float fx, fy, fw, fh;
    local Color tint;

    Super.DrawWindow(gc);

    root = ControllerRootWindow(GetRootWindow());
    if (root == None)
        return;

    if (root.cursorMode != root.CM_Gamepad)
        return;

    nav = root.activeNav;
    if (nav == None)
        return;

    if (!nav.GetFocusedRect(rx, ry, rw, rh))
        return;

    // === Diagnostic: log when the rect changes ===
    if (rx != lastDiagX || ry != lastDiagY || rw != lastDiagW || rh != lastDiagH)
    {
        class'DXControllerDebug'.static.DebugLog(
            "DXC-FOCUS rect x=" $ string(int(rx))
            $ " y=" $ string(int(ry))
            $ " w=" $ string(int(rw))
            $ " h=" $ string(int(rh)));
        lastDiagX = rx;
        lastDiagY = ry;
        lastDiagW = rw;
        lastDiagH = rh;
    }
    // === End diagnostic ===

    fx = rx - FramePadding;
    fy = ry - FramePadding;
    fw = rw + 2.0 * FramePadding;
    fh = rh + 2.0 * FramePadding;

    tint = colBorder;
    tint.A = 255;
    gc.SetStyle(DSTY_Masked);
    gc.SetTileColor(tint);
    gc.DrawBox(fx, fy, fw, fh, 0, 0, FrameThickness, Texture'Solid');
}
