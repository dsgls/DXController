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
// SetFocus drives the vanilla focus-text-color cue on btnHealAll
// (PersonaBorderButtonWindow.SetButtonMetrics uses IsFocusWindow to
// pick colText[1] over colText[0]). The MenuFocusOverlay frame is
// suppressed by the base GetFocusedRect because PersonaBorderButtonWindow
// is in MenuNavController.HasStockFocusCue — one indicator, not two.
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
    SetFocus(s.btnHealAll);
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

function BuildHints()
{
    AddHint("a", "Heal");
    AddHint("b", "Close");
}

defaultproperties
{
    bAllowRepeat=False
}
