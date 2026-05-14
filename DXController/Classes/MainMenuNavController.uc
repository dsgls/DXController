//=============================================================================
// MainMenuNavController — D-pad navigation for the main-menu screen family.
//
// Shared across every MenuUIScreenWindow subclass that uses the standard
// choices[] pattern (Options, Display, Sound, Controls, AdjustColors, etc.).
// Children (MenuUIChoice instances) live inside screen.winClient, not the
// screen window itself.
//
// A button:      activates the focused choice (cycles enum/slider, or
//                navigates for action choices — same as clicking btnAction).
// D-pad up/down: moves focus among choices.
// D-pad left:    CyclePreviousValue on the focused choice (no-op on actions).
// D-pad right:   CycleNextValue on the focused choice (no-op on actions).
//=============================================================================
class MainMenuNavController extends MenuNavController;

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

// Walk winClient's child list and collect MenuUIChoice instances in order.
// Children are stored in z-order (GetTopChild = top of z-stack = last
// created); the standard screens add choices in ascending Y order, so
// this enumerates them bottom-to-top visually. We reverse by walking
// GetLowerSibling to get the creation/display order correct.
function CollectChoices()
{
    local MenuUIScreenWindow menuScreen;
    local Window c;

    choiceCount = 0;
    if (screen == None)
        return;

    // Cast to MenuUIScreenWindow to reach winClient. If the screen is not
    // actually a MenuUIScreenWindow subclass this returns None and we
    // enumerate nothing (safe no-op).
    menuScreen = MenuUIScreenWindow(screen);
    if (menuScreen == None || menuScreen.winClient == None)
        return;

    // GetTopChild() returns children in reverse-declared (top-of-z-stack) order.
    // We collect them as-is; navigation is uniform either way.
    c = menuScreen.winClient.GetTopChild();
    while (c != None && choiceCount < ArrayCount(choices))
    {
        if (c.IsA('MenuUIChoice'))
        {
            choices[choiceCount] = MenuUIChoice(c);
            choiceCount++;
        }
        c = c.GetLowerSibling();
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

    // Only the A button activates in main-menu.
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
