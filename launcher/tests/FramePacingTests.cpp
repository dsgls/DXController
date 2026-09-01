#include "doctest.h"
#include "FramePacing.h"

namespace
{
    //A round frequency keeps the expected tick counts exact.
    constexpr long long kiFreq = 10000000; //10 MHz, i.e. one tick == 100 ns
}

TEST_CASE("FramePacing::EffectiveRate picks the smaller non-zero rate")
{
    CHECK(FramePacing::EffectiveRate(120.0f, 60.0f) == doctest::Approx(60.0f));
    CHECK(FramePacing::EffectiveRate(60.0f, 120.0f) == doctest::Approx(60.0f));
}

TEST_CASE("FramePacing::EffectiveRate treats zero as unlimited, not as the minimum")
{
    CHECK(FramePacing::EffectiveRate(120.0f, 0.0f) == doctest::Approx(120.0f));
    CHECK(FramePacing::EffectiveRate(0.0f, 120.0f) == doctest::Approx(120.0f));
    CHECK(FramePacing::EffectiveRate(0.0f, 0.0f) == doctest::Approx(0.0f));
}

TEST_CASE("FramePacing::EffectivePeriodTicks converts the effective rate to QPC ticks")
{
    //100 Hz at 10 MHz -> 100000 ticks (10 ms).
    CHECK(FramePacing::EffectivePeriodTicks(100.0f, 0.0f, kiFreq) == 100000);
    CHECK(FramePacing::EffectivePeriodTicks(100.0f, 200.0f, kiFreq) == 100000);
    //1 fps is a legal FPSLimit value.
    CHECK(FramePacing::EffectivePeriodTicks(1.0f, 0.0f, kiFreq) == kiFreq);
}

TEST_CASE("FramePacing::EffectivePeriodTicks returns zero when both rates are unlimited")
{
    CHECK(FramePacing::EffectivePeriodTicks(0.0f, 0.0f, kiFreq) == 0);
}

TEST_CASE("FramePacing::NextDeadline anchors to now and does not accumulate")
{
    CHECK(FramePacing::NextDeadline(1000, 250) == 1250);
    //An overrun (waking 5000 ticks late) still schedules exactly one period out.
    CHECK(FramePacing::NextDeadline(6000, 250) == 6250);
    CHECK(FramePacing::NextDeadline(1000, 0) == 1000);
}

TEST_CASE("FramePacing::RemainingMs rounds up so the wait never returns early")
{
    //15000 ticks == 1.5 ms -> 2 ms.
    CHECK(FramePacing::RemainingMs(0, 15000, kiFreq) == 2u);
    //Exactly 10 ms stays 10 ms.
    CHECK(FramePacing::RemainingMs(0, 100000, kiFreq) == 10u);
}

TEST_CASE("FramePacing::RemainingMs is zero once the deadline has passed")
{
    CHECK(FramePacing::RemainingMs(100000, 100000, kiFreq) == 0u);
    CHECK(FramePacing::RemainingMs(200000, 100000, kiFreq) == 0u);
}

TEST_CASE("FramePacing::TicksTo100ns converts a period to timer units")
{
    //At 10 MHz one tick is already 100 ns.
    CHECK(FramePacing::TicksTo100ns(100000, kiFreq) == 100000);
    //At 1 MHz one tick is 1 us == ten 100 ns units.
    CHECK(FramePacing::TicksTo100ns(1000, 1000000) == 10000);
    CHECK(FramePacing::TicksTo100ns(0, kiFreq) == 0);
}

TEST_CASE("FramePacing::ClampedDelta converts a tick span to seconds")
{
    CHECK(FramePacing::ClampedDelta(0, 100000, kiFreq) == doctest::Approx(0.01f));
}

TEST_CASE("FramePacing::ClampedDelta clamps a long stall to 0.2 s")
{
    CHECK(FramePacing::ClampedDelta(0, 50 * kiFreq, kiFreq) == doctest::Approx(0.2f));
}

TEST_CASE("FramePacing::ClampedDelta clamps a backwards QPC to zero")
{
    CHECK(FramePacing::ClampedDelta(100000, 0, kiFreq) == doctest::Approx(0.0f));
}

TEST_CASE("FramePacing::OvershootMs measures how late the wake was")
{
    //15000 ticks past the deadline == 1.5 ms.
    CHECK(FramePacing::OvershootMs(115000, 100000, kiFreq) == doctest::Approx(1.5));
}

TEST_CASE("FramePacing::OvershootMs never reports a negative overshoot")
{
    CHECK(FramePacing::OvershootMs(90000, 100000, kiFreq) == doctest::Approx(0.0));
}
