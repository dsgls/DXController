//=============================================================================
// OptionsNavController — D-pad navigation for MenuUIScreenWindow subclasses
// that use the standard choices[] pattern, plus the bottom action bar.
//
// Wired screens: MenuScreenOptions, MenuScreenDisplay, MenuScreenSound,
// MenuScreenControls, MenuScreenAdjustColors, MenuScreenBrightness. All
// six have identical action-bar layouts (Cancel / OK / Reset Defaults).
//
// Linear focus cycle:
//   Choice[0] ⇄ Choice[1] ⇄ … ⇄ Choice[last enabled] ⇄ Action bar ⇄ Choice[0]
//
// Inside the action bar (state bInActionBar):
//   D-pad L/R walks [Reset] [OK] [Cancel] in visual order, no wraparound.
//   A presses the focused button (same path as a mouse click).
//   D-pad up exits to the last enabled choice.
//   D-pad down wraps to the first enabled choice.
//
// Inside choices (default state):
//   D-pad up/down moves focus among choices (existing behaviour).
//   D-pad L/R cycles the focused choice's value (existing behaviour).
//   A activates the focused choice (existing behaviour).
//   D-pad down past last enabled choice → enter action bar at primary
//     (OK by codebase convention; first sensitive in L→R as fallback).
//   D-pad up at first enabled choice → enter action bar at primary.
//=============================================================================
class OptionsNavController extends MenuNavController;

// Collected once on Attach. Re-collected via CollectChoices() if needed.
// MenuUIScreenWindow supports up to 13 choices[] entries; 32 is a safe
// ceiling that covers any future expansion.
var MenuUIChoice choices[32];
var int          choiceCount;

// Action-bar state. Populated lazily on first transition into the bar.
var bool                     bInActionBar;
var MenuUIActionButtonWindow actionBtns[5];
var int                      actionBtnCount;
var int                      actionBtnIdx;

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

// Walk choices[] from last to first; return the index of the last
// enabled (sensitive) choice, or -1 if none.
function int FindLastEnabled()
{
    local int i;
    for (i = choiceCount - 1; i >= 0; i--)
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

    if (choiceCount == 0 && !bInActionBar)
        return true;        // nothing to do

    // ---- L/R inside action bar ----
    if (bInActionBar && dx != 0)
    {
        // Re-collect so dynamic sensitivity changes are honoured
        // between presses (defensive — options screens don't toggle
        // their action buttons mid-session, but the cost is trivial).
        class'ActionBarNav'.static.CollectButtons(
            MenuUIWindow(screen), actionBtns, actionBtnCount);
        if (dx < 0)
            actionBtnIdx = class'ActionBarNav'.static.MoveLeft(
                actionBtns, actionBtnCount, actionBtnIdx);
        else
            actionBtnIdx = class'ActionBarNav'.static.MoveRight(
                actionBtns, actionBtnCount, actionBtnIdx);
        if (actionBtnCount > 0)
            focused = actionBtns[actionBtnIdx];
        class'DXControllerDebug'.static.DebugLog(
            "DXC-NAV FOCUS options-ab idx=" $ string(actionBtnIdx));
        return true;
    }

    // ---- Up/Down ----
    if (dy != 0)
    {
        // Down from action bar → wrap to first enabled choice.
        if (bInActionBar && dy > 0)
        {
            bInActionBar = false;
            focusIndex = FindFirstEnabled();
            if (focusIndex >= 0)
                focused = choices[focusIndex];
            else
                focused = None;
            class'DXControllerDebug'.static.DebugLog(
                "DXC-NAV FOCUS options exit-ab → idx=" $ string(focusIndex));
            return true;
        }

        // Up from action bar → last enabled choice.
        if (bInActionBar && dy < 0)
        {
            bInActionBar = false;
            focusIndex = FindLastEnabled();
            if (focusIndex >= 0)
                focused = choices[focusIndex];
            else
                focused = None;
            class'DXControllerDebug'.static.DebugLog(
                "DXC-NAV FOCUS options exit-ab ↑ idx=" $ string(focusIndex));
            return true;
        }

        // Down inside choices: if we're already on the last enabled
        // choice, transition into the action bar. EnterActionBar
        // mutates state on success and is a no-op if no sensitive
        // button exists, so consume unconditionally either way.
        // Edge note: if no choice is enabled at all, FindLastEnabled()
        // returns -1 and focusIndex is also -1 — the match still
        // fires, which is the right outcome (the user has nowhere
        // else to step, so the action bar is the only useful target).
        if (dy > 0 && focusIndex == FindLastEnabled())
        {
            EnterActionBar();
            return true;
        }

        // Up inside choices: if we're on the first enabled choice,
        // transition into the action bar (wrap upward). Same -1==-1
        // edge case as above.
        if (dy < 0 && focusIndex == FindFirstEnabled())
        {
            EnterActionBar();
            return true;
        }

        // Otherwise: step to next/previous enabled choice (existing
        // behaviour preserved).
        if (dy > 0) step = 1; else step = -1;
        newIdx = focusIndex;
        for (i = 0; i < choiceCount; i++)
        {
            newIdx = (newIdx + step + choiceCount) % choiceCount;
            if (IsEnabled(choices[newIdx]))
            {
                focusIndex = newIdx;
                focused = choices[focusIndex];
                class'DXControllerDebug'.static.DebugLog(
                    "DXC-NAV FOCUS options idx=" $ string(focusIndex));
                return true;
            }
        }
        return true;
    }

    // ---- L/R inside choices: cycle the focused choice's value ----
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

// Transition from choices to action-bar focus. Returns true if a
// sensitive action button was found and focused; false if not (caller
// stays on the current choice).
function bool EnterActionBar()
{
    local int primaryIdx;

    class'ActionBarNav'.static.CollectButtons(
        MenuUIWindow(screen), actionBtns, actionBtnCount);
    if (actionBtnCount == 0)
        return false;

    primaryIdx = class'ActionBarNav'.static.FindPrimaryIndex(
        MenuUIWindow(screen), actionBtns, actionBtnCount);
    if (primaryIdx < 0)
        return false;

    bInActionBar = true;
    actionBtnIdx = primaryIdx;
    focused = actionBtns[actionBtnIdx];
    class'DXControllerDebug'.static.DebugLog(
        "DXC-NAV FOCUS options enter-ab idx=" $ string(actionBtnIdx));
    return true;
}

function bool HandleActivate(byte button)
{
    local MenuUIChoice focusedChoice;

    // Only the A button activates. X / Y / R-stick consume no-op.
    // IK_Joy1 (A) = 0xC8 = 200. EInputKey isn't reachable from Object scope.
    if (button != 200)
        return true;

    if (bInActionBar)
    {
        if (focused != None && MenuUIActionButtonWindow(focused) != None
            && MenuUIActionButtonWindow(focused).bIsSensitive)
        {
            MenuUIActionButtonWindow(focused).PressButton();
            class'DXControllerDebug'.static.DebugLog(
                "DXC-NAV ACTIVATE options-ab idx=" $ string(actionBtnIdx));
        }
        return true;
    }

    focusedChoice = MenuUIChoice(focused);
    if (focusedChoice == None || !IsEnabled(focusedChoice))
        return true;

    // Pressing btnAction on any MenuUIChoice subclass:
    //   MenuUIChoiceAction  → ProcessMenuAction (navigate to screen/menu)
    //   MenuUIChoiceEnum    → CycleNextValue (cycle enum)
    //   MenuUIChoiceSlider  → CycleNextValue (advance slider one tick)
    // Same path as a left-click on the choice button.
    if (focusedChoice.btnAction != None)
        focusedChoice.btnAction.PressButton();

    return true;
}

function Detach()
{
    bInActionBar = false;
    actionBtnCount = 0;
    actionBtnIdx = 0;
    Super.Detach();
}

function BuildHints()
{
    AddHint("a", "Select");
    AddHint("b", "Back");
}

defaultproperties
{
    bAllowRepeat=True
}
