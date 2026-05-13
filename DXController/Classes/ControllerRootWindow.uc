//=============================================================================
// ControllerRootWindow — DeusExRootWindow subclass.
//
// Intercepts gamepad key events when a persona screen is on top:
//   IK_Joy5 (LB)  -> previous persona tab
//   IK_Joy6 (RB)  -> next persona tab
//   IK_Joy7 (Back) -> Player.TogglePlayerMenuWindow()
// All others pass through to Super.VirtualKeyPressed (existing arrow /
// tab focus nav stays intact).
//
// Engine-routed via [Engine.Engine] Root=DXController.ControllerRootWindow
// in DeusEx.ini, read by the native InitRootWindow() declared at
// ../deusex-scripts/Extension/Classes/PlayerPawnExt.uc:35. DeusExPlayer
// has an inline comment "it can be changed in the ini" at
// ../deusex-scripts/DeusEx/Classes/DeusExPlayer.uc:11966.
//=============================================================================
class ControllerRootWindow extends DeusExRootWindow;

// Override is safe: parent's VirtualKeyPressed is declared `event`
// (../deusex-scripts/DeusEx/Classes/DeusExRootWindow.uc:133), not final,
// and our same-state global override intercepts every dispatch path the
// player goes through while in the F1 menu (no state-scoped overrides
// exist in DeusExRootWindow).
event bool VirtualKeyPressed(EInputKey key, bool bRepeat)
{
    local ControllerPlayer player;

    if (key == IK_Joy7)
    {
        player = ControllerPlayer(parentPawn);
        if (player != None)
        {
            player.TogglePlayerMenuWindow();
            return true;
        }
    }

    // Tasks 10-11 add LB/RB handling here.

    return Super.VirtualKeyPressed(key, bRepeat);
}
