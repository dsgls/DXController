//=============================================================================
// InvNavController — Inventory grid navigation + per-button activations.
//
// Focus model: variable-size PersonaInventoryItemButtons in winItems treated
// as single navigable units. D-pad picks the nearest item in the requested
// direction by button-center geometry. If no item exists in that direction,
// wrap to the opposite edge of the grid.
//
// Activations:
//   A (Joy1/200)          — Equip if enabled, else Use if enabled
//   X (Joy3/202)          — open belt-assign wheel sub-dialog
//   Y (Joy4/203)          — change ammo on selected weapon
//   R-stick click (Joy10/209) — drop selected item
//=============================================================================
class InvNavController extends MenuNavController;

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

    s = PersonaScreenInventory(screen);
    if (s == None)
        return true;

    if (button == 200)        // IK_Joy1 (A): Equip if enabled, else Use.
    {
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

defaultproperties
{
    bAllowRepeat=False    // grid nav: single-press only
}
