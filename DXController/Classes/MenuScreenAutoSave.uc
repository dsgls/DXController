//=============================================================================
// MenuScreenAutoSave -- the Settings -> Autosave page.
//
// A narrow standard-choices options screen with three rows (enable toggle,
// interval, max-saves) bound to AutoSaveManager's config. Navigated by
// OptionsNavController like the other options screens. Background is the
// generated MenuAutoSaveBackground_1..2 tile set (assets/gen-menu-bg.py);
// ClientWidth/Height/helpPosY here MUST match that generator page spec.
//
// VirtualKeyPressed forwards LB/RB to the focused int row's coarse step
// (OptionsNavController routes only D-pad + A); the enable toggle is not a
// MenuChoice_AutoSaveInt, so LB/RB fall through to Super for it.
//=============================================================================
class MenuScreenAutoSave extends MenuUIScreenWindow;

event bool VirtualKeyPressed(EInputKey key, bool bRepeat)
{
    local MenuChoice_AutoSaveInt fp;

    if (currentChoice == None)
        return Super.VirtualKeyPressed(key, bRepeat);

    fp = MenuChoice_AutoSaveInt(currentChoice);

    if (key == IK_Joy5)         // LB = coarse step down
    {
        if (fp != None) { fp.CycleCoarsePrev(); return True; }
        return Super.VirtualKeyPressed(key, bRepeat);
    }
    if (key == IK_Joy6)         // RB = coarse step up
    {
        if (fp != None) { fp.CycleCoarseNext(); return True; }
        return Super.VirtualKeyPressed(key, bRepeat);
    }

    return Super.VirtualKeyPressed(key, bRepeat);
}

defaultproperties
{
    Title="Autosave"
    ClientWidth=400
    ClientHeight=200
    helpPosY=160
    actionButtons(0)=(Align=HALIGN_Right,Action=AB_OK)
    choices(0)=Class'DXController.MenuChoice_AutoSaveEnabled'
    choices(1)=Class'DXController.MenuChoice_AutoSaveInterval'
    choices(2)=Class'DXController.MenuChoice_AutoSaveMaxSaves'
    clientTextures(0)=Texture'DXController.MenuAutoSaveBackground_1'
    clientTextures(1)=Texture'DXController.MenuAutoSaveBackground_2'
    textureRows=1
    textureCols=2
}
