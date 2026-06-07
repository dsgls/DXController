#pragma once

// RAII override for a single GConfig key.
//
// On construction: snapshots the key's current value (present-or-absent) and
// the owning config file's Dirty flag, then writes the override value.
//
// On destruction: restores the key (writing the original value, or removing
// the key if it wasn't present) and writes the Dirty flag back to its
// pre-construction state. The Dirty restore is what keeps the user's ini
// untouched on disk: FConfigCacheIni::Flush() at shutdown skips files whose
// Dirty flag is clear, even if their in-memory contents were modified.
//
// All const wchar_t* arguments must outlive the instance. String literals and
// FString-backed buffers owned by GConfig satisfy this trivially.
class CConfigOverride
{
public:
    // pszFilename = nullptr targets System.ini (DeusEx.ini for stock DX).
    // Pass *static_cast<FConfigCacheIni*>(GConfig)->UserIni for User.ini.
    CConfigOverride(const wchar_t* pszSection, const wchar_t* pszKey, const wchar_t* pszValue, const wchar_t* pszFilename = nullptr);
    ~CConfigOverride();

    CConfigOverride(const CConfigOverride&) = delete;
    CConfigOverride& operator=(const CConfigOverride&) = delete;
    CConfigOverride(CConfigOverride&&) = delete;
    CConfigOverride& operator=(CConfigOverride&&) = delete;

private:
    const wchar_t* const m_pszSection;
    const wchar_t* const m_pszKey;
    const wchar_t* const m_pszFilename;
    std::wstring m_strOriginal;
    bool m_bWasPresent;
    UBOOL m_bWasDirty;
};
