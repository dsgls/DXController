//=============================================================================
// ControllerConsole — engine Console subclass.
//
// Phase 1: synthesises press/release for LT (IK_JoyZ -> IK_Joy16) and
// RT (IK_JoyR -> IK_Joy15) from the IST_Axis stream the XInput shim feeds
// us. All other events pass through to Super.KeyEvent.
//
// Engine-routed via [Engine.Engine] Console=DXController.ControllerConsole
// in DeusEx.ini. See CLAUDE.md "Overriding base-game classes" for the
// ini-swap pattern.
//=============================================================================
class ControllerConsole extends Console;

// (deliberately empty — Task 2 fills this in)
