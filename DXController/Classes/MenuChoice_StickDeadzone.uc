//=============================================================================
// MenuChoice_StickDeadzone -- base for the per-stick deadzone rows.
//
// Cycles an int (SHORT-clamped) value in 10-unit (fine) or 100-unit (coarse)
// increments over [0, 10000]. The launcher's hard limit is 32767 but even a
// very worn controller is unlikely to need past ~5000; 10000 is a generous
// upper bound that keeps the coarse step usable.
//
// Subclasses override Get/Set to bind to either StickDeadzoneLeft or
// StickDeadzoneRight on ControllerSettings.
//
// Display path note: MenuUIChoiceEnum has no GetDisplayText hook; it renders
// via UpdateInfoButton -> btnInfo.SetButtonText(enumText[currentValue]).
// We override UpdateInfoButton to write the raw int instead.
//=============================================================================
class MenuChoice_StickDeadzone extends MenuUIChoiceEnum
    abstract;

const FINE_STEP   = 10;
const COARSE_STEP = 100;
const MIN_VAL     = 0;
const MAX_VAL     = 10000;

// Abstract hooks -- subclasses must override.
function int  GetSettingValue()         { return 0; }
function      SetSettingValue(int v)    { }
function byte GetStickIdx()             { return 0; }

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
        btnInfo.SetButtonText(string(currentValue));
}

function ApplyAndReload(int newVal)
{
    if (newVal < MIN_VAL) newVal = MIN_VAL;
    if (newVal > MAX_VAL) newVal = MAX_VAL;

    SetSettingValue(newVal);
    Class'ControllerSettings'.static.StaticSaveConfig();

    if (player != None)
        player.ConsoleCommand("XInputReload");

    SetValue(newVal);
    NotifyParent();
}

function NotifyParent()
{
    local MenuScreenController parent;
    parent = MenuScreenController(GetParent().GetParent());
    if (parent != None)
        parent.OnDeadzoneChanged(GetStickIdx());
}

function CycleNextValue()
{
    ApplyAndReload(GetSettingValue() + FINE_STEP);
    PlaySound(Sound'Menu_Press', 0.25);
}

function CyclePreviousValue()
{
    ApplyAndReload(GetSettingValue() - FINE_STEP);
    PlaySound(Sound'Menu_Press', 0.25);
}

function CycleCoarseNext()
{
    ApplyAndReload(GetSettingValue() + COARSE_STEP);
    PlaySound(Sound'Menu_Press', 0.25);
}

function CycleCoarsePrev()
{
    ApplyAndReload(GetSettingValue() - COARSE_STEP);
    PlaySound(Sound'Menu_Press', 0.25);
}
