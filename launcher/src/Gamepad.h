#pragma once

class UViewport;

class CGamepad
{
public:
    CGamepad();
    CGamepad(const CGamepad&) = delete;
    CGamepad& operator=(const CGamepad&) = delete;
    ~CGamepad();

    // New explicit init step, called from CLauncher's constructor after
    // pEngine->Init() and the viewport lookup -- SDL must not start before
    // then (see CGamepad()). Probes for the delay-loaded SDL3.dll, then
    // calls SDL_Init(SDL_INIT_GAMEPAD). On failure, logs once via GLog->Logf
    // and returns false, leaving m_bInitialized false; every other CGamepad
    // entry point is expected to no-op in that case.
    bool Init(UViewport* pViewport);

private:
    bool m_bInitialized;
};
