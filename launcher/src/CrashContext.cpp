#include "stdafx.h"
#pragma warning(push, 0)
#include <DbgHelp.h>
#pragma warning(pop)
#include "CrashRecord.h"
#include "CrashContext.h"

#pragma comment(lib, "dbghelp.lib")

#ifndef _M_IX86
#error The fault record reads the x86 CONTEXT layout (Eip/Esp/Ebp); port before building for another target.
#endif

namespace
{
    //Latest recorded fault. g_bHaveFault is cleared before and set after the
    //fields are written, so a report racing a fault on another thread sees
    //either the whole old record or the whole new one.
    EXCEPTION_RECORD g_Record = {};
    CONTEXT g_Context = {};
    DWORD g_dwFaultThread = 0;
    ULONGLONG g_ullFaultTick = 0;
    volatile bool g_bHaveFault = false;

    //The report walks memory the crash may have corrupted and can fault
    //itself; those faults must not replace the record being reported.
    volatile bool g_bReporting = false;

    //Top of the faulting stack, copied at first chance. The catch block that
    //eventually reports runs in a frame above the crashed ones, and its
    //callees (this file, DbgHelp) overwrite them, so the walk reads the
    //crashed frames from here instead of from live memory.
    BYTE g_StackSnapshot[16 * 1024];
    DWORD_PTR g_SnapshotBase = 0;
    size_t g_iSnapshotSize = 0;
    bool g_bUseSnapshot = false;

    wchar_t g_szMap[128] = {};
    wchar_t g_szStage[256] = {};
    ULONGLONG g_ullMapTick = 0;
    ULONGLONG g_ullStageTick = 0;

    LONG CALLBACK FirstChanceHandler(EXCEPTION_POINTERS* const pInfo)
    {
        if (g_bReporting || !pInfo || !pInfo->ExceptionRecord || !pInfo->ContextRecord)
        {
            return EXCEPTION_CONTINUE_SEARCH;
        }

        //Error-severity codes (0xC...) only: the guard chain's C++ rethrows
        //(0xE06D7363), breakpoints and guard-page hits pass through untouched.
        if ((pInfo->ExceptionRecord->ExceptionCode & 0xF0000000) != 0xC0000000)
        {
            return EXCEPTION_CONTINUE_SEARCH;
        }

        //Latest wins. Some DLLs raise and swallow their own faults as probes, so
        //the process's first fault is not reliably the fatal one; the one right
        //before the report is, and the report states its age so a reader can
        //tell.
        g_bHaveFault = false;
        g_Record = *pInfo->ExceptionRecord;
        g_Context = *pInfo->ContextRecord;
        g_dwFaultThread = GetCurrentThreadId();
        g_ullFaultTick = GetTickCount64();

        g_iSnapshotSize = 0;
        const DWORD_PTR iEsp = g_Context.Esp;
        const DWORD_PTR iStackTop = reinterpret_cast<DWORD_PTR>(reinterpret_cast<const NT_TIB*>(NtCurrentTeb())->StackBase); //The TEB starts with its NT_TIB; _TEB itself is opaque in winnt.h
        if (iStackTop > iEsp) //Everything between ESP and the stack top is committed and in use, so the copy cannot fault
        {
            const size_t iAvailable = static_cast<size_t>(iStackTop - iEsp);
            g_iSnapshotSize = iAvailable < sizeof(g_StackSnapshot) ? iAvailable : sizeof(g_StackSnapshot);
            memcpy(g_StackSnapshot, reinterpret_cast<const void*>(iEsp), g_iSnapshotSize);
            g_SnapshotBase = iEsp;
        }

        g_bHaveFault = true;
        return EXCEPTION_CONTINUE_SEARCH;
    }

    //StackWalk64's memory reader: the snapshot for the crashed frames, live
    //memory for everything else (heap-resident unwind data, other stacks).
    BOOL CALLBACK ReadStackMemory(HANDLE /*hProcess*/, DWORD64 ullAddress, PVOID pBuffer, DWORD dwSize, LPDWORD pdwRead)
    {
        if (g_bUseSnapshot && g_iSnapshotSize > 0 && ullAddress >= g_SnapshotBase && ullAddress + dwSize <= g_SnapshotBase + g_iSnapshotSize)
        {
            memcpy(pBuffer, g_StackSnapshot + (ullAddress - g_SnapshotBase), dwSize);
            *pdwRead = dwSize;
            return TRUE;
        }

        //ReadProcessMemory on our own process reports an unreadable address
        //instead of faulting on it.
        SIZE_T iRead = 0;
        const BOOL bOk = ReadProcessMemory(GetCurrentProcess(), reinterpret_cast<LPCVOID>(static_cast<DWORD_PTR>(ullAddress)), pBuffer, dwSize, &iRead);
        *pdwRead = static_cast<DWORD>(iRead);
        return bOk;
    }

    //One frame per line. Module resolution per frame takes the loader lock, as
    //the faulting-module line does; symbols come from PDBs next to the exe when
    //present, else from export tables, which already name most engine functions.
    void WalkStackBody(const CONTEXT& Context)
    {
        static CONTEXT Walk;
        Walk = Context; //StackWalk64 advances the context it is given

        static STACKFRAME64 Frame;
        ZeroMemory(&Frame, sizeof(Frame));
        Frame.AddrPC.Offset = Walk.Eip;
        Frame.AddrPC.Mode = AddrModeFlat;
        Frame.AddrFrame.Offset = Walk.Ebp;
        Frame.AddrFrame.Mode = AddrModeFlat;
        Frame.AddrStack.Offset = Walk.Esp;
        Frame.AddrStack.Mode = AddrModeFlat;

        const HANDLE hProcess = GetCurrentProcess();
        static wchar_t szSearchPath[MAX_PATH];
        szSearchPath[0] = L'\0';
        GetModuleFileNameW(NULL, szSearchPath, static_cast<DWORD>(_countof(szSearchPath)));
        szSearchPath[_countof(szSearchPath) - 1] = L'\0';
        PathRemoveFileSpec(szSearchPath);

        //An explicit search path: with _NT_SYMBOL_PATH set, the default would
        //spend the crash report waiting on a symbol server.
        SymSetOptions(SYMOPT_UNDNAME | SYMOPT_DEFERRED_LOADS | SYMOPT_FAIL_CRITICAL_ERRORS | SYMOPT_NO_PROMPTS);
        const bool bSymbols = SymInitializeW(hProcess, szSearchPath, TRUE) != FALSE;
        GLog->Log(NAME_Critical, bSymbols ? L"Crash: call stack (innermost first):" : L"Crash: call stack (innermost first; symbol engine unavailable):");

        static union { SYMBOL_INFOW Info; BYTE Bytes[sizeof(SYMBOL_INFOW) + 256 * sizeof(wchar_t)]; } Symbol;
        static wchar_t szLine[512];
        static wchar_t szModulePath[MAX_PATH];

        for (unsigned int uIndex = 0; uIndex < 48; ++uIndex)
        {
            if (!StackWalk64(IMAGE_FILE_MACHINE_I386, hProcess, GetCurrentThread(), &Frame, &Walk, ReadStackMemory, SymFunctionTableAccess64, SymGetModuleBase64, NULL)
                || Frame.AddrPC.Offset == 0)
            {
                break;
            }

            const void* const pPc = reinterpret_cast<const void*>(static_cast<DWORD_PTR>(Frame.AddrPC.Offset));

            HMODULE hModule = NULL;
            szModulePath[0] = L'\0';
            if (GetModuleHandleExW(GET_MODULE_HANDLE_EX_FLAG_FROM_ADDRESS | GET_MODULE_HANDLE_EX_FLAG_UNCHANGED_REFCOUNT, static_cast<LPCWSTR>(pPc), &hModule))
            {
                GetModuleFileNameW(hModule, szModulePath, static_cast<DWORD>(_countof(szModulePath)));
                szModulePath[_countof(szModulePath) - 1] = L'\0';
            }

            const wchar_t* pszSymbol = nullptr;
            DWORD64 ullDisplacement = 0;
            if (bSymbols)
            {
                Symbol.Info.SizeOfStruct = sizeof(SYMBOL_INFOW);
                Symbol.Info.MaxNameLen = 256;
                if (SymFromAddrW(hProcess, Frame.AddrPC.Offset, &ullDisplacement, &Symbol.Info))
                {
                    pszSymbol = Symbol.Info.Name;
                }
            }

            CrashRecord::FormatFrame(uIndex, pPc, hModule, szModulePath, pszSymbol, ullDisplacement, szLine, _countof(szLine));
            GLog->Log(NAME_Critical, szLine);
        }

        if (bSymbols)
        {
            SymCleanup(hProcess);
        }
    }

    //Kept free of C++ objects so __try is allowed; a walk through corrupted
    //memory is exactly the kind of thing that faults again.
    void WalkStackGuarded(const CONTEXT& Context)
    {
        __try
        {
            WalkStackBody(Context);
        }
        __except (EXCEPTION_EXECUTE_HANDLER)
        {
            GLog->Log(NAME_Critical, L"Crash: stack walk aborted by a secondary fault.");
        }
    }

    void SetBreadcrumb(wchar_t* const pszSlot, const size_t iSlotChars, ULONGLONG& ullTick, const wchar_t* const pszValue)
    {
        if (pszValue && *pszValue)
        {
            wcsncpy_s(pszSlot, iSlotChars, pszValue, _TRUNCATE);
            ullTick = GetTickCount64();
        }
        else
        {
            pszSlot[0] = L'\0';
            ullTick = 0;
        }
    }
}

void CrashContext::Install()
{
    AddVectoredExceptionHandler(1 /*first*/, FirstChanceHandler);
}

void CrashContext::SetMap(const wchar_t* const pszMap)
{
    SetBreadcrumb(g_szMap, _countof(g_szMap), g_ullMapTick, pszMap);
}

void CrashContext::SetStage(const wchar_t* const pszStage)
{
    SetBreadcrumb(g_szStage, _countof(g_szStage), g_ullStageTick, pszStage);
}

void CrashContext::LogReport(const EXCEPTION_POINTERS* const pLive)
{
    static LONG lEntered = 0;
    if (InterlockedExchange(&lEntered, 1) != 0)
    {
        return; //Both the main loop's catch and the unhandled filter can get here for one crash
    }
    g_bReporting = true;

    if (!GLog)
    {
        return;
    }

    static wchar_t szLine[512];
    const ULONGLONG ullNow = GetTickCount64();

    //Live pointers (unhandled filter) beat the record; the record is the
    //only source when the engine caught the fault itself. The snapshot is
    //trusted only when it belongs to the exception being reported.
    const EXCEPTION_RECORD* pRecord = nullptr;
    const CONTEXT* pContext = nullptr;
    bool bFirstChance = false;
    DWORD dwThread = 0;
    if (pLive && pLive->ExceptionRecord)
    {
        pRecord = pLive->ExceptionRecord;
        pContext = pLive->ContextRecord;
        dwThread = GetCurrentThreadId();
        g_bUseSnapshot = g_bHaveFault && g_Record.ExceptionAddress == pRecord->ExceptionAddress && g_Record.ExceptionCode == pRecord->ExceptionCode;
    }
    else if (g_bHaveFault)
    {
        pRecord = &g_Record;
        pContext = &g_Context;
        bFirstChance = true;
        dwThread = g_dwFaultThread;
        g_bUseSnapshot = true;
    }

    if (!pRecord)
    {
        GLog->Log(NAME_Critical, L"Crash: no hardware fault recorded; the error was raised by the engine (appError) or a C++ throw.");
    }
    else
    {
        CrashRecord::FormatOrigin(bFirstChance, dwThread, bFirstChance ? ullNow - g_ullFaultTick : 0, szLine, _countof(szLine));
        GLog->Log(NAME_Critical, szLine);
        CrashRecord::FormatException(pRecord->ExceptionCode, pRecord->ExceptionAddress, szLine, _countof(szLine));
        GLog->Log(NAME_Critical, szLine);
    }

    CrashRecord::FormatBreadcrumbs(g_szMap, g_ullMapTick ? ullNow - g_ullMapTick : 0, g_szStage, g_ullStageTick ? ullNow - g_ullStageTick : 0, szLine, _countof(szLine));
    GLog->Log(NAME_Critical, szLine);

    if (pContext)
    {
        const CrashRecord::Registers Regs = {
            pContext->Eip, pContext->Esp, pContext->Ebp,
            pContext->Eax, pContext->Ebx, pContext->Ecx, pContext->Edx, pContext->Esi, pContext->Edi,
            pContext->EFlags,
        };
        CrashRecord::FormatRegisters(Regs, szLine, _countof(szLine));
        GLog->Log(NAME_Critical, szLine);
    }

    //Log, not Logf: the history is up to 4096 chars and would overflow Core's
    //format buffer. Empty for a fault the guard chain never saw.
    GLog->Log(NAME_Critical, GErrorHist[0] ? GErrorHist : L"(GErrorHist empty)");

    //Loader-lock users from here on: a fault under that lock deadlocks these,
    //and everything above is already on disk by then.
    if (pRecord)
    {
        HMODULE hModule = NULL;
        static wchar_t szModulePath[MAX_PATH];
        szModulePath[0] = L'\0';
        if (GetModuleHandleExW(GET_MODULE_HANDLE_EX_FLAG_FROM_ADDRESS | GET_MODULE_HANDLE_EX_FLAG_UNCHANGED_REFCOUNT, static_cast<LPCWSTR>(pRecord->ExceptionAddress), &hModule))
        {
            GetModuleFileNameW(hModule, szModulePath, static_cast<DWORD>(_countof(szModulePath)));
            szModulePath[_countof(szModulePath) - 1] = L'\0'; //A path longer than the buffer truncates without terminating on XP
        }
        CrashRecord::FormatModuleOffset(pRecord->ExceptionAddress, hModule, szModulePath, szLine, _countof(szLine));
        GLog->Log(NAME_Critical, szLine);
    }

    if (pContext)
    {
        WalkStackGuarded(*pContext);
    }
}
