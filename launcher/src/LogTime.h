#pragma once

#pragma warning(push, 0)
#pragma warning(disable: 4324) //SDK structs padded by the launcher project's /Zp4
#include <windows.h>
#pragma warning(pop)

#include <cstddef>

// Pure formatting of the per-line log timestamp prefix. No CRT formatting
// (this path also runs while logging a crash) and no syscalls - see
// development.md's pure-unit-layer entry.
namespace LogTime
{
    //"[HH:MM:SS.mmm] ", zero-padded, fixed width. Output is truncated to fit
    //and always NUL-terminated (unless iOutChars is 0, which writes nothing).
    void FormatPrefix(const SYSTEMTIME& st, wchar_t* const pOut, const size_t iOutChars);
}
