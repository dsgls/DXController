//=============================================================================
// RechargeNavController — gamepad nav for HUDRechargeWindow (RepairBot UI).
//
// Two PersonaActionButtonWindow buttons in a PersonaButtonBarWindow:
//   - btnClose    (always enabled)
//   - btnRecharge (disabled when energy is full or bot is recharging)
//
// HUDRechargeWindow has no VirtualKeyPressed override (inherits Window's
// no-op), so root-side Escape synthesis is a dead end.
// AllowsMenuToggle=false routes B to HandleActivate, which presses
// btnClose — matches the visible Close affordance and reuses the same
// teardown path (root.PopWindow via ButtonActivated).
//
// SetFocusWindow lights up the vanilla focus text color on
// PersonaBorderButtonWindow. Frame overlay still draws on top.
//=============================================================================
class RechargeNavController extends MenuNavController;

function InitFocus()
{
    local HUDRechargeWindow s;

    s = HUDRechargeWindow(screen);
    if (s == None)
        return;

    // Prefer the affirmative action when it's actionable.
    if (s.btnRecharge != None && s.btnRecharge.bIsSensitive)
        focused = s.btnRecharge;
    else
        focused = s.btnClose;

    if (focused != None)
        s.SetFocusWindow(focused);
}

function bool HandleDPad(int dx, int dy)
{
    local HUDRechargeWindow s;
    local Window candidate;

    if (dx == 0)
        return true;   // up/down: consume, no-op

    s = HUDRechargeWindow(screen);
    if (s == None || s.btnClose == None || s.btnRecharge == None)
        return true;

    if (focused == s.btnRecharge)
        candidate = s.btnClose;
    else
        candidate = s.btnRecharge;

    if (candidate == None || !candidate.bIsSensitive)
        return true;   // disabled neighbour: stay put

    focused = candidate;
    s.SetFocusWindow(focused);

    if (focused == s.btnRecharge)
        class'DXControllerDebug'.static.DebugLog("DXC-NAV FOCUS recharge=recharge");
    else
        class'DXControllerDebug'.static.DebugLog("DXC-NAV FOCUS recharge=close");
    return true;
}

function bool HandleActivate(byte button)
{
    local HUDRechargeWindow s;

    s = HUDRechargeWindow(screen);

    // B (201): press btnClose. Same teardown as the visible Close button.
    if (button == 201)
    {
        if (s != None && s.btnClose != None)
            s.btnClose.PressButton();
        return true;
    }

    // A (200): press focused. Other buttons consumed.
    if (button != 200)
        return true;

    if (focused != None && ButtonWindow(focused) != None && focused.bIsSensitive)
        ButtonWindow(focused).PressButton();
    return true;
}

function bool AllowsMenuToggle()
{
    return false;
}

defaultproperties
{
    bAllowRepeat=False
}
