//=============================================================================
// MenuChoice_AutoSaveInt -- abstract base for the integer autosave rows
// (interval, max-saves). Cycles an int in fineStep / coarseStep increments,
// clamped to [minVal, maxVal], rendering the raw value with an optional unit
// suffix. Subclasses bind Get/SetSettingValue to one AutoSaveManager config
// field and set the range/steps/suffix in defaultproperties.
//
// Live-apply: writes the field on Class'AutoSaveManager'.Default and persists
// via StaticSaveConfig; the live manager reads Default on its next poll.
//
// Display path note: MenuUIChoiceEnum renders via UpdateInfoButton ->
// btnInfo.SetButtonText(enumText[currentValue]); we override UpdateInfoButton
// to write the formatted int instead (same approach as MenuChoice_StickDeadzone).
//=============================================================================
class MenuChoice_AutoSaveInt extends MenuUIChoiceEnum
    abstract;

var int    minVal, maxVal, fineStep, coarseStep;
var string suffix;

// Abstract hooks -- subclasses must override.
function int GetSettingValue()      { return 0; }
function     SetSettingValue(int v) { }

function LoadSetting()
{
    SetValue(GetSettingValue());
}

// Live-apply: nothing to batch save.
function SaveSetting()
{
}

function UpdateInfoButton()
{
    if (btnInfo != None)
        btnInfo.SetButtonText(string(currentValue) $ suffix);
}

function ApplyAndSave(int newVal)
{
    if (newVal < minVal) newVal = minVal;
    if (newVal > maxVal) newVal = maxVal;

    SetSettingValue(newVal);
    Class'AutoSaveManager'.static.StaticSaveConfig();

    SetValue(newVal);
}

function CycleNextValue()
{
    ApplyAndSave(GetSettingValue() + fineStep);
    PlaySound(Sound'Menu_Press', 0.25);
}

function CyclePreviousValue()
{
    ApplyAndSave(GetSettingValue() - fineStep);
    PlaySound(Sound'Menu_Press', 0.25);
}

function CycleCoarseNext()
{
    ApplyAndSave(GetSettingValue() + coarseStep);
    PlaySound(Sound'Menu_Press', 0.25);
}

function CycleCoarsePrev()
{
    ApplyAndSave(GetSettingValue() - coarseStep);
    PlaySound(Sound'Menu_Press', 0.25);
}
