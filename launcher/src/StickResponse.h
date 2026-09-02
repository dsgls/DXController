#pragma once

// Pure analog-stick and trigger response math: radial deadzone, response
// curve, output scale and clamp. No SDL, no engine - the Gamepad shim reads
// raw SDL axis values and feeds them here, and the in-game curve preview
// (CGamepad::SampleCurve) samples the same functions so preview and reality
// cannot drift.
namespace StickResponse
{
    //Stock Unreal WinDrv configures DirectInput joystick axes to -1000..1000
    //via DIPROP_RANGE; User.ini Speed= values are tuned for that magnitude.
    //Emit in the same convention so existing bindings work without retuning.
    constexpr float kAxisRange = 1000.0f;

    //Full-scale magnitude of a single SDL axis. -32768 is normalized away by
    //ClampAxis so both directions are symmetric.
    constexpr float kRawFullScale = 32767.0f;

    enum class ECurveType { Linear, Power, Expo, Sigmoid };

    //Parameters for all four curve types at once: only the fields the active
    //eType names are read, so switching type in the ini never invalidates the
    //others' tuning.
    struct SCurve
    {
        ECurveType eType;
        float      fPower;
        float      fExpo;
        float      fSigSteepness;
        float      fSigMidpoint;
        float      fSigStrength;
    };

    //Post-pipeline axis pair, in Unreal's -1000..1000 joystick convention.
    struct SAxes
    {
        float fX;
        float fY;
    };

    //Shape a normalized magnitude u (>= 0) into a shaped magnitude. Endpoints
    //pinned: returns 0 at u <= 0, ~1 at u = 1. Linear short-circuits. May
    //return > 1 for u > 1 (diagonal overflow); callers clamp the final axes.
    float ShapeMagnitude(const float fU, const SCurve& Curve);

    //The magnitude half of the pipeline, shared by Shape() and the curve
    //preview: radial deadzone remap of (cDz, 1] to (0, 1], then the curve,
    //then the output scale. fU is raw magnitude / 32767; iDeadzoneRaw is an
    //Sint16 magnitude. Result is normalized (1.0 = full axis range).
    float ShapeNormalized(const float fU, const int iDeadzoneRaw, const SCurve& Curve, const float fScale);

    //SDL can report -32768, one past the positive end of the range. Clamp to
    //-32767 so both axes are symmetric and negation can't overflow.
    int ClampAxis(const int iRaw);

    //SDL Y axes are positive-down; the pipeline wants positive-up.
    int NegateY(const int iRaw);

    //Full stick pipeline. iRawX/iRawY are in SDL's Sint16 range but taken as
    //int: the caller negates SDL's positive-down Y, which overflows Sint16.
    //Direction is preserved and each output axis is clamped to +/-1000
    //independently, so a full diagonal yields an output *vector* magnitude of
    //~1414 by design.
    SAxes Shape(const int iRawX, const int iRawY, const int iDeadzoneRaw,
                const SCurve& Curve, const float fScale);

    //Trigger pipeline. iThreshold255 keeps the ini key's XInput-era 0..255
    //meaning; SDL reports triggers as 0..32767, so the threshold is scaled up
    //rather than the value down. Returns 0 at or below the threshold, else a
    //linear remap of (iT, 32767] to (0, 1000].
    float Trigger(const int iRaw, const int iThreshold255);
}
