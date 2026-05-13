//=============================================================================
// ControllerRootWindow — DeusExRootWindow subclass.
//
// Owns:
//   - LastPersonaScreen memory (which persona tab to re-open).
//   - TogglePlayerMenuWindow() — the actual open/close logic. Called from
//     both VirtualKeyPressed (for the menu-open close path) and
//     ControllerConsole's exec (for the menu-closed open path via the
//     binding system).
//
// Intercepts gamepad key events when a persona screen is on top:
//   IK_Joy5 (LB)   -> previous persona tab
//   IK_Joy6 (RB)   -> next persona tab
//   IK_Joy7 (Back) -> close the menu (via TogglePlayerMenuWindow)
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
var Class<PersonaScreenBaseWindow> PersonaScreens[8];

// The persona screen last seen open at toggle-close time. The original
// spec parked this on a custom player class with `travel`-qualified
// state so it survived map transitions; we can't reach the JCDentonMale
// pawn (engine-spawned, not subclassable in SP — see docs/issues.md).
// Living on the root window means we lose this across save/load — Inventory
// is the fallback in that case. Acceptable trade-off for the architecture
// simplification.
var Class<PersonaScreenBaseWindow> LastPersonaScreen;

event bool VirtualKeyPressed(EInputKey key, bool bRepeat)
{
    if (key == IK_Joy7)
    {
        TogglePlayerMenuWindow();
        return true;
    }

    // LB/RB only act when a persona screen is the top window. Any other
    // top window (datacube, conversation, sub-window) gets the event
    // through to Super so existing arrow/tab focus nav still works.
    if (PersonaScreenBaseWindow(GetTopWindow()) != None)
    {
        if (key == IK_Joy5)
        {
            ShowPrevPersonaScreen();
            return true;
        }
        if (key == IK_Joy6)
        {
            ShowNextPersonaScreen();
            return true;
        }
    }

    return Super.VirtualKeyPressed(key, bRepeat);
}

// Walks from GetTopWindow() up the parent-owner chain looking for the
// first ancestor that IS-A PersonaScreenBaseWindow. Returns None if no
// persona screen is anywhere in the chain (menu isn't open, or only
// non-persona windows like map/save dialogs are on the stack).
//
// Why a walk rather than just GetTopWindow(): a sub-window can be pushed
// in front of an open persona screen (e.g. HUDMedBotAddAugsScreen on top
// of PersonaScreenAugmentations). winStack is private on DeusExRootWindow
// (../deusex-scripts/DeusEx/Classes/DeusExRootWindow.uc:17), so we can't
// iterate the stack from outside; the parent-owner chain is what's
// available. Window.GetParent() is native(1428) final on
// ../deusex-scripts/Extension/Classes/Window.uc:152.
function PersonaScreenBaseWindow FindTopPersonaScreen()
{
    local Window w;

    w = GetTopWindow();
    while (w != None)
    {
        if (PersonaScreenBaseWindow(w) != None)
            return PersonaScreenBaseWindow(w);
        w = w.GetParent();
    }
    return None;
}

// Open: opens the menu at LastPersonaScreen (defaulting to Inventory).
// Closed: clears the window stack and records the last persona screen
// for next time.
//
// RestrictInput + multiplayer-inventory guards mirror ShowInventoryWindow
// (../deusex-scripts/DeusEx/Classes/DeusExPlayer.uc:6627-6638) — we bypass
// the vanilla Show*Window path by calling InvokeUIScreen directly with an
// arbitrary class, so we re-impose the same guards here. The close branch
// is unguarded — if the menu's open, the user must already be in a state
// where opening it was allowed.
function TogglePlayerMenuWindow()
{
    local PersonaScreenBaseWindow topPersona;
    local DeusExPlayer player;

    topPersona = FindTopPersonaScreen();
    if (topPersona != None)
    {
        LastPersonaScreen = topPersona.Class;
        // ClearWindowStack matches "leave the menu entirely". Vanilla
        // uses the same call for similar full-close situations
        // (DeusExPlayer.LoadGame / StartNewGame branches). PopWindow
        // would only pop one screen, leaving any sub-windows behind.
        ClearWindowStack();
        return;
    }

    player = DeusExPlayer(parentPawn);
    if (player == None)
        return;

    if (player.RestrictInput())
        return;
    if ((player.Level.NetMode != NM_Standalone) && player.bBeltIsMPInventory)
    {
        player.ClientMessage("Inventory screen disabled in multiplayer");
        return;
    }

    if (LastPersonaScreen == None)
        LastPersonaScreen = Class'DeusEx.PersonaScreenInventory';

    InvokeUIScreen(LastPersonaScreen);
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
