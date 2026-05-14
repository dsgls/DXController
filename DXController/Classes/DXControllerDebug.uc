//=============================================================================
// DXControllerDebug — project-wide gamepad debug-log toggle.
//
// Callers: class'DXControllerDebug'.static.DebugLog("DXC-...")
// Enable:  [DXController.DXControllerDebug] bGamepadDebugLog=True in DeusEx.ini
//=============================================================================
class DXControllerDebug extends Object
    config(DeusEx)
    abstract;

var config bool bGamepadDebugLog;

static final function DebugLog(coerce string msg)
{
    if (Default.bGamepadDebugLog)
        Log(msg);
}
