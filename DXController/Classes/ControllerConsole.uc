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

    if (Action == IST_Axis)
    {
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
            if (root != None && root.radial != None && root.radial.bOpen)
            {
                if (Key == IK_JoyU)
                    root.radial.UpdateStick(Delta, root.radial.stickY);
                else
                    root.radial.UpdateStick(root.radial.stickX, Delta);
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
            if (!p.bGamepadLBHeld && !p.bGamepadRBHeld && !p.RestrictInput())
            {
                root = ControllerRootWindow(p.rootWindow);
                p.OnGamepadWeaponWheel(true);
                if (root != None && root.radial != None)
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
            if (!p.bGamepadLBHeld && !p.bGamepadRBHeld && !p.RestrictInput())
            {
                root = ControllerRootWindow(p.rootWindow);
                p.OnGamepadAugWheel(true);
                if (root != None && root.radial != None)
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
