#pragma once

//For RECT only. Pushed to warning level 0 the way stdafx.h does it: this header
//is also compiled into the test project, which builds at /W4 /WX.
#pragma warning(push, 0)
#pragma warning(disable: 4324) //SDK structs padded by the launcher project's /Zp4
#include <windows.h>
#pragma warning(pop)

// Pure cursor-state decision logic for the main loop: this frame's facts in,
// desired clip/visibility out, plus a diff against the actual OS state so the
// caller applies at most one ClipCursor/ShowCursor step per transition
// (ShowCursor moves a counter by +-1 per call - repeated calls run it away).
// No syscalls, no engine headers - see development.md's pure-unit-layer entry.
namespace CursorPolicy
{
    struct Facts
    {
        //Foreground, NOT focus: the clip and the hidden cursor follow the window
        //the user is actually working in. GetFocus() is thread-queue focus, which
        //tracks the launcher's own windows rather than the user's active one.
        bool bForeground = false;
        bool bFullscreen = false;
        bool bRawInput = false;
        bool bInMenu = false;
        bool bPrevInMenu = false;
        bool bPadActive = false;
        bool bMouseOverWindow = false;
        bool bMouseInClientRect = false;
        bool bCaptured = false;
        RECT rClientScreen = {};
    };

    struct Desired
    {
        bool bClip = false;
        RECT rClip = {};
        bool bCursorVisible = true;
        //Fullscreen raw-input menu entry: the Windows cursor is elsewhere, so it
        //is snapped onto the game's own cursor position on the rising edge.
        bool bSyncCursorToRootPos = false;
    };

    struct Actions
    {
        bool bSetClip = false;
        bool bReleaseClip = false;
        bool bShowOneStep = false;
        bool bHideOneStep = false;
    };

    Desired Decide(const Facts& Frame);

    //bClipMatchesDesired comes from GetClipCursor, bCursorShowing from
    //GetCursorInfo's CURSOR_SHOWING - actual OS state, not a blind cache, so an
    //externally cleared clip or a foreign ShowCursor is corrected within a frame.
    //bClipHeld is the caller's own last-applied clip state: releasing needs to
    //know we hold one, which GetClipCursor cannot tell us (an unclipped cursor
    //reports the whole virtual screen).
    Actions Diff(const Desired& Want, const bool bClipMatchesDesired, const bool bClipHeld, const bool bCursorShowing);
}
