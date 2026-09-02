//=============================================================================
// DXControllerDebug — project-wide debug-log toggles.
//
// Two independent flags in [DXController.DXControllerDebug] (DeusEx.ini):
//   bGamepadDebugLog — input-layer detail. Callers use DebugLog().
//   bNavDebugLog     — UI/navigation diagnostics. Callers use NavLog().
//
// A few rare, edge-triggered messages log unconditionally via plain Log()
// at their call sites — integration-hooking proof, device handoffs,
// abnormal states. Keep that tier to at most one line per screen change,
// never per-event.
//=============================================================================
class DXControllerDebug extends Object
    config(DeusEx)
    abstract;

var config bool bGamepadDebugLog;
var config bool bNavDebugLog;

static final function DebugLog(coerce string msg)
{
    if (Default.bGamepadDebugLog)
        Log(msg);
}

static final function NavLog(coerce string msg)
{
    if (Default.bNavDebugLog)
        Log(msg);
}
