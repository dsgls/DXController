#include "CursorPolicy.h"

CursorPolicy::Desired CursorPolicy::Decide(const Facts& Frame)
{
    Desired Want;

    //An alt-tabbed (or hung) game must never hold a clip or a hidden cursor.
    if (!Frame.bForeground)
    {
        return Want;
    }

    //Raw input blocks the engine's own cursor confinement, so the clip is what
    //keeps the cursor on the game's monitor in fullscreen on multi-monitor setups.
    if (Frame.bRawInput && Frame.bFullscreen)
    {
        Want.bClip = true;
        Want.rClip = Frame.rClientScreen;
        Want.bSyncCursorToRootPos = Frame.bInMenu && !Frame.bPrevInMenu;
    }

    //Hide while the pad drives, or while the mouse is over the game's own client
    //area. Staying visible outside that keeps the edge resize cursors and any
    //window stacked on top (the preferences dialog) usable.
    const bool bHide = Frame.bPadActive || (Frame.bMouseInClientRect && (Frame.bMouseOverWindow || Frame.bCaptured));
    Want.bCursorVisible = !bHide;

    return Want;
}

CursorPolicy::Actions CursorPolicy::Diff(const Desired& Want, const bool bClipMatchesDesired, const bool bClipHeld, const bool bCursorShowing)
{
    Actions Result;
    Result.bSetClip = Want.bClip && !bClipMatchesDesired;
    Result.bReleaseClip = !Want.bClip && bClipHeld;
    Result.bShowOneStep = Want.bCursorVisible && !bCursorShowing;
    Result.bHideOneStep = !Want.bCursorVisible && bCursorShowing;
    return Result;
}
