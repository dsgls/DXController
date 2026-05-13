//=============================================================================
// ControllerConsole — engine Console subclass.
//
// Hosts the gamepad-specific exec functions and synthesises trigger
// press/release from the IK_JoyZ/IK_JoyR axis stream. Engine-routed via
// [Engine.Engine] Console=DXController.ControllerConsole in DeusEx.ini.
//
// Trigger handling. LT/RT arrive as `IST_Axis` events; we threshold-cross
// to "held" / "released" and dispatch directly to the pawn — the
// binding-synthesis path tried in phase 1 didn't reach `Bindings[]`. RT
// becomes Fire (sets `bFire=1` and calls `Fire(0)` to mimic
// `Button bFire | Fire`); LT becomes a `ToggleScopeOrLaser` call. A Tick
// staleness timeout forces a release if the shim stops sending axis
// events while we still think the trigger is held — the shim applies a
// deadzone, so a release event with value=0 never arrives.
//
// Why no continuous-action gamepad bindings (lean / crouch) live here:
// the shim auto-fires an `IST_Release` immediately after every
// `IST_Press` for Joy* buttons regardless of physical hold state (see
// CLAUDE.md "Joy button event quirk"). Combined with `PreProcess` being
// stubbed (kills `Button bDuck` / `Axis aExtra0 Speed=…` aliases), there
// is no reliable way from script alone to detect "is the button still
// physically held." Lean and crouch via gamepad are out of scope for
// this phase; use the keyboard aliases (Q/E/X by default) for those.
//
// Execs (reachable from the binding system regardless of player class —
// Console is in the exec dispatch chain via stock Talk/Type/ViewUp
// precedent):
//   TogglePlayerMenuWindow — Joy7 (Back). Delegates to the root window
//     where the LastPersonaScreen state lives.
//   ToggleScopeOrLaser    — also called by LT-press synthesis.
//=============================================================================
class ControllerConsole extends Console;

// Trigger held above this fraction of full-scale. -1..1 or -1000..1000
// scales both work as long as the value clears the shim deadzone.
const TriggerThreshold = 0.3;

// If we don't see a trigger axis event for this many seconds while
// holding, assume the user released past the shim deadzone.
const TriggerStaleSeconds = 0.05;

var bool bLeftTriggerHeld;
var bool bRightTriggerHeld;
var float LeftTriggerStaleAge;
var float RightTriggerStaleAge;

event bool KeyEvent(EInputKey Key, EInputAction Action, FLOAT Delta)
{
    if (Action == IST_Axis)
    {
        if (Key == IK_JoyZ)
        {
            HandleLeftTrigger(Delta);
            return false;
        }
        if (Key == IK_JoyR)
        {
            HandleRightTrigger(Delta);
            return false;
        }
    }

    return Super.KeyEvent(Key, Action, Delta);
}

event Tick(float Delta)
{
    local PlayerPawn p;

    Super.Tick(Delta);

    p = GetPawn();

    if (bLeftTriggerHeld)
    {
        LeftTriggerStaleAge += Delta;
        if (LeftTriggerStaleAge > TriggerStaleSeconds)
            bLeftTriggerHeld = false;
        // LT is a press-only toggle — nothing to undo on release.
    }
    if (bRightTriggerHeld)
    {
        RightTriggerStaleAge += Delta;
        if (RightTriggerStaleAge > TriggerStaleSeconds)
        {
            bRightTriggerHeld = false;
            if (p != None)
                p.bFire = 0;
        }
    }
}

function HandleLeftTrigger(float value)
{
    local bool nowHeld;

    LeftTriggerStaleAge = 0.0;

    nowHeld = (value >= TriggerThreshold);
    if (nowHeld == bLeftTriggerHeld)
        return;
    bLeftTriggerHeld = nowHeld;
    if (nowHeld)
        ToggleScopeOrLaser();
}

function HandleRightTrigger(float value)
{
    local bool nowHeld;
    local PlayerPawn p;

    RightTriggerStaleAge = 0.0;

    nowHeld = (value >= TriggerThreshold);
    if (nowHeld == bRightTriggerHeld)
        return;
    bRightTriggerHeld = nowHeld;

    p = GetPawn();
    if (p == None)
        return;
    if (nowHeld)
    {
        // Mirror "Button bFire | Fire" — held-fire bit + initial Fire kick.
        p.bFire = 1;
        p.Fire(0.0);
    }
    else
    {
        p.bFire = 0;
    }
}

function PlayerPawn GetPawn()
{
    if (Viewport == None)
        return None;
    return Viewport.Actor;
}

// Back-button binding target (Joy7=TogglePlayerMenuWindow). Delegates to
// the root window, which owns the LastPersonaScreen state and the actual
// open/close logic. Reachable from the binding system because Console is
// in the exec dispatch chain regardless of which player class spawned
// (stock Console exposes Talk / Type / ViewUp / TimeDemo execs the same way).
exec function TogglePlayerMenuWindow()
{
    local PlayerPawn p;
    local ControllerRootWindow root;

    p = GetPawn();
    if (p == None)
        return;
    root = ControllerRootWindow(PlayerPawnExt(p).rootWindow);
    if (root == None)
        return;
    root.TogglePlayerMenuWindow();
}

// LT-trigger action and an explicit bindable name for users who'd rather
// have scope toggle on a button. Toggles scope if the equipped weapon
// has one, else laser if it has one, else no-op. Field/method names
// confirmed against ../deusex-scripts/DeusEx/Classes/DeusExWeapon.uc
// (bHasScope L70, bHasLaser L76, ScopeToggle L1342, LaserToggle L1411).
exec function ToggleScopeOrLaser()
{
    local PlayerPawn p;
    local DeusExWeapon w;

    p = GetPawn();
    if (p == None)
        return;
    w = DeusExWeapon(p.Weapon);
    if (w == None)
        return;

    if (w.bHasScope)
        w.ScopeToggle();
    else if (w.bHasLaser)
        w.LaserToggle();
}

event NotifyLevelChange()
{
    bLeftTriggerHeld = false;
    bRightTriggerHeld = false;
    LeftTriggerStaleAge = 0.0;
    RightTriggerStaleAge = 0.0;
    Super.NotifyLevelChange();
}
