#pragma once

#include <cstddef>
#include <functional>

//One nav-table row: a control and its four spatial neighbours, indexed by the
//direction order up/down/left/right. 0 = no move.
struct SPadNavEntry
{
    int iControl;
    int iNeighbour[4];
};

//Pure spatial navigation over a dialog's nav table. Control enablement is a
//predicate rather than an IsWindowEnabled() call, so the traversal rules --
//and the no-soft-lock properties they carry -- are testable without a dialog.
namespace PadNavGraph
{
    //True if the control id can take focus (exists in the dialog and enabled).
    using FIsEnabled = std::function<bool(int)>;

    const SPadNavEntry* FindEntry(const SPadNavEntry* pEntries, std::size_t iEntryCount,
                                  int iControl);

    //Returns the control to focus, or 0 for "no move". iCurrentControl may be
    //any id, including one outside the table (0 for "nothing focused").
    //iDirection is 0-3 in up/down/left/right order.
    int Move(const SPadNavEntry* pEntries, std::size_t iEntryCount, int iCurrentControl,
             int iHomeControl, int iDirection, const FIsEnabled& IsEnabled);
}
