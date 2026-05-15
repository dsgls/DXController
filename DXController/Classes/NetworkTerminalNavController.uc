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

// ---- Lifecycle -------------------------------------------------------------

function Attach(Window s)
{
    Super.Attach(s);
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

    // Pane availability check + auto-fallback (Hack/HackAccounts) and
    // pane-2/3 cycling arrive in Task 13. Phase 1 Tick handles only the
    // Computer-pane sub-controller lifecycle.

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

// ---- D-pad delegation ------------------------------------------------------

function bool HandleDPad(int dx, int dy)
{
    // Phase 1: only the Computer pane is active. Pane-cycling (Task 13)
    // will dispatch to Hack / HackAccounts inline handlers based on
    // activePane.
    if (activeSub != None)
        return activeSub.HandleDPad(dx, dy);
    return true;  // unknown-screen fallback: consume so D-pad doesn't fall through
}

function bool HandleActivate(byte button)
{
    local NetworkTerminal nt;
    local Window winComp;

    // B (201): Computer-pane Escape synthesis. Pane-back routing for
    // Hack/HackAccounts arrives in Task 13.
    if (button == 201)
    {
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

    // LB/RB (204/205): pane cycling. Stubbed in Phase 1 skeleton —
    // consume so they don't fall through; real cycling lands in Task 13.
    if (button == 204 || button == 205)
        return true;

    // A/X/Y/R-stick-click: delegate to the active Computer-pane sub.
    if (activeSub != None)
    {
        class'DXControllerDebug'.static.DebugLog(
            "DXC-TERM SUB-ACTIVATE screen=" $ string(activeSub.screen.Class)
            $ " button=" $ string(button));
        return activeSub.HandleActivate(button);
    }

    // Unknown screen fallback: consume so A/X/Y don't fall through.
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
