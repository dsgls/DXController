#include "stdafx.h"
#include "Gamepad.h"

#include "AxisMapParse.h"
#include "ButtonMapResolve.h"

#include <SDL3/SDL.h>
#include <string>

namespace
{
    struct ButtonMapEntry
    {
        SDL_GamepadButton eButton;
        EInputKey         eKey;
    };

    //Compiled-in default button map -- the base layer LoadButtonMap() resolves
    //[DXController.GamepadButtonMap] ini overrides onto. The snapshot mask
    //(see Poll()) indexes by SDL_GamepadButton value, not by position in this
    //table. SDL_GAMEPAD_BUTTON_GUIDE and MISC2..6 are deliberately unmapped
    //by default (reachable via the ini map).
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

    //The snapshot mask (Poll()) and m_ResolvedButtonKeys are both indexed by
    //SDL_GamepadButton value directly, so the full enum -- not just the
    //compiled defaults above -- must fit in the Uint32 mask.
    static_assert(SDL_GAMEPAD_BUTTON_COUNT <= 32, "button mask is a Uint32");

    //Slots the fixed axis pipeline already emits on (EmitStickAxes/
    //EmitTriggerAxis -- see Poll()). A [DXController.GamepadButtonMap] or
    //[DXController.GamepadAxisMap] entry targeting one of these is rejected:
    //per-source edge tracking can't share a destination slot without breaking
    //the press/release and zero-edge contracts. LoadAxisMap() extends the
    //check with the resolved button map and the axis entries it has already
    //accepted.
    bool IsReservedAxisDestination(const EInputKey eKey)
    {
        return eKey == IK_JoyX || eKey == IK_JoyY ||
               eKey == IK_JoyZ || eKey == IK_JoyR ||
               eKey == IK_JoyU || eKey == IK_JoyV;
    }

    //SDL's button/key-name vocabulary is ASCII, so a small stack buffer always
    //fits in practice; a name that somehow doesn't fit just fails to resolve
    //below rather than corrupting anything. Returns false if the conversion
    //failed (e.g. buffer too small).
    bool NarrowFromWide(const wchar_t* const pszWide, char* const pszOut, const int iOutSize)
    {
        return WideCharToMultiByte(CP_UTF8, 0, pszWide, -1, pszOut, iOutSize, NULL, NULL) != 0;
    }

    //Inverse of NarrowFromWide, for spelling SDL's button-name strings back
    //into the ini during backfill.
    void WideFromNarrow(const char* const pszNarrow, wchar_t* const pszOut, const int iOutSize)
    {
        MultiByteToWideChar(CP_UTF8, 0, pszNarrow, -1, pszOut, iOutSize);
    }

    //Parses a [DXController.GamepadButtonMap] value: "None"/empty (unmapped),
    //an EInputKey name without the "IK_" prefix (resolved via
    //pViewport->Input->FindKeyName() -- the same table [Extension.InputExt]
    //binding names resolve against; pViewport may be null if Init()/Reload()
    //hasn't been given one yet, in which case name lookup is skipped and only
    //the numeric fallback below can succeed), or a bare numeric byte value as
    //a fallback spelling. Returns false (leaving *peOutKey untouched) if
    //pszValue matches none of these.
    bool ParseEInputKeyValue(const wchar_t* const pszValue, UViewport* const pViewport, EInputKey* const peOutKey)
    {
        if (!pszValue || pszValue[0] == L'\0' || _wcsicmp(pszValue, L"None") == 0)
        {
            *peOutKey = IK_None;
            return true;
        }
        if (pViewport && pViewport->Input)
        {
            EInputKey eKey;
            if (pViewport->Input->FindKeyName(pszValue, eKey))
            {
                *peOutKey = eKey;
                return true;
            }
        }
        wchar_t* pEnd = nullptr;
        const long iVal = wcstol(pszValue, &pEnd, 10);
        if (pEnd != pszValue && pEnd && *pEnd == L'\0' && iVal >= 0 && iVal < IK_MAX)
        {
            *peOutKey = static_cast<EInputKey>(iVal);
            return true;
        }
        return false;
    }

    //Stick deflection at which a non-active pad's AXIS_MOTION claims the active
    //slot: ~25%, deliberately coarser than the emission deadzones so a resting
    //stick on a second pad can't steal input. Triggers are excluded from the
    //switch signal entirely (see IsStickAxis): they rest at 0 and only rise,
    //some pads have a non-zero trigger floor, and SDL delivers initial
    //axis-state events right after SDL_OpenGamepad, so an idle or freshly
    //plugged-in pad would otherwise steal the slot.
    constexpr int kActiveSwitchAxisValue = 8000;

    bool IsStickAxis(const Uint8 iAxis)
    {
        return iAxis == SDL_GAMEPAD_AXIS_LEFTX  || iAxis == SDL_GAMEPAD_AXIS_LEFTY ||
               iAxis == SDL_GAMEPAD_AXIS_RIGHTX || iAxis == SDL_GAMEPAD_AXIS_RIGHTY;
    }
}

bool CGamepad::s_bSdlAvailable = false;

CGamepad::CGamepad()
:m_bInitialized(false),
 m_pViewport(nullptr),
 m_bWantGyro(false),
 m_bWantAccel(false),
 m_bWantTouchpad(false),
 m_iLeftStickDeadzone(3500),
 m_iRightStickDeadzone(3500),
 m_iTriggerThreshold(30),
 m_iMouseActivityPx(4),
 m_iPadActiveGraceMs(500),
 m_LeftStickCurve{  EStickCurveType::Power,   2.0f, 0.60f, 6.0f, 0.60f, 0.60f },
 m_RightStickCurve{ EStickCurveType::Sigmoid, 2.0f, 0.60f, 8.0f, 0.70f, 0.90f },
 m_fRightStickScale(0.6f),
 m_bInvertLookY(0),
 m_iActivePadId(0),
 m_iPrevButtons(0),
 m_fPrevLeftStickX(0.0f),
 m_fPrevLeftStickY(0.0f),
 m_fPrevRightStickX(0.0f),
 m_fPrevRightStickY(0.0f),
 m_fPrevLeftTrigger(0.0f),
 m_fPrevRightTrigger(0.0f),
 m_fLeftStickRawMag(0.0f),
 m_fRightStickRawMag(0.0f)
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

bool CGamepad::InitSdl()
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

    //CDialogPadNav polls gamepads directly (SDL_UpdateGamepads()) during the
    //pre-game dialogs, which run before Init() enables events -- leave the
    //queue disabled until then so nothing accumulates in it unread.
    SDL_SetGamepadEventsEnabled(false);

    m_bInitialized  = true;
    s_bSdlAvailable = true;

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

    return true;
}

bool CGamepad::Init(UViewport* const pViewport)
{
    m_pViewport = pViewport;

    //InitSdl() (called from CLauncher's constructor, ahead of the pre-game
    //dialogs) either failed or hasn't run; nothing below is safe without it.
    if (!m_bInitialized)
    {
        return false;
    }

    //Dialog-phase navigation (CDialogPadNav) is done polling directly; let
    //events start flowing so ProcessEvents' hotplug/active-pad tracking has
    //something to drain.
    SDL_SetGamepadEventsEnabled(true);

    LoadButtonMap();
    LoadAxisMap();

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
                m_OpenPads.push_back({ pIds[i], pPad, false, false, false });
                ApplyPadSensors(m_OpenPads.back());
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
    //overflow the scale into SDL's trigger range in EmitTriggerAxis. The
    //others clamp for the same reason and in the same silent way -- each
    //unit's clamp names what its own math cannot survive.
    m_iTriggerThreshold   = std::min(255, std::max(0, m_iTriggerThreshold));
    m_iLeftStickDeadzone  = StickResponse::ClampDeadzone(m_iLeftStickDeadzone);
    m_iRightStickDeadzone = StickResponse::ClampDeadzone(m_iRightStickDeadzone);
    m_iMouseActivityPx    = PadActivity::ClampMouseActivityPx(m_iMouseActivityPx);
    m_iPadActiveGraceMs   = PadActivity::ClampGraceMs(m_iPadActiveGraceMs);

    //Per-stick response curves. String token chosen so adding/removing curve
    //types in future never invalidates a hand-edited ini. Each numeric param is
    //clamped to guard against typos producing NaN/Inf in pow/exp.
    //Absence is detected via the UBOOL return of GetString rather than a nullptr
    //check (GetStr always returns a static buffer, never nullptr).
    TCHAR szCurveToken[64];
    bool bMissCurveLeftType  = !GConfig->GetString(kSection, L"StickCurveLeft",  szCurveToken, ARRAY_COUNT(szCurveToken));
    m_LeftStickCurve.eType   = AxisMapParse::ParseCurveType(bMissCurveLeftType  ? nullptr : szCurveToken, m_LeftStickCurve.eType);
    bool bMissCurveRightType = !GConfig->GetString(kSection, L"StickCurveRight", szCurveToken, ARRAY_COUNT(szCurveToken));
    m_RightStickCurve.eType  = AxisMapParse::ParseCurveType(bMissCurveRightType ? nullptr : szCurveToken, m_RightStickCurve.eType);

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

    //Gameplay-look Y inversion; negates the raw right-stick Y sample at the
    //EmitStickAxes call site in Poll(). See development.md's input-chain
    //axis table (IK_JoyV footnote) for the launcher/script split.
    bool bMissInvertLookY         = !GConfig->GetBool(kSection, L"InvertLookY",                      m_bInvertLookY);

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

    if (bMissCurveLeftType)    { GConfig->SetString(kSection, L"StickCurveLeft",                          AxisMapParse::CurveTypeToString(m_LeftStickCurve.eType));  bAnyMissing = true; }
    if (bMissCurveRightType)   { GConfig->SetString(kSection, L"StickCurveRight",                         AxisMapParse::CurveTypeToString(m_RightStickCurve.eType)); bAnyMissing = true; }

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
    if (bMissInvertLookY)      { GConfig->SetBool(kSection,  L"InvertLookY",                              m_bInvertLookY);                     bAnyMissing = true; }

    if (bAnyMissing)
    {
        GConfig->Flush(FALSE);
    }
}

void CGamepad::LoadButtonMap()
{
    assert(GConfig);

    static const wchar_t* const kSection = L"DXController.GamepadButtonMap";

    //Compiled-in defaults, indexed by SDL_GamepadButton value (guide and
    //misc2..6 resolve to IK_None here -- they have no compiled default).
    //Kept separate from the resolved table below: backfill writes this
    //default back for an absent ini line, not whatever another button's
    //override happened to leave the slot as.
    std::vector<int> DefaultKeys(SDL_GAMEPAD_BUTTON_COUNT, IK_None);
    for (const ButtonMapEntry& Entry : kButtonMap)
    {
        DefaultKeys[Entry.eButton] = Entry.eKey;
    }

    //Step 2 (spec sec4): fold ini lines into per-button overrides. A later
    //line for the same button wins over an earlier one (logged); OverrideLine
    //records the winning line's position in file order -- used below to break
    //ties when two overrides (neither a surviving default) target the same
    //slot: the later one loses.
    std::vector<bool> HasOverride(SDL_GAMEPAD_BUTTON_COUNT, false);
    std::vector<int>  OverrideKey(SDL_GAMEPAD_BUTTON_COUNT, IK_None);
    std::vector<int>  OverrideLine(SDL_GAMEPAD_BUTTON_COUNT, -1);

    TMultiMap<FString, FString>* const pSection = GConfig->GetSectionPrivate(kSection, FALSE, TRUE);
    if (pSection)
    {
        //Duplicate ini lines land as separate pairs in file order -- iterate,
        //don't Find, so a later line for the same button overrides an earlier
        //one rather than being missed.
        int iLine = 0;
        for (TMultiMap<FString, FString>::TIterator It(*pSection); It; ++It, ++iLine)
        {
            char szKeyUtf8[64];
            if (!NarrowFromWide(*It.Key(), szKeyUtf8, static_cast<int>(sizeof(szKeyUtf8))))
            {
                GLog->Logf(L"Gamepad: [DXController.GamepadButtonMap] key '%s' is not representable -- ignored.", *It.Key());
                continue;
            }
            const SDL_GamepadButton eButton = SDL_GetGamepadButtonFromString(szKeyUtf8);
            if (eButton == SDL_GAMEPAD_BUTTON_INVALID)
            {
                GLog->Logf(L"Gamepad: [DXController.GamepadButtonMap] unknown button name '%s' -- ignored.", *It.Key());
                continue;
            }

            EInputKey eNewKey;
            if (!ParseEInputKeyValue(*It.Value(), m_pViewport, &eNewKey))
            {
                GLog->Logf(L"Gamepad: [DXController.GamepadButtonMap] %s=%s does not name a known key -- ignored.", *It.Key(), *It.Value());
                continue;
            }

            if (HasOverride[eButton])
            {
                GLog->Logf(L"Gamepad: [DXController.GamepadButtonMap] '%s' appears more than once -- an earlier line for it is shadowed.", *It.Key());
            }
            HasOverride[eButton]  = true;
            OverrideKey[eButton]  = eNewKey;
            OverrideLine[eButton] = iLine;
        }
    }

    //Steps 3 and 4 (candidate map, then conflict resolution to a fixpoint) are
    //pure -- see ButtonMapResolve.h for the rules.
    ButtonMapResolve::SParams Params;
    Params.iKeyCount      = IK_MAX;
    Params.iNoneKey       = IK_None;
    Params.Defaults       = DefaultKeys; //the backfill below writes these back too
    Params.HasOverride    = std::move(HasOverride);
    Params.OverrideKey    = std::move(OverrideKey);
    Params.OverrideLine   = std::move(OverrideLine);
    Params.IsReservedDest = [](const int iKey) { return IsReservedAxisDestination(static_cast<EInputKey>(iKey)); };
    Params.ButtonName     = [](const int iButton)
    {
        const char* const pszName = SDL_GetGamepadStringForButton(static_cast<SDL_GamepadButton>(iButton));
        wchar_t szWide[64] = L"?";
        if (pszName)
        {
            WideFromNarrow(pszName, szWide, static_cast<int>(ARRAY_COUNT(szWide)));
        }
        return std::wstring(szWide);
    };

    const ButtonMapResolve::SResult Resolved = ButtonMapResolve::Resolve(Params);
    for (const std::wstring& Message : Resolved.Log)
    {
        GLog->Logf(L"%s", Message.c_str());
    }

    m_ResolvedButtonKeys.clear();
    m_ResolvedButtonKeys.reserve(Resolved.Keys.size());
    for (const int iKey : Resolved.Keys)
    {
        m_ResolvedButtonKeys.push_back(static_cast<EInputKey>(iKey));
    }

    //Backfill: any SDL button name absent from the section gets its compiled
    //default written back, spelled via SDL_GetGamepadStringForButton() (key
    //side) and Input->GetKeyName() (value side -- the same table FindKeyName
    //resolves against, so the round trip is exact), so the ini
    //self-documents every button name and its current slot. Same pattern as
    //LoadSettings(): only missing keys are written, one Flush if anything was.
    bool bAnyMissing = false;
    for (int i = 0; i < SDL_GAMEPAD_BUTTON_COUNT; ++i)
    {
        const char* const pszButtonName = SDL_GetGamepadStringForButton(static_cast<SDL_GamepadButton>(i));
        if (!pszButtonName)
        {
            continue;
        }
        wchar_t szButtonNameWide[64];
        WideFromNarrow(pszButtonName, szButtonNameWide, static_cast<int>(ARRAY_COUNT(szButtonNameWide)));

        wchar_t szExisting[64];
        if (GConfig->GetString(kSection, szButtonNameWide, szExisting, static_cast<INT>(ARRAY_COUNT(szExisting))))
        {
            continue; //already present -- present-but-invalid lines are left alone, not rewritten
        }

        const EInputKey eDefaultKey = static_cast<EInputKey>(DefaultKeys[i]);
        wchar_t szValueWide[64] = L"None";
        if (eDefaultKey != IK_None)
        {
            const TCHAR* const pszKeyName = (m_pViewport && m_pViewport->Input) ? m_pViewport->Input->GetKeyName(eDefaultKey) : nullptr;
            if (pszKeyName && pszKeyName[0] != L'\0')
            {
                wcscpy_s(szValueWide, pszKeyName);
            }
            else
            {
                //No viewport yet, or the engine has no name for this key:
                //fall back to the numeric spelling ParseEInputKeyValue also
                //accepts, so the backfilled line still round-trips.
                _snwprintf_s(szValueWide, _TRUNCATE, L"%d", static_cast<int>(eDefaultKey));
            }
        }
        GConfig->SetString(kSection, szButtonNameWide, szValueWide);
        bAnyMissing = true;
    }
    if (bAnyMissing)
    {
        GConfig->Flush(FALSE);
    }
}

void CGamepad::LoadAxisMap()
{
    assert(GConfig);

    static const wchar_t* const kSection = L"DXController.GamepadAxisMap";

    //Rebuilt from scratch every load. Callers flush the old entries first
    //(Reload -> ReleaseAll), so dropping their fPrev state here can't strand a
    //held value on a slot the new map no longer emits on.
    m_AxisMap.clear();
    m_bWantGyro     = false;
    m_bWantAccel    = false;
    m_bWantTouchpad = false;

    TMultiMap<FString, FString>* const pSection = GConfig->GetSectionPrivate(kSection, FALSE, TRUE);
    if (!pSection)
    {
        return; //absent section = empty map; nothing is backfilled (spec §5)
    }

    for (TMultiMap<FString, FString>::TIterator It(*pSection); It; ++It)
    {
        EAxisSource eSource  = EAxisSource::JoyAxis;
        int         iJoyAxis = 0;
        if (!AxisMapParse::ParseSourceName(*It.Key(), &eSource, &iJoyAxis))
        {
            GLog->Logf(L"Gamepad: [DXController.GamepadAxisMap] unknown source '%s' -- ignored.", *It.Key());
            continue;
        }

        //Slot name and parameters. The one engine dependency, resolving a slot
        //name against the viewport's key-name table, goes in as a callback.
        const AxisMapParse::SValue Value = AxisMapParse::ParseValue(*It.Key(), *It.Value(), IK_None,
            [this](const wchar_t* const pszName, int* const piOutKey)
            {
                EInputKey eParsed = IK_None;
                if (!ParseEInputKeyValue(pszName, m_pViewport, &eParsed))
                {
                    return false;
                }
                *piOutKey = eParsed;
                return true;
            });
        for (const std::wstring& Message : Value.Log)
        {
            GLog->Logf(L"%s", Message.c_str());
        }
        if (!Value.bAccepted || Value.iKey == IK_None)
        {
            continue; //rejected, or "None"/empty and deliberately inert
        }
        const EInputKey eKey = static_cast<EInputKey>(Value.iKey);

        //Destination registry (spec §5, same rule as §4): the fixed
        //stick/trigger slots, then the already-resolved button map, then the
        //axis entries accepted from earlier lines. Later line loses.
        std::vector<int> ButtonKeys;
        ButtonKeys.reserve(m_ResolvedButtonKeys.size());
        for (const EInputKey eButtonKey : m_ResolvedButtonKeys)
        {
            ButtonKeys.push_back(eButtonKey);
        }
        std::vector<int> AxisKeys;
        AxisKeys.reserve(m_AxisMap.size());
        for (const SAxisEntry& Entry : m_AxisMap)
        {
            AxisKeys.push_back(Entry.eKey);
        }
        const AxisMapParse::EDestStatus eDest = AxisMapParse::CheckDestination(
            Value.iKey,
            [](const int iKey) { return IsReservedAxisDestination(static_cast<EInputKey>(iKey)); },
            ButtonKeys, AxisKeys);
        if (eDest == AxisMapParse::EDestStatus::Reserved)
        {
            GLog->Logf(L"Gamepad: [DXController.GamepadAxisMap] %s targets a slot the stick/trigger pipeline already emits on -- ignored.", *It.Key());
            continue;
        }
        if (eDest == AxisMapParse::EDestStatus::Taken)
        {
            GLog->Logf(L"Gamepad: [DXController.GamepadAxisMap] %s's destination is already claimed by a button or another axis entry -- ignored.", *It.Key());
            continue;
        }

        m_AxisMap.push_back({ eSource, iJoyAxis, eKey, Value.fScale, Value.fDeadzone, 0.0f });

        switch (eSource)
        {
        case EAxisSource::GyroPitch:
        case EAxisSource::GyroYaw:
        case EAxisSource::GyroRoll:
            m_bWantGyro = true;
            break;
        case EAxisSource::AccelX:
        case EAxisSource::AccelY:
        case EAxisSource::AccelZ:
            m_bWantAccel = true;
            break;
        case EAxisSource::TouchpadX:
        case EAxisSource::TouchpadY:
            m_bWantTouchpad = true;
            break;
        default:
            break;
        }
    }
}

void CGamepad::ApplyPadSensors(SOpenPad& Pad)
{
    struct SensorRequest
    {
        SDL_SensorType eType;
        bool           bWanted;
        bool*          pbLogged;
        const wchar_t* pszName;
    };
    const SensorRequest aRequests[] =
    {
        { SDL_SENSOR_GYRO,  m_bWantGyro,  &Pad.bLoggedMissingGyro,  L"gyro"  },
        { SDL_SENSOR_ACCEL, m_bWantAccel, &Pad.bLoggedMissingAccel, L"accel" },
    };

    for (const SensorRequest& Request : aRequests)
    {
        if (!SDL_GamepadHasSensor(Pad.pPad, Request.eType))
        {
            //Logged once per pad so "why doesn't my gyro bind work" is
            //answerable from DeusEx.log without guessing at the hardware.
            if (Request.bWanted && !*Request.pbLogged)
            {
                GLog->Logf(L"Gamepad: [DXController.GamepadAxisMap] binds %s.* but pad %u has no such sensor -- those entries stay silent.",
                    Request.pszName, Pad.iId);
                *Request.pbLogged = true;
            }
            continue;
        }
        //Disabling when nothing is bound is the point of the demand-driven
        //rule: an enabled sensor costs report rate (and BT battery) whether or
        //not anything reads it.
        if (!SDL_SetGamepadSensorEnabled(Pad.pPad, Request.eType, Request.bWanted))
        {
            GLog->Logf(L"Gamepad: could not %s the %s sensor on pad %u: %hs",
                Request.bWanted ? L"enable" : L"disable", Request.pszName, Pad.iId, SDL_GetError());
        }
    }
}

void CGamepad::ApplyPadSensors()
{
    //Every open pad, not just the active one: any of them can take the active
    //slot on the user's next input, and a sensor enabled after the fact starts
    //cold.
    for (SOpenPad& Pad : m_OpenPads)
    {
        ApplyPadSensors(Pad);
    }
}

void CGamepad::Reload(UEngine* const pEngine, UViewport* const pViewport)
{
    if (pViewport)
    {
        m_pViewport = pViewport;
    }

    //Without SDL3.dll, Init() never ran and none of the below is safe --
    //LoadButtonMap()/LoadAxisMap() reach SDL_GetGamepadButtonFromString() /
    //SDL_GetGamepadStringForButton() delay-load thunks unconditionally while
    //writing back defaults, which crashes the process on a missing module.
    //Settings sliders in the in-game menu exec this path, so this has to be
    //silent rather than logged-and-bail like the other guarded entry points.
    if (!m_bInitialized)
    {
        return;
    }

    //Release/flush everything held under the OLD button map before rebuilding
    //it below -- m_iPrevButtons/m_fPrev* are per-source (per SDL button/axis),
    //but EmitButtonChanges/ReleaseHeldButtons translate a held source to an
    //EInputKey via m_ResolvedButtonKeys, which is about to change. Without
    //this, a button held across a reload that moves it to a new slot would
    //leave the old slot's Press with no matching Release, and never emit a
    //Press for the new slot until the physical button is released and
    //re-pressed. Mirrors ReleaseAll()'s use in the disconnect/pad-switch
    //paths. Skipped if either pointer is null (e.g. reload requested before
    //the engine/viewport exist) -- only the in-memory state is refreshed then.
    if (pEngine && pViewport)
    {
        ReleaseAll(pEngine, pViewport);
    }

    LoadSettings();
    LoadButtonMap();
    LoadAxisMap();
    ApplyPadSensors();
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
    const float        fDenom  = static_cast<float>(iCount - 1);

    //"%.4f," is 7 chars per value; 256 * 7 + 1 = 1793.
    wchar_t szBuffer[2048];
    int     iWritten = 0;
    for (int i = 0; i < iCount; ++i)
    {
        //The same magnitude pipeline EmitStickAxes runs, so the preview cannot
        //drift from the real response.
        const float fU = static_cast<float>(i) / fDenom;
        float fY = StickResponse::ShapeNormalized(fU, iDz, Curve, fScale);

        //ShapeMagnitude is pinned to 0 and 1 across all four curves on
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

const wchar_t* CGamepad::GetInfo() const
{
    if (!m_bInitialized)
    {
        return L"None";
    }
    SDL_Gamepad* const pPad = GetActivePad();
    if (pPad == nullptr)
    {
        return L"None";
    }
    switch (SDL_GetGamepadType(pPad))
    {
        case SDL_GAMEPAD_TYPE_XBOX360:                     return L"Xbox360";
        case SDL_GAMEPAD_TYPE_XBOXONE:                     return L"XboxOne";
        case SDL_GAMEPAD_TYPE_PS3:                          return L"PS3";
        case SDL_GAMEPAD_TYPE_PS4:                          return L"PS4";
        case SDL_GAMEPAD_TYPE_PS5:                          return L"PS5";
        case SDL_GAMEPAD_TYPE_NINTENDO_SWITCH_PRO:          return L"SwitchPro";
        case SDL_GAMEPAD_TYPE_NINTENDO_SWITCH_JOYCON_LEFT:  return L"JoyconLeft";
        case SDL_GAMEPAD_TYPE_NINTENDO_SWITCH_JOYCON_RIGHT: return L"JoyconRight";
        case SDL_GAMEPAD_TYPE_NINTENDO_SWITCH_JOYCON_PAIR:  return L"JoyconPair";
        case SDL_GAMEPAD_TYPE_GAMECUBE:                     return L"GameCube";
        case SDL_GAMEPAD_TYPE_STANDARD:                     return L"Standard";
        default:                                            return L"Unknown";
    }
}

void CGamepad::GetActivePadNameAndGuid(wchar_t* const pszOutName, const size_t iNameCap,
                                        wchar_t* const pszOutGuid, const size_t iGuidCap) const
{
    if (iNameCap > 0) pszOutName[0] = L'\0';
    if (iGuidCap > 0) pszOutGuid[0] = L'\0';

    SDL_Gamepad* const pPad = m_bInitialized ? GetActivePad() : nullptr;
    if (pPad == nullptr)
    {
        if (iNameCap > 0) WideFromNarrow("None", pszOutName, static_cast<int>(iNameCap));
        if (iGuidCap > 0) WideFromNarrow("none", pszOutGuid, static_cast<int>(iGuidCap));
        return;
    }

    if (iNameCap > 0)
    {
        const char* const pszName = SDL_GetGamepadName(pPad);
        WideFromNarrow(pszName ? pszName : "Unknown", pszOutName, static_cast<int>(iNameCap));
        pszOutName[iNameCap - 1] = L'\0'; //MultiByteToWideChar does not guarantee termination on truncation
    }

    if (iGuidCap > 0)
    {
        const SDL_GUID Guid = SDL_GetJoystickGUIDForID(m_iActivePadId);
        char szGuidUtf8[64] = {};
        SDL_GUIDToString(Guid, szGuidUtf8, static_cast<int>(sizeof(szGuidUtf8)));
        WideFromNarrow(szGuidUtf8, pszOutGuid, static_cast<int>(iGuidCap));
        pszOutGuid[iGuidCap - 1] = L'\0';
    }
}

void CGamepad::EmitButtonChanges(UEngine* const pEngine, UViewport* const pViewport, const std::uint32_t iNewButtons)
{
    const std::uint32_t iChanged = iNewButtons ^ m_iPrevButtons;
    if (iChanged == 0)
    {
        return;
    }
    for (size_t i = 0; i < m_ResolvedButtonKeys.size(); ++i)
    {
        const std::uint32_t iBit = 1u << i;
        if ((iChanged & iBit) == 0)
        {
            continue;
        }
        const EInputKey eKey = m_ResolvedButtonKeys[i];
        if (eKey != IK_None)
        {
            const EInputAction eAction = (iNewButtons & iBit) ? IST_Press : IST_Release;
            pEngine->InputEvent(pViewport, eKey, eAction, 0.0f);
        }
    }
    m_iPrevButtons = iNewButtons;
}

void CGamepad::ReleaseHeldButtons(UEngine* const pEngine, UViewport* const pViewport)
{
    if (m_iPrevButtons == 0)
    {
        return;
    }
    for (size_t i = 0; i < m_ResolvedButtonKeys.size(); ++i)
    {
        if ((m_iPrevButtons & (1u << i)) == 0)
        {
            continue;
        }
        const EInputKey eKey = m_ResolvedButtonKeys[i];
        if (eKey != IK_None)
        {
            pEngine->InputEvent(pViewport, eKey, IST_Release, 0.0f);
        }
    }
    m_iPrevButtons = 0;
}

static constexpr float kAxisRange = StickResponse::kAxisRange;

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

    const StickResponse::SAxes Out = StickResponse::Shape(iRawX, iRawY, iDeadzone, Curve, fScale);
    fOutX = Out.fX;
    fOutY = Out.fY;

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
    const float fOut = StickResponse::Trigger(iRaw, m_iTriggerThreshold);

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

void CGamepad::ReportUnsatisfiedJoyAxes(const int iNumAxes)
{
    SOpenPad* pActive = nullptr;
    for (SOpenPad& Pad : m_OpenPads)
    {
        if (Pad.iId == m_iActivePadId)
        {
            pActive = &Pad;
            break;
        }
    }
    if (!pActive || pActive->bLoggedMissingJoyAxis)
    {
        return;
    }

    //Collect first, log second: one line naming every index this pad can't
    //satisfy beats one line per entry, and the flag below means a pad only
    //ever produces this line once.
    wchar_t szIndices[128] = {};
    int     iWritten       = 0;
    for (const SAxisEntry& Entry : m_AxisMap)
    {
        if (Entry.eSource != EAxisSource::JoyAxis || Entry.iJoyAxis < iNumAxes)
        {
            continue;
        }
        const int iCap = static_cast<int>(ARRAY_COUNT(szIndices)) - iWritten;
        const int iN   = _snwprintf_s(szIndices + iWritten, iCap, _TRUNCATE,
                                      (iWritten == 0) ? L"%d" : L", %d", Entry.iJoyAxis);
        if (iN < 0)
        {
            break; //buffer full -- the line is already diagnostic enough
        }
        iWritten += iN;
    }
    if (iWritten == 0)
    {
        return; //this pad satisfies every joyaxis entry
    }

    GLog->Logf(L"Gamepad: [DXController.GamepadAxisMap] joyaxis.%s out of range -- pad %u reports %d axes; those entries stay silent.",
        szIndices, pActive->iId, iNumAxes);
    pActive->bLoggedMissingJoyAxis = true;
}

void CGamepad::EmitAxisMap(UEngine* const pEngine, UViewport* const pViewport,
                           SDL_Gamepad* const pPad, bool& bOutActivity)
{
    if (m_AxisMap.empty())
    {
        return;
    }

    //Read each source once per tick rather than once per entry: three gyro
    //axes bound to three slots is one sensor read, not three.
    float aGyro[3]  = { 0.0f, 0.0f, 0.0f };
    float aAccel[3] = { 0.0f, 0.0f, 0.0f };
    if (m_bWantGyro && !SDL_GetGamepadSensorData(pPad, SDL_SENSOR_GYRO, aGyro, 3))
    {
        aGyro[0] = aGyro[1] = aGyro[2] = 0.0f;
    }
    if (m_bWantAccel && !SDL_GetGamepadSensorData(pPad, SDL_SENSOR_ACCEL, aAccel, 3))
    {
        aAccel[0] = aAccel[1] = aAccel[2] = 0.0f;
    }

    //Touchpad 0, finger 0. A lifted finger reads as zero, so the generic
    //zero-edge below turns finger-up into the single 0.0 emit the contract
    //owes the engine.
    float fTouchX = 0.0f;
    float fTouchY = 0.0f;
    if (m_bWantTouchpad)
    {
        bool  bDown     = false;
        float fRawX     = 0.0f;
        float fRawY     = 0.0f;
        float fPressure = 0.0f;
        if (SDL_GetGamepadTouchpadFinger(pPad, 0, 0, &bDown, &fRawX, &fRawY, &fPressure) && bDown)
        {
            //SDL reports 0..1 with the origin at the upper left; re-center to
            //-1..1 and negate Y so up is positive, matching the sticks.
            fTouchX =   fRawX * 2.0f - 1.0f;
            fTouchY = -(fRawY * 2.0f - 1.0f);
        }
    }

    SDL_Joystick* const pJoystick = SDL_GetGamepadJoystick(pPad);
    const int           iNumAxes  = pJoystick ? SDL_GetNumJoystickAxes(pJoystick) : 0;

    //A joyaxis.N past this pad's axis count reads as zero below and would
    //otherwise stay silently inert. Diagnosed here rather than rejected at
    //load: axis counts are per-pad, and the map outlives any one pad. Logged
    //once per pad (they hotplug; a pad that can satisfy the entry says
    //nothing), naming every offending index in one line.
    ReportUnsatisfiedJoyAxes(iNumAxes);

    for (SAxisEntry& Entry : m_AxisMap)
    {
        float fSource = 0.0f;
        switch (Entry.eSource)
        {
        case EAxisSource::GyroPitch: fSource = aGyro[0];  break;
        case EAxisSource::GyroYaw:   fSource = aGyro[1];  break;
        case EAxisSource::GyroRoll:  fSource = aGyro[2];  break;
        case EAxisSource::AccelX:    fSource = aAccel[0]; break;
        case EAxisSource::AccelY:    fSource = aAccel[1]; break;
        case EAxisSource::AccelZ:    fSource = aAccel[2]; break;
        case EAxisSource::TouchpadX: fSource = fTouchX;   break;
        case EAxisSource::TouchpadY: fSource = fTouchY;   break;
        case EAxisSource::JoyAxis:
            if (Entry.iJoyAxis < iNumAxes)
            {
                fSource = static_cast<float>(SDL_GetJoystickAxis(pJoystick, Entry.iJoyAxis)) / 32767.0f;
            }
            break;
        }

        //out = clamp(deadzone(source) * Scale, -1000, 1000): the deadzone is
        //in the source's own units and applies before the scale (spec §5).
        if (std::fabs(fSource) < Entry.fDeadzone)
        {
            fSource = 0.0f;
        }
        float fOut = fSource * Entry.fScale;
        fOut = std::min(kAxisRange, std::max(-kAxisRange, fOut));

        if (fOut != 0.0f)
        {
            pEngine->InputEvent(pViewport, Entry.eKey, IST_Axis, fOut);
            if (!AxisMapParse::IsSensorSource(Entry.eSource))
            {
                bOutActivity = true;
            }
        }
        else if (Entry.fPrev != 0.0f)
        {
            pEngine->InputEvent(pViewport, Entry.eKey, IST_Axis, 0.0f);
        }
        Entry.fPrev = fOut;
    }
}

void CGamepad::FlushAxisMap(UEngine* const pEngine, UViewport* const pViewport)
{
    for (SAxisEntry& Entry : m_AxisMap)
    {
        if (Entry.fPrev != 0.0f)
        {
            pEngine->InputEvent(pViewport, Entry.eKey, IST_Axis, 0.0f);
            Entry.fPrev = 0.0f;
        }
    }
}

void CGamepad::ReleaseAll(UEngine* const pEngine, UViewport* const pViewport)
{
    ReleaseHeldButtons(pEngine, pViewport);
    FlushHeldAxes(pEngine, pViewport);
    FlushAxisMap(pEngine, pViewport);
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
                m_OpenPads.push_back({ Event.gdevice.which, pPad, false, false, false });
                ApplyPadSensors(m_OpenPads.back());
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
    //positions as the SDL_GamepadButton enum (the snapshot mask's index, see
    //Poll()). Structure only; nothing supplements today.
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
    for (size_t i = 0; i < m_ResolvedButtonKeys.size(); ++i)
    {
        if (m_ResolvedButtonKeys[i] == IK_None)
        {
            continue; //unmapped -- no destination to emit on, skip the SDL query too
        }
        if (SDL_GetGamepadButton(pPad, static_cast<SDL_GamepadButton>(i)))
        {
            iButtons |= (1u << i);
        }
    }
    iButtons |= SupplementalButtonMask(pPad);

    const int iLeftX      = StickResponse::ClampAxis(SDL_GetGamepadAxis(pPad, SDL_GAMEPAD_AXIS_LEFTX));
    const int iLeftY      = StickResponse::NegateY(SDL_GetGamepadAxis(pPad, SDL_GAMEPAD_AXIS_LEFTY));
    const int iRightX     = StickResponse::ClampAxis(SDL_GetGamepadAxis(pPad, SDL_GAMEPAD_AXIS_RIGHTX));
    const int iRightY     = StickResponse::NegateY(SDL_GetGamepadAxis(pPad, SDL_GAMEPAD_AXIS_RIGHTY));
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

    //InvertLookY negates the raw Y here rather than the emitted output: the
    //curve pipeline shapes magnitude (radially symmetric), so negating raw is
    //equivalent to negating the result, and it keeps fPrevRightStickY's
    //non-zero -> zero edge detection consistent with what EmitStickAxes just
    //emitted. iRightY is already clamped to [-32767, 32767] (NegateY),
    //so this negation cannot overflow.
    const int iRightYForEmit = m_bInvertLookY ? -iRightY : iRightY;
    EmitStickAxes(pEngine, pViewport,
                  iRightX, iRightYForEmit, m_iRightStickDeadzone,
                  m_RightStickCurve, m_fRightStickScale,
                  IK_JoyU, IK_JoyV,
                  m_fPrevRightStickX, m_fPrevRightStickY);
    m_fPrevLeftTrigger  = EmitTriggerAxis(pEngine, pViewport, iLeftTrig,  m_fPrevLeftTrigger,  IK_JoyZ);
    m_fPrevRightTrigger = EmitTriggerAxis(pEngine, pViewport, iRightTrig, m_fPrevRightTrigger, IK_JoyR);

    //Only the touchpad/joyaxis entries report activity here -- see EmitAxisMap.
    bool bAxisMapActivity = false;
    EmitAxisMap(pEngine, pViewport, pPad, bAxisMapActivity);

    const bool bPadActiveThisPoll =
        bAxisMapActivity ||
        iButtonsChanged != 0 ||
        m_fPrevLeftStickX  != 0.0f || m_fPrevLeftStickY  != 0.0f ||
        m_fPrevRightStickX != 0.0f || m_fPrevRightStickY != 0.0f ||
        m_fPrevLeftTrigger != 0.0f || m_fPrevRightTrigger != 0.0f;
    if (bPadActiveThisPoll)
    {
        PadActivity::NotePadActivity(m_Activity, GetTickCount64());
    }
}

bool CGamepad::IsPadActive() const
{
    return PadActivity::IsPadActive(m_Activity, GetTickCount64(), m_iPadActiveGraceMs);
}

bool CGamepad::IsMouseActive() const
{
    return PadActivity::IsMouseActive(m_Activity, GetTickCount64(), m_iPadActiveGraceMs);
}

void CGamepad::NotifyMouseActivity(const int iDeltaX, const int iDeltaY)
{
    PadActivity::NotifyMouseActivity(m_Activity, iDeltaX, iDeltaY, m_iMouseActivityPx, GetTickCount64());
}
