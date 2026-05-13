//=============================================================================
// ControllerRootWindow — DeusExRootWindow subclass.
//
// Owns gamepad navigation when a menu is on top:
//   IK_Joy5 (LB)   -> previous persona tab
//   IK_Joy6 (RB)   -> next persona tab
//   IK_Joy7 (Back) -> close the menu (delegates to pawn TogglePlayerMenuWindow)
//
// The menu open/close logic, LastPersonaScreen memory, and persona-stack
// traversal all live on DeusExPlayer. This class just routes UI-time
// events; the pawn's exec handles binding-time events when no menu is
// open. Both paths land on the same pawn method.
//
// Engine-routed via [Engine.Engine] Root=DXController.ControllerRootWindow
// in DeusEx.ini.
//=============================================================================
class ControllerRootWindow extends DeusExRootWindow;

// Persona screen tab order, matching the vanilla navbar
// (../deusex-scripts/DeusEx/Classes/PersonaNavBarWindow.uc:28-40 with
// buttons created in reverse to render left-to-right).
var Class<PersonaScreenBaseWindow> PersonaScreens[8];

event bool VirtualKeyPressed(EInputKey key, bool bRepeat)
{
    local DeusExPlayer p;

    if (key == IK_Joy7)
    {
        p = DeusExPlayer(parentPawn);
        if (p != None)
            p.TogglePlayerMenuWindow();
        return true;
    }

    // LB/RB only act when a persona screen is the top window. Any other
    // top window (datacube, conversation, sub-window) gets the event
    // through to Super so existing arrow/tab focus nav still works.
    if (PersonaScreenBaseWindow(GetTopWindow()) != None)
    {
        if (key == IK_Joy5)
        {
            ShowAdjacentPersonaScreen(-1);
            return true;
        }
        if (key == IK_Joy6)
        {
            ShowAdjacentPersonaScreen(+1);
            return true;
        }
    }

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

    // Mirror PersonaNavBarWindow.ButtonActivated: persist current screen
    // state, then invoke the next one. InvokeUIScreen pops the existing
    // screen when the new one can't stack on top, which is what we want
    // for tabbing.
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
