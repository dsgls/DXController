//=============================================================================
// MenuScreenController — the Settings → Controller page.
//
// Hosts up to 15 MenuUIChoice rows on the left (one Apply action, plus
// 7 per stick: deadzone, curve type, and 5 curve-param rows of which
// only the active curve's are shown) and two ControllerCurvePreview
// windows on the right (one per stick, stacked vertically).
//
// All rows are spawned at InitWindow regardless of curve type; visibility
// toggling is handled by RepackLayout. Stock CreateChoices iterates the
// 13-slot choices[] array, which we exceed (15 rows), so we override
// CreateChoices and spawn directly via winClient.NewChild.
//=============================================================================
class MenuScreenController extends MenuUIScreenWindow;

// Apply action.
var MenuChoice_StickApplyRecommended btnApply;

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

// Confirm-dialog state shared between OnApplyRecommendedPressed and the
// BoxOptionSelected callback. mode 0 = "ask to apply" (Yes/No), mode 1 =
// "applied, single-button dismiss".
var int applyDialogMode;

function CreateChoices()
{
    btnApply       = MenuChoice_StickApplyRecommended(winClient.NewChild(Class'MenuChoice_StickApplyRecommended'));

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

    // Right-side curve previews. Stack vertically with a 14-px gap. Y for
    // vizRight is computed from the viz's known size (PLOT_SIZE+24 = 174)
    // rather than vizLeft.height; reading the var back after SetSize is
    // unreliable across UE1 windowing paths and gave us overlapping vizs.
    vizLeft  = ControllerCurvePreview(winClient.NewChild(Class'ControllerCurvePreview'));
    vizLeft.stickIdx  = 0;
    vizLeft.lblPrefix = "Left stick — ";
    vizLeft.SetPos(540, 8);

    vizRight = ControllerCurvePreview(winClient.NewChild(Class'ControllerCurvePreview'));
    vizRight.stickIdx  = 1;
    vizRight.lblPrefix = "Right stick — ";
    vizRight.SetPos(540, 8 + 174 + 14);

    // Re-Refresh after both previews exist and parent linkage is final, so
    // GetPlayerPawn() definitely resolves and the launcher command runs.
    vizLeft.Refresh();
    vizRight.Refresh();

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
    n = PlaceRow(btnApply,      n);

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

// Entry point invoked by the Apply Recommended row. Pops a Yes/No
// confirm dialog; the actual ini write is deferred to ApplyRecommended()
// from BoxOptionSelected so the user can back out.
function OnApplyRecommendedPressed()
{
    local DeusExRootWindow root;

    root = DeusExRootWindow(GetRootWindow());
    applyDialogMode = 0;
    root.MessageBox(
        "Apply recommended controller config?",
        "This will apply the recommended controller .ini settings:" $ Chr(13) $ Chr(13) $
        "  - bToggleCrouch = True" $ Chr(13) $
        "  - UseDirectInput = False" $ Chr(13) $
        "  - UseJoystick = False" $ Chr(13) $
        "  - [Extension.InputExt] Joy* bindings (replaces existing)" $ Chr(13) $ Chr(13) $
        "The Joy* bindings change is destructive -- your current gamepad" $ Chr(13) $
        "button bindings will be overwritten with the defaults." $ Chr(13) $ Chr(13) $
        "UseDirectInput / UseJoystick take effect on next launch.",
        0,                  // MB_YesNo per MenuUIMessageBoxWindow.SetMode
        False,              // hideCurrentScreen
        Self);              // notifyWindow -> BoxOptionSelected
}

// MessageBox callback. Stock signature from DeusExRootWindow:510. For the
// Yes/No confirm, buttonNumber 0 = Yes (Apply), 1 = No (Cancel). For the
// follow-up MB_OK acknowledgement (mode==1 here), the single OK posts
// buttonNumber 0 and just dismisses.
event bool BoxOptionSelected(Window button, int buttonNumber)
{
    local DeusExRootWindow root;

    root = DeusExRootWindow(GetRootWindow());

    if (applyDialogMode == 0)
    {
        root.PopWindow();
        if (buttonNumber == 0)
        {
            ApplyRecommended();
            applyDialogMode = 1;
            root.MessageBox(
                "Applied",
                "Restart the game for UseDirectInput / UseJoystick to take effect.",
                1,                  // MB_OK per MenuUIMessageBoxWindow.SetMode
                False,
                Self);
        }
        return True;
    }

    if (applyDialogMode == 1)
    {
        root.PopWindow();
        return True;
    }

    return False;
}

// Three-step recommended-config write. Each block is independent so a
// partial failure (e.g. p == None) just skips that block.
//
// 1) bToggleCrouch: live + persists via player config.
// 2) WinDrv keys: ini-only (effective next launch). Stock precedent for
//    `set ini:` is Engine/Classes/PlayerPawn.uc:361.
// 3) Bindings: live via `set InputExt`. The `set ini:Extension.InputExt`
//    follow-up forces persistence even if the runtime path doesn't write
//    through (stock CustomizeKeys relies on the runtime write alone, but
//    belt-and-braces is cheap here).
function ApplyRecommended()
{
    local DeusExPlayer p;
    local int i;
    local string key, alias;

    p = DeusExPlayer(GetPlayerPawn());
    if (p == None) return;

    p.bToggleCrouch = True;
    p.SaveConfig();

    p.ConsoleCommand("set ini:WinDrv.WindowsClient UseDirectInput False");
    p.ConsoleCommand("set ini:WinDrv.WindowsClient UseJoystick False");
    p.ConsoleCommand("flush");

    for (i = 0; i < 20; i++)
    {
        key = Class'ControllerRecommendedBindings'.Default.keys[i];
        if (key == "") break;
        alias = Class'ControllerRecommendedBindings'.Default.aliases[i];
        p.ConsoleCommand("set InputExt " $ key $ " " $ alias);
        p.ConsoleCommand("set ini:Extension.InputExt " $ key $ " " $ alias);
    }
    p.ConsoleCommand("flush");
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
    clientTextures(0)=Texture'DeusExUI.UserInterface.MenuGameOptionsBackground_1'
    clientTextures(1)=Texture'DeusExUI.UserInterface.MenuGameOptionsBackground_2'
    clientTextures(2)=Texture'DeusExUI.UserInterface.MenuGameOptionsBackground_3'
    clientTextures(3)=Texture'DeusExUI.UserInterface.MenuGameOptionsBackground_4'
    clientTextures(4)=Texture'DeusExUI.UserInterface.MenuGameOptionsBackground_5'
    clientTextures(5)=Texture'DeusExUI.UserInterface.MenuGameOptionsBackground_6'
    textureRows=2
    textureCols=3
    helpPosY=438
}
