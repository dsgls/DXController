#include "StickResponse.h"

#include <algorithm>
#include <cmath>

namespace StickResponse
{

float ShapeMagnitude(const float fU, const SCurve& Curve)
{
    if (fU <= 0.0f)
    {
        return 0.0f;
    }
    switch (Curve.eType)
    {
    case ECurveType::Power:
        return std::pow(fU, Curve.fPower);

    case ECurveType::Expo:
    {
        const float e = Curve.fExpo;
        return (1.0f - e) * fU + e * fU * fU * fU;
    }

    case ECurveType::Sigmoid:
    {
        const float k  = Curve.fSigSteepness;
        const float c  = Curve.fSigMidpoint;
        const float w  = Curve.fSigStrength;
        const float lo = 1.0f / (1.0f + std::exp(  k * c));
        const float hi = 1.0f / (1.0f + std::exp(-k * (1.0f - c)));
        const float s  = (1.0f / (1.0f + std::exp(-k * (fU - c))) - lo) / (hi - lo);
        return (1.0f - w) * fU + w * s;
    }

    case ECurveType::Linear:
    default:
        return fU;
    }
}

float ShapeNormalized(const float fU, const int iDeadzoneRaw, const SCurve& Curve, const float fScale)
{
    const float fCDz = static_cast<float>(iDeadzoneRaw) / kRawFullScale;
    if (fU <= fCDz)
    {
        return 0.0f;
    }
    const float fR = (fU - fCDz) / (1.0f - fCDz);
    return ShapeMagnitude(fR, Curve) * fScale;
}

int ClampDeadzone(const int iDeadzoneRaw)
{
    return std::min(32766, std::max(0, iDeadzoneRaw));
}

int ClampAxis(const int iRaw)
{
    return (iRaw <= -32767) ? -32767 : iRaw;
}

int NegateY(const int iRaw)
{
    return -ClampAxis(iRaw);
}

SAxes Shape(const int iRawX, const int iRawY, const int iDeadzoneRaw,
            const SCurve& Curve, const float fScale)
{
    //Work entirely in normalized magnitude [0, 1]; scale to axis units once at
    //the end. fRawMag can exceed 32767 on a diagonal (~46340 at full 45 deg);
    //the curve extrapolates monotonically and the per-axis clamp catches it.
    const float fXf     = static_cast<float>(iRawX);
    const float fYf     = static_cast<float>(iRawY);
    const float fRawMag = std::sqrt(fXf * fXf + fYf * fYf);
    const float fU      = fRawMag / kRawFullScale;

    const float fOutNorm = ShapeNormalized(fU, iDeadzoneRaw, Curve, fScale);
    if (fOutNorm == 0.0f || fRawMag <= 0.0f)
    {
        return { 0.0f, 0.0f };
    }

    //Direction preserved: a single combined scale = out_axis_mag / raw_mag
    //applied to raw X/Y yields direction * out_axis_mag with no intermediate
    //sqrt.
    const float fAxisScale = (fOutNorm * kAxisRange) / fRawMag;
    return { std::min(kAxisRange, std::max(-kAxisRange, fXf * fAxisScale)),
             std::min(kAxisRange, std::max(-kAxisRange, fYf * fAxisScale)) };
}

float Trigger(const int iRaw, const int iThreshold255)
{
    const int iT = iThreshold255 * 32767 / 255;
    if (iRaw <= iT)
    {
        return 0.0f;
    }
    //Linear remap (iT, 32767] -> (0, kAxisRange]; same convention as sticks.
    return std::min(kAxisRange,
                    static_cast<float>(iRaw - iT) * kAxisRange / static_cast<float>(32767 - iT));
}

}
