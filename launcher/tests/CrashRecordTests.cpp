#include "doctest.h"
#include "CrashRecord.h"

#include <cstdlib>
#include <string>

namespace
{
    //The launcher is Win32 x86, so pointers format as 8 hex digits throughout.
    const void* Address(const unsigned long ulValue)
    {
        return reinterpret_cast<const void*>(static_cast<size_t>(ulValue));
    }

    std::wstring FormatException(const unsigned long ulCode, const unsigned long ulFault)
    {
        wchar_t szLine[512] = L"poison";
        CrashRecord::FormatException(ulCode, Address(ulFault), szLine, _countof(szLine));
        return szLine;
    }

    std::wstring FormatModuleOffset(const unsigned long ulFault, const unsigned long ulBase, const wchar_t* const pszPath)
    {
        wchar_t szLine[512] = L"poison";
        CrashRecord::FormatModuleOffset(Address(ulFault), Address(ulBase), pszPath, szLine, _countof(szLine));
        return szLine;
    }
}

TEST_CASE("CrashRecord names the exception codes worth naming")
{
    CHECK(FormatException(0xC0000005ul, 0x00401234ul) == L"Crash: exception 0xC0000005 (EXCEPTION_ACCESS_VIOLATION) at 0x00401234");
    CHECK(FormatException(0xC00000FDul, 0x7C801234ul) == L"Crash: exception 0xC00000FD (EXCEPTION_STACK_OVERFLOW) at 0x7C801234");
}

TEST_CASE("CrashRecord omits the name for an unrecognized exception code")
{
    CHECK(FormatException(0x12345678ul, 0x00401234ul) == L"Crash: exception 0x12345678 at 0x00401234");
}

TEST_CASE("CrashRecord formats a null faulting address")
{
    CHECK(FormatException(0xC0000005ul, 0ul) == L"Crash: exception 0xC0000005 (EXCEPTION_ACCESS_VIOLATION) at 0x00000000");
}

TEST_CASE("CrashRecord resolves the fault to a module and offset")
{
    CHECK(FormatModuleOffset(0x10401234ul, 0x10400000ul, L"C:\\Games\\DeusEx\\System\\Engine.dll") == L"Crash: faulting module C:\\Games\\DeusEx\\System\\Engine.dll + 0x00001234");
}

TEST_CASE("CrashRecord still reports the offset when the module path is unavailable")
{
    //GetModuleHandleEx can succeed where GetModuleFileNameW fails; the offset is
    //the useful half, so it is still logged.
    CHECK(FormatModuleOffset(0x10401234ul, 0x10400000ul, L"") == L"Crash: faulting module (unknown path) + 0x00001234");
    CHECK(FormatModuleOffset(0x10401234ul, 0x10400000ul, nullptr) == L"Crash: faulting module (unknown path) + 0x00001234");
}

TEST_CASE("CrashRecord reports an unknown module when the base is missing or above the fault")
{
    CHECK(FormatModuleOffset(0x00401234ul, 0ul, L"C:\\Games\\DeusEx.exe") == L"Crash: faulting module unknown (address 0x00401234)");
    CHECK(FormatModuleOffset(0x00401234ul, 0x10400000ul, L"C:\\Games\\DeusEx.exe") == L"Crash: faulting module unknown (address 0x00401234)");
}

TEST_CASE("CrashRecord truncates into a short buffer and always terminates")
{
    wchar_t szShort[16] = {};
    szShort[15] = L'X'; //Sentinel: the last cell must end up as the terminator, never overrun
    CrashRecord::FormatException(0xC0000005ul, Address(0x00401234ul), szShort, _countof(szShort));
    CHECK(std::wstring(szShort) == L"Crash: exceptio");
    CHECK(szShort[15] == L'\0');

    CrashRecord::FormatModuleOffset(Address(0x10401234ul), Address(0x10400000ul), L"C:\\Games\\DeusEx\\System\\Engine.dll", szShort, _countof(szShort));
    CHECK(std::wstring(szShort) == L"Crash: faulting");
    CHECK(szShort[15] == L'\0');
}

TEST_CASE("CrashRecord writes nothing into a zero-length buffer")
{
    wchar_t szNone[1] = { L'X' };
    CrashRecord::FormatException(0xC0000005ul, Address(0x00401234ul), szNone, 0);
    CrashRecord::FormatModuleOffset(Address(0x10401234ul), Address(0x10400000ul), L"m", szNone, 0);
    CHECK(szNone[0] == L'X');
}

TEST_CASE("CrashRecord describes where the fault record came from")
{
    wchar_t szLine[512] = L"poison";
    CrashRecord::FormatOrigin(true, 1234ul, 15ull, szLine, _countof(szLine));
    CHECK(std::wstring(szLine) == L"Crash: fault recorded first-chance on thread 1234, 15 ms before this report");
    CrashRecord::FormatOrigin(false, 1234ul, 0ull, szLine, _countof(szLine));
    CHECK(std::wstring(szLine) == L"Crash: fault reached the unhandled-exception filter on thread 1234");
}

TEST_CASE("CrashRecord formats the map and engine-stage breadcrumbs")
{
    wchar_t szLine[512] = L"poison";
    CrashRecord::FormatBreadcrumbs(L"02_NYC_BatteryPark", 120000ull, L"Loading DeusExCon.u", 12ull, szLine, _countof(szLine));
    CHECK(std::wstring(szLine) == L"Crash: map '02_NYC_BatteryPark' (set 120000 ms ago); engine stage 'Loading DeusExCon.u' (set 12 ms ago)");
    CrashRecord::FormatBreadcrumbs(L"", 0ull, nullptr, 0ull, szLine, _countof(szLine));
    CHECK(std::wstring(szLine) == L"Crash: map unknown; engine stage none");
}

TEST_CASE("CrashRecord formats the register dump on one line")
{
    const CrashRecord::Registers Regs = { 0x10023456ul, 0x0019F000ul, 0x0019F020ul, 1ul, 2ul, 3ul, 4ul, 5ul, 6ul, 0x246ul };
    wchar_t szLine[512] = L"poison";
    CrashRecord::FormatRegisters(Regs, szLine, _countof(szLine));
    CHECK(std::wstring(szLine) == L"Crash: registers EIP=0x10023456 ESP=0x0019F000 EBP=0x0019F020 EAX=0x00000001 EBX=0x00000002 ECX=0x00000003 EDX=0x00000004 ESI=0x00000005 EDI=0x00000006 EFLAGS=0x00000246");
}

TEST_CASE("CrashRecord formats a stack frame with module, offset and symbol")
{
    wchar_t szLine[512] = L"poison";
    CrashRecord::FormatFrame(3u, Address(0x10023456ul), Address(0x10000000ul), L"C:\\Games\\DeusEx\\System\\Engine.dll", L"UGameEngine::Tick", 0x1A6ull, szLine, _countof(szLine));
    CHECK(std::wstring(szLine) == L"Crash:   #03 0x10023456 Engine.dll+0x00023456 UGameEngine::Tick+0x1A6");
}

TEST_CASE("CrashRecord formats a stack frame without a symbol or module")
{
    wchar_t szLine[512] = L"poison";
    CrashRecord::FormatFrame(12u, Address(0x10023456ul), Address(0x10000000ul), L"Engine.dll", nullptr, 0ull, szLine, _countof(szLine));
    CHECK(std::wstring(szLine) == L"Crash:   #12 0x10023456 Engine.dll+0x00023456");
    CrashRecord::FormatFrame(0u, Address(0x00401234ul), nullptr, nullptr, L"", 0ull, szLine, _countof(szLine));
    CHECK(std::wstring(szLine) == L"Crash:   #00 0x00401234 unknown");
}
