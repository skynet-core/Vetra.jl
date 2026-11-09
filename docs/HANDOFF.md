# Current handoff

Updated: 2026-11-07

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
**96.29% coverage (7013/7283)**. Next ready tasks:
T030 (T019 awaits an explicit publication request; T029 awaits the
provider decision, D031 §6, now that T028 is done). T013–T028
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

No active implementation task. Next ready:
[T030](../tasks/T030-codec-design.md) — JPEG/WebP codec contracts, which
unblocks T031 (JPEG encoding) and T032 (WebP). T029 (shaping/bidi) remains
blocked on the provider decision (D031 §6) now that T028 is done.
Protocol (user, 2026-11-08): commit and push to `origin main` after each
completed task. T019 (registration/publication) remains gated on an
explicit user request.
Planned features are not implemented capabilities; see
[Compatibility](COMPATIBILITY.md). Fresh installation on Julia 1.10,
cross-platform CI (Windows/macOS), and the ProfileView GUI were not rerun;
Pluto was not installed, so T016 verification used IJulia only. Historical
release evidence is in [T011](../tasks/T011-release.md),
[T012](../tasks/T012-optimization.md),
[T018](../tasks/T018-release-readiness.md), and
[DECISIONS.md](DECISIONS.md).

## Recent verification (T014–T028)

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
