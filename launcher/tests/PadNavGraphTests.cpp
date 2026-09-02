#include "doctest.h"
#include "PadNavGraph.h"

#include <set>

namespace
{
    enum { kUp = 0, kDown = 1, kLeft = 2, kRight = 3 };

    //A: B above/below itself is a two-row column; C sits to the right of both.
    //           up   down  left  right
    constexpr SPadNavEntry kTable[] =
    {
        { 1,       0,    2,    0,    3 },
        { 2,       1,    0,    0,    3 },
        { 3,       0,    0,    1,    0 },
    };
    constexpr std::size_t kCount = sizeof(kTable) / sizeof(kTable[0]);

    //Every control enabled unless listed.
    PadNavGraph::FIsEnabled Disabled(std::set<int> Ids)
    {
        return [Ids](const int iControl) { return Ids.count(iControl) == 0; };
    }

    const PadNavGraph::FIsEnabled kAllEnabled = Disabled({});
}

TEST_CASE("A neighbour is followed when it is enabled")
{
    CHECK(PadNavGraph::Move(kTable, kCount, 1, 1, kDown, kAllEnabled) == 2);
    CHECK(PadNavGraph::Move(kTable, kCount, 2, 1, kRight, kAllEnabled) == 3);
}

TEST_CASE("A zero neighbour means no move")
{
    CHECK(PadNavGraph::Move(kTable, kCount, 1, 1, kUp, kAllEnabled) == 0);
}

TEST_CASE("A disabled neighbour is skipped in the same direction")
{
    //1 down -> 2 (disabled) -> 2's down is 0, so no move; but going right from
    //2 with 3 disabled likewise stops.
    CHECK(PadNavGraph::Move(kTable, kCount, 1, 1, kDown, Disabled({2})) == 0);
    CHECK(PadNavGraph::Move(kTable, kCount, 2, 1, kRight, Disabled({3})) == 0);

    //A three-in-a-row column: the middle being disabled hands focus to the end.
    //           up   down  left  right
    constexpr SPadNavEntry Column[] =
    {
        { 10,      0,   11,    0,    0 },
        { 11,     10,   12,    0,    0 },
        { 12,     11,    0,    0,    0 },
    };
    CHECK(PadNavGraph::Move(Column, 3, 10, 10, kDown, Disabled({11})) == 12);
}

TEST_CASE("An all-disabled directional cycle terminates with no move")
{
    //Every row's "down" points at the next, and the last wraps to the first.
    //           up   down  left  right
    constexpr SPadNavEntry Ring[] =
    {
        { 20,      0,   21,    0,    0 },
        { 21,      0,   22,    0,    0 },
        { 22,      0,   20,    0,    0 },
    };
    CHECK(PadNavGraph::Move(Ring, 3, 20, 20, kDown, Disabled({20, 21, 22})) == 0);
}

TEST_CASE("Focus outside the graph snaps to the home control")
{
    //Id 99 is in no row, and 0 stands for nothing focused.
    CHECK(PadNavGraph::Move(kTable, kCount, 99, 3, kUp, kAllEnabled) == 3);
    CHECK(PadNavGraph::Move(kTable, kCount, 0, 3, kRight, kAllEnabled) == 3);
}

TEST_CASE("A disabled home control means no move, not a search onward")
{
    //The home path deliberately skips the disabled-skip walk: 1 has a live
    //"down" neighbour, but an out-of-graph focus with 1 disabled stops dead.
    CHECK(PadNavGraph::Move(kTable, kCount, 99, 1, kDown, Disabled({1})) == 0);
}

TEST_CASE("A zero home control means no move")
{
    CHECK(PadNavGraph::Move(kTable, kCount, 99, 0, kDown, kAllEnabled) == 0);
}

TEST_CASE("FindEntry matches by control id")
{
    CHECK(PadNavGraph::FindEntry(kTable, kCount, 3) == &kTable[2]);
    CHECK(PadNavGraph::FindEntry(kTable, kCount, 99) == nullptr);
    CHECK(PadNavGraph::FindEntry(kTable, 0, 1) == nullptr);
}
