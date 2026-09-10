#pragma once

//Logs level transitions from the main loop and feeds the current map to the
//crash report. The switch itself happens inside one Tick(), so this sees the
//level before and after; the queued-travel and level-action lines are what
//show up while the switch is still pending.
class CLevelWatch
{
public:
    void Update(UEngine* const pEngine); //Call once per frame, after Tick()

private:
    const void* m_pLevel = nullptr; //Identity only: the level can be garbage collected, so never dereferenced
    ULONGLONG m_ullLastChangeTick = 0;
    wchar_t m_szMap[128] = {};
    wchar_t m_szNextURL[256] = {};
    BYTE m_LevelAction = 0; //LEVACT_None
};
