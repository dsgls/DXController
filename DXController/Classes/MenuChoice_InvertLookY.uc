//=============================================================================
// MenuChoice_InvertLookY -- No/Yes toggle for ControllerSettings.InvertLookY.
//
// The launcher owns the inversion (it negates the raw right-stick Y before
// emitting IK_JoyV), so the change needs a GamepadReload to take effect.
// Inversion does not change the response curve, so the previews are not
// refreshed. Uses the default enum render path (enumText[currentValue]).
//=============================================================================
class MenuChoice_InvertLookY extends MenuUIChoiceEnum;

const NO  = 0;
const YES = 1;

function LoadSetting()
{
    if (Class'ControllerSettings'.Default.InvertLookY)
        SetValue(YES);
    else
        SetValue(NO);
}

// Live-apply: nothing to batch save.
function SaveSetting()
{
}

function ApplyAndReload(int newIdx)
{
    if (newIdx != NO)
        newIdx = YES;

    Class'ControllerSettings'.Default.InvertLookY = (newIdx == YES);
    Class'ControllerSettings'.static.StaticSaveConfig();

    if (player != None)
        player.ConsoleCommand("GamepadReload");

    SetValue(newIdx);
}

function CycleNextValue()
{
    if (Class'ControllerSettings'.Default.InvertLookY)
        ApplyAndReload(NO);
    else
        ApplyAndReload(YES);
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
    enumText(0)="No"
    enumText(1)="Yes"
    actionText="Invert look Y-axis"
    helpText="Pushing the right stick up looks down instead of up. Affects gameplay look and the security camera view."
}
