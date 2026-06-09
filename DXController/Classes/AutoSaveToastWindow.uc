//=============================================================================
// AutoSaveToastWindow — unobtrusive autosave feedback.
//
// A HUDBaseWindow child of ControllerRootWindow (NewChild'd in InitWindow).
// Draws nothing unless ControllerRootWindow.autoSave.ShouldShowToast() is
// true, in which case it paints a single light-gray line in the bottom-left
// corner. Pure read-only draw — all timing/mutation lives on AutoSaveManager,
// driven from ControllerRootWindow.Tick. (Per the development.md rule that
// DrawWindow must never mutate / trigger reconfigure.)
//=============================================================================
class AutoSaveToastWindow extends HUDBaseWindow;

const MARGIN = 8.0;     // inset from the bottom-left corner
const TEXT_H = 16.0;    // line height (FontMenuSmall)
const TEXT_W = 300.0;   // text box width (clips, doesn't scale)

event DrawWindow(GC gc)
{
    local ControllerRootWindow root;
    local AutoSaveManager mgr;
    local Color c;
    local float ty;

    Super.DrawWindow(gc);

    root = ControllerRootWindow(GetRootWindow());
    if (root == None)
        return;
    mgr = root.autoSave;
    if (mgr == None || !mgr.ShouldShowToast())
        return;

    // Light gray, bottom-left. SetTextColor + DSTY_Normal + explicit A=255
    // avoid the SetTextColorRGB alpha-zero quirk (transparent text).
    gc.SetFont(Font'DeusExUI.FontMenuSmall');
    gc.SetStyle(DSTY_Normal);
    c = MakeColor(180, 180, 180, 255);
    gc.SetTextColor(c);
    // Pin alignment explicitly — the GC is shared across sibling windows, so
    // a prior draw could leave center/right set and shift us off the corner.
    gc.SetAlignments(HALIGN_Left, VALIGN_Top);

    ty = height - TEXT_H - MARGIN;
    gc.DrawText(MARGIN, ty, TEXT_W, TEXT_H, mgr.AutoSavingLabel);
}

function Color MakeColor(int r, int g, int b, int a)
{
    local Color c;
    c.R = r;
    c.G = g;
    c.B = b;
    c.A = a;
    return c;
}
