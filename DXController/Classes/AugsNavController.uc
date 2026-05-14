//=============================================================================
// AugsNavController — augmentation slot grid + Upgrade activation.
//
// Spatial nearest-neighbor for D-pad on the body silhouette, no wrap.
// A toggles the focused aug (via btnActivate). X upgrades (via btnUpgrade).
//
// Slot buttons: PersonaScreenAugmentations.augItems[12] (fixed-size array,
// populated from index 0 upward, trailing entries are None).
// Buttons are direct winClient children; positions come from ConvertCoordinates.
//=============================================================================
class AugsNavController extends MenuNavController;

// ---- InitFocus -------------------------------------------------------------

function InitFocus()
{
    local PersonaScreenAugmentations s;
    local PersonaAugmentationItemButton btn;
    local int i;

    s = PersonaScreenAugmentations(screen);
    if (s == None)
        return;

    for (i = 0; i < arrayCount(s.augItems); i++)
    {
        btn = s.augItems[i];
        if (btn != None)
        {
            focused = btn;
            s.SelectAugmentation(btn);
            return;
        }
    }
}

// ---- D-pad navigation (spatial nearest-neighbor, no wrap) ------------------

function bool HandleDPad(int dx, int dy)
{
    local PersonaScreenAugmentations s;
    local Window root;
    local PersonaAugmentationItemButton btn, bestBtn;
    local float fx, fy, cx, cy, bx, by;
    local float distance, bestDist;
    local bool bSkip;
    local int i;

    s = PersonaScreenAugmentations(screen);
    if (s == None || focused == None)
        return true;

    root = focused.GetRootWindow();

    // Compute focused center in root coords.
    focused.ConvertCoordinates(focused, 0, 0, root, fx, fy);
    fx = fx + focused.width  * 0.5;
    fy = fy + focused.height * 0.5;

    bestDist = 100000000.0;
    bestBtn = None;

    for (i = 0; i < arrayCount(s.augItems); i++)
    {
        btn = s.augItems[i];
        bSkip = false;
        if (btn != None && btn != PersonaAugmentationItemButton(focused))
        {
            btn.ConvertCoordinates(btn, 0, 0, root, bx, by);
            cx = bx + btn.width  * 0.5;
            cy = by + btn.height * 0.5;

            // Filter to the requested half-plane.
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
                    bestBtn = btn;
                }
            }
        }
    }

    if (bestBtn != None)
    {
        focused = bestBtn;
        s.SelectAugmentation(bestBtn);
        class'DXControllerDebug'.static.DebugLog("DXC-NAV FOCUS aug=" $ string(bestBtn));
    }
    return true;
}

// ---- Button activations ----------------------------------------------------

function bool HandleActivate(byte button)
{
    local PersonaScreenAugmentations s;

    s = PersonaScreenAugmentations(screen);
    if (s == None)
        return true;

    if (button == 200)   // A: toggle focused aug via btnActivate.
    {
        if (s.btnActivate != None && s.btnActivate.bIsSensitive)
            s.btnActivate.PressButton();
        return true;
    }

    if (button == 202)   // X: upgrade via btnUpgrade.
    {
        if (s.btnUpgrade != None && s.btnUpgrade.bIsSensitive)
            s.btnUpgrade.PressButton();
        return true;
    }

    return true;
}

defaultproperties
{
    bAllowRepeat=False
}
