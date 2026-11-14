# ============================================================================
# R010 revision 9 — small contract-boundary check
#
# Evidence level (per the revision-4 scope correction, kept): this file
# proves ONLY arithmetic / record / dispatch boundaries. It imports the
# ACTUAL Vetra primitives (colors, Mat3/Vec2/Rect/Path, Paint/PaintKind,
# Image, the pinned rgbx/toStraightAlpha/blend* kernels, BlendMode values,
# the actual legacy PictureRecorder/Picture/drawPicture for the 1×1
# wrapper counterexamples) — no re-implemented graphics engine.
#
# It deliberately does NOT contain, and must not grow into:
#   - a Canvas frontend or drawing/recording engine
#   - text metrics or layout, hit tests, effect execution
#   - picture replay, raster-fallback execution
#   - a browser runtime, an array engine, PDF/SVG publication
#   - eval-generated providers (ordinary modules only)
# Runtime acceptance for those behaviors is PENDING their roadmap tasks
# (R020/R021/R022/R023, R013, R050–R054, R061–R063) and is tracked in the
# normative contract's §19 scenario register — none of it is closed here.
#
# What it executes (each row below corresponds to a "✓" cell in §19):
#   G1  protocol dispatch + the §8.1 (revision 9) single completion
#       route over core-owned tracked frontend handles: direct
#       wait(handle) and wait(c) share one completion step;
#       completed-handle retirement incl. the 16-frame root drain and
#       provider-root release verified by the ACTUAL batch reference
#       (a completed handle — provider-tracked or externally kept —
#       holds no batch); STICKY provider failure (batch retained) and
#       STICKY staged failure with the ORIGINAL named error by
#       identity (TransferError :partial/:unwritten, action
#       BackendSubmitError, AND the §7 phase-1 named validation
#       ArgumentError — zero stores, same error on wait/wait-all/
#       close, action once, core staging retained, provider already
#       released; success flag only after success); inert core no-op
#   G3  W3C compositing reference incl. vector nonseparable modes, the
#       separable endpoint order and the artistic-before-additive anchor
#   G5  §14 placement under the actual Vetra Mat3 (point transforms,
#       rejected v4 order as control) + the owned CanvasRecording
#       machine (revision 7: seal boundary — already-owned ops, asset-
#       byte deep copies, container ownership, balance, uncaptured
#       reference rejection in both id classes; the one 1:1 remap;
#       mapping/clip arithmetics) + the disjoint conservative legacy-
#       lowering DECISION PROCEDURE (revision 8: + zero-opacity Copy
#       rejection) + the actual-recorder 1×1 wrapper counterexamples
#       (clipped Copy, clipped Multiply, zero-opacity Copy) and their
#       unclipped preserving controls
#   §5.7 the exact-rational hue anchor (independent of kernel output)
#   G8  compositing/array anchors: coverage/atop/lighter/matte/quant/
#       pinned kernels + transparent gray (composite first, then luma)
#   G9  browser readback identity vs the SAVED request (§11), payload
#       checks before consumption
#   G10 browser document namespace + captured-id insertion (revision 7:
#       the machine never invents ids; initial.id preserved on
#       construction AND destructive resize; the next-capture counter
#       is separate already-reserved state; resize continues the
#       namespace) + canonical UTF-8 byte accounting + upload dispatch
#       identity + the §7 ordered upload route (tracked frontend
#       handle) + execution-ack identity + resize
#   G11 pixel layout / scan / conversion table (§7 single table;
#       revision 7: raw-route positional axes THROUGH axes(M) —
#       zero-based raw matrices in both scan orientations — top-level
#       transpose peel, the channel-packed raw vec scramble pin)
#   G12 upload pre-dispatch validation + the §7 commit rule (two-phase,
#       :partial unless atomic) + idempotent opaque staging + the
#       staged-upload negative control (inert no-op flush does not
#       complete the upload; the tracked handle does, once)
#   G13 storage-adapter provider surface (zero-based regions, explicit
#       alloc) + the normative consumer trace (record machine)
#   G14 one input-size invariant across all constructors (array + adapter
#       routes) + promotion-before-multiplication physical rounding
#       (revision 6: inverse-DPI promotion-before-division pin)
#   G15 concrete wire records: tags + fields + paint-kind mapping +
#       canonical serialization fixtures (§11; revision 7: Float32
#       numeric policy incl. the image-opacity 0.1f0 ⇒ 0.1 pin — the
#       revision-6 one-field widening is gone — fractional image
#       srcRect / effect regions)
# ============================================================================

using Test
using Base64
import Vetra
import LinearAlgebra

# ===========================================================================
# 1. Contract records — exact types from doc §2 / §6 / §11
# ===========================================================================

# --- §2 composition operators (frozen order) ---
struct CompositionOperator
    value::Int
end
const SourceOver = CompositionOperator(0)
const SourceIn   = CompositionOperator(1)
const SourceOut  = CompositionOperator(2)
const SourceAtop = CompositionOperator(3)
const Over       = CompositionOperator(4)
const In         = CompositionOperator(5)
const Out        = CompositionOperator(6)
const Atop       = CompositionOperator(7)
const Xor        = CompositionOperator(8)
const Copy       = CompositionOperator(9)
const Lighter    = CompositionOperator(10)

# --- §2 capability records ---
struct CapabilityLevel
    value::Int
end
const NativeCapability      = CapabilityLevel(0)
const LoweredCapability     = CapabilityLevel(1)
const FallbackCapability    = CapabilityLevel(2)
const UnsupportedCapability = CapabilityLevel(3)

struct CapabilityStatus
    level::CapabilityLevel
    note::String
end

struct BackendCapabilities
    protocol::Int
    provider::String
    pixel_profile::String
    features::Dict{String, CapabilityStatus}
    limits::Dict{String, Int}
end

# --- §2 errors (frozen field sets) ---
struct CanvasClosedError <: Exception
    op::Symbol
end
struct BackendCapabilityError <: Exception
    feature::String
    op::Symbol
end
struct BackendSubmitError <: Exception
    detail::String
end
struct SnapshotError <: Exception
    kind::Symbol
    detail::String
end
struct TransferError <: Exception
    status::Symbol
    detail::String
end

# --- §6 / §2 core records ---
struct ClipScope
    path::Vetra.Path
    winding::Vetra.WindingRule
end

struct ImageSampling
    filter::Symbol   # :nearest | :linear
    edge::Symbol     # :clamp | :repeat
end
const NearestSampling = ImageSampling(:nearest, :clamp)
const LinearSampling  = ImageSampling(:linear, :clamp)

struct CanvasAsset
    id::Int
    width::Int
    height::Int
    data::Vector{UInt8}   # premultiplied RGBA8, row-major, top-down; owned
end

struct GlyphPath
    outline::Vetra.Path
    tform::Vetra.Mat3
end

struct OwnedPaint
    kind::Vetra.PaintKind
    color::Vetra.ColorRGBA       # solid (straight alpha)
    opacity::Float32
    artistic::Vetra.BlendMode    # NormalBlend = none
    imageAssetId::Int
    imageMat::Vetra.Mat3
    gradientHandles::Vector{Vetra.Vec2}
    gradientStops::Vector{Vetra.ColorStop}
end

abstract type CanvasOp end

struct FillOp <: CanvasOp
    path::Vetra.Path
    paint::OwnedPaint
    tform::Vetra.Mat3
    winding::Vetra.WindingRule
    clips::Vector{ClipScope}
    composition::CompositionOperator
end
struct StrokeOp <: CanvasOp
    path::Vetra.Path
    paint::OwnedPaint
    tform::Vetra.Mat3
    width::Float32
    cap::Vetra.LineCap
    join::Vetra.LineJoin
    miterLimit::Float32
    dashes::Vector{Float32}
    dashOffset::Float32
    clips::Vector{ClipScope}
    composition::CompositionOperator
end
struct ClearOp <: CanvasOp
    r::Vetra.Rect
    tform::Vetra.Mat3
    clips::Vector{ClipScope}
end
struct DrawImageOp <: CanvasOp
    assetId::Int
    srcRect::Vetra.Rect
    destRect::Vetra.Rect
    tform::Vetra.Mat3
    sampling::ImageSampling
    composition::CompositionOperator
    opacity::Float32
    clips::Vector{ClipScope}
end
struct TextOp <: CanvasOp
    glyphs::Vector{GlyphPath}
    paint::OwnedPaint
    tform::Vetra.Mat3
    composition::CompositionOperator
    clips::Vector{ClipScope}
end
struct EffectOp <: CanvasOp
    kind::Symbol
    radius::Float32
    offset::Vetra.Vec2
    color::Vetra.ColorRGB
    opacity::Float32
    inRegion::Vetra.Rect
    outRegion::Vetra.Rect
    tform::Vetra.Mat3
    clips::Vector{ClipScope}
end
struct GroupStartOp <: CanvasOp
    opacity::Float32
    composition::CompositionOperator
    clips::Vector{ClipScope}
end
struct GroupEndOp <: CanvasOp
    clips::Vector{ClipScope}
end

# §6 raster fallback retains the original work (revision 4)
struct FallbackWork
    ops::Vector{CanvasOp}
    assets::Dict{Int, CanvasAsset}
end
struct RasterFallbackOp <: CanvasOp
    feature::String
    reason::String
    scope::Symbol
    original::FallbackWork
    clips::Vector{ClipScope}
end

struct CommandBatch
    ops::Vector{CanvasOp}
    assets::Dict{Int, CanvasAsset}
    size::Vetra.Vec2
    device_scale::Float32
end

# §8 frozen core batch accessors (R020 owns storage freedom)
batch_ops(b::CommandBatch) = b.ops
batch_assets(b::CommandBatch) = b.assets
batch_asset(b::CommandBatch, id::Int) = b.assets[id]
batch_size(b::CommandBatch) = b.size
batch_device_scale(b::CommandBatch) = b.device_scale

# §2 / §10 records
struct CanvasTargetSpec
    logical_width::Int
    logical_height::Int
    device_scale::Float32
    physical_width::Int
    physical_height::Int
    initial::Union{CanvasAsset, Nothing}
end
struct StorageReport
    mode::Symbol
    layout::Symbol
    copied::Bool
end
struct FallbackReport
    op_index::Int
    feature::String
    reason::String
    scope::Symbol
end
struct DrawBounds
    rect::Vetra.Rect
    conservative::Bool
    unknown::Bool
end

# §8 protocol markers + core no-op submission
abstract type CanvasBackend end
abstract type CanvasSubmission end
struct CanvasNoopSubmission <: CanvasSubmission end
# §8.1 (revision 7): the core no-op handle is INERT — wait returns
# immediately, touches no provider, applies no staged action,
# transitions no state; it is never tracked
wait(::CanvasNoopSubmission) = nothing

# --- §8 / §13 core generics (providers implement on their own types) ---
function backend_capabilities(b::CanvasBackend)
    error("backend_capabilities not implemented by provider")
end
function bind_target!(b::CanvasBackend, spec::CanvasTargetSpec)
    error("bind_target! not implemented by provider")
end
function submit!(b::CanvasBackend, batch::CommandBatch)
    error("submit! not implemented by provider")
end
function wait(sub::CanvasSubmission)
    error("wait not implemented by provider")
end
function close(b::CanvasBackend)
    error("close not implemented by provider")
end
# §8 optional capability "pixel-upload": the dispatch carries the captured
# asset (id, physical dims, owned premul RGBA8 bytes) + the zero-based
# physical region — the id survives to the wire `set-pixels` record (§11)
function upload_pixels!(b::CanvasBackend, asset::CanvasAsset, region::Vetra.Rect)
    error("upload_pixels! not implemented by provider")
end

# §13 storage adapter record + core generics
struct PixelLayout
    width::Int
    height::Int
    channels::Int
    alpha::Bool
    premultiplied::Bool
    row_major::Bool
end
struct StorageDescriptor
    element::DataType
    layout::PixelLayout
    writable::Bool
    axes_ordered::Bool
end
abstract type StorageAdapter end
function storage_descriptor(s::StorageAdapter)
    error("storage_descriptor not implemented by provider")
end
function storage_read(s::StorageAdapter, region::Vetra.Rect)
    error("storage_read not implemented by provider")
end
function storage_write!(s::StorageAdapter, region::Vetra.Rect, data::Vector{UInt8})
    error("storage_write! not implemented by provider")
end
# explicit type AND target dimensions — a descriptor cannot infer the
# container shape (doc §13 allocation rule)
function storage_alloc(prototype::StorageAdapter, ::Type{T},
                       dims::Tuple{Int, Int}) where {T<:StorageAdapter}
    error("storage_alloc not implemented by provider")
end

# ===========================================================================
# 2. Narrow size / DPI helpers — doc §4 rule 1 + §10
# ===========================================================================

"""§10: logical → physical extents, checked rounding, ties away."""
function physical_extents(w::Int, h::Int, scale::Float32)::Tuple{Int,Int}
    (isfinite(scale) && scale > 0) ||
        throw(ArgumentError("device_scale must be finite and > 0"))
    pw_f = Float64(w) * Float64(scale)
    ph_f = Float64(h) * Float64(scale)
    (pw_f > typemax(Int) || ph_f > typemax(Int)) &&
        throw(ArgumentError("physical extents overflow Int"))
    return (max(1, Int(round(pw_f, RoundNearestTiesAway))),
            max(1, Int(round(ph_f, RoundNearestTiesAway))))
end

"""§4 rule 1 (revision 4): the ONE input-size invariant for every
array/raw/adapter constructor. Supplied pixels are the target's PHYSICAL
pixels; the logical size must divide them EXACTLY (no rounding) — a
non-integral logical size is rejected before binding. Float64 is
authoritative: the Float32 scale value, not a rational guess."""
function constructor_logical(pw::Int, ph::Int, scale::Float32)::Tuple{Int,Int}
    scale == 1f0 && return (pw, ph)
    lw_f = Float64(pw) / Float64(scale)
    lh_f = Float64(ph) / Float64(scale)
    (lw_f >= 1 && lw_f == floor(lw_f) && lh_f >= 1 && lh_f == floor(lh_f)) ||
        throw(ArgumentError(
            "import dimensions are physical; $pw×$ph at device_scale $scale " *
            "has no exact integral logical size"))
    return (Int(lw_f), Int(lh_f))
end

"""§4 rule 1: `spec.initial` is validated against the PHYSICAL extents."""
function validate_initial(initial::CanvasAsset, pw::Int, ph::Int)::Nothing
    (initial.width, initial.height) == (pw, ph) ||
        throw(ArgumentError(
            "initial asset is $(initial.width)×$(initial.height), physical " *
            "target is $pw×$ph"))
    length(initial.data) == 4 * pw * ph ||
        throw(ArgumentError(
            "initial asset has $(length(initial.data)) bytes, expected " *
            "$(4 * pw * ph) for $pw×$ph"))
    return nothing
end

# ===========================================================================
# 3. Pixel layout / conversion table — doc §7 (single logical indexing)
# ===========================================================================

# §7 frozen byte formulas (cross-checked against the actual pinned kernels
# in the anchors below)
premul_byte(c::Integer, a::Integer) = UInt8((Int(c) * Int(a) + 127) ÷ 255)
function straight_byte(p::Integer, a::Integer)
    a == 0 && return UInt8(0)
    return UInt8(min(round(Float64(p) * 255 / Float64(a), RoundNearestTiesAway), 255))
end
function quant_channel(v::Real)::UInt8
    f = Float64(v)
    (isfinite(f) && 0 ≤ f ≤ 1) ||
        throw(ArgumentError("channel value $v outside 0..1"))
    return UInt8(round(f * 255, RoundNearestTiesAway))
end
luma_byte(r::Integer, g::Integer, b::Integer) =
    UInt8(round(0.2126 * Int(r) + 0.7152 * Int(g) + 0.0722 * Int(b)))

"""§7 flat-index formula: 0-based position of logical pixel (r,c) channel k."""
function flat_index(r::Int, c::Int, k::Int, w::Int, h::Int, ch::Int;
                    row_major::Bool)::Int
    row_major ?
        (r - 1) * (w * ch) + (c - 1) * ch + (k - 1) :
        (c - 1) * (h * ch) + (r - 1) * ch + (k - 1)
end

# --- import: element / raw sources → owned premul RGBA8 bytes ---
function _import_elem(p)
    if p isa Vetra.ColorRGBX
        return (UInt8(p.r), UInt8(p.g), UInt8(p.b), UInt8(p.a))
    elseif p isa Vetra.ColorRGBA
        q = Vetra.rgbx(p)   # ACTUAL pinned straight→premul kernel
        return (UInt8(q.r), UInt8(q.g), UInt8(q.b), UInt8(q.a))
    elseif p isa Vetra.ColorRGB
        return (UInt8(p.r), UInt8(p.g), UInt8(p.b), UInt8(255))
    end
    throw(ArgumentError("unsupported pixel element: $(typeof(p))"))
end

"""Element matrix/vector import: logical (r,c) addressed by position, so
column-major memory (an ordinary Julia Matrix) is imported in logical row
order. Existing fromColors rule (D014, src/colormatrices.jl): ordered
offset axes map by position (first position = first logical pixel);
index-array views, adjoints, and views over transposes raise a named
ArgumentError; a top-level transpose is peeled and materialized (odd count
flips the orientation)."""
function import_elements(A, w::Int, h::Int; row_major::Bool = true)
    out = Vector{UInt8}(undef, 4 * w * h)
    if A isa AbstractMatrix
        _check_readable(A)
        # Peel a top-level transpose; odd count flips orientation.
        base = A
        ntrans = 0
        while base isa LinearAlgebra.Transpose
            ntrans += 1
            base = Base.parent(base)
        end
        M = (ntrans % 2 == 1) ? permutedims(base, (2, 1)) : A
        rows = collect(axes(M)[1]); cols = collect(axes(M)[2])
        (length(rows), length(cols)) == (h, w) ||
            throw(ArgumentError("element matrix is $(length(rows))×$(length(cols)), expected $(h)×$(w)"))
        for (ri, r) in enumerate(rows), (ci, c) in enumerate(cols)
            px = _import_elem(M[r, c])
            o = 4 * ((ri - 1) * w + (ci - 1))
            out[o+1] = px[1]; out[o+2] = px[2]; out[o+3] = px[3]; out[o+4] = px[4]
        end
    elseif A isa AbstractVector
        _check_readable(A)   # index-array views rejected (matrix AND vector)
        ax = axes(A)[1]
        ax isa Base.OneTo || ax isa UnitRange ||
            throw(ArgumentError("non-ordered vector axes rejected: index arrays must be ordered ranges"))
        length(ax) == w * h ||
            throw(ArgumentError("element vector has $(length(ax)) entries, expected $(w * h)"))
        for r in 1:h, c in 1:w
            src = row_major ? (r - 1) * w + c : (c - 1) * h + r   # source position
            px = _import_elem(A[ax[src]])
            o = 4 * ((r - 1) * w + c - 1)                         # logical position
            out[o+1] = px[1]; out[o+2] = px[2]; out[o+3] = px[3]; out[o+4] = px[4]
        end
    else
        throw(ArgumentError("unsupported element source: $(typeof(A))"))
    end
    return out
end

"""Existing fromColors read rule: walk the view layers; reject index-array
SubArrays, any Adjoint, and any Transpose sitting under a view. A top-level
Transpose or range-selected view is readable."""
function _check_readable(A)
    inView = false
    m = A
    while true
        if m isa SubArray
            inView = true
            for idx in m.indices
                idx isa AbstractRange ||
                    throw(ArgumentError("index-array view rejected: select by ranges or copy first (fromColors rule)"))
            end
            m = Base.parent(m)
        elseif m isa LinearAlgebra.Adjoint
            throw(ArgumentError("adjoint rejected: copy the matrix first (fromColors rule)"))
        elseif m isa LinearAlgebra.Transpose
            inView && throw(ArgumentError("view over transpose rejected: copy first (fromColors rule)"))
            m = Base.parent(m)
        else
            break
        end
    end
    return nothing
end

"""A tiny AbstractMatrix subtype with ZERO-BASED axes (revision 7): the
distinguishing offset-axis case for the raw matrix route — an ordinary
range view cannot exercise offset axes, and no dependency is needed.
Used exactly as the contract's positional `axes(M)` rule requires."""
struct OffsetMatrix{T} <: AbstractMatrix{T}
    data::Matrix{T}
end
Base.size(a::OffsetMatrix) = size(a.data)
Base.axes(a::OffsetMatrix) = (0:size(a.data, 1) - 1, 0:size(a.data, 2) - 1)
Base.getindex(a::OffsetMatrix, i::Int, j::Int) = a.data[i + 1, j + 1]

"""Raw channel matrix/vector import per the §7 table (UInt8 0..255 or
float 0..1; gray/3ch replication; straight→premul at the boundary). The
table's flat-index formula is the single mapping; shape is validated
before any write (two-phase)."""
function import_raw(A, lay::PixelLayout)
    w, h, ch = lay.width, lay.height, lay.channels
    (lay.alpha == (ch == 4)) ||
        throw(ArgumentError("layout alpha flag disagrees with channels"))
    local getv
    if A isa AbstractVector
        # revision 6: the §7 indexing rule applies to the raw route —
        # ordered offset axes map by POSITION (zero-based allowed);
        # index-array views / adjoints / views-over-transpose rejected
        _check_readable(A)
        ax = axes(A)[1]
        ax isa Base.OneTo || ax isa UnitRange ||
            throw(ArgumentError("non-ordered raw vector axes rejected: ordered offset axes map by position"))
        length(ax) == w * h * ch ||
            throw(ArgumentError("raw vector has $(length(ax)) values, expected $(w * h * ch) for $(w)×$(h)×$ch"))
        getv = (r, c, k) -> A[ax[flat_index(r, c, k, w, h, ch; row_major=lay.row_major) + 1]]
    elseif A isa AbstractMatrix
        _check_readable(A)
        # top-level transposes are peeled and materialized positionally,
        # per the same §7 rule as the element route
        base = A
        ntrans = 0
        while base isa LinearAlgebra.Transpose
            ntrans += 1
            base = Base.parent(base)
        end
        M = (ntrans % 2 == 1) ? permutedims(base, (2, 1)) : base
        # revision 7: positions translate through axes(M) — ordered
        # OFFSET axes (e.g. zero-based) map by position in BOTH declared
        # scan orientations, exactly as the element route
        rows = collect(axes(M)[1])
        cols = collect(axes(M)[2])
        (length(rows), length(cols)) ==
            (lay.row_major ? (h, w * ch) : (w * ch, h)) ||
            throw(ArgumentError("raw matrix is $(length(rows))×$(length(cols)), expected $(lay.row_major ? (h, w * ch) : (w * ch, h)) for $(w)×$(h)×$ch $(lay.row_major ? "row" : "column")-major"))
        getv = (r, c, k) -> (lay.row_major ?
                             M[rows[r], cols[(c - 1) * ch + k]] :
                             M[rows[(c - 1) * ch + k], cols[r]])
    else
        throw(ArgumentError("unsupported raw source: $(typeof(A))"))
    end
    out = Vector{UInt8}(undef, 4 * w * h)
    for r in 1:h, c in 1:w
        vals = _raw_channel_values(A, getv, r, c, ch)
        _write_premul!(out, 4 * ((r - 1) * w + (c - 1)), vals, ch, lay.premultiplied)
    end
    return out
end
function _raw_channel_values(A, getv, r, c, ch)
    el = eltype(A)
    if el === UInt8
        return [UInt8(getv(r, c, k)) for k in 1:ch]
    elseif el === Float32 || el === Float64
        return [quant_channel(getv(r, c, k)) for k in 1:ch]
    end
    throw(ArgumentError("unsupported raw element: $el"))
end
function _write_premul!(out::Vector{UInt8}, o::Int, vals, ch::Int, premul::Bool)
    if ch == 1
        v = UInt8(vals[1])
        out[o+1] = v; out[o+2] = v; out[o+3] = v; out[o+4] = 255
    elseif ch == 3
        out[o+1] = UInt8(vals[1]); out[o+2] = UInt8(vals[2])
        out[o+3] = UInt8(vals[3]); out[o+4] = 255
    else
        if premul
            out[o+1] = UInt8(vals[1]); out[o+2] = UInt8(vals[2])
            out[o+3] = UInt8(vals[3]); out[o+4] = UInt8(vals[4])
        else
            a = UInt8(vals[4])
            out[o+1] = premul_byte(vals[1], a); out[o+2] = premul_byte(vals[2], a)
            out[o+3] = premul_byte(vals[3], a); out[o+4] = a
        end
    end
    return nothing
end

# --- export: owned premul bytes → caller form (snapshot directions) ---
function _export_elem(px, T, matte)
    if T === Vetra.ColorRGBX
        return px
    elseif T === Vetra.ColorRGBA
        return Vetra.toStraightAlpha(px)   # ACTUAL pinned kernel
    elseif T === Vetra.ColorRGB
        px.a == 255 && return Vetra.ColorRGB(UInt8(px.r), UInt8(px.g), UInt8(px.b))
        matte === nothing &&
            throw(ArgumentError("opaque destination with transparent pixels requires an explicit matte"))
        return _matte_rgb(px, matte)
    end
    throw(ArgumentError("unsupported destination element: $T"))
end
function _matte_rgb(px, m::Vetra.ColorRGB)
    # §7 opaque export formula: (p*255 + m*(255-a) + 127) ÷ 255 per channel
    a = Int(px.a)
    r = (Int(px.r) * 255 + Int(m.r) * (255 - a) + 127) ÷ 255
    g = (Int(px.g) * 255 + Int(m.g) * (255 - a) + 127) ÷ 255
    b = (Int(px.b) * 255 + Int(m.b) * (255 - a) + 127) ÷ 255
    return Vetra.ColorRGB(UInt8(r), UInt8(g), UInt8(b))
end

"""Element-matrix export into a fresh `(height, width)` dest, row 1 = top
scanline; the §7 conversion boundary per the table."""
function export_elements(src::Vector{UInt8}, w::Int, h::Int;
                         T::DataType, matte = nothing)
    4 * w * h == length(src) ||
        throw(ArgumentError(
            "export source holds $(length(src) ÷ 4) pixels, expected $(w * h) for a $(w)×$(h) canvas"))
    dest = Matrix{T}(undef, h, w)
    for r in 1:h, c in 1:w
        o = 4 * ((r-1) * w + (c-1))
        px = Vetra.ColorRGBX(UInt8(src[o+1]), UInt8(src[o+2]),
                             UInt8(src[o+3]), UInt8(src[o+4]))
        dest[r, c] = _export_elem(px, T, matte)
    end
    return dest
end
function export_elements_vec(src::Vector{UInt8}, w::Int, h::Int;
                             T::DataType, row_major::Bool = true, matte = nothing)
     dest = Vector{T}(undef, w * h)
    4 * w * h == length(src) ||
        throw(ArgumentError(
            "export source holds $(length(src) ÷ 4) pixels, expected $(w * h) for a $(w)×$(h) canvas"))
    for r in 1:h, c in 1:w
        i = row_major ? (r-1)*w + c : (c-1)*h + r
        o = 4 * ((r-1) * w + (c-1))
        px = Vetra.ColorRGBX(UInt8(src[o+1]), UInt8(src[o+2]),
                             UInt8(src[o+3]), UInt8(src[o+4]))
        dest[i] = _export_elem(px, T, matte)
    end
    return dest
end

"""§7 two-phase destination validation: an existing element-matrix dest
must be `(height, width)` of the canvas — checked before any write."""
function export_shape_validate!(dest_shape::Tuple{Int,Int}, w::Int, h::Int)
    dest_shape == (h, w) ||
        throw(ArgumentError(
            "element destination is $(dest_shape), expected ($h, $w) for a $(w)×$(h) canvas"))
    return nothing
end
"""Raw export per the §7 table (vector form; matrix forms are the same
bytes reshaped). Straight/float/gray conversions applied; `layout` gives
the scan order + convention. Two-phase: the transparent gray/3-channel
matte rule (doc §7) is validated over the WHOLE source before any output
write — gray composites over the matte first, then computes luma from the
composited straight values."""
function export_raw(src::Vector{UInt8}, w::Int, h::Int, lay::PixelLayout;
                    matte = nothing)
    ch = lay.channels
    if (ch == 1 || ch == 3) && matte === nothing &&
        any(i -> src[i * 4 + 4] != 0xff, 0:(w * h - 1))
        throw(ArgumentError(
            "$ch-channel destination with transparent pixels requires " *
            "an explicit matte"))
    end
    out = Vector{UInt8}(undef, ch * w * h)
    for r in 1:h, c in 1:w
        b = export_raw_pixel(src[4*((r-1)*w + (c-1)) + 1:4*((r-1)*w + (c-1)) + 4],
                             ch, lay.premultiplied, matte)
        for k in 1:ch
            out[flat_index(r, c, k, w, h, ch; row_major=lay.row_major) + 1] =
                b[k]
        end
    end
    return out
end
"""Per-pixel raw export (the §7 conversion boundary): owned premul bytes →
the declared convention. Gray/3-channel composite over the matte first,
then luma; straight via the pinned toStraightAlpha formula."""
function export_raw_pixel(bytes::Vector{UInt8}, ch::Int, premul::Bool, matte)
    px = Vetra.ColorRGBX(bytes[1], bytes[2], bytes[3], bytes[4])
    if ch == 1
        m = px.a == 255 ? Vetra.ColorRGB(px.r, px.g, px.b) : _matte_rgb(px, matte)
        return (luma_byte(m.r, m.g, m.b),)
    elseif ch == 3
        m = px.a == 255 ? Vetra.ColorRGB(UInt8(px.r), UInt8(px.g), UInt8(px.b)) :
            _matte_rgb(px, matte)
        return (UInt8(m.r), UInt8(m.g), UInt8(m.b))
    elseif premul
        return (UInt8(px.r), UInt8(px.g), UInt8(px.b), UInt8(px.a))
    end
    q = Vetra.toStraightAlpha(px)
    return (UInt8(q.r), UInt8(q.g), UInt8(q.b), UInt8(q.a))
end

"""§7 float output: the same conversion boundary de-quantizes to `v/255`
(0..1) in the declared scan order."""
function export_raw_f(src::Vector{UInt8}, w::Int, h::Int, lay::PixelLayout;
                      matte = nothing)
    out = Vector{Float64}(undef, lay.channels * w * h)
    for r in 1:h, c in 1:w
        b = export_raw(src[4*((r-1)*w + (c-1)) + 1:4*((r-1)*w + (c-1)) + 4],
                       1, 1,
                       PixelLayout(1, 1, lay.channels, lay.alpha,
                                   lay.premultiplied, lay.row_major);
                       matte = matte)
        for k in 1:lay.channels
            out[flat_index(r, c, k, w, h, lay.channels;
                           row_major=lay.row_major) + 1] = b[k] / 255
        end
    end
    return out
end

"""§7 idempotent opaque staging reconciliation: a SUCCESSFUL writeback over
an opaque destination replaces the staged pixel with the composite result
(opaque), so repeated identical flushes are stable."""
function reconcile_opaque(staged_px::Vetra.ColorRGBX,
                          dest_px::Vetra.ColorRGB)::Vetra.ColorRGBX
    m = _matte_rgb(staged_px, dest_px)
    return Vetra.ColorRGBX(UInt8(m.r), UInt8(m.g), UInt8(m.b), UInt8(255))
end

"""Truthful storage-order report (§2/§7): an ordinary Julia Matrix is
column-major; range views inherit the parent's memory order; raw
row-major vectors/matrices and borrowed Images are row-major."""
function storage_order(A)
    A isa Matrix && return :col
    A isa SubArray && return storage_order(Base.parent(A))
    return :row
end

# ===========================================================================
# 4. W3C compositing reference — doc §5.7 (vector nonseparable, revision 4)
# ===========================================================================

clamp01f(v::Real) = Float64(clamp(Float64(v), 0.0, 1.0))

# separable B(Cb, Cs) — spec §10.1 scalar formulas. The W3C endpoint
# exceptions test the BACKDROP case before the source case (frozen §5.7,
# W3C §10.1.7/§10.1.8; the pinned kernels agree at the endpoints).
function _blend_separable(mode, Cb, Cs)
    if mode === 1        # Darken
        return min(Cb, Cs)
    elseif mode === 2    # Multiply
        return Cb * Cs
    elseif mode === 3    # ColorBurn: Cb==1 first, then Cs==0 ⇒ 0
        Cb >= 1 && return 1.0
        Cs <= 0 && return 0.0
        return max(0.0, 1 - (1 - Cb) / Cs)
    elseif mode === 4    # Lighten
        return max(Cb, Cs)
    elseif mode === 5    # Screen
        return Cb + Cs - Cb * Cs
    elseif mode === 6    # ColorDodge: Cb==0 first, then Cs==1 ⇒ 1
        Cb <= 0 && return 0.0
        Cs >= 1 && return 1.0
        return min(1.0, Cb / (1 - Cs))
    elseif mode === 7    # Overlay: B(Cb,Cs) = HardLight(Cs,Cb) — the test
        # is on the backdrop value (spec §10.1.4; pinned kernel agrees)
        return Cb <= 0.5 ? 2 * Cb * Cs : 1 - 2 * (1 - Cb) * (1 - Cs)
    elseif mode === 8    # SoftLight
        D = Cb <= 0.25 ? ((16*Cb - 12)*Cb + 4)*Cb : sqrt(Cb)
        return Cs <= 0.5 ? Cb - (1 - 2*Cs)*Cb*(1 - Cb) : Cb + (2*Cs - 1)*(D - Cb)
    elseif mode === 9    # HardLight: the test is on the SOURCE value
        return Cs <= 0.5 ? 2*Cb*Cs : 1 - 2*(1 - Cs)*(1 - Cb)
    elseif mode === 10   # Difference
        return abs(Cb - Cs)
    elseif mode === 11   # Exclusion
        return Cb + Cs - 2*Cb*Cs
    end
    throw(ArgumentError("non-separable modes use the vector pipeline"))
end

# non-separable B(Cb, Cs) — spec §10.2 RGB-vector forms (revision 4)
_lum(C) = 0.3*C[1] + 0.59*C[2] + 0.11*C[3]
function _clip_color(C)
    L = _lum(C); n = minimum(C); x = maximum(C)
    if n < 0
        C = L .+ (C .- L) .* (L / (L - n))
    end
    if x > 1
        C = L .+ (C .- L) .* ((1 - L) / (x - L))
    end
    return C
end
function _set_lum(C, l)
    d = l - _lum(C)
    return _clip_color(C .+ d)
end
_sat(C) = maximum(C) - minimum(C)
function _set_sat(C, s)
    order = sortperm(C)
    i_min, i_mid, i_max = order[1], order[2], order[3]
    Cmin, Cmid, Cmax = C[i_min], C[i_mid], C[i_max]
    if Cmax > Cmin
        Cmid = (Cmid - Cmin) * s / (Cmax - Cmin)
        Cmax = s
    else
        Cmid = Cmax = 0
    end
    Cmin = 0
    out = copy(C)
    out[i_min] = Cmin; out[i_mid] = Cmid; out[i_max] = Cmax
    return out
end
# spec §10.2 mode formulas (B takes RGB vectors)
_blend_hue(Cb, Cs)      = _set_lum(_set_sat(Cs, _sat(Cb)), _lum(Cb))
_blend_saturation(Cb, Cs) = _set_lum(_set_sat(Cb, _sat(Cs)), _lum(Cb))
_blend_color(Cb, Cs)    = _set_lum(Cs, _lum(Cb))
_blend_luminosity(Cb, Cs) = _set_lum(Cb, _lum(Cs))

"""W3C compositing pipeline (§5.7). S, D are straight (r,g,b,a) 0..1.
Returns the premultiplied output (r,g,b,a): the color channels are the
composite `αs·Fa·Cr + αb·Fb·Cb` (straight inputs) and the alpha is the
Porter–Duff row `αo`. `Lighter` adds the premultiplied contribution of
the BLENDED source color (step 2's `Cr`; `Cr = Cs` for a Normal paint) —
the artistic step never bypasses the additive operator. `coverage` scales
source alpha only. Non-separable modes apply B to the RGB vectors only —
the alpha channel never passes through B."""
function composite(compo::CompositionOperator, mode::Int, S, D;
                   coverage::Real = 1.0)
    sr, sg, sb, sa = S
    dr, dg, db, da = D
    αs = clamp01f(sa * coverage)
    αb = clamp01f(da)
    # step 2: artistic blend (straight colors; the alpha channel never
    # passes through B — output alpha is the Porter–Duff row αo, step 3)
    if mode == 0
        Cr = (sr, sg, sb)
    elseif 12 ≤ mode ≤ 15
        B = (mode == 12 ? _blend_hue : mode == 13 ? _blend_saturation :
             mode == 14 ? _blend_color : _blend_luminosity)
        Bvec = B([dr, dg, db], [sr, sg, sb])
        Cr = ((1 - αb)*sr + αb*Bvec[1],
              (1 - αb)*sg + αb*Bvec[2],
              (1 - αb)*sb + αb*Bvec[3])
    else
        Cr = ((1 - αb)*sr + αb*_blend_separable(mode, dr, sr),
              (1 - αb)*sg + αb*_blend_separable(mode, dg, sg),
              (1 - αb)*sb + αb*_blend_separable(mode, db, sb))
    end
    # step 3: Porter–Duff — color channels are the premultiplied composite
    # (straight inputs); the output alpha is the Porter–Duff row αo
    # (the alpha channel never passes through B).
    Fa, Fb, αo = _pd(compo, αs, αb)
    if compo === Lighter
        # additive: premul addition of the BLENDED source, clamped;
        # αo = min(1, αs+αb)
        co = (min(αs*Cr[1] + αb*dr, 1.0), min(αs*Cr[2] + αb*dg, 1.0),
              min(αs*Cr[3] + αb*db, 1.0))
        αo ≈ 0 && return (0.0, 0.0, 0.0, 0.0)
        return (co[1], co[2], co[3], αo)
    end
    co = (αs*Fa*Cr[1] + αb*Fb*dr,
          αs*Fa*Cr[2] + αb*Fb*dg,
          αs*Fa*Cr[3] + αb*Fb*db)
    αo ≈ 0 && return (0.0, 0.0, 0.0, 0.0)
    return (co[1], co[2], co[3], αo)
end

function _pd(compo::CompositionOperator, αs, αb)
    if compo === SourceOver
        return (1.0, 1.0 - αs, αs + αb*(1 - αs))
    elseif compo === SourceIn
        return (αb, 0.0, αs*αb)
    elseif compo === SourceOut
        return (1.0 - αb, 0.0, αs*(1 - αb))
    elseif compo === SourceAtop
        return (αb, 1.0 - αs, αb)
    elseif compo === Over
        return (1.0 - αb, 1.0, αb + αs*(1 - αb))
    elseif compo === In
        return (0.0, αs, αs*αb)
    elseif compo === Out
        return (0.0, 1.0 - αs, αb*(1 - αs))
    elseif compo === Atop
        return (1.0 - αb, αs, αs)
    elseif compo === Xor
        return (1.0 - αb, 1.0 - αs, αs*(1 - αb) + αb*(1 - αs))
    elseif compo === Copy
        return (1.0, 0.0, αs)
    elseif compo === Lighter
        return (1.0, 1.0, min(1.0, αs + αb))
    end
    throw(ArgumentError("unknown composition operator $(compo.value)"))
end

"""§5.7 step 5: single quantization of the premultiplied result."""
function to_premul_bytes(co)
    return (UInt8(round(co[1]*255, RoundNearestTiesAway)),
            UInt8(round(co[2]*255, RoundNearestTiesAway)),
            UInt8(round(co[3]*255, RoundNearestTiesAway)),
            UInt8(round(co[4]*255, RoundNearestTiesAway)))
end

# ===========================================================================
# 5. Browser wire records — doc §11 (tags, fields, accounting, identity)
# ===========================================================================

const WIRE_TAGS = ("fill", "stroke", "clear", "image", "text", "effect",
                   "group-start", "group-end", "fallback", "set-pixels")
const WIRE_TAG_FIELDS = Dict(
    "fill" => ["path", "winding", "paint", "transform", "composition", "clips"],
    # the stroke record carries NO winding — StrokeOp has none (fixed
    # nonzero at execution); the v4 record invented the field
    "stroke" => ["path", "paint", "transform", "composition", "clips",
                 "width", "cap", "join", "miterLimit", "dashes", "dashOffset"],
    "clear" => ["rect", "transform", "clips"],
    "image" => ["assetId", "srcRect", "destRect", "transform", "sampling",
                "composition", "opacity", "clips"],
    "text" => ["glyphs", "paint", "transform", "composition", "clips"],
    "effect" => ["kind", "radius", "offset", "color", "opacity", "inRegion",
                 "outRegion", "transform", "clips"],
    "group-start" => ["opacity", "composition", "clips"],
    "group-end" => ["clips"],
    "fallback" => ["feature", "reason", "scope", "original", "clips"],
    "set-pixels" => ["assetId", "rect"],
)

struct WirePaint
    kind::String
    color::Union{NTuple{4,Int}, Nothing}
    opacity::Float32        # revision 6 numeric policy: core type kept
    artistic::Union{String, Nothing}
    assetId::Union{Int, Nothing}
    imageTransform::Union{NTuple{9,Float32}, Nothing}
    handles::Union{Vector{NTuple{2,Float32}}, Nothing}
    # revision 6 numeric policy: stop colors are byte integers 0..255,
    # the position preserves the declared Float32 (no widening)
    stops::Union{Vector{Tuple{Int,Int,Int,Int,Float32}}, Nothing}
end
struct WireClip
    path::Vector{Float32}
    winding::String
end
struct WireGlyph
    outline::Vector{Float32}
    transform::NTuple{9,Float32}
end
struct WireAsset
    width::Int
    height::Int
    encoding::String
    data::Vector{UInt8}
end
struct WireCommand
    tag::String
    fields::Dict{String, Any}
end
struct WireOriginal
    ops::Vector{WireCommand}
    assets::Dict{Int, WireAsset}
end

# --- §11 canonical serialization (frozen, revision 5 — the ONE byte
# authority; the revision-4 per-leaf upper-bound formula is retracted) ---
function json_escape(s::String)::String
    io = IOBuffer()
    for ch in s
        if ch == '"'
            write(io, "\\\"")
        elseif ch == '\\'
            write(io, "\\\\")
        elseif ch < ' '
            write(io, "\\u" * uppercase(lpad(string(Int(ch), base=16), 4, '0')))
        else
            write(io, ch)
        end
    end
    return String(take!(io))
end
function canon_number(io, v)
    v isa Int && return write(io, string(v))
    s = string(v)   # Float32/Float64 shortest decimal — a valid JSON number
    all(c -> isdigit(c) || c in ".+-eE", s) ||
        throw(ArgumentError("non-JSON canonical number: $s"))
    return write(io, s)
end
canon_string(io, s) = write(io, '"', json_escape(s), '"')
function canon_value(io, v)
    if v === nothing
        write(io, "null")
    elseif v isa Bool
        write(io, v ? "true" : "false")
    elseif v isa String
        canon_string(io, v)
    elseif v isa Number
        canon_number(io, v)
    elseif v isa Vector{<:Tuple{String, Any}}   # JSON object, key order given
        write(io, '{')
        for (i, (k, e)) in enumerate(v)
            i > 1 && write(io, ',')
            canon_string(io, k)
            write(io, ':')
            canon_value(io, e)
        end
        write(io, '}')
    elseif v isa AbstractArray || v isa Tuple   # JSON array
        write(io, '[')
        for (i, e) in enumerate(v)
            i > 1 && write(io, ',')
            canon_value(io, e)
        end
        write(io, ']')
    else
        throw(ArgumentError("unserializable canonical value: $(typeof(v))"))
    end
end
canon_json(v) = sprint(canon_value, v)

# --- §11 readback request/response identity (record machine) ---
struct ReadbackRequest
    id::Int
    scope::String
    session::Int
    generation::Int
    submission::Int
    rect::NTuple{4,Int}
    encoding::String
end
mutable struct ReadbackResponse
    id::Int
    scope::String
    session::Int
    generation::Int
    submission::Int
    encoding::String
    width::Int
    height::Int
    data::Vector{UInt8}
end

mutable struct BrowserSession
    scope::String
    session::Int
    generation::Int
    completed::Int          # count of completed provider submissions
    pending::Dict{Int, ReadbackRequest}
    next_id::Int
    BrowserSession(scope::String) =
        new(scope, 1, 1, 0, Dict{Int, ReadbackRequest}(), 1)
end

function issue_readback(bs::BrowserSession, rect=(0, 0, 0, 0),
                         encoding="rgba8-premul")
    req = ReadbackRequest(bs.next_id, bs.scope, bs.session, bs.generation,
                          bs.completed, rect, encoding)
    bs.next_id += 1
    bs.pending[req.id] = req
    return req
end

"""Deliver a response. Every identity field is checked against the SAVED
request, the live scope identity must still match the saved request, and
the payload (encoding, dimensions, decoded length for rgba8-*) is
validated — all BEFORE consumption. A failing response is rejected by
named ArgumentError and discarded: it authorizes nothing and cannot
silently consume the pending request's authorization."""
function deliver_response(bs::BrowserSession, resp::ReadbackResponse)
    req = get(bs.pending, resp.id, nothing)
    req === nothing &&
        throw(ArgumentError("readback response for unknown request id $(resp.id)"))
    resp.scope != req.scope &&
        throw(ArgumentError("wrong-target readback response (scope)"))
    if resp.session < req.session
        throw(ArgumentError("stale-session readback response"))
    elseif resp.session > req.session
        throw(ArgumentError("future-session readback response"))
    end
    resp.generation != req.generation &&
        throw(ArgumentError("superseded-generation readback response"))
    resp.submission != req.submission &&
        throw(ArgumentError("superseded-submission readback response"))
    resp.encoding != req.encoding &&
        throw(ArgumentError("invalid-encoding readback response"))
    if startswith(resp.encoding, "rgba8-")
        (resp.width, resp.height) != (req.rect[3], req.rect[4]) &&
            throw(ArgumentError("dimension-mismatch readback response"))
        length(resp.data) != 4 * resp.width * resp.height &&
            throw(ArgumentError("decoded-length readback response"))
    end
    (bs.session != req.session || bs.generation != req.generation) &&
        throw(ArgumentError("superseded-live readback response"))
    delete!(bs.pending, resp.id)      # consumed exactly once
    return :consumed
end

"""A snapshot: awaits the request's OWN response (echoing the saved
request identity), consuming it exactly once."""
function snapshot_roundtrip(bs::BrowserSession, id::Int)
    req = get(bs.pending, id, nothing)
    resp = ReadbackResponse(id, req.scope, req.session, req.generation,
                            req.submission, req.encoding,
                            req.rect[3], req.rect[4],
                            UInt8[n % 255 + 1 for n in 0:(4 * req.rect[3] *
                                                          req.rect[4] - 1)])
    deliver_response(bs, resp)
    return resp
end
"""Context loss: the session bumps and every pending request is
invalidated immediately (revision 4)."""
function lose_context!(bs::BrowserSession)
    bs.session += 1
    empty!(bs.pending)
    return nothing
end
"""Recovery: the device generation bumps and the document is re-applied;
new requests carry the fresh generation."""
function recover!(bs::BrowserSession)
    bs.generation += 1
    empty!(bs.pending)
    return nothing
end
function timeout!(bs::BrowserSession, id::Int)
    delete!(bs.pending, id)   # ownership retained
    return nothing
end

# ===========================================================================
# 6. Submission-tracking record machine — doc §8.1
# ===========================================================================

mutable struct SubmissionTracker
    backend::CanvasBackend
    subs::Vector                      # the tracked handles, ordered
                                     # (the core tracking root —
                                     # Canvas.submissions, doc §3)
    closed::Bool
    SubmissionTracker(b::CanvasBackend) = new(b, Any[], false)
end
"""The core-owned tracked frontend handle (doc §8.1 revision 8 — the
contract's `TrackedSubmission`): wraps exactly ONE provider-owned
handle (the §8 five-method protocol is unchanged). The public frontend
routes (flush!, canvas-level upload_pixels!) return only tracked
handles — the caller never receives the bare provider handle. `tracker`
and the concrete `staged` action closure are core-internal
representation (opaque to the provider — the contract's staged::Bool
is its presence). The state machine (pending → complete | failed)
lives on the HANDLE, so a completed handle stays idempotent and a
failed one stays sticky even after it is retired from the tracking
root; `staged_done` is set ONLY after the staged action succeeds."""
mutable struct TrackedSubmission <: CanvasSubmission
    provider::CanvasSubmission
    tracker::SubmissionTracker
    staged::Union{Function, Nothing}
    state::Symbol
    # revision 9: ONE sufficient stored-exception domain — the original
    # named error BY IDENTITY (the provider's BackendSubmitError; the
    # staged TransferError with its :partial/:unwritten status; the §7
    # phase-1 named validation error, e.g. ArgumentError, raised before
    # any store). A restricted union strands :failed with error=nothing
    # (later waits throw nothing), so the domain is not grown class by
    # class — the field holds the exception object it observed.
    error::Any
    staged_done::Bool
    TrackedSubmission(p::CanvasSubmission, tr::SubmissionTracker,
                      staged::Union{Function, Nothing} = nothing) =
        new(p, tr, staged, :pending, nothing, false)
end
"""Track an accepted submission (drawing flush or upload dispatch): wrap
the provider handle in a tracked frontend handle and append the core
tracking entry — the §7 ordered upload route returns its own tracked
handle like any accepted submission."""
function tracker_track(tr::SubmissionTracker, provider_sub::CanvasSubmission,
                       staged::Union{Function, Nothing} = nothing)
    fh = TrackedSubmission(provider_sub, tr, staged)
    push!(tr.subs, fh)
    return fh
end
"""The public flush! shape: submit! (provider protocol), then track."""
function tracker_submit(tr::SubmissionTracker, batch::CommandBatch)
    return tracker_track(tr, submit!(tr.backend, batch))
end
"""§8.1 (revision 9) THE SINGLE COMPLETION ROUTE — shared by BOTH public
waiting forms (direct wait(handle) and wait(c) → wait-all). Two
independent failure classes, both sticky, both preserved:
(1) forward the provider wait; a provider failure (BackendSubmitError)
    marks the entry FAILED — the staged action is NEVER run, the core
    entry + provider resources are retained (the work did not complete);
(2) provider success releases the provider's batch roots (retention
    duty ends at completion); then the core staged completion runs
    EXACTLY ONCE and `staged_done` is set ONLY after it succeeds. A
    staged failure (the ORIGINAL named error by identity — TransferError
    with its :partial/:unwritten status, a named BackendSubmitError, or
    the §7 phase-1 named validation error raised before any store)
    marks the entry FAILED with that original error: repeated
    wait/wait-all/close re-raise it, the action is never re-run
    automatically, the entry is never completed or retired, and the
    core staging is retained by the failed entry (the already-released
    provider roots are NOT — only the core staging is). Success ⇒
    COMPLETE + RETIRE the core entry (:inflight refs released at the §6
    release point). The id counter, not the completed history, is what
    wire identity retains."""
function wait(fh::TrackedSubmission)
    fh.state === :complete && return nothing
    fh.state === :failed && throw(fh.error)
    try
        wait(fh.provider)
    catch e
        e isa BackendSubmitError || throw(e)
        fh.state = :failed
        fh.error = e
        rethrow()
    end
    if !fh.staged_done
        try
            fh.staged !== nothing && fh.staged()
        catch e
            # staged failure: store the ORIGINAL named error by identity
            # (TransferError with its :partial/:unwritten status, a named
            # BackendSubmitError, or the §7 phase-1 named validation
            # error raised before any store) — no conversion, so the
            # failed state can never be stranded with no error; sticky —
            # the state guard above prevents any automatic re-run
            fh.state = :failed
            fh.error = e
            rethrow()
        end
        fh.staged_done = true   # ONLY after successful staging
    end
    fh.state = :complete
    fh.tracker.subs = filter(t -> t !== fh, fh.tracker.subs)
    return nothing   # retire the core entry
end
"""wait(c) route: wait EVERY outstanding tracked entry in order — the
same per-handle route (revision 7: no second completion mechanism)."""
function tracker_wait_all(tr::SubmissionTracker)
    for ts in copy(tr.subs)
        wait(ts)
    end
    return nothing
end
"""§8.1 close: wait-all through the single route, then provider close.
A sticky failure re-raises (the failed entry is retained and the
tracker stays open); a SUCCESSFUL close clears the owned tracking root
entirely."""
function tracker_close(tr::SubmissionTracker)
    tr.closed && return nothing
    tracker_wait_all(tr)
    close(tr.backend)
    tr.subs = Any[]
    tr.closed = true
    return nothing
end
"""§8 no-op: core-owned inert handle — not tracked, never implies
earlier completion (the §8.1 negative control)."""
function tracker_noop(::SubmissionTracker)
    return CanvasNoopSubmission()
end

# ===========================================================================
# 6b. Browser submission / execution-ack identity — doc §11
# ===========================================================================

struct SubmissionRecord
    id::Int
    scope::String
    session::Int
    generation::Int
    n_commands::Int
    n_assets::Int
end
mutable struct ExecutionAck
    id::Int
    scope::String
    session::Int
    generation::Int
    status::String        # "success" | "error"
    detail::String
end
mutable struct BrowserSubmissions
    scope::String
    session::Int
    generation::Int
    next_id::Int
    subs::Dict{Int, SubmissionRecord}
    states::Dict{Int, Symbol}        # :pending | :complete | :failed
    errors::Dict{Int, BackendSubmitError}
    BrowserSubmissions(scope::String) =
        new(scope, 1, 1, 1, Dict{Int, SubmissionRecord}(),
            Dict{Int, Symbol}(), Dict{Int, BackendSubmitError}())
end
"""One submission record per browser flush!; ids are monotonic per scope
and carry the scope/session/generation identity at submit time."""
function submit_browser(bs::BrowserSubmissions, n_commands::Int, n_assets::Int)
    rec = SubmissionRecord(bs.next_id, bs.scope, bs.session, bs.generation,
                           n_commands, n_assets)
    bs.subs[rec.id] = rec
    bs.states[rec.id] = :pending
    bs.next_id += 1
    return rec
end
"""Exactly one execution-ack per submission. An ack matching no pending
submission — unknown id, wrong scope, stale or future session,
superseded generation — is rejected by named ArgumentError and authorizes
nothing; the pending submission is not consumed. A readback response is
NOT an execution ack (separate record machine, §6 above)."""
function deliver_execution_ack!(bs::BrowserSubmissions, ack::ExecutionAck)
    rec = get(bs.subs, ack.id, nothing)
    rec === nothing &&
        throw(ArgumentError("execution ack for unknown submission id $(ack.id)"))
    ack.scope != rec.scope &&
        throw(ArgumentError("wrong-target execution ack (scope)"))
    if ack.session < rec.session
        throw(ArgumentError("stale-session execution ack"))
    elseif ack.session > rec.session
        throw(ArgumentError("future-session execution ack"))
    end
    ack.generation != rec.generation &&
        throw(ArgumentError("superseded-generation execution ack"))
    bs.states[ack.id] !== :pending &&
        throw(ArgumentError("execution ack for non-pending submission $(ack.id)"))
    if ack.status == "success"
        bs.states[ack.id] = :complete
    elseif ack.status == "error"
        bs.states[ack.id] = :failed
        bs.errors[ack.id] = BackendSubmitError(ack.detail)
    else
        throw(ArgumentError("invalid execution ack status $(ack.status)"))
    end
    return nothing
end
"""Sticky completion (browser flavor of the §8 submission state machine):
a failed submission re-raises the same error on every later wait."""
function wait_browser_sub(bs::BrowserSubmissions, id::Int)
    get(bs.states, id, nothing) === nothing &&
        throw(ArgumentError("unknown submission id $id"))
    st = bs.states[id]
    st === :pending && throw(ArgumentError("submission $id still pending"))
    st === :failed && throw(bs.errors[id])
    return :complete
end

# ===========================================================================
# 7. Ordinary-module providers — public dispatch examples (doc §8/§13)
# ===========================================================================

module DemoProvider
import Vetra
import Main

# Provider-owned types. The backend is DEFERRED (execution happens at
# wait), and one variant is FIELD-LESS to prove the frontend needs only
# the five protocol methods.
mutable struct DeferredBackend <: Main.CanvasBackend
    bound::Bool
    spec::Union{Main.CanvasTargetSpec, Nothing}
    submissions::Vector
    close_calls::Int
    fail_next_wait::Bool
    calls::Vector{Symbol}    # dispatch order: :submit then :upload
    DeferredBackend() = new(false, nothing, Vector{Main.Any}(), 0, false,
                            Symbol[])
end
mutable struct DeferredSubmission <: Main.CanvasSubmission
    backend::DeferredBackend
    batch::Union{Main.CommandBatch, Nothing}
                                        # the provider root: CLEARED at
                                        # completion (the §8 retention
                                        # duty ends there — revision 8
                                        # verifies the actual reference,
                                        # not a flag); pending/failed
                                        # handles retain it
    waited::Int
    state::Symbol
    error::Union{Main.BackendSubmitError, Nothing}
end

struct ZeroFieldSubmission <: Main.CanvasSubmission end
struct ZeroFieldBackend <: Main.CanvasBackend end   # no fields at all

Main.backend_capabilities(b::DeferredBackend) = Main.BackendCapabilities(
    1, "demo/deferred", "rgba8-premul",
    Dict("draw.fill" => Main.CapabilityStatus(Main.NativeCapability, ""),
         "composition.source-over" => Main.CapabilityStatus(Main.NativeCapability, "")),
    Dict("readback-timeout-ms" => 5000, "thread-affinity" => 1))
function Main.bind_target!(b::DeferredBackend, spec::Main.CanvasTargetSpec)
    b.bound = true
    b.spec = spec
    Main.StorageReport(:owned, :row, spec.initial !== nothing)
end
function Main.submit!(b::DeferredBackend, batch::Main.CommandBatch)
    push!(b.calls, :submit)
    err = b.fail_next_wait ? Main.BackendSubmitError("demo deferred failure") : nothing
    b.fail_next_wait = false
    sub = DeferredSubmission(b, batch, 0, :pending, err)
    push!(b.submissions, sub)
    return sub
end
"""§7 ordered upload route (revision 6): the upload dispatch returns its
OWN tracked submission, after the older pending drawing."""
function Main.upload_pixels!(b::DeferredBackend, asset::Main.CanvasAsset,
                             region::Vetra.Rect)
    push!(b.calls, :upload)
    err = b.fail_next_wait ? Main.BackendSubmitError("demo upload failure") : nothing
    b.fail_next_wait = false
    sub = DeferredSubmission(
        b, Main.CommandBatch(Main.CanvasOp[],
                             Dict{Int, Main.CanvasAsset}(),
                             Vetra.Vec2(Int(region.w), Int(region.h)), 1f0),
        0, :pending, err)
    push!(b.submissions, sub)
    return sub
end
function Main.wait(sub::DeferredSubmission)
    sub.state === :complete && return nothing
    sub.state === :failed && throw(sub.error)
    sub.waited += 1
    if sub.error !== nothing
        sub.state = :failed
        throw(sub.error)     # pending/failed ownership preserved
    end
    sub.state = :complete
    # the retention duty ends at completion: release the batch root and
    # drop the completed handle from the provider's own tracking (scalar
    # observations — waited/state — remain on the handle)
    sub.batch = nothing
    filter!(s -> s !== sub, sub.backend.submissions)
    return nothing
end
function Main.close(b::DeferredBackend)
    b.close_calls += 1
    return nothing
end

# field-less provider: everything through the five methods
Main.backend_capabilities(::ZeroFieldBackend) = Main.BackendCapabilities(
    1, "demo/zero-field", "rgba8-premul",
    Dict("draw.fill" => Main.CapabilityStatus(Main.NativeCapability, "")),
    Dict("thread-affinity" => 0))
Main.bind_target!(::ZeroFieldBackend, ::Main.CanvasTargetSpec) =
    Main.StorageReport(:owned, :row, false)
Main.submit!(::ZeroFieldBackend, ::Main.CommandBatch) = ZeroFieldSubmission()
Main.wait(::ZeroFieldSubmission) = nothing
Main.close(::ZeroFieldBackend) = nothing

end # module DemoProvider

module StorageHost
import Vetra
import Main

mutable struct HostAdapter <: Main.StorageAdapter
    matrix::Matrix{Vetra.ColorRGBX}
    descriptor_calls::Int
    read_calls::Int
    write_calls::Int
    alloc_calls::Int
    HostAdapter(m::Matrix{Vetra.ColorRGBX}) = new(m, 0, 0, 0, 0)
end

function Main.storage_descriptor(s::HostAdapter)
    s.descriptor_calls += 1
    h, w = size(s.matrix)
    return Main.StorageDescriptor(Vetra.ColorRGBX,
                                  Main.PixelLayout(w, h, 4, true, true, true),
                                  true, true)
end

# regions are ZERO-BASED physical pixel rects: rect(0,0,1,1) addresses the
# storage's first element; the exchange is owned premul RGBA8 (§13
# canonical boundary)
function Main.storage_read(s::HostAdapter, r::Vetra.Rect)
    s.read_calls += 1
    data = UInt8[]
    for y in 0:Int(r.h) - 1, x in 0:Int(r.w) - 1
        p = s.matrix[Int(r.y) + y + 1, Int(r.x) + x + 1]
        append!(data, (p.r, p.g, p.b, p.a))
    end
    Main.CanvasAsset(0, Int(r.w), Int(r.h), data)
end
function Main.storage_write!(s::HostAdapter, r::Vetra.Rect, data::Vector{UInt8})
    s.write_calls += 1
    for y in 0:Int(r.h) - 1, x in 0:Int(r.w) - 1
        i = 4 * (y * Int(r.w) + x)
        s.matrix[Int(r.y) + y + 1, Int(r.x) + x + 1] =
            Vetra.ColorRGBX(data[i+1], data[i+2], data[i+3], data[i+4])
    end
    return nothing
end
function Main.storage_alloc(p::HostAdapter, ::Type{T},
                            dims::Tuple{Int, Int}) where {T<:Main.StorageAdapter}
    p.alloc_calls += 1
    T !== HostAdapter &&
        throw(ArgumentError("host storage_alloc returns the host adapter type"))
    w, h = dims
    HostAdapter(Matrix{Vetra.ColorRGBX}(undef, h, w))
end

end # module StorageHost

# --- upload dispatch recorder: proves the dispatch carries the asset id ---
mutable struct UploadRecorderBackend <: CanvasBackend
    uploads::Vector{Tuple{Int, NTuple{4,Int}}}
    UploadRecorderBackend() = new(Tuple{Int, NTuple{4,Int}}[])
end
backend_capabilities(::UploadRecorderBackend) = BackendCapabilities(
    1, "demo/upload-recorder", "rgba8-premul",
    Dict("pixel-upload" => CapabilityStatus(NativeCapability, "")),
    Dict("thread-affinity" => 0))
bind_target!(::UploadRecorderBackend, ::CanvasTargetSpec) =
    StorageReport(:owned, :row, false)
submit!(::UploadRecorderBackend, ::CommandBatch) =
    error("not part of this record boundary")
close(::UploadRecorderBackend) = nothing
function upload_pixels!(b::UploadRecorderBackend, asset::CanvasAsset,
                        region::Vetra.Rect)
    push!(b.uploads, (asset.id,
                      (Int(region.x), Int(region.y), Int(region.w), Int(region.h))))
    return CanvasNoopSubmission()
end

# ===========================================================================
# 8. Wire-command mapping (core semantics → records, doc §11)
# ===========================================================================

const COMP_NAMES = Dict(SourceOver => "source-over", SourceIn => "source-in",
    SourceOut => "source-out", SourceAtop => "source-atop", Over => "over",
    In => "in", Out => "out", Atop => "atop", Xor => "xor", Copy => "copy",
    Lighter => "lighter")
const ART_NAMES = Dict(1 => "darken", 2 => "multiply", 3 => "color-burn",
    4 => "lighten", 5 => "screen", 6 => "color-dodge", 7 => "overlay",
    8 => "soft-light", 9 => "hard-light", 10 => "difference",
    11 => "exclusion", 12 => "hue", 13 => "saturation", 14 => "color",
    15 => "luminosity")
const WIND_NAMES = Dict(Vetra.NonZero => "nonzero", Vetra.EvenOdd => "evenodd")

_mat9(m::Vetra.Mat3) = Tuple(collect(m.data))
# revision 6 numeric wire policy: geometry preserves the declared
# Float32 (shortest decimal) — never widened to Float64 in the mapping
_rect4f(r::Vetra.Rect) = (r.x, r.y, r.w, r.h)
_rect4i(r::Vetra.Rect) = (Int(r.x), Int(r.y), Int(r.w), Int(r.h))

"""§11 paint-kind mapping: the wire `kind` is the 1:1 name of the owning
PaintKind — a linear gradient never serializes as a tiled-image."""
function paint_wire_kind(k::Vetra.PaintKind)::String
    k === Vetra.SolidPaint && return "solid"
    k === Vetra.ImagePaint && return "image"
    k === Vetra.TiledImagePaint && return "tiled-image"
    k === Vetra.LinearGradientPaint && return "linear-gradient"
    k === Vetra.RadialGradientPaint && return "radial-gradient"
    k === Vetra.AngularGradientPaint && return "angular-gradient"
    throw(ArgumentError("unmappable PaintKind $(k.value)"))
end
function wire_paint(p::OwnedPaint)
    kind = paint_wire_kind(p.kind)
    color = kind == "solid" ?
        (Int(p.color.r), Int(p.color.g), Int(p.color.b), Int(p.color.a)) : nothing
    artistic = p.artistic.value == 0 ? nothing : ART_NAMES[p.artistic.value]
    return WirePaint(kind, color, p.opacity, artistic,
                     p.imageAssetId == 0 ? nothing : p.imageAssetId,
                     # image/tiled paints always carry imageTransform (doc
                     # §11 consistency: assetId + imageTransform set)
                     kind in ("image", "tiled-image") ? _mat9(p.imageMat) : nothing,
                     isempty(p.gradientHandles) ? nothing :
                         [ (Float32(h.x), Float32(h.y)) for h in p.gradientHandles ],
                     isempty(p.gradientStops) ? nothing :
                         [ (Int(s.color.r), Int(s.color.g), Int(s.color.b),
                            Int(s.color.a), s.position)
                           for s in p.gradientStops ])
end
function wire_command(op::FillOp)
    WireCommand("fill", Dict(
        "path" => collect(op.path.commands),
        "winding" => WIND_NAMES[op.winding],
        "paint" => wire_paint(op.paint),
        "transform" => _mat9(op.tform),
        "composition" => COMP_NAMES[op.composition],
        "clips" => [WireClip(collect(c.path.commands), WIND_NAMES[c.winding]) for c in op.clips]))
end
function wire_command(op::StrokeOp)
    # the stroke record carries NO winding — StrokeOp has none (fixed
    # nonzero at execution); the v4 record invented the field
    WireCommand("stroke", Dict(
        "path" => collect(op.path.commands),
        "paint" => wire_paint(op.paint),
        "transform" => _mat9(op.tform),
        "composition" => COMP_NAMES[op.composition],
        "clips" => [WireClip(collect(c.path.commands), WIND_NAMES[c.winding]) for c in op.clips],
        "width" => op.width,
        "cap" => op.cap === Vetra.ButtCap ? "butt" :
                 op.cap === Vetra.RoundCap ? "round" : "square",
        "join" => op.join === Vetra.MiterJoin ? "miter" :
                  op.join === Vetra.RoundJoin ? "round" : "bevel",
        "miterLimit" => op.miterLimit,
        "dashes" => Float32[op.dashes...],
        "dashOffset" => op.dashOffset))
end
function wire_command(op::ClearOp)
    # the clear rect stays FRACTIONAL — no Int truncation at the wire
    WireCommand("clear", Dict(
        "rect" => _rect4f(op.r), "transform" => _mat9(op.tform),
        "clips" => [WireClip(collect(c.path.commands), WIND_NAMES[c.winding]) for c in op.clips]))
end
function wire_command(op::DrawImageOp)
    WireCommand("image", Dict(
        "assetId" => op.assetId,
        # revision 6: the captured Rect as-is (fractional) — truncation
        # is the legacy 8-arg overload only, applied at the call boundary
        "srcRect" => _rect4f(op.srcRect),
        "destRect" => _rect4f(op.destRect),    # fractional
        "transform" => _mat9(op.tform),
        "sampling" => Dict("filter" => string(op.sampling.filter),
                           "edge" => string(op.sampling.edge)),
        "composition" => COMP_NAMES[op.composition],
        # revision 7 numeric policy: the declared Float32 is preserved
        # (the revision-6 mapping widened this one field to Float64,
        # 0.1f0 ⇒ 0.10000000149011612, +16 canonical bytes)
        "opacity" => op.opacity,
        "clips" => [WireClip(collect(c.path.commands), WIND_NAMES[c.winding]) for c in op.clips]))
end
function wire_command(op::TextOp)
    WireCommand("text", Dict(
        "glyphs" => [WireGlyph(collect(g.outline.commands), _mat9(g.tform))
                     for g in op.glyphs],
        "paint" => wire_paint(op.paint),
        "transform" => _mat9(op.tform),
        "composition" => COMP_NAMES[op.composition],
        "clips" => [WireClip(collect(c.path.commands), WIND_NAMES[c.winding]) for c in op.clips]))
end
function wire_command(op::EffectOp)
    WireCommand("effect", Dict(
        "kind" => string(op.kind),
        # revision 6 numeric policy: Float32 preserved; regions are
        # fractional (the core's conservative bounds, no Int conversion)
        "radius" => op.radius,
        "offset" => (op.offset.x, op.offset.y),
        "color" => (Int(op.color.r), Int(op.color.g), Int(op.color.b)),
        "opacity" => op.opacity,
        "inRegion" => _rect4f(op.inRegion),
        "outRegion" => _rect4f(op.outRegion),
        "transform" => _mat9(op.tform),
        "clips" => [WireClip(collect(c.path.commands), WIND_NAMES[c.winding]) for c in op.clips]))
end
function wire_command(op::GroupStartOp)
    WireCommand("group-start", Dict(
        "opacity" => op.opacity,
        "composition" => COMP_NAMES[op.composition],
        "clips" => [WireClip(collect(c.path.commands), WIND_NAMES[c.winding]) for c in op.clips]))
end
function wire_command(op::GroupEndOp)
    WireCommand("group-end", Dict(
        "clips" => [WireClip(collect(c.path.commands), WIND_NAMES[c.winding]) for c in op.clips]))
end
"""§11 boundary rule: core assets are premul RGBA8; image assets cross the
wire as STRAIGHT — converted at serialization time with the §7 formula."""
function to_wire_asset(a::CanvasAsset)::WireAsset
    out = Vector{UInt8}(undef, length(a.data))
    i = 1
    for n in 1:(a.width * a.height)
        r, g, b, al = a.data[i], a.data[i+1], a.data[i+2], a.data[i+3]
        out[i], out[i+1], out[i+2], out[i+3] =
            straight_byte(r, al), straight_byte(g, al),
            straight_byte(b, al), al
        i += 4
    end
    WireAsset(a.width, a.height, "rgba8-straight", out)
end
function wire_command(op::RasterFallbackOp)
    WireCommand("fallback", Dict(
        "feature" => op.feature,
        "reason" => op.reason,
        "scope" => string(op.scope),
        "original" => WireOriginal([wire_command(o) for o in op.original.ops],
                                   Dict(id => to_wire_asset(a)
                                        for (id, a) in op.original.assets)),
        "clips" => [WireClip(collect(c.path.commands), WIND_NAMES[c.winding]) for c in op.clips]))
end

# --- §11 canonical record serialization (fixed field order) ---
function _canon_field(tag, f, v)
    if f == "paint" && v isa WirePaint
        return [ ("kind", v.kind),
                 ("color", v.color === nothing ? nothing :
                     [v.color[1], v.color[2], v.color[3], v.color[4]]),
                 ("opacity", v.opacity), ("artistic", v.artistic),
                 ("assetId", v.assetId),
                 ("imageTransform", v.imageTransform === nothing ? nothing :
                     collect(v.imageTransform)),
                 ("handles", v.handles === nothing ? nothing :
                     [collect(h) for h in v.handles]),
                 ("stops", v.stops === nothing ? nothing :
                     [collect(s) for s in v.stops]) ]
    elseif f == "clips" && v isa Vector{WireClip}
        return [ [ ("path", collect(c.path)), ("winding", c.winding) ]
                 for c in v ]
    elseif f == "glyphs" && v isa Vector{WireGlyph}
        return [ [ ("outline", collect(g.outline)),
                   ("transform", collect(g.transform)) ] for g in v ]
    elseif f == "sampling" && v isa Dict
        return [ ("filter", v["filter"]), ("edge", v["edge"]) ]
    elseif f == "original" && v isa WireOriginal
        return [ ("ops", [canon_command(c) for c in v.ops]),
                 ("assets", [(string(k), canon_asset(v.assets[k]))
                              for k in sort(collect(keys(v.assets)))])]
    end
    return v
end
function canon_command(c::WireCommand)
    pairs = Vector{Tuple{String, Any}}(undef, 1)
    pairs[1] = ("op", c.tag)
    for f in WIRE_TAG_FIELDS[c.tag]
        push!(pairs, (f, _canon_field(c.tag, f, c.fields[f])))
    end
    return pairs
end
function canon_asset(a::WireAsset)
    [ ("kind", "image"), ("width", a.width), ("height", a.height),
      ("encoding", a.encoding), ("data", base64encode(a.data)) ]
end

"""§11 schema validation: tag in vocabulary, exactly the required fields."""
function validate_wire_command!(cmd::WireCommand)
    haskey(WIRE_TAG_FIELDS, cmd.tag) ||
        throw(ArgumentError("unknown wire op tag $(cmd.tag)"))
    for f in WIRE_TAG_FIELDS[cmd.tag]
        haskey(cmd.fields, f) || throw(ArgumentError("wire record $(cmd.tag) missing field $f"))
    end
    for f in keys(cmd.fields)
        f in WIRE_TAG_FIELDS[cmd.tag] || throw(ArgumentError("wire record $(cmd.tag) has extra field $f"))
    end
    p = get(cmd.fields, "paint", nothing)
    p isa WirePaint && validate_wire_paint!(p)
    return nothing
end
"""§11 paint record consistency: kind ↔ field presence (solid: color set,
assetId/imageTransform/handles/stops null; image/tiled: assetId +
imageTransform set, color/handles/stops null; gradients: handles+stops
set, assetId null)."""
function validate_wire_paint!(p::WirePaint)
    if p.kind == "solid"
        p.color === nothing && throw(ArgumentError("solid paint without color"))
        (p.assetId !== nothing || p.imageTransform !== nothing ||
         p.handles !== nothing || p.stops !== nothing) &&
            throw(ArgumentError("solid paint with image/gradient fields"))
    elseif p.kind == "image" || p.kind == "tiled-image"
        p.assetId === nothing &&
            throw(ArgumentError("$(p.kind) paint without assetId"))
        p.imageTransform === nothing &&
            throw(ArgumentError("$(p.kind) paint without imageTransform"))
        (p.color !== nothing || p.handles !== nothing || p.stops !== nothing) &&
            throw(ArgumentError("$(p.kind) paint with solid/gradient fields"))
    elseif p.kind in ("linear-gradient", "radial-gradient", "angular-gradient")
        (p.handles === nothing || p.stops === nothing) &&
            throw(ArgumentError("$(p.kind) paint without handles/stops"))
        (p.color !== nothing || p.assetId !== nothing ||
         p.imageTransform !== nothing) &&
            throw(ArgumentError("$(p.kind) paint with solid/image fields"))
    else
        throw(ArgumentError("unknown paint kind $(p.kind)"))
    end
    return nothing
end


# ===========================================================================
# 9. Browser document record machine — doc §11 (namespace/accounting)
# ===========================================================================

mutable struct BrowserDoc
    scope::String
    provider::String
    profile::String
    generation::Int
    session::Int
    device_scale::Float32
    width::Int
    height::Int
    assets::Dict{Int, WireAsset}
    commands::Vector{WireCommand}
    next_id::Int
end
function doc_new(scope::String, w::Int, h::Int,
                 initial::Union{CanvasAsset, Nothing};
                 provider = "vetra/browser/canvas2d",
                 profile = "portable-2d",
                 device_scale = 1f0,
                 next_id = 1)
    # revision 7: the document machine never invents ids — the initial
    # import is keyed by its SUPPLIED captured id (the core namespace),
    # and the next-capture counter is SEPARATE state with the explicit
    # already-reserved-ID convention: next_id is past every id already
    # reserved (the initial's id is already reserved — the counter is
    # never advanced again for it)
    d = BrowserDoc(scope, provider, profile, 1, 1, device_scale, w, h,
                   Dict{Int, WireAsset}(), WireCommand[], next_id)
    initial === nothing && return d
    initial.id ≥ d.next_id &&
        throw(ArgumentError(
            "initial capture id $(initial.id) is not yet reserved (next_id $(d.next_id))"))
    d.assets[initial.id] = to_wire_asset(initial)
    d.commands = WireCommand[
        WireCommand("set-pixels", Dict("assetId" => initial.id,
                                       "rect" => [0, 0, w, h]))]
    return d   # counter unchanged — the id is already reserved
end
"""The retained document's canonical serialization (§11 — the one byte
authority). Asset map keys are the decimal capture id in ascending order."""
function canonical_document(d::BrowserDoc)::String
    canon_json([
        ("schema", "vetra.canvas.v1"), ("provider", d.provider),
        ("profile", d.profile), ("generation", d.generation),
        ("session", d.session), ("scope", d.scope),
        ("size", [d.width, d.height]), ("deviceScale", d.device_scale),
        ("assets", [(string(k), canon_asset(d.assets[k]))
                    for k in sort(collect(keys(d.assets)))]),
        ("commands", [canon_command(c) for c in d.commands]),
        ("fallbacks", []),
    ])
end
doc_bytes(d::BrowserDoc)::Int = ncodeunits(canonical_document(d))
doc_ops(d::BrowserDoc)::Int = length(d.commands)

"""§11 admission: the ACTUAL canonical UTF-8 length must fit both limits.
The bound applies at construction (initial import) and before every flush
mutation — on exceed the named bound is returned and the document is left
unmutated."""
function doc_admit(d::BrowserDoc, max_bytes::Int, max_ops::Int)
    doc_bytes(d) > max_bytes && return "payload-max-bytes"
    doc_ops(d) > max_ops && return "payload-max-ops"
    return nothing
end
function doc_admit!(d::BrowserDoc, max_bytes::Int, max_ops::Int)
    bound = doc_admit(d, max_bytes, max_ops)
    bound !== nothing &&
        throw(ArgumentError("payload exceeds $bound: $(doc_bytes(d)) bytes, $(doc_ops(d)) ops"))
    return nothing
end
"""Pre-mutation flush admission: serialize the CANDIDATE document (retained
+ new entry) and require it to fit both limits; the document is mutated
only after admission passes. Revision 6: the asset is keyed by the
CAPTURED id the command carries — the document machine never invents
ids (a command whose asset id is absent from its record set is
unresolvable and rejected)."""
function doc_add!(d::BrowserDoc, cmd::WireCommand,
                  asset::Union{WireAsset, Nothing},
                  max_bytes::Int, max_ops::Int)
    aid = asset === nothing ? nothing : cmd.fields["assetId"]
    cand = BrowserDoc(d.scope, d.provider, d.profile, d.generation, d.session,
                      d.device_scale, d.width, d.height,
                      Dict{Int, WireAsset}(d.assets), Vector{WireCommand}(d.commands),
                      d.next_id)
    if asset !== nothing
        cand.assets[aid] = asset
    end
    push!(cand.commands, cmd)
    doc_admit!(cand, max_bytes, max_ops)
    if asset !== nothing
        d.assets[aid] = asset
    end
    push!(d.commands, cmd)
    return d
end
"""Every command that references an asset must resolve it against the
retained asset map (the wire consumer's integrity check)."""
function doc_check!(d::BrowserDoc)
    for cmd in d.commands
        aid = get(cmd.fields, "assetId", nothing)
        aid === nothing && continue
        haskey(d.assets, aid) ||
            throw(ArgumentError("document command references missing asset id $aid"))
    end
    return nothing
end
"""§11 draw capture: the core assigns the fresh capture id from the one
namespace and advances it — the command is then built with that captured
id (the document machine itself never invents ids)."""
function doc_capture!(d::BrowserDoc)::Int
    id = d.next_id
    d.next_id += 1
    return id
end
"""§11 upload capture + wire set-pixels: the core captures the region as a
CanvasAsset (fresh id from the one namespace) and the dispatch carries that
asset — the id is what the wire record references."""
function doc_upload!(d::BrowserDoc, src::Vector{UInt8}, region::Vetra.Rect,
                     max_bytes::Int, max_ops::Int)
    # the core capture assigns the fresh id from the one namespace
    asset = CanvasAsset(doc_capture!(d), Int(region.w), Int(region.h), copy(src))
    cmd = WireCommand("set-pixels",
                      Dict("assetId" => asset.id,
                           "rect" => _rect4i(region)))
    doc_add!(d, cmd, to_wire_asset(asset), max_bytes, max_ops)
    return (asset, cmd)
end
"""§11 destructive resize: the retained document is cleared, the device
generation bumps, and the new document starts from the new initial —
the core capture namespace CONTINUES (revision 6: the v5 helper reset
it via doc_new, contrary to the never-reused core namespace)."""
function doc_resize(d::BrowserDoc, w::Int, h::Int,
                    initial::Union{CanvasAsset, Nothing})
    # revision 7: the new document continues the SEPARATE next-capture
    # counter (namespace continuity); the initial import, when present,
    # is keyed by its own captured id — never re-reserved
    d2 = doc_new(d.scope, w, h, initial;
                 provider = d.provider, profile = d.profile,
                 device_scale = d.device_scale,
                 next_id = d.next_id)
    d2.session = d.session
    d2.generation = d.generation + 1
    return d2
end
const _BROWSER_NEXT = Ref(0)
function fresh_scope()
    _BROWSER_NEXT.x += 1
    return "canvas-$(_BROWSER_NEXT.x)"
end

# ===========================================================================
# 9c. Owned CanvasRecording record machine — doc §14 (revision 6)
# ===========================================================================

"""The owned recording value (doc §14 revision 6): normalized, sealed
(group-balanced) ops, the deep-copied assets they reference, and the
logical canvas size at capture time. The revision-5 capture through
flush! + the batch_* accessors is retracted: flush! returns an opaque
submission, and submit! is the provider protocol, not a frontend replay
route (the batch_* accessors serve the provider side only)."""
struct CanvasRecording
    ops::Vector{CanvasOp}
    assets::Dict{Int, CanvasAsset}
    size::Vetra.Vec2
end

"""record_canvas seal (doc §14 revision 7): group balance is validated
with the same rule as flush! (the named ArgumentError). Seal ownership
boundary: the ops arrive ALREADY OWNED — §6 ownership makes every op's
path/clip/paint the op's own deep snapshot at record time, so the seal
does not re-snapshot ops; it owns its op container (the caller's vector
is not aliased) and deep-copies only the asset bytes the ops reference
(draw AND image/tiled paint id classes); extent = the callback's ops,
not canvas history."""
function record_seal(ops::Vector{CanvasOp}, assets::Dict{Int, CanvasAsset},
                     w::Int, h::Int)::CanvasRecording
    depth = 0
    for op in ops
        if op isa GroupStartOp
            depth += 1
        elseif op isa GroupEndOp
            depth -= 1
        end
        depth < 0 && throw(ArgumentError("unbalanced save_layer at record"))
    end
    depth == 0 || throw(ArgumentError("unbalanced save_layer at record"))
    owned = Dict{Int, CanvasAsset}()
    for (k, v) in assets
        owned[k] = CanvasAsset(k, v.width, v.height, copy(v.data))
    end
    for op in ops
        if op isa DrawImageOp
            haskey(owned, op.assetId) ||
                throw(ArgumentError(
                    "recording op references uncaptured asset $(op.assetId)"))
        elseif op isa Union{FillOp, StrokeOp, TextOp} &&
                op.paint.imageAssetId != 0
            haskey(owned, op.paint.imageAssetId) ||
                throw(ArgumentError(
                    "recording op references uncaptured asset " *
                    "$(op.paint.imageAssetId)"))
        end
    end
    return CanvasRecording(copy(ops), owned, Vetra.Vec2(w, h))
end

"""draw_recording! id remap (doc §14 revision 7): the ONE 1:1 fresh
target-scoped remap over the sorted recording ids — it covers BOTH
reference classes (DrawImageOp.assetId and image/tiled
OwnedPaint.imageAssetId); recording ids are never the target's ids.
Decision record only — the replayed ops themselves are R020's (⏳)."""
function recording_remap(rec::CanvasRecording, next_id::Int)::Dict{Int,Int}
    ids = sort(collect(keys(rec.assets)))
    return Dict{Int, Int}(k => next_id + i - 1 for (i, k) in enumerate(ids))
end
"""draw_recording! placement math (doc §14 — the one authority):
mapping = translate(dest) * scale(dest / recording.size) under the
ACTUAL Mat3 convention (the leftmost factor applies last to a point);
per-op tform composes as ambient * mapping * op.tform; recorded clip
geometry maps under ambient * mapping EXACTLY ONCE (clip paths carry no
per-op tform). Pure matrix arithmetic — no op construction, no replay
engine (the revision-6 multi-op visitor is retired: it is not boundary
evidence, and multi-op replay execution is a normative trace, ⏳ R020)."""
function recording_placement(rec_size::Vetra.Vec2, dest::Vetra.Rect,
                             ambient::Vetra.Mat3 = Vetra.mat3())
    mapping = Vetra.translate(Vetra.Vec2(dest.x, dest.y)) *
              Vetra.scale(Vetra.Vec2(dest.w / rec_size.x, dest.h / rec_size.y))
    return (mapping, ambient * mapping)
end

"""Ordered clip-list equality for the wrapper rule (path + winding)."""
function _clips_equal(a::Vector{ClipScope}, b::Vector{ClipScope})::Bool
    length(a) == length(b) || return false
    return all(i -> a[i].path.commands == b[i].path.commands &&
                        a[i].path.start == b[i].path.start &&
                        a[i].path.at == b[i].path.at &&
                        a[i].winding === b[i].winding, 1:length(a))
end
"""The legacy Picture adapter's CONSERVATIVE LOWERING DECISION PROCEDURE
(doc §14 revision 7): disjoint and complete over op kind × composition ×
artistic × paint kind × required wrapper — first matching rule wins;
raises the named ArgumentError (op index + missing legacy dimension)
for every non-representable combination. A DECISION PROCEDURE, not an
executed converter — it emits no Picture (the adapter itself is
⏳ R020); the rejection rows rest on the actual-recorder 1×1 reproductions
in the checks. Every rejection is a legacy-conversion limit, not a
recording limit — draw_recording! still replays all of them. Returns
the count of normalized ops admitted."""
function lowering_admit!(rec::CanvasRecording)::Int
    n = 0
    group_entry = Vector{ClipScope}[]   # entry clip list of each open group
    for (i, op) in enumerate(rec.ops)
        if op isa GroupStartOp
            op.composition !== SourceOver && throw(ArgumentError(
                "legacy lowering rejects op $i: group composition " *
                "$(COMP_NAMES[op.composition]) ≠ source-over (GroupStart has no composition field)"))
            push!(group_entry, op.clips)
        elseif op isa GroupEndOp
            pop!(group_entry)
        else
            # wrapper rule: inside a group the op's ambient clip list
            # must equal the entry list — a clip set inside the group is
            # not representable (the legacy group mask applies to the
            # whole group)
            if !isempty(group_entry)
                _clips_equal(op.clips, group_entry[end]) ||
                    throw(ArgumentError(
                        "legacy lowering rejects op $i: clip set inside the legacy group (ambient $(length(op.clips)) ≠ entry $(length(group_entry[end])) clips)"))
            end
            wrapped = isempty(group_entry) && !isempty(op.clips)
            if op isa EffectOp
                throw(ArgumentError(
                    "legacy lowering rejects op $i: $(op.kind) has no legacy counterpart (no EffectOp in the vocabulary)"))
            elseif op isa ClearOp
                !isempty(op.clips) && throw(ArgumentError(
                    "legacy lowering rejects op $i: clipped clear (legacy ClearOp has no clip field; the actual recorder never wraps clear)"))
            elseif op isa DrawImageOp
                op.composition !== SourceOver && throw(ArgumentError(
                    "legacy lowering rejects op $i: image composition $(COMP_NAMES[op.composition]) ≠ source-over (no composition field)"))
                op.sampling !== LinearSampling && throw(ArgumentError(
                    "legacy lowering rejects op $i: image sampling ($(op.sampling.filter), $(op.sampling.edge)) ≠ (linear, clamp) (no sampling field)"))
                !all(isinteger, (op.srcRect.x, op.srcRect.y,
                                 op.srcRect.w, op.srcRect.h)) &&
                    throw(ArgumentError(
                        "legacy lowering rejects op $i: fractional image source rect (legacy source region is an integer-truncated subImage)"))
            else
                # FillOp / StrokeOp / TextOp (text = glyph-outline fills)
                paint = op.paint
                if op isa StrokeOp
                    paint.kind !== Vetra.SolidPaint && throw(ArgumentError(
                        "legacy lowering rejects op $i: non-solid stroke paint (the legacy record boundary accepts solid stroke paints only)"))
                    op.dashOffset != 0f0 && throw(ArgumentError(
                        "legacy lowering rejects op $i: dash phase (dashOffset ≠ 0) has no legacy counterpart"))
                end
                if op isa FillOp && paint.kind === Vetra.TiledImagePaint
                    throw(ArgumentError(
                        "legacy lowering rejects op $i: tiled image fill (the actual recorder: TiledImagePaint fills are not recordable)"))
                end
                comp = op.composition
                if comp !== SourceOver && comp !== Copy
                    throw(ArgumentError(
                        "legacy lowering rejects op $i: composition $(COMP_NAMES[comp]) has no legacy counterpart (no composition field)"))
                end
                if comp === Copy
                    paint.artistic !== Vetra.NormalBlend && throw(ArgumentError(
                        "legacy lowering rejects op $i: Copy with an artistic paint (one legacy Paint.blendMode field)"))
                    paint.opacity == 0f0 && throw(ArgumentError(
                        "legacy lowering rejects op $i: zero-opacity Copy (the legacy fill/stroke pipeline early-returns on zero Paint.opacity — the actual Picture leaves the destination where normalized Copy must clear)"))
                    wrapped && throw(ArgumentError(
                        "legacy lowering rejects op $i: Copy under the implicit legacy clip wrapper is not pixel-preserving (the Normal scratch composite loses the Copy operator)"))
                else   # source-over
                    paint.artistic !== Vetra.NormalBlend && wrapped &&
                        throw(ArgumentError(
                            "legacy lowering rejects op $i: artistic blend under the implicit legacy clip wrapper is not pixel-preserving (the blend runs against the transparent scratch, not the destination)"))
                end
            end
        end
        n += 1
    end
    return n
end

# ===========================================================================
# 9b. Upload validation + adapter-dest gate — doc §7 (pre-dispatch rules)
# ===========================================================================

"""Pre-dispatch upload validation: source/region/shape are checked before any
provider call and before any target modification — an invalid upload leaves
the target pixel-for-pixel unchanged (§7)."""
function upload_validate(n_source::Int, target_pw::Int, target_ph::Int,
                         region_w::Int, region_h::Int;
                         x::Int = 0, y::Int = 0)
    (x ≥ 0 && y ≥ 0 && x + region_w ≤ target_pw && y + region_h ≤ target_ph) ||
        throw(ArgumentError("upload region exceeds physical target"))
    n_source == region_w * region_h ||
        throw(ArgumentError(
            "upload source holds $n_source pixels, region needs " *
            "$(region_w * region_h)"))
    return nothing
end
upload_validate_float(v::Real) = quant_channel(v)

"""§7 in-place adapter output gate: writable storage required, checked before
any read/write/alloc call."""
struct StorageReadonly <: StorageAdapter end
storage_descriptor(::StorageReadonly) =
    StorageDescriptor(Vetra.ColorRGBX, PixelLayout(2, 2, 4, true, true, true),
                      false, true)
adapter_dest_validate(desc::StorageDescriptor) =
    desc.writable || throw(ArgumentError("borrow requires writable storage"))

"""§7 single commit rule (record boundary): two phases. Phase 1 validates
the whole source before any store (failure ⇒ destination untouched).
Phase 2 is plain indexed stores — NOT a transaction: a fault after the
first store raises TransferError(:partial) unless the destination
explicitly guarantees atomic commit (then :unwritten + rollback)."""
mutable struct CommitDest
    values::Vector{Int}
    backup::Vector{Int}
    atomic::Bool
    fail_at::Int
    stores::Int
    function CommitDest(values::Vector{Int}; atomic::Bool = false,
                        fail_at::Int = 0)
        new(copy(values), copy(values), atomic, fail_at, 0)
    end
end
function commit_write!(d::CommitDest, vals::Vector{Int})
    any(v -> !(0 ≤ v ≤ 255), vals) &&
        throw(ArgumentError("commit validation failed: channel outside 0..255"))
    for (i, v) in enumerate(vals)
        d.stores += 1
        d.fail_at == i && throw(ErrorException("commit fault after first store"))
        d.values[i] = v
    end
    return nothing
end
function commit_or_report!(d::CommitDest, vals::Vector{Int})
    try
        commit_write!(d, vals)
    catch e
        if e isa ErrorException
            if d.atomic
                d.values .= d.backup   # the destination guarantees rollback
                throw(TransferError(:unwritten, "atomic commit rolled back"))
            end
            throw(TransferError(:partial, "indexed commit is not a transaction"))
        end
        rethrow()                       # phase-1 validation errors
    end
end

# ===========================================================================
# 9c. Normative consumer trace — doc §13 (record machine)
# ===========================================================================

mutable struct RecordingAdapter <: StorageAdapter
    matrix::Matrix{Vetra.ColorRGBX}
    writable::Bool
    calls::Vector{Symbol}
    function RecordingAdapter(m::Matrix{Vetra.ColorRGBX};
                              writable::Bool = true)
        new(m, writable, Symbol[])
    end
end
function storage_descriptor(s::RecordingAdapter)
    push!(s.calls, :descriptor)
    h, w = size(s.matrix)
    StorageDescriptor(Vetra.ColorRGBX,
                      PixelLayout(w, h, 4, true, true, true),
                      s.writable, true)
end
function storage_read(s::RecordingAdapter, r::Vetra.Rect)
    push!(s.calls, :read)
    data = UInt8[]
    for y in 0:Int(r.h) - 1, x in 0:Int(r.w) - 1
        p = s.matrix[Int(r.y) + y + 1, Int(r.x) + x + 1]
        append!(data, (p.r, p.g, p.b, p.a))
    end
    CanvasAsset(0, Int(r.w), Int(r.h), data)
end
function storage_write!(s::RecordingAdapter, r::Vetra.Rect, data::Vector{UInt8})
    push!(s.calls, :write)
    for y in 0:Int(r.h) - 1, x in 0:Int(r.w) - 1
        i = 4 * (y * Int(r.w) + x)
        s.matrix[Int(r.y) + y + 1, Int(r.x) + x + 1] =
            Vetra.ColorRGBX(data[i+1], data[i+2], data[i+3], data[i+4])
    end
    return nothing
end
function storage_alloc(p::RecordingAdapter, ::Type{T},
                       dims::Tuple{Int, Int}) where {T<:StorageAdapter}
    push!(p.calls, :alloc)
    T !== RecordingAdapter &&
        throw(ArgumentError("recording storage_alloc returns the recording type"))
    w, h = dims
    RecordingAdapter(Matrix{Vetra.ColorRGBX}(undef, h, w))
end

"""The canvas side of the consumer trace: the target's public
flush/wait boundary + synchronized read_pixels (recorded)."""
mutable struct ConsumerTarget
    pw::Int
    ph::Int
    bytes::Vector{UInt8}
    ops::Vector{Symbol}
    function ConsumerTarget(pw::Int, ph::Int)
        new(pw, ph, UInt8[n % 256 + 1 for n in 0:(4 * pw * ph - 1)],
            Symbol[])
    end
end
flush_wait!(t::ConsumerTarget) = (push!(t.ops, :flush); nothing)
"""read_pixels returns OWNED premul RGBA8 bytes (a copy — never the
target's storage)."""
function read_pixels(t::ConsumerTarget)
    push!(t.ops, :read)
    return copy(t.bytes)
end

"""§13 consumer route (normative trace, in-place): descriptor →
validation (writable + physical dims; failure ⇒ ZERO read/write/alloc
calls) → flush+wait → read_pixels → owned premul RGBA8 for the
zero-based full physical region → storage_write!. The adapter owns the
conversion to its underlying layout; the core sends canonical premul
bytes only."""
function consumer_snapshot!(s::RecordingAdapter, t::ConsumerTarget)
    desc = storage_descriptor(s)
    desc.writable ||
        throw(ArgumentError("snapshot! requires writable storage"))
    (desc.layout.width, desc.layout.height) == (t.pw, t.ph) ||
        throw(ArgumentError(
            "storage is $(desc.layout.width)×$(desc.layout.height), " *
            "canvas is $(t.pw)×$(t.ph)"))
    flush_wait!(t)
    bytes = read_pixels(t)
    storage_write!(s, Vetra.rect(0f0, 0f0, Float32(t.pw), Float32(t.ph)), bytes)
    return nothing
end
"""§13 consumer route (normative trace, allocating): descriptor →
flush+wait → read_pixels → storage_alloc(s, typeof(s), (pw, ph)) (the
explicit type AND dimensions) → fill the returned adapter through its
own public storage_descriptor + storage_write! → return it."""
function consumer_snapshot_alloc(s::RecordingAdapter, t::ConsumerTarget)
    storage_descriptor(s)
    flush_wait!(t)
    bytes = read_pixels(t)
    out = storage_alloc(s, typeof(s), (t.pw, t.ph))
    storage_descriptor(out)
    storage_write!(out, Vetra.rect(0f0, 0f0, Float32(t.pw), Float32(t.ph)), bytes)
    return out
end

# ===========================================================================
# 10. Checks — executable boundary evidence only (§19 "✓" cells)
# ===========================================================================

function caught(f)
    try
        f()
        return nothing
    catch e
        return e
    end
end

@testset "R010 revision 9: contract boundary check" begin

    # ------------------------------------------------------------------
    @testset "G1 protocol dispatch + submission tracking [dispatch]" begin
        D = DemoProvider
        b = D.DeferredBackend()
        caps = backend_capabilities(b)
        @test caps.protocol == 1 && caps.provider == "demo/deferred"
        @test caps.features["draw.fill"].level === NativeCapability
        @test bind_target!(b, CanvasTargetSpec(2, 1, 2f0, 4, 2, nothing)) ==
            StorageReport(:owned, :row, false)
        @test b.spec !== nothing
        init = CanvasAsset(0, 2, 1, UInt8[255, 0, 0, 255, 0, 255, 0, 255])
        @test bind_target!(b, CanvasTargetSpec(2, 1, 2f0, 4, 2, init)).copied ==
            true
        path = Vetra.newPath(); Vetra.rect(path, 0f0, 0f0, 1f0, 1f0)
        op = FillOp(path,
                    OwnedPaint(Vetra.SolidPaint, Vetra.rgba(255, 0, 0, 255),
                               1f0, Vetra.NormalBlend, 0, Vetra.mat3(),
                               Vetra.Vec2[], Vetra.ColorStop[]),
                    Vetra.mat3(), Vetra.NonZero, ClipScope[], SourceOver)
        batch = CommandBatch([op], Dict(0 => CanvasAsset(0, 1, 1,
                                                         UInt8[255, 0, 0, 255])),
                             Vetra.Vec2(2, 1), 2f0)
        sub = submit!(b, batch)
        @test sub isa D.DeferredSubmission
        @test wait(sub) === nothing
        @test sub.waited == 1                 # executed exactly once
        @test wait(sub) === nothing
        @test sub.waited == 1                 # idempotent

        # field-less external provider through the five methods only
        zf = D.ZeroFieldBackend()
        @test isempty(fieldnames(D.ZeroFieldBackend))
        @test backend_capabilities(zf).provider == "demo/zero-field"
        @test bind_target!(zf, CanvasTargetSpec(1, 1, 1f0, 1, 1, nothing)).mode ==
            :owned
        @test wait(submit!(zf, batch)) === nothing
        close(zf)

        # §8.1 revision 8: the public flush! shape returns the TRACKED
        # frontend handle; direct wait(handle) retires through the SAME
        # single completion route as wait(c), and the provider releases
        # its batch ROOTS at completion (verified by the actual
        # reference — the v7 `released` flag is gone)
        tr = SubmissionTracker(b)
        fh1 = tracker_submit(tr, batch)
        fh2 = tracker_submit(tr, batch)
        @test length(tr.subs) == 2
        @test tr.subs[1].state === :pending
        @test length(b.submissions) == 2     # the provider tracks both
        wait(fh1)                            # direct wait(handle)
        @test length(tr.subs) == 1           # retired IMMEDIATELY (not
                                             # deferred to wait-all)
        @test fh1.provider.waited == 1       # forwarded exactly once
        @test fh1.provider.batch === nothing # provider root RELEASED at
                                             # completion
        @test length(b.submissions) == 1     # provider dropped fh1's
                                             # handle; the pending one
                                             # is kept
        tracker_wait_all(tr)                 # wait(c) — the same route
        @test isempty(tr.subs)               # BOTH retired on completion
        @test fh2.provider.waited == 1
        @test fh2.provider.batch === nothing # the EXTERNALLY kept
                                             # completed handle holds no
                                             # batch (scalars only)
        @test isempty(b.submissions)         # provider tracking empty

        # no-op is untracked, inert, and never implies earlier completion
        b2 = D.DeferredBackend()
        tr2 = SubmissionTracker(b2)
        pending = tracker_submit(tr2, batch)
        noop = tracker_noop(tr2)
        @test noop isa CanvasNoopSubmission
        @test length(tr2.subs) == 1          # the no-op is untracked
        wait(noop)                           # inert: no provider, no state
        @test length(tr2.subs) == 1
        @test pending.provider.state === :pending  # not completed by it
        wait(pending)
        @test isempty(tr2.subs)              # retired; nothing rooted
        @test pending.provider.batch === nothing

        # sticky PROVIDER failure: retained, re-raised by BOTH wait
        # forms, close never succeeds past it; the failed handle KEEPS
        # its batch (the provider's work did not complete)
        b3 = D.DeferredBackend()
        tr3 = SubmissionTracker(b3)
        good = tracker_submit(tr3, batch)    # good work first
        b3.fail_next_wait = true
        bad = tracker_submit(tr3, batch)     # this one fails at wait
        e1 = caught(() -> wait(bad))         # direct wait re-raises
        @test e1 isa BackendSubmitError
        @test bad.state === :failed && bad.error === e1
        @test bad.provider.batch !== nothing # provider retention duty
        wait(good)                           # the success retires
        @test length(tr3.subs) == 1          # failed RETAINED; the
                                             # completed entry retired
        @test tr3.subs[1].state === :failed
        @test length(b3.submissions) == 1    # provider drops completed,
                                             # keeps the failed handle
        tracker_submit(tr3, batch)           # new work after the failure
        @test length(b3.submissions) == 2    # …and the new pending one
        e2 = caught(() -> tracker_wait_all(tr3))  # wait(c) re-waits the
        @test e2 isa BackendSubmitError       # failed entry (sticky)
        @test sprint(showerror, e1) == sprint(showerror, e2)
        e3 = caught(() -> tracker_close(tr3))
        @test e3 isa BackendSubmitError
        @test b3.close_calls == 0            # provider never closed
        @test tr3.closed === false           # stays open
        @test caught(() -> tracker_close(tr3)) isa BackendSubmitError
        # the v7 defect is closed: 16 completed one-pixel frames, each
        # waited by its DIRECT handle — zero core entries and zero
        # REACHABLE provider batch roots (v7 asserted a boolean while
        # the spy rooted every batch; now the references are checked)
        b4 = D.DeferredBackend()
        tr4 = SubmissionTracker(b4)
        for i in 1:16
            fh = tracker_submit(tr4, batch)
            wait(fh)                         # wait(flush!(c)) shape
            @test isempty(tr4.subs)          # no core accumulation
            @test isempty(b4.submissions)    # no provider accumulation
        end
        fh16 = TrackedSubmission(
            submit!(b4, batch), tr4, nothing)   # externally kept
        wait(fh16)
        @test fh16.provider.batch === nothing  # completed handle, kept by
                                               # the caller, holds no batch
        @test b4.close_calls == 0            # (not yet closed)
        tracker_close(tr4)
        @test tr4.closed && b4.close_calls == 1
        @test isempty(b4.submissions)

        # STAGED transfer failure (revision 8): the provider work
        # COMPLETED, then the core staged writeback fails — the original
        # error is sticky on the tracked handle, the action is never
        # re-run, the entry is never completed or retired, and close
        # re-raises. The already-released provider roots are NOT
        # retained — only the core staging is.
        b5 = D.DeferredBackend()
        tr5 = SubmissionTracker(b5)
        dest = CommitDest([7, 7, 7]; fail_at = 2)
        fh5 = tracker_track(tr5, submit!(b5, batch),
                            () -> commit_or_report!(dest, [1, 2, 3]))
        sp = caught(() -> wait(fh5))
        @test sp isa TransferError && sp.status === :partial
        @test dest.values == [1, 7, 7]       # the partial stores remain
        @test dest.stores == 2
        @test fh5.state === :failed && fh5.error === sp
        @test fh5.staged_done === false      # the success flag is set
                                             # ONLY after success
        @test fh5.staged !== nothing         # the core staging is RETAINED
        @test fh5.provider.state === :complete
        @test fh5.provider.batch === nothing # provider work finished:
                                             # its roots were released
        @test isempty(b5.submissions)
        @test length(tr5.subs) == 1 && only(tr5.subs) === fh5
        @test caught(() -> wait(fh5)) === sp # sticky — no re-run
        @test dest.stores == 2 && dest.values == [1, 7, 7]
        @test caught(() -> tracker_wait_all(tr5)) === sp
        @test dest.stores == 2               # wait-all re-waits, it does
                                             # not re-store
        @test caught(() -> tracker_close(tr5)) === sp
        @test tr5.closed === false && b5.close_calls == 0

        # the atomic-destination variant reports :unwritten (rollback)
        b6 = D.DeferredBackend()
        tr6 = SubmissionTracker(b6)
        dest6 = CommitDest([7, 7, 7]; atomic = true, fail_at = 2)
        fh6 = tracker_track(tr6, submit!(b6, batch),
                            () -> commit_or_report!(dest6, [1, 2, 3]))
        un = caught(() -> wait(fh6))
        @test un isa TransferError && un.status === :unwritten
        @test dest6.values == [7, 7, 7]      # rolled back
        @test fh6.state === :failed && fh6.error === un
        @test fh6.staged_done === false
        @test caught(() -> wait(fh6)) === un
        @test caught(() -> tracker_wait_all(tr6)) === un
        @test caught(() -> tracker_close(tr6)) === un

        # a staged action that raises the named dispatch error is sticky
        # alike (the original error is preserved, invoked exactly once)
        b8 = D.DeferredBackend()
        tr8 = SubmissionTracker(b8)
        action_err = BackendSubmitError("staged writeback failed")
        calls8 = Ref(0)
        fh8 = tracker_track(tr8, submit!(b8, batch),
                            () -> (calls8.x += 1; throw(action_err)))
        @test caught(() -> wait(fh8)) === action_err
        @test fh8.state === :failed && fh8.staged_done === false
        @test calls8.x == 1
        @test caught(() -> wait(fh8)) === action_err
        @test calls8.x == 1                  # never re-run
        @test caught(() -> tracker_wait_all(tr8)) === action_err
        @test caught(() -> tracker_close(tr8)) === action_err
        # staged §7 PHASE-1 validation failure (revision 9): the named
        # ArgumentError is preserved BY IDENTITY and sticky — the v8
        # union field could not store it (MethodError at the assignment
        # stranded :failed with error nothing, later waits threw
        # nothing); zero stores, the action runs exactly once, the same
        # error on all three routes, core staging retained, the
        # provider already released. (300 is the record helper's
        # deliberate Int validation input — not a UInt8 buffer claim;
        # upload pre-dispatch validation is unchanged.)
        b9 = D.DeferredBackend()
        tr9 = SubmissionTracker(b9)
        dest9 = CommitDest([7, 7, 7])
        calls9 = Ref(0)
        fh9 = tracker_track(tr9, submit!(b9, batch),
                            () -> (calls9.x += 1;
                                   commit_or_report!(dest9, [1, 300, 3])))
        va = caught(() -> wait(fh9))
        @test va isa ArgumentError
        @test occursin("channel outside 0..255", sprint(showerror, va))
        @test dest9.values == [7, 7, 7]     # untouched — zero stores
        @test dest9.stores == 0
        @test fh9.state === :failed && fh9.error === va
        @test fh9.staged_done === false
        @test fh9.staged !== nothing        # core staging retained
        @test fh9.provider.state === :complete
        @test fh9.provider.batch === nothing # provider already released
        @test isempty(b9.submissions)
        @test calls9.x == 1
        @test caught(() -> wait(fh9)) === va            # the SAME error
        @test caught(() -> tracker_wait_all(tr9)) === va # on all three
        @test caught(() -> tracker_close(tr9)) === va   # routes
        @test calls9.x == 1                  # action never re-run
        @test tr9.closed === false && b9.close_calls == 0
    end

    # ------------------------------------------------------------------
    @testset "G3 W3C compositing reference [math]" begin
        # separable + operator anchors (hand-derived)
        @test to_premul_bytes(composite(SourceOver, 0, (1f0, 0f0, 0f0, 1f0),
                                        (0f0, 0f0, 0f0, 0f0),
                                        coverage = 0.5f0)) == (128, 0, 0, 128)
        @test to_premul_bytes(composite(Atop, 0, (1f0, 0f0, 0f0, 0.25f0),
                                        (0f0, 0f0, 1f0, 0.75f0))) ==
            (16, 0, 48, 64)
        @test composite(Atop, 0, (1f0, 0f0, 0f0, 0.25f0),
                        (0f0, 0f0, 1f0, 0.75f0))[4] == 0.25f0
        @test to_premul_bytes(composite(Lighter, 0, (1f0, 0f0, 0f0, 0.25f0),
                                        (0f0, 0f0, 1f0, 0.75f0))) ==
            (64, 0, 191, 255)
        @test to_premul_bytes(composite(Lighter, 0, (1f0, 0f0, 0f0, 0.8f0),
                                        (0f0, 0f0, 1f0, 0.8f0))) ==
            (204, 0, 204, 255)
        # the artistic step runs BEFORE the additive operator (frozen
        # §5.7 anchor): Screen under Lighter, both straight 0.4 at alpha
        # 0.5 — B=0.64, Cr=0.52, co=0.46 ⇒ byte 117 (the v4 raw unblended
        # sum produced 102)
        @test to_premul_bytes(composite(Lighter, 5, (0.4, 0.4, 0.4, 0.5),
                                        (0.4, 0.4, 0.4, 0.5))) ==
            (117, 117, 117, 255)
        # W3C separable endpoint order (frozen §5.7, spec §10.1.7/§10.1.8):
        # the backdrop exception is tested before the source exception
        @test _blend_separable(3, 0.5, 0.0) == 0.0   # burn: Cs==0, Cb<1 ⇒ 0
        @test _blend_separable(3, 1.0, 0.0) == 1.0   # burn: Cb==1 first ⇒ 1
        @test _blend_separable(6, 0.5, 1.0) == 1.0   # dodge: Cs==1, Cb>0 ⇒ 1
        @test _blend_separable(6, 0.0, 1.0) == 0.0   # dodge: Cb==0 first ⇒ 0
        # full composites: opaque black burned / white dodged over half-gray
        # ⇒ (0,0,0,255) / (255,255,255,255) (the v4 checker returned 128)
        @test to_premul_bytes(composite(SourceOver, 3, (0f0, 0f0, 0f0, 1f0),
                                        (0.5, 0.5, 0.5, 1f0))) == (0, 0, 0, 255)
        @test to_premul_bytes(composite(SourceOver, 6, (1f0, 1f0, 1f0, 1f0),
                                        (0.5, 0.5, 0.5, 1f0))) ==
            (255, 255, 255, 255)
        # the pinned integer kernels agree at the endpoints (byte-exact)
        @test Vetra.blendColorBurn(Vetra.ColorRGBX(128, 128, 128, 255),
                                   Vetra.ColorRGBX(0, 0, 0, 255)) ==
            Vetra.ColorRGBX(0, 0, 0, 255)
        @test Vetra.blendColorBurn(Vetra.ColorRGBX(255, 255, 255, 255),
                                   Vetra.ColorRGBX(0, 0, 0, 255)) ==
            Vetra.ColorRGBX(255, 255, 255, 255)
        @test Vetra.blendColorDodge(Vetra.ColorRGBX(128, 128, 128, 255),
                                   Vetra.ColorRGBX(255, 255, 255, 255)) ==
            Vetra.ColorRGBX(255, 255, 255, 255)
        @test Vetra.blendColorDodge(Vetra.ColorRGBX(0, 0, 0, 255),
                                   Vetra.ColorRGBX(255, 255, 255, 255)) ==
            Vetra.ColorRGBX(0, 0, 0, 255)
        # non-endpoint value: the kernel's byte truncation may differ from
        # the exact reference by the documented 1 byte
        @test abs(UInt8(93) - Int(Vetra.blendColorBurn(
            Vetra.ColorRGBX(128, 128, 128, 255),
            Vetra.ColorRGBX(200, 200, 200, 255)).r)) ≤ 1
        @test to_premul_bytes(composite(SourceOver, 0, (1f0, 0f0, 0f0, 128/255),
                                        (0f0, 0f0, 1f0, 1f0))) ==
            (128, 0, 127, 255)
        @test to_premul_bytes(composite(SourceIn, 0, (1f0, 0f0, 0f0, 1f0),
                                        (0f0, 0f0, 1f0, 0.5f0))) ==
            (128, 0, 0, 128)
        @test to_premul_bytes(composite(SourceOut, 0, (1f0, 0f0, 0f0, 1f0),
                                        (0f0, 0f0, 1f0, 0.5f0))) ==
            (128, 0, 0, 128)
        @test to_premul_bytes(composite(Over, 0, (1f0, 0f0, 0f0, 0.5f0),
                                        (0f0, 1f0, 0f0, 1f0))) ==
            (0, 255, 0, 255)
        @test to_premul_bytes(composite(Copy, 0, (1f0, 0f0, 0f0, 0.5f0),
                                        (0f0, 1f0, 0f0, 1f0))) ==
            (128, 0, 0, 128)
        @test to_premul_bytes(composite(Xor, 0, (1f0, 1f0, 1f0, 1f0),
                                        (1f0, 1f0, 1f0, 1f0))) == (0, 0, 0, 0)
        # alpha-row asymmetry: Atop keeps source alpha, SourceAtop dest alpha
        @test composite(SourceAtop, 0, (1f0, 0f0, 0f0, 1f0),
                        (0f0, 0f0, 1f0, 0.5f0))[4] == 0.5f0
        # nonseparable vector anchors — cross-checked against the ACTUAL
        # pinned kernels (byte-exact CPU reference, §5.7); opaque inputs
        # so straight color == premul bytes/255
        for (mode, kern, sp, dp, pinned) in
            ((12, Vetra.blendHue,
              Vetra.ColorRGBX(255, 128, 0, 255), Vetra.ColorRGBX(51, 51, 51, 255),
              (51, 51, 51, 255)),
             (13, Vetra.blendSaturation,
              Vetra.ColorRGBX(255, 255, 0, 255),
              Vetra.ColorRGBX(128, 128, 128, 255), (128, 128, 128, 255)),
             (14, Vetra.blendColor,
              Vetra.ColorRGBX(255, 128, 0, 255), Vetra.ColorRGBX(51, 51, 51, 255),
              (86, 43, 0, 255)),
             (14, Vetra.blendColor,
              Vetra.ColorRGBX(255, 0, 0, 255), Vetra.ColorRGBX(0, 0, 255, 255),
              (94, 0, 0, 255)),
             (15, Vetra.blendLuminosity,
              Vetra.ColorRGBX(255, 0, 0, 255), Vetra.ColorRGBX(0, 0, 255, 255),
              (54, 54, 255, 255)))
            k = kern(dp, sp)
            @test (Int(k.r), Int(k.g), Int(k.b), Int(k.a)) == pinned
            s = (Int(sp.r) / 255, Int(sp.g) / 255, Int(sp.b) / 255, 1.0)
            d = (Int(dp.r) / 255, Int(dp.g) / 255, Int(dp.b) / 255, 1.0)
            got = to_premul_bytes(composite(SourceOver, mode, s, d))
            @test all(abs(x - y) ≤ 1 for (x, y) in zip(got, pinned))
        end
        # asymmetric color AND alpha through the nonseparable vector path —
        # half-coverage = byte 128 (128/255), cross-checked vs the kernel
        k = Vetra.blendHue(Vetra.ColorRGBX(0, 0, 128, 128),
                           Vetra.ColorRGBX(128, 0, 0, 128))
        @test (Int(k.r), Int(k.g), Int(k.b), Int(k.a)) == (87, 0, 64, 192)
        @test to_premul_bytes(composite(SourceOver, 12,
                                        (1f0, 0f0, 0f0, 128 / 255),
                                        (0f0, 0f0, 1f0, 128 / 255))) ==
            (87, 0, 64, 192)
    end

    # ------------------------------------------------------------------
    @testset "G5 §14 placement under the actual Vetra Mat3 [transform]" begin
        # mapping = translate(dest.x, dest.y) * scale(sx, sy) (the actual
        # Mat3 convention: the leftmost factor applies last to a point) —
        # a 2×2 picture into dest(10, 20, 4, 6)
        mapping = Vetra.translate(Vetra.Vec2(10f0, 20f0)) *
                  Vetra.scale(Vetra.Vec2(4f0 / 2, 6f0 / 2))
        @test Vetra.transform(mapping, Vetra.Vec2(0f0, 0f0)) ==
            Vetra.Vec2(10f0, 20f0)
        @test Vetra.transform(mapping, Vetra.Vec2(2f0, 2f0)) ==
            Vetra.Vec2(14f0, 26f0)
        # control: the rejected revision-4 order scale * translate sends
        # the origin to (20, 60), not (10, 20)
        rejected = Vetra.scale(Vetra.Vec2(2f0, 3f0)) *
                   Vetra.translate(Vetra.Vec2(10f0, 20f0))
        @test Vetra.transform(rejected, Vetra.Vec2(0f0, 0f0)) ==
            Vetra.Vec2(20f0, 60f0)
        # per-op composition ambient * mapping * op.tform (non-unit scale
        # and nonzero translation both active)
        ambient = Vetra.translate(Vetra.Vec2(5f0, 7f0))
        opt = Vetra.translate(Vetra.Vec2(1f0, 0f0))
        @test Vetra.transform(ambient * mapping * opt, Vetra.Vec2(0f0, 0f0)) ==
            Vetra.Vec2(17f0, 27f0)

        # ---- doc §14 revision 7: the owned CanvasRecording machine
        # (narrow: seal boundary, the one remap, placement/clip
        # arithmetics — the revision-6 multi-op replay visitor is
        # retired; multi-op replay execution is a normative trace,
        # ⏳ R020) ----
        solid() = OwnedPaint(Vetra.SolidPaint, Vetra.rgba(255, 0, 0, 255),
                             1f0, Vetra.NormalBlend, 0, Vetra.mat3(),
                             Vetra.Vec2[], Vetra.ColorStop[])
        # capture: one 1×1 asset (id 41) drawn as an image
        img = CanvasAsset(41, 1, 1, UInt8[255, 0, 0, 255])
        diops = CanvasOp[
            DrawImageOp(41, Vetra.rect(0f0, 0f0, 1f0, 1f0),
                        Vetra.rect(0f0, 0f0, 2f0, 2f0), Vetra.mat3(),
                        LinearSampling, SourceOver, 1f0, ClipScope[])]
        rec = record_seal(diops, Dict{Int, CanvasAsset}(41 => img), 2, 2)
        # seal boundary: asset bytes deep-copied — source mutation is
        # inert
        @test rec.assets[41] !== img
        @test rec.assets[41].data !== img.data
        img.data[1] = 0
        @test rec.assets[41].data[1] == 255
        @test rec.size == Vetra.Vec2(2, 2)
        # seal boundary: the recording owns its op CONTAINER — the
        # caller's vector is not aliased (ops themselves are already
        # owned per §6; the seal does not re-snapshot them)
        n_ops = length(rec.ops)
        push!(diops, ClearOp(Vetra.rect(0f0, 0f0, 1f0, 1f0), Vetra.mat3(),
                             ClipScope[]))
        @test length(rec.ops) == n_ops
        # unbalanced group at seal: the named ArgumentError
        unbal = CanvasOp[GroupStartOp(1f0, SourceOver, ClipScope[])]
        eu = caught(() -> record_seal(unbal, Dict{Int, CanvasAsset}(), 2, 2))
        @test eu isa ArgumentError
        @test occursin("unbalanced save_layer at record", sprint(showerror, eu))
        # an op referencing an uncaptured asset: named ArgumentError
        # (BOTH id classes — the draw reference …)
        @test_throws ArgumentError record_seal(
            CanvasOp[DrawImageOp(7, Vetra.rect(0f0, 0f0, 1f0, 1f0),
                                Vetra.rect(0f0, 0f0, 1f0, 1f0), Vetra.mat3(),
                                LinearSampling, SourceOver, 1f0,
                                ClipScope[])],
            Dict{Int, CanvasAsset}(), 2, 2)
        # … and the image/tiled paint reference)
        ipaint = OwnedPaint(Vetra.ImagePaint, Vetra.rgba(255, 0, 0, 255),
                            1f0, Vetra.NormalBlend, 7, Vetra.mat3(),
                            Vetra.Vec2[], Vetra.ColorStop[])
        @test_throws ArgumentError record_seal(
            CanvasOp[FillOp(Vetra.newPath(), ipaint, Vetra.mat3(),
                            Vetra.NonZero, ClipScope[], SourceOver)],
            Dict{Int, CanvasAsset}(), 2, 2)
        # the ONE 1:1 remap over the sorted recording ids — it resolves
        # both reference classes (the v6 visitor remapped draws only and
        # left image-paint ids unchanged)
        remap = recording_remap(rec, 100)
        @test remap[41] == 100
        @test collect(keys(remap)) == [41]
        # placement under the actual Mat3 (a 2×2 recording into
        # dest(10,20,4,6)) — pure arithmetic, no op construction
        (pm, _) = recording_placement(rec.size, Vetra.rect(10f0, 20f0, 4f0, 6f0))
        @test Vetra.transform(pm, Vetra.Vec2(0f0, 0f0)) == Vetra.Vec2(10f0, 20f0)
        @test Vetra.transform(pm, Vetra.Vec2(2f0, 2f0)) == Vetra.Vec2(14f0, 26f0)
        # per-op tform = ambient * mapping * op.tform; recorded clip
        # geometry maps under ambient * mapping EXACTLY ONCE
        (pm2, clipmap) = recording_placement(rec.size,
                                            Vetra.rect(10f0, 20f0, 4f0, 6f0),
                                            ambient)
        @test Vetra.transform(ambient * pm2 * opt, Vetra.Vec2(0f0, 0f0)) ==
            Vetra.Vec2(17f0, 27f0)
        @test Vetra.transform(clipmap, Vetra.Vec2(2f0, 2f0)) ==
            Vetra.Vec2(19f0, 33f0)
        # single-mapping control: mapping the mapped corner AGAIN would
        # land at (38, 98) — the clip map applies it once
        @test Vetra.transform(pm2, Vetra.transform(pm2, Vetra.Vec2(2f0, 2f0))) !=
            Vetra.Vec2(19f0, 33f0)
        # the Xor-group recording seals losslessly (group balance —
        # multi-op replay execution remains the normative trace, ⏳ R020)
        xrec = record_seal(CanvasOp[
            GroupStartOp(1f0, Xor, ClipScope[]),
            FillOp(Vetra.newPath(), solid(), Vetra.mat3(), Vetra.NonZero,
                   ClipScope[], SourceOver),
            GroupEndOp(ClipScope[])],
            Dict{Int, CanvasAsset}(), 2, 2)
        @test xrec.ops[1] isa GroupStartOp && xrec.ops[1].composition === Xor
        # ...but the legacy adapter's disjoint decision procedure
        # rejects it (GroupStart has no composition field)
        ex = caught(() -> lowering_admit!(xrec))
        @test ex isa ArgumentError
        @test occursin("composition xor", sprint(showerror, ex))
        @test occursin("op 1", sprint(showerror, ex))
        # top-level Copy is admitted (lowered to an OverwriteBlend
        # paint); the same Copy under the implicit clip wrapper is not
        function copyop(; clips = ClipScope[])
            return FillOp(Vetra.newPath(), solid(), Vetra.mat3(),
                          Vetra.NonZero, clips, Copy)
        end
        @test lowering_admit!(record_seal(CanvasOp[copyop()],
                                          Dict{Int, CanvasAsset}(), 2, 2)) == 1
        clip = Vetra.newPath(); Vetra.rect(clip, 0f0, 0f0, 1f0, 1f0)
        ec = caught(() -> lowering_admit!(
            record_seal(CanvasOp[copyop(clips=ClipScope[ClipScope(clip,
                                                                Vetra.NonZero)])],
                        Dict{Int, CanvasAsset}(), 2, 2)))
        @test ec isa ArgumentError
        @test occursin("Copy under the implicit legacy clip wrapper",
                       sprint(showerror, ec))
        # the v6 over-rejection is corrected: Copy under an EXPLICIT
        # group (entry opacity ≠ 1.0) is representable — the legacy
        # GroupStart.opacity carries the group factor 1:1 and the
        # scratch is the Copy op's backdrop in both models
        @test lowering_admit!(
            record_seal(CanvasOp[GroupStartOp(0.5f0, SourceOver, ClipScope[]),
                                 copyop(),
                                 GroupEndOp(ClipScope[])],
                        Dict{Int, CanvasAsset}(), 2, 2)) == 3
        # clipped red Multiply fill: the v6 table ACCEPTED this
        # (source-over + artistic) — the disjoint procedure rejects it
        # (the wrapper replaces the backdrop; see the actual-recorder
        # reproduction below)
        mpaint = OwnedPaint(Vetra.SolidPaint, Vetra.rgba(255, 0, 0, 255),
                            1f0, Vetra.MultiplyBlend, 0, Vetra.mat3(),
                            Vetra.Vec2[], Vetra.ColorStop[])
        emul = caught(() -> lowering_admit!(
            record_seal(CanvasOp[FillOp(Vetra.newPath(), mpaint,
                                       Vetra.mat3(), Vetra.NonZero,
                                       ClipScope[ClipScope(clip,
                                                           Vetra.NonZero)],
                                       SourceOver)],
                         Dict{Int, CanvasAsset}(), 2, 2)))
        @test emul isa ArgumentError
        @test occursin("artistic blend under the implicit legacy clip wrapper",
                       sprint(showerror, emul))
        # the same Multiply WITHOUT the wrapper is admitted (the legacy
        # paint carries the blendMode; unclipped direct draw is
        # pixel-preserving — the control below)
        @test lowering_admit!(
            record_seal(CanvasOp[FillOp(Vetra.newPath(), mpaint,
                                       Vetra.mat3(), Vetra.NonZero,
                                       ClipScope[], SourceOver)],
                         Dict{Int, CanvasAsset}(), 2, 2)) == 1
        # zero-opacity Copy: the v7 table ADMITTED this — the legacy
        # fill pipeline early-returns on zero Paint.opacity, so the
        # actual Picture leaves the destination (the reproduction in
        # the actual-recorder testset below)
        zpaint = OwnedPaint(Vetra.SolidPaint, Vetra.rgba(255, 0, 0, 255),
                            0f0, Vetra.NormalBlend, 0, Vetra.mat3(),
                            Vetra.Vec2[], Vetra.ColorStop[])
        ezero = caught(() -> lowering_admit!(
            record_seal(CanvasOp[FillOp(Vetra.newPath(), zpaint,
                                       Vetra.mat3(), Vetra.NonZero,
                                       ClipScope[], Copy)],
                         Dict{Int, CanvasAsset}(), 2, 2)))
        @test ezero isa ArgumentError
        @test occursin("zero-opacity Copy", sprint(showerror, ezero))
        # a dash-phase stroke rejects (legacy StrokeOp has no dashOffset)
        dstroke = StrokeOp(Vetra.newPath(), solid(), Vetra.mat3(), 1f0,
                           Vetra.ButtCap, Vetra.MiterJoin, 4f0,
                           Float32[2f0, 2f0], 1f0, ClipScope[], SourceOver)
        ed = caught(() -> lowering_admit!(
            record_seal(CanvasOp[dstroke], Dict{Int, CanvasAsset}(), 2, 2)))
        @test ed isa ArgumentError
        @test occursin("dash phase", sprint(showerror, ed))
        # a non-solid stroke paint rejects (legacy boundary: solid only)
        gstroke = StrokeOp(Vetra.newPath(),
                          OwnedPaint(Vetra.LinearGradientPaint,
                                    Vetra.rgba(0, 255, 0, 255), 1f0,
                                    Vetra.NormalBlend, 0, Vetra.mat3(),
                                    [Vetra.Vec2(0f0, 0f0), Vetra.Vec2(1f0, 0f0)],
                                    [Vetra.ColorStop(Vetra.rgba(0, 255, 0, 255),
                                                    0f0)]),
                          Vetra.mat3(), 1f0, Vetra.ButtCap, Vetra.MiterJoin,
                          4f0, Float32[], 0f0, ClipScope[], SourceOver)
        eg = caught(() -> lowering_admit!(
            record_seal(CanvasOp[gstroke], Dict{Int, CanvasAsset}(), 2, 2)))
        @test occursin("non-solid stroke paint", sprint(showerror, eg))
        # image sampling / composition / fractional source rect reject;
        # effective opacity is ADMITTED (the implicit alpha wrapper —
        # the revision-6 opacity rejection is retracted)
        for (kw, msg) in ((:sampling, "image sampling"),
                          (:composition, "image composition"),
                          (:srcRect, "fractional image source rect"))
            op = DrawImageOp(41, Vetra.rect(0f0, 0f0, 1f0, 1f0),
                             Vetra.rect(0f0, 0f0, 2f0, 2f0), Vetra.mat3(),
                             LinearSampling, SourceOver, 1f0, ClipScope[])
            if kw === :sampling
                op = DrawImageOp(41, op.srcRect, op.destRect, op.tform,
                                 NearestSampling, op.composition, op.opacity,
                                 op.clips)
            elseif kw === :composition
                op = DrawImageOp(41, op.srcRect, op.destRect, op.tform,
                                 op.sampling, Xor, op.opacity, op.clips)
            else
                op = DrawImageOp(41, Vetra.rect(0.5f0, 0f0, 1f0, 1f0),
                                 op.destRect, op.tform, op.sampling,
                                 op.composition, op.opacity, op.clips)
            end
            r = record_seal(CanvasOp[op], Dict{Int, CanvasAsset}(41 => img),
                            2, 2)
            er = caught(() -> lowering_admit!(r))
            @test er isa ArgumentError
            @test occursin(msg, sprint(showerror, er))
        end
        @test lowering_admit!(
            record_seal(CanvasOp[DrawImageOp(41, Vetra.rect(0f0, 0f0, 1f0, 1f0),
                                    Vetra.rect(0f0, 0f0, 2f0, 2f0),
                                    Vetra.mat3(), LinearSampling, SourceOver,
                                    0.5f0, ClipScope[])],
                         Dict{Int, CanvasAsset}(41 => img), 2, 2)) == 1
        # a tiled-image fill rejects (the actual recorder: not recordable)
        tpaint = OwnedPaint(Vetra.TiledImagePaint, Vetra.rgba(255, 0, 0, 255),
                            1f0, Vetra.NormalBlend, 41, Vetra.mat3(),
                            Vetra.Vec2[], Vetra.ColorStop[])
        et = caught(() -> lowering_admit!(
            record_seal(CanvasOp[FillOp(Vetra.newPath(), tpaint,
                                       Vetra.mat3(), Vetra.NonZero,
                                       ClipScope[], SourceOver)],
                         Dict{Int, CanvasAsset}(41 => img), 2, 2)))
        @test et isa ArgumentError
        @test occursin("tiled image fill", sprint(showerror, et))
        # a clip set INSIDE the group rejects (the legacy group mask
        # applies to the whole group)
        eci = caught(() -> lowering_admit!(
            record_seal(CanvasOp[GroupStartOp(1f0, SourceOver, ClipScope[]),
                                 FillOp(Vetra.newPath(), solid(), Vetra.mat3(),
                                        Vetra.NonZero,
                                        ClipScope[ClipScope(clip,
                                                            Vetra.NonZero)],
                                        SourceOver),
                                 GroupEndOp(ClipScope[])],
                        Dict{Int, CanvasAsset}(), 2, 2)))
        @test eci isa ArgumentError
        @test occursin("clip set inside the legacy group",
                       sprint(showerror, eci))
        # an effect rejects (no EffectOp in the legacy vocabulary)
        effr = record_seal(CanvasOp[
            EffectOp(:blur, 1f0, Vetra.Vec2(), Vetra.rgb(0, 0, 0), 1f0,
                     Vetra.rect(0f0, 0f0, 2f0, 2f0),
                     Vetra.rect(0f0, 0f0, 2f0, 2f0), Vetra.mat3(),
                     ClipScope[])],
            Dict{Int, CanvasAsset}(), 2, 2)
        ee = caught(() -> lowering_admit!(effr))
        @test occursin("blur has no legacy counterpart", sprint(showerror, ee))
        # a clipped clear rejects (legacy ClearOp has no clip field;
        # the actual recorder never wraps clear)
        clr = record_seal(CanvasOp[
            ClearOp(Vetra.rect(0f0, 0f0, 2f0, 2f0), Vetra.mat3(),
                    ClipScope[ClipScope(clip, Vetra.NonZero)])],
            Dict{Int, CanvasAsset}(), 2, 2)
        ecl = caught(() -> lowering_admit!(clr))
        @test occursin("clipped clear", sprint(showerror, ecl))
    end

    # ------------------------------------------------------------------
    @testset "G5 legacy lowering: actual-recorder counterexamples [math]" begin
        # The rejection rows rest on the ACTUAL legacy
        # PictureRecorder/Picture/drawPicture — 1×1 pixel reproductions,
        # independent of the decision procedure above (the pinned
        # kernels' byte-exact reference for the required normalized
        # pixels).
        pclip = Vetra.newPath(); Vetra.rect(pclip, 0f0, 0f0, 1f0, 1f0)
        # (1) clipped transparent Copy: the implicit clip wrapper
        #     composites the scratch Normal — the Copy operator is
        #     LOST: the actual recorder leaves blue where Canvas Copy
        #     must clear
        r1 = Vetra.PictureRecorder(1, 1)
        Vetra.clip(r1.ctx, pclip)
        cp = Vetra.newPaint(Vetra.SolidPaint)
        cp.color = Vetra.rgba(0, 0, 0, 0)
        cp.blendMode = Vetra.OverwriteBlend
        r1.ctx.fillStyle = cp
        Vetra.fillRect(r1.ctx, 0, 0, 1, 1)
        t1 = Vetra.Image(1, 1, UInt8[0, 0, 255, 255])
        Vetra.drawPicture(t1, Vetra.finishRecording(r1))
        @test t1.data == UInt8[0, 0, 255, 255]     # blue left — non-preserving
        @test to_premul_bytes(composite(Copy, 0, (0f0, 0f0, 0f0, 0f0),
                                        (0f0, 0f0, 1f0, 1f0))) == (0, 0, 0, 0)
        # (2) clipped red Multiply: the wrapper replaces the backdrop —
        #     the actual recorder yields RED where the normalized §5.7
        #     rule requires BLACK
        r2 = Vetra.PictureRecorder(1, 1)
        Vetra.clip(r2.ctx, pclip)
        mp = Vetra.newPaint(Vetra.SolidPaint)
        mp.color = Vetra.rgba(255, 0, 0, 255)
        mp.blendMode = Vetra.MultiplyBlend
        r2.ctx.fillStyle = mp
        Vetra.fillRect(r2.ctx, 0, 0, 1, 1)
        t2 = Vetra.Image(1, 1, UInt8[0, 0, 255, 255])
        Vetra.drawPicture(t2, Vetra.finishRecording(r2))
        @test t2.data == UInt8[255, 0, 0, 255]     # red — non-preserving
        @test to_premul_bytes(composite(SourceOver, 2, (1f0, 0f0, 0f0, 1f0),
                                        (0f0, 0f0, 1f0, 1f0))) == (0, 0, 0, 255)
        # (3) preserving CONTROLS — the accept rows, unclipped direct
        #     legacy pictures: Multiply over blue ⇒ black (the legacy
        #     paint carries the blendMode; the true backdrop is
        #     intact), transparent Overwrite ⇒ clear
        mp3 = Vetra.newPaint(Vetra.SolidPaint)
        mp3.color = Vetra.rgba(255, 0, 0, 255)
        mp3.blendMode = Vetra.MultiplyBlend
        pic3 = Vetra.Picture(Vetra.PicOp[Vetra.FillOp(pclip, mp3,
                                                      Vetra.mat3(),
                                                      Vetra.NonZero)],
                             Vetra.Vec2(1, 1))
        t3 = Vetra.Image(1, 1, UInt8[0, 0, 255, 255])
        Vetra.drawPicture(t3, pic3)
        @test t3.data == UInt8[0, 0, 0, 255]       # black — preserving
        cp4 = Vetra.newPaint(Vetra.SolidPaint)
        cp4.color = Vetra.rgba(0, 0, 0, 0)
        cp4.blendMode = Vetra.OverwriteBlend
        pic4 = Vetra.Picture(Vetra.PicOp[Vetra.FillOp(pclip, cp4,
                                                      Vetra.mat3(),
                                                      Vetra.NonZero)],
                             Vetra.Vec2(1, 1))
        t4 = Vetra.Image(1, 1, UInt8[0, 0, 255, 255])
        Vetra.drawPicture(t4, pic4)
        @test t4.data == UInt8[0, 0, 0, 0]         # cleared — preserving
        # (4) zero-opacity Copy (the v7 acceptance, revised): the
        #     legacy fill pipeline early-returns on zero Paint.opacity
        #     — the actual Picture leaves blue where normalized Copy
        #     must clear. The control (3b) is a DIFFERENT route
        #     (transparent COLOR at unit opacity) and does clear.
        zp5 = Vetra.newPaint(Vetra.SolidPaint)
        zp5.color = Vetra.rgba(255, 0, 0, 255)
        zp5.opacity = 0f0
        zp5.blendMode = Vetra.OverwriteBlend
        pic5 = Vetra.Picture(Vetra.PicOp[Vetra.FillOp(pclip, zp5,
                                                      Vetra.mat3(),
                                                      Vetra.NonZero)],
                             Vetra.Vec2(1, 1))
        t5 = Vetra.Image(1, 1, UInt8[0, 0, 255, 255])
        Vetra.drawPicture(t5, pic5)
        @test t5.data == UInt8[0, 0, 255, 255]     # blue left — non-preserving
        @test to_premul_bytes(composite(Copy, 0, (1f0, 0f0, 0f0, 0f0),
                                        (0f0, 0f0, 1f0, 1f0))) == (0, 0, 0, 0)
    end

    # ------------------------------------------------------------------
    @testset "§5.7 exact-rational hue anchor (independent of the kernel) [math]" begin
        # W3C §10.2 nonseparable helpers in exact rationals — the
        # independent oracle for (87, 0, 64, 192); the pinned blendHue
        # kernel reproducing the bytes is a cross-check, not the source.
        function rat_lum(C)
            return 3//10 * C[1] + 59//100 * C[2] + 11//100 * C[3]
        end
        function rat_clip(C)
            L = rat_lum(C); n = minimum(C); x = maximum(C)
            if n < 0
                C = L .+ (C .- L) .* (L // (L - n))
            end
            if x > 1
                C = L .+ (C .- L) .* ((1 - L) // (x - L))
            end
            return C
        end
        rat_setlum(C, l) = rat_clip(C .+ (l - rat_lum(C)))
        rat_sat(C) = maximum(C) - minimum(C)
        function rat_setsat(C, s)
            order = sortperm(C)
            imin, imid, imax = order[1], order[2], order[3]
            Cmin, Cmid, Cmax = C[imin], C[imid], C[imax]
            if Cmax > Cmin
                Cmid = (Cmid - Cmin) * s / (Cmax - Cmin)
                Cmax = s
            else
                Cmid = Cmax = zero(eltype(C))
            end
            Cmin = zero(eltype(C))
            out = copy(C)
            out[imin] = Cmin; out[imid] = Cmid; out[imax] = Cmax
            return out
        end
        rat_blend_hue(Cb, Cs) =
            rat_setlum(rat_setsat(Cs, rat_sat(Cb)), rat_lum(Cb))
        # hue of red (source) over blue (backdrop), both at alpha 128/255
        B = rat_blend_hue([0//1, 0//1, 1//1], [1//1, 0//1, 0//1])
        @test B == [11//30, 0//1, 0//1]      # the W3C ClipColor result
        a = 128//255
        Cr_R = (1 - a) + a * B[1]
        co_R = a * Cr_R                        # source-over: Fa = 1
        co_B = a * (1 - a)                     # Fb = 1−a, Cb_B = 1
        αo = a + a * (1 - a)
        round_ties(v::Rational{Int})::Int = div(255 * v.num + v.den ÷ 2, v.den)
        @test round_ties(co_R) == 87
        @test round_ties(co_B) == 64
        @test round_ties(αo) == 192
        @test (255 * co_R, 255 * co_B, 255 * αo) ==
            (333952//3825, 16256//255, 48896//255)
    end

    # ------------------------------------------------------------------
    @testset "G8 main anchors + pinned kernels [math]" begin
        @test quant_channel(0.5) == 128
        @test quant_channel(1.0) == 255
        @test quant_channel(Float64(1) / 3) == 85
        @test quant_channel(0.25) == 64
        @test_throws ArgumentError quant_channel(1.5)
        @test_throws ArgumentError quant_channel(-0.1)
        @test_throws ArgumentError quant_channel(Float32(NaN))
        # matte composite over white
        @test _matte_rgb(Vetra.ColorRGBX(128, 0, 0, 128),
                         Vetra.ColorRGB(255, 255, 255)) ==
            Vetra.ColorRGB(255, 127, 127)
        # transparent gray/3-channel output: composite FIRST, then luma
        # (frozen §7) — half-red over white ⇒ (255,127,127) ⇒ gray 154,
        # not the un-composited premul luma 27; no matte ⇒ rejected
        # before any write
        HS = UInt8[128, 0, 0, 128]
        @test export_raw(HS, 1, 1, PixelLayout(1, 1, 1, false, false, true);
                         matte = Vetra.ColorRGB(255, 255, 255))[1] == 154
        @test_throws ArgumentError export_raw(
            HS, 1, 1, PixelLayout(1, 1, 1, false, false, true))
        @test_throws ArgumentError export_raw(
            HS, 1, 1, PixelLayout(1, 1, 3, false, false, true))
        # a fully opaque canvas needs no matte
        @test export_raw(UInt8[255, 255, 255, 255], 1, 1,
                         PixelLayout(1, 1, 1, false, false, true))[1] ==
            luma_byte(255, 255, 255)
        # actual pinned kernels at the boundary
        @test Vetra.rgbx(Vetra.rgba(255, 128, 128, 128)) ==
            Vetra.ColorRGBX(128, 64, 64, 128)
        @test Vetra.rgbx(Vetra.rgba(200, 0, 0, 128)) ==
            Vetra.ColorRGBX(100, 0, 0, 128)
        @test Vetra.toStraightAlpha(Vetra.ColorRGBX(128, 0, 0, 128)) ==
            Vetra.ColorRGBA(255, 0, 0, 128)
        # opaque-boundary byte cross-check vs the actual integer kernels
        sp = Vetra.ColorRGBX(255, 128, 0, 255)
        dp = Vetra.ColorRGBX(0, 255, 255, 255)
        s = (1f0, 128 / 255, 0f0, 1f0)
        d = (0f0, 1f0, 1f0, 1f0)
        for (mode, kern) in ((2, Vetra.blendMultiply),
                             (5, Vetra.blendScreen),
                             (10, Vetra.blendDifference),
                             (11, Vetra.blendExclusion))
            k = kern(dp, sp)
            @test to_premul_bytes(composite(SourceOver, mode, s, d)) ==
                (UInt8(k.r), UInt8(k.g), UInt8(k.b), UInt8(k.a))
        end
    end

    # ------------------------------------------------------------------
    @testset "G14 one input-size invariant [math]" begin
        @test physical_extents(2, 2, 2f0) == (4, 4)
        @test physical_extents(3, 3, 0.5f0) == (2, 2)
        @test physical_extents(1, 1, 1.5f0) == (2, 2)
        @test physical_extents(4, 5, 1f0) == (4, 5)
        # promotion BEFORE multiplication (frozen §10): logical 3 at scale
        # Float32(7/6) — the literal Float32 product ties at 3.5 (⇒ 4);
        # the promoted product is 3.4999999 (⇒ 3)
        @test physical_extents(3, 3, Float32(7 / 6)) == (3, 3)
        @test_throws ArgumentError physical_extents(1, 1, 0f0)
        @test_throws ArgumentError physical_extents(1, 1, -1f0)
        @test_throws ArgumentError physical_extents(1, 1, Float32(NaN))
        @test_throws ArgumentError physical_extents(1, 1, Float32(Inf))
        @test_throws ArgumentError physical_extents(
            5_000_000_000_000_000_000, 1, 2f0)
        # exact-integral import invariants
        @test constructor_logical(2, 2, 2f0) == (1, 1)
        @test constructor_logical(4, 2, 2f0) == (2, 1)
        @test constructor_logical(6, 3, 1.5f0) == (4, 2)
        @test constructor_logical(4, 2, 1f0) == (4, 2)
        e = caught(() -> constructor_logical(1, 1, 2f0))
        @test e isa ArgumentError
        @test occursin("no exact integral logical size", sprint(showerror, e))
        @test_throws ArgumentError constructor_logical(3, 3, 2f0)
        @test_throws ArgumentError constructor_logical(5, 3, 1.5f0)
        # inverse DPI: promotion BEFORE division (frozen §4 rule 1,
        # revision 6): physical 6 @ scale 0.6f0 — the literal Float32
        # division is exactly 10.0 and round-trips (the false
        # acceptance); the widened quotient is nonintegral ⇒ rejected
        # (revision 7: the exact widened value is pinned — the v6
        # doc printed ≈10.0000016, which is not what the division
        # yields)
        @test Float64(6) / Float64(0.6f0) == 9.999999602635718
        @test_throws ArgumentError constructor_logical(6, 6, 0.6f0)
        @test Int(6 / 0.6f0) == 10                # literal control
        @test physical_extents(10, 10, 0.6f0) == (6, 6)
        # initial bytes are validated against PHYSICAL extents: a raw 4×2
        # RGBA channel form at scale 2 binds logical 2×1 and carries 32
        # initial bytes (a 16-byte initial is rejected)
        good = CanvasAsset(0, 4, 2, zeros(UInt8, 32))
        @test validate_initial(good, 4, 2) === nothing
        @test_throws ArgumentError validate_initial(
            CanvasAsset(0, 2, 1, zeros(UInt8, 8)), 4, 2)
        @test_throws ArgumentError validate_initial(
            CanvasAsset(0, 4, 2, zeros(UInt8, 16)), 4, 2)
        # the SAME invariant through the adapter descriptor route (§13):
        # a 4×2 host storage at scale 2 binds logical 2×1 with a 32-byte
        # initial read back through the canonical zero-based exchange
        SH = StorageHost
        m = Matrix{Vetra.ColorRGBX}(undef, 2, 4)
        for (i, px) in enumerate(Vetra.ColorRGBX.(1:8, 0, 0, 255))
            m[(i - 1) ÷ 4 + 1, (i - 1) % 4 + 1] = px
        end
        s = SH.HostAdapter(m)
        desc = storage_descriptor(s)
        @test constructor_logical(desc.layout.width, desc.layout.height,
                                  2f0) == (2, 1)
        init2 = storage_read(s, Vetra.rect(0f0, 0f0, 4f0, 2f0))
        @test (init2.width, init2.height, length(init2.data)) == (4, 2, 32)
        @test validate_initial(CanvasAsset(0, 4, 2, init2.data), 4, 2) ===
            nothing
    end

    # ------------------------------------------------------------------
    @testset "G11 layout / scan / conversion table [math]" begin
        px(i) = Vetra.ColorRGBX(UInt8(i), 0, 0, 255)
        # element matrix: ordinary Julia Matrix (column-major MEMORY) is
        # imported by position, logical row-first
        M = Matrix{Vetra.ColorRGBX}(undef, 2, 3)
        M[1, :] = [px(1), px(2), px(3)]
        M[2, :] = [px(4), px(5), px(6)]
        buf = import_elements(M, 3, 2)
        @test buf[1:4] == [1, 0, 0, 255]
        @test buf[9:12] == [3, 0, 0, 255]
        @test buf[13:16] == [4, 0, 0, 255]
        # element vector, declared scan order
        V = [px(1), px(2), px(3), px(4), px(5), px(6)]
        @test import_elements(V, 3, 2; row_major = true)[5:8] == [2, 0, 0, 255]
        VC = [px(1), px(4), px(2), px(5), px(3), px(6)]
        @test import_elements(VC, 3, 2; row_major = false) == buf
        # ordered offset axes map by position
        struct OffsetPx <: AbstractVector{Vetra.ColorRGBX}
            data::Vector{Vetra.ColorRGBX}
        end
        Base.size(v::OffsetPx) = size(v.data)
        Base.axes(v::OffsetPx) = (0:length(v.data) - 1,)
        Base.getindex(v::OffsetPx, i::Int) = v.data[i + 1]
        @test import_elements(OffsetPx(V), 3, 2) == buf
        # index-array views rejected (matrix AND element vector — the
        # vector axis rule, not a memory reinterpretation)
        @test_throws ArgumentError import_elements(view(M, [2, 1], [2, 1, 3]), 3, 2)
        @test_throws ArgumentError import_elements(view(V, [3, 1, 2, 4, 5, 6]), 3, 2)
        # adjoint rejected; top-level transpose imported by position
        @test_throws ArgumentError import_elements(M', 3, 2)
        T = transpose(M)
        @test import_elements(T, 2, 3)[5:8] == [4, 0, 0, 255]
        # straight element import premultiplies at the boundary (actual
        # rgbx kernel)
        A = Matrix{Vetra.ColorRGBA}(undef, 1, 1)
        A[1, 1] = Vetra.rgba(255, 128, 128, 128)
        @test import_elements(A, 1, 1) == [128, 64, 64, 128]
        # opaque element import
        B = Matrix{Vetra.ColorRGB}(undef, 1, 1)
        B[1, 1] = Vetra.ColorRGB(7, 8, 9)
        @test import_elements(B, 1, 1) == [7, 8, 9, 255]
        # raw forms
        lay = PixelLayout(3, 2, 4, true, true, true)
        RM = Matrix{UInt8}(undef, 2, 12)
        RM[1, :] = [1, 0, 0, 255, 2, 0, 0, 255, 3, 0, 0, 255]
        RM[2, :] = [4, 0, 0, 255, 5, 0, 0, 255, 6, 0, 0, 255]
        @test import_raw(RM, lay) == buf
        # column-major raw matrix (w*ch, h) — built explicitly; a
        # top-level transpose of the row-major form is peeled +
        # materialized positionally (the §7 rule, not a rejection)
        CM = Matrix{UInt8}(undef, 12, 2)
        for r in 1:2, c in 1:3
            CM[(c-1)*4+1, r] = (r-1)*3 + c
            CM[(c-1)*4+2, r] = 0
            CM[(c-1)*4+3, r] = 0
            CM[(c-1)*4+4, r] = 255
        end
        lay_col = PixelLayout(3, 2, 4, true, true, false)
        @test import_raw(CM, lay_col) == buf
        # a TOP-LEVEL transpose of the row-major form is peeled +
        # materialized positionally (the §7 rule, not a rejection):
        # transpose(RM) presents (w*ch, h) — the column-major orientation
        @test import_raw(transpose(RM), lay_col) == buf
        @test_throws ArgumentError import_raw(transpose(RM), lay)
        # while an adjoint is rejected named (the fromColors rule, same
        # as the element route)
        @test_throws ArgumentError import_raw(RM', lay)
        # revision 6: the raw route honors the same indexing rule —
        # ordered offset axes map by position (an ordered UnitRange view
        # exercises the positional accessor; an index-array view is
        # rejected named)
        RV = copy(buf)
        @test import_raw(view(RV, 1:24), lay) == buf
        @test_throws ArgumentError import_raw(view(RV, collect(24:-1:1)), lay)
        # revision 7: ZERO-BASED raw matrices map by position through
        # axes(M) in BOTH declared scan orientations (the v6 helper
        # indexed from 1 and raised BoundsError on both)
        OM = OffsetMatrix(RM)
        @test axes(OM) == (0:1, 0:11)
        @test OM[0, 0] == 1
        @test import_raw(OM, lay) == buf
        OMc = OffsetMatrix(CM)
        @test axes(OMc) == (0:11, 0:1)
        @test import_raw(OMc, lay_col) == buf
        # the narrowed vec advice: vec of a channel-packed RAW matrix
        # flattens rows inside each channel column — the flat bytes
        # match no declared scan (pinned: first pixel [1,0,0,255] ⇒
        # vec reads [1,4,0,0]) — materialize the declared order, or
        # use the matrix form
        @test vec(RM)[1:4] == [1, 4, 0, 0]
        @test import_raw(UInt8[1, 0, 0, 255, 2, 0, 0, 255, 3, 0, 0, 255,
                               4, 0, 0, 255, 5, 0, 0, 255, 6, 0, 0, 255],
                        lay) == buf
        @test import_raw(UInt8[1, 0, 0, 255, 4, 0, 0, 255, 2, 0, 0, 255,
                               5, 0, 0, 255, 3, 0, 0, 255, 6, 0, 0, 255],
                        lay_col) == buf
        # raw straight premultiplies at the boundary
        @test import_raw(UInt8[255, 128, 128, 128],
                         PixelLayout(1, 1, 4, true, false, true)) ==
            [128, 64, 64, 128]
        # raw gray replicates, a = 255
        @test import_raw(UInt8[128, 64], PixelLayout(1, 2, 1, false, false, true)) ==
            [128, 128, 128, 255, 64, 64, 64, 255]
        # raw 3-channel opaque
        @test import_raw(UInt8[255, 0, 128],
                         PixelLayout(1, 1, 3, false, false, true)) ==
            [255, 0, 128, 255]
        # raw float quantizes with the frozen rule
        @test import_raw(Float32[0.5f0, 0f0, 0f0, 1f0],
                         PixelLayout(1, 1, 4, true, true, true)) ==
            [128, 0, 0, 255]
        @test_throws ArgumentError import_raw(
            Float32[1.5f0, 0f0, 0f0, 1f0], PixelLayout(1, 1, 4, true, true, true))
        # export: element matrix (height, width)
        D = export_elements(buf, 3, 2; T = Vetra.ColorRGBX)
        @test size(D) == (2, 3) && D[1, 1] == px(1) && D[2, 3] == px(6)
        # export: element vector, both scan orders
        export_vec_row = export_elements_vec(buf, 3, 2; T = Vetra.ColorRGBX)
        @test export_vec_row == V
        @test export_elements_vec(buf, 3, 2; T = Vetra.ColorRGBX,
                                  row_major = false) == VC
        # export: straight via the actual toStraightAlpha kernel
        HS = UInt8[128, 0, 0, 128, 0, 128, 0, 128, 0, 0, 0, 0, 0, 0, 0, 0,
                   0, 0, 0, 0, 0, 0, 0, 0]
        S = export_elements(HS, 3, 2; T = Vetra.ColorRGBA)
        @test S[1, 1] == Vetra.ColorRGBA(255, 0, 0, 128)
        @test S[1, 2] == Vetra.ColorRGBA(0, 255, 0, 128)
        # export: raw matrix row-major and column-major
        rowflat = vcat(RM[1, :], RM[2, :])   # row-major flat over (2,12)
        colflat = UInt8[1, 0, 0, 255, 4, 0, 0, 255, 2, 0, 0, 255,
                        5, 0, 0, 255, 3, 0, 0, 255, 6, 0, 0, 255]
        @test export_raw(buf, 3, 2, lay) == rowflat
        @test export_raw(buf, 3, 2, lay_col) == colflat
        @test export_raw(buf, 3, 2, lay)[1:4] == [1, 0, 0, 255]
        # export: straight raw
        @test export_raw(HS, 3, 2, PixelLayout(3, 2, 4, true, false, true))[1:4] ==
            [255, 0, 0, 128]
        # export: float de-quantization (0..1)
        fvals = export_raw_f(HS, 3, 2, PixelLayout(3, 2, 4, true, false, true))
        @test fvals[1] == 1.0 && fvals[4] == 128 / 255
        # export: gray luma
        @test export_raw(buf, 3, 2, PixelLayout(3, 2, 1, false, false, true))[1] ==
            luma_byte(1, 0, 0)
        # wrong dest shape raises before any write (two-phase)
        @test export_shape_validate!((2, 3), 3, 2) === nothing
        @test_throws ArgumentError export_shape_validate!((3, 2), 3, 2)
        # truthful storage order
        @test storage_order(M) === :col
        @test storage_order(V) === :row
        @test storage_order(view(M, 1:2, 1:3)) === :col
    end

    # ------------------------------------------------------------------
    @testset "G12 upload validation + idempotent opaque staging [math]" begin
        # pre-dispatch validation leaves targets unchanged
        target = zeros(UInt8, 8)
        e = caught(() -> upload_validate(1, 2, 1, 2, 1))  # 1 px into a 2 px region
        @test e isa ArgumentError
        @test occursin("1 pixel", sprint(showerror, e))
        @test target == zeros(UInt8, 8)
        @test_throws ArgumentError upload_validate(3, 2, 1, 3, 1)
        # float-domain validation before any write
        @test_throws ArgumentError upload_validate_float(1.5)
        # §7 route 6 / §8.1 (revision 7): a STAGED upload completes at
        # its own tracked frontend handle's wait — the staged writeback
        # runs exactly once; an empty drawing flush in between is the
        # inert core no-op and does NOT complete it (negative control —
        # the v6 G12 scenario promised wait(empty flush!), which the
        # no-op rule contradicts)
        D = DemoProvider
        b7 = D.DeferredBackend()
        bind_target!(b7, CanvasTargetSpec(2, 1, 2f0, 4, 2, nothing))
        tr7 = SubmissionTracker(b7)
        up7 = upload_pixels!(b7, CanvasAsset(41, 1, 1, UInt8[255, 0, 0, 255]),
                             Vetra.rect(0f0, 0f0, 1f0, 1f0))
        staged_calls = Ref(0)
        fh7 = tracker_track(tr7, up7, () -> (staged_calls.x += 1))
        wait(tracker_noop(tr7))               # empty drawing flush
        @test staged_calls.x == 0             # no-op did not write back
        @test length(tr7.subs) == 1 &&
              tr7.subs[1].state === :pending  # upload still pending
        wait(fh7)                             # the upload's own wait
        @test staged_calls.x == 1             # writeback exactly once
        @test isempty(tr7.subs)               # retired
        wait(fh7)                             # idempotent
        @test staged_calls.x == 1             # …and still exactly once
        # idempotent opaque reconciliation: repeated identical writeback
        staged = Vetra.ColorRGBX(128, 0, 0, 128)
        dest = Vetra.ColorRGB(0, 0, 0)
        once = reconcile_opaque(staged, dest)
        @test once == Vetra.ColorRGBX(128, 0, 0, 255)
        twice = reconcile_opaque(once, Vetra.ColorRGB(0, 0, 0))
        @test twice == once                  # stable: 128 stays 128
        # without reconciliation the same writeback drifts (128 -> 192):
        @test _matte_rgb(staged, Vetra.ColorRGB(once.r, 0, 0)) ==
            Vetra.ColorRGB(192, 0, 0)
        # straight writeback conversion
        @test straight_byte(128, 128) == 255
        @test straight_byte(0, 128) == 0
        @test straight_byte(0, 0) == 0
        # §7 commit rule (frozen): pre-commit validation leaves the
        # destination untouched; a commit-phase fault after the first
        # store is TransferError(:partial) — indexed writeback is NOT a
        # transaction, even from owned, fully-validated staging — unless
        # the destination guarantees atomic commit (:unwritten + rollback)
        d1 = CommitDest(Int[7, 7, 7])
        e = caught(() -> commit_or_report!(d1, Int[1, 256]))
        @test e isa ArgumentError
        @test d1.stores == 0 && d1.values == Int[7, 7, 7]
        d2 = CommitDest(Int[7, 7, 7]; fail_at = 3)
        e2 = caught(() -> commit_or_report!(d2, Int[1, 2, 3]))
        @test e2 isa TransferError && e2.status === :partial
        @test d2.values == Int[1, 2, 7] && d2.stores == 3
        d3 = CommitDest(Int[7, 7, 7]; atomic = true, fail_at = 2)
        e3 = caught(() -> commit_or_report!(d3, Int[1, 2, 3]))
        @test e3 isa TransferError && e3.status === :unwritten
        @test d3.values == Int[7, 7, 7]   # rolled back
        d4 = CommitDest(Int[7, 7, 7])
        commit_or_report!(d4, Int[1, 2, 3])
        @test d4.values == Int[1, 2, 3]
    end

    # ------------------------------------------------------------------
    @testset "G13 storage-adapter surface + normative consumer trace [dispatch]" begin
        SH = StorageHost
        m = Matrix{Vetra.ColorRGBX}(undef, 2, 3)
        m[1, :] = [Vetra.ColorRGBX(1, 2, 3, 255), Vetra.ColorRGBX(4, 5, 6, 255),
                   Vetra.ColorRGBX(7, 8, 9, 255)]
        m[2, :] = [Vetra.ColorRGBX(10, 11, 12, 255), Vetra.ColorRGBX(13, 14, 15, 255),
                   Vetra.ColorRGBX(16, 17, 18, 255)]
        s = SH.HostAdapter(m)
        desc = storage_descriptor(s)
        @test s.descriptor_calls == 1
        @test desc.element === Vetra.ColorRGBX
        @test (desc.layout.width, desc.layout.height) == (3, 2)  # w=cols, h=rows
        @test desc.writable === true
        # zero-based physical regions: rect(0,0,1,1) addresses the
        # storage's FIRST element (the v4 one-based demo is corrected)
        a0 = storage_read(s, Vetra.rect(0f0, 0f0, 1f0, 1f0))
        @test s.read_calls == 1
        @test a0.data == [1, 2, 3, 255]
        a = storage_read(s, Vetra.rect(1f0, 0f0, 2f0, 2f0))
        @test (a.width, a.height) == (2, 2)
        @test a.data[1:4] == [4, 5, 6, 255]        # physical (1,0) = m[1,2]
        @test a.data[5:8] == [7, 8, 9, 255]        # physical (2,0) = m[1,3]
        @test a.data[9:12] == [13, 14, 15, 255]    # physical (1,1) = m[2,2]
        storage_write!(s, Vetra.rect(0f0, 0f0, 1f0, 1f0),
                       UInt8[255, 0, 0, 255])
        @test s.write_calls == 1
        @test m[1, 1] == Vetra.ColorRGBX(255, 0, 0, 255)
        # allocation takes the explicit type AND dimensions — a
        # descriptor cannot infer the container shape
        out = storage_alloc(s, typeof(s), (4, 2))
        @test s.alloc_calls == 1
        @test size(out.matrix) == (2, 4)           # (height, width)
        @test_throws ArgumentError storage_alloc(s, RecordingAdapter, (4, 2))
        # in-place route requires writable storage (record-level gate)
        ro = StorageReadonly()
        @test storage_descriptor(ro).writable === false
        @test_throws ArgumentError adapter_dest_validate(storage_descriptor(ro))
        # --- normative consumer trace (record machine, §13) ---
        t = ConsumerTarget(2, 3)
        s2 = RecordingAdapter(Matrix{Vetra.ColorRGBX}(undef, 3, 2))
        consumer_snapshot!(s2, t)
        @test s2.calls == [:descriptor, :write]    # no read/alloc on this route
        @test t.ops == [:flush, :read]
        @test s2.matrix[1, 1] ==
            Vetra.ColorRGBX(1, 2, 3, 4)            # owned premul RGBA8 bytes
        # validation failure ⇒ ZERO read/write/alloc calls on the adapter
        # (and no flush/read on the canvas side — validation is first)
        s3 = RecordingAdapter(Matrix{Vetra.ColorRGBX}(undef, 3, 2),
                              writable = false)
        t2 = ConsumerTarget(2, 3)
        e = caught(() -> consumer_snapshot!(s3, t2))
        @test e isa ArgumentError
        @test s3.calls == [:descriptor]
        @test t2.ops == Symbol[]
        s4 = RecordingAdapter(Matrix{Vetra.ColorRGBX}(undef, 3, 2))
        t3 = ConsumerTarget(4, 4)
        e = caught(() -> consumer_snapshot!(s4, t3))
        @test e isa ArgumentError
        @test occursin("storage is 2×3", sprint(showerror, e))
        @test s4.calls == [:descriptor]
        # allocating route: explicit type AND dimensions; the returned
        # adapter is filled through its own public descriptor/write
        t4 = ConsumerTarget(2, 3)
        s5 = RecordingAdapter(Matrix{Vetra.ColorRGBX}(undef, 3, 2))
        out5 = consumer_snapshot_alloc(s5, t4)
        @test out5 isa RecordingAdapter
        @test size(out5.matrix) == (3, 2)
        @test s5.calls == [:descriptor, :alloc]
        @test out5.calls == [:descriptor, :write]
        @test t4.ops == [:flush, :read]
        @test out5.matrix[2, 1] ==
            Vetra.ColorRGBX(9, 10, 11, 12)         # physical row 1, col 0
        # direct provider-method calls prove the PROVIDER SURFACE only —
        # not consumer dispatch order (the normative trace is §13; the
        # consumer routes above execute it as a record machine)
    end

    # ------------------------------------------------------------------
    @testset "G9 readback identity vs the SAVED request [record]" begin
        bs = BrowserSession("canvas-1")
        req = issue_readback(bs)
        @test req.id == 1
        @test (req.scope, req.session, req.generation, req.submission) ==
            ("canvas-1", 1, 1, 0)
        @test snapshot_roundtrip(bs, req.id) isa ReadbackResponse
        @test isempty(bs.pending)                    # consumed exactly once
        # a snapshot with no pending request cannot use an old authorization
        resp2 = ReadbackResponse(req.id, bs.scope, bs.session, bs.generation,
                                 bs.completed, "rgba8-premul", 1, 1,
                                 UInt8[255, 0, 0, 255])
        @test_throws ArgumentError deliver_response(bs, resp2)
        # fresh request round-trip
        req2 = issue_readback(bs)
        @test req2.id == 2
        @test snapshot_roundtrip(bs, req2.id) isa ReadbackResponse
        # identity rejections (vs the SAVED request; the pending request
        # survives every rejection — an invalid response consumes nothing)
        bs2 = BrowserSession("canvas-1")
        r = issue_readback(bs2, (1, 1, 1, 1))
        for (mutate, msg) in
            ((x -> x.id = 999, "unknown request id"),
             (x -> x.scope = "foreign", "wrong-target"),
             (x -> x.session = 0, "stale-session"),
             (x -> x.session = 2, "future-session"),
             (x -> x.generation = 2, "superseded-generation"),
             (x -> x.submission = 5, "superseded-submission"),
             (x -> x.encoding = "png-base64", "invalid-encoding"),
             (x -> (x.width, x.height) = (999, 999), "dimension-mismatch"),
             (x -> x.data = UInt8[], "decoded-length"))
            bad = ReadbackResponse(r.id, r.scope, r.session, r.generation,
                                   r.submission, "rgba8-premul", 1, 1,
                                   UInt8[255, 0, 0, 255])
            mutate(bad)
            e = caught(() -> deliver_response(bs2, bad))
            @test e isa ArgumentError
            @test occursin(msg, sprint(showerror, e))
            @test haskey(bs2.pending, r.id)          # not consumed
        end
        @test snapshot_roundtrip(bs2, r.id) isa ReadbackResponse
        # the saved submission count, not the current one: issue at 0
        # completed, then one submission completes; a response echoing 0
        # is accepted, one echoing the (new) current count 1 is rejected
        bs3 = BrowserSession("canvas-1")
        r3 = issue_readback(bs3, (0, 0, 2, 2))
        bs3.completed += 1
        stale = ReadbackResponse(r3.id, bs3.scope, bs3.session, bs3.generation,
                                 1, "rgba8-premul", 2, 2,
                                 UInt8[255 for _ in 1:16])
        @test_throws ArgumentError deliver_response(bs3, stale)
        @test haskey(bs3.pending, r3.id)
        @test snapshot_roundtrip(bs3, r3.id) isa ReadbackResponse
        # context loss invalidates everything immediately
        bs4 = BrowserSession("canvas-1")
        r4 = issue_readback(bs4)
        lose_context!(bs4)
        @test isempty(bs4.pending)
        late = ReadbackResponse(r4.id, bs4.scope, 1, 1, 0, "rgba8-premul",
                                 1, 1, UInt8[255, 0, 0, 255])
        @test_throws ArgumentError deliver_response(bs4, late)
        recover!(bs4)
        @test (bs4.session, bs4.generation) == (2, 2)
        r5 = issue_readback(bs4)
        @test r5.session == 2 && r5.generation == 2
        @test snapshot_roundtrip(bs4, r5.id) isa ReadbackResponse
        # timeout retires the request but retains session ownership
        bs5 = BrowserSession("canvas-1")
        r6 = issue_readback(bs5)
        timeout!(bs5, r6.id)
        @test isempty(bs5.pending)
        @test (bs5.session, bs5.generation) == (1, 1)
    end

    # ------------------------------------------------------------------
    @testset "G10 browser document: namespace, canonical bytes, submissions [record]" begin
        # one monotonic namespace: initial, draw, upload never collide
        d = doc_new("canvas-1", 2, 2,
                    CanvasAsset(0, 2, 2,
                                UInt8[9, 9, 9, 255, 10, 10, 10, 255,
                                      11, 11, 11, 255, 12, 12, 12, 255]))
        @test doc_ops(d) == 1
        draw_asset = WireAsset(1, 1, "rgba8-straight", UInt8[255, 0, 0, 255])
        draw_cmd = WireCommand("image", Dict(
            # revision 6: srcRect fractional (the captured Rect as-is);
            # Float32 values preserved on the wire (no widening)
            "assetId" => doc_capture!(d), "srcRect" => (0f0, 0f0, 1f0, 1f0),
            "destRect" => (0.5f0, 0f0, 1f0, 1f0),
            "transform" => _mat9(Vetra.mat3()),
            "sampling" => Dict("filter" => "linear", "edge" => "clamp"),
            "composition" => "source-over", "opacity" => 1f0,
            "clips" => WireClip[]))
        doc_add!(d, draw_cmd, draw_asset, 100_000, 1_000)
        (up_asset, up_cmd) = doc_upload!(
            d, UInt8[0, 0, 255, 255], Vetra.rect(1f0, 1f0, 1f0, 1f0),
            100_000, 1_000)
        @test length(d.assets) == 3
        # revision 7: the initial is keyed by its SUPPLIED captured id
        # (here 0); the separate counter advances only on captures
        @test sort(collect(keys(d.assets))) == [0, 1, 2]   # collision-free
        @test d.commands[1].fields["assetId"] == 0   # initial retained
        @test d.commands[3].fields["assetId"] == 2  # upload not id 1
        @test up_asset.id == 2 && up_cmd.fields["assetId"] == 2
        doc_check!(d)                            # every id resolves
        # revision 6: a DELIBERATELY non-consecutive captured id — the
        # intervening ids were consumed by pending/saved captures, not
        # by this document; insertion keys by the command's captured id
        # (the v5 helper stored the asset under its private next_id,
        # leaving the command's id unresolved)
        gap_id = d.next_id + 3
        gap_cmd = WireCommand("image", Dict(
            "assetId" => gap_id, "srcRect" => (0f0, 0f0, 1f0, 1f0),
            "destRect" => (0f0, 0f0, 1f0, 1f0),
            "transform" => _mat9(Vetra.mat3()),
            "sampling" => Dict("filter" => "linear", "edge" => "clamp"),
            "composition" => "source-over", "opacity" => 1f0,
            "clips" => WireClip[]))
        doc_add!(d, gap_cmd, WireAsset(1, 1, "rgba8-straight",
                                       UInt8[0, 255, 0, 255]),
                 100_000, 1_000)
        @test haskey(d.assets, gap_id) && !haskey(d.assets, gap_id - 1)
        doc_check!(d)
        # upload dispatch identity: the provider receives the captured
        # asset (its id), not bare (region, bytes) — an intervening
        # upload's id is discoverable alongside a pending draw
        ur = UploadRecorderBackend()
        upload_pixels!(ur, up_asset, Vetra.rect(1f0, 1f0, 1f0, 1f0))
        @test ur.uploads == [(2, (1, 1, 1, 1))]
        # §7 ordered upload route (revision 7): the older pending
        # drawing is submitted BEFORE the upload dispatch, and the
        # canvas-level upload returns its TRACKED frontend handle,
        # completed through the §8.1 single route
        D = DemoProvider
        b5 = D.DeferredBackend()
        bind_target!(b5, CanvasTargetSpec(2, 1, 2f0, 4, 2, nothing))
        tr5 = SubmissionTracker(b5)
        batch5 = CommandBatch(CanvasOp[], Dict{Int, CanvasAsset}(),
                              Vetra.Vec2(2, 1), 2f0)
        fh5 = tracker_submit(tr5, batch5)
        up5 = upload_pixels!(b5, up_asset, Vetra.rect(1f0, 1f0, 1f0, 1f0))
        @test b5.calls == [:submit, :upload]
        fhup = tracker_track(tr5, up5)            # the tracked frontend
                                                 # handle (frozen return)
        wait(fhup)                                # the upload's own wait
        wait(fh5)
        @test isempty(tr5.subs)                  # both retired on completion
        # upload-only work: its own admitted submission + ACK even when
        # the next drawing flush is empty (one set-pixels command, one
        # asset)
        bsu = BrowserSubmissions("canvas-1")
        rec_u = submit_browser(bsu, 1, 1)
        deliver_execution_ack!(bsu, ExecutionAck(rec_u.id, "canvas-1", 1, 1,
                                                "success", ""))
        @test wait_browser_sub(bsu, rec_u.id) === :complete
        # execution-ack identity: one ack per submission, identity vs the
        # SAVED submission record; unknown/stale/wrong-scope acks are
        # rejected and consume nothing
        bsx = BrowserSubmissions("canvas-1")
        rec = submit_browser(bsx, 2, 1)
        @test (rec.id, rec.scope, rec.session, rec.generation) ==
            (1, "canvas-1", 1, 1)
        for (mutate, msg) in
            ((x -> x.id = 999, "unknown submission"),
             (x -> x.scope = "foreign", "wrong-target"),
             (x -> x.session = 0, "stale-session"),
             (x -> x.session = 2, "future-session"),
             (x -> x.generation = 2, "superseded-generation"))
            bad = ExecutionAck(rec.id, rec.scope, rec.session, rec.generation,
                               "success", "")
            mutate(bad)
            e = caught(() -> deliver_execution_ack!(bsx, bad))
            @test e isa ArgumentError
            @test occursin(msg, sprint(showerror, e))
            @test bsx.states[1] === :pending             # not consumed
        end
        deliver_execution_ack!(bsx, ExecutionAck(1, "canvas-1", 1, 1,
                                                "error", "boom"))
        @test bsx.states[1] === :failed
        @test_throws BackendSubmitError wait_browser_sub(bsx, 1)
        e = caught(() -> wait_browser_sub(bsx, 1))       # sticky re-raise
        @test e isa BackendSubmitError && e.detail == "boom"
        e = caught(() -> deliver_execution_ack!(
            bsx, ExecutionAck(1, "canvas-1", 1, 1, "success", "")))
        @test e isa ArgumentError                        # non-pending
        rec2 = submit_browser(bsx, 1, 0)
        @test rec2.id == 2                               # monotonic
        deliver_execution_ack!(bsx, ExecutionAck(2, "canvas-1", 1, 1,
                                                "success", ""))
        @test wait_browser_sub(bsx, 2) === :complete
        # canonical serialization: the pinned 2×2 initial document, exact
        # bytes (hand-derived; verified independently of any estimator) —
        # revision 7: the captured id is 1 and the separate counter has
        # already advanced past it (already-reserved-ID convention)
        d2 = doc_new("canvas-1", 2, 2,
                     CanvasAsset(1, 2, 2,
                                 UInt8[9, 9, 9, 255, 10, 10, 10, 255,
                                       11, 11, 11, 255, 12, 12, 12, 255]);
                     next_id = 2)
        @test d2.next_id == 2                     # not advanced for the
        @test canonical_document(d2) ==
            """{"schema":"vetra.canvas.v1","provider":"vetra/browser/canvas2d","profile":"portable-2d","generation":1,"session":1,"scope":"canvas-1","size":[2,2],"deviceScale":1.0,"assets":{"1":{"kind":"image","width":2,"height":2,"encoding":"rgba8-straight","data":"CQkJ/woKCv8LCwv/DAwM/w=="}},"commands":[{"op":"set-pixels","assetId":1,"rect":[0,0,2,2]}],"fallbacks":[]}"""
        @test doc_bytes(d2) == 357
        # canonical numbers are valid JSON: Float32 shortest decimal
        @test string(floatmax(Float32)) == "3.4028235e38"
        @test all(c -> isdigit(c) || c in ".+-eE", string(floatmax(Float32)))
        @test length(string(typemax(Int))) == 19
        @test all(isdigit, collect(string(typemax(Int))))
        # the retracted v4 target: typemax(Float32) is Inf — not a JSON
        # number at all, so it was never a meaningful 16-digit bound
        @test string(typemax(Float32)) == "Inf"
        # escape: 100 quotes serialize to 202 bytes (\"×100 + delimiters)
        @test 2 + length(json_escape("\""^100)) == 202
        # variable geometry counts its ACTUAL serialization: a rect fill
        # vs a moveTo + 100 lineTo fill differ by exactly 4·Δfloats bytes
        # (each float serializes as 3 digits + a comma)
        p_small = Vetra.newPath(); Vetra.rect(p_small, 0f0, 0f0, 1f0, 1f0)
        p_big = Vetra.newPath(); Vetra.moveTo(p_big, 0f0, 0f0)
        for i in 1:100
            Vetra.lineTo(p_big, Float32(i % 2), 0f0)
        end
        mk_fill(p) = wire_command(FillOp(p,
            OwnedPaint(Vetra.SolidPaint, Vetra.rgba(255, 0, 0, 255), 1f0,
                       Vetra.NormalBlend, 0, Vetra.mat3(),
                       Vetra.Vec2[], Vetra.ColorStop[]),
            Vetra.mat3(), Vetra.NonZero, ClipScope[], SourceOver))
        small, big = canon_json(canon_command(mk_fill(p_small))),
                    canon_json(canon_command(mk_fill(p_big)))
        @test length(p_big.commands) - length(p_small.commands) == 290
        @test length(big) - length(small) == 4 * 290
        # the 64×64 straight-RGBA8 initial: base64 data alone is
        # ⌈16384/3⌉·4 = 21848 bytes and the full canonical document is
        # 22187 — over any 17000-byte limit (the retracted v4 formula had
        # counted 16816 and admitted it)
        d64 = doc_new("canvas-1", 64, 64,
                      CanvasAsset(1, 64, 64, zeros(UInt8, 4 * 64 * 64));
                      next_id = 2)
        @test length(base64encode(d64.assets[1].data)) == 21848
        @test doc_bytes(d64) == 22187
        @test doc_admit(d64, 17_000, 1_000) == "payload-max-bytes"
        e = caught(() -> doc_admit!(d64, 17_000, 1_000))
        @test e isa ArgumentError
        @test occursin("payload-max-bytes", sprint(showerror, e))
        # the bound applies at construction (initial import) and before
        # every flush mutation — the document is left unmutated
        before = (doc_bytes(d), doc_ops(d))
        e = caught(() -> doc_add!(d, draw_cmd, draw_asset, before[1], 10))
        @test e isa ArgumentError
        @test (doc_bytes(d), doc_ops(d)) == before
        @test doc_admit(d, 100_000, 2) == "payload-max-ops"
        # destructive resize: old content cleared, generation bumped,
        # the capture namespace CONTINUES (revision 7: the separate
        # counter carries over; the v5/v6 helpers reset it or re-keyed
        # the initial asset)
        ns_before = d.next_id
        d3 = doc_resize(d, 4, 4, nothing)
        @test isempty(d3.commands) && isempty(d3.assets)
        @test d3.generation == d.generation + 1
        @test d3.session == d.session
        @test d3.next_id == ns_before
        (up3, cmd3) = doc_upload!(d3, UInt8[255, 0, 0, 255],
                                  Vetra.rect(1f0, 1f0, 1f0, 1f0),
                                  100_000, 1_000)
        @test up3.id == ns_before                # continues, not reset
        doc_check!(d3)
        # revision 7: initial.id is PRESERVED on construction and on
        # destructive resize — deliberately unequal initial.id/next_id
        # (id 41 reserved through a real capture; counter now 42)
        d7 = doc_new("canvas-1", 2, 2, nothing; next_id = 41)
        a41 = CanvasAsset(doc_capture!(d7), 1, 1, UInt8[255, 0, 0, 255])
        @test a41.id == 41 && d7.next_id == 42
        d7r = doc_resize(d7, 2, 2, a41)          # resize with the
                                                # captured asset
        @test haskey(d7r.assets, 41)             # keyed by the captured
                                                # id — not re-keyed to 42
        @test d7r.commands[1].fields["assetId"] == 41
        @test d7r.next_id == 42                  # counter never re-
                                                # reserved for it
        doc_check!(d7r)                          # integrity holds because
                                                 # the key IS 41 — not
                                                 # because two wrong
                                                 # references agree
        # a future (unreserved) initial id is rejected by name
        ef = caught(() -> doc_new("canvas-1", 1, 1,
                                  CanvasAsset(5, 1, 1, UInt8[1, 2, 3, 4]);
                                  next_id = 1))
        @test ef isa ArgumentError
        @test occursin("not yet reserved", sprint(showerror, ef))
        # disposal: fresh scope, old scope not reusable
        s1 = fresh_scope(); s2 = fresh_scope()
        @test s1 != s2
    end

    # ------------------------------------------------------------------
    @testset "G15 wire records: tags, fields, canonical fixtures [record]" begin
        @test length(WIRE_TAGS) == 10
        @test length(Set(WIRE_TAGS)) == 10
        # the stroke record carries the full 11-field set — NO winding
        # (StrokeOp has none; the v4 record invented the field)
        @test WIRE_TAG_FIELDS["stroke"] ==
            ["path", "paint", "transform", "composition", "clips",
             "width", "cap", "join", "miterLimit", "dashes", "dashOffset"]
        @test !("winding" in WIRE_TAG_FIELDS["stroke"])
        # image record: srcRect integer (capture truncation) / destRect
        # fractional; set-pixels carries the region for uploads
        @test WIRE_TAG_FIELDS["image"] ==
            ["assetId", "srcRect", "destRect", "transform", "sampling",
             "composition", "opacity", "clips"]
        @test WIRE_TAG_FIELDS["set-pixels"] == ["assetId", "rect"]
        # paint mapping: 1:1 PaintKind → wire kind
        @test paint_wire_kind(Vetra.SolidPaint) == "solid"
        @test paint_wire_kind(Vetra.ImagePaint) == "image"
        @test paint_wire_kind(Vetra.TiledImagePaint) == "tiled-image"
        @test paint_wire_kind(Vetra.LinearGradientPaint) == "linear-gradient"
        @test paint_wire_kind(Vetra.RadialGradientPaint) == "radial-gradient"
        @test paint_wire_kind(Vetra.AngularGradientPaint) == "angular-gradient"
        # a linear gradient never serializes as a tiled-image, and only
        # image/tiled paints carry an asset id
        @test_throws ArgumentError validate_wire_paint!(WirePaint(
            "tiled-image", nothing, 1.0, nothing, 7, nothing, nothing,
            nothing))
        @test_throws ArgumentError validate_wire_paint!(WirePaint(
            "solid", nothing, 1.0, nothing, nothing, nothing, nothing,
            nothing))
        @test_throws ArgumentError validate_wire_paint!(WirePaint(
            "linear-gradient", nothing, 1f0, nothing, 7, nothing,
            [(0f0, 1f0)], nothing))
        validate_wire_paint!(WirePaint("linear-gradient", nothing, 1f0,
                                       nothing, nothing, nothing,
                                       [(0f0, 1f0), (1f0, 0f0)],
                                       [(0, 0, 255, 255, 0f0),
                                        (255, 0, 0, 255, 1f0)]))
        # a real fill record from the actual Vetra primitives — the
        # hand-derived canonical serialization, pinned byte-exact
        path = Vetra.newPath(); Vetra.rect(path, 0f0, 0f0, 4f0, 6f0)
        @test length(path.commands) == 13      # frozen rect encoding
        op = FillOp(path,
                    OwnedPaint(Vetra.SolidPaint, Vetra.rgba(255, 0, 0, 255),
                               1f0, Vetra.NormalBlend, 0, Vetra.mat3(),
                               Vetra.Vec2[], Vetra.ColorStop[]),
                    Vetra.translate(Vetra.Vec2(1f0, 2f0)),
                    Vetra.NonZero,
                    [ClipScope(path, Vetra.NonZero)], SourceOver)
        # clip-free variant — the pinned canonical rect-fill record
        op0 = FillOp(path, op.paint, op.tform, op.winding, ClipScope[],
                     SourceOver)
        cmd = wire_command(op)
        cmd0 = wire_command(op0)
        validate_wire_command!(cmd)
        @test cmd.tag == "fill"
        @test length(cmd.fields["path"]) == 13
        @test cmd.fields["transform"] == (1.0f0, 0.0f0, 0.0f0,
                                         0.0f0, 1.0f0, 0.0f0,
                                         1.0f0, 2.0f0, 1.0f0)
        @test cmd.fields["paint"].color == (255, 0, 0, 255)
        @test cmd.fields["paint"].artistic === nothing
        @test length(cmd.fields["clips"]) == 1
        @test canon_json(canon_command(cmd0)) ==
            """{"op":"fill","path":[1.0,0.0,0.0,2.0,4.0,0.0,2.0,4.0,6.0,2.0,0.0,6.0,0.0],"winding":"nonzero","paint":{"kind":"solid","color":[255,0,0,255],"opacity":1.0,"artistic":null,"assetId":null,"imageTransform":null,"handles":null,"stops":null},"transform":[1.0,0.0,0.0,0.0,1.0,0.0,1.0,2.0,1.0],"composition":"source-over","clips":[]}"""
        @test length(canon_json(canon_command(cmd0))) == 325
        # the clear rect stays FRACTIONAL — no Int truncation at the wire
        clr = ClearOp(Vetra.rect(0.5f0, 1.25f0, 2f0, 3.75f0),
                      Vetra.translate(Vetra.Vec2(1f0, 2f0)), ClipScope[])
        clrc = wire_command(clr)
        validate_wire_command!(clrc)
        @test clrc.fields["rect"] == (0.5f0, 1.25f0, 2.0f0, 3.75f0)
        @test canon_json(canon_command(clrc)) ==
            """{"op":"clear","rect":[0.5,1.25,2.0,3.75],"transform":[1.0,0.0,0.0,0.0,1.0,0.0,1.0,2.0,1.0],"clips":[]}"""
        @test length(canon_json(canon_command(clrc))) == 102
        # revision 6 numeric policy fixture: a 0.1f0 clear corner
        # serializes as the Float32 shortest decimal "0.1" — not the
        # widened-Float64 artifact 0.10000000149011612 (+16 bytes)
        clr2 = ClearOp(Vetra.rect(0.1f0, 0.1f0, 0.1f0, 0.1f0),
                       Vetra.mat3(), ClipScope[])
        @test canon_json(canon_command(wire_command(clr2))) ==
            """{"op":"clear","rect":[0.1,0.1,0.1,0.1],"transform":[1.0,0.0,0.0,0.0,1.0,0.0,0.0,0.0,1.0],"clips":[]}"""
        @test length(canon_json(canon_command(wire_command(clr2)))) == 100
        # image record: srcRect FRACTIONAL (the captured Rect as-is — the
        # v5 Int truncation threw InexactError at x=0.5f0)
        di = DrawImageOp(1, Vetra.rect(0.5f0, 0f0, 2f0, 2f0),
                         Vetra.rect(0f0, 0f0, 4f0, 4f0), Vetra.mat3(),
                         LinearSampling, SourceOver, 1f0, ClipScope[])
        dic = wire_command(di)
        validate_wire_command!(dic)
        @test dic.fields["srcRect"] == (0.5f0, 0f0, 2f0, 2f0)
        @test occursin("\"srcRect\":[0.5,0.0,2.0,2.0]",
                       canon_json(canon_command(dic)))
        # revision 7 numeric policy: image opacity preserves the
        # declared Float32 (the v6 mapping widened exactly this one
        # field: 0.1f0 ⇒ 0.10000000149011612, +16 canonical bytes)
        di2 = DrawImageOp(1, Vetra.rect(0.5f0, 0f0, 2f0, 2f0),
                          Vetra.rect(0f0, 0f0, 4f0, 4f0), Vetra.mat3(),
                          LinearSampling, SourceOver, 0.1f0, ClipScope[])
        dic2 = wire_command(di2)
        validate_wire_command!(dic2)
        @test dic2.fields["opacity"] === 0.1f0
        @test occursin("\"opacity\":0.1,", canon_json(canon_command(dic2)))
        # effect regions FRACTIONAL (no Int conversion at the wire)
        eff2 = EffectOp(:blur, 1.5f0, Vetra.Vec2(), Vetra.rgb(0, 0, 0), 1f0,
                        Vetra.rect(0.5f0, 0f0, 10f0, 10f0),
                        Vetra.rect(0.5f0, 0f0, 10f0, 10f0), Vetra.mat3(),
                        ClipScope[])
        efc = wire_command(eff2)
        validate_wire_command!(efc)
        @test efc.fields["inRegion"] == (0.5f0, 0f0, 10f0, 10f0)
        # missing / extra / unknown fields are rejected
        bad = WireCommand("fill", Dict(cmd.fields))
        pop!(bad.fields, "clips")
        @test_throws ArgumentError validate_wire_command!(bad)
        extra = WireCommand("fill", Dict(cmd.fields))
        extra.fields["bogus"] = 1
        @test_throws ArgumentError validate_wire_command!(extra)
        @test_throws ArgumentError validate_wire_command!(
            WireCommand("other", Dict("bogus" => 1)))
        # full record coverage: every core op maps to its same-tagged
        # record with exactly the documented field set
        st = StrokeOp(path, op.paint, op.tform, 4f0, Vetra.RoundCap,
                      Vetra.RoundJoin, 2f0, Float32[2f0, 3f0], 1f0,
                      ClipScope[], SourceOver)
        stc = wire_command(st)
        validate_wire_command!(stc)
        @test stc.fields["dashOffset"] == 1.0
        @test stc.fields["cap"] == "round"
        txt = TextOp([GlyphPath(path, Vetra.mat3())], op.paint, Vetra.mat3(),
                     SourceOver, ClipScope[])
        validate_wire_command!(wire_command(txt))
        eff = EffectOp(:blur, 2f0, Vetra.Vec2(), Vetra.rgb(0, 0, 0), 1f0,
                       Vetra.rect(0f0, 0f0, 10f0, 10f0),
                       Vetra.rect(0f0, 0f0, 10f0, 10f0), Vetra.mat3(),
                       ClipScope[])
        validate_wire_command!(wire_command(eff))
        # the fallback record embeds the retained original work
        rfb = RasterFallbackOp("effect.blur", "provider raster", :op,
                               FallbackWork([op], Dict(1 =>
                               CanvasAsset(1, 1, 1, UInt8[255, 0, 0, 255]))),
                               ClipScope[])
        fbc = wire_command(rfb)
        validate_wire_command!(fbc)
        canon_json(canon_command(fbc))
        # numeric rule: shortest decimal, JSON-valid (the canonical
        # serializer rejects anything else)
        @test string(0.5f0) == "0.5"
        @test string(1.0f0) == "1.0"
    end

end
