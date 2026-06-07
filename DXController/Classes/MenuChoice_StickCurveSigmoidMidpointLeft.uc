//=============================================================================
// MenuChoice_StickCurveSigmoidMidpointLeft -- binds the base row to
// StickCurveSigmoidMidpointLeft.
//=============================================================================
class MenuChoice_StickCurveSigmoidMidpointLeft extends MenuChoice_StickFloatParam;

function float GetSettingValue()        { return Class'ControllerSettings'.Default.StickCurveSigmoidMidpointLeft; }
function       SetSettingValue(float v) { Class'ControllerSettings'.Default.StickCurveSigmoidMidpointLeft = v; }
function byte  GetStickIdx()            { return 0; }

defaultproperties
{
    actionText="Left sigmoid midpoint"
    helpText="X position of the steep region. Lower = sensitive earlier (more aggressive overall).  *  LB/RB to adjust faster"
    minVal=0.15
    maxVal=0.85
    fineStep=0.05
    coarseStep=0.5
    decimals=2
    appliesTo=Sigmoid
}
