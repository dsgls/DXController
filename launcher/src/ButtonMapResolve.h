#pragma once

#include <functional>
#include <string>
#include <vector>

// Pure resolution of [DXController.GamepadButtonMap]: the compiled-in default
// button map layered under the ini overrides, with every destination conflict
// settled. The GConfig reading and the SDL button-name vocabulary stay in the
// Gamepad shim - this unit works over a plain int key space and a name
// callback, so it needs neither the engine nor SDL.
namespace ButtonMapResolve
{
    struct SParams
    {
        //The engine's EInputKey range. Destinations outside [0, iKeyCount) are
        //ignored; iNoneKey means "unmapped" and never conflicts.
        int iKeyCount = 0;
        int iNoneKey  = 0;

        //One entry per button, all four the same length. OverrideLine is the
        //winning ini line's position in file order, -1 where there is no
        //override; it breaks ties between two overrides claiming one slot.
        std::vector<int>  Defaults;
        std::vector<bool> HasOverride;
        std::vector<int>  OverrideKey;
        std::vector<int>  OverrideLine;

        //True for destinations the fixed stick/trigger pipeline already emits
        //on. Such a slot has no winner at all: every claimant loses it.
        std::function<bool(int)> IsReservedDest;

        //Button name for the log messages, e.g. "leftshoulder".
        std::function<std::wstring(int)> ButtonName;
    };

    struct SResult
    {
        //Resolved destination per button, iNoneKey where unmapped.
        std::vector<int> Keys;
        //Messages the caller forwards to GLog verbatim, in emission order.
        std::vector<std::wstring> Log;
    };

    //Rules, all load-bearing: defaults layered under overrides (so a two-line
    //slot swap is legal - both defaults have moved before either line is
    //validated); an untouched default beats an override; among overrides the
    //earliest line wins; a losing button falls back to its own default once,
    //then to iNoneKey; iterated to a fixpoint because reverting one button can
    //collide afresh with a still-standing override.
    SResult Resolve(const SParams& Params);
}
