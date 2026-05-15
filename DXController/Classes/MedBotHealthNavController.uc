//=============================================================================
// MedBotHealthNavController — gamepad nav for HUDMedBotHealthScreen.
//
// HUDMedBotHealthScreen extends PersonaScreenHealth and sets
// bShowHealButtons=False, so the six body-region buttons are display-
// only on this screen. Only btnHealAll is interactable, so we focus it
// and ignore D-pad. AllowsMenuToggle stays true (inherited): the
// screen inherits PersonaScreenBaseWindow's Escape→CancelScreen path,
// so B routes through the root's standard Escape-synthesis to close.
//
// SetFocusWindow lights up the vanilla focus text color
// (PersonaBorderButtonWindow.SetButtonMetrics uses IsFocusWindow to
// pick colText[1] over colText[0]). The MenuFocusOverlay frame still
// draws on top via the inherited GetFocusedRect.
//=============================================================================
class MedBotHealthNavController extends MenuNavController;

function InitFocus()
{
    local HUDMedBotHealthScreen s;

    s = HUDMedBotHealthScreen(screen);
    if (s == None)
        return;
    if (s.btnHealAll == None)
        return;
    focused = s.btnHealAll;
    s.SetFocusWindow(s.btnHealAll);
}

function bool HandleDPad(int dx, int dy)
{
    return true;   // consumed no-op: only one interactable on this screen
}

function bool HandleActivate(byte button)
{
    // A = IK_Joy1 = 200. Other buttons (X/Y/R-stick): consume, no-op.
    if (button != 200)
        return true;

    if (focused != None && ButtonWindow(focused) != None && focused.bIsSensitive)
        ButtonWindow(focused).PressButton();
    return true;
}

defaultproperties
{
    bAllowRepeat=False
}
