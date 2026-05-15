//=============================================================================
// LoadGameNavController — gamepad nav for MenuScreenLoadGame.
//
// Primary action: "LOAD"   (the Load Game button).
// Secondary:      "DELETE" (the Delete Game button).
//
// Cancel is the keyboard Escape path via ControllerRootWindow's B-button
// synthesizer (Task 8). DELETE prompts an "Are you sure?" message box if
// the "Confirm Savegame Deletion" toggle is on — handled by
// MessageBoxNavController (Task 7).
//=============================================================================
class LoadGameNavController extends ListScreenNavController;

function InitListAndButtons()
{
    local MenuScreenLoadGame s;

    s = MenuScreenLoadGame(screen);
    if (s == None)
        return;

    lst          = s.lstGames;
    primaryBtn   = FindActionBtn(s, "LOAD");
    secondaryBtn = FindActionBtn(s, "DELETE");
}
