#include "LogPath.h"

namespace
{
    bool IsSpace(const wchar_t ch)
    {
        return ch == L' ' || ch == L'\t';
    }

    size_t Length(const wchar_t* const psz)
    {
        size_t iLen = 0;
        while (psz && psz[iLen])
        {
            ++iLen;
        }
        return iLen;
    }

    //Truncate-don't-overrun copy of iLen characters from pSrc, always
    //NUL-terminated (unless iCapacity is 0, which writes nothing).
    void CopyTruncate(wchar_t* const pOut, const size_t iCapacity, const wchar_t* const pSrc, const size_t iLen)
    {
        if (iCapacity == 0)
        {
            return;
        }
        const size_t iCount = (iLen < iCapacity - 1) ? iLen : iCapacity - 1;
        for (size_t i = 0; i < iCount; ++i)
        {
            pOut[i] = pSrc[i];
        }
        pOut[iCount] = L'\0';
    }

    //Finds where argv[0] ends and the argument region begins. Returns
    //nullptr if argv[0]'s quoting can't be resolved (an opened, never
    //closed, quote) - the "exotic quoting" bail-out.
    const wchar_t* SkipArgv0(const wchar_t* pCmdLine)
    {
        const wchar_t* p = pCmdLine;
        while (IsSpace(*p))
        {
            ++p;
        }

        if (*p == L'"')
        {
            ++p;
            while (*p && *p != L'"')
            {
                ++p;
            }
            if (*p != L'"')
            {
                return nullptr; //Unterminated quote
            }
            ++p;
        }
        else
        {
            while (*p && !IsSpace(*p))
            {
                ++p;
            }
        }

        while (IsSpace(*p))
        {
            ++p;
        }
        return p;
    }

    bool IsAlnum(const wchar_t ch)
    {
        return (ch >= L'A' && ch <= L'Z') || (ch >= L'a' && ch <= L'z') || (ch >= L'0' && ch <= L'9');
    }

    wchar_t ToUpperAscii(const wchar_t ch)
    {
        return (ch >= L'a' && ch <= L'z') ? static_cast<wchar_t>(ch - L'a' + L'A') : ch;
    }

    //Case-insensitive match of pszToken at pAt. Returns a pointer just past the
    //token on success, else nullptr.
    const wchar_t* MatchToken(const wchar_t* const pAt, const wchar_t* const pszToken)
    {
        const size_t iTokenLen = Length(pszToken);
        for (size_t i = 0; i < iTokenLen; ++i)
        {
            if (ToUpperAscii(pAt[i]) != ToUpperAscii(pszToken[i]))
            {
                return nullptr;
            }
        }
        return pAt + iTokenLen;
    }

    //Finds pszToken the way the engine's appStrfind does: case-insensitive, and
    //only where the preceding character is non-alphanumeric (or there is none).
    //That is what makes "-LOG=", "/log=" and a bare "LOG=" all match while
    //"SOMELOG=" does not. Returns a pointer to the value, else nullptr.
    const wchar_t* FindToken(const wchar_t* const pArgs, const wchar_t* const pszToken)
    {
        bool bPrevAlnum = false;
        for (const wchar_t* p = pArgs; *p; ++p)
        {
            if (!bPrevAlnum)
            {
                if (const wchar_t* const pAfter = MatchToken(p, pszToken))
                {
                    return pAfter;
                }
            }
            bPrevAlnum = IsAlnum(*p);
        }
        return nullptr;
    }

    //Reads a LOG=/ABSLOG= value: quoted (up to the closing quote) or
    //unquoted (up to whitespace/end). False - exotic - if a quote is opened
    //but never closed.
    bool ReadValue(const wchar_t* pValue, wchar_t* const pOut, const size_t iOutCapacity)
    {
        if (*pValue == L'"')
        {
            ++pValue;
            const wchar_t* const pStart = pValue;
            while (*pValue && *pValue != L'"')
            {
                ++pValue;
            }
            if (*pValue != L'"')
            {
                return false;
            }
            CopyTruncate(pOut, iOutCapacity, pStart, pValue - pStart);
            return true;
        }

        const wchar_t* const pStart = pValue;
        while (*pValue && !IsSpace(*pValue))
        {
            ++pValue;
        }
        CopyTruncate(pOut, iOutCapacity, pStart, pValue - pStart);
        return true;
    }

    //Joins a directory and a filename with exactly one separator between them.
    void JoinPath(wchar_t* const pOut, const size_t iOutCapacity, const wchar_t* const pszDir, const wchar_t* const pszName)
    {
        const size_t iDirLen = Length(pszDir);
        CopyTruncate(pOut, iOutCapacity, pszDir, iDirLen);

        size_t iLen = Length(pOut);
        const bool bNeedsSep = iDirLen > 0 && pOut[iLen - 1] != L'\\' && pOut[iLen - 1] != L'/';
        if (bNeedsSep && iLen + 1 < iOutCapacity)
        {
            pOut[iLen++] = L'\\';
            pOut[iLen] = L'\0';
        }

        const size_t iRemaining = (iLen < iOutCapacity) ? iOutCapacity - iLen : 0;
        CopyTruncate(pOut + iLen, iRemaining, pszName, Length(pszName));
    }

    //Same path with its extension - the part after the last '.' following
    //the last path separator, if any - replaced by ".old.log".
    void RotatedPath(wchar_t* const pOut, const size_t iOutCapacity, const wchar_t* const pszPath)
    {
        const size_t iLen = Length(pszPath);
        size_t iLastDot = iLen;
        bool bHasDot = false;
        for (size_t i = 0; i < iLen; ++i)
        {
            if (pszPath[i] == L'\\' || pszPath[i] == L'/')
            {
                bHasDot = false; //Dots before the last separator don't count
            }
            else if (pszPath[i] == L'.')
            {
                iLastDot = i;
                bHasDot = true;
            }
        }

        const size_t iBaseLen = bHasDot ? iLastDot : iLen;
        CopyTruncate(pOut, iOutCapacity, pszPath, iBaseLen);

        const size_t iWritten = Length(pOut);
        const wchar_t* const pszSuffix = L".old.log";
        const size_t iRemaining = (iWritten < iOutCapacity) ? iOutCapacity - iWritten : 0;
        CopyTruncate(pOut + iWritten, iRemaining, pszSuffix, Length(pszSuffix));
    }
}

LogPath::Result LogPath::Parse(const wchar_t* const pszCommandLine, const wchar_t* const pszExeDir, const wchar_t* const pszPackageName)
{
    Result Res;

    if (!pszCommandLine || !pszExeDir || !pszPackageName)
    {
        return Res;
    }

    const wchar_t* const pArgs = SkipArgv0(pszCommandLine);
    if (!pArgs)
    {
        return Res; //Exotic argv[0] quoting
    }

    //Engine precedence (FOutputDeviceFile.h): LOG= is looked up first and wins
    //wherever it appears; ABSLOG= is consulted only when there is no LOG=.
    //"ABSLOG=" cannot be mistaken for "LOG=" because the 'S' in front of it is
    //alphanumeric, which the lead-in rule rejects.
    bool bAbsolute = false;
    const wchar_t* pValue = FindToken(pArgs, L"LOG=");
    if (!pValue)
    {
        pValue = FindToken(pArgs, L"ABSLOG=");
        bAbsolute = pValue != nullptr;
    }

    if (pValue)
    {
        wchar_t szValue[MAX_PATH] = {};
        if (!ReadValue(pValue, szValue, MAX_PATH))
        {
            return Res; //Exotic value quoting
        }

        if (bAbsolute)
        {
            CopyTruncate(Res.szPath, MAX_PATH, szValue, Length(szValue));
        }
        else
        {
            JoinPath(Res.szPath, MAX_PATH, pszExeDir, szValue);
        }
    }
    else
    {
        wchar_t szDefaultName[MAX_PATH] = {};
        const size_t iPkgLen = Length(pszPackageName);
        CopyTruncate(szDefaultName, MAX_PATH, pszPackageName, iPkgLen);
        const size_t iLen = Length(szDefaultName);
        const wchar_t* const pszExt = L".log";
        const size_t iRemaining = (iLen < MAX_PATH) ? MAX_PATH - iLen : 0;
        CopyTruncate(szDefaultName + iLen, iRemaining, pszExt, Length(pszExt));

        JoinPath(Res.szPath, MAX_PATH, pszExeDir, szDefaultName);
    }

    RotatedPath(Res.szRotatedPath, MAX_PATH, Res.szPath);
    Res.bFound = true;
    return Res;
}
