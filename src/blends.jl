# ---------- blends (T007a) ----------
# Upstream: pixie/blends.nim -- the W3C blend-mode pixel functions and the
# `blender` dispatcher; and the float (chroma-color) pipeline used by
# softLight/hue/saturation/color/luminosity (chroma/src/chroma/blends.nim
# lum/sat/setLum/setSat/clipColor/alphaFix + transformations.nim
# color/ColorRGBA/rgbx). All 20 modes dispatch: the 16 W3C modes +
# Overwrite plus the three mask modes (MaskBlend is used by clip/saveLayer
# and the non-solid fillPath pipeline; SubtractMask/ExcludeMask are plain
# pixel blends, like upstream).
#
# All arithmetic mirrors the pinned Nim exactly: byte mixes do the integer
# `div 255` in the range the source gives them and cast with `.uint8`
# (which wraps on 8 bits), so wrap is reproduced with `% 256`. `round` ties
# away from zero (upstream roundHalfAway / chroma round), never banker's.
# The float pipeline is Float32 throughout (chroma Color is a float32 point).

"""Fill blend mode, upstream `BlendMode` enum order (stable values 0..19)."""
struct BlendMode
    value::Int
end

const NormalBlend       = BlendMode(0)
const DarkenBlend       = BlendMode(1)
const MultiplyBlend     = BlendMode(2)
const ColorBurnBlend    = BlendMode(3)
const LightenBlend      = BlendMode(4)
const ScreenBlend       = BlendMode(5)
const ColorDodgeBlend   = BlendMode(6)
const OverlayBlend      = BlendMode(7)
const SoftLightBlend    = BlendMode(8)
const HardLightBlend    = BlendMode(9)
const DifferenceBlend   = BlendMode(10)
const ExclusionBlend    = BlendMode(11)
const HueBlend          = BlendMode(12)
const SaturationBlend   = BlendMode(13)
const ColorBlend        = BlendMode(14)
const LuminosityBlend   = BlendMode(15)
const MaskBlend         = BlendMode(16)
const OverwriteBlend    = BlendMode(17)
const SubtractMaskBlend = BlendMode(18)
const ExcludeMaskBlend  = BlendMode(19)

# ---------- byte helpers (blends.nim) ----------

"""Upstream local `screen` (uint32 arithmetic, `.uint8` cast)."""
function _screenByte(b::UInt8, s::UInt8)
    return UInt8((Int(b) + Int(s) - (Int(b) * Int(s)) ÷ 255) % 256)
end

"""
Upstream local `hardLight` (byte pipeline). Argument order matches the
upstream parameters (backdropColor, backdropAlpha, sourceColor, sourceAlpha);
blendOverlay and blendHardLight pass them in opposite orders.
"""
function _hardLightByte(
    backdropColor::UInt8, backdropAlpha::UInt8,
    sourceColor::UInt8, sourceAlpha::UInt8
)
    bc = Int(backdropColor)
    ba = Int(backdropAlpha)
    sc = Int(sourceColor)
    sa = Int(sourceAlpha)
    if sc * 2 <= sa
        return UInt8(
            (2 * sc * bc + sc * (255 - ba) + bc * (255 - sa)) ÷ 255 % 256)
    end
    return _screenByte(backdropColor, sourceColor)
end

# ---------- W3C byte-pipeline blends ----------

"""`blendDarken`: per-channel min of the two alpha-blended candidates."""
function blendDarken(backdrop::ColorRGBX, source::ColorRGBX)
    ba = Int(backdrop.a)
    sa = Int(source.a)
    f(bv::UInt8, sv::UInt8) = UInt8(min(
        Int(bv) + ((255 - ba) * Int(sv)) ÷ 255,
        Int(sv) + ((255 - sa) * Int(bv)) ÷ 255) % 256)
    return ColorRGBX(f(backdrop.r, source.r), f(backdrop.g, source.g),
        f(backdrop.b, source.b), blendAlpha(backdrop.a, source.a))
end

"""`blendMultiply` (byte pipeline over premultiplied inputs)."""
function blendMultiply(backdrop::ColorRGBX, source::ColorRGBX)
    ba = Int(backdrop.a)
    sa = Int(source.a)
    f(bv::UInt8, sv::UInt8) = UInt8((
        (255 - ba) * Int(sv) + (255 - sa) * Int(bv) + Int(bv) * Int(sv)) ÷ 255 % 256)
    return ColorRGBX(f(backdrop.r, source.r), f(backdrop.g, source.g),
        f(backdrop.b, source.b), blendAlpha(backdrop.a, source.a))
end

"""`blendLighten`: per-channel max of the two alpha-blended candidates."""
function blendLighten(backdrop::ColorRGBX, source::ColorRGBX)
    ba = Int(backdrop.a)
    sa = Int(source.a)
    f(bv::UInt8, sv::UInt8) = UInt8(max(
        Int(bv) + ((255 - ba) * Int(sv)) ÷ 255,
        Int(sv) + ((255 - sa) * Int(bv)) ÷ 255) % 256)
    return ColorRGBX(f(backdrop.r, source.r), f(backdrop.g, source.g),
        f(backdrop.b, source.b), blendAlpha(backdrop.a, source.a))
end

"""`blendScreen` (byte pipeline)."""
function blendScreen(backdrop::ColorRGBX, source::ColorRGBX)
    return ColorRGBX(
        _screenByte(backdrop.r, source.r),
        _screenByte(backdrop.g, source.g),
        _screenByte(backdrop.b, source.b),
        blendAlpha(backdrop.a, source.a))
end

"""`blendOverlay`: hardLight with the source and backdrop roles swapped."""
function blendOverlay(backdrop::ColorRGBX, source::ColorRGBX)
    return ColorRGBX(
        _hardLightByte(source.r, source.a, backdrop.r, backdrop.a),
        _hardLightByte(source.g, source.a, backdrop.g, backdrop.a),
        _hardLightByte(source.b, source.a, backdrop.b, backdrop.a),
        blendAlpha(backdrop.a, source.a))
end

"""`blendHardLight` (byte pipeline)."""
function blendHardLight(backdrop::ColorRGBX, source::ColorRGBX)
    return ColorRGBX(
        _hardLightByte(backdrop.r, backdrop.a, source.r, source.a),
        _hardLightByte(backdrop.g, backdrop.a, source.g, source.a),
        _hardLightByte(backdrop.b, backdrop.a, source.b, source.a),
        blendAlpha(backdrop.a, source.a))
end

"""`blendDifference` (byte pipeline; `.uint8` casts wrap, mirrored here)."""
function blendDifference(backdrop::ColorRGBX, source::ColorRGBX)
    sa = Int(source.a)
    ba = Int(backdrop.a)
    f(bv::UInt8, sv::UInt8) = UInt8((
        Int(bv) + Int(sv) -
        2 * (min(Int(bv) * sa, Int(sv) * ba) ÷ 255)) % 256)
    return ColorRGBX(f(backdrop.r, source.r), f(backdrop.g, source.g),
        f(backdrop.b, source.b), blendAlpha(backdrop.a, source.a))
end

"""`blendExclusion` (byte pipeline; `max(0, v)`)."""
function blendExclusion(backdrop::ColorRGBX, source::ColorRGBX)
    f(bv::UInt8, sv::UInt8) = UInt8(max(
        0, Int(bv) + Int(sv) - (2 * Int(bv) * Int(sv)) ÷ 255) % 256)
    return ColorRGBX(f(backdrop.r, source.r), f(backdrop.g, source.g),
        f(backdrop.b, source.b), blendAlpha(backdrop.a, source.a))
end

# ---------- chroma-float pipeline (softLight, hue, saturation, color,
#            luminosity) ----------

"""chroma `Color` (a float32 point, upstream straight-alpha 0..1 space)."""
struct _FColor
    r::Float32
    g::Float32
    b::Float32
    a::Float32
end

"""`round` ties away from zero for either sign (chroma round)."""
function _rhaz(x::AbstractFloat)
    return Int(sign(x) * floor(abs(x) + abs(Float32(0.5))))
end

"""
chroma `rgba(ColorRGBX)` exactly, including its `.uint8` truncation wrap:
the fixture grid deliberately contains `255,255,255,254`, whose straight
conversion is 256 and wraps to 0 upstream. T002's `rgba` covers the valid
premultiplied domain only and would throw on that row.
"""
function _rgbaWrap(c::ColorRGBX)
    a = Int(c.a)
    if a == 0 || a == 0xff
        return ColorRGBA(c.r, c.g, c.b, c.a)
    end
    mult = _rhaz(Float32(255) / Float32(a) * Float32(255))
    return ColorRGBA(
        UInt8((Int(c.r) * mult + 127) ÷ 255 % 256),
        UInt8((Int(c.g) * mult + 127) ÷ 255 % 256),
        UInt8((Int(c.b) * mult + 127) ÷ 255 % 256),
        c.a)
end

"""chroma `color*(ColorRGBA)` (byte straight alpha to float32 0..1)."""
function _toF(c::ColorRGBA)
    return _FColor(Float32(c.r) / 255f0, Float32(c.g) / 255f0,
        Float32(c.b) / 255f0, Float32(c.a) / 255f0)
end

"""
chroma `rgba(Color)` (`round(c * 255).uint8` per channel incl. alpha; casts
wrap outside 0..1 exactly as the upstream uint8 cast) -> straight ColorRGBA.
"""
function _fromF(fc::_FColor)
    return ColorRGBA(
        UInt8(_rhaz(fc.r * 255f0) % 256),
        UInt8(_rhaz(fc.g * 255f0) % 256),
        UInt8(_rhaz(fc.b * 255f0) % 256),
        UInt8(_rhaz(fc.a * 255f0) % 256))
end

"""chroma `lum`."""
_lum(c::_FColor) = 0.3f0 * c.r + 0.59f0 * c.g + 0.11f0 * c.b

"""chroma `sat`."""
_sat(c::_FColor) = max(c.r, c.g, c.b) - min(c.r, c.g, c.b)

"""
chroma `clipColor`: an affine map in each of the four components, driven by
lightness L (from r,g,b) and the min/max (n,x) of r,g,b.
"""
function _clipColor(c::_FColor)
    L = _lum(c)
    n = min(c.r, c.g, c.b)
    x = max(c.r, c.g, c.b)
    if n < 0
        k = L / (L - n)
        c = _FColor(
            L + (c.r - L) * k, L + (c.g - L) * k,
            L + (c.b - L) * k, L + (c.a - L) * k)
    end
    if x > 1
        k = (1f0 - L) / (x - L)
        c = _FColor(
            L + (c.r - L) * k, L + (c.g - L) * k,
            L + (c.b - L) * k, L + (c.a - L) * k)
    end
    return c
end

"""chroma `setLum` (sets r,g,b; alpha left zero, clipColor over all four)."""
function _setLum(c::_FColor, l::Float32)
    d = l - _lum(c)
    return _clipColor(
        _FColor(c.r + d, c.g + d, c.b + d, 0f0))
end

"""chroma `setSat` (zero Color when already desaturated, as upstream)."""
function _setSat(c::_FColor, s::Float32)
    satC = _sat(c)
    if satC > 0
        m = min(c.r, c.g, c.b)
        return _FColor(
            (c.r - m) * s / satC, (c.g - m) * s / satC,
            (c.b - m) * s / satC, (c.a - m) * s / satC)
    end
    return _FColor(0f0, 0f0, 0f0, 0f0)
end

"""chroma `alphaFix` (float pipeline; combines source/mixed/backdrop alpha)."""
function _alphaFixF(bd::_FColor, sc::_FColor, mx::_FColor)
    a = sc.a + bd.a * (1f0 - sc.a)
    if a == 0f0
        return _FColor(0f0, 0f0, 0f0, 0f0)
    end
    t0 = sc.a * (1f0 - bd.a)
    t1 = sc.a * bd.a
    t2 = (1f0 - sc.a) * bd.a
    r = t0 * sc.r + t1 * mx.r + t2 * bd.r
    g = t0 * sc.g + t1 * mx.g + t2 * bd.g
    b = t0 * sc.b + t1 * mx.b + t2 * bd.b
    return _FColor(r / a, g / a, b / a, a)
end

"""chroma `softLight` (Pegtop form)."""
_softLight(b::Float32, s::Float32) =
    (1f0 - 2f0 * s) * b * b + 2f0 * s * b

# Float-pipeline blends, each `blendXxx(backdrop.color, source.color).rgbx`.

"""`blendSoftLight` via the chroma-float pipeline."""
function blendSoftLight(backdrop::ColorRGBX, source::ColorRGBX)
    bd = _toF(_rgbaWrap(backdrop))
    sc = _toF(_rgbaWrap(source))
    mx = _FColor(
        _softLight(bd.r, sc.r), _softLight(bd.g, sc.g),
        _softLight(bd.b, sc.b), 0f0)
    return rgbx(_fromF(_alphaFixF(bd, sc, mx)))
end

"""`blendHue` via the chroma-float pipeline."""
function blendHue(backdrop::ColorRGBX, source::ColorRGBX)
    bd = _toF(_rgbaWrap(backdrop))
    sc = _toF(_rgbaWrap(source))
    mx = _setLum(_setSat(sc, _sat(bd)), _lum(bd))
    return rgbx(_fromF(_alphaFixF(bd, sc, mx)))
end

"""`blendSaturation` via the chroma-float pipeline."""
function blendSaturation(backdrop::ColorRGBX, source::ColorRGBX)
    bd = _toF(_rgbaWrap(backdrop))
    sc = _toF(_rgbaWrap(source))
    mx = _setLum(_setSat(bd, _sat(sc)), _lum(bd))
    return rgbx(_fromF(_alphaFixF(bd, sc, mx)))
end

"""`blendColor` via the chroma-float pipeline."""
function blendColor(backdrop::ColorRGBX, source::ColorRGBX)
    bd = _toF(_rgbaWrap(backdrop))
    sc = _toF(_rgbaWrap(source))
    mx = _setLum(sc, _lum(bd))
    return rgbx(_fromF(_alphaFixF(bd, sc, mx)))
end

"""`blendLuminosity` via the chroma-float pipeline."""
function blendLuminosity(backdrop::ColorRGBX, source::ColorRGBX)
    bd = _toF(_rgbaWrap(backdrop))
    sc = _toF(_rgbaWrap(source))
    mx = _setLum(bd, _lum(sc))
    return rgbx(_fromF(_alphaFixF(bd, sc, mx)))
end

# ---------- straight byte-pipeline + the three mask pixel functions ----------

"""`blendColorBurn` (straight alpha, chroma `alphaFix` in byte form)."""
function blendColorBurn(backdrop::ColorRGBX, source::ColorRGBX)
    bd = _rgbaWrap(backdrop)
    sc = _rgbaWrap(source)
    f(bv::UInt8, sv::UInt8) =
        bv == 0xff ? 0xff : sv == 0x00 ? 0x00 :
            UInt8(255 - min(255, 255 * (255 - Int(bv)) ÷ Int(sv)))
    mixed = ColorRGBA(f(bd.r, sc.r), f(bd.g, sc.g), f(bd.b, sc.b), 0x00)
    return rgbx(_alphaFixByte(bd, sc, mixed))
end

"""
`alphaFix` (byte form, blends.nim): straight-alpha source/mixed/backdrop into
a straight result, then the caller premultiplies with `rgbx`.
"""
function _alphaFixByte(bd::ColorRGBA, sc::ColorRGBA, mx::ColorRGBA)
    sa = Int(sc.a)
    ba = Int(bd.a)
    t0 = sa * (255 - ba)
    t1 = sa * ba
    t2 = (255 - sa) * ba
    r = t0 * Int(sc.r) + t1 * Int(mx.r) + t2 * Int(bd.r)
    g = t0 * Int(sc.g) + t1 * Int(mx.g) + t2 * Int(bd.g)
    b = t0 * Int(sc.b) + t1 * Int(mx.b) + t2 * Int(bd.b)
    a = sa + ba * (255 - sa) ÷ 255
    if a == 0
        return ColorRGBA(0x00, 0x00, 0x00, 0x00)
    end
    # Upstream `.uint8` truncation wraps for out-of-domain straight channels.
    return ColorRGBA(
        UInt8(r ÷ a ÷ 255 % 256), UInt8(g ÷ a ÷ 255 % 256),
        UInt8(b ÷ a ÷ 255 % 256), UInt8(a % 256))
end

"""`blendColorDodge` (straight alpha, chroma byte `alphaFix`)."""
function blendColorDodge(backdrop::ColorRGBX, source::ColorRGBX)
    bd = _rgbaWrap(backdrop)
    sc = _rgbaWrap(source)
    f(bv::UInt8, sv::UInt8) =
        bv == 0x00 ? 0x00 : sv == 0xff ? 0xff :
            UInt8(min(255, 255 * Int(bv) ÷ (255 - Int(sv))))
    mixed = ColorRGBA(f(bd.r, sc.r), f(bd.g, sc.g), f(bd.b, sc.b), 0x00)
    return rgbx(_alphaFixByte(bd, sc, mixed))
end

"""
`blendMask`: scale the backdrop by the source alpha. Used by clip/saveLayer
restoration, the rasterizer's clears-uncovered pass, and the non-solid
fillPath pipeline.
"""
function blendMask(backdrop::ColorRGBX, source::ColorRGBX)
    k = Int(source.a)
    return ColorRGBX(
        UInt8(Int(backdrop.r) * k ÷ 255),
        UInt8(Int(backdrop.g) * k ÷ 255),
        UInt8(Int(backdrop.b) * k ÷ 255),
        UInt8(Int(backdrop.a) * k ÷ 255))
end

"""`blendSubtractMask` (upstream `blender`-dispatchable pixel blend)."""
function blendSubtractMask(backdrop::ColorRGBX, source::ColorRGBX)
    a = Int(backdrop.a) * (255 - Int(source.a)) ÷ 255
    return ColorRGBX(
        UInt8(Int(backdrop.r) * a ÷ 255),
        UInt8(Int(backdrop.g) * a ÷ 255),
        UInt8(Int(backdrop.b) * a ÷ 255),
        UInt8(a))
end

"""`blendExcludeMask` (upstream `blender`-dispatchable pixel blend)."""
function blendExcludeMask(backdrop::ColorRGBX, source::ColorRGBX)
    a = max(Int(backdrop.a), Int(source.a)) - min(Int(backdrop.a), Int(source.a))
    return ColorRGBX(
        UInt8(Int(source.r) * a ÷ 255),
        UInt8(Int(source.g) * a ÷ 255),
        UInt8(Int(source.b) * a ÷ 255),
        UInt8(a))
end

"""
`blender(mode)`: returns the pixel function for all 20 pinned modes
(16 W3C + Overwrite + the three mask modes).
"""
function blender(mode::BlendMode)
    v = mode.value
    return (b::ColorRGBX, s::ColorRGBX) ->
        v == 0 ? blendNormal(b, s) :
        v == 1 ? blendDarken(b, s) :
        v == 2 ? blendMultiply(b, s) :
        v == 3 ? blendColorBurn(b, s) :
        v == 4 ? blendLighten(b, s) :
        v == 5 ? blendScreen(b, s) :
        v == 6 ? blendColorDodge(b, s) :
        v == 7 ? blendOverlay(b, s) :
        v == 8 ? blendSoftLight(b, s) :
        v == 9 ? blendHardLight(b, s) :
        v == 10 ? blendDifference(b, s) :
        v == 11 ? blendExclusion(b, s) :
        v == 12 ? blendHue(b, s) :
        v == 13 ? blendSaturation(b, s) :
        v == 14 ? blendColor(b, s) :
        v == 15 ? blendLuminosity(b, s) :
        v == 16 ? blendMask(b, s) :
        v == 17 ? s :
        v == 18 ? blendSubtractMask(b, s) :
        v == 19 ? blendExcludeMask(b, s) :
        throw(ArgumentError("unknown blend mode BlendMode($(v))"))
end
