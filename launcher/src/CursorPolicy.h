#pragma once

//For RECT only. Pushed to warning level 0 the way stdafx.h does it: this header
//is also compiled into the test project, which builds at /W4 /WX.
#pragma warning(push, 0)
#pragma warning(disable: 4324) //SDK structs padded by the launcher project's /Zp4
#include <windows.h>
#pragma warning(pop)

// Pure cursor-state decision logic for the main loop: this frame's facts in,
// desired clip/visibility out, plus a diff against the state the caller can
// actually observe. Visibility is judged from ShowCursor's own per-thread
// display counter (the value its last call returned), never from
// GetCursorInfo: CURSOR_SHOWING belongs to whichever thread's window last
// received the cursor and says nothing about this thread's counter.
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
        //Walk this thread's display counter to < 0 (hide) or >= 0 (show). The
        //caller loops on ShowCursor's return value, so the walk is exact.
        bool bHide = false;
        bool bShow = false;
    };

    Desired Decide(const Facts& Frame);

    //bClipMatchesDesired comes from GetClipCursor - actual OS state, so an
    //externally cleared clip is corrected within a frame. bClipHeld is the
    //caller's own last-applied clip state: releasing needs to know we hold one,
    //which GetClipCursor cannot tell us (an unclipped cursor reports the whole
    //virtual screen). iDisplayCount is this thread's ShowCursor counter as last
    //returned by ShowCursor; the cursor is visible while it is >= 0.
    Actions Diff(const Desired& Want, const bool bClipMatchesDesired, const bool bClipHeld, const int iDisplayCount);
}
