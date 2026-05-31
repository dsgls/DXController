//=============================================================================
// InvNavController — Inventory grid navigation + per-button activations.
//
// Focus model: variable-size PersonaInventoryItemButtons in winItems treated
// as single navigable units, navigated on the underlying tile grid. A
// logical cursor cell (cursorX, cursorY) rides inside the focused item;
// `focused` is the whole item the cursor sits on. D-pad picks the nearest
// item whose tile-rectangle lies in the pressed direction, ranked by lane
// distance (how far it is from the cursor's row/column) then directional
// distance. The perpendicular lane coordinate is preserved across
// straight-line travel, so leaving a multi-slot item exits under the tile
// you entered on. If no item lies in that direction, wrap within the lane
// to the far edge of the grid. An item's tile span is invSlotsX/invSlotsY
// (each tile invButtonWidth/Height px); collapsing items to a single
// center point — the old model — mis-picked neighbours of multi-slot items.
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
// mod's tile, captured on ModApply enter for B-cancel focus restore.
// NB: like `focused`, this may go stale across PersonaScreenInventory's
// periodic RefreshInventoryItemButtons rebuild (~0.25s) — same
// pre-existing inventory-screen limitation noted in the design spec.
var Window modSourceButton;
var localized String NoCompatibleWeaponLabel;

// --- Tile cursor ---
// The logical cursor cell, in grid tile coordinates (0-based col/row).
// Always kept inside `focused`'s tile rectangle. The perpendicular
// coordinate acts as the "lane" preserved across straight-line D-pad
// travel — this is what makes leaving a multi-slot item exit under the
// tile it was entered on. Seeded by SeedCursor; advanced by
// UpdateCursorAfterMove.
var int cursorX, cursorY;

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
        SeedCursor(first);
        s.SelectInventory(PersonaItemButton(first));
    }
}

// Place the cursor on an item's top-left tile. Used when focus is set
// without a directional move (InitFocus, ModApply enter, B-cancel).
function SeedCursor(Window w)
{
    local PersonaInventoryItemButton btn;
    btn = PersonaInventoryItemButton(w);
    if (btn != None)
    {
        cursorX = btn.dragPosX;
        cursorY = btn.dragPosY;
    }
}

// An item's inclusive tile rectangle: top-left (dragPosX,dragPosY), span
// invSlotsX/invSlotsY from the client Inventory. Returns false for a
// non-item window (e.g. a stray winItems child) so callers can skip it.
function bool GetItemRect(Window w, out int x0, out int y0, out int x1, out int y1)
{
    local PersonaInventoryItemButton btn;
    local Inventory inv;

    btn = PersonaInventoryItemButton(w);
    if (btn == None)
        return false;
    inv = Inventory(btn.GetClientObject());
    if (inv == None)
        return false;

    x0 = btn.dragPosX;
    y0 = btn.dragPosY;
    x1 = x0 + inv.invSlotsX - 1;
    y1 = y0 + inv.invSlotsY - 1;
    return true;
}

// Distance from scalar `v` to the inclusive span [lo..hi]: 0 if inside.
function int SpanDist(int v, int lo, int hi)
{
    if (v < lo)
        return lo - v;
    if (v > hi)
        return v - hi;
    return 0;
}

// After landing on `next` via a (dx,dy) press, move the cursor onto the
// edge tile it was entered on while preserving the lane (the
// perpendicular coordinate), clamped into `next`'s span if a wrap or
// off-lane landing put it outside.
function UpdateCursorAfterMove(Window next, int dx, int dy)
{
    local int x0, y0, x1, y1;

    if (!GetItemRect(next, x0, y0, x1, y1))
        return;

    if (dx != 0)
    {
        if (dx > 0)
            cursorX = x0;
        else
            cursorX = x1;
        if (cursorY < y0)
            cursorY = y0;
        else if (cursorY > y1)
            cursorY = y1;
    }
    else if (dy != 0)
    {
        if (dy > 0)
            cursorY = y0;
        else
            cursorY = y1;
        if (cursorX < x0)
            cursorX = x0;
        else if (cursorX > x1)
            cursorX = x1;
    }
}

// The focused item button was Destroyed out from under us — the item was
// dropped (R-stick) or a single-use consumable was used up (A), and
// vanilla RemoveSelectedItem ran selectedItem.Destroy(). Re-home focus to
// the nearest remaining item to the preserved cursor cell — i.e. the next
// neighbour — rather than restarting at the first item. The cursor cell
// (cursorX, cursorY) is plain ints, so it survives the button's
// destruction and anchors the choice. Called from ControllerRootWindow.
// Tick (between frames), where SelectInventory is safe to call.
function OnFocusedDestroyed()
{
    local PersonaScreenInventory s;
    local Window nbr;

    s = PersonaScreenInventory(screen);
    if (s == None)
    {
        Super.OnFocusedDestroyed();
        return;
    }

    nbr = FindNearestToCursor(s);
    if (nbr == None)
    {
        // Nothing left to focus — shouldn't happen (the NanoKeyRing is
        // non-droppable and non-usable, so an item always remains), but
        // stay safe and fall back to the base reseed path.
        Super.OnFocusedDestroyed();
        return;
    }

    focused = nbr;
    ClampCursorInto(nbr);
    s.SelectInventory(PersonaItemButton(nbr));
    class'DXControllerDebug'.static.DebugLog("DXC-NAV INV-RECOVER focus=" $ string(nbr));
}

// Nearest remaining inventory item to the logical cursor cell, by tile
// Manhattan distance, tie-broken in reading order (top-most then
// left-most). The cursor sits in the now-vacated tiles of the removed
// item, so the nearest surviving item is its spatial neighbour.
function Window FindNearestToCursor(PersonaScreenInventory s)
{
    local Window c, best;
    local int x0, y0, x1, y1;
    local int d, bestD;
    local PersonaInventoryItemButton btn, bestBtn;

    if (s == None || s.winItems == None)
        return None;

    c = s.winItems.GetTopChild();
    while (c != None)
    {
        if (GetItemRect(c, x0, y0, x1, y1))
        {
            d = SpanDist(cursorX, x0, x1) + SpanDist(cursorY, y0, y1);
            btn = PersonaInventoryItemButton(c);
            if (best == None
                || d < bestD
                || (d == bestD
                    && (btn.dragPosY < bestBtn.dragPosY
                        || (btn.dragPosY == bestBtn.dragPosY
                            && btn.dragPosX < bestBtn.dragPosX))))
            {
                best = c;
                bestD = d;
                bestBtn = btn;
            }
        }
        c = c.GetLowerSibling();
    }
    return best;
}

// Clamp the preserved cursor cell into w's tile rect, so a subsequent
// D-pad move continues from where the cursor was rather than jumping to a
// corner.
function ClampCursorInto(Window w)
{
    local int x0, y0, x1, y1;

    if (!GetItemRect(w, x0, y0, x1, y1))
        return;
    if (cursorX < x0)
        cursorX = x0;
    else if (cursorX > x1)
        cursorX = x1;
    if (cursorY < y0)
        cursorY = y0;
    else if (cursorY > y1)
        cursorY = y1;
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
        {
            focused = next;
            UpdateCursorAfterMove(next, dx, dy);
        }
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
        UpdateCursorAfterMove(next, dx, dy);
        s.SelectInventory(PersonaItemButton(next));
        class'DXControllerDebug'.static.DebugLog("DXC-NAV FOCUS item=" $ string(next));
    }
    return true;
}

function Window FindNearestInDirection(PersonaScreenInventory s, Window from, int dx, int dy)
{
    // Phase 1: nearest item whose tile-rectangle lies strictly in the
    // pressed direction, ranked by lane distance (distance from the
    // cursor's row/column) then directional distance.
    local Window c, best;
    local int fx0, fy0, fx1, fy1;       // focused item's tile rect
    local int jx0, jy0, jx1, jy1;       // candidate's tile rect
    local int laneDist, dirDist, bestLane, bestDir;
    local bool bInDir;

    if (s == None || s.winItems == None || !GetItemRect(from, fx0, fy0, fx1, fy1))
        return None;

    c = s.winItems.GetTopChild();
    while (c != None)
    {
        if (c != from && GetItemRect(c, jx0, jy0, jx1, jy1))
        {
            // "In direction": candidate's near edge is strictly past the
            // focused item's far edge along the pressed axis. Lane is the
            // cursor's perpendicular coordinate.
            bInDir = false;
            if (dx > 0 && jx0 > fx1)
            {
                bInDir = true;
                dirDist = jx0 - fx1;
                laneDist = SpanDist(cursorY, jy0, jy1);
            }
            else if (dx < 0 && jx1 < fx0)
            {
                bInDir = true;
                dirDist = fx0 - jx1;
                laneDist = SpanDist(cursorY, jy0, jy1);
            }
            else if (dy > 0 && jy0 > fy1)
            {
                bInDir = true;
                dirDist = jy0 - fy1;
                laneDist = SpanDist(cursorX, jx0, jx1);
            }
            else if (dy < 0 && jy1 < fy0)
            {
                bInDir = true;
                dirDist = fy0 - jy1;
                laneDist = SpanDist(cursorX, jx0, jx1);
            }

            if (bInDir
                && (best == None
                    || laneDist < bestLane
                    || (laneDist == bestLane && dirDist < bestDir)))
            {
                best = c;
                bestLane = laneDist;
                bestDir = dirDist;
            }
        }
        c = c.GetLowerSibling();
    }
    return best;
}

function Window FindWrapTarget(PersonaScreenInventory s, Window from, int dx, int dy)
{
    // Phase 2 (only when nothing is in-direction): wrap within the lane to
    // the item furthest in the OPPOSITE direction. Prefer the cursor's
    // lane (same row for a horizontal press, same column for vertical),
    // then take the furthest-back item — so a left press lands on the
    // row's rightmost item, a down press on the column's topmost, etc.
    local Window c, best;
    local int fx0, fy0, fx1, fy1;
    local int jx0, jy0, jx1, jy1;
    local int laneDist, dirKey, bestLane, bestDir;

    if (s == None || s.winItems == None || !GetItemRect(from, fx0, fy0, fx1, fy1))
        return None;

    c = s.winItems.GetTopChild();
    while (c != None)
    {
        if (c != from && GetItemRect(c, jx0, jy0, jx1, jy1))
        {
            if (dx != 0)
            {
                laneDist = SpanDist(cursorY, jy0, jy1);
                // Minimising dirKey maximises distance in the opposite
                // direction: left press -> largest jx1, right -> smallest jx0.
                if (dx < 0)
                    dirKey = -jx1;
                else
                    dirKey = jx0;
            }
            else
            {
                laneDist = SpanDist(cursorX, jx0, jx1);
                if (dy < 0)
                    dirKey = -jy1;
                else
                    dirKey = jy0;
            }

            if (best == None
                || laneDist < bestLane
                || (laneDist == bestLane && dirKey < bestDir))
            {
                best = c;
                bestLane = laneDist;
                bestDir = dirKey;
            }
        }
        c = c.GetLowerSibling();
    }
    return best;
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
        // EnableButtons disables ChangeAmmo and Use for a WeaponMod,
        // but Equip stays sensitive — equipping a mod does nothing
        // useful, so this branch must short-circuit before the
        // Equip/Use fall-through.
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
    SeedCursor(first);
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
        {
            focused = modSourceButton;
            SeedCursor(modSourceButton);
        }
        modSourceButton = None;
        subDialogActive = '';
        class'DXControllerDebug'.static.DebugLog("DXC-NAV MODAPPLY CANCEL");
    }
    // other buttons: no-op while ModApply is active.
}

// Context-dependent legend: the inventory screen rebinds A/B while a
// sub-dialog is active, and BuildHints runs every frame, so it just
// branches on subDialogActive.
function BuildHints()
{
    if (subDialogActive == 'ModApply')
    {
        AddHint("a", "Apply mod");
        AddHint("b", "Cancel");
        return;
    }
    if (subDialogActive == 'WheelAssign')
    {
        AddHint("a", "Assign");
        AddHint("b", "Cancel");
        return;
    }
    AddHint("a", "Use/Equip");
    AddHint("x", "Assign slot");
    AddHint("y", "Change ammo");
    AddHint("rs", "Drop");
    AddHint("lb", "Prev tab");
    AddHint("rb", "Next tab");
    AddHint("b", "Close");
}

defaultproperties
{
    bAllowRepeat=False    // grid nav: single-press only
    NoCompatibleWeaponLabel="No compatible weapon to upgrade"
}
