#include "doctest.h"
#include "LogTime.h"

#include <string>

namespace
{
    SYSTEMTIME Time(const WORD wHour, const WORD wMinute, const WORD wSecond, const WORD wMs)
    {
        SYSTEMTIME st = {};
        st.wHour = wHour;
        st.wMinute = wMinute;
        st.wSecond = wSecond;
        st.wMilliseconds = wMs;
        return st;
    }

    std::wstring FormatPrefix(const SYSTEMTIME& st)
    {
        wchar_t szOut[32] = L"poison";
        LogTime::FormatPrefix(st, szOut, _countof(szOut));
        return szOut;
    }
}

TEST_CASE("LogTime formats a fully zero-padded prefix")
{
    CHECK(FormatPrefix(Time(1, 2, 3, 4)) == L"[01:02:03.004] ");
}

TEST_CASE("LogTime formats the maximum field values")
{
    CHECK(FormatPrefix(Time(23, 59, 59, 999)) == L"[23:59:59.999] ");
}

TEST_CASE("LogTime formats midnight with no padding needed")
{
    CHECK(FormatPrefix(Time(0, 0, 0, 0)) == L"[00:00:00.000] ");
}

TEST_CASE("LogTime truncates into a short buffer and always terminates")
{
    wchar_t szShort[6] = {};
    szShort[5] = L'X'; //Sentinel: must end up as the terminator, never overrun
    LogTime::FormatPrefix(Time(12, 34, 56, 789), szShort, _countof(szShort));
    CHECK(std::wstring(szShort) == L"[12:3");
    CHECK(szShort[5] == L'\0');
}

TEST_CASE("LogTime writes nothing into a zero-length buffer")
{
    wchar_t szNone[1] = { L'X' };
    LogTime::FormatPrefix(Time(1, 2, 3, 4), szNone, 0);
    CHECK(szNone[0] == L'X');
}
