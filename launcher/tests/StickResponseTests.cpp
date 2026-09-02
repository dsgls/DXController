#include "doctest.h"
#include "StickResponse.h"

#include <cmath>
#include <initializer_list>

namespace
{
    using StickResponse::ECurveType;
    using StickResponse::SCurve;

    constexpr SCurve kLinear  { ECurveType::Linear,  2.0f, 0.60f, 6.0f, 0.60f, 0.60f };
    constexpr SCurve kPower   { ECurveType::Power,   2.0f, 0.60f, 6.0f, 0.60f, 0.60f };
    constexpr SCurve kExpo    { ECurveType::Expo,    2.0f, 0.60f, 6.0f, 0.60f, 0.60f };
    constexpr SCurve kSigmoid { ECurveType::Sigmoid, 2.0f, 0.60f, 8.0f, 0.70f, 0.90f };

    //Approx tolerant enough for float pipelines whose expected values are
    //derived in double here.
    doctest::Approx Near(const double d) { return doctest::Approx(d).epsilon(0.001); }
}

TEST_CASE("ClampAxis normalizes SDL's asymmetric -32768 and leaves everything else")
{
    CHECK(StickResponse::ClampAxis(-32768) == -32767);
    CHECK(StickResponse::ClampAxis(-32767) == -32767);
    CHECK(StickResponse::ClampAxis(-1)     == -1);
    CHECK(StickResponse::ClampAxis(32767)  == 32767);
    CHECK(StickResponse::NegateY(-32768)   == 32767);
    CHECK(StickResponse::NegateY(1000)     == -1000);
}

TEST_CASE("Linear curve is the identity on magnitude")
{
    for (const float fU : { 0.0f, 0.25f, 0.5f, 0.75f, 1.0f })
    {
        CHECK(StickResponse::ShapeMagnitude(fU, kLinear) == Near(fU));
    }
}

TEST_CASE("Every curve pins both endpoints")
{
    for (const SCurve& Curve : { kLinear, kPower, kExpo, kSigmoid })
    {
        CHECK(StickResponse::ShapeMagnitude(0.0f, Curve) == Near(0.0));
        CHECK(StickResponse::ShapeMagnitude(1.0f, Curve) == Near(1.0));
    }
}

TEST_CASE("Every curve is monotonic in magnitude")
{
    for (const SCurve& Curve : { kLinear, kPower, kExpo, kSigmoid })
    {
        float fPrev = -1.0f;
        for (int i = 0; i <= 100; ++i)
        {
            const float fOut = StickResponse::ShapeMagnitude(static_cast<float>(i) / 100.0f, Curve);
            CHECK(fOut >= fPrev);
            fPrev = fOut;
        }
    }
}

TEST_CASE("A centred stick emits nothing and full deflection emits scale * 1000")
{
    CHECK(StickResponse::Shape(0, 0, 0, kLinear, 1.0f).fX == Near(0.0));
    CHECK(StickResponse::Shape(0, 0, 3500, kLinear, 1.0f).fY == Near(0.0));

    CHECK(StickResponse::Shape(32767, 0, 0, kLinear, 1.0f).fX == Near(1000.0));
    CHECK(StickResponse::Shape(0, 32767, 0, kLinear, 0.6f).fY == Near(600.0));
    CHECK(StickResponse::Shape(0, -32767, 0, kLinear, 1.0f).fY == Near(-1000.0));
}

TEST_CASE("The deadzone is radial, not per-axis")
{
    //Each axis alone is well inside the deadzone; the vector is not, so the
    //sample survives. A per-axis deadzone would zero it.
    const StickResponse::SAxes Out = StickResponse::Shape(12000, 12000, 16384, kLinear, 1.0f);
    CHECK(Out.fX > 0.0f);
    CHECK(Out.fY > 0.0f);

    //Same magnitude split unevenly stays inside the deadzone in both cases.
    CHECK(StickResponse::Shape(11000, 0, 16384, kLinear, 1.0f).fX == Near(0.0));
    CHECK(StickResponse::Shape(0, 11000, 16384, kLinear, 1.0f).fY == Near(0.0));
}

TEST_CASE("Deadzone remap starts the output at zero just past the edge")
{
    CHECK(StickResponse::Shape(3500, 0, 3500, kLinear, 1.0f).fX == Near(0.0));
    CHECK(StickResponse::Shape(3501, 0, 3500, kLinear, 1.0f).fX > 0.0f);
    CHECK(StickResponse::Shape(3501, 0, 3500, kLinear, 1.0f).fX < 1.0f);
}

TEST_CASE("Each output axis is clamped to +/-1000 on diagonals")
{
    //A full diagonal has raw magnitude ~46340, so the output *vector*
    //magnitude reaches ~1414 by design -- the clamp is per axis.
    for (const SCurve& Curve : { kLinear, kPower, kExpo, kSigmoid })
    {
        for (const int iSignX : { -1, 1 })
        {
            for (const int iSignY : { -1, 1 })
            {
                const StickResponse::SAxes Out =
                    StickResponse::Shape(iSignX * 32767, iSignY * 32767, 3500, Curve, 1.0f);
                CHECK(std::fabs(Out.fX) <= 1000.0f);
                CHECK(std::fabs(Out.fY) <= 1000.0f);
            }
        }
    }

    //Power 2 overshoots hard enough on a full diagonal that the clamp is what
    //produces the result.
    const StickResponse::SAxes Out = StickResponse::Shape(32767, 32767, 0, kPower, 1.0f);
    CHECK(Out.fX == Near(1000.0));
    CHECK(Out.fY == Near(1000.0));
}

TEST_CASE("Shape is symmetric under negation -- the property InvertLookY relies on")
{
    const int aSamples[][2] = { { 1, 0 }, { 12000, 5000 }, { 32767, 32767 }, { 3000, 3000 }, { 20000, -9000 } };
    for (const SCurve& Curve : { kLinear, kPower, kExpo, kSigmoid })
    {
        for (const auto& Sample : aSamples)
        {
            const StickResponse::SAxes Pos = StickResponse::Shape(Sample[0], Sample[1], 3500, Curve, 0.6f);
            const StickResponse::SAxes Neg = StickResponse::Shape(-Sample[0], -Sample[1], 3500, Curve, 0.6f);
            CHECK(Neg.fX == -Pos.fX);
            CHECK(Neg.fY == -Pos.fY);
        }
    }
}

TEST_CASE("Trigger threshold 0 passes everything above rest")
{
    CHECK(StickResponse::Trigger(0, 0)     == Near(0.0));
    CHECK(StickResponse::Trigger(1, 0)     == Near(1000.0 / 32767.0));
    CHECK(StickResponse::Trigger(32767, 0) == Near(1000.0));
}

TEST_CASE("Trigger threshold 255 scales to the top of SDL's range and can never divide by zero")
{
    //iT = 255 * 32767 / 255 = 32767, so iRaw <= iT always holds and the
    //(32767 - iT) denominator is never reached.
    CHECK(StickResponse::Trigger(0, 255)     == Near(0.0));
    CHECK(StickResponse::Trigger(16000, 255) == Near(0.0));
    CHECK(StickResponse::Trigger(32767, 255) == Near(0.0));
}

TEST_CASE("Trigger actuates one count past the scaled threshold")
{
    //30 is the shipped default: 30 * 32767 / 255 truncates to 3854.
    CHECK(StickResponse::Trigger(3854, 30) == Near(0.0));
    CHECK(StickResponse::Trigger(3855, 30) == Near(1000.0 / (32767.0 - 3854.0)));
    CHECK(StickResponse::Trigger(32767, 30) == Near(1000.0));
}

TEST_CASE("Unclamped ini deadzones misbehave (pinned pre-fix behavior)")
{
    //A negative deadzone lifts the whole remap: a raw sample of 1 -- a stick
    //at rest -- already emits nearly half scale.
    CHECK(StickResponse::Shape(1, 0, -30000, kLinear, 1.0f).fX == Near(477.97));

    //At 32767 the (1 - cDz) denominator is zero. Everything on or inside the
    //unit circle is dead; a diagonal past it divides by zero and snaps
    //straight to full scale.
    CHECK(StickResponse::Shape(32767, 0, 32767, kLinear, 1.0f).fX == Near(0.0));
    const StickResponse::SAxes Out = StickResponse::Shape(32767, 32767, 32767, kLinear, 1.0f);
    CHECK(Out.fX == Near(1000.0));
    CHECK(Out.fY == Near(1000.0));
}
