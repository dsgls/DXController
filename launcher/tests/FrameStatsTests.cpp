#include "doctest.h"
#include "FrameStats.h"

#include <cmath>

TEST_CASE("FrameStats::Compute with zero samples")
{
    const FrameStats::Stats Result = FrameStats::Compute(nullptr, 0);
    CHECK(Result.iCount == 0);
    CHECK(Result.fAvg == 0.0);
    CHECK(Result.fP50 == 0.0);
    CHECK(Result.fP99 == 0.0);
    CHECK(Result.fMax == 0.0);
    CHECK(Result.fStdDev == 0.0);
}

TEST_CASE("FrameStats::Compute with one sample")
{
    const double Samples[] = { 7.5 };
    const FrameStats::Stats Result = FrameStats::Compute(Samples, 1);
    CHECK(Result.iCount == 1);
    CHECK(Result.fAvg == doctest::Approx(7.5));
    CHECK(Result.fP50 == doctest::Approx(7.5));
    CHECK(Result.fP99 == doctest::Approx(7.5));
    CHECK(Result.fMax == doctest::Approx(7.5));
    CHECK(Result.fStdDev == doctest::Approx(0.0));
}

TEST_CASE("FrameStats::Compute average and max over an unsorted span")
{
    const double Samples[] = { 3.0, 1.0, 2.0, 5.0, 4.0 };
    const FrameStats::Stats Result = FrameStats::Compute(Samples, 5);
    CHECK(Result.iCount == 5);
    CHECK(Result.fAvg == doctest::Approx(3.0));
    CHECK(Result.fMax == doctest::Approx(5.0));
}

TEST_CASE("FrameStats::Compute nearest-rank percentiles on a known set")
{
    //Ascending: 1..10. Nearest-rank: index = ceil(p*n) - 1, clamped.
    double Samples[10];
    for (int i = 0; i < 10; ++i)
    {
        Samples[i] = static_cast<double>(10 - i); //deliberately unsorted (descending)
    }
    const FrameStats::Stats Result = FrameStats::Compute(Samples, 10);
    CHECK(Result.iCount == 10);
    //p50: ceil(0.5*10)-1 = 4 -> sorted[4] == 5
    CHECK(Result.fP50 == doctest::Approx(5.0));
    //p99: ceil(0.99*10)-1 = ceil(9.9)-1 = 10-1 = 9 -> sorted[9] == 10 (== max)
    CHECK(Result.fP99 == doctest::Approx(10.0));
    CHECK(Result.fMax == doctest::Approx(10.0));
}

TEST_CASE("FrameStats::Compute p99 on a small sample count clamps into range")
{
    const double Samples[] = { 1.0, 2.0 };
    const FrameStats::Stats Result = FrameStats::Compute(Samples, 2);
    CHECK(Result.iCount == 2);
    //p99: ceil(0.99*2)-1 = ceil(1.98)-1 = 2-1 = 1 -> sorted[1] == 2.0 (== max)
    CHECK(Result.fP99 == doctest::Approx(2.0));
}

TEST_CASE("FrameStats::Compute standard deviation on a known set")
{
    //Population stdev of {2, 4, 4, 4, 5, 5, 7, 9} is 2.0 (textbook example).
    const double Samples[] = { 2.0, 4.0, 4.0, 4.0, 5.0, 5.0, 7.0, 9.0 };
    const FrameStats::Stats Result = FrameStats::Compute(Samples, 8);
    CHECK(Result.iCount == 8);
    CHECK(Result.fAvg == doctest::Approx(5.0));
    CHECK(Result.fStdDev == doctest::Approx(2.0));
}
