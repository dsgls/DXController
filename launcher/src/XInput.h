#pragma once

class UEngine;
class UViewport;

class CXInput
{
public:
    enum class EStickCurveType { Linear, Power, Expo, Sigmoid };

    enum class EStick { Left, Right };

    struct SStickCurve
    {
        EStickCurveType eType = EStickCurveType::Power;
        float fPower         = 2.0f;
        float fExpo          = 0.60f;
        float fSigSteepness  = 6.0f;
        float fSigMidpoint   = 0.60f;
        float fSigStrength   = 0.60f;
    };

    CXInput();
    CXInput(const CXInput&) = delete;
    CXInput& operator=(const CXInput&) = delete;

    // Called once per engine tick (gated to FPS limit by the caller). Polls the
    // active controller, diffs against previous state, emits IST_Press/IST_Release
    // /IST_Axis events. Must NOT be called every MainLoop iteration -- the engine
    // accumulates IST_Axis between ticks, so multiple emits per tick scale the
    // resulting turn/look amount by the poll count and produce visible jerk.
    // No-op if pViewport is null. Synthesizes releases for any held buttons and
    // IST_Axis(0.0) for any held analog channels when bHasFocus is false or the
    // controller has disconnected, so the engine never sees stuck inputs.
    void Poll(UEngine* pEngine, UViewport* pViewport, bool bHasFocus);

    // True if controller input crossed activity thresholds within the last
    // grace window AND no qualifying mouse activity has since occurred.
    bool IsPadActive() const;

    // Called by MainLoop from its WM_MOUSEMOVE branch with the client-relative
    // cursor position. Internally tracks previous position; if the delta
    // exceeds the configured pixel threshold, flips the active-source signal
    // back to mouse.
    void NotifyMouseActivity(int iX, int iY);

    // Re-reads the [DXController.ControllerSettings] section into the in-memory
    // settings. Safe to call between Poll() invocations; the next Poll uses
    // the new settings. Held-stick cached values are deliberately preserved so
    // live tuning doesn't produce a spurious release/zero frame.
    void Reload();

    // Samples the current stick curve at iCount evenly spaced points across
    // the full normalized input range [0, 1] and writes a CSV of normalized
    // [0, 1] output magnitudes to Ar (single Logf call). iCount is clamped to
    // [2, 256]. Includes the deadzone flat region as leading zeros so the
    // preview reflects the player experience.
    void SampleCurve(EStick eStick, int iCount, FOutputDevice& Ar) const;

    // Writes "L=%.4f R=%.4f" to Ar: the most recent raw (pre-deadzone,
    // pre-curve) stick magnitudes, normalized to [0, 1]. Zero when the
    // controller is disconnected or the window has lost focus.
    void GetRawStickMags(FOutputDevice& Ar) const;

private:
    //Settings (loaded by LoadSettings(); refreshed by Reload())
    int m_iLeftStickDeadzone;       //SHORT magnitude, 0..32767
    int m_iRightStickDeadzone;      //SHORT magnitude, 0..32767
    int m_iTriggerThreshold;        //BYTE, 0..255
    int m_iMouseActivityPx;         //pixels
    int m_iPadActiveGraceMs;        //milliseconds
    int m_iHotplugScanMs;           //milliseconds
    SStickCurve m_LeftStickCurve;   //response curve applied to post-deadzone left-stick magnitude
    SStickCurve m_RightStickCurve;  //response curve applied to post-deadzone right-stick magnitude

    //Runtime state
    DWORD m_iActiveSlot;        //(DWORD)-1 when not connected
    bool  m_bConnected;
    WORD  m_iPrevButtons;       //bitmask of XINPUT_GAMEPAD_* bits from last poll

    //Previous-frame post-deadzone stick/trigger values, in Unreal's joystick axis
    //convention (-1000..1000 for sticks, 0..1000 for triggers). Used by packet
    //dedup, by the non-zero -> zero edge emit in EmitStickAxes/EmitTriggerAxis,
    //and by FlushHeldAxes.
    float m_fPrevLeftStickX;
    float m_fPrevLeftStickY;
    float m_fPrevRightStickX;
    float m_fPrevRightStickY;
    float m_fPrevLeftTrigger;
    float m_fPrevRightTrigger;
    float m_fLeftStickRawMag;   //Most recent raw (pre-deadzone, pre-curve) left-stick magnitude, normalized to [0, 1]. Read by GetRawStickMags().
    float m_fRightStickRawMag;  //Same for right stick.
    DWORD m_iPrevPacket;
    ULONGLONG m_iLastHotplugScanMs;
    ULONGLONG m_iLastPadActivityMs;
    ULONGLONG m_iLastMouseActivityMs;
    int       m_iPrevMouseX;
    int       m_iPrevMouseY;
    bool      m_bHasPrevMousePos;

    //Helpers

    //Reads all 18 keys from [DXController.ControllerSettings] into the
    //corresponding members and clamps the curve parameters into their
    //valid ranges. Called from the constructor and from Reload().
    void LoadSettings();

    void EmitButtonChanges(UEngine* pEngine, UViewport* pViewport, WORD iNewButtons);
    void ReleaseHeldButtons(UEngine* pEngine, UViewport* pViewport);

    //Emits IST_Axis(eKey, 0.0f) for every analog channel whose cached prev
    //is non-zero, then zeros the prev. Used by the focus-loss and disconnect
    //paths so scripts see a clean release rather than a stuck last value.
    void FlushHeldAxes(UEngine* pEngine, UViewport* pViewport);

    //Emits IST_Axis on (eKeyX, eKeyY) after applying radial deadzone with the
    //given iDeadzone parameter (SHORT magnitude), then applying the configured
    //response curve to the post-deadzone magnitude (direction preserved).
    //Stores resulting values in fOutX/fOutY (zero when inside the deadzone),
    //in -1000..1000 axis units.
    void EmitStickAxes(UEngine* pEngine, UViewport* pViewport,
                       SHORT iRawX, SHORT iRawY, int iDeadzone, const SStickCurve& Curve,
                       EInputKey eKeyX, EInputKey eKeyY,
                       float& fOutX, float& fOutY);

    //Returns post-threshold value in [0, 1000]. Emits IST_Axis(eKey, fOut) when
    //fOut is non-zero, or IST_Axis(eKey, 0.0f) on the non-zero -> zero edge
    //(when fOut is zero but fPrev is non-zero). Caller passes the previous
    //tick's cached value as fPrev.
    float EmitTriggerAxis(UEngine* pEngine, UViewport* pViewport,
                          BYTE iRaw, float fPrev, EInputKey eKey);
};
