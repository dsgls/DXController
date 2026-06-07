//=============================================================================
// MenuChoice_StickCurveExpoRight -- binds the base row to StickCurveExpoRight.
//=============================================================================
class MenuChoice_StickCurveExpoRight extends MenuChoice_StickFloatParam;

function float GetSettingValue()        { return Class'ControllerSettings'.Default.StickCurveExpoRight; }
function       SetSettingValue(float v) { Class'ControllerSettings'.Default.StickCurveExpoRight = v; }
function byte  GetStickIdx()            { return 1; }

defaultproperties
{
    actionText="Right expo"
    helpText="Expo blend e: 0.0 = linear, 1.0 = full cubic. Higher = more sensitive near full deflection.  *  LB/RB to adjust faster"
    minVal=0.0
    maxVal=1.0
    fineStep=0.05
    coarseStep=0.5
    decimals=2
    appliesTo=Expo
}
