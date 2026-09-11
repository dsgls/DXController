#include "doctest.h"
#include "CursorPolicy.h"

namespace
{
    //Foreground, fullscreen, raw input, mouse sitting inside the client area:
    //the state in which the loop clips and hides.
    CursorPolicy::Facts ClippedGameplayFacts()
    {
        CursorPolicy::Facts Frame;
        Frame.bForeground = true;
        Frame.bFullscreen = true;
        Frame.bRawInput = true;
        Frame.bMouseOverWindow = true;
        Frame.bMouseInClientRect = true;
        Frame.rClientScreen = RECT{ 0, 0, 1920, 1080 };
        return Frame;
    }
}

TEST_CASE("CursorPolicy clips to the client rect when fullscreen with raw input")
{
    const CursorPolicy::Desired Want = CursorPolicy::Decide(ClippedGameplayFacts());
    CHECK(Want.bClip);
    CHECK(Want.rClip.right == 1920);
    CHECK(Want.rClip.bottom == 1080);
}

TEST_CASE("CursorPolicy does not clip without raw input or without fullscreen")
{
    CursorPolicy::Facts Frame = ClippedGameplayFacts();
    Frame.bRawInput = false;
    CHECK_FALSE(CursorPolicy::Decide(Frame).bClip);

    Frame = ClippedGameplayFacts();
    Frame.bFullscreen = false;
    CHECK_FALSE(CursorPolicy::Decide(Frame).bClip);
}

TEST_CASE("CursorPolicy releases the clip and shows the cursor when not foreground")
{
    CursorPolicy::Facts Frame = ClippedGameplayFacts();
    Frame.bForeground = false;
    Frame.bPadActive = true; //Would otherwise force-hide

    const CursorPolicy::Desired Want = CursorPolicy::Decide(Frame);
    CHECK_FALSE(Want.bClip);
    CHECK(Want.bCursorVisible);
    CHECK_FALSE(Want.bSyncCursorToRootPos);
}

TEST_CASE("CursorPolicy hides the cursor while the mouse is over the client area")
{
    CHECK_FALSE(CursorPolicy::Decide(ClippedGameplayFacts()).bCursorVisible);
}

TEST_CASE("CursorPolicy hides the cursor whenever the pad is the active source")
{
    CursorPolicy::Facts Frame = ClippedGameplayFacts();
    Frame.bMouseOverWindow = false;
    Frame.bMouseInClientRect = false;
    Frame.bCaptured = false;
    Frame.bPadActive = true;
    CHECK_FALSE(CursorPolicy::Decide(Frame).bCursorVisible);
}

TEST_CASE("CursorPolicy shows the cursor when it sits outside the client rect")
{
    //Keeps the resize cursor visible on the window edges.
    CursorPolicy::Facts Frame = ClippedGameplayFacts();
    Frame.bMouseInClientRect = false;
    CHECK(CursorPolicy::Decide(Frame).bCursorVisible);
}

TEST_CASE("CursorPolicy shows the cursor when it is inside the rect but over another window")
{
    //Cursor over the preferences window stacked on top of the game.
    CursorPolicy::Facts Frame = ClippedGameplayFacts();
    Frame.bMouseOverWindow = false;
    CHECK(CursorPolicy::Decide(Frame).bCursorVisible);
}

TEST_CASE("CursorPolicy hides the cursor for a capturing window even when the mouse is elsewhere")
{
    CursorPolicy::Facts Frame = ClippedGameplayFacts();
    Frame.bMouseOverWindow = false;
    Frame.bCaptured = true;
    CHECK_FALSE(CursorPolicy::Decide(Frame).bCursorVisible);
}

TEST_CASE("CursorPolicy asks for a cursor sync only on the fullscreen menu rising edge")
{
    CursorPolicy::Facts Frame = ClippedGameplayFacts();
    Frame.bInMenu = true;
    Frame.bPrevInMenu = false;
    CHECK(CursorPolicy::Decide(Frame).bSyncCursorToRootPos);

    Frame.bPrevInMenu = true; //Already in the menu last frame
    CHECK_FALSE(CursorPolicy::Decide(Frame).bSyncCursorToRootPos);
}

TEST_CASE("CursorPolicy does not sync the cursor outside fullscreen raw input")
{
    CursorPolicy::Facts Frame = ClippedGameplayFacts();
    Frame.bInMenu = true;
    Frame.bFullscreen = false;
    CHECK_FALSE(CursorPolicy::Decide(Frame).bSyncCursorToRootPos);

    Frame = ClippedGameplayFacts();
    Frame.bInMenu = true;
    Frame.bRawInput = false;
    CHECK_FALSE(CursorPolicy::Decide(Frame).bSyncCursorToRootPos);
}

TEST_CASE("CursorPolicy::Diff sets a clip only when the OS clip does not already match")
{
    CursorPolicy::Desired Want;
    Want.bClip = true;

    const CursorPolicy::Actions Stale = CursorPolicy::Diff(Want, false, true, 0);
    CHECK(Stale.bSetClip);
    CHECK_FALSE(Stale.bReleaseClip);

    const CursorPolicy::Actions Steady = CursorPolicy::Diff(Want, true, true, 0);
    CHECK_FALSE(Steady.bSetClip);
    CHECK_FALSE(Steady.bReleaseClip);
}

TEST_CASE("CursorPolicy::Diff releases a clip only while one is held")
{
    CursorPolicy::Desired Want; //No clip wanted

    CHECK(CursorPolicy::Diff(Want, false, true, 0).bReleaseClip);
    CHECK_FALSE(CursorPolicy::Diff(Want, false, false, 0).bReleaseClip);
}

TEST_CASE("CursorPolicy::Diff judges visibility from the thread's display counter")
{
    CursorPolicy::Desired Hide;
    Hide.bCursorVisible = false;

    //Visible at 0 and at any positive count (a ratcheted counter still shows).
    const int aVisibleCounts[] = { 0, 1, 19190 };
    for (const int iCount : aVisibleCounts)
    {
        const CursorPolicy::Actions ToHidden = CursorPolicy::Diff(Hide, false, false, iCount);
        CHECK(ToHidden.bHide);
        CHECK_FALSE(ToHidden.bShow);
    }

    CursorPolicy::Desired Show;
    const int aHiddenCounts[] = { -1, -30 };
    for (const int iCount : aHiddenCounts)
    {
        const CursorPolicy::Actions ToShown = CursorPolicy::Diff(Show, false, false, iCount);
        CHECK(ToShown.bShow);
        CHECK_FALSE(ToShown.bHide);
    }
}

TEST_CASE("CursorPolicy::Diff does nothing while visibility already matches")
{
    CursorPolicy::Desired Hide;
    Hide.bCursorVisible = false;
    const CursorPolicy::Actions Hidden = CursorPolicy::Diff(Hide, false, false, -1);
    CHECK_FALSE(Hidden.bHide);
    CHECK_FALSE(Hidden.bShow);

    CursorPolicy::Desired Show;
    const CursorPolicy::Actions Shown = CursorPolicy::Diff(Show, false, false, 0);
    CHECK_FALSE(Shown.bHide);
    CHECK_FALSE(Shown.bShow);
}
