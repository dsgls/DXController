//=============================================================================
// MenuChoice_StickCurveSigmoidMidpointRight -- binds the base row to
// StickCurveSigmoidMidpointRight.
//=============================================================================
class MenuChoice_StickCurveSigmoidMidpointRight extends MenuChoice_StickFloatParam;

function float GetSettingValue()        { return Class'ControllerSettings'.Default.StickCurveSigmoidMidpointRight; }
function       SetSettingValue(float v) { Class'ControllerSettings'.Default.StickCurveSigmoidMidpointRight = v; }
function byte  GetStickIdx()            { return 1; }

defaultproperties
{
    actionText="Right sigmoid midpoint"
    helpText="X position of the steep region. Lower = sensitive earlier (more aggressive overall).  *  LB/RB to adjust faster"
    minVal=0.15
    maxVal=0.85
    fineStep=0.05
    coarseStep=0.5
    decimals=2
    appliesTo=Sigmoid
}
