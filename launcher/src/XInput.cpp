#include "stdafx.h"
#include "XInput.h"

#include <Xinput.h>

namespace
{
    struct ButtonMapEntry
    {
        WORD       iXInputBit;
        EInputKey  eKey;
    };

    //10 face/shoulder/stick/menu buttons -> IK_Joy1..IK_Joy10
    //4 D-pad directions -> IK_JoyPov*
    constexpr ButtonMapEntry kButtonMap[] =
    {
        { XINPUT_GAMEPAD_A,              IK_Joy1        },
        { XINPUT_GAMEPAD_B,              IK_Joy2        },
        { XINPUT_GAMEPAD_X,              IK_Joy3        },
        { XINPUT_GAMEPAD_Y,              IK_Joy4        },
        { XINPUT_GAMEPAD_LEFT_SHOULDER,  IK_Joy5        },
        { XINPUT_GAMEPAD_RIGHT_SHOULDER, IK_Joy6        },
        { XINPUT_GAMEPAD_BACK,           IK_Joy7        },
        { XINPUT_GAMEPAD_START,          IK_Joy8        },
        { XINPUT_GAMEPAD_LEFT_THUMB,     IK_Joy9        },
        { XINPUT_GAMEPAD_RIGHT_THUMB,    IK_Joy10       },
        { XINPUT_GAMEPAD_DPAD_UP,        IK_JoyPovUp    },
        { XINPUT_GAMEPAD_DPAD_DOWN,      IK_JoyPovDown  },
        { XINPUT_GAMEPAD_DPAD_LEFT,      IK_JoyPovLeft  },
        { XINPUT_GAMEPAD_DPAD_RIGHT,     IK_JoyPovRight },
    };

    //Case-insensitive parse of the curve-type INI token. Returns eDefault when
    //pszToken is null or doesn't match any of the four expected tokens.
    CXInput::EStickCurveType ParseStickCurveType(const wchar_t* const pszToken,
                                                 const CXInput::EStickCurveType eDefault)
    {
        if (!pszToken)
        {
            return eDefault;
        }
        if (_wcsicmp(pszToken, L"Linear")  == 0) return CXInput::EStickCurveType::Linear;
        if (_wcsicmp(pszToken, L"Power")   == 0) return CXInput::EStickCurveType::Power;
        if (_wcsicmp(pszToken, L"Expo")    == 0) return CXInput::EStickCurveType::Expo;
        if (_wcsicmp(pszToken, L"Sigmoid") == 0) return CXInput::EStickCurveType::Sigmoid;
        return eDefault;
    }

    //Pure: shape a normalized magnitude u (>= 0) into a shaped magnitude.
    //Endpoints pinned: returns 0 at u <= 0, ~1 at u = 1. Linear short-circuits.
    //May return > 1 for u > 1 (diagonal overflow); caller clamps final axes.
    float ShapeStickMagnitude(const float fU, const CXInput::SStickCurve& Curve)
    {
        if (fU <= 0.0f)
        {
            return 0.0f;
        }
        switch (Curve.eType)
        {
        case CXInput::EStickCurveType::Power:
            return std::pow(fU, Curve.fPower);

        case CXInput::EStickCurveType::Expo:
        {
            const float e = Curve.fExpo;
            return (1.0f - e) * fU + e * fU * fU * fU;
        }

        case CXInput::EStickCurveType::Sigmoid:
        {
            const float k  = Curve.fSigSteepness;
            const float c  = Curve.fSigMidpoint;
            const float w  = Curve.fSigStrength;
            const float lo = 1.0f / (1.0f + std::exp(  k * c));
            const float hi = 1.0f / (1.0f + std::exp(-k * (1.0f - c)));
            const float s  = (1.0f / (1.0f + std::exp(-k * (fU - c))) - lo) / (hi - lo);
            return (1.0f - w) * fU + w * s;
        }

        case CXInput::EStickCurveType::Linear:
        default:
            return fU;
        }
    }
}

CXInput::CXInput()
:m_iLeftStickDeadzone(2500),
 m_iRightStickDeadzone(2500),
 m_iTriggerThreshold(XINPUT_GAMEPAD_TRIGGER_THRESHOLD),
 m_iMouseActivityPx(4),
 m_iPadActiveGraceMs(500),
 m_iHotplugScanMs(1000),
 m_iActiveSlot(static_cast<DWORD>(-1)),
 m_bConnected(false),
 m_iPrevButtons(0),
 m_fPrevLeftStickX(0.0f),
 m_fPrevLeftStickY(0.0f),
 m_fPrevRightStickX(0.0f),
 m_fPrevRightStickY(0.0f),
 m_fPrevLeftTrigger(0.0f),
 m_fPrevRightTrigger(0.0f),
 m_iPrevPacket(0),
 m_iLastHotplugScanMs(0),
 m_iLastPadActivityMs(0),
 m_iLastMouseActivityMs(0),
 m_iPrevMouseX(0),
 m_iPrevMouseY(0),
 m_bHasPrevMousePos(false)
{
    assert(GConfig);
    GConfig->GetInt(L"DXController", L"StickDeadzoneLeft",  m_iLeftStickDeadzone);
    GConfig->GetInt(L"DXController", L"StickDeadzoneRight", m_iRightStickDeadzone);
    GConfig->GetInt(L"DXController", L"TriggerThreshold",   m_iTriggerThreshold);
    GConfig->GetInt(L"DXController", L"MouseActivityPx",    m_iMouseActivityPx);
    GConfig->GetInt(L"DXController", L"PadActiveGraceMs",   m_iPadActiveGraceMs);
    GConfig->GetInt(L"DXController", L"HotplugScanMs",      m_iHotplugScanMs);

    //Per-stick response curves. String token chosen so adding/removing curve
    //types in future never invalidates a hand-edited ini. Each numeric param is
    //clamped to guard against typos producing NaN/Inf in pow/exp.
    m_LeftStickCurve.eType  = ParseStickCurveType(GConfig->GetStr(L"DXController", L"StickCurveLeft"),  m_LeftStickCurve.eType);
    m_RightStickCurve.eType = ParseStickCurveType(GConfig->GetStr(L"DXController", L"StickCurveRight"), m_RightStickCurve.eType);

    GConfig->GetFloat(L"DXController", L"StickCurvePowerLeft",             m_LeftStickCurve.fPower);
    GConfig->GetFloat(L"DXController", L"StickCurvePowerRight",            m_RightStickCurve.fPower);
    GConfig->GetFloat(L"DXController", L"StickCurveExpoLeft",              m_LeftStickCurve.fExpo);
    GConfig->GetFloat(L"DXController", L"StickCurveExpoRight",             m_RightStickCurve.fExpo);
    GConfig->GetFloat(L"DXController", L"StickCurveSigmoidSteepnessLeft",  m_LeftStickCurve.fSigSteepness);
    GConfig->GetFloat(L"DXController", L"StickCurveSigmoidSteepnessRight", m_RightStickCurve.fSigSteepness);
    GConfig->GetFloat(L"DXController", L"StickCurveSigmoidMidpointLeft",   m_LeftStickCurve.fSigMidpoint);
    GConfig->GetFloat(L"DXController", L"StickCurveSigmoidMidpointRight",  m_RightStickCurve.fSigMidpoint);
    GConfig->GetFloat(L"DXController", L"StickCurveSigmoidStrengthLeft",   m_LeftStickCurve.fSigStrength);
    GConfig->GetFloat(L"DXController", L"StickCurveSigmoidStrengthRight",  m_RightStickCurve.fSigStrength);

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
}

void CXInput::EmitButtonChanges(UEngine* const pEngine, UViewport* const pViewport, const WORD iNewButtons)
{
    const WORD iChanged = static_cast<WORD>(iNewButtons ^ m_iPrevButtons);
    if (iChanged == 0)
    {
        return;
    }
    for (const ButtonMapEntry& Entry : kButtonMap)
    {
        if ((iChanged & Entry.iXInputBit) == 0)
        {
            continue;
        }
        const EInputAction eAction = (iNewButtons & Entry.iXInputBit) ? IST_Press : IST_Release;
        pEngine->InputEvent(pViewport, Entry.eKey, eAction, 0.0f);
    }
    m_iPrevButtons = iNewButtons;
}

void CXInput::ReleaseHeldButtons(UEngine* const pEngine, UViewport* const pViewport)
{
    if (m_iPrevButtons == 0)
    {
        return;
    }
    for (const ButtonMapEntry& Entry : kButtonMap)
    {
        if (m_iPrevButtons & Entry.iXInputBit)
        {
            pEngine->InputEvent(pViewport, Entry.eKey, IST_Release, 0.0f);
        }
    }
    m_iPrevButtons = 0;
}

//Stock Unreal WinDrv configures DirectInput joystick axes to -1000..1000 via
//DIPROP_RANGE; User.ini Speed= values are tuned for that magnitude. Emit in the
//same convention so existing bindings work without retuning.
static constexpr float kAxisRange = 1000.0f;

void CXInput::EmitStickAxes(UEngine* const pEngine, UViewport* const pViewport,
                            const SHORT iRawX, const SHORT iRawY, const int iDeadzone,
                            const SStickCurve& Curve,
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
        //post-deadzone magnitude. Direction preserved: a single combined
        //scale = out_axis_mag / raw_mag applied to raw X/Y yields
        //direction * out_axis_mag with no intermediate sqrt.
        const float fR      = (fU - fCDz) / (1.0f - fCDz);
        const float fS      = ShapeStickMagnitude(fR, Curve);
        const float fOutMag = fS * kAxisRange;
        const float fScale  = fOutMag / fRawMag;
        fOutX = std::min(kAxisRange, std::max(-kAxisRange, fXf * fScale));
        fOutY = std::min(kAxisRange, std::max(-kAxisRange, fYf * fScale));
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

float CXInput::EmitTriggerAxis(UEngine* const pEngine, UViewport* const pViewport,
                               const BYTE iRaw, const float fPrev, const EInputKey eKey)
{
    const int iT = m_iTriggerThreshold;

    float fOut;
    if (iRaw <= iT)
    {
        fOut = 0.0f;
    }
    else
    {
        //Linear remap (iT, 255] -> (0, kAxisRange]; same convention as sticks.
        fOut = static_cast<float>(iRaw - iT) * kAxisRange / static_cast<float>(255 - iT);
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

void CXInput::FlushHeldAxes(UEngine* const pEngine, UViewport* const pViewport)
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

void CXInput::Poll(UEngine* const pEngine, UViewport* const pViewport, const bool bHasFocus)
{
    if (!pViewport)
    {
        return;
    }
    if (!bHasFocus)
    {
        ReleaseHeldButtons(pEngine, pViewport);
        FlushHeldAxes(pEngine, pViewport);
        return;
    }
    if (!m_bConnected)
    {
        const ULONGLONG iNowMs = GetTickCount64();
        if (iNowMs - m_iLastHotplugScanMs < static_cast<ULONGLONG>(m_iHotplugScanMs))
        {
            return;
        }
        m_iLastHotplugScanMs = iNowMs;

        for (DWORD i = 0; i < XUSER_MAX_COUNT; ++i)
        {
            XINPUT_STATE Probe = {};
            if (XInputGetState(i, &Probe) == ERROR_SUCCESS)
            {
                m_iActiveSlot = i;
                m_bConnected = true;
                break;
            }
        }
        if (!m_bConnected)
        {
            return;
        }
    }

    XINPUT_STATE State = {};
    const DWORD iResult = XInputGetState(m_iActiveSlot, &State);
    if (iResult == ERROR_DEVICE_NOT_CONNECTED)
    {
        ReleaseHeldButtons(pEngine, pViewport);
        FlushHeldAxes(pEngine, pViewport);
        m_bConnected = false;
        m_iActiveSlot = static_cast<DWORD>(-1);
        return;
    }
    if (iResult != ERROR_SUCCESS)
    {
        return;
    }

    const bool bHadHeldAnalog =
        m_fPrevLeftStickX  != 0.0f || m_fPrevLeftStickY  != 0.0f ||
        m_fPrevRightStickX != 0.0f || m_fPrevRightStickY != 0.0f ||
        m_fPrevLeftTrigger != 0.0f || m_fPrevRightTrigger != 0.0f;

    if (State.dwPacketNumber == m_iPrevPacket && !bHadHeldAnalog)
    {
        return;
    }
    m_iPrevPacket = State.dwPacketNumber;

    const WORD iButtonsChanged = static_cast<WORD>(State.Gamepad.wButtons ^ m_iPrevButtons);

    EmitButtonChanges(pEngine, pViewport, State.Gamepad.wButtons);
    EmitStickAxes(pEngine, pViewport,
                  State.Gamepad.sThumbLX, State.Gamepad.sThumbLY, m_iLeftStickDeadzone,
                  m_LeftStickCurve,
                  IK_JoyX, IK_JoyY,
                  m_fPrevLeftStickX, m_fPrevLeftStickY);
    EmitStickAxes(pEngine, pViewport,
                  State.Gamepad.sThumbRX, State.Gamepad.sThumbRY, m_iRightStickDeadzone,
                  m_RightStickCurve,
                  IK_JoyU, IK_JoyV,
                  m_fPrevRightStickX, m_fPrevRightStickY);
    m_fPrevLeftTrigger  = EmitTriggerAxis(pEngine, pViewport, State.Gamepad.bLeftTrigger,  m_fPrevLeftTrigger,  IK_JoyZ);
    m_fPrevRightTrigger = EmitTriggerAxis(pEngine, pViewport, State.Gamepad.bRightTrigger, m_fPrevRightTrigger, IK_JoyR);

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

bool CXInput::IsPadActive() const
{
    const ULONGLONG iNowMs    = GetTickCount64();
    const ULONGLONG iGraceMs  = static_cast<ULONGLONG>(m_iPadActiveGraceMs);
    const bool bPadRecent     = m_iLastPadActivityMs   != 0 && (iNowMs - m_iLastPadActivityMs)   < iGraceMs;
    const bool bMouseRecent   = m_iLastMouseActivityMs != 0 && (iNowMs - m_iLastMouseActivityMs) < iGraceMs;
    return bPadRecent && !bMouseRecent;
}

void CXInput::NotifyMouseActivity(const int iX, const int iY)
{
    if (!m_bHasPrevMousePos)
    {
        m_iPrevMouseX     = iX;
        m_iPrevMouseY     = iY;
        m_bHasPrevMousePos = true;
        return;
    }
    const int iDx = iX - m_iPrevMouseX;
    const int iDy = iY - m_iPrevMouseY;
    const int iManhattan = (iDx < 0 ? -iDx : iDx) + (iDy < 0 ? -iDy : iDy);
    m_iPrevMouseX = iX;
    m_iPrevMouseY = iY;
    if (iManhattan > m_iMouseActivityPx)
    {
        m_iLastMouseActivityMs = GetTickCount64();
    }
}
