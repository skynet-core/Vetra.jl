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

# T029 shaped-placement records (the shaping logic lives in
# formats/shaping.jl, included after this file — the types precede
# `ParagraphLayout`, which references them).

"""Placed glyphs of one logical cluster (buffer order); x is
line-relative scratch pixels, y is baseline-relative (harfbuzz's
y_offset sign: positive = up — the renderer adds it to the scratch
baseline). `ws` marks whitespace entries (the line-end decoration
rule, §5.1)."""
struct _ShapedEntryPos
    glyphs::Vector{Tuple{Int, Float32, Float32, Float32}} # (gid, x, y, adv)
    rectX0::Float32
    rectX1::Float32
    ws::Bool
end

"""One shaped line: visual (L2R) order of the line's logical cluster
indices, placement per slot, span index per slot, and the line's
baseline (scratch pixels, vAlign already applied)."""
struct _ShapedLinePos
    order::Vector{Int}
    pos::Vector{_ShapedEntryPos}
    spans::Vector{Int}
    baselineY::Float32
end

"""The result of `layoutParagraph`: clusters, lines, and the underlying
`Arrangement` (rendered by `fillParagraph`/`strokeParagraph`).
`shaped` is the logical→visual cluster permutation per line (UAX#9 §5.3;
identity for the unshaped legacy path); `shapedPos`/`shapedFonts`
carry the shaped glyph placement and are empty on the legacy path."""
struct ParagraphLayout
    paragraph::Paragraph
    clusters::Vector{Cluster}
    lines::Vector{ParagraphLine}
    arrangement::Arrangement
    # per cluster: (rune range in arrangement.runes, anchor rune for line
    # assignment); the range is 1:0 when the cluster maps to no runes.
    clusterRunes::Vector{Tuple{UnitRange{Int}, Int}}
    shaped::Vector{Vector{Int}}
    shapedPos::Vector{_ShapedLinePos}
    shapedFonts::Vector{Font}
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
    # RTL construction is allowed (T029); the shaper requirement is
    # checked at layout time (docs/TEXT_LAYOUT.md §5.3).
    return Paragraph(spans, Float32(width), Float32(height),
        Float32(lineHeight), hAlign, vAlign, overflow, dir)
end

# ---------- grapheme clusters (UAX#29 subset, D031 §3) ----------

# Generated tables — do not edit by hand.
# Provenance: Unicode 16.0.0 (https://unicode.org/Public/16.0.0/ucd/).
#   _CLUSTER_EXTEND: derived property Grapheme_Extend
#     (DerivedCoreProperties-16.0.0.txt; = Me + Mn + Other_Grapheme_Extend),
#     BMP subset (220 ranges) plus U+200D (ZWJ is category Cf and therefore
#     absent from the derived property; UAX#29 GB9a/GB9d needs it in the
#     Extend class — U+200C already appears in the derived property).
#   _CLUSTER_MC: general category Mc (spacing combining marks),
#     from UnicodeData-16.0.0.txt, BMP subset (112 ranges).
# Regenerated 2026-11-09 (T029) by tools/oracle/gen_cluster_tables.py —
# the original T028 generation had range misalignment (base letters such
# as Devanagari 0905/0915/0936 and Myanmar 1000..100B were inside both
# tables; round-trip verified codepoint-exact against the UCD sources).
# Used by _canBreakCluster (docs/TEXT_LAYOUT.md §3).
const _CLUSTER_EXTEND = [
    0x0300, 0x036f, 0x0483, 0x0489, 0x0591, 0x05bd,
    0x05bf, 0x05bf, 0x05c1, 0x05c2, 0x05c4, 0x05c5,
    0x05c7, 0x05c7, 0x0610, 0x061a, 0x064b, 0x065f,
    0x0670, 0x0670, 0x06d6, 0x06dc, 0x06df, 0x06e4,
    0x06e7, 0x06e8, 0x06ea, 0x06ed, 0x0711, 0x0711,
    0x0730, 0x074a, 0x07a6, 0x07b0, 0x07eb, 0x07f3,
    0x07fd, 0x07fd, 0x0816, 0x0819, 0x081b, 0x0823,
    0x0825, 0x0827, 0x0829, 0x082d, 0x0859, 0x085b,
    0x0897, 0x089f, 0x08ca, 0x08e1, 0x08e3, 0x0902,
    0x093a, 0x093a, 0x093c, 0x093c, 0x0941, 0x0948,
    0x094d, 0x094d, 0x0951, 0x0957, 0x0962, 0x0963,
    0x0981, 0x0981, 0x09bc, 0x09bc, 0x09be, 0x09be,
    0x09c1, 0x09c4, 0x09cd, 0x09cd, 0x09d7, 0x09d7,
    0x09e2, 0x09e3, 0x09fe, 0x09fe, 0x0a01, 0x0a02,
    0x0a3c, 0x0a3c, 0x0a41, 0x0a42, 0x0a47, 0x0a48,
    0x0a4b, 0x0a4d, 0x0a51, 0x0a51, 0x0a70, 0x0a71,
    0x0a75, 0x0a75, 0x0a81, 0x0a82, 0x0abc, 0x0abc,
    0x0ac1, 0x0ac5, 0x0ac7, 0x0ac8, 0x0acd, 0x0acd,
    0x0ae2, 0x0ae3, 0x0afa, 0x0aff, 0x0b01, 0x0b01,
    0x0b3c, 0x0b3c, 0x0b3e, 0x0b3f, 0x0b41, 0x0b44,
    0x0b4d, 0x0b4d, 0x0b55, 0x0b57, 0x0b62, 0x0b63,
    0x0b82, 0x0b82, 0x0bbe, 0x0bbe, 0x0bc0, 0x0bc0,
    0x0bcd, 0x0bcd, 0x0bd7, 0x0bd7, 0x0c00, 0x0c00,
    0x0c04, 0x0c04, 0x0c3c, 0x0c3c, 0x0c3e, 0x0c40,
    0x0c46, 0x0c48, 0x0c4a, 0x0c4d, 0x0c55, 0x0c56,
    0x0c62, 0x0c63, 0x0c81, 0x0c81, 0x0cbc, 0x0cbc,
    0x0cbf, 0x0cc0, 0x0cc2, 0x0cc2, 0x0cc6, 0x0cc8,
    0x0cca, 0x0ccd, 0x0cd5, 0x0cd6, 0x0ce2, 0x0ce3,
    0x0d00, 0x0d01, 0x0d3b, 0x0d3c, 0x0d3e, 0x0d3e,
    0x0d41, 0x0d44, 0x0d4d, 0x0d4d, 0x0d57, 0x0d57,
    0x0d62, 0x0d63, 0x0d81, 0x0d81, 0x0dca, 0x0dca,
    0x0dcf, 0x0dcf, 0x0dd2, 0x0dd4, 0x0dd6, 0x0dd6,
    0x0ddf, 0x0ddf, 0x0e31, 0x0e31, 0x0e34, 0x0e3a,
    0x0e47, 0x0e4e, 0x0eb1, 0x0eb1, 0x0eb4, 0x0ebc,
    0x0ec8, 0x0ece, 0x0f18, 0x0f19, 0x0f35, 0x0f35,
    0x0f37, 0x0f37, 0x0f39, 0x0f39, 0x0f71, 0x0f7e,
    0x0f80, 0x0f84, 0x0f86, 0x0f87, 0x0f8d, 0x0f97,
    0x0f99, 0x0fbc, 0x0fc6, 0x0fc6, 0x102d, 0x1030,
    0x1032, 0x1037, 0x1039, 0x103a, 0x103d, 0x103e,
    0x1058, 0x1059, 0x105e, 0x1060, 0x1071, 0x1074,
    0x1082, 0x1082, 0x1085, 0x1086, 0x108d, 0x108d,
    0x109d, 0x109d, 0x135d, 0x135f, 0x1712, 0x1715,
    0x1732, 0x1734, 0x1752, 0x1753, 0x1772, 0x1773,
    0x17b4, 0x17b5, 0x17b7, 0x17bd, 0x17c6, 0x17c6,
    0x17c9, 0x17d3, 0x17dd, 0x17dd, 0x180b, 0x180d,
    0x180f, 0x180f, 0x1885, 0x1886, 0x18a9, 0x18a9,
    0x1920, 0x1922, 0x1927, 0x1928, 0x1932, 0x1932,
    0x1939, 0x193b, 0x1a17, 0x1a18, 0x1a1b, 0x1a1b,
    0x1a56, 0x1a56, 0x1a58, 0x1a5e, 0x1a60, 0x1a60,
    0x1a62, 0x1a62, 0x1a65, 0x1a6c, 0x1a73, 0x1a7c,
    0x1a7f, 0x1a7f, 0x1ab0, 0x1ace, 0x1b00, 0x1b03,
    0x1b34, 0x1b3d, 0x1b42, 0x1b44, 0x1b6b, 0x1b73,
    0x1b80, 0x1b81, 0x1ba2, 0x1ba5, 0x1ba8, 0x1bad,
    0x1be6, 0x1be6, 0x1be8, 0x1be9, 0x1bed, 0x1bed,
    0x1bef, 0x1bf3, 0x1c2c, 0x1c33, 0x1c36, 0x1c37,
    0x1cd0, 0x1cd2, 0x1cd4, 0x1ce0, 0x1ce2, 0x1ce8,
    0x1ced, 0x1ced, 0x1cf4, 0x1cf4, 0x1cf8, 0x1cf9,
    0x1dc0, 0x1dff, 0x200c, 0x200d, 0x20d0, 0x20f0,
    0x2cef, 0x2cf1, 0x2d7f, 0x2d7f, 0x2de0, 0x2dff,
    0x302a, 0x302f, 0x3099, 0x309a, 0xa66f, 0xa672,
    0xa674, 0xa67d, 0xa69e, 0xa69f, 0xa6f0, 0xa6f1,
    0xa802, 0xa802, 0xa806, 0xa806, 0xa80b, 0xa80b,
    0xa825, 0xa826, 0xa82c, 0xa82c, 0xa8c4, 0xa8c5,
    0xa8e0, 0xa8f1, 0xa8ff, 0xa8ff, 0xa926, 0xa92d,
    0xa947, 0xa951, 0xa953, 0xa953, 0xa980, 0xa982,
    0xa9b3, 0xa9b3, 0xa9b6, 0xa9b9, 0xa9bc, 0xa9bd,
    0xa9c0, 0xa9c0, 0xa9e5, 0xa9e5, 0xaa29, 0xaa2e,
    0xaa31, 0xaa32, 0xaa35, 0xaa36, 0xaa43, 0xaa43,
    0xaa4c, 0xaa4c, 0xaa7c, 0xaa7c, 0xaab0, 0xaab0,
    0xaab2, 0xaab4, 0xaab7, 0xaab8, 0xaabe, 0xaabf,
    0xaac1, 0xaac1, 0xaaec, 0xaaed, 0xaaf6, 0xaaf6,
    0xabe5, 0xabe5, 0xabe8, 0xabe8, 0xabed, 0xabed,
    0xfb1e, 0xfb1e, 0xfe00, 0xfe0f, 0xfe20, 0xfe2f,
    0xff9e, 0xff9f,
]

const _CLUSTER_MC = [
    0x0903, 0x0903, 0x093b, 0x093b, 0x093e, 0x0940,
    0x0949, 0x094c, 0x094e, 0x094f, 0x0982, 0x0983,
    0x09be, 0x09c0, 0x09c7, 0x09c8, 0x09cb, 0x09cc,
    0x09d7, 0x09d7, 0x0a03, 0x0a03, 0x0a3e, 0x0a40,
    0x0a83, 0x0a83, 0x0abe, 0x0ac0, 0x0ac9, 0x0ac9,
    0x0acb, 0x0acc, 0x0b02, 0x0b03, 0x0b3e, 0x0b3e,
    0x0b40, 0x0b40, 0x0b47, 0x0b48, 0x0b4b, 0x0b4c,
    0x0b57, 0x0b57, 0x0bbe, 0x0bbf, 0x0bc1, 0x0bc2,
    0x0bc6, 0x0bc8, 0x0bca, 0x0bcc, 0x0bd7, 0x0bd7,
    0x0c01, 0x0c03, 0x0c41, 0x0c44, 0x0c82, 0x0c83,
    0x0cbe, 0x0cbe, 0x0cc0, 0x0cc4, 0x0cc7, 0x0cc8,
    0x0cca, 0x0ccb, 0x0cd5, 0x0cd6, 0x0cf3, 0x0cf3,
    0x0d02, 0x0d03, 0x0d3e, 0x0d40, 0x0d46, 0x0d48,
    0x0d4a, 0x0d4c, 0x0d57, 0x0d57, 0x0d82, 0x0d83,
    0x0dcf, 0x0dd1, 0x0dd8, 0x0ddf, 0x0df2, 0x0df3,
    0x0f3e, 0x0f3f, 0x0f7f, 0x0f7f, 0x102b, 0x102c,
    0x1031, 0x1031, 0x1038, 0x1038, 0x103b, 0x103c,
    0x1056, 0x1057, 0x1062, 0x1064, 0x1067, 0x106d,
    0x1083, 0x1084, 0x1087, 0x108c, 0x108f, 0x108f,
    0x109a, 0x109c, 0x1715, 0x1715, 0x1734, 0x1734,
    0x17b6, 0x17b6, 0x17be, 0x17c5, 0x17c7, 0x17c8,
    0x1923, 0x1926, 0x1929, 0x192b, 0x1930, 0x1931,
    0x1933, 0x1938, 0x1a19, 0x1a1a, 0x1a55, 0x1a55,
    0x1a57, 0x1a57, 0x1a61, 0x1a61, 0x1a63, 0x1a64,
    0x1a6d, 0x1a72, 0x1b04, 0x1b04, 0x1b35, 0x1b35,
    0x1b3b, 0x1b3b, 0x1b3d, 0x1b41, 0x1b43, 0x1b44,
    0x1b82, 0x1b82, 0x1ba1, 0x1ba1, 0x1ba6, 0x1ba7,
    0x1baa, 0x1baa, 0x1be7, 0x1be7, 0x1bea, 0x1bec,
    0x1bee, 0x1bee, 0x1bf2, 0x1bf3, 0x1c24, 0x1c2b,
    0x1c34, 0x1c35, 0x1ce1, 0x1ce1, 0x1cf7, 0x1cf7,
    0x302e, 0x302f, 0xa823, 0xa824, 0xa827, 0xa827,
    0xa880, 0xa881, 0xa8b4, 0xa8c3, 0xa952, 0xa953,
    0xa983, 0xa983, 0xa9b4, 0xa9b5, 0xa9ba, 0xa9bb,
    0xa9be, 0xa9c0, 0xaa2f, 0xaa30, 0xaa33, 0xaa34,
    0xaa4d, 0xaa4d, 0xaa7b, 0xaa7b, 0xaa7d, 0xaa7d,
    0xaaeb, 0xaaeb, 0xaaee, 0xaaef, 0xaaf5, 0xaaf5,
    0xabe3, 0xabe4, 0xabe6, 0xabe7, 0xabe9, 0xabea,
    0xabec, 0xabec,
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

"""Lay out the paragraph. Engagement (docs/TEXT_LAYOUT.md §5.3): a
`RightToLeft` paragraph requires the T029 shaper (a missing provider
raises the explicit shaping error, D033); an LTR paragraph containing
strong-RTL content shapes when the provider is present and keeps the
legacy isolated-forms `typeset` rendering when absent (the T028
documented limit). Otherwise: the pinned `typeset` (alignment effective
only on constrained dimensions — §2.5), the ellipsis pass, clusters and
lines."""
function layoutParagraph(p::Paragraph)
    if p.dir === RightToLeft
        _requireHarfBuzz()
        return Base.invokelatest(_shapedLayout, p)
    end
    if _hasStrongRtl(p.spans) && Base.locate_package(_HB_PKGID) !== nothing
        _requireHarfBuzz()
        return Base.invokelatest(_shapedLayout, p)
    end
    return _legacyLayout(p)
end

"""The unshaped (legacy) layout: the pinned `typeset`, the ellipsis
pass, clusters and lines; `shaped` is the identity permutation."""
function _legacyLayout(p::Paragraph)
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
    shaped = [collect(ln.clusters) for ln in lines]
    return ParagraphLayout(p, clusters, lines, arrangement, cranges,
        shaped, _ShapedLinePos[], Font[])
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
    if !isempty(l.shapedPos)
        # shaped text (T029): GID placement, not the typeset arrangement
        if stroke
            _shapedUber(scratch, l, mat3(), true;
                strokeWidth = Float32(strokeWidth), lineCap = lineCap,
                lineJoin = lineJoin, miterLimit = Float32(miterLimit),
                dashes = dashes)
        else
            _shapedUber(scratch, l, mat3(), false)
        end
    elseif stroke
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
