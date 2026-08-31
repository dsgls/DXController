#include "stdafx.h"
#include "Gamepad.h"

#include <SDL3/SDL.h>

namespace
{
    struct ButtonMapEntry
    {
        SDL_GamepadButton eButton;
        EInputKey         eKey;
    };

    //Compiled-in default button map. The snapshot mask uses one bit per entry
    //(bit i = kButtonMap[i]), so order is load-bearing only in that it must
    //stay stable within a run -- the engine slot is what users bind.
    //SDL_GAMEPAD_BUTTON_GUIDE and MISC2..6 are deliberately unmapped.
    constexpr ButtonMapEntry kButtonMap[] =
    {
        { SDL_GAMEPAD_BUTTON_SOUTH,          IK_Joy1        },
        { SDL_GAMEPAD_BUTTON_EAST,           IK_Joy2        },
        { SDL_GAMEPAD_BUTTON_WEST,           IK_Joy3        },
        { SDL_GAMEPAD_BUTTON_NORTH,          IK_Joy4        },
        { SDL_GAMEPAD_BUTTON_LEFT_SHOULDER,  IK_Joy5        },
        { SDL_GAMEPAD_BUTTON_RIGHT_SHOULDER, IK_Joy6        },
        { SDL_GAMEPAD_BUTTON_BACK,           IK_Joy7        },
        { SDL_GAMEPAD_BUTTON_START,          IK_Joy8        },
        { SDL_GAMEPAD_BUTTON_LEFT_STICK,     IK_Joy9        },
        { SDL_GAMEPAD_BUTTON_RIGHT_STICK,    IK_Joy10       },
        { SDL_GAMEPAD_BUTTON_RIGHT_PADDLE1,  IK_Joy11       },
        { SDL_GAMEPAD_BUTTON_LEFT_PADDLE1,   IK_Joy12       },
        { SDL_GAMEPAD_BUTTON_RIGHT_PADDLE2,  IK_Joy13       },
        { SDL_GAMEPAD_BUTTON_LEFT_PADDLE2,   IK_Joy14       },
        { SDL_GAMEPAD_BUTTON_MISC1,          IK_Joy15       },
        { SDL_GAMEPAD_BUTTON_TOUCHPAD,       IK_Joy16       },
        { SDL_GAMEPAD_BUTTON_DPAD_UP,        IK_JoyPovUp    },
        { SDL_GAMEPAD_BUTTON_DPAD_DOWN,      IK_JoyPovDown  },
        { SDL_GAMEPAD_BUTTON_DPAD_LEFT,      IK_JoyPovLeft  },
        { SDL_GAMEPAD_BUTTON_DPAD_RIGHT,     IK_JoyPovRight },
    };
    static_assert(ARRAY_COUNT(kButtonMap) <= 32, "button mask is a Uint32");

    //Stick deflection at which a non-active pad's AXIS_MOTION claims the active
    //slot: ~25%, deliberately coarser than the emission deadzones so a resting
    //stick on a second pad can't steal input. Triggers are excluded from the
    //switch signal entirely (see IsStickAxis): they rest at 0 and only rise,
    //some pads have a non-zero trigger floor, and SDL delivers initial
    //axis-state events right after SDL_OpenGamepad, so an idle or freshly
    //plugged-in pad would otherwise steal the slot.
    constexpr int kActiveSwitchAxisValue = 8000;

    //Case-insensitive parse of the curve-type INI token. Returns eDefault when
    //pszToken is null or doesn't match any of the four expected tokens.
    CGamepad::EStickCurveType ParseStickCurveType(const wchar_t* const pszToken,
                                                  const CGamepad::EStickCurveType eDefault)
    {
        if (!pszToken)
        {
            return eDefault;
        }
        if (_wcsicmp(pszToken, L"Linear")  == 0) return CGamepad::EStickCurveType::Linear;
        if (_wcsicmp(pszToken, L"Power")   == 0) return CGamepad::EStickCurveType::Power;
        if (_wcsicmp(pszToken, L"Expo")    == 0) return CGamepad::EStickCurveType::Expo;
        if (_wcsicmp(pszToken, L"Sigmoid") == 0) return CGamepad::EStickCurveType::Sigmoid;
        return eDefault;
    }

    //Inverse of ParseStickCurveType: maps the enum back to the canonical
    //token. Defaults to L"Linear" so the function is total even if the
    //enum is extended without updating this helper.
    const wchar_t* StickCurveTypeToString(const CGamepad::EStickCurveType eType)
    {
        switch (eType)
        {
        case CGamepad::EStickCurveType::Linear:  return L"Linear";
        case CGamepad::EStickCurveType::Power:   return L"Power";
        case CGamepad::EStickCurveType::Expo:    return L"Expo";
        case CGamepad::EStickCurveType::Sigmoid: return L"Sigmoid";
        }
        return L"Linear";
    }

    //Pure: shape a normalized magnitude u (>= 0) into a shaped magnitude.
    //Endpoints pinned: returns 0 at u <= 0, ~1 at u = 1. Linear short-circuits.
    //May return > 1 for u > 1 (diagonal overflow); caller clamps final axes.
    float ShapeStickMagnitude(const float fU, const CGamepad::SStickCurve& Curve)
    {
        if (fU <= 0.0f)
        {
            return 0.0f;
        }
        switch (Curve.eType)
        {
        case CGamepad::EStickCurveType::Power:
            return std::pow(fU, Curve.fPower);

        case CGamepad::EStickCurveType::Expo:
        {
            const float e = Curve.fExpo;
            return (1.0f - e) * fU + e * fU * fU * fU;
        }

        case CGamepad::EStickCurveType::Sigmoid:
        {
            const float k  = Curve.fSigSteepness;
            const float c  = Curve.fSigMidpoint;
            const float w  = Curve.fSigStrength;
            const float lo = 1.0f / (1.0f + std::exp(  k * c));
            const float hi = 1.0f / (1.0f + std::exp(-k * (1.0f - c)));
            const float s  = (1.0f / (1.0f + std::exp(-k * (fU - c))) - lo) / (hi - lo);
            return (1.0f - w) * fU + w * s;
        }

        case CGamepad::EStickCurveType::Linear:
        default:
            return fU;
        }
    }

    //SDL can report -32768, one past the positive end of the range. Clamp to
    //-32767 so both axes are symmetric and negation can't overflow.
    int ClampStickAxis(const int iRaw)
    {
        return (iRaw <= -32767) ? -32767 : iRaw;
    }

    //SDL Y axes are positive-down; the pipeline wants positive-up.
    int NegateStickY(const int iRaw)
    {
        return -ClampStickAxis(iRaw);
    }

    bool IsStickAxis(const Uint8 iAxis)
    {
        return iAxis == SDL_GAMEPAD_AXIS_LEFTX  || iAxis == SDL_GAMEPAD_AXIS_LEFTY ||
               iAxis == SDL_GAMEPAD_AXIS_RIGHTX || iAxis == SDL_GAMEPAD_AXIS_RIGHTY;
    }
}

CGamepad::CGamepad()
:m_bInitialized(false),
 m_iLeftStickDeadzone(3500),
 m_iRightStickDeadzone(3500),
 m_iTriggerThreshold(30),
 m_iMouseActivityPx(4),
 m_iPadActiveGraceMs(500),
 m_LeftStickCurve{  EStickCurveType::Power,   2.0f, 0.60f, 6.0f, 0.60f, 0.60f },
 m_RightStickCurve{ EStickCurveType::Sigmoid, 2.0f, 0.60f, 8.0f, 0.70f, 0.90f },
 m_fRightStickScale(0.6f),
 m_iActivePadId(0),
 m_iPrevButtons(0),
 m_fPrevLeftStickX(0.0f),
 m_fPrevLeftStickY(0.0f),
 m_fPrevRightStickX(0.0f),
 m_fPrevRightStickY(0.0f),
 m_fPrevLeftTrigger(0.0f),
 m_fPrevRightTrigger(0.0f),
 m_fLeftStickRawMag(0.0f),
 m_fRightStickRawMag(0.0f),
 m_iLastPadActivityMs(0),
 m_iLastMouseActivityMs(0),
 m_iRawMouseAccum(0),
 m_iRawMouseAccumStartMs(0)
{
    //No SDL calls here: this runs during CLauncher's member-init phase,
    //before any engine package is loaded, and SDL_Init must not run until
    //Init() (see its comment in Gamepad.h).
    LoadSettings();
}

CGamepad::~CGamepad()
{
    if (m_bInitialized)
    {
        for (const SOpenPad& Pad : m_OpenPads)
        {
            SDL_CloseGamepad(Pad.pPad);
        }
        m_OpenPads.clear();
        SDL_Quit();
    }
}

bool CGamepad::Init(UViewport* /*pViewport*/)
{
    //Probe for the delay-loaded SDL3.dll before making any SDL call, so a
    //machine without it degrades to gamepad-less instead of failing to
    //start. Keep the handle, never FreeLibrary it -- the delay-load thunks
    //resolve against this same load. Deliberately no SEH here: MSVC rejects
    //__try in functions requiring object unwinding (C2712).
    const HMODULE hSDL = LoadLibraryW(L"SDL3.dll");
    if (!hSDL)
    {
        GLog->Logf(L"Gamepad: SDL3.dll not found -- running gamepad-less.");
        return false;
    }

    if (!SDL_Init(SDL_INIT_GAMEPAD))
    {
        //%hs is an MSVC vswprintf extension for inserting a narrow string
        //into a wide format; SDL_GetError() returns UTF-8/ASCII char*.
        GLog->Logf(L"Gamepad: SDL_Init failed: %hs -- running gamepad-less.", SDL_GetError());
        return false;
    }

    m_bInitialized = true;

    //Optional user-supplied controller database next to the exe, for hardware
    //newer than the SDL build's built-in mappings.
    wchar_t szDbPath[MAX_PATH] = {};
    if (GetModuleFileNameW(NULL, szDbPath, static_cast<DWORD>(ARRAY_COUNT(szDbPath))) != 0 &&
        PathRemoveFileSpecW(szDbPath) &&
        PathAppendW(szDbPath, L"gamecontrollerdb.txt") &&
        PathFileExistsW(szDbPath))
    {
        char szDbPathUtf8[MAX_PATH * 4] = {};
        if (WideCharToMultiByte(CP_UTF8, 0, szDbPath, -1, szDbPathUtf8, static_cast<int>(sizeof(szDbPathUtf8)), NULL, NULL) != 0)
        {
            const int iAdded = SDL_AddGamepadMappingsFromFile(szDbPathUtf8);
            if (iAdded < 0)
            {
                GLog->Logf(L"Gamepad: failed to load gamecontrollerdb.txt: %hs", SDL_GetError());
            }
            else
            {
                GLog->Logf(L"Gamepad: loaded %d mappings from gamecontrollerdb.txt", iAdded);
            }
        }
    }

    //Pads already connected at startup. SDL also queues an ADDED event for
    //each of them, which ProcessEvents ignores as already-open.
    int iCount = 0;
    SDL_JoystickID* const pIds = SDL_GetGamepads(&iCount);
    if (pIds)
    {
        for (int i = 0; i < iCount; ++i)
        {
            SDL_Gamepad* const pPad = SDL_OpenGamepad(pIds[i]);
            if (pPad)
            {
                m_OpenPads.push_back({ pIds[i], pPad });
                if (m_iActivePadId == 0)
                {
                    m_iActivePadId = pIds[i];
                }
            }
        }
        SDL_free(pIds);
    }

    return true;
}

void CGamepad::LoadSettings()
{
    assert(GConfig);

    //Track absence per key. Each Get* indicates absence via UBOOL==0 (numeric
    //reads) or UBOOL==0 from GetString (string reads). For absent keys we leave
    //the field alone -- a fresh-constructed CGamepad keeps its initializer-list
    //default; a reload preserves the last-loaded value. After clamping, every
    //absent key is written back so the ini is self-documenting and UScript's
    //var config always finds a value.
    static const wchar_t* const kSection = L"DXController.ControllerSettings";

    bool bMissDeadzoneLeft       = !GConfig->GetInt(kSection, L"StickDeadzoneLeft",  m_iLeftStickDeadzone);
    bool bMissDeadzoneRight      = !GConfig->GetInt(kSection, L"StickDeadzoneRight", m_iRightStickDeadzone);
    bool bMissTriggerThreshold   = !GConfig->GetInt(kSection, L"TriggerThreshold",   m_iTriggerThreshold);
    bool bMissMouseActivityPx    = !GConfig->GetInt(kSection, L"MouseActivityPx",    m_iMouseActivityPx);
    bool bMissPadActiveGraceMs   = !GConfig->GetInt(kSection, L"PadActiveGraceMs",   m_iPadActiveGraceMs);

    //The threshold keeps its 0..255 meaning; out-of-range hand-edits would
    //overflow the scale into SDL's trigger range in EmitTriggerAxis.
    m_iTriggerThreshold = std::min(255, std::max(0, m_iTriggerThreshold));

    //Per-stick response curves. String token chosen so adding/removing curve
    //types in future never invalidates a hand-edited ini. Each numeric param is
    //clamped to guard against typos producing NaN/Inf in pow/exp.
    //Absence is detected via the UBOOL return of GetString rather than a nullptr
    //check (GetStr always returns a static buffer, never nullptr).
    TCHAR szCurveToken[64];
    bool bMissCurveLeftType  = !GConfig->GetString(kSection, L"StickCurveLeft",  szCurveToken, ARRAY_COUNT(szCurveToken));
    m_LeftStickCurve.eType   = ParseStickCurveType(bMissCurveLeftType  ? nullptr : szCurveToken, m_LeftStickCurve.eType);
    bool bMissCurveRightType = !GConfig->GetString(kSection, L"StickCurveRight", szCurveToken, ARRAY_COUNT(szCurveToken));
    m_RightStickCurve.eType  = ParseStickCurveType(bMissCurveRightType ? nullptr : szCurveToken, m_RightStickCurve.eType);

    bool bMissPowerLeft           = !GConfig->GetFloat(kSection, L"StickCurvePowerLeft",             m_LeftStickCurve.fPower);
    bool bMissPowerRight          = !GConfig->GetFloat(kSection, L"StickCurvePowerRight",            m_RightStickCurve.fPower);
    bool bMissExpoLeft            = !GConfig->GetFloat(kSection, L"StickCurveExpoLeft",              m_LeftStickCurve.fExpo);
    bool bMissExpoRight           = !GConfig->GetFloat(kSection, L"StickCurveExpoRight",             m_RightStickCurve.fExpo);
    bool bMissSigSteepLeft        = !GConfig->GetFloat(kSection, L"StickCurveSigmoidSteepnessLeft",  m_LeftStickCurve.fSigSteepness);
    bool bMissSigSteepRight       = !GConfig->GetFloat(kSection, L"StickCurveSigmoidSteepnessRight", m_RightStickCurve.fSigSteepness);
    bool bMissSigMidLeft          = !GConfig->GetFloat(kSection, L"StickCurveSigmoidMidpointLeft",   m_LeftStickCurve.fSigMidpoint);
    bool bMissSigMidRight         = !GConfig->GetFloat(kSection, L"StickCurveSigmoidMidpointRight",  m_RightStickCurve.fSigMidpoint);
    bool bMissSigStrengthLeft     = !GConfig->GetFloat(kSection, L"StickCurveSigmoidStrengthLeft",   m_LeftStickCurve.fSigStrength);
    bool bMissSigStrengthRight    = !GConfig->GetFloat(kSection, L"StickCurveSigmoidStrengthRight",  m_RightStickCurve.fSigStrength);

    //Post-curve output scale for the right stick: full deflection tops out at
    //scale * 1000 axis units. No left-stick counterpart -- capping movement
    //speed was judged useless.
    bool bMissScaleRight          = !GConfig->GetFloat(kSection, L"StickScaleRight",                 m_fRightStickScale);
    m_fRightStickScale = std::min(1.0f, std::max(0.1f, m_fRightStickScale));

    auto ClampCurve = [](SStickCurve& Curve)
    {
        Curve.fPower        = std::min(10.0f,  std::max(0.1f,  Curve.fPower));
        Curve.fExpo         = std::min(1.0f,   std::max(0.0f,  Curve.fExpo));
        Curve.fSigSteepness = std::min(12.0f,  std::max(1.0f,  Curve.fSigSteepness));
        Curve.fSigMidpoint  = std::min(0.85f,  std::max(0.15f, Curve.fSigMidpoint));
        Curve.fSigStrength  = std::min(1.0f,   std::max(0.0f,  Curve.fSigStrength));
    };
    ClampCurve(m_LeftStickCurve);
    ClampCurve(m_RightStickCurve);

    //Backfill: write only the keys that were missing this load. Present keys
    //are not rewritten -- a present-but-out-of-range hand-edit gets clamped
    //in memory but its ini line is left alone.
    bool bAnyMissing = false;
    if (bMissDeadzoneLeft)     { GConfig->SetInt(kSection, L"StickDeadzoneLeft",                          m_iLeftStickDeadzone);              bAnyMissing = true; }
    if (bMissDeadzoneRight)    { GConfig->SetInt(kSection, L"StickDeadzoneRight",                         m_iRightStickDeadzone);             bAnyMissing = true; }
    if (bMissTriggerThreshold) { GConfig->SetInt(kSection, L"TriggerThreshold",                           m_iTriggerThreshold);               bAnyMissing = true; }
    if (bMissMouseActivityPx)  { GConfig->SetInt(kSection, L"MouseActivityPx",                            m_iMouseActivityPx);                bAnyMissing = true; }
    if (bMissPadActiveGraceMs) { GConfig->SetInt(kSection, L"PadActiveGraceMs",                           m_iPadActiveGraceMs);               bAnyMissing = true; }

    if (bMissCurveLeftType)    { GConfig->SetString(kSection, L"StickCurveLeft",                          StickCurveTypeToString(m_LeftStickCurve.eType));  bAnyMissing = true; }
    if (bMissCurveRightType)   { GConfig->SetString(kSection, L"StickCurveRight",                         StickCurveTypeToString(m_RightStickCurve.eType)); bAnyMissing = true; }

    if (bMissPowerLeft)        { GConfig->SetFloat(kSection, L"StickCurvePowerLeft",                      m_LeftStickCurve.fPower);           bAnyMissing = true; }
    if (bMissPowerRight)       { GConfig->SetFloat(kSection, L"StickCurvePowerRight",                     m_RightStickCurve.fPower);          bAnyMissing = true; }
    if (bMissExpoLeft)         { GConfig->SetFloat(kSection, L"StickCurveExpoLeft",                       m_LeftStickCurve.fExpo);            bAnyMissing = true; }
    if (bMissExpoRight)        { GConfig->SetFloat(kSection, L"StickCurveExpoRight",                      m_RightStickCurve.fExpo);           bAnyMissing = true; }
    if (bMissSigSteepLeft)     { GConfig->SetFloat(kSection, L"StickCurveSigmoidSteepnessLeft",           m_LeftStickCurve.fSigSteepness);    bAnyMissing = true; }
    if (bMissSigSteepRight)    { GConfig->SetFloat(kSection, L"StickCurveSigmoidSteepnessRight",          m_RightStickCurve.fSigSteepness);   bAnyMissing = true; }
    if (bMissSigMidLeft)       { GConfig->SetFloat(kSection, L"StickCurveSigmoidMidpointLeft",            m_LeftStickCurve.fSigMidpoint);     bAnyMissing = true; }
    if (bMissSigMidRight)      { GConfig->SetFloat(kSection, L"StickCurveSigmoidMidpointRight",           m_RightStickCurve.fSigMidpoint);    bAnyMissing = true; }
    if (bMissSigStrengthLeft)  { GConfig->SetFloat(kSection, L"StickCurveSigmoidStrengthLeft",            m_LeftStickCurve.fSigStrength);     bAnyMissing = true; }
    if (bMissSigStrengthRight) { GConfig->SetFloat(kSection, L"StickCurveSigmoidStrengthRight",           m_RightStickCurve.fSigStrength);    bAnyMissing = true; }
    if (bMissScaleRight)       { GConfig->SetFloat(kSection, L"StickScaleRight",                          m_fRightStickScale);                bAnyMissing = true; }

    if (bAnyMissing)
    {
        GConfig->Flush(FALSE);
    }
}

void CGamepad::Reload()
{
    LoadSettings();
}

void CGamepad::SampleCurve(const EStick eStick, int iCount, FOutputDevice& Ar) const
{
    //Clamp to [2, 256]: 2 to have well-defined endpoints, 256 well above any
    //plausible preview pixel-width need. The buffer below is sized for the
    //upper bound.
    if (iCount < 2)   iCount = 2;
    if (iCount > 256) iCount = 256;

    const SStickCurve& Curve   = (eStick == EStick::Left) ? m_LeftStickCurve    : m_RightStickCurve;
    const int          iDz     = (eStick == EStick::Left) ? m_iLeftStickDeadzone : m_iRightStickDeadzone;
    const float        fScale  = (eStick == EStick::Left) ? 1.0f                 : m_fRightStickScale;
    const float        fCDz    = static_cast<float>(iDz) / 32767.0f;
    const float        fDenom  = static_cast<float>(iCount - 1);

    //"%.4f," is 7 chars per value; 256 * 7 + 1 = 1793.
    wchar_t szBuffer[2048];
    int     iWritten = 0;
    for (int i = 0; i < iCount; ++i)
    {
        const float fU = static_cast<float>(i) / fDenom;
        float fY;
        if (fU <= fCDz)
        {
            fY = 0.0f;
        }
        else
        {
            //Same pipeline as EmitStickAxes: shape, then apply the output
            //scale, so the preview shows the real ceiling.
            const float fR = (fU - fCDz) / (1.0f - fCDz);
            fY = ShapeStickMagnitude(fR, Curve) * fScale;
        }

        //ShapeStickMagnitude is pinned to 0 and 1 across all four curves on
        //inputs in [0, 1]; clamp defensively against accumulated float error.
        if (fY < 0.0f) fY = 0.0f;
        if (fY > 1.0f) fY = 1.0f;

        const int iCap = static_cast<int>(_countof(szBuffer)) - iWritten;
        const int iN   = _snwprintf_s(szBuffer + iWritten, iCap, _TRUNCATE,
                                      (i + 1 < iCount) ? L"%.4f," : L"%.4f", fY);
        if (iN < 0)
        {
            break;
        }
        iWritten += iN;
    }

    Ar.Logf(L"%s", szBuffer);
}

void CGamepad::GetRawStickMags(FOutputDevice& Ar) const
{
    wchar_t szBuffer[32];
    _snwprintf_s(szBuffer, _TRUNCATE, L"L=%.4f R=%.4f", m_fLeftStickRawMag, m_fRightStickRawMag);
    Ar.Logf(L"%s", szBuffer);
}

void CGamepad::EmitButtonChanges(UEngine* const pEngine, UViewport* const pViewport, const std::uint32_t iNewButtons)
{
    const std::uint32_t iChanged = iNewButtons ^ m_iPrevButtons;
    if (iChanged == 0)
    {
        return;
    }
    for (size_t i = 0; i < ARRAY_COUNT(kButtonMap); ++i)
    {
        const std::uint32_t iBit = 1u << i;
        if ((iChanged & iBit) == 0)
        {
            continue;
        }
        const EInputAction eAction = (iNewButtons & iBit) ? IST_Press : IST_Release;
        pEngine->InputEvent(pViewport, kButtonMap[i].eKey, eAction, 0.0f);
    }
    m_iPrevButtons = iNewButtons;
}

void CGamepad::ReleaseHeldButtons(UEngine* const pEngine, UViewport* const pViewport)
{
    if (m_iPrevButtons == 0)
    {
        return;
    }
    for (size_t i = 0; i < ARRAY_COUNT(kButtonMap); ++i)
    {
        if (m_iPrevButtons & (1u << i))
        {
            pEngine->InputEvent(pViewport, kButtonMap[i].eKey, IST_Release, 0.0f);
        }
    }
    m_iPrevButtons = 0;
}

//Stock Unreal WinDrv configures DirectInput joystick axes to -1000..1000 via
//DIPROP_RANGE; User.ini Speed= values are tuned for that magnitude. Emit in the
//same convention so existing bindings work without retuning.
static constexpr float kAxisRange = 1000.0f;

void CGamepad::EmitStickAxes(UEngine* const pEngine, UViewport* const pViewport,
                             const int iRawX, const int iRawY, const int iDeadzone,
                             const SStickCurve& Curve, const float fScale,
                             const EInputKey eKeyX, const EInputKey eKeyY,
                             float& fOutX, float& fOutY)
{
    //fOutX/fOutY are passed by reference and hold the previous tick's
    //post-deadzone value on entry. Snapshot before the new value overwrites
    //them so we can detect the non-zero -> zero edge below.
    const float fPrevX = fOutX;
    const float fPrevY = fOutY;

    //Work entirely in normalized magnitude [0, 1]; scale to axis units once at
    //the end. fRawMag can exceed 32767 on a diagonal (~46340 at full 45 deg);
    //the curve extrapolates monotonically and the per-axis clamp catches it.
    const float fXf     = static_cast<float>(iRawX);
    const float fYf     = static_cast<float>(iRawY);
    const float fRawMag = std::sqrt(fXf * fXf + fYf * fYf);
    const float fU      = fRawMag / 32767.0f;
    const float fCDz    = static_cast<float>(iDeadzone) / 32767.0f;

    if (fU <= fCDz || fRawMag <= 0.0f)
    {
        fOutX = 0.0f;
        fOutY = 0.0f;
    }
    else
    {
        //Radial deadzone: remap (cDz, 1] to (0, 1] linearly. Curve shapes that
        //post-deadzone magnitude; fScale then caps the output ceiling. Direction
        //preserved: a single combined scale = out_axis_mag / raw_mag applied to
        //raw X/Y yields direction * out_axis_mag with no intermediate sqrt.
        const float fR         = (fU - fCDz) / (1.0f - fCDz);
        const float fS         = ShapeStickMagnitude(fR, Curve);
        const float fOutMag    = fS * fScale * kAxisRange;
        const float fAxisScale = fOutMag / fRawMag;
        fOutX = std::min(kAxisRange, std::max(-kAxisRange, fXf * fAxisScale));
        fOutY = std::min(kAxisRange, std::max(-kAxisRange, fYf * fAxisScale));
    }

    if (fOutX != 0.0f)
    {
        pEngine->InputEvent(pViewport, eKeyX, IST_Axis, fOutX);
    }
    else if (fPrevX != 0.0f)
    {
        pEngine->InputEvent(pViewport, eKeyX, IST_Axis, 0.0f);
    }
    if (fOutY != 0.0f)
    {
        pEngine->InputEvent(pViewport, eKeyY, IST_Axis, fOutY);
    }
    else if (fPrevY != 0.0f)
    {
        pEngine->InputEvent(pViewport, eKeyY, IST_Axis, 0.0f);
    }
}

float CGamepad::EmitTriggerAxis(UEngine* const pEngine, UViewport* const pViewport,
                                const int iRaw, const float fPrev, const EInputKey eKey)
{
    //The ini key keeps its XInput-era 0..255 meaning so existing settings stay
    //valid; SDL reports triggers as 0..32767, so scale the threshold up rather
    //than the value down.
    const int iT = m_iTriggerThreshold * 32767 / 255;

    float fOut;
    if (iRaw <= iT)
    {
        fOut = 0.0f;
    }
    else
    {
        //Linear remap (iT, 32767] -> (0, kAxisRange]; same convention as sticks.
        fOut = static_cast<float>(iRaw - iT) * kAxisRange / static_cast<float>(32767 - iT);
        fOut = std::min(kAxisRange, fOut);
    }

    if (fOut != 0.0f)
    {
        pEngine->InputEvent(pViewport, eKey, IST_Axis, fOut);
    }
    else if (fPrev != 0.0f)
    {
        pEngine->InputEvent(pViewport, eKey, IST_Axis, 0.0f);
    }
    return fOut;
}

void CGamepad::FlushHeldAxes(UEngine* const pEngine, UViewport* const pViewport)
{
    struct Entry
    {
        float*    pPrev;
        EInputKey eKey;
    };
    Entry aAxes[] =
    {
        { &m_fPrevLeftStickX,   IK_JoyX },
        { &m_fPrevLeftStickY,   IK_JoyY },
        { &m_fPrevRightStickX,  IK_JoyU },
        { &m_fPrevRightStickY,  IK_JoyV },
        { &m_fPrevLeftTrigger,  IK_JoyZ },
        { &m_fPrevRightTrigger, IK_JoyR },
    };
    for (Entry& Axis : aAxes)
    {
        if (*Axis.pPrev != 0.0f)
        {
            pEngine->InputEvent(pViewport, Axis.eKey, IST_Axis, 0.0f);
            *Axis.pPrev = 0.0f;
        }
    }
}

void CGamepad::ReleaseAll(UEngine* const pEngine, UViewport* const pViewport)
{
    ReleaseHeldButtons(pEngine, pViewport);
    FlushHeldAxes(pEngine, pViewport);
    m_fLeftStickRawMag  = 0.0f;
    m_fRightStickRawMag = 0.0f;
}

SDL_Gamepad* CGamepad::GetActivePad() const
{
    if (m_iActivePadId == 0)
    {
        return nullptr;
    }
    for (const SOpenPad& Pad : m_OpenPads)
    {
        if (Pad.iId == m_iActivePadId)
        {
            return Pad.pPad;
        }
    }
    return nullptr;
}

void CGamepad::ClosePad(const std::uint32_t iPadId)
{
    for (size_t i = 0; i < m_OpenPads.size(); ++i)
    {
        if (m_OpenPads[i].iId == iPadId)
        {
            SDL_CloseGamepad(m_OpenPads[i].pPad);
            m_OpenPads.erase(m_OpenPads.begin() + i);
            return;
        }
    }
}

void CGamepad::SetActivePad(UEngine* const pEngine, UViewport* const pViewport, const std::uint32_t iPadId)
{
    if (iPadId == m_iActivePadId)
    {
        return;
    }
    bool bOpen = false;
    for (const SOpenPad& Pad : m_OpenPads)
    {
        if (Pad.iId == iPadId)
        {
            bOpen = true;
            break;
        }
    }
    if (!bOpen)
    {
        return;
    }

    //Everything the outgoing pad still holds is released before the switch, so
    //a mid-hold change of hands can't leave a stuck button or axis behind.
    ReleaseAll(pEngine, pViewport);
    m_iActivePadId = iPadId;
}

void CGamepad::ProcessEvents(UEngine* const pEngine, UViewport* const pViewport)
{
    SDL_Event Event;
    while (SDL_PollEvent(&Event))
    {
        switch (Event.type)
        {
        case SDL_EVENT_GAMEPAD_ADDED:
        {
            bool bAlreadyOpen = false;
            for (const SOpenPad& Pad : m_OpenPads)
            {
                if (Pad.iId == Event.gdevice.which)
                {
                    bAlreadyOpen = true;
                    break;
                }
            }
            if (bAlreadyOpen)
            {
                break;
            }
            SDL_Gamepad* const pPad = SDL_OpenGamepad(Event.gdevice.which);
            if (pPad)
            {
                m_OpenPads.push_back({ Event.gdevice.which, pPad });
                if (m_iActivePadId == 0)
                {
                    m_iActivePadId = Event.gdevice.which;
                }
            }
            break;
        }

        case SDL_EVENT_GAMEPAD_REMOVED:
        {
            ClosePad(Event.gdevice.which);
            if (Event.gdevice.which == m_iActivePadId)
            {
                ReleaseAll(pEngine, pViewport);
                m_iActivePadId = m_OpenPads.empty() ? 0 : m_OpenPads.front().iId;
            }
            break;
        }

        //A press or a decisive stick push on a non-active pad hands it the
        //active slot. These events carry no other duty -- emission comes from
        //the snapshot in Poll().
        case SDL_EVENT_GAMEPAD_BUTTON_DOWN:
            SetActivePad(pEngine, pViewport, Event.gbutton.which);
            break;

        case SDL_EVENT_GAMEPAD_AXIS_MOTION:
            if (IsStickAxis(Event.gaxis.axis) &&
                (Event.gaxis.value > kActiveSwitchAxisValue || Event.gaxis.value < -kActiveSwitchAxisValue))
            {
                SetActivePad(pEngine, pViewport, Event.gaxis.which);
            }
            break;

        default:
            break;
        }
    }
}

std::uint32_t CGamepad::SupplementalButtonMask(SDL_Gamepad* const /*pPad*/) const
{
    //Spec §7 (docs/superpowers/specs/2026-08-31-sdl3-gamepad-design.md): the
    //single point where a supplemental source -- e.g. a launcher-side
    //GameInput read for Xbox Elite paddles, which stock SDL cannot report on
    //Windows -- ORs extra bits into the snapshot mask, using the same bit
    //positions as kButtonMap. Structure only; nothing supplements today.
    return 0;
}

void CGamepad::Poll(UEngine* const pEngine, UViewport* const pViewport, const bool bHasFocus)
{
    if (!pViewport || !m_bInitialized)
    {
        return;
    }

    //Draining the queue is also what pumps joystick updates
    //(SDL_HINT_AUTO_UPDATE_JOYSTICKS is on by default), so the reads below are
    //fresh without a separate SDL_UpdateGamepads.
    ProcessEvents(pEngine, pViewport);

    if (!bHasFocus)
    {
        ReleaseAll(pEngine, pViewport);
        return;
    }

    SDL_Gamepad* const pPad = GetActivePad();
    if (!pPad)
    {
        return;
    }

    std::uint32_t iButtons = 0;
    for (size_t i = 0; i < ARRAY_COUNT(kButtonMap); ++i)
    {
        if (SDL_GetGamepadButton(pPad, kButtonMap[i].eButton))
        {
            iButtons |= (1u << i);
        }
    }
    iButtons |= SupplementalButtonMask(pPad);

    const int iLeftX      = ClampStickAxis(SDL_GetGamepadAxis(pPad, SDL_GAMEPAD_AXIS_LEFTX));
    const int iLeftY      = NegateStickY(SDL_GetGamepadAxis(pPad, SDL_GAMEPAD_AXIS_LEFTY));
    const int iRightX     = ClampStickAxis(SDL_GetGamepadAxis(pPad, SDL_GAMEPAD_AXIS_RIGHTX));
    const int iRightY     = NegateStickY(SDL_GetGamepadAxis(pPad, SDL_GAMEPAD_AXIS_RIGHTY));
    const int iLeftTrig   = SDL_GetGamepadAxis(pPad, SDL_GAMEPAD_AXIS_LEFT_TRIGGER);
    const int iRightTrig  = SDL_GetGamepadAxis(pPad, SDL_GAMEPAD_AXIS_RIGHT_TRIGGER);

    //Cache raw normalized magnitudes for GetRawStickMags(). Diagonal max is
    //~1.414; clamp to [0, 1] so UScript's preview dot stays inside the plot
    //domain.
    {
        const float fLX = static_cast<float>(iLeftX);
        const float fLY = static_cast<float>(iLeftY);
        const float fRX = static_cast<float>(iRightX);
        const float fRY = static_cast<float>(iRightY);
        float fLMag = std::sqrt(fLX * fLX + fLY * fLY) / 32767.0f;
        float fRMag = std::sqrt(fRX * fRX + fRY * fRY) / 32767.0f;
        if (fLMag > 1.0f) fLMag = 1.0f;
        if (fRMag > 1.0f) fRMag = 1.0f;
        m_fLeftStickRawMag  = fLMag;
        m_fRightStickRawMag = fRMag;
    }

    const std::uint32_t iButtonsChanged = iButtons ^ m_iPrevButtons;

    EmitButtonChanges(pEngine, pViewport, iButtons);
    EmitStickAxes(pEngine, pViewport,
                  iLeftX, iLeftY, m_iLeftStickDeadzone,
                  m_LeftStickCurve, 1.0f,
                  IK_JoyX, IK_JoyY,
                  m_fPrevLeftStickX, m_fPrevLeftStickY);
    EmitStickAxes(pEngine, pViewport,
                  iRightX, iRightY, m_iRightStickDeadzone,
                  m_RightStickCurve, m_fRightStickScale,
                  IK_JoyU, IK_JoyV,
                  m_fPrevRightStickX, m_fPrevRightStickY);
    m_fPrevLeftTrigger  = EmitTriggerAxis(pEngine, pViewport, iLeftTrig,  m_fPrevLeftTrigger,  IK_JoyZ);
    m_fPrevRightTrigger = EmitTriggerAxis(pEngine, pViewport, iRightTrig, m_fPrevRightTrigger, IK_JoyR);

    const bool bPadActiveThisPoll =
        iButtonsChanged != 0 ||
        m_fPrevLeftStickX  != 0.0f || m_fPrevLeftStickY  != 0.0f ||
        m_fPrevRightStickX != 0.0f || m_fPrevRightStickY != 0.0f ||
        m_fPrevLeftTrigger != 0.0f || m_fPrevRightTrigger != 0.0f;
    if (bPadActiveThisPoll)
    {
        m_iLastPadActivityMs = GetTickCount64();
    }
}

bool CGamepad::IsPadActive() const
{
    const ULONGLONG iNowMs    = GetTickCount64();
    const ULONGLONG iGraceMs  = static_cast<ULONGLONG>(m_iPadActiveGraceMs);
    const bool bPadRecent     = m_iLastPadActivityMs   != 0 && (iNowMs - m_iLastPadActivityMs)   < iGraceMs;
    const bool bMouseRecent   = m_iLastMouseActivityMs != 0 && (iNowMs - m_iLastMouseActivityMs) < iGraceMs;
    return bPadRecent && !bMouseRecent;
}

bool CGamepad::IsMouseActive() const
{
    const ULONGLONG iNowMs   = GetTickCount64();
    const ULONGLONG iGraceMs = static_cast<ULONGLONG>(m_iPadActiveGraceMs);
    return m_iLastMouseActivityMs != 0 && (iNowMs - m_iLastMouseActivityMs) < iGraceMs;
}

void CGamepad::NotifyMouseActivity(const int iDeltaX, const int iDeltaY)
{
    const int iManhattan = (iDeltaX < 0 ? -iDeltaX : iDeltaX) + (iDeltaY < 0 ? -iDeltaY : iDeltaY);
    if (iManhattan == 0)
    {
        return; //button-only WM_INPUT packet
    }

    //Accumulate over a short window: a single raw packet from a slow hand
    //movement carries only 1-2 counts, well under the threshold that one
    //coalesced WM_MOUSEMOVE used to clear in a frame.
    constexpr ULONGLONG kAccumWindowMs = 250;
    const ULONGLONG iNowMs = GetTickCount64();
    if (m_iRawMouseAccumStartMs == 0 || iNowMs - m_iRawMouseAccumStartMs > kAccumWindowMs)
    {
        m_iRawMouseAccum        = 0;
        m_iRawMouseAccumStartMs = iNowMs;
    }
    m_iRawMouseAccum += iManhattan;
    if (m_iRawMouseAccum > m_iMouseActivityPx)
    {
        m_iLastMouseActivityMs = iNowMs;
    }
}
