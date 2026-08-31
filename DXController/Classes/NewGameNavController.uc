//=============================================================================
// NewGameNavController — gamepad nav for MenuScreenNewGame.
//
// MenuScreenNewGame is heterogeneous: a Real Name text field, a portrait
// region (btnPortrait + arrow buttons, but only btnPortrait is focusable
// from the gamepad — L/R cycles the portrait via the existing
// PreviousPortrait/NextPortrait helpers and the arrow buttons are visual
// only), a vertical skills list, and a bottom action bar
// [Reset] [Start Game] [Cancel]. Inline btnUpgrade / btnDowngrade (in
// winClient, not winButtonBar) are folded into the skills-list region as
// A=upgrade / X=downgrade verbs rather than separate focus stops —
// reaching them via "exit list, focus button, A" would be tedious
// per-skill.
//
// The graph is two columns plus the action bar shared between them. Each
// column wraps vertically on its own:
//
//   left column:   NAME → PORTRAIT → RESET → (wrap) NAME
//   right column:  SKILLS[0..n] → action-bar primary → (wrap) SKILLS[0]
//   crossing:      NAME ↔ SKILLS (D-pad left/right)
//   action bar:    RESET ↔ START GAME ↔ CANCEL (D-pad left/right)
//
// Region state:
//   REGION_Name:
//     D-pad right → skills row 0; left → consume no-op.
//     D-pad down  → REGION_Portrait; up → action bar at Reset (wrap).
//     A           → open the on-screen keyboard on editName, filtered to
//                   the field's stock filterString set.
//     SetFocus(editName) puts engine focus on the field, so a physical
//     keyboard types into it while NAME is focused. MenuUIEditWindow is
//     not in HasStockFocusCue, so the overlay frame draws the cue.
//
//   REGION_Portrait:
//     D-pad L/R  → PreviousPortrait / NextPortrait. No horizontal exit.
//     A          → NextPortrait (mirrors vanilla btnPortrait click).
//     D-pad up   → REGION_Name; down → action bar at Reset.
//     btnPortrait is a plain ButtonWindow (not a MenuUIBorderButtonWindow
//     / PersonaBorderButtonWindow subclass), so it has no engine-focus
//     cue — the region stays on the overlay frame.
//
//   REGION_Skills:
//     D-pad up/down → MoveRow; on edge (MoveRow doesn't change focus
//                     row), cross out to the action bar's primary entry
//                     in both directions.
//     D-pad left    → REGION_Name; right → consume no-op.
//     A             → UpgradeSkill (mirrors vanilla ListRowActivated).
//                     Gated by btnUpgrade.bIsSensitive.
//     X             → DowngradeSkill. Gated by btnDowngrade.bIsSensitive.
//
//   REGION_ActionBar:
//     D-pad L/R  → walk [Reset] [Start Game] [Cancel] via ActionBarNav,
//                  skipping insensitive. No wraparound at edges.
//     D-pad up   → from Reset: REGION_Portrait; otherwise skills last row.
//     D-pad down → from Reset: REGION_Name (wrap); otherwise skills row 0.
//     A          → PressButton on the focused action button.
//     SetFocus drives the vanilla yellow-text cue on the focused action
//     button. Overlay frame is suppressed by the base GetFocusedRect.
//
// Start (Joy8) presses Start Game from any region without moving focus
// (ConsumesStartButton). With a blank name START is insensitive, and both
// Start and A-on-START instead jump to NAME and open the keyboard.
//
// The Code Name field stays excluded from nav — vanilla marks it
// read-only (SetSensitivity(False)).
//
// EInputKey is not in scope from Object subclasses (CLAUDE.md). A=200,
// X=202, Y=203, Start=207, R-stick=209.
//
// bAllowRepeat=True so list-row stepping benefits from key repeat. The
// portrait L/R and action-bar L/R are short enough that auto-repeat is
// harmless.
//=============================================================================
class NewGameNavController extends MenuNavController;

const REGION_Name      = 0;
const REGION_Portrait  = 1;
const REGION_Skills    = 2;
const REGION_ActionBar = 3;

// Index of the Reset button within a CollectButtons result on this
// screen. Positional, not by key: NewGame's Reset entry is
// actionButtons(2)=(Action=AB_Reset) with no .key, so FindByKey can't
// see it. CollectButtons emits left-aligned buttons first and Reset is
// the only left-aligned entry here, so it is always index 0.
const AB_RESET_IDX = 0;

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

    // Only on this branch: InitWindow has run by now, so the selection
    // to clear exists. The first (Attach-time) call early-returns above,
    // before vanilla has built the field at all.
    ClearNameSelection(s);

    class'DXControllerDebug'.static.DebugLog(
        "DXC-NAV INIT newgame region=skills row=0");
}

// Vanilla InitWindow leaves the pre-filled Real Name fully selected
// (SetFocusWindow(editName) + SetSelectedArea(0, Len)), so it renders
// as an active edit while gamepad focus sits on the skills list.
// Collapse the selection; the text itself stays.
//
// A zero-length SetSelectedArea rather than
// MoveInsertionPoint(MOVEINSERT_End): EMoveInsert is declared on
// EditWindow and is not in scope from an Object subclass, the same
// restriction as EInputKey. That leaves the caret at offset 0, so
// follow it with an explicit move to the end — vanilla parks the caret
// there (MenuScreenNewGame.CreateNameEditWindow), and without this a
// physical keyboard would prepend.
function ClearNameSelection(MenuScreenNewGame s)
{
    if (s == None || s.editName == None)
        return;
    s.editName.SetSelectedArea(0, 0);
    s.editName.SetInsertionPoint(s.editName.GetTextLength());
}

// True while START is insensitive for the vanilla reason: an empty
// Real Name. Matches EnableButtons' own test exactly (untrimmed) —
// a whitespace-only name still reaches ProcessAction and the vanilla
// NameBlank message box.
function bool IsNameBlank(MenuScreenNewGame s)
{
    return s.editName == None || s.editName.GetText() == "";
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
        if (region == REGION_Name)
        {
            if (dx > 0)
                EnterSkillsTop(s);
            // left from the left column: consume no-op.
            return true;
        }
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
        // REGION_Skills: left crosses to the name field, right no-ops.
        if (dx < 0)
            EnterName(s);
        return true;
    }

    // ---- Up/Down ----
    if (dy != 0)
    {
        if (region == REGION_Name)
        {
            if (dy > 0)
                EnterPortrait(s);
            else
                EnterActionBarAt(s, AB_RESET_IDX);
            return true;
        }

        if (region == REGION_Portrait)
        {
            if (dy > 0)
                EnterActionBarAt(s, AB_RESET_IDX);
            else
                EnterName(s);
            return true;
        }

        if (region == REGION_Skills)
        {
            if (s.lstSkills == None || s.lstSkills.GetNumRows() <= 0)
            {
                // Degenerate: list became empty. Cross out anyway.
                EnterActionBarPrimary(s);
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
            // Edge in either direction — cross out to the action bar.
            EnterActionBarPrimary(s);
            return true;
        }

        if (region == REGION_ActionBar)
        {
            if (actionBtnIdx == AB_RESET_IDX)
            {
                if (dy > 0)
                    EnterName(s);
                else
                    EnterPortrait(s);
            }
            else
            {
                if (dy > 0)
                    EnterSkillsTop(s);
                else
                    EnterSkillsBottom(s);
            }
            return true;
        }
    }

    return true;
}

// Transition to the Real Name field. Engine focus goes onto editName so
// a physical keyboard can type into it, and so whichever action-bar
// button we just left releases its yellow text.
function EnterName(MenuScreenNewGame s)
{
    if (s.editName == None)
        return;
    region = REGION_Name;
    SetFocus(s.editName);
    class'DXControllerDebug'.static.DebugLog(
        "DXC-NAV FOCUS newgame region=name");
}

// Transition to portrait region. Focus = btnPortrait. SetFocusWindow
// is called even though btnPortrait has no stock cue, so engine focus
// moves off whichever action-bar button we just left — without this,
// the action button keeps its yellow text while we're on the portrait.
function EnterPortrait(MenuScreenNewGame s)
{
    region = REGION_Portrait;
    focused = s.btnPortrait;
    if (screen != None && s.btnPortrait != None)
        screen.SetFocusWindow(s.btnPortrait);
    class'DXControllerDebug'.static.DebugLog(
        "DXC-NAV FOCUS newgame region=portrait");
}

// Transition to skills region, selecting the given row index. Uses
// SetRow(... True, True) so ListSelectionChanged fires and updates
// winSkillInfo / EnableButtons automatically. Engine focus moves onto
// lstSkills so the previously focused action-bar button releases its
// yellow text — the list draws its own row-highlight cue, so engine
// focus on it is invisible.
function EnterSkillsAt(MenuScreenNewGame s, int targetIdx)
{
    region = REGION_Skills;
    focused = s.lstSkills;          // sentinel
    if (s.lstSkills == None || s.lstSkills.GetNumRows() <= 0)
        return;
    if (screen != None)
        screen.SetFocusWindow(s.lstSkills);
    s.lstSkills.SetRow(s.lstSkills.IndexToRowId(targetIdx), True, True);
    class'DXControllerDebug'.static.DebugLog(
        "DXC-NAV FOCUS newgame region=skills row=" $ string(targetIdx));
}

// Enter the skills list at row 0 (used when crossing in from above or
// wrapping down out of the action bar).
function EnterSkillsTop(MenuScreenNewGame s)
{
    EnterSkillsAt(s, 0);
}

// Enter the skills list at the last row (used when crossing in from
// below — D-up from the action bar).
function EnterSkillsBottom(MenuScreenNewGame s)
{
    if (s.lstSkills == None)
        return;
    EnterSkillsAt(s, s.lstSkills.GetNumRows() - 1);
}

// Enter the action bar at the screen's primary action — Start Game when
// sensitive, otherwise the first sensitive button L→R (Reset, when the
// name is blank). Used by the skills column's vertical edges.
function EnterActionBarPrimary(MenuScreenNewGame s)
{
    EnterActionBarAt(s, -1);
}

// Enter the action bar. targetIdx < 0 lands on the primary; otherwise it
// lands on that index in visual L→R order, falling back to the primary
// if the requested button is missing or insensitive.
function EnterActionBarAt(MenuScreenNewGame s, int targetIdx)
{
    local int idx;

    class'ActionBarNav'.static.CollectButtons(s, actionBtns, actionBtnCount);
    if (actionBtnCount == 0)
    {
        // No action buttons at all — stay where we are. (Defensive.)
        class'DXControllerDebug'.static.DebugLog(
            "DXC-NAV FOCUS newgame ab-empty");
        return;
    }

    idx = -1;
    if (targetIdx >= 0 && targetIdx < actionBtnCount
        && actionBtns[targetIdx] != None
        && actionBtns[targetIdx].bIsSensitive)
        idx = targetIdx;

    if (idx < 0)
        idx = class'ActionBarNav'.static.FindPrimaryIndex(
            s, actionBtns, actionBtnCount);
    if (idx < 0)
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
    actionBtnIdx = idx;
    SetFocus(actionBtns[actionBtnIdx]);
    class'DXControllerDebug'.static.DebugLog(
        "DXC-NAV FOCUS newgame region=ab ab-idx=" $ string(actionBtnIdx));
}

// Open the on-screen keyboard on the Real Name field. The keyboard edits
// the field in place through the EditWindow natives; there is no commit
// step. It is uppercase-only, so a name typed this way comes out in caps.
function OpenNameKeyboard(MenuScreenNewGame s)
{
    local ControllerRootWindow root;

    if (s.editName == None || screen == None)
        return;
    root = ControllerRootWindow(screen.GetRootWindow());
    if (root == None)
        return;
    // filterString is the same set vanilla hands editName.SetFilter, so
    // the keyboard's . - _ # keys are consumed no-ops on this field.
    root.OpenKeyboard(s.editName, screen, "ENTER NAME", s.filterString);
    class'DXControllerDebug'.static.DebugLog("DXC-NAV ACTIVATE newgame kbd-open");
}

// "You need a name" affordance for the paths that find START insensitive:
// move to the field and open the keyboard, rather than no-op silently.
function PromptForName(MenuScreenNewGame s)
{
    EnterName(s);
    OpenNameKeyboard(s);
}

// The name keyboard has closed. Re-run vanilla sensitivity so START
// reflects the edited text whether or not the native InsertText fires
// TextChanged, and re-clear the selection the field may be left holding.
function KeyboardClosed()
{
    local MenuScreenNewGame s;

    s = MenuScreenNewGame(screen);
    if (s == None)
        return;
    s.EnableButtons();
    ClearNameSelection(s);
}

// Start (Joy8) drives Start Game from any region.
function bool ConsumesStartButton()
{
    return true;
}

function bool HandleActivate(byte button)
{
    local MenuScreenNewGame s;
    local MenuUIActionButtonWindow startBtn, focusedBtn;

    s = MenuScreenNewGame(screen);
    if (s == None)
        return true;

    // Byte literals — see CLAUDE.md "EInputKey is not in scope from controllers":
    //   200 = IK_Joy1 (A)
    //   202 = IK_Joy3 (X)
    //   203 = IK_Joy4 (Y) — consumed no-op
    //   207 = IK_Joy8 (Start)
    //   209 = IK_Joy10 (R-stick click) — consumed no-op

    if (button == 200)        // A
    {
        if (region == REGION_Name)
        {
            OpenNameKeyboard(s);
            return true;
        }
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
            focusedBtn = MenuUIActionButtonWindow(focused);
            if (focusedBtn != None)
            {
                if (focusedBtn.bIsSensitive)
                {
                    focusedBtn.PressButton();
                    class'DXControllerDebug'.static.DebugLog(
                        "DXC-NAV ACTIVATE newgame ab idx=" $ string(actionBtnIdx));
                }
                else if (IsNameBlank(s)
                    && focusedBtn == class'ActionBarNav'.static.FindByKey(s, "START"))
                {
                    // The name was blanked while START held focus.
                    PromptForName(s);
                }
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

    if (button == 207)        // Start
    {
        startBtn = class'ActionBarNav'.static.FindByKey(s, "START");
        if (startBtn != None && startBtn.bIsSensitive)
        {
            startBtn.PressButton();
            class'DXControllerDebug'.static.DebugLog(
                "DXC-NAV ACTIVATE newgame start");
        }
        else if (IsNameBlank(s))
        {
            PromptForName(s);
        }
        return true;
    }

    // Y (203), R-stick (209), and anything else: consume no-op.
    return true;
}

// Rows in lstSkills aren't Window objects, so the focus overlay can't
// draw a frame around the focused row — the native list draws its own
// row highlight. Suppress overlay only in the skills region; the other
// regions return their focused widget's rect via the base
// implementation (editName and btnPortrait have no stock cue, so the
// frame is their only indicator).
function bool GetFocusedRect(out float x, out float y, out float w, out float h)
{
    if (region == REGION_Skills)
        return false;
    return Super.GetFocusedRect(x, y, w, h);
}

function Detach()
{
    region = REGION_Skills;
    actionBtnCount = 0;
    actionBtnIdx = 0;
    Super.Detach();
}

// A is region-dependent (open the keyboard / cycle portrait / upgrade
// skill / press action button); the combined "Upgrade / Select" label
// covers them without per-region legend switching. X downgrades a skill
// (Skills region only); the static label is accepted per the spec.
function BuildHints()
{
    AddHint("a", "Upgrade / Select");
    AddHint("x", "Downgrade");
    AddHint("start", "Start Game");
    AddHint("b", "Back");
}

defaultproperties
{
    bAllowRepeat=True
}
