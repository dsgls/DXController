//=============================================================================
// SaveGameNavController — gamepad nav for MenuScreenSaveGame.
//
// Primary action: "SAVE"   (the Save Game button).
// Secondary:      "DELETE" (the Delete Game button).
//
// MenuScreenSaveGame overlays an edit control on the focused list row,
// repositioned by the engine's ListSelectionChanged callback. Our
// MoveRow(..., True, True) in the base class triggers that callback
// the same way a mouse click does — no special handling needed.
// Typing the save name remains keyboard-only (no virtual keyboard
// in scope for this feature).
//=============================================================================
class SaveGameNavController extends ListScreenNavController;

function InitListAndButtons()
{
    local MenuScreenSaveGame s;

    s = MenuScreenSaveGame(screen);
    if (s == None)
        return;

    lst          = s.lstGames;
    primaryBtn   = FindActionBtn(s, "SAVE");
    secondaryBtn = FindActionBtn(s, "DELETE");
}
