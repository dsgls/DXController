#pragma once

#include <cstddef>

// Pure stats math over a span of millisecond samples (frame times, gate/deadline
// lateness, etc.). No syscalls, no engine headers - see development.md's
// pure-unit-layer entry.
namespace FrameStats
{
    struct Stats
    {
        size_t iCount = 0;
        double fAvg = 0.0;
        double fP50 = 0.0;
        double fP99 = 0.0;
        double fMax = 0.0;
        double fStdDev = 0.0; //Population standard deviation (divides by iCount, not iCount-1)
    };

    //Percentile convention: nearest-rank on the ascending-sorted samples -
    //index = ceil(fPercentile * iCount) - 1, clamped to [0, iCount-1].
    //pSamples is read-only; the function sorts a local copy.
    Stats Compute(const double* const pSamples, const size_t iCount);
}
