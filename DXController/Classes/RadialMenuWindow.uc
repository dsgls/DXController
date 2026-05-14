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

defaultproperties
{
    bOpen=False
    mode=0
    highlightedSlot=-1
}
