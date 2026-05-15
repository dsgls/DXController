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

function bool HandleActivate(byte button)
{
    local NetworkTerminal nt;
    local Window winComp;

    // Phase 1 skeleton: only B is wired. Pane cycling (Joy5/Joy6) and
    // A delegation to active sub arrive in Tasks 13 and 6 respectively.
    if (button != 201)   // 201 = IK_Joy2 (B)
        return true;

    nt = NetworkTerminal(screen);
    if (nt == None)
        return true;

    winComp = nt.winComputer;
    if (winComp != None)
    {
        // Computer pane: synthesize Escape into winComputer.
        // Vanilla ComputerUIWindow.VirtualKeyPressed handles IK_Escape
        // by calling CloseScreen(escapeAction) — each screen's
        // escapeAction determines whether this exits the terminal
        // (EXIT) or routes through the terminal's LOGOUT path.
        class'DXControllerDebug'.static.DebugLog(
            "DXC-TERM B-ESCAPE screen=" $ string(winComp.Class));
        winComp.VirtualKeyPressed(IK_Escape, false);
    }
    return true;
}

defaultproperties
{
    bAllowRepeat=True
}
