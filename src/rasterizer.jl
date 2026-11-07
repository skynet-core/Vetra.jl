# ---------- rasterizer (T004, solid fills; T010 overlaps) ----------
# Upstream: pixie/paths.nim -- PartitionEntry/Partition, shapesToSegments
# (quantizeY), computeBounds(segments), initPartitionEntry / solveX / solveY /
# midpointX, requiresAntiAliasing, partitionSegments, maxEntryCount,
# sortHits, shouldFill, walk, computeCoverage (24.8 fixed point, quality=5
# AA samples), the trapezoid fast path of fillShapes, fillShapes, overlaps
# (scanline point-in-path test, T010), and the
# NormalBlend/OverwriteBlend branches of fillHits / fillCoverage.
# Helpers from pinned sources: pixie/internal.nim `intersectsInside`,
# bumpy `intersects(Line, Segment)`, vmath `quantize`.
#
# Pinned arithmetic is followed exactly: Float32 throughout, `div` and
# truncation-toward-zero integer casts (`Int32`, `p ÷ 256`), coverage
# accumulation in uint8 with wrap (upstream release builds; a scalar build
# would raise on overflow), epsilon = 0.0001 * pi offsets, and `hasCoverage`
# with ties-away-from-zero rounding (`roundHalfAway`, not Base round).
# Upstream UB territory (writes before the clipped row start for paths that
# extend left of the image) is clipped here instead of written out of bounds.
# The other blend branches (masks, Paint gradients) come with Paint (T007a,
# blends.jl) and blender() now dispatches all 20 modes: MaskBlend carries the
# upstream `clearsUncovered` semantics -- uncovered row parts are cleared,
# covered parts go through blendMask (paths.nim fillHits/fillCoverage/
# fillShapes L1466-1591, L1612-1630, L1823-1885, L1926-1928). BlendMode and
# its constants live in blends.jl (included before this file).

"""A scanline hit: x in 24.8 fixed point (256 units per pixel) + winding."""
struct Hit
    at::Int32
    winding::Int16
end

"""One clip of a segment inside a partition (upstream `PartitionEntry`,
a mutable `var object` whose `segment` is clipped in place):
m/b are the line x(y) = m * x + b (m = 0 holds vertical lines in b)."""
mutable struct PartitionEntry
    segment::Segment
    m::Float32
    b::Float32
    winding::Int16
end

"""A y-clip of segments (upstream `Partition`)."""
mutable struct Partition
    entries::Vector{PartitionEntry}
    requiresAntiAliasing::Bool
    twoNonintersectingSpanningSegments::Bool
    top::Int
    bottom::Int
end
function Partition()
    return Partition(Vector{PartitionEntry}(), false, false, 0, 0)
end

"""Build a line representation (upstream `initPartitionEntry`)."""
function initPartitionEntry(segment::Segment, winding::Int16)
    d = segment.at.x - segment.to.x
    if d == 0f0
        m = 0f0
        b = segment.at.x # keep m = 0 and store the x in b
    else
        m = (segment.at.y - segment.to.y) / d
        b = segment.at.y - m * segment.at.x
    end
    return PartitionEntry(segment, m, b, winding)
end

"""x coordinate of a line at y (upstream `solveX`)."""
function solveX(e::PartitionEntry, y::Float32)
    return e.m == 0f0 ? e.b : (y - e.b) / e.m
end

"""y coordinate of a line at x (upstream `solveY`)."""
solveY(e::PartitionEntry, x::Float32) = e.m * x + e.b

midpointX(s::Segment) = (s.at.x + s.to.x) * 0.5f0 # upstream `midpointX`

"""
True if the segment needs anti-aliasing (upstream
`requiresAntiAliasing(segment)`: any non-vertical or fractional coordinate).
"""
function requiresAASegment(s::Segment)
    hasFractional(v::Float32) = (v - trunc(v)) != 0f0
    return s.at.x != s.to.x ||
        hasFractional(s.at.x) || # at.x and to.x are the same here
        hasFractional(s.at.y) || hasFractional(s.to.y)
end

function requiresAAEntries(entries::Vector{PartitionEntry})
    for e in entries
        requiresAASegment(e.segment) && return true
    end
    return false
end

"""
Quantize y onto the 1/256 grid to prevent leaks (upstream `quantizeY`,
vmath `quantize(v, n) = trunc(v / n) * n`; the power-of-two ops make this
identical to `trunc(v * 256) / 256`).
"""
quantizeY(v::Vec2) = Vec2(v.x, trunc(v.y * 256f0) / 256f0)

"""A segment with its winding direction (upstream `(Segment, int16)`)."""
struct SegW
    segment::Segment
    winding::Int16
end

"""
Convert the shapes into filtered segments with winding
(upstream `shapesToSegments`): closing zero-length edges skipped, horizontal
segments dropped when `skipHorizontal`, downward segments swapped to
upward with winding -1.
"""
function shapesToSegments(shapes::Vector{Vector{Vec2}}, skipHorizontal::Bool)
    out = Vector{SegW}()
    for poly in shapes
        isempty(poly) && continue
        prev = quantizeY(poly[end])
        for (k, v) in enumerate(poly)
            cur = quantizeY(v)
            if k == 1 && prev == cur
                continue # the closing point duplicates the start
            end
            seg = Segment(prev, cur)
            prev = cur
            if skipHorizontal && seg.at.y == seg.to.y
                continue
            end
            winding = Int16(1)
            if seg.at.y > seg.to.y
                seg = Segment(seg.to, seg.at)
                winding = Int16(-1)
            end
            push!(out, SegW(seg, winding))
        end
    end
    return out
end

"""
Bounding box of the segments (upstream `computeBounds(segments)`); with no
segments or NaN bounds the zero Rect is returned (fillPath then no-ops).
"""
function computeBoundsOfSegments(segments::Vector{SegW})
    isempty(segments) && return Rect(0f0, 0f0, 0f0, 0f0)
    xMin = typemax(Float32)
    xMax = typemin(Float32)
    yMin = typemax(Float32)
    yMax = typemin(Float32)
    for s in segments
        xMin = min(xMin, min(s.segment.at.x, s.segment.to.x))
        xMax = max(xMax, max(s.segment.at.x, s.segment.to.x))
        yMin = min(yMin, s.segment.at.y)
        yMax = max(yMax, s.segment.to.y)
    end
    if isnan(xMin) || isnan(xMax) || isnan(yMin) || isnan(yMax)
        return Rect(0f0, 0f0, 0f0, 0f0)
    end
    return Rect(xMin, yMin, xMax - xMin, yMax - yMin)
end

"""
Put the segments into the partitions they intersect (upstream
`partitionSegments`): at most `max(1, height ÷ 4)` partitions, at most one
per two segments, the last one reaching the actual bottom; entries spanning
an entire partition are clipped to it, and two non-intersecting spanning
entries set the fast-path flag (ordered left-to-right).
"""
function partitionSegments(segments::Vector{SegW}, top::Int, height::Int)
    maxPartitions = max(1, height ÷ 4)
    numPartitions = min(maxPartitions, max(1, length(segments) ÷ 2))
    partitionHeight = height ÷ numPartitions
    parts = Vector{Partition}(undef, numPartitions)
    for i in 1:numPartitions
        parts[i] = Partition()
    end
    parts[1].top = top
    parts[1].bottom = top + partitionHeight
    for i in 2:numPartitions
        parts[i].top = parts[i - 1].bottom
        parts[i].bottom = parts[i - 1].bottom + partitionHeight
    end
    # The final partition reaches the actual bottom (rounding remainder).
    parts[numPartitions].bottom = top + height

    entries = [initPartitionEntry(s.segment, s.winding) for s in segments]
    if numPartitions == 1
        parts[1].entries = entries
    else
        partIndex(v::Float32) =
            # upstream: `max(0, at.y - start).uint32 div partitionHeight`
            # (0-based); +1 for Julia indexing
            min(max(0, Int(trunc(v - Float32(top)))) ÷ partitionHeight, numPartitions - 1) + 1
        counts = zeros(Int, numPartitions)
        for s in segments
            for pi in partIndex(s.segment.at.y):partIndex(s.segment.to.y)
                counts[pi] += 1
            end
        end
        for pi in 1:numPartitions
            parts[pi].entries = Vector{PartitionEntry}(undef, counts[pi])
        end
        cursor = zeros(Int, numPartitions)
        for (k, s) in enumerate(segments)
            e = entries[k]
            for pi in partIndex(s.segment.at.y):partIndex(s.segment.to.y)
                # fresh wrapper per partition: upstream `add` copies by value,
                # and the clip below mutates the wrapper in place. (Segment and
                # Vec2 are immutable, so sharing them is safe.)
                parts[pi].entries[cursor[pi] + 1] =
                    PartitionEntry(e.segment, e.m, e.b, e.winding)
                cursor[pi] += 1
            end
        end
    end

    for part in parts
        part.requiresAntiAliasing = requiresAAEntries(part.entries)

        # Clip entries that span the whole partition to its bounds
        topF = Float32(part.top)
        botF = Float32(part.bottom)
        topLine = Line(Vec2(0f0, topF), Vec2(1000f0, topF))
        botLine = Line(Vec2(0f0, botF), Vec2(1000f0, botF))
        for e in part.entries
            if e.segment.at.y <= topF && e.segment.to.y >= botF
                # Upstream clips `at` first, then clips `to` against the
                # *modified* segment (new `at` as start). The two float32
                # intersection evaluations differ in the last ulp; matching
                # the order keeps partition-boundary rows on the trapezoid
                # fast path exactly as upstream does.
                newAt = lineSegmentPoint(topLine, e.segment)
                e.segment = Segment(newAt, e.segment.to)
                newTo = lineSegmentPoint(botLine, e.segment)
                e.segment = Segment(e.segment.at, newTo)
            end
        end

        if length(part.entries) == 2
            e0 = part.entries[1].segment
            e1 = part.entries[2].segment
            if !intersectsInsideSeg(e0, e1) &&
                e0.at.y <= topF && e0.to.y >= botF &&
                e1.at.y <= topF && e1.to.y >= botF
                # Two non-intersecting segments spanning the partition
                part.twoNonintersectingSpanningSegments = true
                # Keep entry[1] on the left
                if midpointX(e0) > midpointX(e1)
                    part.entries[1], part.entries[2] =
                        part.entries[2], part.entries[1]
                end
            end
        end
    end
    return parts
end

"""Largest partition entry count (upstream `maxEntryCount`)."""
function maxEntryCount(parts::Vector{Partition})
    m = 0
    for p in parts
        m = max(m, length(p.entries))
    end
    return m
end

"""
Intersection point of a line with a segment (bumpy
`intersects(Line, Segment)`); returned point assumes `0 <= u <= 1` (the
callers here test the span first).
"""
function lineSegmentPoint(l::Line, s::Segment)
    s1 = l.b - l.a
    s2 = s.to - s.at
    denom = (-s2.x * s1.y + s1.x * s2.y)
    num = s1.x * (l.a.y - s.at.y) - s1.y * (l.a.x - s.at.x)
    u = num / denom
    if u >= 0f0 && u <= 1f0
        return s.at + u * s2
    end
    return Vec2(0f0, 0f0) # unreachable via partition clipping
end

"""
True if two segments cross strictly inside (endpoints excluded)
(upstream `intersectsInside`).
"""
function intersectsInsideSeg(a::Segment, b::Segment)
    s1 = a.to - a.at
    s2 = b.to - b.at
    denom = (-s2.x * s1.y + s1.x * s2.y)
    s = (-s1.y * (a.at.x - b.at.x) + s1.x * (a.at.y - b.at.y)) / denom
    t = (s2.x * (a.at.y - b.at.y) - s2.y * (a.at.x - b.at.x)) / denom
    return s > 0f0 && s < 1f0 && t > 0f0 && t < 1f0
end

# ---- 24.8 fixed point (upstream `Fixed32`) -------------------------------

fixed32(f::Float32) = Int32(trunc(f * 256f0)) # float->int32 cast truncates (Nim cast)

fixedInteger(p::Integer) = p ÷ 256

fixedTrunc(p::Integer) = (p ÷ 256) * 256

"""Stable insertion sort of hit x positions (upstream `sortHits`)."""
function sortHits!(hits::Vector{Hit}, len::Int)
    for i in 2:len
        j = i - 1
        k = i
        while j >= 1 && hits[j].at > hits[k].at
            tmp = hits[j + 1]
            hits[j + 1] = hits[j]
            hits[j] = tmp
            j -= 1
            k -= 1
        end
    end
    return nothing
end

"""True if a fill should render at this winding count (upstream `shouldFill`)."""
function shouldFill(rule, count::Int)
    return rule === NonZero ? (count != 0) : (count % 2 != 0)
end

"""
Pair up the sorted hits into fill spans (upstream `walk`): returns
`(prevAt, at, count)` fixed-point spans.
"""
function walk(hits::Vector{Hit}, numHits::Int, rule)
    out = Vector{NTuple{3,Int}}()
    i = 1
    count = 0
    prevAt = Int32(0)
    while i <= numHits
        h = hits[i]
        if h.at > 0
            if shouldFill(rule, count)
                if i < numHits
                    nxt = hits[i + 1]
                    # Canceling touches are skipped here; the span will be
                    # yielded later as one larger chunk.
                    if nxt.at == h.at && h.winding + nxt.winding == 0
                        i += 2
                        continue
                    end
                    # Only the stop-fill (or last hit) matters in NonZero.
                    if rule === NonZero && count + h.winding != 0
                        count += h.winding
                        i += 1
                        continue
                    end
                end
                push!(out, (prevAt, h.at, count))
            end
            prevAt = h.at
        end
        count += h.winding
        i += 1
    end
    return out
end

"""`hasCoverage(area)`: non-SIMD upstream variant, `round(area*255) != 0`."""
hasCoverage(area::Float32) = roundHalfAway(area * Float32(255)) != 0

"""
Sample the scanline and accumulate per-pixel coverage
(upstream `computeCoverage`): `quality = aa ? 5 : 1` subpixel samples
(offset `1 / quality`, first sample at `+offset / 2 + epsilon`), hits at
`min(x, width)`, uint8 coverage accumulations with upstream wrap.
"""
function computeCoverage!(coverages::Vector{UInt8}, hits::Vector{Hit}, imageWidth::Int, y::Int, startX::Int, part::Partition, entryIndices::Vector{Int}, numEntryIndices::Int, rule)
    aa = part.requiresAntiAliasing
    quality = aa ? 5 : 1 # quality divides 255 cleanly
    sampleCoverage = UInt8(255 ÷ quality)
    cov32 = Float32(sampleCoverage)
    offset = Float32(1) / Float32(quality)
    initialOffset = offset / 2f0 + PIXIE_EPSILON
    numHits = 0
    yLine = Float32(y) + initialOffset - offset
    for m in 1:quality
        yLine += offset
        numHits = 0
        for ii in 1:numEntryIndices
            entry = part.entries[entryIndices[ii]]
            if entry.segment.at.y <= yLine && entry.segment.to.y >= yLine
                x = entry.m == 0f0 ? entry.b : (yLine - entry.b) / entry.m
                hits[numHits + 1] = Hit(fixed32(min(x, Float32(imageWidth))), entry.winding)
                numHits += 1
            end
        end
        numHits > 1 && sortHits!(hits, numHits)
        if aa
            # Upstream walks and accumulates per sample row, inside the loop.
            for (prevAt, at, _cnt) in walk(hits, numHits, rule)
                fillStart = fixedInteger(prevAt)
                pixelCrossed = fixedInteger(at) != fixedInteger(prevAt)
                leftCover = pixelCrossed ? (fixedTrunc(prevAt) + 256 - prevAt) :
                    (at - prevAt)
                if leftCover != 0
                    fillStart += 1
                    idx = fixedInteger(prevAt) - startX + 1
                    if 1 <= idx <= length(coverages)
                        contrib = Int(Int32(leftCover * cov32) ÷ 256)
                        coverages[idx] = UInt8((Int(coverages[idx]) + contrib) & 0xff)
                    end
                end
                if pixelCrossed
                    rightCover = at - fixedTrunc(at)
                    if rightCover > 0
                        idx = fixedInteger(at) - startX + 1
                        if 1 <= idx <= length(coverages)
                            contrib = Int(Int32(rightCover * cov32) ÷ 256)
                            coverages[idx] = UInt8((Int(coverages[idx]) + contrib) & 0xff)
                        end
                    end
                end
                fillLen = fixedInteger(at) - fillStart
                if fillLen > 0
                    # Fill absolute pixels [fillStart, fillStart+fillLen) using the
                    # same 1-based index mapping as the left/right slivers
                    # (absolute_pixel - startX + 1); upstream covers exactly fillLen
                    # pixels: `for j in fillStart ..< fillStart+fillLen`.
                    lo = max(fillStart - startX + 1, 1)
                    hi = min(fillStart + fillLen - startX, length(coverages))
                    for k in lo:hi
                        # uint8 accumulation wraps (upstream release semantics)
                        coverages[k] = UInt8((Int(coverages[k]) + Int(sampleCoverage)) & 0xff)
                    end
                end
            end
        end
    end
    return numHits
end

"""
Write a solid color over the 0-based span `[x0, x1)` of row `y0..y1-1`
(upstream `fillUnsafe` in scalar form).
"""
function fillRowRange(image::Image, rgbx::ColorRGBX, x0::Int, y0::Int, x1::Int, y1::Int)
    xlo = max(x0, 0)
    xhi = min(x1, image.width)
    ylo = max(y0, 0)
    yhi = min(y1, image.height)
    if xlo >= xhi || ylo >= yhi
        return nothing
    end
    # x1/y1 are exclusive (0-based); the loop bounds are inclusive.
    d = image.data
    w = image.width
    for yy in ylo:(yhi - 1)
        for xx in xlo:(xhi - 1)
            i = (yy * w + xx) * 4
            d[i + 1] = rgbx.r
            d[i + 2] = rgbx.g
            d[i + 3] = rgbx.b
            d[i + 4] = rgbx.a
        end
    end
    return nothing
end

"""
Fill the 0-based span `[x0, x1)` of row `y` (upstream `fillHits` span loop
for Normal/Overwrite/Mask; clamps the span to the image; the mask-mode
clears for the row's uncovered parts live in `fillShapes`/`fillCoverageLine`)
"""
function fillHitsLine(image::Image, rgbx::ColorRGBX, y::Int, x0::Int, x1::Int, blendMode)
    lo = max(x0, 0)
    hi = min(x1, image.width)
    if lo >= hi
        return nothing
    end
    if blendMode === MaskBlend
        # Upstream skips the write when rgbx.a == 255 (blendMask with an
        # opaque source is the identity: ch * 255 div 255 == ch).
        rgbx.a == 0xff && return nothing
        for x in lo:(hi - 1)
            backdrop = getColor(image, x + 1, y + 1)
            set_pixel(image, x + 1, y + 1, blendMask(backdrop, rgbx))
        end
        return nothing
    end
    # Fast path: Overwrite writes the color; an opaque Normal source is itself
    # (W3C modes are not, so they fall through to the blended path).
    if blendMode === OverwriteBlend ||
        (blendMode === NormalBlend && rgbx.a == 0xff)
        fillRowRange(image, rgbx, lo, y, hi, y + 1)
        return nothing
    end
    blend = blender(blendMode)
    for x in lo:(hi - 1)
        backdrop = getColor(image, x + 1, y + 1)
        set_pixel(image, x + 1, y + 1, blend(backdrop, rgbx))
    end
    return nothing
end

"""
Blit a per-pixel coverage row (0-based `x = startX + k`) into the image
(upstream `fillCoverage`: Normal/Overwrite branches; plus the MaskBlend
branch where full coverage keeps the pixel, zero coverage clears it, and
the row's uncovered ends are cleared).
"""
function fillCoverageLine(image::Image, rgbx::ColorRGBX, startX::Int, y::Int, coverages::Vector{UInt8}, blendMode)
    d = image.data
    w = image.width
    if blendMode === MaskBlend
        for k in 1:length(coverages)
            cov = coverages[k]
            cov == 0xff && continue # full cover: keep the pixel (upstream skip)
            j = (y * w + (startX + k - 1)) * 4
            backdrop = ColorRGBX(d[j + 1], d[j + 2], d[j + 3], d[j + 4])
            out = blendMask(backdrop, rgbx * cov)
            d[j + 1] = out.r
            d[j + 2] = out.g
            d[j + 3] = out.b
            d[j + 4] = out.a
        end
        fillRowRange(image, ColorRGBX(0x00, 0x00, 0x00, 0x00), 0, y, startX, y + 1)
        fillRowRange(image, ColorRGBX(0x00, 0x00, 0x00, 0x00),
            startX + length(coverages), y, w, y + 1)
        return nothing
    elseif blendMode === OverwriteBlend
        for k in 1:length(coverages)
            cov = coverages[k]
            cov == 0x00 && continue
            out = rgbx * cov
            j = (y * w + (startX + k - 1)) * 4
            d[j + 1] = out.r
            d[j + 2] = out.g
            d[j + 3] = out.b
            d[j + 4] = out.a
        end
    else
        blend = blender(blendMode)
        for k in 1:length(coverages)
            cov = coverages[k]
            cov == 0x00 && continue
            j = (y * w + (startX + k - 1)) * 4
            backdrop = ColorRGBX(d[j + 1], d[j + 2], d[j + 3], d[j + 4])
            out = blend(backdrop, rgbx * cov)
            d[j + 1] = out.r
            d[j + 2] = out.g
            d[j + 3] = out.b
            d[j + 4] = out.a
        end
    end
    return nothing
end

function _blendFillPixel(image::Image, x0::Int, y0::Int, rgbx::ColorRGBX, area::Float32, blendMode)
    j = (y0 * image.width + x0) * 4
    d = image.data
    if blendMode === OverwriteBlend
        out = rgbx * area
    else
        backdrop = ColorRGBX(d[j + 1], d[j + 2], d[j + 3], d[j + 4])
        out = blender(blendMode)(backdrop, rgbx * area) # mask: blendMask
    end
    d[j + 1] = out.r
    d[j + 2] = out.g
    d[j + 3] = out.b
    d[j + 4] = out.a
    return nothing
end

"""
Trapezoid fast path for a scanline fully inside all edges
(upstream `fillShapes` trapezoid shortcut): trapezoids at the edges with the
exact per-pixel coverage area (triangle + rectangle decomposition) and a
flat fill in between. Returns false if the shortcut's preconditions fail,
leaving the coverage pass to run instead.
"""
function fillTrapezoids!(image, rgbx::ColorRGBX, y::Int, part::Partition, entryIndices::Vector{Int}, numEntryIndices::Int, traps::Vector{Segment}, rule, blendMode)
    W = image.width
    scanTop = Float32(y)
    scanBottom = Float32(y + 1)
    for i in 1:numEntryIndices
        idx = entryIndices[i]
        e = part.entries[idx]
        traps[idx] = Segment(
            Vec2(solveX(e, scanTop), scanTop),
            Vec2(solveX(e, scanBottom), scanBottom))
    end
    # Sort by midpoint; wrong order across an intersection is caught by the
    # overlap check below.
    for i in 2:numEntryIndices
        j = i - 1
        k = i
        while j >= 1 && midpointX(traps[entryIndices[j]]) > midpointX(traps[entryIndices[k]])
            tmp = entryIndices[j + 1]
            entryIndices[j + 1] = entryIndices[j]
            entryIndices[j] = tmp
            j -= 1
            k -= 1
        end
    end
    # Take the shortcut only if left/right coverage regions do not overlap.
    for i in 1:(numEntryIndices - 1)
        l = traps[entryIndices[i]]
        r = traps[entryIndices[i + 1]]
        # upstream: `leftMaxX.ceil.int > rightMinX.int` (both truncate)
        if Int(ceil(Float32(max(l.at.x, l.to.x)))) > Int(trunc(min(r.at.x, r.to.x)))
            return false
        end
    end
    # Confirm the pairs form simple fills under the winding rule.
    i = 1
    windingCount = 0
    while i < numEntryIndices
        windingCount += part.entries[entryIndices[i]].winding
        !shouldFill(rule, windingCount) && return false
        windingCount += part.entries[entryIndices[i + 1]].winding
        shouldFill(rule, windingCount) && return false
        i += 2
    end
    # Julia `a:b:c` is start:step:stop -- iterate steps of 2 up to numEntryIndices.
    filledTo = 0 # upstream `filledTo` (last pair's right edge, mask clears)
    for i in 2:2:numEntryIndices
        left = part.entries[entryIndices[i - 1]]
        right = part.entries[entryIndices[i]]
        tl = traps[entryIndices[i - 1]]
        tr = traps[entryIndices[i]]
        leftMaxX = max(tl.at.x, tl.to.x)
        rightMinX = min(tr.at.x, tr.to.x)
        fillBegin = clamp(Int(ceil(leftMaxX)), 0, W)
        # upstream: `rightMinX.trunc.int`
        fillEnd = clamp(Int(trunc(Float32(rightMinX))), 0, W)
        # Middle: full coverage between the two rounded boundaries
        fillHitsLine(image, rgbx, y, fillBegin, fillEnd, blendMode)
        # Left-side partial coverage
        inverted = tl.at.x < tl.to.x
        sliverStart = min(tl.at.x, tl.to.x)
        rectStart = leftMaxX
        pen = sliverStart
        prevPen = sliverStart
        penY = inverted ? Float32(y) : Float32(y + 1)
        prevPenY = penY
        # upstream: `for x in sliverStart.int ..< rectStart.ceil.int`
        for x in Int(trunc(sliverStart)):(Int(ceil(rectStart)) - 1)
            prevPen = pen
            pen = Float32(x + 1)
            rightRectArea = 0f0
            if pen > rectStart
                rightRectArea = pen - rectStart
                pen = rectStart
            end
            prevPenY = penY
            penY = solveY(left, pen)
            if x >= 0 && x < W
                run = pen - prevPen
                triangleArea = 0.5f0 * run * abs(penY - prevPenY)
                rectArea = (inverted ? (prevPenY - Float32(y)) :
                    (Float32(y + 1) - prevPenY)) * run
                area = triangleArea + rectArea + rightRectArea
                # upstream: `hasCoverage(area) or clearsUncovered` (MaskBlend
                # writes even sub-quantized slivers, which clear the pixel)
                (hasCoverage(area) || blendMode === MaskBlend) &&
                    _blendFillPixel(image, x, y, rgbx, area, blendMode)
            end
        end
        # Right-side partial coverage
        inverted = tr.at.x > tr.to.x
        rectEnd = rightMinX
        sliverEnd = max(tr.at.x, tr.to.x)
        pen = rectEnd
        prevPen = rectEnd
        penY = inverted ? Float32(y + 1) : Float32(y)
        prevPenY = penY
        # upstream: `for x in rectEnd.int ..< sliverEnd.ceil.int`
        for x in Int(trunc(rectEnd)):(Int(ceil(sliverEnd)) - 1)
            prevPen = pen
            pen = Float32(x + 1)
            leftRectArea = abs(prevPen) - trunc(abs(prevPen)) # upstream
            # `prevPen.fractional` = vmath fract: abs-based, so negative
            # pens (possible under rotated transforms) stay positive.
            if pen > sliverEnd
                pen = sliverEnd
            end
            prevPenY = penY
            penY = solveY(right, pen)
            if x >= 0 && x < W
                run = pen - prevPen
                triangleArea = 0.5f0 * run * abs(penY - prevPenY)
                rectArea = (inverted ? (penY - Float32(y)) :
                    (Float32(y + 1) - penY)) * run
                area = leftRectArea + triangleArea + rectArea
                (hasCoverage(area) || blendMode === MaskBlend) &&
                    _blendFillPixel(image, x, y, rgbx, area, blendMode)
            end
        end
        # Upstream mask mode: clear the gap between this pair's left edge and
        # the previous pair's right edge, then advance the frontier.
        if blendMode === MaskBlend
            clearTo = Int(trunc(min(tl.at.x, tl.to.x)))
            fillRowRange(image, ColorRGBX(0x00, 0x00, 0x00, 0x00),
                min(filledTo, W), y, min(clearTo, W), y + 1)
        end
        filledTo = Int(ceil(max(tr.at.x, tr.to.x)))
    end
    if blendMode === MaskBlend
        fillRowRange(image, ColorRGBX(0x00, 0x00, 0x00, 0x00),
            min(filledTo, W), y, W, y + 1)
    end
    return true
end

"""Scanline point test (upstream `overlaps`, paths.nim L2232): a
horizontal scanline rightward from the test point; hits are 1/256
fixed-point x's with the segment windings, sorted and walked. A point
past the last hit is outside (upstream falls through to `false`)."""
function overlaps(shapes::Vector{Vector{Vec2}}, test::Vec2, rule)
    hits = Vector{Hit}()
    scanline = Line(Vec2(0f0, test.y), Vec2(1000f0, test.y))
    for sw in shapesToSegments(shapes, true)
        seg = sw.segment
        seg.at.y <= test.y <= seg.to.y || continue
        # Line/segment intersection (upstream bumpy `intersects`): u is the
        # parameter along the segment; parallel (denom 0) yields NaN/Inf.
        s1 = scanline.b - scanline.a
        s2 = seg.to - seg.at
        u = (s1.x * (scanline.a.y - seg.at.y) -
            s1.y * (scanline.a.x - seg.at.x)) /
            (-s2.x * s1.y + s1.x * s2.y)
        (u >= 0f0 && u <= 1f0) || continue
        at = seg.at + u * s2
        seg.to == at && continue
        push!(hits, Hit(fixed32(at.x), sw.winding))
    end
    sortHits!(hits, length(hits))
    testX = fixed32(test.x)
    count = 0
    for h in hits
        h.at > testX && return shouldFill(rule, count)
        count += h.winding
    end
    return false
end

"""
Solid-fill the shapes into the image (upstream `fillShapes` for
Normal/Overwrite/MaskBlend; the mask mode clears the uncovered parts of the
row as upstream does): within `snapToPixels(bound)` per partition -- two
non-intersecting spanning segments take the pixel-aligned fast path, a
fully-spanning even entry set takes the trapezoid shortcut per scanline,
otherwise the coverage pass (AA: 5-sampled `computeCoverage` + blended rows;
no-AA: solid row fills from the integer hit walk).
"""

function fillShapes(image::Image, shapes::Vector{Vector{Vec2}}, color::ColorRGBX, rule; blendMode = NormalBlend)
    rgbx = color
    segments = shapesToSegments(shapes, true)
    bounds = snapToPixels(computeBoundsOfSegments(segments))
    W = image.width
    H = image.height
    startX = max(0, Int(bounds.x))
    startY = clamp(Int(bounds.y), 0, H)
    pathWidth = startX < W ? min(Int(bounds.w), W - startX) : 0
    pathHeight = clamp(Int(bounds.y + bounds.h), 0, H)
    zeroPx = ColorRGBX(0x00, 0x00, 0x00, 0x00) # clears-uncovered clear color
    if pathWidth == 0
        if blendMode === MaskBlend
            # The path is entirely outside the image horizontally, but a mask
            # fill still records that: clear the whole image (upstream).
            fillRowRange(image, zeroPx, 0, 0, W, H)
        end
        return nothing
    end
    pathWidth >= 0 || throw(ArgumentError("Path int overflow detected"))
    parts = partitionSegments(segments, startY, pathHeight - startY)
    partitionIndex = 1
    capacity = max(maxEntryCount(parts), 2)
    entryIndices = Int[0 for _ in 1:capacity]
    traps = Vector{Segment}(undef, capacity)
    coverages = zeros(UInt8, pathWidth)
    hits = Vector{Hit}(undef, capacity)

    y = startY
    while y < pathHeight
        if y >= parts[partitionIndex].bottom
            partitionIndex += 1
        end
        part = parts[partitionIndex]
        partHeight = part.bottom - part.top
        partHeight == 0 && continue

        if part.twoNonintersectingSpanningSegments && !part.requiresAntiAliasing
            # No AA needed: two vertical pixel-aligned lines
            # upstream casts with `.int` (truncation)
            minX = clamp(Int(trunc(part.entries[1].segment.at.x)), 0, W)
            maxX = clamp(Int(trunc(part.entries[2].segment.at.x)), 0, W)
            skipBlending = blendMode === OverwriteBlend ||
                (blendMode === NormalBlend && rgbx.a == 0xff)
            if skipBlending && minX == 0 && maxX == W
                # Greedy: one big multi-row fill (upstream fillUnsafe over
                # `dataIndex(0, y)` .. `dataIndex(0, y + partitionHeight)`).
                fillRowRange(image, rgbx, 0, y, W, y + partHeight)
            elseif blendMode === MaskBlend
                # Upstream fillHits (maskClears): clear both row ends, blend
                # the span between.
                for r in 0:(partHeight - 1)
                    fillRowRange(image, zeroPx, 0, y + r, minX, y + r + 1)
                    fillHitsLine(image, rgbx, y + r, minX, maxX, blendMode)
                    fillRowRange(image, zeroPx, maxX, y + r, W, y + r + 1)
                end
            else
                for r in 0:(partHeight - 1)
                    fillHitsLine(image, rgbx, y + r, minX, maxX, blendMode)
                end
            end
            y += partHeight
            continue
        end

        scanTop = Float32(y)
        scanBottom = Float32(y + 1)
        numEntryIndices = 0
        allEntriesInScanlineSpanIt = true
        if part.twoNonintersectingSpanningSegments
            numEntryIndices = 2
            entryIndices[1] = 1
            entryIndices[2] = 2
        else
            for idx in eachindex(part.entries)
                seg = part.entries[idx].segment
                (seg.to.y <= scanTop || seg.at.y >= scanBottom) && continue
                (seg.at.y > scanTop || seg.to.y < scanBottom) &&
                    (allEntriesInScanlineSpanIt = false)
                entryIndices[numEntryIndices + 1] = idx
                numEntryIndices += 1
            end
        end

        if allEntriesInScanlineSpanIt && numEntryIndices % 2 == 0 &&
            fillTrapezoids!(image, rgbx, y, part, entryIndices, numEntryIndices, traps, rule, blendMode)
            y += 1
            continue
        end

        numHits = computeCoverage!(coverages, hits, W, y, startX, part, entryIndices, numEntryIndices, rule)
        if part.requiresAntiAliasing
            fillCoverageLine(image, rgbx, startX, y, coverages, blendMode)
        elseif blendMode === MaskBlend
            # Upstream fillHits (maskClears = true): clear the gap before each
            # span, blend the span, then clear both ends of the row.
            filledTo = startX
            for (prevAt, at, _cnt) in walk(hits, numHits, rule)
                fillStart = fixedInteger(prevAt)
                fillLen = fixedInteger(at) - fillStart
                if fillLen <= 0
                    continue
                end
                gap = fillStart - filledTo
                gap > 0 && fillRowRange(image, zeroPx, filledTo, y, fillStart, y + 1)
                fillHitsLine(image, rgbx, y, fillStart, fillStart + fillLen, blendMode)
                filledTo = fillStart + fillLen
            end
            fillRowRange(image, zeroPx, 0, y, startX, y + 1)
            fillRowRange(image, zeroPx, filledTo, y, W, y + 1)
        else
            for (prevAt, at, _cnt) in walk(hits, numHits, rule)
                fillStart = fixedInteger(prevAt)
                fillLen = fixedInteger(at) - fillStart
                fillLen > 0 && fillHitsLine(image, rgbx, y, fillStart, fillStart + fillLen, blendMode)
            end
        end
        fill!(coverages, zero(UInt8))
        y += 1
    end

    # Upstream: a MaskBlend fill clears the rows fully above and below the
    # path's bounds, recording that they are uncovered by the clip.
    if blendMode === MaskBlend
        fillRowRange(image, zeroPx, 0, 0, W, startY)
        fillRowRange(image, zeroPx, 0, pathHeight, W, H)
    end
    return nothing
end

"""
Fill `path` (a `Path` or an SVG path string) with a solid color into
`image` (upstream `fillPath` solid-paint path): the path is closed into
shapes, transformed by `transform` (exactly once), and rasterized with
`windingRule` under `blendMode` (Normal by default, as the documented
entry point). Colors convert to premultiplied alpha before blending.
Mutates `image` and returns nothing.
"""
function fillPath(image::Image, path, color, ; transform::Mat3 = mat3(),
    windingRule = NonZero, blendMode = NormalBlend)
    (windingRule === NonZero || windingRule === EvenOdd) ||
        throw(ArgumentError("windingRule must be NonZero or EvenOdd"))
    c = color isa ColorRGBX ? color :
        color isa ColorRGBA ? rgbx(color) :
        color isa ColorRGB ? rgbx(color) :
        throw(ArgumentError("color must be a ColorRGB, ColorRGBA or ColorRGBX"))
    if c.a == 0x00
        return nothing # zero-alpha solid (upstream fillPath gate)
    end
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
    fillShapes(image, shapes, c, windingRule; blendMode = blendMode)
    return nothing
end
