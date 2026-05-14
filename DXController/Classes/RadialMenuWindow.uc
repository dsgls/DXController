//=============================================================================
// RadialMenuWindow — gamepad weapon / aug wheel.
//
// Rendered as a sibling of `hud` in the root-window tree. Does NOT push
// onto the window stack (a pushed UI window would cause Extension.InputExt
// to synthesise a release on the held trigger button, immediately closing
// the wheel — see CLAUDE.md "Input flow" section).
//
// State machine:
//   - bOpen = false      : window invisible, ticks idle.
//   - Open(WM_Weapon)    : begin showing the weapon wheel.
//   - Open(WM_Aug)       : begin showing the aug wheel.
//   - UpdateStick(x, y)  : called every right-stick axis event while open.
//   - Close(bApply)      : tear down. If bApply, dispatch the selected
//                          action (equip / unequip / toggle).
//=============================================================================
class RadialMenuWindow extends HUDBaseWindow;

// Wheel mode values; matches the spec's EWheelMode.
const WM_None   = 0;
const WM_Weapon = 1;
const WM_Aug    = 2;

const StickDeadzone     = 400.0;    // ~40% of the -1000..1000 axis range
const DegreesPerRadian  = 57.2957795;

const WheelRadius      = 130.0;   // pixels from screen-centre to each icon's centre
const IconSize         = 48.0;    // base icon edge length, pixels
const IconSelScale     = 1.15;    // size multiplier for the selected slot
const FramePadding     = 8.0;     // selection frame is icon size + 2 * this

var bool  bOpen;
var int   mode;            // WM_None | WM_Weapon | WM_Aug
var float stickX, stickY;  // latest right-stick sample, -1000..1000
var int   highlightedSlot; // 0..9 or -1 if in deadzone / wheel closed

function Open(int newMode)
{
    if (bOpen)
        return;
    bOpen = true;
    mode = newMode;
    stickX = 0;
    stickY = 0;
    highlightedSlot = -1;
    Log("DXC-WHEEL OPEN mode=" $ string(newMode));
}

function Close(bool bApply)
{
    if (!bOpen)
        return;
    Log("DXC-WHEEL CLOSE slot=" $ string(highlightedSlot)
        $ " apply=" $ string(bApply));
    bOpen = false;
    mode = WM_None;
    highlightedSlot = -1;
}

// Returns angle in degrees clockwise from "up", 0..360.
// Assumes shim sends stick-up as y < 0 (screen-coord convention). If
// in-game testing shows the wheel inverted vertically, negate y here.
function float ComputeAngleDegrees(float x, float y)
{
    local float angle;
    if (Abs(y) < 0.001)
    {
        if (x >= 0) return 90.0;
        return 270.0;
    }
    angle = Atan(x / (-y)) * DegreesPerRadian;
    if (y > 0)
        angle += 180.0;         // stick pushed down (y > 0 in screen coords)
    else if (angle < 0)
        angle += 360.0;         // stick in upper-left quadrant
    return angle;
}

function UpdateStick(float x, float y)
{
    local float mag, angle;
    local int   slot, oldSlot;

    stickX = x;
    stickY = y;

    if (!bOpen)
        return;

    oldSlot = highlightedSlot;

    mag = Sqrt(x*x + y*y);
    if (mag < StickDeadzone)
    {
        highlightedSlot = -1;
    }
    else
    {
        angle = ComputeAngleDegrees(x, y);

        // Each segment is 36°; slot 0 is centred on 0°, so segment N
        // spans (N*36 - 18) .. (N*36 + 18). Add 18 before dividing to
        // collapse this to a plain integer divide.
        slot = int((angle + 18.0) / 36.0) % 10;
        highlightedSlot = slot;
    }

    if (highlightedSlot != oldSlot)
        Log("DXC-WHEEL HL slot=" $ string(highlightedSlot));
}

event DrawWindow(GC gc)
{
    local int i;
    local float cx, cy;
    local Color tintIcon, tintFrame, tintDim;
    local Inventory inv;
    local DeusExRootWindow root;
    local HUDObjectBelt belt;

    Super.DrawWindow(gc);

    if (!bOpen || mode != WM_Weapon)
        return;

    root = DeusExRootWindow(GetRootWindow());
    if (root == None || root.hud == None || root.hud.belt == None)
        return;
    belt = root.hud.belt;

    cx = width  * 0.5;
    cy = height * 0.5;

    // Pull the HUD theme colour for our accent (colBorder is maintained by
    // HUDBaseWindow.StyleChanged and stays in sync with theme changes).
    tintFrame = colBorder;
    tintIcon  = ColorAlpha(255, 255, 255, 255);
    tintDim   = ColorAlpha(80, 80, 80, 255);

    gc.EnableTranslucency(true);

    for (i = 0; i < 10; i++)
    {
        inv = belt.objects[i].GetItem();
        DrawSlot(gc, i, cx, cy, inv, (i == highlightedSlot), tintFrame, tintIcon, tintDim);
    }
}

function DrawSlot(GC gc, int slotIdx, float cx, float cy,
                  Inventory inv, bool bSelected,
                  Color tintFrame, Color tintIcon, Color tintDim)
{
    local float angleDeg, angleRad;
    local float sx, sy;             // slot centre
    local float size, x, y;         // icon rect
    local float frameSize, fx, fy;  // frame rect

    angleDeg = slotIdx * 36.0;
    angleRad = angleDeg / DegreesPerRadian;
    sx = cx + WheelRadius * Sin(angleRad);
    sy = cy - WheelRadius * Cos(angleRad);

    size = IconSize;
    if (bSelected)
        size = IconSize * IconSelScale;

    x = sx - size * 0.5;
    y = sy - size * 0.5;

    // Selection frame: a tinted square drawn behind the icon.
    if (bSelected)
    {
        frameSize = size + 2.0 * FramePadding;
        fx = sx - frameSize * 0.5;
        fy = sy - frameSize * 0.5;
        gc.SetTileColor(tintFrame);
        gc.DrawTexture(fx, fy, frameSize, frameSize, 0, 0, Texture'Engine.WhiteTexture');
    }

    if (inv != None && inv.Icon != None)
    {
        gc.SetTileColor(tintIcon);
        gc.DrawTexture(x, y, size, size, 0, 0, inv.Icon);
    }
    else
    {
        // Empty slot — dim placeholder frame, no icon.
        gc.SetTileColor(tintDim);
        gc.DrawTexture(x, y, size, size, 0, 0, Texture'Engine.WhiteTexture');
    }
}

function Color ColorAlpha(int r, int g, int b, int a)
{
    local Color c;
    c.R = r;
    c.G = g;
    c.B = b;
    c.A = a;
    return c;
}

defaultproperties
{
    bOpen=False
    mode=0
    highlightedSlot=-1
}
