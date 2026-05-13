//=============================================================================
// ControllerConsole — engine Console subclass.
//
// Synthesises press/release for LT (IK_JoyZ -> IK_Joy16) and RT
// (IK_JoyR -> IK_Joy15) from the IST_Axis stream. Hysteresis: press at
// >= 0.5, release at < 0.4. Engine-routed via [Engine.Engine] Console=
// DXController.ControllerConsole in DeusEx.ini.
//=============================================================================
class ControllerConsole extends Console;

const TriggerPressThreshold = 0.5;
const TriggerReleaseThreshold = 0.4;

var bool bLeftTriggerPressed;
var bool bRightTriggerPressed;

event bool KeyEvent(EInputKey Key, EInputAction Action, FLOAT Delta)
{
    if (Action == IST_Axis)
    {
        if (Key == IK_JoyZ)
        {
            if (!bLeftTriggerPressed && Delta >= TriggerPressThreshold)
            {
                bLeftTriggerPressed = true;
                Super.KeyEvent(IK_Joy16, IST_Press, 0.0);
            }
            else if (bLeftTriggerPressed && Delta < TriggerReleaseThreshold)
            {
                bLeftTriggerPressed = false;
                Super.KeyEvent(IK_Joy16, IST_Release, 0.0);
            }
            return false;
        }

        if (Key == IK_JoyR)
        {
            if (!bRightTriggerPressed && Delta >= TriggerPressThreshold)
            {
                bRightTriggerPressed = true;
                Super.KeyEvent(IK_Joy15, IST_Press, 0.0);
            }
            else if (bRightTriggerPressed && Delta < TriggerReleaseThreshold)
            {
                bRightTriggerPressed = false;
                Super.KeyEvent(IK_Joy15, IST_Release, 0.0);
            }
            return false;
        }
    }

    return Super.KeyEvent(Key, Action, Delta);
}

event NotifyLevelChange()
{
    bLeftTriggerPressed = false;
    bRightTriggerPressed = false;
    Super.NotifyLevelChange();
}
