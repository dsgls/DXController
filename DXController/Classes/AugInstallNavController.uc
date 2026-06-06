//=============================================================================
// AugInstallNavController — MedBot aug installation screen navigation.
//
// The MedBot aug-install screen (HUDMedBotAddAugsScreen) shows a scrolling
// list of available aug cannisters, each row (HUDMedBotAugCanWindow) holding
// two HUDMedBotAugItemButton slots — col 0 = btnAug1 (left), col 1 = btnAug2
// (right) — for the two mutually-exclusive augs in that cannister.
// Navigation:
//
//   D-pad up/down : move row, preserve column. Each focus change calls
//                   SelectAugmentation, so the focused canister is always
//                   the one Install would commit. Wraps within rowCount.
//   D-pad left/right : switch column (left = col 0, right = col 1) within
//                   the current row. No wrap (only two slots per row).
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

// Per-row left/right slots. Each HUDMedBotAugCanWindow always populates
// both btnAug1 and btnAug2 (HUDMedBotAugCanWindow.SetCan fills them with
// augCan.GetAugmentation(0) and GetAugmentation(1)), so col 1 is reliably
// present whenever col 0 is. 16 rows covers a typical run (canister count
// caps well below).
var HUDMedBotAugItemButton augRow1[16];     // col 0 — left
var HUDMedBotAugItemButton augRow2[16];     // col 1 — right
var int                    rowCount;

// (row, col) of the currently-focused canister. col 0 = left (btnAug1),
// col 1 = right (btnAug2). focused mirrors ColButton(focusRow, focusCol).
var int focusRow;
var int focusCol;

// ---- Attach / InitFocus ----------------------------------------------------

function HUDMedBotAugItemButton ColButton(int row, int col)
{
    if (row < 0 || row >= rowCount)
        return None;
    if (col == 0)
        return augRow1[row];
    return augRow2[row];
}

function CollectAugButtons()
{
    local HUDMedBotAddAugsScreen s;
    local Window rowWin;
    local HUDMedBotAugCanWindow row;
    local int i;

    rowCount = 0;
    for (i = 0; i < ArrayCount(augRow1); i++)
    {
        augRow1[i] = None;
        augRow2[i] = None;
    }

    s = HUDMedBotAddAugsScreen(screen);
    if (s == None || s.winAugsTile == None)
        return;

    // Walk TileWindow children — each is a HUDMedBotAugCanWindow.
    // GetBottomChild returns the first-created (visually topmost) child;
    // GetHigherSibling walks toward later-created rows.  This matches the
    // visual top-to-bottom order of the cannister list.
    rowWin = s.winAugsTile.GetBottomChild();
    while (rowWin != None && rowCount < ArrayCount(augRow1))
    {
        row = HUDMedBotAugCanWindow(rowWin);
        if (row != None && row.btnAug1 != None
                && row.btnAug1.GetClientObject() != None)
        {
            augRow1[rowCount] = row.btnAug1;
            // btnAug2 is the paired slot — always present alongside btnAug1
            // for real canisters. Tolerate a missing client object defensively
            // (col 1 is then treated as empty for that row).
            if (row.btnAug2 != None && row.btnAug2.GetClientObject() != None)
                augRow2[rowCount] = row.btnAug2;
            rowCount++;
        }
        rowWin = rowWin.GetHigherSibling();
    }

    class'DXControllerDebug'.static.DebugLog(
        "DXC-NAV AugInstall collected rows=" $ string(rowCount));
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
    local HUDMedBotAugItemButton btn;

    bStale = false;
    for (i = 0; i < rowCount; i++)
    {
        if (augRow1[i] == None || augRow1[i].GetClientObject() == None)
        {
            bStale = true;
            break;
        }
        if (augRow2[i] != None && augRow2[i].GetClientObject() == None)
        {
            bStale = true;
            break;
        }
    }
    if (!bStale)
        return;

    class'DXControllerDebug'.static.DebugLog("DXC-NAV AugInstall stale-refresh");
    CollectAugButtons();

    focusRow = -1;
    focusCol = 0;
    focused  = None;
    if (rowCount > 0)
    {
        focusRow = 0;
        focusCol = 0;
        btn      = ColButton(0, 0);
        if (btn != None)
        {
            focused = btn;
            HUDMedBotAddAugsScreen(screen).SelectAugmentation(btn);
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
    local HUDMedBotAugItemButton btn;

    // screen is set by the base Attach before InitFocus is called.
    CollectAugButtons();

    focusRow = -1;
    focusCol = 0;
    focused  = None;

    if (rowCount == 0)
        return;

    focusRow = 0;
    focusCol = 0;
    btn      = ColButton(0, 0);
    if (btn != None)
    {
        focused = btn;
        // Pre-select the first button so the install screen shows info.
        HUDMedBotAddAugsScreen(screen).SelectAugmentation(btn);
        class'DXControllerDebug'.static.DebugLog(
            "DXC-NAV AugInstall focus init row=0 col=0");
    }
}

// ---- D-pad navigation ------------------------------------------------------

function bool HandleDPad(int dx, int dy)
{
    local int newRow, newCol;
    local HUDMedBotAugItemButton btn;

    RefreshIfStale();
    if (rowCount == 0)
        return true;

    if (dy != 0)
    {
        // Up/down: change row, preserve column. Wrap within rowCount.
        if (dy > 0)
            newRow = (focusRow + 1) % rowCount;
        else
            newRow = (focusRow - 1 + rowCount) % rowCount;
        newCol = focusCol;
        btn = ColButton(newRow, newCol);
        if (btn == None)
        {
            // Target column is empty in this row (defensive — pairs are
            // normally always present). Fall back to col 0.
            btn = ColButton(newRow, 0);
            if (btn != None)
                newCol = 0;
        }
    }
    else if (dx != 0)
    {
        // Left/right: pick the column directly. No wrap (only two slots).
        if (dx > 0)
            newCol = 1;
        else
            newCol = 0;
        newRow = focusRow;
        if (newCol == focusCol)
            return true;        // already on that side
        btn = ColButton(newRow, newCol);
        if (btn == None)
            return true;        // target column empty (defensive)
    }
    else
    {
        return true;
    }

    if (btn == None)
        return true;

    focusRow = newRow;
    focusCol = newCol;
    focused  = btn;
    HUDMedBotAddAugsScreen(screen).SelectAugmentation(btn);
    class'DXControllerDebug'.static.DebugLog(
        "DXC-NAV AugInstall focus row=" $ string(newRow)
            $ " col=" $ string(newCol));
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
