#pragma once

#include <cstddef>

// Pure formatting for the unhandled-exception filter's log lines. Everything
// here runs in a crashed process, so it touches no CRT formatting, allocates
// nothing, and writes only into a caller-supplied buffer (a static one at the
// call site). No syscalls, no engine headers - see development.md's
// pure-unit-layer entry.
namespace CrashRecord
{
    //Name for the exception codes worth naming; nullptr for anything else.
    const wchar_t* ExceptionName(const unsigned long ulExceptionCode);

    //"Crash: unhandled exception 0xC0000005 (EXCEPTION_ACCESS_VIOLATION) at 0x00401234"
    //Output is truncated to fit and always NUL-terminated (unless iOutChars is 0,
    //which writes nothing at all).
    void FormatException(const unsigned long ulExceptionCode, const void* const pFaultAddress, wchar_t* const pOut, const size_t iOutChars);

    //"Crash: faulting module <path> + 0x00001234", from GetModuleHandleEx /
    //GetModuleFileNameW results. A missing base, or one above the faulting
    //address, yields the "unknown" form; a missing path still reports the offset.
    void FormatModuleOffset(const void* const pFaultAddress, const void* const pModuleBase, const wchar_t* const pszModulePath, wchar_t* const pOut, const size_t iOutChars);
}
