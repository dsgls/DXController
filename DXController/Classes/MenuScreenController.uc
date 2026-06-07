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
// toggling is handled by RepackLayout. Stock CreateChoices iterates the
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
    clientTextures(0)=Texture'DXController.MenuBg_1'
    clientTextures(1)=Texture'DXController.MenuBg_2'
    clientTextures(2)=Texture'DXController.MenuBg_3'
    clientTextures(3)=Texture'DXController.MenuBg_4'
    clientTextures(4)=Texture'DXController.MenuBg_5'
    clientTextures(5)=Texture'DXController.MenuBg_6'
    textureRows=2
    textureCols=3
    helpPosY=438
}
