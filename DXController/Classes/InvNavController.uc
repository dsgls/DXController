//=============================================================================
// InvNavController — Inventory grid navigation + per-button activations.
//
// Focus model: variable-size PersonaInventoryItemButtons in winItems treated
// as single navigable units. D-pad picks the nearest item in the requested
// direction by button-center geometry. If no item exists in that direction,
// wrap to the opposite edge of the grid.
//
// Activations:
//   A (Joy1/200)          — on a weapon mod: enter apply-to-weapon mode;
//                           otherwise Equip if enabled, else Use
//   X (Joy3/202)          — open belt-assign wheel sub-dialog
//   Y (Joy4/203)          — change ammo on selected weapon
//   R-stick click (Joy10/209) — drop selected item
//
// ModApply sub-dialog: while applying a weapon mod, the D-pad moves the
// focus frame over any inventory tile (mod stays selected), A applies
// the mod to a focused eligible weapon, B cancels.
//=============================================================================
class InvNavController extends MenuNavController;

// --- Weapon-mod apply (ModApply sub-dialog) ---
var Window modSourceButton;          // mod's tile, captured on enter for B-cancel focus restore
var localized String NoCompatibleWeaponLabel;

function InitFocus()
{
    local PersonaScreenInventory s;
    local Window first;
    s = PersonaScreenInventory(screen);
    if (s == None)
        return;
    first = FirstItemButton(s);
    if (first != None)
    {
        focused = first;
        s.SelectInventory(PersonaItemButton(first));
    }
}

function Window FirstItemButton(PersonaScreenInventory s)
{
    // Topmost (smallest dragPosY then smallest dragPosX) item in winItems.
    local Window c, best;
    local PersonaInventoryItemButton btn, bestBtn;

    if (s == None || s.winItems == None)
        return None;

    c = s.winItems.GetTopChild();
    while (c != None)
    {
        btn = PersonaInventoryItemButton(c);
        if (btn != None)
        {
            if (best == None
                || btn.dragPosY < bestBtn.dragPosY
                || (btn.dragPosY == bestBtn.dragPosY && btn.dragPosX < bestBtn.dragPosX))
            {
                best = c;
                bestBtn = btn;
            }
        }
        c = c.GetLowerSibling();
    }
    return best;
}

function bool HandleDPad(int dx, int dy)
{
    local PersonaScreenInventory s;
    local Window next;

    if (subDialogActive == 'WheelAssign')
        return true;

    if (subDialogActive == 'ModApply')
    {
        s = PersonaScreenInventory(screen);
        if (s == None || focused == None)
            return true;

        next = FindNearestInDirection(s, focused, dx, dy);
        if (next == None)
            next = FindWrapTarget(s, focused, dx, dy);

        // Move the focus frame only — do NOT SelectInventory. Selecting a
        // weapon would run ClearSpecialHighlights and wipe the green
        // upgradeable-weapon highlights, and swap the info panel off the mod.
        if (next != None && next != focused)
            focused = next;
        return true;
    }

    s = PersonaScreenInventory(screen);
    if (s == None || focused == None)
        return true;

    next = FindNearestInDirection(s, focused, dx, dy);
    if (next == None)
        next = FindWrapTarget(s, focused, dx, dy);

    if (next != None && next != focused)
    {
        focused = next;
        s.SelectInventory(PersonaItemButton(next));
        class'DXControllerDebug'.static.DebugLog("DXC-NAV FOCUS item=" $ string(next));
    }
    return true;
}

function Window FindNearestInDirection(PersonaScreenInventory s, Window from, int dx, int dy)
{
    local Window c, best;
    local PersonaInventoryItemButton fromBtn, btn, bestBtn;
    local float fx, fy, cx, cy, distance, bestDist;
    local bool bSkip;

    fromBtn = PersonaInventoryItemButton(from);
    if (fromBtn == None || s.winItems == None)
        return None;

    fx = fromBtn.dragPosX + 0.5 * fromBtn.width  / s.invButtonWidth;
    fy = fromBtn.dragPosY + 0.5 * fromBtn.height / s.invButtonHeight;

    bestDist = 100000000.0;
    c = s.winItems.GetTopChild();
    while (c != None)
    {
        btn = PersonaInventoryItemButton(c);
        bSkip = false;
        if (btn != None && c != from)
        {
            cx = btn.dragPosX + 0.5 * btn.width  / s.invButtonWidth;
            cy = btn.dragPosY + 0.5 * btn.height / s.invButtonHeight;

            // Filter to the requested direction.
            if (dx > 0 && cx <= fx) bSkip = true;
            if (!bSkip && dx < 0 && cx >= fx) bSkip = true;
            if (!bSkip && dy > 0 && cy <= fy) bSkip = true;
            if (!bSkip && dy < 0 && cy >= fy) bSkip = true;

            if (!bSkip)
            {
                distance = (cx - fx) * (cx - fx) + (cy - fy) * (cy - fy);
                if (distance < bestDist)
                {
                    bestDist = distance;
                    best = c;
                    bestBtn = btn;
                }
            }
        }
        c = c.GetLowerSibling();
    }
    return best;
}

function Window FindWrapTarget(PersonaScreenInventory s, Window from, int dx, int dy)
{
    // Wrap: pick the item furthest in the OPPOSITE direction (same row/col when possible).
    local Window c, best;
    local PersonaInventoryItemButton fromBtn, btn, bestBtn;
    local float fy, cx, cy;
    local float bestKey;
    local bool sameAxis;

    fromBtn = PersonaInventoryItemButton(from);
    if (fromBtn == None || s.winItems == None)
        return None;

    fy = fromBtn.dragPosY + 0.5;

    if (dx != 0)
    {
        // Horizontal wrap: pick item furthest in OPPOSITE direction on the same row.
        if (dx > 0) bestKey = 100000000.0;
        else bestKey = -100000000.0;
        c = s.winItems.GetTopChild();
        while (c != None)
        {
            btn = PersonaInventoryItemButton(c);
            if (btn != None && c != from)
            {
                cx = btn.dragPosX + 0.5;
                cy = btn.dragPosY + 0.5;
                sameAxis = Abs(cy - fy) < 0.5;
                if (sameAxis)
                {
                    if ((dx > 0 && cx < bestKey) || (dx < 0 && cx > bestKey))
                    {
                        bestKey = cx;
                        best = c;
                        bestBtn = btn;
                    }
                }
            }
            c = c.GetLowerSibling();
        }
        if (best != None)
            return best;
    }
    if (dy != 0)
    {
        // Vertical wrap: pick item furthest in OPPOSITE direction (any column).
        if (dy > 0) bestKey = 100000000.0;
        else bestKey = -100000000.0;
        c = s.winItems.GetTopChild();
        while (c != None)
        {
            btn = PersonaInventoryItemButton(c);
            if (btn != None && c != from)
            {
                cy = btn.dragPosY + 0.5;
                if ((dy > 0 && cy < bestKey) || (dy < 0 && cy > bestKey))
                {
                    bestKey = cy;
                    best = c;
                    bestBtn = btn;
                }
            }
            c = c.GetLowerSibling();
        }
        return best;
    }
    return None;
}

function bool HandleActivate(byte button)
{
    local PersonaScreenInventory s;

    if (subDialogActive == 'WheelAssign')
    {
        ResolveAssignWheel(button);
        return true;
    }

    if (subDialogActive == 'ModApply')
    {
        ResolveModApply(button);
        return true;
    }

    s = PersonaScreenInventory(screen);
    if (s == None)
        return true;

    if (button == 200)        // IK_Joy1 (A)
    {
        // Weapon mod selected: A starts the apply-to-weapon flow.
        // EnableButtons disables Use for a WeaponMod, but Equip stays
        // sensitive — equipping a mod does nothing useful, so this
        // branch must short-circuit before the Equip/Use fall-through.
        if (s.selectedItem != None && WeaponMod(s.selectedItem.GetClientObject()) != None)
        {
            EnterModApply(s);
            return true;
        }

        // Otherwise: Equip if enabled, else Use.
        if (s.btnEquip != None && s.btnEquip.bIsSensitive)
            s.btnEquip.PressButton();
        else if (s.btnUse != None && s.btnUse.bIsSensitive)
            s.btnUse.PressButton();
        return true;
    }

    if (button == 202)        // IK_Joy3 (X): belt-assign wheel.
    {
        OpenAssignWheel(s);
        return true;
    }

    if (button == 203)        // IK_Joy4 (Y): change ammo.
    {
        if (s.btnChangeAmmo != None && s.btnChangeAmmo.bIsSensitive)
            s.btnChangeAmmo.PressButton();
        return true;
    }

    if (button == 209)        // IK_Joy10 (R-stick click): drop.
    {
        if (s.btnDrop != None && s.btnDrop.bIsSensitive)
            s.btnDrop.PressButton();
        return true;
    }

    return true;
}

function OpenAssignWheel(PersonaScreenInventory s)
{
    local ControllerRootWindow root;
    local Inventory inv;

    if (s == None || s.selectedItem == None)
        return;

    inv = Inventory(s.selectedItem.GetClientObject());
    if (inv == None)
        return;

    // Skip items not assignable to the belt (NanoKeyRing in vanilla).
    if (inv.IsA('NanoKeyRing'))
        return;

    root = ControllerRootWindow(s.GetRootWindow());
    if (root == None || root.radial == None)
        return;

    root.radial.Open(root.radial.WM_BeltAssign, inv, true, s);
    subDialogActive = 'WheelAssign';
    class'DXControllerDebug'.static.DebugLog("DXC-WHEEL OPEN mode=BeltAssign source=" $ inv.ItemName);
}

function ResolveAssignWheel(byte button)
{
    local ControllerRootWindow root;

    root = ControllerRootWindow(screen.GetRootWindow());
    if (root == None || root.radial == None)
    {
        subDialogActive = '';
        return;
    }

    if (button == 200)   // A: confirm if a slot is highlighted; else cancel.
    {
        if (root.radial.highlightedSlot >= 0)
            root.radial.Close(true);
        else
            root.radial.Close(false);
    }
    else if (button == 201)   // B: cancel
    {
        root.radial.Close(false);
    }
    else
    {
        return;    // other buttons no-op while sub-dialog is open
    }

    subDialogActive = '';
}

// ----------------------------------------------------------------------
// IsEligibleWeapon — true if `tile` holds a weapon `mod` can upgrade.
// ----------------------------------------------------------------------

function bool IsEligibleWeapon(Window tile, WeaponMod mod)
{
    local DeusExWeapon wpn;

    if (tile == None || mod == None)
        return false;

    wpn = DeusExWeapon(tile.GetClientObject());
    if (wpn == None)
        return false;

    return mod.CanUpgradeWeapon(wpn);
}

// ----------------------------------------------------------------------
// FirstEligibleWeapon — topmost-leftmost tile holding a weapon `mod` can
// upgrade. Also returns the total eligible count via the out-param.
// ----------------------------------------------------------------------

function Window FirstEligibleWeapon(PersonaScreenInventory s, WeaponMod mod, out int count)
{
    local Window c, best;
    local PersonaInventoryItemButton btn, bestBtn;

    count = 0;
    if (s == None || s.winItems == None || mod == None)
        return None;

    c = s.winItems.GetTopChild();
    while (c != None)
    {
        btn = PersonaInventoryItemButton(c);
        if (btn != None && IsEligibleWeapon(btn, mod))
        {
            count++;
            if (best == None
                || btn.dragPosY < bestBtn.dragPosY
                || (btn.dragPosY == bestBtn.dragPosY && btn.dragPosX < bestBtn.dragPosX))
            {
                best = c;
                bestBtn = btn;
            }
        }
        c = c.GetLowerSibling();
    }
    return best;
}

// ----------------------------------------------------------------------
// EnterModApply — A pressed on a selected weapon mod. Enters ModApply if
// at least one weapon is upgradeable; otherwise posts a status message.
// Caller has already confirmed s.selectedItem holds a WeaponMod.
// ----------------------------------------------------------------------

function EnterModApply(PersonaScreenInventory s)
{
    local WeaponMod mod;
    local Window first;
    local int count;

    if (s == None || s.selectedItem == None)
        return;

    mod = WeaponMod(s.selectedItem.GetClientObject());
    if (mod == None)
        return;

    first = FirstEligibleWeapon(s, mod, count);
    if (count == 0 || first == None)
    {
        if (s.winStatus != None)
            s.winStatus.AddText(NoCompatibleWeaponLabel);
        class'DXControllerDebug'.static.DebugLog("DXC-NAV MODAPPLY no-target mod=" $ mod.ItemName);
        return;
    }

    modSourceButton = focused;
    focused = first;
    subDialogActive = 'ModApply';
    class'DXControllerDebug'.static.DebugLog(
        "DXC-NAV MODAPPLY ENTER mod=" $ mod.ItemName $ " targets=" $ string(count));
}

// ----------------------------------------------------------------------
// ApplyModToFocusedWeapon — applies the selected mod to the focused
// weapon, mirroring the vanilla PersonaScreenInventory.FinishButtonDrag
// block, then reselects the upgraded weapon.
// ----------------------------------------------------------------------

function ApplyModToFocusedWeapon(PersonaScreenInventory s)
{
    local WeaponMod mod;
    local DeusExWeapon wpn;

    if (s == None || s.selectedItem == None || focused == None)
        return;

    mod = WeaponMod(s.selectedItem.GetClientObject());
    wpn = DeusExWeapon(focused.GetClientObject());
    if (mod == None || wpn == None || !mod.CanUpgradeWeapon(wpn))
        return;

    mod.ApplyMod(wpn);
    s.player.RemoveObjectFromBelt(mod);
    if (s.winStatus != None)
        s.winStatus.AddText(Sprintf(s.WeaponUpgradedLabel, wpn.itemName));
    mod.DestroyMod();   // destroys the mod actor; its tile is removed via InventoryDeleted

    class'DXControllerDebug'.static.DebugLog("DXC-NAV MODAPPLY APPLY weapon=" $ wpn.ItemName);

    // Reselect the upgraded weapon (parity with FinishButtonDrag) so its
    // updated stats show in the info panel. focused still points at the
    // weapon tile — only the mod tile was destroyed above.
    s.SelectInventory(PersonaItemButton(focused));
}

// ----------------------------------------------------------------------
// ResolveModApply — button dispatch while ModApply is active.
//   A (200) — apply if focused on an eligible weapon, then exit mode.
//   B (201) — cancel, restore focus to the mod tile, exit mode.
//   other   — no-op (consumed).
// ----------------------------------------------------------------------

function ResolveModApply(byte button)
{
    local PersonaScreenInventory s;

    s = PersonaScreenInventory(screen);
    if (s == None)
    {
        subDialogActive = '';
        modSourceButton = None;
        return;
    }

    if (button == 200)        // A
    {
        if (s.selectedItem != None && focused != None
            && IsEligibleWeapon(focused, WeaponMod(s.selectedItem.GetClientObject())))
        {
            ApplyModToFocusedWeapon(s);
            subDialogActive = '';
            modSourceButton = None;
        }
        // else: ignored — the green highlight already signals validity,
        // and B exits, so there is no soft-lock.
    }
    else if (button == 201)   // B
    {
        if (modSourceButton != None)
            focused = modSourceButton;
        modSourceButton = None;
        subDialogActive = '';
        class'DXControllerDebug'.static.DebugLog("DXC-NAV MODAPPLY CANCEL");
    }
    // other buttons: no-op while ModApply is active.
}

defaultproperties
{
    bAllowRepeat=False    // grid nav: single-press only
    NoCompatibleWeaponLabel="No compatible weapon to upgrade"
}
