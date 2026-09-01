#pragma once

// Pure frame-pacing math for the main loop's deadline scheduling. Integer QPC
// ticks throughout; only the per-frame delta becomes a float. No syscalls, no
// engine headers - see development.md's pure-unit-layer entry.
namespace FramePacing
{
    //Effective frame rate: the smaller of the NON-ZERO rates. Zero means
    //"unlimited", so a plain min() would wrongly let an unlimited rate win.
    //Both zero -> 0 (unlimited).
    float EffectiveRate(const float fFpsLimit, const float fMaxTickRate);

    //Frame period in QPC ticks for the effective rate. 0 when unlimited.
    long long EffectivePeriodTicks(const float fFpsLimit, const float fMaxTickRate, const long long iQpcFrequency);

    //Non-accumulating: each deadline is anchored to this frame's post-wait
    //timestamp, so an overrunning frame never triggers a catch-up burst.
    long long NextDeadline(const long long iNowQpc, const long long iPeriodQpc);

    //Wait timeout for the MsgWaitForMultipleObjects re-arm, rounded up so the
    //wait never returns fractionally early. 0 once the deadline has passed.
    unsigned long RemainingMs(const long long iNowQpc, const long long iDeadlineQpc, const long long iQpcFrequency);

    //Relative due time for a waitable timer, in 100 ns units (positive
    //magnitude; the caller negates it to make it relative).
    long long TicksTo100ns(const long long iTicks, const long long iQpcFrequency);

    //Tick-to-tick span in ms, unclamped: what the frame actually took, so a
    //hitch stays comparable across builds instead of pinning at the delta clamp.
    double ElapsedMs(const long long iPrevQpc, const long long iNowQpc, const long long iQpcFrequency);

    //Tick-to-tick delta in seconds, clamped to [0, 0.2] - bounds a stall
    //handing the engine seconds of movement in one tick, and covers QPC going
    //backwards.
    float ClampedDelta(const long long iPrevQpc, const long long iNowQpc, const long long iQpcFrequency);

    //How far past its deadline the loop actually woke, in ms, never negative.
    double OvershootMs(const long long iWakeQpc, const long long iDeadlineQpc, const long long iQpcFrequency);
}
