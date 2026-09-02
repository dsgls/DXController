//=============================================================================
// DXControllerDebug — project-wide debug-log toggles.
//
// Two independent flags in [DXController.DXControllerDebug] (DeusEx.ini):
//   bGamepadDebugLog — input-layer detail (axis routing, wheel stick
//                      magnitudes; the launcher also reads it for its
//                      device-idle edges). Callers use DebugLog().
//   bNavDebugLog     — UI/navigation diagnostics (focus moves, activation,
//                      terminal/conversation/keyboard/wheel traces).
//                      Callers use NavLog().
//
// A few messages log unconditionally via plain Log() at their call sites:
// the ControllerRootWindow hooking events (direct-child DESC-ADD, TICK-TOP,
// TICK-INIT), cursor-mode switches (DXC-CURSOR) and slow-frame reports
// (DXC-PERF) — the baseline every user ticket log should contain.
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
