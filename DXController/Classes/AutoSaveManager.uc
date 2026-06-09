//=============================================================================
// AutoSaveManager — periodic rotating autosave (DXController feature).
//
// Owned and driven by ControllerRootWindow: created in InitWindow via
// New(None), polled once per frame from ControllerRootWindow.Tick (as
// autoSave.Poll). It reads the player's saveTime play-clock to measure the
// interval (so paused/menu time is excluded for free), applies QuickSave's
// guards plus conversation/menu deferral, and keeps a rotating pool of the
// most-recent MaxSaves autosaves identified by an "Auto Save -" description
// prefix.
//
// Config section: [DXController.AutoSaveManager] in DeusEx.ini.
// No DeusEx-overlay or launcher changes.
//=============================================================================
class AutoSaveManager extends Object
    config(DeusEx);

// --- User config (read via Default, then clamped) ---
var config bool bEnabled;
var config int  IntervalSeconds;
var config int  MaxSaves;

// --- Localized strings (defaultproperties supply the fallback when no
//     .int language file defines them) ---
var localized string AutoSaveTitle;    // "Auto Save"  -> save-description prefix
var localized string AutoSavingLabel;  // "Auto Saving..." -> toast text

// --- Runtime state ---
var ControllerRootWindow root;
var DeusExPlayer cachedPlayer;
var float lastSaveAtPlayTime;
var float toastRemaining;
var int   intervalClamped;
var int   maxSavesClamped;

// --- Scratch arrays for the rotation scan. Date/time are packed into ints
//     for exact ordering (a float key loses second-precision at year-scale
//     magnitudes). The [128] dimension must match SCAN_MAX below. ---
var int scanDate[128];   // (Year*100 + Month)*100 + Day
var int scanTime[128];   // (Hour*100 + Minute)*100 + Second
var int scanIndex[128];  // DeusExSaveInfo.DirectoryIndex

const TOAST_SECONDS = 2.0;
const SCAN_MAX      = 128;
const SCAN_CONSUMED = 2000000000;   // sentinel: scan entry already deleted

function Init(ControllerRootWindow inRoot)
{
    root = inRoot;

    intervalClamped = Default.IntervalSeconds;
    if (intervalClamped < 10)            // floor to avoid save-thrash
        intervalClamped = 10;

    maxSavesClamped = Default.MaxSaves;
    if (maxSavesClamped < 1)
        maxSavesClamped = 1;
    if (maxSavesClamped > 100)
        maxSavesClamped = 100;

    cachedPlayer = None;
    lastSaveAtPlayTime = 0.0;
    toastRemaining = 0.0;
}

// Called once per frame from ControllerRootWindow.Tick.
function Poll(float deltaTime)
{
    local DeusExPlayer p;

    // Toast countdown advances regardless of enable state.
    if (toastRemaining > 0.0)
        toastRemaining -= deltaTime;

    if (!Default.bEnabled)
        return;
    if (root == None)
        return;

    p = DeusExPlayer(root.parentPawn);
    if (p == None)
        return;

    // Re-baseline whenever the player object changes (new game, or arrival
    // on a new map after travel). Don't fire on that same tick.
    if (p != cachedPlayer)
    {
        cachedPlayer = p;
        lastSaveAtPlayTime = p.saveTime;
        return;
    }

    // Not due yet?
    if (p.saveTime - lastSaveAtPlayTime < float(intervalClamped))
        return;

    // Due. Defer (WITHOUT resetting the baseline) if a guard blocks, so the
    // save lands the instant normal play resumes.
    if (!CanAutoSaveNow(p))
        return;

    DoAutoSave(p);
    lastSaveAtPlayTime = p.saveTime;
    toastRemaining = TOAST_SECONDS;
}

// Mirrors QuickSave's guards (DeusExPlayer.uc:935-940) plus conversation and
// menu-foreground deferral. Single-player only, so no netmode check.
function bool CanAutoSaveNow(DeusExPlayer p)
{
    local DeusExLevelInfo info;

    info = p.GetLevelInfo();
    if (info == None)
        return false;
    if (info.MissionNumber < 0)                 // logo / intro map
        return false;
    if (p.IsInState('Dying') || p.IsInState('Paralyzed') || p.IsInState('Interpolating'))
        return false;
    if (p.dataLinkPlay != None)                 // datalink / infolink playing
        return false;
    if (p.conPlay != None)                      // conversation active
        return false;
    if (root.IsAnyUIForeground())               // pause menu / inventory / save screen
        return false;
    return true;
}

// Enumerate the autosave pool, delete the oldest down to (MaxSaves - 1) so
// the new save lands at exactly MaxSaves, then write the new autosave.
function DoAutoSave(DeusExPlayer p)
{
    local GameDirectory saveDir;
    local DeusExSaveInfo si;
    local DeusExLevelInfo info;
    local string desc, prefix, mapName;
    local int i, dirCount, poolCount, toDelete, k, oldest;

    // Description: "Auto Save - <map name>".
    info = p.GetLevelInfo();
    mapName = "";
    if (info != None)
        mapName = info.MapName;
    if (mapName == "")
        mapName = p.GetURLMap();
    desc   = AutoSaveTitle $ " - " $ mapName;
    prefix = AutoSaveTitle $ " -";

    // Enumerate existing pool members into the scratch arrays.
    saveDir = p.CreateGameDirectoryObject();
    poolCount = 0;
    if (saveDir != None)
    {
        saveDir.SetDirType(saveDir.EGameDirectoryTypes.GD_SaveGames);
        saveDir.GetGameDirectory();
        dirCount = saveDir.GetDirCount();
        for (i = 0; i < dirCount && poolCount < SCAN_MAX; i++)
        {
            si = saveDir.GetSaveInfoFromDirectoryIndex(i);
            if (si == None)
                continue;
            if (Left(si.Description, Len(prefix)) ~= prefix)
            {
                scanDate[poolCount]  = (si.Year * 100 + si.Month) * 100 + si.Day;
                scanTime[poolCount]  = (si.Hour * 100 + si.Minute) * 100 + si.Second;
                scanIndex[poolCount] = si.DirectoryIndex;
                poolCount++;
            }
            // Free each temp save-info (stock frees it per entry in its own
            // enumeration loop — MenuScreenLoadGame.PopulateGames).
            saveDir.DeleteSaveInfo(si);
        }
    }

    // Delete oldest members until there is room for one more. toDelete is
    // negative (loop no-ops) when under capacity, and >1 when the user just
    // lowered MaxSaves (trims the surplus oldest-first).
    toDelete = poolCount - maxSavesClamped + 1;
    for (k = 0; k < toDelete; k++)
    {
        oldest = FindOldest(poolCount);
        if (oldest < 0)
            break;
        p.ConsoleCommand("DeleteGame " $ string(scanIndex[oldest]));
        scanDate[oldest] = SCAN_CONSUMED;   // don't pick it again
    }

    // Write the new autosave; index 0 => native allocates a fresh slot
    // (same path as the Save screen's "new save" row).
    p.SaveGame(0, desc);
}

// Index of the oldest not-yet-consumed scan entry, or -1 if none.
function int FindOldest(int poolCount)
{
    local int i, best;

    best = -1;
    for (i = 0; i < poolCount; i++)
    {
        if (scanDate[i] == SCAN_CONSUMED)
            continue;
        if (best < 0
            || scanDate[i] < scanDate[best]
            || (scanDate[i] == scanDate[best] && scanTime[i] < scanTime[best]))
            best = i;
    }
    return best;
}

function bool ShouldShowToast()
{
    return toastRemaining > 0.0;
}

defaultproperties
{
    bEnabled=True
    IntervalSeconds=60
    MaxSaves=40
    AutoSaveTitle="Auto Save"
    AutoSavingLabel="Auto Saving..."
}
