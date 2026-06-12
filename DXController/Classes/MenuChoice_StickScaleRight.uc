//=============================================================================
// MenuChoice_StickScaleRight -- binds the base row to StickScaleRight,
// the post-curve output scale for the right stick. Unlike the curve-param
// rows it applies to every curve type, so MenuScreenController places it
// with PlaceRow (always visible) and appliesTo stays unset.
//=============================================================================
class MenuChoice_StickScaleRight extends MenuChoice_StickFloatParam;

function float GetSettingValue()        { return Class'ControllerSettings'.Default.StickScaleRight; }
function       SetSettingValue(float v) { Class'ControllerSettings'.Default.StickScaleRight = v; }
function byte  GetStickIdx()            { return 1; }

defaultproperties
{
    actionText="Right stick sensitivity"
    helpText="Scales look speed. At 1.00 full deflection turns at the game's normal maximum rate; lower values slow it down.  *  LB/RB to adjust faster"
    minVal=0.10
    maxVal=1.00
    fineStep=0.05
    coarseStep=0.25
    decimals=2
}
