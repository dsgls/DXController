#include "doctest.h"
#include "PadActivity.h"

namespace
{
    constexpr int kGraceMs    = 500;
    constexpr int kThresholdPx = 4;
    constexpr unsigned long long kT0 = 1'000'000; //an arbitrary non-zero clock origin
}

TEST_CASE("A fresh state reports neither device active")
{
    const PadActivity::SState S;
    CHECK_FALSE(PadActivity::IsPadActive(S, kT0, kGraceMs));
    CHECK_FALSE(PadActivity::IsMouseActive(S, kT0, kGraceMs));
}

TEST_CASE("Pad activity lasts exactly the grace window")
{
    PadActivity::SState S;
    PadActivity::NotePadActivity(S, kT0);
    CHECK(PadActivity::IsPadActive(S, kT0, kGraceMs));
    CHECK(PadActivity::IsPadActive(S, kT0 + kGraceMs - 1, kGraceMs));
    CHECK_FALSE(PadActivity::IsPadActive(S, kT0 + kGraceMs, kGraceMs));
    CHECK_FALSE(PadActivity::IsPadActive(S, kT0 + kGraceMs + 1, kGraceMs));
}

TEST_CASE("Mouse activity within the grace window suppresses the pad signal")
{
    PadActivity::SState S;
    PadActivity::NotePadActivity(S, kT0);
    PadActivity::NotifyMouseActivity(S, 10, 0, kThresholdPx, kT0 + 10);

    CHECK(PadActivity::IsMouseActive(S, kT0 + 10, kGraceMs));
    CHECK_FALSE(PadActivity::IsPadActive(S, kT0 + 10, kGraceMs));

    //Once the mouse falls out of the window the pad would win again -- but by
    //then its own window has expired too, so both are quiet.
    CHECK_FALSE(PadActivity::IsPadActive(S, kT0 + 600, kGraceMs));
    CHECK_FALSE(PadActivity::IsMouseActive(S, kT0 + 600, kGraceMs));

    //A fresh pad event after the mouse went quiet takes the signal back.
    PadActivity::NotePadActivity(S, kT0 + 600);
    CHECK(PadActivity::IsPadActive(S, kT0 + 600, kGraceMs));
}

TEST_CASE("Raw deltas below the threshold accumulate rather than being discarded")
{
    PadActivity::SState S;
    for (int i = 0; i < 4; ++i)
    {
        PadActivity::NotifyMouseActivity(S, 1, 0, kThresholdPx, kT0 + i);
        CHECK_FALSE(PadActivity::IsMouseActive(S, kT0 + i, kGraceMs)); //4 counts is not yet > 4
    }
    PadActivity::NotifyMouseActivity(S, 1, 0, kThresholdPx, kT0 + 4);
    CHECK(PadActivity::IsMouseActive(S, kT0 + 4, kGraceMs));
}

TEST_CASE("The accumulator resets once the window lapses")
{
    PadActivity::SState S;
    PadActivity::NotifyMouseActivity(S, 4, 0, kThresholdPx, kT0);
    CHECK_FALSE(PadActivity::IsMouseActive(S, kT0, kGraceMs));

    //One count past the 250 ms window starts a new accumulation, so the
    //leftover 4 counts do not help the next single-count packet over the line.
    PadActivity::NotifyMouseActivity(S, 1, 0, kThresholdPx, kT0 + PadActivity::kAccumWindowMs + 1);
    CHECK_FALSE(PadActivity::IsMouseActive(S, kT0 + PadActivity::kAccumWindowMs + 1, kGraceMs));

    //Exactly at the window edge the accumulation continues.
    PadActivity::SState S2;
    PadActivity::NotifyMouseActivity(S2, 4, 0, kThresholdPx, kT0);
    PadActivity::NotifyMouseActivity(S2, 1, 0, kThresholdPx, kT0 + PadActivity::kAccumWindowMs);
    CHECK(PadActivity::IsMouseActive(S2, kT0 + PadActivity::kAccumWindowMs, kGraceMs));
}

TEST_CASE("The threshold is Manhattan distance, not per-axis")
{
    PadActivity::SState S;
    PadActivity::NotifyMouseActivity(S, 3, -3, kThresholdPx, kT0); //|3| + |-3| = 6 > 4
    CHECK(PadActivity::IsMouseActive(S, kT0, kGraceMs));
}

TEST_CASE("A zero-delta packet is ignored entirely")
{
    PadActivity::SState S;
    PadActivity::NotifyMouseActivity(S, 4, 0, kThresholdPx, kT0);
    PadActivity::NotifyMouseActivity(S, 0, 0, kThresholdPx, kT0 + 1);
    CHECK_FALSE(PadActivity::IsMouseActive(S, kT0 + 1, kGraceMs));
    CHECK(S.iRawMouseAccum == 4); //the button-only packet neither added nor reset
}

TEST_CASE("A negative PadActiveGraceMs never expires (pinned pre-fix behavior)")
{
    //The unsigned cast turns -1 into an effectively infinite window: activity
    //from any point in the past still reads as current.
    PadActivity::SState S;
    PadActivity::NotePadActivity(S, 1);
    CHECK(PadActivity::IsPadActive(S, kT0, -1));
    CHECK(PadActivity::IsPadActive(S, 0xFFFFFFFFULL, -1));
}

TEST_CASE("A negative MouseActivityPx makes every raw packet count (pinned pre-fix behavior)")
{
    PadActivity::SState S;
    PadActivity::NotifyMouseActivity(S, 1, 0, -1, kT0);
    CHECK(PadActivity::IsMouseActive(S, kT0, kGraceMs));
}
