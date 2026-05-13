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

// Subsequent tasks add ToggleScopeOrLaser, FindTopPersonaScreen,
// TogglePlayerMenuWindow.
