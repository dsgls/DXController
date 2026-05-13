//=============================================================================
// ControllerPlayer — JCDentonMale subclass.
//
// Adds the TogglePlayerMenuWindow and ToggleScopeOrLaser exec functions
// used by the controller binding snippet, and remembers which persona
// screen was last open so a subsequent F1-toggle re-opens it.
//
// Extends JCDentonMale (not DeusExPlayer) because DeusExGameInfo.Login
// forces SpawnClass=JCDentonMale unless ApproveClass approves it; we keep
// the protagonist identity by inheriting from it. ControllerGameInfo
// overrides ApproveClass so this class actually spawns.
//
// Engine-routed via ControllerGameInfo.DefaultPlayerClass (see Task 4).
//=============================================================================
class ControllerPlayer extends JCDentonMale;

// Travel-scoped so it survives map transitions. The player is destroyed
// and re-spawned on level change; travel vars are copied across. Without
// `travel`, every map change would reset this to None and Back would
// always reopen Inventory rather than the user's last screen.
var travel Class<PersonaScreenBaseWindow> LastPersonaScreen;

// LT (Joy16) binding target. Toggles scope if the equipped weapon has
// one, else laser if it has one, else no-op. Field/method names confirmed
// against ../deusex-scripts/DeusEx/Classes/DeusExWeapon.uc (bHasScope L70,
// bHasLaser L76, ScopeToggle L1342, LaserToggle L1411).
exec function ToggleScopeOrLaser()
{
    local DeusExWeapon w;

    w = DeusExWeapon(Weapon);
    if (w == None)
        return;

    if (w.bHasScope)
        w.ScopeToggle();
    else if (w.bHasLaser)
        w.LaserToggle();
}

// Subsequent tasks add FindTopPersonaScreen, TogglePlayerMenuWindow.
