//=============================================================================
// AugsNavController — augmentation slot grid + Upgrade activation.
//
// Spatial nearest-neighbor for D-pad on the body silhouette, no wrap.
// A toggles the focused aug (via btnActivate). X upgrades (via btnUpgrade).
// R-stick Y scrolls the aug-description panel (winInfo).
//
// Slot buttons: PersonaScreenAugmentations.augItems[12] (fixed-size array,
// populated from index 0 upward, trailing entries are None).
// Buttons are direct winClient children; positions come from ConvertCoordinates.
//
// SelectAugmentation on each focus update drives the vanilla selected-
// state highlight on the focused aug slot (PersonaAugmentationItemButton,
// via PersonaItemButton.bSelected → DrawWindow's selection border). The
// MenuFocusOverlay frame is suppressed by the base GetFocusedRect because
// PersonaAugmentationItemButton is in HasStockFocusCue — one indicator,
// not two.
//=============================================================================
class AugsNavController extends MenuNavController;

// Accumulator for R-stick smooth scroll of the aug-description panel
// (winInfo). Same pattern as InvNavController / GoalsNavController.
const ScrollDeadzone  = 10.0;    // raw axis units; ignore small stick deflections
const ScrollThreshold = 500.0;   // accumulated units before one MoveThumb step

var float scrollAccum;

// ---- InitFocus -------------------------------------------------------------

function InitFocus()
{
    local PersonaScreenAugmentations s;
    local PersonaAugmentationItemButton btn;
    local int i;

    scrollAccum = 0.0;
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

// ----------------------------------------------------------------------
// HandleScroll — R-stick Y scrolls the aug-description panel (winInfo).
//
// winInfo.winScroll is the PersonaScrollAreaWindow wrapping the
// description text (declared on PersonaInfoWindow). Positive ry = stick
// pushed up = scroll content up = StepUp. Scrolls regardless of which
// aug slot is focused — R-stick has no other role on this screen.
// ----------------------------------------------------------------------

function bool HandleScroll(float ry)
{
    local PersonaScreenAugmentations s;

    s = PersonaScreenAugmentations(screen);
    if (s == None || s.winInfo == None || s.winInfo.winScroll == None)
        return false;

    if (Abs(ry) < ScrollDeadzone)
    {
        scrollAccum = 0.0;
        return false;
    }

    scrollAccum += ry;

    if (Abs(scrollAccum) < ScrollThreshold)
        return true;

    if (s.winInfo.winScroll.vScale == None)
    {
        scrollAccum = 0.0;
        return false;
    }

    if (scrollAccum > 0.0)
        s.winInfo.winScroll.vScale.MoveThumb(MOVETHUMB_StepUp);
    else
        s.winInfo.winScroll.vScale.MoveThumb(MOVETHUMB_StepDown);

    scrollAccum = 0.0;
    return true;
}

function BuildHints()
{
    AddHint("a", "Toggle");
    AddHint("x", "Upgrade");
    AddHint("rs", "Scroll info");
    AddHint("lb", "Prev tab");
    AddHint("rb", "Next tab");
    AddHint("b", "Close");
}

defaultproperties
{
    bAllowRepeat=False
}
