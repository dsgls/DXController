#include "stdafx.h"
#include "ConfigOverride.h"

CConfigOverride::CConfigOverride(const wchar_t* const pszSection, const wchar_t* const pszKey, const wchar_t* const pszValue, const wchar_t* const pszFilename)
:m_pszSection(pszSection)
,m_pszKey(pszKey)
,m_pszFilename(pszFilename)
,m_bWasPresent(false)
,m_bWasDirty(0)
{
    FConfigCacheIni* const pCache = static_cast<FConfigCacheIni*>(GConfig);
    FConfigFile* const pFile = pCache->Find(pszFilename, 1); //Force-load the file so Dirty is meaningful
    assert(pFile);
    m_bWasDirty = pFile->Dirty;

    wchar_t szOriginal[1024] = {};
    m_bWasPresent = GConfig->GetString(pszSection, pszKey, szOriginal, _countof(szOriginal), pszFilename) != 0;
    if (m_bWasPresent)
    {
        m_strOriginal = szOriginal;
    }

    GConfig->SetString(pszSection, pszKey, pszValue, pszFilename);
}

CConfigOverride::~CConfigOverride()
{
    if (m_bWasPresent)
    {
        GConfig->SetString(m_pszSection, m_pszKey, m_strOriginal.c_str(), m_pszFilename);
    }
    else
    {
        //Remove the key entirely so the on-disk file stays unchanged when Dirty is restored.
        FConfigCacheIni* const pCache = static_cast<FConfigCacheIni*>(GConfig);
        FConfigFile* const pFile = pCache->Find(m_pszFilename, 0);
        if (pFile)
        {
            FConfigSection* const pSec = pFile->Find(m_pszSection);
            if (pSec)
            {
                pSec->Remove(m_pszKey);
            }
        }
    }

    //Restore Dirty flag last; the SetString/Remove above will have set it.
    FConfigCacheIni* const pCache = static_cast<FConfigCacheIni*>(GConfig);
    FConfigFile* const pFile = pCache->Find(m_pszFilename, 0);
    if (pFile)
    {
        pFile->Dirty = m_bWasDirty;
    }
}
