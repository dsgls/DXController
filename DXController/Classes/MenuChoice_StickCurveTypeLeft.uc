//=============================================================================
// MenuChoice_StickCurveTypeLeft -- binds the base row to StickCurveLeft.
//=============================================================================
class MenuChoice_StickCurveTypeLeft extends MenuChoice_StickCurveType;

function string GetSettingValue()           { return Class'ControllerSettings'.Default.StickCurveLeft; }
function        SetSettingValue(string v)   { Class'ControllerSettings'.Default.StickCurveLeft = v; }
function byte   GetStickIdx()               { return 0; }

defaultproperties
{
    actionText="Left stick &curve"
    helpText="Response shape applied after the deadzone. Power = u^k; Expo = blend of linear and cubic; Sigmoid = S-shape with adjustable midpoint."
}
