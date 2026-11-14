# Canvas contract (R010) — frozen public interfaces

Status: **approved contract freeze (R010, revision 9)**, 2026-11-14.
Qwen3.8 candidate `c81e15b` passed coordinator and independent review (D039).
The candidate checker passes 524 assertions on Julia 1.13.3 and 1.10.13;
separate coordinator and independent probes pass 103 and 271 assertions per
version. This is contract/boundary evidence, not production Canvas or backend
implementation. Earlier candidate history is retained in the R010 task record.
This freezes the exact types, signatures, defaults, lifecycle, ownership and
error rules of the renderer-independent `Canvas` frontend, the backend
extension protocol, the normalized command/asset model, the pixel-storage
boundary, the browser payload boundary (Canvas2D and the separately added
WebGL2 provider), the document backends, and the renderer/storage/codec/
media/display extension seams. [CANVAS_DESIGN.md](CANVAS_DESIGN.md) is the
rationale; this document is the implementation gate. The 2026-11-12 user
amendment (WebGL2 provider R053–R055, native GPU + browser showcases) is
included. These are implementation contracts; runtime work follows the
dependencies and explicit ownership in `tasks/CANVAS_ROADMAP.md`.

**Evidence-level rule (revision 4 scope correction, kept).** R010's
acceptance is this reviewed contract plus the compact defect-scenario
register (§19) and a small executable boundary check
(`tasks/r010/boundary_check.jl`) that imports the actual Vetra primitives
and verifies only arithmetic/record/dispatch boundaries. The revision-3
4,660-line parallel frontend is **retired** (deleted, not moved): Canvas
recording, drawing execution, text metrics, hit tests, effects, picture
replay, raster-fallback execution, the browser runtime, the array engine and
PDF publication are **not** implemented or re-implemented here. Runtime
acceptance for those behaviors belongs to their roadmap tasks (R020/R021/
R022/R023 for commands/frontend/storage/transfers, R013 for the external
package, R050–R054 for the browser, R061–R063 for documents). Retired mock
failures are not runtime fixes: every v1–v4 defect scenario remains visible
in §19 with its required behavior, normative clause and downstream owner,
and stays open until its owner task is reviewed.

**One authoritative definition per boundary (revision 5 consolidation).**
Every normative boundary in this document has exactly one owning clause;
repeated call sites link to it instead of restating it. Revision-5
corrections consolidated, rather than layering: the §7 pixel table
(shape/scan/alpha/conversion/`:direct`/commit) is the single authority
referenced by §4 constructors, §7 snapshots and §13 adapter routes; §13 is
the single authority for the canonical adapter exchange and consumer
trace; §14 is the single authority for recording losslessness, the legacy
`Picture` adapter and placement; §11 is the single authority for the wire
records, canonical serialization/accounting and transport identity
(submission/execution-ACK, readback); §10 is the single authority for
physical sizing and the `resize!` signature.

Scope rule (review item 1): the contract freezes the **full** 2D feature set
of the approved plan — composition operators and artistic blends as
separate state, painted (non-solid) strokes, tiled paints, image
compositing with explicit sampling — with their semantics. Backend
capabilities may report those features unsupported until the owning
implementation task (R031/R032/R033/R043/…) passes; the frontend semantics
must not prohibit them. Legacy `Context` behavior is unchanged (migration
§14); legacy limitations are not canvas limitations.

All code blocks use concrete Julia 1.10-compatible types. New API is
snake_case; existing camelCase names are frozen legacy (docs/MIGRATION.md).

## 1. Versioning and protocol identity

- `canvas_protocol_version()::Int` returns `1` (core function, frozen value).
- A backend advertises the major version it implements in
  `BackendCapabilities.protocol`. Binding a backend whose
  `protocol != 1` raises
  `ArgumentError("backend protocol version $(n) not supported; core supports 1")`
  before any target is bound.
- Evolution rule: a new provider for existing primitives needs zero core
  edits. A new primitive or semantic guarantee requires a reviewed,
  versioned contract change (major bump), never a silent field.
- Fidelity profiles are inherited verbatim from CANVAS_DESIGN.md §4 (CPU
  regression, portable 2D, native text/display). This contract defines the
  portable-2D profile's state machine and reference equations; per-feature
  tolerance bounds are set by R011 with independently derived expected
  values before implementation output is examined.

## 2. Core types (exact)

```julia
abstract type CanvasBackend end    # zero-method marker; providers own subtypes
abstract type CanvasSubmission end # completion handle: providers own their
                                   # subtypes (§8 five-method protocol); the
                                   # core owns the tracked frontend wrapper
                                   # (the `TrackedSubmission` record, §8.1
                                   # revision 9)

struct CompositionOperator         # house struct-const pattern (cf. BlendMode)
    value::Int
end
# HTML compositing operators (W3C Compositing / WHATWG canvas), frozen order:
const SourceOver = CompositionOperator(0)   # default
const SourceIn   = CompositionOperator(1)
const SourceOut  = CompositionOperator(2)
const SourceAtop = CompositionOperator(3)
const Over       = CompositionOperator(4)   # destination-over
const In         = CompositionOperator(5)
const Out        = CompositionOperator(6)
const Atop       = CompositionOperator(7)
const Xor        = CompositionOperator(8)
const Copy       = CompositionOperator(9)   # "copy" (replaces legacy OverwriteBlend as state)
const Lighter    = CompositionOperator(10)  # additive

struct CapabilityLevel
    value::Int
end
const NativeCapability      = CapabilityLevel(0)
const LoweredCapability     = CapabilityLevel(1)
const FallbackCapability    = CapabilityLevel(2)
const UnsupportedCapability = CapabilityLevel(3)

struct CapabilityStatus
    level::CapabilityLevel
    note::String                   # provider-owned detail, "" allowed
end

struct BackendCapabilities
    protocol::Int                  # 1
    provider::String               # "vetra/cpu" | "vetra/vulkan" |
                                   # "vetra/browser/canvas2d" |
                                   # "vetra/browser/webgl2" | "vetra/pdf" |
                                   # "vetra/svg" | provider-owned
    pixel_profile::String          # "rgba8-premul" (portable) or provider string
    features::Dict{String, CapabilityStatus}
    limits::Dict{String, Int}      # provider-owned namespaced limits
end

struct CanvasTargetSpec
    logical_width::Int             # validated logical dims (§4 rule 1 —
    logical_height::Int            # the single input-size invariant)
    device_scale::Float32
    physical_width::Int            # §10 checked rounding
    physical_height::Int
    initial::Union{CanvasAsset, Nothing}   # imported pixels, or nothing;
                                           # iff present: asset dims ==
                                           # (physical_width, physical_height)
                                           # and length(data) ==
                                           # 4·physical_width·physical_height
end

struct StorageReport
    mode::Symbol                   # :direct | :staged | :owned
    layout::Symbol                 # :row | :col (the actual storage scan order)
    copied::Bool                   # true iff construction copied input pixels
end

struct FallbackReport
    op_index::Int                  # 1-based position of the marker in the sealed batch
    feature::String                # the failing capability id (§9)
    reason::String
    scope::Symbol                  # :op | :group | :frame | :page
end

struct DrawBounds
    rect::Rect                     # local canvas units, 0-based
    conservative::Bool             # superset; false ⇒ exact geometry box
    unknown::Bool                  # true ⇒ destination-dependent; redraw all
end
```

Error types (all `<: Exception`, frozen field sets):

```julia
struct CanvasClosedError <: Exception
    op::Symbol                     # :flush! | :snapshot | :close | :fill! ...
end
struct BackendCapabilityError <: Exception
    feature::String                # capability id (§9)
    op::Symbol                     # the drawing call that tripped preflight
end
struct BackendSubmitError <: Exception
    detail::String                 # provider-owned message
end
struct SnapshotError <: Exception
    kind::Symbol                   # Symbol("readback-timeout") |
                                   # Symbol("readback-failed") |
                                   # Symbol("offline-readback")
    detail::String
end
struct TransferError <: Exception
    status::Symbol                 # :unwritten | :partial
    detail::String
end
```

Dash-containing symbol values (e.g. `Symbol("offline-readback")`) are
constructed with `Symbol(...)`; no other nonstandard syntax is required
anywhere in this contract.

## 3. `Canvas` state (exact)

```julia
mutable struct Canvas{B<:CanvasBackend}
    backend::B
    width::Int                      # logical, > 0
    height::Int                     # logical, > 0
    device_scale::Float32           # > 0, finite, default 1f0
    fill_style::SomePaint           # Paint | ColorRGB | ColorRGBA | ColorRGBX | String
    stroke_style::SomePaint
    global_alpha::Float32           # 0f0..1f0, default 1f0
    composition::CompositionOperator # default SourceOver
    line_width::Float32             # ≥ 0f0, default 1f0
    miter_limit::Float32            # ≥ 1f0, default 10f0
    line_cap::LineCap               # default ButtCap
    line_join::LineJoin             # default MiterJoin
    line_dash::Vector{Float32}      # default []; copied on set
    line_dash_offset::Float32       # ≥ 0f0, default 0f0 (dash phase)
    font::String                    # default "" (file path, as in Context)
    font_size::Float32              # default 12f0
    text_align::HorizontalAlignment        # default LeftAlign
    text_baseline::BaselineAlignment        # default AlphabeticBaseline
    transform::Mat3                 # default mat3()
    clips::Vector{ClipScope}        # effective cumulative clip (§5.4)
    path::Path                      # current-path convenience state
    pending_ops::Vector{CanvasOp}   # validated ops since last flush
    assets::Dict{Int, CanvasAsset}  # captures owned by ≥ 1 live owner (§6
                                    # asset identity and ownership); retained
                                    # across flushes while referenced,
                                    # released at the §6 release points
    asset_refs::Dict{Int, Vector{Symbol}}  # live owner categories per
                                    # capture id: :pending | :saved |
                                    # :recording | :inflight (§6)
    asset_next_id::Int              # monotonic per canvas, never reused (§6)
    storage::StorageReport          # from bind_target! (§8); core-owned copy
    adapter::Union{StorageAdapter, Nothing}  # §13 borrow/stage route
    borrowed::Union{Any, Nothing}   # adopted host storage (array or Image);
                                    # close never frees it
    submissions::Vector{TrackedSubmission}  # every OUTSTANDING accepted
                                    # submission — the core-owned tracked
                                    # frontend handles (§8.1 revision 9)
                                    # wrapping the provider submissions,
                                    # in order; pending and failed
                                    # entries are retained; a
                                    # wait-completed entry is RETIRED by
                                    # the single completion route (direct
                                    # `wait(handle)` and `wait(c)` alike
                                    # — the entry is removed, batch/asset
                                    # references released at the §6
                                    # `:inflight` release point, the
                                    # provider roots released, §8.1)
    fallback_policy::Symbol         # :strict (default) | :report
    fallback_reports::Vector{FallbackReport}
    closed::Bool
    state_stack::Vector             # internal: save/restore snapshots (§5.5)
    group_depth::Int                # internal: open GroupStartOp count
end
```

- One `Canvas` is single-writer; independent canvases may run concurrently.
  The core never moves a canvas between threads; provider thread affinity is
  declared in `BackendCapabilities.limits` under `"thread-affinity"`
  (0 = any thread, 1 = creation thread).
- Drawing calls validate (§9 preflight) and append to `pending_ops` with
  owned effective-state snapshots. **All backends execute exclusively at
  `submit!` of a sealed batch** — one execution path, no immediate-on-append
  execution, no backend whitelists — **except the explicit pixel-transfer
  route `upload_pixels!` (§7 ordered upload route), which dispatches as
  its own tracked submission after the older pending drawing**. The CPU
  backend's `submit!` simply
  executes the batch synchronously (its submission is pre-completed);
  GPU/browser backends execute at their own completion boundary.
- `SomePaint`, `LineCap`, `LineJoin`, `HorizontalAlignment`,
  `BaselineAlignment`, `Mat3`, `Vec2`, `Rect`, `Path`, `Paint`,
  `WindingRule`, `BlendMode` are the existing frozen types (docs/API.md).
  R021 exports `SomePaint` (the existing union
  `Paint | ColorRGB | ColorRGBA | ColorRGBX | String`) as part of the
  frozen canvas surface. `ClipScope` is §5.4; `TrackedSubmission` is the
  §8.1 core tracking record (revision 9).

Defaults equal the legacy `Context(image)` defaults plus:
`composition = SourceOver` (new state), `line_dash_offset = 0f0` (new),
`clips`/`pending_*`/`asset_next_id` are canvas internals.

## 4. Constructors (exact)

```julia
Canvas(w::Int, h::Int)                              # CPU, owned transparent Image
Canvas(w::Int, h::Int; backend::CanvasBackend,
       device_scale::Float32 = 1f0,
       fallback::Symbol = :strict)                  # provider binds its target
Canvas(img::Image)                                  # CPU, borrows img (caller-owned)
Canvas(A::AbstractMatrix;
       backend::CanvasBackend = _default_cpu_backend(),
       copy::Bool = true,
       device_scale::Float32 = 1f0,
       fallback::Symbol = :strict)                  # pixel-element matrix, §7
Canvas(A::AbstractVector;
       backend::CanvasBackend = _default_cpu_backend(),
       dims = nothing,
       row_major::Bool = true,
       copy::Bool = true,
       device_scale::Float32 = 1f0,
       fallback::Symbol = :strict)                  # pixel-element vector, §7
Canvas(v::AbstractVector{<:Union{UInt8,Float32,Float64}};
       layout::PixelLayout,
       backend::CanvasBackend = _default_cpu_backend(),
       copy::Bool = true,
       device_scale::Float32 = 1f0,
       fallback::Symbol = :strict)                  # raw channel vector, §7
Canvas(m::AbstractMatrix{<:Union{UInt8,Float32,Float64}};
       layout::PixelLayout,
       backend::CanvasBackend = _default_cpu_backend(),
       copy::Bool = true,
       device_scale::Float32 = 1f0,
       fallback::Symbol = :strict)                  # raw channel matrix, §7
Canvas(picture::Picture, w::Int, h::Int;
       backend::CanvasBackend = _default_cpu_backend(),
       device_scale::Float32 = 1f0,
       fallback::Symbol = :strict)                  # replays picture at (w, h)
Canvas(s::StorageAdapter;
       backend::CanvasBackend = _default_cpu_backend(),
       copy::Bool = true,
       device_scale::Float32 = 1f0,
       fallback::Symbol = :strict)                  # §13 storage adapter route
```

`_default_cpu_backend()` is the core-owned CPU backend construction (no user
configuration). Array forms take the element/layout rules of §7.

Rules (all raise `ArgumentError` before the target is bound; the message
names the failing condition):

1. `w > 0`, `h > 0`; `4 * w * h` overflow-checked (existing `_checked_nbytes`);
   physical extents per §10 (checked rounding of `w*scale`).
   **One input-size invariant for every constructor (frozen, revision 4)**:
   the supplied pixels (array/raw element or raw channel form, adapter
   descriptor, imported `Image`, `spec.initial`) are the target's
   **physical** pixels. The core derives the logical size by
   **widening both operands before the division** (frozen, revision 6) —
   `lw, lh = Float64(pw) / Float64(scale), Float64(ph) / Float64(scale)` —
   and requires, **before binding**, that the quotients are exactly
   integral ≥ 1 (the `Int` conversion happens only after that check) and
   that `physical_extents(lw, lh, scale) == (pw, ph)` round-trips; any
   violation (fractional or non-integral logical size, inconsistent
   round-trip) raises `ArgumentError` naming the failing dimension. Pinned
   distinguishing case: physical `6` at scale `0.6f0` — the literal
   `Float32` division `6 / 0.6f0` rounds to exactly `10.0` (and
   round-trips to `6`, a false acceptance), while the widened quotient
   `Float64(6) / Float64(0.6f0) = 9.999999602635718` is non-integral ⇒
   rejected; the widened rule is authoritative (the rounding is not
   switched). The derived
   logical `(lw, lh)` — never the raw physical extents — is what
   `bind_target!` receives in `CanvasTargetSpec` together with the
   physical pair, and `initial` (when present) is validated against the
   **physical** extents: asset dimensions `(pw, ph)` and
   `length(initial.data) == 4·pw·ph`, raising `ArgumentError` before
   binding when they do not match. Pinned rejections: a 1×1 array at
   scale 2 (fractional logical) and a 5×3 element matrix at scale 1.5
   (`5/1.5` non-integral). Pinned acceptance: a raw 4×2 RGBA channel form
   (8 pixels) at scale 2 carries **32** initial bytes (`4·4·2`) and binds
   logical 2×1; a **16-byte** initial for the same target is rejected by
   the length rule above. `device_scale = 1` keeps
   logical = physical.
2. `device_scale` finite, `> 0`; `fallback ∈ {:strict, :report}`.
3. Protocol binding: `backend_capabilities(backend)` is called first;
   `protocol != 1` ⇒ §1 error. The core then calls
   `bind_target!(backend, spec)` (§8) with the validated
   `CanvasTargetSpec`. The provider allocates/adopts its target and validates
   its own device/format constraints. A bind failure propagates the provider
   error **and the core calls `close(backend)` on the failed backend before
   abandoning it** (provider cleanup duty); the canvas is not constructed.
4. `Canvas(img)` borrows: the CPU backend target is `img` itself;
   `storage(c) == StorageReport(:direct, :row, false)`; `close(c)` never frees
   `img` or its buffer; drawing after `close` raises `CanvasClosedError`.
5. `Canvas(A; copy=true)` imports a **snapshot**: pixels are converted (§7)
   into owned storage; later mutation of `A` cannot invalidate the canvas;
   `A` may be collected after construction; `storage(c) ==
   StorageReport(:owned, :row, true)`. Works with every backend (GPU
   construction = snapshot upload via `spec.initial`, never host-memory
   borrow).
6. `Canvas(A; copy=false)` borrows a writable host array as the CPU target
   (R022). Rejected for non-CPU backends
   (`"copy=false requires the CPU backend"`), for immutable destinations
   (static arrays, read-only views — `"borrow target must be writable"`),
   and for unsupported element/layout (§7). Borrow mode and storage order
   follow the single §7 table: `:direct` only when the host memory is
   contiguous in the logical row-major byte order **and** already
   premultiplied RGBA8 (borrowed `Image` data, premul raw `UInt8` vectors,
   row-major foreign storage); an ordinary Julia `Matrix` — element or raw
   — is column-major memory and is never `:direct`, it stages and reports
   `StorageReport(:staged, :col, false)`. Staged writeback completes at
   `wait(flush!(canvas))` under the single §7 commit rule (pre-commit
   validation leaves the host untouched; commit failure is `:partial`
   unless the destination explicitly guarantees atomic commit).
   **Opaque borrow policy**: a `Matrix{ColorRGB}` (or `RGB{N0f8}`) borrow is
   accepted — the writeback composites each premul pixel over the array's
   **existing** pixel as the matte (the frozen §7 matte formula, matte =
   current destination content), so no data is lost and no external matte
   argument is needed. Writeback for staged borrows uses plain indexing
   (views included) through the shared §7 conversion boundary.
7. `Canvas(picture, w, h)`: the picture's ops are converted into the
   fresh canvas's normalized ops at construction (no target-specific
   code); placement follows §14 (the one authority) with `dest` = the
   full `(w, h)` canvas.
8. Backend construction/binding failure (provider error, missing driver,
   context creation failure) propagates as in rule 3; the canvas is not
   constructed.

## 5. Drawing surface and semantics

### 5.1 State accessors

```julia
set_fill_style!(c, s::SomePaint)
get_fill_style(c)::SomePaint
set_stroke_style!(c, s::SomePaint)
get_stroke_style(c)::SomePaint
set_global_alpha!(c, a::Real)
get_global_alpha(c)::Float32
set_composition!(c, op::CompositionOperator)
get_composition(c)::CompositionOperator
set_line_width!(c, w::Real)
set_miter_limit!(c, m::Real)
set_line_cap!(c, cap::LineCap)
set_line_join!(c, join::LineJoin)
set_line_dash!(c, dash::AbstractVector{<:Real})   # stores a copy (M004 rule)
get_line_dash(c)::Vector{Float32}                 # returns a copy
set_line_dash_offset!(c, o::Real)
get_line_dash_offset(c)::Float32
set_font!(c, path::String)
set_font_size!(c, s::Real)
set_text_align!(c, a::HorizontalAlignment)
set_text_baseline!(c, b::BaselineAlignment)
```

Real-boundary rule (T014): every `Real` argument is converted to `Float32`
**once** at the boundary method, which delegates to the `Float32` kernel.
Ranges: `global_alpha ∈ [0,1]`, `line_width ≥ 0`, `miter_limit ≥ 1`,
`line_dash_offset ≥ 0`, dash elements `> 0`, `font_size > 0`; violations
raise `ArgumentError` naming the field. `fill_style`/`stroke_style` are
stored as given; the effective paint is resolved at **record time** (hex
`String` resolves through `parseHtmlColor`, so an invalid string raises on
the draw call, as in the legacy `Context`). Legacy `Paint.blendMode` values
convert at record time: `NormalBlend` → `artistic = none`;
`OverwriteBlend` → `composition = Copy` for that op; the 15 artistic
`BlendMode`s → `artistic`; the three mask-family values are internal and
raise `ArgumentError` if set as a user style (§5.7).

### 5.2 Transforms

```julia
get_transform(c)::Mat3
set_transform!(c, m::Mat3)
reset_transform!(c)
transform!(c, m::Mat3)
translate!(c, x::Real, y::Real)
translate!(c, v::Vec2)
scale!(c, x::Real, y::Real)
scale!(c, v::Vec2)
rotate!(c, angle::Real)   # radians
```

Ordered post-multiplication, exactly as `Context`: `transform!(c, m)` sets
`c.transform = c.transform * m`, so `m` applies to points first.

Singular-transform contract (pinned by R011 conformance):

- A finite but exactly singular CTM makes fills and strokes degenerate
  (measure zero): the op is recorded normally (preflight passes, the
  command is sealed into the batch) and the provider executes
  singular-transform ops as a **no-op** — no pixels painted, no error.
  Hit-testing under a singular CTM reports false (§5.6).
- Non-finite CTM entries (NaN/Inf, from a caller-built `Mat3`) raise
  `ArgumentError` at the draw call, before any command is recorded.
- Stroke width is carried by the geometry: stroke outlines are expanded in
  path-local space using the transform's pixel scale for subdivision, then
  mapped by the CTM (existing `strokePath` behavior). Non-uniform scale
  therefore scales the stroke with the geometry.
- Dash lengths and the dash offset are in path-local units (scaled with the
  geometry by the same transform).

### 5.3 Current path and convenience builders

`begin_path!`, `move_to!`, `line_to!`, `quadratic_curve_to!`,
`bezier_curve_to!`, `elliptical_arc_to!`, `arc!`, `arc_to!`, `close_path!`,
`rect!`, `rounded_rect!`, `ellipse!`, `circle!`, `polygon!`, `add_path!` have
the same argument forms as the existing `Context`/`RecordingContext`
builders (T014 Real boundary included) and mutate `c.path`. The explicit
`Path` argument forms of `fill!`/`stroke!`/`clip!` are canonical; the
current-path forms are convenience state, exactly as in `Context`. `Path`
geometry is in local coordinates; the effective transform is captured into
the op at draw time (§6).

Arc contract (frozen): `elliptical_arc_to!`/`arc!` accept the existing
endpoint/center parameters; a zero-radius arc is a no-op; a full-turn arc
(angular span a multiple of 2π) renders as the complete ellipse (the native
browser `ellipse` full-circumference case, per CANVAS_RESEARCH.md — the
browser payload must preserve the full turn, R050); a zero-span arc with
`largeArc`/sweep set is a point (no-op), distinct from a full turn.

### 5.4 Clips (new semantics)

```julia
clip!(c, path::Path, windingRule = NonZero)
clip!(c, windingRule = NonZero)         # current path

struct ClipScope
    path::Path
    winding::WindingRule
end
```

- A clip is established in **canvas coordinates**: the path is transformed
  by `c.transform` at the `clip!` call with the existing frozen
  `transform(path, mat)` semantics (absolute points transformed; relative
  command deltas transformed with zero translation; arc radii scaled by the
  matrix scales; a leading relative move becomes absolute), and the
  transformed geometry is stored as a `ClipScope` (owned deep copy of the
  path). Later transform changes do **not** move the clip. (Deliberate
  divergence from legacy `Context.clip`, which ignores the transform —
  migration note §14.)
- Clips intersect cumulatively within the current save scope; `save!` copies
  the clip list, `restore!` restores it — no clip leakage between scopes.
- Every recorded op carries the **full ambient `clips` snapshot** (§6), so a
  clipped fill is a different command than an unclipped fill; backends
  execute the clip without any canvas-state access.
- Winding applies exactly as for `fill!` (nonzero/evenodd). An empty clip
  path still records a scope (intersection with empty = empty — later draws
  are suppressed), matching HTML semantics.

### 5.5 Save/restore and layers

```julia
save!(c)          save_layer!(c)     restore!(c)
```

- `save!` snapshots **drawing state only**: `fill_style`, `stroke_style`,
  `global_alpha`, `composition`, `line_width`, `miter_limit`, `line_cap`,
  `line_join`, `line_dash` (copy), `line_dash_offset`, `font`, `font_size`,
  `text_align`, `text_baseline`, `transform`, `clips` (copy). Paints are
  snapshotted into owned `OwnedPaint` (§6): in a state snapshot
  `OwnedPaint.opacity` is the paint's own opacity — no global-alpha fold
  (folding happens at op record time only). Image/tiled styles are
  **captured at save time** into the retained asset store (unique id per
  capture, §6), independently of the current pending batch, so `restore!`
  materializes a fresh `Image` from that capture even after flushes and
  caller mutation. `OverwriteBlend` styles retain their `Copy` composition
  override in the snapshot: the restored draw executes with `Copy`, not the
  canvas composition in effect at `restore!` time.
  A failed `restore!` (materialization/validation error) raises and leaves
  the snapshot **unpopped** — no partial state transition.
  It does **not** copy pending
  commands, the backend, lifecycle flags (`closed`, `fallback_reports`,
  `asset_next_id`) or any execution internal. `text_baseline` **is** saved
  (deliberate fix of the legacy quirk). The current path is **not** part of
  saved state (matches HTML canvas and legacy `Context`).
- `save_layer!` = `save!` plus a `GroupStartOp(opacity, composition,
  clips)`; it starts an isolated transparent group at full physical size.
  **Atomic preflight (frozen)**: before ANY state mutation, `save_layer!`
  runs the full §9 preflight for its required id set — `layer.group`,
  `composition.<entry composition>` (the group composite operator is
  frozen at entry, so it must be supported now), `state.clip` whenever
  the ambient clip list is non-empty — plus the same style
  resolvability validation as op record time (image/tiled paints must
  carry an image, `String` styles must parse, gradients must be valid).
  Any failure raises before the state snapshot is pushed, before
  `group_depth` changes and before any op is recorded — a `save_layer!`
  never leaves a partially entered group.
- **Group rule (frozen, unambiguous; the revision-3 0.25 expectation is
  retracted)**:
  - `save_layer!` captures the parent state (as `save!`), records
    `GroupStartOp(opacity, composition, clips)` with **entry alpha
    frozen** (`opacity = c.global_alpha` at entry) and **entry
    composition frozen** (`composition = c.composition` at entry — the
    operator of the group composite), and then sets the child context to
    **neutral entry**: `global_alpha = 1f0`, `composition = SourceOver`.
    The child's own state changes thereafter affect child ops only.
  - Child ops carry `OwnedPaint.opacity = clamp01(paint.opacity ×
    child global_alpha)` — the *child* `global_alpha` (1.0 at entry),
    never the entry alpha again.
  - The group factor is applied **exactly once**, by the provider, at
    `GroupEndOp` composite time: the transparent group buffer is
    composited into the parent under `GroupStartOp.composition` with the
    buffer's alpha scaled by `GroupStartOp.opacity`. Nothing else
    multiplies by the entry alpha.
  - `restore!` restores the parent's state exactly — including the entry
    `global_alpha` and entry composition.
  Pinned expectations (hand-derived; R011 fixes the byte corpus):
  - `global_alpha 0.5 → save_layer! → fill! (opaque solid paint) →
    restore!`: `GroupStartOp.opacity = 0.5`, child `FillOp.paint.opacity
    = 1.0`, net group alpha **0.5** — one application of the entry
    factor to the composed group, never 0.25.
  - `global_alpha 0.5 → save_layer! → set_global_alpha!(1.0) → fill!`:
    group factor 0.5, child op 1.0; after `restore!` the parent
    `global_alpha` is 0.5 and composition is the entry value again.
  - Nested: outer entry alpha 0.5, inner `save_layer!` without changing
    alpha → inner `GroupStartOp.opacity = 1.0` (the child context's alpha
    at the inner entry); the inner group composites into the outer buffer
    at full strength and the outer buffer composites at 0.5 — each
    frozen factor applied exactly once, depth-first.
  - Unsupported entry composition: `set_composition!(Xor)` with
    `composition.xor` unsupported ⇒ `save_layer!` raises
    `BackendCapabilityError` before any mutation (the group's own
    composite requires the entry operator, not the child's).
- **Entry/child/restore clips (frozen)**: `GroupStartOp.clips` is the
  ambient clip list at entry (the layer buffer is clipped to it); child
  ops carry their own ambient snapshots (clips set inside the layer are
  child state); the composite at `GroupEndOp` is clipped by the ambient
  clip list **at restore time** (carried in the op, §6). A clip set
  inside the layer does not leak to the parent on `restore!`.
- An unbalanced `save_layer!` at `flush!` time raises
  `ArgumentError("unbalanced save_layer at flush")` before any submission;
  `restore!` with an empty stack raises `ArgumentError("restore with no
  saved state")` (legacy rule kept).

### 5.6 Draw operations

```julia
fill!(c, windingRule = NonZero)         # current path
fill!(c, path::Path, windingRule = NonZero)
stroke!(c)                             # current path
stroke!(c, path::Path)
fill_rect!(c, r::Rect)
fill_rect!(c, x::Real, y::Real, w::Real, h::Real)
stroke_rect!(c, r::Rect)
stroke_rect!(c, x::Real, y::Real, w::Real, h::Real)
clear_rect!(c, r::Rect)
clear_rect!(c, x::Real, y::Real, w::Real, h::Real)
draw_image!(c, img::Image, dx::Real, dy::Real, dw::Real, dh::Real)
draw_image!(c, img::Image, dx::Real, dy::Real)
draw_image!(c, img::Image, sx::Real, sy::Real, sw::Real, sh::Real,
            dx::Real, dy::Real, dw::Real, dh::Real)
draw_image!(c, img::Image, src::Rect, dest::Rect;
            sampling::ImageSampling = LinearSampling)
draw_picture!(c, picture::Picture)
draw_picture!(c, picture::Picture, dest::Rect)   # dest defaults to full canvas
fill_text!(c, text::String, x::Real, y::Real)
fill_text!(c, text::String, pos::Vec2)
stroke_text!(c, text::String, x::Real, y::Real)
stroke_text!(c, text::String, pos::Vec2)
measure_text(c, text::String)::TextMetrics
blur!(c, radius::Real)
spread!(c, radius::Real)
shadow!(c, radius::Real, offset::Vec2, color::ColorRGB)
is_point_in_path(c, x::Real, y::Real; winding::WindingRule = NonZero)
is_point_in_path(c, path::Path, x::Real, y::Real; winding::WindingRule = NonZero)
is_point_in_stroke(c, x::Real, y::Real)          # new (R031)
```

Semantics (portable profile):

- **Fill**: effective paint = owned snapshot of `fill_style` with
  `global_alpha` folded into opacity (§6); compositing operator =
  `c.composition`; artistic blend = the paint's (Normal = none).
- **Stroke**: effective paint = owned snapshot of `stroke_style` with
  `global_alpha` folded in; **any paint kind is valid** (solid, gradients,
  image, tiled — painted strokes, C2D-021, owner R031). Execution lowering is
  the shared stroke outline filled with the stroke paint; the outline is
  expanded in path-local space with the CTM's pixel scale, dash + dash
  offset + caps + joins + miter per §5.2, then the outline is filled under
  `c.composition`. Painted strokes sample the paint in the same path-local
  gradient/image space as fills.
- **clear_rect!**: replaces the destination rectangle with transparent
  pixels under the effective transform and the ambient clip; ignores
  fill/stroke paint, `global_alpha` and composition (unconditional
  destination replacement, `CompositionOperator`-independent).
- **draw_image!**: composites the source image region with the **current
  composition operator**, `global_alpha`, nearest/linear sampling (explicit
  `sampling`, default linear) and clamp/repeat edge behavior. Source
  geometry (frozen, revision 6): the **Rect form preserves the fractional
  source rectangle** — `DrawImageOp.srcRect` is the captured `Rect` as-is
  (no truncation at the op boundary, no `Int` conversion at the wire —
  §11); the integer truncation of the source rectangle is isolated to the
  **legacy 8-arg overload**, applied once at the call boundary (the op
  then carries the truncated integer rect). The destination rectangle may
  be fractional in both forms; destination scaling is applied by sampling,
  not by prefiltering. Image contents are captured at the call
  boundary as an immutable asset (§6): **every capture event assigns a
  fresh unique id** (never reused, no version field — §6 asset identity);
  a mutated source is re-captured at the next draw, so drawing, mutating,
  then drawing the same `Image` yields two distinct ids with distinct
  owned content in one batch; re-drawing an unmutated `Image` is a fresh id
  too (content sharing of identical captures is an optimization that must
  never change ids or references, §6).
- **Text (portable mode)**: glyph outlines are lowered at call time by the
  existing `typeset`/`computePaths` machinery under the canvas font state
  (R012 owns shared correctness); `measure_text` is headless — no device
  initialization, no pixel readback — and its advance width equals the
  drawn layout's width exactly (C2D-033). Text honors `global_alpha`,
  composition and artistic blend like fills. Native browser text is a
  separate capability/profile (`draw.text.native`), never substituted
  silently.
- **Effects**: `blur!`/`spread!`/`shadow!` operate on the whole current
  canvas content in v1 (region = canvas bounds), with the existing kernel
  formulas (Gaussian kernel / spread / shadow offset); recorded as bounded
  `EffectOp`s whose in/out regions the core computes conservatively as
  **fractional logical `Rect`s** (frozen, revision 6 — the whole-canvas
  bounds at call time; no integer-enclosure rule, no `Int` conversion:
  the §11 wire serializes them exactly as declared). Effects carry their
  effective `opacity` (`global_alpha` at call time) and
  the ambient `clips`; `shadow!` composites the blurred source copy under
  `offset` with `color` at the frozen opacity, then the unshifted source
  (existing `shadow` semantics). Radii: finite, `≥ 0`; offset finite.
  Sub-region effects are a later optimization (C2D-041) — the op carries
  bounded regions so backends can use them when they appear.
- **Hit tests**: `is_point_in_path` uses fill semantics with the current
  transform applied to the path (legacy rule) and the given winding.
  `is_point_in_stroke` tests the stroked band under the current stroke state
  (width, caps, joins, miter limit, dash + dash offset) with the same
  transform rule; under a singular transform it returns `false` (the stroke
  is degenerate). Both are geometric, read-only, and available on every
  backend (they never touch the target).

### 5.7 Compositing contract

Compositing separates the **Porter–Duff composition operator** (canvas
state, `set_composition!`) from the **artistic blend mode** (per-paint, the
existing 15 `BlendMode` values 1..15: `DarkenBlend` … `LuminosityBlend` —
**fifteen**, not fourteen). `NormalBlend` (value 0) means "no artistic
blend"; `OverwriteBlend` (17) maps to `Copy` as an operator; the mask
family (16/18/19) is internal and not user-settable (§5.1 conversion rule).

Frozen reference (portable profile). One internal representation:
**straight (non-premultiplied) Float32** colors in `0..1`, per the W3C
Compositing specification (TR/compositing-1 §6, §9.1 — the equations below
are the frozen transcription of its Porter–Duff operator table; the spec is
the normative source, this table is the binding contract). The pipeline,
in order, per pixel:

1. **Coverage**: per-pixel raster coverage `cov ∈ [0,1]` scales the source
   alpha only — `αs ← cov·αs`, source color unchanged (equivalently: all
   premultiplied source channels × cov). Rasterizing half an opaque red
   pixel gives `(128, 0, 0, 128)` premultiplied bytes — never
   `(64, 0, 0, 128)` (straight color is *not* scaled by coverage). Coverage
   computation is backend-owned (CPU regression profile: the existing
   pinned rasterizer coverage; portable comparisons use R011's justified
   edge bounds).
2. **Artistic blend** (only when the paint's artistic mode ≠ normal):
   `Cr = (1 − αb)·Cs + αb·B(Cb, Cs)` where `B` is the W3C blend function
   for the mode — blending never uses premultiplied values.
   **Separable endpoint order (frozen, W3C §10.1.7/§10.1.8)**: the
   backdrop exceptions are tested before the source exceptions —
   color-burn `B = Cb==1 ? 1 : (Cs==0 ? 0 : 1 − min(1, (1−Cb)/Cs))`;
   color-dodge `B = Cb==0 ? 0 : (Cs==1 ? 1 : min(1, Cb/(1−Cs)))`.
   **Vector versus scalar application (frozen)**: the eleven separable
   modes apply `B` per channel to scalar `(Cb, Cs) ∈ [0,1]` (spec §10.1
   formulas). The four non-separable modes (hue, saturation, color,
   luminosity) apply `B` to the **RGB color vectors** — `B(Cb, Cs)` with
   `Cb = (CbR, CbG, CbB)` and `Cs = (CsR, CsG, CsB)` in straight color
   `0..1` — per spec §10.2, with the exact auxiliary functions (spec is
   the normative source; this transcription is binding):

   ```
   Lum(C)    = 0.3·Cred + 0.59·Cgreen + 0.11·Cblue
   ClipColor(C):
     L = Lum(C); n = min(C); x = max(C)
     if n < 0: C = L + ((C − L)·L) / (L − n)
     if x > 1: C = L + ((C − L)·(1 − L)) / (x − L)
     return C
   SetLum(C, l):
     d = l − Lum(C); C = C + (d, d, d); return ClipColor(C)
   Sat(C)    = max(C) − min(C)
   SetSat(C, s):
     if Cmax > Cmin: Cmid = (Cmid − Cmin)·s / (Cmax − Cmin); Cmax = s
     else:           Cmid = Cmax = 0
     Cmin = 0; return C
   hue:        B(Cb, Cs) = SetLum(SetSat(Cs, Sat(Cb)), Lum(Cb))
   saturation: B(Cb, Cs) = SetLum(SetSat(Cb, Sat(Cs)), Lum(Cb))
   color:      B(Cb, Cs) = SetLum(Cs, Lum(Cb))
   luminosity: B(Cb, Cs) = SetLum(Cb, Lum(Cs))
   ```

   where `Cmin/Cmid/Cmax` are the components with the minimum, middle and
   maximum values on entry to `SetSat`. For these four modes the **alpha
    channel never enters B**: the output is exactly the item-3 rule —
    premultiplied color composite `co = αs·Fa·Cr + αb·Fb·Cb` (straight
    inputs) with the Porter–Duff alpha row `αo = αs·Fa + αb·Fb` (the
    §5.7 αo table) — same as every other mode. (The spec's
   §10.2 `Lum` weights 0.3/0.59/0.11 are distinct from the §7 gray-luma
   BT.709 weights 0.2126/0.7152/0.0722 — do not mix them.)
   Pinned hand-derived anchors, one quantization:
    hue of opaque orange (1, 0.5, 0) over opaque gray (0.2, 0.2, 0.2)
    ⇒ (51, 51, 51, 255); color of the same pair ⇒ (86, 43, 0, 255);
    color of opaque red over opaque blue ⇒ (94, 0, 0, 255); luminosity
    of opaque red over opaque blue ⇒ (54, 54, 255, 255); saturation of
    opaque yellow over opaque mid-gray ⇒ (128, 128, 128, 255)
    (pure-gray backdrop is unchanged, per spec). The opaque anchors are
    cross-checked byte-exact against the pinned integer kernels
    (`src/blends.jl`); the mid-gray saturation case sits on the 127.5
    tie, which both the exact-arithmetic rule (ties away) and the
    Float32 kernel resolve to 128.
   **Separable endpoint anchors (frozen, independently justified)**:
    color-burn `B(0.5, 0) = 0` (source exception, backdrop < 1) and
    `B(1, 0) = 1` (backdrop exception first); color-dodge
    `B(0.5, 1) = 1` (source exception, backdrop > 0) and `B(0, 1) = 0`
    (backdrop exception first). Full composites, opaque source over
    half-gray (0.5, 0.5, 0.5, 1): color-burn black ⇒ (0, 0, 0, 255);
    color-dodge white ⇒ (255, 255, 255, 255).
   **Artistic-before-additive anchor (frozen)**: Screen under
    `Lighter`, both colors straight (0.4, 0.4, 0.4) at α 0.5:
    `B = 0.64`, `Cr = 0.5·0.4 + 0.5·0.64 = 0.52`,
    `co = 0.5·0.52 + 0.5·0.4 = 0.46` ⇒ byte 117 per channel,
    `αo = 1` ⇒ (117, 117, 117, 255). The rejected v4 branch (raw
    unblended channel sums) produced 102.
   **Asymmetric nonseparable anchor (frozen)**: hue of red at α 128
    over blue at α 128, source-over ⇒ (87, 0, 64, 192). Provenance:
    an exact-rational derivation (the independent oracle — not
    observed kernel output): `Sat(blue) = 1`,
    `SetSat((1,0,0), 1) = (1,0,0)`, `Lum(blue) = 11/100`;
    `SetLum` shifts by `d = −19/100` to
    `(81/100, −19/100, −19/100)`; `ClipColor` with `L = 11/100`,
    `n = −19/100`, `L − n = 3/10` gives `B = (11/30, 0, 0)`
    (R: `11/100 + (7/10)·(11/100)/(3/10) = 11/30`; G/B:
    `11/100 − (3/10)·(11/100)/(3/10) = 0`). With `a = 128/255`,
    `Cr_R = (1−a) + a·11/30`; source-over `Fa = 1`,
    `Fb = 1−a`, `αo = a + a(1−a)`; `co = (a·Cr_R, 0, a(1−a))`.
    Ties-away quantization: `255·co_R = 667904/7650 = 87.31 → 87`;
    `255·co_B = 16256/255 = 63.75 → 64`; `255·αo = 48896/255 =
    191.75 → 192`. The pinned `blendHue` kernel reproduces the same
    bytes (cross-check, not oracle).
   The 15 implemented modes keep the **existing pinned integer kernels**
   (`blendDarken` … `blendLuminosity`, `src/blends.jl`) as the CPU-profile
   byte-exact reference (NUMERICAL_CONTRACT.md); other backends match them
   within R011's per-feature bounds.
3. **Porter–Duff coefficients** (`Cs` below is the blended `Cr`; straight
   colors): `co = αs·Fa·Cs + αb·Fb·Cb`, `αo = αs·Fa + αb·Fb`:

   | Op | `Fa` | `Fb` | `αo` |
   | --- | --- | --- | --- |
   | `SourceOver` | 1 | 1 − αs | αs + αb(1 − αs) |
   | `SourceIn` | αb | 0 | αsαb |
   | `SourceOut` | 1 − αb | 0 | αs(1 − αb) |
   | `SourceAtop` | αb | 1 − αs | αb |
   | `Over` (destination-over) | 1 − αb | 1 | αb + αs(1 − αb) |
   | `In` (destination-in) | 0 | αs | αsαb |
   | `Out` (destination-out) | 0 | 1 − αs | αb(1 − αs) |
   | `Atop` (destination-atop) | 1 − αb | αs | **αs** |
   | `Xor` | 1 − αb | 1 − αs | αs(1 − αb) + αb(1 − αs) |
   | `Copy` | 1 | 0 | αs |
   | `Lighter` | 1 | 1 | min(1, αs + αb) |

   Note the asymmetric alpha rows: `SourceAtop` keeps destination alpha
   (αo = αb) while `Atop` keeps **source** alpha (αo = αs); `Over`
   (destination-over) gives `αo = αb + αs(1−αb)`. `Lighter` adds the
   premultiplied contribution of the **blended** source color (step 2's
   `Cr`; for a Normal paint `Cr = Cs`) to the premultiplied backdrop:
   `co = min(αs·Cr + αb·Cb, 1)` per channel — it never sums the
   unblended source/backdrop channels and never divides by `αo`.
4. **Zero alpha**: where `αo = 0` the result color is undefined and is
   stored as 0 (all premultiplied channels 0).
5. **Quantization (specified once)**: the premultiplied result is converted
   to `UInt8` storage per channel (RGB and alpha alike) by
   `UInt8(round(v·255, RoundNearestTiesAway))` — the same validated
   `Float64(v)·255` rounding rule as §7 raw float channels. Straight-byte
   outputs (PNG/IO boundaries) use the existing `toStraightAlpha` kernel.

   Hand-derived anchors: half-covered opaque red, source-over transparent →
   `(128,0,0,128)`; `Atop` of straight `(1,0,0,0.25)` over
   `(0,0,1,0.75)` → `αo = 0.25`, bytes `(16,0,48,64)`; `Lighter` of the
   same pair → premul `(0.25, 0, 0.75, 1)` → bytes `(64,0,191,255)`;
   `Xor` of two fully-opaque sources → fully transparent. R032/R043 own
   execution and R011 pins the full coefficient corpus before outputs are
   compared.

- `global_alpha` is folded into the op's source at record time (§6
  effective opacity) — it multiplies the **source** coverage, not the
  destination; clips apply **after** compositing (§5.4).

### 5.8 Paints and gradients

Paint construction is the existing `Paint`/`PaintKind` family (solid,
image, **tiled image**, linear/radial/angular gradients, stops via
`colorStop`). Freeze additions:

- All five kinds are valid canvas fill **and stroke** paints and valid
  `draw_image!`-adjacent image sources; tiled fills tile the image in the
  transformed image space with `TiledImagePaint` repeat semantics (R033
  owns execution; recording remains an op — document-export strictness is a
  boundary decision, §12).
- Gradient coordinate spaces are **path-local** (the gradient's
  `imageMat`/handles transform with the op transform, exactly as the
  existing `fillGradient` pipeline samples them); stop positions are
  `Float32` in `0..1`, finite, sorted non-decreasing (linear/radial);
  angular stops use the existing angle-stop fields. Degenerate handles
  (zero length) keep the existing kernel behavior, pinned by C2D-025.
- `Paint` values are **mutable** descriptors; the canvas never stores a
  caller `Paint` in an op or in saved state — record time and save time
  produce owned `OwnedPaint` snapshots (§6). Mutating a stored paint after
  `save!` does not leak into saved state; mutating the caller's paint
  before the next draw affects the next op (call-boundary capture).
- Image/tiled paints in ops carry an **asset id**, not a live `Image`
  reference.

## 6. Normalized commands, assets, batch (exact)

```julia
struct ImageSampling
    filter::Symbol         # :nearest | :linear
    edge::Symbol           # :clamp (default) | :repeat
end
const NearestSampling = ImageSampling(:nearest, :clamp)
const LinearSampling  = ImageSampling(:linear, :clamp)

struct GlyphPath
    outline::Path          # owned copy; glyph outline (typeset + computePaths at call time)
    tform::Mat3            # positioning (font scale × canvas transform)
end

struct OwnedPaint          # immutable owned paint snapshot carried by ops
    kind::PaintKind
    color::ColorRGBA       # solid color (straight alpha)
    opacity::Float32       # EFFECTIVE: clamp01(paint.opacity * global_alpha)
    artistic::BlendMode    # NormalBlend = no artistic blend
    imageAssetId::Int      # 0 unless kind ∈ {ImagePaint, TiledImagePaint}
    imageMat::Mat3
    gradientHandles::Vector{Vec2}
    gradientStops::Vector{ColorStop}
end

abstract type CanvasOp end
# Every op carries its full effective state at call time:
#   tform      — canvas transform at call time
#   clips      — owned deep snapshot of the ambient ClipScope list
#   composition— canvas composition operator at call time
# (plus kind-specific fields below)

struct FillOp <: CanvasOp
    path::Path             # owned deep copy
    paint::OwnedPaint
    tform::Mat3
    winding::WindingRule
    clips::Vector{ClipScope}
    composition::CompositionOperator
end
struct StrokeOp <: CanvasOp
    path::Path
    paint::OwnedPaint
    tform::Mat3
    width::Float32
    cap::LineCap
    join::LineJoin
    miterLimit::Float32
    dashes::Vector{Float32}
    dashOffset::Float32
    clips::Vector{ClipScope}
    composition::CompositionOperator
end
struct ClearOp <: CanvasOp
    r::Rect
    tform::Mat3
    clips::Vector{ClipScope}
end
struct DrawImageOp <: CanvasOp
    assetId::Int
    srcRect::Rect
    destRect::Rect
    tform::Mat3
    sampling::ImageSampling
    composition::CompositionOperator
    opacity::Float32       # effective global_alpha
    clips::Vector{ClipScope}
end
struct TextOp <: CanvasOp
    glyphs::Vector{GlyphPath}
    paint::OwnedPaint
    tform::Mat3
    composition::CompositionOperator
    clips::Vector{ClipScope}
end
struct EffectOp <: CanvasOp
    kind::Symbol           # :blur | :spread | :shadow
    radius::Float32
    offset::Vec2           # shadow only; Vec2() otherwise
    color::ColorRGB        # shadow only; rgb(0,0,0) otherwise
    opacity::Float32       # effective global_alpha at call time
    inRegion::Rect
    outRegion::Rect
    tform::Mat3
    clips::Vector{ClipScope}
end
struct GroupStartOp <: CanvasOp
    opacity::Float32       # ENTRY global_alpha — the group factor, applied
                           # exactly once at GroupEndOp composite (§5.5);
                           # the child context starts at global_alpha 1.0
                           # and composition SourceOver
    composition::CompositionOperator  # frozen at save_layer! time; the
                           # operator of the group composite (entry value)
    clips::Vector{ClipScope}   # ambient clips at layer entry
end
struct GroupEndOp <: CanvasOp
    clips::Vector{ClipScope}   # ambient clips at restore time (composite clip)
end
struct FallbackWork
    ops::Vector{CanvasOp}          # :op ⇒ [the failed op]; :group ⇒ the
                                   # complete span [GroupStartOp, children…,
                                   # GroupEndOp]; :frame/:page ⇒ the covered
                                   # ops in order (filled at seal, §6 rules)
    assets::Dict{Int, CanvasAsset} # owned assets referenced by those ops
end

struct RasterFallbackOp <: CanvasOp    # marker, emitted under :report only
    feature::String
    reason::String
    scope::Symbol                  # :op | :group | :frame | :page
    original::FallbackWork         # the unexecuted work, owned and complete —
                                   # the provider's replacement is computed
                                   # from this, never from a placeholder
    clips::Vector{ClipScope}       # the marker's ambient scope boundary
end

struct CanvasAsset
    id::Int                      # unique per capture event, monotonic,
                                 # never reused (§6 asset identity)
    width::Int                   # source pixels
    height::Int
    data::Vector{UInt8}          # premultiplied RGBA8, row-major, top-down; owned
end

struct CommandBatch
    ops::Vector{CanvasOp}
    assets::Dict{Int, CanvasAsset}
    size::Vec2                   # logical
    device_scale::Float32
end
```

Rules:

- **State capture**: every op carries its effective state at call time —
  transform, composition, ambient clips (owned copies), stroke settings,
  and the owned paint with effective opacity. Backends execute ops in order
  with **no canvas-state access**. Painter order is preserved by the core;
  overlapping translucent ops are never reordered.
- **Asset identity** (fresh-id rule, kept from revision 3): **every
  capture event assigns a fresh unique id** from `asset_next_id`
  (monotonic, never reused, no `version` field). A capture event is each
  `draw_image!`, each image/tiled-paint `fill!`/`stroke!`, each `save!` of
  an image/tiled style, each `upload_pixels!`, and each imported initial.
  Drawing red, mutating the same `Image` to green, then drawing again
  before one flush yields **two distinct ids with distinct owned content**
  in `CommandBatch.assets` — no reference can point at an overwritten
  capture. Re-drawing an unmutated `Image` is a fresh id too.
- **Bounded asset ownership (frozen, revision 4; the revision-3
  retain-forever rule is retracted)**: a capture is owned by the set of
  categories in `asset_refs[id]` — `:pending` (unflushed `pending_ops`),
  `:saved` (state snapshots in `state_stack`), `:recording` (a live
  fallback marker's `original.assets`, or ops not yet flushed that
  reference it during picture capture), `:inflight` (sealed batches whose
  submission is not yet `complete`). The core releases a capture (removes
  its id from `assets` and drops the bytes) exactly at the release points:
  (a) a submission's `wait` completes ⇒ its `:inflight` owners are
  consumed (the provider must have consumed the batch by then — its
  resources are its own, §8); (b) a state snapshot is popped
  (`restore!`/`close`/`resize!` state preservation) ⇒ its `:saved` owners;
  (c) a fallback marker is sealed into a batch ⇒ its `:recording` owners
  transfer to `:inflight`; (d) canvas `close` ⇒ all remaining owners.
  **An id is released iff its owner list is empty** — so `restore!` after
  `flush!` still materializes pre-flush bytes (`:saved` keeps the capture
  alive across flushes, as before), while completed-and-unreferenced
  captures do not accumulate: ten completed draws of one pixel retain at
  most one shared immutable byte array while referenced and zero after
  close. Content-identical captures **may** share the underlying owned
  bytes (reusable owned immutable asset) but never share ids; sharing
  must not change any reference's content. Provider device-resource cache
  key = `(canvas scope, asset id, pixel profile, device generation)` —
  the id is capture-unique and canvas-scoped, so keys can never collide
  across batches, canvases or generations on a shared device.
- **Ownership**: op `path`s, `clips` paths, `OwnedPaint` arrays and asset
  `data` are owned by the canvas at record time (deep copies); mutating
  caller objects afterwards never changes sealed or pending commands.
  `CommandBatch` is immutable once sealed (`flush!`); external backends
  consume it through the frozen accessors (R020 owns storage freedom):
  `batch_ops(b)::Vector{CanvasOp}`, `batch_assets(b)`,
  `batch_asset(b, id::Int)::CanvasAsset`, `batch_size(b)`,
  `batch_device_scale(b)`.
- Core asset `data` is always premultiplied RGBA8 — straight conversion
  happens only at documented IO boundaries (§7, §10).
- **Raster fallback (frozen, revision 4)**: `RasterFallbackOp` appears only
  under `fallback=:report` when the provider advertised
  `"<feature>.fallback-raster"` at a usable level; the marker occupies the
  failed op's position in the sealed batch and `FallbackReport.op_index`
  points at the marker. **The marker retains the original work**:
  `original.ops` is the complete unexecuted command (owned deep copies of
  path/paint/geometry — never dropped) and `original.assets` the owned
  assets it references, so a public lowering route exists: at `submit!` the
  provider rasterizes `marker.original` (its own fallback capability,
  within `scope`) and composites that result at the marker's position. The
  core never fabricates replacement pixels — zero-filled placeholders are
  not execution and are not permitted. `:group` scope markers are opened at
  `save_layer!` (which keeps full canvas state — the state stack and group
  balance are **never** suppressed by a marker) and completed at the
  matching `restore!`; between them the group's ops and captures are
  retained in `original`. `:frame`/`:page` scope markers are completed at
  seal time. Destination-dependent features (non-source-over composition,
  effects, opaque-matte exports) fall back to `:frame` or a proven isolated
  `:group`, never to an `:op` in isolation (§9). No fallback marker is
  ever emitted under `:strict`. Owner: R020 (records/lowering boundary);
  per-provider raster replacement: the provider task.
- **Marker validation**: the core validates the marker record structure
  (scope consistency, owned original complete, `fallback_reports` entry
  present) at seal time; the provider validates its own replacement at
  execution time.
- `GroupStartOp.clips` is the ambient clip list snapshot at `save_layer!`
  time; ops inside the group carry their own ambient snapshots; the
  composite at `GroupEndOp` uses `GroupEndOp.clips` (restore-time ambient
  list).

## 7. Pixel storage boundary (exact, R022/R023 consume)

Supported pixel elements (v1):

| Element | Channels | Alpha | Boundary rule |
| --- | --- | --- | --- |
| `ColorRGBX` | 4 | premultiplied (canonical) | direct |
| `ColorRGBA` | 4 | straight | premultiply `rgbx(ColorRGBA)`: `(c*a + 127) div 255` |
| `ColorRGB` | 3 | opaque (a = 255) | direct |
| `Gray{N0f8}`, `RGB{N0f8}`, `RGBA{N0f8}` (opt-in ColorTypes) | 1/3/4 | `RGBA` straight | existing `toColors`/`fromColors` PNG-boundary formulas (the existing ColorTypes API is unchanged; the canvas array boundary below quantizes floats by its own frozen rule) |
| `N0f8` scalar matrix | 1 | opaque | luma byte direct |
| `UInt8` raw **vector** | declared | declared | 1-D `Vector{UInt8}` of `w*h*channels` bytes, pixel-major channel order R,G,B,(A); `PixelLayout` required, never inferred |
| `UInt8` raw **matrix** | declared | declared | `Matrix{UInt8}` — shape per the single table below (row-major scan: `(height, width*channels)`; column-major scan: `(width*channels, height)`); pixel-major channels; `PixelLayout` required |
| `Float32`/`Float64` raw vector/matrix | declared | declared | same shapes as the `UInt8` forms; values 0..1; `PixelLayout` required |

`PixelLayout` (frozen):

```julia
struct PixelLayout
    width::Int
    height::Int
    channels::Int            # 1 | 3 | 4
    alpha::Bool              # channels == 4
    premultiplied::Bool      # alpha convention
    row_major::Bool          # false = column-major scan
end
```

Frozen boundary formulas (v1):

- straight→premultiplied (`ColorRGBA` import, browser/codec inbound):
  `(c*a + 127) div 255` per channel, `a` unchanged — the existing
  `rgbx(ColorRGBA)` formula.
- premultiplied→straight (snapshot/browser/codec outbound):
  `min(round_half_away(c * 255/a), 255)` in Float64, `a == 0 ⇒ 0` — the
  existing `toStraightAlpha` PNG-boundary formula (round ties away from
  zero, **not** banker's).
- opaque export over an explicit matte (matte is **absent by default**; see
  `snapshot!` below): `out = (p*255 + m*(255-a) + 127) div 255` per
  channel — the existing JPEG composite formula.
- grayscale luma (straight 0..255 space):
  `luma = UInt8(round(0.2126r + 0.7152g + 0.0722b))` (BT.709 weights).
- float raw channels: values must be finite in `0..1` (violations raise
  `ArgumentError` at the array boundary, before any write); quantization is
  `UInt8(round(v * 255, RoundNearestTiesAway))` — the validated
  `Float64(v) * 255` rounding (the `N0f8`-cast shortcut is **not** the
  rule: `UInt8(N0f8(v))` loses the ×255 scaling).

**Single logical indexing, conversion and borrow table (frozen,
revision 5 — the one authority; §4 constructors, §7 snapshots and
writebacks and §13 adapter routes all reference this table).**
A logical pixel is addressed by row `r ∈ 1..height`, column
`c ∈ 1..width`, channel `k ∈ 1..channels`; the logical scan order is
row-first (row 1 = top scanline) unless the form declares otherwise.
Flat index (0-based) into a raw channel buffer:

```
row-major:     i = (r−1)·(width·ch) + (c−1)·ch + (k−1)
column-major:  i = (c−1)·(height·ch) + (r−1)·ch + (k−1)
```

| Form | Storage shape | Element addressing | Alpha / convention | Conversion (both directions) | `:direct` eligible |
| --- | --- | --- | --- | --- | --- |
| element matrix (`Matrix{<:PixelElem}`) | `(height, width)` | `A[r, c]` by position | per element: `ColorRGBX` premul (canonical), `ColorRGBA` straight, `ColorRGB` opaque (a = 255) | per the convention column below | only if host memory is contiguous row-major **and** the element is premul `ColorRGBX`; an ordinary Julia matrix is column-major memory ⇒ never `:direct` |
| element vector (`Vector{<:PixelElem}`) | `width·height` | logical scan order (`dims` required, `row_major` declared, default `true`) | same | same | premul `ColorRGBX` with row-major declared |
| raw vector | `width·height·ch` | the flat-index formula | declared by `PixelLayout` | declared (formulas below) | premul, row-major declared — a vector's memory **is** its declared scan order |
| raw matrix | row-major: `(height, width·ch)`; column-major: `(width·ch, height)` | positional per the **declared** scan (row-major: `A[r, (c−1)·ch + k]`; column-major: `A[(c−1)·ch + k, r]`) | declared by `PixelLayout` | declared | only when the actual memory honors the declared scan contiguously; a row-major-declared ordinary Julia matrix is column-major memory ⇒ `:staged` |
| 3-D plane matrices | — | — | — | — | rejected (existing `fromColors` rule) |

Indexing rules (existing `fromColors` rule, unchanged, applied to the
element **and** raw routes): ordered offset axes map by position (first
position = first logical pixel/channel); matrix positions are translated
through `axes(M)` — zero-based (or otherwise offset) raw matrices are
accepted in **both** declared scan orientations, exactly as offset
element matrices; index-array views, adjoints, and views built over
transposes raise `ArgumentError` naming the rule; top-level transposes
are peeled and materialized, odd count flipping the orientation; strided
range views are accepted through logical indexing — the boundary
reads/writes by index, never by `pointer` arithmetic over assumed
contiguity. **The simple `vec(matrix)` advice applies to
pixel-element matrices only**: a bare `vec(element_matrix)` is
column-major memory and must be declared `row_major = false`; no route
may reinterpret a `vec(Matrix)` byte buffer as row-major. It does
**not** extend to channel-packed raw matrices: `vec` of a
`(height, width·ch)` row-major raw matrix flattens rows inside each
channel column, so the flat bytes match no declared scan (pinned: a 2×12
RGBA row-major matrix whose first pixel is `[1,0,0,255]` flattens to
`[1,4,0,0, …]`) — raw flattening must materialize the declared
pixel/channel order (the matrix form is the safe route), and a raw source
that cannot be mapped positionally is rejected as incompatible. Direct
(`:direct`) access is possible only if the provider/host storage honors
the actual memory mapping 1:1 in logical row-major premul bytes;
everything else stages (`:staged`) and is indexed positionally through
this table.

Conversion and scalar type (every form, both directions):

- element `ColorRGBX` (premul, canonical): direct; element `ColorRGBA`
  (straight): import premultiplies with the actual `rgbx` formula,
  output un-premultiplies with the actual `toStraightAlpha` formula;
  element `ColorRGB` (opaque): import direct with `a = 255`, output to it
  uses the matte rule below.
- raw `UInt8`: bytes 0..255; `premultiplied = false` (straight)
  premultiplies on import / un-premultiplies on output (formulas above);
  `premultiplied = true` is direct.
- raw `Float32`/`Float64`: values must be finite in `0..1` (violations
  raise `ArgumentError` at the array boundary, before any write);
  import quantizes `UInt8(round(v·255, RoundNearestTiesAway))`; output
  de-quantizes `v/255`. Raw **allocating** output forms return raw bytes
  in the **declared layout convention** (premul if
  `layout.premultiplied`, straight otherwise — never "raw premul"
  regardless of the declaration).
- `channels = 1` (gray): import replicates the channel to `R = G = B`
  with `a = 255` (gray is opaque); output to gray uses the
  transparent-gray rule below. `channels = 3` (opaque RGB): import sets
  `a = 255`; output to 3-channel uses the matte rule below.

**Transparent gray/3-channel output rule (frozen)**: output to
`channels = 1` or `channels = 3` **requires an explicit matte whenever
any canvas pixel has `a < 255`** — matte is absent by default; the
rejection raises before any write (two-phase). The matte composite
(formula above) is applied **first**, and the luma (gray) is computed
from the composited straight values. Pinned: half-red premul
`(128, 0, 0, 128)` over the white matte ⇒ `(255, 127, 127)` ⇒ gray
`154` (BT.709 luma) — not `27`, the un-composited premul luma (the
rejected v4 branch). A fully opaque canvas needs no matte.

**Truthful storage-order reporting (frozen)**:
`StorageReport.layout` reports the *actual memory* scan order of the
borrowed/host storage, independently of the declared logical scan: an
ordinary Julia `Matrix` (element or raw) ⇒ `layout = :col`; vectors and
borrowed `Image` data (row-major `data`) ⇒ `layout = :row`;
adapter/foreign storage declares its actual memory order in its
descriptor. The table above is the single mapping between logical
pixels and storage positions — import, `snapshot`/`snapshot!` output and
writeback all use it; no route may silently re-interpret `:col` storage
as `:row`.

Copy/borrow/transfer (frozen):

- `copy=true` (default): snapshot import; `storage(c).copied == true`.
- `copy=false` CPU borrow: `:direct`/`:staged` per the table's
  eligibility column. Staged borrows render into core-owned staging and
  write back at `wait(flush!(c))` through the table. **Single commit
  rule (frozen)**: every in-place output — borrow writeback,
  `snapshot!` into an existing destination, adapter write (§13) — is
  two-phase. Phase 1 (validation): destination size/element/layout,
  float domain, the matte rule and region bounds are validated over the
  whole source **before any write**; a validation error leaves the
  destination untouched and raises the named error. Phase 2 (commit):
  plain indexed stores; a failure **after the first store** raises
  `TransferError(:partial)` — indexed writeback is **not** a
  transaction, even when its staging source is owned and fully
  validated — unless the destination explicitly guarantees atomic
  commit, in which case it raises `TransferError(:unwritten)` with the
  destination rolled back. Owned staging is retained for retry; the core
  never claims the host was rolled back. (The v4 "all-or-nothing where
  the adapter guarantees it" phrasing is retracted.) **Staged failure on
  the tracked handle (frozen, revision 9)**: a failed staged writeback
  never completes the tracked frontend handle that carries it (§8.1
  single route) — the **original named error is preserved by identity
  and sticky** on that handle: the `TransferError` with its
  `:partial`/`:unwritten` status, a named `BackendSubmitError` from the
  core dispatch, or the phase-1 named validation error (e.g.
  `ArgumentError`) raised before any store — the staged action is never
  re-run automatically, the entry is never completed or retired, and
  the owned staging is retained by the failed entry; the provider roots
  for the already-completed provider work are released (the contract
  retains no released resources, only the core staging).
- **Idempotent opaque staging (frozen)**: when a writeback composites
  over an opaque destination (the matte rule in
  `snapshot!`/borrow writeback below), a **successful** commit must
  *reconcile the staging representation*: after writeback, the staged
  pixels in the written region are replaced by the composite result
  (opaque). Repeated identical flushes over the same borrow are then
  stable — compositing the same half-transparent pixel over an opaque
  borrow twice must not drift (pinned: red `128` stays `128`, never
  compounds to `192`). Reconciliation happens only on success — a failed
  commit leaves the staging **unreconciled**, and the host state follows
  the actual commit result (the `:partial` stores remain, or the
  destination is rolled back when it explicitly guarantees atomic commit)
  — the single §7 commit rule above.
- `snapshot!(dest, c; layout = nothing, matte = nothing)`: flushes, waits,
   then reads the target through the **public synchronized `read_pixels`**
   (the same conversion boundary for every backend — no per-backend storage
   switches) and converts into caller-owned host storage per the §7
   table. `dest` shapes: element matrix `(height, width)` of a §7 pixel
   element; element vector of length `width·height` (row-major scan);
   raw `UInt8`/float matrix **per the single §7 table** (row-major:
   `(height, width·channels)`; column-major: `(width·channels,
   height)`) or vector of length `width·height·channels` — raw
   destinations **require** the `layout` keyword (same `PixelLayout` as
   import; the declared scan fixes the shape — there is no second
   snapshot shape). The commit runs
   under the single §7 two-phase rule: validation (destination
   size/type/layout, float domain, the transparent-gray/matte rule)
   before any write; commit failure `:partial` unless the destination
   explicitly guarantees atomic commit (`:unwritten` + rollback).
   Overlapping `dest` (sharing storage with the canvas's own borrowed
   target) is handled through the owned staging phase or rejected
   before modification.
- `snapshot(c) -> Image`: owned premultiplied `Image` at **physical** size
   (§10): flush + wait + copy for CPU, synchronized readback for GPU,
   acknowledged readback for a connected browser (§11 request identity),
   `BackendCapabilityError` for offline browser/PDF/SVG unless the caller
   explicitly requested CPU rasterization of a retained recording.
   **Allocating typed forms return the requested type, never `Image`**:
   `snapshot(c, Matrix{<:PixelElem})` → element matrix `(height, width)`;
   `snapshot(c, Vector{<:PixelElem})` → row-major element vector;
   `snapshot(c, Matrix{UInt8}; layout)` / `snapshot(c, Vector{UInt8};
   layout)` → raw bytes in the **declared layout convention** (§7 table:
   premul if `layout.premultiplied`, straight otherwise). Immutable
   static outputs are constructed, never mutated.
- Upload: `upload_pixels!(c, A[, region::Rect]; layout = nothing)` accepts
   the §7 array forms (element matrix `(height, width)` of the region,
   element vector, raw matrix/vector with `layout`, or `Image`) — not only
   `Image` — and replaces target pixels explicitly (capability
   `pixel-upload`). **Return (frozen, revision 7)**: the canvas-level
   route returns the upload's **tracked frontend completion handle**
   (the same tracked type as `flush!` — §8 routing, §8.1 single
   completion route); upload-only work completes at that handle's
   `wait`, never at a later drawing flush. **Dispatch identity (frozen, revision 5)**: the core
   first captures the region as a `CanvasAsset` (the §6 fresh capture id,
   physical dimensions, owned premultiplied RGBA8 bytes) and routes
   through the public
   `upload_pixels!(backend, asset::CanvasAsset, region::Rect)` — the
   captured asset, with its id, is what the provider receives; the id is
   preserved all the way to the wire `set-pixels` record (§11), so a
   pending draw can never collide with or obscure an intervening
   upload's identity. **Pre-dispatch validation (frozen)**: source
   shape/scan order, element/layout convertibility, float domain and
   region bounds (region in **zero-based physical** units, §10) are all
   validated **before any provider call and before any target
   modification** — an invalid upload leaves the target pixel-for-pixel
   unchanged (no partial-region writes from failed validation) and the
   pending drawing stays untouched. Array dimensions must match the
   region's **physical** size; mismatches raise `ArgumentError` naming
   the mismatch. **Ordered upload route (frozen, revision 6)**:
   (1) the entire upload is validated before any provider call (the
   pre-dispatch rule above); (2) if `pending_ops` is non-empty, the
   **older pending drawing is submitted first** (`flush!(c)`) so the
   provider executes drawing before the transfer — painter/document
   order is preserved; (3) the upload is then dispatched through
   `upload_pixels!(backend, asset, region)` and the provider preserves
   execution order with the preceding batch; (4) the canvas-level
   `upload_pixels!` returns the upload's **tracked frontend completion
   handle** (frozen, revision 7 — the same tracked type as `flush!`),
   tracked like any accepted submission (§8.1 single completion route,
   incl. completed-handle retirement); (5) browser: admission is applied
   to the upload's `set-pixels` mutation **before** it (the §11
   pre-mutation rule), and the upload receives its own submission record
   and execution-ack even when the next drawing flush is empty; (6) a
   staged upload (into a `:staged` borrow or an adapter-staged route)
   completes at **its own tracked frontend handle's** `wait` — the
   staged writeback is the upload's core staged completion, applied
   exactly once by the §8.1 single completion route, not in any later
   drawing flush; a zero-op drawing flush between dispatch and wait is
   the inert core no-op and cannot complete it (negative control,
   §8.1). **A staged failure keeps the upload FAILED on its own
   tracked handle** (the original named error — the `TransferError`
   with its `:partial`/`:unwritten` status, or the phase-1 named
   validation error raised before any store — is sticky, the writeback
   is never re-run automatically, and `close` re-raises; the provider
   roots are already released, only the core staging is retained —
   §8.1 single route, revision 9). A dispatch failure (named `BackendSubmitError`)
   retains the staged bytes for retry; the already-submitted older
   drawing is never re-submitted.
   Device and host mirrors never synchronize implicitly.
- **Adapter-taking output**: `snapshot!(s::StorageAdapter, c)` and
   `snapshot_alloc(s::StorageAdapter, c)` are the only public routes from
   a canvas into adapter-owned storage. Their canonical boundary and the
   frozen dispatch order are specified **once** in §13 (consumer routes):
   the exchange is owned premultiplied RGBA8 over zero-based physical
   regions; allocation takes the explicit type and dimensions
   (`storage_alloc(prototype, ::Type{T}, dims)`); native array
   conversion (straight/gray/float/element) is a separate §7 route and
   never travels through `storage_write!`.
- Processor switching creates a **new concretely typed Canvas**:
  pixels via `snapshot` + `Canvas(A; backend=...)`, geometry via
  `draw_recording!` (the §14 owned recording — the full normalized
  feature set) or `Canvas(picture, w, h; backend=...)` (the legacy
  `Picture`, convertible subset only), shared drawing state via the
  explicit `copy_canvas_state!(dst, src)` (copies §3 drawing-state fields
  only, never pixels, pending work or lifecycle flags). The backend type
  field is never mutated in place; fidelity profile is preserved,
  bit-identity across processors is not promised.

## 8. Backend protocol (required vs optional, exact)

Required for every `CanvasBackend` (core defines the generics; providers
implement on their own types — no method is optional to *define* beyond the
five below, and none ships a dummy):

```julia
backend_capabilities(b::CanvasBackend)::BackendCapabilities
bind_target!(b::CanvasBackend, spec::CanvasTargetSpec)::StorageReport
submit!(b::CanvasBackend, batch::CommandBatch)::CanvasSubmission
wait(sub::CanvasSubmission)::Nothing
close(b::CanvasBackend)::Nothing
```

- **The frontend uses nothing else.** The core canvas interacts with a
  provider exclusively through these methods, the returned `BackendCapabilities`
  data and `CommandBatch`/`CanvasAsset` accessors — no provider field
  reads, no concrete-type dispatch, no specially named fields. A provider
  that implements the five methods (immutable or not, with no fields at
  all) is a sufficient backend for every frontend path.
- `bind_target!` allocates or adopts the target from `spec` (physical size,
  device scale, optional initial pixels as an owned asset) and returns the
  provider's `StorageReport` (the core keeps it; `storage(c)` returns the
  core copy — the provider is the only source of the storage mode). The
  provider validates its device/format constraints here; failure raises the
  provider's error (the core then calls `close(b)` on the failed backend,
  §4 rule 3). Binding is the only point where target storage is created or
  adopted.
- `submit!` executes `batch` in order and returns a provider-owned
  `CanvasSubmission` that retains every resource the batch references until
  completion — **at completion the provider releases those references:
  a completed provider handle retains no batch/asset roots** (scalar
  completion observations may remain), while pending and failed handles
  retain them (§8.1 revision 9). **Every accepted submission is
  tracked**: the canvas keeps the full ordered handle list
  (`Canvas.submissions`, §3) — never just the latest. The public
  frontend routes (`flush!`, canvas-level `upload_pixels!`) wrap that
  provider handle in the core-owned **tracked frontend handle**
  (`TrackedSubmission`, §8.1 revision 9) and return the wrapper —
  callers never receive the bare provider handle; the provider roots are
  released when the provider's work completes inside the wrapper's
  `wait` (§8.1 single completion route — before the staged completion,
  so a later staged failure does not re-root them).
  Completion handles are **individually tracked, not cumulative
  fences**: waiting one handle completes exactly that batch, and later
  handles must not be required to release earlier resources. A canvas
  flush with zero pending ops returns the **core-owned**
  `CanvasNoopSubmission <: CanvasSubmission` without any backend call; the
  no-op is not a provider submission, is not appended to
  `Canvas.submissions`, and **never implies completion of earlier
  outstanding work** (waiting a no-op waits nothing else, §8.1).
- `wait` is the completion/error boundary with a frozen submission state
  machine `pending → complete | failed`: synchronous backends (CPU, PDF,
  SVG) return already-completed handles; `wait` is idempotent; the first
  `wait` on a deferred submission completes it — the provider executes the
  batch **exactly once**; a completion failure marks the submission
  `failed` and raises `BackendSubmitError`; **every later `wait` on the
  same failed submission re-raises the same failure** (sticky — cleanup,
  retry or repeated close must never silently turn failed work into
  successful rendering, and unknown completion must not trigger duplicate
  execution). Handles, ops and assets remain retained through failure and
  timeout until a `close` that succeeds or provider disposal.
- `close` waits for **all of the canvas's** outstanding submissions, in
  order (the provider preserves submission order and owns every
  outstanding resource, §8.1), then releases owned resources. It never
  destroys borrowed objects (arrays, host images, externally supplied
  devices/surfaces). A completion failure makes `close` raise with the
  provider's resources retained for retry/deferred cleanup — it does not
  free in-flight resources and does not mark the canvas closed. `close` on
  a closed backend is a no-op.
- Finalizers (provider-side, if any) only arrange nonblocking deferred
  cleanup; they never wait on queues or destroy resources whose completion
  is unknown.

Optional capabilities (advertised in `features`; calling an unadvertised one
raises `BackendCapabilityError` — never a dummy result):

```julia
read_pixels(b::CanvasBackend, region::Rect)::Image        # "raster-readback"
present!(b::CanvasBackend)::Nothing                       # "presentation"
upload_pixels!(b::CanvasBackend, asset::CanvasAsset, region::Rect)
       ::CanvasSubmission                                    # "pixel-upload"
       # dispatch carries the captured asset (id, physical dims,
       # owned premul RGBA8 bytes) + zero-based physical region (§7
       # upload dispatch identity) — the id survives to the wire
       # `set-pixels` record (§11)
host_surface!(b::CanvasBackend, handle::Any)::Nothing      # "host-surface"
resize!(b::CanvasBackend, spec::CanvasTargetSpec)::Nothing # "resize"
```

Canvas-level routing (core, frozen):

```julia
flush!(c)::CanvasSubmission      # seals pending_ops into a CommandBatch,
                                 # submit!s; returns the flush's TRACKED
                                 # FRONTEND completion handle (the
                                 # §8.1 revision 9 wrapper); zero
                                 # pending ops ⇒ the inert core no-op
                                 # handle, untracked, no backend call
upload_pixels!(c, A[, region::Rect];
               layout = nothing)  # §7 ordered upload route; returns the
        ::CanvasSubmission        # upload's TRACKED FRONTEND completion
                                  # handle (the same tracked type as
                                  # flush! — §8.1 revision 9, frozen
                                  # return type)
wait(c)::Nothing                 # convenience: flush! then wait EVERY
                                  # outstanding tracked submission in
                                  # order — the §8.1 single completion
                                  # route (identical to direct
                                  # wait(handle))
snapshot(c)::Image               # §7 owned premultiplied Image (physical size)
snapshot(c, T)                   # §7 typed allocating forms — return T
snapshot!(dest, c; layout = nothing, matte = nothing) # §7 two-phase conversion
close(c)::Nothing                 # §8.1: flush-on-close, sticky failure
capabilities(c)::BackendCapabilities
canvas_closed(c)::Bool
storage(c)::StorageReport         # the core copy from bind_target!
fallback_reports(c)::Vector{FallbackReport}
physical_size(c)::Tuple{Int, Int}          # §10
resize!(c, w::Int, h::Int;
        device_scale = nothing)   # §10 (capability "resize");
                                  # nothing keeps the current scale; a
                                  # Real is converted once to Float32
local_to_device(c, x::Real, y::Real)::Tuple{Float64, Float64}   # §10
device_to_local(c, x::Real, y::Real)::Tuple{Float64, Float64}   # §10
copy_canvas_state!(dst::Canvas, src::Canvas)::Canvas
```

`flush!` with pending `GroupStartOp`s that have no matching `GroupEndOp`
raises `ArgumentError("unbalanced save_layer at flush")` before submission.
Any operation on a closed canvas raises `CanvasClosedError`.
`read_pixels`/`snapshot` on an offline browser view raise
`SnapshotError(Symbol("offline-readback"), ...)`; a readback that times out
raises `SnapshotError(Symbol("readback-timeout"), ...)` (timeout is a
provider limit, default 5000 ms, declared in `limits["readback-timeout-ms"]`);
a browser readback whose fresh request/response identity does not match
raises `SnapshotError(Symbol("readback-failed"), ...)` (§11 readback
records). `wait(c)`/`snapshot(c)` never return while any tracked provider
submission is still pending.

### 8.1 Submission tracking, close and failed completion (frozen, revision 9)

The revision-3 "single latest handle" rule (`inflight`) is retracted: a
canvas keeps **every outstanding (pending or failed) accepted submission**
in `Canvas.submissions` (ordered) as core-owned tracking entries. The
**backend protocol is unchanged** — `submit!`/`upload_pixels!` still
return **provider-owned** handles, and the provider retains every batch/
asset root until its own handle completes (§8). The frontend adds one
core layer on top (frozen, revision 9): every accepted submission —
every drawing `flush!` and every `upload_pixels!` dispatch (§7 ordered
route) — is wrapped in the **core-owned tracked frontend handle**, and
the public routes (`flush!`, canvas-level `upload_pixels!`, `wait(c)`)
return/await wrappers only:

```julia
mutable struct TrackedSubmission <: CanvasSubmission
    provider::CanvasSubmission   # the wrapped provider-owned handle
    staged::Bool                 # carries core staged completion (§7:
                                 # staged borrow writeback / staged upload)
    state::Symbol                # pending → complete | failed (§8 machine)
    error::Any                   # the sticky failure — the ORIGINAL
                                 # named error, preserved by identity:
                                 # the provider's BackendSubmitError;
                                 # the staged TransferError preserving
                                 # its :partial / :unwritten status;
                                 # the §7 phase-1 named validation
                                 # error (e.g. ArgumentError) raised
                                 # before any store. One sufficient
                                 # stored-exception domain — never a
                                 # conversion that could strand
                                 # `:failed` with no error
    staged_done::Bool            # set ONLY after successful staging
end
```

The concrete staged action closure and the core tracking-root
back-reference are **core-internal representation** (opaque to the
provider — the executable boundary sketch carries them as the action
closure and the root pointer; the frozen public surface is the
handle's `wait` behavior and the fields above). The submission's state
machine `pending → complete | failed` (§8 `wait` machine) and the
once-flag for the staged action live on the tracked handle — a
completed handle stays idempotent and a failed one sticky even after it
is retired from the tracking root. The per-canvas id counter is
monotonic (wire identity uses the counter, not the handle).

- **The single completion route (frozen, revision 9)**: BOTH public
  waiting forms — direct `wait(handle)` on a tracked frontend handle and
  `wait(c)` (flush pending, then wait every outstanding tracked entry in
  order) — complete a submission through exactly this route, with TWO
  independent sticky failure classes:
  (1) forward `wait(provider)` — the provider executes its work exactly
  once (§8 machine);
  (2) **provider failure** (a `BackendSubmitError`): mark the entry
  `failed` with that error — **sticky**: every later `wait` on the same
  handle, `wait(c)` or `close(c)` re-raises the same failure; the staged
  action is **never run**; the core entry and the provider resources are
  retained (the work did not complete);
  (3) **provider success**: the provider releases the roots it held for
  that batch (the §8 retention duty ends at completion — a completed
  provider handle retains **no** batch/asset references, wherever it is
  kept); then the core staged completion (§7 staged writeback / upload
  completion action) runs **exactly once**, and the success flag
  (`staged_done`) is set **only after** the staged action returns
  successfully;
  (4) **staged failure** — the original named error is preserved **by
  identity** (a `TransferError` keeping its `:partial`/`:unwritten`
  status and detail; a named `BackendSubmitError` from the core
  dispatch; or the §7 phase-1 named validation error — e.g.
  `ArgumentError` — raised before any store): mark the entry `failed`
  with that original error — **sticky**: repeated
  direct `wait`, `wait(c)` and `close(c)` re-raise the same failure; the
  staged action is **never re-run automatically** (no implicit retry, no
  resubmission of the already-completed provider work, no reset); the
  entry is **not** completed or retired; the core staging (the
  destination and any partial bytes) is retained by the failed entry;
  the provider roots are **already released** (step 3) — the contract
  retains no released resources, only the core staging;
  (5) **staged success**: mark the entry `complete` and **retire it** —
  removed from `Canvas.submissions`, batch/asset references released at
  the §6 `:inflight` release point.
  Direct waits therefore retire as eagerly as wait-all: sixteen
  `submit → wait(flush!(c))` frames leave **zero** outstanding core
  entries and **zero reachable provider batch roots** (checked by the
  actual references — the completed handles, provider-tracked or
  externally kept, hold no batches — not by a release flag), not
  sixteen.
- `wait(c)` returns only when all outstanding entries have completed
  (or re-raises the first failure); an explicit `flush!` followed by
  `wait(c)` or `snapshot(c)` therefore cannot return while that
  submission is still pending.
- A core no-op submission (`CanvasNoopSubmission`) is core-owned (no
  provider type, no batch), never tracked, and inert: `wait` on it
  returns immediately without touching the provider, applying no staged
  action and transitioning no state — a zero-op flush between two real
  flushes does not complete, order, or otherwise affect the earlier
  handle.
- `close(c)` = **explicit flush-on-close, then wait-all through the
  single route**: (1) if `pending_ops` is non-empty: `flush!(c)` — on
  submit failure the pending work is **retained** (nothing is dropped or
  cleared), the canvas stays open and the error propagates; on success
  the tracked entry is appended to `Canvas.submissions`; (2) wait
  **all** tracked entries in order — including every earlier failed
  entry from prior `flush!`/`wait!`/`close` attempts (the same handles
  are re-waited; **no batch is ever re-submitted**, so unknown completion
  cannot trigger duplicate execution); a sticky failure — provider
  dispatch failure or staged failure (the original named error
  preserved) — re-raises, the staged action is never re-run — the
  failed entry remains in `Canvas.submissions` and the canvas **stays
  open** with all handles and assets retained for retry/deferred
  cleanup; later drawing and further flushes do not overwrite or retire
  the failed entry, and a later successful flush does not make `close`
  succeed while the failed entry is outstanding; (3) only when every
  tracked entry is `complete` (or a synchronous backend's handles
  pre-complete) and no pending work remains: `close(backend)`;
  `c.closed = true` — a **successful** close clears the owned tracking
  root entirely (every completed handle already retired; a
  provider-failed entry retains provider resources until the provider's
  own close per §8 — a staged-failed entry retains only the core
  staging, its provider roots already released at provider completion);
  a failed close leaves the failed entries retained (rule 2).
- Two flushes then close waits **every not-yet-complete** batch in order
  (a batch that completed earlier was already waited in order before its
  retirement) — a provider that forgets all but the latest submission
  violates this contract.
- Idempotent: `close` on a closed canvas is a no-op. Pending work is
  never silently dropped, and a failed close never frees provider
  resources or marks the canvas closed.
- **Bounded wait cost (frozen, revision 7)**: `wait(c)` scans only the
  outstanding (pending/failed) entries, so wait cost does not grow with
  total frame count; pending and failed entries are retained until a
  successful close or the §6 release points, and no successful history
  is kept (the counter is retained, not the handles).

## 9. Capability preflight (per-operation accounting)

Every draw call runs, in order: (1) state validation (finite geometry,
ranges, balanced state, paint resolvability — `ArgumentError`); (2)
capability preflight over the op's **full required id set** against the
public `capabilities(c).features` (no provider field access); (3) only
then owned state snapshots + op recording. A failed preflight records
**nothing and mutates no state** (atomicity — including `save!`/
`save_layer!`, which preflight **before** pushing the state snapshot,
incrementing `group_depth` or recording any op: `save_layer!` preflights
`layer.group`, `composition.<entry composition>` (§5.5 group rule — the
frozen group composite operator must be supported at entry) and
`state.clip` when ambient clips are present, plus fill/stroke style
resolvability (an image/tiled style without an image, or an unparseable
`String` style, raises at `save!` before any mutation, not at a later
draw); and image operations: `draw_image!` / image-paint
`fill!`/`stroke!` preflight **before** any asset capture is published — a
failed call leaves `assets`, `asset_next_id` and `asset_refs` unchanged).

Level policy: under `:strict` only `native` and `lowered` pass;
`fallback` and `unsupported` raise `BackendCapabilityError(feature,
:op_symbol)`. Under `:report`, a `fallback`-level provider advertisement
for `"<feature>.fallback-raster"` records the `RasterFallbackOp` marker +
`FallbackReport` instead of the op; `unsupported` still raises. Unknown
feature ids are unsupported, never assumed supported. **Marker lifecycle
(revision 4)**: an `:op`-scope marker is complete at record time. A
`:group`-scope marker (a `save_layer!` preflighting the group fallback)
opens at `save_layer!` — the state stack and group balance are maintained
exactly as for a supported group, so the matching `restore!` succeeds —
and is completed at that `restore!`, when the span's ops and captures
are retained in `marker.original` (§6). `:frame`/`:page`-scope markers
are completed at seal time with all covered ops. A marker never suppresses
canvas state and never leaves an unbalanced group.

Required id sets (combination-level; `state.clip`/`layer.group` are added
whenever the op carries ambient clips or is inside a group):

| Op | Base capability ids |
| --- | --- |
| `fill!` | `draw.fill`, `<paint id>`, `composition.<op>`, [`artistic.<name>` if artistic ≠ none], [`<paint>.alpha` if a gradient stop has a < 255] |
| `stroke!` | `draw.stroke`, `<paint id>`, `composition.<op>`, [`artistic.<name>`], [`<paint>.alpha`] |
| `clear_rect!` | `draw.clear` |
| `draw_image!` | `draw.image`, `sampling.<filter>[.<edge>]` (edge suffix only when ≠ clamp), `composition.<op>` |
| `draw_picture!` | the union of the replayed ops' ids |
| `fill_text!` / `stroke_text!` | `draw.text.portable`, `paint.solid` (text paints are solid in the portable profile), `composition.<op>`, [`artistic.<name>`] |
| `blur!` / `spread!` / `shadow!` | `effect.<kind>` |
| `clip!` | `state.clip` |
| `save_layer!` | `layer.group`, `composition.<entry composition>`, [`state.clip` when ambient clips are present] |
| `save!` | fill/stroke style resolvability only (no capability ids) |

`<paint id>` ∈ `paint.solid`, `paint.image`, `paint.tiled-image`,
`paint.linear-gradient`, `paint.radial-gradient`, `paint.angular-gradient`.
`composition.<op>` uses the 11 stable names: `source-over`, `source-in`,
`source-out`, `source-atop`, `over`, `in`, `out`, `atop`, `xor`, `copy`,
`lighter`. `artistic.<name>` uses the 15 stable names: `darken`,
`multiply`, `color-burn`, `lighten`, `screen`, `color-dodge`, `overlay`,
`soft-light`, `hard-light`, `difference`, `exclusion`, `hue`, `saturation`,
`color`, `luminosity` (the existing `BlendMode.value` 1..19 order minus the
internal mask values).

Public combination query seam (frozen): `feature_status(c, id::String)::
CapabilityStatus` (missing id ⇒ unsupported) lets consumers and conformance
tooling ask about any combination id before drawing; the per-op id
composition above is the complete rule — there is no separate hidden
accounting.

Equivalent shared lowerings (e.g. a stroke expanded to its outline, a
painted stroke lowered to outline fill) are permitted only where the
capability reports `lowered` and the lowering is covered by the R011
conformance corpus. Raster fallback scope is conservative:
destination-dependent operations (non-source-over composition, effects,
opaque-matte exports) fall back to the whole frame or a proven isolated
group, never an individual op in isolation. A GPU backend never routes work
through CPU rasterization without an explicit `:report` policy and an
advertised `fallback.cpu-raster` feature.

## 10. Physical sizing, device scale, mapping, resize

- Physical extents: `physical_width = max(1, Int(round(Float64(w) *
  Float64(device_scale), RoundNearestTiesAway)))` (height likewise),
  with checked `Int` overflow (overflow ⇒ `ArgumentError` at
  construction/resize). **Promotion before multiplication (frozen)**:
  the `Int` extent and the `Float32` scale are both widened to `Float64`
  *before* the product — `Float64(w) * Float64(device_scale)`, never
  `w * device_scale` in `Float32`. Pinned: logical `3` at scale
  `Float32(7/6)` → physical `3` (the rejected literal `Float32`
  multiplication ties at `3.5` and rounds away to `4`). Example:
  logical `(3, 2)` at scale `1.5` → physical `(5, 3)`. The same
  `physical_extents` function serves both directions of the §4 rule 1
  invariant (logical → physical at construction/resize; physical →
  logical at array/raw/adapter import), so no constructor route can bind
  a logical/physical pair that disagrees with the scale.
- `snapshot`, `read_pixels`, `upload_pixels!` regions and target arrays are
  all in **physical** units; `physical_size(c)` exposes the pair. Logical
  units are drawing coordinates throughout §3–§7.
- `local_to_device(c, x, y)` = `(x * scale, y * scale)` computed in
  `Float64`; `device_to_local(c, x, y)` = `(x / scale, y / scale)` in
  `Float64`. Round-trip bound:
  `|device_to_local(local_to_device(p)) - p| ≤ 0.5 / scale` physical units
  per axis (the contract states the bound; it does **not** claim an exact
  floating-point inverse for all finite inputs). Render narrowing to
  `Float32` happens at op capture, after host-precision mapping (plotting
  hosts subtract large integer origins before this boundary, §13).
- Browser DPR and PDF `dpi` are boundary mappings applied once, never extra
  transforms.
- `resize!(c, w, h; device_scale = nothing)` (requires capability
  `resize`; presentation targets) is the **public DPI-changing operation** —
  `device_scale` updates the scale (validated finite, > 0, overflow-checked
  per §10) or keeps the current one. Sequence: (0) **atomic validation**
  before any provider call — dimensions, scale, capability advertisement
  and the borrowed/staged rule below; (1) pending work is flushed first
  (unbalanced group or sticky completion failure ⇒ error, canvas stays
  open); (2) the provider re-binds through its documented
  `resize!(backend, spec)` method with the new `CanvasTargetSpec` —
  **old content is not retained** (callers snapshot beforehand if needed)
  and the rebind **bumps the provider generation** (§11 content rules);
  (3) device-scoped assets/pipelines are invalidated by the provider;
  (4) drawing state (styles, transform, font state, composition, alpha) is
  preserved; the cumulative clip list is **reset to the full canvas**
  (old-extent clips are invalid); (5) borrowed/staged host storage cannot
  change shape in place — `resize!` on such a canvas raises
  `ArgumentError("resize requires a re-bound canvas")`; the caller creates
  a new canvas and transfers state with `copy_canvas_state!`.

## 11. Browser boundary (Canvas2D + WebGL2, exact at the wire level)

- One versioned, closed JSON payload serves offline HTML, connected
  notebook views and both browser runtimes. The Julia adapter serializes the
  sealed `CommandBatch` + assets; the runtime (a small maintained JS module
  under `browser/`) replays it through the selected provider. No `eval`, no
  serialized Julia closures, no required server, no mandatory
  Julia-in-WASM.
- Schema identity: `"schema": "vetra.canvas.v1"`, `"provider":
  "vetra/browser/canvas2d" | "vetra/browser/webgl2"`, `"profile":
  "portable-2d"`. The runtime rejects a different major version (failed
  replay, named console error) and ignores unknown fields. Unknown op
  kinds fail replay with a named error — there is **no** generic "other"
  kind; every op crosses the wire with its actual geometry and state.
- **Wire records (frozen, revision 5)** — the payload is a closed set of
   concrete JSON records; independent Julia and JS writers/validators must
   not need to consult private model internals. R050 owns the serializer,
   this section owns the records. Every command is an object with a
   mandatory `"op"` tag from the fixed vocabulary below plus exactly the
   listed fields (no optional tags, no generic "other" kind — an unknown
   tag fails replay with a named error):

   ```
   envelope: { schema, provider, profile, generation, session, scope,
               size: [w, h] (physical), deviceScale,
               assets: { <id>: <asset record> },
               commands: [ <command record>, … document order … ],
               fallbacks: [ { index, feature, reason, scope } … ] }

   <clip record>    = { path: [number …], winding: "nonzero" | "evenodd" }
   <paint record>   = { kind: "solid" | "image" | "tiled-image" |
                        "linear-gradient" | "radial-gradient" |
                        "angular-gradient",
                        color: [r, g, b, a] 0..255 straight | null,
                        opacity: number 0..1,
                        artistic: <artistic name> | null,
                        assetId: number | null,
                        imageTransform: [9 numbers] | null,
                        handles: [[x, y] …] | null,
                        stops: [[r, g, b, a, pos] …] | null }
   <path>           = flat float array in the existing Vetra Path.commands
                      encoding (owned by the Path type; e.g. a rect is
                      13 floats) — the actual command count, never a
                      fixed-size placeholder

   "fill":          { op, path, winding, paint, transform: [9 numbers],
                      composition: <composition name>, clips: [<clip> …] }
   "stroke":        { op, path, paint, transform, composition, clips,
                      width, cap: "butt"|"round"|"square",
                      join: "miter"|"round"|"bevel", miterLimit,
                      dashes: [number …], dashOffset }
   "clear":         { op, rect: [x, y, w, h] (fractional — JSON numbers,
                      no truncation), transform, clips }
   "image":         { op, assetId, srcRect: [x, y, w, h] (fractional —
                      the captured Rect as-is; integer truncation is the
                      legacy 8-arg overload only, §5.6),
                      destRect: [x, y, w, h] (fractional), transform,
                      sampling: { filter: "nearest"|"linear",
                                  edge: "clamp"|"repeat" },
                      composition, opacity, clips }
   "text":          { op, glyphs: [{ outline: <path>,
                      transform: [9 numbers] } …], paint, transform,
                      composition, clips }
   "effect":        { op, kind: "blur"|"spread"|"shadow", radius,
                      offset: [x, y] | null, color: [r, g, b] | null,
                      opacity, inRegion: [x, y, w, h] (fractional —
                      the core's conservative bounds as declared),
                      outRegion: [x, y, w, h] (fractional), transform,
                      clips }
   "group-start":   { op, opacity, composition, clips }
   "group-end":     { op, clips }
   "fallback":      { op, feature, reason, scope: "op"|"group"|"frame"
                      |"page", original: { ops: [<command record> …],
                      assets: { <id>: <asset record> } }, clips }
   "set-pixels":    { op, assetId, rect: [x, y, w, h] }   # initial pixels
                                                           # (full canvas)
                                                           # and uploads
                                                           # (region);
                                                           # assetId is the
                                                           # captured core
                                                           # asset id (§6
                                                           # one namespace,
                                                           # §8 dispatch)

   submission (Julia → runtime, one per accepted execution — every
    drawing flush! and every upload dispatch, §7 ordered upload route):
     { kind: "vetra.canvas.v1.submission", id: number (monotonic per
       scope), scope, session, generation,
       commands: [ <command record> … sealed-batch delta, document order … ],
       assets: { <id>: <asset record> … new captures of this submission } }
   execution-ack (runtime → Julia, one per submission):
     { kind: "vetra.canvas.v1.execution-ack", id: <submission id echo>,
       scope, session, generation,
       status: "success" | "error", detail: string | null }
   ```

   **Command mapping (frozen)**: core semantics map onto records
   one-to-one (§6 accessors are the source): `FillOp`/`StrokeOp`/`ClearOp`/
   `DrawImageOp`/`TextOp`/`EffectOp`/`GroupStartOp`/`GroupEndOp`/
   `RasterFallbackOp` → the same-tagged records (a fallback record embeds
   its `original.ops` as nested command records); `upload_pixels!`/initial
   import → `set-pixels` carrying the captured asset id.
   `<composition name>`/`<artistic name>` are the §9 stable names.
   **The paint `kind` is the 1:1 wire name of the owning `PaintKind`**:
   `SolidPaint` → `solid` (`color` set, `assetId`/`handles`/`stops` null);
   `ImagePaint` → `image` and `TiledImagePaint` → `tiled-image`
   (`assetId` + `imageTransform` set, `color` null);
   `LinearGradientPaint` → `linear-gradient`, `RadialGradientPaint` →
   `radial-gradient`, `AngularGradientPaint` → `angular-gradient`
   (`handles` + `stops` set, `assetId` null). A linear gradient never
   serializes as a tiled-image, and only image/tiled paints carry an
   asset id. Image assets cross the boundary as **straight** RGBA8 (the
   browser `ImageData`/texture boundary), converted from the core
   premultiplied assets at serialization time with the §7 formulas.
   **Execution-ACK rules (frozen, revision 5)**: the runtime appends each
   submission's delta to the retained document in `id` order and emits
   **exactly one** execution-ack per submission after executing (or
   failing) it. A browser `wait(sub)` completes on **its own** success
   ack (→ `complete`) or error ack (→ `failed`, sticky
   `BackendSubmitError(detail)` per §8). An ack matching no pending
   submission — unknown `id`, wrong `scope`, stale or future `session`,
   superseded `generation` — is rejected by named `ArgumentError` and
   authorizes nothing; the pending submission is not consumed. A readback
   response is **not** an execution ack (it carries no pixel
   authorization of execution), and an execution ack is not a readback
   response. Context loss invalidates all pending submission acks and all
   pending readback requests immediately (the loss rule below).
- **Asset records and the one namespace (frozen, revision 4)**:
  `<asset record> = { kind: "image", width, height, encoding:
  "rgba8-straight" | "png-base64", data }` where `data` is the base64 of
  the encoded byte stream (raw straight bytes for `rgba8-straight`). The
  payload's `assets` map is keyed by the core's unique capture ids (§6),
  and **one monotonic namespace covers initial pixels, uploads and draw
  image/tiled captures** — all of them `set-pixels`/draw assets from the
  same `asset_next_id` counter. No two document entries may share an id
  or a key: a draw cannot take an id an upload (or the initial import)
  already holds, and content-identical captures remain distinct ids, so
  the payload never depends on version numbering.
- **Cumulative complete document**: the payload is the *complete* scene —
  every sealed batch in order, never a last-batch shadow. The target's
  **initial pixels** (imported at construction or uploaded) are retained as
  the document's first set-pixels entry with their asset; explicit
  `upload_pixels!` replacements are retained as entries in document order,
  so a standalone page rebuilt from the payload alone reproduces the full
  scene. A zero-op flush appends nothing (no empty marker).
- **Bounded retention with canonical accounting (frozen, revision 5 — the
  one authority for byte admission; the revision-4 per-leaf upper-bound
  formula is retracted)**: the provider advertises
  `limits["payload-max-ops"]` and `limits["payload-max-bytes"]`.
  **Canonical serialization**: the retained document is one JSON object,
  no whitespace, fixed key order — envelope keys in the documented
  order; the `assets` map keys are the captured core ids — insertion
  preserves each command's `assetId` (the document machine never
  invents ids, and the core namespace stays monotonic across
  destructive resize) — in ascending decimal order; asset records
  `kind, width, height, encoding, data`; command records `"op"` first, then the record's documented
  field order; arrays in element order. **Numeric wire types (frozen,
  revision 6 — one policy, no widening)**: integer fields (ids, sizes,
  pixel dimensions) serialize as plain decimal digits; every
  `Float32`-declared core field — geometry rects (clear/image/effect
  regions), the 9-element transforms, handles, radii, opacities, dash
  values, `deviceScale`, stop positions — serializes as that value's
  `Float32` shortest decimal (`string(v)` of the `Float32`), **never
  widened to `Float64` by the mapping** (pinned: a clear-rect corner
  `0.1f0` serializes as `0.1`, not `0.10000000149011612`, the
  widened-Float64 artifact); paint stop colors are byte integers
  0..255. Booleans `true`/`false`; absent values `null`. Strings are
  JSON-
  escaped: `"` → `\"`, `\` → `\\`, control U+0000–U+001F → `\uXXXX`.
  Asset `data` is standard base64 (with padding) of the encoded byte
  stream. **Admission**: `document_bytes` = the UTF-8 byte length
  (`ncodeunits`) of that canonical serialization of the retained
  document — the actual wire bytes, including base64, escaping, every
  field and the envelope; `document_ops` = command-entry count. The
  bound applies **at construction** — the initial pixels are the first
  `set-pixels` entry; an initial import alone over the bound raises
  `ArgumentError` naming the bound — and **before every flush
  mutation**: the core serializes the candidate document (retained +
  new entries) and requires it to fit both limits; on exceed it raises
  `ArgumentError` naming the bound, leaves the document unmutated and
  the pending ops retained. No estimate stands in for the measured
  length — variable geometry, base64 expansion, string escaping and
  integer width all count exactly. Pinned, independently justified
  admission examples (verified by the boundary checker against hand-
  derived fixtures): a 64×64 straight-RGBA8 initial asset's base64
  `data` alone is `⌈16384/3⌉·4 = 21848` bytes and its full canonical
  document is 22187 bytes — over any 17000-byte limit, where the
  retracted v4 formula had counted 16816; a 100-quote string
  serializes to 202 bytes (`\"`×100 + delimiters), not 104;
  `typemax(Int)` serializes to 19 digits, not 16;
  `floatmax(Float32)` serializes to `3.4028235e38` (12 bytes) — a
  finite bound, unlike the infinite `typemax(Float32)` the v4 checker
  tested. Because the canonical form keeps the declared `Float32`
  values (shortest decimal, no widening), the runtime's `Math.fround`
  re-quantization at decode is exact for every geometry field —
  canonical values survive Julia/JS parsing bit-exactly. The JS runtime replays
  exactly the serialized document it received (the same canonical
  form), so no second accounting formula is needed at replay. Providers
  that later advertise a reviewed checkpoint rule may instead
  checkpoint; v1 is pre-mutation rejection only.
- **HTML embedding (separate boundary)**: JSON quoting and HTML
  embedding are separate boundaries — the payload embedded in a
  `<script>` raw-text element is protected against `</script>`
  termination (`<\/script>`), and HTML labels/attributes are escaped in
  their own context (CANVAS_DESIGN.md §Browser).
- **Readback request/response records and consumption (frozen,
  revision 4)** — connected transport only; offline HTML has no readback
  channel at all. A browser canvas has a scope id; the session and device
  generations bump on context loss/recovery and on rebind/resize (§10
  generation rule).

  ```
  request  (Julia → runtime):
    { kind: "vetra.canvas.v1.readback-request", id: number (monotonic per
      scope), scope, session, generation, submission: number (count of
      COMPLETED provider submissions at issue — the execution boundary
      the request is bound to), rect: [x, y, w, h] (physical),
      encoding: "rgba8-premul" | "rgba8-straight" }
  response (runtime → Julia):
    { kind: "vetra.canvas.v1.readback-response", id: <request id echo>,
      scope, session, generation, submission: <echo>, encoding: <echo>,
      width, height, data: base64 }
  ```

  Rules:
  - Every `snapshot`/`read_pixels` on a connected browser issues
    **exactly one fresh request** after the execution boundary — all
    tracked submissions complete (§8.1) — and waits for **that
    request's own response** before producing pixels. Readback never
    reuses a previous request's authorization: each response is
    **consumed exactly once** (the pending-request set shrinks) and
    must match the **saved request** on every identity field — `id`
    (pending lookup), `scope`, `session`, `generation`, `submission`
    (the completed count *saved at issue*, not the current one),
    `encoding` — and the live identity must still match the saved
    request's (`session`/`generation` equal the scope's current
    values; context loss discards the pending request, so a live
    mismatch means the saved request is superseded).
  - A response failing **any** of those checks — unknown `id`, wrong
    `scope`, stale session, future session, superseded `generation`,
    `submission` ≠ the saved request's `submission`, `encoding` ≠ the
    saved request's `encoding`, `width`/`height` ≠ the saved request's
    rect dimensions, or decoded `data` length ≠ `4·width·height` for
    the `rgba8-*` encodings — is rejected by named `ArgumentError`
    **before consumption and discarded**: an invalid response
    authorizes nothing and cannot silently consume the pending
    request's authorization. A snapshot with no matching pending
    request raises
    `SnapshotError(Symbol("readback-failed"), ...)`. Readback
    responses are not execution ACKs (and execution ACKs are not
    readback responses) — the §11 execution-ACK rules govern
    submission completion separately.
  - Context loss invalidates **all pending requests and all prior
    authorization immediately** (session and generation bump, §11
    recovery below): a pre-loss response arriving after recovery is stale
    and rejected; a snapshot after loss must issue a fresh post-recovery
    request. Only a matching execution response completes a readback;
    rejection and timeout retain ownership — the retired request is
    dropped, the document/assets stay provider-owned and the next
    snapshot re-issues.
  - Readback timeout raises
    `SnapshotError(Symbol("readback-timeout"), ...)` (provider limit,
    default 5000 ms, declared in `limits["readback-timeout-ms"]`).
  - No implicit GPU readback ever creates a checkpoint.
- Canvas2D runtime: maps normalized ops onto native Canvas 2D APIs with the
  new canvas semantics (§5) — not a verbatim replay of legacy `Context`
  method names. `raster-readback` exists only on a **connected** transport
  (the request/ack flow above, timeout, disposal, tainted-canvas errors);
  offline HTML has no Julia readback channel, reports
  `SnapshotError(:offline-readback)`, and the payload remains
  **browser-owned** — the document data is sufficient to serve standalone
  pages after Julia exits.
- WebGL2 runtime (separate provider, user amendment 2026-11-12): real
  `canvas.getContext("webgl2")` draw calls — Canvas2D rendering, SVG display
  or uploading a completed CPU frame are **not** WebGL evidence. Context
  loss: on `webglcontextlost` in-flight submissions fail
  (`BackendSubmitError`, sticky per §8), **every pending readback request
  is invalidated immediately** (revision 4), the provider **retains the
  complete document** (ops + assets, browser-owned) and on
  `webglcontextrestored` re-uploads assets and replays from the retained
  document; canvas state is re-applied from §3 fields; the session and
  device generations bump, invalidating every prior ack (stale-session
  rule above). **Destructive resize (revision 4)**: a browser `resize!`
  clears the retained document — prior commands, uploads and their asset
  entries referenced the old size — bumps the device generation, and
  restarts the document with the new physical target's initial pixels
  (as the first `set-pixels` entry, when present); prior-generation
  requests are invalidated. Framebuffer orientation (top-down),
  premultiplied-alpha color-space handling, DPR/resize and async disposal
  have explicit conformance cases (C2D-045…049).
- **Disposal (revision 4)**: a successful `close` removes the canvas's
  scope from the provider's root and releases **every** provider-held
  reference — the retained document, its assets, all submission handles
  and all pending request/response records (failed submissions keep
  provider resources per §8 until the provider's own close, but the root
  entry is removed regardless) — closed sessions never persist in
  provider-owned roots; a later canvas gets a fresh scope that cannot
  alias a closed one. Disposal does not read back the GPU.
- **Shader route decision record (for R053 review; the frontend contract
  above does not depend on it).** WebGL2 consumes GLSL ES 3.00 shaders, not
  Vulkan SPIR-V modules; no verified Julia→GLSL compiler or SPIR-V→GLSL
  translator exists in the approved dependency set (D014/D015;
  CANVAS_RESEARCH.md). Options: (a) provider-owned GLSL ES 3.00 shader
  sources in `lib/VetraBrowser/`, with the Julia-owned geometry/lowering
  (tessellation, arc flattening, gradient sampling tables, coverage math
  mirrored from the Julia kernels) shared and the per-pixel coverage kernel
  expressed in GLSL; conformance against the CPU portable profile is
  required before any capability is advertised — **recommended, explicit
  proposal for review, not an approved policy**; (b) a reviewed external
  translator — currently unverified and blocked; (c) CPU raster + texture
  upload — forbidden (not native scene execution). (a) is a deliberate,
  reviewable narrowing of the "algorithms in Julia" policy to the browser
  provider's kernel boundary; the coordinator must approve (a) or (b)
  before R053 kernels.
- The two browser providers are separately selectable (constructor
  `backend = BrowserBackend(:canvas2d)` / `BrowserBackend(:webgl2)` shape,
  R050/R053 own the concrete type) and separately reported in
  `capabilities.provider`. A capability matrix row is per-provider.

## 12. Document backends (PDF, SVG)

PDF (R061/R062 own implementation; v1 semantics frozen here, built on the
existing strict `pdf_write.jl`):

```julia
PdfDocument(path::String; dpi::Float32 = Float32(96))::PdfDocument
new_page!(doc::PdfDocument, w::Int, h::Int)::Canvas   # seals the open page
close!(doc::PdfDocument)::Nothing                     # finalizes exactly once
```

- **Page identity vs batches**: a page is a canvas, not a batch. Repeated
  `flush!` on a page canvas accumulate that page's batches **in order** —
  they never create new pages. Only `new_page!` starts a new page.
- `new_page!` seals the open page canvas: it flushes the canvas's pending
  work (unbalanced group ⇒ `ArgumentError`, the new page is not created),
  then **closes the sealed page canvas** — drawing on it afterwards raises
  `CanvasClosedError`.
- Page units: logical units × 72/dpi points (existing `writePdf` dpi rule);
  one `dpi` per document in v1.
- `close!(doc)`: seals the open page (same rule as `new_page!`), then runs
  the document-level strict pre-scan over every page's accumulated batches —
  the rule source is the frozen PDF v1 strict matrix (RECORDING.md §6.2;
  `pdf_write.jl`): the first unexportable op raises `ArgumentError` naming
  page, batch, op index and feature, and **no file is published** (staged
  publication only); the
  canvas-level `:report` policy is the raster-fallback equivalent
  (whole-page raster, documented).
- Empty document (zero `new_page!`): `ArgumentError("PDF document has no
  pages")`. Repeated `close!`: `ArgumentError("document already closed")`.
  Closed IO: `ArgumentError` carrying the system message (existing style).
- `read_pixels`/`snapshot` on a PDF canvas: `BackendCapabilityError`
  (documents have no raster), unless the caller explicitly requested CPU
  rasterization of the retained recording (documented opt-in, R061).

SVG (R063): `Canvas(w, h; backend = SvgBackend())`; export
`write_svg!(file, c)` (or `write_svg!(file, c; raster_fallback = false)`)
follows the existing strict v1 matrix (RECORDING.md §6.1) over the sealed
batch; the canvas itself stays rasterless.

## 13. Extension seams (zero core edits)

Every seam below is provider-owned types + methods on frozen core generics.
No closed enum, no registry, no core `weakdeps`/export edit for new
providers. Sketches in §16.

- **Render backend**: §8 protocol + §6 command/asset accessors. Provider
  owns its `CanvasBackend`/`CanvasSubmission` subtypes and implements only
  advertised capabilities; `bind_target!` is the sole target-binding point.
- **Pixel storage adapter (frozen, revision 5 — the one authority for
   the adapter boundary)**: provider-owned wrapper implementing the
   minimum public surface:
   ```julia
   storage_descriptor(s::StorageAdapter)::StorageDescriptor
   storage_read(s::StorageAdapter, region::Rect)::CanvasAsset
   storage_write!(s::StorageAdapter, region::Rect, data::Vector{UInt8})::Nothing
   storage_alloc(prototype::StorageAdapter, ::Type{T},
                 dims::Tuple{Int, Int})::T where {T<:StorageAdapter}  # optional
   ```
   where `StorageDescriptor(element, layout::PixelLayout, writable::Bool,
   axes_ordered::Bool)` describes the provider's storage —
   `layout.width` is the pixel width (columns), `layout.height` the
   pixel height (rows). **Canonical exchange**: `storage_read`/
   `storage_write!` exchange **owned premultiplied RGBA8** bytes for the
   region — top-down, row-major, `length(data) == 4·region.w·region.h`;
   a read never aliases provider storage. Regions are **zero-based
   physical pixel rectangles**: `storage_read(s, rect(0, 0, 1, 1))`
   addresses the provider storage's first element. The **adapter owns
   the conversion** between this canonical boundary and its underlying
   layout (straight/gray/float/element, either scan order); the core
   never sends converted bytes through `storage_write!`, and native
   array output conversion is the separate §7 route. **Allocation is
   explicit**: `storage_alloc` takes the requested type `T` (a
   `StorageAdapter` subtype) and the target pixel `dims` `(width,
   height)` — a descriptor cannot infer `Matrix` versus `Vector` or any
   container shape — and returns a fresh same-type adapter with that
   storage; the core fills it through the public descriptor/write
   dispatch below, never by touching provider fields.
   **Consumer routes (frozen, revision 5)**:
   - `Canvas(s::StorageAdapter; copy=true)` calls `storage_descriptor` +
     `storage_read` (full-canvas region) and passes the owned premul
     pixels to the provider **as `spec.initial`** (owned import — never
     assigned to provider internals after binding); the initial asset is
     validated against the physical extents per §4 rule 1.
   - `Canvas(s; copy=false)` requires `writable` storage, stages into
     the provider target and writes back through `storage_write!` at
     `wait(flush!(c))` (the §7 commit rule applies to the writeback;
     the exchange stays canonical premul RGBA8).
   - `snapshot!(s::StorageAdapter, c)` — the only public in-place
     route. Dispatch order: (1) `storage_descriptor(s)`; (2) validate
     against the canvas — `writable == true`, `layout.width`/
     `layout.height` equal the canvas's physical extents — otherwise
     `ArgumentError` naming the failure, with **zero**
     read/write/alloc calls on the adapter; (3) flush and wait all
     outstanding work (§8.1); (4) read the target through the public
     synchronized `read_pixels`; (5) slice the owned premul RGBA8
     bytes for the full physical region (the canonical boundary — no
     conversion step here; that is the adapter's); (6)
     `storage_write!(s, rect(0, 0, pw, ph), bytes)`.
   - `snapshot_alloc(s::StorageAdapter, c)` — the only public
     allocating route. Dispatch order: (1) `storage_descriptor(s)`;
     (2) flush + wait; (3) `read_pixels`; (4)
     `storage_alloc(s, typeof(s), (pw, ph))` — the explicit type and
     dimensions; (5) fill the **returned adapter** via its own public
     `storage_descriptor` + `storage_write!` (full region, premul
     bytes); (6) return the filled adapter. Native array allocation
     (`snapshot(c, T)` for array `T`) is the separate §7 typed route
     and never involves an adapter.
   An out-of-tree owned wrapper tracing through these public consumers
   is the proof boundary for this seam (§16 sketch; R013/R022 execute
   it). Direct provider-method calls in the boundary checker prove the
   provider surface only — not consumer dispatch order (the normative
   trace is this section; runtime integration is pending, §19 G13).
   External pixel layouts integrate without adding branches to the
   built-in conversion kernels.
- **Image codec**: provider-owned format type + methods on the frozen
  public extension generics (pure functions, dispatched on the provider
  type): `Vetra.decode_image(data::AbstractVector{UInt8}, fmt) -> Image`,
  `Vetra.decode_image_dimensions(data::AbstractVector{UInt8}, fmt) ->
  Tuple{Int, Int}`, `Vetra.encode_image(image::Image, fmt) ->
  Vector{UInt8}`. The built-in one-arg `decode_image` magic sniffing and
  `FileFormat`-enum `encode_image` stay core-owned convenience; external
  formats never require an entry in that table. Decode-only/encode-only
  codecs implement only their side.
- **Frame/media provider** (details frozen by R064 against this boundary):
  frame pixels are owned `Image`s or §7 arrays (never decoder-buffer
  aliases); timing is `Rational{Int}` seconds with checked arithmetic; loop
  counters normalized (`0` = infinite). Lifecycle names: `close!(reader)`,
  `finish!(writer)`, `abort!(writer)`. Recording callback (frozen shape):
  `record_frames!(writer, n::Int, draw::Function; fps::Rational{Int} = 30)`
  invokes `draw(canvas, i, t, dt)` once per frame in presentation order —
  `i` 1-based `Int`, `t`, `dt` rational seconds on the output timeline,
  `t = 0` first; the canvas is core-created at the writer's declared frame
  size with fresh state per frame; callback error aborts the writer,
  preserves source files (staged output) and propagates. Detailed media
  metadata (tracks, VFR, palette policy) stays R064-owned and is explicitly
  deferred from this contract.
- **Display integration**: provider-owned view types wrapping public
  payloads (`snapshot`, browser payload, document path) with provider
  `Base.show`/`Base.display` methods; the core keeps its existing `Image`
  MIMEs (`image/png`, `text/plain`) unchanged. No provider may override
  another package's `show`; notebook HTML views must carry a static
  fallback (PNG) inside the HTML itself. The verified notebook targets are
  the portable IJulia kernel path (V001-approved) with VS Code notebooks as
  the user acceptance frontend.
- **Embedding beneath GUI/plotting** (R014 verifies): headless metrics
  (`measure_text`, `typeset`+`layout_bounds`, `paragraph_metrics`,
  `compute_paths` — advances equal drawn placement), precise mapping
  `local_to_device(c, x, y)` / `device_to_local(c, x, y)` (§10 bound),
  world→local is host-owned (hosts subtract large integer origins in host
  precision before Float32 narrowing — the canvas receives finite local
  geometry only), geometric hit tests (§5.6), conservative bounds
  `picture_bounds(p) / op_bounds(op) -> DrawBounds` (including stroke/
  effect expansion; `unknown = true` for destination-dependent regions),
  and host lifecycle via §8 (hosts own event loops, flush/wait/present
  timing and invalidation; a zero-size minimized window pauses
  presentation instead of allocating an invalid target).

## 14. Legacy migration (Context / Picture)

- Legacy `Context`, `Picture`, `PictureRecorder`, `RecordingContext` keep
  their documented behavior byte-for-byte (CPU regression profile); the
  canvas does not alter them. Legacy limitations (solid-only Context
  strokes, identity-transform clip, unsaved text baseline, clear ignoring
  clip, all-20-blend fill styles) remain legacy behavior, **not** canvas
  semantics.
- Name mapping `Context` → `Canvas` surface is 1:1 plus the new-profile
  rules: composition state (§5.7), clip captures the transform (§5.4),
  `text_baseline` is saved (§5.5), `clear_rect!` honors the clip (§5.6),
  `line_dash_offset` added (§5.2), mask-family blends internal-only (§5.7),
  painted strokes and tiled fills become valid (§5.6/§5.8 — new capabilities,
  not restrictions).
- **Lossless normalized recording (frozen, revision 7 — the one
  authority)**: the Canvas's own recording boundary is lossless. Every
  `CanvasOp` kind carries its full effective state (§6): `GroupStartOp`
  (entry opacity **and** entry composition), `DrawImageOp` (asset id,
  **sampling**, composition), `StrokeOp` (dash array **and dash phase**
  `dashOffset`, caps/joins/miter), `EffectOp`, `TextOp` (owned glyph
  outlines), `ClearOp` (fractional rect + clips), `ClipScope` (winding).
  **The recording boundary is the owned `CanvasRecording` value and the
  two public routes around it** (frozen, revision 7 — capture does NOT
  go through `flush!`: that returns the tracked frontend handle (§8.1)
  with no public accessor back to a `CommandBatch`, and `submit!` is the
  provider protocol, not a frontend replay route; the `batch_*`
  accessors serve the provider side only, §6):
   ```julia
   struct CanvasRecording
       ops::Vector{CanvasOp}          # normalized, sealed (group-balanced)
       assets::Dict{Int, CanvasAsset} # every capture the ops reference
                                      # (owned deep copies, §6)
       size::Vec2                     # the logical canvas at capture time
   end
   record_canvas(f::Function, w::Int, h::Int)::CanvasRecording
   draw_recording!(c::Canvas, r::CanvasRecording)::Nothing
   draw_recording!(c::Canvas, r::CanvasRecording, dest::Rect)::Nothing
   ```
   - `record_canvas(f, w, h)` is the **record-only capture route**:
     `f(rc)` draws into a headless record canvas — **no backend is bound
     and no device execution happens** (no `submit!`, no staged
     writeback), and the record canvas **cannot read pixels**
     (`snapshot`/`read_pixels` raise
     `SnapshotError(Symbol("record-only"), …)`). At the end of `f`, the
     pending ops are sealed with the same validation as `flush!` — an
     unbalanced `save_layer!` raises the same named
     `ArgumentError("unbalanced save_layer at record")` — and the
     recording owns **every asset the ops reference** (deep copies at
     call-boundary capture, §6 ownership; the source canvas may release
     its captures without invalidating the recording). Extent: the
     recording covers exactly the ops `f` recorded — **not** the
     canvas's whole history (the record route never implicitly retains
     backend history). **Seal ownership boundary (frozen, revision
     7)**: the seal takes the ops **already owned** — §6 ownership makes
     every op's `path`, `clips` paths and `OwnedPaint` arrays the op's
     own deep snapshots at record time, so the seal does not re-snapshot
     ops (no double ownership); it owns its op container and deep-copies
     only the asset bytes the ops reference (assets live in a separate
     store that ops address by id). Mutating asset bytes after the seal
     is inert; the record route never hands out mutating handles to op
     internals, so caller mutation of an op path after the seal is
     outside the contract (no such handle exists on the public surface).
   - `draw_recording!(c, r[, dest])` replays the recording into the
     Canvas world of any open (non-record-only) canvas: each referenced
     asset is re-captured into `c`'s asset store with fresh
     target-scoped ids — the **one 1:1 remap covers both reference
     classes**: `DrawImageOp.assetId` draw references and
     image/tiled `OwnedPaint.imageAssetId` fill/stroke/text paint
     references (no second id space; the recording's internal ids are
     never the target's ids, §6 fresh-id rule); every op is recorded as
     a fresh
     normalized op with the remapped ids, preflighted as a union under
     the target's capabilities (the §9 `draw_picture!` union rule — an
     unsupported op raises the named `BackendCapabilityError` **before
     any op is recorded**), and placed per the placement rule below
     (`dest` defaults to the full canvas). **Target ambient clip
     combination (frozen, revision 7)**: the replayed op's clip list is
     the **target's ambient clip list (canvas space, unchanged — a
     target clip must not disappear during replay) followed by the op's
     recorded clips mapped under `ambient * mapping` exactly once** —
     cumulative intersection in list order (§5.4); `GroupStartOp.clips`
     (recorded entry ambient) and `GroupEndOp.clips` (recorded restore
     ambient) combine the same way (target ambient first, mapped
     recorded list second). The replayed ops enter `c.pending_ops` in
     order and execute at the target's next `submit!` like any other
     ops. Replay inside the Canvas world preserves every field; the §11
     wire records map one-to-one. No legacy extension or semantic
     change is needed to record and replay new Canvas content.
- **Legacy `Picture` adapter (frozen, revision 9 — explicit,
  conservative, lossy only in named dimensions)**:
  `canvas_picture(r::CanvasRecording)::Picture` (frozen name; R020
  owns) converts the explicit normalized recording to the **unchanged**
  legacy vocabulary — the actual Vetra `Picture(ops::Vector{PicOp},
  size::Vec2)` with `FillOp`, `StrokeOp`, `ClearOp`, `DrawImageOp`,
  `GroupStart`, `GroupEnd`, `PicClip` — reusing the legacy
  `RecordingContext`/`PictureRecorder` snapshot rules (paths
  deep-copied, paints deep-copied **including the image payload and
  opacity**, per-op `tform`, clip paths shared by reference and never
  mutated after recording, text lowered to glyph-outline fills at the
  record boundary). The legacy APIs and their behavior are unchanged.
  **The unchanged vocabulary cannot carry everything the normalized op
  can**; the conversion is conservative — it lowers only the
  combinations below and raises a named `ArgumentError` (op index +
  missing legacy dimension) for the rest.
  **Decision procedure (frozen, revision 9 — disjoint and complete;
  first matching rule wins; the revision-6 overlapping rows, the
  revision-7 row-coverage holes and the revision-8 final accept row
  that required non-artistic (leaving the unwrapped artistic draw
  without an accept row) are retracted)**: per op, in recording
  order, let `L` be the op's ambient
  clip list and `E` the entry clip list of the innermost enclosing
  normalized group (none at root). **Wrapper rule** (mirrors the actual
  `_recWrap` emission): at root, `L ≠ ∅` ⇒ the op is emitted inside an
  implicit clip group (`GroupStart(1.0)` … op … `GroupEnd(L)` — the
  clip carried as `PicClip` by the wrapper's `GroupEnd`); inside a
  group, `L == E` ⇒ no per-op wrapper (the enclosing group's `GroupEnd`
  mask carries it — the legacy group composite is Normal-drawn with
  `GroupStart.opacity` applied once, exactly the §5.5 group rule); an
  op whose `L` differs from `E` inside a group (a clip set inside the
  group) ⇒ **reject** (the legacy group mask applies to the whole
  group — a partial-lifetime child clip is not representable). For
  fill/stroke/text the op's effective opacity is **baked into the
  emitted legacy `Paint.opacity`** (an actual paint field the legacy
  fill pipeline applies); for `DrawImageOp` with effective opacity ≠ 1
  it is carried by the implicit alpha group (`GroupStart(α)` — the
  legacy `DrawImageOp` replay constructs its own unit-opacity paint).
  The clip and alpha wrappers compose exactly as the actual `_recWrap`
  (clip group outer, alpha group inner). The implicit clip wrapper
  replaces the op's destination with a transparent scratch composited
  back **Normal**: it is pixel-preserving exactly for source-over,
  non-artistic, non-Copy draws.
   | Normalized input (first match wins) | Legacy constraint | Result |
   | --- | --- | --- |
   | `GroupStartOp.composition ≠ SourceOver` | `GroupStart` has no composition field (the legacy group composite is Normal-drawn) | **reject** |
   | `GroupStartOp` / `GroupEndOp` (composition source-over) | lowered 1:1 — `GroupStart(opacity)` (entry alpha frozen, §5.5) and `GroupEnd(clips)` (the restore-time mask) | accept |
   | `EffectOp` (any kind) | no `EffectOp` in the legacy vocabulary | **reject** |
   | `ClearOp` with non-empty `L` | legacy `ClearOp` has no clip field and the actual recorder never wraps clear (legacy clear ignores the clip; Canvas `clear_rect!` honors it, §5.6) | **reject** |
   | `ClearOp` (unclipped) | lowered 1:1 (clear ignores paint/alpha/composition in both models) | accept |
   | `DrawImageOp` with composition ≠ source-over | no composition field; the Normal wrapper composite would lose the operator | **reject** |
   | `DrawImageOp` with sampling ≠ (linear, clamp) | no sampling field in the legacy vocabulary | **reject** |
   | `DrawImageOp` with fractional `srcRect` | the legacy source region is an integer-truncated `subImage` (the actual 8-arg/Rect recorder overloads) | **reject** |
   | `DrawImageOp` (source-over, linear/clamp, integral `srcRect`, any effective opacity) | lowered 1:1 (deep-copied payload, `imageMat`, dest rect; the implicit clip wrapper per the wrapper rule at root, the alpha wrapper for opacity ≠ 1) | accept |
   | `FillOp` with a tiled-image paint | the actual recorder raises at the record boundary ("TiledImagePaint fills are not recordable") | **reject** |
   | `StrokeOp` with a non-solid paint | the legacy record boundary accepts solid stroke paints only (the actual `_solidPaint` raises) | **reject** |
   | `StrokeOp` with `dashOffset ≠ 0` | legacy `StrokeOp` has no dash phase | **reject** |
   | fill/stroke (incl. `TextOp` glyph outlines) with composition ∉ {source-over, `Copy`} | `FillOp`/`StrokeOp` carry no composition operator; the Normal wrapper composite would lose it | **reject** |
   | `Copy` fill/stroke with an artistic paint | one legacy `Paint.blendMode` field — it cannot carry `OverwriteBlend` and an artistic blend at once | **reject** |
   | `Copy` fill/stroke/text with effective opacity 0 (baked `Paint.opacity = 0`) | the legacy fill/stroke pipeline **early-returns** on zero paint opacity — the actual Picture leaves the destination untouched where normalized Copy must clear (**reproduced on the actual legacy recorder**: an opaque-red Copy at `Paint.opacity = 0` over opaque blue **leaves blue**; the revision-7 transparent-color @ unit-opacity control is a different route — color alpha at unit opacity — and does clear) | **reject** |
   | `Copy` fill/stroke with the implicit clip wrapper (root `L ≠ ∅`) | the wrapper composites the scratch Normal — the Copy operator is lost (**reproduced on the actual legacy recorder**: a clipped transparent Copy replayed over opaque blue **leaves blue** where Canvas Copy must clear) | **reject** |
   | `Copy` fill/stroke/text with effective opacity ≠ 0, non-artistic paint, and **no implicit clip wrapper** — unclipped at root **or inside an explicit group** (`L == E`; the legacy `GroupStart.opacity` carries the group factor 1:1 — the scratch is the Copy op's backdrop in both models) | lowers to an `OverwriteBlend` paint with `Paint.opacity =` the effective opacity — verified pixel-preserving (**reproduced**: an unclipped transparent `Overwrite` fill clears) | accept |
   | source-over fill/stroke (incl. text outlines) with an artistic paint **and** the implicit clip wrapper (root `L ≠ ∅`) | the wrapper replaces the backdrop: the blend runs against the transparent scratch, not the real destination (**reproduced on the actual legacy recorder**: clipped red Multiply over opaque blue yields **red** — the layer sees a transparent backdrop — where the normalized §5.7 rule requires **black**; the unclipped direct draw is the preserving control — **reproduced**: black) | **reject** |
   | source-over fill/stroke (incl. text outlines; solid/gradient/image paint, any effective opacity baked into `Paint.opacity`) at root — unclipped, **or with the implicit clip wrapper only when non-artistic** (`L ≠ ∅` — source-over non-artistic is pixel-preserving through the Normal scratch composite; the wrapped-artistic case is governed by the reject row above) — or inside a group with `L == E` (incl. under a group entry opacity ≠ 1.0 — the scratch is the op's backdrop in both models; the group factor applies once at composite) | lowered 1:1 (clips via `PicClip` in the wrapper's `GroupEnd` where required; an artistic blend rides on `Paint.blendMode` — the true backdrop is intact, so the unclipped direct draw is pixel-preserving (**reproduced**: Multiply over blue ⇒ black)) | accept |
   Every rejection is a **legacy-conversion limit, not a recording
   limit**: the lossless normalized route (`draw_recording!`) supports
   all rejected features. The adapter never fabricates an encoding and
   never changes semantics silently. The revision-3 two-field canvas
   "Picture", the revision-4 promise that "every normalized op
   converts to its existing counterpart", the revision-5 unconditional
   `Copy` lowering, and the revision-6 overlapping table rows (a
   blanket non-source-over reject that still accepted `Copy`; a
   non-solid stroke reject that still accepted gradient/image strokes;
   a `DrawImageOp` opacity rejection though the wrapper preserves it;
   a `Copy` rejection under a group entry opacity the legacy
   `GroupStart.opacity` carries 1:1), the revision-7 zero-opacity
   `Copy` acceptance (the legacy fill/stroke early-return leaves the
   destination — reproduced), the revision-7 `Copy` accept row that
   covered only top-level draws (grouped Copy is representable), and
   the revision-7 source-over accept row that covered only unclipped
   root draws (the clipped non-artistic root is representable through
   the wrapper) are all retracted by this table.
- **Owned resources, ID remapping and lifetime (frozen, revision 7)**:
  a `CanvasRecording` is self-contained — its `assets` map holds the
  deep-copied owned payloads, never live canvas references, so the
  source canvas may release the captures (the `:recording` owner ends
  at the `record_canvas` seal) without invalidating the recording;
  `draw_recording!` re-captures each referenced asset into the
  **target's** asset store with fresh target-scoped ids (the
  recording's internal ids are remapped 1:1 within the replay — the
  one remap over both reference classes, the `draw_recording!` rule
  above — and are never the target's ids), owned for the target's
  pending/inflight lifetime (§6). A `Picture` is self-contained the same way
  (`DrawImageOp.image` is the deep-copied owned payload; the source
  canvas's `:recording` owner ends at `canvas_picture`), and
  `draw_picture!`/`Canvas(picture, w, h)` remap ids the same way. The
  revision-3 replay that produced a `DrawImageOp` with an empty asset
  map is a defect, not a rule.
- **Placement (frozen, revision 7 — the one authority for the math;
  the revision-4 factor order is corrected, the revision-6
  target-ambient-clip gap is closed by the `draw_recording!` rule
  above)**: `draw_picture!(c, picture)` maps the
  picture's logical canvas onto the **full canvas** in vector space;
  `draw_picture!(c, picture, dest::Rect)` maps it onto `dest`. Under the
  actual Vetra `Mat3` convention (the leftmost factor applies last to a
  point; `transform!(c, m)` sets `c.transform = c.transform * m`, §5.2),
  the mapping is

  ```
  mapping = translate(dest.x, dest.y)
            * scale(dest.w / picture.size.x, dest.h / picture.size.y)
  ```

  so the picture origin lands at `(dest.x, dest.y)` and the picture
  corner at `(dest.x + dest.w, dest.y + dest.h)`. The rejected
  revision-4 order `scale * translate` scaled the destination origin
  (a 2×2 picture into `dest(10, 20, 4, 6)` sent its origin to
  (20, 60), not (10, 20)). Per-op transforms compose as
  `ambient * mapping * op.tform` — the target's ambient transform at
  the call, then the mapping, then the op's picture-space transform
  (exactly as `drawPicture` applies `canvas * op.tform`). Picture-space
  clip geometry (root clips, `GroupEnd` restore-time clips) maps under
  `ambient * mapping` — clip paths carry no per-op `tform`, so they too
  are mapped exactly once. Image geometry (an op's picture-space dest
  rect and `imageMat`, or the normalized equivalent) is mapped **exactly
  once** by the same rule; the image's own pixel space is addressed only
  through the already-mapped `imageMat`, never re-scaled by the
  placement. Replayed ops are recorded as fresh normalized ops in the
  target (preflighted under the target's capabilities — §9
  `draw_picture!` union rule), never by re-reading picture state.
  `Canvas(picture, w, h)` is the same placement with `dest` = the full
  `(w, h)` canvas. Owner: R020 (implementation + conformance); the
  semantic boundary is this section.

## 15. Conformance inventory (bounded table)

Ids are the stable conformance identifiers used by R011 fixtures and every
backend capability report. Owner = implementation task; `profile` ∈ CPU
regression / portable 2D / native display. Requirements state the **full**
semantics a passing backend must honor; per-backend capability reports
(track `native/lowered/fallback/unsupported`) state what each backend
actually supports at a given revision — an unsupported required feature is
an explicit test outcome of its owner task, not a permanent exclusion.

| Id | Requirement (semantic) | Profile | Owner |
| --- | --- | --- | --- |
| C2D-001 | Top-left origin, y-down, x-right; finite Real boundary converts once | portable | R021 |
| C2D-002 | Pixel `[row,col]` covers `[c-1,c]×[r-1,r]`; center `(c-0.5, r-0.5)` | portable | R021 |
| C2D-003 | Device scale separates logical/device; physical rounding per §10, no double transform | portable | R021 |
| C2D-004 | Transform post-multiply order; singular ⇒ no-op fill/stroke | portable | R021 |
| C2D-005 | Non-finite CTM rejected at draw call | portable | R021 |
| C2D-006 | Clip captured in canvas coords at `clip!`; later transforms don't move it; ops carry ambient clips | portable | R032 |
| C2D-007 | Clips intersect; save/restore scopes leak nothing | portable | R032 |
| C2D-008 | Clear replaces with transparent under transform+clip, ignores paint/composition | portable | R032 |
| C2D-009 | Save/restore snapshots drawing state only (incl. text baseline, dash copy, composition); no pending/exec internals | portable | R021 |
| C2D-010 | Isolated layers; entry alpha/composition frozen on the group; child context starts neutral (alpha 1, SourceOver); group factor applied exactly once at GroupEnd; net single-child alpha 0.5 for entry 0.5; nested groups compose; entry composition preflighted (§5.5) | portable | R032 |
| C2D-011 | Source-over byte-pinned (existing `blendNormal` kernel) | portable | R030 |
| C2D-012 | Copy operator byte-pinned | portable | R030 |
| C2D-013 | 15 artistic modes byte-pinned to existing kernels as CPU reference | portable | R030 |
| C2D-014 | 8 non-source-over/copy Porter–Duff operators + Lighter per W3C reference equations, quantized §5.7 | portable | R032/R043 |
| C2D-015 | globalAlpha multiplies source before compositing; clip after; coverage weighting frozen | portable | R032 |
| C2D-016 | Mask-family blends internal-only; user setting rejected | portable | R032 |
| C2D-017 | Composition × artistic × paint × sampling combinations preflighted per §9 table | portable | R021/R032 |
| C2D-018 | Solid fill nonzero/evenodd winding, holes, self-intersections | portable | R030 |
| C2D-019 | Arcs: zero radius no-op; full turn complete; zero span ≠ full turn | portable | R030/R050 |
| C2D-020 | Stroke under non-uniform scale follows geometry (local-space expansion) | portable | R031 |
| C2D-021 | Painted (non-solid) strokes: shared outline lowering, dash/offset, any paint kind | portable | R031 |
| C2D-022 | Dash array + dash offset phase, caps, joins, miter limit | portable | R031 |
| C2D-023 | Stroke hit test incl. dashes; singular transform ⇒ false | portable | R031 |
| C2D-024 | Linear/radial/angular gradients: local coord space, stop validation | portable | R033 |
| C2D-025 | Degenerate gradient handles keep pinned kernel behavior | portable | R033 |
| C2D-026 | draw_image src/dest rects (integer src truncation = legacy 8-arg overload only; the Rect form preserves the fractional source rect), nearest/linear, clamp/repeat edges | portable | R033 |
| C2D-027 | Image asset capture at call/save boundary; every capture = fresh unique id (draw/mutate/draw ⇒ two distinct contents in one batch); owner-tracked retention — saved state keeps captures across flushes, completed-and-unreferenced captures release; mutation inert on sealed ops and saved state | portable | R020 |
| C2D-028 | Tiled image paints: repeat in transformed image space, recordable as ops | portable | R033 |
| C2D-029 | Blur/spread/shadow: effective opacity + clips in ops, bounded regions, existing kernel formulas | portable | R034 |
| C2D-030 | Portable text: outlines at call time, headless metrics == placement, composition/alpha honored | portable | R012 |
| C2D-031 | Native browser text is a separate profile, labeled | native | R052 |
| C2D-032 | Painter order preserved; overlapping translucent ops not reordered | portable | R021 |
| C2D-033 | `measure_text` headless, no device init/readback | portable | R012 |
| C2D-034 | Array copy import; source mutation inert after construction | portable | R022 |
| C2D-035 | CPU borrow `:direct`/`:staged` with **truthful** memory layout label (ordinary Julia matrix ⇒ `:col`); staged upload and draw writeback at **their own tracked frontend handle's `wait`** (§7 route 6 / §8.1 single route — an empty drawing flush never completes them); idempotent opaque staging reconciliation; no implicit free | portable | R022 |
| C2D-036 | Ordered/offset axes mapped; non-ordered rejected named | portable | R022 |
| C2D-037 | `vec` column-major declared for **pixel-element** matrices (channel-packed raw `vec` materialized or rejected — it scrambles channels); raw layout never inferred; single logical indexing/conversion table (§7) for import/output/writeback incl. raw positional axes; float/gray conversion | portable | R022 |
| C2D-038 | premul/straight boundary formulas pinned; matte absent by default, required for transparent→opaque; float quantization §7 | portable | R022 |
| C2D-039 | StaticArray immutable in / constructed out; mutable in for writeback | portable | R022 |
| C2D-040 | `snapshot!` two-phase; upload/snapshot validation leaves targets unchanged pre-dispatch; commit failures report `:partial`/`:unwritten` truthfully; adapter-taking output/allocation routes (§13 dispatch order) | portable | R022/R023 |
| C2D-041 | Sub-region effects: later optimization; ops already carry bounded regions | portable | R034 |
| C2D-042 | Processor switch = new concrete canvas; state transfer explicit, pixels never implied | portable | R023 |
| C2D-043 | GPU `copy=false` rejected; upload = explicit `upload_pixels!`/`spec.initial` | portable | R023 |
| C2D-044 | flush/wait/snapshot/close lifecycle; every outstanding submission tracked and waited in order (**completed handles retired** — pending/failed retained, counter kept, successful close clears the owned root); no-op flush never implies earlier completion; §8.1 flush-on-close over every outstanding handle; close frees owned, never borrowed | portable | R021/R041 |
| C2D-045 | WebGL2 orientation top-down, premul colorspace, DPR | native | R053 |
| C2D-046 | WebGL2 readback: each snapshot issues and consumes exactly one fresh request/response after the submitted-work boundary; loss invalidates immediately; stale/future session, wrong scope, superseded generation, unknown id all rejected; timeout named | native | R053 |
| C2D-047 | WebGL2 context loss ⇒ failed submissions, complete-scene recovery from browser-owned payload; destructive resize clears retained document; disposal releases all roots/submissions/request-asset references | native | R053 |
| C2D-048 | WebGL2 allocations bounded; painter order kept | native | R054 |
| C2D-049 | Canvas2D vs WebGL2 selected explicitly; no silent substitution | native | R051/R053 |
| C2D-050 | Browser payload v1: concrete wire records per command/asset/submission/execution-ack/readback-request/response (§11 tags + fields; 1:1 paint-kind mapping; no stroke winding; fractional clear rect), one collision-free asset namespace incl. upload dispatch identity, canonical UTF-8 byte accounting with pre-mutation rejection incl. initial import, version reject, unknown-field ignore, JSON escape rules | native | R050 |
| C2D-051 | PDF page≠batch; `new_page!`/`close!` seal + invalidate; empty/unfinished/repeated close/IO errors named | portable | R061 |
| C2D-052 | PDF document-level strict pre-scan before staged publication; no partial file | portable | R061/R062 |
| C2D-053 | SVG strict matrix over sealed batches; raster fallback documented | portable | R063 |
| C2D-054 | Codec seam: 2-arg decode/encode generics, no sniff-table edits | portable | R060 |
| C2D-055 | Media seam: owned frames, rational timing, record callback shape; metadata details R064-deferred | portable | R064–R068 |
| C2D-056 | Display seam: provider view types, static HTML fallback, portable kernel path | native | R070 |
| C2D-057 | Third-party provider added with zero core edits (R013 gate) | portable | R013 |
| C2D-058 | Storage adapter seam: provider wrapper, descriptor/read/write/alloc, no core-kernel branches | portable | R022/R013 |
| C2D-059 | Bounds/hit/metrics usable headless for GUI/plot hosts; mapping bound §10 | portable | R014 |
| C2D-060 | Physical sizing/resize/DPI: §10 rounding, content-drop rule, clip reset, borrowed resize rejection | portable | R021/R045 |

## 16. Extension sketches (frozen surface, third-party providers)

All sketches are the frozen surface only; provider internals are theirs.
Nothing here edits Vetra source, exports, `weakdeps` or registries.
**The shared-scene and extension sketches below are reviewed API sketches,
explicitly UNIMPLEMENTED at this revision** — they are parse-only contract
evidence, not executed renderers and not fake execution. The same
drawing function driving CPU/Vulkan/Canvas2D/WebGL2/PDF is the acceptance
shape, not a claim that any of those runtimes exist yet; execution
belongs to R020+ and the backend tasks (runtime acceptance is pending,
§19). The small boundary check exercises equivalent provider-owned types
through ordinary-module public dispatch (no eval-generated code); the
sketches remain the third-party surface.

**Render backend** (R013 proves it executable out-of-tree; the boundary
check runs the equivalent provider-owned module through public dispatch —
the sketch itself is parse-only, not executable proof):

```julia
module MyRenderer
import Vetra

struct MySubmission <: Vetra.CanvasSubmission
    batch::Vetra.CommandBatch
end
mutable struct MyBackend <: Vetra.CanvasBackend
    device_token::UInt64
    bound::Bool
end
MyBackend(device_token::UInt64) = MyBackend(device_token, false)

Vetra.backend_capabilities(b::MyBackend) = Vetra.BackendCapabilities(
    1, "myrenderer/gpu", "rgba8-premul",
    Dict("draw.fill" => Vetra.CapabilityStatus(Vetra.NativeCapability, ""),
         "paint.solid" =>
             Vetra.CapabilityStatus(Vetra.NativeCapability, ""),
         "composition.source-over" =>
             Vetra.CapabilityStatus(Vetra.NativeCapability, "")),
    Dict("readback-timeout-ms" => 5000))   # the exact set badge! requires
Vetra.bind_target!(b::MyBackend, spec::Vetra.CanvasTargetSpec) =
    (b.bound = true; Vetra.StorageReport(:owned, :row, false))
Vetra.submit!(b::MyBackend, batch::Vetra.CommandBatch) =
    MySubmission(batch)                            # provider-owned handle
Vetra.wait(s::MySubmission) =
    error("MyRenderer: execution body — outside this contract's scope (R041+)")
Vetra.close(b::MyBackend) = (b.bound = false; nothing)

end # module

using Vetra, MyRenderer

function badge!(c::Vetra.Canvas)                # one drawing function,
    Vetra.fill_rect!(c, 16, 16, 288, 168)       # no target-specific fields
    return c                                     # requires draw.fill +
end                                              # paint.solid +
                                                 # composition.source-over

cpu = Vetra.Canvas(320, 200)                                        # default CPU
gpu = Vetra.Canvas(320, 200; backend = MyRenderer.MyBackend(UInt64(1)))  # third-party
web2d = Vetra.Canvas(320, 200; backend = Browser2D())       # (R050/R051 type)
webgl = Vetra.Canvas(320, 200; backend = BrowserGL2())      # (R053 type)
page = Vetra.new_page!(Vetra.PdfDocument("/tmp/x.pdf"), 320, 200)

badge!(cpu); badge!(gpu); badge!(web2d); badge!(webgl); badge!(page)
Vetra.wait(Vetra.flush!(gpu))      # completion without readback
pixels = Vetra.snapshot(cpu)       # owned host Image, physical size
Vetra.close(gpu)
```

**Pixel storage adapter** (bodies provider-owned; the boundary check
carries the executable equivalent with real dispatch):

```julia
module MyStorage
import Vetra

struct MyAdapter <: Vetra.StorageAdapter
    handle::UInt64
    width::Int
    height::Int
end
Vetra.storage_descriptor(s::MyAdapter) =
    Vetra.StorageDescriptor(Vetra.ColorRGBX,
        Vetra.PixelLayout(s.width, s.height, 4, true, true, true), true, true)
Vetra.storage_read(s::MyAdapter, r::Vetra.Rect) =
    error("MyStorage: provider-owned pixel read — outside this contract's scope")
Vetra.storage_write!(s::MyAdapter, r::Vetra.Rect, data::Vector{UInt8}) =
    error("MyStorage: provider-owned pixel write — outside this contract's scope")
# regions are zero-based physical pixel rects (rect(0,0,1,1) = first
# element); the exchange is owned premul RGBA8 (§13 canonical boundary)
Vetra.storage_alloc(prototype::MyAdapter, ::Type{T},
                    dims::Tuple{Int, Int}) where {T<:Vetra.StorageAdapter} =
    error("MyStorage: provider-owned allocation — outside this contract's scope")

end # module
```

**Image codec** (provider-owned bodies; selection stays public):

```julia
module MyCodec
import Vetra
struct MyFmt end
Vetra.decode_image(data::AbstractVector{UInt8}, ::MyFmt) =
    error("MyCodec: provider-owned decode — outside this contract's scope (R060)")
Vetra.decode_image_dimensions(data::AbstractVector{UInt8}, ::MyFmt) =
    error("MyCodec: provider-owned dimensions — outside this contract's scope (R060)")
Vetra.encode_image(image::Vetra.Image, ::MyFmt) =
    error("MyCodec: provider-owned encode — outside this contract's scope (R060)")
end # module
# selection: Vetra.decode_image(bytes, MyCodec.MyFmt()) — no sniff-table entry
```

**Frame provider** (shape only; R064 owns metadata details and the
provider-owned frame bodies):

```julia
module MyFrames
import Vetra
struct MyReader; end
function Vetra.close!(r::MyReader) end
Base.iterate(r::MyReader, s = nothing) =
    error("MyFrames: provider-owned frame iteration — outside this contract's scope (R064)")
end # module
Vetra.record_frames!(writer, 30, (c, i, t, dt) -> Vetra.fill_rect!(c, 0, 0, 8, 8))
```

**Display adapter** (provider-owned payload bodies; the static-fallback
rule in the prose is the contract):

```julia
module MyDisplay
import Vetra
struct MyView; payload::Dict{String, Any}; end
Base.show(io::IO, ::MIME{"text/html"}, v::MyView) =
    error("MyDisplay: provider-owned HTML payload — outside this contract's scope (R070)")
end # module
```

## 17. Package and compatibility constraints (R040/D037-informed)

| Piece | Constraint (frozen) |
| --- | --- |
| CPU core (this contract, R020/R021/R030…) | Julia ≥ 1.10, stdlib-only (`Libdl`, `LinearAlgebra`); loads and precompiles device-free, codec-free |
| Vulkan companion (R041+) | Isolated package, **higher Julia minimum** (pinned SPIRV source does not load on 1.10 ⇒ companion minimum ≥ 1.11); bounded tested pins from D037: Julia 1.11.9, Vulkan.jl 0.6.30, VulkanCore 1.3.1, SPIRV.jl 0.6.11 @ `218b33b`, SPIRV-Tools 2026.4.0, VVL `vulkan-sdk-1.4.363.1`; executed evidence Linux x86_64 + NVIDIA (3050 Ti laptop, driver 615.71.09) only — other OS/vendor/arch and Vulkan 0.7 remain unverified blockers, not claims |
| Vulkan install | Device-free **only** with precompile preference `false` (the device workload is skipped); `auto` *runs* the device workload and catches missing-driver failure (D037 probe `p50_errors.jl`: `false` ⇒ skipped, `auto` ⇒ run+caught, `true` ⇒ rethrown); explicit device creation; missing driver reports a named error, never hidden CPU fallback |
| Browser companion (R050+) | Isolated; JS runtime + payload only; no device load; WebGL2 shader route = explicit pending policy decision (§11), no compiler support claimed |
| Media companion (R064+) | Isolated; provider pins await R064 runtime probes |
| StaticArrays | Standard optional extension (weakdep pattern); core-only behavior unaffected; immutable in / constructed out (§7) |
| ColorTypes/JpegTurbo/PNGFiles/WebP/XML/HarfBuzz_jll | Existing opt-in providers (D014/D032/D033) unchanged; lazy first-use loading (D028) |

No new Vulkan probe is created by this contract; the table records existing
approved constraints. The RTX 3090 / Linux Chromium / VSCode notebooks
acceptance profile (user, 2026-11-12) is an **evidence target** for R055/R070
on the user's local machine — not a backend minimum; portable notebook
kernel evidence exists (V001, main `39c8f9c`), VS Code UI and 3090 GPU
execution remain unverified.

## 18. Open questions and recommendations (presented, not silently decided)

1. **WebGL2 shader route** — GLSL ES 3.00 is required by WebGL2; no verified
   Julia→GLSL compiler or SPIR-V→GLSL translator exists in the approved
   dependency set. Options: (a) provider-owned GLSL ES 3.00 shader sources
   in `lib/VetraBrowser/`, with the Julia-owned geometry/lowering shared and
   the per-pixel coverage kernel in GLSL, conformance-gated against the CPU
   portable profile — **recommended, explicit proposal for review, not an
   approved policy**; (b) a reviewed external translator — currently
   unverified and blocked; (c) CPU raster + texture upload — forbidden
   (not native scene execution). The coordinator must approve (a) or (b)
   before R053 kernels; the frontend contract does not depend on the choice.
2. **Porter–Duff reference** — the 8 operators beyond source-over/copy use
   the W3C Compositing spec equations as frozen reference (C2D-014); R011
   pins hand-derived expected pixels before R032/R043 compare outputs.
3. **Deliberate legacy divergences** — clip transform capture, `text_baseline`
   saved, clear honors clip, mask-family internal-only, painted strokes and
   tiled fills now valid (new capabilities): all documented in §14.
4. **`draw_image!` artistic blend** — image draws honor the composition
   operator but not an artistic paint mode (the drawn image is a source, not
   a painted fill); matching legacy behavior. Artistic-on-image sampling is
   a tracked extension, not v1.
5. **`SomePaint` export** — R021 exports the existing union as part of the
   frozen canvas surface (§3).

## 19. Defect-scenario register (v1–v9 reviews)

This register keeps **every observed defect scenario** from the revision-1
through revision-8 reviews visible, mapped to its required (revision-9)
behavior, the normative clause that now carries it, and the downstream
task that must implement and be conformance-tested for it. **A scenario
is closed only when its owner task lands and passes R011/R013-independent
conformance — never by deleting a mock.** The small boundary check
(`tasks/r010/boundary_check.jl`) executes only the *normative
arithmetic/record/dispatch* cells marked **✓ executed** (arithmetic,
records and dispatch traces only — never runtime proof); all other cells
are contract-level traces whose runtime acceptance is **pending** the
owner task. Evidence levels are distinguished in
`tasks/r010/R010-freeze-frontend-backend-contract.md`.

Legend: ✓ = executable in the small boundary check (arithmetic/record/
dispatch only); ⏳ = normative contract now fixed, runtime acceptance
pending the named owner; all rows are visible, none removed.

### G1 — Submission tracking and synchronization (clause §8/§8.1)

| Scenario (input → action) | Required v9 result | Clause | Owner |
| --- | --- | --- | --- |
| deferred `submit!` (GPU) → `wait(c)` | `wait(c)` returns only after **every** tracked submission completes, not just the latest | §8.1 | ⏳ R021 |
| explicit `flush!` → `snapshot(c)` | snapshot waits the outstanding submission first | §8.1 | ⏳ R021/R023 |
| 16 × `submit → wait(flush!(c))` (direct waits) | **every** completed handle is retired at its **direct** `wait(handle)` — the single completion route (forward provider wait, staged completion once, core entry removed, `:inflight` refs released at the §6 release point, **provider batch roots released at provider completion**); the core tracking root does not grow with frame history (sixteen direct waits leave zero core entries and **zero reachable provider batch roots** — checked by the actual references, including an externally kept completed handle, not by a release flag) | §8.1 (revision 9) | ✓ tracker record (reference-checked) / ⏳ R021 |
| `wait(c)` after outstanding work | flush pending, then wait every outstanding tracked entry **through the same single completion route** as direct `wait(handle)` | §8.1 (revision 9) | ✓ tracker record / ⏳ R021 |
| two `flush!` → `close(c)` | every not-yet-complete batch waited in order before provider close (a completed handle was already waited in order before its retirement) | §8.1 | ⏳ R021 |
| failed handle + new draw + `close` | failed entry retained (**sticky** — re-raised by direct wait and by `wait(c)`); close re-raises it; no re-submit; a **provider**-failed handle keeps its batch (the provider's work did not complete), a **staged**-failed handle does not (the provider work already completed and released its roots) | §8.1 (revision 9) | ✓ tracker record / ⏳ R021 |
| staged failure (`:partial` / `:unwritten` / action error / phase-1 validation) → repeated `wait` / `wait(c)` / `close` | the **original named error is preserved by identity** and **sticky** on the tracked handle (the `TransferError` keeps its `:partial`/`:unwritten` status; the §7 phase-1 named validation error — e.g. `ArgumentError` — raised before any store is preserved likewise; the revision-8 restricted union is retracted — it stranded `:failed` with no error, later waits threw `nothing`); the stored-error domain is one sufficient `Any`-typed field, not a growing union; the staged action is **never re-run automatically** (success flag set only after success); the entry is never completed or retired; the core staging is retained by the failed entry; the already-released provider roots are NOT retained; `close` re-raises and stays open | §8.1 (revision 9) / §7 commit rule | ✓ tracker record (all four failure pins) / ⏳ R022 |
| zero-op `flush!` | core `CanvasNoopSubmission` handle; no backend call; **inert** `wait` (no state transition, no staged action); does **not** complete earlier work | §8/§8.1 (revision 7) | ✓ tracker record |
| successful `close` | clears the owned tracking root entirely (every completed entry already retired by the single route; the counter is retained, not the handles; a provider-failed entry retains provider resources, a staged-failed entry retains only the core staging) | §8.1 (revision 9) | ✓ tracker record / ⏳ R021 |

### G2 — Group entry alpha (clause §5.5)

| Scenario | Required v9 result | Clause | Owner |
| --- | --- | --- | --- |
| `global_alpha 0.5 → save_layer! → fill! (opaque) → restore!` | `GroupStartOp.opacity = 0.5`, child opacity `1.0`, **net group alpha 0.5** (never 0.25) | §5.5 | ⏳ R032 |
| `set_composition!(Xor)` unsupported → `save_layer!` | raises `BackendCapabilityError` **before** any state mutation | §5.5/§9 | ⏳ R021 |
| image paint without image → `save!` | raises `ArgumentError` before snapshot push; no partial group | §5.5/§9 | ⏳ R021 |
| alpha/composition change inside group | affects child ops only; restore returns parent alpha+composition | §5.5 | ⏳ R032 |
| nested groups | each frozen factor applied exactly once at its own `GroupEndOp` | §5.5 | ⏳ R032 |

### G3 — Non-separable artistic pipeline (clause §5.7)

| Scenario | Required v9 result | Clause | Owner |
| --- | --- | --- | --- |
| hue/saturation/color/luminosity through `composite` | B applied to **RGB vectors** (spec §10.2), alpha via the Porter–Duff row; executes on asymmetric color/alpha inputs | §5.7 | ✓ math |
| hue of orange over mid-gray | `(51,51,51,255)` | §5.7 anchor | ✓ math |
| color of orange over mid-gray | `(86,43,0,255)` | §5.7 anchor | ✓ math |
| color of red over blue / luminosity of red over blue | `(94,0,0,255)` / `(54,54,255,255)` | §5.7 anchors | ✓ math |
| saturation of yellow over mid-gray | `(128,128,128,255)` (pure-gray backdrop unchanged) | §5.7 anchor | ✓ math |

### G4 — Fallback retains original work (clause §6/§9)

| Scenario | Required v9 result | Clause | Owner |
| --- | --- | --- | --- |
| `:report` op fallback | marker retains `original.ops`/`original.assets` (owned path/paint/dest); provider computes replacement from them; no zero-filled placeholder | §6 | ⏳ R020 |
| `:report` group fallback | state stack + group balance kept; matching `restore!` succeeds; `original` = full span | §6/§9 | ⏳ R020/R032 |
| destination-dependent feature | falls back to `:frame` or proven isolated `:group`, never isolated `:op` | §9 | ⏳ R020 |
| `:strict` | named `BackendCapabilityError`, no marker | §9 | ⏳ R021 |

### G5 — Recording boundary, legacy adapter, placement (clause §14)

| Scenario | Required v9 result | Clause | Owner |
| --- | --- | --- | --- |
| new Canvas content (Xor group, effect, dash phase, sampled image, fractional clear) | **losslessly** recorded/replayed inside the Canvas world through the owned `CanvasRecording` — `record_canvas` capture + `draw_recording!` replay (revision 7); every `CanvasOp` field captured (§6); wire records 1:1. The revision-5 "`flush!` + `batch_*` accessors" capture is **retracted** — `flush!` returns the tracked frontend handle (no public accessor back to a batch), and `submit!` is the provider protocol, not a frontend replay route. **Normative replay trace — runtime acceptance pending** (⏳ R020); the executed evidence is the narrow seal/remap/placement-arithmetics rows below, not multi-op replay | §14 (lossless boundary) | ⏳ R020/R050 |
| `record_canvas` capture | **record-only route**: no backend bound, no device execution (no `submit!`), no pixel read (record-only `SnapshotError` — runtime, ⏳ R020); seal: group balance (named `ArgumentError("unbalanced save_layer at record")`), the **seal ownership boundary** (§14 revision 7 — ops arrive already owned per §6; the seal owns its op container and deep-copies only the referenced asset bytes; asset-byte mutation inert, container mutation inert), uncaptured asset references rejected (draw **and** image/tiled paint id classes), extent = the callback's ops, **not** the canvas history | §14 (revision 7) | ✓ record (seal machine) / ⏳ R020 (record-only runtime) |
| `draw_recording!` replay | assets re-captured into the target store with fresh target-scoped ids — **the one 1:1 remap over both reference classes** (`DrawImageOp.assetId` and `OwnedPaint.imageAssetId`; recording ids never the target's); ops preflighted as a union under the target's capabilities (named `BackendCapabilityError` before any op recorded — runtime, ⏳ R020); placement per §14; **target ambient clip combination** (§14 revision 7 — target ambient list unchanged + recorded clips mapped under `ambient * mapping` exactly once; a target clip must not disappear); replayed ops enter `pending_ops` for the target's next `submit!` (runtime, ⏳ R020) | §14/§9 | ✓ record (remap + placement/clip arithmetics under the actual `Mat3`) / ⏳ R020 (multi-op replay execution, preflight, clip-list combination) |
| `canvas_picture(r)` on the convertible subset | actual Vetra `Picture(ops, size)` from the **explicit recording**; image payload deep-copied and owned; text lowered to glyph outlines; the §14 revision-9 wrapper emission (root implicit clip group; opacity baked into `Paint.opacity`; explicit `GroupStart(opacity)`/`GroupEnd(clips)`); `Copy` admitted at effective opacity ≠ 0 with **no implicit clip wrapper** — unclipped at root **or inside an explicit group** (`L == E`; `GroupStart.opacity` carries the group factor 1:1); source-over **artistic** admitted when **unwrapped** — unclipped at root or inside an explicit group with `L == E` (the legacy `Paint` carries the blendMode; the true backdrop is intact — reproduced: Multiply over blue ⇒ black; the wrapped artistic case stays rejected by the earlier row) | §14 (adapter) | ⏳ R020 |
| `canvas_picture(r)` on non-representable ops | the **disjoint conservative decision procedure** (§14 revision 9 — first match wins; the revision-8 final accept row that required non-artistic — leaving the unwrapped artistic draw without an accept row — is retracted, the preceding wrapped-artistic rejection governs): group composition ≠ source-over; effect; clipped clear; draw-image composition/sampling/fractional-srcRect; tiled fill; non-solid stroke; dash phase; fill/stroke composition ∉ {source-over, Copy}; Copy + artistic paint; **zero-opacity Copy** (the legacy fill/stroke pipeline early-returns on zero `Paint.opacity` — an opaque-red Copy at opacity 0 over opaque blue **leaves blue** on the actual recorder where Canvas Copy must clear; the revision-7 transparent-color @ unit-opacity control is a different route and does clear — both reproduced in the boundary check); **Copy under the implicit clip wrapper** (a clipped transparent Copy replayed over opaque blue leaves blue on the **actual** legacy recorder, where Canvas Copy must clear — reproduced in the boundary check); **source-over artistic under the implicit clip wrapper** (clipped red Multiply over opaque blue yields red on the actual recorder, required black — reproduced; the unclipped direct draws are the preserving controls — reproduced); clip set inside a group; child clip differing from the group entry list — named `ArgumentError` (op index + missing legacy dimension). The revision-6 overlapping rows, the revision-7 zero-opacity `Copy` acceptance, and the revision-7 accept rows that covered only top-level `Copy` / only unclipped root source-over are retracted. Every rejection is a **legacy-conversion limit only** — `draw_recording!` still replays all of them losslessly | §14 (adapter, revision 9) | ✓ record (decision procedure) + ✓ math (actual-recorder 1×1 reproductions) / ⏳ R020 (adapter implementation + conformance) |
| replay into fresh canvas | image re-captured into target asset store with fresh target-scoped id (both reference classes, one remap) | §14/§6 | ⏳ R020 |
| `draw_picture!(c, pic, dest(10,20,4,6))` of a 2×2 pic | `mapping = translate(10,20) * scale(2,3)` — origin → **(10,20)**, corner → (14,26); per-op `ambient * mapping * op.tform`; recorded clip geometry under `ambient * mapping` **exactly once** (single-mapping control executed); image geometry scaled **exactly once**; the v4 order `scale * translate` (origin → (20,60)) is retracted | §14 (placement) | ✓ transform (actual `Mat3`) / ⏳ R020 |

### G6 — Bounded asset lifetime (clause §6)

| Scenario | Required v9 result | Clause | Owner |
| --- | --- | --- | --- |
| 10 completed draws of one pixel | retained capture bytes bounded by live owners; **0 after close** | §6 | ⏳ R020/R021 |
| `restore!` after `flush!` | `:saved` owner keeps the capture alive across flushes (pre-flush bytes materialize) | §6 | ⏳ R021 |
| draw/mutate/draw in one batch | two distinct ids with distinct owned content (fresh-id rule kept) | §6 | ⏳ R020 |

### G7 — Scope/proof reduction (clause: this revision)

| Scenario | Required v9 result | Clause | Owner |
| --- | --- | --- | --- |
| 4,660-line parallel frontend | **retired (deleted)**: no Canvas/drawing/text/hit-test/effects/replay/fallback-exec/browser-runtime/array-engine/PDF-publication/eval-provider | header + §19 | R010 (done here) |
| boundary proof | small `boundary_check.jl` importing actual Vetra primitives; ordinary modules only; **no recreated engines** | §19 | ✓ executed |
| shared-scene + extension sketches | reviewed API sketches, **explicitly unimplemented**, parse-only; internally coherent (qualified types, declared argument types, exact advertised features) | §16 | R020+/owner tasks |
| retired mock failures | not runtime fixes; each G1–G15 scenario stays open against its owner | §19 | ⏳ owners |

### G8 — Compositing/array anchors (clause §5.7/§7) — executable

| Scenario | Required v9 result | Clause | Owner |
| --- | --- | --- | --- |
| half-covered opaque red, source-over transparent | `(128,0,0,128)` (coverage scales αs only) | §5.7 | ✓ math |
| Atop of (1,0,0,0.25) over (0,0,1,0.75) | `(16,0,48,64)` (αo=αs) | §5.7 | ✓ math |
| Lighter of same pair (Normal paint) | `(64,0,191,255)` (premul add of the blended source — Normal paint: Cr = Cs — min(1,αs+αb)) | §5.7 | ✓ math |
| Screen under Lighter, both straight 0.4/α 0.5 | `(117,117,117,255)` (B=0.64 → Cr=0.52 → co=0.46; the v4 raw unblended sum gave 102) | §5.7 anchor | ✓ math |
| color-burn endpoints | `B(0.5,0)=0`, `B(1,0)=1` (backdrop exception first); opaque black burned over half-gray ⇒ `(0,0,0,255)` (the v4 checker returned 128) | §5.7 anchor | ✓ math |
| color-dodge endpoints | `B(0.5,1)=1`, `B(0,1)=0` (backdrop exception first); opaque white dodged over half-gray ⇒ `(255,255,255,255)` (the v4 checker returned 128) | §5.7 anchor | ✓ math |
| hue of red α128 over blue α128, source-over | `(87,0,64,192)` from the exact-rational derivation (`B = (11/30,0,0)`; `co = (a((1−a)+a·11/30), 0, a(1−a))`, `a = 128/255`; ties-away) — kernel bytes are a cross-check, not the oracle | §5.7 anchor | ✓ math |
| `rgbx(rgba(255,128,128,128))` | `ColorRGBX(128,64,64,128)` | §7 | ✓ math (actual kernel) |
| quantization `0.5→128`, `1/3→85` | `RoundNearestTiesAway` | §5.7/§7 | ✓ math |
| matte over white | `(255,127,127)` | §7 | ✓ math |
| half-red `(128,0,0,128)` → gray over white matte | composite first, then luma ⇒ `154` (the v4 branch computed luma of the un-composited premul ⇒ 27); **no matte ⇒ rejected before any write** | §7 gray rule | ✓ conversion |
| opaque-boundary kernel cross-check | byte-exact vs pinned `blend*` kernels | §5.7 | ✓ math (actual kernels) |

### G9 — Browser fresh-response readback (clause §11)

| Scenario | Required v9 result | Clause | Owner |
| --- | --- | --- | --- |
| stale ACK after context loss | rejected; loss invalidates **all** pending requests immediately | §11 | ⏳ R053 |
| N snapshots | N fresh requests issued+consumed after the submitted-work boundary; each response consumed exactly once | §11 | ⏳ R053 |
| response vs **saved request** | `id`/`scope`/`session`/`generation`/`submission` (the count saved at issue — not the current one)/`encoding` must all echo the saved request, and the live identity must still match; **plus** `width`/`height` = saved rect dims and decoded `data` length = `4·w·h`; any mismatch rejected **before consumption** — an invalid response cannot silently consume authorization | §11 | ✓ record |
| unmatched later response | authorizes nothing; named `ArgumentError` | §11 | ✓ record |
| submission completion | only a matching execution response completes a readback; timeout/rejection retain ownership; readback responses are **not** execution ACKs | §11 | ⏳ R053 |

### G10 — Browser namespace, canonical bytes, submissions, resize, cleanup (clause §11)

| Scenario | Required v9 result | Clause | Owner |
| --- | --- | --- | --- |
| draw red then upload blue | one monotonic, collision-free id namespace (draw/initial/upload); earlier capture not overwritten; **the older pending drawing is submitted before the upload dispatch** (provider order preserved), the canvas-level `upload_pixels!` returns the upload's **tracked frontend completion handle** (frozen, revision 7) tracked like any accepted submission, and upload-only work is admitted + submission + ACKed even when the next drawing flush is empty; assets are keyed by the **captured** id (the document machine never invents ids — deliberately non-consecutive ids, the separate next-capture counter with the already-reserved-ID convention, and resize-monotonic namespace — incl. **resize with an already-captured initial: the captured id is preserved, never substituted** — all checked) | §7/§11 (revision 7) | ✓ record |
| upload dispatch identity | `upload_pixels!(backend, asset::CanvasAsset, region)` carries the captured asset id to the provider and to the wire `set-pixels.assetId` (the v4 `(region, bytes)` dispatch cannot discover an intervening upload's id) | §7/§8/§11 | ✓ record |
| execution-ack identity | per-submission `submission` record (id/scope/session/generation + delta commands/assets) and exactly one `execution-ack` (id echo + identity + `status`/`detail`); success → `complete`, error → sticky `failed`; unknown/stale acks rejected before consumption | §11 | ✓ record |
| byte bound | admission = the **actual canonical UTF-8 serialization length** (base64 + escaping + every field + envelope), measured before mutation; pinned: 64×64 initial document = 22187 bytes (base64 data alone 21848) > a 17000 limit ⇒ rejected at construction (the retracted v4 formula counted 16816); 100-quote string ⇒ 202 bytes; `typemax(Int)` ⇒ 19 digits; `floatmax(Float32)` ⇒ `3.4028235e38`; **`Float32`-declared fields serialize as `Float32` shortest decimal — no widening** (a `0.1f0` clear corner ⇒ `0.1`, not the widened `0.10000000149011612`) | §11 (revision 6) | ✓ accounting (pinned fixtures) |
| initial import | subject to the bound **at construction** (first `set-pixels`) | §11 | ✓ accounting |
| `resize!` | destructive: clears retained document (commands/uploads/assets), bumps generation | §10/§11 | ⏳ R053 |
| `close`/disposal | releases scope root, document, submissions, request/asset references | §11 | ⏳ R053 |

### G11 — Layout scan, axes, straight/premul, float/gray (clause §7)

| Scenario | Required v9 result | Clause | Owner |
| --- | --- | --- | --- |
| column-major declared vector | scans in declared column order (not vector order) | §7 table | ✓ conversion |
| ordered offset axes | map by position (**element and raw routes** — matrix positions translated through `axes(M)`, so **zero-based raw matrices import in both declared scan orientations**; index-array/non-ordered rejected named (element **vectors** included — the v4 checker accepted an index-array vector view; raw index-array views likewise)) | §7 table (revision 7) | ✓ conversion |
| dest shape `(height,width)` for `Canvas(w,h)` | accepted and validated; wrong shape raises **before any write** | §7 table | ✓ conversion |
| straight-declared dest | receives straight bytes (premul→straight), never premul; allocating raw output follows the **declared** layout convention | §7 table | ✓ conversion |
| column-major raw output | scans column-major (table shape) | §7 table | ✓ conversion |
| float/gray dest | `0..1` float de-quantized; gray via composite-then-luma (see G8 row) | §7 table | ✓ conversion |
| `vec(matrix)` | **pixel-element matrices only**: declared `row_major = false`; the byte buffer is **never** reinterpreted as row-major. Channel-packed raw matrices are **excluded** — `vec` flattens rows inside each channel column (2×12 RGBA, first pixel `[1,0,0,255]` ⇒ flat `[1,4,0,0]`): raw flattening must materialize the declared pixel/channel order or be rejected as incompatible; `:direct` only if the actual memory honors the mapping, otherwise `:staged` | §7 table (revision 6) | ✓ record |
| borrowed ordinary Julia matrix | storage order reported **truthfully `:col`** (raw forms: declared scan positional; actual memory order reported); a row-major-declared ordinary raw matrix is column-major memory ⇒ `:staged`, never `:direct` | §2/§7 table | ✓ record |

### G12 — Upload validation, staged completion, idempotent matte, commit (clause §7)

| Scenario | Required v9 result | Clause | Owner |
| --- | --- | --- | --- |
| source/region mismatch | raises **before provider dispatch**; target unchanged (no partial write) | §7 pre-dispatch | ✓ validation |
| staged upload → `wait(upload's tracked frontend handle)` | host borrow written back **exactly once** — the staged writeback is the upload's core staged completion at the upload's own completion (§7 route 6 / §8.1 single route); **negative control**: a zero-op drawing flush between dispatch and wait is the inert core no-op and leaves the upload pending (does not write back); **failure**: a staged failure keeps the upload FAILED on its own handle — the original named error (the `TransferError` `:partial`/`:unwritten`, or the phase-1 named validation error raised before any store) is preserved by identity and sticky, the writeback is never re-run automatically, `close` re-raises, and only the core staging is retained (the provider roots were released at provider completion) | §7/§8.1 (revision 9) | ✓ record (single route, both wait forms, failure pins) / ⏳ R022 (writeback runtime) |
| raw `UInt8` view writeback | receives `0..255` bytes (eltype-driven, not normalized 1.0) | §7 | ✓ conversion |
| repeated half-transparent writeback over opaque borrow | idempotent: red `128` stays `128` (staging reconciled on success) | §7 staging rule | ✓ reconciliation |
| commit failure | **pre-commit validation ⇒ destination unchanged** (named error); **commit-phase failure ⇒ `TransferError(:partial)`** unless the destination explicitly guarantees atomic commit (`:unwritten` + rollback); indexed writeback is not a transaction even from owned, fully-validated staging (the v4 "all-or-nothing where the adapter guarantees it" phrasing is retracted); staging retained for retry | §7 commit rule | ✓ record / ⏳ R022 |

### G13 — External output/allocation consumer (clause §13)

| Scenario | Required v9 result | Clause | Owner |
| --- | --- | --- | --- |
| `snapshot!(s::StorageAdapter, c)` | normative consumer trace: descriptor → validation (`writable`, physical dims; failure ⇒ **zero** read/write/alloc calls) → flush+wait → `read_pixels` → owned premul RGBA8 for the zero-based physical region → `storage_write!`; the adapter owns the conversion to its underlying layout | §13 | ✓ consumer trace (record machine) |
| `snapshot_alloc(s, c)` | descriptor → flush+wait → `read_pixels` → `storage_alloc(s, typeof(s), (pw, ph))` (explicit type **and** dimensions — a descriptor cannot infer the container shape) → fill the returned adapter through its public descriptor/write dispatch → return it | §13 | ✓ consumer trace (record machine) |
| direct provider-method calls | prove the provider surface (zero-based region addressing, premul exchange, explicit alloc) — **not** consumer dispatch order | §13 | ✓ surface |
| out-of-tree owned wrapper | traced through the actual public consumers (sketch §16) | §13/§16 | ⏳ R013/R022 |

### G14 — Physical sizing across all constructors (clause §4/§10)

| Scenario | Required v9 result | Clause | Owner |
| --- | --- | --- | --- |
| raw 4×2 RGBA @ scale 2 | logical 2×1 derived, physical 4×2, initial **32 bytes accepted**; a **16-byte** initial for the same target rejected (the v4 register pinned the wrong count) | §4 rule 1 | ✓ invariant |
| adapter 4×2 @ scale 2 | same invariant via descriptor | §13/§4 | ✓ invariant |
| element 5×3 @ 1.5 | rejected before binding (non-integral logical) | §4 rule 1 | ✓ invariant |
| 1×1 @ 2 | rejected (fractional logical) | §4 rule 1 | ✓ invariant |
| physical rounding precision | **promotion before multiplication**: `Float64(w) * Float64(scale)` — logical 3 at `Float32(7/6)` ⇒ physical 3 (the rejected literal Float32 multiply ties ⇒ 4); `resize!(c, w, h; device_scale = nothing)` (an optional-compatible keyword, not `device_scale::Float32 = nothing`) | §10 | ✓ invariant |
| inverse DPI, physical 6 @ `0.6f0` | **widening both operands before the division**: `Float64(6) / Float64(0.6f0) = 9.999999602635718` — non-integral ⇒ **rejected** before binding; the literal-Float32 control `6 / 0.6f0 = 10.0` round-trips to physical 6 (the false acceptance the widened rule exists to catch); `physical_extents(10, 10, 0.6f0) == (6, 6)` confirms the round-trip side | §4 rule 1 (revision 7) | ✓ math |

### G15 — Full wire records (clause §11)

| Scenario | Required v9 result | Clause | Owner |
| --- | --- | --- | --- |
| every command record | fixed `"op"` tag + complete field set — `stroke` carries **no winding** (StrokeOp has none; fixed nonzero — the v4 record invented a field); `clear` rect stays **fractional** (no Int truncation); `image` **srcRect fractional** (the captured Rect as-is — truncation is the legacy 8-arg overload only) / destRect fractional; **effect in/out regions fractional** (no Int conversion); **`Float32`-declared fields serialize as `Float32` shortest decimal (no Float64 widening)**; `set-pixels.assetId` = captured core id | §11 (revision 6) | ✓ record schema |
| paint mapping | 1:1 `PaintKind` → wire kind (`linear-gradient` never maps to `tiled-image`; gradients carry `handles`/`stops`, image/tiled carry `assetId`) | §11 | ✓ record |
| text record | accounted by the actual serialization (variable glyph outlines — the v4 `64 + 32/glyph` constant is retracted with the whole formula) | §11 | ✓ record |
| asset + transport records | frozen with identity fields (one namespace; submission/execution-ack; request/response echo the **saved** request + payload checks) | §11 | ✓ record schema |
| canonical fixtures | hand-derived pinned literals: the 2×2 initial document (exact bytes, 357), the fractional clear record (102), the rect-fill record (325), the `0.1f0` clear record (100 — Float32 preserved); base64/escape/integer-width lengths (21848/202/19/12) | §11 (revision 6) | ✓ accounting |
| independent Julia+JS writers | serialize from the records alone; no private model internals needed | §11 | ⏳ R050 |
| numeric/escaping | shortest-decimal `Float32` rule + JSON escaping (canonical serialization) + separate `</script>` HTML boundary | §11 | ✓ record / ⏳ R050 |
