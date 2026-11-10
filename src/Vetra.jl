"""
A Julia port of treeform/pixie, pinned at revision 30bb510 (see upstream.toml).

CPU 2D drawing: images, colors, affine geometry, paths, paints, compositing,
text, and image formats. See docs/COMPATIBILITY.md for supported subsets.

Ported formulas (with source in the pinned tree):

- `pixie/common.nim`: newImage, mix, `*`(ColorRGBX, float32),
  `*`(ColorRGBX, uint8)
- `pixie/images.nim`: inside, getColor, setColor, fill (via fillUnsafe)
- `pixie/internal.nim`: toPremultipliedAlpha, straightAlphaTable/toStraightAlpha
- `pixie/blends.nim`: blendAlpha, blendNormal
- `chroma/transformations.nim`: rgbx(ColorRGBA), rgbx(ColorRGB), rgba(ColorRGBX)

See docs/NUMERICAL_CONTRACT.md for the binding spec and the documented
differences between the two premul->straight conversion paths.
"""
module Vetra

# Extend Base generics so image methods coexist with scalar/array methods.
import Base: *, ceil, diff, fill, copy

# Upstream (Nim) `round` ties away from zero (verified against the pinned
# toolchain: round(-1.5f) == -2); Julia's default round ties to even.
# Non-negative inputs (most call sites) are unaffected by the change.
roundHalfAway(x::AbstractFloat) = Int(round(x, RoundNearestTiesAway))

include("geometry.jl")
# paths.jl and rasterizer.jl are included at the end of the module: they
# reference the core color/image types defined below.

# ---------- colors (chroma/src/chroma/colortypes.nim) ----------

struct ColorRGB
    r::UInt8
    g::UInt8
    b::UInt8
end

struct ColorRGBA
    r::UInt8
    g::UInt8
    b::UInt8
    a::UInt8
end

"""Premultiplied-alpha RGBA; the stored image pixel format (r, g, b <= a)."""
struct ColorRGBX
    r::UInt8
    g::UInt8
    b::UInt8
    a::UInt8
end

function _byte(v::UInt8)
    return v
end

function _byte(v::Int)
    (0 <= v <= 255) || throw(ArgumentError("byte value must be 0..255, got $(v)"))
    return UInt8(v)
end

function rgb(r, g, b)
    return ColorRGB(_byte(r), _byte(g), _byte(b))
end

function rgba(r, g, b, a)
    return ColorRGBA(_byte(r), _byte(g), _byte(b), _byte(a))
end

function rgbx(r, g, b, a)
    return ColorRGBX(_byte(r), _byte(g), _byte(b), _byte(a))
end

# ---------- alpha conversion ----------

"""
chroma `rgbx(c: ColorRGBA)`: straight alpha to premultiplied alpha.
`channel = (c * a + 127) div 255`; `a` unchanged.
"""
function rgbx(c::ColorRGBA)
    a = Int(c.a)
    return ColorRGBX(
        UInt8((Int(c.r) * a + 127) ÷ 255),
        UInt8((Int(c.g) * a + 127) ÷ 255),
        UInt8((Int(c.b) * a + 127) ÷ 255),
        c.a)
end

rgbx(c::ColorRGB) = ColorRGBX(c.r, c.g, c.b, 0xff)

"""
pixie `toPremultipliedAlpha`: same formula as `rgbx(ColorRGBA)`; the
`a == 255` no-op branch is explicit upstream and yields the same result here.
"""
toPremultipliedAlpha(c::ColorRGBA) = rgbx(c)

"""
chroma `rgba(c: ColorRGBX)` (a.k.a. pixie `autoStraightAlpha`): premultiplied
to straight. For `a` in 1..254: `multiplier = round(255/a * 255)` (float32,
ties away from zero per `roundHalfAway`),
`channel = (c * multiplier + 127) div 255`; for `a == 0` or `a == 255` the
channels are unchanged.
"""
function rgba(c::ColorRGBX)
    a = Int(c.a)
    if a == 0 || a == 0xff
        return ColorRGBA(c.r, c.g, c.b, c.a)
    end
    mult = roundHalfAway(Float32(255) / Float32(a) * Float32(255))
    return ColorRGBA(
        UInt8((Int(c.r) * mult + 127) ÷ 255),
        UInt8((Int(c.g) * mult + 127) ÷ 255),
        UInt8((Int(c.b) * mult + 127) ÷ 255),
        c.a)
end

"""
pixie `toStraightAlpha` (straightAlphaTable): `channel = min(round(c *
255/a), 255)`. Upstream's `let multiplier = if a > 0: (255 / a.float32)
else: 0` infers float64, so the product is computed in float64 (verified
bit-exact against straight_alpha.tsv on all 32896 valid rows). The `a == 0`
table row is all zeros. Diverges from `rgba` on many valid-domain inputs,
e.g. a=4, c=2 -> 128 vs 127.
"""
function toStraightAlpha(c::ColorRGBX)
    a = Int(c.a)
    if a == 0
        return ColorRGBA(0x00, 0x00, 0x00, 0x00)
    end
    mult = 255.0 / a                       # Float64, as upstream infers
    chan(v::UInt8) = UInt8(min(roundHalfAway(Float64(v) * mult), 255))
    return ColorRGBA(chan(c.r), chan(c.g), chan(c.b), c.a)
end

# ---------- image storage (pixie/common.nim, images.nim) ----------

"""
Bitmap in premultiplied-alpha RGBA, row-major, rows top to bottom, 4 bytes per
pixel (R, G, B, A). 1-based pixel coordinates.
"""
struct Image
    width::Int
    height::Int
    data::Vector{UInt8}
end

function newImage(width::Int, height::Int)
    (width > 0 && height > 0) ||
        throw(ArgumentError("Image width and height must be > 0"))
    return Image(width, height, zeros(UInt8, 4 * width * height))
end

"""Copy the image data into a new image (upstream `copy`)."""
Base.copy(image::Image) = Image(image.width, image.height, copy(image.data))

width(image::Image) = image.width
height(image::Image) = image.height

"""True if 1-based (x, y) is inside the image (upstream `inside`, 0-based)."""
function inside(image::Image, x::Int, y::Int)
    1 <= x <= image.width && 1 <= y <= image.height
end

function pixel_index(image::Image, x::Int, y::Int)
    inside(image, x, y) ||
        throw(BoundsError("pixel ($x, $y) outside $(image.width)×$(image.height)"))
    return 4 * ((y - 1) * image.width + (x - 1))
end

function getColor(image::Image, x::Int, y::Int)
    i = pixel_index(image, x, y)
    d = image.data
    return ColorRGBX(d[i + 1], d[i + 2], d[i + 3], d[i + 4])
end

function set_pixel(image::Image, x::Int, y::Int, c::ColorRGBX)
    i = pixel_index(image, x, y)
    d = image.data
    d[i + 1] = c.r
    d[i + 2] = c.g
    d[i + 3] = c.b
    d[i + 4] = c.a
end

setColor(image::Image, x::Int, y::Int, color::ColorRGBX) =
    set_pixel(image, x, y, color)
setColor(image::Image, x::Int, y::Int, color::ColorRGBA) =
    set_pixel(image, x, y, rgbx(color))
setColor(image::Image, x::Int, y::Int, color::ColorRGB) =
    set_pixel(image, x, y, rgbx(color))

"""Fill the whole image with a solid color (upstream `fill`/`fillUnsafe`)."""
function fill(image::Image, color::ColorRGBX)
    d = image.data
    d[1:4:length(d)] .= color.r
    d[2:4:length(d)] .= color.g
    d[3:4:length(d)] .= color.b
    d[4:4:length(d)] .= color.a
end

function fill(image::Image, color::ColorRGBA)
    fill(image, rgbx(color))
end

fill(image::Image, color::ColorRGB) =
    fill(image, ColorRGBX(color.r, color.g, color.b, 0xff))

# ---------- compositing (pixie/common.nim, blends.nim) ----------

"""
`pixie/common.nim mix(a, b, t)`: `x = round(t * 255)`,
`c = (a_c * (255 - x) + b_c * x + 127) div 255` per channel and alpha.
"""
function mix(a::ColorRGBX, b::ColorRGBX, t::Float32)
    x = roundHalfAway(t * Float32(255))
    # `255 - x` is a constant over the four channels: hoist it so the
    # per-channel closure is a simple integer mix (bit-identical results).
    invx = 255 - x
    f(av::UInt8, bv::UInt8) = UInt8((Int(av) * invx + Int(bv) * x + 127) ÷ 255)
    return ColorRGBX(f(a.r, b.r), f(a.g, b.g), f(a.b, b.b), f(a.a, b.a))
end

"""
`pixie/common.nim `*`(ColorRGBX, float32)`: opacity 0 -> (0,0,0,0); else
`x = round(opacity * 255)`, `c = (c * x + 127) div 255` per channel and
alpha. Upstream computes in uint32 and truncates to uint8, so out-of-range
areas wrap instead of raising (the `& 0xff` preserves that).
"""
function *(color::ColorRGBX, opacity::Float32)
    if opacity == Float32(0)
        return ColorRGBX(0x00, 0x00, 0x00, 0x00)
    end
    x = roundHalfAway(opacity * Float32(255))
    # Constant closure over the four channels (bit-identical results).
    f(v::UInt8) = UInt8((Int(v) * x + 127) ÷ 255 & 0xff)
    return ColorRGBX(f(color.r), f(color.g), f(color.b), f(color.a))
end

"""
`pixie/common.nim `*`(ColorRGBX, uint8)`: 0 -> (0,0,0,0); 255 -> unchanged;
else `c = (c * coverage + 127) div 255` per channel and alpha.
"""
function *(color::ColorRGBX, coverage::UInt8)
    if coverage == 0x00
        return ColorRGBX(0x00, 0x00, 0x00, 0x00)
    elseif coverage == 0xff
        return color
    end
    cov = Int(coverage)
    # Constant closure over the four channels (bit-identical results).
    f(v::UInt8) = UInt8((Int(v) * cov + 127) ÷ 255)
    return ColorRGBX(f(color.r), f(color.g), f(color.b), f(color.a))
end

"""`pixie/blends.nim blendAlpha`: `sa + (ba * (255 - sa)) div 255`."""
function blendAlpha(backdrop::UInt8, source::UInt8)
    return UInt8(Int(source) + (Int(backdrop) * (255 - Int(source))) ÷ 255)
end

"""
`pixie/blends.nim blendNormal` (source-over). Returns `source` if
`backdrop.a == 0 || source.a == 255`, returns `backdrop` if `source.a == 0`;
else with `k = 255 - sa`: `c = sc + (bc * k) div 255`,
`a = blendAlpha(ba, sa)`. Expects valid premultiplied input (r, g, b <= a).
"""
function blendNormal(backdrop::ColorRGBX, source::ColorRGBX)
    if backdrop.a == 0x00 || source.a == 0xff
        return source
    end
    if source.a == 0x00
        return backdrop
    end
    k = 255 - Int(source.a)
    sR, sG, sB = Int(source.r), Int(source.g), Int(source.b)
    # Upstream adds in `uint8`: sums past 255 wrap (visible on the
    # invalid-premul fixture cells, e.g. 255+255 -> 0). Mirror that.
    f(bv::UInt8, sv::Int) = UInt8((sv + (Int(bv) * k) ÷ 255) % 256)
    return ColorRGBX(f(backdrop.r, sR), f(backdrop.g, sG), f(backdrop.b, sB),
        blendAlpha(backdrop.a, source.a))
end

# Public API (Julia 1.10-compatible exports).
export ColorRGB, ColorRGBA, ColorRGBX, Image,
    rgb, rgba, rgbx, toStraightAlpha, toPremultipliedAlpha,
    newImage, width, height, inside, fill, copy,
    getColor, setColor, mix, blendAlpha, blendNormal,
    Vec2, Rect, Circle, Segment, Line, Polygon, Mat3,
    rect, xy, wh, left, top, right, bottom, circle, segment, line,
    dot, length, lengthSq, normalize, perpendicular,
    mat3, translate, scale, rotate, determinant, transpose, inverse,
    transform, snapToPixels,
    Path, PathCommandKind, WindingRule, NonZero, EvenOdd,
    BlendMode, NormalBlend, DarkenBlend, MultiplyBlend, ColorBurnBlend,
    LightenBlend, ScreenBlend, ColorDodgeBlend, OverlayBlend, SoftLightBlend,
    HardLightBlend, DifferenceBlend, ExclusionBlend, HueBlend,
    SaturationBlend, ColorBlend, LuminosityBlend, MaskBlend, OverwriteBlend,
    SubtractMaskBlend, ExcludeMaskBlend,
    newPath, addPath, closePath, moveTo, lineTo, bezierCurveTo,
    quadraticCurveTo, ellipticalArcTo, arc, arcTo, roundedRect,
    ellipse, polygon,
    parsePath, computeBounds, fillShapes, fillPath,
    Paint, PaintKind, SolidPaint, ImagePaint, TiledImagePaint,
    LinearGradientPaint, RadialGradientPaint, AngularGradientPaint,
    ColorStop, newPaint, colorStop, parseHtmlColor,
    fillGradient,
    blendDarken, blendMultiply, blendColorBurn, blendLighten, blendScreen,
    blendColorDodge, blendOverlay, blendSoftLight, blendHardLight,
    blendDifference, blendExclusion, blendHue, blendSaturation,
    blendColor, blendLuminosity,
    blendMask, blendSubtractMask, blendExcludeMask, blender,
    getRgbaSmooth, minifyBy2, magnifyBy2, applyOpacity, subImage,
    draw, drawTiled, drawImage,
    gaussianKernel, flipHorizontal, flipVertical, rotate90, diff,
    invert, ceil, blur, resize, spread, shadow, superImage, opaqueBounds,
    LineCap, LineJoin, ButtCap, RoundCap, SquareCap,
    MiterJoin, RoundJoin, BevelJoin,
    defaultMiterLimit, miterLimitToAngle, angleToMiterLimit,
    strokeShapes, strokePath,
    Context, save, saveLayer, restore, clip,
    getTransform, setTransform, resetTransform, isPointInPath,
    beginPath, stroke, fillRect, strokeRect, clearRect, strokeSegment,
    encodePPM, writePPM,
    decodePPM, decodePPMDimensions,
    parseSvg, SvgNode, SvgProperties, SvgLinearGradient, Svg,
    decodePNG, encodePNG, decodePNGDimensions,
    decodeBMP, decodeDIB, encodeBMP, decodeBMPDimensions,
    decodeQOI, encodeQOI, decodeQOIDimensions, Qoi, QoiColorspace,
    sRBG, Linear, srgbToLinear, qoiHash,
    decodeGIF, decodeGIFDimensions, Gif,
    decodeJPEG, decodeJPEGDimensions, encodeJPEG,
    decodeWebP, decodeWebPDimensions, encodeWebP,
    FileFormat, PngFormat, BmpFormat, JpegFormat, GifFormat, QoiFormat,
    PpmFormat, WebpFormat,
    decodeImage, decodeImageDimensions, readImage, readImageDimensions,
    encodeImage, writeFile, encodeBase64, decodeBase64,
    Typeface, Font, Span, Arrangement, TextMetrics,
    HorizontalAlignment, LeftAlign, CenterAlign, RightAlign,
    VerticalAlignment, TopAlign, MiddleAlign, BottomAlign,
    TextCase, NormalCase, UpperCase, LowerCase, TitleCase,
    BaselineAlignment, TopBaseline, HangingBaseline, MiddleBaseline,
    AlphabeticBaseline, IdeographicBaseline, BottomBaseline,
    autoLineHeight, newFont, newSpan, readFont, readTypeface,
    parseTtf, parseOtf, parseOpenType,
    typeset, layoutBounds, measureText, fillText, strokeText,
    setLineDash, getLineDash,
    computePaths, defaultLineHeight,
    ascent, descent, lineGap, lineHeight, capHeight,
    hasGlyph, fallbackTypeface, getGlyphPath, getAdvance,
    glyphPathByGid,
    getKerningAdjustment, getLeftSideBearing, isCCW, name,
    withFallback,
    Paragraph, Cluster, ParagraphLine, ParagraphMetrics, ParagraphLayout,
    OverflowPolicy, ClipOverflow, EllipsisOverflow,
    TextDirection, LeftToRight, RightToLeft,
    newParagraph, layoutParagraph, paragraphMetrics,
    fillParagraph, strokeParagraph,
    ShapedGlyph, shapeText,
    toColors, fromColors,
    Picture, PictureRecorder, RecordingContext, finishRecording, drawPicture,
    writeSvg, writePdf

include("paths.jl")
include("blends.jl")
include("rasterizer.jl")
include("image_ops.jl")
include("paints.jl")
include("strokes.jl")
include("fontformats/opentype.jl")
include("fontformats/unicase.jl")
include("formats/fonts.jl")
include("context.jl")
include("formats/paragraph.jl")
include("formats/shaping.jl")
include("recordings.jl")
include("formats/ppm.jl")
include("formats/svg.jl")
include("formats/png.jl")
include("formats/svg_write.jl")
include("formats/pdf_write.jl")
include("formats/bmp.jl")
include("formats/qoi.jl")
include("formats/gif.jl")
include("formats/jpeg.jl")
include("formats/webp.jl")
include("formats/io.jl")
include("colormatrices.jl")

# --- precompile common entry points (T021) ---
# Measured in fresh processes: the first fillRect/stroke/fillText call
# compiles the whole draw pipeline (mask, rasterizer, text layout) for ~2.5 s
# on first use. Compiling these instances at precompile time moves that cost
# to the install/precompile stage (reported separately; no sysimage needed).
precompile(Context, (Image,))
precompile(newImage, (Int, Int))
precompile(fillRect, (Context, Float32, Float32, Float32, Float32))
precompile(fillRect, (Context, Rect))
precompile(fill, (Context, Path))
precompile(stroke, (Context, Path))
precompile(strokeSegment, (Context, Float32, Float32, Float32, Float32))
precompile(fillText, (Context, String, Float32, Float32))
precompile(measureText, (Context, String))
precompile(drawImage, (Context, Image, Float32, Float32, Float32, Float32))
precompile(save, (Context,))
precompile(restore, (Context,))
precompile(saveLayer, (Context,))
precompile(clip, (Context, Path))
precompile(getColor, (Image, Int, Int))
precompile(encodeImage, (Image, FileFormat))

function __init__()
    # Optional codecs are discovered lazily on first use (D028): each
    # _require* loads its package only when a user actually calls the
    # feature, so `using Vetra` stays fast in codec-enabled environments.
    return nothing
end

end # module Vetra
