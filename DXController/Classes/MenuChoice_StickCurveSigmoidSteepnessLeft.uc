//=============================================================================
// MenuChoice_StickCurveSigmoidSteepnessLeft -- binds the base row to
// StickCurveSigmoidSteepnessLeft.
//=============================================================================
class MenuChoice_StickCurveSigmoidSteepnessLeft extends MenuChoice_StickFloatParam;

function float GetSettingValue()        { return Class'ControllerSettings'.Default.StickCurveSigmoidSteepnessLeft; }
function       SetSettingValue(float v) { Class'ControllerSettings'.Default.StickCurveSigmoidSteepnessLeft = v; }
function byte  GetStickIdx()            { return 0; }

defaultproperties
{
    actionText="Left sigmoid &steepness"
    helpText="Sharpness of the S-curve. Higher = sharper transition between dead zone and full speed.  *  LB/RB to adjust faster"
    minVal=1.0
    maxVal=12.0
    fineStep=0.5
    coarseStep=5.0
    decimals=1
    appliesTo=Sigmoid
}
