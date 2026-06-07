//=============================================================================
// MenuScreenController — the Settings → Controller page.
//
// Hosts up to 14 MenuUIChoice rows on the left (7 per stick: deadzone,
// curve type, and up to 5 curve-param rows of which only the active
// curve's are shown — at most 5 visible per stick, 10 at once) and two
// ControllerCurvePreview windows on the right (one per stick, stacked
// vertically).
//
// All rows are spawned at InitWindow regardless of curve type; visibility
// toggling is handled by RepackLayout, which also swaps the background to
// the variant matching the visible-row count. Stock CreateChoices iterates the
// 13-slot choices[] array, which we exceed (14 rows), so we override
// CreateChoices and spawn directly via winClient.NewChild.
//=============================================================================
class MenuScreenController extends MenuUIScreenWindow;

// Per-stick rows.
var MenuChoice_StickDeadzone         rowDeadzoneL, rowDeadzoneR;
var MenuChoice_StickCurveType        rowCurveTypeL, rowCurveTypeR;
var MenuChoice_StickFloatParam       rowPowerL, rowPowerR;
var MenuChoice_StickFloatParam       rowExpoL, rowExpoR;
var MenuChoice_StickFloatParam       rowSigSteepL, rowSigSteepR;
var MenuChoice_StickFloatParam       rowSigMidL, rowSigMidR;
var MenuChoice_StickFloatParam       rowSigStrL, rowSigStrR;

// Curve previews (one per stick).
var ControllerCurvePreview vizLeft, vizRight;

// Background tile sets, one per possible visible-row total. Declared one
// array per line: UE1 UCC does not reliably accept multiple sized arrays
// in a single `var` statement. SelectBackground picks the set matching
// the row count RepackLayout computed and pushes it into winClient.
var Texture bgTiles4[6];
var Texture bgTiles5[6];
var Texture bgTiles6[6];
var Texture bgTiles7[6];
var Texture bgTiles8[6];
var Texture bgTiles10[6];

// Y position where the Right-stick block begins; used by a future divider
// line drawn between the two stick blocks.
var int dividerRightY;

function CreateChoices()
{
    rowDeadzoneL   = MenuChoice_StickDeadzone(  winClient.NewChild(Class'MenuChoice_StickDeadzoneLeft' ));
    rowCurveTypeL  = MenuChoice_StickCurveType( winClient.NewChild(Class'MenuChoice_StickCurveTypeLeft'));
    rowPowerL      = MenuChoice_StickFloatParam(winClient.NewChild(Class'MenuChoice_StickCurvePowerLeft'));
    rowExpoL       = MenuChoice_StickFloatParam(winClient.NewChild(Class'MenuChoice_StickCurveExpoLeft' ));
    rowSigSteepL   = MenuChoice_StickFloatParam(winClient.NewChild(Class'MenuChoice_StickCurveSigmoidSteepnessLeft'));
    rowSigMidL     = MenuChoice_StickFloatParam(winClient.NewChild(Class'MenuChoice_StickCurveSigmoidMidpointLeft' ));
    rowSigStrL     = MenuChoice_StickFloatParam(winClient.NewChild(Class'MenuChoice_StickCurveSigmoidStrengthLeft' ));

    rowDeadzoneR   = MenuChoice_StickDeadzone(  winClient.NewChild(Class'MenuChoice_StickDeadzoneRight' ));
    rowCurveTypeR  = MenuChoice_StickCurveType( winClient.NewChild(Class'MenuChoice_StickCurveTypeRight'));
    rowPowerR      = MenuChoice_StickFloatParam(winClient.NewChild(Class'MenuChoice_StickCurvePowerRight'));
    rowExpoR       = MenuChoice_StickFloatParam(winClient.NewChild(Class'MenuChoice_StickCurveExpoRight' ));
    rowSigSteepR   = MenuChoice_StickFloatParam(winClient.NewChild(Class'MenuChoice_StickCurveSigmoidSteepnessRight'));
    rowSigMidR     = MenuChoice_StickFloatParam(winClient.NewChild(Class'MenuChoice_StickCurveSigmoidMidpointRight' ));
    rowSigStrR     = MenuChoice_StickFloatParam(winClient.NewChild(Class'MenuChoice_StickCurveSigmoidStrengthRight' ));

    // Right-side curve previews. Stack vertically with a 14-px gap. Y
    // for vizRight is hardcoded against ControllerCurvePreview.WIN_HEIGHT
    // (188); UE1 has no cross-class const access, and reading vizLeft.height
    // back after SetSize is unreliable across UE1 windowing paths and gave
    // us overlapping vizs. Keep this in sync with WIN_HEIGHT if it changes.
    vizLeft  = ControllerCurvePreview(winClient.NewChild(Class'ControllerCurvePreview'));
    vizLeft.stickIdx  = 0;
    vizLeft.lblPrefix = "Left stick: ";
    vizLeft.SetPos(540, 8);

    vizRight = ControllerCurvePreview(winClient.NewChild(Class'ControllerCurvePreview'));
    vizRight.stickIdx  = 1;
    vizRight.lblPrefix = "Right stick: ";
    vizRight.SetPos(540, 8 + 188 + 14);

    // Re-Refresh after both previews exist and parent linkage is final, so
    // GetPlayerPawn() definitely resolves and the launcher command runs.
    vizLeft.Refresh();
    vizRight.Refresh();

    // RepackLayout (which hides curve-param rows that don't apply to the
    // active curve type) runs from InitWindow *after* LoadSettings. Window's
    // GetTopChild defaults to bVisibleOnly=True, so MenuUIScreenWindow's
    // LoadSettings would skip already-hidden rows and they'd display empty
    // when later toggled visible.
}

event InitWindow()
{
    Super.InitWindow();
    RepackLayout();
}

// Lay out the choice rows in the left column, hiding rows that don't
// apply to the active curve type for their stick.
function RepackLayout()
{
    local string leftType, rightType;
    local int n;

    leftType  = Class'ControllerSettings'.Default.StickCurveLeft;
    rightType = Class'ControllerSettings'.Default.StickCurveRight;

    n = 0;

    // Left stick block.
    n = PlaceRow(rowDeadzoneL,  n);
    n = PlaceRow(rowCurveTypeL, n);
    n = PlaceVisibleParam(rowPowerL,    leftType, 'Power',   n);
    n = PlaceVisibleParam(rowExpoL,     leftType, 'Expo',    n);
    n = PlaceVisibleParam(rowSigSteepL, leftType, 'Sigmoid', n);
    n = PlaceVisibleParam(rowSigMidL,   leftType, 'Sigmoid', n);
    n = PlaceVisibleParam(rowSigStrL,   leftType, 'Sigmoid', n);

    // Right stick divider position is between the L block and the R block.
    dividerRightY = choiceStartY + (n * choiceVerticalGap) - 4;

    // Right stick block.
    n = PlaceRow(rowDeadzoneR,  n);
    n = PlaceRow(rowCurveTypeR, n);
    n = PlaceVisibleParam(rowPowerR,    rightType, 'Power',   n);
    n = PlaceVisibleParam(rowExpoR,     rightType, 'Expo',    n);
    n = PlaceVisibleParam(rowSigSteepR, rightType, 'Sigmoid', n);
    n = PlaceVisibleParam(rowSigMidR,   rightType, 'Sigmoid', n);
    n = PlaceVisibleParam(rowSigStrR,   rightType, 'Sigmoid', n);

    SelectBackground(n);
}

function int PlaceRow(MenuUIChoice row, int n)
{
    if (row == None) return n;
    row.Show();
    row.SetPos(choiceStartX, choiceStartY + (n * choiceVerticalGap) - row.buttonVerticalOffset);
    return n + 1;
}

function int PlaceVisibleParam(MenuChoice_StickFloatParam row, string activeType, name appliesTo, int n)
{
    if (row == None) return n;
    if (string(appliesTo) ~= activeType)
    {
        row.Show();
        row.SetPos(choiceStartX, choiceStartY + (n * choiceVerticalGap) - row.buttonVerticalOffset);
        return n + 1;
    }
    else
    {
        row.Hide();
        return n;
    }
}

// Swap the live client background to the tile set whose recesses match
// the number of rows now visible. winClient redraws from clientTextures
// each frame, so overwriting them takes effect next frame with no
// re-init. rowCount is always one of {4,5,6,7,8,10} by construction; the
// default falls back to the tallest (10-row) set if that ever changes.
function SelectBackground(int rowCount)
{
    local int i;

    switch (rowCount)
    {
        case 4:  for (i = 0; i < 6; i++) winClient.SetClientTexture(i, bgTiles4[i]);  break;
        case 5:  for (i = 0; i < 6; i++) winClient.SetClientTexture(i, bgTiles5[i]);  break;
        case 6:  for (i = 0; i < 6; i++) winClient.SetClientTexture(i, bgTiles6[i]);  break;
        case 7:  for (i = 0; i < 6; i++) winClient.SetClientTexture(i, bgTiles7[i]);  break;
        case 8:  for (i = 0; i < 6; i++) winClient.SetClientTexture(i, bgTiles8[i]);  break;
        case 10: for (i = 0; i < 6; i++) winClient.SetClientTexture(i, bgTiles10[i]); break;
        default: for (i = 0; i < 6; i++) winClient.SetClientTexture(i, bgTiles10[i]); break;
    }
}

// Notification hooks called by the per-row MenuChoice subclasses after a
// live-applied value change. Deadzone changes don't move the curve plot
// — only the deadzone bar — and DrawWindow already reads the current
// deadzone every frame, so no Refresh is needed there.
function OnDeadzoneChanged(byte stickIdx)
{
}

function OnCurveTypeChanged(byte stickIdx)
{
    RepackLayout();
    if (stickIdx == 0) vizLeft.Refresh(); else vizRight.Refresh();
}

function OnCurveParamChanged(byte stickIdx)
{
    if (stickIdx == 0) vizLeft.Refresh(); else vizRight.Refresh();
}

event bool VirtualKeyPressed(EInputKey key, bool bRepeat)
{
    local MenuChoice_StickDeadzone   dz;
    local MenuChoice_StickFloatParam fp;

    if (currentChoice == None)
        return Super.VirtualKeyPressed(key, bRepeat);

    if (key == IK_Joy5)
    {
        dz = MenuChoice_StickDeadzone(currentChoice);
        if (dz != None) { dz.CycleCoarsePrev(); return True; }
        fp = MenuChoice_StickFloatParam(currentChoice);
        if (fp != None) { fp.CycleCoarsePrev(); return True; }
        // Curve-type rows have no coarse step; CycleCoarsePrev aliases to
        // CyclePreviousValue so LB/RB still cycle the curve type.
        if (MenuChoice_StickCurveType(currentChoice) != None)
        {
            MenuChoice_StickCurveType(currentChoice).CycleCoarsePrev();
            return True;
        }
        return Super.VirtualKeyPressed(key, bRepeat);
    }
    if (key == IK_Joy6)
    {
        dz = MenuChoice_StickDeadzone(currentChoice);
        if (dz != None) { dz.CycleCoarseNext(); return True; }
        fp = MenuChoice_StickFloatParam(currentChoice);
        if (fp != None) { fp.CycleCoarseNext(); return True; }
        if (MenuChoice_StickCurveType(currentChoice) != None)
        {
            MenuChoice_StickCurveType(currentChoice).CycleCoarseNext();
            return True;
        }
        return Super.VirtualKeyPressed(key, bRepeat);
    }

    return Super.VirtualKeyPressed(key, bRepeat);
}

defaultproperties
{
    actionButtons(0)=(Align=HALIGN_Right,Action=AB_OK)
    Title="Controller"
    ClientWidth=720
    ClientHeight=480
    bgTiles4(0)=Texture'DXController.MenuControllerBackground_4_1'
    bgTiles4(1)=Texture'DXController.MenuControllerBackground_4_2'
    bgTiles4(2)=Texture'DXController.MenuControllerBackground_4_3'
    bgTiles4(3)=Texture'DXController.MenuControllerBackground_4_4'
    bgTiles4(4)=Texture'DXController.MenuControllerBackground_4_5'
    bgTiles4(5)=Texture'DXController.MenuControllerBackground_4_6'
    bgTiles5(0)=Texture'DXController.MenuControllerBackground_5_1'
    bgTiles5(1)=Texture'DXController.MenuControllerBackground_5_2'
    bgTiles5(2)=Texture'DXController.MenuControllerBackground_5_3'
    bgTiles5(3)=Texture'DXController.MenuControllerBackground_5_4'
    bgTiles5(4)=Texture'DXController.MenuControllerBackground_5_5'
    bgTiles5(5)=Texture'DXController.MenuControllerBackground_5_6'
    bgTiles6(0)=Texture'DXController.MenuControllerBackground_6_1'
    bgTiles6(1)=Texture'DXController.MenuControllerBackground_6_2'
    bgTiles6(2)=Texture'DXController.MenuControllerBackground_6_3'
    bgTiles6(3)=Texture'DXController.MenuControllerBackground_6_4'
    bgTiles6(4)=Texture'DXController.MenuControllerBackground_6_5'
    bgTiles6(5)=Texture'DXController.MenuControllerBackground_6_6'
    bgTiles7(0)=Texture'DXController.MenuControllerBackground_7_1'
    bgTiles7(1)=Texture'DXController.MenuControllerBackground_7_2'
    bgTiles7(2)=Texture'DXController.MenuControllerBackground_7_3'
    bgTiles7(3)=Texture'DXController.MenuControllerBackground_7_4'
    bgTiles7(4)=Texture'DXController.MenuControllerBackground_7_5'
    bgTiles7(5)=Texture'DXController.MenuControllerBackground_7_6'
    bgTiles8(0)=Texture'DXController.MenuControllerBackground_8_1'
    bgTiles8(1)=Texture'DXController.MenuControllerBackground_8_2'
    bgTiles8(2)=Texture'DXController.MenuControllerBackground_8_3'
    bgTiles8(3)=Texture'DXController.MenuControllerBackground_8_4'
    bgTiles8(4)=Texture'DXController.MenuControllerBackground_8_5'
    bgTiles8(5)=Texture'DXController.MenuControllerBackground_8_6'
    bgTiles10(0)=Texture'DXController.MenuControllerBackground_10_1'
    bgTiles10(1)=Texture'DXController.MenuControllerBackground_10_2'
    bgTiles10(2)=Texture'DXController.MenuControllerBackground_10_3'
    bgTiles10(3)=Texture'DXController.MenuControllerBackground_10_4'
    bgTiles10(4)=Texture'DXController.MenuControllerBackground_10_5'
    bgTiles10(5)=Texture'DXController.MenuControllerBackground_10_6'
    textureRows=2
    textureCols=3
    helpPosY=438
}
