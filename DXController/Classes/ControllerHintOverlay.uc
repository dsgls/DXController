//=============================================================================
// ControllerHintOverlay — draws the on-screen controller-button legend
// for whichever menu screen is on top.
//
// Sibling of MenuFocusOverlay: a child of ControllerRootWindow that
// each frame pulls the active nav controller's hint set and renders it
// as a centred strip near the bottom of the active screen. Like
// MenuFocusOverlay it is purely a read/draw consumer — it triggers no
// reconfigure / select / press (forbidden during draw in UE1).
//
// Each frame: ResetHints() + BuildHints() on the active controller,
// then draw entries 0..hintCount-1. Draws nothing in mouse mode, while
// the on-screen keyboard is open (it draws its own footer), when there
// is no active controller, or when the controller declared no hints
// (the inherited no-op BuildHints default).
//=============================================================================
class ControllerHintOverlay extends HUDBaseWindow;

const HINT_GAP     = 20.0;   // gap between adjacent hints
const STRIP_PADX   = 12.0;   // horizontal padding inside the veil
const STRIP_PADY   = 6.0;    // vertical padding inside the veil
const STRIP_H      = 16.0;   // hint row height (== ControllerButtonHint.ICON_SIZE)
const STRIP_MARGIN = 8.0;    // gap below the active screen's bottom edge

event DrawWindow(GC gc)
{
    local ControllerRootWindow root;
    local MenuNavController nav;
    local int i, n;
    local float totalW, startX, y;
    local float sx, sy, sw, sh;
    local float fx;

    Super.DrawWindow(gc);

    root = ControllerRootWindow(GetRootWindow());
    if (root == None)
        return;
    if (root.cursorMode != root.CM_Gamepad)
        return;
    if (root.keyboard != None && root.keyboard.bOpen)
        return;

    nav = root.activeNav;
    if (nav == None)
        return;

    nav.ResetHints();
    nav.BuildHints();
    n = nav.hintCount;
    if (n <= 0)
        return;

    // Total width of the hint row (hints + inter-hint gaps).
    totalW = 0.0;
    for (i = 0; i < n; i++)
    {
        totalW += class'ControllerButtonHint'.static.MeasureHint(
            gc, nav.hintIds[i], nav.hintLabels[i]);
        if (i < n - 1)
            totalW += HINT_GAP;
    }

    y = ResolveStripY(nav);

    // Centred; clamp the start so an over-wide strip left-aligns
    // rather than starting off-screen.
    startX = (width - totalW) * 0.5;
    if (startX < STRIP_PADX)
        startX = STRIP_PADX;

    // Two-pass dark veil so the legend stays readable over any
    // background — see OnScreenKeyboardWindow's panel and the CLAUDE.md
    // "no GC blend style gives a uniform translucent fill" quirk.
    // Modulate the scene toward black, then add a flat dark floor.
    sx = startX - STRIP_PADX;
    sy = y - STRIP_PADY;
    sw = totalW + 2.0 * STRIP_PADX;
    sh = STRIP_H + 2.0 * STRIP_PADY;
    gc.SetStyle(DSTY_Modulated);
    gc.SetTileColor(MakeColor(24, 24, 24, 255));
    gc.DrawPattern(sx, sy, sw, sh, 0, 0, Texture'Solid');
    gc.SetStyle(DSTY_Translucent);
    gc.SetTileColor(MakeColor(26, 26, 26, 255));
    gc.DrawPattern(sx, sy, sw, sh, 0, 0, Texture'Solid');

    // Hints left-to-right. DrawHint returns the x just past the label.
    fx = startX;
    for (i = 0; i < n; i++)
    {
        fx = class'ControllerButtonHint'.static.DrawHint(
            gc, fx, y, nav.hintIds[i], nav.hintLabels[i]);
        if (i < n - 1)
            fx += HINT_GAP;
    }
}

// Top y of the hint row: just below the active screen's bottom edge,
// clamped into the viewport. Falls back to the viewport bottom when
// the screen reference is missing (transient mid-transition).
function float ResolveStripY(MenuNavController nav)
{
    local Window rootWin;
    local float lx, ly, ox, oy;
    local float yPos, defaultY;

    defaultY = height - STRIP_H - STRIP_MARGIN;

    if (nav.screen == None)
        return defaultY;
    rootWin = nav.screen.GetRootWindow();
    if (rootWin == None)
        return defaultY;

    lx = 0.0;
    ly = 0.0;
    nav.screen.ConvertCoordinates(nav.screen, lx, ly, rootWin, ox, oy);
    yPos = oy + nav.screen.height + STRIP_MARGIN;

    if (yPos > defaultY)
        yPos = defaultY;
    if (yPos < STRIP_MARGIN)
        yPos = STRIP_MARGIN;
    return yPos;
}

function Color MakeColor(int r, int g, int b, int a)
{
    local Color c;
    c.R = r;
    c.G = g;
    c.B = b;
    c.A = a;
    return c;
}
