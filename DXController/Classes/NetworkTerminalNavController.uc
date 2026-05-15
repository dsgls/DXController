//=============================================================================
// NetworkTerminalNavController — gamepad nav dispatcher for in-world
// network terminals (Personal, Public, ATM, Security shell).
//
// Phase 1 scope: Computer pane (whichever ComputerScreenX is current,
// dispatched to a per-class ComputerScreenNavSub), plus inline handling
// for the winHack and winHackAccounts overlay panes when present. The
// Security-screen-specific sub-controller is Phase 2 — until then the
// unknown-screen fallback (consumed no-op) applies on Security terminals.
//
// AllowsMenuToggle=false: Start/Back can't open the persona menu while
// a terminal is foreground. B routes to HandleActivate (Computer pane:
// synthesize IK_Escape on winTerm.winComputer; Hack/HackAccounts: pane
// back to Computer — added in Task 13).
//
// One controller class, registered against five terminal subclasses
// (NetworkTerminal itself is abstract; registered for defensive
// completeness only — the four concrete subclasses are what get pushed).
//
// See docs/superpowers/specs/2026-05-15-network-terminal-nav-phase1-design.md
//=============================================================================
class NetworkTerminalNavController extends MenuNavController;

// ---- Sub-controller registry -----------------------------------------------
//
// Keyed by ComputerScreenX class via parallel arrays. Populated in
// defaultproperties. Each entry is lazy-instantiated on first encounter
// in LookupOrCreateSub and cached for the dispatcher's lifetime.
//
// Size 16: 8 concrete ComputerScreen classes in scope this phase
// (Login, ATMLogin/Withdraw/Disabled, Bulletins, Email, SpecialOptions
// — and Security in Phase 2) + headroom.
var Class<ComputerUIWindow>     subKeys[16];
var Class<ComputerScreenNavSub> subClasses[16];
var ComputerScreenNavSub        subInstances[16];

// ---- Active-sub state ------------------------------------------------------
var ComputerScreenNavSub activeSub;       // sub for the current Computer-pane screen
var ComputerUIWindow     lastWinComputer; // identity check for Tick-based screen-swap detection

// ---- Pane model ------------------------------------------------------------
//
// A terminal session can have up to three coexisting focusable regions:
//   Computer     — always present (winTerm.winComputer)
//   Hack         — winTerm.winHack       (present when player can hack)
//   HackAccounts — winTerm.winHackAccounts (post-hack on multi-user email)
//
// LB cycles previous, RB cycles next, skipping absent panes.
const PANE_COMPUTER     = 0;
const PANE_HACK         = 1;
const PANE_HACKACCOUNTS = 2;

var int activePane;

// Inline pane state — set in Task 14/15. Declared here so vars stay
// before any function bodies per UE1 strict ordering.
var Window paneHackFocused;          // points at winHack.btnHack
var Window paneAccountsFocused;      // lstAccounts or btnChangeAccount
var int    paneAccountsRowKind;      // 0 = list, 1 = btnChangeAccount

// ---- Lifecycle -------------------------------------------------------------

function Attach(Window s)
{
    Super.Attach(s);
    activePane = PANE_COMPUTER;
    paneHackFocused = None;
    paneAccountsFocused = None;
    paneAccountsRowKind = 0;
    class'DXControllerDebug'.static.DebugLog(
        "DXC-TERM ATTACH terminal=" $ string(s.Class));
}

function Detach()
{
    if (screen != None)
        class'DXControllerDebug'.static.DebugLog(
            "DXC-TERM DETACH terminal=" $ string(screen.Class));

    if (activeSub != None)
    {
        activeSub.OnLeave();
        activeSub = None;
    }
    lastWinComputer = None;

    Super.Detach();
}

// ---- B / Start / Back routing ---------------------------------------------

// Block Start/Back from opening the persona menu over a terminal, and
// route B to HandleActivate (where the dispatcher decides pane-back vs
// Escape synthesis).
function bool AllowsMenuToggle()
{
    return false;
}

// ---- NavTick: screen-swap detection + sub lifecycle ------------------------

function NavTick(float deltaSeconds)
{
    local NetworkTerminal nt;
    local ComputerUIWindow newWinComp;
    local Class<ComputerUIWindow> oldClass, newClass;

    nt = NetworkTerminal(screen);
    if (nt == None)
        return;

    // Pane availability check + auto-fallback. If the active pane's
    // owning window vanishes mid-session (Hack pressed → winHack.Destroy,
    // or HackAccounts torn down on Email screen-swap), revert to
    // Computer. Focus state on Computer survives across these transitions.
    if (activePane != PANE_COMPUTER && !IsPanePresent(activePane))
    {
        class'DXControllerDebug'.static.DebugLog(
            "DXC-TERM PANE-AUTO-FALLBACK pane=" $ string(activePane));
        activePane = PANE_COMPUTER;
    }

    newWinComp = nt.winComputer;

    if (newWinComp != lastWinComputer)
    {
        if (lastWinComputer != None)
            oldClass = lastWinComputer.Class;
        if (newWinComp != None)
            newClass = newWinComp.Class;

        class'DXControllerDebug'.static.DebugLog(
            "DXC-TERM SCREEN-SWAP from=" $ string(oldClass)
            $ " to=" $ string(newClass));

        if (activeSub != None)
            activeSub.OnLeave();

        lastWinComputer = newWinComp;
        if (newWinComp != None)
        {
            activeSub = LookupOrCreateSub(newWinComp.Class);
            if (activeSub != None)
                activeSub.OnEnter(newWinComp);
        }
        else
        {
            activeSub = None;
        }
    }

    // Deferred-init retry. Some screens populate action-bar children
    // inside SetNetworkTerminal AFTER NewChild fires, so OnEnter may
    // run before the children exist. Retry while activeSub has no
    // focused element.
    if (activeSub != None && activeSub.focused == None && newWinComp != None)
        activeSub.OnEnter(newWinComp);

    if (activeSub != None)
        activeSub.OnTick();
}

// ---- Sub-controller registry helpers ---------------------------------------

function int FindSubIndex(Class<ComputerUIWindow> screenClass)
{
    local int i;
    if (screenClass == None)
        return -1;
    for (i = 0; i < ArrayCount(subKeys); i++)
    {
        if (subKeys[i] == screenClass)
            return i;
    }
    return -1;
}

function ComputerScreenNavSub LookupOrCreateSub(Class<ComputerUIWindow> screenClass)
{
    local int idx;

    idx = FindSubIndex(screenClass);
    if (idx < 0)
        return None;
    if (subInstances[idx] == None && subClasses[idx] != None)
        subInstances[idx] = new(None) subClasses[idx];
    return subInstances[idx];
}

// ---- Pane availability & cycling -------------------------------------------

function bool IsPanePresent(int pane)
{
    local NetworkTerminal nt;

    nt = NetworkTerminal(screen);
    if (nt == None)
        return false;

    if (pane == PANE_COMPUTER)
        return nt.winComputer != None;
    if (pane == PANE_HACK)
        return nt.winHack != None;
    if (pane == PANE_HACKACCOUNTS)
        return nt.winHackAccounts != None;
    return false;
}

function int CyclePane(int from, int direction)
{
    local int cur, i;
    cur = from;
    for (i = 0; i < 3; i++)
    {
        cur = (cur + direction + 3) % 3;
        if (IsPanePresent(cur))
            return cur;
    }
    return PANE_COMPUTER;  // fallback (Computer always present)
}

function SwitchPane(int newPane)
{
    local NetworkTerminal nt;
    local int oldPane;
    if (newPane == activePane)
        return;
    oldPane = activePane;
    activePane = newPane;

    nt = NetworkTerminal(screen);
    if (newPane == PANE_HACK && nt != None && nt.winHack != None)
    {
        paneHackFocused = nt.winHack.btnHack;
        nt.winHack.SetFocusWindow(paneHackFocused);
    }
    else if (newPane == PANE_HACKACCOUNTS && nt != None && nt.winHackAccounts != None)
    {
        // Vanilla SetCompOwner already selects the current-user row;
        // anchor gamepad focus on the list (the list itself is the
        // tab-stop; the per-row highlight is intra-list).
        paneAccountsFocused = nt.winHackAccounts.lstAccounts;
        paneAccountsRowKind = 0;  // list
    }

    class'DXControllerDebug'.static.DebugLog(
        "DXC-TERM PANE-SWITCH from=" $ string(oldPane) $ " to=" $ string(newPane));
}

// ---- D-pad delegation ------------------------------------------------------

function bool HandleDPad(int dx, int dy)
{
    if (activePane == PANE_COMPUTER)
    {
        if (activeSub != None)
            return activeSub.HandleDPad(dx, dy);
        return true;
    }
    if (activePane == PANE_HACK)
    {
        // Single-button pane (btnHack). D-pad consumed no-op.
        return true;
    }
    if (activePane == PANE_HACKACCOUNTS)
    {
        return HandleHackAccountsDPad(dx, dy);
    }
    return true;
}

function bool HandleHackAccountsDPad(int dx, int dy)
{
    local NetworkTerminal nt;
    local ComputerScreenHackAccounts ha;
    local int prevRowId, newRowId;

    nt = NetworkTerminal(screen);
    if (nt == None || nt.winHackAccounts == None)
        return true;
    ha = nt.winHackAccounts;

    if (dy == 0)
        return true;  // single-column list, single-button row — L/R no-op

    if (paneAccountsRowKind == 0 && ha.lstAccounts != None)
    {
        prevRowId = ha.lstAccounts.GetFocusRow();
        if (dy > 0)
            ha.lstAccounts.MoveRow(MOVELIST_Down, True, True);
        else
            ha.lstAccounts.MoveRow(MOVELIST_Up, True, True);
        newRowId = ha.lstAccounts.GetFocusRow();
        if (newRowId == prevRowId)
        {
            if (dy > 0)
            {
                // At bottom edge — advance to btnChangeAccount.
                paneAccountsRowKind = 1;
                paneAccountsFocused = ha.btnChangeAccount;
            }
            else
            {
                // At top edge — wrap up to btnChangeAccount.
                paneAccountsRowKind = 1;
                paneAccountsFocused = ha.btnChangeAccount;
            }
        }
        return true;
    }

    if (paneAccountsRowKind == 1)
    {
        // Both wrap directions go to the list.
        paneAccountsRowKind = 0;
        paneAccountsFocused = ha.lstAccounts;
        return true;
    }
    return true;
}

function bool HandleHackAccountsActivate(byte button)
{
    local NetworkTerminal nt;
    local ComputerScreenHackAccounts ha;

    if (button != 200)
        return true;

    nt = NetworkTerminal(screen);
    if (nt == None || nt.winHackAccounts == None)
        return true;
    ha = nt.winHackAccounts;

    if (paneAccountsRowKind == 0)
    {
        // A on list row: explicit activation — vanilla's
        // ListRowActivated wires ChangeSelectedAccount.
        ha.ChangeSelectedAccount();
        class'DXControllerDebug'.static.DebugLog("DXC-TERM HACKACCOUNTS-LIST-ACTIVATE");
    }
    else if (paneAccountsRowKind == 1 && ha.btnChangeAccount != None && ha.btnChangeAccount.bIsSensitive)
    {
        // A on btnChangeAccount: PressButton → ButtonActivated →
        // ChangeSelectedAccount (vanilla).
        ha.btnChangeAccount.PressButton();
        class'DXControllerDebug'.static.DebugLog("DXC-TERM HACKACCOUNTS-BTN-ACTIVATE");
    }
    return true;
}

function bool HandleActivate(byte button)
{
    local NetworkTerminal nt;
    local Window winComp;

    // B (201). Pane-aware:
    //   - non-Computer pane: step back to Computer.
    //   - Computer pane:     synthesize Escape into winComputer.
    if (button == 201)
    {
        if (activePane != PANE_COMPUTER)
        {
            SwitchPane(PANE_COMPUTER);
            return true;
        }
        nt = NetworkTerminal(screen);
        if (nt == None)
            return true;
        winComp = nt.winComputer;
        if (winComp != None)
        {
            class'DXControllerDebug'.static.DebugLog(
                "DXC-TERM B-ESCAPE screen=" $ string(winComp.Class));
            winComp.VirtualKeyPressed(IK_Escape, false);
        }
        return true;
    }

    // LB (204) = previous pane, RB (205) = next pane. Skips absent panes.
    if (button == 204)
    {
        SwitchPane(CyclePane(activePane, -1));
        return true;
    }
    if (button == 205)
    {
        SwitchPane(CyclePane(activePane, +1));
        return true;
    }

    // A/X/Y/R-stick-click: dispatch by active pane. Stubs for
    // Hack/HackAccounts panes — Tasks 14 and 15 add real handlers.
    if (activePane == PANE_COMPUTER)
    {
        if (activeSub != None)
            return activeSub.HandleActivate(button);
        return true;
    }
    if (activePane == PANE_HACK)
    {
        if (button == 200    // A
            && paneHackFocused != None
            && paneHackFocused.bIsSensitive
            && PersonaActionButtonWindow(paneHackFocused) != None)
        {
            class'DXControllerDebug'.static.DebugLog(
                "DXC-TERM HACK-PRESS label=" $ PersonaActionButtonWindow(paneHackFocused).buttonText);
            PersonaActionButtonWindow(paneHackFocused).PressButton();
        }
        return true;  // D-pad / X / Y / R-stick all consumed
    }
    if (activePane == PANE_HACKACCOUNTS)
    {
        return HandleHackAccountsActivate(button);
    }
    return true;
}

defaultproperties
{
    bAllowRepeat=True

    subKeys(0)=Class'DeusEx.ComputerScreenLogin'
    subClasses(0)=Class'DXController.ComputerScreenLoginNav'

    subKeys(1)=Class'DeusEx.ComputerScreenATM'
    subClasses(1)=Class'DXController.ComputerScreenATMLoginNav'

    subKeys(2)=Class'DeusEx.ComputerScreenATMWithdraw'
    subClasses(2)=Class'DXController.ComputerScreenATMWithdrawNav'

    subKeys(3)=Class'DeusEx.ComputerScreenATMDisabled'
    subClasses(3)=Class'DXController.ComputerScreenATMDisabledNav'

    subKeys(4)=Class'DeusEx.ComputerScreenBulletins'
    subClasses(4)=Class'DXController.ComputerScreenBulletinsNav'

    subKeys(5)=Class'DeusEx.ComputerScreenEmail'
    subClasses(5)=Class'DXController.ComputerScreenEmailNav'

    subKeys(6)=Class'DeusEx.ComputerScreenSpecialOptions'
    subClasses(6)=Class'DXController.ComputerScreenSpecialOptionsNav'
}
