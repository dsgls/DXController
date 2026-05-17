//=============================================================================
// ControllerConsole — engine Console subclass.
//
// Stateless event forwarder. Intercepts the gamepad events that the
// binding system can't deliver cleanly (axis-to-button for the triggers,
// press+release pair for L-stick click) and forwards them to the pawn.
// Everything else falls through to Super.
//
// Engine-routed via [Engine.Engine] Console=DXController.ControllerConsole
// in DeusEx.ini.
//=============================================================================
class ControllerConsole extends Console;

// True if Key is one of the gamepad slots fed by the XInput shim:
// buttons IK_Joy1..16 (0xC8-0xD7), D-pad (0xF0-0xF3), and the stick /
// trigger axes JoyX/Y/Z/R (0xE0-0xE3) + JoyU/V (0xE8-0xE9). KeyEvent is
// the first script entry point for ALL input — mouse (IK_MouseX/Y,
// IK_LeftMouse) and keyboard events arrive here too — so the
// NoticeGamepadActivity hook must whitelist gamepad slots before
// flipping the cursor mode. Mirrors the byte-range gate in
// ControllerRootWindow.VirtualKeyPressed.
function bool IsGamepadKey(EInputKey Key)
{
    local int k;
    k = Key;                                  // EInputKey->int widening assignment
    if (k >= 0xC8 && k <= 0xD7) return true;  // IK_Joy1..IK_Joy16
    if (k >= 0xF0 && k <= 0xF3) return true;  // D-pad slots
    if (k >= 0xE0 && k <= 0xE3) return true;  // JoyX/Y/Z/R (sticks + triggers)
    if (k == 0xE8 || k == 0xE9) return true;  // JoyU/JoyV (right stick)
    return false;
}

event bool KeyEvent(EInputKey Key, EInputAction Action, FLOAT Delta)
{
    local DeusExPlayer p;
    local ControllerRootWindow root;

    if (Viewport != None)
        p = DeusExPlayer(Viewport.Actor);
    if (p == None)
        return Super.KeyEvent(Key, Action, Delta);

    // Notify root window so it can flip from CM_Mouse → CM_Gamepad —
    // but ONLY for genuine gamepad events. KeyEvent also carries mouse
    // and keyboard input; treating mouse-movement axes (IK_MouseX/Y) as
    // gamepad activity makes the title-screen main menu flicker between
    // cursor modes (one mouse motion fires both MouseMoved → CM_Mouse
    // and IK_MouseX/Y axes → here → CM_Gamepad). See IsGamepadKey.
    if (p.rootWindow != None && IsGamepadKey(Key))
    {
        if (ControllerRootWindow(p.rootWindow) != None)
            ControllerRootWindow(p.rootWindow).NoticeGamepadActivity();
    }

    if (Action == IST_Axis)
    {
        // Log L-stick / R-stick events when the radial is open/sticky or a
        // nav controller is active. Filter |Delta|>100 to skip centring
        // noise; only the four player sticks (X/Y/U/V) are interesting.
        // Useful to confirm the Menuing-state forwarder (state block at
        // end of file) is reaching here and the gates below see the
        // expected wheel/nav state.
        if (Abs(Delta) > 100.0
            && (Key == IK_JoyX || Key == IK_JoyY || Key == IK_JoyU || Key == IK_JoyV))
        {
            root = ControllerRootWindow(p.rootWindow);
            if (root != None && root.radial != None
                && (root.radial.bOpen || root.radial.bSticky || root.activeNav != None))
            {
                class'DXControllerDebug'.static.DebugLog(
                    "DXC-AXIS Key=" $ string(Key) $ " Delta=" $ string(int(Delta))
                    $ " bOpen=" $ string(root.radial.bOpen)
                    $ " bSticky=" $ string(root.radial.bSticky)
                    $ " nav=" $ string(root.activeNav != None));
            }
        }

        // Triggers fire the weapon / use tools (RT) and toggle
        // scope-laser (LT). Suppress both while a UI screen owns the
        // foreground — terminals, conversations, keypads and datacubes
        // are pushed bNoPause, so the console never enters state
        // Menuing and this class-scoped handler still runs (the persona
        // menu, which IS in Menuing, already drops triggers via the
        // state override). Force-release (pass 0.0) rather than skip
        // the call, so a trigger physically held when the UI opened
        // doesn't stay latched as bFire / scope state.
        if (Key == IK_JoyZ)
        {
            root = ControllerRootWindow(p.rootWindow);
            // A UI nav controller may claim the trigger (Security-screen
            // camera zoom). It must only claim while its screen owns the
            // foreground — claiming during gameplay would silently drop the
            // trigger. If it consumes, skip the force-zero and suppress
            // binding dispatch.
            if (root != None && root.activeNav != None
                && root.activeNav.HandleTrigger(0, Delta))
                return true;
            if (root != None && root.IsAnyUIForeground())
                p.OnGamepadLeftTrigger(0.0);
            else
                p.OnGamepadLeftTrigger(Delta);
            return false;
        }
        if (Key == IK_JoyR)
        {
            root = ControllerRootWindow(p.rootWindow);
            // Same nav-controller intercept as IK_JoyZ above.
            if (root != None && root.activeNav != None
                && root.activeNav.HandleTrigger(1, Delta))
                return true;
            if (root != None && root.IsAnyUIForeground())
                p.OnGamepadRightTrigger(0.0);
            else
                p.OnGamepadRightTrigger(Delta);
            return false;
        }
        if (Key == IK_JoyX || Key == IK_JoyY)
        {
            root = ControllerRootWindow(p.rootWindow);
            // Sticky wheel (belt-assign from a persona screen): L-stick
            // navigates slots. The non-sticky weapon/aug wheels (held
            // with LB/RB during gameplay) deliberately leave L-stick on
            // player movement; their navigation is R-stick (next block).
            // Gate on bSticky to distinguish. Using bOpen (rather than
            // IsViewLocked()) also keeps the post-close grace window —
            // R-stick-only — from holding L-stick away from movement.
            if (root != None && root.radial != None && root.radial.bOpen && root.radial.bSticky)
            {
                if (Key == IK_JoyX)
                    root.radial.UpdateStick(Delta, root.radial.stickY);
                else
                    root.radial.UpdateStick(root.radial.stickX, Delta);
                return true;  // consumed — suppress binding-system movement
            }
        }

        if (Key == IK_JoyX)
        {
            p.OnGamepadLeftStick(Delta, p.GamepadStickY);
            return false;
        }
        if (Key == IK_JoyY)
        {
            p.OnGamepadLeftStick(p.GamepadStickX, Delta);
            return false;
        }
        if (Key == IK_JoyU || Key == IK_JoyV)
        {
            root = ControllerRootWindow(p.rootWindow);
            if (root != None && root.radial != None && root.radial.IsViewLocked())
            {
                // UpdateStick short-circuits when !bOpen, so calling it during
                // the post-close grace window is a no-op past the field write.
                if (Key == IK_JoyU)
                    root.radial.UpdateStick(Delta, root.radial.stickY);
                else
                    root.radial.UpdateStick(root.radial.stickX, Delta);
                return true;  // consumed — suppress binding-system camera-pan
            }

            // No wheel open. If a menu screen owns the focus and its
            // nav controller accepts R-stick scroll, forward and consume.
            if (root != None && root.activeNav != None && Key == IK_JoyV)
            {
                if (root.activeNav.HandleScroll(Delta))
                    return true;  // consumed — suppress binding-system camera-pan
            }
            // Same for R-stick X (Security-screen camera yaw).
            if (root != None && root.activeNav != None && Key == IK_JoyU)
            {
                if (root.activeNav.HandleScrollX(Delta))
                    return true;  // consumed — suppress binding-system camera-pan
            }
        }
    }
    else if (Key == IK_Joy9)
    {
        if (Action == IST_Press)
        {
            p.OnGamepadCrouchPress();
            return true;
        }
        if (Action == IST_Release)
        {
            p.OnGamepadCrouchRelease();
            return true;
        }
    }
    else if (Key == IK_Joy5)
    {
        if (Action == IST_Press)
        {
            // Block wheel-open while any UI screen owns the foreground
            // (conversation, datacube, persona menu, etc.) — otherwise
            // the wheel opens *behind* the UI and the synthesised
            // release on close fires an unintended equip.
            root = ControllerRootWindow(p.rootWindow);
            if (!p.bGamepadLBHeld && !p.bGamepadRBHeld && !p.RestrictInput()
                && root != None && !root.IsAnyUIForeground())
            {
                p.OnGamepadWeaponWheel(true);
                if (root.radial != None)
                    root.radial.Open(root.radial.WM_Weapon);
                return true;
            }
            // A UI screen owns the foreground: LB is not the weapon
            // wheel here — it belongs to the active nav controller
            // (e.g. network-terminal LB/RB pane cycling, read in
            // ControllerRootWindow.VirtualKeyPressed). Terminals are
            // pushed bNoPause=True, so the console stays out of
            // state Menuing and this class-scoped handler — not the
            // Menuing override — is what runs; an unconditional
            // return true would consume LB before the window system
            // ever sees it. Fall through to Super.KeyEvent so it
            // reaches VirtualKeyPressed, exactly as A (IK_Joy1) does.
            // (Restricted input / a wheel already held still consume —
            // no nav use there.)
            if (root != None && root.IsAnyUIForeground())
                return Super.KeyEvent(Key, Action, Delta);
            return true;
        }
        if (Action == IST_Release)
        {
            if (p.bGamepadLBHeld)
            {
                root = ControllerRootWindow(p.rootWindow);
                p.OnGamepadWeaponWheel(false);
                if (root != None && root.radial != None)
                    root.radial.Close(true);
                return true;
            }
            // No weapon wheel was open (UI foreground gated it off).
            // Mirror the press: pass the release through so press and
            // release stay symmetric for the window system.
            root = ControllerRootWindow(p.rootWindow);
            if (root != None && root.IsAnyUIForeground())
                return Super.KeyEvent(Key, Action, Delta);
            return true;
        }
    }
    else if (Key == IK_Joy6)
    {
        if (Action == IST_Press)
        {
            // Same UI-foreground gate as Joy5 — see comment above.
            root = ControllerRootWindow(p.rootWindow);
            if (!p.bGamepadLBHeld && !p.bGamepadRBHeld && !p.RestrictInput()
                && root != None && !root.IsAnyUIForeground())
            {
                p.OnGamepadAugWheel(true);
                if (root.radial != None)
                    root.radial.Open(root.radial.WM_Aug);
                return true;
            }
            // UI foreground: RB belongs to the active nav controller,
            // not the aug wheel — fall through. See the Joy5 press
            // comment for the full rationale.
            if (root != None && root.IsAnyUIForeground())
                return Super.KeyEvent(Key, Action, Delta);
            return true;
        }
        if (Action == IST_Release)
        {
            if (p.bGamepadRBHeld)
            {
                root = ControllerRootWindow(p.rootWindow);
                p.OnGamepadAugWheel(false);
                if (root != None && root.radial != None)
                    root.radial.Close(true);
                return true;
            }
            // No aug wheel was open — mirror the press, pass through.
            root = ControllerRootWindow(p.rootWindow);
            if (root != None && root.IsAnyUIForeground())
                return Super.KeyEvent(Key, Action, Delta);
            return true;
        }
    }

    return Super.KeyEvent(Key, Action, Delta);
}

//=============================================================================
// state Menuing — selective axis pass-through.
//
// UI-paused state. Entered by PlayerPawn.ShowMenu() from
// DeusExRootWindow.UIPauseGame(), which fires from every PushWindow that
// doesn't pass bNoPause=True (persona screens, conversations launched via
// PushWindow, datacubes, computer terminals).
//
// Stock Console.state Menuing.KeyEvent (Engine/Classes/Console.uc:731)
// short-circuits on Action != IST_Press, dropping every axis event. Per
// UE1 state-scoped dispatch (CLAUDE.md "State-scoped dispatch"), the
// parent's state-scoped function shadows the child's class-scoped
// override, so the IST_Axis branch of ControllerConsole.KeyEvent — the
// sticky-wheel UpdateStick path and the nav-controller HandleScroll
// path — never runs while a Menuing-state menu owns the foreground.
//
// Forward stick axes (X/Y/U/V) to the class-scoped (global) handler so
// those consumers receive their events. Triggers (IK_JoyZ/IK_JoyR) are
// deliberately not forwarded: OnGamepadRightTrigger raises bFire and
// OnGamepadLeftTrigger toggles scope/laser, and Fire()'s RestrictInput()
// guard does not catch the menu-open case (it only fires for
// Interpolating/Dying/Paralyzed). Non-axis events stay on stock Menuing
// semantics: Super.KeyEvent resolves to Console.state Menuing.KeyEvent,
// preserving MainMenu.MenuProcessInput dispatch and the Scrollback
// reset.
//
// This is the same idiom as stock state Typing.KeyEvent at
// Engine/Classes/Console.uc:635, which calls global.KeyEvent so the
// subclass's KeyEvent sees typing-state events.
//=============================================================================
state Menuing
{
    function bool KeyEvent(EInputKey Key, EInputAction Action, FLOAT Delta)
    {
        if (Action == IST_Axis
            && (Key == IK_JoyX || Key == IK_JoyY
             || Key == IK_JoyU || Key == IK_JoyV))
            return global.KeyEvent(Key, Action, Delta);
        return Super.KeyEvent(Key, Action, Delta);
    }
}
