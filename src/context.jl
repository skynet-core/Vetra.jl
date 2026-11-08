# ---------- context (T005 + T007b mask/layer) ----------
# Upstream: pixie/contexts.nim -- Context state (L17-48),
# newContext (L53-80), state/save/saveLayer/restore (L73-137),
# path command wrappers (L261-365), fill/stroke (L139-177, L365-423) and
# the rect operations (L425-467), clip (L384-408),
# setTransform/getTransform/transform/translate/scale/rotate/resetTransform
# (L521-558, all post-multiply: downstream applied first), strokeSegment
# (L709-720).
# Documented deviations:
# - `restore` with an empty stack raises ArgumentError (upstream is a no-op);
# - fillStyle/strokeStyle accept Paint | ColorRGB | ColorRGBA | ColorRGBX |
#   hex String (upstream's parseSomePaint set) and are converted at draw
#   time, so an invalid string raises on fill/stroke, not at assignment;
# - `clip` fills the mask with the identity transform: upstream L395/L400
#   pass no transform, so the context matrix does not clip the path.
# The field is named `mat`, as upstream; getTransform/setTransform/
# resetTransform are the accessors. lineDash and the text state landed
# with T009 (text drawing needs both); upstream `ContextState` saves
# font/fontSize/textAlign/lineDash but NOT textBaseline (quirk preserved).

const SomePaint = Union{Paint, ColorRGB, ColorRGBA, ColorRGBX, String}

"""
Saved context state (upstream `ContextState`): `mask` is copied on save
(upstream `state()`); `layer` is the layer reference active at save time.
Upstream saves font/fontSize/textAlign/lineDash but not textBaseline —
the port keeps that quirk.
"""
struct ContextState
    fillStyle::SomePaint
    strokeStyle::SomePaint
    globalAlpha::Float32
    lineWidth::Float32
    miterLimit::Float32
    lineCap::LineCap
    lineJoin::LineJoin
    mat::Mat3
    mask::Union{Image,Nothing}
    layer::Union{Image,Nothing}
    font::String
    fontSize::Float32
    textAlign::HorizontalAlignment
    lineDash::Vector{Float32}
end

"""Minimal drawing context (upstream `newContext`): opaque-black solid
fill/stroke, globalAlpha 1, lineWidth 1, miterLimit 10, ButtCap/MiterJoin,
identity transform, empty path, no mask/layer; stateStack holds saves."""
mutable struct Context
    image::Image
    fillStyle::SomePaint
    strokeStyle::SomePaint
    globalAlpha::Float32
    lineWidth::Float32
    miterLimit::Float32
    lineCap::LineCap
    lineJoin::LineJoin
    font::String
    fontSize::Float32
    textAlign::HorizontalAlignment
    textBaseline::BaselineAlignment
    lineDash::Vector{Float32}
    path::Path
    mat::Mat3
    mask::Union{Image,Nothing}
    layer::Union{Image,Nothing}
    stateStack::Vector{ContextState}
    typefaces::Dict{String,Typeface} # ctx.font -> loaded typeface cache
end

function Context(image::Image)
    return Context(
        image,
        Paint(rgba(0x00, 0x00, 0x00, 0xff)),
        Paint(rgba(0x00, 0x00, 0x00, 0xff)),
        Float32(1),
        Float32(1),
        Float32(10),
        ButtCap,
        MiterJoin,
        "",
        Float32(12),
        LeftAlign,
        AlphabeticBaseline,
        Vector{Float32}(),
        newPath(),
        mat3(),
        nothing,
        nothing,
        Vector{ContextState}(),
        Dict{String,Typeface}())
end

"""Context over a new image (upstream `newContext(width, height)`)."""
Context(width::Int, height::Int) = Context(newImage(width, height))

# ---------- state ----------

"""Upstream `state()`: the snapshot a save pushes (mask copied, layer nil)."""
function _ctxState(ctx::Context; layer = nothing)
    return ContextState(
        ctx.fillStyle, ctx.strokeStyle, ctx.globalAlpha,
        ctx.lineWidth, ctx.miterLimit, ctx.lineCap, ctx.lineJoin,
        ctx.mat,
        ctx.mask === nothing ? nothing : copy(ctx.mask),
        layer,
        ctx.font, ctx.fontSize, ctx.textAlign, copy(ctx.lineDash))
end

"""
Push the current state onto the stack (upstream `save`). As upstream, the
solid paints are copied after the push, so mutating a later-assigned Paint
does not rewrite stored state (and editing the original after `save` does
not either); the mask image is copied on save.
"""
function save(ctx::Context)
    push!(ctx.stateStack, _ctxState(ctx))
    if ctx.fillStyle isa Paint
        ctx.fillStyle = copy(ctx.fillStyle)
    end
    if ctx.strokeStyle isa Paint
        ctx.strokeStyle = copy(ctx.strokeStyle)
    end
    return nothing
end

"""
Push the current state and start drawing on a fresh full-size layer
(upstream `saveLayer`, which stores the layer *reference* then replaces
`ctx.layer`); `restore` composites the layer back.
"""
function saveLayer(ctx::Context)
    push!(ctx.stateStack, _ctxState(ctx; layer = ctx.layer))
    ctx.layer = newImage(ctx.image.width, ctx.image.height)
    return nothing
end

"""
Pop the most recent state (deviation: an empty stack raises `ArgumentError`;
upstream no-ops). The path is not part of the saved state, as upstream
(L111-137): a popped layer first gets the popped state's mask applied, then
is drawn onto the restored layer (or the root image).
"""
function restore(ctx::Context)
    isempty(ctx.stateStack) &&
        throw(ArgumentError("restore() with no saved state"))
    poppedLayer = ctx.layer
    poppedMask = ctx.mask
    state = pop!(ctx.stateStack)
    ctx.fillStyle = state.fillStyle
    ctx.strokeStyle = state.strokeStyle
    ctx.globalAlpha = state.globalAlpha
    ctx.lineWidth = state.lineWidth
    ctx.miterLimit = state.miterLimit
    ctx.lineCap = state.lineCap
    ctx.lineJoin = state.lineJoin
    ctx.font = state.font
    ctx.fontSize = state.fontSize
    ctx.textAlign = state.textAlign
    ctx.lineDash = state.lineDash
    ctx.mat = state.mat
    ctx.mask = state.mask
    ctx.layer = state.layer
    if poppedLayer !== nothing
        if poppedMask !== nothing
            draw(poppedLayer, poppedMask; blendMode = MaskBlend)
        end
        if ctx.layer !== nothing
            draw(ctx.layer, poppedLayer)
        else
            draw(ctx.image, poppedLayer)
        end
    end
    return nothing
end

# ---------- transforms (post-multiply, upstream order) ----------

"""Current transform matrix (upstream `getTransform`)."""
getTransform(ctx::Context) = ctx.mat

"""Override the transform (upstream `setTransform`)."""
function setTransform(ctx::Context, m::Mat3)
    ctx.mat = m
    return nothing
end

"""Reset to the identity (upstream `resetTransform`)."""
function resetTransform(ctx::Context)
    ctx.mat = mat3()
    return nothing
end

# ---------- point-in-path (upstream contexts.nim isPointInPath) ----------

function _ctxPathShapes(ctx::Context, path::Path)
    # Upstream fillOverlaps: shapes = commandsToShapes(true, pixelScale),
    # then transformed by the CTM.
    shapes = commandsToShapes(path, true, pixelScale(ctx.mat))
    if ctx.mat != mat3()
        for s in shapes
            for k in eachindex(s)
                s[k] = ctx.mat * s[k]
            end
        end
    end
    return shapes
end

"""Upstream `isPointInPath(ctx, path, pos, windingRule = NonZero)`."""
function isPointInPath(ctx::Context, path::Path, pos::Vec2,
    windingRule = NonZero)
    return overlaps(_ctxPathShapes(ctx, path), pos, windingRule)
end

isPointInPath(ctx::Context, path::Path, x::Float32, y::Float32,
    windingRule = NonZero) =
    isPointInPath(ctx, path, Vec2(x, y), windingRule)
isPointInPath(ctx::Context, path::Path, x::Real, y::Real, windingRule = NonZero) = # T014
    isPointInPath(ctx, path, Vec2(Float32(x), Float32(y)), windingRule)

isPointInPath(ctx::Context, pos::Vec2, windingRule = NonZero) =
    isPointInPath(ctx, ctx.path, pos, windingRule)

isPointInPath(ctx::Context, x::Float32, y::Float32, windingRule = NonZero) =
    isPointInPath(ctx, ctx.path, Vec2(x, y), windingRule)
isPointInPath(ctx::Context, x::Real, y::Real, windingRule = NonZero) = # T014
    isPointInPath(ctx, ctx.path, Vec2(Float32(x), Float32(y)), windingRule)

"""`ctx.mat = ctx.mat * m` -- the new matrix is applied to points first
(upstream `transform`)."""
function transform(ctx::Context, m::Mat3)
    ctx.mat = ctx.mat * m
    return nothing
end

function translate(ctx::Context, v::Vec2)
    ctx.mat = ctx.mat * translate(v)
    return nothing
end

translate(ctx::Context, x::Float32, y::Float32) =
    translate(ctx, Vec2(x, y))
translate(ctx::Context, x::Real, y::Real) = translate(ctx, Vec2(x, y)) # T014

function scale(ctx::Context, v::Vec2)
    ctx.mat = ctx.mat * scale(v)
    return nothing
end

scale(ctx::Context, x::Float32, y::Float32) =
    scale(ctx, Vec2(x, y))
scale(ctx::Context, x::Real, y::Real) = scale(ctx, Vec2(x, y)) # T014

"""`ctx.mat = ctx.mat * rotate(angle)` (upstream `rotate`, radians)."""
function rotate(ctx::Context, angle::Float32)
    ctx.mat = ctx.mat * rotate(angle)
    return nothing
end
"""Ordinary-number form (T014); the `Vec2` wrappers below convert the same way."""
rotate(ctx::Context, angle::Real) = rotate(ctx, Float32(angle))

# ---------- path command wrappers ----------

"""Start a new path by emptying the sub-path list (upstream `beginPath`)."""
function beginPath(ctx::Context)
    ctx.path = newPath()
    return nothing
end

function moveTo(ctx::Context, v::Vec2)
    moveTo(ctx.path, v)
    return nothing
end

moveTo(ctx::Context, x::Float32, y::Float32) =
    moveTo(ctx, Vec2(x, y))
moveTo(ctx::Context, x::Real, y::Real) = moveTo(ctx, Vec2(x, y)) # T014

function lineTo(ctx::Context, v::Vec2)
    lineTo(ctx.path, v)
    return nothing
end

lineTo(ctx::Context, x::Float32, y::Float32) =
    lineTo(ctx, Vec2(x, y))
lineTo(ctx::Context, x::Real, y::Real) = lineTo(ctx, Vec2(x, y)) # T014

function bezierCurveTo(ctx::Context, c1::Vec2, c2::Vec2, to::Vec2)
    bezierCurveTo(ctx.path, c1, c2, to)
    return nothing
end

function bezierCurveTo(
    ctx::Context, c1x::Float32, c1y::Float32, c2x::Float32, c2y::Float32,
    x::Float32, y::Float32
)
    return bezierCurveTo(ctx, Vec2(c1x, c1y), Vec2(c2x, c2y), Vec2(x, y))
end
bezierCurveTo(ctx::Context, c1x::Real, c1y::Real, c2x::Real, c2y::Real,
    x::Real, y::Real) = # T014
    bezierCurveTo(ctx, Vec2(c1x, c1y), Vec2(c2x, c2y), Vec2(x, y))

function quadraticCurveTo(ctx::Context, c::Vec2, to::Vec2)
    quadraticCurveTo(ctx.path, c, to)
    return nothing
end

function quadraticCurveTo(
    ctx::Context, cpx::Float32, cpy::Float32, x::Float32, y::Float32
)
    return quadraticCurveTo(ctx, Vec2(cpx, cpy), Vec2(x, y))
end
quadraticCurveTo(ctx::Context, cpx::Real, cpy::Real, x::Real, y::Real) = # T014
    quadraticCurveTo(ctx, Vec2(cpx, cpy), Vec2(x, y))

function arc(
    ctx::Context, x::Float32, y::Float32, r::Float32, a0::Float32, a1::Float32;
    ccw::Bool = false
)
    arc(ctx.path, x, y, r, a0, a1; ccw = ccw)
    return nothing
end
arc(ctx::Context, x::Real, y::Real, r::Real, a0::Real, a1::Real; ccw::Bool = false) = # T014
    arc(ctx.path, x, y, r, a0, a1; ccw = ccw)

function arc(ctx::Context, pos::Vec2, r::Float32, a::Vec2; ccw::Bool = false)
    arc(ctx.path, pos, r, a; ccw = ccw)
    return nothing
end

function arcTo(
    ctx::Context, x1::Float32, y1::Float32, x2::Float32, y2::Float32,
    radius::Float32
)
    arcTo(ctx.path, x1, y1, x2, y2, radius)
    return nothing
end
arcTo(ctx::Context, x1::Real, y1::Real, x2::Real, y2::Real, radius::Real) = # T014
    arcTo(ctx.path, x1, y1, x2, y2, radius)

function arcTo(ctx::Context, a::Vec2, b::Vec2, r::Float32)
    arcTo(ctx.path, a, b, r)
    return nothing
end

function closePath(ctx::Context)
    closePath(ctx.path)
    return nothing
end

function rect(ctx::Context, r::Rect)
    rect(ctx.path, r)
    return nothing
end

function rect(ctx::Context, x::Float32, y::Float32, w::Float32, h::Float32)
    rect(ctx.path, x, y, w, h)
    return nothing
end
function rect(ctx::Context, x::Real, y::Real, w::Real, h::Real)
    rect(ctx.path, x, y, w, h)
    return nothing
end

function ellipse(ctx::Context, c::Vec2, rx::Float32, ry::Float32)
    ellipse(ctx.path, c, rx, ry)
    return nothing
end

function ellipse(ctx::Context, x::Float32, y::Float32, rx::Float32, ry::Float32)
    ellipse(ctx.path, x, y, rx, ry)
    return nothing
end
function ellipse(ctx::Context, x::Real, y::Real, rx::Real, ry::Real)
    ellipse(ctx.path, x, y, rx, ry)
    return nothing
end

function roundedRect(
    ctx::Context, x::Float32, y::Float32, w::Float32, h::Float32,
    nw::Float32, ne::Float32, se::Float32, sw::Float32
)
    roundedRect(ctx.path, x, y, w, h, nw, ne, se, sw)
    return nothing
end

function roundedRect(
    ctx::Context, r::Rect, nw::Float32, ne::Float32, se::Float32, sw::Float32
)
    roundedRect(ctx.path, r, nw, ne, se, sw)
    return nothing
end
function roundedRect(
    ctx::Context, x::Real, y::Real, w::Real, h::Real, nw::Real, ne::Real,
    se::Real, sw::Real
)
    roundedRect(ctx.path, x, y, w, h, nw, ne, se, sw)
    return nothing
end

function circle(ctx::Context, cx::Float32, cy::Float32, r::Float32)
    circle(ctx.path, cx, cy, r)
    return nothing
end
function circle(ctx::Context, cx::Real, cy::Real, r::Real)
    circle(ctx.path, cx, cy, r)
    return nothing
end

function circle(ctx::Context, c::Circle)
    circle(ctx.path, c)
    return nothing
end

function polygon(ctx::Context, x::Float32, y::Float32, size::Float32, sides::Int)
    polygon(ctx.path, x, y, size, sides)
    return nothing
end
function polygon(ctx::Context, x::Real, y::Real, size::Real, sides::Int)
    polygon(ctx.path, x, y, size, sides)
    return nothing
end

function polygon(ctx::Context, pos::Vec2, size::Float32, sides::Int)
    polygon(ctx.path, pos, size, sides)
    return nothing
end

# ---------- drawing ----------

"""
Fill `path` into `image` with the current fillStyle (upstream private
`fill`, L139-156): when `globalAlpha != 1` the fill goes to a fresh layer,
the whole layer is scaled by `globalAlpha`, and restore composites it (the
mask applies through that restore, so the opacity lands under the clip).
"""
function fill(ctx::Context, image::Image, path::Path, windingRule = NonZero)
    img = image
    if ctx.globalAlpha != Float32(1)
        saveLayer(ctx)
        img = ctx.layer
    end
    fillPath(img, path, convert(Paint, ctx.fillStyle),
        transform = ctx.mat, windingRule = windingRule)
    if ctx.globalAlpha != Float32(1)
        applyOpacity(ctx.layer, ctx.globalAlpha)
        restore(ctx)
    end
    return nothing
end

"""
Fill `path` with the current fillStyle (upstream `fill`, L365-398): a clip
at the root goes through saveLayer/draw into the layer/restore (where the
clip applies); an active layer draws into it; otherwise the root image.
The style is converted at draw time, so a hex string assigned to
`ctx.fillStyle` works (except that it raises here, not at assignment).
"""
function fill(ctx::Context, path::Path, windingRule = NonZero)
    if ctx.mask !== nothing && ctx.layer === nothing
        saveLayer(ctx)
        fill(ctx, ctx.layer, path, windingRule)
        restore(ctx)
    elseif ctx.layer !== nothing
        fill(ctx, ctx.layer, path, windingRule)
    else
        fill(ctx, ctx.image, path, windingRule)
    end
    return nothing
end

"""Fill the current path (upstream `fill(ctx, windingRule)`)."""
function fill(ctx::Context, windingRule = NonZero)
    fill(ctx, ctx.path, windingRule)
    return nothing
end

"""
Stroke `path` into `image` with the current strokeWidth/cap/join/miterLimit/
lineDash (upstream private `stroke`, L157-177): the same globalAlpha
layering as private `fill`.
"""
function stroke(ctx::Context, image::Image, path::Path)
    img = image
    if ctx.globalAlpha != Float32(1)
        saveLayer(ctx)
        img = ctx.layer
    end
    strokePath(img, path, convert(Paint, ctx.strokeStyle),
        transform = ctx.mat, strokeWidth = ctx.lineWidth,
        lineCap = ctx.lineCap, lineJoin = ctx.lineJoin,
        miterLimit = ctx.miterLimit, dashes = ctx.lineDash)
    if ctx.globalAlpha != Float32(1)
        applyOpacity(ctx.layer, ctx.globalAlpha)
        restore(ctx)
    end
    return nothing
end

"""Stroke `path` (upstream `stroke`, L410-423): mask/layer routing as `fill`."""
function stroke(ctx::Context, path::Path)
    if ctx.mask !== nothing && ctx.layer === nothing
        saveLayer(ctx)
        stroke(ctx, ctx.layer, path)
        restore(ctx)
    elseif ctx.layer !== nothing
        stroke(ctx, ctx.layer, path)
    else
        stroke(ctx, ctx.image, path)
    end
    return nothing
end

"""Stroke the current path (upstream `stroke(ctx)`)."""
function stroke(ctx::Context)
    return stroke(ctx, ctx.path)
end

"""
Turn `path` into the current clipping region (upstream `clip`, L384-408):
the first clip allocates `ctx.mask` and fills the path with an opaque white
solid under OverwriteBlend; every later clip fills under MaskBlend, which
the rasterizer's clears-uncovered pass intersects with the previous region.
The fill uses the identity transform (as upstream -- the context matrix is
not applied).
"""
function clip(ctx::Context, path::Path, windingRule = NonZero)
    if ctx.mask === nothing
        ctx.mask = newImage(ctx.image.width, ctx.image.height)
        paint = Paint(rgba(0xff, 0xff, 0xff, 0xff); blendMode = OverwriteBlend)
        fillPath(ctx.mask, path, paint, windingRule = windingRule)
    else
        paint = Paint(rgba(0xff, 0xff, 0xff, 0xff); blendMode = MaskBlend)
        fillPath(ctx.mask, path, paint, windingRule = windingRule)
    end
    return nothing
end

"""Clip to the current path (upstream `clip(ctx, windingRule)`)."""
function clip(ctx::Context, windingRule = NonZero)
    clip(ctx, ctx.path, windingRule)
    return nothing
end

"""
Erase the rectangular area (upstream `clearRect`, L425-441): the
zero-alpha Overwrite paint over a fresh rect path, into the active layer
when there is one, else the root image.
"""
function clearRect(ctx::Context, r::Rect)
    paint = Paint(ColorRGBA(0x00, 0x00, 0x00, 0x00); blendMode = OverwriteBlend)
    p = newPath()
    rect(p, r)
    if ctx.layer !== nothing
        fillPath(ctx.layer, p, paint, transform = ctx.mat)
    else
        fillPath(ctx.image, p, paint, transform = ctx.mat)
    end
    return nothing
end

function clearRect(ctx::Context, x::Float32, y::Float32, w::Float32, h::Float32)
    clearRect(ctx, rect(x, y, w, h))
    return nothing
end
clearRect(ctx::Context, x::Real, y::Real, w::Real, h::Real) = # T014
    clearRect(ctx, rect(x, y, w, h))

"""Fill a rect per fillStyle (upstream `fillRect`): fresh path, rect, fill."""
function fillRect(ctx::Context, r::Rect)
    p = newPath()
    rect(p, r)
    fill(ctx, p)
    return nothing
end

function fillRect(ctx::Context, x::Float32, y::Float32, w::Float32, h::Float32)
    fillRect(ctx, rect(x, y, w, h))
    return nothing
end
fillRect(ctx::Context, x::Real, y::Real, w::Real, h::Real) = # T014
    fillRect(ctx, rect(x, y, w, h))

"""Stroke a rect per strokeStyle (upstream `strokeRect`)."""
function strokeRect(ctx::Context, r::Rect)
    p = newPath()
    rect(p, r)
    stroke(ctx, p)
    return nothing
end

function strokeRect(ctx::Context, x::Float32, y::Float32, w::Float32, h::Float32)
    strokeRect(ctx, rect(x, y, w, h))
    return nothing
end
strokeRect(ctx::Context, x::Real, y::Real, w::Real, h::Real) = # T014
    strokeRect(ctx, rect(x, y, w, h))

"""
Draw `image` into the destination rect `(dx, dy, dWidth, dHeight)` of the
context (upstream `drawImage`, contexts.nim L560-593): sets the fill style
to an ImagePaint whose matrix is `ctx.mat * translate(dx, dy) * scale
(dWidth / srcW, dHeight / srcH)` and fills a fresh rect path, restoring the
previous fill style afterwards.
"""
function drawImage(
    ctx::Context, image::Image,
    dx::Float32, dy::Float32, dWidth::Float32, dHeight::Float32
)
    imageMat = ctx.mat * translate(Vec2(dx, dy)) * scale(Vec2(
        dWidth / Float32(image.width), dHeight / Float32(image.height)))
    savedFillStyle = ctx.fillStyle
    ctx.fillStyle = Paint(image,
        imageMat = imageMat)
    p = newPath()
    rect(p, dx, dy, dWidth, dHeight)
    fill(ctx, p)
    ctx.fillStyle = savedFillStyle
    return nothing
end

function drawImage(ctx::Context, image::Image, dx::Float32, dy::Float32)
    drawImage(ctx, image, dx, dy, Float32(image.width), Float32(image.height))
    return nothing
end
drawImage(ctx::Context, image::Image, dx::Real, dy::Real) = # T014
    drawImage(ctx, image, Float32(dx), Float32(dy))
drawImage(ctx::Context, image::Image, dx::Real, dy::Real,
    dWidth::Real, dHeight::Real) = # T014
    drawImage(ctx, image, Float32(dx), Float32(dy), Float32(dWidth),
        Float32(dHeight))

function drawImage(ctx::Context, image::Image, pos::Vec2)
    drawImage(ctx, image, pos.x, pos.y)
    return nothing
end

function drawImage(ctx::Context, image::Image, r::Rect)
    drawImage(ctx, image, r.x, r.y, r.w, r.h)
    return nothing
end

"""
Draw the sub-rect `(sx, sy, sWidth, sHeight)` of `image` into
`(dx, dy, dWidth, dHeight)` (upstream `drawImage`, L595-611); coordinates
truncate to integers for the sub-image (upstream `.int` cast).
"""
function drawImage(
    ctx::Context, image::Image,
    sx::Float32, sy::Float32, sWidth::Float32, sHeight::Float32,
    dx::Float32, dy::Float32, dWidth::Float32, dHeight::Float32
)
    sub = subImage(image,
        Int(trunc(sx)), Int(trunc(sy)), Int(trunc(sWidth)), Int(trunc(sHeight)))
    drawImage(ctx, sub, dx, dy, Float32(sub.width), Float32(sub.height))
    return nothing
end
function drawImage(
    ctx::Context, image::Image,
    sx::Real, sy::Real, sWidth::Real, sHeight::Real,
    dx::Real, dy::Real, dWidth::Real, dHeight::Real
)
    drawImage(
        ctx, image,
        Float32(sx), Float32(sy), Float32(sWidth), Float32(sHeight),
        Float32(dx), Float32(dy), Float32(dWidth), Float32(dHeight))
    return nothing
end

function drawImage(ctx::Context, image::Image, src::Rect, dest::Rect)
    drawImage(
        ctx, image,
        src.x, src.y, src.w, src.h, dest.x, dest.y, dest.w, dest.h)
    return nothing
end

"""
Stroke a segment per the current stroke settings (upstream `strokeSegment`,
L709: moveTo + lineTo then stroke).
"""
function strokeSegment(ctx::Context, seg::Segment)
    p = newPath()
    moveTo(p, seg.at)
    lineTo(p, seg.to)
    stroke(ctx, p)
    return nothing
end

function strokeSegment(
    ctx::Context, ax::Float32, ay::Float32, bx::Float32, by::Float32
)
    strokeSegment(ctx, segment(Vec2(ax, ay), Vec2(bx, by)))
    return nothing
end
strokeSegment(ctx::Context, ax::Real, ay::Real, bx::Real, by::Real) = # T014
    strokeSegment(ctx, segment(Vec2(ax, ay), Vec2(bx, by)))

# ---------- text (T009; upstream contexts.nim L50-52, L179-259, L469-513) ----------

"""Upstream `TextMetrics` (only `width` is populated)."""
struct TextMetrics
    width::Float32
end

"""Upstream `newFont(ctx)`: load (and cache) the typeface for `ctx.font`,
then build a `Font` at `ctx.fontSize`. Raises if no font is set."""
function _ctxFont(ctx::Context)
    if ctx.font == ""
        throw(ArgumentError("No font has been set on this Context"))
    end
    if !haskey(ctx.typefaces, ctx.font)
        ctx.typefaces[ctx.font] = readTypeface(ctx.font)
    end
    font = newFont(ctx.typefaces[ctx.font])
    font.size = ctx.fontSize
    return font
end

function _ctxSetPaint(font::Font, paint::SomePaint)
    font.paints = [convert(Paint, paint)]
    return nothing
end

"""Upstream `fillText(ctx, image, text, at)` (baseline + globalAlpha
adjustments, then the image-level `fillText`)."""
function _ctxFillTextImage(ctx::Context, image::Image, text::String, at::Vec2)
    font = _ctxFont(ctx)
    # Canvas positions text relative to the alphabetic baseline by default.
    var_at = at
    if ctx.textBaseline === MiddleBaseline
        var_at = Vec2(at.x, at.y - Float32(roundHalfAway(
            (ascent(font.typeface) - descent(font.typeface)) /
            Float32(2) * scale(font))))
    elseif ctx.textBaseline === AlphabeticBaseline
        var_at = Vec2(at.x, at.y - Float32(roundHalfAway(
            ascent(font.typeface) * scale(font))))
    elseif ctx.textBaseline === IdeographicBaseline ||
        ctx.textBaseline === BottomBaseline
        var_at = Vec2(at.x, at.y - Float32(roundHalfAway(
            (ascent(font.typeface) - descent(font.typeface)) *
            scale(font))))
    end
    _ctxSetPaint(font, ctx.fillStyle)
    var_image = image
    if ctx.globalAlpha != Float32(1)
        saveLayer(ctx)
        var_image = ctx.layer
    end
    fillText(
        var_image, font, text,
        transform = ctx.mat * translate(var_at),
        hAlign = ctx.textAlign)
    if ctx.globalAlpha != Float32(1)
        applyOpacity(ctx.layer, ctx.globalAlpha)
        restore(ctx)
    end
    return nothing
end

"""Draw `text` at `at` with the current fillStyle (upstream `fillText`)."""
function fillText(ctx::Context, text::String, at::Vec2)
    if ctx.mask !== nothing && ctx.layer === nothing
        saveLayer(ctx)
        _ctxFillTextImage(ctx, ctx.layer, text, at)
        restore(ctx)
    elseif ctx.layer !== nothing
        _ctxFillTextImage(ctx, ctx.layer, text, at)
    else
        _ctxFillTextImage(ctx, ctx.image, text, at)
    end
    return nothing
end

"""Draw `text` at (x, y) with the current fillStyle."""
function fillText(ctx::Context, text::String, x::Float32, y::Float32)
    fillText(ctx, text, Vec2(x, y))
    return nothing
end
fillText(ctx::Context, text::String, x::Real, y::Real) = # T014
    fillText(ctx, text, Vec2(x, y))

"""Upstream `strokeText(ctx, image, text, at)` (alphabetic-baseline
adjustment, current stroke settings, then the image-level `strokeText`)."""
function _ctxStrokeTextImage(ctx::Context, image::Image, text::String,
    at::Vec2)
    font = _ctxFont(ctx)
    var_at = Vec2(at.x, at.y - Float32(roundHalfAway(
        ascent(font.typeface) * scale(font))))
    _ctxSetPaint(font, ctx.strokeStyle)
    var_image = image
    if ctx.globalAlpha != Float32(1)
        saveLayer(ctx)
        var_image = ctx.layer
    end
    strokeText(
        var_image, font, text,
        transform = ctx.mat * translate(var_at),
        strokeWidth = ctx.lineWidth, hAlign = ctx.textAlign,
        lineCap = ctx.lineCap, lineJoin = ctx.lineJoin,
        miterLimit = ctx.miterLimit, dashes = ctx.lineDash)
    if ctx.globalAlpha != Float32(1)
        applyOpacity(ctx.layer, ctx.globalAlpha)
        restore(ctx)
    end
    return nothing
end

"""Stroke `text` at `at` with the current strokeStyle (upstream
`strokeText`)."""
function strokeText(ctx::Context, text::String, at::Vec2)
    if ctx.mask !== nothing && ctx.layer === nothing
        saveLayer(ctx)
        _ctxStrokeTextImage(ctx, ctx.layer, text, at)
        restore(ctx)
    elseif ctx.layer !== nothing
        _ctxStrokeTextImage(ctx, ctx.layer, text, at)
    else
        _ctxStrokeTextImage(ctx, ctx.image, text, at)
    end
    return nothing
end

"""Stroke `text` at (x, y) with the current strokeStyle."""
function strokeText(ctx::Context, text::String, x::Float32, y::Float32)
    strokeText(ctx, text, Vec2(x, y))
    return nothing
end
strokeText(ctx::Context, text::String, x::Real, y::Real) = # T014
    strokeText(ctx, text, Vec2(x, y))

"""Upstream `measureText(ctx, text)`: the typeset width in pixels."""
function measureText(ctx::Context, text::String)
    font = _ctxFont(ctx)
    bounds = layoutBounds(typeset(font, text))
    return TextMetrics(bounds.x)
end

"""Upstream `setLineDash`."""
function setLineDash(ctx::Context, lineDash::Vector{Float32})
    ctx.lineDash = lineDash
    return nothing
end

"""Upstream `getLineDash`."""
getLineDash(ctx::Context) = ctx.lineDash
