//=============================================================================
// MenuChoice_StickDeadzoneLeft -- binds the base row to StickDeadzoneLeft.
//=============================================================================
class MenuChoice_StickDeadzoneLeft extends MenuChoice_StickDeadzone;

function int  GetSettingValue()         { return Class'ControllerSettings'.Default.StickDeadzoneLeft; }
function      SetSettingValue(int v)    { Class'ControllerSettings'.Default.StickDeadzoneLeft = v; }
function byte GetStickIdx()             { return 0; }

defaultproperties
{
    actionText="Left stick deadzone"
    helpText="Radial deadzone in raw XInput units. Below this magnitude the stick is treated as centered; above it, output is rescaled to start at 0. Range 0-10000.  *  LB/RB to adjust faster"
}
