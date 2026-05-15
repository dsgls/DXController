//=============================================================================
// ThemesSaveNavController — gamepad nav for MenuScreenThemesSave.
//
// Primary action: "SAVE" (Save Theme). No secondary action.
//=============================================================================
class ThemesSaveNavController extends ListScreenNavController;

function InitListAndButtons()
{
    local MenuScreenThemesSave s;

    s = MenuScreenThemesSave(screen);
    if (s == None)
        return;

    lst        = s.lstThemes;
    primaryBtn = class'ActionBarNav'.static.FindByKey(s, "SAVE");
}
