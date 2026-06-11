//=============================================================================
// DXCUITheme — static colour helpers for the belt-derived UI theme.
//
// The stock item bar (HUDObjectBelt) draws greyscale art tinted by the
// HUD colour theme using DSTY_Translucent, which in this engine is
// additive: texture/fill luminance IS opacity. Measured from the stock
// belt textures:
//   cell fill = luminance 50   (HUDObjectBeltBackground_Cell interior)
//   frames    = luminance 75   (bar fill / cell edges)
// All DXController translucent UI (weapon/aug wheel, on-screen
// keyboard) derives its tile colours from these helpers, so the widgets
// follow the selected HUD colour scheme exactly like the belt does.
//
// Translucent draws stack additively (a cell drawn over a panel fill
// reads brighter than the panel); the *Opaque variants bake that
// stacking into absolute colours for when the player turns HUD
// translucency off.
//=============================================================================
class DXCUITheme extends Object abstract;

// ScaleColor: scale a colour's RGB by f (0..1), clamped, with A forced
// to 255 (masked draws ignore alpha; translucent draws use brightness
// only — an explicit 255 avoids the invisible-text trap either way).
// Named ScaleColor (not Scale) to avoid a name collision with Core's
// built-in `struct Scale`.
static function Color ScaleColor(Color c, float f)
{
    local Color o;
    o.R = Clamp(int(float(c.R) * f), 0, 255);
    o.G = Clamp(int(float(c.G) * f), 0, 255);
    o.B = Clamp(int(float(c.B) * f), 0, 255);
    o.A = 255;
    return o;
}

// ---- translucent (additive) tile colours ----
// Panel and cell fills both add LUM 50; a cell drawn over a panel fill
// stacks to an effective 100. Frames add LUM 75.
static function Color FillAdd(Color themeBg)
{
    return ScaleColor(themeBg, 50.0 / 255.0);
}

static function Color FrameAdd(Color themeBg)
{
    return ScaleColor(themeBg, 75.0 / 255.0);
}

// ---- opaque (masked) equivalents, same relative brightnesses ----
// CellOpaque is 100 because a translucent cell is two stacked 50-lum
// passes (panel fill + cell fill); the opaque path draws once.
static function Color PanelOpaque(Color themeBg)
{
    return ScaleColor(themeBg, 50.0 / 255.0);
}

static function Color CellOpaque(Color themeBg)
{
    return ScaleColor(themeBg, 100.0 / 255.0);
}

static function Color FrameOpaque(Color themeBg)
{
    return ScaleColor(themeBg, 125.0 / 255.0);
}

// DSTY_Modulated darkening veil: multiplies the scene to ~x0.25
// (modulate maps tile grey 128 -> x1.0, so 32 -> x0.25). Theme-
// independent; the colour scheme shows in the additive passes on top.
static function Color VeilColor()
{
    local Color c;
    c.R = 32;
    c.G = 32;
    c.B = 32;
    c.A = 255;
    return c;
}
