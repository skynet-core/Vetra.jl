# T028: paragraph layout (D031, docs/TEXT_LAYOUT.md).
#
# Additive layer over the existing Span/Font/typeset machinery: the layout
# pass is the pinned `typeset` (byte-exact legacy behaviour), the code here
# adds the paragraph box/overflow, cluster pass, line/metrics objects and
# rendering. No new dependencies. LTR only — RTL raises a named
# ArgumentError until the T029 shaper lands.
#
# NOTE on this build's String semantics: `length(s)` and iteration are
# codepoint-based (as upstream Nim's `len`), while `s[i]` and `s[a:b]` are
# byte-based with character-boundary checks. Cluster indices are
# codepoints; `_charStarts` provides the byte conversion for slicing.

# ---------- enums and types ----------

"""Paragraph overflow policy (D031 §2.3)."""
struct OverflowPolicy
    kind::Int
end
const ClipOverflow = OverflowPolicy(0)
const EllipsisOverflow = OverflowPolicy(1)

"""Paragraph direction (D031 §5.3)."""
struct TextDirection
    kind::Int
end
const LeftToRight = TextDirection(0)
const RightToLeft = TextDirection(1)

"""A paragraph: styled runs in a width/height box (0 = unconstrained)."""
struct Paragraph
    spans::Vector{Span}
    width::Float32
    height::Float32
    lineHeight::Float32
    hAlign::HorizontalAlignment
    vAlign::VerticalAlignment
    overflow::OverflowPolicy
    dir::TextDirection
end

"""A grapheme cluster: codepoint range `[first, last)` (1-based, last
exclusive) within `span`'s text — docs/TEXT_LAYOUT.md §2.8/§3."""
struct Cluster
    span::Int
    first::Int
    last::Int
end

"""One laid-out line: cluster range + used font metrics + content width
(trailing spaces excluded, matching the `typeset` hAlign measurement)."""
struct ParagraphLine
    clusters::UnitRange{Int}
    ascent::Float32
    descent::Float32
    width::Float32
end

"""Layout facts (unclipped) — docs/TEXT_LAYOUT.md §2.9."""
struct ParagraphMetrics
    width::Float32
    height::Float32
    lineCount::Int
    maxAscent::Float32
    minDescent::Float32
end

"""The result of `layoutParagraph`: clusters, lines, and the underlying
`Arrangement` (rendered by `fillParagraph`/`strokeParagraph`)."""
struct ParagraphLayout
    paragraph::Paragraph
    clusters::Vector{Cluster}
    lines::Vector{ParagraphLine}
    arrangement::Arrangement
    # per cluster: (rune range in arrangement.runes, anchor rune for line
    # assignment); the range is 1:0 when the cluster maps to no runes.
    clusterRunes::Vector{Tuple{UnitRange{Int}, Int}}
end

# ---------- construction ----------

function newParagraph(text::String, font::Font;
    width::Real = 0, height::Real = 0,
    lineHeight::Real = autoLineHeight,
    hAlign::HorizontalAlignment = LeftAlign,
    vAlign::VerticalAlignment = TopAlign,
    overflow::OverflowPolicy = ClipOverflow,
    dir::TextDirection = LeftToRight)
    return newParagraph([newSpan(text, font)]; width = width,
        height = height, lineHeight = lineHeight, hAlign = hAlign,
        vAlign = vAlign, overflow = overflow, dir = dir)
end

function newParagraph(spans::Vector{Span};
    width::Real = 0, height::Real = 0,
    lineHeight::Real = autoLineHeight,
    hAlign::HorizontalAlignment = LeftAlign,
    vAlign::VerticalAlignment = TopAlign,
    overflow::OverflowPolicy = ClipOverflow,
    dir::TextDirection = LeftToRight)
    if dir === RightToLeft
        throw(ArgumentError("RTL requires the T029 shaper"))
    end
    return Paragraph(spans, Float32(width), Float32(height),
        Float32(lineHeight), hAlign, vAlign, overflow, dir)
end

# ---------- grapheme clusters (UAX#29 subset, D031 §3) ----------

# Generated tables — do not edit by hand.
# Provenance: Unicode 16.0.0 (https://unicode.org/Public/16.0.0/ucd/).
#   _CLUSTER_EXTEND: derived property Grapheme_Extend
#     (DerivedCoreProperties-16.0.0.txt; = Me + Mn + Other_Grapheme_Extend),
#     BMP subset (219 ranges) plus U+200D (ZWJ is category Cf and therefore
#     absent from the derived property; UAX#29 GB9a/GB9d needs it in the
#     Extend class — U+200C already appears in the derived property).
#   _CLUSTER_MC: general category Mc (spacing combining marks),
#     from UnicodeData-16.0.0.txt, BMP subset (104 ranges).
# Used by _canBreakCluster (docs/TEXT_LAYOUT.md §3).
const _CLUSTER_EXTEND = [
    0x0300, 0x036F, 0x0483, 0x0489, 0x0591, 0x05BD, 0x05BF, 0x05C1, 0x05C2,
    0x05C4, 0x05C5, 0x05C7, 0x0610, 0x061A, 0x064B, 0x065F, 0x0670, 0x06D6,
    0x06DC, 0x06DF, 0x06E4, 0x06E7, 0x06E8, 0x06EA, 0x06ED, 0x0711, 0x0730,
    0x074A, 0x07A6, 0x07B0, 0x07EB, 0x07F3, 0x07FD, 0x0816, 0x0819, 0x081B,
    0x0823, 0x0825, 0x0827, 0x0829, 0x082D, 0x0859, 0x085B, 0x0897, 0x089F,
    0x08CA, 0x08E1, 0x08E3, 0x0902, 0x093A, 0x093C, 0x0941, 0x0948, 0x094D,
    0x0951, 0x0957, 0x0962, 0x0963, 0x0981, 0x09BC, 0x09BE, 0x09C1, 0x09C4,
    0x09CD, 0x09D7, 0x09E2, 0x09E3, 0x09FE, 0x0A01, 0x0A02, 0x0A3C, 0x0A41,
    0x0A42, 0x0A47, 0x0A48, 0x0A4B, 0x0A4D, 0x0A51, 0x0A70, 0x0A71, 0x0A75,
    0x0A81, 0x0A82, 0x0ABC, 0x0AC1, 0x0AC5, 0x0AC7, 0x0AC8, 0x0ACD, 0x0AE2,
    0x0AE3, 0x0AFA, 0x0AFF, 0x0B01, 0x0B3C, 0x0B3E, 0x0B3F, 0x0B41, 0x0B44,
    0x0B4D, 0x0B55, 0x0B57, 0x0B62, 0x0B63, 0x0B82, 0x0BBE, 0x0BC0, 0x0BCD,
    0x0BD7, 0x0C00, 0x0C04, 0x0C3C, 0x0C3E, 0x0C40, 0x0C46, 0x0C48, 0x0C4A,
    0x0C4D, 0x0C55, 0x0C56, 0x0C62, 0x0C63, 0x0C81, 0x0CBC, 0x0CBF, 0x0CC0,
    0x0CC2, 0x0CC6, 0x0CC8, 0x0CCA, 0x0CCD, 0x0CD5, 0x0CD6, 0x0CE2, 0x0CE3,
    0x0D00, 0x0D01, 0x0D3B, 0x0D3C, 0x0D3E, 0x0D41, 0x0D44, 0x0D4D, 0x0D57,
    0x0D62, 0x0D63, 0x0D81, 0x0DCA, 0x0DCF, 0x0DD2, 0x0DD4, 0x0DD6, 0x0DDF,
    0x0E31, 0x0E34, 0x0E3A, 0x0E47, 0x0E4E, 0x0EB1, 0x0EB4, 0x0EBC, 0x0EC8,
    0x0ECE, 0x0F18, 0x0F19, 0x0F35, 0x0F37, 0x0F39, 0x0F71, 0x0F7E, 0x0F80,
    0x0F84, 0x0F86, 0x0F87, 0x0F8D, 0x0F97, 0x0F99, 0x0FBC, 0x0FC6, 0x102D,
    0x1030, 0x1032, 0x1037, 0x1039, 0x103A, 0x103D, 0x103E, 0x1058, 0x1059,
    0x105E, 0x1060, 0x1071, 0x1074, 0x1082, 0x1085, 0x1086, 0x108D, 0x109D,
    0x135D, 0x135F, 0x1712, 0x1715, 0x1732, 0x1734, 0x1752, 0x1753, 0x1772,
    0x1773, 0x17B4, 0x17B5, 0x17B7, 0x17BD, 0x17C6, 0x17C9, 0x17D3, 0x17DD,
    0x180B, 0x180D, 0x180F, 0x1885, 0x1886, 0x18A9, 0x1920, 0x1922, 0x1927,
    0x1928, 0x1932, 0x1939, 0x193B, 0x1A17, 0x1A18, 0x1A1B, 0x1A56, 0x1A58,
    0x1A5E, 0x1A60, 0x1A62, 0x1A65, 0x1A6C, 0x1A73, 0x1A7C, 0x1A7F, 0x1AB0,
    0x1ACE, 0x1B00, 0x1B03, 0x1B34, 0x1B3D, 0x1B42, 0x1B44, 0x1B6B, 0x1B73,
    0x1B80, 0x1B81, 0x1BA2, 0x1BA5, 0x1BA8, 0x1BAD, 0x1BE6, 0x1BE8, 0x1BE9,
    0x1BED, 0x1BEF, 0x1BF3, 0x1C2C, 0x1C33, 0x1C36, 0x1C37, 0x1CD0, 0x1CD2,
    0x1CD4, 0x1CE0, 0x1CE2, 0x1CE8, 0x1CED, 0x1CF4, 0x1CF8, 0x1CF9, 0x1DC0,
    0x1DFF, 0x200C, 0x200D, 0x20D0, 0x20F0, 0x2CEF, 0x2CF1, 0x2D7F, 0x2DE0,
    0x2DFF, 0x302A, 0x302F, 0x3099, 0x309A, 0xA66F, 0xA672, 0xA674, 0xA67D,
    0xA69E, 0xA69F, 0xA6F0, 0xA6F1, 0xA802, 0xA806, 0xA80B, 0xA825, 0xA826,
    0xA82C, 0xA8C4, 0xA8C5, 0xA8E0, 0xA8F1, 0xA8FF, 0xA926, 0xA92D, 0xA947,
    0xA951, 0xA953, 0xA980, 0xA982, 0xA9B3, 0xA9B6, 0xA9B9, 0xA9BC, 0xA9BD,
    0xA9C0, 0xA9E5, 0xAA29, 0xAA2E, 0xAA31, 0xAA32, 0xAA35, 0xAA36, 0xAA43,
    0xAA4C, 0xAA7C, 0xAAB0, 0xAAB2, 0xAAB4, 0xAAB7, 0xAAB8, 0xAABE, 0xAABF,
    0xAAC1, 0xAAEC, 0xAAED, 0xAAF6, 0xABE5, 0xABE8, 0xABED, 0xFB1E, 0xFE00,
    0xFE0F, 0xFE20, 0xFE2F, 0xFF9E, 0xFF9F,
]

const _CLUSTER_MC = [
    0x0903, 0x093B, 0x093E, 0x0940, 0x0949, 0x094C, 0x094E, 0x094F, 0x0982,
    0x0983, 0x09BE, 0x09C0, 0x09C7, 0x09CC, 0x09D7, 0x0A03, 0x0A3E, 0x0A40,
    0x0A83, 0x0ABE, 0x0AC0, 0x0AC9, 0x0ACC, 0x0B02, 0x0B03, 0x0B3E, 0x0B40,
    0x0B47, 0x0B4C, 0x0B57, 0x0BBE, 0x0BBF, 0x0BC1, 0x0BCC, 0x0BD7, 0x0C01,
    0x0C03, 0x0C41, 0x0C44, 0x0C82, 0x0C83, 0x0CBE, 0x0CC0, 0x0CC4, 0x0CC7,
    0x0CCB, 0x0CD5, 0x0CD6, 0x0CF3, 0x0D02, 0x0D03, 0x0D3E, 0x0D40, 0x0D46,
    0x0D4C, 0x0D57, 0x0D82, 0x0D83, 0x0DCF, 0x0DD1, 0x0DD8, 0x0DDF, 0x0DF2,
    0x0DF3, 0x0F3E, 0x0F3F, 0x0F7F, 0x102B, 0x102C, 0x1031, 0x1038, 0x103B,
    0x103C, 0x1056, 0x1057, 0x1062, 0x1064, 0x1067, 0x106D, 0x1083, 0x1084,
    0x1087, 0x108C, 0x108F, 0x109A, 0x109C, 0x1715, 0x1734, 0x17B6, 0x17BE,
    0x17C5, 0x17C7, 0x17C8, 0x1923, 0x1926, 0x1929, 0x1931, 0x1933, 0x1938,
    0x1A19, 0x1A1A, 0x1A55, 0x1A57, 0x1A61, 0x1A63, 0x1A64, 0x1A6D, 0x1A72,
    0x1B04, 0x1B35, 0x1B3B, 0x1B3D, 0x1B41, 0x1B43, 0x1B44, 0x1B82, 0x1BA1,
    0x1BA6, 0x1BA7, 0x1BAA, 0x1BE7, 0x1BEA, 0x1BEC, 0x1BEE, 0x1BF2, 0x1BF3,
    0x1C24, 0x1C2B, 0x1C34, 0x1C35, 0x1CE1, 0x1CF7, 0x302E, 0x302F, 0xA823,
    0xA824, 0xA827, 0xA880, 0xA881, 0xA8B4, 0xA8C3, 0xA952, 0xA953, 0xA983,
    0xA9B4, 0xA9B5, 0xA9BA, 0xA9BB, 0xA9BE, 0xA9C0, 0xAA2F, 0xAA30, 0xAA33,
    0xAA34, 0xAA4D, 0xAA7B, 0xAA7D, 0xAAEB, 0xAAEE, 0xAAEF, 0xAAF5, 0xABE3,
    0xABE4, 0xABE6, 0xABE7, 0xABE9, 0xABEA, 0xABEC,
]

"""Binary search over a flat `[lo, hi, lo, hi, ...]` ascending range list."""
function _inRanges(x::UInt32, ranges::Vector{UInt32})
    lo = 1
    hi = length(ranges) ÷ 2
    while lo <= hi
        mid = lo + (hi - lo) ÷ 2
        rlo = ranges[2 * mid - 1]
        rhi = ranges[2 * mid]
        if x < rlo
            hi = mid - 1
        elseif x > rhi
            lo = mid + 1
        else
            return true
        end
    end
    return false
end

const _CLUSTER_EXTEND32 = UInt32[x for x in _CLUSTER_EXTEND]
const _CLUSTER_MC32 = UInt32[x for x in _CLUSTER_MC]

"""BMP Cc (general category Cc): U+0000..U+001F, U+007F..U+009F."""
function _isCC(cp::UInt32)
    return cp <= UInt32(0x1f) || (UInt32(0x7f) <= cp <= UInt32(0x9f))
end

"""UAX#29 GB9a/GB9b (v1 subset): no break before Extend/Mc (the vendored
tables cover Me as well — Me is part of Grapheme_Extend)."""
function _isExtendOrMc(cp::UInt32)
    return _inRanges(cp, _CLUSTER_EXTEND32) || _inRanges(cp, _CLUSTER_MC32)
end

"""Hangul jamo class: 1=L, 2=V, 3=T, 4=precomposed syllable
(U+AC00..U+D7A3, LV/LVT not distinguished), 0=other."""
function _hangulClass(cp::UInt32)
    if UInt32(0x1100) <= cp <= UInt32(0x115f)
        return 1
    end
    if UInt32(0x1160) <= cp <= UInt32(0x11a7)
        return 2
    end
    if UInt32(0x11a8) <= cp <= UInt32(0x11ff)
        return 3
    end
    if UInt32(0xac00) <= cp <= UInt32(0xd7a3)
        return 4
    end
    return 0
end

"""UAX#29 GB8 narrow approximation (docs/TEXT_LAYOUT.md §3.1): no break
for L×{L,V,T}, V×T, and precomposed syllable × {V,T}."""
function _hangulNoBreak(a::UInt32, b::UInt32)
    ca = _hangulClass(a)
    cb = _hangulClass(b)
    return (ca == 1 || ca == 4) && (cb == 2 || cb == 3) ||
        (ca == 1 && cb == 1) ||
        (ca == 2 && cb == 3)
end

"""UAX#29 subset break decision: may a cluster boundary fall between
codepoint `a` (left) and `b` (right)? Rules in order: GB3 (control
sequences), GB9a/9b (Extend/Mc on the right), GB9d (after ZWJ), GB8
(Hangul approximation); otherwise break."""
function _canBreakCluster(a::UInt32, b::UInt32)
    if _isCC(a) && _isCC(b)
        return false
    end
    if _isExtendOrMc(b)
        return false
    end
    if a == UInt32(0x200d)
        return false
    end
    if _hangulNoBreak(a, b)
        return false
    end
    return true
end

"""Clusterize `text` (codepoint indices, this build's `String` unit)."""
function _clustersInSpan(spanIdx::Int, text::String)
    out = Vector{Cluster}()
    n = length(text)
    n == 0 && return out
    start = 1
    prev = UInt32(0)
    for (i, c) in enumerate(text)
        cp = UInt32(c)
        if i > 1 && _canBreakCluster(prev, cp)
            push!(out, Cluster(spanIdx, start, i))
            start = i
        end
        prev = cp
    end
    push!(out, Cluster(spanIdx, start, n + 1))
    return out
end

function _clusters(spans)
    out = Vector{Cluster}()
    for (s, span) in enumerate(spans)
        append!(out, _clustersInSpan(s, span.text))
    end
    return out
end

"""Byte start positions of every codepoint (this build slices `String` by
byte); the last entry is the sentinel `totalBytes + 1`."""
function _charStarts(text::String)
    bytes = Vector{UInt8}(text)
    starts = Vector{Int}(undef, length(text) + 1)
    k = 1
    for i in 1:length(bytes)
        b = bytes[i]
        if b < UInt8(0x80) || b > UInt8(0xbf)
            starts[k] = i
            k += 1
        end
    end
    starts[length(text) + 1] = length(bytes) + 1
    return starts
end

"""The first `k` codepoints of `text` (k >= 1), as a String; k == 0 is ""."""
function _takeCodepoints(text::String, k::Int)
    k <= 0 && return ""
    starts = _charStarts(text)
    return text[1:starts[k]]
end

"""Per cluster: (global rune range in `arrangement.runes`, anchor rune).
`typeset` drops control codepoints < 32 (except LF), so a cluster maps to
the retained subset of its codepoints; the anchor (next/previous retained
rune in the same span) pins control-only clusters to a line."""
function _clusterRuneRanges(arrangement::Arrangement, spans, clusters)
    nSpans = length(spans)
    retainedCum = Vector{Vector{Int}}(undef, nSpans)
    spanArrIdx = Dict{Int,Int}()
    j = 0
    for (s, span) in enumerate(spans)
        cum = Int[0]
        for cp in _otCodepoints(span.text)
            push!(cum, cum[end] + Int(cp >= _SP_RUNE || cp == _LF_RUNE))
        end
        retainedCum[s] = cum
        if cum[end] > 0
            j += 1
            spanArrIdx[s] = j
        end
    end
    out = Vector{Tuple{UnitRange{Int}, Int}}(undef, length(clusters))
    # cum invariant: cum[k] = number of retained codepoints among the first
    # k-1 codepoints (the leading 0 sits at slot 1; cps are 1-based, so the
    # k-th retained cp of the span is at global arrangement.spans[..][1]
    # + k - 1).
    for (ci, cl) in enumerate(clusters)
        cum = retainedCum[cl.span]
        nCp = length(cum) - 1
        nRetBefore = cum[cl.first]
        nRetIn = cum[cl.last] - cum[cl.first]
        if nRetIn > 0
            gstart = arrangement.spans[spanArrIdx[cl.span]][1]
            out[ci] = ((gstart + nRetBefore):(gstart + nRetBefore + nRetIn - 1),
                gstart + nRetBefore)
        else
            anchor = 0
            arrIdx = get(spanArrIdx, cl.span, 0)
            if arrIdx > 0
                gstart = arrangement.spans[arrIdx][1]
                i = cl.last
                while i <= nCp && cum[i + 1] == cum[i]
                    i += 1
                end
                if i <= nCp
                    anchor = gstart + cum[i + 1] - 1
                else
                    i = cl.first - 1
                    while i >= 1 && cum[i + 1] == cum[i]
                        i -= 1
                    end
                    if i >= 1
                        anchor = gstart + cum[i + 1] - 1
                    end
                end
            end
            out[ci] = ((1:0), anchor)
        end
    end
    return out
end

# ---------- layout ----------

"""The layout spans: the paragraph's spans with the paragraph's absolute
line height applied (each Font copied — source spans stay untouched)."""
function _layoutSpans(p::Paragraph)
    spans = Vector{Span}(undef, length(p.spans))
    for (i, s) in enumerate(p.spans)
        f = copy(s.font)
        if p.lineHeight >= 0
            f.lineHeight = p.lineHeight
        end
        spans[i] = Span(s.text, f)
    end
    return spans
end

"""Intrinsic content width of an arrangement line: furthest right edge
minus leftmost left edge over non-SPACE/non-LF selection rects.
(Post-alignment right edges would read the box width for
Center/RightAlign; `typeset` measures the same intrinsic width as its
hAlign `furthestX`.)"""
function _lineContentWidth(arrangement::Arrangement, ls::Int, le::Int)
    lo = nothing
    hi = Float32(0)
    for i in ls:le
        cp = arrangement.runes[i]
        if cp == _SP_RUNE || cp == _LF_RUNE
            continue
        end
        r = arrangement.selectionRects[i]
        if lo === nothing
            lo = r.x
        end
        hi = max(hi, r.x + r.w)
    end
    return lo === nothing ? Float32(0) : hi - lo
end

"""Line box (ascent, descent) from the pinned vertical pass: each
touching run's baseline offset is `roundHalfAway((ascent + lineGap/2) *
scale)` (lineGap resolves auto vs absolute exactly as `typeset` does),
the shared baseline sits at the max offset, and the run's box bottom is
offset + its line height. `ascent`/`descent` are the maxes (§2.4
"multi-run lines: max over runs")."""
function _lineBox(arrangement::Arrangement, ls::Int, le::Int)
    asc = Float32(0)
    desc = Float32(0)
    for (j, (start, stop)) in enumerate(arrangement.spans)
        if start <= le && stop >= ls
            f = arrangement.fonts[j]
            offset = Float32(roundHalfAway((ascent(f.typeface) +
                lineGap(f) / Float32(2)) * scale(f)))
            lh = f.lineHeight >= 0 ? f.lineHeight : defaultLineHeight(f)
            asc = max(asc, offset)
            desc = max(desc, lh - offset)
        end
    end
    return asc, desc
end

function _lineBoxOfFont(f::Font)
    offset = Float32(roundHalfAway((ascent(f.typeface) +
        lineGap(f) / Float32(2)) * scale(f)))
    lh = f.lineHeight >= 0 ? f.lineHeight : defaultLineHeight(f)
    return offset, lh - offset
end

const _ELLIPSIS_RUNE = UInt32(0x2026)

"""EllipsisOverflow (D031 §2.3): when the last line's content exceeds the
box, drop trailing clusters (fewest first, re-laying out each trial) until
the last line with the appended U+2026 fits. The ellipsis is placed in the
span holding the last kept cluster, and that span's effective font (after
fallback) must have the glyph — otherwise the trial is skipped; if no
trial fits, the original layout is returned and the clip binds."""
function _ellipsisTruncate(p::Paragraph, spans, arrangement::Arrangement,
    hAlign::HorizontalAlignment, vAlign::VerticalAlignment)
    n = length(arrangement.runes)
    n == 0 && return (spans, arrangement)
    ls, le = arrangement.lines[end]
    if _lineContentWidth(arrangement, ls, le) <= p.width
        return (spans, arrangement)
    end
    clusters = _clusters(spans)
    cranges = _clusterRuneRanges(arrangement, spans, clusters)
    kMax = 0
    for (_ci, cl) in enumerate(clusters)
        rng, anchor = cranges[_ci]
        firstR = isempty(rng) ? anchor : first(rng)
        if firstR >= ls && firstR <= le
            kMax += 1
        end
    end
    for k in 1:kMax
        trial = _truncateTrailing(spans, clusters, k)
        ellIdx = length(clusters) - k + 1
        # The ellipsis lives in the span of the first removed cluster.
        ellSpan = clusters[ellIdx].span
        fallbackTypeface(trial[ellSpan].font.typeface, _ELLIPSIS_RUNE) ===
            nothing && continue
        arrK = typeset(trial; bounds = Vec2(p.width, p.height),
            hAlign = hAlign, vAlign = vAlign, wrap = true)
        kls, kle = arrK.lines[end]
        if _lineContentWidth(arrK, kls, kle) <= p.width
            return (trial, arrK)
        end
    end
    return (spans, arrangement)
end

"""Remove the last `k` clusters; the ellipsis is appended to the span of
the first removed cluster (its kept text may be empty)."""
function _truncateTrailing(spans, clusters, k::Int)
    out = copy(spans)
    cut = clusters[length(clusters) - k + 1]
    for (s, sp) in enumerate(spans)
        if s < cut.span
            continue
        elseif s == cut.span
            kept = _takeCodepoints(sp.text, cut.first - 1)
            out[s] = Span(kept * "\u2026", sp.font)
        else
            out[s] = Span("", sp.font)
        end
    end
    return out
end

"""Build the paragraph lines from the arrangement: one line per
`arrangement.lines` entry; each cluster is assigned to the line of its
first retained rune (anchor for control-only clusters)."""
function _paragraphLines(arrangement::Arrangement, layoutSpans, clusters,
    cranges)
    n = length(arrangement.runes)
    if n == 0
        if isempty(layoutSpans)
            return [ParagraphLine(1:0, Float32(0), Float32(0), Float32(0))]
        end
        asc, desc = _lineBoxOfFont(layoutSpans[1].font)
        return [ParagraphLine(1:0, asc, desc, Float32(0))]
    end
    lines = Vector{ParagraphLine}()
    cFirst = 1
    for (ls, le) in arrangement.lines
        cLast = cFirst
        while cLast <= length(clusters)
            rng, anchor = cranges[cLast]
            firstR = isempty(rng) ? (anchor == 0 ? ls : anchor) : first(rng)
            if firstR < ls || firstR > le
                break
            end
            cLast += 1
        end
        cLast -= 1
        asc, desc = _lineBox(arrangement, ls, le)
        push!(lines, ParagraphLine(cFirst:cLast, asc, desc,
            _lineContentWidth(arrangement, ls, le)))
        cFirst = cLast + 1
    end
    return lines
end

"""Lay out the paragraph: the pinned `typeset` (alignment effective only
on constrained dimensions — §2.5), the ellipsis pass, clusters and lines."""
function layoutParagraph(p::Paragraph)
    spans = _layoutSpans(p)
    hAlign = p.width > 0 ? p.hAlign : LeftAlign
    vAlign = p.height > 0 ? p.vAlign : TopAlign
    arrangement = typeset(spans; bounds = Vec2(p.width, p.height),
        hAlign = hAlign, vAlign = vAlign, wrap = p.width > 0)
    if p.overflow === EllipsisOverflow && p.width > 0
        (spans, arrangement) = _ellipsisTruncate(p, spans, arrangement,
            hAlign, vAlign)
    end
    clusters = _clusters(spans)
    cranges = _clusterRuneRanges(arrangement, spans, clusters)
    lines = _paragraphLines(arrangement, spans, clusters, cranges)
    return ParagraphLayout(p, clusters, lines, arrangement, cranges)
end

"""Layout facts (unclipped) — docs/TEXT_LAYOUT.md §2.9."""
function paragraphMetrics(l::ParagraphLayout)
    w = Float32(0)
    h = Float32(0)
    a = Float32(0)
    d = Float32(0)
    for ln in l.lines
        w = max(w, ln.width)
        h += ln.ascent + ln.descent
        a = max(a, ln.ascent)
        d = max(d, ln.descent)
    end
    return ParagraphMetrics(w, h, length(l.lines), a, d)
end

# ---------- rendering ----------

"""Render the layout at (x, y) through the context. The arrangement is
drawn into a scratch and blitted via `drawImage`, so the context's
transform/clip/globalAlpha/mask always apply (a direct `_textUber` would
bypass them). When the box constrains a dimension, the scratch is
exactly the box (ClipOverflow's clip); the open dimension gets a
one-line-box margin (plus half the stroke width) so glyph ink
overshooting the hhea metrics is not cut.
`shortcut: the margin assumes ink stays within one line box of the
metrics; a glyph drawn far outside its metrics in a custom font could
still be cut on the open dimension.`"""
function _paragraphDraw(targetCtx::Context, l::ParagraphLayout, x::Real,
    y::Real, stroke::Bool; strokeWidth::Real = 1, lineCap::LineCap = ButtCap,
    lineJoin::LineJoin = MiterJoin, miterLimit::Real = defaultMiterLimit,
    dashes::Vector{Float32} = Vector{Float32}())
    p = l.paragraph
    m = paragraphMetrics(l)
    boxW = p.width > 0
    boxH = p.height > 0
    margin = m.maxAscent + m.minDescent +
        (stroke ? Float32(strokeWidth) / Float32(2) : Float32(0))
    w = boxW ? Int(ceil(p.width)) : Int(ceil(m.width + margin))
    h = boxH ? Int(ceil(p.height)) : Int(ceil(m.height + margin))
    if w <= 0 || h <= 0
        return nothing
    end
    scratch = newImage(w, h)
    if stroke
        _textUber(scratch, l.arrangement, mat3(), true;
            strokeWidth = Float32(strokeWidth), lineCap = lineCap,
            lineJoin = lineJoin, miterLimit = Float32(miterLimit),
            dashes = dashes)
    else
        _textUber(scratch, l.arrangement, mat3(), false)
    end
    drawImage(targetCtx, scratch, Float32(x), Float32(y))
    return nothing
end

"""Fill the paragraph at (x, y) (context variant)."""
function fillParagraph(ctx::Context, l::ParagraphLayout, x::Real, y::Real)
    return _paragraphDraw(ctx, l, x, y, false)
end

"""Fill the paragraph at (x, y) (image variant: a fresh context over the
image, so its existing pixels/alpha are preserved)."""
function fillParagraph(image::Image, l::ParagraphLayout, x::Real, y::Real)
    return fillParagraph(Context(image), l, x, y)
end

"""Stroke the paragraph at (x, y) (context variant)."""
function strokeParagraph(ctx::Context, l::ParagraphLayout, x::Real, y::Real;
    strokeWidth::Real = 1, lineCap::LineCap = ButtCap,
    lineJoin::LineJoin = MiterJoin, miterLimit::Real = defaultMiterLimit,
    dashes::Vector{Float32} = Vector{Float32}())
    return _paragraphDraw(ctx, l, x, y, true; strokeWidth = strokeWidth,
        lineCap = lineCap, lineJoin = lineJoin, miterLimit = miterLimit,
        dashes = dashes)
end

"""Stroke the paragraph at (x, y) (image variant)."""
function strokeParagraph(image::Image, l::ParagraphLayout, x::Real, y::Real;
    strokeWidth::Real = 1, lineCap::LineCap = ButtCap,
    lineJoin::LineJoin = MiterJoin, miterLimit::Real = defaultMiterLimit,
    dashes::Vector{Float32} = Vector{Float32}())
    return strokeParagraph(Context(image), l, x, y; strokeWidth = strokeWidth,
        lineCap = lineCap, lineJoin = lineJoin, miterLimit = miterLimit,
        dashes = dashes)
end
