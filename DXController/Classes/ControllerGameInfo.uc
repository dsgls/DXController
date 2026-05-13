//=============================================================================
// ControllerGameInfo — DeusExGameInfo subclass.
//
// Sole responsibility: override DefaultPlayerClass to point at
// ControllerPlayer. DefaultPlayerClass is var() (not config) on
// GameInfo.uc:41, so an ini override of the stock class wouldn't take
// effect — subclassing is the only path.
//
// Engine-routed via [Engine.Engine] DefaultGame=DXController.ControllerGameInfo.
//=============================================================================
class ControllerGameInfo extends DeusExGameInfo;

defaultproperties
{
    DefaultPlayerClass=Class'DXController.ControllerPlayer'
}
