#pragma once

//First-chance fault capture plus the crash report built from it.
//
//The engine's VC6 guard chain catches a hardware fault as catch(...) and
//rethrows it as a C++ exception, so by the time the launcher's own catch or
//the unhandled-exception filter runs, the registers and the faulting frames
//are gone. A vectored handler sees every exception first: it snapshots the
//record, the thread context and the top of the stack, so the report can be
//written later from an ordinary (unwound) context. Everything here writes
//into static buffers and allocates nothing.
//
//Not a pure unit (Win32 + DbgHelp + GLog); the line formatting lives in
//CrashRecord.
namespace CrashContext
{
    //Installs the vectored handler. Call once, as early as possible; it does
    //not need GLog.
    void Install();

    //Breadcrumbs the report includes: the current map and the engine's last
    //slow-task status text. Null or empty clears.
    void SetMap(const wchar_t* const pszMap);
    void SetStage(const wchar_t* const pszStage);

    //Logs the report through GLog: origin, exception, breadcrumbs, registers,
    //GErrorHist, faulting module and a symbolised stack walk. pLive is the
    //unhandled filter's pointers, or null to report the recorded fault (or
    //its absence). Runs once per process; later calls return immediately. The
    //module lookups and the DbgHelp walk come last because they take the
    //loader lock.
    void LogReport(const EXCEPTION_POINTERS* const pLive);
}
