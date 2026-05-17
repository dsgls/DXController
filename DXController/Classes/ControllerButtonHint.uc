//=============================================================================
// ControllerButtonHint — static helpers for drawing controller-button
// icon + label hints.
//
// Owns the logical-id -> texture map for the DXControllerTex package
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
const ICON_GAP  = 4.0;    // gap between an icon and its label
const ICON_SRC  = 64.0;   // native edge length of the DXControllerTex
                          // textures (assets/png-to-pcx.py SIZE)

// Resolve a logical button id to its texture. id is one of:
//   a, b, x, y, back, share, start,
//   dpad, dpad_up, dpad_down, dpad_left, dpad_right,
//   lb, ls, lt, rb, rs, rt
// Returns None for an unrecognised id.
static function Texture GetButtonTexture(string id)
{
    if (id == "a")          return Texture'DXControllerTex.a';
    if (id == "b")          return Texture'DXControllerTex.b';
    if (id == "x")          return Texture'DXControllerTex.x';
    if (id == "y")          return Texture'DXControllerTex.y';
    if (id == "back")       return Texture'DXControllerTex.back';
    if (id == "share")      return Texture'DXControllerTex.share';
    if (id == "start")      return Texture'DXControllerTex.start';
    if (id == "dpad")       return Texture'DXControllerTex.dpad';
    if (id == "dpad_up")    return Texture'DXControllerTex.dpad_up';
    if (id == "dpad_down")  return Texture'DXControllerTex.dpad_down';
    if (id == "dpad_left")  return Texture'DXControllerTex.dpad_left';
    if (id == "dpad_right") return Texture'DXControllerTex.dpad_right';
    if (id == "lb")         return Texture'DXControllerTex.lb';
    if (id == "ls")         return Texture'DXControllerTex.ls';
    if (id == "lt")         return Texture'DXControllerTex.lt';
    if (id == "rb")         return Texture'DXControllerTex.rb';
    if (id == "rs")         return Texture'DXControllerTex.rs';
    if (id == "rt")         return Texture'DXControllerTex.rt';
    return None;
}

// Draw [icon] label at (x, y). Returns the x coordinate just past the
// label text so callers can chain hints left-to-right.
static function float DrawHint(GC gc, float x, float y, string id, string label)
{
    local Texture icon;
    local float xExt, yExt, textX;
    local Color iconCol, textCol;

    icon = GetButtonTexture(id);
    gc.SetStyle(DSTY_Masked);

    // GC.SetTileColorRGB / SetTextColorRGB build a Color but leave the
    // alpha byte at 0. Under DSTY_Masked the text renderer honours that
    // alpha, so an RGB-only text colour draws the label fully
    // transparent. Build both colours with an explicit opaque alpha.
    iconCol.R = 255;
    iconCol.G = 255;
    iconCol.B = 255;
    iconCol.A = 255;
    textCol.R = 200;
    textCol.G = 198;
    textCol.B = 170;
    textCol.A = 255;

    // textX trails the icon when one resolved; for an unrecognised id
    // (icon == None) the label sits at x with no phantom icon gap.
    textX = x;
    if (icon != None)
    {
        gc.SetTileColor(iconCol);
        // DrawTexture blits 1:1 — destWidth/Height only clip, they do
        // not scale (the call takes a source *origin*, not a source
        // rect), so a 64x64 glyph in a 16x16 box shows only its
        // transparent corner. DrawStretchedTexture takes a source rect
        // and scales it to the destination rect.
        gc.DrawStretchedTexture(x, y, ICON_SIZE, ICON_SIZE,
                                0, 0, ICON_SRC, ICON_SRC, icon);
        textX = x + ICON_SIZE + ICON_GAP;
    }

    gc.SetFont(Font'DeusExUI.FontMenuSmall');
    gc.SetTextColor(textCol);
    gc.SetAlignments(HALIGN_Left, VALIGN_Center);
    gc.DrawText(textX, y, 200.0, ICON_SIZE, label);

    gc.GetTextExtent(0.0, xExt, yExt, label);
    return textX + xExt;
}

// Pixel width one hint will occupy when drawn by DrawHint. Used by
// ControllerHintOverlay to size and centre the legend strip before
// drawing. Mirrors DrawHint's layout exactly: an icon box + gap when
// the id resolves to a texture, plus the label's measured extent.
// The caller's GC font is overwritten (set to FontMenuSmall) — same
// as DrawHint does.
static function float MeasureHint(GC gc, string id, string label)
{
    local float xExt, yExt;
    local float w;

    w = 0.0;
    if (GetButtonTexture(id) != None)
        w = ICON_SIZE + ICON_GAP;

    gc.SetFont(Font'DeusExUI.FontMenuSmall');
    gc.GetTextExtent(0.0, xExt, yExt, label);
    return w + xExt;
}
