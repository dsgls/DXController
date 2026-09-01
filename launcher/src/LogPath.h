#pragma once

//For MAX_PATH only. Pushed to warning level 0 the way stdafx.h does it: this
//header is also compiled into the test project, which builds at /W4 /WX.
#pragma warning(push, 0)
#pragma warning(disable: 4324) //SDK structs padded by the launcher project's /Zp4
#include <windows.h>
#pragma warning(pop)

// Pure parsing of the LOG=/ABSLOG= command-line overrides into the log file
// path FOutputDeviceFile will open, plus its rotated (".old.log") counterpart
// - so WinMain can rename the previous run's log before appInit's first
// Serialize() opens (and overwrites) a fresh one. Redirection
// (FFileManagerDeusExeUserDocs::ToModernFileName) is NOT applied here; the
// file manager is the single source of truth for that - see
// development.md's pure-unit-layer entry and the launcher-improvements
// design doc, section 3.2.
namespace LogPath
{
    struct Result
    {
        //False only when this parser's supported quoting subset can't make
        //sense of the command line (e.g. an unterminated quote) - callers
        //skip rotation for this launch rather than guess. True covers both
        //the default path (no override present) and a successfully parsed
        //LOG=/ABSLOG= override.
        bool bFound = false;
        wchar_t szPath[MAX_PATH] = {};
        wchar_t szRotatedPath[MAX_PATH] = {}; //szPath with its extension replaced by ".old.log"
    };

    //pszCommandLine: the raw command line, argv[0] included, as from
    //GetCommandLineW - argv[0] is stripped internally so a quoted exe path
    //containing "LOG=" can't false-positive.
    //pszExeDir: the executable's directory (trailing separator optional).
    //pszPackageName: exe basename without extension - used to build the
    //default "<package>.log" path when no override is present.
    Result Parse(const wchar_t* const pszCommandLine, const wchar_t* const pszExeDir, const wchar_t* const pszPackageName);
}
