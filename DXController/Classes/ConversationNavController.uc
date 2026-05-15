//=============================================================================
// ConversationNavController — gamepad navigation for in-world conversations.
//
// Covers BOTH ConWindow (non-interactive first-person speech) and
// ConWindowActive (third-person interactive with choice list and
// cinematic mode). One controller class, two registry entries.
//
// Bindings:
//   speech mode:   A / B    -> conPlay.PlayNextEvent (advance)
//                  D-pad    -> consumed no-op
//   choice mode:   D-pad U/D-> wrap-aware focus cycle through conChoices[]
//                  D-pad L/R-> consumed no-op
//                  A        -> PressButton on focused choice; clear focus
//                  B        -> consumed no-op (no accidental conv exit)
//   cinematic:     A / B    -> AbortCinematicConvo (ConWindowActive only)
//                  D-pad    -> consumed no-op
//
// AllowsMenuToggle() returns false so Start/Back don't open the persona
// menu on top of an active conversation, and so B routes to HandleActivate
// instead of being synthesised as Escape on the PushWindow stack.
//
// Casts:
//   ConWindow(screen)        for conPlay access and bForcePlay test
//                            (both fields are declared on ConWindow base).
//   ConWindowActive(screen)  for numChoices, conChoices[], AbortCinematicConvo,
//                            and the bGamepadMode setter (overlay var).
//
// See docs/superpowers/specs/2026-05-15-conversation-nav-design.md
//=============================================================================
class ConversationNavController extends MenuNavController;

// ---- Attach / Detach -------------------------------------------------------

function Attach(Window s)
{
    local ConWindowActive cwa;

    Super.Attach(s);

    cwa = ConWindowActive(s);
    if (cwa != None)
        cwa.bGamepadMode = true;

    class'DXControllerDebug'.static.DebugLog(
        "DXC-CONV ATTACH screen=" $ string(s.Class)
        $ " numChoices=" $ string(GetNumChoices()));
}

function Detach()
{
    local ConWindowActive cwa;

    if (screen != None)
    {
        cwa = ConWindowActive(screen);
        if (cwa != None)
            cwa.bGamepadMode = false;
        class'DXControllerDebug'.static.DebugLog(
            "DXC-CONV DETACH screen=" $ string(screen.Class));
    }
    Super.Detach();
}

// ---- Mode helpers ----------------------------------------------------------

function int GetNumChoices()
{
    local ConWindowActive cwa;
    cwa = ConWindowActive(screen);
    if (cwa == None)
        return 0;
    return cwa.numChoices;
}

function bool IsCinematic()
{
    local ConWindow cw;
    cw = ConWindow(screen);
    if (cw == None)
        return false;
    return cw.bForcePlay;
}

function bool IsChoiceMode()
{
    return GetNumChoices() > 0 && !IsCinematic();
}

// ---- InitFocus -------------------------------------------------------------

// Called from Super.Attach and re-run each frame by
// ControllerRootWindow.Tick (deferred-focus-init block) until
// focused != None. Speech-mode convos legitimately leave focused = None
// (no list to highlight); the retry only "succeeds" once a choice list
// appears.
function InitFocus()
{
    local ConWindowActive cwa;

    cwa = ConWindowActive(screen);
    if (cwa == None || cwa.numChoices <= 0)
    {
        focused = None;
        focusIndex = -1;
        return;
    }

    focusIndex = 0;
    focused = cwa.conChoices[0];
    ApplyChoiceHighlight();

    class'DXControllerDebug'.static.DebugLog(
        "DXC-CONV INIT-FOCUS focusIndex=0 numChoices="
        $ string(cwa.numChoices));
}

// Drive vanilla ConChoiceWindow / ButtonWindow's hover indicator (a
// solid blue tile + yellow text, wired by DisplayChoice's
// SetButtonTextures / SetButtonColors / SetTextColors calls) by moving
// the underlying cursor position to the focused button's centre. The
// engine's native hover-detection loop polls cursor position each
// frame and dispatches MouseEnteredWindow / MouseLeftWindow + updates
// ButtonWindow's curTileColor / curTextColor accordingly. Direct
// script-side dispatch of those events doesn't update the native
// state — hover is position-driven, not event-driven.
//
// ShowCursor(False) hides the cursor sprite but (per CLAUDE.md
// "Source overlay model" note about hover detection) does NOT disable
// position-driven hover, so SetCursorPos still moves the highlight
// while the cursor remains invisible. The lastCursorX/Y baseline on
// ControllerRootWindow is updated to match so the Tick cursor-poll
// doesn't spuriously flip to CM_Mouse on our own teleport.
//
// We do this instead of drawing a MenuFocusOverlay frame so the user
// sees ONE focus indicator (the vanilla one), not two stacked on top
// of each other. GetFocusedRect returns false below to suppress the
// frame for conversation screens specifically; other controllers
// (persona / menu / list / etc.) continue to use the frame overlay.
function ApplyChoiceHighlight()
{
    local Window rootWin;
    local ControllerRootWindow crw;
    local float cx, cy;

    if (focused == None)
        return;
    if (focused.width <= 0 || focused.height <= 0)
        return;  // layout not settled yet; Tick will retry next frame

    rootWin = focused.GetRootWindow();
    if (rootWin == None)
        return;

    // Convert button-local centre to root-window coords.
    focused.ConvertCoordinates(focused,
        focused.width * 0.5, focused.height * 0.5,
        rootWin, cx, cy);

    rootWin.SetCursorPos(cx, cy);

    // Keep the cursor-poll baseline in sync — without this, the next
    // Tick would see (curX, curY) != (lastCursorX, lastCursorY) and
    // flip to CM_Mouse, fighting the gamepad focus we just set.
    crw = ControllerRootWindow(rootWin);
    if (crw != None)
    {
        crw.lastCursorX = cx;
        crw.lastCursorY = cy;
    }
}

// ---- D-pad -----------------------------------------------------------------

function bool HandleDPad(int dx, int dy)
{
    local ConWindowActive cwa;
    local int n, oldIndex;

    // Cinematic: vanilla returns False for all non-Escape keys when
    // bForcePlay (ConWindowActive.uc:423-434), so there's nothing
    // meaningful to forward. Consume.
    if (IsCinematic())
        return true;

    // Speech mode: no list to navigate. Consume so D-pad doesn't fall
    // through to player movement bindings underneath.
    if (!IsChoiceMode())
        return true;

    // Choice mode: vertical wrap-aware cycle. Horizontal is consumed.
    if (dy == 0)
        return true;

    cwa = ConWindowActive(screen);
    n = cwa.numChoices;
    if (n <= 0)
        return true;

    oldIndex = focusIndex;
    // UScript % keeps sign of dividend; add n before mod to handle dy = -1.
    focusIndex = (focusIndex + dy + n) % n;
    focused = cwa.conChoices[focusIndex];
    ApplyChoiceHighlight();

    class'DXControllerDebug'.static.DebugLog(
        "DXC-CONV DPAD dy=" $ string(dy)
        $ " focusIndex=" $ string(oldIndex) $ "->" $ string(focusIndex));
    return true;
}

// ---- Activate (A, B, X, Y, R-stick click) ---------------------------------

function bool HandleActivate(byte button)
{
    local ConWindow cw;
    local ConWindowActive cwa;
    local int committedIndex;

    // Only A (200) and B (201) are meaningful here. X/Y/R-stick-click
    // are consumed (return true) so they don't trigger any default
    // behaviour underneath.
    if (button != 200 && button != 201)
        return true;

    cw = ConWindow(screen);
    if (cw == None)
        return true;     // defensive

    cwa = ConWindowActive(screen);

    // Cinematic: A/B abort. Only ConWindowActive has AbortCinematicConvo;
    // ConWindow + bForcePlay is an unused configuration in practice.
    if (cw.bForcePlay)
    {
        if (cwa != None)
        {
            cwa.AbortCinematicConvo();
            class'DXControllerDebug'.static.DebugLog("DXC-CONV CINEMATIC-ABORT");
        }
        return true;
    }

    // Choice mode: A commits, B is no-op.
    if (cwa != None && cwa.numChoices > 0)
    {
        if (button == 200)        // A
        {
            if (focused != None && ConChoiceWindow(focused) != None)
            {
                committedIndex = focusIndex;
                ConChoiceWindow(focused).PressButton();
                // Clear focus state immediately. PressButton -> ButtonActivated
                // -> PlayChoice -> Clear -> DestroyChildren zeros numChoices
                // and destroys the ConChoiceWindow on the same frame; without
                // this clear, focused points at a freed window for one frame
                // before Tick's deferred-init reconciles. InitFocus on the
                // next frame correctly sees numChoices == 0 and leaves
                // focused = None until the next list appears.
                focused = None;
                focusIndex = -1;
                class'DXControllerDebug'.static.DebugLog(
                    "DXC-CONV COMMIT focusIndex=" $ string(committedIndex));
            }
            return true;
        }
        // B in choice mode: consumed no-op.
        class'DXControllerDebug'.static.DebugLog("DXC-CONV B-NOOP");
        return true;
    }

    // Speech mode: A and B both advance.
    if (cw.conPlay != None)
    {
        cw.conPlay.PlayNextEvent();
        class'DXControllerDebug'.static.DebugLog(
            "DXC-CONV ADVANCE btn=" $ string(button));
    }
    return true;
}

// ---- Menu toggle policy ----------------------------------------------------

// Block Start/Back from opening the persona menu on top of a conversation,
// and route B through HandleActivate instead of Escape synthesis.
function bool AllowsMenuToggle()
{
    return false;
}

// ---- Focus overlay rect ----------------------------------------------------

// Conversations use the vanilla yellow-text choice highlight (driven
// by ApplyChoiceHighlight), not the MenuFocusOverlay frame. Returning
// false here keeps the overlay from drawing a second indicator on top.
// Other nav controllers inherit the base implementation and keep the
// frame.
function bool GetFocusedRect(out float x, out float y, out float w, out float h)
{
    return false;
}

defaultproperties
{
    bAllowRepeat=False    // single-press D-pad on short choice lists
}
