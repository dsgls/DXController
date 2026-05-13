#pragma once

class UEngine;
class UViewport;

class CXInput
{
public:
    CXInput();
    CXInput(const CXInput&) = delete;
    CXInput& operator=(const CXInput&) = delete;

    // Called once per MainLoop iteration. Polls the active controller, diffs
    // against previous state, emits IST_Press/IST_Release/IST_Axis events.
    // No-op if pViewport is null. Synthesizes releases for any held buttons
    // when bHasFocus is false or the controller has disconnected, so the engine
    // never sees stuck inputs.
    void Poll(UEngine* pEngine, UViewport* pViewport, bool bHasFocus);

    // True if controller input crossed activity thresholds within the last
    // grace window AND no qualifying mouse activity has since occurred.
    bool IsPadActive() const;

    // Called by MainLoop from its WM_MOUSEMOVE branch with the client-relative
    // cursor position. Internally tracks previous position; if the delta
    // exceeds the configured pixel threshold, flips the active-source signal
    // back to mouse.
    void NotifyMouseActivity(int iX, int iY);

private:
    //Settings (read once in constructor)
    int m_iLeftStickDeadzone;       //SHORT magnitude, 0..32767
    int m_iRightStickDeadzone;      //SHORT magnitude, 0..32767
    int m_iTriggerThreshold;        //BYTE, 0..255
    int m_iMouseActivityPx;         //pixels
    int m_iPadActiveGraceMs;        //milliseconds
    int m_iHotplugScanMs;           //milliseconds

    //Runtime state
    DWORD m_iActiveSlot;        //(DWORD)-1 when not connected
    bool  m_bConnected;
    WORD  m_iPrevButtons;       //bitmask of XINPUT_GAMEPAD_* bits from last poll

    //Previous-frame post-deadzone stick values, in [-1, 1]. Used by packet
    //dedup (Task 7) to know whether axes need re-emission.
    float m_fPrevLeftStickX;
    float m_fPrevLeftStickY;
    float m_fPrevRightStickX;
    float m_fPrevRightStickY;
    float m_fPrevLeftTrigger;
    float m_fPrevRightTrigger;
    DWORD m_iPrevPacket;
    ULONGLONG m_iLastHotplugScanMs;
    ULONGLONG m_iLastPadActivityMs;
    ULONGLONG m_iLastMouseActivityMs;
    int       m_iPrevMouseX;
    int       m_iPrevMouseY;
    bool      m_bHasPrevMousePos;

    //Helpers
    void EmitButtonChanges(UEngine* pEngine, UViewport* pViewport, WORD iNewButtons);
    void ReleaseHeldButtons(UEngine* pEngine, UViewport* pViewport);

    //Emits IST_Axis on (eKeyX, eKeyY) after applying radial deadzone with the
    //given iDeadzone parameter (SHORT magnitude). Stores resulting values in
    //fOutX/fOutY (zero when inside the deadzone).
    void EmitStickAxes(UEngine* pEngine, UViewport* pViewport,
                       SHORT iRawX, SHORT iRawY, int iDeadzone,
                       EInputKey eKeyX, EInputKey eKeyY,
                       float& fOutX, float& fOutY);

    //Returns post-threshold value in [0, 1] and emits IST_Axis on eKey when
    //non-zero.
    float EmitTriggerAxis(UEngine* pEngine, UViewport* pViewport,
                          BYTE iRaw, EInputKey eKey);
};
