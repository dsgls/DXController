//=============================================================================
// NewGameNavController — gamepad nav for MenuScreenNewGame.
//
// MenuScreenNewGame is heterogeneous: portrait region (btnPortrait + arrow
// buttons, but only btnPortrait is focusable from the gamepad — L/R cycles
// the portrait via the existing PreviousPortrait/NextPortrait helpers and
// the arrow buttons are visually only), a vertical skills list, and a
// bottom action bar [Reset] [Start Game] [Cancel]. Inline btnUpgrade /
// btnDowngrade (in winClient, not winButtonBar) are folded into the
// skills-list region as A=upgrade / X=downgrade verbs rather than separate
// focus stops — reaching them via "exit list, focus button, A" would be
// tedious per-skill.
//
// Excluded from focus by design: editName / editCodeName text fields.
// Keyboard typing into editName still works because vanilla InitWindow
// calls SetFocusWindow(editName) — the engine's text-input focus is
// independent of our gamepad `focused`. Gamepad nav never lands on a
// text field.
//
// Linear focus cycle (D-pad up/down):
//   Portrait → Skills[0] → Skills[1] → … → Skills[last] → Action bar
//             → Portrait  (wraps)
//
// Region state:
//   REGION_Portrait:
//     D-pad L/R → PreviousPortrait / NextPortrait.
//     A         → NextPortrait (mirrors vanilla btnPortrait click).
//     D-pad down → enter skills list at row 0.
//     D-pad up   → enter action bar at Start Game (wraparound).
//     Verification: btnPortrait is a plain ButtonWindow (not a
//     MenuUIBorderButtonWindow / PersonaBorderButtonWindow subclass), so
//     it has no engine-focus cue — region stays on overlay frame, no
//     SetFocus call. Verified 2026-06-02.
//
//   REGION_Skills:
//     D-pad up/down → MoveRow; on edge (MoveRow doesn't change focus
//                     row), cross out: top → REGION_Portrait;
//                     bottom → enter action bar at Start Game.
//     D-pad L/R    → consume no-op (A/X are the verbs).
//     A            → UpgradeSkill (mirrors vanilla ListRowActivated).
//                    Gated by btnUpgrade.bIsSensitive.
//     X            → DowngradeSkill. Gated by btnDowngrade.bIsSensitive.
//
//   REGION_ActionBar:
//     D-pad L/R    → walk [Reset] [Start Game] [Cancel] via ActionBarNav,
//                    skipping insensitive. No wraparound at edges.
//     D-pad up     → enter skills list at last row.
//     D-pad down   → enter REGION_Portrait (wraparound).
//     A            → PressButton on the focused action button.
//     SetFocus drives the vanilla yellow-text cue on the focused action
//     button. Overlay frame is suppressed by the base GetFocusedRect.
//
// EInputKey is not in scope from Object subclasses (CLAUDE.md). A=200,
// X=202, Y=203, R-stick=209.
//
// bAllowRepeat=True so list-row stepping benefits from key repeat. The
// portrait L/R and action-bar L/R are short enough that auto-repeat is
// harmless.
//=============================================================================
class NewGameNavController extends MenuNavController;

const REGION_Portrait  = 0;
const REGION_Skills    = 1;
const REGION_ActionBar = 2;

var int region;

// Action-bar state.
var MenuUIActionButtonWindow actionBtns[5];
var int                      actionBtnCount;
var int                      actionBtnIdx;

function InitFocus()
{
    local MenuScreenNewGame s;

    s = MenuScreenNewGame(screen);
    if (s == None)
        return;

    // Defer until the skills list has been populated. MenuScreenNewGame
    // builds lstSkills via CreateSkillsListWindow in InitWindow, then
    // PopulateSkillsList AddRow's the spawned local skills.
    if (s.lstSkills == None || s.lstSkills.GetNumRows() <= 0)
    {
        // Degenerate fallback if the screen genuinely has 0 rows: park
        // on portrait. (Won't happen in vanilla; defensive only.)
        if (s.btnPortrait != None)
        {
            region = REGION_Portrait;
            focused = s.btnPortrait;
        }
        return;
    }

    // Start in skills region at row 0. Force-select row 0 to fire
    // ListSelectionChanged → winSkillInfo.SetSkill + EnableButtons.
    s.lstSkills.SetRow(s.lstSkills.IndexToRowId(0), True, True);
    region = REGION_Skills;
    focused = s.lstSkills;    // sentinel: stops Tick re-calling InitFocus
    class'DXControllerDebug'.static.DebugLog(
        "DXC-NAV INIT newgame region=skills row=0");
}

function bool HandleDPad(int dx, int dy)
{
    local MenuScreenNewGame s;
    local int prevRow, curRow;

    s = MenuScreenNewGame(screen);
    if (s == None)
        return true;

    // ---- L/R ----
    if (dx != 0)
    {
        if (region == REGION_Portrait)
        {
            if (dx < 0)
                s.PreviousPortrait();
            else
                s.NextPortrait();
            return true;
        }
        if (region == REGION_ActionBar)
        {
            class'ActionBarNav'.static.CollectButtons(
                s, actionBtns, actionBtnCount);
            if (dx < 0)
                actionBtnIdx = class'ActionBarNav'.static.MoveLeft(
                    actionBtns, actionBtnCount, actionBtnIdx);
            else
                actionBtnIdx = class'ActionBarNav'.static.MoveRight(
                    actionBtns, actionBtnCount, actionBtnIdx);
            if (actionBtnCount > 0)
                SetFocus(actionBtns[actionBtnIdx]);
            class'DXControllerDebug'.static.DebugLog(
                "DXC-NAV FOCUS newgame ab-idx=" $ string(actionBtnIdx));
            return true;
        }
        // REGION_Skills: L/R consumes no-op (verbs are on A/X)
        return true;
    }

    // ---- Up/Down ----
    if (dy != 0)
    {
        if (region == REGION_Portrait)
        {
            if (dy > 0)
                EnterSkillsTop(s);
            else
                EnterActionBar(s);
            return true;
        }

        if (region == REGION_Skills)
        {
            if (s.lstSkills == None || s.lstSkills.GetNumRows() <= 0)
            {
                // Degenerate: list became empty. Fall through to portrait/AB.
                if (dy > 0)
                    EnterActionBar(s);
                else
                    EnterPortrait(s);
                return true;
            }
            prevRow = s.lstSkills.GetFocusRow();
            if (dy > 0)
                s.lstSkills.MoveRow(MOVELIST_Down, True, True);
            else
                s.lstSkills.MoveRow(MOVELIST_Up, True, True);
            curRow = s.lstSkills.GetFocusRow();
            if (curRow != prevRow)
            {
                // Stayed inside the list.
                class'DXControllerDebug'.static.DebugLog(
                    "DXC-NAV FOCUS newgame skills row=" $ string(curRow));
                return true;
            }
            // Edge — cross out.
            if (dy > 0)
                EnterActionBar(s);
            else
                EnterPortrait(s);
            return true;
        }

        if (region == REGION_ActionBar)
        {
            if (dy > 0)
                EnterPortrait(s);
            else
                EnterSkillsBottom(s);
            return true;
        }
    }

    return true;
}

// Transition to portrait region. Focus = btnPortrait.
function EnterPortrait(MenuScreenNewGame s)
{
    region = REGION_Portrait;
    focused = s.btnPortrait;
    class'DXControllerDebug'.static.DebugLog(
        "DXC-NAV FOCUS newgame region=portrait");
}

// Transition to skills region, selecting the given row index. Uses
// SetRow(... True, True) so ListSelectionChanged fires and updates
// winSkillInfo / EnableButtons automatically.
function EnterSkillsAt(MenuScreenNewGame s, int targetIdx)
{
    region = REGION_Skills;
    focused = s.lstSkills;          // sentinel
    if (s.lstSkills == None || s.lstSkills.GetNumRows() <= 0)
        return;
    s.lstSkills.SetRow(s.lstSkills.IndexToRowId(targetIdx), True, True);
    class'DXControllerDebug'.static.DebugLog(
        "DXC-NAV FOCUS newgame region=skills row=" $ string(targetIdx));
}

// Enter the skills list at row 0 (used when crossing in from above —
// D-down from portrait, D-up from action bar wraparound is the
// EnterSkillsBottom path).
function EnterSkillsTop(MenuScreenNewGame s)
{
    EnterSkillsAt(s, 0);
}

// Enter the skills list at the last row (used when crossing in from
// below — D-up from action bar).
function EnterSkillsBottom(MenuScreenNewGame s)
{
    if (s.lstSkills == None)
        return;
    EnterSkillsAt(s, s.lstSkills.GetNumRows() - 1);
}

// Transition to action bar. Collects sensitive buttons and lands on the
// primary (Start Game by convention; first sensitive in L→R as fallback).
function EnterActionBar(MenuScreenNewGame s)
{
    local int primaryIdx;

    class'ActionBarNav'.static.CollectButtons(s, actionBtns, actionBtnCount);
    if (actionBtnCount == 0)
    {
        // No action buttons at all — stay where we are. (Defensive.)
        class'DXControllerDebug'.static.DebugLog(
            "DXC-NAV FOCUS newgame ab-empty");
        return;
    }
    primaryIdx = class'ActionBarNav'.static.FindPrimaryIndex(
        s, actionBtns, actionBtnCount);
    if (primaryIdx < 0)
    {
        // All collected buttons are insensitive — no useful target.
        // Stay in the current region, matching OptionsNavController's
        // behavior in the same case (D-down past last row consumes
        // but doesn't transition). Won't happen in vanilla.
        class'DXControllerDebug'.static.DebugLog(
            "DXC-NAV FOCUS newgame ab-no-sensitive");
        return;
    }
    region = REGION_ActionBar;
    actionBtnIdx = primaryIdx;
    SetFocus(actionBtns[actionBtnIdx]);
    class'DXControllerDebug'.static.DebugLog(
        "DXC-NAV FOCUS newgame region=ab ab-idx=" $ string(actionBtnIdx));
}

function bool HandleActivate(byte button)
{
    local MenuScreenNewGame s;

    s = MenuScreenNewGame(screen);
    if (s == None)
        return true;

    // Byte literals — see CLAUDE.md "EInputKey is not in scope from controllers":
    //   200 = IK_Joy1 (A)
    //   202 = IK_Joy3 (X)
    //   203 = IK_Joy4 (Y) — consumed no-op
    //   209 = IK_Joy10 (R-stick click) — consumed no-op

    if (button == 200)        // A
    {
        if (region == REGION_Portrait)
        {
            s.NextPortrait();
            class'DXControllerDebug'.static.DebugLog(
                "DXC-NAV ACTIVATE newgame portrait next");
            return true;
        }
        if (region == REGION_Skills)
        {
            // UpgradeSkill mirrors vanilla ListRowActivated. Vanilla
            // calls UpgradeSkill directly; we do the same and let
            // btnUpgrade.bIsSensitive gate the affordability check.
            if (s.btnUpgrade != None && s.btnUpgrade.bIsSensitive)
            {
                s.UpgradeSkill();
                class'DXControllerDebug'.static.DebugLog(
                    "DXC-NAV ACTIVATE newgame upgrade");
            }
            return true;
        }
        if (region == REGION_ActionBar)
        {
            if (focused != None && MenuUIActionButtonWindow(focused) != None
                && MenuUIActionButtonWindow(focused).bIsSensitive)
            {
                MenuUIActionButtonWindow(focused).PressButton();
                class'DXControllerDebug'.static.DebugLog(
                    "DXC-NAV ACTIVATE newgame ab idx=" $ string(actionBtnIdx));
            }
            return true;
        }
    }

    if (button == 202)        // X
    {
        if (region == REGION_Skills)
        {
            if (s.btnDowngrade != None && s.btnDowngrade.bIsSensitive)
            {
                s.DowngradeSkill();
                class'DXControllerDebug'.static.DebugLog(
                    "DXC-NAV ACTIVATE newgame downgrade");
            }
            return true;
        }
        return true;
    }

    // Y (203), R-stick (209), and anything else: consume no-op.
    return true;
}

// Rows in lstSkills aren't Window objects, so the focus overlay can't
// draw a frame around the focused row — the native list draws its own
// row highlight. Suppress overlay only in the skills region; portrait
// and action-bar regions return their focused button's rect via the
// base implementation.
function bool GetFocusedRect(out float x, out float y, out float w, out float h)
{
    if (region == REGION_Skills)
        return false;
    return Super.GetFocusedRect(x, y, w, h);
}

function Detach()
{
    region = REGION_Portrait;
    actionBtnCount = 0;
    actionBtnIdx = 0;
    Super.Detach();
}

// A is region-dependent (cycle portrait / upgrade skill / press action
// button); the combined "Upgrade / Select" label covers all three
// without per-region legend switching. X downgrades a skill (Skills
// region only); the static label is accepted per the spec.
function BuildHints()
{
    AddHint("a", "Upgrade / Select");
    AddHint("x", "Downgrade");
    AddHint("b", "Back");
}

defaultproperties
{
    bAllowRepeat=True
}
