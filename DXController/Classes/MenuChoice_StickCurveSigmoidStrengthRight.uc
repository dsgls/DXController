//=============================================================================
// MenuChoice_StickCurveSigmoidStrengthRight -- binds the base row to
// StickCurveSigmoidStrengthRight.
//=============================================================================
class MenuChoice_StickCurveSigmoidStrengthRight extends MenuChoice_StickFloatParam;

function float GetSettingValue()        { return Class'ControllerSettings'.Default.StickCurveSigmoidStrengthRight; }
function       SetSettingValue(float v) { Class'ControllerSettings'.Default.StickCurveSigmoidStrengthRight = v; }
function byte  GetStickIdx()            { return 1; }

defaultproperties
{
    actionText="Right sigmoid stren&gth"
    helpText="Dry/wet blend with linear. 0.0 = linear, 1.0 = pure S.  *  LB/RB to adjust faster"
    minVal=0.0
    maxVal=1.0
    fineStep=0.05
    coarseStep=0.5
    decimals=2
    appliesTo=Sigmoid
}
