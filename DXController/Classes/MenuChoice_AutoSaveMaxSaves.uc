//=============================================================================
// MenuChoice_AutoSaveMaxSaves -- binds the int row to MaxSaves.
//=============================================================================
class MenuChoice_AutoSaveMaxSaves extends MenuChoice_AutoSaveInt;

function int GetSettingValue()      { return Class'AutoSaveManager'.Default.MaxSaves; }
function     SetSettingValue(int v) { Class'AutoSaveManager'.Default.MaxSaves = v; }

defaultproperties
{
    minVal=1
    maxVal=100
    fineStep=1
    coarseStep=10
    suffix=""
    actionText="Autosaves to keep"
    helpText="How many autosaves to keep. The oldest is discarded when a new one is made. Range 1-100.  *  LB/RB to adjust faster"
}
