# Canvas and rendering backends

Status: **approved implementation plan (R000)**, requested 2026-11-10.
Independent architectural/task-plan review: **approved** after corrections 1–10
(2026-11-10, 43 tasks). Source review and final media-amendment review are complete.
R010's executable interface freeze remains pending; approval is not provider/runtime evidence.
The interfaces below are design contracts, not claims that new backends exist.
Implementation and review gates are in [the development plan](../tasks/CANVAS_ROADMAP.md).
Independently checked source findings and unresolved toolchain constraints are
in [the research record](CANVAS_RESEARCH.md); source inspection is not runtime proof.

## 1. Product goal

Write a drawing function once and use it for a CPU bitmap, a Vulkan render
target, an HTML canvas, a notebook output, or a PDF page. Keep 2D geometry,
layout, state, and image manipulation independent of the destination.

Design Vetra as an embeddable graphics core for future GUI frameworks and plotting
libraries. Their integration must use the same public extension/drawing contracts
as standalone clients; no framework-specific fork or mandatory window/event loop.

First-tier destinations:

| Destination | Execution / representation | Required integration |
| --- | --- | --- |
| CPU image | Existing native Julia raster kernels | Headless rendering, editing, deterministic regression profile |
| Julia arrays | Pixel storage independent of execution | Import, draw into mutable Matrix/Vector storage, export into host arrays and StaticArrays |
| Native GPU | **Vulkan.jl** | Offscreen rendering first; optional window/swapchain presentation later in this milestone |
| Browser | Browser Canvas 2D APIs | Main-thread canvas; capability-tested OffscreenCanvas/worker path |
| Image files | A codec encodes a raster result | PNG, JPEG, WebP, BMP, QOI, PPM; preserve GIF decoding |
| Animation / video | Streaming temporal media pipeline | Decode, edit, encode, record and concatenate GIF/WebP animations and MP4 video frames |
| SVG | Vector document plus embedded raster assets | Adapt the existing writer and reader; explicit vector limitations |
| PDF | Document/page backend | Vector paths, images, text, multipage lifecycle, explicit raster fallback |
| Jupyter | A display/interaction adapter | IJulia execution, MIME fallbacks, optional live browser view |

An image file format is **not another renderer**. PNG and JPEG share the same
rendered pixels and differ at encoding. A notebook is **not another rasterizer**:
it displays a CPU/GPU snapshot, vector document, or browser view. These
distinctions avoid duplicating the drawing engine for every output combination.

“First-tier” means owned implementation, documentation, capability tests, and
release evidence. It does not imply that every driver, browser, file format,
or optional provider supports every operation natively.

### Format and delivery matrix

`Current` describes the existing codecs/writers. `Planned` names new Canvas
integration; new sequence encoders are explicitly planned below. Canonical image assets feed GPU
upload, browser transport and PDF embedding after decoding, rather than requiring
each backend to parse the source file independently.

| Format | Current read | Current write | Animation / representation | Planned Canvas delivery |
| --- | --- | --- | --- | --- |
| PNG | Yes, opt-in PNGFiles | Yes, opt-in PNGFiles | Static raster | CPU asset → GPU upload / browser payload / PDF image; snapshot encoder; PNG notebook fallback |
| JPEG | Yes, opt-in JpegTurbo | Yes, opt-in JpegTurbo | Static, no alpha; explicit encode background | Same canonical asset destinations; lossy snapshot encoder |
| WebP | Yes, opt-in WebP | Yes, opt-in WebP | Existing static APIs reject animation | Static assets plus new composited animation reader and animation encoder (R065/R066) |
| BMP/DIB | BMP and DIB decode | BMP encode | Static raster | Same asset destinations; BMP snapshot encoder |
| QOI | Yes | Yes | Static raster | Same asset destinations; QOI snapshot encoder |
| PPM | P3/P6 decode | P6 encode | Static raster | Same asset destinations; PPM snapshot encoder |
| GIF | Yes | No | Existing decoder retained | Composited editable frame sequences and new GIF encoder (R065/R066) |
| MP4 | No | No | Video container; codec/profile selected separately | New frame reader/writer, editing, recording and concatenation (R065/R067/R068) |
| SVG | Documented subset, opt-in XML | Recorded vector subset with explicit fallback | Vector document, not a general SVG/CSS browser | Common vector commands or explicit rasterization; vector export/display |
| PDF | No PDF import | Recorded single-page subset with explicit fallback | Vector/raster document | Page backend, multipage/vector export; notebook link/vector display where supported |

Notebook MIME and browser image decoders need not recognize BMP/QOI/PPM directly:
the display adapter can use a canonical payload or PNG. Raster codec encoding
does not retain vector editability. R060 owns codec capability checks; R063 owns
SVG and R061/R062 own PDF. R064–R069 own temporal media. R022/R023 own host
array storage and CPU/GPU transfers. R090 verifies their end-to-end integration.

## 2. Starting point and reuse

The current library already has a CPU renderer, paths, paints, compositing,
clipping/layers, effects, TTF text and optional shaping, codecs, recordings,
and SVG/PDF writers. Relevant implementation:

- `src/context.jl`: immediate CPU drawing and state.
- `src/recordings.jl`: `Picture`, snapshot operations, CPU replay.
- `src/rasterizer.jl`, `src/strokes.jl`, `src/paints.jl`, `src/image_ops.jl`:
  reusable CPU geometry and pixel algorithms.
- `src/formats/svg_write.jl`, `src/formats/pdf_write.jl`: existing exporters.
- `src/formats/fonts.jl`, `paragraph.jl`, `shaping.jl`: layout and glyph outlines.
- `src/formats/` and `src/colormatrices.jl`: codec / alpha / matrix boundaries.

Do not replace proven kernels with a new engine before the adapter is correct.
Do not independently reimplement the drawing-state machine in each backend.
The existing recording structs are a starting point, not a frozen GPU wire
format: they contain CPU Images, mutable containers, duplicated Context state,
and historical clipping/clear behavior. Translate or migrate them deliberately.

M002 already verified CPU tests and benchmark smoke on Linux, Windows, macOS,
and FreeBSD ([CI evidence](https://github.com/skynet-core/Vetra.jl/actions/runs/42811680553)).
That result is **not GPU or browser validation**. The M003 Julia-native API
work remains additive preparation; the known correctness/lifetime fixes from
M004 are prerequisites for the new engine's release.

## 3. Architecture

```text
User drawing function / reusable Picture
                 |
    Canvas: validated 2D state, paths, layout
                 |
     backend-neutral commands + owned assets
                 |
     capability preflight / explicit fallback
          /          |          |         \
       CPU        Vulkan     Browser     PDF/SVG
        |            |          |           |
       Image    device image   Canvas     document
          \       /              \         /
       explicit snapshot       display / export
               |
       arrays / codecs / frame writers / notebook MIME
```

### 3.1 Canvas is the frontend

Use a concrete parametric `Canvas{B<:AbstractBackend}`. Its common state and
methods do not access `Image.data`, Vulkan handles, browser DOM nodes, or PDF
objects. It holds a backend value of concrete type `B`; Julia multiple dispatch
selects execution. No central `if backend == :gpu` switch and no plugin registry.

All Canvas implementations share:

- Logical dimensions, device scale, drawing state, and validation.
- Path construction, transform composition, stroke style and dash validation.
- Paint descriptors, clipping scopes, isolated layers and compositing semantics.
- Text layout and glyph positioning when using portable outline text.
- Command ordering, asset snapshots, fallback policy and diagnostics.

Pixel kernels and backend command submission sit behind function barriers.
Backend selection occurs per operation/batch, never per pixel. Do not use an
abstractly typed backend field, `Any`-typed resource dictionaries in hot loops,
or large generated combinations of backend/style/format types without evidence.

### 3.2 Backend owns execution and the target

Backend instances own or borrow an explicitly documented target:

- CPU: an Image or validated mutable array target, with explicit copy/borrow rules.
- Vulkan: device/queue context and device-local images, with explicit ownership.
- Browser: a transport/session or an offline browser-view document.
- PDF/SVG: an in-memory document/page builder and eventual IO destination.

The minimal **public extension protocol** is versioned and documented separately
from private implementation details. It has a required execution/lifecycle core
and optional capabilities; it is not a base class requiring every method below:

| Operation | Contract |
| --- | --- |
| `backend_capabilities(backend)` | Concrete feature/limit report, including device-dependent limits |
| `submit!(backend, sealed_commands)` | Ordered execution; returns a submission handle retaining required resources |
| `wait(submission)` | Completion/error boundary; immediate for synchronous CPU/document work |
| `read_pixels(backend, region)` | Optional raster capability; synchronized, returns owned host pixels |
| `present!(backend)` | Optional display capability; not required for offscreen or document targets |
| `close(backend)` | Wait for its owned in-flight submissions, then release owned resources; bounded failure/timeout is reported without freeing in-flight resources; never destroys borrowed objects |

There is no mandatory `read_pixels` or `present!` implementation for a PDF page.
Unsupported operations return a named capability error, not a dummy image.
Protocol tests use a test-only spy backend; no public placeholder backend ships.
External backends consume documented sealed-command/asset accessors, not private
field layouts. Core owns shared Canvas validation/preflight; a provider validates
its device/format constraints and implements only its advertised capabilities.

### 3.3 Submission and observable behavior

Canvas may buffer commands. `flush!(canvas)` seals/submits pending commands;
`wait(flush!(canvas))` is the explicit completion boundary. `snapshot(canvas)`
flushes and waits before returning an owned CPU Image. No operation quietly
reads a GPU target back to the CPU merely to inspect pixels or implement a
performance-critical draw. Readback and presentation costs are measured.

Snapshot means a CPU copy for CPU targets, synchronized device readback for
Vulkan, and an acknowledged asynchronous readback for a connected browser
(with timeout/error propagation). An offline browser view has no Julia readback
channel; PDF/SVG targets return a capability error unless the caller explicitly
requests CPU rasterization of a retained recording.

State persists between batches. Save/restore state scopes may persist, but
isolated layer groups must be balanced before a batch is sealed. Invalid state
or unsupported operations fail preflight before changing the destination.
Device loss or an execution/IO failure after submission can leave a partial
target; report that honestly and invalidate affected resources. Do not promise
transactional GPU frames. File exports stage output and publish only on success.

`close(canvas)` rejects new work, waits for its owned submissions and releases
resources only after completion. A timeout retains ownership for retry/deferred
cleanup and reports the failure. It must not destroy a shared/borrowed device
or wait for unrelated users' submissions. Device-loss cleanup follows Vulkan's
documented rules and reports whether the target remains usable.

Explicit close is primary. Finalizers only arrange nonblocking deferred cleanup;
they neither wait on queues nor destroy resources whose completion is unknown.
The deferred owner retains native handles and their parent device until safe
destruction. A failed cleanup is reported, not disguised as successful release.
One Canvas is single-writer; independent canvases may be used concurrently.

### 3.4 Recording and assets

One normalized command vocabulary drives all backends:

- Fill path / stroke path (or a shared stroke-to-outline lowering).
- Draw image region with transform, sampling and compositing.
- Clear a region, explicit clip snapshots, begin/end isolated layer.
- Glyph runs/outlines with positioned glyphs and paint.
- Defined image-effect operations with bounded input/output regions.

Commands carry effective state and explicit coordinate spaces. Resources use
validated identifiers and owned snapshots, not Julia object addresses, Vulkan
handles, arbitrary callbacks, or serialized Julia objects. The browser wire
schema is separately versioned; it is not an on-disk dump of Julia structs.

`draw_image!(canvas, mutable_image, ...)` captures the image contents at the
documented recording boundary. Repeated images/fonts may be captured once as
immutable assets and referenced many times. Cache keys include identity/version,
device, format and relevant scale; bounded caches have explicit eviction and
in-flight ownership. No global strong cache of every font or device image.

Choose command storage after measuring the existing recordings. A small union
or tagged buffer may help batching; dynamic dispatch once per large draw can
also be acceptable. Never put boxed command interpretation inside a pixel loop.

### 3.5 Intended user experience (proposed API)

The exact overloads are frozen in R010. This illustrates the required separation,
not currently executable code:

```julia
function badge!(canvas, font)
    fill!(canvas, rgb(246, 248, 252))
    fill_rect!(canvas, 16, 16, 288, 168; paint=rgb(30, 90, 210))
    fill_text!(canvas, font, "One drawing, many targets", 28, 90;
               paint=rgb(255, 255, 255))
    return canvas
end

cpu = Canvas(320, 200)                        # default CPU target
gpu = Canvas(320, 200; backend=VulkanBackend(device))
web = Canvas(320, 200; backend=BrowserBackend())
page = new_page!(pdf_document, 320, 200)       # returns a PDF-backed Canvas

badge!(cpu, font)
badge!(gpu, font)
badge!(web, font)
badge!(page, font)

pixels = snapshot(cpu)                       # owned host Image; flush + wait
wait(flush!(gpu))                            # completion without a readback
display(web)                                # browser/notebook adapter
```

Concrete backend construction binds/allocates its target from the logical size
and device-scale specification. Construction helpers dispatch on the backend
configuration; the shared drawing methods never inspect that configuration.
Encoding `pixels` as PNG/JPEG/WebP is a codec choice outside `badge!`.

### 3.6 Array storage and execution are independent

An image's storage format does not choose its processor. Support host
`AbstractMatrix` and `AbstractVector` inputs/outputs through ordinary Julia
indexing and typed pixel conversions. Rendering stays in the CPU or Vulkan
backend selected by the caller. Reuse the existing color-matrix conversions;
M003's owned-image matrix imports are not the new interoperability limit.

Required storage contracts:

| Storage | Interpretation and requirements |
| --- | --- |
| Matrix of pixels | `[row, column]`, top-left origin; supported Vetra/ColorTypes pixel elements determine channel and alpha interpretation |
| Vector of pixels | Explicit width/height and row-major or column-major layout; `vec(matrix)` is column-major, not a row-major image buffer |
| Raw channel Matrix/Vector | Explicit channel order, channel type/range, alpha convention, dimensions and layout/strides; do not infer RGBA from `UInt8` or guess a packed integer's byte order |
| Views / reshaped / strided arrays | Use logical indices, respect strides and preserve pixels outside the destination view; no assumption that `pointer(A)` describes contiguous pixels |
| StaticArrays | With the optional integration installed/activated, immutable `SMatrix`/`SVector` are valid inputs and newly constructed outputs; mutable `MMatrix`/`MVector` also accept writeback. Fixed shape must match. Core-only use needs no StaticArrays dependency |

R010 freezes supported pixel types (including grayscale and RGB/RGBA), scalar
ranges, quantization and alpha conversion. Explicit conversion can bridge other
libraries' representations; arbitrary foreign pixel types are not automatically
understood. Arrays with non-one-based axes are mapped by ordered axes with the
first row/column at the origin. Device arrays need a dedicated transfer adapter,
not scalar host indexing disguised as generic array support. Internal RGBA8
render precision remains explicit even when importing/exporting float arrays.
Export to opaque RGB/grayscale requires an explicit matte when pixels contain
transparency; grayscale conversion has a specified luma rule. Validate nonfinite
channel values and out-of-range conversion policies at the array boundary.

Proposed API behavior, with exact signatures frozen in R010:

- `Canvas(A; backend=..., copy=true, ...)` imports a snapshot of the supplied
  pixels. CPU or GPU execution can be selected independently; later writes to A
  do not silently invalidate uploaded assets.
- CPU `Canvas(A; copy=false, ...)` borrows a writable array as its target.
  Compatible native layout can alias directly; other supported layouts use
  staging with writeback complete at `wait(flush!(canvas))`. Report which path
  is used. Keep A alive, forbid concurrent outside mutation/resizing, and never
  free it on close. Immutable destinations are rejected before drawing.
- `snapshot!(destination, canvas; ...)` flushes, waits and copies/converts into
  caller-owned host storage. This is the explicit GPU→host synchronization
  boundary, including row-pitch/orientation conversion. Validate destination
  size/type/layout before writing; overlapping views are handled through a
  safe staging copy or rejected before modification.
- Allocating snapshot conversion supports a requested Matrix/Vector or fixed
  StaticArray type. Immutable static output is constructed, never mutated.
- Explicit pixel replacement/upload updates the render target from an array
  after external edits. Device/host mirrors never synchronize implicitly.

GPU construction from A uploads a snapshot; it does not borrow ordinary host
memory as a device render target. `copy=false` is rejected for that combination.
GPU drawing remains on the device until an explicit snapshot/export requests
host pixels. Export may use staging; interoperability does not promise zero-copy.
Transfer errors identify whether a destination is unchanged or partially written.

Changing processor creates a new concretely typed Canvas: transfer current
pixels explicitly to continue raster editing, or replay an owned Picture to
rerender geometry. Copy shared drawing state explicitly when continuation needs
it; a pixel snapshot alone does not include clips, transforms or saved states.
Do not mutate the backend type field or pretend a GPU image becomes a Matrix.
Changing processor preserves the chosen fidelity profile, not necessarily
bit-identical antialiasing between CPU and GPU.

Example of the intended workflow (proposed, not implemented):

```julia
gpu = Canvas(input_matrix; backend=VulkanBackend(device))
badge!(gpu, font)
snapshot!(output_matrix, gpu)  # synchronized GPU render → host pixels

cpu = Canvas(output_matrix; copy=false)
badge!(cpu, font)
wait(flush!(cpu))              # caller's matrix now contains the CPU edits
```

The same array boundary accepts decoded media frames and supplies encoder
frames, so an external Julia library can edit pixels between decode and encode.

### 3.7 SOLID and extension without core edits

**Requirement:** a third-party package can add a renderer, image codec, frame
provider, pixel-storage adapter or display integration using published contracts,
without editing Vetra source, exports, dependency lists, provider registries or
existing consumer algorithms. Installing/loading/selecting the new package is
expected configuration, not a change to the drawing function. The guarantee is
within a supported protocol version and the capabilities the consumer requires.

Apply SOLID through Julia multiple dispatch and composition:

| Principle | Concrete architectural rule | Evidence |
| --- | --- | --- |
| Single responsibility | Canvas owns drawing semantics; backends own execution/resources; storage adapters own pixel conversion/access; codecs own single-image IO; media providers own temporal IO; display adapters own presentation | Independent modules and tests; no codec imports in drawing-state code or device management in pixel layouts |
| Open/closed | Add provider-owned types and methods on documented extension functions; existing frontend and consumer code keep working | An external-package extension test with an unchanged core tree and metadata |
| Liskov substitution | Providers advertising the same profile honor the same ordering, pixel/alpha/timing, ownership, error and completion contracts; no stronger hidden preconditions | Shared conformance suite plus negative/lifetime tests; capability negotiation occurs before target modification |
| Interface segregation | Drawing execution does not require readback, presentation, encoding or seeking. Read-only codecs need no encoder; sequential frame readers need no random access | Narrow required method sets and explicit optional capabilities, no dummy implementations |
| Dependency inversion | Frontend and pipelines depend on Vetra-owned stable contracts; optional concrete providers depend inward on those contracts | Core-only load/precompile tests and dependency inspection; provider instances are passed explicitly |

Small extension surfaces, finalized in R010/R064:

| Extension | Required integration | Optional features remain separate |
| --- | --- | --- |
| Render backend | Provider-owned backend/target construction, capability query, ordered submit, completion handle and close; consume public commands/assets | Host readback, window presentation, device-specific acceleration |
| Pixel storage | Supported pixel/layout description and indexed read/conversion; writable adapters add validated write/conversion | Direct aliasing, bulk transfer, allocating static output; no mutable-target claim for immutable storage |
| Image codec | Provider-owned codec value and implemented decode and/or encode operation over canonical pixels/IO | Sniffing, provider options, format-specific metadata |
| Frame provider | Provider-owned reader/writer types, frame/timeline metadata, implemented iteration or append, close/finish/abort lifecycle as applicable | Seek, VFR output, extra-track preservation, hardware encoding |
| Display integration | Adapter-owned view/session over public snapshots, recordings or browser payloads | Live updates, comms, interactive presentation |

Provider selection uses concrete objects/multiple dispatch, not edits to a closed
backend enum, an `isa` ladder, a central known-package list or a required global
registration hook. Existing built-in format inference may stay as convenience;
explicit codec/provider selection must support unknown external formats without
changing that inference table. Capability identifiers and extension options are
namespaced/provider-owned, with stable shared identifiers for common profiles.
Unknown capabilities are unsupported, never assumed supported.

An extension specializes methods on at least one type it owns. When integrating
two foreign packages, own an adapter wrapper and dispatch on it; avoid type piracy
and cross-provider method ambiguities. Optional companion packages depend on the
core and their concrete dependencies. Package extensions are useful for known
optional integrations, but adding a wholly new provider must not require updating
Vetra's `[weakdeps]`/`[extensions]`. Provider loading must not initialize a device
or silently replace another provider's defaults.

Expose only the types/accessors necessary to construct targets, consume commands,
read/write pixels and report capabilities/errors. Keep scratch buffers, caches,
driver objects and command storage layout private. Algorithms dispatch at coarse
boundaries with concrete values; SOLID is not a reason for abstract fields in hot
loops, a service locator, a plugin registry or a hierarchy of one-method wrappers.

Version the public extension contract, command semantics and browser wire schema
explicitly; state supported version ranges and reject incompatible providers at
binding/preflight before execution. Evolve compatibly where possible with an
announced deprecation/migration policy; tests run against supported core versions.
New providers implementing existing primitives require zero core changes. New
high-level operations can also live externally when lowered into existing public
primitives. A genuinely new primitive/semantic guarantee requires a reviewed,
versioned contract change; arbitrary unknown commands are not silently accepted.

R013 proves this with out-of-tree packages consuming only supported APIs, including
two simultaneously loaded providers and core-source/metadata integrity checks.
R090 repeats the proof at the release candidate. A clean-looking class diagram
or a backend that depends on private Vetra fields does not satisfy this requirement.

### 3.8 Embedding beneath GUI frameworks and plotting libraries

The shared engine supplies geometry, text measurement/layout, raster/vector
drawing, compositing, surfaces, resource lifetime and export. Consumers own their
domain objects and scheduling. These are required integration seams now, verified
by small external consumer prototypes in R014; complete GUI/plotting products
remain separate libraries.

| Concern | Vetra contract | GUI / plotting consumer owns |
| --- | --- | --- |
| Drawing | Same Canvas commands/Pictures on CPU, Vulkan, browser and documents | Widget trees, chart/series objects and conversion to drawing primitives |
| Text | Headless reusable measurement/shaping, advance versus ink bounds, baselines, line metrics, positioned glyphs and cluster mapping matching drawing | Widget layout, tick/legend layout, text editing/selection policies, mathematical typesetting |
| Input | Public coordinate mappings and geometric fill/stroke hit tests; documented singular-transform behavior | Pointer/keyboard/IME routing, focus, gestures, accessibility tree and semantic hit ownership |
| Viewports | Logical/device scale, nested transforms/clips, target size and resize lifecycle | Scroll/zoom/pan state, chart data limits, nonlinear scales and axes/ticks |
| Frame lifecycle | Explicit ordered submission/completion, reusable assets, optional presentation and host readback | Event loop, frame clock, invalidation requests, UI-thread ownership and backpressure policy |
| Surfaces | Offscreen rendering and adapters for host-owned display/device targets with explicit borrowing | Window creation, OS toolkit integration, swapchain ownership when externally supplied |
| Export | Reuse the same drawing description for raster, vector, notebooks and recorded media | Selecting document/page size, print layout and application metadata |

**Host-controlled integration.** Drawing/measurement must work without a window,
running event loop or notebook. Core never captures global input, starts a hidden
UI loop or forces a windowing dependency. A framework can hold a Canvas and reuse
assets across frames; presentation is separate from drawing. It chooses when to
flush, wait, present, snapshot and close. Thread affinity is declared by the
surface/provider, not silently changed by core; one Canvas remains single-writer.
Resize/DPI changes specify when old submissions finish, which targets/assets are
invalidated and how device resources are recreated. A zero-size minimized window
pauses presentation instead of allocating an invalid render target.

Borrowed GPU devices/queues/images or host surfaces require documented incoming
and outgoing synchronization, image-layout/queue-ownership transitions, format
and lifetime rules. Capability-test each supported external target; do not claim
arbitrary toolkit/native-handle compatibility or force the host to give Vetra
ownership of its device. Offscreen rendering plus an explicit copy is the
portable integration path when direct target sharing is unavailable. R040/R041/
R045 freeze and demonstrate the supported native sharing seam.

**Reusable rendering and invalidation.** A consumer can retain immutable Pictures,
glyph runs and image assets, replay them under documented placement/clip rules,
and replace only changed recordings. It may organize those into its own scene
graph; Vetra does not require one. Expose geometric/ink/effect bounds with their
coordinate space and whether they are conservative. Consumers can use them for
layout, hit-test broad phases and invalidation without reading pixels back.
Region redraw is an optional optimization, never an assumed swapchain guarantee:
preserve/restore a valid background, account for old and new bounds, stroke and
filter halos and painter order, and promote to full redraw when destination
dependencies or unknown bounds require it. Both paths must match a fresh full
render. The initial baseline may redraw the whole frame while reusing assets.

**Plotting precision.** Separate high-range data/world coordinates from local
canvas coordinates. Plot adapters apply their data mapping/origin subtraction
in sufficient host precision before constructing Float32 render paths. For
example, timestamps near `10^12` differing by one must remain distinct after
mapping into a small viewport; converting them to Float32 before subtraction
would destroy that distinction. Subtract large integer origins before float
conversion when needed. Caller-supplied logarithmic/categorical mappings and
missing-data segmentation stay in the plotting layer; Canvas receives finite
local geometry. Publish the conversion point, precision/error bounds and inverse
mapping conventions used for picking. GPU Float64 support is not required for
this local-coordinate path. Existing legacy Path precision remains unchanged.

**Plotting workloads.** Repeated markers, polylines, glyph labels and Matrix-based
heatmaps must reuse the existing path/image/asset primitives, with measured
allocation and transfer costs. Large data clipping, decimation and statistical
aggregation belong to the plotting library; core must not silently simplify a
path or discard samples. Screen and PDF/SVG output share logical geometry/text
layout; output scale and backend antialiasing have their declared profiles.

R014's external consumers exercise a small host-driven UI scene and a chart
adapter, using only public contracts. Their required code changes are confined
to consumer configuration when selecting another backend. Integration gaps feed
back into R010's contracts; a demo using private fields does not pass.

## 4. Numerical and drawing semantics

The contract task freezes these rules with independent examples before parallel
backend implementation. Existing `Context` keeps its documented legacy behavior;
new Canvas behavior is versioned and any differences get a migration note.

| Area | Canvas contract |
| --- | --- |
| Coordinates | 2D continuous logical coordinates, origin top-left, x right, y down; finite `Real` input converted once at the boundary |
| Precision | Float32 local render geometry initially; data/world mapping and origin subtraction occur before narrowing, in sufficient host precision. Int dimensions/indices use checked arithmetic; pixel/layout math is explicit |
| Pixel indexing | Julia host matrices/Image use `[row, column]`; legacy `(x,y)` accessors stay explicit |
| Pixel geometry | Host pixel `[row, column]` covers `[column-1,column] × [row-1,row]`; its center is `(column-0.5,row-0.5)`. Coverage describes the pixel area; point-sampled paints use the center in the new profile |
| Device scale | Separate logical size from physical pixels; browser DPR and PDF dpi are boundary mappings, not extra transforms applied twice |
| Paths | Explicit Path geometry is in local coordinates; effective transform is captured at drawing time. Canvas convenience path builders follow this same contract, rather than silently inheriting browser-specific path-state behavior |
| Transforms | Ordered affine composition; define singular/degenerate cases and stroke scaling before implementation |
| Clipping | Transform a clip into canvas coordinates when established; subsequent transform changes do not move it; clips intersect and save/restore scopes correctly |
| Clear | Respect the effective transform and clip, ignore paint/global alpha; transparent destination replacement, not painting white |
| State | Save/restore covers every documented state field, including text baseline and dash copies; no clip leakage between scopes |
| Layers | Isolated transparent intermediates; group opacity applies once to the composed group |
| Compositing | Separate Porter–Duff operator from artistic blend mode; specify coefficient/rounding tables and transparent-pixel cases |
| Color | Initial portable profile is sRGB-encoded RGB with explicit premultiplied alpha for rendering; straight RGBA at codecs/browser ImageData boundaries |
| GPU storage | Specify channel order, format, row pitch, alignment, orientation and transfer conversion; do not accidentally enable sRGB hardware conversions twice |
| Gradients | Paint coordinate space, stop validation, interpolation, spread modes and degenerate handles are explicit |
| Sampling | Explicit nearest/linear modes, source rectangle and edge behavior; no backend-dependent implicit filter |
| Effects | Define blur/shadow/spread radii, bounds expansion, clipping, edge padding and alpha treatment |
| Text | Shared layout + positioned outlines is the portable mode; browser-native text is an explicitly different capability/profile |

Legacy gradient/sample locations must be translated or kept under the legacy
profile explicitly; a half-pixel coordinate disagreement is not an antialias
tolerance to hide. R010 pins representative boundary cases before adapter work.

Wide-gamut/HDR, arbitrary ICC management and 3D transforms are future milestones,
not optional flags silently accepted today. Color conversion and numeric tests
must precede any broader color profile.

### Fidelity profiles

1. **CPU regression profile:** byte-exact against existing fixtures where the
   operation's semantics have not intentionally changed.
2. **Portable 2D profile:** same geometry, state, composition and layout across
   backends. Exact assertions for integer-aligned opaque interiors, dimensions,
   ordering and simple nearest sampling. Antialias and float differences have
   feature-specific bounds justified before implementation and approved by the
   reviewer; do not compare only a global average error that hides missing paths.
3. **Native text/display profile:** browser/font/device-specific rendering is
   labeled as such; it does not satisfy deterministic outline-text checks.

Each comparison reports interior/edge errors separately, the first mismatch,
maximum error, affected-pixel count, and relevant device/browser details.
CPU output alone is not an independent oracle: use hand-derived geometry,
existing independent fixtures, browser standards cases, font-shaper references,
and independent PDF readers where appropriate.

## 5. Capabilities and fallback

Preflight evaluates the actual command/paint/format combination and target
limits, not just a coarse “supports gradients” Boolean. The capability report
distinguishes native, equivalent lowering, explicit raster fallback, and
unsupported. Examples: a PDF can support opaque radial gradients but not the
same representation with varying alpha; a Vulkan device can lack a required
storage-image format; a browser may lack OffscreenCanvas or a filter.

Default policy is **strict**. Equivalent shared lowerings (such as a stroke
outline) are permitted when their semantics are covered by conformance tests.
Opt-in raster fallback is reported in the render result, with reason and scope.
For destination-dependent blending/filters, conservatively rasterize the whole
frame/page or a proven isolated group, not an arbitrary individual operation.
Never silently route a Vulkan benchmark through CPU rasterization.

A standalone static browser page cannot invoke Julia to render a missing
feature. It uses supported browser operations or an already supplied fallback
asset; otherwise it gives a capability error. A connected notebook can request
an explicitly enabled CPU fallback. The site and capability matrix must make
that distinction visible. A browser release cannot claim the full portable
profile if required offline operations are still unsupported.

## 6. Backend-specific design

### CPU

Adapt existing kernels first. Shared stroke outlines and text outlines can be
used by all backends. Preserve the fast direct CPU path and avoid extra image
copies for ordinary rendering. Close the recorded full-2D gaps explicitly:
painted strokes, transformed/scoped clips, compositing operators, dash phase,
stroke hit-testing, resource ownership, and advertised text/layout behavior.

### Vulkan.jl

Native GPU work must use Vulkan.jl; CUDA, OpenGL or WebGPU are not substitutes
for this target. A compatibility spike establishes supported Julia/Vulkan.jl,
loader, shader compiler and driver versions before fixing the package compat.
Rendering algorithms remain Julia-authored under the repository policy: the
spike must demonstrate a supported Julia-to-SPIR-V route and validate its output.
Do not assume arbitrary Julia rasterizer code can be compiled into a shader.
If that route is incompatible, record the concrete blocker and resolve the
shader/toolchain decision explicitly before implementing GPU algorithms.
The [reviewed Vulkan findings](CANVAS_RESEARCH.md) identify SPIRV.jl as an
experimental candidate with a Vulkan-version compatibility constraint. OpenCL
`Kernel` SPIR-V is not a validated Vulkan compute path. Require validation for
the chosen Vulkan target environment plus an executed pipeline/readback probe;
shader validation and runtime Vulkan validation layers are complementary.

Start with an offscreen target, one command buffer, upload, draw/dispatch,
barrier, fence and verified readback. Reuse CPU path flattening/stroke geometry
initially, while raster coverage, paint evaluation and composition execute on
the GPU. A correctness-first path implementation must support holes, winding,
self-intersections and antialiasing before tile binning/batching optimization.

Advanced blends and filters may need storage images and ping-pong targets;
ordinary fixed-function alpha blending is insufficient for all existing modes.
Clip/layer dependencies constrain batching: preserve painter order and do not
reorder overlapping translucent operations to reduce draw calls.

Treat the device, queue, command buffers, descriptors, pipelines, uploaded
assets, temporary images and submission fences as explicit owned resources.
Validate non-coherent flush/invalidate ranges and memory barriers. Test close,
reuse, resize, timeout, failed creation and device-loss paths. GPU-dependent
code is optional and cannot slow or break `using Vetra` on CPU-only machines.

### Browser

The Julia adapter emits a closed, versioned command/asset schema. A small JS
runtime invokes native Canvas 2D APIs and shares the same runtime between
offline HTML, Pages examples and notebook views. No `eval`, serialized Julia
closures, required application server or mandatory native Julia-in-WASM runtime.

Translate the normalized path/paint/state contract explicitly instead of replaying
legacy Context method names verbatim. Use outline text for portable layout;
opt-in native text awaits browser font readiness and has separate metric tests.
Use capability detection for OffscreenCanvas, worker rendering and filters.
Define resize/DPR reset, context loss, tainted canvas/CORS and asset decode errors.
Embedded text/JSON is escaped safely; assets are bounded and schema-validated.
JSON quoting and HTML embedding are distinct boundaries: protect script raw-text
against `</script>` termination and escape HTML labels/attributes in their own
contexts. Preserve canonical numeric values across Julia/JS parsing. Affine paint
and blend-name mappings need semantic tests, not just a matching browser API name.

### PDF and SVG

Reuse the existing strict writers behind the backend interface. Preserve vector
content when supported; preflight before publishing files. A PDF document owns
pages, each page gets a Canvas, and finalization writes a valid cross-reference
table exactly once. Define behavior for empty documents, unfinished pages,
closed IO and repeated finalization. Extend supported vector operations and
image effects by explicit mappings or documented fallback.

Outline text is the deterministic baseline. Selectable/searchable PDF text
requires a separate font-subsetting/embedding and ToUnicode contract, licensing
checks on the actual font, and independent text extraction tests. Do not call
outline-only text searchable. SVG import remains a documented parser subset;
exporting a vector scene does not imply full arbitrary-SVG support.

### Codecs, matrices and image manipulation

All existing decoders feed owned canonical images/assets; encoders consume an
explicit raster snapshot. Existing GIF APIs decode; sequence APIs add encoding.
JPEG has no alpha. Preserve the existing static WebP animation rejection guard:
new animated decoding must use a verified animation-capable path. SVG remains a
vector import/export path. Optional providers keep explicit installation errors.

Canvas image effects are recorded operations with shared semantics. Direct
`Image` mutation remains a useful CPU API; it is not emulated by pretending GPU
memory is an ordinary `Matrix`. Cross-device copies/readback are explicit.

### Animated GIF, animated WebP and MP4 frame editing

Required workflow: **decode existing media → select/edit frames using Canvas or
array/image operations → encode the edited sequence**, retaining source timing
by default where representable. Also record newly rendered frames and append
multiple sources into one output. Temporal media is a frame pipeline alongside
render backends; it consumes host snapshots from CPU/GPU or a connected browser.

Proposed families, frozen after the R064 provider spike:

- Closeable `FrameReader`: sequential presentation-order iteration yielding
  owned editable pixels, rational presentation time and duration. Retained frames
  never silently alias a reused decoder buffer. Reusable-buffer reads, if offered,
  are an explicit separate mutating API.
- `FrameWriter` / `write_frame!`: append an Image or declared array layout with
  timing, bounded queues/backpressure, explicit finish/abort and useful errors.
- `append_frames!`: decode, optionally edit/normalize, rebase relative timestamps
  after the preceding segment, and re-encode. This is not file-byte concatenation.
- `record_frames!`: invoke the supplied callback as `draw!(canvas, i, t, dt)`
  once per requested frame in presentation order: `i` is 1-based, `t` and `dt`
  are rational seconds on the requested output timeline, starting at `t = 0`.
  Capture/write after callback completion and render synchronization. Encoder
  time quantization happens afterward and is reported; wall-clock rendering
  speed never changes the callback's requested time or playback schedule.

Readers expose fully composited display frames. GIF/WebP offsets, blend,
transparency and disposal (including GIF restore-previous) are resolved before
editing. Sequence metadata records dimensions, timing and loop semantics; source
loop counters are normalized rather than assumed identical across containers.
MP4 decoding returns presentation order even when coded packets are reordered.

Frame selection by index or time must work through sequential decoding. Efficient
seeking is a separately reported capability: video may require seeking to an
earlier keyframe and decoding forward; GIF/WebP may need replay of preceding
disposal state. Define which displayed frame contains a requested timestamp and
end-of-stream behavior. Do not promise constant-time indexing or materialize all
frames just to edit a few. Unselected frames flow through with their timing;
all output frames may still need re-encoding.

| Boundary | Required behavior |
| --- | --- |
| Timing | Rational timestamps/durations with checked arithmetic; preserve VFR when supported, otherwise require explicit resampling. Unknown/zero delays have a documented policy, never an inferred wall-clock cadence |
| GIF output | Explicit palette quantization/dithering, binary transparency and centisecond delay conversion; cumulative-time quantization bounds drift. Two-pass global palettes disclose spooling/buffering |
| Animated WebP | Verified animation demux/decode and encode/mux path; alpha, millisecond timing, loop/blend/disposal and size/timestamp limits tested |
| MP4 output | Specify codec and pixel-format profile independently of the container; define RGB↔YUV range/matrix/transfer and dimension constraints. Transparent input requires an explicit matte if the profile lacks alpha |
| Concatenation | Preserve relative presentation timing, rebase segment starts, choose one explicit output loop policy; require selected resize/matte/color/retiming rules for incompatible inputs |
| Editing | Preserve untouched display regions within format precision; no promise of lossless compressed-byte edits, identical palettes or identical lossy pixels after re-encoding |
| Streaming | Bound raw-frame memory by queue/buffer count, not sequence length; measure/disclose provider compressed-output buffering and temporary disk spooling |
| Files / IO | Write to a separate staged output, publish only after successful finalization; failures preserve the original. Explicit same-path replacement closes input first and is staged. Borrowed IO stays open; unsupported non-seekable muxing is rejected before writing |

Initially the frame-editing output is video-only. Readers report audio/subtitle
tracks; editing a file with such tracks requires an explicit drop policy if
preservation is unsupported, rather than silently losing them. Audio editing and
packet-level lossless remuxing are outside this frame API. Required pixel/timing/
loop/color metadata is distinguished from ancillary metadata not preserved.

R064 verifies actual provider support for each format and four-OS availability;
VideoIO/FFmpeg/static WebP wrapper availability alone is not proof. Media remains
optional. The portable GPU path uses explicit readback; hardware video encoding
and zero-copy encoder interop require separate demonstrated capabilities.
The reviewed media findings in [the research record](CANVAS_RESEARCH.md) identify
WebP ABI/library-boundary defects, VideoIO timing/conversion probe requirements
and an FFmpeg build-selection constraint. No provider choice is frozen here.

### Jupyter

Retain `image/png` and concise `text/plain` display. Add HTML/browser output and
vector MIME only where supported, always with a useful fallback. Ordinary
display must work without a live comm channel. Optional IJulia comms carry
versioned updates with backpressure, errors and disposal; notebook reruns must
not leave devices, widgets or sessions permanently retained. Test actual saved
and executed notebooks, not only string contents of `show` methods.
Keep PNG/plain text available and include a useful static fallback inside HTML:
untrusted frontends may sanitize scripts or reject SVG, and co-bundling PNG alone
does not establish fallback selection. Verify trusted/untrusted, reopened and
script-blocked views per supported frontend. Media playback uses a tested HTML
video/poster/download view unless native MIME support is actually demonstrated.

## 7. Packaging and future extension

Keep the CPU core usable on Julia 1.10+ without Vulkan, a browser bridge or a
notebook kernel. Prefer optional companion packages for heavy backends when
their minimum Julia version or platform support differs from core. The Vulkan
spike settles a pinned tested combination; it may have a higher Julia minimum
without silently raising the core minimum. Browser transport dependencies are
similarly isolated. Use standard Julia package extensions for lightweight
integrations where their load/version semantics fit, rather than ad-hoc import
hooks. Exact package boundaries are frozen in the interface gate.

Backend initialization is explicit: loading or precompiling the CPU package
does not create a Vulkan instance/device or start a browser/kernel. Native
handles and device pipeline caches are process/device scoped and never stored
as reusable handles in Julia precompile artifacts. Shader-cache compatibility
includes shader source/hash, device/driver and relevant compile options.

Future 3D can reuse device/resource ownership, submission and presentation.
Do not expose 2D edge bins, assume every future target is RGBA8, or bake CPU
pointers into the public protocol. Do not add cameras, depth, meshes, 4×4
transforms, materials, a scene graph or a speculative universal graphics IR in
this milestone. `Canvas` remains a 2D API; a future 3D API can be separate.

## 8. Delivery and evidence

The [task plan](../tasks/CANVAS_ROADMAP.md) assigns nonoverlapping workstreams,
dependency gates, tests and review ownership. The coordinator reviews every
implementation diff, reproduces important claims, requests edits, and approves
only after its stated evidence exists. A subagent's “done” report is not approval.

The **last task** executes and publishes an interactive tutorial through GitHub
Pages CI. It uses the actual browser runtime for live rendering, labels native
Julia/Vulkan examples correctly, and offers runnable Julia scripts/notebooks.
The preceding README task produces real Vetra-rendered image examples, tested
installation/use-case snippets, a clear capability table, and links to the site.
