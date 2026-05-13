//=============================================================================
// ControllerRootWindow — DeusExRootWindow subclass.
//
// Intercepts gamepad key events when a persona screen is on top:
//   IK_Joy5 (LB)  -> previous persona tab
//   IK_Joy6 (RB)  -> next persona tab
//   IK_Joy7 (Back) -> Player.TogglePlayerMenuWindow()
// All others pass through to Super.VirtualKeyPressed (existing arrow /
// tab focus nav stays intact).
//
// Engine-routed via [Engine.Engine] Root=DXController.ControllerRootWindow
// in DeusEx.ini, read by the native InitRootWindow() declared at
// ../deusex-scripts/Extension/Classes/PlayerPawnExt.uc:35. DeusExPlayer
// has an inline comment "it can be changed in the ini" at
// ../deusex-scripts/DeusEx/Classes/DeusExPlayer.uc:11966.
//=============================================================================
class ControllerRootWindow extends DeusExRootWindow;

// Persona screen tab order, matching the vanilla navbar
// (../deusex-scripts/DeusEx/Classes/PersonaNavBarWindow.uc:28-40 with
// buttons created in reverse to render left-to-right):
// Inventory, Health, Augs, Skills, Goals, Cons, Images, Logs.
//
// Static — populated in defaultproperties so we can index without a
// per-instance init step. Wraps at both ends.
var Class<PersonaScreenBaseWindow> PersonaScreens[8];

// Override is safe: parent's VirtualKeyPressed is declared `event`
// (../deusex-scripts/DeusEx/Classes/DeusExRootWindow.uc:133), not final,
// and our same-state global override intercepts every dispatch path the
// player goes through while in the F1 menu (no state-scoped overrides
// exist in DeusExRootWindow).
event bool VirtualKeyPressed(EInputKey key, bool bRepeat)
{
    local ControllerPlayer player;

    if (key == IK_Joy7)
    {
        player = ControllerPlayer(parentPawn);
        if (player != None)
        {
            player.TogglePlayerMenuWindow();
            return true;
        }
    }

    // Tasks 10-11 add LB/RB handling here.

    return Super.VirtualKeyPressed(key, bRepeat);
}

function int FindPersonaScreenIndex(Class<PersonaScreenBaseWindow> c)
{
    local int i;
    if (c == None)
        return -1;
    for (i = 0; i < 8; i++)
    {
        if (PersonaScreens[i] == c)
            return i;
    }
    return -1;
}

function ShowAdjacentPersonaScreen(int direction)
{
    local PersonaScreenBaseWindow top;
    local int idx;

    top = PersonaScreenBaseWindow(GetTopWindow());
    if (top == None)
        return;

    idx = FindPersonaScreenIndex(top.Class);
    if (idx < 0)
        return;

    // Modulo 8 wrap. UScript's % keeps the sign of the dividend, so add
    // 8 before taking the mod to handle direction = -1 cleanly.
    idx = (idx + direction + 8) % 8;

    // Mirror PersonaNavBarWindow.ButtonActivated (line 94-95): persist
    // current screen state, then invoke the next one. InvokeUIScreen
    // pops the existing screen when the new one can't stack on top,
    // which is what we want for tabbing.
    top.SaveSettings();
    InvokeUIScreen(PersonaScreens[idx]);
}

function ShowPrevPersonaScreen() { ShowAdjacentPersonaScreen(-1); }
function ShowNextPersonaScreen() { ShowAdjacentPersonaScreen(+1); }

defaultproperties
{
    PersonaScreens(0)=Class'DeusEx.PersonaScreenInventory'
    PersonaScreens(1)=Class'DeusEx.PersonaScreenHealth'
    PersonaScreens(2)=Class'DeusEx.PersonaScreenAugmentations'
    PersonaScreens(3)=Class'DeusEx.PersonaScreenSkills'
    PersonaScreens(4)=Class'DeusEx.PersonaScreenGoals'
    PersonaScreens(5)=Class'DeusEx.PersonaScreenConversations'
    PersonaScreens(6)=Class'DeusEx.PersonaScreenImages'
    PersonaScreens(7)=Class'DeusEx.PersonaScreenLogs'
}
