#pragma once

// Pure "which input device is the user actually holding" heuristic. The clock
// is a parameter rather than a GetTickCount64() call, so the accumulation
// window and grace boundaries are testable without SDL or the engine.
namespace PadActivity
{
    //Raw mouse deltas are accumulated over this window before being compared
    //against the pixel threshold: a single raw packet from a slow hand
    //movement carries only 1-2 counts, well under any useful threshold.
    constexpr unsigned long long kAccumWindowMs = 250;

    struct SState
    {
        unsigned long long iLastPadActivityMs   = 0;
        unsigned long long iLastMouseActivityMs = 0;
        int                iRawMouseAccum       = 0; //Manhattan sum within the current window
        unsigned long long iRawMouseAccumStartMs = 0; //window start; 0 = no window open
    };

    //Clamps for the hand-editable ini values these functions take. A negative
    //grace window survives the unsigned cast below as an effectively infinite
    //one; a negative pixel threshold makes every raw packet qualify.
    int ClampGraceMs(const int iGraceMs);
    int ClampMouseActivityPx(const int iThresholdPx);

    void NotePadActivity(SState& State, const unsigned long long iNowMs);

    //Raw hardware mouse deltas. Raw input is the physical-motion ground truth:
    //synthetic cursor moves generate WM_MOUSEMOVE but never WM_INPUT, so they
    //must not flip the active-source signal back to mouse.
    void NotifyMouseActivity(SState& State, const int iDeltaX, const int iDeltaY,
                             const int iThresholdPx, const unsigned long long iNowMs);

    //True if controller input crossed activity thresholds within the last
    //grace window AND no qualifying mouse activity has since occurred.
    bool IsPadActive(const SState& State, const unsigned long long iNowMs, const int iGraceMs);

    //True if qualifying physical mouse activity occurred within the last grace
    //window - positive evidence of the user's hand on the mouse.
    bool IsMouseActive(const SState& State, const unsigned long long iNowMs, const int iGraceMs);
}
