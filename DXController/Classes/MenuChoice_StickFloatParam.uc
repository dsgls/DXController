//=============================================================================
// MenuChoice_StickFloatParam -- base for curve-parameter rows.
//
// Cycles a float in fineStep / coarseStep increments over [minVal, maxVal],
// clamped to range. Display is fixed-decimal-places (decimals=1 for "2.0",
// decimals=2 for "0.60"). appliesTo names the curve type this row is
// relevant for ('Power' / 'Expo' / 'Sigmoid'); the parent screen uses it
// to hide rows that don't apply to the currently-selected curve.
//
// Subclasses override Get/Set to bind to a specific ControllerSettings
// float field and set min/max/step/decimals/appliesTo in defaultproperties.
//
// Display path note: MenuUIChoiceEnum renders via UpdateInfoButton ->
// btnInfo.SetButtonText(enumText[currentValue]). We override
// UpdateInfoButton to write the formatted float instead.
//=============================================================================
class MenuChoice_StickFloatParam extends MenuUIChoiceEnum
    abstract;

var float minVal, maxVal, fineStep, coarseStep;
var byte  decimals;          // 1 = "2.0", 2 = "0.60"
var name  appliesTo;         // 'Power', 'Expo', or 'Sigmoid'

// Abstract hooks -- subclasses must override.
function float GetSettingValue()              { return 0.0; }
function       SetSettingValue(float v)       { }
function byte  GetStickIdx()                  { return 0; }

function NotifyParent()
{
    local MenuScreenController parent;
    parent = MenuScreenController(GetParent().GetParent());
    if (parent != None)
        parent.OnCurveParamChanged(GetStickIdx());
}

function LoadSetting()
{
    // Stash an int approximation in the choice value so the base class's
    // value model has something coherent; UpdateInfoButton reads the
    // actual float via GetSettingValue.
    SetValue(int(GetSettingValue() * 100));
}

// Live-apply: nothing to batch save.
function SaveSetting()
{
}

// Format the float to `decimals` places. UE1 has no printf, so split
// into integer + fractional parts and pad the fractional with leading
// zeros.
function string FormatValue()
{
    local float v;
    local int scaled, intPart, fracPart, divisor, i;
    local string frac;

    v = GetSettingValue();
    divisor = 1;
    for (i = 0; i < decimals; i++) divisor *= 10;

    scaled = int(v * divisor + 0.5);
    if (scaled < 0) scaled = 0;
    intPart  = scaled / divisor;
    fracPart = scaled - (intPart * divisor);

    frac = string(fracPart);
    while (Len(frac) < decimals) frac = "0" $ frac;

    return string(intPart) $ "." $ frac;
}

function UpdateInfoButton()
{
    if (btnInfo != None)
        btnInfo.SetButtonText(FormatValue());
}

function ApplyAndReload(float newVal)
{
    if (newVal < minVal) newVal = minVal;
    if (newVal > maxVal) newVal = maxVal;

    SetSettingValue(newVal);
    Class'ControllerSettings'.static.StaticSaveConfig();

    if (player != None)
        player.ConsoleCommand("XInputReload");

    SetValue(int(newVal * 100));
    NotifyParent();
}

function CycleNextValue()
{
    ApplyAndReload(GetSettingValue() + fineStep);
    PlaySound(Sound'Menu_Press', 0.25);
}

function CyclePreviousValue()
{
    ApplyAndReload(GetSettingValue() - fineStep);
    PlaySound(Sound'Menu_Press', 0.25);
}

function CycleCoarseNext()
{
    ApplyAndReload(GetSettingValue() + coarseStep);
    PlaySound(Sound'Menu_Press', 0.25);
}

function CycleCoarsePrev()
{
    ApplyAndReload(GetSettingValue() - coarseStep);
    PlaySound(Sound'Menu_Press', 0.25);
}
