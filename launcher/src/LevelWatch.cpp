#include "stdafx.h"
#include "CrashContext.h"
#include "LevelWatch.h"

namespace
{
    const wchar_t* LevelActionName(const BYTE Action)
    {
        switch (Action)
        {
        case LEVACT_None:       return L"None";
        case LEVACT_Loading:    return L"Loading";
        case LEVACT_Saving:     return L"Saving";
        case LEVACT_Connecting: return L"Connecting";
        case LEVACT_Precaching: return L"Precaching";
        default:                return L"Unknown";
        }
    }
}

void CLevelWatch::Update(UEngine* const pEngine)
{
    UGameEngine* const pGameEngine = Cast<UGameEngine>(pEngine);
    ULevel* const pLevel = pGameEngine ? pGameEngine->GLevel : nullptr;

    if (pLevel != m_pLevel)
    {
        const ULONGLONG ullNow = GetTickCount64();
        wchar_t szMap[_countof(m_szMap)] = L"<none>";
        if (pLevel)
        {
            wcsncpy_s(szMap, *pLevel->URL.Map, _TRUNCATE);
        }

        GLog->Logf(L"Level: '%s' -> '%s' (%i actors, %.1f s since the previous change).",
            m_szMap[0] ? m_szMap : L"<none>", szMap,
            pLevel ? pLevel->Actors.Num() : 0,
            m_ullLastChangeTick ? (ullNow - m_ullLastChangeTick) / 1000.0 : 0.0);

        wcscpy_s(m_szMap, szMap);
        m_pLevel = pLevel;
        m_ullLastChangeTick = ullNow;
        CrashContext::SetMap(pLevel ? szMap : nullptr);
    }

    //Actors(0) is the LevelInfo; absent while a level is being built
    ALevelInfo* const pInfo = (pLevel && pLevel->Actors.Num() > 0) ? Cast<ALevelInfo>(pLevel->Actors(0)) : nullptr;
    if (!pInfo)
    {
        return;
    }

    if (pInfo->LevelAction != m_LevelAction)
    {
        GLog->Logf(L"Level: action %s -> %s.", LevelActionName(m_LevelAction), LevelActionName(pInfo->LevelAction));
        m_LevelAction = pInfo->LevelAction;
    }

    //Set a frame or more before the engine actually travels, so this is the
    //last line before a transition.
    if (wcsncmp(*pInfo->NextURL, m_szNextURL, _countof(m_szNextURL) - 1) != 0)
    {
        wcsncpy_s(m_szNextURL, *pInfo->NextURL, _TRUNCATE);
        if (m_szNextURL[0])
        {
            GLog->Logf(L"Level: travel queued to '%s' (in %.2f s, carry items: %s).", m_szNextURL, pInfo->NextSwitchCountdown, pInfo->bNextItems ? L"yes" : L"no");
        }
    }
}
