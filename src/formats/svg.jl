# ---------- SVG (T008) ----------
# Upstream: pixie/fileformats/svg.nim -- xmlSignature/svgSignature (L9-11),
# Svg/SvgProperties/LinearGradient (L13-35), parseSvgProperties (L54-300),
# parseSvgElement (L302-503), parseSvg (L505-558), newImage(Svg) (L560-611).
#
# Porting notes:
# - Upstream `parseFloat` is Float64; every value enters our Float32
#   geometry/paint types at the same point the upstream float32 fields do
#   (implicit widening->narrowing at assignment).
# - Upstream `mat3()` fields are assigned as `m[row, col]`; our row-major
#   `Mat3` data layout maps SVG `matrix(a b c d e f)` to
#   (a, b, 0, c, d, 0, e, f, 1) (x' = ax + cy + e, y' = bx + dy + f).
# - The XML document model is a small `SvgNode` (tag/attrs/children). The
#   `parseSvg(root)` entry point is pure core; `parseSvg(data::String)`
#   builds the tree from the opt-in `XML` package (pixie's xmlparser/
#   xmltree are reference-only dependencies, per D008/D014).
# - `defs` children are NOT recursed into (upstream `parseSvgElement` case
#   "defs": no recursion) -- gradients must be direct children of `<g>` or
#   `<svg>`, pinned behavior.
# - Invalid input raises `ArgumentError` with the upstream message
#   (upstream `PixieError`).

const SVG_XML_SIGNATURE = "<?xml"
const SVG_SIGNATURE = "<svg"

"""Small XML element DOM node used by the SVG port (upstream `XmlNode`)."""
struct SvgNode
    tag::String
    attrs::Vector{Tuple{String,String}}
    children::Vector{SvgNode}
end

"""Upstream `SvgProperties` (attribute-derived element properties)."""
# mutable: parseSvgProperties updates fields in place (upstream Nim object).
mutable struct SvgProperties
    display::Bool
    fillRule::WindingRule
    fill::String
    stroke::ColorRGBX
    strokeWidth::Float32
    strokeLineCap::LineCap
    strokeLineJoin::LineJoin
    strokeMiterLimit::Float32
    strokeDashArray::Vector{Float32}
    transform::Mat3
    opacity::Float32
    fillOpacity::Float32
    strokeOpacity::Float32
end

"""Upstream `LinearGradient` (only `gradientUnits = "userSpaceOnUse"`)."""
struct SvgLinearGradient
    x1::Float32
    y1::Float32
    x2::Float32
    y2::Float32
    stops::Vector{ColorStop}
end

"""Upstream `Svg`: parsed elements plus the gradient table."""
struct Svg
    width::Int
    height::Int
    elements::Vector{Tuple{Path,SvgProperties}}
    linearGradients::Dict{String,SvgLinearGradient}
end

function _svgFail()
    throw(ArgumentError("Invalid SVG data"))
end

# Julia struct assignment aliases (this build has no `copy` for structs);
# upstream Nim copies `SvgProperties` by value in `result = inherited`.
function _svgCopyProps(p::SvgProperties)
    # strokeDashArray is copied (upstream `result = inherited` value-copies
    # the seq); appending child values must not reach the parent's list.
    return SvgProperties(p.display, p.fillRule, p.fill, p.stroke,
        p.strokeWidth, p.strokeLineCap, p.strokeLineJoin, p.strokeMiterLimit,
        copy(p.strokeDashArray), p.transform, p.opacity, p.fillOpacity,
        p.strokeOpacity)
end

"""Upstream `attrOrDefault`: missing attributes and empty values both
read as the default."""
function _svgAttr(node::SvgNode, name::String, default = "")
    for (k, v) in node.attrs
        k == name && return isempty(v) ? default : v
    end
    return default
end

"""Upstream `parseFloat`: Float64 parse; failures are `Invalid SVG data`.
AbstractString because `split` yields SubStrings in this build."""
function _svgParseFloat(text::AbstractString)
    try
        return parse(Float64, text)
    catch
        _svgFail()
    end
end

"""Upstream `parseInt` (viewBox only); failures are `Invalid SVG data`.
AbstractString because `split` yields SubStrings in this build."""
function _svgParseInt(text::AbstractString)
    try
        return parse(Int, text)
    catch
        _svgFail()
    end
end

"""
Upstream `splitArgs` (inside `parseSvgProperties`): commas become spaces,
whitespace split, empty entries dropped.
"""
function _svgSplitArgs(s::AbstractString)
    out = String[]
    for part in split(replace(s, ',' => ' '), ' ')
        !isempty(part) && push!(out, part)
    end
    return out
end

"""Upstream `initSvgProperties` (L44-52)."""
function svgDefaultProperties()
    return SvgProperties(
        true, NonZero, "black",
        ColorRGBX(0x00, 0x00, 0x00, 0x00),
        Float32(1), ButtCap, MiterJoin, defaultMiterLimit,
        Vector{Float32}(), mat3(),
        Float32(1), Float32(1), Float32(1))
end

"""
Upstream `parseSvgProperties` (L54-300): node attributes first, then the
`style` attribute fills in any property the element did not set itself;
empty values inherit from the parent.
"""
function parseSvgProperties(node::SvgNode, inherited::SvgProperties)
    # Upstream `result = inherited` copies the Nim object by value; Julia
    # would alias the mutable struct, and every element in the tree would
    # render with the last-written values.
    result = _svgCopyProps(inherited)

    fillRule = _svgAttr(node, "fill-rule")
    fill = _svgAttr(node, "fill")
    stroke = _svgAttr(node, "stroke")
    strokeWidth = _svgAttr(node, "stroke-width")
    strokeLineCap = _svgAttr(node, "stroke-linecap")
    strokeLineJoin = _svgAttr(node, "stroke-linejoin")
    strokeMiterLimit = _svgAttr(node, "stroke-miterlimit")
    strokeDashArray = _svgAttr(node, "stroke-dasharray")
    transform = _svgAttr(node, "transform")
    style = _svgAttr(node, "style")
    display = _svgAttr(node, "display")
    opacity = _svgAttr(node, "opacity")
    fillOpacity = _svgAttr(node, "fill-opacity")
    strokeOpacity = _svgAttr(node, "stroke-opacity")

    for pair in split(style, ';')
        parts = split(pair, ':')
        if length(parts) == 2
            # Do not override element properties (upstream).
            # String(): split/strip yield SubStrings; properties are String.
            key = String(strip(parts[1]))
            value = String(strip(parts[2]))
            if key == "fill-rule"
                isempty(fillRule) && (fillRule = value)
            elseif key == "fill"
                isempty(fill) && (fill = value)
            elseif key == "stroke"
                isempty(stroke) && (stroke = value)
            elseif key == "stroke-linecap"
                isempty(strokeLineCap) && (strokeLineCap = value)
            elseif key == "stroke-linejoin"
                isempty(strokeLineJoin) && (strokeLineJoin = value)
            elseif key == "stroke-width"
                isempty(strokeWidth) && (strokeWidth = value)
            elseif key == "stroke-miterlimit"
                isempty(strokeMiterLimit) && (strokeMiterLimit = value)
            elseif key == "stroke-dasharray"
                isempty(strokeDashArray) && (strokeDashArray = value)
            elseif key == "display"
                isempty(display) && (display = value)
            elseif key == "opacity"
                isempty(opacity) && (opacity = value)
            elseif key == "fillOpacity"
                isempty(fillOpacity) && (fillOpacity = value)
            elseif key == "strokeOpacity"
                isempty(strokeOpacity) && (strokeOpacity = value)
            end
        end
    end

    if !isempty(display)
        result.display = strip(display) != "none"
    end

    if !isempty(opacity)
        result.opacity = Float32(clamp(_svgParseFloat(opacity), 0.0, 1.0))
    end

    if fillRule == ""
        # Inherit.
    elseif fillRule == "nonzero"
        result.fillRule = NonZero
    elseif fillRule == "evenodd"
        result.fillRule = EvenOdd
    else
        throw(ArgumentError("Invalid fill-rule value $fillRule"))
    end

    if fill == "" || fill == "currentColor"
        result.fill = inherited.fill
    else
        result.fill = fill
    end

    if stroke == ""
        # Inherit.
    elseif stroke == "currentColor"
        if result.stroke == ColorRGBX(0x00, 0x00, 0x00, 0x00)
            result.stroke = ColorRGBX(0x00, 0x00, 0x00, 0xff)
        end
    elseif stroke == "none"
        result.stroke = ColorRGBX(0x00, 0x00, 0x00, 0x00)
    else
        result.stroke = rgbx(parseHtmlColor(stroke))
    end

    if !isempty(fillOpacity)
        result.fillOpacity =
            Float32(clamp(_svgParseFloat(fillOpacity), 0.0, 1.0))
    end

    if !isempty(strokeOpacity)
        result.strokeOpacity =
            Float32(clamp(_svgParseFloat(strokeOpacity), 0.0, 1.0))
    end

    if strokeWidth == ""
        # Inherit.
    else
        if endswith(strokeWidth, "px")
            strokeWidth = strokeWidth[1:(length(strokeWidth) - 2)]
        end
        result.strokeWidth = Float32(_svgParseFloat(strokeWidth))
        if result.stroke == ColorRGBX(0x00, 0x00, 0x00, 0x00)
            result.stroke = ColorRGBX(0x00, 0x00, 0x00, 0xff)
        end
    end

    if strokeLineCap == ""
        # Inherit.
    elseif strokeLineCap == "butt"
        result.strokeLineCap = ButtCap
    elseif strokeLineCap == "round"
        result.strokeLineCap = RoundCap
    elseif strokeLineCap == "square"
        result.strokeLineCap = SquareCap
    elseif strokeLineCap == "inherit"
        # Keep inherited.
    else
        throw(ArgumentError("Invalid stroke-linecap value $strokeLineCap"))
    end

    if strokeLineJoin == ""
        # Inherit.
    elseif strokeLineJoin == "miter"
        result.strokeLineJoin = MiterJoin
    elseif strokeLineJoin == "round"
        result.strokeLineJoin = RoundJoin
    elseif strokeLineJoin == "bevel"
        result.strokeLineJoin = BevelJoin
    elseif strokeLineJoin == "inherit"
        # Keep inherited.
    else
        throw(ArgumentError("Invalid stroke-linejoin value $strokeLineJoin"))
    end

    if strokeMiterLimit != ""
        result.strokeMiterLimit = Float32(_svgParseFloat(strokeMiterLimit))
    end

    if strokeDashArray != ""
        values = _svgSplitArgs(strokeDashArray)
        # Upstream appends the child's values onto the inherited list
        # (pinned quirk: parent [1,2] + child [3,4] -> [1,2,3,4]).
        append!(result.strokeDashArray,
            [Float32(_svgParseFloat(v)) for v in values])
    end

    if transform == ""
        # Inherit.
    else
        remaining = transform
        while !isempty(remaining)
            closeAt = findfirst(')', remaining)
            closeAt === nothing &&
                throw(ArgumentError("Unsupported SVG transform: $transform"))
            f = strip(remaining[1:closeAt])
            remaining = remaining[closeAt + 1:end]

            if startswith(f, "matrix(")
                arr = _svgSplitArgs(f[8:end - 1])
                length(arr) != 6 &&
                    throw(ArgumentError("Unsupported SVG transform: $transform"))
                # SVG matrix(a b c d e f): x' = ax + cy + e, y' = bx + dy + f.
                # Row-major data layout: x' = d1x + d4y + d7, y' = d2x + d5y + d8.
                m = Mat3(
                    (Float32(_svgParseFloat(arr[1])),
                     Float32(_svgParseFloat(arr[2])), Float32(0),
                     Float32(_svgParseFloat(arr[3])),
                     Float32(_svgParseFloat(arr[4])), Float32(0),
                     Float32(_svgParseFloat(arr[5])),
                     Float32(_svgParseFloat(arr[6])), Float32(1)))
                result.transform = result.transform * m
            elseif startswith(f, "translate(")
                components = _svgSplitArgs(f[11:end - 1])
                tx = Float32(_svgParseFloat(components[1]))
                ty = length(components) == 1 ? Float32(0) :
                    Float32(_svgParseFloat(components[2]))
                result.transform =
                    result.transform * translate(Vec2(tx, ty))
            elseif startswith(f, "rotate(")
                values = _svgSplitArgs(f[8:end - 1])
                angle = Float32(_svgParseFloat(values[1]) * pi / 180)
                cx = length(values) > 1 ?
                    Float32(_svgParseFloat(values[2])) : Float32(0)
                cy = length(values) > 2 ?
                    Float32(_svgParseFloat(values[3])) : Float32(0)
                center = Vec2(cx, cy)
                result.transform = result.transform *
                    translate(center) * rotate(angle) *
                    translate(Vec2(-cx, -cy))
            elseif startswith(f, "scale(")
                values = _svgSplitArgs(f[7:end - 1])
                sx = Float32(_svgParseFloat(values[1]))
                sy = length(values) > 1 ?
                    Float32(_svgParseFloat(values[2])) : sx
                result.transform = result.transform * scale(Vec2(sx, sy))
            else
                throw(ArgumentError("Unsupported SVG transform: $transform"))
            end
        end
    end

    return result
end

"""
Upstream `parseSvgElement` (L302-503): returns the `(Path, SvgProperties)`
elements for `node` and, for groups, its descendants. Unsupported tags are
skipped; `linearGradient` fills the gradient table.
"""
function parseSvgElement(
    node::SvgNode,
    gradients::Dict{String,SvgLinearGradient},
    propertiesStack::Vector{SvgProperties}
)
    out = Vector{Tuple{Path,SvgProperties}}()

    if node.tag in ("title", "desc")
        return out
    end

    if node.tag == "defs"
        # Upstream: no recursion into defs (pinned behavior).
        return out
    end

    if node.tag == "g"
        props = parseSvgProperties(node, propertiesStack[end])
        push!(propertiesStack, props)
        for child in node.children
            append!(out, parseSvgElement(child, gradients, propertiesStack))
        end
        pop!(propertiesStack)
        return out
    end

    if node.tag == "path"
        d = _svgAttr(node, "d")
        props = parseSvgProperties(node, propertiesStack[end])
        path = nothing # pre-declare: this build loses try-assigned locals
        try
            path = parsePath(d)
        catch
            _svgFail()
        end
        push!(out, (path, props))
        return out
    end

    if node.tag == "line"
        props = parseSvgProperties(node, propertiesStack[end])
        x1 = Float32(_svgParseFloat(_svgAttr(node, "x1", "0")))
        y1 = Float32(_svgParseFloat(_svgAttr(node, "y1", "0")))
        x2 = Float32(_svgParseFloat(_svgAttr(node, "x2", "0")))
        y2 = Float32(_svgParseFloat(_svgAttr(node, "y2", "0")))
        path = newPath()
        moveTo(path, x1, y1)
        lineTo(path, x2, y2)
        push!(out, (path, props))
        return out
    end

    if node.tag in ("polyline", "polygon")
        props = parseSvgProperties(node, propertiesStack[end])
        points = _svgAttr(node, "points")
        vecs = Vector{Vec2}()
        if occursin(",", points)
            for pair in split(points, ' ')
                parts = split(pair, ',')
                length(parts) != 2 && _svgFail()
                push!(vecs, Vec2(
                    Float32(_svgParseFloat(parts[1])),
                    Float32(_svgParseFloat(parts[2]))))
            end
        else
            parts = split(points, ' ')
            length(parts) % 2 != 0 && _svgFail()
            for i in 1:(length(parts) ÷ 2)
                push!(vecs, Vec2(
                    Float32(_svgParseFloat(parts[2 * i - 1])),
                    Float32(_svgParseFloat(parts[2 * i]))))
            end
        end
        isempty(vecs) && _svgFail()

        path = newPath()
        moveTo(path, vecs[1].x, vecs[1].y)
        for i in 2:length(vecs)
            lineTo(path, vecs[i].x, vecs[i].y)
        end
        if node.tag == "polygon"
            closePath(path)
        end
        push!(out, (path, props))
        return out
    end

    if node.tag == "rect"
        props = parseSvgProperties(node, propertiesStack[end])
        x = Float32(_svgParseFloat(_svgAttr(node, "x", "0")))
        y = Float32(_svgParseFloat(_svgAttr(node, "y", "0")))
        w = Float32(_svgParseFloat(_svgAttr(node, "width", "0")))
        h = Float32(_svgParseFloat(_svgAttr(node, "height", "0")))

        if w == 0 || h == 0
            return out
        end

        rx = max(Float32(_svgParseFloat(_svgAttr(node, "rx", "0"))),
            Float32(0))
        ry = max(Float32(_svgParseFloat(_svgAttr(node, "ry", "0"))),
            Float32(0))

        path = newPath()
        if rx > 0 || ry > 0
            if rx == 0
                rx = ry
            elseif ry == 0
                ry = rx
            end
            rx = min(rx, w / Float32(2))
            ry = min(ry, h / Float32(2))

            moveTo(path, x + rx, y)
            lineTo(path, x + w - rx, y)
            ellipticalArcTo(path, rx, ry, Float32(0), false, true,
                x + w, y + ry)
            lineTo(path, x + w, y + h - ry)
            ellipticalArcTo(path, rx, ry, Float32(0), false, true,
                x + w - rx, y + h)
            lineTo(path, x + rx, y + h)
            ellipticalArcTo(path, rx, ry, Float32(0), false, true,
                x, y + h - ry)
            lineTo(path, x, y + ry)
            ellipticalArcTo(path, rx, ry, Float32(0), false, true,
                x + rx, y)
        else
            rect(path, x, y, w, h)
        end
        push!(out, (path, props))
        return out
    end

    if node.tag in ("circle", "ellipse")
        props = parseSvgProperties(node, propertiesStack[end])
        cx = Float32(_svgParseFloat(_svgAttr(node, "cx", "0")))
        cy = Float32(_svgParseFloat(_svgAttr(node, "cy", "0")))
        rx = Float32(0)
        ry = Float32(0)
        if node.tag == "circle"
            rx = Float32(_svgParseFloat(_svgAttr(node, "r")))
            ry = rx
        else
            rx = Float32(_svgParseFloat(_svgAttr(node, "rx", "0")))
            ry = Float32(_svgParseFloat(_svgAttr(node, "ry", "0")))
        end
        path = newPath()
        ellipse(path, cx, cy, rx, ry)
        push!(out, (path, props))
        return out
    end

    if node.tag == "radialGradient"
        return out
    end

    if node.tag == "linearGradient"
        id = _svgAttr(node, "id")
        gradientUnits = _svgAttr(node, "gradientUnits")
        gradientTransform = _svgAttr(node, "gradientTransform")

        if gradientUnits != "userSpaceOnUse"
            throw(ArgumentError("Unsupported gradient units: $gradientUnits"))
        end
        if gradientTransform != ""
            throw(ArgumentError("Unsupported gradient transform: $gradientTransform"))
        end

        x1 = Float32(_svgParseFloat(_svgAttr(node, "x1")))
        y1 = Float32(_svgParseFloat(_svgAttr(node, "y1")))
        x2 = Float32(_svgParseFloat(_svgAttr(node, "x2")))
        y2 = Float32(_svgParseFloat(_svgAttr(node, "y2")))

        stops = Vector{ColorStop}()
        for child in node.children
            if child.tag == "stop"
                color = _svgAttr(child, "stop-color")
                if color == ""
                    style = _svgAttr(child, "style")
                    for pair in split(style, ';')
                        parts = split(pair, ':')
                        if length(parts) == 2
                            if strip(parts[1]) == "stop-color"
                                if color == ""
                                    # Widen: strip of a SubString stays a
                                    # SubString, and colorStop wants String.
                                    color = String(strip(parts[2]))
                                end
                            end
                        end
                    end
                end
                if color == ""
                    throw(ArgumentError("Invalid SVG gradient, missing stop-color"))
                end
                push!(stops, colorStop(
                    color, Float32(_svgParseFloat(_svgAttr(child, "offset")))))
            end
        end

        gradients[id] = SvgLinearGradient(x1, y1, x2, y2, stops)
        return out
    end

    # Skip unsupported tags (mask, filter, text, ...) and continue (upstream).
    return out
end

"""
Parse an SVG document tree (upstream `parseSvg(root: XmlNode, width,
height)`): defaults to the viewBox size; explicit (width, height) adds the
box scale to the root transform.
"""
function parseSvg(root::SvgNode, width::Int = 0, height::Int = 0)
    if root.tag != "svg"
        _svgFail()
    end

    viewBox = _svgAttr(root, "viewBox")
    box = split(viewBox, ' ')
    length(box) < 4 && _svgFail()
    viewBoxMinX = _svgParseInt(box[1])
    viewBoxMinY = _svgParseInt(box[2])
    viewBoxWidth = _svgParseInt(box[3])
    viewBoxHeight = _svgParseInt(box[4])

    rootProps = svgDefaultProperties()
    rootProps = parseSvgProperties(root, rootProps)

    if viewBoxMinX != 0 || viewBoxMinY != 0
        viewBoxMin = Vec2(Float32(-viewBoxMinX), Float32(-viewBoxMinY))
        rootProps.transform = rootProps.transform * translate(viewBoxMin)
    end

    w = 0
    h = 0
    if width == 0 && height == 0
        # Default to the view box size.
        w, h = viewBoxWidth, viewBoxHeight
    else
        w, h = width, height
        scaleX = Float32(width) / Float32(viewBoxWidth)
        scaleY = Float32(height) / Float32(viewBoxHeight)
        rootProps.transform = rootProps.transform *
            scale(Vec2(scaleX, scaleY))
    end

    gradients = Dict{String,SvgLinearGradient}()
    elements = Vector{Tuple{Path,SvgProperties}}()
    propertiesStack = SvgProperties[rootProps]
    for node in root.children
        append!(elements, parseSvgElement(node, gradients, propertiesStack))
    end

    return Svg(w, h, elements, gradients)
end

"""
Render a parsed SVG (upstream `newImage(svg)`): each element is filled with
its paint (first element overwrites, later ones composite normally) and
stroked when the stroke color/width are set.
"""
function newImage(svg::Svg)
    result = newImage(svg.width, svg.height)

    blendMode = OverwriteBlend # Start as overwrite.
    for (path, props) in svg.elements
        if props.display && props.opacity > Float32(0)
            if props.fill != "none"
                paint = if startswith(props.fill, "url(")
                    # First ')' at 1-based position >= 6 (this build has no
                    # 3-arg findfirst): search the tail, offset by +5.
                    closingParen = findfirst(')', props.fill[6:end])
                    if closingParen === nothing
                        throw(ArgumentError(
                            "Malformed fill: $(props.fill)"))
                    end
                    id = props.fill[6:(closingParen + 4)]
                    if haskey(svg.linearGradients, id)
                        linearGradient = svg.linearGradients[id]
                        p = newPaint(LinearGradientPaint)
                        p.gradientHandlePositions = [
                            props.transform *
                                Vec2(linearGradient.x1, linearGradient.y1),
                            props.transform *
                                Vec2(linearGradient.x2, linearGradient.y2)]
                        p.gradientStops = linearGradient.stops
                        p
                    else
                        throw(ArgumentError("Missing SVG resource $id"))
                    end
                else
                    Paint(rgbx(parseHtmlColor(props.fill)))
                end

                paint.opacity = props.fillOpacity * props.opacity
                paint.blendMode = blendMode

                fillPath(
                    result, path, paint;
                    transform = props.transform,
                    windingRule = props.fillRule)
            end

            # Switch to normal when compositing multiple paths.
            blendMode = NormalBlend

            if props.stroke != ColorRGBX(0x00, 0x00, 0x00, 0x00) &&
                props.strokeWidth > Float32(0)
                p = Paint(props.stroke)
                # Upstream: stroke color alpha is float32 end to end --
                # `(a/255) * (opacity*strokeOpacity)` then `round(*255)` at the
                # Color->ColorRGBX boundary. Truncating instead shifts the
                # alpha by 1 whenever the product hits a .5 (e.g.
                # stroke-opacity 0.5), moving AA stroke pixels by ±1.
                sa = Float32(p.color.a) / Float32(255)
                sa = sa * (props.opacity * props.strokeOpacity)
                p.color = ColorRGBA(
                    p.color.r, p.color.g, p.color.b,
                    UInt8(roundHalfAway(sa * Float32(255))))
                strokePath(
                    result, path, p;
                    transform = props.transform,
                    strokeWidth = props.strokeWidth,
                    lineCap = props.strokeLineCap,
                    lineJoin = props.strokeLineJoin,
                    miterLimit = props.strokeMiterLimit,
                    dashes = props.strokeDashArray)
            end
        end
    end

    return result
end

# ---------- XML backend (opt-in, D014) ----------

const _XML_PKGID = Base.PkgId(
    Base.UUID("72c71f33-b9b6-44de-8c94-c961784809e2"), "XML")

"""
The `XML` module, loaded on first use (lazy discovery, D028), or a clear
install hint (D014). Environments without XML load normally and get this
error only on use.
"""
function _requireXml()
    if Base.locate_package(_XML_PKGID) === nothing
        throw(ErrorException(
            "SVG support is opt-in: add the XML package to your environment " *
            "(Pkg.add(\"XML\")) and retry"))
    end
    return Base.require(_XML_PKGID)
end

"""True for `XML` element nodes (text/comments/xml-decl are skipped).
Only Element nodes carry a non-`nothing` `tag` (verified on XML v0.4.7;
this build materializes `NodeType` enum values without named constants,
so the tag check is the discriminator)."""
function _isXmlElement(el)
    return el.tag !== nothing
end

"""
Collapse whitespace runs to single spaces. Upstream's Nim xmlparser
normalizes each space/tab/CR/LF in quoted attribute values to a space
(without collapsing runs); XML.jl preserves them as-is. Collapsing is
observationally equivalent for our parsers: their tokenizers
(`splitArgs`, path/points splitting) drop empty fields either way.
"""
function _svgCollapseWs(s::String)
    if isempty(s)
        return s
    end
    out = String[]
    prevWs = false
    for c in s
        if c == ' ' || c == '\t' || c == '\n' || c == '\r'
            if !prevWs
                push!(out, " ")
            end
            prevWs = true
        else
            push!(out, string(c))
            prevWs = false
        end
    end
    return join(out)
end

"""Build an `SvgNode` tree from an `XML` element node (skipping text)."""
function _svgNodeFrom(el)
    attrs = el.attributes
    attrList = if attrs === nothing
        Tuple{String,String}[]
    else
        [(String(k), _svgCollapseWs(String(v))) for (k, v) in attrs]
    end
    children = el.children
    kids = if children === nothing
        SvgNode[]
    else
        [_svgNodeFrom(c) for c in children if _isXmlElement(c)]
    end
    return SvgNode(String(el.tag), attrList, kids)
end

"""
Parse SVG data (upstream `parseSvg(data: string, width, height)`): XML parse
(opt-in `XML` package) then the core `parseSvg(root)`.
"""
function parseSvg(data::String, width::Int = 0, height::Int = 0)
    xml = _requireXml()
    # Pre-declare `doc`: this build loses locals first assigned inside a
    # try block (verified; see T008 notes).
    doc = nothing
    try
        # invokelatest: XML may be required (lazy discovery, D028) by this
        # very call, so `parse` can be newer than this method instance.
        doc = Base.invokelatest(xml.parse, data, xml.Node)
    catch
        _svgFail()
    end
    root = nothing
    for c in doc.children
        if _isXmlElement(c)
            root = c
            break
        end
    end
    root === nothing && _svgFail()
    return parseSvg(_svgNodeFrom(root), width, height)
end
