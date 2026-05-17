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
var OnScreenKeyboardWindow keyboard;

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

// Button-legend overlay (drawn above all menu content when in CM_Gamepad).
var ControllerHintOverlay hintOverlay;

// Nav controller registry. Keyed by screen class via parallel arrays.
// Entries populated in InitWindow. Concrete classes are instantiated
// lazily on first attach.
// Size 48: 8 persona + ~19 main-menu/modal + 3 conversation + 5
// network-terminal slots = 35 in use, plus headroom. RegisterNav
// silently drops any call past ArrayCount, so this MUST stay >= the
// number of RegisterNav calls in RegisterNavControllers.
var Class<MenuNavController> navClasses[48];
var Class<Window>            navScreenKeys[48];
var MenuNavController        navInstances[48];
var int                      navCount;

// Active nav controller (the one whose screen is currently on top).
var MenuNavController activeNav;

// Diagnostic: last reported top-screen class name from Tick, used to
// emit a log line only on transitions (avoid per-frame spam).
var string lastDiagTopName;

event InitWindow()
{
    Super.InitWindow();

    radial = RadialMenuWindow(NewChild(Class'RadialMenuWindow'));
    radial.SetWindowAlignments(HALIGN_Full, VALIGN_Full, 0, 0);

    focusOverlay = MenuFocusOverlay(NewChild(Class'MenuFocusOverlay'));
    focusOverlay.SetWindowAlignments(HALIGN_Full, VALIGN_Full, 0, 0);

    hintOverlay = ControllerHintOverlay(NewChild(Class'ControllerHintOverlay'));
    hintOverlay.SetWindowAlignments(HALIGN_Full, VALIGN_Full, 0, 0);

    keyboard = OnScreenKeyboardWindow(NewChild(Class'OnScreenKeyboardWindow'));
    keyboard.SetWindowAlignments(HALIGN_Full, VALIGN_Full, 0, 0);

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

    // Standalone modal devices: numeric keypad (coded doors), MedBot
    // health-only variant of PersonaScreenHealth, and the RepairBot
    // recharge popup. See docs/superpowers/specs/2026-05-15-modal-devices-nav-design.md.
    RegisterNav(Class'DeusEx.HUDKeypadWindow',       Class'KeypadNavController');
    RegisterNav(Class'DeusEx.HUDMedBotHealthScreen', Class'MedBotHealthNavController');
    RegisterNav(Class'DeusEx.HUDRechargeWindow',     Class'RechargeNavController');

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

    // New Game screen — portrait + skills list + action bar.
    // editName / editCodeName text fields are intentionally excluded
    // from gamepad nav (no virtual keyboard); keyboard typing into
    // editName remains independent via the engine's text-focus path.
    RegisterNav(Class'DeusEx.MenuScreenNewGame', Class'NewGameNavController');

    // List-shape menu screens.
    RegisterNav(Class'DeusEx.MenuScreenLoadGame',   Class'LoadGameNavController');
    RegisterNav(Class'DeusEx.MenuScreenSaveGame',   Class'SaveGameNavController');
    RegisterNav(Class'DeusEx.MenuScreenThemesLoad', Class'ThemesLoadNavController');
    RegisterNav(Class'DeusEx.MenuScreenThemesSave', Class'ThemesSaveNavController');

    // Modal confirmation dialogs (Quit, Overwrite, Delete confirm,
    // AskToTrain, intro/training warnings, etc.).
    RegisterNav(Class'DeusEx.MenuUIMessageBoxWindow', Class'MessageBoxNavController');

    // In-world conversation windows. ConWindowActive is the third-person
    // interactive conversation (with choice list); ConWindow is the
    // first-person non-interactive variant. Both are NewChild'd onto
    // root (not PushWindow'd), so they don't appear in GetTopWindow();
    // the controller's AllowsMenuToggle=false routes B and gates
    // Start/Back. See ConversationNavController for binding details.
    //
    // The DeusExe launcher (../DeusExe-XInput/DeusExe/SubTitleFix.cpp)
    // hooks NewChild and silently swaps DeusEx.ConWindowActive for its
    // own DeusExe.ConWindowActive2 (a widescreen subtitle fix), so the
    // runtime class is the subclass. FindNavIndex matches on exact class
    // identity, so we register both — the base class for any caller that
    // bypasses the launcher swap, and the subclass for the normal path.
    RegisterNav(Class'DeusEx.ConWindow',           Class'ConversationNavController');
    RegisterNav(Class'DeusEx.ConWindowActive',     Class'ConversationNavController');
    RegisterNav(Class'DeusExe.ConWindowActive2',   Class'ConversationNavController');

    // In-world network terminals. Phase 1: shell dispatch + Computer
    // pane sub-controllers (Login/Bulletins/Email/SpecialOptions/ATM*).
    // ComputerScreenSecurity sub-controller is Phase 2; Security
    // terminals still register here so the shell-level B / pane-cycling
    // / Logout paths work on them.
    //
    // NetworkTerminal itself is abstract; registered for defensive
    // completeness only — FindNavIndex is exact-class-match so each
    // concrete subclass needs its own line.
    RegisterNav(Class'DeusEx.NetworkTerminalPersonal', Class'NetworkTerminalNavController');
    RegisterNav(Class'DeusEx.NetworkTerminalPublic',   Class'NetworkTerminalNavController');
    RegisterNav(Class'DeusEx.NetworkTerminalATM',      Class'NetworkTerminalNavController');
    RegisterNav(Class'DeusEx.NetworkTerminalSecurity', Class'NetworkTerminalNavController');
    RegisterNav(Class'DeusEx.NetworkTerminal',         Class'NetworkTerminalNavController');
    // The ATM actor hardcodes InvokeUIScreen(Class'ATMWindow') —
    // ATMWindow is a "dummy" backwards-compat subclass of
    // NetworkTerminalATM and is the class actually pushed for every
    // ATM. NetworkTerminalATM itself is never instantiated. Since
    // FindNavIndex is exact-class-match, ATMWindow needs its own
    // entry (cf. the ConWindowActive / ConWindowActive2 pair above).
    RegisterNav(Class'DeusEx.ATMWindow',               Class'NetworkTerminalNavController');

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

// Walk root's direct children (top-of-z-stack first) and stop at the
// topmost modal screen — a DeusExBaseWindow direct child of root. That
// predicate cleanly separates modal screens (PushWindow'd menus,
// conversations, datacubes — all inherit ModalWindow via
// DeusExBaseWindow) from the always-present HUD-style children
// (hud, actorDisplay, scopeView, radial, focusOverlay, keyboard —
// all extend Window directly, NOT DeusExBaseWindow). Returns:
//
//   (controller, screen) when the topmost modal is registered.
//   (None,       screen) when the topmost modal is not registered
//                        (e.g., MenuScreenNewGame / CustomizeKeys /
//                        RGB) — SwitchActiveNav then clears activeNav
//                        so D-pad/A/X don't drive a screen beneath the
//                        visible modal.
//   (None,       None)   when no modal is foregrounded (gameplay).
//
// The walk STOPS at the topmost modal; it does not skip an unregistered
// modal to find a registered screen beneath it.
//
// Why this is called from Tick instead of from DescendantRemoved:
// PopWindow runs `oldWindow.Destroy()` BEFORE `newWindow.Show()`, and
// Hide() unlinks the parent from root's child list. That means
// DescendantRemoved fires while the parent is still hidden+unlinked
// and this walk would return None for the back-nav case (verified by
// the test 2 log capture for Bug 5 — `DETACH MenuSelectDifficulty`
// with no matching `ATTACH MenuMain` follow-up). Tick runs between
// frames, after Show() has relinked the parent into the child list,
// so the parent is found then. Tick reconciliation is the canonical
// source of truth; DescendantAdded is retained as a same-frame
// optimization for the push case (no Hide/Show transition there).
function MenuNavController FindTopmostModalNav(out Window outScreen)
{
    local Window c;
    local int idx;

    outScreen = None;
    c = GetTopChild();
    while (c != None)
    {
        if (DeusExBaseWindow(c) != None && c.GetParent() == Self)
        {
            outScreen = c;
            idx = FindNavIndex(c.Class);
            if (idx >= 0)
                return GetOrCreateNav(idx);
            return None;
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

        // Raise the focus overlay so it draws on top of the newly-
        // attached modal screen. PushWindow / NewChild add the modal
        // at the top of the z-stack (above focusOverlay's
        // InitWindow-time position), so without this the focus frame
        // would render behind the modal. For most persona screens the
        // backgrounds are translucent enough that the frame shows
        // through anyway, but ConWindowActive's lowerConWindow draws
        // an opaque modulated tile that hides the frame entirely.
        if (focusOverlay != None)
            focusOverlay.Raise();

        // Keep the legend overlay above the newly-attached modal too.
        if (hintOverlay != None)
            hintOverlay.Raise();

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

// Open the gamepad on-screen keyboard targeting `target`. `label` is
// drawn at the top of the keyboard panel (e.g. "ENTER USERNAME").
// Invoked by nav controllers from their A-on-text-field handlers.
function OpenKeyboard(MenuUIEditWindow target, Window ownerScreen, string label)
{
    if (keyboard == None || target == None)
        return;
    keyboard.Open(target, ownerScreen, label);
}

// Override of the DeusExRootWindow.CloseGamepadKeyboard hook. Called
// from ComputerUIWindow's IK_Escape handler so a physical-keyboard Esc
// dismisses the on-screen keyboard. Returns true if the keyboard was
// open and has now been closed.
function bool CloseGamepadKeyboard()
{
    if (keyboard != None && keyboard.bOpen)
    {
        keyboard.CloseKbd("Esc");
        return true;
    }
    return false;
}

// Engine-event-driven nav attach/detach. Fires on every ancestor when
// a child enters or leaves the native window tree, while the descendant
// pointer is still valid (vanilla HUDBarkDisplay.DescendantRemoved
// calls descendant.IsA(...), proving safety).
//
// DescendantAdded uses direct descendant.Class lookup because the
// engine fires this event before the new child is reachable via
// GetTopChild (verified empirically: a GetTopChild walk here misses
// the freshly-pushed screen). This stays a same-frame attach for push,
// which has no Hide/Show transition that would invalidate state.
//
// DescendantRemoved cannot re-derive activeNav reliably: when a
// sub-menu is popped, PopWindow runs Destroy (firing this event) BEFORE
// Show on the underlying parent, so the parent is still hidden and
// unlinked from root's child list. The walk would miss it. Instead,
// DescendantRemoved just clears activeNav defensively if the active
// screen is going away, and Tick re-resolves on the next frame after
// Show has settled the tree. See FindTopmostModalNav.
event DescendantAdded(Window descendant)
{
    local int idx;
    local bool bIsModalScreen;
    local string parentName;  // diagnostic

    Super.DescendantAdded(descendant);

    if (descendant == None)
    {
        class'DXControllerDebug'.static.DebugLog("DXC-NAV DESC-ADD descendant=None");  // diagnostic
        return;
    }

    if (descendant.GetParent() != None)
        parentName = string(descendant.GetParent().Class);
    else
        parentName = "None";
    class'DXControllerDebug'.static.DebugLog(
        "DXC-NAV DESC-ADD class=" $ string(descendant.Class)
        $ " parent=" $ parentName
        $ " isModal=" $ string(DeusExBaseWindow(descendant) != None)
        $ " parentIsSelf=" $ string(descendant.GetParent() == Self));  // diagnostic

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
    class'DXControllerDebug'.static.DebugLog(
        "DXC-NAV DESC-ADD FindNavIndex result idx=" $ string(idx));  // diagnostic
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
    Super.DescendantRemoved(descendant);

    // Force the keyboard closed when the screen owning its target
    // field is torn down. This catches an inner ComputerScreenX swap
    // (e.g. a successful login), where the removed descendant is the
    // inner screen — not activeNav.screen, which is the NetworkTerminal
    // shell. Whole-terminal teardown also destroys the inner screen
    // first, so this check covers that case too; the activeNav block
    // below is defence in depth.
    if (keyboard != None && keyboard.bOpen && keyboard.targetScreen == descendant)
        keyboard.ForceClose();

    // The active screen is being torn down — drop activeNav now so
    // VirtualKeyPressed / MenuFocusOverlay don't dereference the
    // destroyed window during the rest of this frame. Don't try to
    // re-resolve the new top here: in the back-nav-from-hidden-parent
    // case the parent is still hidden+unlinked at this moment and the
    // walk would return None anyway. Tick re-resolves post-Show.
    if (activeNav != None && activeNav.screen == descendant)
    {
        // The screen owning any open on-screen keyboard target is
        // going away — force the keyboard closed before its target
        // field is destroyed.
        if (keyboard != None && keyboard.bOpen)
            keyboard.ForceClose();
        SwitchActiveNav(None, None);
    }
}

// Per-frame work, run between frames after the engine has settled any
// in-flight Hide/Show / PushWindow / PopWindow transitions. Three jobs:
//
//   1. Reconcile activeNav against the visible top-of-stack. The
//      engine-event-driven attach in DescendantAdded handles the push
//      case in the same frame, but DescendantRemoved can't reach
//      a hidden parent that PopWindow has yet to Show. Tick is the
//      canonical resolver — SwitchActiveNav early-exits when nothing
//      has changed, so the steady-state cost is one short sibling walk.
//
//   2. Detect mouse motion while the cursor is hidden. ShowCursor(False)
//      suppresses script-level MouseMoved, so polling GetCursorPos is
//      the only signal that the user grabbed the mouse.
//
//   3. Retry deferred focus init. Some screens (PersonaScreenInventory
//      in particular) populate dynamic children — winItems contents —
//      inside InitWindow AFTER DescendantAdded fires, so InitFocus
//      called from Attach finds an empty container. Tick runs once the
//      screen is fully initialized, so the retry succeeds. The DXC-NAV
//      TICK-INIT log is the diagnostic that Tick on subclasses fires
//      in this codebase.
function Tick(float deltaSeconds)
{
    local float curX, curY;
    local Window topScreen;
    local MenuNavController topNav;

    Super.Tick(deltaSeconds);

    // 1. activeNav reconciliation. Runs first so the cursor-poll and
    //    focus-retry blocks below see the up-to-date activeNav.
    topNav = FindTopmostModalNav(topScreen);

    // === Diagnostic: log top-screen identity transitions ===
    if (topScreen != None && string(topScreen.Class) != lastDiagTopName)
    {
        class'DXControllerDebug'.static.DebugLog(
            "DXC-NAV TICK-TOP topScreen=" $ string(topScreen.Class)
            $ " idx=" $ string(FindNavIndex(topScreen.Class))
            $ " hasNav=" $ string(topNav != None));
        lastDiagTopName = string(topScreen.Class);
    }
    else if (topScreen == None && lastDiagTopName != "None")
    {
        class'DXControllerDebug'.static.DebugLog("DXC-NAV TICK-TOP topScreen=None");
        lastDiagTopName = "None";
    }
    // === End diagnostic ===

    SwitchActiveNav(topNav, topScreen);

    // 2. Mouse-grab detection while cursor is hidden.
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

    // 3. Deferred focus init for screens whose children populate lazily.
    if (activeNav != None && activeNav.focused == None && activeNav.screen != None)
    {
        activeNav.InitFocus();
        if (activeNav.focused != None)
            class'DXControllerDebug'.static.DebugLog(
                "DXC-NAV TICK-INIT screen=" $ string(activeNav.screen.Class));
    }

    // 4. Drive the active controller's per-frame hook. MenuNavController
    //    is Object-scoped so the engine doesn't tick it directly; this
    //    is the manual pump. NetworkTerminalNavController uses it for
    //    winComputer screen-swap detection; most controllers no-op.
    if (activeNav != None)
        activeNav.NavTick(deltaSeconds);
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

    // ---- On-screen keyboard owns input while open ----
    // The keyboard window does not reliably receive engine focus
    // (verified by play-test — SetFocusWindow on a root-child window
    // does not capture key dispatch). Gamepad keys do bubble up to this
    // root VirtualKeyPressed, the same path every nav controller relies
    // on, so intercept them here: D-pad / A / X / B all route into the
    // keyboard, and every key is consumed so nothing leaks to the
    // terminal beneath. (Physical-keyboard Esc is handled separately —
    // it is swallowed by ComputerUIWindow below the root.)
    if (keyboard != None && keyboard.bOpen)
    {
        keyboard.HandleKey(key, bRepeat);
        return true;
    }

    // ---- Close-menu buttons ----

    // B (Joy2): cancel one level. Three routes, in priority order:
    //   1. Sub-dialog ownership (radial wheel belt-assign): the active
    //      controller closes its sub-dialog via HandleActivate.
    //   2. In-world modal controllers (conversation, future keypad /
    //      computer): the controller overrides AllowsMenuToggle()
    //      to false; B routes to its HandleActivate so it can
    //      decide advance / commit / noop. These windows are
    //      NewChild'd on root (not PushWindow'd), so GetTopWindow()
    //      can't see them and Escape synthesis below would no-op.
    //   3. Default — synthesise IK_Escape on the topmost PushWindow,
    //      letting each menu screen's CancelScreen() or
    //      PostResult() handler run untouched:
    //        - MenuUIWindow-family screens: Escape -> CancelScreen() ->
    //          root.PopWindow() (per-screen overrides like
    //          MenuScreenNewGame.CancelScreen restoring skill points
    //          run as written).
    //        - MenuUIMessageBoxWindow: Escape -> PostResult(1) for YesNo
    //          ("No" path) or PostResult(0) for OK.
    //
    // Caveat: GetTopWindow() reflects the PushWindow stack only
    // (CLAUDE.md). Every menu screen and message box in scope is
    // PushWindow-stacked, so route 3 is correct for them.
    if (key == IK_Joy2 && !bRepeat)
    {
        if (activeNav != None && activeNav.subDialogActive != '')
        {
            activeNav.HandleActivate(bkey);
            return true;
        }

        if (activeNav != None && !activeNav.AllowsMenuToggle())
        {
            activeNav.HandleActivate(bkey);
            return true;
        }

        top = GetTopWindow();
        if (top != None)
            top.VirtualKeyPressed(IK_Escape, false);
        return true;
    }

    // Back (Joy7): close menu (panic exit, ignores sub-dialogs).
    // Gated by activeNav.AllowsMenuToggle() so an in-world modal
    // (conversation, future keypad / computer) can suppress the
    // toggle and prevent the persona menu stacking on top of itself.
    if (key == IK_Joy7 && !bRepeat)
    {
        if (activeNav != None && !activeNav.AllowsMenuToggle())
        {
            class'DXControllerDebug'.static.DebugLog(
                "DXC-NAV BLOCK-MENU-TOGGLE key=Joy7");
            return true;
        }
        class'DXControllerDebug'.static.DebugLog(
            "DXC-NAV BACK-RECV p=" $ string(p != None)
            $ " topPersona=" $ string(PersonaScreenBaseWindow(GetTopWindow()) != None));
        if (p != None)
            p.TogglePlayerMenuWindow();
        return true;
    }

    // Start (Joy8): toggle menu when a game is running.
    // TogglePlayerMenuWindow has an internal "are we already at title?"
    // gate, so calling it unconditionally is safe — the vanilla gate
    // no-ops at the title screen. Gated by AllowsMenuToggle() for the
    // same reason as Joy7.
    if (key == IK_Joy8 && !bRepeat)
    {
        if (activeNav != None && !activeNav.AllowsMenuToggle())
        {
            class'DXControllerDebug'.static.DebugLog(
                "DXC-NAV BLOCK-MENU-TOGGLE key=Joy8");
            return true;
        }
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
    // LB/RB (Joy5/Joy6) also dispatch here, but only when GetTopWindow
    // is not a persona screen — the persona-screen LB/RB tab block
    // above runs first and consumes those keys for persona-tab cycling.
    // Network-terminal pane cycling uses Joy5/Joy6 via HandleActivate;
    // existing controllers consume them as no-ops (HandleActivate
    // returns true for unrecognised bytes).

    if (key == IK_Joy1 || key == IK_Joy3 || key == IK_Joy4 || key == IK_Joy10
        || key == IK_Joy5 || key == IK_Joy6)
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
