#include "FrameStats.h"

#include <algorithm>
#include <cmath>
#include <vector>

namespace
{
    //Nearest-rank percentile on an ascending-sorted span.
    double Percentile(const std::vector<double>& Sorted, const double fPercentile)
    {
        const size_t iCount = Sorted.size();
        const size_t iRank = static_cast<size_t>(std::ceil(fPercentile * static_cast<double>(iCount)));
        const size_t iIndex = (iRank == 0) ? 0 : std::min(iRank, iCount) - 1;
        return Sorted[iIndex];
    }
}

FrameStats::Stats FrameStats::Compute(const double* const pSamples, const size_t iCount)
{
    Stats Result;
    if (iCount == 0)
    {
        return Result;
    }

    std::vector<double> Sorted(pSamples, pSamples + iCount);
    std::sort(Sorted.begin(), Sorted.end());

    double fSum = 0.0;
    for (const double fSample : Sorted)
    {
        fSum += fSample;
    }
    const double fAvg = fSum / static_cast<double>(iCount);

    double fSquaredDiffSum = 0.0;
    for (const double fSample : Sorted)
    {
        const double fDiff = fSample - fAvg;
        fSquaredDiffSum += fDiff * fDiff;
    }

    Result.iCount = iCount;
    Result.fAvg = fAvg;
    Result.fP50 = Percentile(Sorted, 0.50);
    Result.fP99 = Percentile(Sorted, 0.99);
    Result.fMax = Sorted.back();
    Result.fStdDev = std::sqrt(fSquaredDiffSum / static_cast<double>(iCount));
    return Result;
}
