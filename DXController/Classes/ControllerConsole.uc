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
        // Bug 3 diagnostic: log L-stick / R-stick events when the radial is
        // open/sticky or a nav controller is active, so we can tell whether
        // axis events reach Console.KeyEvent at all during menu mode.
        // Filter |Delta|>100 to skip centring noise; only the four player
        // sticks (X/Y/U/V) are interesting.
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
            // Sticky belt-assign wheel: persona screen owns the foreground,
            // so IsViewLocked() is false. bOpen+bSticky is the unambiguous
            // signal that the wheel is the intended L-stick consumer.
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
