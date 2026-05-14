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
var RadialMenuWindow radial;

// Cursor mode.
const CM_Gamepad = 0;
const CM_Mouse   = 1;
var int cursorMode;

// Focus overlay (drawn above all menu content when in CM_Gamepad).
var MenuFocusOverlay focusOverlay;

// Nav controller registry. Keyed by screen class via parallel arrays.
// Entries populated in InitWindow. Concrete classes are instantiated
// lazily on first attach.
// Size 32: 8 persona slots + up to ~13 main-menu screen slots + headroom.
var Class<MenuNavController> navClasses[32];
var Class<Window>            navScreenKeys[32];
var MenuNavController        navInstances[32];
var int                      navCount;

// Active nav controller (the one whose screen is currently on top).
var MenuNavController activeNav;

event InitWindow()
{
    Super.InitWindow();

    radial = RadialMenuWindow(NewChild(Class'RadialMenuWindow'));
    radial.SetWindowAlignments(HALIGN_Full, VALIGN_Full, 0, 0);

    focusOverlay = MenuFocusOverlay(NewChild(Class'MenuFocusOverlay'));
    focusOverlay.SetWindowAlignments(HALIGN_Full, VALIGN_Full, 0, 0);

    RegisterNavControllers();
    cursorMode = CM_Gamepad;
}

function RegisterNavControllers()
{
    // Concrete nav controller classes are added per-task as controllers
    // come online (Tasks 8-19). Registrations will be uncommented here
    // as each controller class is implemented.
    //
    // Persona screens:
    RegisterNav(Class'DeusEx.PersonaScreenInventory',     Class'InvNavController');
    RegisterNav(Class'DeusEx.PersonaScreenHealth',        Class'HealthNavController');
    RegisterNav(Class'DeusEx.PersonaScreenAugmentations', Class'AugsNavController');
    RegisterNav(Class'DeusEx.PersonaScreenSkills',        Class'SkillsNavController');
    RegisterNav(Class'DeusEx.PersonaScreenGoals',         Class'GoalsNavController');
    RegisterNav(Class'DeusEx.PersonaScreenConversations', Class'ConvNavController');
    RegisterNav(Class'DeusEx.PersonaScreenImages',        Class'ImagesNavController');
    RegisterNav(Class'DeusEx.PersonaScreenLogs',          Class'LogsNavController');

    // MedBot aug installation screen — separate from the normal aug persona screen.
    RegisterNav(Class'DeusEx.HUDMedBotAddAugsScreen', Class'AugInstallNavController');

    // Main-menu family: MenuUIScreenWindow subclasses using the standard
    // choices[] pattern. Complex screens (list-based, edit controls, etc.)
    // are omitted — see comments below.
    RegisterNav(Class'DeusEx.MenuScreenOptions',      Class'MainMenuNavController');
    RegisterNav(Class'DeusEx.MenuScreenDisplay',      Class'MainMenuNavController');
    RegisterNav(Class'DeusEx.MenuScreenSound',        Class'MainMenuNavController');
    RegisterNav(Class'DeusEx.MenuScreenControls',     Class'MainMenuNavController');
    RegisterNav(Class'DeusEx.MenuScreenAdjustColors', Class'MainMenuNavController');
    RegisterNav(Class'DeusEx.MenuScreenBrightness',   Class'MainMenuNavController');
    // Omitted: MenuScreenCustomizeKeys — list-based key binding UI.
    // Omitted: MenuScreenNewGame      — skill list, text edit fields, portrait buttons.
    // Omitted: MenuScreenLoadGame     — list-based save file picker.
    // Omitted: MenuScreenSaveGame     — extends MenuScreenLoadGame, list-based.
    // Omitted: MenuScreenRGB          — tab-based, complex color picker controls.
    // Omitted: MenuScreenThemesLoad   — list-based theme picker.
    // Omitted: MenuScreenThemesSave   — list-based (extends MenuScreenLoadGame).
    // Note: MenuMain extends MenuUIMenuWindow (not MenuUIScreenWindow); it uses
    // winButtons[] not choices[], so it requires a separate controller if needed.
}

function RegisterNav(Class<Window> screenClass, Class<MenuNavController> navClass)
{
    if (navCount >= ArrayCount(navClasses))
        return;
    navScreenKeys[navCount] = screenClass;
    navClasses[navCount] = navClass;
    navInstances[navCount] = None;  // lazy instantiation on first attach
    navCount++;
}

function MenuNavController GetOrCreateNav(int idx)
{
    if (navInstances[idx] == None && navClasses[idx] != None)
        navInstances[idx] = new(None) navClasses[idx];
    return navInstances[idx];
}

function int FindNavIndex(Class screenClass)
{
    local int i;
    for (i = 0; i < navCount; i++)
    {
        if (navScreenKeys[i] == screenClass)
            return i;
    }
    return -1;
}

// Engine-event-driven nav attach/detach. Fires on every ancestor when
// a child enters or leaves the native window tree, while the descendant
// pointer is still valid (vanilla HUDBarkDisplay.DescendantRemoved
// calls descendant.IsA(...), proving safety). Replaces the lazy
// MaybeAttachNav polling, which observed dangling pointers after
// in-band InvokeUIScreen swaps.
event DescendantAdded(Window descendant)
{
    local int idx;
    local MenuNavController nav;

    Super.DescendantAdded(descendant);

    if (descendant == None)
        return;

    // Radial cancel-on-UI-takeover. PushWindow only accepts
    // DeusExBaseWindow subclasses, so that cast cleanly excludes the
    // root's HUD-style children (hud, scopeView, actorDisplay, radial,
    // focusOverlay) and every grandchild built during InitWindow.
    if (radial != None && radial.bOpen
        && DeusExBaseWindow(descendant) != None
        && descendant.GetParent() == Self)
    {
        radial.OnTopWindowPushed(descendant);
    }

    idx = FindNavIndex(descendant.Class);
    if (idx < 0)
        return;

    // Defensive: a registered screen is appearing and we still have a
    // controller bound. Normal flow detaches via DescendantRemoved
    // before we get here; this branch only matters if the engine
    // ordering ever reverses.
    if (activeNav != None)
    {
        activeNav.Detach();
        activeNav = None;
    }

    nav = GetOrCreateNav(idx);
    if (nav != None)
    {
        nav.Attach(descendant);
        activeNav = nav;
        class'DXControllerDebug'.static.DebugLog(
            "DXC-NAV ATTACH-EVT screen=" $ string(descendant.Class));
    }
}

event DescendantRemoved(Window descendant)
{
    Super.DescendantRemoved(descendant);

    if (activeNav != None && activeNav.screen == descendant)
    {
        class'DXControllerDebug'.static.DebugLog(
            "DXC-NAV DETACH-EVT screen=" $ string(descendant.Class));
        activeNav.Detach();
        activeNav = None;
    }
}

// Retry deferred focus init. Some screens (PersonaScreenInventory in
// particular) populate dynamic children — winItems contents — inside
// InitWindow AFTER DescendantAdded fires, so InitFocus called from
// Attach finds an empty container. Tick runs between frames once the
// screen is fully initialized, so the retry succeeds. The DXC-NAV
// TICK-INIT log below is the diagnostic that Tick on subclasses fires
// in this codebase (CLAUDE.md flagged it as unverified).
function Tick(float deltaSeconds)
{
    Super.Tick(deltaSeconds);

    if (activeNav != None && activeNav.focused == None && activeNav.screen != None)
    {
        activeNav.InitFocus();
        if (activeNav.focused != None)
            class'DXControllerDebug'.static.DebugLog(
                "DXC-NAV TICK-INIT screen=" $ string(activeNav.screen.Class));
    }
}

// Called by ControllerConsole at the top of every gamepad event handler.
function NoticeGamepadActivity()
{
    if (cursorMode == CM_Mouse)
    {
        cursorMode = CM_Gamepad;
        HideCursorAndClearHover();
        class'DXControllerDebug'.static.DebugLog("DXC-CURSOR mode=gamepad");
    }
}

function HideCursorAndClearHover()
{
    local Window top;
    // Clear any active hover state on buttons so vanilla hover visuals
    // don't compete with the gamepad focus highlight.
    top = GetTopWindow();
    if (top != None)
        ClearHoverRecursive(top);
}

function ClearHoverRecursive(Window w)
{
    local Window child;
    if (w == None)
        return;
    // MouseLeftWindow is the event Window fires when the mouse leaves a window.
    // Calling it unconditionally clears whatever "hovered" state vanilla sets
    // via MouseEnteredWindow. Verified against Extension/Classes/Window.uc:570.
    w.MouseLeftWindow();
    child = w.GetTopChild();
    while (child != None)
    {
        ClearHoverRecursive(child);
        child = child.GetLowerSibling();
    }
}

event MouseMoved(float newX, float newY)
{
    if (cursorMode == CM_Gamepad)
    {
        cursorMode = CM_Mouse;
        class'DXControllerDebug'.static.DebugLog("DXC-CURSOR mode=mouse");
    }
    Super.MouseMoved(newX, newY);
}

event bool VirtualKeyPressed(EInputKey key, bool bRepeat)
{
    local DeusExPlayer p;
    local int dx, dy;
    local byte bkey;        // byte alias for key — HandleActivate takes byte,
                            // and UE1 rejects EInputKey→byte implicit coercion.

    p = DeusExPlayer(parentPawn);
    bkey = key;             // EInputKey IS a byte; assignment (not cast) compiles.

    // ---- Close-menu buttons ----

    // B (Joy2): close sub-dialog if open; else close the menu.
    if (key == IK_Joy2 && !bRepeat)
    {
        if (activeNav != None && activeNav.subDialogActive != '')
        {
            // Sub-dialog ownership: route B to the active controller so
            // it can close its own sub-dialog cleanly.
            activeNav.HandleActivate(bkey);
            return true;
        }
        if (p != None)
            p.TogglePlayerMenuWindow();
        return true;
    }

    // Back (Joy7): always close menu, ignore sub-dialogs (panic exit).
    if (key == IK_Joy7 && !bRepeat)
    {
        class'DXControllerDebug'.static.DebugLog(
            "DXC-NAV BACK-RECV p=" $ string(p != None)
            $ " topPersona=" $ string(PersonaScreenBaseWindow(GetTopWindow()) != None));
        if (p != None)
            p.TogglePlayerMenuWindow();
        return true;
    }

    // Start (Joy8): close menu when a game is running. TogglePlayerMenuWindow
    // has an internal "are we already at title?" gate, so calling it
    // unconditionally is safe — the vanilla gate no-ops at the title screen.
    if (key == IK_Joy8 && !bRepeat)
    {
        if (p != None)
            p.TogglePlayerMenuWindow();
        return true;
    }

    // ---- LB/RB tab traversal (persona screens only, no sub-dialog) ----

    if (PersonaScreenBaseWindow(GetTopWindow()) != None
        && (activeNav == None || activeNav.subDialogActive == ''))
    {
        if (key == IK_Joy5 && !bRepeat)
        {
            ShowAdjacentPersonaScreen(-1);
            return true;
        }
        if (key == IK_Joy6 && !bRepeat)
        {
            ShowAdjacentPersonaScreen(+1);
            return true;
        }
    }

    // ---- D-pad → active controller's HandleDPad ----
    // Note: ControllerRootWindow extends Window (via DeusExRootWindow), NOT
    // Console. In Window/ExtensionObject scope the D-pad slots are named
    // IK_JoyPovUp..Right (0xF0-0xF3), NOT IK_UnknownF0..F3 (which only
    // applies in Console-scope where the stale EInputKey copy lives).

    dx = 0; dy = 0;
    if      (key == IK_JoyPovUp)    dy = -1;
    else if (key == IK_JoyPovDown)  dy = +1;
    else if (key == IK_JoyPovLeft)  dx = -1;
    else if (key == IK_JoyPovRight) dx = +1;

    if ((dx != 0 || dy != 0) && activeNav != None)
    {
        // bRepeat policy: list/scroll screens accept repeats (bAllowRepeat=true);
        // grid screens (Inventory, Augs) reject them (bAllowRepeat=false).
        if (bRepeat && !activeNav.bAllowRepeat)
            return true;   // consume the repeat but don't act on it
        if (activeNav.HandleDPad(dx, dy))
            return true;
    }

    // ---- A/X/Y/R-stick-click → active controller's HandleActivate ----
    // HandleActivate takes byte; EInputKey auto-coerces to byte in UE1.

    if (key == IK_Joy1 || key == IK_Joy3 || key == IK_Joy4 || key == IK_Joy10)
    {
        if (!bRepeat && activeNav != None && activeNav.HandleActivate(bkey))
            return true;
    }

    return Super.VirtualKeyPressed(key, bRepeat);
}

function int FindPersonaScreenIndex(Class<PersonaScreenBaseWindow> c)
{
    local int i;
    if (c == None)
        return -1;
    for (i = 0; i < ArrayCount(PersonaScreens); i++)
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

    // UScript's % keeps the sign of the dividend, so add ArrayCount
    // before the modulus to handle direction = -1 cleanly.
    idx = (idx + direction + ArrayCount(PersonaScreens)) % ArrayCount(PersonaScreens);

    // Mirror PersonaNavBarWindow.ButtonActivated: persist current screen
    // state, then invoke the next one. InvokeUIScreen pops the existing
    // screen when the new one can't stack on top, which is what we want
    // for tabbing.
    top.SaveSettings();
    InvokeUIScreen(PersonaScreens[idx]);
}

// True if any DeusExBaseWindow is currently a direct child of the root.
// Matches both PushWindow-managed screens (persona, main menu) AND
// NewChild-only windows (conversations via ConPlay.PlayerEnterConversation,
// computer/datacube terminals, etc.). GetTopWindow() only sees the
// PushWindow stack, so it misses conversations entirely.
//
// Same predicate DescendantAdded uses to fire the radial cancel-on-UI-
// takeover; factored here so wheel-open gating and cancel logic agree.
function bool IsAnyUIForeground()
{
    local Window c;

    c = GetTopChild();
    while (c != None)
    {
        if (DeusExBaseWindow(c) != None)
            return true;
        c = c.GetLowerSibling();
    }
    return false;
}

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
