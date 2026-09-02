#pragma once

#include <functional>
#include <string>
#include <vector>

#include "StickResponse.h"

// Pure parsing for [DXController.GamepadAxisMap] (and the curve-type tokens
// [DXController.ControllerSettings] shares with it). The GConfig section walk
// and the engine's key-name table stay in the Gamepad shim; the one engine
// dependency here, resolving a slot name to an EInputKey, is injected as a
// callback so the parser needs neither the engine nor SDL.
namespace AxisMapParse
{
    //Source kinds a [DXController.GamepadAxisMap] line can name (spec sec5).
    //Natural units: gyro rad/s, accel m/s^2, touchpad and joyaxis -1..1.
    enum class ESource
    {
        GyroPitch, GyroYaw, GyroRoll,
        AccelX, AccelY, AccelZ,
        TouchpadX, TouchpadY,
        JoyAxis
    };

    //Parses an axis-map key into a source kind: "gyro.pitch|yaw|roll",
    //"accel.x|y|z", "touchpad.x|y", or "joyaxis.N" for a raw joystick axis
    //index. Case-insensitive. *piOutJoyAxis is only meaningful for the joyaxis
    //form. Returns false for anything else.
    bool ParseSourceName(const wchar_t* const pszName, ESource* const peOutSource, int* const piOutJoyAxis);

    //True for the sensor-derived sources, which never count as pad activity
    //(spec sec6).
    bool IsSensorSource(const ESource eSource);

    //Strict float parse: the whole token must be consumed, so "1e" or "12x"
    //is rejected rather than silently read as a prefix.
    bool ParseFloatToken(const wchar_t* const pszToken, float* const pfOut);

    //Case-insensitive parse of a curve-type ini token. Returns eDefault when
    //pszToken is null or matches none of the four expected tokens.
    StickResponse::ECurveType ParseCurveType(const wchar_t* const pszToken,
                                             const StickResponse::ECurveType eDefault);

    //Inverse of ParseCurveType, for writing the ini back. Total: an enum value
    //without a token maps to L"Linear".
    const wchar_t* CurveTypeToString(const StickResponse::ECurveType eType);

    //Resolves a slot name to a key in the caller's key space. Returns false if
    //the name resolves to nothing.
    using FParseKey = std::function<bool(const wchar_t* const pszName, int* const piOutKey)>;

    struct SValue
    {
        //False when the line is rejected outright; Log says why. A line
        //accepted with iKey == the caller's "none" key is deliberately inert.
        bool  bAccepted = false;
        int   iKey      = 0;
        float fScale    = 1000.0f; //suits the -1..1 sources; gyro/accel need an explicit one
        float fDeadzone = 0.0f;

        //Messages the caller forwards to GLog verbatim, in emission order.
        //Present on accepted lines too: an unknown or unparseable parameter is
        //logged and skipped without losing the line.
        std::vector<std::wstring> Log;
    };

    //Parses an axis-map value: "<SlotName> [Scale=<f>] [Deadzone=<f>]",
    //whitespace separated. A negative Deadzone or an unparseable number keeps
    //the default for that parameter; a non-finite one drops the whole line,
    //having no sane substitute. pszSourceName is only used to spell the log
    //messages.
    SValue ParseValue(const wchar_t* const pszSourceName, const wchar_t* const pszValue,
                      const int iNoneKey, const FParseKey& ParseKey);

    //Why a destination is unavailable, in the precedence the log messages
    //assume: the fixed stick/trigger slots first, then anything the resolved
    //button map or an earlier accepted axis entry already claims.
    enum class EDestStatus { Free, Reserved, Taken };

    EDestStatus CheckDestination(const int iKey,
                                 const std::function<bool(const int)>& IsReservedDest,
                                 const std::vector<int>& ButtonKeys,
                                 const std::vector<int>& AcceptedAxisKeys);
}
