//=============================================================================
// MenuChoice_StickDeadzoneRight -- binds the base row to StickDeadzoneRight.
//=============================================================================
class MenuChoice_StickDeadzoneRight extends MenuChoice_StickDeadzone;

function int  GetSettingValue()         { return Class'ControllerSettings'.Default.StickDeadzoneRight; }
function      SetSettingValue(int v)    { Class'ControllerSettings'.Default.StickDeadzoneRight = v; }
function byte GetStickIdx()             { return 1; }

defaultproperties
{
    actionText="Right stick deadzone"
    helpText="Radial deadzone in raw XInput units. Below this magnitude the stick is treated as centered; above it, output is rescaled to start at 0. Range 0-10000.  *  LB/RB to adjust faster"
}
