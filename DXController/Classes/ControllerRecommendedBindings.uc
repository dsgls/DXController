//=============================================================================
// ControllerRecommendedBindings — keys/aliases that the Apply Recommended
// action writes into [Extension.InputExt] via `set InputExt`. Mirrors
// the block in README.md verbatim; if you change one, change both.
//
// Empty alias means "unbind" (the `set InputExt JoyN` form with no value
// clears the binding — same pattern as MenuScreenCustomizeKeys.uc Clear).
//=============================================================================
class ControllerRecommendedBindings extends Object
    abstract;

var string keys[20];
var string aliases[20];

defaultproperties
{
    keys(0)="Joy1"          aliases(0)="Jump"
    keys(1)="Joy2"          aliases(1)="ReloadWeapon"
    keys(2)="Joy3"          aliases(2)="ParseRightClick"
    keys(3)="Joy4"          aliases(3)=""
    keys(4)="Joy5"          aliases(4)=""
    keys(5)="Joy6"          aliases(5)=""
    keys(6)="Joy7"          aliases(6)="TogglePlayerMenuWindow"
    keys(7)="Joy8"          aliases(7)="ShowMainMenu"
    keys(8)="Joy9"          aliases(8)=""
    keys(9)="Joy10"         aliases(9)=""
    keys(10)="Joy15"        aliases(10)=""
    keys(11)="Joy16"        aliases(11)=""
    keys(12)="JoyPovUp"     aliases(12)="ActivateBelt 1"
    keys(13)="JoyPovLeft"   aliases(13)="ActivateBelt 2"
    keys(14)="JoyPovRight"  aliases(14)="ActivateBelt 3"
    keys(15)="JoyPovDown"   aliases(15)="ActivateBelt 4"
    keys(16)="JoyX"         aliases(16)="Axis aStrafe"
    keys(17)="JoyY"         aliases(17)="Axis aBaseY"
    keys(18)="JoyU"         aliases(18)="Axis aTurn"
    keys(19)="JoyV"         aliases(19)="Axis aLookUp"
}
