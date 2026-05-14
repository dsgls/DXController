//=============================================================================
// RadialMenuWindow — gamepad weapon / aug wheel.
//
// Rendered as a sibling of `hud` in the root-window tree. Does NOT push
// onto the window stack (a pushed UI window would cause Extension.InputExt
// to synthesise a release on the held trigger button, immediately closing
// the wheel — see CLAUDE.md "Input flow" section).
//
// State machine:
//   - bOpen = false, bClosing = false : window invisible, ticks idle.
//   - Open(WM_Weapon)    : begin showing the weapon wheel (fades in).
//   - Open(WM_Aug)       : begin showing the aug wheel (fades in).
//   - UpdateStick(x, y)  : called every right-stick axis event while open.
//   - Close(bApply)      : dispatch selection at button-release time, then
//                          fade out. bOpen becomes false immediately;
//                          bClosing stays true until openAlpha reaches 0.
//=============================================================================
class RadialMenuWindow extends HUDBaseWindow
    config(DeusEx);

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

var config bool bGamepadDebugLog;

var bool  bOpen;
var int   mode;            // WM_None | WM_Weapon | WM_Aug
var float stickX, stickY;  // latest right-stick sample, -1000..1000
var int   highlightedSlot; // 0..9 or -1 if in deadzone / wheel closed
var Augmentation augSlots[10];  // null where slot is empty
var Color colAugActive;
var Color colAugInactive;

// Fade state.
var float openAlpha;       // 0..1
var bool  bClosing;        // true while fading out (bOpen is already false)
var float lastDrawTime;    // for per-frame delta computation in DrawWindow

function DebugLog(string msg)
{
    if (bGamepadDebugLog)
        Log(msg);
}

function Open(int newMode)
{
    if (bOpen)
        return;
    bOpen = true;
    bClosing = false;
    openAlpha = 0.0;
    mode = newMode;
    stickX = 0;
    stickY = 0;
    highlightedSlot = -1;
    if (mode == WM_Aug)
        PopulateAugSlots();
    DebugLog("DXC-WHEEL OPEN mode=" $ string(newMode));
}

function PopulateAugSlots()
{
    local Augmentation aug;
    local int i, j;

    // Clear the cache.
    for (i = 0; i < 10; i++)
        augSlots[i] = None;

    if (player == None || player.AugmentationSystem == None)
        return;

    // Walk the aug list, insertion-sort by HotKeyNum into augSlots.
    aug = player.AugmentationSystem.FirstAug;
    while (aug != None)
    {
        if (aug.bHasIt && !aug.bAlwaysActive)
        {
            // Find insertion index.
            for (i = 0; i < 10; i++)
            {
                if (augSlots[i] == None)
                    break;
                if (aug.HotKeyNum < augSlots[i].HotKeyNum)
                    break;
            }

            if (i < 10)
            {
                // Shift higher slots up.
                for (j = 9; j > i; j--)
                    augSlots[j] = augSlots[j-1];
                augSlots[i] = aug;
            }
        }
        aug = aug.next;
    }
}

function Close(bool bApply)
{
    local DeusExRootWindow root;
    local HUDObjectBelt belt;
    local Inventory inv;
    local Augmentation aug;
    local string actionLog;

    if (!bOpen)
        return;

    actionLog = "cancel";

    // If a non-HUD window is on top at close time, the close was triggered
    // by Extension.InputExt's synthesised release (UI took focus mid-hold).
    // Demote to cancel so we don't accidentally equip/toggle.
    if (bApply)
    {
        root = DeusExRootWindow(GetRootWindow());
        if (root != None && root.GetTopWindow() != None)
        {
            bApply = false;
            actionLog = "cancel-ui";
        }
    }

    if (bApply && highlightedSlot >= 0)
    {
        if (mode == WM_Weapon)
        {
            root = DeusExRootWindow(GetRootWindow());
            if (root != None && root.hud != None && root.hud.belt != None && player != None)
            {
                belt = root.hud.belt;
                inv = belt.objects[highlightedSlot].GetItem();
                if (inv != None)
                {
                    player.ActivateBelt(highlightedSlot);
                    actionLog = "equip";
                }
                else
                {
                    player.PutInHand(None);
                    actionLog = "unequip";
                }
            }
        }
        else if (mode == WM_Aug)
        {
            aug = augSlots[highlightedSlot];
            if (aug != None)
            {
                if (aug.IsActive())
                {
                    aug.Deactivate();
                    actionLog = "deactivate";
                }
                else
                {
                    aug.Activate();
                    actionLog = "activate";
                }
            }
        }
    }

    DebugLog("DXC-WHEEL CLOSE slot=" $ string(highlightedSlot)
        $ " action=" $ actionLog);

    bOpen = false;
    bClosing = true;
    highlightedSlot = -1;
    // mode stays set until fade-out completes — so DrawWindow can still
    // render the right wheel type during the fade.
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
        DebugLog("DXC-WHEEL HL slot=" $ string(highlightedSlot));
}

function RefreshHUDDisplay(float DeltaTime)
{
    local DeusExRootWindow root;

    Super.RefreshHUDDisplay(DeltaTime);

    if (!bOpen)
        return;

    root = DeusExRootWindow(GetRootWindow());
    if (root == None)
        return;

    // GetTopWindow returns the topmost pushed window (datacube, conversation,
    // persona screen, computer terminal). If anything is pushed, cancel —
    // Extension.InputExt will synthesise releases for all held keys including
    // our trigger button, and we don't want that release to be treated as an
    // intentional selection.
    if (root.GetTopWindow() != None)
    {
        DebugLog("DXC-WHEEL CANCEL reason=ui-takeover");
        Close(false);
    }
}

event DrawWindow(GC gc)
{
    local int i;
    local float cx, cy;
    local float now, delta;
    local Color tintFrame, tintWhite, tintDim, tintAug;
    local DeusExRootWindow root;
    local HUDObjectBelt belt;
    local Inventory inv;
    local Augmentation aug;

    Super.DrawWindow(gc);

    if (!bOpen && !bClosing)
        return;

    // Per-frame fade animation. Use Level.TimeSeconds because RefreshHUDDisplay
    // is throttled to 4 Hz upstream and would produce a step-jump rather than
    // a smooth fade.
    if (player != None)
    {
        now = player.Level.TimeSeconds;
        if (lastDrawTime <= 0.0)
            delta = 0.0;          // first frame since open/reopen
        else
            delta = now - lastDrawTime;
        lastDrawTime = now;

        // Long delta = wheel was closed for a while, reset cleanly.
        if (delta > 0.5)
            delta = 0.0;

        if (bOpen && !bClosing)
            openAlpha = FMin(1.0, openAlpha + delta / 0.08);
        else if (bClosing)
        {
            openAlpha = FMax(0.0, openAlpha - delta / 0.08);
            if (openAlpha <= 0.0)
            {
                bClosing = false;
                mode = WM_None;
                lastDrawTime = 0.0;
                return;  // fade-out done, nothing to draw
            }
        }
    }

    root = DeusExRootWindow(GetRootWindow());
    if (root == None)
        return;

    cx = width  * 0.5;
    cy = height * 0.5;

    // Pull the HUD theme colour for our accent (colBorder is maintained by
    // HUDBaseWindow.StyleChanged and stays in sync with theme changes).
    tintFrame = colBorder;
    tintWhite = ColorAlpha(255, 255, 255, 255);
    tintDim   = ColorAlpha(80, 80, 80, 255);

    gc.EnableTranslucency(true);

    if (mode == WM_Weapon)
    {
        if (root.hud == None || root.hud.belt == None)
            return;
        belt = root.hud.belt;
        for (i = 0; i < 10; i++)
        {
            inv = belt.objects[i].GetItem();
            DrawSlot(gc, i, cx, cy, inv, (i == highlightedSlot),
                     tintFrame, tintWhite, tintDim, openAlpha);
        }
    }
    else if (mode == WM_Aug)
    {
        for (i = 0; i < 10; i++)
        {
            aug = augSlots[i];
            if (aug != None && aug.IsActive())
                tintAug = colAugActive;
            else
                tintAug = colAugInactive;
            DrawAugSlot(gc, i, cx, cy, aug, (i == highlightedSlot),
                        tintFrame, tintAug, tintDim, openAlpha);
        }
    }

    DrawCentreReadout(gc, cx, cy, tintFrame, tintWhite, openAlpha);
}

function DrawSlot(GC gc, int slotIdx, float cx, float cy,
                  Inventory inv, bool bSelected,
                  Color tintFrame, Color tintIcon, Color tintDim,
                  float alpha)
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
        gc.SetTileColor(ScaleAlpha(tintFrame, alpha));
        gc.DrawTexture(fx, fy, frameSize, frameSize, 0, 0, Texture'Engine.WhiteTexture');
    }

    if (inv != None && inv.Icon != None)
    {
        gc.SetTileColor(ScaleAlpha(tintIcon, alpha));
        gc.DrawTexture(x, y, size, size, 0, 0, inv.Icon);
    }
    else
    {
        // Empty slot — dim placeholder frame, no icon.
        gc.SetTileColor(ScaleAlpha(tintDim, alpha));
        gc.DrawTexture(x, y, size, size, 0, 0, Texture'Engine.WhiteTexture');
    }
}

function DrawAugSlot(GC gc, int slotIdx, float cx, float cy,
                     Augmentation aug, bool bSelected,
                     Color tintFrame, Color tintAug, Color tintDim,
                     float alpha)
{
    local float angleDeg, angleRad;
    local float sx, sy, size, x, y;
    local float frameSize, fx, fy;
    local Texture iconTex;

    angleDeg = slotIdx * 36.0;
    angleRad = angleDeg / DegreesPerRadian;
    sx = cx + WheelRadius * Sin(angleRad);
    sy = cy - WheelRadius * Cos(angleRad);

    size = IconSize;
    if (bSelected)
        size = IconSize * IconSelScale;
    x = sx - size * 0.5;
    y = sy - size * 0.5;

    if (bSelected)
    {
        frameSize = size + 2.0 * FramePadding;
        fx = sx - frameSize * 0.5;
        fy = sy - frameSize * 0.5;
        gc.SetTileColor(ScaleAlpha(tintFrame, alpha));
        gc.DrawTexture(fx, fy, frameSize, frameSize, 0, 0, Texture'Engine.WhiteTexture');
    }

    if (aug != None)
    {
        iconTex = aug.smallIcon;
        if (iconTex == None)
            iconTex = aug.Icon;
        if (iconTex != None)
        {
            gc.SetTileColor(ScaleAlpha(tintAug, alpha));
            gc.DrawTexture(x, y, size, size, 0, 0, iconTex);
        }
    }
    else
    {
        gc.SetTileColor(ScaleAlpha(tintDim, alpha));
        gc.DrawTexture(x, y, size, size, 0, 0, Texture'Engine.WhiteTexture');
    }
}

function DrawCentreReadout(GC gc, float cx, float cy,
                           Color tintFrame, Color tintText, float alpha)
{
    local DeusExRootWindow root;
    local HUDObjectBelt belt;
    local Inventory inv;
    local DeusExWeapon dxWeapon;
    local Augmentation aug;
    local string nameLine, statusLine;
    local float panelW, panelH, panelX, panelY;

    if (highlightedSlot < 0)
        return;  // deadzone — nothing to show

    nameLine = "";
    statusLine = "";

    if (mode == WM_Weapon)
    {
        root = DeusExRootWindow(GetRootWindow());
        if (root == None || root.hud == None || root.hud.belt == None)
            return;
        belt = root.hud.belt;
        inv = belt.objects[highlightedSlot].GetItem();
        if (inv == None)
        {
            nameLine   = "(empty)";
            statusLine = "";
        }
        else
        {
            nameLine = inv.ItemName;
            dxWeapon = DeusExWeapon(inv);
            if (dxWeapon != None && dxWeapon.AmmoType != None)
                statusLine = string(dxWeapon.AmmoType.AmmoAmount)
                           $ " / " $ string(dxWeapon.AmmoType.MaxAmmo);
            else
                statusLine = "";
        }
    }
    else if (mode == WM_Aug)
    {
        aug = augSlots[highlightedSlot];
        if (aug == None)
        {
            nameLine   = "(unassigned)";
            statusLine = "";
        }
        else
        {
            nameLine = aug.AugmentationName;
            if (aug.IsActive())
                statusLine = string(Int(aug.EnergyRate)) $ "/min  ACTIVE";
            else
                statusLine = string(Int(aug.EnergyRate)) $ "/min  OFF";
        }
    }

    // Background panel.
    panelW = 180;
    panelH = 40;
    panelX = cx - panelW * 0.5;
    panelY = cy - panelH * 0.5;
    gc.SetTileColor(ScaleAlpha(tintFrame, alpha));
    gc.DrawTexture(panelX, panelY, panelW, panelH, 0, 0, Texture'Engine.WhiteTexture');

    gc.SetTextColor(ScaleAlpha(tintText, alpha));
    gc.SetFont(Font'DeusExUI.FontMenuSmall');
    gc.SetAlignments(HALIGN_Center, VALIGN_Top);
    gc.DrawText(panelX, panelY + 4, panelW, 16, nameLine);
    gc.DrawText(panelX, panelY + 20, panelW, 16, statusLine);
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

function Color ScaleAlpha(Color c, float scale)
{
    c.A = int(float(c.A) * scale);
    return c;
}

defaultproperties
{
    bOpen=False
    mode=0
    highlightedSlot=-1
    openAlpha=0.0
    bClosing=False
    lastDrawTime=0.0
    colAugActive=(R=255,G=255,B=0,A=255)
    colAugInactive=(R=100,G=100,B=100,A=255)
}
