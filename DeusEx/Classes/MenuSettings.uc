//=============================================================================
// MenuSettings
//=============================================================================

class MenuSettings expands MenuUIMenuWindow;

// ----------------------------------------------------------------------
// InitWindow
//
// Two MenuSettings-side fixes layered on the stock screen:
//
// 1. `ButtonNames` is `var localized` -- DeusEx.int's [MenuSettings] section
//    still has the stock 7-button layout (slot 6 = "Previous Menu"), which
//    silently overrides our defaultproperties at load. Re-write the entries
//    we changed before Super.InitWindow runs CreateMenuButtons.
//
// 2. The Class'DXController.MenuScreenController' literal in defaultproperties
//    can resolve to None at runtime if DXController.u hasn't been demand-loaded
//    by the time DeusEx.u parses these defaults. DynamicLoadObject forces the
//    package load and gives us a guaranteed-valid class ref to write into
//    buttonDefaults[6].invoke.
// ----------------------------------------------------------------------

event InitWindow()
{
    local Class controllerScreenClass;

    ButtonNames[6] = "Controller";
    ButtonNames[7] = "Previous Menu";

    controllerScreenClass = Class(DynamicLoadObject("DXController.MenuScreenController", Class'Class', True));
    if (controllerScreenClass != None)
        buttonDefaults[6].invoke = controllerScreenClass;

    Super.InitWindow();
}

// ----------------------------------------------------------------------
// ----------------------------------------------------------------------

defaultproperties
{
     ButtonNames(0)="Keyboard/Mouse"
     ButtonNames(1)="Controls"
     ButtonNames(2)="Game Options"
     ButtonNames(3)="Display"
     ButtonNames(4)="Colors"
     ButtonNames(5)="Sound"
     ButtonNames(6)="Controller"
     ButtonNames(7)="Previous Menu"
     buttonXPos=7
     buttonWidth=282
     buttonDefaults(0)=(Y=13,Action=MA_MenuScreen,Invoke=Class'DeusEx.MenuScreenCustomizeKeys')
     buttonDefaults(1)=(Y=49,Action=MA_MenuScreen,Invoke=Class'DeusEx.MenuScreenControls')
     buttonDefaults(2)=(Y=85,Action=MA_MenuScreen,Invoke=Class'DeusEx.MenuScreenOptions')
     buttonDefaults(3)=(Y=121,Action=MA_MenuScreen,Invoke=Class'DeusEx.MenuScreenDisplay')
     buttonDefaults(4)=(Y=157,Action=MA_MenuScreen,Invoke=Class'DeusEx.MenuScreenAdjustColors')
     buttonDefaults(5)=(Y=193,Action=MA_MenuScreen,Invoke=Class'DeusEx.MenuScreenSound')
     buttonDefaults(6)=(Y=229,Action=MA_MenuScreen)
     buttonDefaults(7)=(Y=265,Action=MA_Previous)
     Title="Settings"
     ClientWidth=294
     ClientHeight=308
     clientTextures(0)=Texture'DeusExUI.UserInterface.MenuOptionsBackground_1'
     clientTextures(1)=Texture'DeusExUI.UserInterface.MenuOptionsBackground_2'
     clientTextures(2)=Texture'DeusExUI.UserInterface.MenuOptionsBackground_3'
     clientTextures(3)=Texture'DeusExUI.UserInterface.MenuOptionsBackground_4'
     textureCols=2
}
