//=============================================================================
// ControllerButtonHint — static helpers for drawing controller-button
// icon + label hints.
//
// Owns the logical-id -> texture map for the DXControllerBtn package
// (textures live in Group=XboxSeries; each object is named after its
// logical id). Callers pass a logical id ("a", "dpad_down", ...) and
// never a texture path.
//
// The on-screen keyboard footer is the first consumer; future
// per-context button hints reuse the same helper. Extends
// ExtensionObject so the EDrawStyle / EHAlign / EVAlign enums resolve
// (same reason ComputerButtonBarNav does).
//=============================================================================
class ControllerButtonHint extends ExtensionObject;

const ICON_SIZE = 16.0;
const ICON_GAP  = 4.0;   // gap between an icon and its label

// Resolve a logical button id to its texture. id is one of:
//   a, b, x, y, back, share, start,
//   dpad, dpad_up, dpad_down, dpad_left, dpad_right,
//   lb, ls, lt, rb, rs, rt
// Returns None for an unrecognised id.
static function Texture GetButtonTexture(string id)
{
    if (id == "a")          return Texture'DXControllerBtn.a';
    if (id == "b")          return Texture'DXControllerBtn.b';
    if (id == "x")          return Texture'DXControllerBtn.x';
    if (id == "y")          return Texture'DXControllerBtn.y';
    if (id == "back")       return Texture'DXControllerBtn.back';
    if (id == "share")      return Texture'DXControllerBtn.share';
    if (id == "start")      return Texture'DXControllerBtn.start';
    if (id == "dpad")       return Texture'DXControllerBtn.dpad';
    if (id == "dpad_up")    return Texture'DXControllerBtn.dpad_up';
    if (id == "dpad_down")  return Texture'DXControllerBtn.dpad_down';
    if (id == "dpad_left")  return Texture'DXControllerBtn.dpad_left';
    if (id == "dpad_right") return Texture'DXControllerBtn.dpad_right';
    if (id == "lb")         return Texture'DXControllerBtn.lb';
    if (id == "ls")         return Texture'DXControllerBtn.ls';
    if (id == "lt")         return Texture'DXControllerBtn.lt';
    if (id == "rb")         return Texture'DXControllerBtn.rb';
    if (id == "rs")         return Texture'DXControllerBtn.rs';
    if (id == "rt")         return Texture'DXControllerBtn.rt';
    return None;
}

// Draw [icon] label at (x, y). Returns the x coordinate just past the
// label text so callers can chain hints left-to-right.
static function float DrawHint(GC gc, float x, float y, string id, string label)
{
    local Texture icon;
    local float xExt, yExt, textX;

    icon = GetButtonTexture(id);
    gc.SetStyle(DSTY_Masked);

    // textX trails the icon when one resolved; for an unrecognised id
    // (icon == None) the label sits at x with no phantom icon gap.
    textX = x;
    if (icon != None)
    {
        gc.SetTileColorRGB(255, 255, 255);
        gc.DrawTexture(x, y, ICON_SIZE, ICON_SIZE, 0, 0, icon);
        textX = x + ICON_SIZE + ICON_GAP;
    }

    gc.SetFont(Font'DeusExUI.FontMenuSmall');
    gc.SetTextColorRGB(200, 198, 170);
    gc.SetAlignments(HALIGN_Left, VALIGN_Center);
    gc.DrawText(textX, y, 200.0, ICON_SIZE, label);

    gc.GetTextExtent(0.0, xExt, yExt, label);
    return textX + xExt;
}
