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

function UpdateStick(float x, float y)
{
    stickX = x;
    stickY = y;
    // highlightedSlot stays -1 until Task 3 implements the math.
}

defaultproperties
{
    bOpen=False
    mode=0
    highlightedSlot=-1
}
