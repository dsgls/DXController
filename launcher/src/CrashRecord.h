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

    //"Crash: exception 0xC0000005 (EXCEPTION_ACCESS_VIOLATION) at 0x00401234"
    //Output is truncated to fit and always NUL-terminated (unless iOutChars is 0,
    //which writes nothing at all).
    void FormatException(const unsigned long ulExceptionCode, const void* const pFaultAddress, wchar_t* const pOut, const size_t iOutChars);

    //"Crash: faulting module <path> + 0x00001234", from GetModuleHandleEx /
    //GetModuleFileNameW results. A missing base, or one above the faulting
    //address, yields the "unknown" form; a missing path still reports the offset.
    void FormatModuleOffset(const void* const pFaultAddress, const void* const pModuleBase, const wchar_t* const pszModulePath, wchar_t* const pOut, const size_t iOutChars);

    //"Crash: fault recorded first-chance on thread 1234, 15 ms before this report"
    //or "Crash: fault reached the unhandled-exception filter on thread 1234".
    void FormatOrigin(const bool bFirstChance, const unsigned long ulThreadId, const unsigned long long ullAgeMs, wchar_t* const pOut, const size_t iOutChars);

    //"Crash: map 'Name' (set 1234 ms ago); engine stage 'Loading X' (set 12 ms ago)".
    //An empty or null map/stage reads "map unknown" / "engine stage none".
    void FormatBreadcrumbs(const wchar_t* const pszMap, const unsigned long long ullMapAgeMs, const wchar_t* const pszStage, const unsigned long long ullStageAgeMs, wchar_t* const pOut, const size_t iOutChars);

    struct Registers
    {
        unsigned long ulEip, ulEsp, ulEbp, ulEax, ulEbx, ulEcx, ulEdx, ulEsi, ulEdi, ulEflags;
    };

    //"Crash: registers EIP=0x... ESP=0x... EBP=0x... EAX=0x... EBX=0x... ECX=0x... EDX=0x... ESI=0x... EDI=0x... EFLAGS=0x..."
    void FormatRegisters(const Registers& Regs, wchar_t* const pOut, const size_t iOutChars);

    //"Crash:   #03 0x10023456 Engine.dll+0x00023456 UGameEngine::Tick+0x1A6". The
    //module part is the path's file name only, "unknown" without a base; the
    //symbol part is omitted when pszSymbol is empty or null.
    void FormatFrame(const unsigned int uIndex, const void* const pPc, const void* const pModuleBase, const wchar_t* const pszModulePath, const wchar_t* const pszSymbol, const unsigned long long ullDisplacement, wchar_t* const pOut, const size_t iOutChars);
}
