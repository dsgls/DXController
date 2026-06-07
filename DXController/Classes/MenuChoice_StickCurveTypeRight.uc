//=============================================================================
// MenuChoice_StickCurveTypeRight -- binds the base row to StickCurveRight.
//=============================================================================
class MenuChoice_StickCurveTypeRight extends MenuChoice_StickCurveType;

function string GetSettingValue()           { return Class'ControllerSettings'.Default.StickCurveRight; }
function        SetSettingValue(string v)   { Class'ControllerSettings'.Default.StickCurveRight = v; }
function byte   GetStickIdx()               { return 1; }

defaultproperties
{
    actionText="Right stick curve"
    helpText="Response shape applied after the deadzone. Power = u^k; Expo = blend of linear and cubic; Sigmoid = S-shape with adjustable midpoint."
}
