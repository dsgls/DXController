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

event bool KeyEvent(EInputKey Key, EInputAction Action, FLOAT Delta)
{
    local DeusExPlayer p;
    local ControllerRootWindow root;

    if (Viewport != None)
        p = DeusExPlayer(Viewport.Actor);
    if (p == None)
        return Super.KeyEvent(Key, Action, Delta);

    // Notify root window so it can flip from CM_Mouse → CM_Gamepad.
    if (p.rootWindow != None)
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

        if (Key == IK_JoyZ)
        {
            p.OnGamepadLeftTrigger(Delta);
            return false;
        }
        if (Key == IK_JoyR)
        {
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
            }
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
            }
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
            }
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
            }
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
