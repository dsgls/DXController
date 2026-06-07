//=============================================================================
// MenuChoice_StickCurveSigmoidStrengthLeft -- binds the base row to
// StickCurveSigmoidStrengthLeft.
//=============================================================================
class MenuChoice_StickCurveSigmoidStrengthLeft extends MenuChoice_StickFloatParam;

function float GetSettingValue()        { return Class'ControllerSettings'.Default.StickCurveSigmoidStrengthLeft; }
function       SetSettingValue(float v) { Class'ControllerSettings'.Default.StickCurveSigmoidStrengthLeft = v; }
function byte  GetStickIdx()            { return 0; }

defaultproperties
{
    actionText="Left sigmoid strength"
    helpText="Dry/wet blend with linear. 0.0 = linear, 1.0 = pure S.  *  LB/RB to adjust faster"
    minVal=0.0
    maxVal=1.0
    fineStep=0.05
    coarseStep=0.5
    decimals=2
    appliesTo=Sigmoid
}
