# ---------- strokes (T005) ----------
# Upstream: pixie/paths.nim -- LineCap/LineJoin enums (~30-36),
# miterLimitToAngle/angleToMiterLimit (1930-1936), strokeShapes (1938-2098),
# strokePath (2160-2192, solid branch only). Helpers used verbatim:
# pkgs/vmath fixAngle (595), angle (1852), dist/dir (1057-1065);
# pkgs/bumpy intersects(Line, Line) (492-505).
# strokeShapes returns a flat seq[Polygon] upstream: each shapeStroke is
# appended into result (Nim `add` on a sequence), and the strokePath result
# is passed straight to fillShapes.
# Image/mask strokes and dashes-in-Context arrive with T010 (upstream
# `ctx.lineDash`).

"""Line cap type (upstream `LineCap`, enum order)."""
struct LineCap
    kind::Int
end

const ButtCap = LineCap(0)
const RoundCap = LineCap(1)
const SquareCap = LineCap(2)

"""Line join type (upstream `LineJoin`, enum order)."""
struct LineJoin
    kind::Int
end

const MiterJoin = LineJoin(0)
const RoundJoin = LineJoin(1)
const BevelJoin = LineJoin(2)

"""Default miter limit for strokePath (upstream `defaultMiterLimit = 4`)."""
const defaultMiterLimit = Float32(4)

"""Converts miter-limit-ratio to miter-limit-angle (upstream, L1930)."""
miterLimitToAngle(limit::Float32) =
    asin(Float32(1) / limit) * Float32(2)

"""Converts miter-limit-angle to miter-limit-ratio (upstream, L1934)."""
angleToMiterLimit(angle::Float32) =
    Float32(1) / sin(angle / Float32(2))

"""vmath `angle(GVec2)`: `atan2(a.y, a.x)` (L1852)."""
_angle(v::Vec2) = atan(v.y, v.x)

"""
vmath `fixAngle` (L595): normalize an angle to (-PI, PI].
In the pinned build the PI literal adapts to the Float32 context (verified
against the pinned vmath: `fixAngle(PI_F) == PI_F`, `fixAngle(-PI_F) == PI_F`),
so the loop compares against the Float32 `PI_F`/`TAU_F`.
"""
function fixAngle(angle::Float32)
    r = angle
    while r > PI_F
        r -= TAU_F
    end
    while r <= -PI_F
        r += TAU_F
    end
    return r
end

"""
bumpy `intersects(Line, Line, at)` (L492-505). Returns (hit, at); on the
parallel (`denominator == 0`) case `at` is the zero vector. Mirrors upstream
(no error; the join callers skip it anyway).
"""
function _lineIntersect(a::Line, b::Line)
    s1 = a.b - a.a
    s2 = b.b - b.a
    denominator = -s2.x * s1.y + s1.x * s2.y
    if denominator == 0f0
        return (false, Vec2())
    end
    t = (s2.x * (a.a.y - b.a.y) - s2.y * (a.a.x - b.a.x)) / denominator
    at = a.a + t * s1
    return (true, at)
end

"""
Expand `shapes` (flat polygons from `commandsToShapes`) into stroked
polygons (upstream `strokeShapes`, L1938-2098): edge rectangles, round/square
caps, and miter/bevel/round joins. `dashes` (Float32 draw/gap lengths) is
copied, duplicated once when odd-length, and any non-positive value raises
`ArgumentError` (upstream `Invalid line dash value`; the guard is there to
stop the dash loop from hanging). Returns a flat `Vector{Polygon}`.
`strokeWidth <= 0` yields no polygons (upstream early return).
"""
function strokeShapes(
    shapes::Vector{Vector{Vec2}},
    strokeWidth::Float32,
    lineCap::LineCap,
    lineJoin::LineJoin,
    miterLimit::Float32,
    dashes,
    pixelScale::Float32,
)
    if strokeWidth <= 0f0
        return Vector{Vector{Vec2}}()
    end

    halfStroke = strokeWidth / Float32(2)
    miterAngleLimit = miterLimitToAngle(miterLimit)

    makeCircle(at::Vec2) = (
        p = newPath();
        ellipse(p, at, halfStroke, halfStroke);
        commandsToShapes(p, true, pixelScale)[1])

    function makeRect(at::Vec2, to::Vec2)
        # Same arithmetic as upstream, with the tangent components kept in
        # local variables instead of re-deriving a Vec2 each use.
        tangent = normalize(to - at)
        nx = tangent.y
        ny = tangent.x
        out = Vector{Vec2}(undef, 5)
        out[1] = Vec2(at.x + nx * halfStroke, at.y - ny * halfStroke)
        out[2] = Vec2(to.x + nx * halfStroke, to.y - ny * halfStroke)
        out[3] = Vec2(to.x - nx * halfStroke, to.y + ny * halfStroke)
        out[4] = Vec2(at.x - nx * halfStroke, at.y + ny * halfStroke)
        out[5] = out[1]
        return out
    end

    function addJoin!(shape, prevPos::Vec2, pos::Vec2, nextPos::Vec2)
        minArea = PIXEL_ERROR_MARGIN / pixelScale

        if lineJoin === RoundJoin
            area = PI_F * halfStroke * halfStroke
            if area > minArea
                push!(shape, makeCircle(pos))
            end
            # Handled above, skipping angle calculation
            return nothing
        end

        turn = fixAngle(_angle(nextPos - pos) - _angle(prevPos - pos))
        if abs(abs(turn) - PI_F) > PIXIE_EPSILON
            # Collinear (or anti-collinear) corners add nothing.
            a = normalize(pos - prevPos) * halfStroke
            b = normalize(pos - nextPos) * halfStroke
            if turn >= 0f0
                a = Vec2(-a.y, a.x)
                b = Vec2(b.y, -b.x)
            else
                a = Vec2(a.y, -a.x)
                b = Vec2(-b.y, b.x)
            end

            localJoin = lineJoin
            if localJoin === MiterJoin && abs(turn) < miterAngleLimit
                localJoin = BevelJoin
            end

            if localJoin === MiterJoin
                la = line(prevPos + a, pos + a)
                lb = line(nextPos + b, pos + b)
                hit, at = _lineIntersect(la, lb)
                if hit
                    bisectorLengthSq = lengthSq(at - pos)
                    areaSq = Float32(0.25) * (
                        lengthSq(a) * bisectorLengthSq +
                        lengthSq(b) * bisectorLengthSq)
                    if areaSq > minArea * minArea
                        push!(shape, Vec2[pos + a, at, pos + b, pos, pos + a])
                    end
                end
            elseif localJoin === BevelJoin
                areaSq = Float32(0.25) * lengthSq(a) * lengthSq(b)
                if areaSq > minArea * minArea
                    push!(shape, Vec2[a + pos, b + pos, pos, a + pos])
                end
            end
            # RoundJoin: handled above
        end
        return nothing
    end

    result = Vector{Vector{Vec2}}()

    for shape in shapes
        shapeStroke = Vector{Vector{Vec2}}()

        if shape[1] != shape[end]
            # This shape does not end at the same point it starts so draw the
            # first line cap.
            if lineCap === RoundCap
                push!(shapeStroke, makeCircle(shape[1]))
            elseif lineCap === SquareCap
                tangent = normalize(shape[2] - shape[1])
                push!(shapeStroke,
                    makeRect(shape[1] - tangent * halfStroke, shape[1]))
            end
        end

        # Copy only when needed: an empty dash list is never extended.
        dashCopy = isempty(dashes) ? dashes : copy(dashes)
        if length(dashCopy) % 2 != 0
            append!(dashCopy, dashCopy)
        end
        # Make sure gaps and dashes are more than zero, otherwise it will hang.
        for d in dashCopy
            if d <= 0f0
                throw(ArgumentError("Invalid line dash value"))
            end
        end

        n = length(shape)
        for i in 2:n
            pos = shape[i]
            prevPos = shape[i - 1]

            if !isempty(dashCopy)
                distance = length(pos - prevPos)
                dir = normalize(pos - prevPos)
                currPos = prevPos
                usedUp = false # upstream `break dashLoop` when distance <= 0
                while !usedUp
                    for (idx, d) in enumerate(dashCopy)
                        if (idx - 1) % 2 == 0 # upstream 0-based even index draws
                            push!(shapeStroke,
                                makeRect(currPos, currPos + dir * min(distance, d)))
                        end
                        currPos += dir * d
                        distance -= d
                        if distance <= 0f0
                            usedUp = true
                            break
                        end
                    end
                end
            else
                push!(shapeStroke, makeRect(prevPos, pos))
            end

            # If we need a line join
            if i < n
                addJoin!(shapeStroke, prevPos, pos, shape[i + 1])
            end
        end

        if shape[1] == shape[end]
            addJoin!(shapeStroke, shape[n - 1], shape[n], shape[2])
        else
            if lineCap === RoundCap
                push!(shapeStroke, makeCircle(shape[n]))
            elseif lineCap === SquareCap
                tangent = normalize(shape[n] - shape[n - 1])
                push!(shapeStroke,
                    makeRect(shape[n] + tangent * halfStroke, shape[n]))
            end
        end

        append!(result, shapeStroke)
    end
    return result
end

"""
Stroke `path` (a `Path` or an SVG path string) with a solid `Paint`
(upstream `strokePath` solid branch, L2160-2192): opacity is clamped to 0..1
in place, zero opacity is a no-op, and zero-alpha solid paints are skipped
unless `OverwriteBlend` (which can clear). The path stays open
(closeSubpaths = false), strokes are expanded in untransformed space using
`transform`'s pixel scale, then transformed; rasterization uses NonZero
winding (upstream) and the paint's blend mode.
"""
function strokePath(
    image::Image, path, paint::Paint;
    transform::Mat3 = mat3(),
    strokeWidth::Float32 = Float32(1),
    lineCap::LineCap = ButtCap,
    lineJoin::LineJoin = MiterJoin,
    miterLimit::Float32 = defaultMiterLimit,
    dashes = Vector{Float32}(),
)
    paint.opacity = clamp(paint.opacity, Float32(0), Float32(1))
    if paint.opacity == Float32(0)
        return nothing
    end
    if paint.color.a == 0x00 && paint.blendMode !== OverwriteBlend
        return nothing
    end
    src = path isa Path ? path :
        path isa String ? parsePath(path) :
        throw(ArgumentError("path must be a Path or an SVG path string"))
    ps = pixelScale(transform)
    strokes = strokeShapes(
        commandsToShapes(src, false, ps),
        strokeWidth, lineCap, lineJoin, miterLimit, dashes, ps)
    if transform != mat3()
        for s in strokes
            for k in eachindex(s)
                s[k] = transform * s[k]
            end
        end
    end
    fillShapes(image, strokes, solidColorRGBX(paint), NonZero;
        blendMode = paint.blendMode)
    return nothing
end
