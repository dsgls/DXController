#include "doctest.h"
#include "FixAppNavTable.h"
#include "PadNavGraph.h"

#include <set>
#include <vector>

namespace
{
    constexpr std::size_t kCount = sizeof(kFixAppNavTable) / sizeof(kFixAppNavTable[0]);
}

//A neighbour id with no row of its own is a dead end the pad cannot leave in
//the same direction, and usually a typo'd resource id.
TEST_CASE("Every neighbour the FixApp table names is itself a row")
{
    for (const SPadNavEntry& Entry : kFixAppNavTable)
    {
        for (const int iNeighbour : Entry.iNeighbour)
        {
            if (iNeighbour != 0)
            {
                INFO("control ", Entry.iControl, " names neighbour ", iNeighbour);
                CHECK(PadNavGraph::FindEntry(kFixAppNavTable, kCount, iNeighbour) != nullptr);
            }
        }
    }
}

TEST_CASE("The FixApp table names each control once")
{
    std::set<int> Seen;
    for (const SPadNavEntry& Entry : kFixAppNavTable)
    {
        INFO("control ", Entry.iControl);
        CHECK(Seen.insert(Entry.iControl).second);
    }
}

//A row no walk from the home control reaches is a control the pad can never
//get to, which is exactly the soft-lock the nav graph exists to prevent.
TEST_CASE("Every FixApp row is reachable from the home control")
{
    std::set<int>    Reached{ kFixAppNavHome };
    std::vector<int> Pending{ kFixAppNavHome };
    while (!Pending.empty())
    {
        const int iControl = Pending.back();
        Pending.pop_back();
        const SPadNavEntry* const pEntry = PadNavGraph::FindEntry(kFixAppNavTable, kCount, iControl);
        REQUIRE(pEntry != nullptr);
        for (const int iNeighbour : pEntry->iNeighbour)
        {
            if (iNeighbour != 0 && Reached.insert(iNeighbour).second)
            {
                Pending.push_back(iNeighbour);
            }
        }
    }

    for (const SPadNavEntry& Entry : kFixAppNavTable)
    {
        INFO("control ", Entry.iControl);
        CHECK(Reached.count(Entry.iControl) == 1);
    }
}
