#include "PadNavGraph.h"

namespace PadNavGraph
{

const SPadNavEntry* FindEntry(const SPadNavEntry* const pEntries, const std::size_t iEntryCount,
                              const int iControl)
{
    for (std::size_t i = 0; i < iEntryCount; ++i)
    {
        if (pEntries[i].iControl == iControl)
        {
            return &pEntries[i];
        }
    }
    return nullptr;
}

int Move(const SPadNavEntry* const pEntries, const std::size_t iEntryCount,
         const int iCurrentControl, const int iHomeControl, const int iDirection,
         const FIsEnabled& IsEnabled)
{
    const SPadNavEntry* const pEntry = FindEntry(pEntries, iEntryCount, iCurrentControl);

    int iTarget;
    if (!pEntry)
    {
        //Focus is outside the nav graph (e.g. the user Tabbed onto a SysLink,
        //which pads can't reach) -- snap back to the home control. Deliberately
        //without the skip-disabled walk below: a disabled home control means no
        //move, not a search onward.
        iTarget = iHomeControl;
    }
    else
    {
        iTarget = pEntry->iNeighbour[iDirection];
        //Skip disabled controls by following the same direction onward. The
        //iteration cap guards against an all-disabled directional cycle.
        for (std::size_t iGuard = 0; iTarget != 0 && iGuard < iEntryCount; ++iGuard)
        {
            if (IsEnabled(iTarget))
            {
                break;
            }
            const SPadNavEntry* const pNext = FindEntry(pEntries, iEntryCount, iTarget);
            iTarget = pNext ? pNext->iNeighbour[iDirection] : 0;
        }
    }

    if (iTarget == 0 || !IsEnabled(iTarget))
    {
        return 0;
    }
    return iTarget;
}

}
