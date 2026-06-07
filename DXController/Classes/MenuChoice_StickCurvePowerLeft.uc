//=============================================================================
// MenuChoice_StickCurvePowerLeft -- binds the base row to StickCurvePowerLeft.
//=============================================================================
class MenuChoice_StickCurvePowerLeft extends MenuChoice_StickFloatParam;

function float GetSettingValue()        { return Class'ControllerSettings'.Default.StickCurvePowerLeft; }
function       SetSettingValue(float v) { Class'ControllerSettings'.Default.StickCurvePowerLeft = v; }
function byte  GetStickIdx()            { return 0; }

defaultproperties
{
    actionText="Left power"
    helpText="Exponent k in u^k. 1.0 = linear; >1 = finer control near center; <1 = snappier near center.  *  LB/RB to adjust faster"
    minVal=0.1
    maxVal=10.0
    fineStep=0.1
    coarseStep=1.0
    decimals=1
    appliesTo=Power
}
