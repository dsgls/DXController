#include "doctest.h"
#include "ButtonMapResolve.h"

#include <algorithm>
#include <string>

namespace
{
    //A miniature key space standing in for EInputKey. 0 is "unmapped"; 90..92
    //stand in for the reserved stick/trigger slots the axis pipeline owns.
    constexpr int kNone     = 0;
    constexpr int kKeyCount = 100;

    bool IsReserved(const int iKey) { return iKey >= 90 && iKey < 93; }

    std::wstring NameOf(const int iButton) { return L"btn" + std::to_wstring(iButton); }

    //Builder for the four parallel per-button arrays. Buttons are numbered
    //0..N-1 in the same way SDL_GamepadButton values index the real map.
    struct Fixture
    {
        ButtonMapResolve::SParams Params;

        explicit Fixture(const std::vector<int>& Defaults)
        {
            Params.iKeyCount      = kKeyCount;
            Params.iNoneKey       = kNone;
            Params.Defaults       = Defaults;
            Params.HasOverride.assign(Defaults.size(), false);
            Params.OverrideKey.assign(Defaults.size(), kNone);
            Params.OverrideLine.assign(Defaults.size(), -1);
            Params.IsReservedDest = IsReserved;
            Params.ButtonName     = NameOf;
        }

        //An ini line "button = iKey" at file position iLine. A later line for
        //the same button simply overwrites, exactly as the shim's parse loop
        //leaves it.
        void Line(const size_t iButton, const int iKey, const int iLine)
        {
            Params.HasOverride[iButton]  = true;
            Params.OverrideKey[iButton]  = iKey;
            Params.OverrideLine[iButton] = iLine;
        }

        ButtonMapResolve::SResult Resolve() const { return ButtonMapResolve::Resolve(Params); }
    };

    bool AnyLogContains(const ButtonMapResolve::SResult& Res, const std::wstring& Needle)
    {
        return std::any_of(Res.Log.begin(), Res.Log.end(),
                           [&](const std::wstring& S) { return S.find(Needle) != std::wstring::npos; });
    }
}

TEST_CASE("An untouched default map resolves to itself and logs nothing")
{
    Fixture F({ 1, 2, 3, 4 });
    const ButtonMapResolve::SResult Res = F.Resolve();
    const std::vector<int> Expected { 1, 2, 3, 4 };
    CHECK(Res.Keys == Expected);
    CHECK(Res.Log.empty());
}

TEST_CASE("A two-line slot swap is legal")
{
    Fixture F({ 1, 2, 3, 4 });
    F.Line(0, 2, 0);
    F.Line(1, 1, 1);
    const ButtonMapResolve::SResult Res = F.Resolve();
    const std::vector<int> Expected { 2, 1, 3, 4 };
    CHECK(Res.Keys == Expected);
    CHECK(Res.Log.empty());
}

TEST_CASE("An untouched default beats an override that wants its slot")
{
    Fixture F({ 1, 2, 3, 4 });
    F.Line(1, 1, 0); //button 1 tries to take button 0's untouched default
    const ButtonMapResolve::SResult Res = F.Resolve();
    CHECK(Res.Keys[0] == 1);
    CHECK(Res.Keys[1] == 2); //reverted to its own default
    CHECK(AnyLogContains(Res, L"btn1's override duplicates"));
}

TEST_CASE("Among overrides the earliest line wins")
{
    Fixture F({ 1, 2, 3, 4 });
    F.Line(0, 50, 3);
    F.Line(1, 50, 1);
    const ButtonMapResolve::SResult Res = F.Resolve();
    CHECK(Res.Keys[1] == 50); //line 1 beats line 3
    CHECK(Res.Keys[0] == 1);  //loser falls back to its own default
    CHECK(AnyLogContains(Res, L"btn0's override duplicates"));
}

TEST_CASE("A later duplicate line for one button shadows the earlier one")
{
    //The shim's parse loop keeps only the last line per button; the resolver
    //sees exactly that, and the shadowed destination leaves no trace.
    Fixture F({ 1, 2, 3, 4 });
    F.Line(0, 50, 0);
    F.Line(0, 51, 1);
    const ButtonMapResolve::SResult Res = F.Resolve();
    CHECK(Res.Keys[0] == 51);
    CHECK(Res.Log.empty());
}

TEST_CASE("A reserved axis slot has no winner: every claimant loses it")
{
    Fixture F({ 1, 2, 3, 4 });
    F.Line(0, 90, 0);
    F.Line(1, 90, 1);
    const ButtonMapResolve::SResult Res = F.Resolve();
    CHECK(Res.Keys[0] == 1);
    CHECK(Res.Keys[1] == 2);
    CHECK(AnyLogContains(Res, L"btn0 targets a slot the axis pipeline already emits on"));
    CHECK(AnyLogContains(Res, L"btn1 targets a slot the axis pipeline already emits on"));
}

TEST_CASE("A default that is itself a reserved slot is dropped too")
{
    Fixture F({ 91, 2 });
    const ButtonMapResolve::SResult Res = F.Resolve();
    CHECK(Res.Keys[0] == kNone); //default reverts to itself, then to None
    CHECK(AnyLogContains(Res, L"btn0's default also collides"));
}

TEST_CASE("Each button spends exactly one fallback, then goes unmapped")
{
    //Buttons 1 and 2 both override onto button 0's untouched default, so both
    //revert; their own defaults collide with each other, so the later one
    //ends up unmapped rather than re-logging forever.
    Fixture F({ 1, 7, 7 });
    F.Line(1, 1, 0);
    F.Line(2, 1, 1);
    const ButtonMapResolve::SResult Res = F.Resolve();
    CHECK(Res.Keys[0] == 1);
    CHECK((Res.Keys[1] == 7) != (Res.Keys[2] == 7)); //exactly one keeps the shared default
    CHECK((Res.Keys[1] == kNone) != (Res.Keys[2] == kNone));
    CHECK(AnyLogContains(Res, L"default also collides"));
}

TEST_CASE("Resolution terminates when every button names the same destination")
{
    std::vector<int> Defaults(20);
    for (size_t i = 0; i < Defaults.size(); ++i)
    {
        Defaults[i] = static_cast<int>(i) + 1;
    }
    Fixture F(Defaults);
    for (size_t i = 0; i < Defaults.size(); ++i)
    {
        F.Line(i, 42, static_cast<int>(i));
    }
    const ButtonMapResolve::SResult Res = F.Resolve();
    //Earliest line keeps the contested slot; everything else falls back to its
    //own (distinct) default.
    CHECK(Res.Keys[0] == 42);
    for (size_t i = 1; i < Defaults.size(); ++i)
    {
        CHECK(Res.Keys[i] == Defaults[i]);
    }
}

TEST_CASE("Resolution terminates when every button also shares one default")
{
    Fixture F(std::vector<int>(16, 5));
    for (size_t i = 0; i < 16; ++i)
    {
        F.Line(i, 90, static_cast<int>(i)); //all onto a reserved slot
    }
    const ButtonMapResolve::SResult Res = F.Resolve();
    //One button keeps the shared default 5; the rest are unmapped.
    CHECK(std::count(Res.Keys.begin(), Res.Keys.end(), 5) == 1);
    CHECK(std::count(Res.Keys.begin(), Res.Keys.end(), kNone) == 15);
}

TEST_CASE("Unmapped buttons never contest each other")
{
    Fixture F({ kNone, kNone, kNone });
    const ButtonMapResolve::SResult Res = F.Resolve();
    const std::vector<int> Expected { kNone, kNone, kNone };
    CHECK(Res.Keys == Expected);
    CHECK(Res.Log.empty());
}
