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
// SelectInventory on each focus update drives the vanilla selected-
// state highlight on the focused item. The MenuFocusOverlay frame is
// suppressed by the base GetFocusedRect because
// PersonaInventoryItemButton is in HasStockFocusCue.
//
// Activations:
//   A (Joy1/200)          — on a weapon mod: enter apply-to-weapon mode;
//                           on ChargedPickup armour: Use (toggle);
//                           otherwise Equip if enabled, else Use
//   X (Joy3/202)          — open belt-assign wheel sub-dialog
//   Y (Joy4/203)          — enter move-item mode
//   L-stick click (Joy9/208) — change ammo on selected weapon
//   R-stick click (Joy10/209) — drop selected item
//
// Move sub-dialog: while moving, the D-pad nudges the selected item one
// grid cell at a time (clamped on-grid, no wrap), tinting it green if the
// cells are free or red if it would overlap another item. A places it
// (only when green), B cancels back to the original cell. The screen's
// bDragging flag is held for the duration to suppress the periodic
// item-button rebuild; Detach restores the item if the menu closes
// mid-move.
//
// ModApply sub-dialog: while applying a weapon mod, the D-pad moves the
// focus frame over any inventory tile (mod stays selected), A applies
// the mod to a focused eligible weapon, B cancels.
//
// In ModApply mode the overlay frame is the cursor indicator (see
// GetFocusedRect override below): the base HasStockFocusCue policy
// would otherwise suppress it because PersonaInventoryItemButton is
// registered as having its own selection cue — but that cue is on the
// mod, not on the candidate the cursor is over.
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

// --- Move item (Move sub-dialog) ---
// The item's grid anchor captured on Move enter, for B-cancel / Detach
// restore. invPos itself is left unchanged during the move (only the
// button's dragPos slides for preview), so PlaceItemInSlot(moveOrigX,
// moveOrigY) refills the original cells on cancel.
var int moveOrigX, moveOrigY;

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

// Override the base policy in ModApply sub-mode. In that mode the
// controller deliberately doesn't call SelectInventory on the focused
// candidate (the mod itself stays bSelected) — so the candidate has no
// vanilla cue and would have no indicator at all if the base
// GetFocusedRect suppressed the overlay frame (which it does, because
// PersonaInventoryItemButton is in HasStockFocusCue from Task C2). Force
// the frame back on while ModApply is active; outside ModApply, fall
// through to the base policy.
function bool GetFocusedRect(out float x, out float y, out float w, out float h)
{
    local Window root;
    local float lx, ly;

    if (!IsFocusedLive())
        return false;

    if (subDialogActive == 'ModApply')
    {
        root = focused.GetRootWindow();
        lx = 0;
        ly = 0;
        focused.ConvertCoordinates(focused, lx, ly, root, x, y);
        w = focused.width;
        h = focused.height;
        return true;
    }

    return Super.GetFocusedRect(x, y, w, h);
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

    if (subDialogActive == 'Move')
    {
        MoveNudge(dx, dy);
        return true;
    }

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
    local Inventory inv;
    local DeusExPickup pk;
    local bool bUseItem;

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

    if (subDialogActive == 'Move')
    {
        ResolveMove(button);
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

        // Otherwise classify by behaviour, not by class name: a
        // stackable activatable consumable (drinks, biocells, food,
        // cigarettes, medkits, vials, flares) is USED directly;
        // everything else (weapons, grenades, binoculars, tools,
        // wearable charged gear) is EQUIPPED. The use -> equip -> use
        // fall-through keeps A always acting (no soft-lock) and is
        // mirrored exactly by BuildHints' A label.
        inv = None;
        if (s.selectedItem != None)
            inv = Inventory(s.selectedItem.GetClientObject());
        pk = DeusExPickup(inv);
        // ChargedPickup armour/camo (Ballistic, Thermoptic, HazMat,
        // Rebreather, TechGoggles) is bActivatable but single-copy, so it
        // would fall through to Equip (PutInHand — useless). Classify it
        // with the used-in-place items so A toggles it via btnUse.
        bUseItem = (pk != None && pk.bActivatable && pk.bCanHaveMultipleCopies)
                   || (ChargedPickup(inv) != None);

        if (bUseItem && s.btnUse != None && s.btnUse.bIsSensitive)
            s.btnUse.PressButton();
        else if (s.btnEquip != None && s.btnEquip.bIsSensitive)
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

    if (button == 203)        // IK_Joy4 (Y): enter move-item mode.
    {
        EnterMove(s);
        return true;
    }

    if (button == 208)        // IK_Joy9 (L-stick click): change ammo.
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

// ----------------------------------------------------------------------
// EnterMove — Y pressed in normal mode. Begins a modal reposition of the
// selected item: clears its own footprint so it can't collide with
// itself, holds the screen's bDragging flag to suppress the 0.25s rebuild
// (keeping `focused` and the cleared invSlots valid), and starts the
// item green. Mirrors the mouse StartButtonDrag setup.
// ----------------------------------------------------------------------
function EnterMove(PersonaScreenInventory s)
{
    local Inventory inv;

    if (s == None || s.selectedItem == None || focused == None)
        return;

    inv = Inventory(s.selectedItem.GetClientObject());
    if (inv == None)
        return;

    moveOrigX = inv.invPosX;
    moveOrigY = inv.invPosY;

    s.bDragging = True;                 // suppress rebuild for the duration
    s.ClearSpecialHighlights();         // drop mod/ammo green overlays
    s.SelectInventory(None);            // deselect (like stock StartButtonDrag)
                                        // so the green/red tint owns the button
                                        // during the move and the selected cue
                                        // restores cleanly via SelectInventory
                                        // on exit
    s.player.SetInvSlots(inv, 0);       // free the item's own cells

    focused.Raise();                                          // draw on top
    PersonaInventoryItemButton(focused).SetDropFill(True);    // start green

    subDialogActive = 'Move';
    class'DXControllerDebug'.static.DebugLog("DXC-NAV MOVE ENTER item=" $ inv.ItemName);
}

// ----------------------------------------------------------------------
// MoveNudge — D-pad in Move mode. Shifts the item's anchor one cell,
// clamped so its footprint stays on the 5x6 grid (no wrap), slides the
// button there, and recolours green (free) / red (would overlap).
// ----------------------------------------------------------------------
function MoveNudge(int dx, int dy)
{
    local PersonaScreenInventory s;
    local PersonaInventoryItemButton btn;
    local Inventory inv;
    local int nx, ny, maxX, maxY;

    s = PersonaScreenInventory(screen);
    btn = PersonaInventoryItemButton(focused);
    if (s == None || btn == None)
        return;
    inv = Inventory(btn.GetClientObject());
    if (inv == None)
        return;

    nx = btn.dragPosX + dx;
    ny = btn.dragPosY + dy;

    maxX = s.player.maxInvCols - inv.invSlotsX;
    maxY = s.player.maxInvRows - inv.invSlotsY;
    if (nx < 0)
        nx = 0;
    else if (nx > maxX)
        nx = maxX;
    if (ny < 0)
        ny = 0;
    else if (ny > maxY)
        ny = maxY;

    s.SetItemButtonPos(btn, nx, ny);
    btn.SetDropFill(s.player.IsEmptyItemSlot(inv, nx, ny));
}

// ----------------------------------------------------------------------
// ResolveMove — button dispatch while Move is active.
//   A (200) — place if the candidate cell is valid (green), else no-op.
//   B (201) — cancel: restore the item to its original cell.
//   other   — no-op (consumed).
// Both A-commit and B-cancel restore the normal selected cue via
// SelectInventory and clear move flags via EndMove.
// ----------------------------------------------------------------------
function ResolveMove(byte button)
{
    local PersonaScreenInventory s;
    local PersonaInventoryItemButton btn;
    local Inventory inv;

    s = PersonaScreenInventory(screen);
    btn = PersonaInventoryItemButton(focused);
    if (s == None || btn == None)
    {
        EndMove();
        return;
    }
    inv = Inventory(btn.GetClientObject());
    if (inv == None)          // item gone out from under us — bail cleanly so
    {                         // bDragging/subDialogActive never stick.
        EndMove();
        return;
    }

    if (button == 200)        // A: place if valid.
    {
        if (s.player.IsEmptyItemSlot(inv, btn.dragPosX, btn.dragPosY))
        {
            s.MoveItemButton(btn, btn.dragPosX, btn.dragPosY);
            EndMove();
            s.SelectInventory(btn);
            class'DXControllerDebug'.static.DebugLog(
                "DXC-NAV MOVE PLACE x=" $ string(btn.dragPosX) $ " y=" $ string(btn.dragPosY));
        }
        // else: invalid (red) — no-op; B exits, so no soft-lock.
    }
    else if (button == 201)   // B: cancel, restore original position.
    {
        s.player.PlaceItemInSlot(inv, moveOrigX, moveOrigY);
        s.SetItemButtonPos(btn, moveOrigX, moveOrigY);
        EndMove();
        s.SelectInventory(btn);
        class'DXControllerDebug'.static.DebugLog("DXC-NAV MOVE CANCEL");
    }
    // other buttons: no-op while moving.
}

// ----------------------------------------------------------------------
// EndMove — clear move-mode flags. Slot state is the caller's job (commit
// places via MoveItemButton; cancel restores via PlaceItemInSlot).
// ----------------------------------------------------------------------
function EndMove()
{
    local PersonaScreenInventory s;

    s = PersonaScreenInventory(screen);
    if (s != None)
        s.bDragging = False;
    subDialogActive = '';
}

// ----------------------------------------------------------------------
// Detach — if a move is in progress when the screen leaves (Back/Start
// close the menu without routing through B-cancel), restore the item's
// cleared footprint before the screen ref is lost. The player's invSlots
// grid persists across the menu closing, so leaving it cleared would
// corrupt the next pickup's slot search. invPos was never changed during
// the move, so PlaceItemInSlot(moveOrig…) refills exactly the right cells.
// ----------------------------------------------------------------------
function Detach()
{
    local PersonaScreenInventory s;
    local Inventory inv;

    if (subDialogActive == 'Move')
    {
        s = PersonaScreenInventory(screen);
        if (s != None && focused != None)
        {
            inv = Inventory(focused.GetClientObject());
            if (inv != None)
                s.player.PlaceItemInSlot(inv, moveOrigX, moveOrigY);
            s.bDragging = False;
        }
        subDialogActive = '';
    }
    Super.Detach();
}

// Context-dependent legend: the inventory screen rebinds A/B while a
// sub-dialog is active, and BuildHints runs every frame, so it just
// branches on subDialogActive.
function BuildHints()
{
    local PersonaScreenInventory s;
    local Inventory inv;
    local DeusExPickup pk;
    local string aLabel;

    if (subDialogActive == 'ModApply')
    {
        AddHint("a", "Apply mod");
        AddHint("b", "Cancel");
        return;
    }
    if (subDialogActive == 'Move')
    {
        AddHint("a", "Place");
        AddHint("b", "Cancel");
        return;
    }
    if (subDialogActive == 'WheelAssign')
    {
        AddHint("a", "Assign");
        AddHint("b", "Cancel");
        return;
    }

    // Label A with the exact action it will perform on the focused
    // item — derived from the same decision HandleActivate makes, so
    // the hint can never disagree with the action. Drop the hint
    // entirely when nothing is actionable rather than advertise a
    // dead button.
    s = PersonaScreenInventory(screen);
    aLabel = "";
    if (s != None && s.selectedItem != None)
    {
        inv = Inventory(s.selectedItem.GetClientObject());
        pk = DeusExPickup(inv);

        if (WeaponMod(inv) != None)                 // matches the ModApply short-circuit
            aLabel = "Apply mod";
        else if (((pk != None && pk.bActivatable && pk.bCanHaveMultipleCopies)
                  || ChargedPickup(inv) != None)
                 && s.btnUse != None && s.btnUse.bIsSensitive)
            aLabel = "Use";
        else if (s.btnEquip != None && s.btnEquip.bIsSensitive)
        {
            if (inv == s.player.inHand || inv == s.player.inHandPending)
                aLabel = "Unequip";
            else
                aLabel = "Equip";
        }
        else if (s.btnUse != None && s.btnUse.bIsSensitive)
            aLabel = "Use";
    }
    if (aLabel != "")
        AddHint("a", aLabel);

    AddHint("x", "Assign slot");
    AddHint("y", "Move");
    if (s != None && s.btnChangeAmmo != None && s.btnChangeAmmo.bIsSensitive)
        AddHint("ls", "Change ammo");
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
