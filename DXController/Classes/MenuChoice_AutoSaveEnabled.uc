//=============================================================================
// MenuChoice_AutoSaveEnabled -- On/Off toggle for AutoSaveManager.bEnabled.
//
// Writes Class'AutoSaveManager'.Default.bEnabled and persists via
// StaticSaveConfig. The live AutoSaveManager (owned by ControllerRootWindow)
// reads Default.bEnabled each Poll, so the change applies immediately with no
// restart and no native reload. Uses the default enum render path
// (enumText[currentValue]) -- no UpdateInfoButton override needed.
//=============================================================================
class MenuChoice_AutoSaveEnabled extends MenuUIChoiceEnum;

const OFF = 0;
const ON  = 1;

function LoadSetting()
{
    if (Class'AutoSaveManager'.Default.bEnabled)
        SetValue(ON);
    else
        SetValue(OFF);
}

// Live-apply: nothing to batch save.
function SaveSetting()
{
}

function ApplyAndSave(int newIdx)
{
    if (newIdx != OFF)
        newIdx = ON;

    Class'AutoSaveManager'.Default.bEnabled = (newIdx == ON);
    Class'AutoSaveManager'.static.StaticSaveConfig();

    SetValue(newIdx);
}

function CycleNextValue()
{
    if (Class'AutoSaveManager'.Default.bEnabled)
        ApplyAndSave(OFF);
    else
        ApplyAndSave(ON);
    PlaySound(Sound'Menu_Press', 0.25);
}

// Two-state toggle: previous == next.
function CyclePreviousValue()
{
    CycleNextValue();
}

// No coarse step for a toggle; route LB/RB through the same flip.
function CycleCoarseNext() { CycleNextValue(); }
function CycleCoarsePrev() { CycleNextValue(); }

defaultproperties
{
    enumText(0)="Off"
    enumText(1)="On"
    actionText="Autosave"
    helpText="Periodically saves your game during play. Writing each save can cause a brief stutter - turn this off if it bothers you."
}
