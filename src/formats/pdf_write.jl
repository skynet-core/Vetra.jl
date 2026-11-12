# ---------- PDF write (T026; contract: docs/RECORDING.md §6.2, D030) ----------
#
# No upstream writer: pixie has no PDF writer; ISO 32000-1:2008 (PDF 1.4)
# is the export reference. Single page; content units are picture units
# mapped to points via `dpi` (page = W*72/dpi x H*72/dpi pt). The root CTM
# does the top-left/y-down -> bottom-left/y-up mapping:
#
#     cm  s 0 0 -s 0 sH      (s = 72/dpi)
#
# after which every coordinate is emitted in picture space (op tforms go
# on `cm` exactly as in the SVG writer; the PDF cm convention
# x' = ax + cy + e, y' = bx + dy + f matches the SVG matrix() mapping).
#
# Mapping (derived in T026, pinned by test/pdf_export_tests.jl):
# - Paths -> m/l/c/h (quadratics -> exact cubic, PDF has no `q`); S/T
#   reflection tracked as in the raster; elliptical
#   arcs flatten to <=90-degree cubic segments via the pinned
#   endpointToCenterArcParams (k = (4/3)tan(d/4), the classical Bezier arc
#   approximation; affine-invariant under the group transforms below).
#   Gradient fills clip the path with `W n` first: `sh` paints the whole
#   (clipped) user space, not the current path (ISO 32000-2, Table 76).
# - Clips -> successive `W n` (EvenOdd: `W *`) at the start of the owning
#   group's content — intersecting, as in the cumulative raster mask.
# - Solid fills/strokes -> DeviceRGB (straight) + constant alpha /ca, /CA
#   in an ExtGState (the same clamp01(opacity)*a/255 formula as SVG).
# - Linear gradient -> ShadingType 2 with Coords repelled into the
#   element space (the raster samples the gradient in canvas space,
#   untransformed; affine match: axis d' = (|d|^2/|T^+d|^2) T^+d and h'1
#   pinned to the constant term — exact for every invertible T).
# - Radial gradient -> unit radial (ShadingType 3, Coords 0 0 0 0 0 1)
#   under an extra `cm M`, M = the raster's ellipse map
#   translate(center)*rotate(theta)*scale(dX, dY), with the path emitted
#   in M^-1 space — the D030 ellipse-to-circle CTM trick, exact for every
#   invertible T and M.
# - Groups (saveLayer / globalAlpha wrappers) -> Form XObjects with
#   /Group /S /Transparency (isolated, group-unit); the group opacity is
#   the /ca of the ExtGState in effect when the form is drawn.
# - Images (drawImage) -> DeviceRGB image XObject + DeviceGray SMask
#   (premul -> straight at the boundary); v1 emits uncompressed raw
#   streams — this frozen build has no stdlib Compression, and adding
#   CodecZlib would be a dependency outside D030 (recorded; FlateDecode
#   is a follow-up).
# - Text is already glyph outline paths in the recording (D030 §3) — no
#   font embedding, no licensing surface.
#
# Strict pre-scan: the first unexportable op raises ArgumentError naming
# the op index before any file is written (same contract as writeSvg);
# rasterFallback renders the whole picture to one embedded image.

# ---------- number / matrix helpers ----------

"""PDF real (ISO 32000-1 §7.3.3): decimal digits, PERIOD optional, no
exponent form — §7.3.3 NOTE 1: a conforming writer shall not use the
PostScript exponential syntax (such as 6.02E23). poppler 26.01.0 (the
pinned T026 validator) enforces that, which is why axis-aligned radial
gradient maps (Float32 sin residuals like 3e-6 in the ellipse CTM)
must not reach a content stream in `string` form. `string` yields
exponent notation whenever its shortest round-trip digits need the
scientific form (e.g. |v| >= 1e6 or |v| < 1e-4); those values are
rewritten by decimal expansion of the same digits (no rounding, no
digit cap, no integer promotion — see _pdfExpanded). Signed zero
normalizes to `0` (inverses produce -0.0); non-finite values are
rejected earlier by the pre-scan / isfinite validation."""
function _pdfNum(v)
    v == 0 && return "0"
    s = string(v)
    if !occursin('e', s) && !occursin('E', s)
        return s
    end
    return _pdfExpanded(s)
end
_pdfNum(v::Float32) = _pdfNum(Float64(v))

"""Lossless decimal expansion of the exponent form `string` produces
(`[−]d[.ddd]e±ddd`): fold the exponent into the decimal-point position
of the same digit string. Let D be the full digit string (int part +
fraction, length n) and p the shift of the decimal point from the end
of D (p = exponent − fraction length; the value is D × 10^p). Three
cases: p >= 0 puts the point after all digits (append zeros),
0 > p with −p < n puts it inside the digit string (split), p <= −n
puts it before (leading zeros). The result is a decimal that
round-trips to the original value, not the exact decimal expansion of
the binary float: `string` gives the shortest round-trip digits, so
Float32(1e20) — exactly 100000002004087734272 in binary — expands to
the shorter 100000002004087730000, which parses back to the same
Float32 (verified by the round-trip tests)."""
function _pdfExpanded(s)
    m = match(r"^[+-]?(\d+)(?:\.(\d+))?[eE]([+-]?\d+)$", s)
    m === nothing && return s
    sign = startswith(s, "-") ? "-" : ""
    frac = something(m.captures[2], "")
    digits = m.captures[1] * frac
    p = parse(Int, m.captures[3]) - length(frac)
    n = length(digits)
    if p >= 0
        return sign * digits * "0"^p
    elseif -p < n
        return sign * digits[1:n + p] * "." * digits[n + p + 1:n]
    end
    return sign * "0." * "0"^(-p - n) * digits
end

"""The six PDF `cm` numbers for a Vetra `Mat3` (same mapping as the SVG
`matrix(a b c d e f)`)."""
function _pdfCm(m::Mat3)
    return _pdfNum(m[1, 1]) * " " * _pdfNum(m[1, 2]) * " " *
        _pdfNum(m[2, 1]) * " " * _pdfNum(m[2, 2]) * " " *
        _pdfNum(m[3, 1]) * " " * _pdfNum(m[3, 2])
end

function _pdfPt(p::Vec2)
    return _pdfNum(p.x) * " " * _pdfNum(p.y)
end

# ---------- path emitter ----------

mutable struct _PdfPathState
    io::IOBuffer
    cur::Vec2
    subStart::Vec2
    prevC2::Vec2
    prevQ::Vec2
    prevKind::PathCommandKind
end

function _PdfPathState(io::IOBuffer)
    return _PdfPathState(io, Vec2(), Vec2(), Vec2(), Vec2(), Move)
end

function _pdfPath(p::Path, st::_PdfPathState)
    cmds = p.commands
    i = 1
    while i <= length(cmds)
        kind = PathCommandKind(Int(cmds[i]))
        i += 1
        c0 = kind === Close ? nothing : Vec2(cmds[i], cmds[i + 1])
        if kind === Close
            print(st.io, "h\n")
            st.cur = st.subStart
        elseif kind === Move
            st.subStart = c0
            st.cur = c0
            print(st.io, _pdfPt(c0) * " m\n")
        elseif kind === RMove
            st.cur = st.cur + c0
            st.subStart = st.cur
            print(st.io, _pdfPt(st.cur) * " m\n")
        elseif kind === LineTo
            st.cur = c0
            print(st.io, _pdfPt(c0) * " l\n")
        elseif kind === RLine
            st.cur = st.cur + c0
            print(st.io, _pdfPt(st.cur) * " l\n")
        elseif kind === HLine
            st.cur = Vec2(cmds[i], st.cur.y)
            print(st.io, _pdfPt(st.cur) * " l\n")
        elseif kind === RHLine
            st.cur = Vec2(st.cur.x + cmds[i], st.cur.y)
            print(st.io, _pdfPt(st.cur) * " l\n")
        elseif kind === VLine
            st.cur = Vec2(st.cur.x, cmds[i])
            print(st.io, _pdfPt(st.cur) * " l\n")
        elseif kind === RVLine
            st.cur = Vec2(st.cur.x, st.cur.y + cmds[i])
            print(st.io, _pdfPt(st.cur) * " l\n")
        elseif kind === Cubic
            c1 = Vec2(cmds[i], cmds[i + 1])
            c2 = Vec2(cmds[i + 2], cmds[i + 3])
            st.cur = Vec2(cmds[i + 4], cmds[i + 5])
            st.prevC2 = c2
            print(st.io, _pdfPt(c1) * " " * _pdfPt(c2) * " " *
                _pdfPt(st.cur) * " c\n")
        elseif kind === RCubic
            c1 = st.cur + Vec2(cmds[i], cmds[i + 1])
            c2 = st.cur + Vec2(cmds[i + 2], cmds[i + 3])
            st.cur = st.cur + Vec2(cmds[i + 4], cmds[i + 5])
            st.prevC2 = c2
            print(st.io, _pdfPt(c1) * " " * _pdfPt(c2) * " " *
                _pdfPt(st.cur) * " c\n")
        elseif kind === SCubic
            c2 = c0
            c1 = st.prevKind in (Cubic, SCubic, RCubic, RSCubic) ?
                st.cur * 2f0 - st.prevC2 : st.cur
            st.cur = Vec2(cmds[i + 2], cmds[i + 3])
            st.prevC2 = c2
            print(st.io, _pdfPt(c1) * " " * _pdfPt(c2) * " " *
                _pdfPt(st.cur) * " c\n")
        elseif kind === RSCubic
            c2 = st.cur + c0
            c1 = st.prevKind in (Cubic, SCubic, RCubic, RSCubic) ?
                st.cur * 2f0 - st.prevC2 : st.cur
            st.cur = st.cur + Vec2(cmds[i + 2], cmds[i + 3])
            st.prevC2 = c2
            print(st.io, _pdfPt(c1) * " " * _pdfPt(c2) * " " *
                _pdfPt(st.cur) * " c\n")
        elseif kind === Quad
            st.prevQ = c0
            p2 = Vec2(cmds[i + 2], cmds[i + 3])
            _pdfQuadSeg(st, st.cur, c0, p2)
            st.cur = p2
        elseif kind === RQuad
            st.prevQ = st.cur + c0
            p2 = st.cur + Vec2(cmds[i + 2], cmds[i + 3])
            _pdfQuadSeg(st, st.cur, st.prevQ, p2)
            st.cur = p2
        elseif kind === TQuad
            st.prevQ = st.prevKind in (Quad, TQuad, RQuad, RTQuad) ?
                st.cur * 2f0 - st.prevQ : st.cur
            p2 = c0
            _pdfQuadSeg(st, st.cur, st.prevQ, p2)
            st.cur = p2
        elseif kind === RTQuad
            st.prevQ = st.prevKind in (Quad, TQuad, RQuad, RTQuad) ?
                st.cur * 2f0 - st.prevQ : st.cur
            p2 = st.cur + c0
            _pdfQuadSeg(st, st.cur, st.prevQ, p2)
            st.cur = p2
        else # Arc || RArc — flatten to cubic segments
            rx = cmds[i]; ry = cmds[i + 1]; rotDeg = cmds[i + 2]
            large = Int(cmds[i + 3]) == 1
            sweep = Int(cmds[i + 4]) == 1
            # The arc endpoint is the last argument pair (not c0, which
            # holds (rx, ry) here).
            to = Vec2(cmds[i + 5], cmds[i + 6])
            if kind === RArc
                to = st.cur + to
            end
            _pdfArc(st, st.cur, Vec2(rx, ry), rotDeg, large, sweep, to)
            st.cur = to
        end
        i += parameterCount(kind)
        st.prevKind = kind
    end
    return nothing
end

"""PDF has no quadratic path operator (paths are straight lines,
rectangles, and cubic Beziers — ISO 32000-2 §8.5.2), so quads are emitted
as the exact cubic equivalent: c1 = p0 + 2/3 (q - p0),
c2 = p2 + 2/3 (q - p2)."""
function _pdfQuadSeg(st::_PdfPathState, p0::Vec2, q::Vec2, p2::Vec2)
    t2 = Float32(2) / Float32(3)
    c1 = p0 + (q - p0) * t2
    c2 = p2 + (q - p2) * t2
    print(st.io, _pdfPt(c1) * " " * _pdfPt(c2) * " " * _pdfPt(p2) * " c\n")
    return nothing
end

"""
Flatten the endpoint-parameterized arc to cubic segments (<= 90 degrees
each) — the classical Bezier approximation (k = (4/3)tan(d/4) along the
unit-circle tangents, affinely mapped). The center/rotation come from the
pinned `endpointToCenterArcParams` (the same conversion the rasterizer
discretizes), so the arc's shape matches the raster's.
"""
function _pdfArc(st::_PdfPathState, at::Vec2, radii::Vec2, rotDeg::Float32,
    large::Bool, sweep::Bool, to::Vec2)
    arc = endpointToCenterArcParams(at, radii, rotDeg, large, sweep, to)
    sgn = arc.delta >= 0f0 ? Float32(1) : Float32(-1)
    total = abs(arc.delta)
    a = arc.theta
    while total > Float32(1e-9)
        d = min(total, Float32(pi) / Float32(2))
        b = a + sgn * d
        k = (Float32(4) / Float32(3)) * tan(d / Float32(4))
        c1u = Vec2(cos(a), sin(a)) + k * sgn * Vec2(-sin(a), cos(a))
        c2u = Vec2(cos(b), sin(b)) - k * sgn * Vec2(-sin(b), cos(b))
        p3u = Vec2(cos(b), sin(b))
        mp(q) = arc.rotMat * Vec2(q.x * arc.radii.x, q.y * arc.radii.y) +
            arc.center
        print(st.io, _pdfPt(mp(c1u)) * " " * _pdfPt(mp(c2u)) * " " *
            _pdfPt(mp(p3u)) * " c\n")
        a = b
        total -= d
    end
    return nothing
end

"""Transform a path by the affine `m` (for the radial-gradient unit-space
emission): walk the source with the same cursor rules commandsToShapes
uses, map every point (reflection included — affine maps preserve the
reflected control), and rebuild with absolute builders. Arcs are
flattened in the source space with transformed control points."""
function _affinePath(p::Path, m::Mat3)
    out = newPath()
    cmds = p.commands
    src = Vec2()
    srcStart = Vec2()
    prevC2 = Vec2()
    prevQ = Vec2()
    prevKind = Move
    i = 1
    while i <= length(cmds)
        kind = PathCommandKind(Int(cmds[i]))
        i += 1
        c0 = kind === Close ? nothing : Vec2(cmds[i], cmds[i + 1])
        if kind === Close
            closePath(out)
            src = srcStart
        elseif kind === Move
            src = c0
            srcStart = src
            moveTo(out, m * src)
        elseif kind === RMove
            src = src + c0
            srcStart = src
            moveTo(out, m * src)
        elseif kind === LineTo
            src = c0
            lineTo(out, m * src)
        elseif kind === RLine
            src = src + c0
            lineTo(out, m * src)
        elseif kind === HLine
            src = Vec2(cmds[i], src.y)
            lineTo(out, m * src)
        elseif kind === RHLine
            src = Vec2(src.x + cmds[i], src.y)
            lineTo(out, m * src)
        elseif kind === VLine
            src = Vec2(src.x, cmds[i])
            lineTo(out, m * src)
        elseif kind === RVLine
            src = Vec2(src.x, src.y + cmds[i])
            lineTo(out, m * src)
        elseif kind === Cubic
            c1 = Vec2(cmds[i], cmds[i + 1])
            c2 = Vec2(cmds[i + 2], cmds[i + 3])
            src = Vec2(cmds[i + 4], cmds[i + 5])
            prevC2 = c2
            bezierCurveTo(out, m * c1, m * c2, m * src)
        elseif kind === RCubic
            c1 = src + Vec2(cmds[i], cmds[i + 1])
            c2 = src + Vec2(cmds[i + 2], cmds[i + 3])
            src = src + Vec2(cmds[i + 4], cmds[i + 5])
            prevC2 = c2
            bezierCurveTo(out, m * c1, m * c2, m * src)
        elseif kind === SCubic
            c2 = c0
            c1 = prevKind in (Cubic, SCubic, RCubic, RSCubic) ?
                src * 2f0 - prevC2 : src
            src = Vec2(cmds[i + 2], cmds[i + 3])
            prevC2 = c2
            bezierCurveTo(out, m * c1, m * c2, m * src)
        elseif kind === RSCubic
            c2 = src + c0
            c1 = prevKind in (Cubic, SCubic, RCubic, RSCubic) ?
                src * 2f0 - prevC2 : src
            src = src + Vec2(cmds[i + 2], cmds[i + 3])
            prevC2 = c2
            bezierCurveTo(out, m * c1, m * c2, m * src)
        elseif kind === Quad
            prevQ = c0
            src = Vec2(cmds[i + 2], cmds[i + 3])
            quadraticCurveTo(out, m * prevQ, m * src)
        elseif kind === RQuad
            prevQ = src + c0
            src = src + Vec2(cmds[i + 2], cmds[i + 3])
            quadraticCurveTo(out, m * prevQ, m * src)
        elseif kind === TQuad
            prevQ = prevKind in (Quad, TQuad, RQuad, RTQuad) ?
                src * 2f0 - prevQ : src
            src = c0
            quadraticCurveTo(out, m * prevQ, m * src)
        elseif kind === RTQuad
            prevQ = prevKind in (Quad, TQuad, RQuad, RTQuad) ?
                src * 2f0 - prevQ : src
            src = src + c0
            quadraticCurveTo(out, m * prevQ, m * src)
        else # Arc || RArc
            rx = cmds[i]; ry = cmds[i + 1]; rotDeg = cmds[i + 2]
            large = Int(cmds[i + 3]) == 1
            sweep = Int(cmds[i + 4]) == 1
            # The arc endpoint is the last argument pair (not c0, which
            # holds (rx, ry) here).
            to = Vec2(cmds[i + 5], cmds[i + 6])
            if kind === RArc
                to = src + to
            end
            _affineArc(out, m, src, Vec2(rx, ry), rotDeg, large, sweep, to)
            src = to
        end
        i += parameterCount(kind)
        prevKind = kind
    end
    return out
end

"""The affine image of an endpoint arc: flatten the source arc (same
center parameters as the raster) and map the Bezier control points."""
function _affineArc(out, m, at, radii, rotDeg, large, sweep, to)
    arc = endpointToCenterArcParams(at, radii, rotDeg, large, sweep, to)
    sgn = arc.delta >= 0f0 ? Float32(1) : Float32(-1)
    total = abs(arc.delta)
    a = arc.theta
    mp(q) = m * q
    src(q) = arc.rotMat * Vec2(q.x * arc.radii.x, q.y * arc.radii.y) +
        arc.center
    while total > Float32(1e-9)
        d = min(total, Float32(pi) / Float32(2))
        b = a + sgn * d
        k = (Float32(4) / Float32(3)) * tan(d / Float32(4))
        c1u = Vec2(cos(a), sin(a)) + k * sgn * Vec2(-sin(a), cos(a))
        c2u = Vec2(cos(b), sin(b)) - k * sgn * Vec2(-sin(b), cos(b))
        p3u = Vec2(cos(b), sin(b))
        bezierCurveTo(out, mp(src(c1u)), mp(src(c2u)), mp(src(p3u)))
        a = b
        total -= d
    end
    return nothing
end

# ---------- strict pre-scan ----------

"""PDF stops: positions must be finite, in [0, 1], and STRICTLY
increasing (the stitching function needs nonzero segment lengths; the
raster allows ties with degenerate lerp, so this is a named export-time
strict error). Stops must be fully opaque: a shading function's 4th
(alpha) component is not portably honored by the pinned renderers (gs
drops the fill, poppler silently skips it, mupdf ignores the alpha), so
per-stop transparency is a strict v1 error (uniform `paint.opacity`
still works via the op's ExtGState /ca)."""
function _pdfStopsCheck(stops, opidx::Int)
    prev = -Inf
    for stop in stops
        pos = stop.position
        isfinite(pos) || throw(ArgumentError(
            "PDF op $opidx: non-finite gradient stop position"))
        (pos < Float32(0) || pos > Float32(1)) && throw(ArgumentError(
            "PDF op $opidx: gradient stop position $(pos) outside [0, 1] (PDF)"))
        pos <= prev && throw(ArgumentError(
            "PDF op $opidx: gradient stops must be strictly increasing in position (PDF)"))
        prev = pos
        Int(stop.color.a) != 255 && throw(ArgumentError(
            "PDF op $opidx: semi-transparent gradient stops are not " *
            "PDF-exportable (v1); use rasterFallback = true"))
    end
    return nothing
end

function _pdfFiniteMat(m::Mat3, opidx::Int, what::String)
    for j in 1:2
        for i in 1:3
            isfinite(m[i, j]) || throw(ArgumentError(
                "PDF op $opidx ($what): non-finite transform coordinate"))
        end
    end
    return nothing
end

function _pdfFinitePath(p::Path, opidx::Int, what::String)
    for v in p.commands
        isfinite(v) || throw(ArgumentError(
            "PDF op $opidx ($what): non-finite path coordinate"))
    end
    return nothing
end

function _pdfPreScan(picture::Picture)
    for (i, op) in enumerate(picture.ops)
        if op isa ClearOp
            throw(ArgumentError(
                "PDF op $i (ClearOp): clearRect has no PDF erase operator " *
                "in v1; use rasterFallback = true"))
        elseif op isa FillOp
            _pdfFiniteMat(op.tform, i, "FillOp")
            _pdfFinitePath(op.path, i, "FillOp")
            paint = op.paint
            if paint.kind === AngularGradientPaint
                throw(ArgumentError(
                    "PDF op $i (FillOp): angular gradients have no conic " *
                    "shading in PDF (v1)"))
            end
            if paint.kind === ImagePaint
                throw(ArgumentError(
                    "PDF op $i (FillOp): ImagePaint fills are not " *
                    "PDF-exportable (v1)"))
            end
            if paint.blendMode !== NormalBlend
                throw(ArgumentError(
                    "PDF op $i (FillOp): non-Normal blend mode is not " *
                    "PDF-exportable (v1)"))
            end
            if paint.kind === LinearGradientPaint ||
                paint.kind === RadialGradientPaint
                if op.windingRule === EvenOdd
                    throw(ArgumentError(
                        "PDF op $i (FillOp): even-odd gradient fills are " *
                        "not PDF-exportable (v1; `sh` has no fill rule)"))
                end
                h = paint.gradientHandlePositions
                if paint.kind === LinearGradientPaint
                    length(h) == 2 ||
                        throw(ArgumentError("Linear gradient requires 2 handles"))
                    if lengthSq(h[2] - h[1]) == Float32(0)
                        throw(ArgumentError(
                            "PDF op $i (FillOp): degenerate linear " *
                            "gradient (coincident handles)"))
                    end
                else
                    length(h) == 3 ||
                        throw(ArgumentError("Radial gradient requires 3 handles"))
                    if length(h[1] - h[2]) == Float32(0)
                        throw(ArgumentError(
                            "PDF op $i (FillOp): degenerate radial gradient " *
                            "(center == edge)"))
                    end
                    if length(h[1] - h[3]) == Float32(0)
                        throw(ArgumentError(
                            "PDF op $i (FillOp): degenerate radial gradient " *
                            "(center == skew)"))
                    end
                end
                if determinant(op.tform) == Float32(0)
                    throw(ArgumentError(
                        "PDF op $i (FillOp): gradient fill under a " *
                        "singular transform"))
                end
                if isempty(paint.gradientStops)
                    throw(ArgumentError(
                        "PDF op $i (FillOp): gradient must have at least 1 color stop"))
                end
                _pdfStopsCheck(paint.gradientStops, i)
            end
        elseif op isa StrokeOp
            _pdfFiniteMat(op.tform, i, "StrokeOp")
            _pdfFinitePath(op.path, i, "StrokeOp")
            isfinite(op.width) || throw(ArgumentError(
                "PDF op $i (StrokeOp): non-finite stroke width"))
            isfinite(op.miterLimit) || throw(ArgumentError(
                "PDF op $i (StrokeOp): non-finite miter limit"))
            for d in op.dashes
                isfinite(d) || throw(ArgumentError(
                    "PDF op $i (StrokeOp): non-finite dash value"))
            end
            if op.paint.blendMode !== NormalBlend
                throw(ArgumentError(
                    "PDF op $i (StrokeOp): non-Normal blend mode is not " *
                    "PDF-exportable (v1)"))
            end
        elseif op isa DrawImageOp
            _pdfFiniteMat(op.imageMat, i, "DrawImageOp")
        elseif op isa GroupStart
            isfinite(op.opacity) || throw(ArgumentError(
                "PDF op $i (GroupStart): non-finite group opacity"))
        else # GroupEnd
            for c in op.clips
                _pdfFinitePath(c.path, i, "GroupEnd")
            end
        end
    end
    return nothing
end

# ---------- shading ----------

"""A stop as the Type-2 function color [r g b] (straight, 0..1). Stops must
be fully opaque in v1 (see `_pdfStopsCheck` — a 4th alpha component in a
shading function is not portably honored by the pinned renderers)."""
function _pdfStopColor(s)
    c = s.color
    return _pdfNum(Float64(c.r) / 255) * " " *
        _pdfNum(Float64(c.g) / 255) * " " *
        _pdfNum(Float64(c.b) / 255)
end

"""The stitching (ISO 32000 FunctionType 3) over the stops: one Type-2
linear-interpolation segment per stop pair, `Encode` mapping each
subdomain to [0 1] (required by the spec and by poppler). A single stop
is a Type-2 with C0 == C1 (the spec has no constant type)."""
function _pdfStopsFunction(stops)
    n = length(stops)
    if n == 1
        return "<</Type /Function /FunctionType 2 /Domain [0 1] " *
            "/C0 [" * _pdfStopColor(stops[1]) * "] /C1 [" *
            _pdfStopColor(stops[1]) * "] /N 1>>"
    end
    fns = String[]
    bounds = String[]
    for k in 1:(n - 1)
        s2 = stops[k + 1].position
        push!(fns, "<</Type /Function /FunctionType 2 /Domain [0 1] " *
            "/C0 [" * _pdfStopColor(stops[k]) * "] /C1 [" *
            _pdfStopColor(stops[k + 1]) * "] /N 1>>")
        k < n - 1 && push!(bounds, _pdfNum(s2))
    end
    encode = join("0 1" for _ in 1:(n - 1))
    return "<</Type /Function /FunctionType 3 /Domain [0 1] /Functions [" *
        join(fns, " ") * "] /Bounds [" * join(bounds, " ") *
        "] /Encode [" * encode * "]>>"
end

"""Repel the linear-gradient handles into the element space for tform T:
the raster samples t(c) = ((c - h1).d)/|d|^2 in canvas space c = T p; the
PDF shading samples s(p) = ((p - h'1).d')/|d'|^2 in element space. Both
are affine, so matching the gradient direction (d' parallel to T^+d,
scaled to the same slope) and the constant term is exact."""
function _pdfLinearHandles(h1::Vec2, h2::Vec2, T::Mat3)
    if T == mat3()
        return h1, h2
    end
    d = h2 - h1
    Ttd = Vec2(T[1, 1] * d.x + T[2, 1] * d.y,
        T[1, 2] * d.x + T[2, 2] * d.y)
    dp = (lengthSq(d) / lengthSq(Ttd)) * Ttd
    h1p = inverse(T) * h1
    t0 = dot(d, h1) / lengthSq(d)
    alpha = t0 - dot(h1p, dp) / lengthSq(dp)
    h1p = h1p + alpha * dp
    return h1p, h1p + dp
end

"""The raster's ellipse map (identical formula to the SVG writer and the
masked radial fill)."""
function _pdfEllipseMap(center::Vec2, edge::Vec2, skew::Vec2)
    dX = length(center - edge)
    dY = length(center - skew)
    theta = fixAngle(angle(normalize(center - edge)))
    return translate(center) * rotate(theta) * scale(Vec2(dX, dY))
end

# ---------- document assembly ----------

function _pdfXref(out, offsets, nObj)
    xrefPos = Int(position(out))
    println(out, "xref")
    println(out, "0 ", nObj + 1)
    println(out, "0000000000 65535 f ")
    for n in 1:nObj
        println(out, lpad(string(offsets[n]), 10, '0') * " 00000 n ")
    end
    println(out, "trailer")
    println(out, "<</Size ", nObj + 1, " /Root 1 0 R>>")
    println(out, "startxref")
    println(out, xrefPos)
    print(out, "%%EOF\n")
    return nothing
end

"""Raster fallback: one full-page image XObject (+ SMask) over a
transparent group; the page content carries a comment marking it
(identifiable raster, D030 §6)."""
function _pdfRaster(file, img, W, H, s, sW, sH)
    rgb, gray = _pdfImageBytes(img)
    # Do maps the image onto the unit square, so the CTM scales it to the
    # full page (s*W x s*H pt) and flips y (picture space is y-down).
    content = "q\n" * _pdfNum(s * W) * " 0 0 " * _pdfNum(-s * H) *
        " 0 " * _pdfNum(s * H) * " cm\n/Im1 Do\nQ\n"
    out = IOBuffer()
    println(out, "%PDF-1.4")
    offsets = Dict{Int,Int}()
    function objBegin(n)
        offsets[n] = Int(position(out))
        return nothing
    end
    objBegin(1)
    print(out, "1 0 obj\n<</Type /Catalog /Pages 2 0 R>>\nendobj\n")
    objBegin(2)
    print(out, "2 0 obj\n<</Type /Pages /Kids [3 0 R] /Count 1>>\nendobj\n")
    objBegin(3)
    print(out, "3 0 obj\n<</Type /Page /Parent 2 0 R " *
        "/MediaBox [0 0 " * _pdfNum(sW) * " " * _pdfNum(sH) * "] " *
        "/Resources <</XObject <</Im1 5 0 R>>>> " *
        "/Contents 4 0 R>>\nendobj\n")
    objBegin(4)
    print(out, "4 0 obj\n<</Length ", length(content),
        ">>\nstream\n")
    write(out, content)
    print(out, "\nendstream\nendobj\n")
    objBegin(5)
    print(out, "5 0 obj\n<</Type /XObject /Subtype /Image /Width ", W,
        " /Height ", H, " /ColorSpace /DeviceRGB /BitsPerComponent 8 " *
        "/SMask 6 0 R /Length ", length(rgb), ">>\nstream\n")
    write(out, rgb)
    print(out, "\nendstream\nendobj\n")
    objBegin(6)
    print(out, "6 0 obj\n<</Type /XObject /Subtype /Image /Width ", W,
        " /Height ", H, " /ColorSpace /DeviceGray /BitsPerComponent 8 " *
        "/Length ", length(gray), ">>\nstream\n")
    write(out, gray)
    print(out, "\nendstream\nendobj\n")
    _pdfXref(out, offsets, 6)
    doc = String(out.data[1:out.size])
    _svgWriteFile(file, doc)
    return doc
end

"""premul -> straight (uncompressed) RGB + alpha bytes for an image."""
function _pdfImageBytes(img)
    rgb = Vector{UInt8}(undef, 3 * img.width * img.height)
    gray = Vector{UInt8}(undef, img.width * img.height)
    d = img.data
    @inbounds for y in 0:(img.height - 1)
        for x in 0:(img.width - 1)
            pi = 4 * (y * img.width + x)
            c = toStraightAlpha(ColorRGBX(d[pi + 1], d[pi + 2],
                d[pi + 3], d[pi + 4]))
            k = 3 * (y * img.width + x)
            rgb[k + 1] = c.r
            rgb[k + 2] = c.g
            rgb[k + 3] = c.b
            gray[y * img.width + x + 1] = c.a
        end
    end
    return rgb, gray
end

"""
Write `picture` to `file` as a standalone single-page PDF (D030 §6.2;
T026) and return the document bytes (a binary-safe String). Page size is
`picture.size * 72 / dpi` points; `dpi` defaults to 96. Strict by default:
the first unexportable op (clearRect, angular / ImagePaint fills,
non-Normal blends, even-odd gradient fills, degenerate gradients,
out-of-range or non-strictly-increasing stops, non-finite geometry,
singular-transform gradients) raises `ArgumentError` naming the op index,
and no file is written. `rasterFallback = true` renders the whole picture
to one embedded image XObject instead of vector content.
"""
function writePdf(file::String, picture::Picture; dpi::Float32 =
    Float32(96), rasterFallback::Bool = false)
    W = Int(picture.size.x)
    H = Int(picture.size.y)
    s = Float64(72) / Float64(dpi)
    sW = s * W
    sH = s * H
    if rasterFallback
        img = newImage(W, H)
        drawPicture(img, picture)
        return _pdfRaster(file, img, W, H, s, sW, sH)
    end
    _pdfPreScan(picture)
    # ---- pass 1: assign object numbers in op order ----
    # 1 Catalog, 2 Pages, 3 Page, 4 root content, 5 resources; 6+ below.
    next = 6
    gsOf = Dict{Int,Int}()     # op index -> ExtGState obj (fill/stroke)
    gsGroupOf = Dict{Int,Int}() # op index -> ExtGState obj (group ca)
    shOf = Dict{Int,Int}()     # op index -> Shading obj
    fmOf = Dict{Int,Int}()     # op index (GroupStart) -> Form obj
    imOf = Dict{Int,Int}()     # op index -> image obj (SMask = obj + 1)
    for (i, op) in enumerate(picture.ops)
        if op isa FillOp
            paint = op.paint
            if paint.kind === SolidPaint
                fo = clamp(paint.opacity, Float32(0), Float32(1)) *
                    Float32(paint.color.a) / Float32(255)
                if fo != Float32(1)
                    gsOf[i] = next
                    next += 1
                end
            else
                shOf[i] = next
                next += 1
                fo = clamp(paint.opacity, Float32(0), Float32(1))
                if fo != Float32(1)
                    gsOf[i] = next
                    next += 1
                end
            end
        elseif op isa StrokeOp
            so = clamp(op.paint.opacity, Float32(0), Float32(1)) *
                Float32(op.paint.color.a) / Float32(255)
            if so != Float32(1)
                gsOf[i] = next
                next += 1
            end
        elseif op isa GroupStart
            fmOf[i] = next
            next += 1
            o = clamp(op.opacity, Float32(0), Float32(1))
            if o != Float32(1)
                gsGroupOf[i] = next
                next += 1
            end
        elseif op isa DrawImageOp
            imOf[i] = next
            next += 2
        end
    end
    # Resource names: sequential per class in object order.
    gsName = Dict{Int,Int}()
    for o in sort(collect(values(gsOf)))
        gsName[o] = length(gsName) + 1
    end
    for o in sort(collect(values(gsGroupOf)))
        gsName[o] = length(gsName) + 1
    end
    shName = Dict{Int,Int}()
    for o in sort(collect(values(shOf)))
        shName[o] = length(shName) + 1
    end
    fmName = Dict{Int,Int}()
    for o in sort(collect(values(fmOf)))
        fmName[o] = length(fmName) + 1
    end
    imName = Dict{Int,Int}()
    for o in sort(collect(values(imOf)))
        imName[o] = length(imName) + 1
    end
    # ---- pass 2: build the content streams ----
    forms = Dict{Int,Vector{UInt8}}()
    gsGroupOfForm = Dict{Int,Int}() # form obj -> group ca gs obj (0 = none)
    stack = Vector{Tuple{Int,IOBuffer}}()
    rootBuf = IOBuffer()
    print(rootBuf, _pdfNum(s) * " 0 0 " * _pdfNum(-s) * " 0 " *
        _pdfNum(s * H) * " cm\n")
    push!(stack, (0, rootBuf))
    for (i, op) in enumerate(picture.ops)
        top = stack[end][2]
        if op isa GroupStart
            fm = fmOf[i]
            push!(stack, (fm, IOBuffer()))
            gsGroupOfForm[fm] = get(gsGroupOf, i, 0)
        elseif op isa GroupEnd
            fm, buf = pop!(stack)
            parent = stack[end][2]
            # Clip prefix (picture space — the form is drawn under the
            # root CTM, as in the SVG writer).
            prefix = IOBuffer()
            for c in op.clips
                st = _PdfPathState(prefix)
                _pdfPath(c.path, st)
                print(prefix, c.windingRule === EvenOdd ? "W *\n" : "W n\n")
            end
            forms[fm] = vcat(prefix.data[1:prefix.size],
                buf.data[1:buf.size])
            print(parent, "q\n")
            gsg = gsGroupOfForm[fm]
            if gsg > 0
                print(parent, "/GS$(gsName[gsg]) gs\n")
            end
            print(parent, "/Fm$(fmName[fm]) Do\nQ\n")
        elseif op isa FillOp
            paint = op.paint
            print(top, "q\n")
            if paint.kind !== RadialGradientPaint && op.tform != mat3()
                print(top, _pdfCm(op.tform) * " cm\n")
            end
            if paint.kind === SolidPaint
                st = _PdfPathState(top)
                _pdfPath(op.path, st)
                c = paint.color
                print(top, _pdfNum(Float64(c.r) / 255) * " " *
                    _pdfNum(Float64(c.g) / 255) * " " *
                    _pdfNum(Float64(c.b) / 255) * " rg\n")
                if haskey(gsOf, i)
                    print(top, "/GS$(gsName[gsOf[i]]) gs\n")
                end
                print(top, op.windingRule === EvenOdd ? "f*\n" : "f\n")
            else
                # `sh` paints the whole (clipped) user space, not the
                # current path (ISO 32000-2, Table 76), so the path is
                # clipped with `W n` first (even-odd gradient fills are
                # rejected by the pre-scan, so `W n` is always right).
                sh = shOf[i]
                if paint.kind === LinearGradientPaint
                    # The raster samples t in canvas space (untransformed
                    # handles); the element-space Coords are the repelled
                    # handles (exact for every invertible T — derivation in
                    # the file header and tasks/T026-pdf-export.md).
                    st = _PdfPathState(top)
                    _pdfPath(op.path, st)
                    print(top, "W n\n")
                    h = paint.gradientHandlePositions
                    h1, h2 = _pdfLinearHandles(h[1], h[2], op.tform)
                    print(top, _pdfNum(h1.x) * " " * _pdfNum(h1.y) * " " *
                        _pdfNum(h2.x) * " " * _pdfNum(h2.y) * " " *
                        "/Sh$(shName[sh]) sh\n")
                else
                    # Radial: unit circle under cm M (the raster's ellipse
                    # map); the CTM must be exactly M for the unit radial
                    # to equal |M^-1 c|, so the path is emitted in M^-1 o T
                    # space (no separate cm T).
                    h = paint.gradientHandlePositions
                    M = _pdfEllipseMap(h[1], h[2], h[3])
                    print(top, _pdfCm(M) * " cm\n")
                    st = _PdfPathState(top)
                    _pdfPath(_affinePath(op.path, inverse(M) * op.tform), st)
                    print(top, "W n\n")
                    print(top, "0 0 0 0 0 1 /Sh$(shName[sh]) sh\n")
                end
                if haskey(gsOf, i)
                    print(top, "/GS$(gsName[gsOf[i]]) gs\n")
                end
            end
            print(top, "Q\n")
        elseif op isa StrokeOp
            paint = op.paint
            print(top, "q\n")
            if op.tform != mat3()
                print(top, _pdfCm(op.tform) * " cm\n")
            end
            st = _PdfPathState(top)
            _pdfPath(op.path, st)
            c = paint.color
            print(top, _pdfNum(Float64(c.r) / 255) * " " *
                _pdfNum(Float64(c.g) / 255) * " " *
                _pdfNum(Float64(c.b) / 255) * " RG\n")
            print(top, _pdfNum(op.width) * " w\n")
            j = op.cap === ButtCap ? 0 : op.cap === RoundCap ? 1 : 2
            jj = op.join === MiterJoin ? 0 : op.join === RoundJoin ? 1 : 2
            print(top, string(j) * " J\n")
            print(top, string(jj) * " j\n")
            print(top, _pdfNum(op.miterLimit) * " M\n")
            if !isempty(op.dashes)
                print(top, "[" *
                    join((_pdfNum(d) for d in op.dashes), " ") *
                    "] 0 d\n")
            end
            if haskey(gsOf, i)
                print(top, "/GS$(gsName[gsOf[i]]) gs\n")
            end
            print(top, "S\n")
            print(top, "Q\n")
        else # DrawImageOp
            # Do maps the image onto the unit square in user space, so the
            # CTM is imageMat (image pixel space -> picture space) composed
            # with the pixel-size scale.
            im = op.image
            m = op.imageMat * scale(Vec2(Float32(im.width),
                Float32(im.height)))
            print(top, "q\n")
            if m != mat3()
                print(top, _pdfCm(m) * " cm\n")
            end
            print(top, "/Im$(imName[imOf[i]]) Do\n")
            print(top, "Q\n")
        end
    end
    rootBytes = stack[end][2].data[1:stack[end][2].size]
    # ---- assemble the document ----
    out = IOBuffer()
    println(out, "%PDF-1.4")
    offsets = Dict{Int,Int}()
    function objBegin(n)
        offsets[n] = Int(position(out))
        return nothing
    end
    objBegin(1)
    print(out, "1 0 obj\n<</Type /Catalog /Pages 2 0 R>>\nendobj\n")
    objBegin(2)
    print(out, "2 0 obj\n<</Type /Pages /Kids [3 0 R] /Count 1>>\nendobj\n")
    objBegin(3)
    print(out, "3 0 obj\n<</Type /Page /Parent 2 0 R " *
        "/MediaBox [0 0 " * _pdfNum(sW) * " " * _pdfNum(sH) * "] " *
        "/Resources 5 0 R /Contents 4 0 R>>\nendobj\n")
    objBegin(4)
    print(out, "4 0 obj\n<</Length ", length(rootBytes),
        ">>\nstream\n")
    write(out, rootBytes)
    print(out, "\nendstream\nendobj\n")
    gsRes = join(("/GS$(k) $(o) 0 R" for (o, k) in sort(collect(
        gsName))), " ")
    shRes = join(("/Sh$(k) $(o) 0 R" for (o, k) in sort(collect(
        shName))), " ")
    fmRes = join(("/Fm$(k) $(o) 0 R" for (o, k) in sort(collect(
        fmName))), " ")
    imRes = join(("/Im$(k) $(o) 0 R" for (o, k) in sort(collect(
        imName))), " ")
    objBegin(5)
    print(out, "5 0 obj\n<</ExtGState << " * gsRes *
        ">> /XObject << " * fmRes * " " * imRes *
        ">> /Shading << " * shRes * ">>>>\nendobj\n")
    # Auxiliary objects, in ascending object-number order (canonical xref).
    nObj = next - 1
    for o in 6:nObj
        if haskey(gsName, o)
            gsg = collect(values(gsGroupOf))
            if in(o, gsg)
                gi = only(i for i in keys(gsGroupOf) if gsGroupOf[i] == o)
                val = clamp(Float64(picture.ops[gi].opacity), 0.0, 1.0)
            else
                fi = only(i for i in keys(gsOf) if gsOf[i] == o)
                op = picture.ops[fi]
                if op isa FillOp && op.paint.kind !== SolidPaint
                    val = clamp(Float64(op.paint.opacity), 0.0, 1.0)
                else
                    val = clamp(Float64(op.paint.opacity), 0.0, 1.0) *
                        Float64(op.paint.color.a) / 255
                end
            end
            objBegin(o)
            print(out, "$(o) 0 obj\n<</Type /ExtGState /ca " *
                _pdfNum(val) * " /CA " * _pdfNum(val) * ">>\nendobj\n")
        elseif haskey(shName, o)
            i = only(j for j in keys(shOf) if shOf[j] == o)
            op = picture.ops[i]
            objBegin(o)
            if op.paint.kind === LinearGradientPaint
                h = op.paint.gradientHandlePositions
                h1, h2 = _pdfLinearHandles(h[1], h[2], op.tform)
                print(out, "$(o) 0 obj\n<</Type /Shading /ShadingType 2 " *
                    "/ColorSpace /DeviceRGB /Coords [" *
                    _pdfNum(h1.x) * " " * _pdfNum(h1.y) * " " *
                    _pdfNum(h2.x) * " " * _pdfNum(h2.y) *
                    "] /Extend [true true] /Function " *
                    _pdfStopsFunction(op.paint.gradientStops) *
                    ">>\nendobj\n")
            else
                print(out, "$(o) 0 obj\n<</Type /Shading /ShadingType 3 " *
                    "/ColorSpace /DeviceRGB /Coords [0 0 0 0 0 1] " *
                    "/Extend [true true] /Function " *
                    _pdfStopsFunction(op.paint.gradientStops) *
                    ">>\nendobj\n")
            end
        elseif haskey(fmName, o)
            objBegin(o)
            bytes = forms[o]
            print(out, "$(o) 0 obj\n<</Type /XObject /Subtype /Form " *
                "/BBox [0 0 " * _pdfNum(W) * " " * _pdfNum(H) * "] " *
                "/Matrix [1 0 0 1 0 0] /Resources 5 0 R " *
                "/Group <</Type /Group /S /Transparency /I true>> " *
                "/Length ", length(bytes), ">>\nstream\n")
            write(out, bytes)
            print(out, "\nendstream\nendobj\n")
        elseif in(o, collect(values(imOf)))
            # image XObject (SMask = o + 1, written here as well)
            i = only(j for j in keys(imOf) if imOf[j] == o)
            op = picture.ops[i]
            rgb, gray = _pdfImageBytes(op.image)
            objBegin(o)
            print(out, "$(o) 0 obj\n<</Type /XObject /Subtype /Image " *
                "/Width " * string(op.image.width) *
                " /Height " * string(op.image.height) *
                " /ColorSpace /DeviceRGB /BitsPerComponent 8 " *
                "/SMask " * string(o + 1) * " 0 R /Length " *
                string(length(rgb)) * ">>\nstream\n")
            write(out, rgb)
            print(out, "\nendstream\nendobj\n")
            objBegin(o + 1)
            print(out, "$(o + 1) 0 obj\n<</Type /XObject /Subtype /Image " *
                "/Width " * string(op.image.width) *
                " /Height " * string(op.image.height) *
                " /ColorSpace /DeviceGray /BitsPerComponent 8 " *
                "/Length " * string(length(gray)) * ">>\nstream\n")
            write(out, gray)
            print(out, "\nendstream\nendobj\n")
        end
    end
    _pdfXref(out, offsets, nObj)
    doc = String(out.data[1:out.size])
    _svgWriteFile(file, doc)
    return doc
end
