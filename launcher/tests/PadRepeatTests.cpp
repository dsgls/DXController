#include "doctest.h"
#include "PadRepeat.h"

namespace
{
    //Arbitrary but distinct masks, matching CDialogPadNav's direction order.
    constexpr WORD kUp    = 1 << 0;
    constexpr WORD kDown  = 1 << 1;
    constexpr WORD kLeft  = 1 << 2;
    constexpr WORD kRight = 1 << 3;
    constexpr WORD kDirBits[4] = { kUp, kDown, kLeft, kRight };

    constexpr ULONGLONG kT0 = 1'000'000; //an arbitrary non-zero clock origin
}

TEST_CASE("A press edge fires immediately and arms the initial delay")
{
    PadRepeat::SRepeatState aState[4] = {};
    bool bFired[4] = {};

    PadRepeat::Tick(aState, kDirBits, 0, kUp, kT0, bFired);
    CHECK(bFired[0]);
    CHECK_FALSE(bFired[1]);
    CHECK(aState[0].bDown);
    CHECK(aState[0].iNextFireMs == kT0 + PadRepeat::kRepeatDelayMs);
}

TEST_CASE("A held direction stays silent until the initial delay elapses")
{
    PadRepeat::SRepeatState aState[4] = {};
    bool bFired[4] = {};
    PadRepeat::Tick(aState, kDirBits, 0, kUp, kT0, bFired);

    PadRepeat::Tick(aState, kDirBits, kUp, kUp, kT0 + PadRepeat::kRepeatDelayMs - 1, bFired);
    CHECK_FALSE(bFired[0]);

    //The deadline itself fires and re-arms at the shorter repeat interval.
    const ULONGLONG iDue = kT0 + PadRepeat::kRepeatDelayMs;
    PadRepeat::Tick(aState, kDirBits, kUp, kUp, iDue, bFired);
    CHECK(bFired[0]);
    CHECK(aState[0].iNextFireMs == iDue + PadRepeat::kRepeatIntervalMs);

    PadRepeat::Tick(aState, kDirBits, kUp, kUp, iDue + PadRepeat::kRepeatIntervalMs - 1, bFired);
    CHECK_FALSE(bFired[0]);
    PadRepeat::Tick(aState, kDirBits, kUp, kUp, iDue + PadRepeat::kRepeatIntervalMs, bFired);
    CHECK(bFired[0]);
}

TEST_CASE("Releasing a direction resets its slot")
{
    PadRepeat::SRepeatState aState[4] = {};
    bool bFired[4] = {};
    PadRepeat::Tick(aState, kDirBits, 0, kUp, kT0, bFired);

    PadRepeat::Tick(aState, kDirBits, kUp, 0, kT0 + 1, bFired);
    CHECK_FALSE(bFired[0]);
    CHECK_FALSE(aState[0].bDown);
    CHECK(aState[0].iNextFireMs == 0);

    //Long past the old deadline, an un-held direction still fires nothing.
    PadRepeat::Tick(aState, kDirBits, 0, 0, kT0 + 10 * PadRepeat::kRepeatDelayMs, bFired);
    CHECK_FALSE(bFired[0]);
}

TEST_CASE("No direction fires without its button held")
{
    PadRepeat::SRepeatState aState[4] = {};
    bool bFired[4] = { true, true, true, true };

    //A non-direction bit is held; every slot must report not fired.
    PadRepeat::Tick(aState, kDirBits, 0, 1 << 8, kT0, bFired);
    for (const bool b : bFired)
    {
        CHECK_FALSE(b);
    }
}

TEST_CASE("Directions repeat independently")
{
    PadRepeat::SRepeatState aState[4] = {};
    bool bFired[4] = {};

    PadRepeat::Tick(aState, kDirBits, 0, kUp, kT0, bFired);
    //Left pressed later: it is on its own initial delay while up repeats.
    PadRepeat::Tick(aState, kDirBits, kUp, kUp | kLeft, kT0 + PadRepeat::kRepeatDelayMs, bFired);
    CHECK(bFired[0]); //up: repeat due
    CHECK(bFired[2]); //left: press edge
    CHECK(aState[0].iNextFireMs == kT0 + PadRepeat::kRepeatDelayMs + PadRepeat::kRepeatIntervalMs);
    CHECK(aState[2].iNextFireMs == kT0 + 2 * PadRepeat::kRepeatDelayMs);
}
