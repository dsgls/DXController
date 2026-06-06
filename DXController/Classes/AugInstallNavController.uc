//=============================================================================
// AugInstallNavController — MedBot aug installation screen navigation.
//
// The MedBot aug-install screen (HUDMedBotAddAugsScreen) shows a scrolling
// list of available aug cannisters, each row holding two HUDMedBotAugItemButton
// slots.  Navigation:
//
//   D-pad up/down : move focus among aug item buttons (linear, with wrap).
//                   Each focus change calls SelectAugmentation, so the
//                   focused canister is always the one Install would commit.
//   A             : press the Install button (if sensitive) to install the
//                   focused aug. Matches the heal screen, where A also
//                   commits the screen's single action.
//   B / Back      : close the screen (handled upstream by ControllerRootWindow).
//
// Button collection happens once at Attach time.  If the cannister list
// changes mid-session (edge case) the controller keeps the stale list;
// a re-attach at the next top-window change will re-collect.
//
// Selection-cue migration: HUDMedBotAugItemButton extends PersonaItemButton,
// which paints a bright colSelectionBorder when bSelected is true (and the
// subclass adds a dim unselected outline of its own). HUDMedBotAddAugsScreen
// .SelectAugmentation drives that bSelected state via SelectButton(True/False)
// on the focused/previous button, so the per-button vanilla cue is reliable.
// Every focused = … site in this controller (InitFocus, RefreshIfStale,
// HandleDPad) is paired with a SelectAugmentation call, so the cue tracks
// focus without drift. HUDMedBotAugItemButton is therefore registered in
// MenuNavController.HasStockFocusCue and the overlay frame stays off here.
//
// Edge case: HUDMedBotAddAugsScreen.SelectAugmentation bails without
// painting bSelected when the focused canister's aug is already
// installed (bHasIt) or its slot is full (bSlotFull). The
// GetFocusedRect override below catches that case and re-enables the
// overlay frame so the gamepad cursor is still visible — same shape as
// InvNavController's ModApply fix.
//=============================================================================
class AugInstallNavController extends MenuNavController;

// Flat array of all HUDMedBotAugItemButton instances on the screen.
// Populated in CollectAugButtons; max 32 covers real canisters (2 per row × up
// to ~12 cannisters in a typical run).
var HUDMedBotAugItemButton augButtons[32];
var int                    augButtonCount;

// ---- Attach / InitFocus ----------------------------------------------------

function CollectAugButtons()
{
    local HUDMedBotAddAugsScreen s;
    local Window rowWin;
    local HUDMedBotAugCanWindow row;

    augButtonCount = 0;

    s = HUDMedBotAddAugsScreen(screen);
    if (s == None || s.winAugsTile == None)
        return;

    // Walk TileWindow children — each is a HUDMedBotAugCanWindow.
    // GetBottomChild returns the first-created (visually topmost) child;
    // GetHigherSibling walks toward later-created rows.  This matches the
    // visual top-to-bottom order of the cannister list.
    rowWin = s.winAugsTile.GetBottomChild();
    while (rowWin != None && augButtonCount < ArrayCount(augButtons))
    {
        row = HUDMedBotAugCanWindow(rowWin);
        if (row != None)
        {
            // Only add a button if it carries a real augmentation reference.
            // Buttons with no client object represent empty cannister slots.
            if (row.btnAug1 != None && row.btnAug1.GetClientObject() != None)
            {
                augButtons[augButtonCount] = row.btnAug1;
                augButtonCount++;
            }
            if (augButtonCount < ArrayCount(augButtons)
                    && row.btnAug2 != None && row.btnAug2.GetClientObject() != None)
            {
                augButtons[augButtonCount] = row.btnAug2;
                augButtonCount++;
            }
        }
        rowWin = rowWin.GetHigherSibling();
    }

    class'DXControllerDebug'.static.DebugLog(
        "DXC-NAV AugInstall collected=" $ string(augButtonCount));
}

// Detect that PopulateAugCanList has rebuilt the cannister tree since the
// last CollectAugButtons (e.g. after an aug has been installed) and
// re-collect if so. UE1 nulls references to destroyed Window objects, so
// a None entry or an empty client object on a cached button indicates
// the underlying row is gone.
function RefreshIfStale()
{
    local int i;
    local bool bStale;

    bStale = false;
    for (i = 0; i < augButtonCount; i++)
    {
        if (augButtons[i] == None || augButtons[i].GetClientObject() == None)
        {
            bStale = true;
            break;
        }
    }
    if (!bStale)
        return;

    class'DXControllerDebug'.static.DebugLog("DXC-NAV AugInstall stale-refresh");
    CollectAugButtons();

    focusIndex = -1;
    focused    = None;
    for (i = 0; i < augButtonCount; i++)
    {
        if (augButtons[i] != None)
        {
            focusIndex = i;
            focused    = augButtons[i];
            HUDMedBotAddAugsScreen(screen).SelectAugmentation(augButtons[i]);
            return;
        }
    }
}

// Override the base policy when the vanilla cue isn't painted. The
// stock `HUDMedBotAddAugsScreen.SelectAugmentation` bails out without
// calling SelectButton(True) on canisters whose aug is already
// installed (bHasIt) or whose slot is full (bSlotFull). When that
// happens, `focused.bSelected` stays False — meaning the
// PersonaItemButton border isn't drawn, and the controller would have
// no visible cursor (only the dim unselected outline shared by every
// other canister). Force the overlay frame back on as the cursor
// indicator in that case. Outside this corner, fall through to the
// base policy (which suppresses the frame because
// HUDMedBotAugItemButton is in HasStockFocusCue from Task C4).
function bool GetFocusedRect(out float x, out float y, out float w, out float h)
{
    local Window root;
    local float lx, ly;
    local PersonaItemButton btn;

    if (!IsFocusedLive())
        return false;

    btn = PersonaItemButton(focused);
    if (btn != None && !btn.bSelected)
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

function InitFocus()
{
    local int i;

    // screen is set by the base Attach before InitFocus is called.
    CollectAugButtons();

    focusIndex = -1;
    focused    = None;

    for (i = 0; i < augButtonCount; i++)
    {
        if (augButtons[i] != None)
        {
            focusIndex = i;
            focused    = augButtons[i];
            // Pre-select the first button so the install screen shows info.
            HUDMedBotAddAugsScreen(screen).SelectAugmentation(augButtons[i]);
            class'DXControllerDebug'.static.DebugLog(
                "DXC-NAV AugInstall focus init idx=" $ string(i));
            return;
        }
    }
}

// ---- D-pad navigation ------------------------------------------------------

function bool HandleDPad(int dx, int dy)
{
    local int step, i, idx;

    RefreshIfStale();
    if (augButtonCount == 0 || dy == 0)
        return true;    // consume; left/right ignored on this screen

    if (dy > 0)
        step = 1;
    else
        step = -1;

    idx = focusIndex;
    for (i = 0; i < augButtonCount; i++)
    {
        idx = (idx + step + augButtonCount) % augButtonCount;
        if (augButtons[idx] != None)
        {
            focusIndex = idx;
            focused    = augButtons[idx];
            // Selecting the aug button also updates the info panel.
            HUDMedBotAddAugsScreen(screen).SelectAugmentation(augButtons[idx]);
            class'DXControllerDebug'.static.DebugLog(
                "DXC-NAV AugInstall focus idx=" $ string(idx));
            return true;
        }
    }
    return true;
}

// ---- Button activations ----------------------------------------------------

function bool HandleActivate(byte button)
{
    local HUDMedBotAddAugsScreen s;

    RefreshIfStale();
    s = HUDMedBotAddAugsScreen(screen);
    if (s == None)
        return true;

    // A (IK_Joy1 = 0xC8 = 200): install the focused aug. D-pad already
    // pre-selected it via SelectAugmentation, so btnInstall is sensitive
    // whenever the focused canister is installable.
    if (button == 200)
    {
        if (s.btnInstall != None && s.btnInstall.bIsSensitive)
        {
            s.btnInstall.PressButton();
            class'DXControllerDebug'.static.DebugLog("DXC-NAV AugInstall install");
        }
        return true;
    }

    // X (IK_Joy3 = 0xCA = 202) / Y (IK_Joy4 = 0xCB = 203) /
    // R-stick click (IK_Joy10 = 0xD1 = 209): no-op.
    return true;
}

function BuildHints()
{
    AddHint("a", "Install");
    AddHint("b", "Close");
}

defaultproperties
{
    bAllowRepeat=False
}
