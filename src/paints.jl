# ---------- paints (T005 solid, T007a gradients + image/tiled kinds) ----------
# Upstream: pixie/paints.nim -- PaintKind (L4), Paint (L15), ColorStop (L26),
# newPaint (L33), `copy` (L36), parseSomePaint (L48), colorStop (L65),
# gradientColor (L68, unexported), fillGradientLinear/Radial/Angular
# (L95/L179/L211), fillGradient (L238); pixie/paths.nim fillPath
# (L2109-2158) solid and non-solid branches.
#
# This port has no float `Color` type (D010): Paint.color and
# ColorStop.color are straight-alpha ColorRGBA, and float `Color` pipelines
# convert with chroma's `color()` (component / 255) at use time. The solid
# effective color stays `a = round(c.a/255*opacity*255)` then `rgbx` (chroma
# `color.rgba() -> rgbx()`), verified in T002. Gradient stops mix in float32
# with chroma `lerp` (`a*(1-v) + b*v`), then
# `color.a *= paint.opacity`, `round(c*255)` and premultiply (`rgbx`) -- the
# pinned `gradientColor` pipeline.
#
# Upstream quirks kept: the fill entry points clamp `paint.opacity` to 0..1
# in place; zero-alpha solid paints are a no-op under NormalBlend but still
# fill under OverwriteBlend; the non-solid path draws with opaque paint and
# then applies the paint's opacity to the *mask*; `draw(fill, mask, MaskBlend)`
# composites the fill through the mask. The angular-gradient handle-count
# error message reads "2 handles" like upstream (the check is 3).
# `parseHtmlColor` accepts hex, rgb()/rgba(), and named CSS colors.

"""Upstream `PaintKind` enum order (stable values 0..5)."""
struct PaintKind
    value::Int
end

const SolidPaint = PaintKind(0)
const ImagePaint = PaintKind(1)
const TiledImagePaint = PaintKind(2)
const LinearGradientPaint = PaintKind(3)
const RadialGradientPaint = PaintKind(4)
const AngularGradientPaint = PaintKind(5)

"""
A gradient stop (upstream `ColorStop`): a straight color plus the stop
position on the gradient (documented 0..1; positions outside the stop range
clamp to the nearest stop, as `gradientColor` does).
"""
struct ColorStop
    color::ColorRGBA
    position::Float32
end

"""
`Paint` (upstream `Paint`): fill style with a kind. Solid paints carry
straight-alpha `color` (`opacity` (Float32, default 1) scales its alpha at
draw time and is clamped to 0..1 in place by the draw entry points;
`blendMode` picks the composite). Image/tiled paints carry `image` plus the
`imageMat` transform. Gradient paints carry `gradientHandlePositions`
(image space) and `gradientStops` (gradient space). `copy` returns an
independent paint (upstream `copy`).
"""
mutable struct Paint
    kind::PaintKind
    color::ColorRGBA
    opacity::Float32
    blendMode::BlendMode
    image::Union{Image,Nothing}
    imageMat::Mat3
    gradientHandlePositions::Vector{Vec2}
    gradientStops::Vector{ColorStop}
end

"""Upstream `newPaint(kind)`: zero color, opacity 1, NormalBlend, identity imageMat."""
function newPaint(kind::PaintKind)
    return Paint(
        kind,
        ColorRGBA(0x00, 0x00, 0x00, 0x00),
        Float32(1),
        NormalBlend,
        nothing,
        mat3(),
        Vector{Vec2}(),
        Vector{ColorStop}())
end

"""Solid paint (upstream solid `Paint(k: SolidPaint, ...)`)."""
function Paint(color::ColorRGBA; opacity::Float32 = Float32(1),
    blendMode = NormalBlend)
    p = newPaint(SolidPaint)
    p.color = color
    p.opacity = opacity
    p.blendMode = blendMode
    return p
end

Paint(c::ColorRGB) = Paint(ColorRGBA(c.r, c.g, c.b, 0xff))
Paint(c::ColorRGBX) = Paint(rgba(c))

# Upstream `parseSomePaint` (string case): any color parse failure is
# re-raised as `Unable to parse color <paint>`.
function Paint(s::String)
    try
        return Paint(parseHtmlColor(s))
    catch
        throw(ArgumentError("Unable to parse color $(s)"))
    end
end

"""Image paint (upstream `newPaint(ImagePaint)` + `paint.image`/`imageMat`)."""
function Paint(image::Image; opacity::Float32 = Float32(1),
    blendMode = NormalBlend, imageMat::Mat3 = mat3())
    p = newPaint(ImagePaint)
    p.image = image
    p.imageMat = imageMat
    p.opacity = opacity
    p.blendMode = blendMode
    return p
end

"""`Paint(kind)` (upstream `newPaint`): an empty paint of the given kind."""
Paint(kind::PaintKind) = newPaint(kind)

"""Upstream `copy(Paint)`: a new paint with the same properties."""
function Base.copy(paint::Paint)
    p = newPaint(paint.kind)
    p.blendMode = paint.blendMode
    p.opacity = paint.opacity
    p.color = paint.color
    p.image = paint.image
    p.imageMat = paint.imageMat
    p.gradientHandlePositions = copy(paint.gradientHandlePositions)
    p.gradientStops = copy(paint.gradientStops)
    return p
end

"""
A hex digit of a CSS hex color (upstream chroma `c2n`); non-hex characters
raise `ArgumentError` (upstream `InvalidColor`).
"""
function hexDigit(c)
    (c >= '0' && c <= '9') && return Int(c) - Int('0')
    (c >= 'a' && c <= 'f') && return 10 + Int(c) - Int('a')
    (c >= 'A' && c <= 'F') && return 10 + Int(c) - Int('A')
    throw(ArgumentError("format is not hex"))
end

# chroma `colorNames` (names.nim) ported verbatim: CSS color name ->
# 0xRRGGBB. Used by the named-color branch of `parseHtmlColor`.
const _htmlColorNames = Dict{String,UInt32}(
    "aliceblue" => 0xf0f8ff,
    "antiquewhite" => 0xfaebd7,
    "aqua" => 0x00ffff,
    "aquamarine" => 0x7fffd4,
    "azure" => 0xf0ffff,
    "beige" => 0xf5f5dc,
    "bisque" => 0xffe4c4,
    "black" => 0x000000,
    "blanchedalmond" => 0xffebcd,
    "blue" => 0x0000ff,
    "blueviolet" => 0x8a2be2,
    "brown" => 0xa52a2a,
    "burlywood" => 0xdeb887,
    "cadetblue" => 0x5f9ea0,
    "chartreuse" => 0x7fff00,
    "chocolate" => 0xd2691e,
    "coral" => 0xff7f50,
    "cornflowerblue" => 0x6495ed,
    "cornsilk" => 0xfff8dc,
    "crimson" => 0xdc143c,
    "cyan" => 0x00ffff,
    "darkblue" => 0x00008b,
    "darkcyan" => 0x008b8b,
    "darkgoldenrod" => 0xb8860b,
    "darkgray" => 0xa9a9a9,
    "darkgrey" => 0xa9a9a9,
    "darkgreen" => 0x006400,
    "darkkhaki" => 0xbdb76b,
    "darkmagenta" => 0x8b008b,
    "darkolivegreen" => 0x556b2f,
    "darkorange" => 0xff8c00,
    "darkorchid" => 0x9932cc,
    "darkred" => 0x8b0000,
    "darksalmon" => 0xe9967a,
    "darkseagreen" => 0x8fbc8f,
    "darkslateblue" => 0x483d8b,
    "darkslategray" => 0x2f4f4f,
    "darkslategrey" => 0x2f4f4f,
    "darkturquoise" => 0x00ced1,
    "darkviolet" => 0x9400d3,
    "deeppink" => 0xff1493,
    "deepskyblue" => 0x00bfff,
    "dimgray" => 0x696969,
    "dimgrey" => 0x696969,
    "dodgerblue" => 0x1e90ff,
    "firebrick" => 0xb22222,
    "floralwhite" => 0xfffaf0,
    "forestgreen" => 0x228b22,
    "fuchsia" => 0xff00ff,
    "gainsboro" => 0xdcdcdc,
    "ghostwhite" => 0xf8f8ff,
    "gold" => 0xffd700,
    "goldenrod" => 0xdaa520,
    "gray" => 0x808080,
    "grey" => 0x808080,
    "green" => 0x008000,
    "greenyellow" => 0xadff2f,
    "honeydew" => 0xf0fff0,
    "hotpink" => 0xff69b4,
    "indianred" => 0xcd5c5c,
    "indigo" => 0x4b0082,
    "ivory" => 0xfffff0,
    "khaki" => 0xf0e68c,
    "lavender" => 0xe6e6fa,
    "lavenderblush" => 0xfff0f5,
    "lawngreen" => 0x7cfc00,
    "lemonchiffon" => 0xfffacd,
    "lightblue" => 0xadd8e6,
    "lightcoral" => 0xf08080,
    "lightcyan" => 0xe0ffff,
    "lightgoldenrodyellow" => 0xfafad2,
    "lightgray" => 0xd3d3d3,
    "lightgrey" => 0xd3d3d3,
    "lightgreen" => 0x90ee90,
    "lightpink" => 0xffb6c1,
    "lightsalmon" => 0xffa07a,
    "lightseagreen" => 0x20b2aa,
    "lightskyblue" => 0x87cefa,
    "lightslategray" => 0x778899,
    "lightslategrey" => 0x778899,
    "lightsteelblue" => 0xb0c4de,
    "lightyellow" => 0xffffe0,
    "lime" => 0x00ff00,
    "limegreen" => 0x32cd32,
    "linen" => 0xfaf0e6,
    "magenta" => 0xff00ff,
    "maroon" => 0x800000,
    "mediumaquamarine" => 0x66cdaa,
    "mediumblue" => 0x0000cd,
    "mediumorchid" => 0xba55d3,
    "mediumpurple" => 0x9370db,
    "mediumseagreen" => 0x3cb371,
    "mediumslateblue" => 0x7b68ee,
    "mediumspringgreen" => 0x00fa9a,
    "mediumturquoise" => 0x48d1cc,
    "mediumvioletred" => 0xc71585,
    "midnightblue" => 0x191970,
    "mintcream" => 0xf5fffa,
    "mistyrose" => 0xffe4e1,
    "moccasin" => 0xffe4b5,
    "navajowhite" => 0xffdead,
    "navy" => 0x000080,
    "oldlace" => 0xfdf5e6,
    "olive" => 0x808000,
    "olivedrab" => 0x6b8e23,
    "orange" => 0xffa500,
    "orangered" => 0xff4500,
    "orchid" => 0xda70d6,
    "palegoldenrod" => 0xeee8aa,
    "palegreen" => 0x98fb98,
    "paleturquoise" => 0xafeeee,
    "palevioletred" => 0xdb7093,
    "papayawhip" => 0xffefd5,
    "peachpuff" => 0xffdab9,
    "peru" => 0xcd853f,
    "pink" => 0xffc0cb,
    "plum" => 0xdda0dd,
    "powderblue" => 0xb0e0e6,
    "purple" => 0x800080,
    "rebeccapurple" => 0x663399,
    "red" => 0xff0000,
    "rosybrown" => 0xbc8f8f,
    "royalblue" => 0x4169e1,
    "saddlebrown" => 0x8b4513,
    "salmon" => 0xfa8072,
    "sandybrown" => 0xf4a460,
    "seagreen" => 0x2e8b57,
    "seashell" => 0xfff5ee,
    "sienna" => 0xa0522d,
    "silver" => 0xc0c0c0,
    "skyblue" => 0x87ceeb,
    "slateblue" => 0x6a5acd,
    "slategray" => 0x708090,
    "slategrey" => 0x708090,
    "snow" => 0xfffafa,
    "springgreen" => 0x00ff7f,
    "steelblue" => 0x4682b4,
    "tan" => 0xd2b48c,
    "teal" => 0x008080,
    "thistle" => 0xd8bfd8,
    "tomato" => 0xff6347,
    "turquoise" => 0x40e0d0,
    "violet" => 0xee82ee,
    "wheat" => 0xf5deb3,
    "white" => 0xffffff,
    "whitesmoke" => 0xf5f5f5,
    "yellow" => 0xffff00,
    "yellowgreen" => 0x9acd32,
)

# chroma `min(1.0, value / 255)` rgb/rgba component -> byte, via chroma
# `rgba(Color)`'s `round(c * 255)`. The clamp only guards UInt8
# construction (chroma's float Color underflows on negative input).
function _htmlChannelByte(v::Float64)
    return UInt8(clamp(roundHalfAway(min(1.0, v / 255) * 255), 0, 255))
end

# chroma `min(1.0, value)` rgba alpha -> byte.
function _htmlAlphaByte(v::Float64)
    return UInt8(clamp(roundHalfAway(min(1.0, v) * 255), 0, 255))
end

# Numeric parse failure: the SVG port's established convention (upstream
# Nim's ValueError is wrapped into a PixieError; the paint path wraps all
# failures into "Unable to parse color" regardless).
function _htmlFloat(text::AbstractString)
    try
        return parse(Float64, text)
    catch
        throw(ArgumentError("Invalid SVG data"))
    end
end

"""chroma `parseHtmlRgb`: `rgb(r, g, b)`, components 0-255, alpha 1."""
function _parseHtmlRgb(t::AbstractString)
    t[1:4] != "rgb(" && throw(ArgumentError("Expected 'rgb('"))
    t[end] != ')' && throw(ArgumentError("Expected ')'"))
    inner = replace(t[5:length(t) - 1], ' ' => "")
    arr = split(inner, ",")
    length(arr) != 3 && throw(ArgumentError("Expected 3 numbers in rgb()"))
    return ColorRGBA(_htmlChannelByte(_htmlFloat(arr[1])),
        _htmlChannelByte(_htmlFloat(arr[2])),
        _htmlChannelByte(_htmlFloat(arr[3])), 0xff)
end

"""chroma `parseHtmlRgba`: `rgba(r, g, b, a)`, components 0-255, alpha 0-1."""
function _parseHtmlRgba(t::AbstractString)
    t[1:5] != "rgba(" && throw(ArgumentError("Expected 'rgba('"))
    t[end] != ')' && throw(ArgumentError("Expected ')'"))
    inner = replace(t[6:length(t) - 1], ' ' => "")
    arr = split(inner, ",")
    length(arr) != 4 && throw(ArgumentError("Expected 4 numbers in rgba()"))
    return ColorRGBA(_htmlChannelByte(_htmlFloat(arr[1])),
        _htmlChannelByte(_htmlFloat(arr[2])),
        _htmlChannelByte(_htmlFloat(arr[3])),
        _htmlAlphaByte(_htmlFloat(arr[4])))
end

"""
Chroma `parseHtmlColor` (full port), returned as a straight `ColorRGBA`:
`#RGB` (tiny), `#RRGGBB`, `rgb()`, `rgba()` and named CSS colors
(chroma `colorNames`, ASCII case-insensitive). The float->byte step
mirrors chroma's `Color -> rgba` conversion (`round(c * 255)`).
"""
function parseHtmlColor(text::String)
    t = strip(text)
    isempty(t) && throw(ArgumentError("HTML color invalid: $(text)"))
    if t[1] == '#'
        if length(t) == 4
            # chroma `parseHtmlHexTiny`: channel = d / 15 (float), a = 1.
            f(d) = UInt8(roundHalfAway(Float32(d) / Float32(15) * Float32(255)))
            return ColorRGBA(f(hexDigit(t[2])), f(hexDigit(t[3])),
                f(hexDigit(t[4])), 0xff)
        elseif length(t) == 7
            pair(i) = UInt8(hexDigit(t[i]) * 16 + hexDigit(t[i + 1]))
            return ColorRGBA(pair(2), pair(4), pair(6), 0xff)
        end
        throw(ArgumentError("HTML color invalid: $(text)"))
    end
    # chroma checks `rgba` before `rgb` (both are prefixes of each other).
    if length(t) > 4 && t[1:4] == "rgba"
        return _parseHtmlRgba(t)
    end
    if length(t) > 3 && t[1:3] == "rgb"
        return _parseHtmlRgb(t)
    end
    # chroma `parseHtmlName`: toLowerAscii, then the colorNames table.
    v = get(_htmlColorNames, lowercase(t), nothing)
    v === nothing &&
        throw(ArgumentError("Not a valid color name: $(text)"))
    return ColorRGBA(UInt8((v >> 16) & 0xff), UInt8((v >> 8) & 0xff),
        UInt8(v & 0xff), 0xff)
end

"""
Upstream `parseSomePaint` for the solid cases: `convert(Paint, x)` from
`ColorRGB`/`ColorRGBA`/`ColorRGBX`/hex string. Invalid input raises
`ArgumentError` (upstream `PixieError`).
"""
Base.convert(::Type{Paint}, v::Paint) = v
function Base.convert(::Type{Paint}, v)
    (v isa ColorRGB || v isa ColorRGBA || v isa ColorRGBX || v isa String) ||
        throw(ArgumentError("Paint cannot be converted from $(typeof(v))"))
    return Paint(v)
end

"""
Color stop (upstream `colorStop(color, position)`); accepts the solid-color
forms (including hex strings), converted straight as chroma `color()` would.
"""
function colorStop(color, position::Float32)
    c = color isa ColorRGB ? ColorRGBA(color.r, color.g, color.b, 0xff) :
        color isa ColorRGBA ? color :
        color isa ColorRGBX ? rgba(color) :
        color isa String ? parseHtmlColor(color) :
        throw(ArgumentError("colorStop color must be a ColorRGB, ColorRGBA, ColorRGBX or hex string"))
    return ColorStop(c, position)
end

"""
Effective premultiplied color of a solid paint (solid branch):
`a = round(c.a/255*opacity*255)`, then `rgbx` (the chroma pipeline upstream
`fillShapes` uses on `paint.color.rgba()`... `rgbx()`).
"""
function solidColorRGBX(paint::Paint)
    c = paint.color
    a = UInt8(roundHalfAway(Float32(c.a) / Float32(255) * paint.opacity * Float32(255)))
    return rgbx(ColorRGBA(c.r, c.g, c.b, a))
end

"""
Stop color for parameter `t` (upstream `gradientColor`, L68): solid color of
the first/last stop outside the range, chroma `lerp` between neighboring
stops inside, then `a *= opacity` and the `rgba -> rgbx` byte pipeline
(`round(c * 255)` per channel, premultiplied). Stops are straight bytes in
this port; the float-space lerp matches chroma `Color` arithmetic.
"""
function gradientColor(paint::Paint, t::Float32)
    stops = paint.gradientStops
    index = -1
    for (k, stop) in enumerate(stops)
        if stop.position < t
            index = k
        end
        if stop.position > t
            break
        end
    end
    if index == -1
        c = _toF(stops[1].color)
    elseif index + 1 > length(stops)
        c = _toF(stops[index].color)
    else
        gs1 = stops[index]
        gs2 = stops[index + 1]
        v = (t - gs1.position) / (gs2.position - gs1.position)
        c1 = _toF(gs1.color)
        c2 = _toF(gs2.color)
        c = _FColor(
            c1.r * (Float32(1) - v) + c2.r * v,
            c1.g * (Float32(1) - v) + c2.g * v,
            c1.b * (Float32(1) - v) + c2.b * v,
            c1.a * (Float32(1) - v) + c2.a * v)
    end
    c = _FColor(c.r, c.g, c.b, c.a * paint.opacity)
    cc = ColorRGBA(
        UInt8(roundHalfAway(c.r * 255f0) % 256),
        UInt8(roundHalfAway(c.g * 255f0) % 256),
        UInt8(roundHalfAway(c.b * 255f0) % 256),
        UInt8(roundHalfAway(c.a * 255f0) % 256))
    return rgbx(cc)
end

"""
Fill `image` with a linear gradient (upstream `fillGradientLinear`,
L95-177, scalar port; the SIMD column fast paths produce byte-identical
values): 2 handles required, >= 1 stop; `toLineSpace` projects pixels onto
the handle line and `gradientColor` shades.
"""
function fillGradientLinear(image::Image, paint::Paint)
    if length(paint.gradientHandlePositions) != 2
        throw(ArgumentError("Linear gradient requires 2 handles"))
    end
    if length(paint.gradientStops) == 0
        throw(ArgumentError("Gradient must have at least 1 color stop"))
    end
    paint.opacity = clamp(paint.opacity, Float32(0), Float32(1))
    if paint.opacity == Float32(0)
        return nothing
    end
    toLineSpace(at, to, point::Vec2) = begin
        d = to - at
        det = d.x * d.x + d.y * d.y
        (d.y * (point.y - at.y) + d.x * (point.x - at.x)) / det
    end
    at = paint.gradientHandlePositions[1]
    to = paint.gradientHandlePositions[2]
    if at.y == to.y # horizontal
        for x in 0:(image.width - 1)
            t = toLineSpace(at, to, Vec2(Float32(x), 0f0))
            rgbx = gradientColor(paint, t)
            for y in 0:(image.height - 1)
                set_pixel(image, x + 1, y + 1, rgbx)
            end
        end
    elseif at.x == to.x # vertical
        for y in 0:(image.height - 1)
            t = toLineSpace(at, to, Vec2(0f0, Float32(y)))
            rgbx = gradientColor(paint, t)
            for x in 0:(image.width - 1)
                set_pixel(image, x + 1, y + 1, rgbx)
            end
        end
    else
        for y in 0:(image.height - 1)
            for x in 0:(image.width - 1)
                t = toLineSpace(at, to, Vec2(Float32(x), Float32(y)))
                set_pixel(image, x + 1, y + 1, gradientColor(paint, t))
            end
        end
    end
    return nothing
end

"""
Fill `image` with a radial gradient (upstream `fillGradientRadial`,
L179-209): 3 handles (center, edge, skew) map the unit circle into
`translate(center) * rotate(angle) * scale(distanceX, distanceY)`; the
distance from center in that space is `t`.
"""
function fillGradientRadial(image::Image, paint::Paint)
    if length(paint.gradientHandlePositions) != 3
        throw(ArgumentError("Radial gradient requires 3 handles"))
    end
    if length(paint.gradientStops) == 0
        throw(ArgumentError("Gradient must have at least 1 color stop"))
    end
    paint.opacity = clamp(paint.opacity, Float32(0), Float32(1))
    if paint.opacity == Float32(0)
        return nothing
    end
    center = paint.gradientHandlePositions[1]
    edge = paint.gradientHandlePositions[2]
    skew = paint.gradientHandlePositions[3]
    distanceX = length(center - edge)
    distanceY = length(center - skew)
    gradientAngle = fixAngle(angle(normalize(center - edge)))
    mat = inverse(
        translate(center) * rotate(gradientAngle) *
        scale(Vec2(distanceX, distanceY)))
    for y in 0:(image.height - 1)
        for x in 0:(image.width - 1)
            xy = Vec2(Float32(x), Float32(y))
            t = length(mat * xy)
            set_pixel(image, x + 1, y + 1, gradientColor(paint, t))
        end
    end
    return nothing
end

"""
Fill `image` with an angular (conic) gradient (upstream `fillGradientAngular`,
L211-236): 3 handles (center, edge); `t` is the normalized absolute angle
from `edge` around `center` (0 at the edge direction, 1 at the wrap).
"""
function fillGradientAngular(image::Image, paint::Paint)
    if length(paint.gradientHandlePositions) != 3
        throw(ArgumentError("Angular gradient requires 2 handles"))
    end
    if length(paint.gradientStops) == 0
        throw(ArgumentError("Gradient must have at least 1 color stop"))
    end
    paint.opacity = clamp(paint.opacity, Float32(0), Float32(1))
    if paint.opacity == Float32(0)
        return nothing
    end
    center = paint.gradientHandlePositions[1]
    edge = paint.gradientHandlePositions[2]
    f32PI = Float32(pi)
    gradientAngle = fixAngle(angle(normalize(edge - center)))
    for y in 0:(image.height - 1)
        for x in 0:(image.width - 1)
            xy = Vec2(Float32(x), Float32(y))
            a = angle(normalize(xy - center))
            t = fixAngle(a + gradientAngle + f32PI / Float32(2)) /
                Float32(2) / f32PI + Float32(0.5)
            set_pixel(image, x + 1, y + 1, gradientColor(paint, t))
        end
    end
    return nothing
end

"""
Fill `image` with the paint's gradient by kind (upstream `fillGradient`,
L238); non-gradient paints raise (upstream `PixieError`).
"""
function fillGradient(image::Image, paint::Paint)
    if paint.kind === LinearGradientPaint
        return fillGradientLinear(image, paint)
    elseif paint.kind === RadialGradientPaint
        return fillGradientRadial(image, paint)
    elseif paint.kind === AngularGradientPaint
        return fillGradientAngular(image, paint)
    end
    throw(ArgumentError("Paint must be a gradient"))
end

"""
Fill `path` (a `Path` or an SVG path string) with a `Paint` (upstream
`fillPath`, paths.nim L2109-2158): opacity is clamped to 0..1 in place and
zero opacity is a no-op. Solid paints fill via the rasterizer exactly as in
T005 (zero-alpha skipped unless `OverwriteBlend`, which can clear). Non-solid
paints: the path rasterized white becomes the mask, the image/tiled/gradient
is drawn opaque into a fill canvas, the paint's opacity scales the mask,
`fill.draw(mask, MaskBlend)` composites the cut-out, and
`image.draw(fill, paint.blendMode)` writes it to `image` (both identity
transforms, exactly as upstream).
"""
function fillPath(
    image::Image, path, paint::Paint;
    transform::Mat3 = mat3(), windingRule = NonZero
)
    (windingRule === NonZero || windingRule === EvenOdd) ||
        throw(ArgumentError("windingRule must be NonZero or EvenOdd"))
    paint.opacity = clamp(paint.opacity, Float32(0), Float32(1))
    if paint.opacity == Float32(0)
        return nothing
    end
    if paint.kind === SolidPaint
        # Solid Paints delegate to the rasterizer's ColorRGBX entry point:
        # identical pixels, one fewer Paint conversion per call.
        c = solidColorRGBX(paint)
        if c.a > 0x00 || paint.blendMode === OverwriteBlend
            if c.a > 0x00 || paint.blendMode !== OverwriteBlend
                fillPath(image, path, c;
                    transform = transform, windingRule = windingRule,
                    blendMode = paint.blendMode)
            else
                # Zero-alpha Overwrite is a clear: the ColorRGBX entry
                # returns early on zero alpha, so rasterize directly.
                src = path isa Path ? path :
                    path isa String ? parsePath(path) :
                    throw(ArgumentError("path must be a Path or an SVG path string"))
                shapes = commandsToShapes(src, true, pixelScale(transform))
                if transform != mat3()
                    for s in shapes
                        for k in eachindex(s)
                            s[k] = transform * s[k]
                        end
                    end
                end
                fillShapes(image, shapes, c, windingRule;
                    blendMode = paint.blendMode)
            end
        end
        return nothing
    end
    # Non-solid (paints.nim `case paint.kind` + mask composite, L2131-2158)
    mask = newImage(image.width, image.height)
    fillImg = newImage(image.width, image.height)
    fillPath(
        mask, path, ColorRGBX(0xff, 0xff, 0xff, 0xff), # solid white
        transform = transform, windingRule = windingRule)
    savedOpacity = paint.opacity
    paint.opacity = Float32(1)
    if paint.kind === ImagePaint
        if paint.image === nothing
            throw(ArgumentError("ImagePaint requires paint.image"))
        end
        draw(fillImg, paint.image, paint.imageMat)
    elseif paint.kind === TiledImagePaint
        if paint.image === nothing
            throw(ArgumentError("TiledImagePaint requires paint.image"))
        end
        drawTiled(fillImg, paint.image, paint.imageMat)
    else
        fillGradient(fillImg, paint)
    end
    paint.opacity = savedOpacity
    if paint.opacity != Float32(1)
        applyOpacity(mask, paint.opacity)
    end
    draw(fillImg, mask; blendMode = MaskBlend)
    draw(image, fillImg; blendMode = paint.blendMode)
    return nothing
end
