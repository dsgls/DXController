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

// (Task 9 + 10 + 11 fill this in)
