//=============================================================================
// MenuChoice_AutoSaveInterval -- binds the int row to IntervalSeconds.
//=============================================================================
class MenuChoice_AutoSaveInterval extends MenuChoice_AutoSaveInt;

function int GetSettingValue()      { return Class'AutoSaveManager'.Default.IntervalSeconds; }
function     SetSettingValue(int v) { Class'AutoSaveManager'.Default.IntervalSeconds = v; }

defaultproperties
{
    minVal=15
    maxVal=600
    fineStep=15
    coarseStep=60
    suffix="s"
    actionText="Autosave interval"
    helpText="Seconds of play between autosaves. Counts play time only, not paused or menu time. Range 15-600.  *  LB/RB to adjust faster"
}
