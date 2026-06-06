//=============================================================================
// RadialMenuWindow — gamepad weapon / aug wheel.
//
// Rendered as a sibling of `hud` in the root-window tree. Does NOT push
// onto the window stack (a pushed UI window would cause Extension.InputExt
// to synthesise a release on the held trigger button, immediately closing
// the wheel — see CLAUDE.md "Input flow" section).
//
// State machine:
//   - bOpen = false : window invisible, ticks idle.
//   - Open(WM_Weapon)   : show the weapon wheel immediately (no fade).
//   - Open(WM_Aug)      : show the aug wheel immediately (no fade).
//   - UpdateStick(x, y) : called every right-stick axis event while open.
//   - Close(bApply)     : dispatch selection at button-release time, hide
//                         immediately. bOpen becomes false right away.
//=============================================================================
class RadialMenuWindow extends HUDBaseWindow;

// Wheel mode values; matches the spec's EWheelMode.
const WM_None      = 0;
const WM_Weapon    = 1;
const WM_Aug       = 2;
const WM_BeltAssign = 3;

const StickDeadzone     = 300.0;    // ~30% of the -1000..1000 axis range
const DegreesPerRadian  = 57.2957795;
const ViewLockGrace     = 0.3;     // seconds after close where RS still swallowed
const FocusGrace        = 0.3;      // seconds after stick recentres where Close still dispatches last-focused slot

const WheelRadius      = 130.0;   // pixels from screen-centre to each icon's centre
const IconSize         = 48.0;    // base icon edge length, pixels
const NumberRadius     = 72.0;    // distance from centre to each slot-number label
const PlateDiameter    = 360.0;   // backplate draw size, pixels (encloses the icon ring)
const PlateTexSize     = 1024.0;  // WheelPlate source texture edge length
const WedgeTexSize     = 1024.0;  // Wedge0..9 source texture edge length (matches the plate)

// Per-slot highlight wedge textures, indexed by slot 0..9. Populated
// from defaultproperties (the `wedgeTex(i)=Texture'...'` literal makes
// the texture name resolvable in the pass-2 DXController compile and
// avoids a 10-way switch at draw time).
var Texture wedgeTex[10];

var bool  bOpen;
var bool  bSticky;
var Inventory sourceItem;
var Window    stickySourceScreen;  // the persona screen the wheel was opened from
var int   mode;            // WM_None | WM_Weapon | WM_Aug | WM_BeltAssign
var float stickX, stickY;  // latest right-stick sample, -1000..1000
var int   highlightedSlot; // 0..9 or -1 if in deadzone / wheel closed
var Augmentation augSlots[10];  // null where slot is empty
var Color colAugActive;
var Color colAugInactive;
// 0..1 brightness scale for the slice glow. DSTY_Translucent ignores
// the colour's alpha, so we dim by scaling colBorder's R/G/B instead.
var float HighlightIntensity;

// Level.TimeSeconds value until which RS axis events should still be
// swallowed after the wheel has closed. Prevents the camera from jerking
// when the user releases LB/RB before re-centring the right stick.
var float viewLockUntil;

// Sticky version of highlightedSlot used by Close's grace fallback.
// Updated in UpdateStick whenever the stick is on a real segment;
// retains its value when the stick re-enters the deadzone so the
// most recently focused slot can still be dispatched if the button
// is released within FocusGrace.
var int   lastFocusedSlot;
// Level.TimeSeconds at which highlightedSlot most recently transitioned
// from a real slot back to -1 (deadzone). 0 means the grace clock has
// never started this open-cycle.
var float lastFocusTime;

function Open(int newMode, optional Inventory item, optional bool bStickyMode, optional Window sourceScreen)
{
    if (bOpen)
        return;
    bOpen = true;
    mode = newMode;
    stickX = 0.0;
    stickY = 0.0;
    highlightedSlot = -1;
    lastFocusedSlot = -1;
    lastFocusTime = 0.0;
    bSticky = bStickyMode;
    sourceItem = item;
    stickySourceScreen = sourceScreen;

    // Draw above any pushed UI. The wheel is a persistent InitWindow-time
    // child of the root, so a later-pushed persona screen — e.g. the
    // inventory screen behind a belt-assign wheel — renders on top of it
    // unless we raise. Without this the opaque backplate is occluded and
    // the wheel ghosts through the screen's translucent background. Same
    // pattern as OnScreenKeyboardWindow.Open and the focus/hint overlays.
    Raise();

    if (mode == WM_Aug)
        PopulateAugSlots();
    class'DXControllerDebug'.static.DebugLog("DXC-WHEEL OPEN mode=" $ string(newMode));
}

function PopulateAugSlots()
{
    local Augmentation aug;
    local int i, idx;

    // Clear the cache.
    for (i = 0; i < 10; i++)
        augSlots[i] = None;

    if (player == None || player.AugmentationSystem == None)
        return;

    // Place augs by hotkey so slot i is always aug F(i+3). HotKeyNum 3..12
    // are the activatable range (AugmentationManager.ActivateAugByKey
    // rejects keyNum outside 0..9). Anything outside that range is
    // silently dropped — a missing hotkey leaves a labelled-but-empty gap.
    aug = player.AugmentationSystem.FirstAug;
    while (aug != None)
    {
        if (aug.bHasIt && !aug.bAlwaysActive)
        {
            idx = aug.HotKeyNum - 3;
            if (idx >= 0 && idx < 10)
                augSlots[idx] = aug;
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
    local PersonaScreenInventory invScreen;
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
            if (bSticky && root.GetTopWindow() == stickySourceScreen)
            {
                // Source screen is the top window — expected for sticky mode. Don't demote.
            }
            else
            {
                bApply = false;
                actionLog = "cancel-ui";
            }
        }
    }

    // Grace fallback: if the stick is in the deadzone at close time but
    // a slot was recently focused, dispatch that slot. Covers the
    // recentre-then-release muscle pattern.
    if (!bSticky && bApply && highlightedSlot < 0 && lastFocusedSlot >= 0 && player != None
        && (player.Level.TimeSeconds - lastFocusTime) < FocusGrace)
    {
        highlightedSlot = lastFocusedSlot;
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
        else if (mode == WM_BeltAssign)
        {
            if (player != None && sourceItem != None)
            {
                // Assign through the inventory screen's belt helper, which
                // updates BOTH the real HUD belt (root.hud.belt — what the
                // wheel and the gameplay item bar read) and the screen's
                // local objBelt display copy, atomically. This is the same
                // path the drag-and-drop handler uses
                // (PersonaScreenInventory drop -> invBelt.AddObject).
                //
                // Do NOT call PersonaScreenInventory.CleanBelt() here: it
                // runs invBelt.hudBelt.ClearBelt() (emptying the real HUD
                // belt) but only repopulates the local objBelt copy, so the
                // gameplay belt and the weapon wheel are left permanently
                // empty while the inventory screen's own bar still looks
                // correct (it rebuilds from item flags on open). CleanBelt
                // is only "safe" in stock because its sole SP caller,
                // RefreshWindow, is dead under NM_Standalone.
                invScreen = PersonaScreenInventory(stickySourceScreen);
                if (invScreen != None && invScreen.invBelt != None)
                    invScreen.invBelt.AddObject(sourceItem, highlightedSlot);
                else
                    player.AddObjectToBelt(sourceItem, highlightedSlot, true);
                actionLog = "assign:" $ string(highlightedSlot);
            }
        }
    }

    class'DXControllerDebug'.static.DebugLog("DXC-WHEEL CLOSE slot=" $ string(highlightedSlot)
        $ " action=" $ actionLog);

    bOpen = false;
    highlightedSlot = -1;
    if (player != None)
        viewLockUntil = player.Level.TimeSeconds + ViewLockGrace;
}

// True while RS events should still bypass the camera-look binding —
// either the wheel is open, or we're inside the post-close grace window.
function bool IsViewLocked()
{
    if (bOpen)
        return true;
    if (player != None && player.Level.TimeSeconds < viewLockUntil)
        return true;
    return false;
}

// Returns angle in degrees clockwise from "up", 0..360.
// Shim sends raw axis: y > 0 = stick up (physical), y < 0 = stick down.
// (User.ini's `JoyY ... INVERT=-1` flips this only for the camera-look
// binding path; the raw axis we receive here is uninverted.)
function float ComputeAngleDegrees(float x, float y)
{
    local float angle;
    if (Abs(y) < 0.001)
    {
        if (x >= 0) return 90.0;
        return 270.0;
    }
    // Shim sends raw axis: y > 0 = stick up (physical), y < 0 = stick down.
    // (User.ini's `JoyY ... INVERT=-1` flips this only for the camera-look
    // binding path; the raw axis we receive here is uninverted.)
    angle = Atan(x / y) * DegreesPerRadian;
    if (y < 0)
        angle += 180.0;         // stick pushed down
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

    if (highlightedSlot >= 0)
    {
        lastFocusedSlot = highlightedSlot;
    }
    else if (oldSlot >= 0 && player != None)
    {
        // Transition from a real slot into the deadzone — start the
        // grace clock so Close can resurrect lastFocusedSlot if the
        // button is released soon after.
        lastFocusTime = player.Level.TimeSeconds;
    }

    if (highlightedSlot != oldSlot)
        class'DXControllerDebug'.static.DebugLog("DXC-WHEEL HL slot=" $ string(highlightedSlot));
}

// Called by ControllerRootWindow.DescendantAdded when a screen gets
// pushed onto the stack. Cancels the wheel so the synthesised release
// (Extension.InputExt fires IST_Release for held keys when UI takes
// focus) doesn't commit an accidental equip/toggle. Replaces the
// per-tick RefreshHUDDisplay polling, which never fired in
// single-player (RefreshDisplay short-circuits on NM_Standalone).
function OnTopWindowPushed(Window pushed)
{
    if (!bOpen)
        return;

    // Sticky-mode source screens (Inventory's belt-assign wheel) are
    // expected — the source is exactly the window we want on top.
    if (bSticky && pushed == stickySourceScreen)
        return;

    class'DXControllerDebug'.static.DebugLog(
        "DXC-WHEEL CANCEL reason=ui-takeover");
    Close(false);
}

event DrawWindow(GC gc)
{
    local int i;
    local float cx, cy;
    local Color tintWhite, tintAug;
    local DeusExRootWindow root;
    local HUDObjectBelt belt;
    local Inventory inv;
    local Augmentation aug;

    Super.DrawWindow(gc);

    if (!bOpen)
        return;

    root = DeusExRootWindow(GetRootWindow());
    if (root == None)
        return;

    cx = width  * 0.5;
    cy = height * 0.5;

    DrawBackplate(gc, cx, cy);

    tintWhite = ColorAlpha(255, 255, 255, 255);

    // Highlight the selected slice (drawn AFTER the plate, BEFORE the
    // icons + numbers, so icons sit on top of the glow). Skipped in the
    // deadzone (highlightedSlot == -1).
    if (highlightedSlot >= 0)
        DrawHighlightSlice(gc, cx, cy, highlightedSlot);

    if (mode == WM_Weapon || mode == WM_BeltAssign)
    {
        if (root.hud == None || root.hud.belt == None)
            return;
        belt = root.hud.belt;
        for (i = 0; i < 10; i++)
        {
            inv = belt.objects[i].GetItem();
            DrawSlot(gc, i, cx, cy, inv);
            DrawSlotNumber(gc, cx, cy, i, string(i));
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
            DrawAugSlot(gc, i, cx, cy, aug, tintAug);
            DrawSlotNumber(gc, cx, cy, i, string(i + 3));
        }
    }

    DrawCentreReadout(gc, cx, cy, tintWhite);
}

// Opaque circular backplate behind the wheel. The WheelPlate texture
// bakes the dark disc, the 10 segment spokes, the steel rim and the
// inset hub; everything outside the circle is the magenta key, so a
// masked draw keys it out. Drawn before any slot. It does not fade —
// an opaque masked texture cannot alpha-fade — so the whole wheel
// hard-snaps (see the design doc).
function DrawBackplate(GC gc, float cx, float cy)
{
    gc.SetStyle(DSTY_Masked);
    gc.SetTileColorRGB(255, 255, 255);
    gc.DrawStretchedTexture(cx - PlateDiameter * 0.5, cy - PlateDiameter * 0.5,
                            PlateDiameter, PlateDiameter,
                            0, 0, PlateTexSize, PlateTexSize,
                            Texture'DXController.WheelPlate');
}

function DrawSlot(GC gc, int slotIdx, float cx, float cy, Inventory inv)
{
    local float angleDeg, angleRad;
    local float sx, sy;
    local Texture tex;
    local float srcW, srcH;

    angleDeg = slotIdx * 36.0;
    angleRad = angleDeg / DegreesPerRadian;
    sx = cx + WheelRadius * Sin(angleRad);
    sy = cy - WheelRadius * Cos(angleRad);

    if (inv != None)
    {
        // Prefer the large icon — the wheel slot is ~48 px, so the
        // large art downscales crisply rather than upscaling soft.
        // Mirror the stock persona inventory screen's choice.
        if (inv.largeIcon != None && inv.largeIconWidth > 0 && inv.largeIconHeight > 0)
        {
            tex  = inv.largeIcon;
            srcW = inv.largeIconWidth;
            srcH = inv.largeIconHeight;
        }
        else if (inv.Icon != None)
        {
            tex  = inv.Icon;
            // Stock weapon `Icon` art is 40x35 inside a padded texture.
            srcW = 40;
            srcH = 35;
        }

        if (tex != None)
            DrawIconCentered(gc, sx, sy, tex, srcW, srcH,
                             ColorAlpha(255, 255, 255, 255));
        else
            DrawEmptyMark(gc, sx, sy);
    }
    else
    {
        DrawEmptyMark(gc, sx, sy);
    }
}

function DrawAugSlot(GC gc, int slotIdx, float cx, float cy,
                     Augmentation aug, Color tintAug)
{
    local float angleDeg, angleRad;
    local float sx, sy;
    local Texture tex;
    local float srcW, srcH;

    angleDeg = slotIdx * 36.0;
    angleRad = angleDeg / DegreesPerRadian;
    sx = cx + WheelRadius * Sin(angleRad);
    sy = cy - WheelRadius * Cos(angleRad);

    if (aug != None)
    {
        // Prefer the large icon (52x52) — same choice as the persona
        // aug screen. Fall back to smallIcon (32x32) if large is unset.
        if (aug.Icon != None)
        {
            tex  = aug.Icon;
            srcW = 52;
            srcH = 52;
        }
        else if (aug.smallIcon != None)
        {
            tex  = aug.smallIcon;
            srcW = 32;
            srcH = 32;
        }

        if (tex != None)
            DrawIconCentered(gc, sx, sy, tex, srcW, srcH, tintAug);
    }
    else
    {
        DrawEmptyMark(gc, sx, sy);
    }
}

// Draws the additive theme-tinted glow over the selected slice. Drawn
// onto the same disc rect as the plate, so the wedge art (greyscale on
// black, slice-shaped) aligns with the plate's spokes by construction.
// Black texels in the wedge add zero under DSTY_Translucent — only the
// slice itself glows. tileColor scales the brightness; default
// colBorder (HUD theme accent).
function DrawHighlightSlice(GC gc, float cx, float cy, int slotIdx)
{
    local Texture tex;
    local Color tinted;

    if (slotIdx < 0 || slotIdx > 9)
        return;
    tex = wedgeTex[slotIdx];
    if (tex == None)
        return;

    tinted.R = int(float(colBorder.R) * HighlightIntensity);
    tinted.G = int(float(colBorder.G) * HighlightIntensity);
    tinted.B = int(float(colBorder.B) * HighlightIntensity);
    tinted.A = colBorder.A;

    gc.SetStyle(DSTY_Translucent);
    gc.SetTileColor(tinted);
    gc.DrawStretchedTexture(cx - PlateDiameter * 0.5, cy - PlateDiameter * 0.5,
                            PlateDiameter, PlateDiameter,
                            0, 0, WedgeTexSize, WedgeTexSize,
                            tex);
}

// Draws an icon texture centred at (sx, sy), scaled to fit inside an
// IconSize box while preserving the source aspect ratio. Uses
// DrawStretchedTexture (which takes a source rect and scales);
// DrawTexture would 1:1-blit the art into the top-left of the box.
// srcW/srcH are the art dimensions (NOT the texture's padded USize/VSize).
function DrawIconCentered(GC gc, float sx, float sy, Texture tex,
                          float srcW, float srcH, Color tileColor)
{
    local float scale, drawW, drawH;

    if (tex == None || srcW <= 0.0 || srcH <= 0.0)
        return;

    scale = IconSize / FMax(srcW, srcH);
    drawW = srcW * scale;
    drawH = srcH * scale;

    gc.SetStyle(DSTY_Masked);
    gc.SetTileColor(tileColor);
    gc.DrawStretchedTexture(sx - drawW * 0.5, sy - drawH * 0.5,
                            drawW, drawH,
                            0, 0, srcW, srcH,
                            tex);
}

// Draws the small reference digit for a slot. Uniform dim cool-grey on
// every slot — the highlighted slot does NOT brighten its number;
// selection emphasis lives entirely in the slice glow (DrawHighlightSlice).
// The colour is built with explicit A=255 and drawn via SetTextColor
// (not SetTextColorRGB) — SetTextColorRGB leaves Color.A == 0 and the
// text would draw fully transparent under DSTY_Masked. See CLAUDE.md
// "GC.SetTextColorRGB / SetTileColorRGB leave Color.A == 0".
function DrawSlotNumber(GC gc, float cx, float cy, int slotIdx, string label)
{
    local float angleDeg, angleRad;
    local float sx, sy;
    local Color dim;
    local float boxW, boxH;

    angleDeg = slotIdx * 36.0;
    angleRad = angleDeg / DegreesPerRadian;
    sx = cx + NumberRadius * Sin(angleRad);
    sy = cy - NumberRadius * Cos(angleRad);

    dim = ColorAlpha(140, 150, 165, 255);
    boxW = 24;
    boxH = 14;

    gc.SetStyle(DSTY_Masked);
    gc.SetTextColor(dim);
    gc.SetFont(Font'DeusExUI.FontMenuSmall');
    gc.SetAlignments(HALIGN_Center, VALIGN_Center);
    gc.DrawText(sx - boxW * 0.5, sy - boxH * 0.5, boxW, boxH, label);
}

// Empty-slot marker: a thin dim outline box with a "+" inside, drawn at
// the slot's icon position. The "+" is two thin filled rectangles —
// GC has no DrawLine primitive, and a thin DrawPattern rect is the
// idiom for an axis-aligned line. All geometric, no texture, so it
// stays visually consistent with the DrawBox outline.
function DrawEmptyMark(GC gc, float sx, float sy)
{
    local Color dim;
    local float boxSize, bx, by;
    local float armLen, armThick;

    dim     = ColorAlpha(74, 81, 96, 255);
    boxSize = IconSize;
    bx      = sx - boxSize * 0.5;
    by      = sy - boxSize * 0.5;

    gc.SetStyle(DSTY_Masked);
    gc.SetTileColor(dim);
    gc.DrawBox(bx, by, boxSize, boxSize, 0, 0, 1, Texture'Solid');

    armLen   = 14.0;
    armThick = 2.0;
    gc.DrawPattern(sx - armLen * 0.5, sy - armThick * 0.5,
                   armLen, armThick, 0, 0, Texture'Solid');
    gc.DrawPattern(sx - armThick * 0.5, sy - armLen * 0.5,
                   armThick, armLen, 0, 0, Texture'Solid');
}

function DrawCentreReadout(GC gc, float cx, float cy, Color tintText)
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
    else if (mode == WM_BeltAssign)
    {
        if (sourceItem != None)
        {
            nameLine = sourceItem.ItemName $ " -> slot " $ string(highlightedSlot);
            root = DeusExRootWindow(GetRootWindow());
            if (root != None && root.hud != None && root.hud.belt != None)
            {
                inv = root.hud.belt.objects[highlightedSlot].GetItem();
                if (inv == None)
                    statusLine = "(empty)";
                else
                    statusLine = "currently: " $ inv.ItemName;
            }
            else
            {
                statusLine = "";
            }
        }
    }

    // The readout text sits on the inset hub baked into the backplate
    // texture, so no separate panel fill is drawn. panelW/panelH/panelX/
    // panelY are kept purely as the text layout rect.
    panelW = 180;
    panelH = 40;
    panelX = cx - panelW * 0.5;
    panelY = cy - panelH * 0.5;

    gc.SetStyle(DSTY_Masked);
    gc.SetTextColor(tintText);
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

defaultproperties
{
    bOpen=False
    mode=0
    highlightedSlot=-1
    colAugActive=(R=255,G=255,B=0,A=255)
    colAugInactive=(R=100,G=100,B=100,A=255)
    HighlightIntensity=0.5
    wedgeTex(0)=Texture'DXController.Wedge0'
    wedgeTex(1)=Texture'DXController.Wedge1'
    wedgeTex(2)=Texture'DXController.Wedge2'
    wedgeTex(3)=Texture'DXController.Wedge3'
    wedgeTex(4)=Texture'DXController.Wedge4'
    wedgeTex(5)=Texture'DXController.Wedge5'
    wedgeTex(6)=Texture'DXController.Wedge6'
    wedgeTex(7)=Texture'DXController.Wedge7'
    wedgeTex(8)=Texture'DXController.Wedge8'
    wedgeTex(9)=Texture'DXController.Wedge9'
}
