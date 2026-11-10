# Current handoff

## Latest request: Canvas architecture and parallel implementation plan

R000 is **done (approved 2026-11-10)**: `docs/CANVAS_DESIGN.md` and
`tasks/CANVAS_ROADMAP.md` define
renderer-independent Canvas, CPU/Vulkan.jl/browser/document execution, existing
codecs and Jupyter integration. Independent architecture/task-plan review has
passed; source review and final independent media consistency review are complete
with no blocking findings.
Coordinator owns these documents. Qwen's bounded M003 implementation in
`modernization/native-api` is now approved and integrated; no writer is currently
assigned. Future streams are gated by
R010's contract review. Final milestone task R099 publishes the real interactive
tutorial via GitHub Pages CI; R098 prepares the illustrated README.

User additions incorporated into the plan: GIF/WebP/MP4 existing-frame editing,
decode/encode/record/concatenate (R064–R069), and Matrix/Vector/StaticArray storage
independent of CPU/GPU execution (R022/R023). Array contracts cover copy/borrow,
views/layout/alpha, explicit GPU→host snapshot, immutable static output versus
mutable targets, and explicit processor changes. Media contracts cover composed
frames, timing/loops, selection/seeking, re-encoding, original-file preservation
and explicit handling of unsupported audio tracks.

Further user direction: SOLID and zero-core-change extension are explicit public
protocol requirements (§3.7), with R013 external-package conformance. Future GUI/
plotting-core adoption is specified in §3.8 and verified by R014 external consumer
prototypes. Contracts include headless text/bounds queries, host event-loop and
surface ownership, reusable recordings, conservative invalidation and high-range
world→local mapping before Float32 narrowing. There are now 43 task specs.

Media research was steered to include existing-frame editing. Independent plan
re-review returned **approved** after confirming every correction and independently
checking all 43 specs/98 edges. Coordinator applied findings 1–10: R013 writer dependency, explicit `(canvas, i, t, dt)`
recording callback, optional StaticArrays checks, CPU array-target invariants,
R070 drawn-GPU dependency, non-vacuous media CI status, connected-browser capture
ownership, a pinned PNGFiles consumer test, importable companion test support and
Q's integration-consumer paths. The remaining non-blocking R070 media-view note
now explicitly uses a pinned prerecorded fixture, with engine-generated media
integration in R099 after R069; it adds no premature encoder dependency.
Approval covers architecture/task documents only, not providers or execution.
Next: assign bounded M004 correctness work and the dependency-ready R040 spike
explicitly before starting them, with separate worktrees. M003's final candidate
is approved (evidence below); R010 now awaits R040. R099 remains the final task.

Vulkan source research is **reviewed for planning**, with coordinator qualifications
recorded in `docs/CANVAS_RESEARCH.md`: SPIRV.jl exists (experimental,
Julia 1.11 / Vulkan 0.6 declared compat), LLVM translator's OpenCL Kernel output
does not establish Vulkan compute compatibility, Vulkan 0.7 defaults to System
loader, and SPIR-V validation cannot replace runtime layers. FreeBSD Lavapipe-JLL
limitations are route-specific, not proof all system Vulkan is unavailable.
The corrected report was received; coordinator additionally checked pinned stage
exports, Vulkan extension, execution harness and CI definition. SPIRV.jl is the
first candidate to probe, not a finalized choice; neither a one-line compat fix,
the companion Julia minimum nor software/hardware platform support is established.
R040 now checks nonconstant device work, actual minimum features and the upstream
disabled-validation concern. Hardware evidence remains required. No runtime probe run.

Browser/notebook source research is also **reviewed for planning**. Independently
checked BCD/IJulia/JupyterLab sources are in `docs/CANVAS_RESEARCH.md`: Safari
filters are preference-gated, Firefox has the standard convertToBlob name as
well as an alias, current conic entries are unflagged, untrusted SVG is rejected
by the inspected JupyterLab renderer, and no default MP4 MIME factory was found.
The corrected report was received and incorporated with coordinator qualifications:
native Canvas can draw full turns (WHATWG steps checked), exact independent simple
pixel assertions remain, optional vector MIME is retained, and renderer-module
unit tests do not replace actual kernel/frontend checks. Mapping formulas remain
conformance-gated proposals. Plan amendments require a static fallback inside
HTML, trust/frontend tests, correct HTML/JSON escaping, new Canvas semantics and
independent affine/composition/numeric checks. No new browser/kernel execution
was performed.

Media source review is **complete for planning**, with the accepted subset and
rejected proposals recorded in `docs/CANVAS_RESEARCH.md`. Coordinator verified
exact libwebp upstream provenance and its exported Internal constructors/ABI
helpers, VideoIO rational reader position and explicit-index writer/duration
behavior, and FFmpeg artifact/source provenance. Limited Linux symbol/tool and
sample-metadata checks are explicitly separated from provider acceptance: no
resolved VideoIO environment, animation FFI lifecycle or four-OS media test ran.
The odd-size MP4 sample is YUV444; the VFR sample's stream duration differs from
the final frame end. Neither supports the report's broad timing/dimension claims.
The inspected FFmpeg build enables nonfree components; R064 owns distribution-
compatible provider/build selection. No dependencies were added. R064–R069 retain
streaming, explicit matte/retiming/track policies and staged-output contracts.
The final independent review approved these amendments and rechecked the
43-task/98-edge graph without shifting any implementation or ownership gate.

Latest architecture amendment checks passed: inline Python task/spec/DAG/release-closure
and local link validation found 43 matching tasks, 98 dependency edges, all tasks leading
to final R099, and 24 valid local links including the research record;
`git diff --check` passed. No Julia runtime
gate run for these documentation-only changes; provider/backend acceptance is
still unverified by this planning work.

Existing M005 docs, M006 cleanup and M007 final validation are folded into
R099/R086/R090; M003/M004 remain prerequisites. All proposed backend interfaces
must remain labeled as plans until implemented and validated.

## Active direction: Julia-native modernization

### M003 completed: review and validation (2026-11-10)

**Approved and integrated:** Qwen's final `0c88c91`, following three reviewed
correction rounds. Integration commits are `ae9faf6`, `5716ae2`, `bdf39a5` and
`901b9d7`; source, tests, examples and package metadata match the validated
candidate exactly. M004 is ready; registration remains user-owned.

Qwen submitted `c1ea06e` on `modernization/native-api`, based on `d2d44fa`.
**Initial candidate rejected.** Coordinator read the diff and connected methods,
then reproduced six correction groups: unchecked four-argument Image creation;
missing one-based axes validation before color-import kernels; incorrectly
classified/missing native mutators; missing current-path `fill!` on recordings;
separate `dot`/`normalize` exports still conflicting with LinearAlgebra; and
missing dimension/end/eachindex/linear-assignment methods on the Image interface.

A standard inner constructor using `new` worked under both Julia 1.13.3 and
1.10.13; the reported platform limitation does not justify a fourth Image field
or an unchecked constructor. Exact minimum-version probe (exit 0):

```sh
julia +1.10 --startup-file=no -e 'println(VERSION); struct ConstructorProbe; x::Int; function ConstructorProbe(x::Int); x > 0 || throw(ArgumentError("positive")); new(x); end; end; @assert ConstructorProbe(1).x == 1; println("inner constructor works");'
```

Other focused probes used the candidate's `--project=.` and the existing
`--project=/tmp/opencode/m002env` environment, with `pathof(Vetra)` verified.
Expressions and outcomes are recorded in the M003 task review. A safe zero-based
matrix wrapper entered `fromColors` and failed only after three element reads.
No expected fixtures were modified.

Numbered corrections were returned to the same Qwen writer, including regression
tests, corrected migration documentation, both Julia gates and remeasurement of
the reported +16-byte context allocations after restoring the three-field Image.
Subsequent corrections `e0d1ff8` and `62afa30` restore the validated three-field
constructor, shared LinearAlgebra bindings, correct mutator inventory, early
axes checks and row-major linear `eachindex`. Coordinator ran the exact `62afa30`
full gates in detached worktrees `/tmp/opencode/vetra-m003-coord-{113,110}`:

- `julia --startup-file=no --project=. scripts/check.jl`: exit 0,
  **95.84% (7734/8070)**, `/tmp/opencode/m003-coord-gate113.log`.
- `julia +1.10 --startup-file=no --project=. scripts/check.jl`: exit 0,
  **95.88% (7837/8174)**, `/tmp/opencode/m003-coord-gate110.log`.
- Focused `test/api_native_tests.jl`: **375/375** on both versions; logs
  `/tmp/opencode/m003-coord-focused{113,110}.log`.
- `python3 /tmp/opencode/m003-coord-loading.py`: all eight fresh-process
  version × core/provider × load-order combinations pass. Candidate paths were
  asserted; `JULIA_LOAD_PATH=@:@stdlib` excludes global provider leakage.
- Independent `/tmp/opencode/m003-coord-probes.jl`: **37 pass, 5 errors** on
  both versions. `axes(img,d)` is missing, so dimensional `begin`/`end` also fail;
  Qwen is adding that method and nonsquare read/write regressions. The other
  corrected groups passed, including rejection of offset axes before any reads.

Final correction `0c88c91` adds dimension-aware `axes` with nonsquare begin/end
read/write tests. Coordinator verified the diff and reran the exact final source:

| Check | Julia 1.13.3 | Julia 1.10.13 |
| --- | --- | --- |
| Full `scripts/check.jl` gate | exit 0; **95.84% (7735/8071)** | exit 0; **95.88% (7838/8175)** |
| Native API suite within the gate | **383/383** | **383/383** |
| Independent corrected-case probes | **42/42** | **42/42** |

Exact commands, run in the corresponding detached worktree:

```sh
julia --startup-file=no --project=. scripts/check.jl
julia +1.10 --startup-file=no --project=. scripts/check.jl
julia --startup-file=no --project=/tmp/opencode/m003-coord-env113 /tmp/opencode/m003-coord-probes.jl /tmp/opencode/vetra-m003-coord-113
julia +1.10 --startup-file=no --project=/tmp/opencode/m003-coord-env110 /tmp/opencode/m003-coord-probes.jl /tmp/opencode/vetra-m003-coord-110
```

Logs: `/tmp/opencode/m003-coord-final-gate{113,110}.log` and
`/tmp/opencode/m003-coord-final-probes{113,110}.log`. Full gates also exercise
all six optional providers after core-only precompilation. PyMuPDF interop was
skipped because the module is unavailable. Source/test/migration corrections
are Qwen's; shared evidence and integration are coordinator-owned.

Coordinator benchmark comparison used Linux Julia 1.13.3, the same resolved
provider versions, baseline `9d6bdc8` and final candidate `0c88c91`. Both
eight-workload output-checking smoke runs passed. In the respective worktrees:

```sh
VETRA_BENCH_SMOKE=1 julia --startup-file=no --project=/tmp/opencode/m003-coord-env-before -e 'using Vetra; @assert dirname(dirname(pathof(Vetra))) == pwd(); include("benchmark/run_benchmarks.jl")'
VETRA_BENCH_SMOKE=1 julia --startup-file=no --project=/tmp/opencode/m003-coord-env113 -e 'using Vetra; @assert dirname(dirname(pathof(Vetra))) == pwd(); include("benchmark/run_benchmarks.jl")'
```

| Workload | Before median ms | After median ms | Before bytes | After bytes |
| --- | ---: | ---: | ---: | ---: |
| fill_rects_1000 | 0.954 | 0.927 | 8515560 | 8515560 |
| stroke_lines_1000 | 26.750 | 28.755 | 22203640 | 22203640 |
| blur_128_r3 | 0.383 | 0.375 | 656800 | 656800 |
| shadow_128 | 0.406 | 0.423 | 1640760 | 1640760 |
| draw_10 | 0.235 | 0.357 | 1639120 | 1639120 |
| png_encode_256_x10 | 26.321 | 28.370 | 47522280 | 47511880 |
| png_decode_basic1_x10 | 2.915 | 2.892 | 13901360 | 13880560 |
| text_parse_layout_x100_measure_x20 | 1.273 | 1.283 | 10136080 | 10136080 |

Logs: `/tmp/opencode/m003-coord-bench-{before,after}.log`; TSVs in each
worktree's `benchmark/results/julia_2026-11-10_smoke.tsv`. No allocation total
increased: six match, PNG totals are slightly lower (the implementer's all-eight
equality was not reproduced). The earlier +16-byte fill/stroke regression is
gone. Shared-host five-sample timings are observations, not a speed claim:
draw's minimum stayed 0.232→0.231 ms despite the median variation. No kernel
optimization is inferred.

M003 remote validation is complete at `f8b2dfe`: [run 42913541720](https://github.com/skynet-core/Vetra.jl/actions/runs/42913541720)
passed **all 10 jobs**. Julia 1.10 and stable tests passed on Linux, Windows and
macOS; FreeBSD 14.3 / Julia 1.10.13 passed tests and benchmark smoke. All four
platform benchmark artifacts are present and unexpired. Coordinator verified
with `gh run watch 42913541720 --exit-status` (exit 0),
`gh run view 42913541720 --json conclusion,url,jobs` and
`gh api repos/skynet-core/Vetra.jl/actions/runs/42913541720/artifacts`.

2026-11-10: user requested independent Julia-native identity/API, obsolete
port-document cleanup, rewritten interactive GitHub Pages documentation, and
working Linux/Windows/macOS/FreeBSD tests and benchmarks. Follow
`tasks/MODERNIZATION.md` M001–M007 in order. GPT-6 Astra validates; Qwen3.8
implements. M001–M003 are complete; M004 correctness work is ready.
Baseline `415c7a0` was clean and already pushed. Existing remote CI fails;
Pages workflow hosting is enabled but there is no deployment yet.
M002 implementation and review fixes are integrated (`95185c3`, `8bfd7ae`).
Coordinator full gates now pass concurrently on Julia 1.13.3 (95.82%) and
1.10.13 (95.86%), after fixing a shared Chromium fixture directory. Benchmark
smoke passes. Qwen's sole implementation worktree is now `julia-native-api`
(branch `modernization/native-api`); old M002 worktree is validation-only.
Remote run 42809642886 passed all six Linux/Windows/macOS tests and three
benchmark jobs. FreeBSD booted/installed Julia, then failed for missing Git;
VM preparation is fixed; run 42811680553 passed all 10 jobs, including FreeBSD's
full test/coverage gate (95.32%) and benchmark smoke. Four OS-specific benchmark
artifacts are present. M002 acceptance is satisfied at revision `d2d44fa`.
Keep registration user-owned. Preserve licenses, attribution, regression
fixtures and test/benchmark/docs infrastructure during cleanup.

The historical handoff below is evidence to consolidate, not the active plan.

Updated: 2026-11-10

## State

T000–T022 are complete. The adoption milestone (T014–T018, D024–D026)
finished on 2026-11-07: friendly numeric arguments, opt-in ColorTypes
interop, native notebook display, docs/gallery/cookbook, and a verified
0.1.0 release candidate (nothing published). T020 established the
application performance baselines (`benchmark/app_benchmarks.jl` +
`benchmark/startup_benchmarks.jl`, three sequential runs with raw TSVs,
machine meta, and representative PNGs). T021 then cut startup and
first-render latency (D028): lazy codec discovery (`__init__` no longer
requires the optional packages — `using Vetra` in a codec-enabled env went
~580 ms -> ~20 ms), `invokelatest` at the lazy-require boundary (world-age
safety), and 16 precompile entry points (first render ~2.5 s -> ~30 ms).
Cost moved to the reported install stage: precompile+load 1.7 s -> 3.8 s,
cache .so 2.4 MB -> 6.2 MB. T022 cut repeated-render allocations (D029):
non-solid gradient fills (linear/radial/angular) replaced the 2-buffer
mask+fillImg pipeline with a fused single-buffer path — one call-owned row
scratch (4*width bytes) through geometry sampling, `_cutRowOut!`
(applyOpacity+MaskBlend arithmetic), and `_blendRowInto!` (blendRect's
exact per-pixel branches); ImagePaint/TiledImagePaint unchanged. Byte-exact
against a 4204-scene A/B corpus of the original pipeline. Draw allocation
vs T020 targets: 25->17 MB @1080p, 96->64 MB @4K, 173->131 MB
@clip_layers; wall time neutral overall with one recorded canvas_4k +5%
regression. PNG encode allocation deferred as codec-bound (23.8 MB @1080p
= 7.9 MB staging + ~15.8 MB PNGFiles/libpng internals + payload; the
toStraightAlpha boundary pass is already at the no-aliasing 1-buffer
minimum). T023 settled the recording contract (D030, docs/RECORDING.md):
design only — a kernel-level display list recorded by a one-shot
`PictureRecorder`/`RecordingContext`, deep snapshots at the record boundary
(text lowered to glyph outlines), vector-space replay scaling, fail-fast
record-boundary errors, and strict v1 SVG/PDF export matrices with a
documented whole-picture raster fallback. T024 implemented it
(`src/recordings.jl` + 5 exports + `drawPicture`): record/replay is
byte-identical to direct CPU drawing on 11 contract scenes, scaling is
vector (area-justified coverage, not a raster enlargement), snapshots
survive source mutation, and record-boundary errors fail fast. T025 added
SVG export (`src/formats/svg_write.jl` + `writeSvg`): strict pre-scan with
named errors and no partial file, exact gradient mapping via
`gradientTransform` (linear: raw canvas handles + T^-1; radial: unit circle
+ T^-1·M, the raster ellipse map), clipPaths per group scope, group-unit
opacity, base64-PNG data-URI images (opt-in PNGFiles), and a documented
whole-picture `rasterFallback`. Verified byte-exactly against hand-derived
documents, independently with XML, read back through the pinned SVG reader
(byte-identical for the supported shape), and rendered in headless
Chromium 156.0.8078.47 with exact geometry checks. T026 added PDF export
(`src/formats/pdf_write.jl` + `writePdf`): single-page PDF 1.4,
scale-independent via `dpi` (page = picture size × 72/dpi pt), strict
pre-scan with named errors and no partial file, gradients as PDF
shadings (linear: repelled element-space handles; radial: CTM exactly
the raster ellipse map, path in M^-1∘T space; stops as FunctionType-3
stitching — the spec defines no constant function type), `W n` clip
before `sh` (shading paints the whole clipped user space, ISO Table
76), group-unit alpha via isolated Form XObjects + `/ca` ExtGState at
`Do` time (pinned empirically against both verifiers), raw uncompressed
RGB + SMask images, glyph outline text, arcs flattened via the pinned
`endpointToCenterArcParams`, quadratics as exact cubic equivalents (PDF
has no quadratic path operator), and a documented whole-picture
`rasterFallback`; the SVG arc x-axis rotation emission was fixed to
degrees verbatim along the way. Verified with hand-derived geometry
under gs 10.06.0 + poppler/pdftoppm 26.01.0. Full gate:
**95.83% coverage (7603/7934)** (T029). No ready rows: T019 awaits an
explicit publication request (user-owned — the user registers the
package directly). T013–T032
are committed and pushed to origin main (protocol: commit+push after each
task); the package is unregistered (General `P/Vetra` = 404, re-checked
2026-11-07).

## Changes

- Planned adoption work, notebook/image interoperability, documentation/recipes,
  release preparation and registration, application benchmarks, performance,
  recording/replay, SVG/PDF export, typography/shaping, and JPEG/WebP codecs.
- Each task defines scope, likely touchpoints, acceptance criteria, validation,
  and handoff requirements. Design prerequisites gate advanced implementation;
  GPU rendering and widget frameworks remain deferred.
### Prior completed work (T013 and tutorial)

- Added [GETTING_STARTED.md](GETTING_STARTED.md), a basics-to-advanced Markdown
  guide with 13 runnable blocks, exercises, expected outputs, and troubleshooting.
- Removed committed allocation traces and obsolete scaffold documentation;
  ignored process-suffixed allocation output and removed stale generated traces.
- Simplified PNG encoding by sharing `toStraightAlpha`, retaining its opaque
  fast path. Removed an unused XML wrapper and a duplicate export.
- Consolidated API, architecture, task board, and current handoff documentation.
  Historical acceptance evidence remains in task records and decisions.

## Verification

Roadmap planning: local file links passed in 53 Markdown documents; all 19 new
specs have acceptance/validation/handoff sections and matching prerequisites.
The dependency graph is acyclic, all eight ready tasks have completed
prerequisites, decision IDs are unique, and `git diff --check` passed.
No source/runtime changes; the results below are prior implementation evidence,
not new runs for this documentation edit.

- Extracted all 13 guide blocks to
  `/tmp/opencode/vetra-getting-started.jl` and ran
  `julia --startup-file=no --project=docs /tmp/opencode/vetra-getting-started.jl`.
  All assertions passed on Julia 1.13.3 before and after cleanup; card,
  curves/holes, blending, and SVG outputs were visually inspected.
- `julia --startup-file=no --project=. scripts/check.jl` passed:
  **811,409 assertions**, **97.94% coverage (5331/5443)** with fresh coverage
  output. Log: `/tmp/opencode/cleanup-check.log`.
- `julia --startup-file=no --project=docs docs/make_tutorial.jl` passed:
  both Markdown and notebook executed. README profiling example also ran and
  collected samples; the old claim that sampling was unusable is superseded.
- Local Markdown file links checked in 33 documents; public exports unchanged
  (276 names); `git diff --check` passed. Fixtures are unchanged.
- Benchmark before/after logs: `/tmp/opencode/cleanup-benchmark-{before,after}.log`.
  PNG encode workload median 23.906 → 24.702 ms, identical allocation total;
  these single-run measurements are a regression check, not a new speed claim.

## Working commands

From the repository root:

```sh
julia --startup-file=no --project=. scripts/fetch_upstream.jl
julia --startup-file=no --project=. scripts/check.jl
julia --startup-file=no --project=docs -e 'using Pkg; Pkg.develop(path="."); Pkg.instantiate()'
julia --startup-file=no --project=docs docs/make_tutorial.jl
julia --startup-file=no --project=docs docs/make_cookbook.jl
julia --startup-file=no --project=docs docs/cookbook.jl
julia --startup-file=no --project=docs benchmark/run_benchmarks.jl
```

Reference assets are under ignored `.reference/`; tests do not fetch them.
Tutorial and cookbook output (executed Markdown, notebooks, recipe PNGs, and
`docs/build/gallery.html`) go to ignored `docs/build/`; the OHLC project's
named exports go to ignored `artifacts/`; benchmark TSVs go to ignored
`benchmark/results/`. Optional codecs are discovered at runtime; install
them before loading Vetra, or restart Julia after installation.

## Next step and limits

No active implementation task. The roadmap is complete except T019
(registration/publication), which is user-owned — the user registers the
package directly ("no, I'll register myself"), so it needs an explicit
publication request. T029 (shaping/bidi) is done: option (b) of D031 §6
selected and recorded as D033 — an opt-in `HarfBuzz_jll` (harfbuzz
15.1.0) shaper behind a thin `ccall` surface (blob/face/font/buffer/
`hb_shape`), loaded lazily on first shaped call (core-only and
legacy-LTR installs never load it; a missing provider raises the
explicit `ErrorException("Shaping support is opt-in: ...")`). Public
API: `shapeText(tf, codepoints; script, direction, language)` →
per-cluster `Vector{Vector{ShapedGlyph}}`, additive `glyphPathByGid`
(GID → outline, no cmap; 0/out-of-range → `.notdef`), and
`ParagraphLayout.shaped` (logical → visual permutation). Engagement:
`RightToLeft` paragraphs and LTR paragraphs with strong-RTL content
shape (Arabic contextual joining, Devanagari conjuncts, Roboto `fi`
ligature, combining-mark cluster merge, L2E digit runs, mirrored
punctuation, `.notdef` missing-glyph policy); pure-LTR complex scripts
keep the T028 isolated-forms rendering (named v1 limit). Bidi is a
documented UAX#9 simplification; RTL placement follows harfbuzz's
cairo-bridge pen model. Reference: system libharfbuzz 12.3.2 via the C
driver `tools/oracle/hb_refshape.c`, 10 cases pinned in
`test/reference/shaping_reference.tsv` over the OFL
NotoSansArabic/NotoSansDevanagari fixtures (`test/fixtures/`) +
upstream-pinned Roboto; JLL 15.1.0 ≡ 12.3.2 on all 10 (probe log in
tasks/T029-unicode-shaping.md). Evidence: `test/shaping_tests.jl` (223
assertions), the codec-loading legs, cookbook recipe 15
(multilingual card). T029 also fixed the T028 vendored UAX#29 cluster
tables (a range misalignment had put base letters inside both
`_CLUSTER_EXTEND`/`_CLUSTER_MC`); they are regenerated codepoint-exact
from Unicode 16.0.0 (`tools/oracle/gen_cluster_tables.py`). T032 shipped the WebP half: `decodeWebP`/`decodeWebPDimensions`/
`encodeWebP` per the T030 contract (docs/JPEG_WEBP_CODECS.md §3, D032)
via the opt-in `WebP.jl` 0.1.3 + `libwebp_jll` 1.6.1+0 extra — success-
checked feature scan first (the provider's auto-decode ignores the
scan's return value), animation rejected with a named `ArgumentError`
**before** pixel decode (the provider decode crashes the process at C
level on animated input), always-RGBA encode with the 16383 dimension
bound (the provider silently returns 0 bytes at 16384), lossless
round-trips byte-exact in the premultiplied API, lossy validated by
dimensions + PSNR floor (≥ 35 dB at q75, measured 37.67). Decode
evidence: the 129-file pinned upstream libwebp corpus at the upstream
`test_webp.nim` dimensions (12 exact expectations) + corpus-wide
decode/alpha classification; the animation-error path uses the pinned
Wikimedia fixture (sha256 in its meta). Record: no independent WebP
pixel decoder on the machine (contract §3.5 limitation). D028 lazy
loading protocol extended to WebP (absent → install hint, present →
round-trip). T031 shipped the JPEG half before it: `encodeJPEG`
(contract §2) over the existing opt-in `JpegTurbo` dependency, with
mupdf 1.28.2 independent-reader interop (max channel delta ≤ 8,
measured 4) and the PSNR floor (measured 48.78 dB at q92) — plus a
latent world-age fix in `decodeJPEG` (first-use decode in a fresh
process now works).
Protocol (user, 2026-11-08): commit and push to `origin main` after each
completed task.
Planned features are not implemented capabilities; see
[Compatibility](COMPATIBILITY.md). Fresh installation on Julia 1.10,
cross-platform CI (Windows/macOS), and the ProfileView GUI were not rerun;
Pluto was not installed, so T016 verification used IJulia only. Historical
release evidence is in [T011](../tasks/T011-release.md),
[T012](../tasks/T012-optimization.md),
[T018](../tasks/T018-release-readiness.md), and
[DECISIONS.md](DECISIONS.md).

## Recent verification (T014–T032)

- T014 `test/numeric_api_tests.jl` (23 assertions, byte-for-byte Int-vs-Float32
  scene parity); T015 `test/colormatrices_tests.jl` (29) + core-only ColorTypes
  hint in `test/codec_loading_tests.jl`; T016 `test/notebook_display_tests.jl`
  (11) + a real IJulia/nbclient kernel run (execute_result mime keys
  `image/png` + `text/plain`, valid 191-byte PNG).
- Full gate after each: T014 811,432 / 97.98%, T015 811,461 / 97.99%,
  T016 811,472 / 97.97%. T017 is docs-only; gate re-run unchanged at
  811,472 / 97.97%. Log: `/tmp/opencode/t017-check.log`.
- T017: `make_cookbook.jl` executed end to end (COOKBOOK.md/.ipynb, 8 named
  PNGs, gallery.html); clean `rm -rf docs/build` rebuild reproduced all
  images; 0 broken relative links across README, INDEX, GETTING_STARTED,
  TUTORIAL, ROADMAP, build/cookbook/COOKBOOK.md, and gallery.html; all 8
  rendered recipes visually inspected.
- T018: fresh clean-depot installs (core-only and optional-integration)
  from a working-tree release candidate; full `scripts/check.jl` gate green
  in a clean environment (811,472 assertions, 97.97%); namespace check
  (279 exports; 6 intentional Base shadows); NOTICE updated; version 0.1.0
  loads clean. Logs: `/tmp/opencode/t018-{fresh-gate2,main-fresh}.log`.
- T020: `benchmark/app_benchmarks.jl` (27 workload/stage rows, 3
  sequential runs, invariants before timing, representative PNGs inspected)
  + `benchmark/startup_benchmarks.jl` (fresh-process protocol, 3 cached + 1
  cold-depot runs). Raw outputs in `benchmark/results/app_2026-11-07_r*.tsv`
  and `startup_2026-11-07.tsv`; baseline table and T021/T022 targets in
  `tasks/T020-application-benchmarks.md`.
- T021: before/after startup protocol
  (`benchmark/results/startup_2026-11-07_{before,after}.tsv`): cached load
  579–587 -> 19–20 ms, first render 2468–2548 -> 28–32 ms, warm 38–40 ->
  30–32 ms, cold-depot total 4328 -> 3877 ms. Reported install-stage cost:
  precompile+load 1.7 -> 3.8 s, cache .so 2.4 -> 6.2 MB. Fresh-process lazy
  codec proofs (encodePNG/parseSvg/readImage JPEG/toColors-fromColors, no
  preload) all pass. Steady-state app suite r4/r5 within r1–r3 spread. Gate
  811,472 assertions / 97.99% (5458/5570); logs
  `/tmp/opencode/t021-{gate3,app-r4,app-r5,startup-after}.log`.
- T022: fused single-buffer gradient fill (D029). Byte-exact 4204-scene A/B
  corpus (3 gradient kinds × linear horizontal/vertical/diagonal × 4 paths ×
  17 blend modes × 4 opacities × 3 backgrounds, plus image/tiled controls and
  globalAlpha layers) — the original 2-buffer pipeline vs the fused path,
  dumped as raw bytes, **4204/4204 identical**; the corpus caught two real
  regressions during development (alpha left uncut; horizontal double
  cut-out). Independent review (openai/gpt-6-astra, 2026-11-08): no
  must-fix pixel findings; three should-fix items implemented — finite
  stop-position validation before any destination write (preserves the
  old pipeline's all-or-nothing error contract; non-finite stops now
  throw a deliberate ArgumentError), tests pinning the horizontal
  double-cut regression plus mask-family/translucent/tie-neighbor gaps,
  and stale comment fixes. Full gate green: **98.01% coverage
  (5662/5777)**; 42-assertion hand-derived regression testset ("T022
  fused non-solid gradient fill").
  App suite r1–r5 (baseline) vs r12–r14 (fused), medians: draw allocation
  25→17 MB @1080p, 96→64 MB @4K, 173→131 MB @clip_layers; wall time neutral
  overall, canvas_4k/draw a consistent +12–15 ms (+5%) regression recorded
  as the cost. PNG encode allocation deferred as codec-bound (23.8 MB @1080p
  = 7.9 MB staging + ~15.8 MB PNGFiles/libpng internals + 10 KB payload;
  toStraightAlpha boundary pass already at the no-aliasing 1-buffer minimum).
  Logs: `/tmp/opencode/t022-gate4.log`,
  `/tmp/opencode/t022-app-r1{2,3,4}.log`; raw TSVs
  `benchmark/results/app_2026-11-07_r{12,13,14}.tsv`.
- T023: recording contract (D030). Design only — `docs/RECORDING.md`
  (kernel-level display list, `PictureRecorder`/`RecordingContext`, deep
  snapshots, vector-space replay scaling, strict v1 SVG/PDF export matrices
  + whole-picture rasterFallback, five canonical validation scenes and
  per-task references for T024–T026), the D030 decision entry, and the
  docs/API.md §Recordings proposal (marked specified-not-implemented).
  Contract walked through all five scenes; `git diff --check` clean; no
  source changes, so the T022 gate result stands (98.01%, 5662/5777).
  T024 unblocked; committed and pushed per the commit+publish-after-each-
  task protocol.
- T024: `src/recordings.jl` (op records, one-shot
  `PictureRecorder`/`RecordingContext` mirroring the `Context` drawing
  surface, `drawPicture` replay) + 5 exports + `test/recording_tests.jl`
  (38 assertions). Record/replay byte-parity vs direct CPU drawing on 11
  contract scenes (fills/strokes, gradients, transforms, clips,
  layers+globalAlpha, nested saveLayer-in-clip, drawImage incl. src/dst
  rect, text, clearRect, save/restore); vector-space scaling (2× and ½×)
  with area-justified coverage; snapshots survive source mutation;
  record-boundary errors (TiledImagePaint fill, non-solid strokeStyle,
  unmatched restore, finished recorder). Cookbook recipe 9 (record once /
  replay at 480×300 + 960×600) with both PNGs visually inspected; gallery
  rebuilt. Full gate green: **811,552 assertions, 98.13% (5939/6052)**.
  Benchmark (800×500 activity card): record 0.36 ms vs direct 2.3 ms;
  replay ×4 amortizes to ~1.1 ms/render; replay == direct byte-identical.
  Frozen-build quirk: do-block syntax mis-parses, so `_recWrap` call sites
  use explicit function literals.
- T025: `src/formats/svg_write.jl` + `writeSvg` export (D030 §6.1
  contract) + `test/svg_export_tests.jl` (333 assertions). Strict pre-scan
  (clearRect, angular/ImagePaint fills, non-Normal blends, degenerate /
  out-of-range / unsorted gradient stops, non-finite geometry,
  singular-transform gradients → named `ArgumentError`, no file written);
  exact gradient mapping via `gradientTransform` (linear: raw canvas
  handles + T^-1; radial: unit circle + T^-1·M, the raster's ellipse map —
  both proven affine-exact for every invertible T); `clipPath` per group
  scope (intersecting children), group-unit `opacity`, base64-PNG data-URI
  images (opt-in PNGFiles), whole-picture `rasterFallback`.
  Verification: byte-exact minimal document; exact `d` strings for all 19
  path command kinds; hand-derived `matrix(…)`/`gradientTransform` values;
  independent XML structural parse (all `url(#id)` refs resolve); pinned
  SVG reader read-back byte-identical to the replay (identity-transform
  scene); headless Chromium 156.0.8078.47 (snap; verifier tooling only,
  no resvg on this machine) render with exact rect/background/dash-body
  geometry and the justified ≤2-channel gradient sampling tolerance
  (Vetra samples at integer x, Chromium at pixel centers). Known renderer
  difference documented: interior dash-end caps (SVG spec vs pinned
  raster). Cookbook recipe 10 (record → replay → SVG) + 12-item gallery.
  Frozen-build quirks hit: `Base.base64encode`/`takebuf`/`popen`/
  `ignorestderr` are stripped (pinned `_base64Encode`/`IOBuffer.data`/
  string commands used), backtick concatenation mis-parses, and a shared
  counter reassigned from `pop!` restarted after a group close.
  Full gate green: **811,885 assertions, 98.28% (6241/6350)**.
- T026: `src/formats/pdf_write.jl` + `writePdf` export (D030 §6.2
  contract) + `test/pdf_export_tests.jl` (202 assertions, 10 testsets).
  Strict pre-scan (clearRect, angular/ImagePaint fills, non-Normal
  blends, even-odd gradient fills, degenerate / out-of-range /
  non-strictly-increasing / semi-transparent gradient stops, non-finite
  geometry, singular-transform gradients → named `ArgumentError`, no
  file written; pre-scan skipped under `rasterFallback`); gradients as
  PDF shadings — linear with repelled element-space handles
  (`d' = (|d|²/|Tᵀd|²)·Tᵀd`, `h'1 = T⁻¹h1 + α·d'`, exact for every
  invertible T), radial under the CTM exactly equal to the raster's
  ellipse map with the path emitted in `M^-1∘T` space; stops as
  FunctionType-3 stitchings of Type-2 segments (`Encode` required; the
  spec defines no constant type, so a single stop is Type-2 with
  C0 == C1 — numbering settled against ISO 32000-2 Table 38 + poppler
  26.01.0 `Function.cc` + mupdf 1.28.2 + gs empirically); `W n` clip
  before `sh` (`sh` paints the whole clipped user space, ISO Table 76 —
  confirmed in both renderers); group-unit alpha via isolated Form
  XObjects (`/Group /S /Transparency /I true`) + the group's `/ca`
  ExtGState in effect at `Do` time, pinned empirically against both
  verifiers on a hand-crafted constant-alpha case (overlap
  (191,127,191) gs / (190,127,191) poppler vs per-child
  (127,191,191)); raw uncompressed RGB + DeviceGray SMask images
  (`Do` maps the image to the unit square → CTM = imageMat·scale(w,h);
  FlateDecode deferred — no codec dependencies allowed); arcs flattened
  via the pinned `endpointToCenterArcParams` (k = (4/3)tan(d/4));
  quadratics as exact cubic equivalents (PDF has no quadratic path
  operator — the first emission used SVG's `q`, which gs/poppler/mupdf
  all silently ignore). Verification: self-consistent document
  structure (xref offsets, stream Lengths, trailer); hand-derived
  geometry at pixel centers under gs 10.06.0 + poppler/pdftoppm
  26.01.0 (verifier tooling only); dpi scale independence (96 vs 144,
  proportional pages, identical re-rasterizations); byte-exact image
  and rasterFallback streams; strict errors with no file written.
  Tolerances documented: radial shading ±10 (renderer-specific
  sub-pixel sampling offsets up to ~1 px; the spec does not pin shading
  sampling), stroke-band pixel checks use centers >=0.5 pt inside /
  >=1.5 pt outside (renderer antialiasing fuzz). Also fixed the SVG arc
  x-axis rotation emission (the path buffer stores degrees; the T025
  conversion ×180/π was wrong, uncaught because T025 tested rotation 0
  only). Cookbook recipe 11 (report graphic exported at 96/288 dpi, two
  named PDFs) + 13-item gallery; both PDFs render-verified. Frozen-build
  quirks hit: `position(io)` is 0-based (xref offsets need no +1),
  range slices with expression starts need parentheses
  (`v[a + n:(b)]` mis-parses), vector-pattern and regex
  `findfirst`/`findlast`/`findall` return the matched range (unwrap
  with `first`), `match`'s `offset` kwarg is stripped (walk suffixes),
  `SubString` has no `.length` field (use `length(s)`), `String*Int`
  needs `string`, and a `return` directly in a `@testset` body exits the
  enclosing testset's whole body (kept testset bodies
  `return`-free). Full gate green: **96.25% (6718/6980)** (coverage
  down from 98.28% because the new writer's relative-command branches —
  unreachable via the public path API, kept for parity with the SVG
  writer — are exercised only structurally).
- T027: paragraph layout and shaping contract (D031, `docs/TEXT_LAYOUT.md`;
  design only, no source changes — the T026 gate result stands).
  Investigated the 2026 package landscape: the General registry (full
  package-name sweep, 2026-11-09) has **no maintained Julia shaping
  provider** — `HarfKit.jl`/`Pango.jl` are delisted, `FreeType`/`Cairo`
  do not shape, JLL wrappers exist (`HarfBuzz_jll` v8.5.1+0) but a JLL
  alone is not an API; system `libharfbuzz` present but no CLI tools.
  Contract: **T028 core-only** (zero new dependencies) — additive
  `Paragraph`/`ParagraphLayout`/`fillParagraph` over the existing
  `Span`/`typeset` machinery (the existing `Font` already carries
  per-run style, `Typeface.fallbacks` already does recursive per-rune
  fallback — T028 adds box/overflow, paragraph line height, v1 wrap
  opportunities [white-space + explicit `\n`, no UAX#14 — recorded
  shortcut], `withFallback`, `.notdef`/zero-advance missing-glyph
  policy, metrics, vendored UAX#29-subset grapheme clusters [BMP,
  recorded provenance; per-codepoint fallback outside the subset]).
  **T029 specified but provider-gated**: shaper interface (raw font
  bytes + codepoints + script/language/direction → per-cluster
  GID/advance/offset), additive `glyphPathByGid` (GID → outline by
  direct loca/glyf index — pinned parser data sufficient; CFF/TTC stay
  unsupported under every option), UAX#9 paragraph-level base direction
  with logical→visual permutation exposed; options (a) re-emerged
  binding / (b) HarfBuzz_jll + thin `ccall` / (c) pure-Julia UAX#9 +
  GSUB-subset (needs an explicit D015 extension) / (d) defer recorded;
  **T029 blocked until one is chosen** (no provider preselected per the
  task spec). Test fonts: existing pinned fixtures for T028; new pinned
  OFL 1.1 Noto Sans Arabic + Devanagari for T029; shaping expectations
  from a pinned external reference (`hb-shape`/equivalent) or hand
  derivation — never the code under test; separate suites
  `test/paragraph_tests.jl` (T028) / `test/shaping_tests.jl` (T029).
  Seven worked examples traced in the doc (wrapped Latin, mixed-size
  runs, fallback, Arabic joining, Indic conjunct, mixed RTL/LTR,
  combining marks). API proposal in docs/API.md marked
  specified-not-implemented.
- T028: paragraph layout implemented (`src/formats/paragraph.jl` +
  `withFallback` in `src/formats/fonts.jl`; `test/paragraph_tests.jl`,
  22,760 assertions; cookbook recipe 12 `paragraph-card.png`).
  **Reuse confirmed in practice**: the layout pass is the pinned
  `typeset` (absolute `lineHeight` applied by copying each run's `Font`,
  alignment forced Left/Top on zero dimensions); the new code adds the
  box/overflow (Clip via a box-sized scratch blit so context
  transform/clip/globalAlpha/mask apply; Ellipsis drops trailing
  clusters — fewest first, re-laid-out per trial — until the last line
  with U+2026 fits, glyph-existence checked on the ellipsis span's
  effective font, plain clip otherwise), the cluster pass (vendored
  UAX#29 subset: BMP `Grapheme_Extend` + `Mc` tables, Unicode 16.0.0
  provenance; ZWJ joins both sides, ZWNJ left only, narrow Hangul
  `L V* T*`, GB3 control sequences; stdlib `Unicode.graphemes`
  deliberately not used — likely-cluster semantics differ and it is
  version-gated), line/metrics objects, and rendering. **Frozen-build
  String quirk hit and worked around**: `length(s)`/iteration are
  codepoint-based but `s[i]`/`s[a:b]` are byte-based with boundary
  checks — cluster indices are codepoints; `_charStarts` converts for
  slicing. `withFallback` does real cycle detection (a diamond DAG with
  shared descendants is allowed; a candidate reaching the base graph or
  an earlier candidate raises `ArgumentError`); `fallbackTypeface` is
  guaranteed to terminate. Contract amendments recorded in
  docs/TEXT_LAYOUT.md: NBSP is an ordinary wrap position (not no-wrap),
  long unbreakable runs split character-wise at overflow (the pinned
  engine behavior — a wrapping paragraph never overflows its box
  horizontally except dangling end-of-line SPACE), alignment is
  ineffective on zero dimensions, cluster indices are codepoints.
  Legacy `typeset`/render suites byte-unchanged. Large-paragraph timing:
  20,000 words @ 800 px — layout ~24 ms (pinned engine ~14 ms of it),
  fill ~1.14 s for 3.28 M ink px (shared glyph-fill cost, log
  `/tmp/opencode/t028-bench.jl`). Gate green: **96.29% (7013/7283)**.
- T030: JPEG/WebP codec contracts + provider decision
  (docs/JPEG_WEBP_CODECS.md, D032 amending D014; design only, no source
  changes — gate unchanged at **96.29% (7013/7283)**).
  **Providers verified in isolated scratch environments**
  (`/tmp/opencode/codecprobe`, commands + versions in the task record):
  JPEG encode = `JpegTurbo` 0.1.6 (JpegTurbo_jll 3.2.1+0; the existing
  opt-in decode dependency — zero new deps; `jpeg_encode` confirmed with
  quality/JFIF-header/density kwargs); WebP = `WebP.jl` 0.1.3 +
  `libwebp_jll` 1.6.1+0 (the registry's only WebP package, MIT, pushed
  2026-06-24, 18 platform artifacts; new opt-in extra for T032).
  **Contract decisions**: `encodeJPEG(image; quality=92,
  background=white)` — exact integer premultiplied→straight composite
  (`out8 = clamp((p8*255 + b8*(255-a8) + 127) div 255)`, no division by
  alpha), JFIF with **contract-mandated 72×72 dpi** (without it mupdf
  assumes 96 dpi and scales the page 0.75× — measured on all four
  header variants), quality 1..100, no EXIF/Adobe, dimension bound
  65500 (the provider segfaults at 65501 — bisected); `encodeWebP(image;
  lossy=true, quality=75)` always RGBA (lossless ignores quality —
  provider API), dimension bound 16383 (the provider silently returns
  an empty vector at 16384 — verified);
  WebP decode = feature scan first, **animation rejected with a named
  `ArgumentError` before pixel decode** (reproduced: `WebP.decode` on an
  animated file crashes the Julia process at C level — uncatchable),
  straight→premultiplied via the house formula. **Validation policy
  (lossy is never byte-exact)**: JPEG = hand-derived marker structure +
  PyMuPDF/mupdf 1.28.2 interop (page rect = SOF at 72 dpi; pixmap max
  channel delta ≤ 8, measured 4; PSNR floor, measured 48.78 dB at q92) +
  conversion worked examples; WebP = pinned Google gstatic gallery
  fixtures (lossy VP8 368×550, lossless VP8L 301×400) + Wikimedia
  animated fixture, all with URL + byte size + sha256, plus the
  round-trip exactness partition (lossless: alpha exact everywhere, RGB
  exact where α>0, unspecified where α=0 — measured 81/3072 mismatches,
  all in the α=0 corner). Recorded limitation: no independent WebP
  decoder on the verification machine (no ffmpeg/cwebp/dwebp/ImageMagick/
  PIL; mupdf refuses WebP) → WebP decode pixels are fixture-dimension-only
  assertions. **Test plan**: extend the D019 present/absent + shared-cache
  codec-loading protocol to WebP; RIFF+WEBP magic dispatch in
  `decodeImage`/`decodeImageDimensions`; `encodeBase64` stays PNG-only
  (upstream parity), `decodeBase64` gains WebP via the magic dispatch.
  T031/T032 unblocked; COMPATIBILITY/API rows updated to
  specified-not-implemented.
- T031: JPEG encoding implemented (`encodeJPEG` in
  `src/formats/jpeg.jl`; `encodeImage`/`writeFile` JpegFormat dispatch in
  `src/formats/io.jl`; export; `test/jpeg_encode_tests.jl`, 61
  assertions; cookbook recipe 13). Contract §2 in full: exact integer
  premultiplied→straight composite over `background` (default white;
  `out8 = clamp((p8*255 + b8*(255-a8) + 127) div 255)` — no division by
  alpha, so no undefined case), JFIF baseline with the contract's
  72×72 dpi density, quality 1..100 (default 92; out-of-range is a named
  `ArgumentError`, non-Int is a `TypeError`), dimension bound 65500
  (named error — bisected: the provider segfaults at 65501 in
  `jinit_compress_master`, uncatchable). The pixel loop runs in a
  Vetra-side kernel called via `Base.invokelatest` (D028 world-age
  safety, same pattern as `toColors`). **Latent bug found + fixed**:
  `decodeJPEG`'s inline `N0f8 → Float64` conversion hit the same
  world-age wall on a fresh process (first codec call = JPEG decode
  → `MethodError: Float64(::N0f8) ... method too new`); the conversion
  is now in a `_decodeJPEGPixels!` kernel under `invokelatest`
  (byte-identical output — T008 fixtures green). **Validation**:
  hand-derived marker walk (SOI, JFIF units=1 72×72, SOF0 via the
  existing native dimensions scan, EOI); mupdf 1.28.2 interop
  (conditional on `VETRA_MUPDF_PY`; page rect = 64×48 pt, 72-dpi pixmap
  = 64×48, max channel delta 4 ≤ 8); PSNR 48.78 dB at q92 ≥ 40 floor,
  q10 strictly worse; transparent → solid background exact
  (10,20,30); half-alpha §2.2 examples exact (255 over white, 128 over
  black); `encodeImage(JpegFormat) == encodeJPEG(img)` (deterministic);
  six writable extensions incl. `.jpg`/`.jpeg`; `encodeBase64` stays
  PNG-only while `decodeBase64` accepts a JPEG payload. **T008 dispatch
  tests updated** (JPEG out of the "unencodable" loop, into the
  writable list — the try/catch assertions were silently vanishing,
  dropping the suite count 796459 → 796456; restored with real
  assertions). Codec-loading protocol extended: absent environment →
  `encodeJPEG` raises the install hint; codec-enabled →
  `decodeJPEGDimensions(encodeJPEG(img)) == (2, 3)`. **Benchmark**
  (warm medians, log `/tmp/opencode/t031_bench.jl`): mandrill 512×512
  photo — JPEG q85 105142 B / 3.39 ms vs PNG 732157 B / 17.13 ms
  (0.144×); 256×256 thumbnail — 26559 B / 0.82 ms vs 180278 B /
  3.83 ms (0.147×); flat 320×240 gradient scene — JPEG 4333 B vs PNG
  2411 B (1.797× — the unsuitable case, noted in recipe 13). Gate
  green: **96.31% coverage (7039/7309)**; T008 suite back to 796459.
 - T032: static WebP read/write implemented (`decodeWebP`/
   `decodeWebPDimensions`/`encodeWebP` in `src/formats/webp.jl`;
   RIFF+WEBP magic branches in `decodeImage`/`decodeImageDimensions`;
   `encodeImage` WebpFormat + `writeFile` `.webp`; exports;
   `test/webp_tests.jl`, 353 assertions; cookbook recipe 14). Per the
   T030 contract §3: success-checked `WebPGetFeaturesInternal` scan
   first (the provider's own auto-decode ignores the scan's return
   value — unsafe on invalid data; observed rv: 0 = OK, 3/7 =
   failure), animation rejected with the named
   `ArgumentError("WebP animation is not supported")` **before** pixel
   decode (the provider decode crashes the process at C level on
   animated input — the pinned Wikimedia fixture exercises the path;
   `decodeWebPDimensions` still reports the 211×211 canvas), invalid/
   truncated input → `ArgumentError("Invalid WebP, unable to load")`,
   always-RGBA encode (premul→straight `(p8*255 + a8 div 2) div a8`,
   clamped; `a8 = 0` → 0), dimension bound 16383 (the provider silently
   returns 0 bytes at 16384 — rejected first), lossy quality 0..100
   (the provider's named error; lossless ignores quality). **Decode
   evidence**: the 129-file pinned upstream libwebp corpus
   (`.reference/upstream/tests/fileformats/webp/`, per its SOURCE.txt)
   feature-scans and pixel-decodes at the feature dimensions for every
   file (provider matrices are `[row=y, col=x]` — confirmed corpus-
   wide); the 12 exact dimension expectations from upstream
   `test_webp.nim` all match; corpus alpha classification (89 files
   RGB → `a = 255`, 40 carry semi/transparent pixels — e.g.
   `one_color_no_palette` fully transparent, `lossless1` mixes 211284
   a=0 pixels with opaque). **Encode evidence**: lossless round-trips
   are byte-exact in the premultiplied API (opaque exact; alpha exact
   everywhere; RGB where α>0 exact; RGB where α=0 forced to 0 — the
   contract's straight-domain α=0 non-determinism, measured 81/3072,
   is unobservable in premul); lossy q75 PSNR ≥ 35 dB on the fixed
   gradient (measured 37.67; the knob bites, q10 worse); hand-walked
   RIFF chunk table (VP8L lossless; single VP8 for lossy fully-opaque;
   VP8X+ALPH+VP8 for lossy with real alpha — observed libwebp_jll
   1.6.1 order). **Loading**: D028 lazy protocol extended (absent →
   "WebP support is opt-in" hint; present → lossless byte-exact +
   dimension round-trips); T008 dispatch tests updated to the seven
   writable formats (count restored: 796459). Recorded limitation
   (contract §3.5): no independent WebP pixel decoder on the machine
   (no ffmpeg/cwebp/dwebp/ImageMagick/PIL; mupdf refuses WebP) →
   corpus decode gets dimension/classification assertions only.
   **Benchmark** (warm medians, log `/tmp/opencode/t032_bench.jl`):
   mandrill 512×512 photo — WebP lossy q75 76648 B / 27.79 ms,
   lossless 579344 B / 145.72 ms vs PNG 732157 B / 17.26 ms, JPEG q85
   105142 B / 2.79 ms; 256×256 thumbnail — lossy q75 19162 B / 6.41 ms,
   lossless 136458 B / 77.28 ms vs PNG 180278 B / 3.72 ms, JPEG q85
   26559 B / 0.82 ms; decode 512 lossy 5.96 ms, 512 lossless 5.14 ms,
   256 lossy 1.49 ms; transparent 256×256 card — PNG 1740 B vs WebP
   lossless 394 B (recipe 14 reports the numbers without claiming
   universal superiority). Gate green: **96.32% coverage (7110/7382)**;
   T008 suite 796459.
  - T029: optional shaping and bidi implemented
    (`src/formats/shaping.jl`; `shapeText`/`ShapedGlyph`,
    `glyphPathByGid`; `ParagraphLayout.shaped` + RTL engagement in
    `paragraph.jl`; `test/shaping_tests.jl`, 223 assertions; cookbook
    recipe 15). Provider: opt-in `HarfBuzz_jll` 100.15001.0+0
    (harfbuzz 15.1.0) behind a 15-symbol `ccall` surface, loaded lazily
    (D033; D028 protocol — absent → the named `ErrorException("Shaping
    support is opt-in: ...")` on RTL `layoutParagraph` and on
    `shapeText`; present → the pinned outputs). **Reference evidence**
    (protocol §8 option 2): system libharfbuzz 12.3.2 through the C
    driver `tools/oracle/hb_refshape.c` — 10 pinned cases in
    `test/reference/shaping_reference.tsv` over the OFL
    `NotoSansArabic-Regular.ttf`/`NotoSansDevanagari-Regular.ttf`
    (`test/fixtures/`, sha256 sidecars + `scripts/
    fetch_shaping_fixtures.jl`) and upstream-pinned `Roboto-Regular_1.ttf`;
    the JLL 15.1.0 provider agrees with the 12.3.2 reference on all 10
    cases (gid/cluster/advance/offset; probe log in
    tasks/T029-unicode-shaping.md). Demonstrated: Arabic contextual
    joining (shaped GIDs 424/59/36 ≠ isolated cmap 420/56/34),
    script sensitivity (Arab vs Zinh rows), Devanagari conjuncts
    (k+virama+ssa → one GID 179; the reference akshara word keeps
    clusters 0/1/4), the Roboto `fi` ligature (one GID 444; `ff` does
    not ligate), combining-mark cluster merge, missing-glyph →
    `.notdef` (gid 0, the font's 600-unit advance) with no silent
    cluster drop, L2E digit order under an RTL base, mirrored
    punctuation, RTL placement per the cairo-bridge pen model
    (right-aligned ink on the box edge), and RTL wrap with per-line
    re-shaping. **Table fix carried from T028**: the vendored UAX#29
    cluster tables had a range misalignment (base letters — Devanagari
    0905/0915/0936, Myanmar 1000..100B — inside both tables, so
    "akshara" (0905 0915 094d 0936 0930) clustered as one grapheme);
    regenerated from Unicode 16.0.0 by
    `tools/oracle/gen_cluster_tables.py`, round-trip verified
    codepoint-exact (220 extend / 112 mc BMP ranges); one T028
    expectation corrected ("ka+virama+ssa" = 2 UAX#29 clusters;
    conjunct formation is shaper-level, not grapheme-level). Gate
    green: **95.83% coverage (7603/7934)**; all legacy suites
    byte-unchanged (T028 paragraph suite 22,761 with the corrected
    expectation).
