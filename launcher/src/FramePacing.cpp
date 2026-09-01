#include "FramePacing.h"

#include <algorithm>
#include <cmath>

namespace
{
    constexpr double kfMaxDeltaSeconds = 0.2;
    constexpr long long ki100nsPerSecond = 10000000;
}

float FramePacing::EffectiveRate(const float fFpsLimit, const float fMaxTickRate)
{
    if (fFpsLimit > 0.0f && fMaxTickRate > 0.0f)
    {
        return (fFpsLimit < fMaxTickRate) ? fFpsLimit : fMaxTickRate;
    }
    if (fFpsLimit > 0.0f)
    {
        return fFpsLimit;
    }
    return (fMaxTickRate > 0.0f) ? fMaxTickRate : 0.0f;
}

long long FramePacing::EffectivePeriodTicks(const float fFpsLimit, const float fMaxTickRate, const long long iQpcFrequency)
{
    const float fRate = EffectiveRate(fFpsLimit, fMaxTickRate);
    if (fRate <= 0.0f || iQpcFrequency <= 0)
    {
        return 0;
    }
    return static_cast<long long>(std::llround(static_cast<double>(iQpcFrequency) / static_cast<double>(fRate)));
}

long long FramePacing::NextDeadline(const long long iNowQpc, const long long iPeriodQpc)
{
    return iNowQpc + iPeriodQpc;
}

unsigned long FramePacing::RemainingMs(const long long iNowQpc, const long long iDeadlineQpc, const long long iQpcFrequency)
{
    const long long iRemainingTicks = iDeadlineQpc - iNowQpc;
    if (iRemainingTicks <= 0 || iQpcFrequency <= 0)
    {
        return 0;
    }
    //Round up: waking a fraction of a millisecond early would only re-enter the wait.
    return static_cast<unsigned long>((iRemainingTicks * 1000 + iQpcFrequency - 1) / iQpcFrequency);
}

long long FramePacing::TicksTo100ns(const long long iTicks, const long long iQpcFrequency)
{
    if (iTicks <= 0 || iQpcFrequency <= 0)
    {
        return 0;
    }
    return iTicks * ki100nsPerSecond / iQpcFrequency;
}

double FramePacing::ElapsedMs(const long long iPrevQpc, const long long iNowQpc, const long long iQpcFrequency)
{
    if (iQpcFrequency <= 0)
    {
        return 0.0;
    }
    return static_cast<double>(iNowQpc - iPrevQpc) * 1000.0 / static_cast<double>(iQpcFrequency);
}

float FramePacing::ClampedDelta(const long long iPrevQpc, const long long iNowQpc, const long long iQpcFrequency)
{
    if (iQpcFrequency <= 0)
    {
        return 0.0f;
    }
    const double fSeconds = static_cast<double>(iNowQpc - iPrevQpc) / static_cast<double>(iQpcFrequency);
    return static_cast<float>(std::min(std::max(fSeconds, 0.0), kfMaxDeltaSeconds));
}

double FramePacing::OvershootMs(const long long iWakeQpc, const long long iDeadlineQpc, const long long iQpcFrequency)
{
    const long long iLateTicks = iWakeQpc - iDeadlineQpc;
    if (iLateTicks <= 0 || iQpcFrequency <= 0)
    {
        return 0.0;
    }
    return static_cast<double>(iLateTicks) * 1000.0 / static_cast<double>(iQpcFrequency);
}
