//=============================================================================
// OptionsNavController — D-pad navigation for MenuUIScreenWindow subclasses
// that use the standard choices[] pattern.
//
// Wired screens: MenuScreenOptions, MenuScreenDisplay, MenuScreenSound,
// MenuScreenControls, MenuScreenAdjustColors, MenuScreenBrightness.
// Children (MenuUIChoice instances) live inside screen.winClient, not the
// screen window itself.
//
// A button:      activates the focused choice (cycles enum/slider, or
//                navigates for action choices — same as clicking btnAction).
// D-pad up/down: moves focus among choices.
// D-pad left:    CyclePreviousValue on the focused choice (no-op on actions).
// D-pad right:   CycleNextValue on the focused choice (no-op on actions).
//=============================================================================
class OptionsNavController extends MenuNavController;

// Collected once on Attach. Re-collected via CollectChoices() if needed.
// MenuUIScreenWindow supports up to 13 choices[] entries; 32 is a safe
// ceiling that covers any future expansion.
var MenuUIChoice choices[32];
var int          choiceCount;

function InitFocus()
{
    CollectChoices();
    focusIndex = FindFirstEnabled();
    if (focusIndex >= 0)
        focused = choices[focusIndex];
    else
        focused = None;
}

// Walk winClient's child list and collect MenuUIChoice instances in
// creation order (== visual top-to-bottom order). MenuUIScreenWindow
// creates choices via winClient.NewChild in declaration order and
// positions each at Y = choiceStartY + i * choiceVerticalGap, so the
// first-created choice sits at the visual top and the last-created at
// the visual bottom.
//
// z-stack ordering is the OPPOSITE: NewChild puts the new child at the
// top of z (drawn last, on top), so the first-created choice is at the
// bottom of z. We walk z-bottom → z-top via GetBottomChild +
// GetHigherSibling to traverse in creation/visual order. (Walking
// GetTopChild + GetLowerSibling produces reverse order, which makes
// D-pad-down step visually UP — bug fixed here.)
function CollectChoices()
{
    local MenuUIScreenWindow menuScreen;
    local Window c;

    choiceCount = 0;
    if (screen == None)
        return;

    menuScreen = MenuUIScreenWindow(screen);
    if (menuScreen == None || menuScreen.winClient == None)
        return;

    c = menuScreen.winClient.GetBottomChild();
    while (c != None && choiceCount < ArrayCount(choices))
    {
        if (c.IsA('MenuUIChoice'))
        {
            choices[choiceCount] = MenuUIChoice(c);
            choiceCount++;
        }
        c = c.GetHigherSibling();
    }
}

function int FindFirstEnabled()
{
    local int i;
    for (i = 0; i < choiceCount; i++)
    {
        if (IsEnabled(choices[i]))
            return i;
    }
    return -1;
}

// A choice is enabled if its window is sensitive (can take input).
// Window.bIsSensitive is a const bool updated by SetSensitivity/EnableWindow.
function bool IsEnabled(MenuUIChoice w)
{
    if (w == None)
        return false;
    return w.bIsSensitive;
}

function bool HandleDPad(int dx, int dy)
{
    local int step, newIdx, i;

    if (choiceCount == 0)
        return true;    // consume, nothing to do

    // Up/Down: move focus.
    if (dy != 0)
    {
        // dy > 0 = d-pad down = move to next (higher-index) choice.
        if (dy > 0)
            step = 1;
        else
            step = -1;
        newIdx = focusIndex;
        for (i = 0; i < choiceCount; i++)
        {
            newIdx = (newIdx + step + choiceCount) % choiceCount;
            if (IsEnabled(choices[newIdx]))
            {
                focusIndex = newIdx;
                focused = choices[focusIndex];
                class'DXControllerDebug'.static.DebugLog(
                    "DXC-NAV FOCUS idx=" $ string(focusIndex));
                return true;
            }
        }
        return true;    // no enabled choice found, consume anyway
    }

    // Left/Right: cycle the focused choice's value.
    // CyclePreviousValue / CycleNextValue are no-ops on MenuUIChoiceAction,
    // so this is safe to call unconditionally.
    // Cast `focused` (Window) to MenuUIChoice to reach the cycle methods.
    if (dx != 0 && focused != None && IsEnabled(MenuUIChoice(focused)))
    {
        if (dx < 0)
            MenuUIChoice(focused).CyclePreviousValue();
        else
            MenuUIChoice(focused).CycleNextValue();
        return true;
    }

    return true;
}

function bool HandleActivate(byte button)
{
    local MenuUIChoice focusedChoice;

    // Only the A button activates the focused choice.
    // Other face buttons (X=IK_Joy3, Y=IK_Joy4) and R-stick (IK_Joy10):
    // consume and no-op so they don't fall through to vanilla handling.
    if (button != 200)    // IK_Joy1 (A) = 0xC8 = 200 — enum not reachable from Object scope
        return true;

    focusedChoice = MenuUIChoice(focused);
    if (focusedChoice == None || !IsEnabled(focusedChoice))
        return true;

    // Pressing btnAction on any MenuUIChoice subclass:
    //   MenuUIChoiceAction  → ProcessMenuAction (navigate to screen/menu)
    //   MenuUIChoiceEnum    → CycleNextValue (cycle enum)
    //   MenuUIChoiceSlider  → CycleNextValue (advance slider one tick)
    // This mirrors what a left-click on the choice button does.
    if (focusedChoice.btnAction != None)
        focusedChoice.btnAction.PressButton();

    return true;
}

defaultproperties
{
    bAllowRepeat=True
}
