//=============================================================================
// ControllerGameInfo — DeusExGameInfo subclass.
//
// Routes the engine to ControllerPlayer:
//   - DefaultPlayerClass picks ControllerPlayer as the default SpawnClass.
//   - ApproveClass approves ControllerPlayer (stock ApproveClass returns
//     false unconditionally, which forces SpawnClass back to JCDentonMale
//     in DeusExGameInfo.Login — without this override, DefaultPlayerClass
//     is silently bypassed).
//
// DefaultPlayerClass is var() (not config) on GameInfo.uc:41, so an ini
// override of the stock class wouldn't work — subclassing is the only path.
//
// Engine-routed via [Engine.Engine] DefaultGame=DXController.ControllerGameInfo.
//=============================================================================
class ControllerGameInfo extends DeusExGameInfo;

function bool ApproveClass(class<PlayerPawn> SpawnClass)
{
    return ClassIsChildOf(SpawnClass, Class'DXController.ControllerPlayer');
}

defaultproperties
{
    DefaultPlayerClass=Class'DXController.ControllerPlayer'
}
