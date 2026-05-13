//=============================================================================
// ControllerPlayer — DeusExPlayer subclass.
//
// Adds the TogglePlayerMenuWindow and ToggleScopeOrLaser exec functions
// used by the controller binding snippet, and remembers which persona
// screen was last open so a subsequent F1-toggle re-opens it.
//
// Engine-routed via ControllerGameInfo.DefaultPlayerClass (see Task 4).
//=============================================================================
class ControllerPlayer extends DeusExPlayer;

// Travel-scoped so it survives map transitions. DeusExPlayer is destroyed
// and re-spawned on level change; travel vars are copied across. Without
// `travel`, every map change would reset this to None and Back would
// always reopen Inventory rather than the user's last screen.
var travel Class<PersonaScreenBaseWindow> LastPersonaScreen;

// Subsequent tasks add ToggleScopeOrLaser, FindTopPersonaScreen,
// TogglePlayerMenuWindow.

// Routing-sanity log; removed in this task's Step 5.
function PostBeginPlay()
{
    Super.PostBeginPlay();
    log("ControllerPlayer.PostBeginPlay — routing OK");
}
