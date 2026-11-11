# Multi-backend 2D engine: agent development plan

Requested 2026-11-10. Architecture: [Canvas design](../docs/CANVAS_DESIGN.md).
This is an implementation plan, not a list of already supported backends.
R000 is complete. New backend implementation starts only after
its listed dependencies and interface review gate pass.

Independent re-review approved the architecture/task plan on 2026-11-10 after
verifying all ten corrections: 43 matching task specs, 98 dependency edges,
acyclic, every task leading to R099. Source review and final independent media
consistency review are complete, with no blocking findings;
R040/R064 supply later runtime evidence and R010 freezes executable contracts.

## Ownership, execution and approval

- **Coordinator/reviewer:** the primary agent owns architecture, shared exports,
  package metadata, task status, integration, evidence and final approval.
- **Implementers:** bounded agents, initially Qwen3.8, each in a separate Git
  worktree/branch. One active task per writer. Independent streams may run in
  parallel after shared interfaces are frozen. Never share a writable worktree.
- An agent receives one task ID, pinned base revision, owned paths, contracts,
  exact checks and a stop condition. It returns commits, diff summary, test logs,
  benchmark data and remaining limits; it does not mark its own work approved.
- Coordinator reads connected callers, error/lifetime paths and tests, reruns
  representative checks, and requests numbered fixes. Changes to shared
  contracts require a coordinator decision and updates to every consumer in the
  same integration wave. No independent incompatible protocol variations.
- Approved tasks are committed and pushed individually. A push needed to test CI
  is recorded as **verification pending**, not completed. Failures get follow-up
  fixes; no `continue-on-error` or tolerance changes to manufacture approval.
- Package registration remains user-owned. Documentation publication is authorized.

Status vocabulary: `ready`, `in_progress`, `review`, `verification_pending`,
`blocked` (with reason), `done` (approved with evidence). The initial table uses
`planned` for dependency-gated tasks; it is not authorization to claim completion.

## Reconcile the modernization work

| Existing task | Treatment |
| --- | --- |
| M001 baseline/audit | Done; retain evidence |
| M002 four-platform CI | Done at `d2d44fa`, run 42811680553; extend, do not replace |
| M003 Julia-native API | Done; independently validated additive foundation for Canvas (see handoff) |
| M004 correctness fixes | Done: independently validated FFI ownership/failure handling, cmap-12 bounds, dash copies and crop fixes (see handoff) |
| M005 new docs/Pages | Fold into **R099**, the last task; do not publish prospective backend support as current |
| M006 obsolete-file cleanup | Fold into **R086**, after durable contracts have replacements |
| M007 final validation | Fold into **R090**; R099 additionally validates the final published docs revision |

M003 must not expand into a second, competing Canvas implementation. R000 does
not authorize a blanket rename/rewrite of tested raster kernels.

## Streams and owned paths

| Stream | Main work | Exclusive implementation paths (proposed) |
| --- | --- | --- |
| F — frontend/contracts | Commands, Canvas, shared state/layout | `src/canvas/`, `src/recordings.jl`, `src/formats/{fonts,paragraph,shaping}.jl`, `src/fontformats/`, their tests; separate typography owner |
| C — CPU | Kernel adapter and full-2D gaps | `src/backends/cpu.jl`, selected existing raster/path/effect files, `test/cpu_backend/` |
| G — Vulkan | Native device rendering through Vulkan.jl | `lib/VetraVulkan/` (or the reviewed extension boundary), its shaders/tests |
| W — browser | Canvas2D protocol/runtime/worker | `lib/VetraBrowser/`, `browser/`, browser tests |
| O — outputs | Host array targets, pixel/codec interop and PDF/SVG | Proposed `src/arrays.jl`, `test/arrays/`, `src/backends/{pdf,svg}.jl`, raster codec/IO/color-matrix files and SVG/PDF writers; excludes font/layout/shaping files |
| T — temporal media | Frame decoding, editing, encoding and concatenation | Proposed `lib/VetraMedia/`, `test/media/`; shared pixel contracts remain coordinator-owned |
| N — notebooks | MIME/display and optional IJulia updates | Proposed `src/display.jl`, notebook extension/adapter, `test/notebook_display_tests.jl`, `test/notebooks/` |
| Q — validation/performance | Common conformance, CI and benchmarks | `test/conformance/`, proposed `lib/VetraTestSupport/`, `test/integration_consumers/`, `benchmark/backends/`, `.github/workflows/`, CI scripts |
| D — docs | User guides, images, final interactive tutorial | Existing flat user guides and `docs/*.jl` build sources, `docs/assets/`, README; `docs/src/` only if the approved site layout introduces it |

Coordinator alone integrates `src/Vetra.jl`, root `Project.toml`,
`test/runtests.jl`, shared command/schema definitions and task/decision documents.
Agents submit suggested changes to those files with their patch when streams
are concurrent. R030 and R031 are sequential because they share CPU ownership;
the same CPU writer then completes R032–R034 in order.
R061/R062 are sequential for PDF ownership. CI changes go through Q, not each
backend agent independently. Typography work owns font/layout files and finishes
before backend text integration touches them.

`src/context.jl` is coordinator-integrated: frontend/CPU agents submit scoped
patches rather than writing it concurrently. The same rule applies when moving
existing MIME methods out of codec/IO files into the display adapter. Shared
architecture/decision/API documents remain coordinator-owned; D owns user-facing
guides and supplies proposed reference edits for integration.

R022's CPU target hooks are coordinator-integrated to avoid concurrent writes
with C. R031–R034 operations must work on every valid CPU target (Image and
R022 arrays); C and O coordinate target-path changes through that integration
rule, with combined array/feature checks once both branches are available.
R023 belongs to G and edits only Vulkan transfer code/tests. T submits
changes to existing GIF/WebP codecs through O/coordinator; the static decoder
guard stays intact. R066/R067 can run in parallel only with separate GIF/WebP
and MP4 modules/worktrees after R065 freezes the common reader/writer interface.

## Dependency board

| ID | Task | Stream | Depends on | Initial status |
| --- | --- | --- | --- | --- |
| R000 | Architecture, research and reviewed task plan | Coordinator | — | done |
| R040 | Vulkan.jl/platform/shader compatibility spike | G | R000 | in_progress (713543b rejected; probe corrections assigned) |
| R010 | Freeze Canvas semantics and backend/package contracts | F | R000, R040, M003 | planned |
| R011 | Independent conformance corpus and capability inventory | Q | R010 | planned |
| R012 | Shared text/layout correctness and font contract | F | R010, M004 | planned |
| R013 | Zero-core-change external extension conformance | Q | R021, R022, R060, R065, R066 | planned |
| R014 | External GUI and plotting integration proofs | Q | R013, R012, R034, R045, R052, R062, R063 | planned |
| R020 | Owned commands/assets and legacy Picture adapter | F | R010 | planned |
| R021 | Renderer-independent Canvas and submission lifecycle | F | R020 | planned |
| R022 | Host array canvas targets and pixel import/export | O | R030, M003 | planned |
| R023 | GPU/host array transfers and processor switching | G | R022, R043 | planned |
| R030 | CPU backend with regression parity | C | R021, R011, M004 | planned |
| R031 | Shared painted strokes, dash phase and stroke hit tests | C | R030 | planned |
| R032 | Composition, scoped clips/layers and clear | C | R031 | planned |
| R033 | Paint/pattern transforms and image sampling | C | R032 | planned |
| R034 | Recordable blur/shadow/spread and effect bounds | C | R033 | planned |
| R041 | Vulkan resource/submission/readback foundation | G | R040, R021, R011 | planned |
| R042 | Vulkan path coverage and stroke geometry | G | R041, R031 | planned |
| R043 | Vulkan paints/images/compositing | G | R042, R033 | planned |
| R044 | Vulkan clips/layers/effects/text | G | R043, R034, R012 | planned |
| R045 | Vulkan presentation and measured optimization | G | R044, R081 | planned |
| R050 | Versioned browser protocol and asset transport | W | R020, R011 | planned |
| R051 | Browser Canvas2D replay and static HTML view | W | R050, R021 | planned |
| R052 | Browser full-profile gaps, workers and browser matrix | W | R051, R034, R012 | planned |
| R060 | Codec/color-matrix/snapshot integration | O | R022 | planned |
| R061 | PDF page backend and document lifecycle | O | R021, R011 | planned |
| R062 | PDF completeness, text accessibility and fallback | O | R061, R034, R012, R060 | planned |
| R063 | SVG target/import integration | O | R061, R034 | planned |
| R064 | Media provider spike and frame/timing contracts | T | R010 | planned |
| R065 | GIF/WebP/MP4 editable frame readers | T | R064, R060 | planned |
| R066 | GIF and animated WebP frame writers | T | R065 | planned |
| R067 | MP4 frame writer and timing/color conversion | T | R065 | planned |
| R068 | Edit, record and concatenate frame pipelines | T | R066, R067, R034, R023, R052 | planned |
| R069 | Media conformance, lifecycle and performance | T + Q | R068, R081 | planned |
| R070 | Jupyter MIME display and real notebook execution | N | R051, R060, R061, R042 | planned |
| R071 | Optional live notebook updates and disposal | N | R070, R052 | planned |
| R080 | Backend/platform CI and artifact infrastructure | Q | R010 | planned |
| R081 | Reproducible backend benchmark/profiling harness | Q | R011, R030 | planned |
| R082 | End-to-end performance and allocation review | Q | R045, R052, R060, R062, R071, R081, R023, R069, R014 | planned |
| R086 | Package/document cleanup and migration consolidation | Coordinator | R082, R063, M004 | planned |
| R090 | Independent integrated release validation | Q + coordinator | R086, R080, R011 | planned |
| R098 | Illustrated, executable README and use cases | D | R090 | planned |
| R099 | Interactive tutorial + CI GitHub Pages publication | D + coordinator | R098 | planned, **last task** |

### Parallel waves

1. **Preparation:** finish M003/M004 in bounded sequence; Vulkan compatibility
   research/probe R040 can run independently. Coordinator reviews R010.
2. **Contracts:** after M003/M004 and R010, R011 conformance, R012 typography,
   R020 commands, R064 media probes and R080 CI can run concurrently in disjoint
   paths. R021 follows R020.
3. **Adapters:** CPU R030, Vulkan R041, browser R050→R051 and PDF R061 proceed
   in parallel once their dependencies pass. R081 starts from CPU baselines.
4. **Completeness:** sequential CPU R031→R034 unblocks GPU geometry, paints
   and effects at their respective feature gates, plus browser gaps;
   output R022→R060/R062/R063 and notebooks R070/R071 progress in their own paths.
   R023 adds GPU array transfers after R043. Media R065 then R066/R067 runs
   independently, joining CPU/GPU editing in R068 and validation in R069.
5. **Stabilization:** GPU R045 and cross-backend profiling culminate in R082;
   R013 proves external extension without core edits after the relevant protocols
   exist; R014 verifies host-driven GUI/plotting consumers. Consolidate in R086,
   independently validate in R090.
6. **Publication:** README R098, then the final interactive tutorial R099.

Concurrency is by owned paths and frozen interfaces, not by assigning two
agents to the same feature. A task can be split only with explicit ownership
and acceptance updates; do not add speculative subprojects merely to occupy agents.

## Task specifications

### R000 — Architecture and agent-ready plan

**Owner:** coordinator; read-only Vulkan, browser/notebook and media research agents.

- Inventory implemented CPU, recording, export, codecs, text and display APIs.
- Establish target/backend/codec/display separation, lifecycle, numerical and
  fallback policies, first-tier feature boundaries and migration approach.
- Include array storage independent of CPU/GPU execution and existing-frame
  editing/recording/concatenation for GIF, animated WebP and MP4.
- Target future GUI/plotting consumers through public embedding, measurement,
  reusable drawing, host-owned surface/scheduling and high-range coordinate seams.
- Verify Vulkan.jl and browser integration facts using primary sources; record
  source versions/URLs and unresolved compatibility probes.
- Deliver `docs/CANVAS_DESIGN.md`, this plan, decision record and active handoff.
- **Acceptance:** reviewed architecture, acyclic dependencies, nonoverlapping
  stream ownership, explicit tests/evidence for every task, final tutorial last.
- **Validation:** link/dependency checks, `git diff --check`, independent plan
  review. No new backend functionality is represented as implemented.
- **Completed 2026-11-10:** independent architecture and final media-amendment
  reviews approved; coordinator closed primary-source research with qualified
  evidence in `docs/CANVAS_RESEARCH.md`. Validation: 43 matching specs, 98 edges,
  acyclic, every task reaches final R099; 24 local links and whitespace checks pass.

### R040 — Vulkan.jl compatibility spike

**Owner/paths:** G; isolated probe environment under `lib/VetraVulkan/` or
temporary experiment output until the package boundary is approved.

Assigned 2026-11-11: Qwen3.8, branch `canvas/vulkan-probe`, worktree
`/tmp/opencode/vetra-r040`, base `9826b7e`; owns `lib/VetraVulkan/probe/` only.
Coordinator reviews evidence and packaging proposals before R010 or approval.

First submission `713543b` is not approved. Coordinator reproduced offscreen
and compute readbacks on Linux NVIDIA, but found incorrect validation severity
masks (errors/warnings silently omitted), an uncommitted Manifest, an unrooted
feature-query pNext chain in the pinned wrapper, and unsupported minimum-feature
claims. Bounded corrections are assigned to the same writer; exact findings and
independent evidence are in `docs/HANDOFF.md`. Other OS execution remains open.

- Start from the [reviewed research corrections](../docs/CANVAS_RESEARCH.md),
  not the superseded initial report's compiler/loader/platform conclusions.
- Pin a reproducible Vulkan.jl version/revision and Julia version. Verify
  package compat, loader/ICD discovery, required Vulkan API/features, validation
  layers, shader compilation and SPIR-V validation tooling.
- Run instance/device/queue discovery, create a small offscreen RGBA target,
  upload/clear/execute, synchronize and compare a readback to hand-derived pixels.
- Check Linux/Windows; investigate macOS MoltenVK portability requirements and
  FreeBSD loader/JLL availability. A package listing is not execution evidence.
- Demonstrate the smallest maintained Julia-authored shader route compatible
  with the pinned wrapper, including compilation and SPIR-V validation. The
  repository keeps rendering algorithms in Julia; an incompatible compiler is
  an explicit design blocker, not permission to silently change that policy.
  Do not assume arbitrary Julia CPU functions become SPIR-V.
- Evaluate pinned SPIRV.jl and its actual shader stages/Julia/Vulkan compatibility;
  its inspected Vulkan `0.6` compat does not permit `0.7` without review. OpenCL
  `Kernel` output from LLVM translators is not a Vulkan compute proof. Validate
  emitted shaders with the explicit Vulkan `--target-env`, execute them and
  independently verify results before selecting the compiler/raster pipeline.
- Compare a declared-compatible pinned stack against any locally patched 0.7
  candidate; matching symbol names do not prove compatibility. Record patches
  and successful execution before approving a compat change or package minimum.
  Exercise runtime buffer inputs/branches/loops that cannot all constant-fold;
  validate and execute each stage used by the selected raster path.
- Separate upstream execution-harness requirements from actual Vetra shader
  requirements (especially Float64/Int64, BDA and variable pointers). Investigate
  the upstream Bool/validation-layer comment with layers enabled; do not inherit
  disabled validation or call software-driver lanes guaranteed hardware support.
- Distinguish upstream precompile device requirements from Vetra's chosen runtime
  profile. Verify System versus artifact loader selection and the preference/load
  path that keeps optional-provider installation/initialization device-free.
- **Acceptance:** tested version/feature matrix, exact probe commands/artifact
  checksums, native ownership/synchronization notes, packaging/shader decision,
  explicit blockers for missing devices/drivers. The CPU minimum stays 1.10.
- **Checks:** Vulkan validation output clean; known clear/readback exact;
  failed-device/unsupported-format paths return useful errors; no device leak.
  SPIR-V validation supplements runtime validation layers, never substitutes for
  them. Missing packaged FreeBSD ICD support blocks that CI route, not a claim
  that all FreeBSD system Vulkan is impossible; record those investigations separately.
- **Handoff:** R010 receives actual types/compat constraints, not guessed APIs.

### R010 — Freeze the frontend/backend contract

**Owner/paths:** coordinator + F; design/decision docs and proposed public API.

- Freeze constructors, drawing signatures, Canvas state, logical/physical size,
  path/paint coordinate spaces, transforms, clear/clip/layer semantics, pixel
  boundaries and compositing equations from the architecture document.
- Freeze the public backend extension protocol: required execution/lifecycle
  methods, optional readback/presentation, submission/readback/close behavior,
  command vocabulary/accessors, asset ownership and capability/error/fallback types.
- Document SOLID responsibilities/dependency direction and zero-core-change
  extension for renderers, codecs, array adapters, media and displays. Specify
  provider-owned dispatch types, explicit provider selection, namespaced
  capabilities, supported protocol versions and compatibility/deprecation rules.
  No mandatory central registration or core weak-dependency edit for new providers.
- Freeze Matrix/Vector/StaticArray pixel layouts, copy/borrow/writeback rules,
  array axes/strides, scalar/alpha conversion, typed snapshot destinations and
  explicit upload/readback. Processor switching creates a new concrete Canvas;
  distinguish pixel transfer from drawing-state transfer and Picture replay.
- Freeze headless text/bounds queries, reusable recording placement, logical/
  device mapping and resize/DPI/host-scheduling rules for GUI/plotting embedding.
  Specify sufficient-precision world→local conversion before Float32 paths,
  public hit tests/inverse mapping, and conservative bounds/invalidation limits.
  Hosts own scene/widget/plot models, event loops and nonlinear data mappings.
- Set package boundaries based on R040, optional dependency activation and
  compatibility policy. Document legacy Context/Picture migration explicitly.
- Inventory full-2D requirements: filled/painted strokes, winding/curves/arcs,
  dash phase/caps/joins, hit tests, image regions/sampling, gradients/patterns,
  Porter–Duff + artistic blends, masks/layers, effects, text and layout.
- **Acceptance:** examples for CPU, Vulkan, browser and PDF invoke the same
  drawing function; no target-specific fields in that function. Each feature
  has a semantic rule, planned owner and conformance identifier.
- SVG, codec/image-file and Jupyter semantics are assigned explicitly to
  R063/R060/R070; their contracts derive from the shared drawing/pixel profiles
  and their distinct export/display boundaries, covering every first-tier row.
- R022/R023 own array targets and CPU/GPU transfers; R064 freezes temporal
  metadata/provider details against this pixel boundary before media implementation.
- **Checks:** coordinator and one independent reviewer trace edge cases through
  all four destinations; resolve disagreements before downstream implementation.
  Review an external-package implementation sketch for every extension surface;
  R013 later proves the executable contracts without relying on private fields.

### R011 — Conformance corpus and capability accounting

**Owner/paths:** Q; `test/conformance/`, proposed `lib/VetraTestSupport/`, fixture
metadata and comparison tools.

- Define independent scenes for fractional/negative geometry, degenerate paths,
  holes/self-intersections, nonuniform transforms, stroke joins/dashes, clip
  intersections, isolated groups, transparent pixels, gradients, resampling,
  image subrects, text, effects and destination-dependent blends.
- Keep legacy byte-exact fixtures. Add hand-derived Canvas cases for deliberate
  semantic corrections. Label external reference version/license/provenance.
- Define interior/edge masks, numeric comparisons, justified per-feature
  tolerance bounds and golden approval before implementation output is examined.
- Publish capability manifests with native/lowered/fallback/unsupported status
  per feature and backend; unsupported cases are explicit test outcomes, not
  silently skipped successes. Include resource-limit and invalid-input cases.
- Make conformance helpers reusable by third-party packages through a documented
  importable companion test-support module (`lib/VetraTestSupport/`), with minimal
  fixtures and provider-supplied factories. Consumers must not include private
  files from Vetra's `test/` tree; core does not acquire a runtime Test dependency.
- **Acceptance:** independent expected results and reproducible comparison
  harness. Failing examples retain useful diff images and first-mismatch
  diagnostics. The command-order spy belongs to R021, after commands exist.
- **Checks:** verify fixture hashes; ensure modifying a scene/expected result
  requires reviewed provenance; test error reporting with a deliberately wrong
  test image, not a mutated production implementation.

### R012 — Shared typography and layout

**Owner/paths:** F typography specialist; font/layout/shaping files and tests.

- First close M004 HarfBuzz cache/lifetime/language-binding defects. Define
  reusable positioned glyph runs/assets with glyph IDs, clusters, advances,
  offsets, baselines and font identity independent of the target renderer.
- Expose reusable headless measurement with advances, ink/line bounds and
  baseline/cluster information that matches actual glyph placement. No device
  initialization or pixel readback is required to lay out widgets or chart labels.
- Make complex LTR as well as RTL shaping engagement correct; specify fallback,
  wrapping, alignment, line breaking, ellipsis and missing-glyph behavior.
- Replace claims of general bidi/grapheme support with a pinned tested Unicode
  contract; implement the required UAX#9/UAX#29 cases and run their conformance
  data before claiming conformance. Preserve scoped limits where not promised.
- Specify supported native font containers/outlines and a feature matrix for
  CFF/TTC/color fonts; each unsupported format must fail clearly rather than
  render a misleading placeholder. New format support gets separately bounded
  subtasks if required by the frozen first-tier typography profile.
- **Acceptance:** portable glyph-outline layout reproducible across backends,
  no font/FFI leaks under repeated creation/GC, pinned shaper/reference agreement,
  truthful advertised Unicode/font scope. Native-browser text stays a separate mode.
- **Checks:** focused malformed-font/layout tests; full Julia gate; Unicode and
  shaper corpora; repeated shaping allocations/native lifetime; 1.10 core loading.

### R013 — Zero-core-change external extension conformance

**Owner/paths:** Q; `test/conformance/` external-package fixtures and reusable
contract suite. Coordinator integrates any interface fixes; providers own theirs.

- Build isolated test-only packages against published extension APIs: a small
  real renderer for a declared profile, a codec, a custom pixel-storage adapter,
  a frame reader/writer and a display adapter. They must perform actual pixel/IO
  work and exercise errors/lifecycle; spies alone do not establish extensibility.
- Install/select those packages without editing Vetra source, exports, project
  metadata, discovery lists or existing drawing/editing pipelines. Consumers
  change only construction/configuration of the selected provider.
- Prove substitution for the declared common profile, optional-capability errors,
  public command/asset access, custom layout ownership, temporal metadata and
  close/abort. Verify new high-level drawing helpers lower to existing primitives.
- Load two independent providers together and in both load orders; inspect
  ambiguities, type piracy, dependency isolation and incompatible-version errors.
  A display adapter owns its view type rather than overriding another package's
  `show` methods. Core precompile/load must not create device/codec sessions.
- **Acceptance:** same unchanged drawing/frame pipeline works through external
  providers; a generic external format needs no built-in extension/sniff table
  entry. Core tree/Project hashes match before and after. No private Vetra fields
  or undocumented functions are required; all supported profiles pass the common
  conformance suite. Test packages are fixtures, not public placeholder backends.
- **Checks:** fresh-process isolated environments, supported Julia/core versions,
  core-only load, negative/version/capability/ownership cases and coarse-boundary
  inference/allocation checks. Any required core edit exposes an interface gap:
  fix the contract and rerun before approval. R090 repeats at release revision.

### R014 — External GUI and plotting integration proofs

**Owner/paths:** Q; proposed `test/integration_consumers/` and small runnable
examples. Backend owners fix their implementations; coordinator integrates any
public-contract changes. These are consumers, not new GUI/plotting frameworks.

- Build a small external GUI-style host: caller-driven frame loop, text/image
  content, nested clips/transforms, scrolling, geometric hit tests, resize/DPI
  changes and repeated drawing using retained recordings/assets. Keep event
  routing/layout/focus in the host. Include headless execution and one demonstrated
  borrowed native surface/device path from R045, with correct synchronization.
- Build a plotting-style consumer from public paths, glyphs and image arrays:
  polylines, reusable markers, labels, clipped viewport and heatmap. The consumer
  owns axes/data mapping and preserves large-offset values before Float32
  narrowing. Reuse the scene for CPU/Vulkan/browser and PDF/SVG export.
- Exercise conservative invalidation: compare updated output against fresh full
  rendering after moved translucent content, changed text, clips and effects.
  Full redraw is valid; any advertised partial-update path must include old/new
  bounds, dependencies and halos. Test bounded asset reuse across many frames.
- **Acceptance:** both consumers use only public APIs and leave core unchanged;
  backend changes require construction/configuration only. Text measurement
  matches placement, high-DPI input mapping/hit tests agree, offscreen operation
  works without a window, and borrowed resources remain host-owned on close.
  State exactly which host/platform sharing integrations were exercised.
- **Checks:** independently derived coordinate/clip cases, `10^12 + (0:10)`
  viewport precision, large integer-origin mapping, baseline/ink bounds, resize/
  minimized-window/close ordering, repeated-frame allocations and transfer counts,
  full-versus-update image comparisons, browser and independent PDF/SVG readers.
  Feed R081/R082 workload data; missing native sharing evidence stays blocked.

### R020 — Owned command/asset model and Picture migration

**Owner/paths:** F; command/asset modules and recording adapter tests.

- Implement the frozen command types, sealed batch, resource snapshots, balanced
  layer validation and deterministic ordering. Reuse existing Path/Paint kernels.
- Publish supported command/asset traversal accessors for external backends;
  preserve freedom to change storage without requiring provider rewrites.
- Support reusable recording placement and public conservative bounds/space
  metadata, explicitly marking unknown or destination-dependent bounds. Bounds
  include stroke/effect expansion and do not imply every group can redraw alone.
- Make finished recordings own their resources; reject post-finish edits via
  supported APIs. Reuse captured immutable images/glyph assets without copying
  the full image for every reference. Do not serialize pointers or callbacks.
- Translate existing Pictures explicitly, retaining legacy replay behavior where
  promised. Do not silently reinterpret legacy clip coordinates as new Canvas semantics.
- **Acceptance:** mutation-after-record tests, ownership/alias tests, invalid-ID
  and unbalanced-layer errors, same scene replayable on multiple backends.
- **Checks:** existing recording tests + new command contract tests, full gate;
  record/replay allocation baseline, large repeated-image scene memory accounting.

### R021 — Canvas frontend and lifecycle

**Owner/paths:** F; `src/canvas/` public frontend and tests.

- Implement parametric Canvas, shared state/paths/styles, validated drawing
  entry points and ordinary-number boundaries; no backend-specific branching.
- Bind provider-owned backend values through the public protocol; validate
  compatibility/capabilities without a closed backend whitelist.
- Implement flush/wait/snapshot/close routing, finite dimensions, device scale,
  explicit pending-state rules and capability preflight.
- Retain Context and legacy entry points through tested adapters. Add idiomatic
  Julia mutating names/docstrings without duplicate rendering kernels.
- **Acceptance:** the same drawing function produces identical normalized
  commands regardless of backend selection; save/restore snapshots all state;
  constructors/close/errors obey the frozen contract and core-only loading works.
- **Checks:** spy-backend tests, type inference at public boundaries, warmed
  allocations, dispatch ambiguity checks, full gate. No fake production renderer.

### R022 — Host array canvas targets and pixel import/export

**Owner/paths:** O; `src/arrays.jl`, color-matrix integration, `test/arrays/`;
CPU target/Canvas hooks and optional-extension metadata integrated by coordinator.

- Implement the R010 array boundary for pixel matrices, dimensioned pixel vectors
  and explicitly described raw channels. Support grayscale/RGB/RGBA, declared
  alpha/range conversion, logical axes and strided views without pointer guessing.
- External pixel types/layouts integrate through owned adapters and public
  conversion methods without adding branches to the built-in conversion kernels.
- Implement copied input and explicitly borrowed mutable CPU canvas targets;
  compatible layouts may alias, other layouts stage and finish writeback at
  `wait(flush!(canvas))`. Report staging; retain caller storage and reject unsafe
  overlapping/immutable destinations before modification.
- Support preallocated `snapshot!` and allocating typed output. Optional
  StaticArrays integration accepts immutable inputs/constructed outputs and
  mutable static destinations; fixed dimensions must match. Keep existing
  Image/ColorTypes APIs working and CPU core dependencies lightweight.
- **Acceptance:** draw into a caller's Matrix and Vector; with the optional
  StaticArrays integration installed/activated, also draw into mutable static
  arrays and import/export immutable ones. Core-only loading still works; requests
  through an unavailable optional-provider entry point give an install/activation
  hint. Export float storage without claiming extra render precision.
- Demonstrate a pinned test-environment PNGFiles consumer calling `PNGFiles.save`
  directly on exported ColorTypes matrices, then independently decode the PNG
  and compare to hand-derived pixels. This exercises an external library's array
  contract rather than just Vetra's own export→import roundtrip.
- **Checks:** hand-derived nonsquare patterns, `vec(matrix)` ordering, raw RGBA
  and premultiplication, zero alpha, grayscale, strided/offset-axis views,
  untouched surrounding pixels, alias lifetime/GC, invalid dimensions/overflow,
  static shape mismatch in the optional-provider lane; full Julia gate and
  allocation/copy measurements. Include R031–R034 operations on array targets
  when those implementations are integrated.

### R023 — GPU/host array transfers and processor switching

**Owner/paths:** G; Vulkan transfer integration and package-local array tests;
O's frozen array boundary is consumed without parallel edits.

- Upload Matrix/Vector/static-array pixels through the common conversion boundary,
  render on Vulkan and synchronously export into preallocated host destinations.
  Keep GPU targets resident across draws; no implicit host-mirror refresh.
- Validate shape/layout/alpha before copying, handle odd pitch and orientation,
  and retain staging buffers through submission completion. Reject ordinary host
  `copy=false` GPU targets rather than imply device/host shared storage.
- Demonstrate CPU→GPU→CPU raster continuation by explicit snapshot/import into
  new concrete canvases, plus Picture replay with the same drawing function.
  Document explicit shared-state copying versus a fresh state on pixel import.
- **Acceptance:** GPU drawing exports correctly into Matrix, Vector, a view and
  (with the optional integration) mutable/immutable static outputs; subsequent
  host edits require explicit upload to affect the device. Error paths obey the
  transfer/ownership contract; StaticArrays remains absent from core-only loading.
- **Checks:** independent simple geometry and pixel patterns, layout/alpha cases,
  staging reuse/fence lifetime, poisoned destination validation, software Vulkan
  and declared hardware lanes; record allocations, transfer count and bytes.

### R030 — CPU backend adapter

**Owner/paths:** C; CPU backend and targeted existing kernel integration.

- Execute normalized operations through existing scalar kernels, with shared
  lowering for geometry/text. Preserve direct Image workflows and layout.
- Apply new Canvas clip/clear/state semantics in the adapter without changing
  legacy Context outputs accidentally. Respect borrowed image ownership.
- **Acceptance:** all promised legacy scenes remain byte-exact; new Canvas
  adapter-supported semantic scenes match independent references; snapshot
  copies and flush order work; CPU headless core has no GPU/browser dependency.
  R031–R034 capabilities remain explicitly pending until their own gates pass.
- **Checks:** full test/coverage gate, 1.10+stable four-OS CI, conformance suite,
  direct-vs-Canvas timing/allocation baselines on unchanged workloads.

### R031 — Shared painted strokes, dash phase and stroke hit tests

**Owner/paths:** C; stroke/path geometry, CPU stroke lowering and conformance tests.

- Implement non-solid strokes through shared outline filling, dash offsets and
  stroke hit-testing, with cap/join/miter and nonuniform-transform semantics.
- Reuse this geometry across CPU/GPU/browser/export adapters. Preserve explicit
  degeneracy/invalid-dash behavior and avoid per-backend outline implementations.
- **Acceptance:** solid/gradient/image-painted strokes and hit tests match
  independent geometry, no paint silently disappears, legacy scenes stay exact.
- **Checks:** stroke corpus, invalid/odd dash arrays, high curvature and extreme
  miter cases, full gate and warmed path/stroke allocations. Unblocks R042.

### R032 — Composition, scoped clips/layers and clear

**Owner/paths:** C; composition/mask/layer kernels and CPU adapter; context edits
are coordinator-integrated.

- Implement the R010 Porter–Duff coefficient table and artistic blend contract,
  including zero alpha and destination-dependent cases.
- Complete transformed/scoped clip intersections, isolated group opacity,
  masks, clipped transparent clear and save/restore behavior.
- **Acceptance:** nested/translucent scenes match independent expected results;
  clear never paints white or escapes its clip; fallback scope is derivable
  from explicit group isolation, not guessed from one operation.
- **Checks:** numeric/composition corpus, clip/state snapshots, deep nesting and
  invalid group boundaries, full gate, temporary-buffer/allocation accounting.

### R033 — Paint/pattern transforms and image sampling

**Owner/paths:** C; paint/image-sampling kernels and adapter tests.

- Complete linear/radial/angular gradients, image/tiled paint transforms, source
  image subrectangles and explicit nearest/linear edge rules under Canvas state.
- Validate stops, singular paint transforms and dimensions according to R010;
  handle alpha/orientation without redundant full-image conversions.
- **Acceptance:** all required paint/image combinations work with the composed
  clip/blend pipeline; independent gradient/sampling cases and legacy fixtures pass.
- **Checks:** tile seams, negative/fractional positions, degenerate handles,
  nonsquare/one-pixel images, full gate and measured painted-fill allocations.

### R034 — Recordable effects and effect bounds

**Owner/paths:** C; blur/shadow/spread kernels, effect commands and CPU execution;
new command/schema fields require coordinator integration.

- Make blur/shadow/spread recordable with explicit radii, halo expansion, regions,
  edge padding, alpha and clip/group interactions. Reuse tested scalar kernels.
- Define the ownership of intermediate surfaces and avoid retaining full-size
  scratch images beyond their operation/submission.
- **Acceptance:** effect operations compose correctly with clips/layers/images;
  invalid radii/sizes/overflow fail before destination changes; the full frozen
  CPU 2D feature profile is now complete with truthful capability status.
- **Checks:** independent kernel/effect expectations, asymmetric regions, alpha
  extremes, full gate and peak temporary storage. Unblocks GPU/browser effects.

### R041 — Vulkan execution/resource foundation

**Owner/paths:** G; optional Vulkan package, resource and queue modules/tests.

- Implement device/queue/target selection from R040, explicit ownership,
  command allocation/submission, staging upload/readback and submission fences.
- Implement memory layout/row-pitch conversions, format checks, barriers and
  non-coherent memory flush/invalidation. No global device singleton requirement.
- Handle failed creation, invalid dimensions, device limits, timeout/device loss,
  pending close/resize and borrowed device ownership with clear errors.
- Specify external target acquisition/release synchronization and image-layout/
  queue-ownership transitions for the supported sharing seam; retain host-owned
  handles without destroying them. Reject unsupported sharing combinations.
- **Acceptance:** offscreen upload/clear/readback exact; repeated create/submit/
  close and concurrent independent canvases do not leak or free in-flight assets.
  Close with pending submissions waits for its own fences or reports failure
  while retaining ownership; finalizers never destroy an in-flight device.
- **Checks:** software Vulkan CI + validation layers; hardware smoke; resource
  stress, forced error paths and explicit download timing. The core package
  loads on CPU-only machines without GPU dependencies.

### R042 — Vulkan paths, coverage and strokes

**Owner/paths:** G; geometry upload, coverage shaders and GPU path tests.

- Initially reuse shared CPU flattening and stroke outlines; GPU performs actual
  coverage and raster work. Handle nonzero/even-odd winding, holes, intersections,
  degeneracy, negative/offscreen geometry and transformed strokes.
- Select and document an antialias method with independently justified error
  bounds. A triangle-only demo does not satisfy this task.
- **Acceptance:** the path/stroke corpus passes portable-profile comparisons;
  validation layers clean; no hidden CPU raster/upload fallback reported as GPU.
- **Checks:** exact simple interiors + independent fractional-area cases + edge
  bounds; stress edge counts/tile limits; GPU timestamps and transfer counts.

### R043 — Vulkan paints, images and composition

**Owner/paths:** G; paint/sampling/composition shaders and resource caching tests.

- Implement solid/linear/radial/angular paints, image/tiled paints, image regions,
  nearest/linear sampling, alpha boundaries and defined compositing operators.
- Use programmable composition when fixed-function blending cannot express the
  contract. Preserve ordering; ping-pong/temporary images have bounded lifetimes.
- Cache immutable assets/pipelines by correct device/version/format keys; never
  reuse stale pixels after an explicit resource update or mix device handles.
- **Acceptance:** entire paint/image/blend corpus passes with reported fidelity;
  steady repeated scenes stay GPU-resident with no unsolicited readback.
- **Checks:** alpha extremes, 1-pixel/odd-pitch images, tiled seams, gradient
  degeneracy, overdraw/order cases, cache invalidation and memory accounting.

### R044 — Vulkan clips, layers, effects and text

**Owner/paths:** G; mask/layer/filter/glyph execution modules and tests.

- Implement cumulative clips, isolated layers, opacity-once semantics, clear
  under clips, shared glyph-run rendering and stroke outlines.
- Implement separable blur/shadow/spread or the reviewed equivalent GPU kernels,
  with correct halo bounds, synchronization and temporary image reuse.
- Glyph coverage/atlas caches are device/scale/font-version aware; large glyphs,
  cache eviction, DPI changes and concurrent in-flight use stay correct.
- **Acceptance:** every required GPU 2D feature is native or an approved exact
  lowering; unsupported conditions fail preflight. Report any explicit fallback.
- **Checks:** combined layer/clip/text/filter scenes, glyph references, stress
  resize/eviction/reuse, validation layers and native/GPU memory stability.

### R045 — Vulkan presentation and optimization

**Owner/paths:** G; presentation module and measured shader/batching improvements.

- Keep offscreen rendering independent of window libraries. Add a narrow surface/
  swapchain integration for supported platforms with resize, recreation, image
  acquisition/presentation synchronization and minimized/zero-extent handling.
- Demonstrate integration under a caller-owned event loop and one supported
  borrowed surface/device adapter. Document thread affinity and host/provider
  resize/DPI responsibilities; no mandatory global window or frame scheduler.
- Profile before optimizing. Introduce tile bins, upload reuse, batching and
  pipeline caching only where R081 data identifies a bottleneck; preserve order.
- **Acceptance:** interactive presentation smoke on supported platforms; complete
  offscreen suite still green; measured gains with raw runs and transfer costs.
  Explicitly document where CPU is faster (small scenes/readback-heavy use).
- **Checks:** real GPU/driver runs, repeated resize/context loss, cold/warm
  shader costs, queue timestamps, p50/p95 frame time and peak resource accounting.

### R050 — Browser schema and transport

**Owner/paths:** W; browser protocol/serializer, schema and assets tests.

- Define a closed versioned schema for operations, numeric arrays, images and
  outline glyphs. Validate finite values, sizes, IDs, nesting and resource limits.
- Implement Julia serialization and JS decoding using a maintained serializer
  where appropriate; safely embed JSON/text and reject unknown command versions.
- Distinguish JSON escaping from HTML script raw-text/attribute/text escaping;
  test literal `</script>` and markup in labels. Preserve canonical Float32 values
  as JS numeric coordinates, not only Float32 decimal roundtrip on the Julia side.
  Preserve elliptical arcs or use a conformance-tested geometric lowering.
  Preserve signed sweep and distinguish zero-length arcs from full turns; native
  Canvas ellipse supports full circumference, while an endpoint-only encoding
  may need splitting. Include both cases and sweep directions in shared fixtures.
- Keep transport independent of an HTTP server: initial offline HTML payload,
  connected update messages and worker messages share one schema.
- **Acceptance:** encode/decode contract cases, adversarial text/IDs/dimensions,
  deterministic ordering, no executable-string serialization or pointer leakage.
- **Checks:** shared cross-language fixtures, JSON escaping/injection cases,
  malformed payload errors and payload-size/serialization benchmarks.

### R051 — Browser Canvas2D backend

**Owner/paths:** W; browser replay/runtime and offline HTML view.

- Map normalized paths, transforms, paints, images, clips, layers, composite
  operations and portable outline text onto browser Canvas 2D APIs.
- Apply new Canvas semantics rather than legacy clipping/clear quirks. Test
  affine gradient scalar fields (including shear/nonuniform scale), conic angles,
  source rectangles, dash phase and whole-destination copy/clear behavior with
  independent expectations; do not exclude difficult required scenes.
- Implement readiness/error reporting, asset decoding, correct ImageData alpha
  conversion, target size/DPR mapping and capability preflight.
- Implement acknowledged host readback for a connected Julia/browser transport,
  with frame identity, timeout, disposal and tainted-canvas errors. Offline HTML
  reports no Julia readback capability; it does not invent a return channel.
- Generate a standalone HTML view that executes the real replay runtime and
  renders without Julia/server access. No fake image-switching renderer demo.
- **Acceptance:** core portable corpus in Chromium, Firefox and WebKit;
  native-text differences explicitly labeled; fallback/missing-feature errors
  follow the same contract as the Julia adapter.
- **Checks:** Playwright pixel/geometry tests, save/restore/clip traces, resource
  loading errors, browser console errors, view disposal and repeated replay;
  separately exercise self-contained `file://` and HTTPS-hosted views.

### R052 — Browser completeness, workers and platform differences

**Owner/paths:** W; remaining native/equivalent lowerings, worker support/tests.

- Resolve every gap in the required browser profile, including paint/stroke
  combinations, group opacity, effects and resize. Feature-detect APIs rather
  than assuming Chromium behavior on all browsers.
- Add OffscreenCanvas/worker execution only for supported environments; a
  tested main-thread path remains available. Specify message backpressure,
  transfer/clone ownership, cancellation and context-loss recovery.
- Test default-browser capabilities, not preference-enabled claims. Worker-loss
  recovery respects transferred-canvas ownership and replaces nodes only through
  the declared adapter/host lifecycle; do not assume a canvas can be retransferred.
- Make unavailable offline features visibly unsupported or use supplied explicit
  fallback assets. Connected Julia fallback must be opt-in and reported.
- **Acceptance:** browser capability matrix is backed by three-engine tests;
  no required profile row is silently skipped; native mode and portable mode
  have separate typography claims. Required means the frozen portable-profile
  rows for that browser/runtime mode; a remaining required gap blocks release.
- **Checks:** worker/main parity, repeated resize/DPR, fonts-ready behavior,
  CORS/tainted-canvas readback errors, combined effects scenes and frame timing.

### R060 — Raster snapshots, codecs and Julia image interop

**Owner/paths:** O; snapshot/export routing, codec/interop boundaries and tests.

- Connect owned canonical snapshots to existing encoders and color-matrix APIs;
  all decoders produce the same target-independent asset contract. The CPU path
  is exercised here; device/browser/document pipeline legs live in their owning
  backend tasks and are re-verified together in R090.
- Expose provider-owned codec selection independently of built-in format sniffing;
  decode-only/encode-only external codecs need implement only their capability.
- Preserve codec options, format sniffing, alpha conversion, JPEG background,
  orientation, dimensions, malformed-input validation and optional-load errors.
- Publish current static read/write capabilities separately from planned sequence
  APIs; GIF encoding and animated WebP support belong to R065/R066. Preserve the
  static WebP animation guard and use the common array boundary from R022.
- **Acceptance:** every source format → canonical asset → CPU/snapshot-encoder
  pipeline works; lossless bytes and independently justified lossy checks pass. Unsupported
  readback/encoding is a useful error, never an empty file or silent alpha loss.
- **Checks:** nonsquare/transparent images, matrix views, odd GPU row pitch,
  fresh core-only/provider environments, all existing codec corpus tests.

### R061 — PDF backend and page/document lifetime

**Owner/paths:** O; PDF adapter and document tests, reusing `pdf_write.jl`.

- Add document/page ownership so each page Canvas accepts the common drawing
  function. Preserve vector geometry, images and outline text where supported.
- Define page units/dpi, IO/file ownership, empty/unfinished pages, finalization,
  repeat close and export errors. Preflight before output publication.
- **Acceptance:** valid multipage PDF, correct page boxes/transforms/order,
  explicit capability results and no partially overwritten destination on
  preflight/serialization failure; legacy single-page writer still works.
- **Checks:** two independent PDF readers, exact structural/xref checks,
  hand-derived page geometry, failed/closed IO and deterministic asset reuse.

### R062 — PDF feature completion and useful text

**Owner/paths:** O; PDF blend/mask/gradient/font output and integration tests.

- Implement reviewed vector mappings for the required gradient, blend, clipping
  and transparency features. Unsupported filters/clear operations use strict
  errors or explicit correctly scoped raster fallback, never dropped content.
- Add selectable/searchable text only with font subset/embedding, encoding and
  ToUnicode mappings that preserve glyph positions and extraction. Respect font
  embedding permissions; keep outlines available for deterministic rendering.
- **Acceptance:** feature matrix matches actual PDF output, independent renderers
  agree within justified bounds, text extraction matches logical text, fallback
  is reported and visually correct with destination-dependent operations.
- **Checks:** shaping/RTL clusters, missing glyphs, repeated fonts/pages, alpha
  gradients, mixed vector/raster groups, independent extraction and render tests.

### R063 — SVG target and import integration

**Owner/paths:** O; SVG backend adapter, existing reader/writer and tests.

- Adapt SVG writing to the common commands and asset model. Preserve vector
  geometry/text outlines, paint transforms, clips/layers and explicit fallback.
- Route supported SVG input through the existing parser → common drawing path;
  document unsupported SVG/CSS features rather than claiming full browser parity.
- **Acceptance:** legacy export tests remain valid; the shared drawing function
  exports usable SVG; invalid input and unsupported output name the feature.
- **Checks:** independent XML parse/browser render, viewBox/dimensions, asset
  references, transformed gradients/clips and no partial output on strict errors.

### R064 — Media provider spike and frame/timing contracts

**Owner/paths:** T; isolated provider probes, proposed `lib/VetraMedia/` contract;
coordinator approves dependency/format decisions and shared documentation.

- Verify opt-in provider versions/Julia compat and real decode/encode support
  for GIF, animated WebP and a specified MP4 codec/pixel-format profile. Probe
  VideoIO/FFmpeg/libwebp candidates from primary sources; do not assume a wrapper
  supports animation, VFR, alpha or every OS because the native tool can.
- Start from the reviewed media findings in `docs/CANVAS_RESEARCH.md`. Pin actual
  resolved packages, artifact hashes, upstream headers and build configuration.
  Resolve the inspected FFmpeg build's nonfree distribution constraint before
  selecting it; MP4 container, encoder and player support are separate checks.
- Probe WebP's separate demux/mux libraries, exported Internal constructors,
  ABI initialization/layout and matching frees; switching library handles alone
  does not repair inline-helper calls. Compare animation encoder and manual mux
  paths for display-frame semantics and resource bounds; retain the static guard.
- Probe VideoIO rational reader position, missing/final durations and VFR seek;
  exercise explicit-index writing, packet durations and final hold time together.
  Nominal framerate alone proves neither arbitrary VFR support nor impossibility.
- Freeze owned frame pixels, rational PTS/duration, normalized loops, composited
  frames, metadata policy, close/finish/abort, seek capability and timestamp selection.
  Define unknown/zero delays, cumulative timing quantization and explicit retiming.
- Freeze recording time injection: `draw!(canvas, i, t, dt)` receives 1-based
  frame index and rational requested time/duration in seconds, starting at zero;
  encode quantization is separate. Specify initial/retained canvas state and
  callback failure behavior explicitly, with no hidden wall-clock field.
- Keep provider construction/selection and reader/writer lifecycle public and
  versioned; frame pipelines depend on those contracts rather than a closed
  GIF/WebP/MP4 switch. External sequential readers need no seek implementation.
- Specify bounded raw-frame queues, provider buffering/spooling, IO seeking,
  file staging, dimensions, palette/alpha/color conversions and unsupported tracks.
- **Acceptance:** executable independent probe for each format, exact versions,
  source URLs, Linux/Windows/macOS/FreeBSD matrix with execution or named blockers;
  approved optional packaging, baseline MP4 codec and frame contracts.
- **Checks:** decode known multi-frame media, encode tiny distinct frames, inspect
  timing/loops and decoded pixels with independent tools; CPU core loads without
  providers. Runtime probes remain required even after documentation research.

### R065 — GIF/WebP/MP4 editable frame readers

**Owner/paths:** T; common frame model and format reader modules/tests.

- Implement closeable presentation-order readers yielding owned editable Image
  pixels and timing, convertible through R022 arrays. Resolve GIF/WebP disposal,
  offsets/blend and MP4 packet reordering before yielding displayed frames.
- Support streaming frame selection by index/time; optional accelerated seeking
  must decode forward from valid keyframe/compositor state. Retain source timing,
  loop/color information and report nonvideo tracks and metadata limits.
- Copy borrowed libwebp output before the next read/reset/close. The existing
  eager `Gif`/Float32 timing API is not a streaming reader; verify restore-previous
  and background disposal independently before reusing its compositor logic.
- **Acceptance:** all three formats can be opened, selected frames modified,
  and retained frames remain independent of later reads. No source modification
  or whole-video preload is required. Truncation is distinct from normal EOF.
- **Checks:** independently authored offset/disposal/alpha GIF/WebP fixtures,
  VFR/keyframe/reordered MP4 cases, sequential-versus-seek equivalence, EOF and
  truncated input, early close, repeated iteration and bounded raw-frame memory.

### R066 — GIF and animated WebP frame writers

**Owner/paths:** T animation writer; separate GIF/WebP writer modules/tests.

- Encode Image/array frames with durations, loop policy and alpha conversion.
  Implement declared GIF palette/dither/transparency policies and animation-safe
  WebP encoding; preserve visual display semantics without requiring source deltas.
- Quantize cumulative timestamps with reported limits; reject unrepresentable
  cadence unless caller selects retiming. Disclose global-palette spooling and
  compressed animation buffering; enforce configured resource bounds.
- Test the animation encoder's final timestamp and owned assembled-buffer cleanup
  if selected. Writers target declared IO/files; whole-output byte vectors are
  optional convenience output, not a mandatory provider finalization contract.
- **Acceptance:** one-frame and multi-frame outputs open in independent decoders;
  correct count/duration/loops/transparency, meaningful lossless/lossy guarantees,
  finalization exactly once and staged output preserving existing destinations.
- **Checks:** edit R065 fixtures then decode independently, palette extremes,
  partial transparency conversion, short delays, long timelines, empty output,
  failed writes/finalize/abort, non-seekable IO policy and bounded raw-frame memory.

### R067 — MP4 frame writer and timing/color conversion

**Owner/paths:** T video writer; MP4-specific module/tests, no R066 file overlap.

- Encode the R064 tested codec/profile, CFR recording with rational rates and
  VFR preservation where demonstrated; otherwise require explicit resampling.
- Define RGB↔YUV conversion, color/range tags, alpha matte, dimension alignment,
  timestamps/time base, encoder draining and muxer finalization. Report other
  tracks; require explicit drop policy when frame editing cannot preserve them.
- **Acceptance:** independently playable MP4, correct frame order/count and
  timing, declared precision/color loss, no silent alpha/cadence/track loss.
  Partial output is never published over an existing path on failure.
- **Checks:** ffprobe or equivalent independent timing/container inspection,
  independent decode of color charts, rational-rate/VFR timelines, odd sizes,
  transparent inputs, reordered frames, delayed encoder output, close/abort/IO
  failure and the declared provider/platform matrix.
  Check last-frame hold and container duration as well as PTS differences; qualify
  dimension support by pixel format (an odd-size YUV444 sample is not YUV420 proof).

### R068 — Edit, record and concatenate frame pipelines

**Owner/paths:** T; media pipeline helpers and CPU/GPU/browser integration tests;
W owns connected-browser transport fixes.

- Stream existing GIF/WebP/MP4 frames through a callback that can edit Image/
  Matrix/Vector pixels or draw on a selected CPU/Vulkan Canvas, then write output.
  Preserve source timing/loops by default where representable; require explicit
  policies for cross-format timing/color/alpha conversion and output looping.
- Implement frame-index/time selection, leave unselected display frames flowing
  through, and record via R064's explicit `draw!(canvas, i, t, dt)` callback,
  independent of runtime. Verify the exact callback index/time/duration sequence.
- Exercise a connected browser advertising readback: await the matching frame's
  acknowledged host snapshot before encoding. Test timeout/taint/disconnect and
  reject offline views as capture sources; no hosted encoder is implied.
- Append streams by rebasing segment time; normalize dimensions/matte/cadence
  only when selected. Preserve originals, safely stage same-path replacement,
  and propagate callback/decoder/encoder failures through deterministic cleanup.
- **Acceptance:** edit each input format and encode each supported output format;
  mixed-source concatenation and CPU/GPU recordings work with bounded queues.
  Connected-browser capture works through its declared capability. Array
  interoperability uses R022's pinned PNGFiles consumer and independent decode.
- **Checks:** overlay selected existing frames and compare untouched regions;
  timing/frame-order/loop checks, fractional-rate joins, seek selection, thrown
  callback, writer backpressure, unchanged source hashes and resource cleanup.

### R069 — Media conformance, lifecycle and performance

**Owner/paths:** T owns `test/media/`; Q integrates CI and benchmark harness edits.

- Run the decode→array/Canvas edit→encode and concatenate matrix for GIF/WebP/MP4
  with independent decoded-frame and container/timing checks. Use licensed,
  reproducible fixture provenance, not expected outputs generated by Vetra.
- Extend four-OS optional-provider CI and store capability/version evidence;
  missing providers or codecs explicitly block their support claims.
- Benchmark decode, pixel conversion, CPU/GPU edit, upload/readback, encode and
  finalization separately; record peak memory, queue depth, compressed buffering
  and spool disk usage for short and long sequences.
- **Acceptance:** R064's capability matrix has execution evidence, source files
  survive forced failures, timing drift stays within preapproved bounds and raw
  working memory is independent of sequence length at fixed queue settings.
- **Checks:** independent readers/ffprobe, full affected Julia gate, provider
  lifetime stress, core-only installation, repeated performance trials and
  long-sequence/failed-finalization tests. Feeds R082/R090, never self-approves.

### R070 — Jupyter display

**Owner/paths:** N; MIME/display methods, notebook fixtures and execution tests.

- Preserve core PNG/plain-text display and add browser HTML/vector representations
  with static fallbacks. Snapshot semantics, expensive GPU synchronization and
  provider requirements must be documented and tested.
- Include a static image/description inside HTML before interactive enhancement;
  a co-bundled PNG alone does not prove renderer selection. Test trusted/untrusted,
  saved/reopened and script-blocked states in pinned JupyterLab, and independently
  test any additional advertised frontend. SVG may require trust.
- Retain useful vector MIME where supported. Renderer-module unit tests may
  supplement but do not replace actual kernel/frontend trust and saved-output
  checks; inspect MIME selection in the tested frontend configuration.
- If media playback is advertised, test HTML video/poster/download behavior per
  declared frontend with a pinned prerecorded fixture; R099 verifies generated
  Vetra media once R069 is complete. No dependency on unfinished encoding is hidden here.
- Execute real IJulia notebooks displaying CPU, Vulkan-backed, browser and
  PDF/vector outputs; validate output MIME bundles and saved notebook reuse.
  The Vulkan software-driver lane provides baseline execution; real-device
  notebook evidence is additionally required for the hardware support claims in R090.
- **Acceptance:** normal notebook display requires no comm server; notebooks
  reopen with meaningful static results; missing optional packages fail clearly.
- **Checks:** nbclient/IJulia execution, MIME/image validity, HTML asset loading,
  repeated cell execution and no persistent leaked native/browser resources.

### R071 — Optional live notebook interaction

**Owner/paths:** N; IJulia integration and browser-message adapter.

- Connect bounded versioned updates to the R050/R052 runtime; coalesce obsolete
  frames, surface errors, and dispose views when cells rerun or kernels stop.
- Provide a small real interactive drawing example with parameter updates;
  widgets are integration examples, not a new GUI framework dependency in core.
- **Acceptance:** interactive updates execute the real backend, static MIME
  fallback still works, comm loss/close/restart is recoverable and leaks are bounded.
- **Checks:** real kernel + browser round trip, rapid update/backpressure test,
  error propagation, repeated attach/detach and exported-notebook behavior.

### R080 — CI matrix and evidence storage

**Owner/paths:** Q; workflows, CI scripts and environment manifests.

- Retain M002 Julia 1.10/stable Linux/Windows/macOS full tests/coverage and the
  genuine FreeBSD VM test/benchmark job. Add optional-package/load-order jobs.
- Add browser three-engine tests, PDF independent-reader checks, actual IJulia
  execution, docs builds, Vulkan software-driver correctness/validation layers.
- Provide optional array/StaticArrays load-order lanes and media-provider jobs;
  R069 supplies executable sequence tests as implementations become ready. Until
  then report `not ready (pending R065–R069)` explicitly, never an empty passing
  media suite; R090 requires actual execution of the promised media checks.
- Add a protected real-GPU runner lane for performance/driver evidence; untrusted
  PR code must not execute automatically on a privileged self-hosted GPU machine.
  No GPU runner available means that hardware gate is blocked, not passed.
- Separate CPU four-OS support from the probed Vulkan OS/device matrix; no claim
  of FreeBSD/MoltenVK GPU support without corresponding execution evidence.
- **Acceptance:** required jobs run, artifacts include images/diffs/runtime/device
  metadata/logs/timings, missing requirements fail visibly, timeouts are bounded.
- **Checks:** actionlint, deliberate failing fixture job in a safe test branch,
  actual remote jobs/artifacts, fresh environment reproduction and permissions review.

### R081 — Backend benchmark and profiling harness

**Owner/paths:** Q; `benchmark/backends/`, profiling instructions and raw results.

- Reuse current CPU workload baselines; add small/1080p/4K scenes for paths,
  strokes, gradients, images, text, layers, effects, repeated replay and exports.
- Start with synthetic GUI redraw and plotting polylines/markers/labels/heatmap
  scenes, reusable asset/Picture costs and pan/zoom updates. R014 later adds actual
  external-consumer cases to this harness for R082's integrated measurements.
- Separate cold package/shader compilation, first render, warm steady state,
  host submission, GPU execution, upload/readback, browser transport/presentation,
  and final encoding. Validate output before measuring.
- Include host Matrix/Vector/view/static conversions, staged versus direct CPU
  targets and GPU transfers. R069 extends this harness with decode/edit/encode,
  concatenation and raw/encoded buffering measurements after media exists.
- Use warmed function-scoped Julia allocations/inference/Profile, GPU timestamp
  queries with fence waits and timestampPeriod, browser frame/long-task metrics.
- GPU timings use timestamp writes and query availability, supported valid-bit
  widths and wrap handling. Track owned allocations explicitly; optional driver
  budget/profiling data is labeled separately from portable resource accounting.
- Record version/driver/device/CPU, dimensions, samples, cache state, transfer
  counts, memory accounting and raw runs. Shared-runner timings are smoke evidence.
- **Acceptance:** rerunnable harness and agreed baseline/budgets before tuning;
  no comparison of CPU submit time to GPU completion time or stale outputs.
- **Checks:** repeated trials, output invariants, startup-vs-steady separation,
  instrumentation sanity and reproductions on a dedicated reference machine.

### R082 — Measured end-to-end performance review

**Owner:** Q + backend owners; each owner edits only its backend after review.

- Profile actual bottlenecks; remove unexpected copies/allocations, stale caches,
  excessive submissions/readbacks and redundant geometry work. Fix one measured
  issue at a time and rerun correctness before comparing timings.
- Publish crossover points (CPU vs GPU), p50/p95 frame/latency, peak host/device
  storage, notebook/browser transport costs, PDF/codec costs and cold-start cost.
- **Acceptance:** agreed R081 budgets met or an explicit reviewed limitation;
  no blanket “GPU is faster” claim. No optimizations justified only by shorter
  code, one noisy sample, disabled bounds tests or weaker rendering tolerances.
- **Checks:** repeated before/after raw runs, complete affected conformance,
  native/device lifetime stress and CPU-core startup regression check.

### R086 — Cleanup, packaging and migration

**Owner:** coordinator; scoped cleanup patches may be delegated.

- Consolidate current numerical/backend/format contracts and user migration
  instructions; update contributor/agent instructions and package metadata.
- Remove obsolete completed port reports/duplicate planning documents only after
  their durable provenance, legal notices and relevant contracts have replacements.
- Keep source attribution, licensed test assets, independent oracle generation,
  maintained tests/benchmarks and this active roadmap. Do not delete unknown
  ignored user files or leave links into removed historical tasks.
- **Acceptance:** coherent maintained package tree, optional backend installation
  recipes work, no stale advertised feature/support claims, no broken links.
- **Checks:** clean install/load matrix, docs/reference link audit, full gates,
  license/provenance inventory, manifest/export/version compatibility review.

### R090 — Independent integrated approval gate

**Owner:** coordinator, with a fresh read-only reviewer.

- Re-run all first-tier capability suites at the same candidate revision. Review
  frontend independence, cross-backend semantics, error paths, FFI/GPU/browser
  lifetime, IO publication and optional dependency isolation.
- Repeat R013's external extension proof with an unchanged core and inspect SOLID
  responsibility/dependency boundaries; zero-core-change extension is a release
  criterion, not just a design description.
- Repeat R014's GUI/plotting consumer checks: host lifecycle, headless metrics,
  high-range data mapping, target sharing and raster/vector reuse. Claim readiness
  through the tested seams, not universal compatibility with every framework.
- Verify four-OS CPU CI, the declared Vulkan device/OS matrix, three-browser
  correctness, the codec read/write/animation matrix and source-format→asset→
  target pipelines, Matrix/Vector CPU/GPU interoperability and StaticArray
  interoperability in its installed optional-provider lane (plus core-only and
  missing-provider behavior), GIF/WebP/MP4 decode→edit→encode and concatenation,
  SVG import/export, PDFs in independent readers, real notebooks and performance data.
- Resolve review findings and rerun affected checks; capture commit/run URLs and
  exact commands. Missing hardware or provider coverage is a concrete blocker
  for that support claim, not a successful test.
- **Acceptance:** zero unresolved release-blocking findings; every promised
  feature has evidence and truthful fallback/profile documentation. Working
  tree clean, candidate committed/pushed, package registration still user-owned.

### R098 — Attractive README with real image examples

**Owner/paths:** D; `README.md`, reproducible asset generator, `docs/assets/readme/`.

- Explain practical uses: scientific plots/diagrams, image annotation and
  processing, dashboards/cards, interactive browser graphics, notebook workflows,
  GPU-heavy repeated scenes, array-based image processing, existing animation/
  video frame editing, frame recording/concatenation and vector/multipage reports.
- Add a concise tested installation/quick start, one shared drawing function
  demonstrated on multiple targets, optional backend requirements, truthful
  support/status table and prominent tutorial/API links.
- Generate a small visual gallery with the library itself: a dashboard/diagram,
  multilingual text/image composition and raster/vector or CPU/GPU/browser view.
  Keep checked-in README images compact, reproducible, licensed and accessible
  with descriptive alt text. Do not use synthetic promotional images as evidence.
- **Acceptance:** README works on GitHub before docs deployment, examples execute
  against the approved candidate, every image/link resolves, claims match R090.
- **Checks:** execute snippets in clean environments; regenerate/inspect images;
  local links and image dimensions/size, accessibility and installation commands.

### R099 — Final task: interactive tutorial published from CI

**Owner/paths:** D + coordinator; site sources/build, tutorial notebooks/assets,
Pages workflow integration through Q. This is the last task in this milestone.

- Build a coherent Julia-oriented site: start/install, Canvas mental model,
  paths/paint/composition, image IO/effects, text, CPU/GPU/browser/PDF/notebook
  recipes, capabilities, performance/profiling, API and migration/reference.
- Include an executed extension-author guide: an external provider/array adapter,
  supported public methods, capability/version declarations and the reusable
  conformance suite, with no edits to Vetra or consumer drawing functions.
- Add embedding recipes from R014: a host-driven GUI scene and a plotting adapter,
  separating consumer layout/events/data transforms from Vetra drawing and showing
  reusable recordings, text measurement, high-DPI mapping and vector export.
- Execute Julia examples/notebooks during build. Provide downloadable `.jl`
  and `.ipynb` sources with environment/version instructions.
- Include executed Matrix/Vector/StaticArray import/edit/export and GPU→host
  examples, plus existing GIF/WebP/MP4 frame editing, recording and concatenation.
  Publish generated animations/video with accessible playback controls and static
  posters; explain native Julia encoding versus browser playback. Show timing,
  alpha/track policies and a frame-selection before/after example.
- Verify media playback through actual HTML video/image views with posters and
  downloads; do not assume `video/mp4` is a default notebook MIME renderer. Keep
  independent pixel/geometry expectations alongside cross-renderer comparisons.
- Add real interactive Canvas2D lessons using the shipped browser runtime:
  transform/clip controls, paint/stroke settings, compositing/layer examples,
  image sampling and a rendering/latency view. Show matching Julia code, reset
  controls, keyboard/label support and static fallback images.
- Explain that GitHub Pages runs browser rendering, not native Vulkan/Julia.
  Vulkan examples run in the user's Julia environment; publish measured captures
  and commands with device metadata. No required paid service or hosted kernel.
- Configure CI build, executed-example checks, search/navigation and asset/link
  checks, upload/deploy using GitHub Pages permissions. PRs build/test but do not
  deploy untrusted content with deployment credentials.
- **Acceptance:** clean reproducible build, actual IJulia execution, Playwright
  interaction checks across the supported browser matrix, mobile/keyboard smoke,
  successful Pages deployment of the final revision and live URL verification.
  README links to the live tutorial and the library's actual rendered examples.
- **Coordinator approval:** inspect rendered examples/screenshots, interact with
  controls, fetch live routes/assets, verify deployment/run URLs and final clean
  Git state. Record limitations; do not claim universal bug-freedom.

## Required task handoff template

```text
Task / branch / base / implementation commits:
Owned files and shared-contract changes:
Behavior implemented and capability/profile status:
Independent expected values / reference versions:
Exact commands and actual outcomes (include failure → fix evidence):
Timings / allocations / transfers / device/browser metadata, where relevant:
Known limits and blockers:
Coordinator review findings and responses:
Approval: pending | approved at <revision> with <CI/run links>:
Next dependency-ready task and ownership release:
```

Every backend release claim must be traceable to this evidence. A plan,
compiling code, software-driver pass or screenshot alone is not proof of the
entire advertised feature/platform matrix.
