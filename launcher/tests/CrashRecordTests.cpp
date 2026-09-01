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
    CHECK(FormatException(0xC0000005ul, 0x00401234ul) == L"Crash: unhandled exception 0xC0000005 (EXCEPTION_ACCESS_VIOLATION) at 0x00401234");
    CHECK(FormatException(0xC00000FDul, 0x7C801234ul) == L"Crash: unhandled exception 0xC00000FD (EXCEPTION_STACK_OVERFLOW) at 0x7C801234");
}

TEST_CASE("CrashRecord omits the name for an unrecognized exception code")
{
    CHECK(FormatException(0x12345678ul, 0x00401234ul) == L"Crash: unhandled exception 0x12345678 at 0x00401234");
}

TEST_CASE("CrashRecord formats a null faulting address")
{
    CHECK(FormatException(0xC0000005ul, 0ul) == L"Crash: unhandled exception 0xC0000005 (EXCEPTION_ACCESS_VIOLATION) at 0x00000000");
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
    CHECK(std::wstring(szShort) == L"Crash: unhandle");
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
