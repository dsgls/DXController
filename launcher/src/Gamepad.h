#pragma once

#include <cstdint>
#include <vector>

class UEngine;
class UViewport;
struct SDL_Gamepad;

class CGamepad
{
public:
    enum class EStickCurveType { Linear, Power, Expo, Sigmoid };

    enum class EStick { Left, Right };

    struct SStickCurve
    {
        EStickCurveType eType;
        float fPower;
        float fExpo;
        float fSigSteepness;
        float fSigMidpoint;
        float fSigStrength;
    };

    CGamepad();
    CGamepad(const CGamepad&) = delete;
    CGamepad& operator=(const CGamepad&) = delete;
    ~CGamepad();

    // New explicit init step, called from CLauncher's constructor after
    // pEngine->Init() and the viewport lookup -- SDL must not start before
    // then (see CGamepad()). Probes for the delay-loaded SDL3.dll, then
    // calls SDL_Init(SDL_INIT_GAMEPAD), loads an optional
    // gamecontrollerdb.txt sitting next to the exe, and opens every pad
    // already connected. On failure, logs once via GLog->Logf and returns
    // false, leaving m_bInitialized false; every other CGamepad entry point
    // no-ops in that case.
    bool Init(UViewport* pViewport);

    // Called once per engine tick (gated to FPS limit by the caller). Drains
    // SDL's event queue (hotplug and active-pad switching), snapshots the
    // active controller, diffs against previous state, emits IST_Press/
    // IST_Release/IST_Axis events. Must NOT be called every MainLoop
    // iteration -- the engine accumulates IST_Axis between ticks, so multiple
    // emits per tick scale the resulting turn/look amount by the poll count
    // and produce visible jerk. No-op if pViewport is null. Synthesizes
    // releases for any held buttons and IST_Axis(0.0) for any held analog
    // channels when bHasFocus is false, when the active controller
    // disconnects, and when the active pad changes, so the engine never sees
    // stuck inputs.
    void Poll(UEngine* pEngine, UViewport* pViewport, bool bHasFocus);

    // True if controller input crossed activity thresholds within the last
    // grace window AND no qualifying mouse activity has since occurred.
    bool IsPadActive() const;

    // True if qualifying physical mouse activity (raw-input deltas crossing
    // the accumulator threshold) occurred within the last grace window.
    // Positive evidence of the user's hand on the mouse — used to gate the
    // WM_MOUSEMOVE -> MousePosition feed so synthetic cursor moves (which
    // arrive without raw deltas) can never reach the game's window system.
    bool IsMouseActive() const;

    // Called by MainLoop from its WM_INPUT branch with the raw hardware
    // mouse deltas. Raw input is the physical-motion ground truth: synthetic
    // cursor moves (WinDrv's capture-release position restore on menu open,
    // ClipCursor clamps, our own fullscreen SetCursorPos sync) generate
    // WM_MOUSEMOVE but never WM_INPUT, so they must not flip the
    // active-source signal back to mouse. Deltas are accumulated over a
    // short window (raw packets are far finer-grained than coalesced
    // WM_MOUSEMOVE); once the accumulated Manhattan distance exceeds the
    // configured pixel threshold, the signal flips to mouse.
    void NotifyMouseActivity(int iDeltaX, int iDeltaY);

    // Re-reads the [DXController.ControllerSettings] section into the in-memory
    // settings. Safe to call between Poll() invocations; the next Poll uses
    // the new settings. Held-stick cached values are deliberately preserved so
    // live tuning doesn't produce a spurious release/zero frame.
    void Reload();

    // Samples the current stick curve at iCount evenly spaced points across
    // the full normalized input range [0, 1] and writes a CSV of normalized
    // [0, 1] output magnitudes to Ar (single Logf call). iCount is clamped to
    // [2, 256]. Includes the deadzone flat region as leading zeros and the
    // right stick's output scale so the preview reflects the player
    // experience.
    void SampleCurve(EStick eStick, int iCount, FOutputDevice& Ar) const;

    // Writes "L=%.4f R=%.4f" to Ar: the most recent raw (pre-deadzone,
    // pre-curve) stick magnitudes, normalized to [0, 1]. Zero when no
    // controller is connected or the window has lost focus.
    void GetRawStickMags(FOutputDevice& Ar) const;

private:
    //One opened SDL gamepad. iId is the SDL_JoystickID (SDL's instance id,
    //never 0 for a real device, so 0 doubles as "no active pad").
    struct SOpenPad
    {
        std::uint32_t iId;
        SDL_Gamepad*  pPad;
    };

    bool m_bInitialized;

    //Settings (loaded by LoadSettings(); refreshed by Reload())
    int m_iLeftStickDeadzone;       //Sint16 magnitude, 0..32767
    int m_iRightStickDeadzone;      //Sint16 magnitude, 0..32767
    int m_iTriggerThreshold;        //0..255; scaled to SDL's 0..32767 trigger range at use
    int m_iMouseActivityPx;         //pixels
    int m_iPadActiveGraceMs;        //milliseconds
    SStickCurve m_LeftStickCurve;   //response curve applied to post-deadzone left-stick magnitude
    SStickCurve m_RightStickCurve;  //response curve applied to post-deadzone right-stick magnitude
    float m_fRightStickScale;       //post-curve output scale for the right stick, 0.10..1.00; 1.0 = full axis range

    //Runtime state
    std::vector<SOpenPad> m_OpenPads;
    std::uint32_t m_iActivePadId;   //0 when no pad is active
    std::uint32_t m_iPrevButtons;   //bit i = kButtonMap[i] held as of the last poll

    //Previous-frame post-deadzone stick/trigger values, in Unreal's joystick axis
    //convention (-1000..1000 for sticks, 0..1000 for triggers). Used by the
    //non-zero -> zero edge emit in EmitStickAxes/EmitTriggerAxis and by
    //FlushHeldAxes.
    float m_fPrevLeftStickX;
    float m_fPrevLeftStickY;
    float m_fPrevRightStickX;
    float m_fPrevRightStickY;
    float m_fPrevLeftTrigger;
    float m_fPrevRightTrigger;
    float m_fLeftStickRawMag;   //Most recent raw (pre-deadzone, pre-curve) left-stick magnitude, normalized to [0, 1]. Read by GetRawStickMags().
    float m_fRightStickRawMag;  //Same for right stick.
    ULONGLONG m_iLastPadActivityMs;
    ULONGLONG m_iLastMouseActivityMs;
    int       m_iRawMouseAccum;        //Manhattan sum of raw deltas in the current window
    ULONGLONG m_iRawMouseAccumStartMs; //window start; 0 = no window open

    //Helpers

    //Reads all 18 keys from [DXController.ControllerSettings] into the
    //corresponding members and clamps the curve parameters into their
    //valid ranges. Called from the constructor and from Reload().
    void LoadSettings();

    //Drains SDL's event queue: opens/closes pads on hotplug and moves the
    //active-pad selection to whichever pad the user just touched. Emits only
    //the releases/flushes that a disconnect or an active-pad change owes the
    //engine; all emission proper comes from the snapshot in Poll().
    void ProcessEvents(UEngine* pEngine, UViewport* pViewport);

    //Makes iPadId active, first releasing/flushing everything the outgoing pad
    //still holds so a mid-hold switch can't leave stuck input. No-op if iPadId
    //is already active or isn't open.
    void SetActivePad(UEngine* pEngine, UViewport* pViewport, std::uint32_t iPadId);

    //The open pad matching m_iActivePadId, or null when none is active.
    SDL_Gamepad* GetActivePad() const;

    void ClosePad(std::uint32_t iPadId);

    //Zeroes every held button/axis and the cached raw magnitudes. Used by the
    //focus-loss, disconnect and pad-switch paths.
    void ReleaseAll(UEngine* pEngine, UViewport* pViewport);

    //The Elite-paddle seam (spec §7): the one point where a supplemental
    //button source may OR extra bits into the snapshot mask. Returns 0 --
    //this is structure only, no supplement is wired up.
    std::uint32_t SupplementalButtonMask(SDL_Gamepad* pPad) const;

    void EmitButtonChanges(UEngine* pEngine, UViewport* pViewport, std::uint32_t iNewButtons);
    void ReleaseHeldButtons(UEngine* pEngine, UViewport* pViewport);

    //Emits IST_Axis(eKey, 0.0f) for every analog channel whose cached prev
    //is non-zero, then zeros the prev. Used by the focus-loss and disconnect
    //paths so scripts see a clean release rather than a stuck last value.
    void FlushHeldAxes(UEngine* pEngine, UViewport* pViewport);

    //Emits IST_Axis on (eKeyX, eKeyY) after applying radial deadzone with the
    //given iDeadzone parameter (Sint16 magnitude), then applying the configured
    //response curve to the post-deadzone magnitude (direction preserved), then
    //scaling the output magnitude by fScale (1.0 = full axis range).
    //Stores resulting values in fOutX/fOutY (zero when inside the deadzone),
    //in -1000..1000 axis units. iRawX/iRawY are in SDL's Sint16 range but taken
    //as int: the caller negates SDL's positive-down Y, which overflows Sint16.
    void EmitStickAxes(UEngine* pEngine, UViewport* pViewport,
                       int iRawX, int iRawY, int iDeadzone, const SStickCurve& Curve,
                       float fScale,
                       EInputKey eKeyX, EInputKey eKeyY,
                       float& fOutX, float& fOutY);

    //Returns post-threshold value in [0, 1000]. Emits IST_Axis(eKey, fOut) when
    //fOut is non-zero, or IST_Axis(eKey, 0.0f) on the non-zero -> zero edge
    //(when fOut is zero but fPrev is non-zero). Caller passes the previous
    //tick's cached value as fPrev and SDL's 0..32767 trigger value as iRaw.
    float EmitTriggerAxis(UEngine* pEngine, UViewport* pViewport,
                          int iRaw, float fPrev, EInputKey eKey);
};
