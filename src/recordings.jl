# ---------- recording (T024; contract: docs/RECORDING.md, D030) ----------
#
# New capability (no upstream reference — D011 reserved the
# Picture/PictureRecorder seam). The display list records core-kernel
# invocations (fillPath/strokePath/clear/draw-image lowering + group ops),
# so CPU replay re-executes exactly the calls the immediate pipeline would
# have made: default-size replay is byte-identical to direct drawing by
# construction, and other sizes scale the logical canvas in vector space.
#
# Snapshot rules (record boundary): paths deep-copied, paints deep-copied
# (gradient arrays + image payload), stroke settings copied, per-op tform,
# cumulative clip lists shared by reference (clip paths are never mutated
# after recording), text lowered to glyph outline paths at record time.
# Recording is one-shot; the finished Picture owns its data.

# ---------- op records ----------

abstract type PicOp end

"""Cumulative clip entry: `clip` rasterizes with the identity transform in
image coordinates (first Overwrite-white, later MaskBlend-white)."""
struct PicClip
    path::Path
    windingRule::WindingRule
end

"""`fillPath(target, path, paint; transform = T * tform, windingRule)`."""
struct FillOp <: PicOp
    path::Path
    paint::Paint
    tform::Mat3
    windingRule::WindingRule
end

"""`strokePath(target, path, paint; transform = T * tform, ...settings)`
(solid paints only — record boundary)."""
struct StrokeOp <: PicOp
    path::Path
    paint::Paint
    tform::Mat3
    width::Float32
    cap::LineCap
    join::LineJoin
    miterLimit::Float32
    dashes::Vector{Float32}
end

"""clearRect lowering: zero-alpha Overwrite fill of `r` under `T * tform`
(no globalAlpha/clip wrapper — the raster clearRect has none either)."""
struct ClearOp <: PicOp
    r::Rect
    tform::Mat3
end

"""drawImage lowering: ImagePaint fill of the dest rect `r`; `imageMat` is
the picture-space matrix the Context computes (ctx.mat * translate *
scale). Replay applies the canvas mapping to both matrices."""
struct DrawImageOp <: PicOp
    image::Image
    imageMat::Mat3
    tform::Mat3
    r::Rect
end

"""Group scope (explicit saveLayer or the implicit wrappers the Context
routers add: clip-at-root and the globalAlpha != 1 layer). `opacity` is
applied to the scratch before compositing (the raster applyOpacity)."""
struct GroupStart <: PicOp
    opacity::Float32
end

"""Close a group: the ambient clip list at restore time is rasterized onto
the scratch (first Overwrite-white, rest MaskBlend-white), MaskBlended,
then the scratch is Normal-drawn onto the parent. Matches the raster
restore's poppedMask semantics exactly (clips leak to the outer group,
as in the immediate pipeline)."""
struct GroupEnd <: PicOp
    clips::Vector{PicClip}
end

# ---------- picture / recorder ----------

"""Immutable display list. Owns all snapshots; `size` is the logical
canvas (Int pixel components); `ops` is the kernel-call list in order."""
struct Picture
    ops::Vector{PicOp}
    size::Vec2
end

# ---------- recording context ----------

"""Saved recording state (mirror of `ContextState`, minus pixel buffers):
plain `save` stores layerDepth 0 (exits any open layer on restore, as the
raster's `state.layer = nothing` does); `saveLayer` stores the parent
depth. textBaseline is not saved (upstream quirk preserved)."""
struct RecState
    fillStyle::SomePaint
    strokeStyle::SomePaint
    globalAlpha::Float32
    lineWidth::Float32
    miterLimit::Float32
    lineCap::LineCap
    lineJoin::LineJoin
    mat::Mat3
    clips::Vector{PicClip}
    layerDepth::Int
    font::String
    fontSize::Float32
    textAlign::HorizontalAlignment
    lineDash::Vector{Float32}
end

"""
Drawing surface of a `PictureRecorder`: same state fields and method
signatures as `Context` (D011 coordinate conventions, T014 Real boundary
forms), but drawing appends snapshot ops instead of rasters. The current
path is state, as in `Context`.
"""
mutable struct RecordingContext
    size::Vec2
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
    clips::Vector{PicClip}
    layer::Int
    stateStack::Vector{RecState}
    typefaces::Dict{String,Typeface}
    ops::Vector{PicOp}
    finished::Bool
end

"""One-shot recording surface (D030): `recorder.ctx` is the
`RecordingContext`; `finishRecording` consumes it."""
mutable struct PictureRecorder
    ctx::RecordingContext
end

"""Recording context over a logical `width x height` canvas (defaults
mirror `Context(image)`)."""
function RecordingContext(width::Int, height::Int)
    return RecordingContext(
        Vec2(Float32(width), Float32(height)),
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
        PicClip[],
        0,
        RecState[],
        Dict{String,Typeface}(),
        PicOp[],
        false)
end

function PictureRecorder(width::Int, height::Int)
    return PictureRecorder(RecordingContext(width, height))
end

"""Consume the recorder: returns the Picture and blocks further drawing
(one-shot contract; drawing on a finished recorder raises ArgumentError).
Unclosed saveLayer groups are allowed: as in the immediate pipeline,
their content is never composited and the replay discards it."""
function finishRecording(r::PictureRecorder)
    r.ctx.finished && throw(ArgumentError("recorder already finished"))
    p = Picture(r.ctx.ops, r.ctx.size)
    r.ctx.finished = true
    return p
end

# ---------- internals ----------

"""Reject drawing on a finished recorder."""
function _recCheck(rctx::RecordingContext)
    rctx.finished && throw(ArgumentError("recorder already finished"))
    return nothing
end

"""Snapshot a SomePaint: convert at the record boundary (a bad color
string raises here, before any op is appended), deep-copy the paint, and
copy the referenced image so the Picture is self-contained."""
function _snapPaint(sp::SomePaint)
    p = copy(convert(Paint, sp))
    if p.image !== nothing
        p.image = copy(p.image)
    end
    return p
end

"""Record-boundary check for non-solid stroke styles (D030 §5): the raster
stroke contract is solid paints (a gradient strokeStyle silently no-ops
there via its zero color); recording makes that explicit instead of
recording a no-op."""
function _solidPaint(paint::Paint)
    paint.kind === SolidPaint ||
        throw(ArgumentError("strokeStyle must be a solid paint (recording)"))
    return paint
end

"""Begin a group scope (explicit saveLayer or an implicit Context wrapper)."""
_recBegin(rctx::RecordingContext, opacity::Float32) =
    push!(rctx.ops, GroupStart(opacity))

"""Close a group scope with the ambient clip list at restore time."""
_recEnd(rctx::RecordingContext) =
    push!(rctx.ops, GroupEnd(copy(rctx.clips)))

"""The Context routing wrappers around a draw call: an implicit clip group
when a clip is active at the root, then the globalAlpha layer — in the
raster's nesting order (implicit outer, alpha inner)."""
function _recWrap(rctx::RecordingContext, f)
    implicit = !isempty(rctx.clips) && rctx.layer == 0
    alpha = rctx.globalAlpha != Float32(1)
    implicit && _recBegin(rctx, Float32(1))
    alpha && _recBegin(rctx, rctx.globalAlpha)
    f()
    alpha && _recEnd(rctx)
    implicit && _recEnd(rctx)
    return nothing
end

"""Mirror of the Context `_ctxFont`: load (and cache) the typeface for
`rctx.font`, then build a `Font` at `rctx.fontSize`."""
function _recFont(rctx::RecordingContext)
    if rctx.font == ""
        throw(ArgumentError("No font has been set on this Context"))
    end
    if !haskey(rctx.typefaces, rctx.font)
        rctx.typefaces[rctx.font] = readTypeface(rctx.font)
    end
    font = newFont(rctx.typefaces[rctx.font])
    font.size = rctx.fontSize
    return font
end

# ---------- state ----------

function _recState(rctx::RecordingContext; layerDepth::Int = 0)
    return RecState(
        rctx.fillStyle, rctx.strokeStyle, rctx.globalAlpha,
        rctx.lineWidth, rctx.miterLimit, rctx.lineCap, rctx.lineJoin,
        rctx.mat,
        copy(rctx.clips),
        layerDepth,
        rctx.font, rctx.fontSize, rctx.textAlign, copy(rctx.lineDash))
end

"""Mirror of `Context.save` (snapshot pushed, then the solid paints are
re-copied in place; textBaseline not saved — upstream quirk)."""
function save(rctx::RecordingContext)
    _recCheck(rctx)
    push!(rctx.stateStack, _recState(rctx))
    if rctx.fillStyle isa Paint
        rctx.fillStyle = copy(rctx.fillStyle)
    end
    if rctx.strokeStyle isa Paint
        rctx.strokeStyle = copy(rctx.strokeStyle)
    end
    return nothing
end

"""Mirror of `Context.saveLayer`: push state (parent layer depth) and open
a group scope. `restore` closes it."""
function saveLayer(rctx::RecordingContext)
    _recCheck(rctx)
    push!(rctx.stateStack, _recState(rctx; layerDepth = rctx.layer))
    rctx.layer += 1
    _recBegin(rctx, Float32(1))
    return nothing
end

"""Mirror of `Context.restore`: close the group scope when one is open
(poppedLayer !== nothing), then restore the saved state — including
exiting the layer for plain-save states (layerDepth 0)."""
function restore(rctx::RecordingContext)
    _recCheck(rctx)
    isempty(rctx.stateStack) &&
        throw(ArgumentError("restore() with no saved state"))
    if rctx.layer > 0
        _recEnd(rctx)
    end
    state = pop!(rctx.stateStack)
    rctx.fillStyle = state.fillStyle
    rctx.strokeStyle = state.strokeStyle
    rctx.globalAlpha = state.globalAlpha
    rctx.lineWidth = state.lineWidth
    rctx.miterLimit = state.miterLimit
    rctx.lineCap = state.lineCap
    rctx.lineJoin = state.lineJoin
    rctx.font = state.font
    rctx.fontSize = state.fontSize
    rctx.textAlign = state.textAlign
    rctx.lineDash = state.lineDash
    rctx.mat = state.mat
    rctx.clips = state.clips
    rctx.layer = state.layerDepth
    return nothing
end

# ---------- transforms ----------

function transform(rctx::RecordingContext, m::Mat3)
    _recCheck(rctx)
    rctx.mat = rctx.mat * m
    return nothing
end

function translate(rctx::RecordingContext, v::Vec2)
    _recCheck(rctx)
    rctx.mat = rctx.mat * translate(v)
    return nothing
end
translate(rctx::RecordingContext, x::Float32, y::Float32) =
    translate(rctx, Vec2(x, y))
translate(rctx::RecordingContext, x::Real, y::Real) =
    translate(rctx, Vec2(x, y))

function scale(rctx::RecordingContext, v::Vec2)
    _recCheck(rctx)
    rctx.mat = rctx.mat * scale(v)
    return nothing
end
scale(rctx::RecordingContext, x::Float32, y::Float32) =
    scale(rctx, Vec2(x, y))
scale(rctx::RecordingContext, x::Real, y::Real) = scale(rctx, Vec2(x, y))

function rotate(rctx::RecordingContext, angle::Float32)
    _recCheck(rctx)
    rctx.mat = rctx.mat * rotate(angle)
    return nothing
end
rotate(rctx::RecordingContext, angle::Real) = rotate(rctx, Float32(angle))

"""`rctx.mat = m` (mirror of `Context.setTransform`)."""
function setTransform(rctx::RecordingContext, m::Mat3)
    _recCheck(rctx)
    rctx.mat = m
    return nothing
end

"""The current transform (mirror of `Context.getTransform`)."""
getTransform(rctx::RecordingContext) = rctx.mat

"""`rctx.mat = mat3()` (mirror of `Context.resetTransform`)."""
function resetTransform(rctx::RecordingContext)
    _recCheck(rctx)
    rctx.mat = mat3()
    return nothing
end

# ---------- path builders (delegate to the current path, as Context) ----------

function beginPath(rctx::RecordingContext)
    _recCheck(rctx)
    rctx.path = newPath()
    return nothing
end

function moveTo(rctx::RecordingContext, v::Vec2)
    _recCheck(rctx)
    moveTo(rctx.path, v)
    return nothing
end
moveTo(rctx::RecordingContext, x::Float32, y::Float32) =
    moveTo(rctx, Vec2(x, y))
moveTo(rctx::RecordingContext, x::Real, y::Real) = moveTo(rctx, Vec2(x, y))

function lineTo(rctx::RecordingContext, v::Vec2)
    _recCheck(rctx)
    lineTo(rctx.path, v)
    return nothing
end
lineTo(rctx::RecordingContext, x::Float32, y::Float32) =
    lineTo(rctx, Vec2(x, y))
lineTo(rctx::RecordingContext, x::Real, y::Real) = lineTo(rctx, Vec2(x, y))

function bezierCurveTo(rctx::RecordingContext, c1::Vec2, c2::Vec2, to::Vec2)
    _recCheck(rctx)
    bezierCurveTo(rctx.path, c1, c2, to)
    return nothing
end
function bezierCurveTo(
    rctx::RecordingContext, c1x::Float32, c1y::Float32, c2x::Float32,
    c2y::Float32, x::Float32, y::Float32
)
    return bezierCurveTo(rctx, Vec2(c1x, c1y), Vec2(c2x, c2y), Vec2(x, y))
end
bezierCurveTo(rctx::RecordingContext, c1x::Real, c1y::Real, c2x::Real,
    c2y::Real, x::Real, y::Real) =
        bezierCurveTo(rctx, Vec2(c1x, c1y), Vec2(c2x, c2y), Vec2(x, y))

function quadraticCurveTo(rctx::RecordingContext, c::Vec2, to::Vec2)
    _recCheck(rctx)
    quadraticCurveTo(rctx.path, c, to)
    return nothing
end
function quadraticCurveTo(
    rctx::RecordingContext, cpx::Float32, cpy::Float32, x::Float32, y::Float32
)
    return quadraticCurveTo(rctx, Vec2(cpx, cpy), Vec2(x, y))
end
quadraticCurveTo(rctx::RecordingContext, cpx::Real, cpy::Real,
    x::Real, y::Real) = quadraticCurveTo(rctx, Vec2(cpx, cpy), Vec2(x, y))

function arc(
    rctx::RecordingContext, x::Float32, y::Float32, r::Float32,
    a0::Float32, a1::Float32; ccw::Bool = false
)
    arc(rctx.path, x, y, r, a0, a1; ccw = ccw)
    return nothing
end
function arc(
    rctx::RecordingContext, x::Real, y::Real, r::Real, a0::Real, a1::Real;
    ccw::Bool = false
)
    arc(rctx.path, x, y, r, a0, a1; ccw = ccw)
    return nothing
end
function arc(rctx::RecordingContext, pos::Vec2, r::Float32, a::Vec2;
    ccw::Bool = false)
    arc(rctx.path, pos, r, a; ccw = ccw)
    return nothing
end

function arcTo(
    rctx::RecordingContext, x1::Float32, y1::Float32, x2::Float32,
    y2::Float32, radius::Float32
)
    arcTo(rctx.path, x1, y1, x2, y2, radius)
    return nothing
end
function arcTo(
    rctx::RecordingContext, x1::Real, y1::Real, x2::Real, y2::Real,
    radius::Real
)
    arcTo(rctx.path, x1, y1, x2, y2, radius)
    return nothing
end
function arcTo(rctx::RecordingContext, a::Vec2, b::Vec2, r::Float32)
    arcTo(rctx.path, a, b, r)
    return nothing
end

function closePath(rctx::RecordingContext)
    _recCheck(rctx)
    closePath(rctx.path)
    return nothing
end

function rect(rctx::RecordingContext, r::Rect)
    _recCheck(rctx)
    rect(rctx.path, r)
    return nothing
end
function rect(rctx::RecordingContext, x::Float32, y::Float32, w::Float32,
    h::Float32)
    rect(rctx.path, x, y, w, h)
    return nothing
end
function rect(rctx::RecordingContext, x::Real, y::Real, w::Real, h::Real)
    rect(rctx.path, x, y, w, h)
    return nothing
end

function ellipse(rctx::RecordingContext, c::Vec2, rx::Float32, ry::Float32)
    _recCheck(rctx)
    ellipse(rctx.path, c, rx, ry)
    return nothing
end
function ellipse(rctx::RecordingContext, x::Float32, y::Float32, rx::Float32,
    ry::Float32)
    ellipse(rctx.path, x, y, rx, ry)
    return nothing
end
function ellipse(rctx::RecordingContext, x::Real, y::Real, rx::Real,
    ry::Real)
    ellipse(rctx.path, x, y, rx, ry)
    return nothing
end

function roundedRect(
    rctx::RecordingContext, x::Float32, y::Float32, w::Float32, h::Float32,
    nw::Float32, ne::Float32, se::Float32, sw::Float32
)
    roundedRect(rctx.path, x, y, w, h, nw, ne, se, sw)
    return nothing
end
function roundedRect(
    rctx::RecordingContext, r::Rect, nw::Float32, ne::Float32, se::Float32,
    sw::Float32
)
    roundedRect(rctx.path, r, nw, ne, se, sw)
    return nothing
end
function roundedRect(
    rctx::RecordingContext, x::Real, y::Real, w::Real, h::Real, nw::Real,
    ne::Real, se::Real, sw::Real
)
    roundedRect(rctx.path, x, y, w, h, nw, ne, se, sw)
    return nothing
end

function circle(rctx::RecordingContext, cx::Float32, cy::Float32,
    r::Float32)
    circle(rctx.path, cx, cy, r)
    return nothing
end
function circle(rctx::RecordingContext, cx::Real, cy::Real, r::Real)
    circle(rctx.path, cx, cy, r)
    return nothing
end
function circle(rctx::RecordingContext, c::Circle)
    circle(rctx.path, c)
    return nothing
end

function polygon(rctx::RecordingContext, x::Float32, y::Float32,
    size::Float32, sides::Int)
    polygon(rctx.path, x, y, size, sides)
    return nothing
end
function polygon(rctx::RecordingContext, x::Real, y::Real, size::Real,
    sides::Int)
    polygon(rctx.path, x, y, size, sides)
    return nothing
end
function polygon(rctx::RecordingContext, pos::Vec2, size::Float32,
    sides::Int)
    polygon(rctx.path, pos, size, sides)
    return nothing
end

# ---------- drawing ----------

"""
Fill `path` with the current fillStyle (D030 §1/§5): snapshot the paint and
record a FillOp under the Context routing wrappers (implicit clip group
at the root, globalAlpha layer). TiledImagePaint fills are not recordable
(bounded vector model) and raise at the record boundary.
"""
function fill(rctx::RecordingContext, path::Path, windingRule = NonZero)
    _recCheck(rctx)
    paint = _snapPaint(rctx.fillStyle)
    if paint.kind === TiledImagePaint
        throw(ArgumentError(
            "TiledImagePaint fills are not recordable (recording)"))
    end
    tform = rctx.mat
    # (explicit function literal: this build mis-parses do-block syntax)
    _recWrap(rctx, function()
        push!(rctx.ops, FillOp(copy(path), paint, tform, windingRule))
        return nothing
    end)
    return nothing
end

fill(rctx::RecordingContext, windingRule = NonZero) =
    fill(rctx, rctx.path, windingRule)

"""Stroke `path` with the current stroke settings (solid strokeStyle only)."""
function stroke(rctx::RecordingContext, path::Path)
    _recCheck(rctx)
    paint = _solidPaint(_snapPaint(rctx.strokeStyle))
    tform = rctx.mat
    _recWrap(rctx, function()
        push!(rctx.ops, StrokeOp(
            copy(path), paint, tform, rctx.lineWidth, rctx.lineCap,
            rctx.lineJoin, rctx.miterLimit, copy(rctx.lineDash)))
        return nothing
    end)
    return nothing
end

stroke(rctx::RecordingContext) = stroke(rctx, rctx.path)

"""Fill a rect per fillStyle (mirror of Context.fillRect)."""
function fillRect(rctx::RecordingContext, r::Rect)
    fill(rctx, _rectPath(r))
    return nothing
end
function fillRect(rctx::RecordingContext, x::Float32, y::Float32,
    w::Float32, h::Float32)
    fillRect(rctx, rect(x, y, w, h))
    return nothing
end
function fillRect(rctx::RecordingContext, x::Real, y::Real, w::Real,
    h::Real)
    fillRect(rctx, rect(x, y, w, h))
    return nothing
end

"""Stroke a rect per stroke settings (mirror of Context.strokeRect)."""
function strokeRect(rctx::RecordingContext, r::Rect)
    stroke(rctx, _rectPath(r))
    return nothing
end
function strokeRect(rctx::RecordingContext, x::Float32, y::Float32,
    w::Float32, h::Float32)
    strokeRect(rctx, rect(x, y, w, h))
    return nothing
end
function strokeRect(rctx::RecordingContext, x::Real, y::Real, w::Real,
    h::Real)
    strokeRect(rctx, rect(x, y, w, h))
    return nothing
end

function strokeSegment(rctx::RecordingContext, seg::Segment)
    p = newPath()
    moveTo(p, seg.at)
    lineTo(p, seg.to)
    stroke(rctx, p)
    return nothing
end
function strokeSegment(
    rctx::RecordingContext, ax::Float32, ay::Float32, bx::Float32, by::Float32
)
    strokeSegment(rctx, segment(Vec2(ax, ay), Vec2(bx, by)))
    return nothing
end
function strokeSegment(rctx::RecordingContext, ax::Real, ay::Real, bx::Real,
    by::Real)
    strokeSegment(rctx, segment(Vec2(ax, ay), Vec2(bx, by)))
    return nothing
end

"""Erase the rect (mirror of Context.clearRect — no clip/globalAlpha
wrappers, as in the raster)."""
function clearRect(rctx::RecordingContext, r::Rect)
    _recCheck(rctx)
    push!(rctx.ops, ClearOp(r, rctx.mat))
    return nothing
end
function clearRect(rctx::RecordingContext, x::Float32, y::Float32,
    w::Float32, h::Float32)
    clearRect(rctx, rect(x, y, w, h))
    return nothing
end
function clearRect(rctx::RecordingContext, x::Real, y::Real, w::Real,
    h::Real)
    clearRect(rctx, rect(x, y, w, h))
    return nothing
end

"""Intersect the cumulative clip with `path` (image coordinates, identity
rasterization — mirror of Context.clip)."""
function clip(rctx::RecordingContext, path::Path, windingRule = NonZero)
    _recCheck(rctx)
    push!(rctx.clips, PicClip(copy(path), windingRule))
    return nothing
end
clip(rctx::RecordingContext, windingRule = NonZero) =
    clip(rctx, rctx.path, windingRule)

"""Draw `image` into the dest rect (mirror of Context.drawImage: the
ImagePaint fill lowering with the same imageMat computation)."""
function drawImage(
    rctx::RecordingContext, image::Image,
    dx::Float32, dy::Float32, dWidth::Float32, dHeight::Float32
)
    _recCheck(rctx)
    imageMat = rctx.mat * translate(Vec2(dx, dy)) * scale(Vec2(
        dWidth / Float32(image.width), dHeight / Float32(image.height)))
    img = copy(image)
    r = Rect(dx, dy, dWidth, dHeight)
    tform = rctx.mat
    _recWrap(rctx, function()
        push!(rctx.ops, DrawImageOp(img, imageMat, tform, r))
        return nothing
    end)
    return nothing
end

function drawImage(rctx::RecordingContext, image::Image, dx::Float32,
    dy::Float32)
    drawImage(rctx, image, dx, dy, Float32(image.width), Float32(image.height))
    return nothing
end
drawImage(rctx::RecordingContext, image::Image, dx::Real, dy::Real) =
    drawImage(rctx, image, Float32(dx), Float32(dy))
drawImage(rctx::RecordingContext, image::Image, dx::Real, dy::Real,
    dWidth::Real, dHeight::Real) =
        drawImage(rctx, image, Float32(dx), Float32(dy),
            Float32(dWidth), Float32(dHeight))

function drawImage(rctx::RecordingContext, image::Image, pos::Vec2)
    drawImage(rctx, image, pos.x, pos.y)
    return nothing
end

function drawImage(rctx::RecordingContext, image::Image, r::Rect)
    drawImage(rctx, image, r.x, r.y, r.w, r.h)
    return nothing
end

"""Draw the sub-rect of `image` into the dest rect (mirror of
Context.drawImage: integer-truncated subImage, then the 5-arg form)."""
function drawImage(
    rctx::RecordingContext, image::Image,
    sx::Float32, sy::Float32, sWidth::Float32, sHeight::Float32,
    dx::Float32, dy::Float32, dWidth::Float32, dHeight::Float32
)
    sub = subImage(image,
        Int(trunc(sx)), Int(trunc(sy)), Int(trunc(sWidth)), Int(trunc(sHeight)))
    drawImage(rctx, sub, dx, dy, Float32(sub.width), Float32(sub.height))
    return nothing
end
function drawImage(
    rctx::RecordingContext, image::Image,
    sx::Real, sy::Real, sWidth::Real, sHeight::Real,
    dx::Real, dy::Real, dWidth::Real, dHeight::Real
)
    drawImage(
        rctx, image,
        Float32(sx), Float32(sy), Float32(sWidth), Float32(sHeight),
        Float32(dx), Float32(dy), Float32(dWidth), Float32(dHeight))
    return nothing
end

function drawImage(rctx::RecordingContext, image::Image, src::Rect,
    dest::Rect)
    drawImage(
        rctx, image,
        src.x, src.y, src.w, src.h, dest.x, dest.y, dest.w, dest.h)
    return nothing
end

# ---------- text (D030 §3: lowered to outline paths at record time) ----------

"""Fill `text` at `at` with the current fillStyle (mirror of
Context.fillText: baseline adjustment, globalAlpha wrapper, per-span
outline FillOps with tform = mat * translate(var_at))."""
function fillText(rctx::RecordingContext, text::String, at::Vec2)
    _recCheck(rctx)
    font = _recFont(rctx)
    var_at = at
    if rctx.textBaseline === MiddleBaseline
        var_at = Vec2(at.x, at.y - Float32(roundHalfAway(
            (ascent(font.typeface) - descent(font.typeface)) /
            Float32(2) * scale(font))))
    elseif rctx.textBaseline === AlphabeticBaseline
        var_at = Vec2(at.x, at.y - Float32(roundHalfAway(
            ascent(font.typeface) * scale(font))))
    elseif rctx.textBaseline === IdeographicBaseline ||
        rctx.textBaseline === BottomBaseline
        var_at = Vec2(at.x, at.y - Float32(roundHalfAway(
            (ascent(font.typeface) - descent(font.typeface)) *
            scale(font))))
    end
    paint = _snapPaint(rctx.fillStyle)
    tform = rctx.mat * translate(var_at)
    arr = typeset(font, text; hAlign = rctx.textAlign)
    spanPaths = computePaths(arr)
    _recWrap(rctx, function()
        for spanPath in spanPaths
            push!(rctx.ops,
                FillOp(copy(spanPath), copy(paint), tform, NonZero))
        end
        return nothing
    end)
    return nothing
end

function fillText(rctx::RecordingContext, text::String, x::Float32,
    y::Float32)
    fillText(rctx, text, Vec2(x, y))
    return nothing
end
fillText(rctx::RecordingContext, text::String, x::Real, y::Real) =
    fillText(rctx, text, Vec2(x, y))

"""Stroke `text` at `at` with the current strokeStyle (mirror of
Context.strokeText: the fixed ascent adjustment, globalAlpha wrapper,
per-span outline StrokeOps with the context stroke settings)."""
function strokeText(rctx::RecordingContext, text::String, at::Vec2)
    _recCheck(rctx)
    font = _recFont(rctx)
    var_at = Vec2(at.x, at.y - Float32(roundHalfAway(
        ascent(font.typeface) * scale(font))))
    paint = _solidPaint(_snapPaint(rctx.strokeStyle))
    tform = rctx.mat * translate(var_at)
    arr = typeset(font, text; hAlign = rctx.textAlign)
    spanPaths = computePaths(arr)
    _recWrap(rctx, function()
        for spanPath in spanPaths
            push!(rctx.ops, StrokeOp(
                copy(spanPath), paint, tform, rctx.lineWidth,
                rctx.lineCap, rctx.lineJoin, rctx.miterLimit,
                copy(rctx.lineDash)))
        end
        return nothing
    end)
    return nothing
end

function strokeText(rctx::RecordingContext, text::String, x::Float32,
    y::Float32)
    strokeText(rctx, text, Vec2(x, y))
    return nothing
end
strokeText(rctx::RecordingContext, text::String, x::Real, y::Real) =
    strokeText(rctx, text, Vec2(x, y))

"""The typeset width in pixels (mirror of Context.measureText; records
nothing)."""
function measureText(rctx::RecordingContext, text::String)
    _recCheck(rctx)
    font = _recFont(rctx)
    bounds = layoutBounds(typeset(font, text))
    return TextMetrics(bounds.x)
end

"""Mirror of Context.setLineDash."""
function setLineDash(rctx::RecordingContext, lineDash::Vector{Float32})
    _recCheck(rctx)
    rctx.lineDash = lineDash
    return nothing
end

"""Mirror of Context.getLineDash."""
getLineDash(rctx::RecordingContext) = rctx.lineDash

# ---------- replay (CPU) ----------

"""
Replay `picture` into `image` (D030 §4): the logical canvas is scaled by
(imgW/picW, imgH/picH) in vector space, `tform` composes in picture space,
and the kernel list is re-executed — default size + identity tform
re-executes exactly the calls the immediate pipeline would have made.
Unclosed group scopes are discarded (their content was never composited,
as in the immediate pipeline).
"""
function drawPicture(image::Image, picture::Picture; tform::Mat3 = mat3())
    sx = Float32(image.width) / Float32(picture.size.x)
    sy = Float32(image.height) / Float32(picture.size.y)
    canvas = scale(Vec2(sx, sy)) * tform
    stack = Image[image]
    groupOpacity = Float32[Float32(1)]
    for op in picture.ops
        if op isa FillOp
            fillPath(stack[end], op.path, op.paint,
                transform = canvas * op.tform, windingRule = op.windingRule)
        elseif op isa StrokeOp
            strokePath(stack[end], op.path, op.paint,
                transform = canvas * op.tform, strokeWidth = op.width,
                lineCap = op.cap, lineJoin = op.join, miterLimit =
                op.miterLimit, dashes = op.dashes)
        elseif op isa ClearOp
            p = newPath()
            rect(p, op.r)
            fillPath(stack[end], p,
                Paint(ColorRGBA(0x00, 0x00, 0x00, 0x00);
                    blendMode = OverwriteBlend),
                transform = canvas * op.tform)
        elseif op isa DrawImageOp
            p = newPath()
            rect(p, op.r)
            fillPath(stack[end], p,
                Paint(op.image, imageMat = canvas * op.imageMat),
                transform = canvas * op.tform)
        elseif op isa GroupStart
            push!(stack, newImage(image.width, image.height))
            push!(groupOpacity, op.opacity)
        else # GroupEnd
            scratch = pop!(stack)
            opa = pop!(groupOpacity)
            if opa != Float32(1)
                applyOpacity(scratch, opa)
            end
            if !isempty(op.clips)
                mask = newImage(scratch.width, scratch.height)
                for (i, c) in enumerate(op.clips)
                    paint = i == 1 ?
                        Paint(rgba(0xff, 0xff, 0xff, 0xff);
                            blendMode = OverwriteBlend) :
                        Paint(rgba(0xff, 0xff, 0xff, 0xff);
                            blendMode = MaskBlend)
                    fillPath(mask, c.path, paint,
                        transform = canvas, windingRule = c.windingRule)
                end
                draw(scratch, mask; blendMode = MaskBlend)
            end
            draw(stack[end], scratch)
        end
    end
    return nothing
end

_rectPath(r::Rect) = (p = newPath(); rect(p, r); p)
