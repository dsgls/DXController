//=============================================================================
// ComputerButtonBarNav — static helpers for walking a
// MenuUIActionButtonBarWindow's actionButtons[5] array from
// network-terminal sub-controllers.
//
// Mirrors ActionBarNav (which operates on MenuUIWindow.actionButtons[]),
// but takes the bar directly because ComputerUIWindow doesn't host the
// array at the screen level — the same {btn, align} struct lives on
// the bar instead.
//
// L→R order convention is identical to ActionBarNav:
//   HALIGN_Left/Center/Full: declaration order (first declared = leftmost)
//   HALIGN_Right            : REVERSE declaration order (first declared = rightmost)
//
// extends ExtensionObject so HALIGN_* constants resolve here.
//=============================================================================
class ComputerButtonBarNav extends ExtensionObject;

static function CollectButtons(
    MenuUIActionButtonBarWindow bar,
    out MenuUIActionButtonWindow btns[5],
    out int count)
{
    local int i;

    count = 0;
    if (bar == None)
        return;

    for (i = 0; i < ArrayCount(bar.actionButtons); i++)
    {
        if (bar.actionButtons[i].btn != None
            && (bar.actionButtons[i].align == HALIGN_Left
                || bar.actionButtons[i].align == HALIGN_Center
                || bar.actionButtons[i].align == HALIGN_Full))
        {
            btns[count] = bar.actionButtons[i].btn;
            count++;
        }
    }
    for (i = ArrayCount(bar.actionButtons) - 1; i >= 0; i--)
    {
        if (bar.actionButtons[i].btn != None
            && bar.actionButtons[i].align == HALIGN_Right)
        {
            btns[count] = bar.actionButtons[i].btn;
            count++;
        }
    }
}

// Find a button by visible text label. ButtonLabel constants ship
// "|&Login", "|&Withdraw", etc.; MenuUIBorderButtonWindow.buttonText
// stores the same string (set by AddButton via SetButtonText).
static function MenuUIActionButtonWindow FindByLabel(
    MenuUIActionButtonBarWindow bar,
    string label)
{
    local int i;

    if (bar == None)
        return None;
    for (i = 0; i < ArrayCount(bar.actionButtons); i++)
    {
        if (bar.actionButtons[i].btn != None
            && bar.actionButtons[i].btn.buttonText == label)
            return bar.actionButtons[i].btn;
    }
    return None;
}

// Index within btns[count] of the primary action button. Sub-controllers
// pass preferredLabel (e.g. ButtonLabelLogin). If the preferred button
// exists and is sensitive, returns its index. Otherwise, falls back to
// the first sensitive button in visual L→R order. Returns -1 if no
// sensitive button exists.
static function int FindPrimaryIndex(
    MenuUIActionButtonBarWindow bar,
    MenuUIActionButtonWindow btns[5],
    int count,
    string preferredLabel)
{
    local int i;
    local MenuUIActionButtonWindow preferred;

    preferred = FindByLabel(bar, preferredLabel);
    if (preferred != None && preferred.bIsSensitive)
    {
        for (i = 0; i < count; i++)
        {
            if (btns[i] == preferred)
                return i;
        }
    }
    for (i = 0; i < count; i++)
    {
        if (btns[i] != None && btns[i].bIsSensitive)
            return i;
    }
    return -1;
}

static function int MoveLeft(
    MenuUIActionButtonWindow btns[5],
    int count,
    int currentIdx)
{
    local int i;

    if (count <= 0)
        return 0;
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

static function int MoveRight(
    MenuUIActionButtonWindow btns[5],
    int count,
    int currentIdx)
{
    local int i;

    if (count <= 0)
        return 0;
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
