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

// Baseline cursor position captured each time we hide the cursor.
// ShowCursor(False) suppresses MouseMoved dispatch at the script level
// (vanilla uses it in modes where mouse motion isn't expected — see
// MenuScreenCustomizeKeys' "press a key to rebind" mode). To detect
// the user grabbing the mouse, Tick polls GetCursorPos and compares
// against this baseline.
var float lastCursorX, lastCursorY;

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

    // MenuUIMenuWindow subclasses: title/pause-root MenuMain, the
    // Settings sub-menu opened from MenuMain → Settings, and the
    // difficulty picker opened by the New Game flow. All three share
    // the winButtons[] shape that MenuMainNavController drives.
    RegisterNav(Class'DeusEx.MenuMain',             Class'MenuMainNavController');
    RegisterNav(Class'DeusEx.MenuSettings',         Class'MenuMainNavController');
    RegisterNav(Class'DeusEx.MenuSelectDifficulty', Class'MenuMainNavController');

    // Options sub-screens: MenuUIScreenWindow subclasses using the
    // standard choices[] pattern. Driven by OptionsNavController.
    RegisterNav(Class'DeusEx.MenuScreenOptions',      Class'OptionsNavController');
    RegisterNav(Class'DeusEx.MenuScreenDisplay',      Class'OptionsNavController');
    RegisterNav(Class'DeusEx.MenuScreenSound',        Class'OptionsNavController');
    RegisterNav(Class'DeusEx.MenuScreenControls',     Class'OptionsNavController');
    RegisterNav(Class'DeusEx.MenuScreenAdjustColors', Class'OptionsNavController');
    RegisterNav(Class'DeusEx.MenuScreenBrightness',   Class'OptionsNavController');
    // Omitted: MenuScreenCustomizeKeys — list-based key binding UI.
    // Omitted: MenuScreenNewGame      — skill list, text edit fields, portrait buttons.

    // List-shape menu screens.
    RegisterNav(Class'DeusEx.MenuScreenLoadGame',   Class'LoadGameNavController');
    RegisterNav(Class'DeusEx.MenuScreenSaveGame',   Class'SaveGameNavController');
    RegisterNav(Class'DeusEx.MenuScreenThemesLoad', Class'ThemesLoadNavController');
    RegisterNav(Class'DeusEx.MenuScreenThemesSave', Class'ThemesSaveNavController');

    // Modal confirmation dialogs (Quit, Overwrite, Delete confirm,
    // AskToTrain, intro/training warnings, etc.).
    RegisterNav(Class'DeusEx.MenuUIMessageBoxWindow', Class'MessageBoxNavController');

    // Omitted: MenuScreenRGB          — tab-based, complex color picker controls.
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

// Walk root's direct children (top-of-z-stack first) and return
// the topmost child whose class is in the nav registry, or None.
// Used by DescendantRemoved to find what's still on top after a
// modal overlay closes (e.g., MessageBox dismissed → MenuMain
// underneath should re-attach).
//
// NOT used in DescendantAdded: when a new child is just being
// added, the engine fires DescendantAdded *before* the child is
// reachable via GetTopChild — the walk would miss it. That path
// matches descendant.Class directly instead.
function MenuNavController FindTopmostRegisteredNav(out Window outScreen)
{
    local Window c;
    local int idx;

    outScreen = None;
    c = GetTopChild();
    while (c != None)
    {
        idx = FindNavIndex(c.Class);
        if (idx >= 0)
        {
            outScreen = c;
            return GetOrCreateNav(idx);
        }
        c = c.GetLowerSibling();
    }
    return None;
}

// Switch activeNav. Detaches the current one, attaches `desired` to
// `desiredScreen`. Either may be None.
function SwitchActiveNav(MenuNavController desired, Window desiredScreen)
{
    if (activeNav == desired
        && (desired == None || activeNav.screen == desiredScreen))
        return;

    if (activeNav != None)
    {
        if (activeNav.screen != None)
            class'DXControllerDebug'.static.DebugLog(
                "DXC-NAV SWITCH detach=" $ string(activeNav.screen.Class));
        activeNav.Detach();
    }
    activeNav = desired;
    if (activeNav != None)
    {
        activeNav.Attach(desiredScreen);
        class'DXControllerDebug'.static.DebugLog(
            "DXC-NAV SWITCH attach=" $ string(desiredScreen.Class));
        // Initial menu open arrives here (mode is already CM_Gamepad from
        // InitWindow, so NoticeGamepadActivity won't fire). Hide the cursor
        // unless the user is in CM_Mouse from a prior session.
        if (cursorMode == CM_Gamepad)
        {
            ShowCursor(False);
            GetCursorPos(lastCursorX, lastCursorY);
        }
    }
    else
    {
        // Detached to no registered nav — either gameplay or an unregistered
        // modal that needs mouse/keyboard. Return cursor to engine default.
        ShowCursor(True);
    }
}

// Engine-event-driven nav attach/detach. Fires on every ancestor when
// a child enters or leaves the native window tree, while the descendant
// pointer is still valid (vanilla HUDBarkDisplay.DescendantRemoved
// calls descendant.IsA(...), proving safety).
//
// DescendantAdded uses direct descendant.Class lookup because the
// engine fires this event before the new child is reachable via
// GetTopChild (verified empirically: a GetTopChild walk here misses
// the freshly-pushed screen).
//
// DescendantRemoved walks GetTopChild to handle the modal-overlay
// case — when MessageBox is dismissed, ResolveActiveNav re-attaches
// whichever registered screen is still on top.
event DescendantAdded(Window descendant)
{
    local int idx;
    local bool bIsModalScreen;

    Super.DescendantAdded(descendant);

    if (descendant == None)
        return;

    // Radial cancel-on-UI-takeover. PushWindow only accepts
    // DeusExBaseWindow subclasses, so that cast cleanly excludes the
    // root's HUD-style children (hud, scopeView, actorDisplay, radial,
    // focusOverlay) and every grandchild built during InitWindow.
    bIsModalScreen = DeusExBaseWindow(descendant) != None
                     && descendant.GetParent() == Self;
    if (radial != None && radial.bOpen && bIsModalScreen)
    {
        radial.OnTopWindowPushed(descendant);
    }

    // Direct registry match on the just-added descendant. We can't
    // walk GetTopChild here — the engine fires this event before the
    // new child is in root's child list.
    idx = FindNavIndex(descendant.Class);
    if (idx >= 0)
    {
        SwitchActiveNav(GetOrCreateNav(idx), descendant);
        return;
    }

    // Unregistered DeusExBaseWindow pushed as a direct child of root
    // (e.g., MenuScreenNewGame, MenuScreenCustomizeKeys — out of
    // scope for this controller pass): clear activeNav so the
    // underlying screen's nav doesn't continue handling D-pad / A /
    // X under the new visible modal. B still works (synthesises
    // IK_Escape on top window), so the user can back out.
    if (bIsModalScreen)
        SwitchActiveNav(None, None);
}

event DescendantRemoved(Window descendant)
{
    local Window topScreen;
    local MenuNavController topNav;

    Super.DescendantRemoved(descendant);

    // Re-derive activeNav from the current window tree. Handles the
    // modal-overlay close case (MessageBox popped → MenuMain still
    // on top → its controller re-attaches).
    topNav = FindTopmostRegisteredNav(topScreen);
    SwitchActiveNav(topNav, topScreen);
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
    local float curX, curY;

    Super.Tick(deltaSeconds);

    // Detect mouse motion while the cursor is hidden. The script-level
    // MouseMoved event doesn't fire under ShowCursor(False), so polling
    // GetCursorPos is the only signal that the user grabbed the mouse.
    if (cursorMode == CM_Gamepad && activeNav != None)
    {
        GetCursorPos(curX, curY);
        if (curX != lastCursorX || curY != lastCursorY)
        {
            cursorMode = CM_Mouse;
            ShowCursor(True);
            class'DXControllerDebug'.static.DebugLog("DXC-CURSOR mode=mouse (poll)");
        }
    }

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
    // Hide the OS cursor sprite. RootWindow.ShowCursor is a native
    // (index 1522) inherited via DeusExRootWindow — same call vanilla
    // uses in MenuScreenCustomizeKeys and ConWindowActive.
    ShowCursor(False);
    GetCursorPos(lastCursorX, lastCursorY);
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
        ShowCursor(True);
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
    local Window top;

    p = DeusExPlayer(parentPawn);
    bkey = key;             // EInputKey IS a byte; assignment (not cast) compiles.

    // Re-hide cursor on gamepad button presses. Console.state Menuing
    // doesn't forward IST_Press button events to global.KeyEvent (only
    // axes are forwarded in our override), so the Console-side
    // NoticeGamepadActivity hook misses every menu button press. Gate
    // on the gamepad key ranges so keyboard nav (Tab/arrows/Enter)
    // doesn't trigger an unwanted CM_Gamepad transition.
    //   200..215 = IK_Joy1..IK_Joy16
    //   240..243 = D-pad slots (IK_JoyPovUp..Right, 0xF0..0xF3)
    if ((bkey >= 200 && bkey <= 215) || (bkey >= 240 && bkey <= 243))
        NoticeGamepadActivity();

    // ---- Close-menu buttons ----

    // B (Joy2): cancel one level — either the sub-dialog (if a
    // controller owns one), or the topmost window. The topmost window
    // already routes IK_Escape correctly via its own VirtualKeyPressed:
    //
    //   - MenuUIWindow-family screens: Escape → CancelScreen() →
    //     root.PopWindow() (one level back). Per-screen CancelScreen
    //     overrides (e.g. MenuScreenNewGame restoring skill points)
    //     run untouched.
    //   - MenuUIMessageBoxWindow: Escape → PostResult(1) for YesNo
    //     (the "No" path) or PostResult(0) for OK.
    //
    // Synthesizing Escape lets each screen's existing handler win,
    // without per-screen branching here. Compare with Back (Joy7)
    // below, which is the explicit "full close" path.
    //
    // Caveat: GetTopWindow() reflects the PushWindow stack only
    // (CLAUDE.md). Every menu screen and message box in scope is
    // PushWindow-stacked, so this is correct here.
    if (key == IK_Joy2 && !bRepeat)
    {
        if (activeNav != None && activeNav.subDialogActive != '')
        {
            // Sub-dialog ownership (radial wheel assign, aug install):
            // route B to the active controller so it can close its
            // sub-dialog cleanly. Unchanged.
            activeNav.HandleActivate(bkey);
            return true;
        }

        top = GetTopWindow();
        if (top != None)
            top.VirtualKeyPressed(IK_Escape, false);
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
