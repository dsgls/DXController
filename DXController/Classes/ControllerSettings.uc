//=============================================================================
// ControllerSettings — config shell for [DXController.ControllerSettings].
//
// `config(DeusEx)` puts the keys in DeusEx.ini; UE1's `var config` writes
// to [Package.ClassName] which here gives [DXController.ControllerSettings].
// The launcher reads from the same section, initializes any missing keys
// with its baked-in defaults, and writes them back on startup so the
// .ini is always complete by the time we read.
//
// No defaultproperties — defaults are owned entirely by the launcher
// constructor (launcher/src/XInput.cpp:89-146). Mirroring
// them on the script side would be a divergence trap.
//=============================================================================
class ControllerSettings extends Object
    config(DeusEx)
    abstract;

var config int    StickDeadzoneLeft, StickDeadzoneRight;
var config string StickCurveLeft, StickCurveRight;
var config float  StickCurvePowerLeft, StickCurvePowerRight;
var config float  StickCurveExpoLeft,  StickCurveExpoRight;
var config float  StickCurveSigmoidSteepnessLeft, StickCurveSigmoidSteepnessRight;
var config float  StickCurveSigmoidMidpointLeft,  StickCurveSigmoidMidpointRight;
var config float  StickCurveSigmoidStrengthLeft,  StickCurveSigmoidStrengthRight;
