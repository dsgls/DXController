//=============================================================================
// MenuChoice_StickCurveType -- base for the per-stick curve-type rows.
//
// Cycles the enum {Linear, Power, Expo, Sigmoid}. Saved as a string;
// the launcher matches case-insensitively and falls back to Linear for
// unknown values (DeusExe-XInput/DeusExe/XInput.cpp:43-46).
//
// Subclasses override Get/Set to bind to either StickCurveLeft or
// StickCurveRight on ControllerSettings.
//=============================================================================
class MenuChoice_StickCurveType extends MenuUIChoiceEnum
    abstract;

const CURVE_LINEAR  = 0;
const CURVE_POWER   = 1;
const CURVE_EXPO    = 2;
const CURVE_SIGMOID = 3;

// Abstract hooks -- subclasses must override.
function string GetSettingValue()           { return ""; }
function        SetSettingValue(string v)   { }
function byte   GetStickIdx()               { return 0; }

function int StringToIdx(string s)
{
    if (s ~= "Power")   return CURVE_POWER;
    if (s ~= "Expo")    return CURVE_EXPO;
    if (s ~= "Sigmoid") return CURVE_SIGMOID;
    return CURVE_LINEAR;
}

function string IdxToString(int i)
{
    switch (i)
    {
        case CURVE_POWER:
            return "Power";
        case CURVE_EXPO:
            return "Expo";
        case CURVE_SIGMOID:
            return "Sigmoid";
        default:
            return "Linear";
    }
}

function NotifyParent()
{
    local MenuScreenController parent;
    parent = MenuScreenController(GetParent().GetParent());
    if (parent != None)
        parent.OnCurveTypeChanged(GetStickIdx());
}

function LoadSetting()
{
    SetValue(StringToIdx(GetSettingValue()));
}

// Live-apply: nothing to batch save.
function SaveSetting()
{
}

function ApplyAndReload(int newIdx)
{
    if (newIdx < CURVE_LINEAR)  newIdx = CURVE_LINEAR;
    if (newIdx > CURVE_SIGMOID) newIdx = CURVE_SIGMOID;

    SetSettingValue(IdxToString(newIdx));
    Class'ControllerSettings'.static.StaticSaveConfig();

    if (player != None)
        player.ConsoleCommand("XInputReload");

    SetValue(newIdx);
    NotifyParent();
}

function CycleNextValue()
{
    local int i;
    i = StringToIdx(GetSettingValue()) + 1;
    if (i > CURVE_SIGMOID) i = CURVE_LINEAR;
    ApplyAndReload(i);
    PlaySound(Sound'Menu_Press', 0.25);
}

function CyclePreviousValue()
{
    local int i;
    i = StringToIdx(GetSettingValue()) - 1;
    if (i < CURVE_LINEAR) i = CURVE_SIGMOID;
    ApplyAndReload(i);
    PlaySound(Sound'Menu_Press', 0.25);
}

// Coarse step has no meaning for a 4-element enum; route LB/RB through
// the fine cycle so the row still responds.
function CycleCoarseNext() { CycleNextValue(); }
function CycleCoarsePrev() { CyclePreviousValue(); }

defaultproperties
{
    enumText(0)="Linear"
    enumText(1)="Power"
    enumText(2)="Expo"
    enumText(3)="Sigmoid"
}
