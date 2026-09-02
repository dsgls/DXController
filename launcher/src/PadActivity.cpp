#include "PadActivity.h"

namespace PadActivity
{

int ClampGraceMs(const int iGraceMs)
{
    return (iGraceMs < 0) ? 0 : iGraceMs;
}

int ClampMouseActivityPx(const int iThresholdPx)
{
    return (iThresholdPx < 0) ? 0 : iThresholdPx;
}

void NotePadActivity(SState& State, const unsigned long long iNowMs)
{
    State.iLastPadActivityMs = iNowMs;
}

void NotifyMouseActivity(SState& State, const int iDeltaX, const int iDeltaY,
                         const int iThresholdPx, const unsigned long long iNowMs)
{
    const int iManhattan = (iDeltaX < 0 ? -iDeltaX : iDeltaX) + (iDeltaY < 0 ? -iDeltaY : iDeltaY);
    if (iManhattan == 0)
    {
        return; //button-only WM_INPUT packet
    }

    if (State.iRawMouseAccumStartMs == 0 || iNowMs - State.iRawMouseAccumStartMs > kAccumWindowMs)
    {
        State.iRawMouseAccum        = 0;
        State.iRawMouseAccumStartMs = iNowMs;
    }
    State.iRawMouseAccum += iManhattan;
    if (State.iRawMouseAccum > iThresholdPx)
    {
        State.iLastMouseActivityMs = iNowMs;
    }
}

bool IsPadActive(const SState& State, const unsigned long long iNowMs, const int iGraceMs)
{
    const unsigned long long iGrace = static_cast<unsigned long long>(iGraceMs);
    const bool bPadRecent   = State.iLastPadActivityMs   != 0 && (iNowMs - State.iLastPadActivityMs)   < iGrace;
    const bool bMouseRecent = State.iLastMouseActivityMs != 0 && (iNowMs - State.iLastMouseActivityMs) < iGrace;
    return bPadRecent && !bMouseRecent;
}

bool IsMouseActive(const SState& State, const unsigned long long iNowMs, const int iGraceMs)
{
    const unsigned long long iGrace = static_cast<unsigned long long>(iGraceMs);
    return State.iLastMouseActivityMs != 0 && (iNowMs - State.iLastMouseActivityMs) < iGrace;
}

}
