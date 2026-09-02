#include "doctest.h"
#include "AxisMapParse.h"

#include <algorithm>
#include <cstdlib>
#include <cwchar>
#include <string.h>
#include <string>

namespace
{
    using AxisMapParse::ESource;

    //Stand-in key space: 0 is "unmapped", 90..92 the reserved stick/trigger
    //slots. Slot names are spelled "key<N>" so the callback stays trivial.
    constexpr int kNone = 0;

    bool ParseKey(const wchar_t* const pszName, int* const piOutKey)
    {
        if (!pszName || pszName[0] == L'\0' || _wcsicmp(pszName, L"None") == 0)
        {
            *piOutKey = kNone;
            return true;
        }
        if (_wcsnicmp(pszName, L"key", 3) != 0)
        {
            return false;
        }
        wchar_t* pEnd = nullptr;
        const long iVal = wcstol(pszName + 3, &pEnd, 10);
        if (pEnd == pszName + 3 || !pEnd || *pEnd != L'\0')
        {
            return false;
        }
        *piOutKey = static_cast<int>(iVal);
        return true;
    }

    AxisMapParse::SValue Parse(const wchar_t* const pszValue)
    {
        return AxisMapParse::ParseValue(L"joyaxis.4", pszValue, kNone, ParseKey);
    }

    bool AnyLogContains(const AxisMapParse::SValue& V, const std::wstring& Needle)
    {
        return std::any_of(V.Log.begin(), V.Log.end(),
                           [&](const std::wstring& S) { return S.find(Needle) != std::wstring::npos; });
    }

    bool IsReserved(const int iKey) { return iKey >= 90 && iKey < 93; }
}

TEST_CASE("Sensor and touchpad source names parse case-insensitively")
{
    ESource eSource = ESource::JoyAxis;
    int     iAxis   = -1;
    CHECK(AxisMapParse::ParseSourceName(L"gyro.pitch", &eSource, &iAxis));
    CHECK(eSource == ESource::GyroPitch);
    CHECK(iAxis == 0);
    CHECK(AxisMapParse::ParseSourceName(L"ACCEL.Z", &eSource, &iAxis));
    CHECK(eSource == ESource::AccelZ);
    CHECK(AxisMapParse::ParseSourceName(L"Touchpad.Y", &eSource, &iAxis));
    CHECK(eSource == ESource::TouchpadY);

    CHECK_FALSE(AxisMapParse::ParseSourceName(L"gyro", &eSource, &iAxis));
    CHECK_FALSE(AxisMapParse::ParseSourceName(L"gyro.spin", &eSource, &iAxis));
    CHECK_FALSE(AxisMapParse::ParseSourceName(nullptr, &eSource, &iAxis));
}

TEST_CASE("joyaxis.N is bounded to [0, 64) and must be wholly numeric")
{
    ESource eSource = ESource::GyroPitch;
    int     iAxis   = -1;
    CHECK(AxisMapParse::ParseSourceName(L"joyaxis.0", &eSource, &iAxis));
    CHECK(eSource == ESource::JoyAxis);
    CHECK(iAxis == 0);
    CHECK(AxisMapParse::ParseSourceName(L"JoyAxis.63", &eSource, &iAxis));
    CHECK(iAxis == 63);

    CHECK_FALSE(AxisMapParse::ParseSourceName(L"joyaxis.64", &eSource, &iAxis));
    CHECK_FALSE(AxisMapParse::ParseSourceName(L"joyaxis.-1", &eSource, &iAxis));
    CHECK_FALSE(AxisMapParse::ParseSourceName(L"joyaxis.2x", &eSource, &iAxis));
    CHECK_FALSE(AxisMapParse::ParseSourceName(L"joyaxis.", &eSource, &iAxis));
}

TEST_CASE("Only gyro and accel sources are sensor sources")
{
    CHECK(AxisMapParse::IsSensorSource(ESource::GyroRoll));
    CHECK(AxisMapParse::IsSensorSource(ESource::AccelY));
    CHECK_FALSE(AxisMapParse::IsSensorSource(ESource::TouchpadX));
    CHECK_FALSE(AxisMapParse::IsSensorSource(ESource::JoyAxis));
}

TEST_CASE("Float parsing consumes the whole token or fails")
{
    float f = 0.0f;
    CHECK(AxisMapParse::ParseFloatToken(L"1.5", &f));
    CHECK(f == doctest::Approx(1.5));
    CHECK(AxisMapParse::ParseFloatToken(L"-2", &f));
    CHECK(f == doctest::Approx(-2.0));
    CHECK(AxisMapParse::ParseFloatToken(L"1e3", &f));
    CHECK(f == doctest::Approx(1000.0));

    CHECK_FALSE(AxisMapParse::ParseFloatToken(L"1e", &f));
    CHECK_FALSE(AxisMapParse::ParseFloatToken(L"12x", &f));
    CHECK_FALSE(AxisMapParse::ParseFloatToken(L"", &f));
    CHECK_FALSE(AxisMapParse::ParseFloatToken(L"abc", &f));
}

TEST_CASE("Curve tokens round-trip and unknown tokens keep the default")
{
    using StickResponse::ECurveType;
    for (const ECurveType eType : { ECurveType::Linear, ECurveType::Power, ECurveType::Expo, ECurveType::Sigmoid })
    {
        CHECK(AxisMapParse::ParseCurveType(AxisMapParse::CurveTypeToString(eType), ECurveType::Linear) == eType);
    }
    CHECK(AxisMapParse::ParseCurveType(L"sIgMoId", ECurveType::Linear) == ECurveType::Sigmoid);
    CHECK(AxisMapParse::ParseCurveType(L"Cubic", ECurveType::Expo) == ECurveType::Expo);
    CHECK(AxisMapParse::ParseCurveType(nullptr, ECurveType::Power) == ECurveType::Power);
}

TEST_CASE("A bare slot name takes the parameter defaults")
{
    const AxisMapParse::SValue V = Parse(L"key12");
    CHECK(V.bAccepted);
    CHECK(V.iKey == 12);
    CHECK(V.fScale == doctest::Approx(1000.0));
    CHECK(V.fDeadzone == doctest::Approx(0.0));
    CHECK(V.Log.empty());
}

TEST_CASE("Scale and Deadzone are read case-insensitively in any order")
{
    const AxisMapParse::SValue V = Parse(L"key12  deadzone=0.25\tSCALE=-40");
    CHECK(V.bAccepted);
    CHECK(V.fScale == doctest::Approx(-40.0));
    CHECK(V.fDeadzone == doctest::Approx(0.25));
    CHECK(V.Log.empty());
}

TEST_CASE("An unresolvable slot name rejects the line")
{
    const AxisMapParse::SValue V = Parse(L"NotAKey Scale=2");
    CHECK_FALSE(V.bAccepted);
    CHECK(AnyLogContains(V, L"does not name a known key"));
}

TEST_CASE("None and an empty value are accepted but inert")
{
    const AxisMapParse::SValue VNone = Parse(L"None");
    CHECK(VNone.bAccepted);
    CHECK(VNone.iKey == kNone);
    CHECK(VNone.Log.empty());

    const AxisMapParse::SValue VEmpty = Parse(L"");
    CHECK(VEmpty.bAccepted);
    CHECK(VEmpty.iKey == kNone);
}

TEST_CASE("An unknown parameter is logged and skipped without losing the line")
{
    const AxisMapParse::SValue V = Parse(L"key12 Curve=Expo Scale=2");
    CHECK(V.bAccepted);
    CHECK(V.fScale == doctest::Approx(2.0));
    CHECK(AnyLogContains(V, L"unknown parameter 'Curve=Expo'"));
}

TEST_CASE("An unparseable number keeps that parameter's default")
{
    const AxisMapParse::SValue V = Parse(L"key12 Scale=1e Deadzone=0.5");
    CHECK(V.bAccepted);
    CHECK(V.fScale == doctest::Approx(1000.0));
    CHECK(V.fDeadzone == doctest::Approx(0.5));
    CHECK(AnyLogContains(V, L"bad parameter 'Scale=1e'"));
}

TEST_CASE("A negative deadzone is rejected, a negative scale is not")
{
    const AxisMapParse::SValue VDz = Parse(L"key12 Deadzone=-0.1");
    CHECK(VDz.bAccepted);
    CHECK(VDz.fDeadzone == doctest::Approx(0.0));
    CHECK(AnyLogContains(VDz, L"bad parameter 'Deadzone=-0.1'"));

    const AxisMapParse::SValue VScale = Parse(L"key12 Scale=-0.1");
    CHECK(VScale.fScale == doctest::Approx(-0.1));
    CHECK(VScale.Log.empty());
}

TEST_CASE("A non-finite parameter drops the whole line")
{
    //1e400 overflows a double to infinity while staying a wholly consumed
    //token, so it reaches the finiteness check the way a hand-edited ini would.
    const AxisMapParse::SValue V = Parse(L"key12 Scale=1e400 Deadzone=0.5");
    CHECK_FALSE(V.bAccepted);
    CHECK(AnyLogContains(V, L"is not a finite number -- line ignored."));

    const AxisMapParse::SValue VNeg = Parse(L"key12 Scale=-1e400");
    CHECK_FALSE(VNeg.bAccepted);
}

TEST_CASE("Destination rejection runs reserved, then button map, then earlier axis entries")
{
    const std::vector<int> ButtonKeys { 1, 2, 3 };
    const std::vector<int> AxisKeys   { 7 };

    CHECK(AxisMapParse::CheckDestination(90, IsReserved, ButtonKeys, AxisKeys) == AxisMapParse::EDestStatus::Reserved);
    CHECK(AxisMapParse::CheckDestination(2,  IsReserved, ButtonKeys, AxisKeys) == AxisMapParse::EDestStatus::Taken);
    CHECK(AxisMapParse::CheckDestination(7,  IsReserved, ButtonKeys, AxisKeys) == AxisMapParse::EDestStatus::Taken);
    CHECK(AxisMapParse::CheckDestination(50, IsReserved, ButtonKeys, AxisKeys) == AxisMapParse::EDestStatus::Free);

    //Reserved wins over "already claimed by a button": the message the user
    //gets names the real reason.
    const std::vector<int> ReservedInButtons { 90 };
    CHECK(AxisMapParse::CheckDestination(90, IsReserved, ReservedInButtons, AxisKeys) == AxisMapParse::EDestStatus::Reserved);
}
