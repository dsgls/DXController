//=============================================================================
// SkillsNavController — vertical list of PersonaSkillButtonWindow rows.
//=============================================================================
class SkillsNavController extends MenuNavController;

function InitFocus()
{
    local PersonaScreenSkills s;
    s = PersonaScreenSkills(screen);
    if (s == None)
        return;

    focusIndex = FindFirstNonNullSkill(s);
    if (focusIndex >= 0)
    {
        focused = s.skillButtons[focusIndex];
        s.SelectSkillButton(s.skillButtons[focusIndex]);
    }
}

function int FindFirstNonNullSkill(PersonaScreenSkills s)
{
    local int i;
    for (i = 0; i < ArrayCount(s.skillButtons); i++)
    {
        if (s.skillButtons[i] != None)
            return i;
    }
    return -1;
}

function bool HandleDPad(int dx, int dy)
{
    local PersonaScreenSkills s;
    local int step, i, n, idx;

    s = PersonaScreenSkills(screen);
    if (s == None || dy == 0)
        return true;

    if (dy > 0)
        step = 1;
    else
        step = -1;

    n = ArrayCount(s.skillButtons);
    idx = focusIndex;
    for (i = 0; i < n; i++)
    {
        idx = (idx + step + n) % n;
        if (s.skillButtons[idx] != None)
        {
            focusIndex = idx;
            focused = s.skillButtons[idx];
            s.SelectSkillButton(s.skillButtons[idx]);
            class'DXControllerDebug'.static.DebugLog("DXC-NAV FOCUS skill=" $ string(idx));
            return true;
        }
    }
    return true;
}

function bool HandleActivate(byte button)
{
    local PersonaScreenSkills s;
    if (button != 200)    // IK_Joy1 (A) = 0xC8 = 200 — enum not reachable from Object scope
        return true;
    s = PersonaScreenSkills(screen);
    if (s == None || focused == None)
        return true;
    // Vanilla path: clicking the Upgrade button on the screen invokes UpgradeSkill().
    if (s.btnUpgrade != None && s.btnUpgrade.bIsSensitive)
        s.btnUpgrade.PressButton();
    return true;
}
