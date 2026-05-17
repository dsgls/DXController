//=============================================================================
// ThemesLoadNavController — gamepad nav for MenuScreenThemesLoad.
//
// Primary action: "LOAD" (Load Theme). No secondary action.
//=============================================================================
class ThemesLoadNavController extends ListScreenNavController;

function InitListAndButtons()
{
    local MenuScreenThemesLoad s;

    s = MenuScreenThemesLoad(screen);
    if (s == None)
        return;

    lst        = s.lstThemes;
    primaryBtn = class'ActionBarNav'.static.FindByKey(s, "LOAD");
    // secondaryBtn intentionally None — no delete action.
}

defaultproperties
{
    primaryHintLabel="Apply theme"
}
