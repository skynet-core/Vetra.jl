# ---------- SVG write (T025; contract: docs/RECORDING.md §6.1, D030) ----------
#
# No upstream writer: pixie reads SVG (src/formats/svg.jl, pinned) but does
# not write it; W3C SVG 1.1 is the export reference. The output is a
# standalone document (explicit size + viewBox = the logical canvas), all
# elements in op order, stable sequential identifiers (gnN / cpN / imN).
#
# Mapping (derived in T025, pinned by test/svg_export_tests.jl):
# - FillOp/StrokeOp -> `<path d ... transform="matrix(T)">` with the
#   recorded op tform T (path data stays in picture space; the raster
#   applies T to the built geometry/stroke, so the element transform
#   reproduces that order exactly, stroke brush included).
# - Solid fills/strokes: straight-RGB hex + fill-opacity / stroke-opacity
#   = clamp01(paint.opacity) * a/255 (the raster formula before its byte
#   rounding, which the renderer applies again at rasterization).
# - Linear gradient: raw canvas handles (the raster samples the gradient
#   in image space, untransformed) + gradientTransform = T^-1 — an exact
#   rep of "sample the canvas-anchored gradient through the element
#   space" for every invertible T (affine match: gradient T^+d/|d|^2).
# - Radial gradient: unit circle at the origin + gradientTransform =
#   T^-1 * M, M = translate(center) * rotate(theta) * scale(dX, dY) — the
#   raster's ellipse map; exact for every invertible T.
# - DrawImageOp -> `<image>` data-URI (PNGFiles, D014) at x=0 y=0 with the
#   recorded imageMat as the element transform (it already includes the
#   op tform, as in the immediate drawImage).
# - GroupStart/End -> nested `<g opacity>`; a GroupEnd's ambient clip list
#   -> one `<clipPath>` whose children intersect (the cumulative raster
#   mask); clips are canvas-space and the group carries no transform.
# - Text is already glyph outline paths in the recording (D030 §3), so it
#   exports as `<path>` — no `<text>`, no font availability dependence.
#
# Strict pre-scan (D030 §6): the first unexportable op raises ArgumentError
# naming the op index before any file is written; rasterFallback = true
# renders the whole picture to a single embedded `<image>` instead.
# Nothing in the output is user-controlled text (hex digits, `string` of
# Float32s, base64), so no XML escaping is required.

const _SVG_HEX = "0123456789abcdef"

"""Straight-RGB hex of a `ColorRGBA` (alpha goes to the opacity attribute)."""
function _svgHex(c::ColorRGBA)
    r = Int(c.r); g = Int(c.g); b = Int(c.b)
    return "#" * _SVG_HEX[(r >> 4) + 1] * _SVG_HEX[(r & 15) + 1] *
        _SVG_HEX[(g >> 4) + 1] * _SVG_HEX[(g & 15) + 1] *
        _SVG_HEX[(b >> 4) + 1] * _SVG_HEX[(b & 15) + 1]
end

"""Number as SVG `float`; `-0.0` is normalized to `0.0` (inverse matrices
produce signed zeros). The SVG 1.1 number grammar (W3C DataTypeNumber)
explicitly allows exponent form, so `string` output is emitted as-is
(correcting an over-restriction introduced with E001: the no-exponent
requirement is a PDF one, ISO 32000-1 §7.3.3 NOTE 1, not an SVG one)."""
function _n(v::Float32)
    v == Float32(0) && return "0.0"
    return string(v)
end

"""The SVG `matrix(a b c d e f)` string for a Vetra `Mat3`
(x' = a*x + c*y + e, y' = b*x + d*y + f; Vetra `m[i, j]` = column i, row j)."""
function _svgMatrix(m::Mat3)
    return "matrix(" * _n(m[1, 1]) * " " * _n(m[1, 2]) * " " *
        _n(m[2, 1]) * " " * _n(m[2, 2]) * " " *
        _n(m[3, 1]) * " " * _n(m[3, 2]) * ")"
end

_pt(cmds, i) = _n(cmds[i]) * " " * _n(cmds[i + 1])

"""
The SVG path `d` for the flat command buffer. Same grammar the rasterizer's
`commandsToShapes` consumes (M/L/H/V/C/S/Q/T/A/Z plus the relative forms,
S/T reflection and endpoint arcs included), so a renderer's path build
matches the raster's; arc x-axis rotation is stored in degrees
(upstream unit) and emits verbatim.
"""
function _svgPathD(p::Path)
    cmds = p.commands
    out = Vector{String}()
    i = 1
    while i <= length(cmds)
        kind = PathCommandKind(Int(cmds[i]))
        i += 1
        c0 = kind === Close ? "" : _n(cmds[i])
        if kind === Close
            push!(out, "Z")
        elseif kind === Move
            push!(out, "M " * c0 * " " * _n(cmds[i + 1]))
        elseif kind === RMove
            push!(out, "m " * c0 * " " * _n(cmds[i + 1]))
        elseif kind === LineTo
            push!(out, "L " * c0 * " " * _n(cmds[i + 1]))
        elseif kind === RLine
            push!(out, "l " * c0 * " " * _n(cmds[i + 1]))
        elseif kind === HLine
            push!(out, "H " * c0)
        elseif kind === RHLine
            push!(out, "h " * c0)
        elseif kind === VLine
            push!(out, "V " * c0)
        elseif kind === RVLine
            push!(out, "v " * c0)
        elseif kind === Cubic
            push!(out, "C " * _pt(cmds, i) * " " * _pt(cmds, i + 2) * " " *
                _pt(cmds, i + 4))
        elseif kind === RCubic
            push!(out, "c " * _pt(cmds, i) * " " * _pt(cmds, i + 2) * " " *
                _pt(cmds, i + 4))
        elseif kind === SCubic
            push!(out, "S " * _pt(cmds, i) * " " * _pt(cmds, i + 2))
        elseif kind === RSCubic
            push!(out, "s " * _pt(cmds, i) * " " * _pt(cmds, i + 2))
        elseif kind === Quad
            push!(out, "Q " * _pt(cmds, i) * " " * _pt(cmds, i + 2))
        elseif kind === RQuad
            push!(out, "q " * _pt(cmds, i) * " " * _pt(cmds, i + 2))
        elseif kind === TQuad
            push!(out, "T " * c0 * " " * _n(cmds[i + 1]))
        elseif kind === RTQuad
            push!(out, "t " * c0 * " " * _n(cmds[i + 1]))
        else # Arc || RArc
            # The buffer stores x-axis rotation in degrees (the SVG unit),
            # so it emits verbatim.
            rot = _n(cmds[i + 2])
            large = Int(cmds[i + 3]) == 1 ? "1" : "0"
            sweep = Int(cmds[i + 4]) == 1 ? "1" : "0"
            push!(out, (kind === Arc ? "A " : "a ") * c0 * " " *
                _n(cmds[i + 1]) * " " * rot * " " * large * " " *
                sweep * " " * _pt(cmds, i + 5))
        end
        i += parameterCount(kind)
    end
    return join(out, " ")
end

"""`clamp(paint.opacity, 0, 1) * a/255` — the raster solid-alpha formula
before its byte rounding (the renderer rounds again at rasterization)."""
_svgSolidOpacity(paint::Paint) =
    clamp(paint.opacity, Float32(0), Float32(1)) *
    Float32(paint.color.a) / Float32(255)

"""Strict pre-scan helpers (D030 §6): the first problem raises naming the
op index; no file is written before the scan finishes."""
function _svgFiniteMat(m::Mat3, opidx::Int, what::String)
    for j in 1:2
        for i in 1:3
            isfinite(m[i, j]) || throw(ArgumentError(
                "SVG op $opidx ($what): non-finite transform coordinate"))
        end
    end
    return nothing
end

function _svgFinitePath(p::Path, opidx::Int, what::String)
    for v in p.commands
        isfinite(v) || throw(ArgumentError(
            "SVG op $opidx ($what): non-finite path coordinate"))
    end
    return nothing
end

"""SVG stops: positions must lie in [0, 1] and be non-decreasing (the SVG
stop `offset` contract; the raster samples with arbitrary finite
positions, so these are named export-time strict errors, not silent
clamps)."""
function _svgStopsCheck(stops, opidx::Int)
    prev = -Inf
    for stop in stops
        pos = stop.position
        isfinite(pos) || throw(ArgumentError(
            "SVG op $opidx: non-finite gradient stop position"))
        (pos < Float32(0) || pos > Float32(1)) && throw(ArgumentError(
            "SVG op $opidx: gradient stop position $(pos) outside [0, 1] (SVG)"))
        pos < prev && throw(ArgumentError(
            "SVG op $opidx: gradient stops must be non-decreasing in position (SVG)"))
        prev = pos
    end
    return nothing
end

function _svgLinearCheck(paint::Paint, T::Mat3, opidx::Int)
    h = paint.gradientHandlePositions
    length(h) == 2 || throw(ArgumentError("Linear gradient requires 2 handles"))
    d = h[2] - h[1]
    lengthSq(d) == Float32(0) && throw(ArgumentError(
        "SVG op $opidx (FillOp): degenerate linear gradient (coincident handles)"))
    determinant(T) == Float32(0) && throw(ArgumentError(
        "SVG op $opidx (FillOp): gradient fill under a singular transform"))
    _svgStopsCheck(paint.gradientStops, opidx)
    return nothing
end

function _svgRadialCheck(paint::Paint, T::Mat3, opidx::Int)
    h = paint.gradientHandlePositions
    length(h) == 3 || throw(ArgumentError("Radial gradient requires 3 handles"))
    center = h[1]; edge = h[2]; skew = h[3]
    length(center - edge) == Float32(0) && throw(ArgumentError(
        "SVG op $opidx (FillOp): degenerate radial gradient (center == edge)"))
    length(center - skew) == Float32(0) && throw(ArgumentError(
        "SVG op $opidx (FillOp): degenerate radial gradient (center == skew)"))
    determinant(T) == Float32(0) && throw(ArgumentError(
        "SVG op $opidx (FillOp): gradient fill under a singular transform"))
    _svgStopsCheck(paint.gradientStops, opidx)
    return nothing
end

function _svgPreScan(picture::Picture)
    needPng = false
    for (i, op) in enumerate(picture.ops)
        if op isa ClearOp
            throw(ArgumentError(
                "SVG op $i (ClearOp): clearRect has no static-SVG equivalent; " *
                "use rasterFallback = true"))
        elseif op isa FillOp
            _svgFiniteMat(op.tform, i, "FillOp")
            _svgFinitePath(op.path, i, "FillOp")
            paint = op.paint
            if paint.kind === AngularGradientPaint
                throw(ArgumentError(
                    "SVG op $i (FillOp): angular gradients are not SVG-exportable (v1)"))
            end
            if paint.kind === ImagePaint
                throw(ArgumentError(
                    "SVG op $i (FillOp): ImagePaint fills are not SVG-exportable (v1)"))
            end
            if paint.blendMode !== NormalBlend
                throw(ArgumentError(
                    "SVG op $i (FillOp): non-Normal blend mode is not " *
                    "SVG-exportable (v1)"))
            end
            if paint.kind === LinearGradientPaint
                _svgLinearCheck(paint, op.tform, i)
            elseif paint.kind === RadialGradientPaint
                _svgRadialCheck(paint, op.tform, i)
            end
        elseif op isa StrokeOp
            _svgFiniteMat(op.tform, i, "StrokeOp")
            _svgFinitePath(op.path, i, "StrokeOp")
            isfinite(op.width) || throw(ArgumentError(
                "SVG op $i (StrokeOp): non-finite stroke width"))
            isfinite(op.miterLimit) || throw(ArgumentError(
                "SVG op $i (StrokeOp): non-finite miter limit"))
            for d in op.dashes
                isfinite(d) || throw(ArgumentError(
                    "SVG op $i (StrokeOp): non-finite dash value"))
            end
            if op.paint.blendMode !== NormalBlend
                throw(ArgumentError(
                    "SVG op $i (StrokeOp): non-Normal blend mode is not " *
                    "SVG-exportable (v1)"))
            end
        elseif op isa DrawImageOp
            needPng = true
            _svgFiniteMat(op.imageMat, i, "DrawImageOp")
        elseif op isa GroupStart
            isfinite(op.opacity) || throw(ArgumentError(
                "SVG op $i (GroupStart): non-finite group opacity"))
        else # GroupEnd
            for c in op.clips
                _svgFinitePath(c.path, i, "GroupEnd")
            end
        end
    end
    if needPng && Base.locate_package(_PNGFILES_PKGID) === nothing
        throw(ErrorException(
            "PNG support is opt-in: add the PNGFiles package to your " *
            "environment (Pkg.add(\"PNGFiles\")) and retry"))
    end
    return nothing
end

function _svgGradientStops(io, stops, depth::Int)
    ind = "  " ^ (depth + 1)
    for stop in stops
        attrs = "offset=\"" * _n(stop.position) *
            "\" stop-color=\"" * _svgHex(stop.color) * "\""
        so = Float32(stop.color.a) / Float32(255)
        so != Float32(1) &&
            (attrs *= " stop-opacity=\"" * _n(so) * "\"")
        println(io, ind * "<stop " * attrs * "/>")
    end
    return nothing
end

"""Emit the gradient element as a direct child of the current group (or the
root), in the position its FillOp occupies (the pinned SVG reader requires
gradients as direct `<g>`/`<svg>` children; the shape is also spec-valid).
See the file header for the exact `gradientTransform` derivation."""
function _svgGradient(io, paint::Paint, T::Mat3, depth::Int, gn::Int)
    ind = "  " ^ depth
    if paint.kind === LinearGradientPaint
        h1 = paint.gradientHandlePositions[1]
        h2 = paint.gradientHandlePositions[2]
        attrs = "id=\"gn$gn\" gradientUnits=\"userSpaceOnUse\" " *
            "x1=\"" * _n(h1.x) * "\" y1=\"" * _n(h1.y) *
            "\" x2=\"" * _n(h2.x) * "\" y2=\"" * _n(h2.y) * "\""
        T != mat3() &&
            (attrs *= " gradientTransform=\"" * _svgMatrix(inverse(T)) * "\"")
        println(io, ind * "<linearGradient " * attrs * ">")
        _svgGradientStops(io, paint.gradientStops, depth)
        println(io, ind * "</linearGradient>")
    else # RadialGradientPaint (checked in the pre-scan)
        h = paint.gradientHandlePositions
        center = h[1]; edge = h[2]; skew = h[3]
        # The raster's ellipse map (same formula as _fillGradientRadialMasked):
        # unit circle -> translate(center) * rotate(theta) * scale(dX, dY).
        dX = length(center - edge)
        dY = length(center - skew)
        theta = fixAngle(angle(normalize(center - edge)))
        M = translate(center) * rotate(theta) * scale(Vec2(dX, dY))
        GT = T == mat3() ? M : inverse(T) * M
        attrs = "id=\"gn$gn\" gradientUnits=\"userSpaceOnUse\" " *
            "cx=\"0\" cy=\"0\" r=\"1\" gradientTransform=\"" *
            _svgMatrix(GT) * "\""
        println(io, ind * "<radialGradient " * attrs * ">")
        _svgGradientStops(io, paint.gradientStops, depth)
        println(io, ind * "</radialGradient>")
    end
    return nothing
end

function _svgHeader(io, W::Int, H::Int)
    println(io, "<?xml version=\"1.0\" encoding=\"UTF-8\"?>")
    println(io,
        "<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"$W\" " *
        "height=\"$H\" viewBox=\"0 0 $W $H\">")
    return nothing
end

"""
Write `picture` to `file` as a standalone SVG (D030 §6.1; T025) and return
the document text. Strict by default: the first unexportable op (clearRect,
angular / ImagePaint fills, non-Normal blends, degenerate or out-of-range
gradient stops, non-finite geometry) raises `ArgumentError` naming the op
index, and no file is written. `rasterFallback = true` renders the whole
picture into a single embedded `<image>` (identifiable by its data-URI; the
PNGFiles opt-in, D014) instead of vector content.
"""
function writeSvg(file::String, picture::Picture; rasterFallback::Bool = false)
    W = Int(picture.size.x)
    H = Int(picture.size.y)
    if rasterFallback
        img = newImage(W, H)
        drawPicture(img, picture)
        b64 = _base64Encode(encodePNG(img))
        buf = IOBuffer()
        _svgHeader(buf, W, H)
        println(buf, "<!-- Vetra rasterFallback: whole-picture raster (D030) -->")
        println(buf, "<image x=\"0\" y=\"0\" width=\"$W\" height=\"$H\" " *
            "href=\"data:image/png;base64,$b64\"/>")
        println(buf, "</svg>")
        doc = String(buf.data[1:buf.size])
        _svgWriteFile(file, doc)
        return doc
    end
    _svgPreScan(picture)
    # Data URIs up front (the pre-scan guarantees PNGFiles availability).
    uris = Dict{Int,String}()
    for (i, op) in enumerate(picture.ops)
        op isa DrawImageOp || continue
        uris[i] = "data:image/png;base64," *
            _base64Encode(encodePNG(op.image))
    end
    # Group-clip pre-pass: a clip is known at GroupEnd, so map each group
    # (by start ordinal — nesting depth collides across sibling groups) to
    # its clipPath id before emitting. `nxt` is the monotonic start
    # counter; `g` is the popped id (reusing one variable for both made
    # the counter restart after a close).
    groupClipId = Dict{Int,Int}()
    gstack = Int[]
    nxt = 0
    cp = 0
    for op in picture.ops
        if op isa GroupStart
            nxt += 1
            push!(gstack, nxt)
        elseif op isa GroupEnd
            g = pop!(gstack)
            if !isempty(op.clips)
                cp += 1
                groupClipId[g] = cp
            end
        end
    end
    buf = IOBuffer()
    _svgHeader(buf, W, H)
    depth = 0
    gn = 0
    im = 0
    gstack = Int[]
    nxt = 0
    for (i, op) in enumerate(picture.ops)
        ind = "  " ^ depth
        if op isa GroupStart
            depth += 1
            nxt += 1
            push!(gstack, nxt)
            attrs = String[]
            o = clamp(op.opacity, Float32(0), Float32(1))
            o != Float32(1) && push!(attrs, "opacity=\"" * _n(o) * "\"")
            cN = get(groupClipId, nxt, 0)
            cN > 0 && push!(attrs, "clip-path=\"url(#cp$cN)\"")
            tag = isempty(attrs) ? "<g>" : "<g " * join(attrs, " ") * ">"
            println(buf, ("  " ^ depth) * tag)
        elseif op isa GroupEnd
            g = pop!(gstack)
            cN = get(groupClipId, g, 0)
            if cN > 0
                println(buf, ind * "<clipPath id=\"cp$cN\">")
                for c in op.clips
                    rule = c.windingRule === EvenOdd ?
                        " fill-rule=\"evenodd\"" : ""
                    println(buf,
                        ("  " ^ (depth + 1)) *
                        "<path d=\"" * _svgPathD(c.path) * "\"" * rule * "/>")
                end
                println(buf, ind * "</clipPath>")
            end
            depth -= 1
            println(buf, ind * "</g>")
        elseif op isa FillOp
            paint = op.paint
            fillAttr = ""
            fo = Float32(1)
            if paint.kind === SolidPaint
                fillAttr = "fill=\"" * _svgHex(paint.color) * "\""
                fo = _svgSolidOpacity(paint)
            else # LinearGradientPaint || RadialGradientPaint (pre-scanned)
                gn += 1
                _svgGradient(buf, paint, op.tform, depth, gn)
                fillAttr = "fill=\"url(#gn$gn)\""
                fo = clamp(paint.opacity, Float32(0), Float32(1))
            end
            attrs = "d=\"" * _svgPathD(op.path) * "\""
            op.tform != mat3() &&
                (attrs *= " transform=\"" * _svgMatrix(op.tform) * "\"")
            attrs *= " " * fillAttr
            fo != Float32(1) &&
                (attrs *= " fill-opacity=\"" * _n(fo) * "\"")
            op.windingRule === EvenOdd && (attrs *= " fill-rule=\"evenodd\"")
            println(buf, ind * "<path " * attrs * "/>")
        elseif op isa StrokeOp
            paint = op.paint
            attrs = "d=\"" * _svgPathD(op.path) * "\""
            op.tform != mat3() &&
                (attrs *= " transform=\"" * _svgMatrix(op.tform) * "\"")
            attrs *= " fill=\"none\" stroke=\"" * _svgHex(paint.color) * "\""
            so = _svgSolidOpacity(paint)
            so != Float32(1) &&
                (attrs *= " stroke-opacity=\"" * _n(so) * "\"")
            attrs *= " stroke-width=\"" * _n(op.width) * "\""
            cap = op.cap === RoundCap ? "round" : op.cap === SquareCap ?
                "square" : "butt"
            jn = op.join === RoundJoin ? "round" : op.join === BevelJoin ?
                "bevel" : "miter"
            attrs *= " stroke-linecap=\"$cap\" stroke-linejoin=\"$jn\""
            attrs *= " stroke-miterlimit=\"" * _n(op.miterLimit) * "\""
            if !isempty(op.dashes)
                attrs *= " stroke-dasharray=\"" *
                    join(string.(op.dashes), " ") * "\""
            end
            println(buf, ind * "<path " * attrs * "/>")
        else # DrawImageOp
            im += 1
            attrs = "x=\"0\" y=\"0\" width=\"" * string(op.image.width) *
                "\" height=\"" * string(op.image.height) *
                "\" preserveAspectRatio=\"none\" href=\"" * uris[i] * "\""
            op.imageMat != mat3() &&
                (attrs *= " transform=\"" * _svgMatrix(op.imageMat) * "\"")
            println(buf, ind * "<image " * attrs * "/>")
        end
    end
    println(buf, "</svg>")
    doc = String(buf.data[1:buf.size])
    _svgWriteFile(file, doc)
    return doc
end

"""Write `doc` to `file` (explicit open/write/close: this build
mis-parses do-block argument binding, and `write(file, doc)` is not a
Base call)."""
function _svgWriteFile(file::String, doc::String)
    io = open(file, "w")
    try
        write(io, doc)
    finally
        close(io)
    end
    return nothing
end
