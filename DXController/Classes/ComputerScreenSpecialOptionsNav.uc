//=============================================================================
// ComputerScreenSpecialOptionsNav — sub-controller for ComputerScreenSpecialOptions.
//
// Rows: [choice_0, choice_1, ..., choice_N, ActionBarRow(btnReturn?, btnLogout)].
// ActionBarRow primary: btnReturn when present (Personal/Security terminals),
// else btnLogout (Public/ATM).
//
// Each populated choice button is its own row. Triggered options stay
// visible but vanilla-disabled; focus stays put, A becomes no-op.
//=============================================================================
class ComputerScreenSpecialOptionsNav extends ComputerScreenNavSub;

var int rowIndex;             // 0..numChoices-1 for choices, numChoices = ActionBarRow
var int numChoices;
var int actionBarIndex;
var MenuUIActionButtonWindow barBtns[5];
var int barCount;

// Cached references to populated choice buttons in declaration order.
var MenuUIChoiceButton choices[4];

function int CountChoices(ComputerScreenSpecialOptions sScr)
{
    local int i, n;
    n = 0;
    for (i = 0; i < ArrayCount(sScr.optionButtons); i++)
    {
        if (sScr.optionButtons[i].btnSpecial != None)
        {
            choices[n] = sScr.optionButtons[i].btnSpecial;
            n++;
        }
    }
    return n;
}

function int FirstSensitiveChoice()
{
    local int i;
    for (i = 0; i < numChoices; i++)
    {
        if (choices[i] != None && choices[i].bIsSensitive)
            return i;
    }
    return -1;
}

function OnEnter(ComputerUIWindow s)
{
    local ComputerScreenSpecialOptions sScr;
    local int firstSensitive;

    Super.OnEnter(s);

    sScr = ComputerScreenSpecialOptions(s);
    if (sScr == None || sScr.winButtonBar == None)
        return;

    numChoices = CountChoices(sScr);
    class'ComputerButtonBarNav'.static.CollectButtons(
        sScr.winButtonBar, barBtns, barCount);

    firstSensitive = FirstSensitiveChoice();
    if (firstSensitive >= 0)
    {
        rowIndex = firstSensitive;
        focused = choices[firstSensitive];
        focusIndex = firstSensitive;
        screen.SetFocusWindow(focused);
    }
    else
    {
        MoveToActionBar();
    }
}

function MoveToActionBar()
{
    local ComputerScreenSpecialOptions sScr;
    local string preferredLabel;

    sScr = ComputerScreenSpecialOptions(screen);
    if (sScr == None)
        return;

    class'ComputerButtonBarNav'.static.CollectButtons(
        sScr.winButtonBar, barBtns, barCount);

    // Primary is btnReturn when present (Personal/Security terminals),
    // else btnLogout (Public/ATM). btnReturn is HALIGN_Left so it lands
    // at barBtns[0] via CollectButtons; FindPrimaryIndex's first-sensitive
    // fallback naturally selects it. Pass ButtonLabelLogout as the
    // preferred label so we match btnLogout on Public/ATM terminals where
    // btnReturn is absent; on Personal/Security the first-sensitive
    // fallback will pick btnReturn (index 0) before reaching btnLogout.
    preferredLabel = sScr.ButtonLabelLogout;
    actionBarIndex = class'ComputerButtonBarNav'.static.FindPrimaryIndex(
        sScr.winButtonBar, barBtns, barCount, preferredLabel);
    if (actionBarIndex < 0)
        actionBarIndex = 0;

    rowIndex = numChoices;  // ActionBarRow lives at index numChoices
    focusIndex = rowIndex;
    if (actionBarIndex < barCount)
    {
        focused = barBtns[actionBarIndex];
        screen.SetFocusWindow(focused);
    }
}

function MoveToChoice(int idx)
{
    if (idx < 0 || idx >= numChoices)
        return;
    rowIndex = idx;
    focusIndex = idx;
    focused = choices[idx];
    if (focused != None)
        screen.SetFocusWindow(focused);
}

function bool HandleDPad(int dx, int dy)
{
    local int totalRows, newIdx;

    totalRows = numChoices + 1;  // choices + ActionBarRow

    if (dy != 0)
    {
        // End-to-end wrap across all rows (choices + action bar).
        newIdx = (rowIndex + dy + totalRows) % totalRows;
        if (newIdx == numChoices)
            MoveToActionBar();
        else
            MoveToChoice(newIdx);
        return true;
    }

    if (dx != 0 && rowIndex == numChoices)
    {
        if (dx < 0)
            actionBarIndex = class'ComputerButtonBarNav'.static.MoveLeft(
                barBtns, barCount, actionBarIndex);
        else
            actionBarIndex = class'ComputerButtonBarNav'.static.MoveRight(
                barBtns, barCount, actionBarIndex);
        if (actionBarIndex < barCount)
        {
            focused = barBtns[actionBarIndex];
            screen.SetFocusWindow(focused);
        }
    }
    return true;
}

function bool HandleActivate(byte button)
{
    if (button != 200)
        return true;

    if (focused == None || !focused.bIsSensitive)
        return true;

    // Both MenuUIChoiceButton (choice rows) and MenuUIActionButtonWindow
    // (ActionBarRow) inherit MenuUIBorderButtonWindow → PressButton.
    if (MenuUIBorderButtonWindow(focused) != None)
        MenuUIBorderButtonWindow(focused).PressButton();
    return true;
}

function bool GetFocusedRect(out float x, out float y, out float w, out float h)
{
    return false;  // every row on this screen is a button — suppress frame
}
