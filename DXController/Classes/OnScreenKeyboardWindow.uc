//=============================================================================
// OnScreenKeyboardWindow — gamepad-driven virtual keyboard.
//
// A persistent child of ControllerRootWindow (created in InitWindow,
// like radial / focusOverlay). Draws nothing while bOpen is false.
//
// Opened via ControllerRootWindow.OpenKeyboard, which calls Open()
// here. The keyboard does NOT take engine focus — a root-child window
// cannot capture key dispatch that way (verified by play-test).
// Instead ControllerRootWindow.VirtualKeyPressed intercepts every key
// while bOpen and routes it through HandleKey (D-pad / A / X / B),
// consuming everything so nothing leaks to the screen beneath.
// Physical-keyboard Esc is handled separately: ComputerUIWindow's
// gated IK_Escape handler calls ControllerRootWindow.CloseGamepadKeyboard.
// Characters are written into the target MenuUIEditWindow through the
// stock EditWindow natives (InsertText / DeleteChar) — no synthesised
// keystrokes.
//
// Uppercase-only: every terminal text field is Caps()-compared, so a
// single-case keyboard is sufficient (see the design doc). 4x10 grid of
// QWERTY-ordered letters / digits / the symbols . - _ #, plus a
// SPACE / BACKSPACE special row.
//=============================================================================
class OnScreenKeyboardWindow extends HUDBaseWindow;

// ---- open state ----
var bool             bOpen;
var MenuUIEditWindow target;        // field being edited; None when closed
var Window           targetScreen;  // screen owning `target`; None when closed
var string           promptLabel;  // caller-supplied; drawn at panel top

// ---- grid focus ----
// focusRow 0..3 = character rows; focusRow 4 = the special row.
// focusCol 0..9 on character rows; 0..1 on the special row.
var int focusRow;
var int focusCol;

// The four character rows. Uppercase, QWERTY key order, each padded to
// 10 columns with the symbol set so the grid is a clean rectangle.
var string kbRows[4];

const ROW_SPECIAL   = 4;
const NUM_ROWS      = 5;    // 4 character rows + 1 special row
const CHAR_COLS     = 10;
const SPECIAL_COLS  = 2;
const SPECIAL_SPACE = 0;
const SPECIAL_BKSP  = 1;

// ---- layout constants (pixels) ----
const KEY_W     = 26.0;
const KEY_H     = 22.0;
const KEY_GAP   = 4.0;
const PANEL_PAD = 18.0;
const LABEL_H   = 16.0;
const ECHO_H    = 26.0;
const SPECIAL_W = 130.0;   // width of each special-row key
const FOOTER_H  = 20.0;

// ---------------------------------------------------------------------------
// Open / close
// ---------------------------------------------------------------------------

function Open(MenuUIEditWindow t, Window ownerScreen, string label)
{
    if (t == None)
        return;

    target      = t;
    targetScreen = ownerScreen;
    promptLabel = label;
    bOpen       = true;
    focusRow    = 1;   // home cell = 'Q'
    focusCol    = 0;

    // Insertion point to end of any existing text so typing appends.
    target.SetInsertionPoint(target.GetTextLength());

    // Draw above the focus overlay and every modal screen.
    Raise();

    // The keyboard does NOT take engine focus — a root-child window
    // does not capture key dispatch that way (verified by play-test).
    // Input is delivered by ControllerRootWindow.VirtualKeyPressed,
    // which intercepts gamepad keys into HandleKey while bOpen. The
    // target field keeps its engine focus, so a physical keyboard can
    // still type into it directly.
    class'DXControllerDebug'.static.DebugLog(
        "DXC-KBD OPEN target=" $ string(target.Class) $ " label=" $ label);
}

// Normal close (B / Esc).
function CloseKbd(string reason)
{
    if (!bOpen)
        return;

    bOpen  = false;
    target = None;
    targetScreen = None;

    class'DXControllerDebug'.static.DebugLog("DXC-KBD CLOSE reason=" $ reason);
}

// Teardown close: the target field is being destroyed with its screen,
// so there is nothing to restore focus to.
function ForceClose()
{
    if (!bOpen)
        return;
    bOpen  = false;
    target = None;
    targetScreen = None;
    class'DXControllerDebug'.static.DebugLog("DXC-KBD CLOSE reason=teardown");
}

// ---------------------------------------------------------------------------
// Input
// ---------------------------------------------------------------------------

event bool VirtualKeyPressed(EInputKey key, bool bRepeat)
{
    if (!bOpen)
        return Super.VirtualKeyPressed(key, bRepeat);

    HandleKey(key, bRepeat);
    return true;   // modal: consume every key while open
}

// D-pad acts on auto-repeat (hold a direction to travel the grid);
// A / X / B / Esc fire once per press.
function HandleKey(EInputKey key, bool bRepeat)
{
    if (!bOpen)
        return;

    if (key == IK_JoyPovUp)    { MoveFocus(0, -1); return; }
    if (key == IK_JoyPovDown)  { MoveFocus(0,  1); return; }
    if (key == IK_JoyPovLeft)  { MoveFocus(-1, 0); return; }
    if (key == IK_JoyPovRight) { MoveFocus( 1, 0); return; }

    if (!bRepeat)
    {
        if (key == IK_Joy1)   { ActivateFocusedKey(); return; }   // A
        if (key == IK_Joy3)   { DoBackspace();        return; }   // X
        if (key == IK_Joy2)   { CloseKbd("B");        return; }   // B
        if (key == IK_Escape) { CloseKbd("Esc");      return; }
    }
}

// dx / dy in {-1, 0, +1}. Both axes wrap end-to-end.
function MoveFocus(int dx, int dy)
{
    if (dy != 0)
    {
        focusRow = (focusRow + dy + NUM_ROWS) % NUM_ROWS;
        // Entering the special row from a character row: remap the
        // character column (0..9) onto SPACE (left half) or BACKSPACE
        // (right half). Unconditional — a dy move only lands on the
        // special row when coming from a character row, so focusCol is
        // always a character column here.
        if (focusRow == ROW_SPECIAL)
        {
            if (focusCol < 5)
                focusCol = SPECIAL_SPACE;
            else
                focusCol = SPECIAL_BKSP;
        }
    }
    if (dx != 0)
    {
        if (focusRow == ROW_SPECIAL)
            focusCol = (focusCol + dx + SPECIAL_COLS) % SPECIAL_COLS;
        else
            focusCol = (focusCol + dx + CHAR_COLS) % CHAR_COLS;
    }
}

function ActivateFocusedKey()
{
    if (focusRow == ROW_SPECIAL)
    {
        if (focusCol == SPECIAL_BKSP)
            DoBackspace();
        else
            InsertChar(" ");
        return;
    }
    InsertChar(Mid(kbRows[focusRow], focusCol, 1));
}

function InsertChar(string ch)
{
    if (target == None || ch == "")
        return;
    target.InsertText(ch, true);
    class'DXControllerDebug'.static.DebugLog("DXC-KBD KEY id=" $ ch);
}

function DoBackspace()
{
    if (target == None)
        return;
    target.DeleteChar(true, true);
    class'DXControllerDebug'.static.DebugLog("DXC-KBD BACKSPACE");
}

// ---------------------------------------------------------------------------
// Rendering
// ---------------------------------------------------------------------------

event DrawWindow(GC gc)
{
    local float panelW, panelH, panelX, panelY;
    local float gridW, gridX, y;
    local Color modDark, floorLift, accent, lightText;

    Super.DrawWindow(gc);

    if (!bOpen)
        return;

    gridW  = CHAR_COLS * KEY_W + (CHAR_COLS - 1) * KEY_GAP;
    panelW = gridW + 2.0 * PANEL_PAD;
    panelH = 2.0 * PANEL_PAD + LABEL_H + 6.0 + ECHO_H + 10.0
           + (4.0 * KEY_H + 3.0 * KEY_GAP)   // character grid
           + KEY_GAP + KEY_H                 // special row
           + 12.0 + FOOTER_H;                // footer
    panelX = (width  - panelW) * 0.5;
    panelY = (height - panelH) * 0.5;

    // Panel fill: a uniform dark veil over whatever is behind the
    // keyboard. Neither GC blend style gives a uniform translucent fill
    // on its own — DSTY_Translucent over Texture'Solid' is purely
    // additive (a dark tint adds ~nothing; the panel stays see-through)
    // and DSTY_Modulated is purely multiplicative (it darkens lit areas
    // but leaves black areas pure black, so the panel looks blotchy).
    // Two passes combine into an even veil: modulate the scene down
    // toward black, then add a flat dark floor back. modDark sets how
    // much underlying context still bleeds through; floorLift sets the
    // minimum darkness (raise it if the panel looks uneven).
    modDark   = MakeColor(24, 24, 24, 255);   // multiply: ~0.19x
    floorLift = MakeColor(26, 26, 26, 255);   // additive dark floor
    accent    = colBorder;
    accent.A  = 255;
    lightText = MakeColor(200, 198, 170, 255);

    // Panel: modulate-down then lift to a flat floor, + accent border.
    gc.SetStyle(DSTY_Modulated);
    gc.SetTileColor(modDark);
    gc.DrawPattern(panelX, panelY, panelW, panelH, 0, 0, Texture'Solid');
    gc.SetStyle(DSTY_Translucent);
    gc.SetTileColor(floorLift);
    gc.DrawPattern(panelX, panelY, panelW, panelH, 0, 0, Texture'Solid');
    gc.SetStyle(DSTY_Masked);
    gc.SetTileColor(accent);
    gc.DrawBox(panelX, panelY, panelW, panelH, 0, 0, 2, Texture'Solid');

    gridX = panelX + PANEL_PAD;
    y     = panelY + PANEL_PAD;

    // Label.
    gc.SetStyle(DSTY_Masked);
    gc.SetFont(Font'DeusExUI.FontMenuSmall');
    gc.SetTextColor(accent);
    gc.SetAlignments(HALIGN_Left, VALIGN_Top);
    gc.DrawText(gridX, y, gridW, LABEL_H, promptLabel);
    y += LABEL_H + 6.0;

    // Echo line.
    DrawEcho(gc, gridX, y, gridW, ECHO_H, lightText);
    y += ECHO_H + 10.0;

    // Character grid.
    DrawCharGrid(gc, gridX, y, accent, lightText);
    y += 4.0 * KEY_H + 3.0 * KEY_GAP + KEY_GAP;

    // Special row.
    DrawSpecialRow(gc, gridX, y, gridW, accent, lightText);
    y += KEY_H + 12.0;

    // Footer hints.
    DrawFooter(gc, gridX, y);
}

function DrawEcho(GC gc, float x, float y, float w, float h, Color textCol)
{
    local string shown;
    local float xExt, yExt;

    shown = "";
    if (target != None)
        shown = target.GetText();

    // Echo field: modulated black knocks the panel out to a solid black
    // inset. Translucent black would be additive and draw nothing.
    gc.SetStyle(DSTY_Modulated);
    gc.SetTileColor(MakeColor(0, 0, 0, 255));
    gc.DrawPattern(x, y, w, h, 0, 0, Texture'Solid');

    gc.SetStyle(DSTY_Masked);
    gc.SetFont(Font'DeusExUI.FontMenuSmall');
    gc.SetTextColor(textCol);
    gc.SetAlignments(HALIGN_Left, VALIGN_Center);
    gc.DrawText(x + 6.0, y, w - 12.0, h, shown);

    // Blinking block caret just past the text (~2 Hz).
    if (player != None && (int(player.Level.TimeSeconds * 2.0) % 2) == 0)
    {
        gc.GetTextExtent(0.0, xExt, yExt, shown);
        gc.SetStyle(DSTY_Masked);
        gc.SetTileColor(textCol);
        gc.DrawPattern(x + 6.0 + xExt, y + h * 0.5 - 7.0, 7.0, 12.0,
                       0, 0, Texture'Solid');
    }
}

function DrawCharGrid(GC gc, float x, float y, Color accent, Color textCol)
{
    local int r, c;
    local float cellX, cellY;

    for (r = 0; r < 4; r++)
    {
        cellY = y + r * (KEY_H + KEY_GAP);
        for (c = 0; c < CHAR_COLS; c++)
        {
            cellX = x + c * (KEY_W + KEY_GAP);
            DrawKey(gc, cellX, cellY, KEY_W, KEY_H,
                    Mid(kbRows[r], c, 1), accent, textCol,
                    (focusRow == r && focusCol == c));
        }
    }
}

function DrawSpecialRow(GC gc, float x, float y, float gridW,
                        Color accent, Color textCol)
{
    local float gap;

    gap = gridW - 2.0 * SPECIAL_W;   // space between the two keys
    DrawKey(gc, x, y, SPECIAL_W, KEY_H, "SPACE", accent, textCol,
            (focusRow == ROW_SPECIAL && focusCol == SPECIAL_SPACE));
    DrawKey(gc, x + SPECIAL_W + gap, y, SPECIAL_W, KEY_H, "BACKSPACE",
            accent, textCol,
            (focusRow == ROW_SPECIAL && focusCol == SPECIAL_BKSP));
}

function DrawKey(GC gc, float x, float y, float w, float h, string label,
                 Color accent, Color textCol, bool bFocused)
{
    if (bFocused)
    {
        gc.SetStyle(DSTY_Masked);
        gc.SetTileColor(accent);
        gc.DrawPattern(x, y, w, h, 0, 0, Texture'Solid');
        gc.SetTextColor(MakeColor(8, 8, 8, 255));
    }
    else
    {
        gc.SetStyle(DSTY_Masked);
        gc.SetTileColor(MakeColor(60, 60, 60, 255));
        gc.DrawBox(x, y, w, h, 0, 0, 1, Texture'Solid');
        gc.SetTextColor(textCol);
    }

    gc.SetStyle(DSTY_Masked);
    gc.SetFont(Font'DeusExUI.FontMenuSmall');
    gc.SetAlignments(HALIGN_Center, VALIGN_Center);
    gc.DrawText(x, y, w, h, label);
}

function DrawFooter(GC gc, float x, float y)
{
    local float fx;

    fx = x;
    fx = class'ControllerButtonHint'.static.DrawHint(gc, fx, y, "a", "Select");
    fx += 20.0;
    fx = class'ControllerButtonHint'.static.DrawHint(gc, fx, y, "x", "Backspace");
    fx += 20.0;
    class'ControllerButtonHint'.static.DrawHint(gc, fx, y, "b", "Close");
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

defaultproperties
{
    bOpen=False
    kbRows(0)="1234567890"
    kbRows(1)="QWERTYUIOP"
    kbRows(2)="ASDFGHJKL-"
    kbRows(3)="ZXCVBNM._#"
}
