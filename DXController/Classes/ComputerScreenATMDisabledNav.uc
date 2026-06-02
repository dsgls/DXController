//=============================================================================
// ComputerScreenATMDisabledNav — sub-controller for ComputerScreenATMDisabled.
//
// Single-row screen: only btnClose is interactable. D-pad consumed
// (1-element ring); A → PressButton; B handled by dispatcher.
//=============================================================================
class ComputerScreenATMDisabledNav extends ComputerScreenNavSub;

var MenuUIActionButtonWindow barBtns[5];
var int barCount;

function OnEnter(ComputerUIWindow s)
{
    local ComputerScreenATMDisabled dScr;

    Super.OnEnter(s);

    dScr = ComputerScreenATMDisabled(s);
    if (dScr == None || dScr.winButtonBar == None)
        return;

    class'ComputerButtonBarNav'.static.CollectButtons(
        dScr.winButtonBar, barBtns, barCount);

    if (barCount > 0)
    {
        focusIndex = 0;
        SetFocus(barBtns[0]);
    }
}

function bool HandleDPad(int dx, int dy)
{
    return true;  // single-item ring — consumed no-op
}

function bool HandleActivate(byte button)
{
    if (button != 200)   // 200 = IK_Joy1 (A)
        return true;
    if (focused != None
        && MenuUIActionButtonWindow(focused) != None
        && focused.bIsSensitive)
    {
        MenuUIActionButtonWindow(focused).PressButton();
    }
    return true;
}
