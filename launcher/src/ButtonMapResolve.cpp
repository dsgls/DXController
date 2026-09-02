#include "ButtonMapResolve.h"

namespace ButtonMapResolve
{

SResult Resolve(const SParams& Params)
{
    const int iButtonCount = static_cast<int>(Params.Defaults.size());

    SResult Result;

    //Candidate map = defaults with overrides substituted. A button named in
    //the ini has thereby abandoned its default slot -- this is what makes a
    //two-line slot swap (e.g. y=Joy16 + touchpad=Joy4) valid: by the time
    //either line is validated below, both defaults have already moved.
    std::vector<int> Candidate(static_cast<size_t>(iButtonCount));
    for (int i = 0; i < iButtonCount; ++i)
    {
        Candidate[i] = Params.HasOverride[i] ? Params.OverrideKey[i] : Params.Defaults[i];
    }

    //Validate the candidate map. A losing override falls back to its own
    //compiled default; if that default now collides too, it falls back to
    //iNoneKey instead (both logged). UsedFallback marks a button that has
    //already spent its one fallback, so a second collision goes straight to
    //None rather than retrying (and re-logging) the same default forever.
    //Runs in passes because reverting one button to its default can create a
    //fresh collision with a still-standing override that was targeting that
    //same default (a chain at most two deep per button, hence the bound).
    std::vector<bool> UsedFallback(static_cast<size_t>(iButtonCount), false);
    for (int iPass = 0; iPass <= iButtonCount; ++iPass)
    {
        //Destination -> claimant button indices, excluding iNoneKey. A
        //destination outside the key space cannot be emitted on, so it is
        //left alone rather than indexed.
        std::vector<std::vector<int>> Claimants(static_cast<size_t>(Params.iKeyCount));
        for (int i = 0; i < iButtonCount; ++i)
        {
            const int iKey = Candidate[i];
            if (iKey != Params.iNoneKey && iKey >= 0 && iKey < Params.iKeyCount)
            {
                Claimants[static_cast<size_t>(iKey)].push_back(i);
            }
        }

        bool bChanged = false;
        for (int iDest = 0; iDest < Params.iKeyCount; ++iDest)
        {
            const std::vector<int>& Group = Claimants[static_cast<size_t>(iDest)];
            if (Group.empty())
            {
                continue;
            }
            const bool bReserved = Params.IsReservedDest(iDest);
            if (!bReserved && Group.size() <= 1)
            {
                continue; //uncontested
            }

            //Winner priority: an untouched default holder always wins (it was
            //never named in the ini, so there's no "later line" that could
            //displace it); otherwise the earliest-line override wins. A
            //fixed-axis-pipeline slot (bReserved) has no winner at all --
            //every real claimant there loses.
            int iWinner = -1;
            if (!bReserved)
            {
                for (const int j : Group)
                {
                    if (!Params.HasOverride[j])
                    {
                        iWinner = j;
                        break;
                    }
                }
                if (iWinner < 0)
                {
                    for (const int j : Group)
                    {
                        if (iWinner < 0 || Params.OverrideLine[j] < Params.OverrideLine[iWinner])
                        {
                            iWinner = j;
                        }
                    }
                }
            }

            for (const int j : Group)
            {
                if (j == iWinner)
                {
                    continue;
                }
                const std::wstring ButtonName = Params.ButtonName(j);
                if (!UsedFallback[j])
                {
                    Result.Log.push_back(
                        L"Gamepad: [DXController.GamepadButtonMap] " + ButtonName +
                        (bReserved
                            ? L" targets a slot the axis pipeline already emits on -- reverted to its default."
                            : L"'s override duplicates another button's destination -- reverted to its default."));
                    Candidate[j]    = Params.Defaults[j];
                    UsedFallback[j] = true;
                }
                else
                {
                    Result.Log.push_back(
                        L"Gamepad: [DXController.GamepadButtonMap] " + ButtonName +
                        L"'s default also collides -- left unmapped.");
                    Candidate[j] = Params.iNoneKey;
                }
                bChanged = true;
            }
        }

        if (!bChanged)
        {
            break;
        }
    }

    Result.Keys = std::move(Candidate);
    return Result;
}

}
