//=============================================================================
// MenuChoice_StickCurveExpoLeft -- binds the base row to StickCurveExpoLeft.
//=============================================================================
class MenuChoice_StickCurveExpoLeft extends MenuChoice_StickFloatParam;

function float GetSettingValue()        { return Class'ControllerSettings'.Default.StickCurveExpoLeft; }
function       SetSettingValue(float v) { Class'ControllerSettings'.Default.StickCurveExpoLeft = v; }
function byte  GetStickIdx()            { return 0; }

defaultproperties
{
    actionText="Left e&xpo"
    helpText="Expo blend e: 0.0 = linear, 1.0 = full cubic. Higher = more sensitive near full deflection.  *  LB/RB to adjust faster"
    minVal=0.0
    maxVal=1.0
    fineStep=0.05
    coarseStep=0.5
    decimals=2
    appliesTo=Expo
}
