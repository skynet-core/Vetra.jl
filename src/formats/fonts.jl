# ---------- fonts (T009) ----------
# Upstream: pixie/fonts.nim (30bb510) -- typeset/layout/fill/stroke and the
# font/typeface API, on top of the opentype.jl parser subset (D015).
#
# Conventions (faithful to upstream):
# - Font units are hhea/hmtx integers; pixel values are Float32 computed
#   exactly where upstream computes them (font-level `scale` is
#   size / unitsPerEm).
# - Upstream `round` (ties away from zero) maps to the module-level
#   `roundHalfAway` (all rounded values here are integral pixel offsets).
# - `Rune` is a UInt32 code point. Arrangement indices are 1-based into
#   `runes`/`positions`/`selectionRects`; `spans` and `lines` are
#   (start, stop) 1-based inclusive ranges.
# - Upstream `PixieError` maps to `ArgumentError`.

const autoLineHeight = Float32(-1) # use the font's default line height

const _LF_RUNE = UInt32(10)
const _SP_RUNE = UInt32(32)

"""Unicode White_Space test (Nim `isWhiteSpace`); the fixtures' scripts
need only BMP space separators, which this list covers exactly."""
function _otIsWsRune(rune::UInt32)
    return (0x0009 <= rune <= 0x000d) || rune == 0x0020 ||
        rune == 0x0085 || rune == 0x00a0 || rune == 0x1680 ||
        (0x2000 <= rune <= 0x200a) || rune == 0x2028 || rune == 0x2029 ||
        rune == 0x202f || rune == 0x205f || rune == 0x3000
end

# One-rune case conversion (upstream Rune.toUpper/toLower): the pinned
# Nim stdlib tables and binary search live in fontformats/unicase.jl.
_otToUpper(rune::UInt32) = UInt32(_unicaseUpper(Int(rune)))
_otToLower(rune::UInt32) = UInt32(_unicaseLower(Int(rune)))

"""Code points of a string, mirroring upstream `fastRuneAt` (Nim stdlib,
doInc=true). Julia `String` is always valid UTF-8, so walking its runes
yields exactly the code points `fastRuneAt` would decode; the upstream
invalid-sequence branches (truncated → `0xFFFD`, stray continuation bytes)
are unreachable and omitted. This build has no `codepoints`."""
function _otCodepoints(text::String)
    cps = Vector{UInt32}(undef, length(text))
    for (i, c) in enumerate(text)
        cps[i] = UInt32(c)
    end
    return cps
end

"""Text horizontal alignment (upstream `HorizontalAlignment`, enum order)."""
struct HorizontalAlignment
    kind::Int
end
const LeftAlign = HorizontalAlignment(0)
const CenterAlign = HorizontalAlignment(1)
const RightAlign = HorizontalAlignment(2)

"""Text vertical alignment (upstream `VerticalAlignment`, enum order)."""
struct VerticalAlignment
    kind::Int
end
const TopAlign = VerticalAlignment(0)
const MiddleAlign = VerticalAlignment(1)
const BottomAlign = VerticalAlignment(2)

"""Text case (upstream `TextCase`, enum order)."""
struct TextCase
    kind::Int
end
const NormalCase = TextCase(0)
const UpperCase = TextCase(1)
const LowerCase = TextCase(2)
const TitleCase = TextCase(3)

"""Text baseline (upstream `BaselineAlignment`, enum order)."""
struct BaselineAlignment
    kind::Int
end
const TopBaseline = BaselineAlignment(0)
const HangingBaseline = BaselineAlignment(1)
const MiddleBaseline = BaselineAlignment(2)
const AlphabeticBaseline = BaselineAlignment(3)
const IdeographicBaseline = BaselineAlignment(4)
const BottomBaseline = BaselineAlignment(5)

"""Upstream `Typeface` (D015: opentype subset only — CFF/SVG fonts and
TTC collections are unsupported and raise at parse/load time)."""
mutable struct Typeface
    opentype::OtcOpenType
    filePath::String
    fallbacks::Vector{Typeface}
end
Typeface(ot::OtcOpenType, path::String = "") =
    Typeface(ot, path, Vector{Typeface}())

"""Upstream `Font`."""
mutable struct Font
    typeface::Typeface
    size::Float32
    lineHeight::Float32
    paints::Vector{Paint}
    textCase::TextCase
    underline::Bool
    strikethrough::Bool
    noKerningAdjustments::Bool
end

"""Upstream `Span`."""
struct Span
    text::String
    font::Font
end
newSpan(text::String, font::Font) = Span(text, font)

"""Upstream `Arrangement`."""
mutable struct Arrangement
    lines::Vector{Tuple{Int,Int}}
    spans::Vector{Tuple{Int,Int}}
    fonts::Vector{Font}
    runes::Vector{UInt32}
    positions::Vector{Vec2}
    selectionRects::Vector{Rect}
end

# ---------- typeface metrics ----------

"""Upstream `scale(typeface)`: font units per em."""
scale(tf::Typeface) = Float32(tf.opentype.head.unitsPerEm)

"""Upstream `ascent(typeface)` (hhea, font units)."""
ascent(tf::Typeface) = Float32(tf.opentype.hhea.ascender)

"""Upstream `descent(typeface)` (hhea, font units; usually negative)."""
descent(tf::Typeface) = Float32(tf.opentype.hhea.descender)

"""Upstream `lineGap(typeface)` (hhea, font units)."""
lineGap(tf::Typeface) = Float32(tf.opentype.hhea.lineGap)

"""Upstream `lineHeight(typeface)`: ascent - descent + lineGap."""
lineHeight(tf::Typeface) = ascent(tf) - descent(tf) + lineGap(tf)

"""Upstream `capHeight(typeface)` (OS/2, font units)."""
capHeight(tf::Typeface) = Float32(tf.opentype.os2.sCapHeight)

"""Upstream `isCCW(typeface)`: `opentype.isCCW()` — true for glyf fonts."""
isCCW(tf::Typeface) = isCCW(tf.opentype)

_underlinePosition(tf::Typeface) = Float32(tf.opentype.post.underlinePosition)
_underlineThickness(tf::Typeface) =
    Float32(tf.opentype.post.underlineThickness)
_strikeoutPosition(tf::Typeface) =
    Float32(tf.opentype.os2.yStrikeoutPosition)
_strikeoutThickness(tf::Typeface) =
    Float32(tf.opentype.os2.yStrikeoutSize)

"""Upstream `hasGlyph(typeface, rune)`: only this typeface's cmap (the
fallback chain is consulted by `fallbackTypeface`, not here)."""
hasGlyph(tf::Typeface, rune::UInt32) = hasGlyph(tf.opentype, rune)

"""Upstream `fallbackTypeface(typeface, rune)`: the first typeface in the
fallback chain that has the glyph, or nothing."""
function fallbackTypeface(tf::Typeface, rune::UInt32)
    hasGlyph(tf.opentype, rune) && return tf
    for fb in tf.fallbacks
        found = fallbackTypeface(fb, rune)
        found !== nothing && return found
    end
    return nothing
end

"""D031 §2.7 (T028): additive fallback-chain constructor. Returns a new
`Typeface` sharing `tf`'s parsed data whose chain is `tf.fallbacks`
followed by `chain`. Raises `ArgumentError` when the combined graph
would cycle — a pre-existing cycle in `tf`'s chain, or a candidate
reaching the base graph or an earlier candidate (shared descendants of
candidates are legitimate, not cycles) — so `fallbackTypeface` is
guaranteed to terminate."""
function withFallback(tf::Typeface, chain::Vector{Typeface})
    function cycleWalk(root, seen, errSet)
        onstack = IdSet{Typeface}()
        function walk(t)
            if t in onstack
                throw(ArgumentError(
                    "font fallback cycle: typeface appears in its own fallback chain"))
            end
            if t in errSet
                throw(ArgumentError(
                    "font fallback cycle: typeface already reachable from the base typeface"))
            end
            t in seen && return
            push!(onstack, t)
            for fb in t.fallbacks
                walk(fb)
            end
            delete!(onstack, t)
            push!(seen, t)
        end
        walk(root)
        return seen
    end
    seenBase = cycleWalk(tf, IdSet{Typeface}(), IdSet{Typeface}())
    forbidden = IdSet{Typeface}()
    for t in seenBase
        push!(forbidden, t)
    end
    seenChain = IdSet{Typeface}()
    for t in chain
        cycleWalk(t, seenChain, forbidden)
        push!(forbidden, t)
    end
    return Typeface(tf.opentype, tf.filePath, vcat(tf.fallbacks, chain))
end

"""Upstream `getGlyphPath(typeface, rune)`: a fresh path per call
(`addPath` copies the cached glyph), scaled to the main typeface's ratio."""
function getGlyphPath(tf::Typeface, rune::UInt32)
    result = newPath()
    tf2 = fallbackTypeface(tf, rune)
    tf2 === nothing && return result
    addPath(result, getGlyphPath(tf2.opentype, rune))
    ratio = scale(tf) / scale(tf2)
    if ratio != Float32(1.0)
        transform(result, scale(Vec2(ratio, ratio)))
    end
    return result
end

"""Upstream `getAdvance(typeface, rune)` (pixels)."""
function getAdvance(tf::Typeface, rune::UInt32)
    tf2 = fallbackTypeface(tf, rune)
    tf2 === nothing && (tf2 = tf) # tofu advance (upstream)
    result = getAdvance(tf2.opentype, rune)
    result *= scale(tf) / scale(tf2)
    return result
end

"""Upstream `getKerningAdjustment(typeface, left, right)` (pixels);
zero unless both runes fall in the same typeface."""
function getKerningAdjustment(tf::Typeface, left::UInt32, right::UInt32)
    tfR = fallbackTypeface(tf, right)
    tfL = fallbackTypeface(tf, left)
    (tfR === nothing || tfL === nothing) && return Float32(0)
    tfR !== tfL && return Float32(0)
    result = getKerningAdjustment(tfR.opentype, left, right)
    result *= scale(tf) / scale(tfR)
    return result
end

# ---------- font-level ----------

"""Upstream `scale(font)`: pixels per font unit."""
scale(font::Font) = font.size / scale(font.typeface)

"""Upstream `defaultLineHeight(font)` (pixels)."""
defaultLineHeight(font::Font) =
    Float32(roundHalfAway((ascent(font.typeface) - descent(font.typeface) +
        lineGap(font.typeface)) * scale(font)))

"""Upstream `lineGap(font)` (pixels, for the current size/line-height)."""
function lineGap(font::Font)
    lh = font.lineHeight >= 0 ? font.lineHeight : defaultLineHeight(font)
    if lh == defaultLineHeight(font)
        return lineGap(font.typeface)
    end
    return (lh / scale(font)) - ascent(font.typeface) +
        descent(font.typeface)
end

"""Upstream `newFont(typeface)`: size 12, auto line height, solid black."""
function newFont(tf::Typeface)
    return Font(tf, Float32(12), autoLineHeight,
        [Paint(rgba(0, 0, 0, 255))], NormalCase, false, false,
        false)
end

"""Upstream `copy(Font)` (shallow: the paints vector is copied, the
Paints themselves are shared, as upstream's seq copy of ref objects)."""
function Base.copy(font::Font)
    return Font(font.typeface, font.size, font.lineHeight,
        copy(font.paints), font.textCase, font.underline,
        font.strikethrough, font.noKerningAdjustments)
end

"""Upstream `name(typeface)`: OS/2-less fonts fall back to empty."""
function name(tf::Typeface)
    return fullName(tf.opentype)
end

function _convertTextCase(runes::Vector{UInt32}, textCase::TextCase)
    if textCase === UpperCase
        for i in eachindex(runes)
            runes[i] = _otToUpper(runes[i])
        end
    elseif textCase === LowerCase
        for i in eachindex(runes)
            runes[i] = _otToLower(runes[i])
        end
    elseif textCase === TitleCase
        prevRune = _SP_RUNE
        for i in eachindex(runes)
            if _otIsWsRune(prevRune)
                runes[i] = _otToUpper(runes[i])
            end
            prevRune = runes[i]
        end
    end
end

function _canWrap(rune::UInt32)
    return rune == _SP_RUNE || _otIsWsRune(rune)
end

# ---------- typesetting ----------

"""Upstream `advance(font, runes, i)` (i is 1-based into the arrangement's
full rune list): kerning (unless disabled) + advance, times the scale."""
function _otAdvance(font::Font, runes::Vector{UInt32}, i::Int)
    result = Float32(0)
    if !font.noKerningAdjustments && i + 1 <= length(runes)
        result += getKerningAdjustment(font.typeface,
            runes[i], runes[i + 1])
    end
    result += getAdvance(font.typeface, runes[i])
    result *= scale(font)
    return result
end

"""
Upstream `typeset(spans, bounds, hAlign, vAlign, wrap)`: lay out the glyph
positions and selection rects. `bounds.x` enables wrapping/right-align
when > 0; `bounds.y` drives vAlign.
"""
function typeset(spans::Vector{Span};
    bounds::Vec2 = Vec2(), hAlign::HorizontalAlignment =
    LeftAlign, vAlign::VerticalAlignment =
    TopAlign, wrap::Bool = true)
    runes = UInt32[]
    spanRanges = Vector{Tuple{Int,Int}}()
    fonts = Vector{Font}()
    start = 0
    for span in spans
        spanRunes = UInt32[]
        for cp in _otCodepoints(span.text)
            cp >= _SP_RUNE || cp == _LF_RUNE || continue
            push!(spanRunes, cp)
        end
        if !isempty(spanRunes)
            _convertTextCase(spanRunes, span.font.textCase)
            append!(runes, spanRunes)
            push!(spanRanges, (start + 1, start + length(spanRunes)))
            push!(fonts, span.font)
            start += length(spanRunes)
        end
    end

    arrangement = Arrangement(Tuple{Int,Int}[], spanRanges, fonts, runes,
        Vec2[], Rect[])
    n = length(runes)
    n == 0 && return arrangement
    arrangement.positions = [Vec2() for _ in 1:n]
    arrangement.selectionRects = [Rect(0f0, 0f0, 0f0, 0f0) for _ in 1:n]
    arrangement.lines = [(1, 1)] # (start, stop); stop is settled later

    at = Vec2()
    prevCanWrap = 0
    for (spanIdx, (start, stop)) in enumerate(spanRanges)
        font = fonts[spanIdx]
        for runeIndex in start:stop
            rune = runes[runeIndex]
            if rune == _LF_RUNE
                advance = getAdvance(font.typeface, _SP_RUNE) * scale(font)
                arrangement.positions[runeIndex] = at
                arrangement.selectionRects[runeIndex] =
                    Rect(at.x, at.y, advance, 0f0)
                at = Vec2(0f0, at.y + 1)
                prevCanWrap = 0
                (ls, _) = arrangement.lines[end]
                arrangement.lines[end] = (ls, runeIndex)
                if runeIndex + 1 <= n
                    push!(arrangement.lines, (runeIndex + 1, 0))
                end
            else
                advance = _otAdvance(font, runes, runeIndex)
                if wrap && rune != _SP_RUNE && bounds.x > 0 &&
                    at.x + advance > bounds.x
                    # Wrap to a new line.
                    at = Vec2(0f0, at.y + 1)
                    lineStart = runeIndex
                    if prevCanWrap > 0 && prevCanWrap != runeIndex
                        for i in (prevCanWrap + 1):(runeIndex - 1)
                            arrangement.positions[i] = at
                            sr = arrangement.selectionRects[i]
                            arrangement.selectionRects[i] =
                                Rect(at.x, at.y, sr.w, sr.h)
                            at = Vec2(at.x + _otAdvance(font, runes, i),
                                at.y)
                            lineStart -= 1
                        end
                        prevCanWrap = 0
                    end
                    (ls, _) = arrangement.lines[end]
                    arrangement.lines[end] = (ls, lineStart - 1)
                    push!(arrangement.lines, (lineStart, 0))
                end
                if _canWrap(rune)
                    prevCanWrap = runeIndex
                end
                arrangement.positions[runeIndex] = at
                arrangement.selectionRects[runeIndex] =
                    Rect(at.x, at.y, advance, 0f0)
                at = Vec2(at.x + advance, at.y)
            end
        end
    end
    (ls, _) = arrangement.lines[end]
    arrangement.lines[end] = (ls, n)

    if hAlign !== LeftAlign
        for (start, stop) in arrangement.lines
            furthestX = Float32(0)
            for i in stop:-1:start
                if runes[i] != _SP_RUNE && runes[i] != _LF_RUNE
                    furthestX = arrangement.selectionRects[i].x +
                        arrangement.selectionRects[i].w
                    break
                end
            end
            xAdj = hAlign === CenterAlign ?
                (bounds.x - furthestX) / Float32(2) :
                (bounds.x - furthestX)
            if xAdj != 0
                for i in start:stop
                    pos = arrangement.positions[i]
                    arrangement.positions[i] = Vec2(pos.x + xAdj, pos.y)
                    sr = arrangement.selectionRects[i]
                    arrangement.selectionRects[i] =
                        Rect(sr.x + xAdj, sr.y, sr.w, sr.h)
                end
            end
        end
    end

    # Vertical pass: the initial baseline is the first line's max
    # ascent (upstream quirk: `font.lineGap` is the FONT-level gap in
    # pixels, added to the typeface ascent before scaling).
    initialY = Float32(0)
    for (spanIdx, (start, stop)) in enumerate(spanRanges)
        font = fonts[spanIdx]
        fontUnitInitialY = ascent(font.typeface) + lineGap(font) /
            Float32(2)
        initialY = max(initialY,
            Float32(roundHalfAway(fontUnitInitialY * scale(font))))
        if stop >= arrangement.lines[1][2]
            break
        end
    end

    lineHeights = Vector{Float32}(undef, length(arrangement.lines))
    fill!(lineHeights, Float32(0))
    line = 1
    for (spanIdx, (start, stop)) in enumerate(spanRanges)
        font = fonts[spanIdx]
        fontLineHeight = font.lineHeight >= 0 ? font.lineHeight :
            defaultLineHeight(font)
        lineHeights[line] = max(lineHeights[line], fontLineHeight)
        for runeIndex in start:stop
            # This span could span many lines.
            if line + 1 <= length(arrangement.lines) &&
                runeIndex == arrangement.lines[line + 1][1]
                line += 1
                lineHeights[line] = max(lineHeights[line], fontLineHeight)
            end
        end
        # Handle when span and line endings coincide.
        if line + 1 <= length(arrangement.lines) &&
            stop == arrangement.lines[line][2]
            line += 1
        end
    end

    line = 1
    baseline = initialY
    for (spanIdx, (start, stop)) in enumerate(spanRanges)
        font = fonts[spanIdx]
        lineHeight = font.lineHeight >= 0 ? font.lineHeight :
            defaultLineHeight(font)
        for runeIndex in start:stop
            if line + 1 <= length(arrangement.lines) &&
                runeIndex == arrangement.lines[line + 1][1]
                line += 1
                baseline += lineHeights[line]
            end
            pos = arrangement.positions[runeIndex]
            arrangement.positions[runeIndex] = Vec2(pos.x, baseline)
            sr = arrangement.selectionRects[runeIndex]
            # Upstream quirk: the font-level lineGap (pixels) feeds the
            # selection rect top, mixed with the typeface ascent.
            newY = baseline - Float32(roundHalfAway(
                (ascent(font.typeface) + lineGap(font) / Float32(2)) *
                scale(font)))
            arrangement.selectionRects[runeIndex] =
                Rect(sr.x, newY, sr.w, lineHeight)
        end
    end

    if vAlign !== TopAlign
        finalRect = arrangement.selectionRects[end]
        furthestY = finalRect.y + finalRect.h
        yAdj = vAlign === MiddleAlign ?
            Float32(roundHalfAway((bounds.y - furthestY) / Float32(2))) :
            (bounds.y - furthestY)
        if yAdj != 0
            for i in 1:n
                pos = arrangement.positions[i]
                arrangement.positions[i] = Vec2(pos.x, pos.y + yAdj)
                sr = arrangement.selectionRects[i]
                arrangement.selectionRects[i] = Rect(sr.x, sr.y + yAdj, sr.w, sr.h)
            end
        end
    end

    # Nudge selection rects to the pixel grid.
    for i in 1:n
        r = arrangement.selectionRects[i]
        minX = Float32(roundHalfAway(r.x))
        maxX = Float32(roundHalfAway(r.x + r.w))
        minY = Float32(roundHalfAway(r.y))
        maxY = Float32(roundHalfAway(r.y + r.h))
        arrangement.selectionRects[i] = Rect(minX, minY, maxX - minX,
            maxY - minY)
    end
    return arrangement
end

"""Upstream `typeset(font, text, bounds, hAlign, vAlign, wrap)`."""
function typeset(font::Font, text::String;
    bounds::Vec2 = Vec2(), hAlign::HorizontalAlignment =
    LeftAlign, vAlign::VerticalAlignment =
    TopAlign, wrap::Bool = true)
    return typeset([newSpan(text, font)]; bounds = bounds,
        hAlign = hAlign, vAlign = vAlign, wrap = wrap)
end

# ---------- layout ----------

"""Upstream `layoutBounds(arrangement)` (pixels)."""
function layoutBounds(arrangement::Arrangement)
    result = Vec2()
    n = length(arrangement.runes)
    if n > 0
        for i in 1:n
            if arrangement.runes[i] != _LF_RUNE
                rect = arrangement.selectionRects[i]
                result = Vec2(max(result.x, rect.x + rect.w), result.y)
            end
        end
        finalRect = arrangement.selectionRects[end]
        result = Vec2(result.x, finalRect.y + finalRect.h)
        if arrangement.runes[end] == _LF_RUNE
            result = Vec2(result.x, result.y + finalRect.h)
        end
    end
    return result
end

"""Upstream `layoutBounds(font, text)` (pixels)."""
layoutBounds(font::Font, text::String) =
    layoutBounds(typeset(font, text))

"""Upstream `layoutBounds(spans)` (pixels)."""
layoutBounds(spans::Vector{Span}) = layoutBounds(typeset(spans))

# ---------- rendering ----------

"""Upstream `computePaths(arrangement)`: one span path per span, glyph
paths transformed to their positions, underline/strikethrough decorations
added (skipped for the space at a line end)."""
function computePaths(arrangement::Arrangement)
    out = Vector{Path}()
    line = 1
    for (spanIdx, (start, stop)) in enumerate(arrangement.spans)
        spanPath = newPath()
        font = arrangement.fonts[spanIdx]
        tf = font.typeface
        underlineThickness = _underlineThickness(tf) * scale(font)
        underlinePosition = _underlinePosition(tf) * scale(font)
        strikeoutThickness = _strikeoutThickness(tf) * scale(font)
        strikeoutPosition = _strikeoutPosition(tf) * scale(font)
        for runeIndex in start:stop
            position = arrangement.positions[runeIndex]
            path = getGlyphPath(tf, arrangement.runes[runeIndex])
            s = scale(font)
            transform(path, translate(position) *
                scale(Vec2(s, s)))
            applyDecoration = true
            if runeIndex == arrangement.lines[line][2]
                line += 1
                if arrangement.runes[runeIndex] == _SP_RUNE
                    # Do not decorate the space at the end of a line.
                    applyDecoration = false
                end
            end
            if applyDecoration
                sr = arrangement.selectionRects[runeIndex]
                if font.underline
                    rect(path, sr.x,
                        position.y - underlinePosition +
                            underlineThickness / Float32(2),
                        sr.w, underlineThickness,
                        clockwise = isCCW(tf))
                end
                if font.strikethrough
                    rect(path, sr.x, position.y - strikeoutPosition,
                        sr.w, strikeoutThickness,
                        clockwise = isCCW(tf))
                end
            end
            addPath(spanPath, path)
        end
        push!(out, spanPath)
    end
    return out
end

"""Upstream `computeBounds(arrangement, transform)` (the pixel bounds of
all span paths after the transform)."""
function computeBounds(arrangement::Arrangement;
    transform::Mat3 = mat3())
    fullPath = newPath()
    for path in computePaths(arrangement)
        addPath(fullPath, path)
    end
    transform(fullPath, transform)
    return computeBounds(fullPath)
end

"""Upstream `textUber` (internal): fill or stroke each span path with the
font's paints."""
function _textUber(target::Image, arrangement::Arrangement,
    mat::Mat3, stroke::Bool;
    strokeWidth::Float32 = Float32(1),
    lineCap::LineCap = ButtCap, lineJoin::LineJoin = MiterJoin,
    miterLimit::Float32 = defaultMiterLimit,
    dashes::Vector{Float32} = Vector{Float32}())
    spanPaths = computePaths(arrangement)
    for spanIdx in eachindex(arrangement.spans)
        path = spanPaths[spanIdx]
        font = arrangement.fonts[spanIdx]
        for paint in font.paints
            if stroke
                strokePath(target, path, paint; transform = mat,
                    strokeWidth = strokeWidth, lineCap = lineCap,
                    lineJoin = lineJoin, miterLimit = miterLimit,
                    dashes = dashes)
            else
                fillPath(target, path, paint; transform = mat)
            end
        end
    end
    return nothing
end

"""Upstream `fillText(target, arrangement, transform)`."""
function fillText(target::Image, arrangement::Arrangement;
    transform::Mat3 = mat3())
    return _textUber(target, arrangement, transform, false)
end

"""Upstream `fillText(target, font, text, ...)` (typesets, then fills)."""
function fillText(target::Image, font::Font, text::String;
    transform::Mat3 = mat3(), bounds::Vec2 = Vec2(),
    hAlign::HorizontalAlignment = LeftAlign,
    vAlign::VerticalAlignment = TopAlign)
    fillText(target, typeset(font, text; bounds = bounds,
        hAlign = hAlign, vAlign = vAlign), transform = transform)
    return nothing
end

"""Upstream `strokeText(target, arrangement, ...)`."""
function strokeText(target::Image, arrangement::Arrangement;
    transform::Mat3 = mat3(), strokeWidth::Float32 = Float32(1),
    lineCap::LineCap = ButtCap, lineJoin::LineJoin = MiterJoin,
    miterLimit::Float32 = defaultMiterLimit,
    dashes::Vector{Float32} = Vector{Float32}())
    return _textUber(target, arrangement, transform, true;
        strokeWidth = strokeWidth, lineCap = lineCap, lineJoin = lineJoin,
        miterLimit = miterLimit, dashes = dashes)
end

"""Upstream `strokeText(target, font, text, ...)` (typesets, then strokes)."""
function strokeText(target::Image, font::Font, text::String;
    transform::Mat3 = mat3(), strokeWidth::Float32 = Float32(1),
    bounds::Vec2 = Vec2(),
    hAlign::HorizontalAlignment = LeftAlign,
    vAlign::VerticalAlignment = TopAlign,
    lineCap::LineCap = ButtCap, lineJoin::LineJoin = MiterJoin,
    miterLimit::Float32 = defaultMiterLimit,
    dashes::Vector{Float32} = Vector{Float32}())
    strokeText(target, typeset(font, text; bounds = bounds,
        hAlign = hAlign, vAlign = vAlign), transform = transform,
        strokeWidth = strokeWidth, lineCap = lineCap, lineJoin = lineJoin,
        miterLimit = miterLimit, dashes = dashes)
    return nothing
end

# ---------- loading ----------

"""Upstream `parseTtf` (bytes)."""
function parseTtf(buf::Vector{UInt8})
    return Typeface(parseOpenType(buf))
end

"""Upstream `parseOtf` (bytes; the port's subset is TTF/glyf-only, D015)."""
parseOtf(buf::Vector{UInt8}) = parseTtf(buf)

"""Upstream `readTypeface(filePath)`: extension-dispatched load.
The port supports .ttf/.otf (glyf); .svg and .ttc raise
"Unsupported font format" (D015 subset)."""
function readTypeface(filePath::String)
    ext = lowercase(splitext(filePath)[2])
    if ext in (".ttf", ".otf")
        tf = parseTtf(_readFileBytes(filePath))
        tf.filePath = filePath
        return tf
    end
    throw(ArgumentError("Unsupported font format"))
end

"""Upstream `readFont(filePath)`: a `Font` over the loaded typeface."""
readFont(filePath::String) = newFont(readTypeface(filePath))
