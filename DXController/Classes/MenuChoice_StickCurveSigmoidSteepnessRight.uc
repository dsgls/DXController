//=============================================================================
// MenuChoice_StickCurveSigmoidSteepnessRight -- binds the base row to
// StickCurveSigmoidSteepnessRight.
//=============================================================================
class MenuChoice_StickCurveSigmoidSteepnessRight extends MenuChoice_StickFloatParam;

function float GetSettingValue()        { return Class'ControllerSettings'.Default.StickCurveSigmoidSteepnessRight; }
function       SetSettingValue(float v) { Class'ControllerSettings'.Default.StickCurveSigmoidSteepnessRight = v; }
function byte  GetStickIdx()            { return 1; }

defaultproperties
{
    actionText="Right sigmoid steepness"
    helpText="Sharpness of the S-curve. Higher = sharper transition between dead zone and full speed.  *  LB/RB to adjust faster"
    minVal=1.0
    maxVal=12.0
    fineStep=0.5
    coarseStep=5.0
    decimals=1
    appliesTo=Sigmoid
}
