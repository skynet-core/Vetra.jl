# ---------- fontformats/opentype (T009) ----------
# Upstream: pixie/fontformats/opentype.nim (30bb510). Ported subset (D015):
# table directory, cmap (Windows platform 3, formats 4 and 12), head, hhea,
# maxp, hmtx, name, OS/2, loca (format 0/1), glyf (simple + composite
# glyphs), kern (version 0), GPOS (pair-position format 1/2 via lookup
# type 2), post. NOT ported: CFF outlines (L864-1770), OpenType
# collections (parseOpenTypeCollection), GPOS script/feature lists (the
# upstream only parses the lookup list).
#
# Conventions:
# - Big-endian reads throughout (OpenType), 1-based byte positions;
#   `_eof(b, last)` fails when the last byte index exceeds the buffer.
# - Upstream `PixieError` maps to `ArgumentError`; upstream messages are
#   kept verbatim ("Unexpected error reading font data, EOF",
#   "Unsupported font <what>", "Missing required font table: <tag>").
# - Glyph outlines are cached in `glyphPaths` with the upstream Y-flip
#   applied once at cache fill; the typeface-level `getGlyphPath` copies
#   them out (`addPath`) before callers transform them.

const _otEofMsg = "Unexpected error reading font data, EOF"

function _otEof(buf::Vector{UInt8}, last::Int)
    last > length(buf) && throw(ArgumentError(_otEofMsg))
    return nothing
end

function _otUnsupported(what::String)
    throw(ArgumentError("Unsupported font $what"))
    return nothing
end

_u8(buf::Vector{UInt8}, p::Int) = Int(buf[p])
_i8(buf::Vector{UInt8}, p::Int) = Int(buf[p]) - (buf[p] >> 7 != 0 ? 256 : 0)
function _u16(buf::Vector{UInt8}, p::Int)
    _otEof(buf, p + 1)
    return Int(buf[p]) << 8 | Int(buf[p + 1])
end
function _i16(buf::Vector{UInt8}, p::Int)
    v = _u16(buf, p)
    return v - (v >> 15 != 0 ? 65536 : 0)
end
function _u32(buf::Vector{UInt8}, p::Int)
    _otEof(buf, p + 3)
    return Int(buf[p]) << 24 | Int(buf[p + 1]) << 16 |
        Int(buf[p + 2]) << 8 | Int(buf[p + 3])
end
function _u16seq(buf::Vector{UInt8}, p::Int, count::Int)
    _otEof(buf, p + 2 * count - 1)
    return Int[_u16(buf, p + 2 * i) for i in 0:(count - 1)]
end

"""Upstream `readVersion16Dot16` (major/minor decimal digits from a 16.16
fixed value; invalid digit patterns are unsupported)."""
function _otVersion16Dot16(buf::Vector{UInt8}, p::Int)
    _otEof(buf, p + 3)
    data = _u32(buf, p)
    major = (data & 0x000f0000) >> 16
    minor = (data & 0x0000f000) >> 12
    (major > 9 || minor > 9) && _otUnsupported("invalid version format")
    return (major, minor)
end

"""Upstream `readFixed16`: 2.14 fixed point scaled to 1/16384."""
_otFixed16(buf::Vector{UInt8}, p::Int) =
    Float32(_i16(buf, p)) / Float32(16384)

# ---------- tables ----------

struct OtcCmap
    version::Int
    numTables::Int
    runeToGlyphId::Dict{UInt32,UInt16}
end

struct OtcHead
    unitsPerEm::Int
    indexToLocFormat::Int
end

struct OtcHhea
    ascender::Int
    descender::Int
    lineGap::Int
    numberOfHMetrics::Int
end

struct OtcMaxp
    numGlyphs::Int
end

struct OtcHmtx
    advanceWidths::Vector{Int} # first numberOfHMetrics glyphs
    lsbHead::Vector{Int}
    lsbTail::Vector{Int}
end

struct OtcName
    # (nameID, languageID, text) records in file order (all platforms;
    # platform 3/encoding 1 records are UTF-16BE-decoded, as upstream).
    records::Vector{Tuple{Int,Int,String}}
end

struct OtcOS2
    version::Int
    yStrikeoutSize::Int
    yStrikeoutPosition::Int
    sCapHeight::Int
end

struct OtcPost
    underlinePosition::Int
    underlineThickness::Int
end

struct OtcLoca
    offsets::Vector{UInt32}
end

struct OtcGlyf
    offsets::Vector{UInt32}
end

struct OtcKern
    kerningPairs::Dict{Tuple{UInt16,UInt16},Float32}
end

struct OtcPairPos
    posFormat::Int
    coveredGlyphs::Set{UInt16}
    glyphPairAdjustments::Dict{Tuple{UInt16,UInt16},Int}
    glyphIdToClass1::Dict{UInt16,UInt16}
    glyphIdToClass2::Dict{UInt16,UInt16}
    classPairAdjustments::Dict{Tuple{UInt16,UInt16},Int}
end

struct OtcGpos
    pairPosTables::Vector{OtcPairPos}
end

mutable struct OtcOpenType
    buf::Vector{UInt8}
    tables::Dict{String,Tuple{Int,Int}} # tag -> (offset, length), 0-based
    cmap::OtcCmap
    head::OtcHead
    hhea::OtcHhea
    maxp::OtcMaxp
    hmtx::OtcHmtx
    name::OtcName
    os2::OtcOS2
    loca::Union{OtcLoca,Nothing}
    glyf::Union{OtcGlyf,Nothing}
    kern::Union{OtcKern,Nothing}
    gpos::Union{OtcGpos,Nothing}
    post::OtcPost
    glyphPaths::Dict{UInt32,Path}
end

# ---------- table parsers (upstream offsets are 0-based) ----------

function _otParseCmap(buf::Vector{UInt8}, off::Int)
    _otEof(buf, off + 3)
    version = _u16(buf, off)
    numTables = _u16(buf, off + 2)
    i = off + 4
    map = Dict{UInt32,UInt16}()
    for j in 1:numTables
        _otEof(buf, i + 7)
        platformID = _u16(buf, i)
        off32 = _u32(buf, i + 4)
        i += 8
        platformID == 3 || continue # Windows only (upstream: other TODOs)
        s = off + off32 # 1-based subtable start
        _otEof(buf, s + 1)
        format = _u16(buf, s)
        if format == 4
            _otEof(buf, s + 13)
            segCount = div(_u16(buf, s + 6), 2)
            i2 = s + 14
            _otEof(buf, i2 + 2 + 4 * segCount * 2 - 1)
            endCodes = _u16seq(buf, i2, segCount)
            i2 += 2 * segCount
            i2 += 2 # reservedPad
            startCodes = _u16seq(buf, i2, segCount)
            i2 += 2 * segCount
            idDeltas = _u16seq(buf, i2, segCount)
            i2 += 2 * segCount
            idRangeOffsetPos = i2
            idRangeOffsets = _u16seq(buf, i2, segCount)
            for k in 1:segCount
                endCode = endCodes[k]
                startCode = startCodes[k]
                idDelta = idDeltas[k]
                idRangeOffset = idRangeOffsets[k]
                for c in startCode:endCode
                    glyphId = 0
                    if idRangeOffset != 0
                        p = idRangeOffsetPos + 2 * (k - 1) +
                            idRangeOffset + 2 * (c - startCode)
                        _otEof(buf, p + 1)
                        glyphId = _u16(buf, p)
                        glyphId != 0 &&
                            (glyphId = (glyphId + idDelta) & 0xffff)
                    else
                        glyphId = (c + idDelta) & 0xffff
                    end
                    c != 65535 &&
                        (map[UInt32(c)] = UInt16(glyphId))
                end
            end
        elseif format == 12
            _otEof(buf, s + 15)
            numGroups = _u32(buf, s + 12)
            i2 = s + 16
            _otEof(buf, i2 + 12 * numGroups - 1)
            for k in 1:numGroups
                startCharCode = _u32(buf, i2)
                endCharCode = _u32(buf, i2 + 4)
                startGlyphId = _u32(buf, i2 + 8)
                for c in startCharCode:endCharCode
                    glyphId = startGlyphId + (c - startCharCode)
                    glyphId > 0xffff &&
                        throw(ArgumentError(
                            "Found glyph outside of uint16 range: $glyphId"))
                    map[UInt32(c)] = UInt16(glyphId)
                end
                i2 += 12
            end
        end
    end
    return OtcCmap(version, numTables, map)
end

function _otParseHead(buf::Vector{UInt8}, off::Int)
    _otEof(buf, off + 53)
    _u16(buf, off) != 1 && _otUnsupported("Head major version")
    _u16(buf, off + 2) != 0 && _otUnsupported("Head minor version")
    unitsPerEm = _u16(buf, off + 18)
    indexToLocFormat = _i16(buf, off + 50)
    _i16(buf, off + 52) != 0 && _otUnsupported("Head glyph data format")
    return OtcHead(unitsPerEm, indexToLocFormat)
end

function _otParseHhea(buf::Vector{UInt8}, off::Int)
    _otEof(buf, off + 35)
    _u16(buf, off) != 1 && _otUnsupported("Hhea major version")
    _u16(buf, off + 2) != 0 && _otUnsupported("Hhea minor version")
    ascender = _i16(buf, off + 4)
    descender = _i16(buf, off + 6)
    lineGap = _i16(buf, off + 8)
    _i16(buf, off + 32) != 0 && _otUnsupported("Hhea metric data format")
    numberOfHMetrics = _u16(buf, off + 34)
    return OtcHhea(ascender, descender, lineGap, numberOfHMetrics)
end

function _otParseMaxp(buf::Vector{UInt8}, off::Int)
    _otEof(buf, off + 31)
    (major, minor) = _otVersion16Dot16(buf, off)
    numGlyphs = _u16(buf, off + 4)
    if (major, minor) == (0, 5)
        return OtcMaxp(numGlyphs)
    end
    if (major, minor) == (1, 0)
        return OtcMaxp(numGlyphs)
    end
    _otUnsupported("Maxp version")
end

function _otParseHmtx(buf::Vector{UInt8}, off::Int,
    hhea::OtcHhea, maxp::OtcMaxp)
    n = maxp.numGlyphs
    nMet = hhea.numberOfHMetrics
    _otEof(buf, off + 4 * nMet + 2 * (n - nMet) - 1)
    advanceWidths = Vector{Int}(undef, nMet)
    lsbHead = Vector{Int}(undef, nMet)
    lsbTail = Vector{Int}(undef, n - nMet)
    i = off
    for g in 1:nMet
        advanceWidths[g] = _u16(buf, i)
        lsbHead[g] = _i16(buf, i + 2)
        i += 4
    end
    for g in 1:(n - nMet)
        lsbTail[g] = _i16(buf, i)
        i += 2
    end
    return OtcHmtx(advanceWidths, lsbHead, lsbTail)
end

function _otParseName(buf::Vector{UInt8}, off::Int)
    _otEof(buf, off + 5)
    _u16(buf, off) != 0 && _otUnsupported("Name format")
    count = _u16(buf, off + 2)
    stringOffset = _u16(buf, off + 4)
    i = off + 6
    _otEof(buf, i + 12 * count - 1)
    records = Vector{Tuple{Int,Int,String}}(undef, count)
    for j in 1:count
        platformID = _u16(buf, i)
        encodingID = _u16(buf, i + 2)
        languageID = _u16(buf, i + 4)
        nameID = _u16(buf, i + 6)
        len = _u16(buf, i + 8)
        recOff = _u16(buf, i + 10)
        p = off + stringOffset + recOff
        _otEof(buf, p + len - 1)
        text = String(buf[p:(p + len - 1)])
        if platformID == 3 && encodingID == 1 && languageID == 1033
            # Upstream decodes via flatty fromUTF16BE: surrogate pairs are
            # combined, an unpaired/invalid surrogate becomes tofu (U+25A1),
            # and a trailing odd byte is dropped. Note the upstream
            # `u1 - 0xd800 >= 0x800` is UNSIGNED wraparound: standalone is
            # u1 < 0xD800 or u1 >= 0xE000.
            cps = Vector{UInt32}()
            q = p
            while q + 1 <= p + len - 1
                u1 = _u16(buf, q)
                q += 2
                if u1 < 0xd800 || u1 >= 0xe000
                    push!(cps, UInt32(u1))
                else
                    u2 = _u16(buf, q)
                    q += 2
                    if (u1 & 0xfc00) == 0xd800 && (u2 & 0xfc00) == 0xdc00
                        push!(cps, UInt32(0x10000 + ((u1 & 0x3ff) << 10) +
                            (u2 & 0x3ff)))
                    else
                        push!(cps, UInt32(0x25a1))
                    end
                end
            end
            text = String([Char(cp) for cp in cps])
        end
        records[j] = (nameID, languageID, text)
        i += 12
    end
    return OtcName(records)
end

function _otParseOS2(buf::Vector{UInt8}, off::Int)
    _otEof(buf, off + 77)
    version = _u16(buf, off)
    yStrikeoutSize = _i16(buf, off + 26)
    yStrikeoutPosition = _i16(buf, off + 28)
    sCapHeight = 0
    version >= 2 && (sCapHeight = _i16(buf, off + 88))
    return OtcOS2(version, yStrikeoutSize, yStrikeoutPosition, sCapHeight)
end

function _otParseLoca(buf::Vector{UInt8}, off::Int,
    head::OtcHead, maxp::OtcMaxp)
    n = maxp.numGlyphs
    offsets = Vector{UInt32}(undef, n)
    if head.indexToLocFormat == 0
        _otEof(buf, off + 2 * n - 1)
        for g in 1:n
            offsets[g] = UInt32(_u16(buf, off + 2 * (g - 1)) * 2)
        end
    else
        _otEof(buf, off + 4 * n - 1)
        for g in 1:n
            offsets[g] = UInt32(_u32(buf, off + 4 * (g - 1)))
        end
    end
    return OtcLoca(offsets)
end

function _otParseGlyf(buf::Vector{UInt8}, glyfOffset::Int, loca::OtcLoca)
    return OtcGlyf(UInt32[UInt32(glyfOffset) + o for o in loca.offsets])
end

function _otParseKern(buf::Vector{UInt8}, off::Int)
    _otEof(buf, off + 1)
    version = _u16(buf, off)
    kerningPairs = Dict{Tuple{UInt16,UInt16},Float32}()
    if version == 0
        i = off + 2
        _otEof(buf, i + 1)
        nTables = _u16(buf, i)
        i += 2
        subTables = Vector{Tuple{Int,Vector{Tuple{UInt16,UInt16,Int}}}}()
        for t in 1:nTables
            _otEof(buf, i + 13)
            subVersion = _u16(buf, i)
            subVersion != 0 && _otUnsupported("Kern subtable version")
            coverage = _u16(buf, i + 4)
            (coverage >> 8) != 0 && _otUnsupported("Kern subtable coverage")
            nPairs = _u16(buf, i + 6)
            i += 14
            pairs = Vector{Tuple{UInt16,UInt16,Int}}(undef, nPairs)
            for p in 1:nPairs
                _otEof(buf, i + 5)
                pairs[p] = (_u16(buf, i), _u16(buf, i + 2),
                    _i16(buf, i + 4))
                i += 6
            end
            push!(subTables, (coverage, pairs))
            # Upstream re-walks every sub table added so far after each
            # add (the loop nests inside the sub-table loop).
            for (cov, ps) in subTables
                (cov & 1) == 0 && continue # horizontal data only
                for (l, r, v) in ps
                    v == 0 && continue
                    key = (UInt16(l), UInt16(r))
                    if (cov & 0x08) != 0 # Override
                        kerningPairs[key] = Float32(v)
                    else # Accumulate
                        kerningPairs[key] = Float32(v) +
                            get(kerningPairs, key, 0)
                    end
                end
            end
        end
    elseif version == 1
        discard = nothing # Mac format: upstream skips it
    else
        _otUnsupported("Kern version")
    end
    return OtcKern(kerningPairs)
end

# ---------- GPOS (pair position) ----------

_otValueFormatSize(valueFormat::Integer) =
    count_ones(Int(valueFormat) & 0xffff) * 2

function _otParseCoverage(buf::Vector{UInt8}, off::Int)
    _otEof(buf, off + 3)
    format = _u16(buf, off)
    covered = Set{UInt16}()
    i = off + 2
    if format == 1
        glyphCount = _u16(buf, i)
        i += 2
        for g in _u16seq(buf, i, glyphCount)
            push!(covered, UInt16(g))
        end
    elseif format == 2
        rangeCount = _u16(buf, i)
        i += 2
        _otEof(buf, i + 6 * rangeCount - 1)
        for r in 1:rangeCount
            startGlyphID = _u16(buf, i)
            endGlyphID = _u16(buf, i + 2)
            for g in startGlyphID:endGlyphID
                push!(covered, UInt16(g))
            end
            i += 6
        end
    else
        _otUnsupported("coverage format")
    end
    return covered
end

"""Upstream `parseValueRecord`: only xAdvance is consumed by the port;
the full record is skipped by its value-format size."""
function _otParseValueRecordXAdvance(buf::Vector{UInt8}, off::Int,
    valueFormat::Int)
    _otEof(buf, off + _otValueFormatSize(valueFormat) - 1)
    i = off
    xAdvance = 0
    if (valueFormat & 0b1) != 0
        i += 2
    end
    if (valueFormat & 0b10) != 0
        i += 2
    end
    if (valueFormat & 0b100) != 0
        xAdvance = _i16(buf, i)
    end
    return xAdvance
end

function _otParsePairPos(buf::Vector{UInt8}, off::Int)
    _otEof(buf, off + 3)
    posFormat = _u16(buf, off)
    covered = Set{UInt16}()
    glyphPair = Dict{Tuple{UInt16,UInt16},Int}()
    class1 = Dict{UInt16,UInt16}()
    class2 = Dict{UInt16,UInt16}()
    classPair = Dict{Tuple{UInt16,UInt16},Int}()
    i = off + 2
    if posFormat == 1 # glyph id pairs
        _otEof(buf, i + 7)
        coverageOffset = _u16(buf, i)
        valueFormat1 = _u16(buf, i + 2)
        valueFormat2 = _u16(buf, i + 4)
        pairSetCount = _u16(buf, i + 6)
        i += 8
        pairSetOffsets = _u16seq(buf, i, pairSetCount)
        i += 2 * pairSetCount
        vrSize = 2 + _otValueFormatSize(valueFormat1) +
            _otValueFormatSize(valueFormat2)
        pairSets = Vector{Vector{Tuple{UInt16,Int}}}()
        for psOff in pairSetOffsets
            p = off + psOff
            _otEof(buf, p + 1)
            count = _u16(buf, p)
            recs = Vector{Tuple{UInt16,Int}}(undef, count)
            for j in 1:count
                q = p + 2 + (j - 1) * vrSize
                recs[j] = (UInt16(_u16(buf, q)),
                    _otParseValueRecordXAdvance(buf, q + 2, valueFormat1))
            end
            push!(pairSets, recs)
        end
        covered = _otParseCoverage(buf, off + coverageOffset)
        if (valueFormat1 & 0b100) != 0
            _otEof(buf, off + coverageOffset + 3)
            covFormat = _u16(buf, off + coverageOffset)
            if covFormat == 1
                glyphCount = _u16(buf, off + coverageOffset + 2)
                glyphArray = _u16seq(buf, off + coverageOffset + 4,
                    glyphCount)
                glyphCount != pairSetCount &&
                    _otUnsupported("pair set count")
                for ci in 0:(glyphCount - 1)
                    ci >= length(pairSets) &&
                        _otUnsupported("pair set length")
                    glyphId = UInt16(glyphArray[ci + 1])
                    for (second, xa) in pairSets[ci + 1]
                        xa != 0 && (glyphPair[(glyphId, second)] = xa)
                    end
                end
            elseif covFormat == 2
                rangeCount = _u16(buf, off + coverageOffset + 2)
                for r in 1:rangeCount
                    recOff = off + coverageOffset + 4 + 6 * (r - 1)
                    startGlyphID = _u16(buf, recOff)
                    endGlyphID = _u16(buf, recOff + 2)
                    ci = _u16(buf, recOff + 4) # 0-based coverage index
                    for glyphId in startGlyphID:endGlyphID
                        if ci < 0 || ci >= length(pairSets)
                            _otUnsupported("pair set length")
                        end
                        for (second, xa) in pairSets[ci + 1]
                            xa != 0 &&
                                (glyphPair[(UInt16(glyphId), second)] = xa)
                        end
                        ci += 1
                    end
                end
            end
        end
    elseif posFormat == 2 # class pairs
        _otEof(buf, i + 13)
        coverageOffset = _u16(buf, i)
        valueFormat1 = _u16(buf, i + 2)
        valueFormat2 = _u16(buf, i + 4)
        classDef1Offset = _u16(buf, i + 6)
        classDef2Offset = _u16(buf, i + 8)
        class1Count = _u16(buf, i + 10)
        class2Count = _u16(buf, i + 12)
        i += 14
        c2Size = _otValueFormatSize(valueFormat1) +
            _otValueFormatSize(valueFormat2)
        _otEof(buf, i + c2Size * class1Count * class2Count - 1)
        for c1 in 1:class1Count
            for c2 in 1:class2Count
                p = i + (c1 - 1) * class2Count * c2Size +
                    (c2 - 1) * c2Size
                xa = _otParseValueRecordXAdvance(buf, p, valueFormat1)
                xa != 0 &&
                    (classPair[(UInt16(c1 - 1), UInt16(c2 - 1))] = xa)
            end
        end
        i += c2Size * class1Count * class2Count
        _otClassDef(buf, off + classDef1Offset, class1)
        _otClassDef(buf, off + classDef2Offset, class2)
        covered = _otParseCoverage(buf, off + coverageOffset)
    else
        _otUnsupported("pair pos format")
    end
    return OtcPairPos(posFormat, covered, glyphPair, class1, class2,
        classPair)
end

function _otClassDef(buf::Vector{UInt8}, off::Int, out::Dict{UInt16,UInt16})
    _otEof(buf, off + 1)
    format = _u16(buf, off)
    i = off + 2
    if format == 1
        startGlyphID = _u16(buf, i)
        glyphCount = _u16(buf, i + 2)
        i += 4
        for (k, v) in enumerate(_u16seq(buf, i, glyphCount))
            v != 0 && (out[UInt16(startGlyphID + k - 1)] = UInt16(v))
        end
    elseif format == 2
        classRangeCount = _u16(buf, i)
        i += 2
        for r in 1:classRangeCount
            startGlyphID = _u16(buf, i)
            endGlyphID = _u16(buf, i + 2)
            classVal = _u16(buf, i + 4)
            i += 6
            startGlyphID > endGlyphID &&
                _otUnsupported("glyph out of bounds")
            classVal == 0 && continue
            for g in startGlyphID:endGlyphID
                out[UInt16(g)] = UInt16(classVal)
            end
        end
    else
        _otUnsupported("class format")
    end
end

function _otParseGpos(buf::Vector{UInt8}, off::Int)
    _otEof(buf, off + 9)
    majorVersion = _u16(buf, off)
    majorVersion != 1 && _otUnsupported("Gpos major version")
    minorVersion = _u16(buf, off + 2)
    lookupListOffset = _u16(buf, off + 8)
    if minorVersion == 1
        _otEof(buf, off + 13)
    elseif minorVersion != 0
        _otUnsupported("Gpos minor version")
    end
    # Upstream offsets are PARENT-relative: lookup offsets are relative to
    # the lookup-list start, subtable offsets to their lookup start, and
    # pairPos internals to the pairPos start.
    ll = off + lookupListOffset
    _otEof(buf, ll + 1)
    lookupCount = _u16(buf, ll)
    lookupOffsets = _u16seq(buf, ll + 2, lookupCount)
    pairPosTables = Vector{OtcPairPos}()
    for lo in lookupOffsets
        p = ll + lo
        _otEof(buf, p + 5)
        lookupType = _u16(buf, p)
        subTableCount = _u16(buf, p + 4)
        subTableOffsets = _u16seq(buf, p + 6, subTableCount)
        if lookupType == 2
            for sto in subTableOffsets
                pairPos = _otParsePairPos(buf, p + sto)
                !isempty(pairPos.glyphPairAdjustments) ||
                    !isempty(pairPos.classPairAdjustments) || continue
                push!(pairPosTables, pairPos)
            end
        end
    end
    return OtcGpos(pairPosTables)
end

function _otParsePost(buf::Vector{UInt8}, off::Int)
    _otEof(buf, off + 13)
    _otVersion16Dot16(buf, off) # validates the 16.16 nibbles, as upstream
    underlinePosition = _i16(buf, off + 8)
    underlineThickness = _i16(buf, off + 10)
    return OtcPost(underlinePosition, underlineThickness)
end

# ---------- glyf glyphs ----------

const _otMaxCompositeRecursion = 64

function _otParseGlyphPath(buf::Vector{UInt8}, i0::Int,
    numberOfContours::Int)
    numberOfContours < 0 &&
        throw(ArgumentError("Glyph numberOfContours must be >= 0"))
    result = newPath()
    numberOfContours == 0 && return result
    i = i0
    _otEof(buf, i + 2 * numberOfContours + 1)
    endPts = _u16seq(buf, i, numberOfContours)
    i += 2 * numberOfContours
    instructionLength = _u16(buf, i)
    i += 2
    _otEof(buf, i + instructionLength - 1)
    i += instructionLength
    numPoints = endPts[end] + 1
    # Upstream walks `while point < numPoints`; REPEAT can overshoot, and
    # the X/Y loops below then hit the "point out of bounds" guard.
    flags = Vector{Int}()
    point = 0
    while point < numPoints
        _otEof(buf, i)
        flag = _u8(buf, i)
        i += 1
        push!(flags, flag)
        point += 1
        if (flag & 0b1000) != 0 # REPEAT_FLAG
            _otEof(buf, i)
            repeatCount = _u8(buf, i)
            i += 1
            for j in 1:repeatCount
                push!(flags, flag)
                point += 1
            end
        end
    end
    xs = Vector{Float32}(undef, numPoints)
    ys = Vector{Float32}(undef, numPoints)
    on = Vector{Bool}(undef, numPoints)
    prevX = 0
    for (pt, flag) in enumerate(flags)
        x = 0
        if (flag & 0b10) != 0
            _otEof(buf, i)
            x = _u8(buf, i)
            i += 1
            (flag & 0b10000) == 0 && (x = -x)
        else
            if (flag & 0b10000) == 0
                _otEof(buf, i + 1)
                x = _i16(buf, i)
                i += 2
            end
        end
        prevX += x
        pt > numPoints && _otUnsupported("point out of bounds")
        xs[pt] = Float32(prevX)
        on[pt] = (flag & 1) != 0
    end
    prevY = 0
    for (pt, flag) in enumerate(flags)
        y = 0
        if (flag & 0b100) != 0
            _otEof(buf, i)
            y = _u8(buf, i)
            i += 1
            (flag & 0b100000) == 0 && (y = -y)
        else
            if (flag & 0b100000) == 0
                _otEof(buf, i + 1)
                y = _i16(buf, i)
                i += 2
            end
        end
        prevY += y
        ys[pt] = Float32(prevY)
    end
    startIdx = 1
    for c in 1:numberOfContours
        # endPts are 0-based; upstream slices points[startIdx .. endIdx]
        # inclusive, so the 1-based stop is endPts[c] + 1.
        endIdx = endPts[c] + 1
        contourX = xs[startIdx:(endIdx)]
        contourY = ys[startIdx:(endIdx)]
        contourOn = on[startIdx:(endIdx)]
        startIdx = endIdx + 1
        # Upstream walks (curr, next) with wrap-around; the first segment
        # decides the moveTo target.
        n = length(contourX)
        x0 = contourX[n]; y0 = contourY[n]; o0 = contourOn[n]
        x1 = contourX[1]; y1 = contourY[1]; o1 = contourOn[1]
        if o0
            moveTo(result, x0, y0)
        elseif o1
            moveTo(result, x1, y1)
        else
            moveTo(result, (x0 + x1) / Float32(2), (y0 + y1) / Float32(2))
        end
        for pt in 1:n
            # Upstream reassigns `curr = next` then branches on `curr`, so
            # the on-curve segment targets the CURRENT point (px,py) and the
            # quadratic control is current with endpoint at next (or its
            # midpoint when next is off-curve).
            px = contourX[pt]; py = contourY[pt]; po = contourOn[pt]
            nx = contourX[pt % n + 1]; ny = contourY[pt % n + 1]
            no = contourOn[pt % n + 1]
            if po
                lineTo(result, px, py)
            else
                nx2 = nx; ny2 = ny
                if !no
                    nx2 = (px + nx) / Float32(2)
                    ny2 = (py + ny) / Float32(2)
                end
                quadraticCurveTo(result, px, py, nx2, ny2)
            end
        end
        closePath(result)
    end
    return result
end

function _otParseCompositeGlyph(ot::OtcOpenType, i0::Int,
    recursionDepth::Int)
    buf = ot.buf
    result = newPath()
    i = i0
    moreComponents = true
    while moreComponents
        _otEof(buf, i + 3)
        flags = _u16(buf, i)
        i += 2
        glyphId = _u16(buf, i)
        i += 2
        dx = Float32(0); dy = Float32(0)
        if (flags & 1) != 0 # args are int16
            _otEof(buf, i + 3)
            if (flags & 0b10) != 0 # offsets
                dx = Float32(_i16(buf, i))
                dy = Float32(_i16(buf, i + 2))
            end
            i += 4
        else # args are int8
            _otEof(buf, i + 1)
            if (flags & 0b10) != 0
                dx = Float32(_i8(buf, i))
                dy = Float32(_i8(buf, i + 1))
            end
            i += 2
        end
        xScale = Float32(1); scale01 = Float32(0)
        scale10 = Float32(0); yScale = Float32(1)
        if (flags & 0b1000) != 0 # WE_HAVE_A_SCALE
            _otEof(buf, i + 1)
            xScale = _otFixed16(buf, i)
            yScale = xScale
            i += 2
        elseif (flags & 0b1000000) != 0 # WE_HAVE_AN_X_AND_Y_SCALE
            _otEof(buf, i + 3)
            xScale = _otFixed16(buf, i)
            yScale = _otFixed16(buf, i + 2)
            i += 4
        elseif (flags & 0b10000000) != 0 # WE_HAVE_A_TWO_BY_TWO
            _otEof(buf, i + 7)
            xScale = _otFixed16(buf, i)
            scale10 = _otFixed16(buf, i + 2)
            scale01 = _otFixed16(buf, i + 4)
            yScale = _otFixed16(buf, i + 6)
            i += 8
        end
        subPath = _otParseGlyfGlyph(ot, UInt16(glyphId), recursionDepth + 1)
        transform(subPath, Mat3((xScale, scale10, Float32(0),
            scale01, yScale, Float32(0), dx, dy, Float32(1))))
        addPath(result, subPath)
        moreComponents = (flags & 0b100000) != 0
    end
    return result
end

function _otParseGlyfGlyph(ot::OtcOpenType, glyphId::UInt16,
    recursionDepth::Int = 0)
    recursionDepth > _otMaxCompositeRecursion &&
        throw(ArgumentError("Invalid composite glyph recursion"))
    gi = Int(glyphId) + 1
    gi > length(ot.glyf.offsets) &&
        throw(ArgumentError("Invalid glyph ID $(Int(glyphId))"))
    glyphOffset = ot.glyf.offsets[gi]
    if gi + 1 <= length(ot.glyf.offsets) &&
        glyphOffset == ot.glyf.offsets[gi + 1]
        # Empty glyph
        return newPath()
    end
    i = Int(glyphOffset) + 1
    _otEof(ot.buf, i + 9)
    numberOfContours = _i16(ot.buf, i)
    i += 10
    if numberOfContours < 0
        return _otParseCompositeGlyph(ot, i, recursionDepth)
    else
        return _otParseGlyphPath(ot.buf, i, numberOfContours)
    end
end

# ---------- entry point ----------

"""
Parse an OpenType/TTF buffer (upstream `parseOpenType`). Required tables:
cmap, head, hhea, maxp, hmtx, name, OS/2, post; outlines via glyf+loca
(CFF-only fonts raise "Unsupported font CFF outlines" — D015).
"""
function parseOpenType(buf::Vector{UInt8})
    n = length(buf)
    _otEof(buf, 12)
    numTables = _u16(buf, 5)
    _otEof(buf, 12 + numTables * 16)
    tables = Dict{String,Tuple{Int,Int}}()
    i = 13 # 1-based first table record
    for j in 1:numTables
        tag = String(buf[i:(i + 3)])
        offset = _u32(buf, i + 8)
        len = _u32(buf, i + 12)
        tables[tag] = (offset, len)
        i += 16
    end
    off(tag::String) = get(tables, tag, nothing) === nothing ?
        throw(ArgumentError("Missing required font table: $tag")) :
        tables[tag][1] + 1
    ot = OtcOpenType(
        buf, tables,
        OtcCmap(0, 0, Dict{UInt32,UInt16}()),
        OtcHead(0, 0), OtcHhea(0, 0, 0, 0), OtcMaxp(0),
        OtcHmtx(Int[], Int[], Int[]), OtcName(Tuple{Int,Int,String}[]),
        OtcOS2(0, 0, 0, 0), nothing, nothing, nothing, nothing,
        OtcPost(0, 0), Dict{UInt32,Path}())
    ot.cmap = _otParseCmap(buf, off("cmap"))
    ot.head = _otParseHead(buf, off("head"))
    ot.hhea = _otParseHhea(buf, off("hhea"))
    ot.maxp = _otParseMaxp(buf, off("maxp"))
    ot.hmtx = _otParseHmtx(buf, off("hmtx"), ot.hhea, ot.maxp)
    ot.name = _otParseName(buf, off("name"))
    ot.os2 = _otParseOS2(buf, off("OS/2"))
    if haskey(tables, "loca") && haskey(tables, "glyf")
        ot.loca = _otParseLoca(buf, tables["loca"][1] + 1,
            ot.head, ot.maxp)
        ot.glyf = _otParseGlyf(buf, tables["glyf"][1], ot.loca)
    elseif haskey(tables, "CFF ")
        _otUnsupported("CFF outlines")
    else
        _otUnsupported("glyph outlines")
    end
    if haskey(tables, "kern")
        ot.kern = _otParseKern(buf, tables["kern"][1] + 1)
    end
    if haskey(tables, "GPOS")
        ot.gpos = _otParseGpos(buf, tables["GPOS"][1] + 1)
    end
    ot.post = _otParsePost(buf, off("post"))
    return ot
end

# ---------- consumers ----------

_otGlyphId(ot::OtcOpenType, rune::UInt32) =
    get(ot.cmap.runeToGlyphId, rune, 0)

"""Upstream `hasGlyph`."""
hasGlyph(ot::OtcOpenType, rune::UInt32) =
    haskey(ot.cmap.runeToGlyphId, rune)

"""Upstream `getGlyphPath` (cached in the table; the flip is applied once
at cache fill). Callers copy it out (`addPath`) before transforming."""
function getGlyphPath(ot::OtcOpenType, rune::UInt32)
    if !haskey(ot.glyphPaths, rune)
        path = _otParseGlyfGlyph(ot, _otGlyphId(ot, rune))
        transform(path, scale(Vec2(Float32(1), Float32(-1))))
        ot.glyphPaths[rune] = path
    end
    return ot.glyphPaths[rune]
end

"""Upstream `getAdvance` (hmtx; out-of-range glyphs use the last metric)."""
function getAdvance(ot::OtcOpenType, rune::UInt32)
    glyphId = Int(_otGlyphId(ot, rune))
    if glyphId < length(ot.hmtx.advanceWidths)
        return Float32(ot.hmtx.advanceWidths[glyphId + 1])
    end
    return Float32(ot.hmtx.advanceWidths[end])
end

"""Upstream `getLeftSideBearing`."""
function getLeftSideBearing(ot::OtcOpenType, rune::UInt32)
    glyphId = Int(_otGlyphId(ot, rune))
    if glyphId < length(ot.hmtx.lsbHead)
        return Float32(ot.hmtx.lsbHead[glyphId + 1])
    end
    index = glyphId - length(ot.hmtx.lsbHead)
    # Upstream (opentype.nim getLeftSideBearing) guards with `index > 0`,
    # so the first trailing glyph returns 0.
    if index > 0 && index < length(ot.hmtx.lsbTail)
        return Float32(ot.hmtx.lsbTail[index + 1])
    end
    return Float32(0)
end

"""Upstream `getKerningAdjustment` (GPOS pair-position first, then the
legacy kern table; font units)."""
function getKerningAdjustment(ot::OtcOpenType, left::UInt32, right::UInt32)
    if !haskey(ot.cmap.runeToGlyphId, left) ||
        !haskey(ot.cmap.runeToGlyphId, right)
        return Float32(0)
    end
    leftGlyphId = ot.cmap.runeToGlyphId[left]
    rightGlyphId = ot.cmap.runeToGlyphId[right]
    if ot.gpos !== nothing
        for pairPos in ot.gpos.pairPosTables
            leftGlyphId in pairPos.coveredGlyphs || continue
            if pairPos.posFormat == 1
                v = get(pairPos.glyphPairAdjustments,
                    (leftGlyphId, rightGlyphId), nothing)
                v === nothing || return Float32(v)
            elseif pairPos.posFormat == 2
                leftClass = get(pairPos.glyphIdToClass1, leftGlyphId, 0)
                rightClass = get(pairPos.glyphIdToClass2, rightGlyphId, 0)
                v = get(pairPos.classPairAdjustments,
                    (leftClass, rightClass), nothing)
                v === nothing || return Float32(v)
            end
        end
        return Float32(0)
    end
    if ot.kern !== nothing
        return get(ot.kern.kerningPairs, (leftGlyphId, rightGlyphId), 0)
    end
    return Float32(0)
end

"""Upstream `isCCW`: `opentype.cff == nil` — true for glyf fonts (the
upstream comment contradicts its code; the code is pinned). computePaths
passes this straight to `rect`'s `clockwise` argument."""
isCCW(ot::OtcOpenType) = ot.glyf !== nothing

"""Upstream `fullName`: name record 6 in language 1033, first match."""
function fullName(ot::OtcOpenType)
    for (nameID, languageID, text) in ot.name.records
        nameID == 6 && languageID == 1033 && return text
    end
    return ""
end
