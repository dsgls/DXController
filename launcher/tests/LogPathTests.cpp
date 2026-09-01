#include "doctest.h"
#include "LogPath.h"

#include <string>

namespace
{
    const wchar_t* const kszExeDir = L"C:\\Games\\DeusEx\\System";
    const wchar_t* const kszPackage = L"DeusEx";
}

TEST_CASE("LogPath defaults to exe dir + package + .log when no override is present")
{
    const LogPath::Result Res = LogPath::Parse(L"\"C:\\Games\\DeusEx\\System\\DeusEx.exe\" -something", kszExeDir, kszPackage);
    CHECK(Res.bFound);
    CHECK(std::wstring(Res.szPath) == L"C:\\Games\\DeusEx\\System\\DeusEx.log");
    CHECK(std::wstring(Res.szRotatedPath) == L"C:\\Games\\DeusEx\\System\\DeusEx.old.log");
}

TEST_CASE("LogPath honors a different package name for the default")
{
    const LogPath::Result Res = LogPath::Parse(L"DeusEx.exe", kszExeDir, L"MyMod");
    CHECK(Res.bFound);
    CHECK(std::wstring(Res.szPath) == L"C:\\Games\\DeusEx\\System\\MyMod.log");
    CHECK(std::wstring(Res.szRotatedPath) == L"C:\\Games\\DeusEx\\System\\MyMod.old.log");
}

TEST_CASE("LogPath joins exe dir cleanly whether or not it has a trailing separator")
{
    const LogPath::Result Res = LogPath::Parse(L"DeusEx.exe", L"C:\\Games\\DeusEx\\System\\", kszPackage);
    CHECK(Res.bFound);
    CHECK(std::wstring(Res.szPath) == L"C:\\Games\\DeusEx\\System\\DeusEx.log");
}

TEST_CASE("LogPath applies LOG= relative to the exe dir")
{
    const LogPath::Result Res = LogPath::Parse(L"DeusEx.exe LOG=custom.log", kszExeDir, kszPackage);
    CHECK(Res.bFound);
    CHECK(std::wstring(Res.szPath) == L"C:\\Games\\DeusEx\\System\\custom.log");
    CHECK(std::wstring(Res.szRotatedPath) == L"C:\\Games\\DeusEx\\System\\custom.old.log");
}

TEST_CASE("LogPath applies ABSLOG= as given, ignoring the exe dir")
{
    const LogPath::Result Res = LogPath::Parse(L"DeusEx.exe ABSLOG=D:\\Logs\\game.log", kszExeDir, kszPackage);
    CHECK(Res.bFound);
    CHECK(std::wstring(Res.szPath) == L"D:\\Logs\\game.log");
    CHECK(std::wstring(Res.szRotatedPath) == L"D:\\Logs\\game.old.log");
}

TEST_CASE("LogPath supports a quoted value with spaces")
{
    const LogPath::Result Res = LogPath::Parse(L"DeusEx.exe ABSLOG=\"D:\\Logs\\my game.log\"", kszExeDir, kszPackage);
    CHECK(Res.bFound);
    CHECK(std::wstring(Res.szPath) == L"D:\\Logs\\my game.log");
    CHECK(std::wstring(Res.szRotatedPath) == L"D:\\Logs\\my game.old.log");
}

TEST_CASE("LogPath replaces only the last extension for rotation")
{
    const LogPath::Result Res = LogPath::Parse(L"DeusEx.exe ABSLOG=D:\\Logs\\my.custom.log", kszExeDir, kszPackage);
    CHECK(Res.bFound);
    CHECK(std::wstring(Res.szRotatedPath) == L"D:\\Logs\\my.custom.old.log");
}

TEST_CASE("LogPath appends .old.log even when the override has no extension")
{
    const LogPath::Result Res = LogPath::Parse(L"DeusEx.exe ABSLOG=D:\\Logs\\noext", kszExeDir, kszPackage);
    CHECK(Res.bFound);
    CHECK(std::wstring(Res.szPath) == L"D:\\Logs\\noext");
    CHECK(std::wstring(Res.szRotatedPath) == L"D:\\Logs\\noext.old.log");
}

TEST_CASE("LogPath: LOG= wins over ABSLOG= from either position, as the engine does")
{
    const LogPath::Result First = LogPath::Parse(L"DeusEx.exe LOG=first.log ABSLOG=D:\\second.log", kszExeDir, kszPackage);
    CHECK(First.bFound);
    CHECK(std::wstring(First.szPath) == L"C:\\Games\\DeusEx\\System\\first.log");

    const LogPath::Result Second = LogPath::Parse(L"DeusEx.exe ABSLOG=D:\\second.log LOG=first.log", kszExeDir, kszPackage);
    CHECK(Second.bFound);
    CHECK(std::wstring(Second.szPath) == L"C:\\Games\\DeusEx\\System\\first.log");
}

TEST_CASE("LogPath accepts the documented -LOG= and -ABSLOG= switch forms")
{
    const LogPath::Result Rel = LogPath::Parse(L"DeusEx.exe -LOG=custom.log", kszExeDir, kszPackage);
    CHECK(Rel.bFound);
    CHECK(std::wstring(Rel.szPath) == L"C:\\Games\\DeusEx\\System\\custom.log");

    const LogPath::Result Abs = LogPath::Parse(L"DeusEx.exe -ABSLOG=D:\\Logs\\game.log", kszExeDir, kszPackage);
    CHECK(Abs.bFound);
    CHECK(std::wstring(Abs.szPath) == L"D:\\Logs\\game.log");
}

TEST_CASE("LogPath accepts a forward-slash switch prefix")
{
    const LogPath::Result Res = LogPath::Parse(L"DeusEx.exe /log=custom.log", kszExeDir, kszPackage);
    CHECK(Res.bFound);
    CHECK(std::wstring(Res.szPath) == L"C:\\Games\\DeusEx\\System\\custom.log");
}

TEST_CASE("LogPath matches the token case-insensitively")
{
    const LogPath::Result Lower = LogPath::Parse(L"DeusEx.exe log=custom.log", kszExeDir, kszPackage);
    CHECK(Lower.bFound);
    CHECK(std::wstring(Lower.szPath) == L"C:\\Games\\DeusEx\\System\\custom.log");

    const LogPath::Result Mixed = LogPath::Parse(L"DeusEx.exe -AbsLog=D:\\Logs\\game.log", kszExeDir, kszPackage);
    CHECK(Mixed.bFound);
    CHECK(std::wstring(Mixed.szPath) == L"D:\\Logs\\game.log");
}

TEST_CASE("LogPath strips a quoted argv[0] so LOG= inside it cannot false-positive")
{
    const LogPath::Result Res = LogPath::Parse(L"\"C:\\Games\\LOG=trap.exe\" LOG=real.log", kszExeDir, kszPackage);
    CHECK(Res.bFound);
    CHECK(std::wstring(Res.szPath) == L"C:\\Games\\DeusEx\\System\\real.log");
}

TEST_CASE("LogPath strips an unquoted argv[0] before searching")
{
    const LogPath::Result Res = LogPath::Parse(L"C:\\Games\\DeusEx.exe LOG=real.log", kszExeDir, kszPackage);
    CHECK(Res.bFound);
    CHECK(std::wstring(Res.szPath) == L"C:\\Games\\DeusEx\\System\\real.log");
}

TEST_CASE("LogPath does not false-positive on a flag that merely ends in LOG=")
{
    const LogPath::Result Res = LogPath::Parse(L"DeusEx.exe SOMELOG=trap.log", kszExeDir, kszPackage);
    CHECK(Res.bFound);
    CHECK(std::wstring(Res.szPath) == L"C:\\Games\\DeusEx\\System\\DeusEx.log");

    //The lead-in rule is "not alphanumeric", so a digit blocks the match too.
    const LogPath::Result Digit = LogPath::Parse(L"DeusEx.exe 2log=trap.log", kszExeDir, kszPackage);
    CHECK(Digit.bFound);
    CHECK(std::wstring(Digit.szPath) == L"C:\\Games\\DeusEx\\System\\DeusEx.log");
}

TEST_CASE("LogPath yields no rotation for an unterminated quote around argv[0]")
{
    const LogPath::Result Res = LogPath::Parse(L"\"C:\\Games\\DeusEx.exe LOG=real.log", kszExeDir, kszPackage);
    CHECK_FALSE(Res.bFound);
}

TEST_CASE("LogPath yields no rotation for an unterminated quote around a value")
{
    const LogPath::Result Res = LogPath::Parse(L"DeusEx.exe ABSLOG=\"D:\\Logs\\game.log", kszExeDir, kszPackage);
    CHECK_FALSE(Res.bFound);
}
