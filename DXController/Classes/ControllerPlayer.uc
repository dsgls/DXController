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

// Walks from root.GetTopWindow() up the parent-owner chain looking for
// the first ancestor that IS-A PersonaScreenBaseWindow. Returns None if
// no persona screen is anywhere in the chain (i.e. menu isn't open, or
// only non-persona windows like map/save dialogs are on the stack).
//
// Why a walk rather than just GetTopWindow(): a sub-window can be pushed
// in front of an open persona screen (e.g. HUDMedBotAddAugsScreen on top
// of PersonaScreenAugmentations). winStack is private on DeusExRootWindow
// (../deusex-scripts/DeusEx/Classes/DeusExRootWindow.uc:17), so we can't
// iterate the stack from outside; the parent-owner chain is what's
// available. Window.GetParent() is native(1428) final on
// ../deusex-scripts/Extension/Classes/Window.uc:152.
function PersonaScreenBaseWindow FindTopPersonaScreen(DeusExRootWindow root)
{
    local Window w;

    if (root == None)
        return None;

    w = root.GetTopWindow();
    while (w != None)
    {
        if (PersonaScreenBaseWindow(w) != None)
            return PersonaScreenBaseWindow(w);
        w = w.GetParent();
    }
    return None;
}

// Back-button binding target. Open: closes the entire menu and records
// the last persona screen. Closed: opens the menu at LastPersonaScreen
// (defaulting to Inventory if nothing remembered yet).
//
// RestrictInput + multiplayer-inventory guards mirror ShowInventoryWindow
// (../deusex-scripts/DeusEx/Classes/DeusExPlayer.uc:6627-6638) — we bypass
// the vanilla Show*Window path by calling InvokeUIScreen directly with an
// arbitrary class, so we re-impose the same guards here. The close
// branch is unguarded — if the menu's open, the user must already be in
// a state where opening it was allowed.
exec function TogglePlayerMenuWindow()
{
    local DeusExRootWindow root;
    local PersonaScreenBaseWindow topPersona;

    root = DeusExRootWindow(rootWindow);
    if (root == None)
        return;

    topPersona = FindTopPersonaScreen(root);
    if (topPersona != None)
    {
        LastPersonaScreen = topPersona.Class;
        // ClearWindowStack matches "leave the menu entirely", which is
        // what Back means here. Vanilla uses the same call for similar
        // full-close situations (DeusExPlayer.LoadGame /
        // StartNewGame branches). PopWindow would only pop one screen,
        // leaving any sub-windows behind.
        root.ClearWindowStack();
        return;
    }

    // Open branch — re-impose Show*Window guards.
    if (RestrictInput())
        return;
    if ((Level.NetMode != NM_Standalone) && bBeltIsMPInventory)
    {
        ClientMessage("Inventory screen disabled in multiplayer");
        return;
    }

    if (LastPersonaScreen == None)
        LastPersonaScreen = Class'DeusEx.PersonaScreenInventory';

    InvokeUIScreen(LastPersonaScreen);
}
