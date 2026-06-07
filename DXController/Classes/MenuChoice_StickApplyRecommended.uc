//=============================================================================
// MenuChoice_StickApplyRecommended - action row that writes the recommended
// controller .ini blocks (bToggleCrouch, WinDrv joystick disables,
// recommended Joy* bindings) after a confirm dialog. The actual write
// logic lives in MenuScreenController.ApplyRecommended().
//
// Base: MenuUIChoiceAction, not MenuUIChoiceButton -- the latter is the
// inner widget spawned by MenuUIChoice.CreateActionButton, not a row.
// Stock action rows (MenuChoice_AdjustColors etc.) extend
// MenuUIChoiceAction; Action=MA_Custom routes through ProcessMenuAction
// to the no-op default branch, which we intercept here to call up into
// the page-level controller.
//=============================================================================
class MenuChoice_StickApplyRecommended extends MenuUIChoiceAction;

// Override the stock action dispatcher. For MA_Custom stock does nothing;
// we forward to the parent MenuScreenController so all of the write logic
// (and the confirm dialog it pops) lives in one place. Other action types
// fall through to the stock behaviour.
function ProcessMenuAction(EMenuActions menuAction, Class menuActionClass)
{
    local MenuScreenController parent;

    if (menuAction == MA_Custom)
    {
        parent = MenuScreenController(GetParent().GetParent());
        if (parent != None)
            parent.OnApplyRecommendedPressed();
        return;
    }

    Super.ProcessMenuAction(menuAction, menuActionClass);
}

defaultproperties
{
    Action=MA_Custom
    actionText="Apply &recommended controller config..."
    helpText="Writes the .ini blocks the README used to require by hand: bToggleCrouch, UseDirectInput/UseJoystick disables, and the recommended Joy* bindings."
}
