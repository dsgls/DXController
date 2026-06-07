//=============================================================================
// ControllerCurvePreview — 150x150 stick-response visualizer.
//
// Renders, per stick: a vertical deadzone bar at x = deadzone/32767, a
// 128-sample dot trace of the curve (queried from the launcher via
// XInputSampleCurve), and a live input dot (polled via XInputGetRawMag).
//
// Refresh() is called explicitly by the parent screen whenever the
// stick's settings change. Live dot updates per Tick. No curve math
// runs in this class — all sampling is delegated to the launcher to
// avoid divergence with launcher/src/XInput.cpp ShapeStickMagnitude.
//=============================================================================
class ControllerCurvePreview extends Window;

// Deadzone is configured in raw XInput SHORT units (0..32767),
// matching the launcher (launcher/src/XInput.cpp:208).
// This is the only place in script that knows the 32767 constant.
const KSHORT_RANGE = 32767;

const NUM_SAMPLES = 128;
const PLOT_SIZE   = 150;
const DOT_SIZE    = 2;
const LIVE_DOT_SIZE = 4;
const DEADZONE_BAR_WIDTH = 1;
// Label box above the plot. Tall enough for two wrapped lines (the
// sigmoid suffix "Sigmoid (k=6.0, c=0.60, w=0.60)" overflows PLOT_SIZE
// width and GC.DrawText wraps it). Height tuned to FontMenuSmall's
// 14-px line height. UE1 forbids const-expression initializers (each
// const must be a literal), so the dependent values are precomputed:
//   PLOT_TOP_Y = LABEL_PAD_TOP + LABEL_HEIGHT + LABEL_PAD_BOTTOM
//              = 2 + 28 + 2 = 32
//   WIN_HEIGHT = PLOT_TOP_Y + PLOT_SIZE + 6
//              = 32 + 150 + 6 = 188
//   WIN_WIDTH  = PLOT_SIZE + 16 = 166
const LABEL_PAD_TOP    = 2;
const LABEL_HEIGHT     = 28;
const LABEL_PAD_BOTTOM = 2;
const PLOT_TOP_Y       = 32;
const WIN_HEIGHT       = 188;
const WIN_WIDTH        = 166;

var byte  stickIdx;             // 0 = Left, 1 = Right
var float samples[128];         // y values, 0..1
var float liveU;                // raw stick magnitude, 0..1, polled per Tick

var Color colBorder, colBackground, colDeadzoneBar, colCurveDot, colLiveDotIdle, colLiveDotActive, colLabel;
var string lblPrefix;           // "Left stick: " or "Right stick: ", set per-instance by parent

event InitWindow()
{
    Super.InitWindow();
    SetSize(WIN_WIDTH, WIN_HEIGHT);
    bTickEnabled = True;
    Refresh();
}

// Pull a fresh set of curve samples from the launcher. Called on
// InitWindow and re-called by MenuScreenController whenever the
// stick's curve type or curve params change.
function Refresh()
{
    local string raw, tok;
    local int i, pos, start;
    local string sideName;
    local PlayerPawnExt pawn;

    if (stickIdx == 0) sideName = "Left"; else sideName = "Right";
    pawn = GetPlayerPawn();
    if (pawn == None)
    {
        for (i = 0; i < NUM_SAMPLES; i++) samples[i] = 0.0;
        return;
    }
    raw = pawn.ConsoleCommand("XInputSampleCurve " $ sideName $ " " $ string(NUM_SAMPLES));
    if (raw == "")
    {
        // Launcher doesn't support the command yet — leave samples zero.
        for (i = 0; i < NUM_SAMPLES; i++) samples[i] = 0.0;
        return;
    }

    // Parse "0.0000,0.0000,...,1.0000". Mid(s, ofs) is "s from ofs to end";
    // Mid(s, ofs, n) is "n chars starting at ofs". A trailing token has
    // no comma after it, so the InStr returns -1 and we take the tail.
    start = 0;
    for (i = 0; i < NUM_SAMPLES; i++)
    {
        pos = InStr(Mid(raw, start), ",");
        if (pos < 0)
        {
            tok = Mid(raw, start);
            samples[i] = float(tok);
            break;
        }
        tok = Mid(Mid(raw, start), 0, pos);
        samples[i] = float(tok);
        start = start + pos + 1;
    }
}

event Tick(float dt)
{
    local string raw, tok;
    local int lPos, rPos, sp;
    local PlayerPawnExt pawn;

    pawn = GetPlayerPawn();
    if (pawn == None) { liveU = 0.0; return; }
    raw = pawn.ConsoleCommand("XInputGetRawMag");
    if (raw == "") { liveU = 0.0; return; }

    // Format: "L=0.4200 R=0.0500".
    if (stickIdx == 0)
    {
        lPos = InStr(raw, "L=");
        if (lPos < 0) { liveU = 0.0; return; }
        // Take the substring after "L=", then cut at the next space.
        tok = Mid(raw, lPos + 2);
        sp = InStr(tok, " ");
        if (sp >= 0) tok = Mid(tok, 0, sp);
        liveU = float(tok);
    }
    else
    {
        rPos = InStr(raw, "R=");
        if (rPos < 0) { liveU = 0.0; return; }
        liveU = float(Mid(raw, rPos + 2));
    }
    if (liveU < 0.0) liveU = 0.0;
    if (liveU > 1.0) liveU = 1.0;
}

event DrawWindow(GC gc)
{
    local int i, x, y;
    local int plotX, plotY;
    local int deadzoneShort;
    local float deadzoneFrac;
    local int liveX, liveY;
    local int sampleIdx;
    local Color dotColor;
    local string label;

    // Plot origin (top-left of the 150x150 area, leaving room for the
    // two-line label band above).
    plotX = 4;
    plotY = PLOT_TOP_Y;

    // Opaque background. DSTY_Masked over Texture'Solid' renders fully
    // opaque (masked tile draws ignore tile-colour alpha); DSTY_Translucent
    // is purely additive over Solid and a dark tint would add ~nothing.
    gc.SetStyle(DSTY_Masked);
    gc.SetTileColor(colBackground);
    gc.DrawPattern(plotX, plotY, PLOT_SIZE, PLOT_SIZE, 0, 0, Texture'Solid');

    // Border.
    gc.SetTileColor(colBorder);
    gc.DrawBox(plotX, plotY, PLOT_SIZE, PLOT_SIZE, 0, 0, 1, Texture'Solid');

    // Deadzone bar at x = deadzoneShort / 32767. The launcher already
    // zeroes curve samples below the deadzone, so this is purely a
    // visual marker, not part of the input-output math.
    if (stickIdx == 0)
        deadzoneShort = Class'ControllerSettings'.Default.StickDeadzoneLeft;
    else
        deadzoneShort = Class'ControllerSettings'.Default.StickDeadzoneRight;
    deadzoneFrac = float(deadzoneShort) / float(KSHORT_RANGE);
    if (deadzoneFrac < 0.0) deadzoneFrac = 0.0;
    if (deadzoneFrac > 1.0) deadzoneFrac = 1.0;
    x = plotX + int(deadzoneFrac * float(PLOT_SIZE));
    gc.SetTileColor(colDeadzoneBar);
    gc.DrawPattern(x, plotY, DEADZONE_BAR_WIDTH, PLOT_SIZE, 0, 0, Texture'Solid');

    // Curve dots: x axis is input magnitude 0..1, y axis is output 0..1
    // (inverted because screen-y grows downward).
    gc.SetTileColor(colCurveDot);
    for (i = 0; i < NUM_SAMPLES; i++)
    {
        x = plotX + int(float(i) / float(NUM_SAMPLES - 1) * float(PLOT_SIZE));
        y = plotY + PLOT_SIZE - int(samples[i] * float(PLOT_SIZE)) - DOT_SIZE;
        gc.DrawPattern(x, y, DOT_SIZE, DOT_SIZE, 0, 0, Texture'Solid');
    }

    // Live dot: x from raw input magnitude, y from the matching curve sample.
    sampleIdx = int(liveU * float(NUM_SAMPLES - 1));
    if (sampleIdx < 0) sampleIdx = 0;
    if (sampleIdx >= NUM_SAMPLES) sampleIdx = NUM_SAMPLES - 1;
    liveX = plotX + int(liveU * float(PLOT_SIZE)) - (LIVE_DOT_SIZE / 2);
    liveY = plotY + PLOT_SIZE - int(samples[sampleIdx] * float(PLOT_SIZE)) - (LIVE_DOT_SIZE / 2);
    if (liveU > deadzoneFrac) dotColor = colLiveDotActive; else dotColor = colLiveDotIdle;
    gc.SetTileColor(dotColor);
    gc.DrawPattern(liveX, liveY, LIVE_DOT_SIZE, LIVE_DOT_SIZE, 0, 0, Texture'Solid');

    // Label above the plot. DrawText wraps at the rect width, so the
    // sigmoid suffix can spill onto a second line without overlapping
    // the plot.
    label = lblPrefix $ BuildLabelSuffix();
    gc.SetFont(Font'DeusExUI.FontMenuSmall');
    gc.SetTextColor(colLabel);
    gc.DrawText(plotX, LABEL_PAD_TOP, PLOT_SIZE, LABEL_HEIGHT, label);
}

// Build "Power (k=2.0)" / "Sigmoid (k=6.0, c=0.60, w=0.60)" etc.
function string BuildLabelSuffix()
{
    local string curveType;
    local float p1, p2, p3;

    if (stickIdx == 0)
    {
        curveType = Class'ControllerSettings'.Default.StickCurveLeft;
    }
    else
    {
        curveType = Class'ControllerSettings'.Default.StickCurveRight;
    }

    if (curveType ~= "Power")
    {
        if (stickIdx == 0) p1 = Class'ControllerSettings'.Default.StickCurvePowerLeft;
        else               p1 = Class'ControllerSettings'.Default.StickCurvePowerRight;
        return "Power (k=" $ FmtF1(p1) $ ")";
    }
    if (curveType ~= "Expo")
    {
        if (stickIdx == 0) p1 = Class'ControllerSettings'.Default.StickCurveExpoLeft;
        else               p1 = Class'ControllerSettings'.Default.StickCurveExpoRight;
        return "Expo (e=" $ FmtF2(p1) $ ")";
    }
    if (curveType ~= "Sigmoid")
    {
        if (stickIdx == 0)
        {
            p1 = Class'ControllerSettings'.Default.StickCurveSigmoidSteepnessLeft;
            p2 = Class'ControllerSettings'.Default.StickCurveSigmoidMidpointLeft;
            p3 = Class'ControllerSettings'.Default.StickCurveSigmoidStrengthLeft;
        }
        else
        {
            p1 = Class'ControllerSettings'.Default.StickCurveSigmoidSteepnessRight;
            p2 = Class'ControllerSettings'.Default.StickCurveSigmoidMidpointRight;
            p3 = Class'ControllerSettings'.Default.StickCurveSigmoidStrengthRight;
        }
        return "Sigmoid (k=" $ FmtF1(p1) $ ", c=" $ FmtF2(p2) $ ", w=" $ FmtF2(p3) $ ")";
    }
    return "Linear";
}

// Format float to 1 decimal place: "2.0", "6.5".
function string FmtF1(float v)
{
    local int scaled, intPart, fracPart;
    scaled = int(v * 10.0 + 0.5);
    if (scaled < 0) scaled = 0;
    intPart  = scaled / 10;
    fracPart = scaled - (intPart * 10);
    return string(intPart) $ "." $ string(fracPart);
}

// Format float to 2 decimal places: "0.60", "0.05".
function string FmtF2(float v)
{
    local int scaled, intPart, fracPart;
    local string frac;
    scaled = int(v * 100.0 + 0.5);
    if (scaled < 0) scaled = 0;
    intPart  = scaled / 100;
    fracPart = scaled - (intPart * 100);
    frac = string(fracPart);
    if (Len(frac) < 2) frac = "0" $ frac;
    return string(intPart) $ "." $ frac;
}

defaultproperties
{
    colBorder=(R=80,G=90,B=110,A=255)
    colBackground=(R=20,G=22,B=28,A=255)
    colDeadzoneBar=(R=120,G=130,B=150,A=255)
    colCurveDot=(R=240,G=178,B=96,A=255)
    colLiveDotIdle=(R=255,G=255,B=255,A=255)
    colLiveDotActive=(R=255,G=48,B=48,A=255)
    colLabel=(R=205,G=211,B=220,A=255)
    lblPrefix="Left stick: "
    stickIdx=0
    bTickEnabled=True
}
