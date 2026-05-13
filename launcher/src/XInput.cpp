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
    GConfig->GetInt(PROJECTNAME, L"XInputLeftStickDeadzone",  m_iLeftStickDeadzone);
    GConfig->GetInt(PROJECTNAME, L"XInputRightStickDeadzone", m_iRightStickDeadzone);
    GConfig->GetInt(PROJECTNAME, L"XInputTriggerThreshold",   m_iTriggerThreshold);
    GConfig->GetInt(PROJECTNAME, L"XInputMouseActivityPx",    m_iMouseActivityPx);
    GConfig->GetInt(PROJECTNAME, L"XInputPadActiveGraceMs",   m_iPadActiveGraceMs);
    GConfig->GetInt(PROJECTNAME, L"XInputHotplugScanMs",      m_iHotplugScanMs);
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

void CXInput::EmitStickAxes(UEngine* const pEngine, UViewport* const pViewport,
                            const SHORT iRawX, const SHORT iRawY, const int iDeadzone,
                            const EInputKey eKeyX, const EInputKey eKeyY,
                            float& fOutX, float& fOutY)
{
    //Convert SHORT to float in [-1, 1]. Use 32767.0f for both signs and clamp
    //to handle the -32768 case symmetrically.
    const float fX = std::max(-1.0f, static_cast<float>(iRawX) / 32767.0f);
    const float fY = std::max(-1.0f, static_cast<float>(iRawY) / 32767.0f);

    const float fMag = std::sqrt(fX * fX + fY * fY);
    const float fDz  = static_cast<float>(iDeadzone) / 32767.0f;

    if (fMag <= fDz || fMag <= 0.0f)
    {
        fOutX = 0.0f;
        fOutY = 0.0f;
    }
    else
    {
        const float fScale = (fMag - fDz) / (1.0f - fDz) / fMag;
        fOutX = std::min(1.0f, std::max(-1.0f, fX * fScale));
        fOutY = std::min(1.0f, std::max(-1.0f, fY * fScale));
    }

    if (fOutX != 0.0f)
    {
        pEngine->InputEvent(pViewport, eKeyX, IST_Axis, fOutX);
    }
    if (fOutY != 0.0f)
    {
        pEngine->InputEvent(pViewport, eKeyY, IST_Axis, fOutY);
    }
}

float CXInput::EmitTriggerAxis(UEngine* const pEngine, UViewport* const pViewport,
                               const BYTE iRaw, const EInputKey eKey)
{
    const float fValue = static_cast<float>(iRaw) / 255.0f;
    const float fT     = static_cast<float>(m_iTriggerThreshold) / 255.0f;

    float fOut;
    if (fValue <= fT)
    {
        fOut = 0.0f;
    }
    else
    {
        fOut = (fValue - fT) / (1.0f - fT);
        fOut = std::min(1.0f, fOut);
    }

    if (fOut != 0.0f)
    {
        pEngine->InputEvent(pViewport, eKey, IST_Axis, fOut);
    }
    return fOut;
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
                  IK_JoyX, IK_JoyY,
                  m_fPrevLeftStickX, m_fPrevLeftStickY);
    EmitStickAxes(pEngine, pViewport,
                  State.Gamepad.sThumbRX, State.Gamepad.sThumbRY, m_iRightStickDeadzone,
                  IK_JoyU, IK_JoyV,
                  m_fPrevRightStickX, m_fPrevRightStickY);
    m_fPrevLeftTrigger  = EmitTriggerAxis(pEngine, pViewport, State.Gamepad.bLeftTrigger,  IK_JoyZ);
    m_fPrevRightTrigger = EmitTriggerAxis(pEngine, pViewport, State.Gamepad.bRightTrigger, IK_JoyR);

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
