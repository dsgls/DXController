#include "AxisMapParse.h"

#include <cmath>
#include <cstdlib>
#include <cwchar>
#include <string.h>

namespace AxisMapParse
{

namespace
{
    const wchar_t* const kszPrefix = L"Gamepad: [DXController.GamepadAxisMap] ";
}

bool ParseSourceName(const wchar_t* const pszName, ESource* const peOutSource, int* const piOutJoyAxis)
{
    struct SourceName
    {
        const wchar_t* pszName;
        ESource        eSource;
    };
    static const SourceName kNames[] =
    {
        { L"gyro.pitch",  ESource::GyroPitch },
        { L"gyro.yaw",    ESource::GyroYaw   },
        { L"gyro.roll",   ESource::GyroRoll  },
        { L"accel.x",     ESource::AccelX    },
        { L"accel.y",     ESource::AccelY    },
        { L"accel.z",     ESource::AccelZ    },
        { L"touchpad.x",  ESource::TouchpadX },
        { L"touchpad.y",  ESource::TouchpadY },
    };
    if (!pszName)
    {
        return false;
    }
    for (const SourceName& Name : kNames)
    {
        if (_wcsicmp(pszName, Name.pszName) == 0)
        {
            *peOutSource  = Name.eSource;
            *piOutJoyAxis = 0;
            return true;
        }
    }

    static const wchar_t* const pszJoyAxisPrefix = L"joyaxis.";
    const size_t iPrefixLen = wcslen(pszJoyAxisPrefix);
    if (_wcsnicmp(pszName, pszJoyAxisPrefix, iPrefixLen) == 0)
    {
        const wchar_t* const pszIndex = pszName + iPrefixLen;
        wchar_t* pEnd = nullptr;
        const long iIndex = wcstol(pszIndex, &pEnd, 10);
        //Upper bound is a sanity limit, not an SDL one; the real axis count is
        //checked against the live joystick at read time.
        if (pEnd != pszIndex && pEnd && *pEnd == L'\0' && iIndex >= 0 && iIndex < 64)
        {
            *peOutSource  = ESource::JoyAxis;
            *piOutJoyAxis = static_cast<int>(iIndex);
            return true;
        }
    }
    return false;
}

bool IsSensorSource(const ESource eSource)
{
    switch (eSource)
    {
    case ESource::GyroPitch:
    case ESource::GyroYaw:
    case ESource::GyroRoll:
    case ESource::AccelX:
    case ESource::AccelY:
    case ESource::AccelZ:
        return true;
    default:
        return false;
    }
}

bool ParseFloatToken(const wchar_t* const pszToken, float* const pfOut)
{
    wchar_t* pEnd = nullptr;
    const double dValue = wcstod(pszToken, &pEnd);
    if (pEnd == pszToken || !pEnd || *pEnd != L'\0')
    {
        return false;
    }
    *pfOut = static_cast<float>(dValue);
    return true;
}

StickResponse::ECurveType ParseCurveType(const wchar_t* const pszToken,
                                         const StickResponse::ECurveType eDefault)
{
    if (!pszToken)
    {
        return eDefault;
    }
    if (_wcsicmp(pszToken, L"Linear")  == 0) return StickResponse::ECurveType::Linear;
    if (_wcsicmp(pszToken, L"Power")   == 0) return StickResponse::ECurveType::Power;
    if (_wcsicmp(pszToken, L"Expo")    == 0) return StickResponse::ECurveType::Expo;
    if (_wcsicmp(pszToken, L"Sigmoid") == 0) return StickResponse::ECurveType::Sigmoid;
    return eDefault;
}

const wchar_t* CurveTypeToString(const StickResponse::ECurveType eType)
{
    switch (eType)
    {
    case StickResponse::ECurveType::Linear:  return L"Linear";
    case StickResponse::ECurveType::Power:   return L"Power";
    case StickResponse::ECurveType::Expo:    return L"Expo";
    case StickResponse::ECurveType::Sigmoid: return L"Sigmoid";
    }
    return L"Linear";
}

SValue ParseValue(const wchar_t* const pszSourceName, const wchar_t* const pszValue,
                  const int iNoneKey, const FParseKey& ParseKey)
{
    SValue Result;
    const std::wstring SourceName = pszSourceName ? pszSourceName : L"";

    //wcstok_s writes into its input, so work on a copy.
    wchar_t szValue[256];
    wcsncpy_s(szValue, pszValue ? pszValue : L"", _TRUNCATE);
    wchar_t*       pContext = nullptr;
    const wchar_t* pszSlot  = wcstok_s(szValue, L" \t", &pContext);

    int iKey = iNoneKey;
    if (!ParseKey(pszSlot, &iKey))
    {
        Result.Log.push_back(kszPrefix + SourceName + L"=" + (pszValue ? pszValue : L"") +
                             L" does not name a known key -- ignored.");
        return Result;
    }
    Result.iKey     = iKey;
    Result.bAccepted = true;
    if (iKey == iNoneKey)
    {
        return Result; //"None" or an empty value: the line is deliberately inert
    }

    for (const wchar_t* pszToken = wcstok_s(nullptr, L" \t", &pContext);
         pszToken != nullptr;
         pszToken = wcstok_s(nullptr, L" \t", &pContext))
    {
        float* pfTarget = nullptr;
        const wchar_t* pszNumber = nullptr;
        if (_wcsnicmp(pszToken, L"Scale=", 6) == 0)
        {
            pfTarget  = &Result.fScale;
            pszNumber = pszToken + 6;
        }
        else if (_wcsnicmp(pszToken, L"Deadzone=", 9) == 0)
        {
            pfTarget  = &Result.fDeadzone;
            pszNumber = pszToken + 9;
        }
        else
        {
            Result.Log.push_back(kszPrefix + SourceName + L": unknown parameter '" + pszToken + L"' -- ignored.");
            continue;
        }

        float fParsed = 0.0f;
        if (!ParseFloatToken(pszNumber, &fParsed) || (pfTarget == &Result.fDeadzone && fParsed < 0.0f))
        {
            Result.Log.push_back(kszPrefix + SourceName + L": bad parameter '" + pszToken + L"' -- default kept.");
            continue;
        }
        //NaN/Inf pass every range test above and would peg the axis (a NaN
        //comparison is false, so the clamp in EmitAxisMap leaves -1000).
        //Dropping the line is the safe reading of a value that has no sane
        //substitute.
        if (!std::isfinite(fParsed))
        {
            Result.Log.push_back(kszPrefix + SourceName + L": parameter '" + pszToken +
                                 L"' is not a finite number -- line ignored.");
            Result.bAccepted = false;
            return Result;
        }
        *pfTarget = fParsed;
    }

    return Result;
}

EDestStatus CheckDestination(const int iKey,
                             const std::function<bool(const int)>& IsReservedDest,
                             const std::vector<int>& ButtonKeys,
                             const std::vector<int>& AcceptedAxisKeys)
{
    if (IsReservedDest(iKey))
    {
        return EDestStatus::Reserved;
    }
    for (const int iButtonKey : ButtonKeys)
    {
        if (iButtonKey == iKey)
        {
            return EDestStatus::Taken;
        }
    }
    for (const int iAxisKey : AcceptedAxisKeys)
    {
        if (iAxisKey == iKey)
        {
            return EDestStatus::Taken;
        }
    }
    return EDestStatus::Free;
}

}
