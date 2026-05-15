//=============================================================================
// ActionBarNav — static helpers for working with MenuUIWindow's bottom
// action bar (the winButtonBar / actionButtons[5] pair) from gamepad
// navigation controllers.
//
// Visual L→R order is derived from each entry's .align field:
//   * HALIGN_Left / HALIGN_Center / HALIGN_Full: declaration order from
//     the left edge of the bar (first-declared sits leftmost).
//   * HALIGN_Right: REVERSE declaration order from the right edge
//     (first-declared sits rightmost; second-declared is to its left).
//
// In-scope screens use a few layout variants. Visual L→R order is what
// matters for navigation; here are the screens in scope and their layouts:
//
//   options-family / NewGame:  [Reset]  [Primary] [Cancel]
//   load/save game:            [Delete] [Primary] [Cancel]
//   themes load/save:                   [Primary] [Cancel]
//
// In every case, the primary action lives at actionButtons(1) with
// HALIGN_Right (AB_OK on options screens, AB_Other "START"/"LOAD"/
// "SAVE" elsewhere). Cancel is actionButtons(0). The third slot, when
// present, is a left-aligned secondary verb — Reset, Delete, or none.
//
// `extends ExtensionObject` because EHAlign (HALIGN_Right etc.) is declared
// on ExtensionObject; Object's namespace doesn't include it.
//=============================================================================
class ActionBarNav extends ExtensionObject;

// Collect ALL action buttons in visual L→R order regardless of sensitivity.
// Callers gate on .bIsSensitive when stepping L/R or activating.
//
// Deliberate deviation from spec § "Shared helper", which described a
// winButtonBar child-list walk filtered to sensitive buttons. We instead
// walk the source actionButtons[] array and keep all buttons. Collecting
// all-then-skip is more robust to dynamic sensitivity changes (e.g. user
// blanks editName mid-walk on NewGame and Start becomes insensitive) than
// collect-sensitive-only — filtering at step-time means live bIsSensitive
// toggles don't shift indices out from under a tracked currentIdx.
static function CollectButtons(
    MenuUIWindow s,
    out MenuUIActionButtonWindow btns[5],
    out int count)
{
    local int i;

    count = 0;
    if (s == None)
        return;

    // Left-aligned in declaration order.
    for (i = 0; i < ArrayCount(s.actionButtons); i++)
    {
        if (s.actionButtons[i].btn != None
            && (s.actionButtons[i].align == HALIGN_Left
                || s.actionButtons[i].align == HALIGN_Center
                || s.actionButtons[i].align == HALIGN_Full))
        {
            btns[count] = s.actionButtons[i].btn;
            count++;
        }
    }
    // Right-aligned in REVERSE declaration order. AddButton stacks
    // right-aligned buttons right→left in array order, so iterating
    // the array high→low gives visual left→right.
    for (i = ArrayCount(s.actionButtons) - 1; i >= 0; i--)
    {
        if (s.actionButtons[i].btn != None
            && s.actionButtons[i].align == HALIGN_Right)
        {
            btns[count] = s.actionButtons[i].btn;
            count++;
        }
    }
}

// Look up an AB_Other action button by its .key field
// ("START", "LOAD", "SAVE", "DELETE", ...). Returns None if absent.
//
// Replaces the previous ListScreenNavController.FindActionBtn helper —
// same body, same signature, centralised here so all action-bar lookups
// live in one place.
static function MenuUIActionButtonWindow FindByKey(MenuUIWindow s, string key)
{
    local int i;

    if (s == None)
        return None;
    for (i = 0; i < ArrayCount(s.actionButtons); i++)
    {
        if (s.actionButtons[i].key == key
            && s.actionButtons[i].btn != None)
            return s.actionButtons[i].btn;
    }
    return None;
}

// Index within `btns[]` of the screen's "primary action" button — the one
// the gamepad lands on when entering the action bar from D-pad-down/up.
// By the layout convention documented above, that's actionButtons[1].btn
// on every in-scope screen.
//
// If actionButtons[1] is missing or insensitive, fall back to the first
// sensitive button in visual L→R order. Returns -1 if no sensitive
// button exists (defensive — won't happen on stock screens).
//
// Implementation note: spec § "Shared helper" described looking up the
// primary by EActionButtonEvents type (AB_OK first, then AB_Other key
// "START"). EActionButtonEvents is declared inside DeusEx.MenuUIWindow
// and isn't reachable from ExtensionObject scope without a workaround,
// so we lean on the layout convention instead — slot 1 is always the
// primary on every in-scope screen. A future screen that breaks the
// convention would need an explicit FindByKey call to drive its entry.
static function int FindPrimaryIndex(
    MenuUIWindow s,
    MenuUIActionButtonWindow btns[5],
    int count)
{
    local int i;

    if (s == None)
        return -1;

    if (s.actionButtons[1].btn != None
        && s.actionButtons[1].btn.bIsSensitive)
    {
        for (i = 0; i < count; i++)
        {
            if (btns[i] == s.actionButtons[1].btn)
                return i;
        }
    }
    // Fallback: first sensitive in visual L→R.
    for (i = 0; i < count; i++)
    {
        if (btns[i] != None && btns[i].bIsSensitive)
            return i;
    }
    return -1;
}

// Step one button left in visual order, skipping insensitive buttons.
// Clamps at 0 — no wraparound. Returns currentIdx if no sensitive
// button exists strictly to the left.
static function int MoveLeft(
    MenuUIActionButtonWindow btns[5],
    int count,
    int currentIdx)
{
    local int i;

    if (count <= 0)
        return 0;
    // Clamp stale currentIdx (defensive: re-collect may have shrunk count).
    if (currentIdx >= count)
        currentIdx = count - 1;
    if (currentIdx < 0)
        currentIdx = 0;

    for (i = currentIdx - 1; i >= 0; i--)
    {
        if (btns[i] != None && btns[i].bIsSensitive)
            return i;
    }
    return currentIdx;
}

// Step one button right in visual order, skipping insensitive buttons.
// Clamps at count-1 — no wraparound.
static function int MoveRight(
    MenuUIActionButtonWindow btns[5],
    int count,
    int currentIdx)
{
    local int i;

    if (count <= 0)
        return 0;
    // Clamp stale currentIdx (defensive: re-collect may have shrunk count).
    if (currentIdx >= count)
        currentIdx = count - 1;
    if (currentIdx < 0)
        currentIdx = 0;

    for (i = currentIdx + 1; i < count; i++)
    {
        if (btns[i] != None && btns[i].bIsSensitive)
            return i;
    }
    return currentIdx;
}

// Locate the index of `target` within `btns[count]`. Used by controllers
// to recover the position of a tracked button after a re-collect.
// Returns -1 if not present.
static function int IndexOf(
    MenuUIActionButtonWindow btns[5],
    int count,
    MenuUIActionButtonWindow target)
{
    local int i;

    for (i = 0; i < count; i++)
    {
        if (btns[i] == target)
            return i;
    }
    return -1;
}
