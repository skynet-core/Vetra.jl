# Decisions

## D001 — Empty scaffold (accepted for bootstrap)

Only package structure, tooling, and project guidance are created now.
All graphics implementation remains future work.

## D002 — Package conventions (working default)

Use Vetra as the module name, Julia 1.10 as the minimum, and MIT for new work.
The package name is provisional; registry availability has not been checked.
Use idiomatic Julia mutating APIs while tracking upstream behavior explicitly.

## D003 — Rendering engine (working direction)

Implement rendering algorithms in Julia. Keep Nim as a reference implementation,
not a runtime dependency or a foreign-function rendering backend.

## D004 — Codec and font dependencies (open)

The user has not decided whether external packages or native libraries are
acceptable for image I/O and fonts. The scaffold therefore adds none.
Before T006 choose a minimal output route. Before T008/T009 record the broader
policy, dependency licenses, portability impact, and any fully-Julia requirement.
This open decision does not block T001–T005.

## D005 — Numerical compatibility (provisional)

Seek exact equality for integer color/compositing behavior and for canonical
reference pixels. T001 must specify the reference backend and environment;
upstream scalar and SIMD rounding can require separate characterization.
Use a tolerance only for a named, justified case, with a bounded metric and
recorded rationale. Never silently widen an existing tolerance.

## D006 — Upstream source pin (accepted for bootstrap)

Use the exact revision in upstream.toml, observed on 2026-10-27.
This is not a lock of upstream transitive dependencies. T001 records the actual
Nim/compiler/dependency versions used for reference generation.

## D007 — Rendering backend strategy (accepted — user directive, 2026-10-27)

Problem: the port must not be hard-wired to one device. The user wants any
rendering backend (CPU, Vulkan, OpenGL, or later others) to be usable
conveniently, preferring well-supported Julia packages where possible.

Chosen behavior:

- The core (colors, geometry, paths, coverage, compositing, paints) is
  backend-agnostic: it computes over an abstract pixel-buffer surface
  (a contiguous `UInt8` RGBA row-major buffer, premultiplied alpha) and emits
  per-pixel operations that a backend executes. The pure-Julia CPU backend is
  the default, the reference implementation, and the one held to numerical
  parity and the coverage gate.
- GPU/accelerated backends (Vulkan, OpenGL, CUDA) are opt-in adapters that
  provide the same pixel-ops surface; they are deferred tasks, not stubs, and
  are added only after scalar parity plus a benchmark justifies them
  (AGENTS.md performance rules). Candidate well-supported Julia packages,
  chosen per backend at task time and recorded when used: `OpenKaleido.jl`
  (CPU/Vulkan/OpenGL/CU compute), `Vulkan.jl`, `OpenGL.jl`, `CUDA.jl`.
- The pixel buffer type must not assume CPU memory layout beyond contiguous
  rows of `UInt8`, so a device-backed buffer can be substituted without
  changing the renderer.

Alternatives that matter: hard-code the CPU path (rejected: breaks the
flexibility the user asked for); FFI a C graphics engine as the renderer
(rejected: contradicts D003 and would defeat the port).

Compatibility impact: none on the numerical contract; adds one abstraction
level. Evidence: user directive 2026-10-27; D003; AGENTS.md performance rules.

## D008 — Codec and font dependency policy (supersedes D004, accepted — user
directive, 2026-10-27)

Problem: D004 left codec and font dependencies open.

Chosen behavior: prefer well-supported, mainstream Julia packages for image
codecs and fonts whenever a stable package covers the capability (for example
the `FileIO.jl`/`ImageIO.jl` ecosystem and format packages such as
`PNGFiles.jl`, `JpegViews.jl`, `TiffImages.jl`, `WebP.jl`, `GIF.jl`,
`FreeType.jl` for font parsing and metrics). Hand-written Julia ports remain
allowed where no well-supported package exists or where exact upstream
numerical behavior must be controlled directly (the QOI and PPM codecs are
small enough that a native port may win; decide per task and record it).
The core pixel renderer stays dependency-free: no codec or font package is a
dependency of the rendering path itself.

Supersedes: the "open" status in D004 for codecs and fonts. The T006 output
route is settled by D007's CPU buffer plus a minimal lossless writer (PPM or
PNG via a well-supported package) chosen at T006 time.

Evidence: user directive 2026-10-27.

## D009 — Coverage gate (accepted — user directive, 2026-10-27)

Problem: the user requires the codebase to be fully tested with code coverage
strictly above 95%.

Chosen behavior: enforce a coverage gate of >95% on the rendered source under
`src/` in the local check flow and CI. Coverage is measured with Julia's
built-in line coverage (`Pkg.test(; coverage=true)`, per-source `*.cov` files
parsed by scripts/check.jl) over a full test run — no extra package
dependency (consistent with D008). The gate covers implemented code; an
unimplemented area that intentionally contains no source yet does not lower
the measured figure.
GPU adapter code, when added, must itself meet the gate. Expected outputs
remain independently justified (AGENTS.md); a coverage number is never achieved
by loosening tests or fabricating expectations. The exact measured percentage
is recorded in the handoff and task evidence each time it runs.

Evidence: user directive 2026-10-27 ("code coverage is higher than 95%").

## D010 — T002 core API and storage choices (accepted, 2026-10-28)

Problem: T002 implements the first real public surface; the types, storage,
indexing, error semantics, and upstream rounding behavior had to be chosen
before code could depend on them.

Chosen behavior (recorded per AGENTS.md before relying on these):

- Colors are `UInt8`-field structs: `ColorRGB{r,g,b}`,
  `ColorRGBA{r,g,b,a}`, `ColorRGBX{r,g,b,a}`. Constructors `rgb/rgba/rgbx`
  accept `UInt8` or small `Int`; values outside 0..255 raise `ArgumentError`
  (upstream Nim implicitly converts small ints; we do not silently wrap).
- `Image` holds `width::Int, height::Int, data::Vector{UInt8}`: premultiplied
  RGBA, row-major, rows top-to-bottom, 4 bytes per pixel.
- Pixel coordinates are **1-based** in the Julia API; upstream is 0-based.
  Flat byte offset = `4 * ((y - 1) * width + (x - 1))`. `inside`/`getColor`/
  `setColor` check 1..width / 1..height.
- `newImage(w,h)` raises `ArgumentError` for `w <= 0 || h <= 0`. Out-of-range
  `getColor`/`setColor` raise `BoundsError` rather than performing the
  upstream doc-comment's described no-op (documented deviation; safer).
- `fill` accepts all three color types; straight-alpha inputs are converted
  to premultiplied at the storage boundary (upstream `asRgbx` behavior).
- Both premul→straight paths are kept distinct, as in upstream: chroma
  `rgba(ColorRGBX)` (float32 multiplier) and pixie `toStraightAlpha`
  (float64 multiplier, as upstream's `if` infers; verified bit-exact on all
  32896 valid rows of straight_alpha.tsv). Documented divergence rows, e.g.
  a=4, c=2 → 127 vs 128, stay documented in docs/NUMERICAL_CONTRACT.md.
- Rounding: this Julia build's `round` ties to even while upstream Nim ties
  away from zero; all port sites use `roundHalfAway(x) = Int(floor(x + 0.5))`
  (values are non-negative). Recorded per file in src/Vetra.jl.
- `blendNormal` channel sums wrap mod 256, mirroring upstream `uint8`
  addition (visible in blend_normal.tsv cells, e.g. white over
  (255,255,255,254) → (0,0,0,255)); valid premultiplied inputs never exceed
  255, so parity on valid input is unaffected.
- Exports use classic `export`; the module top does `import Base: *, fill,
  copy` because this trimmed build has no `public` and shadowing rules
  would otherwise break ordinary arithmetic in-module.

Alternatives that matter: 0-based coordinates (rejected: non-idiomatic in
Julia, would mislead every caller); `Int`-field storage (rejected: memory
layout must stay `UInt8` RGBA per D007); raising no error on bad bytes
(rejected: silent wrap diverges from upstream *and* from user expectations).

Compatibility impact: defines the T002 public API in
docs/COMPATIBILITY.md (Foundation rows now implemented). Deviations from
upstream: `ArgumentError`/`BoundsError` on invalid input where upstream
doc-comments describe no-ops; blendNormal wrap on invalid-premul input is
mirrored, not an API change.

Evidence: `test/core_tests.jl` (5 813 assertions, exhaustive against T001
fixtures) + `scripts/check.jl` run of 2026-10-28: tests passed, `src/` line
coverage 100.0% (89/89 measurable lines), gate `> 95%` satisfied.

## D011 — Flutter-inspired public API (accepted — user directive, 2026-10-28)

Problem: every remaining task (T003–T011) needs a stable public API; the
"open" API shape was the main non-code blocker in TASKS.md. The user asked to
take API ideas from Flutter.

Chosen behavior (full text in docs/API.md):

- Flutter/dart:ui supplies the API *shape*: immutable `Float32` geometry
  (`Vec2`, `Rect`, `Circle`), a stateful immediate-mode `Context` drawing into
  an `Image` (save/restore transform+clip, `Paint` objects, `Path`,
  `BlendMode`, drawing and text methods), and a reserved
  `Picture`/`PictureRecorder` seam for backend swapping (D007).
- The pinned pixie/chroma/vmath sources supply *semantics and numerics* and
  keep their symbol names (camelCase, e.g. `newImage`, `fillRect`,
  `quadraticCurveTo`), so public symbols remain traceable to the reference.
- Coordinates for drawing are continuous, 0-based, y-down, radians, `Float32`
  (Flutter convention; upstream vmath is also `Float32`). T002's `Image`
  pixel accessors keep 1-based integer addressing (D010) as a
  storage-inspection API; this mixed convention is documented and tested.
- `Rect` keeps the upstream bumpy layout `(x, y, w, h)` (not Flutter's LTRB
  storage); `left/top/right/bottom` are derived accessors.
- `Mat3` is a column-major affine 3x3 with Flutter/OpenGL multiplication
  order (`A * B` applies B first; `M * p` transforms a point). Verified
  against the pinned vmath implementation.
- `Paint` is mutable like Flutter's; `Path`, `Context`, `Image` are mutable,
  geometry value types are immutable.
- No placeholder APIs: unimplemented Flutter concepts stay in docs/API.md,
  not in `export`.

Alternatives that matter: renaming `Context` to `Canvas` (rejected: pixie's
context is stateful like HTML canvas, unlike Flutter's per-call-paint Canvas,
so the name would mislead); using Flutter `Offset`/`Matrix4` names (rejected:
vmath names keep source traceability); rewriting T002 to 0-based pixel access
(rejected: working, tested behavior; the drawing API is where convention
matters).

Compatibility impact: defines the public surface for T003–T011; no change to
T002 behavior. Evidence: user directive 2026-10-28; docs/API.md; pinned
vmath/pixie sources (`Mat3` multiplication, `Context` state, `Rect` layout).

## D012 — Wave-based readiness (accepted — user directive, 2026-10-28)

Problem: TASKS.md marked every future task `blocked`, which stopped work even
though the gating decisions (D007 backend seam, D008 codec/font policy, D011
API) and the dependency graph are now resolved.

Chosen behavior: all tasks T003–T011 are `ready` once their focused
specification exists in `tasks/`. Execution order is expressed by a `Wave`
column instead of hard `blocked` status; a wave starts when the previous
wave's tasks merge. T008 and T009 share a wave (independent files) and T010
integrates both. Shared files (`TASKS.md`, `docs/HANDOFF.md`, `src/Vetra.jl`)
have one integrator; parallel writers use separate worktrees (D007 /
docs/AGENT_WORKFLOW.md).

Alternatives that matter: keeping hard `blocked` statuses (rejected: the
user asked to unblock all waves; the real blocker was undecided API/policy,
now resolved); starting every task at once (rejected: interface churn in the
early core and conflicting edits).

Compatibility impact: none on code; board semantics and HANDOFF ownership
only. Evidence: user directive 2026-10-28; D007, D008, D011; docs/API.md.

## D013 — T007b image-effects porting choices (accepted, 2026-11-04)

Problem: porting the pinned image effects (images.nim L78–L805, internal.nim
L17/L86) into an immutable-struct Julia core hits three upstream idioms that
have no 1:1 translation: `rotate90` mutates image dimensions in place;
`ceil`/`diff` would shadow `Base.ceil`/`Base.diff` module-wide; and `draw`'s
`blendMode` is a Nim positional default.

Chosen behavior:
- `rotate90(image)` **returns** the rotated image (deviation from upstream's
  in-place mutation); every other effect mutates `image.data` in place and
  returns nothing, as upstream.
- `ceil` and `diff` are added to `import Base: ...` so the new methods
  **extend the Base generics** (same pattern as `fill`/`copy`):
  `ceil(Float32)` calls in geometry/rasterizer keep working, and `using Vetra`
  creates no ambiguous export.
- `draw` keeps its `; blendMode` keyword signature. This Julia build has no
  kwcall fallback for optional positional args (verified:
  `f(1, 2; d = 9)` errors on `function f(a, b, c = 1, d = 2)`), so new
  call sites (`resize`, `shadow`, `superImage`) pass `blendMode` as a
  keyword rather than widening the signature.

Alternatives that matter: making `Image` mutable to match upstream in-place
dimension changes (rejected: breaks D010's immutable core and ripples through
every existing call); renaming the effects to avoid Base (rejected: D011 pins
upstream names); dropping the kwcall-safe `draw` shape (rejected: existing
T007a/T007b call sites use the keyword form).

Compatibility impact: `rotate90` result handling differs from upstream
(users must take the returned image, not read the mutated source); all
other effects are behavior-identical (scalar, pinned truncation chains —
288/288 gaussian_kernel weights exact, 404 hand-derived effect assertions).
Evidence: tasks/T007b-masks-effects.md "Results -- image effects";
src/image_ops.jl; test/image_ops_tests.jl "T007b image effects".

## D014 — T008 codec package choices (accepted, 2026-11-05)

Problem: T008 must deliver PNG, JPEG, BMP, QOI, GIF, SVG and PPM within the
D008 policy ("prefer well-supported Julia packages for codecs when stable;
keep the renderer core dependency-free; dependency use must be opt-in").

Chosen behavior, per format:
- **PNG** — decode + encode via `PNGFiles` (opt-in package).
- **JPEG** — decode via `JpegTurbo` (opt-in package); no encoder, as
  upstream. Pixels are compared against the upstream stb-derived fixtures
  with a recorded max channel delta of 8 (measured: mandrill 5,
  progressive 5, exif_overrun 4, grayscale 1); dimensions are exact and
  Exif-orientation-aware.
- **SVG** — XML parse via the `XML` package (opt-in) feeding the native
  `svg.nim`-subset port (`parseSvg` + `newImage(svg)`).
- **BMP, QOI, GIF, PPM, base64** — native scalar ports, no packages
  (GIF decode-only, as upstream; QOI preserves the upstream op-tag
  quirk: RGB=0xFE, RGBA=0xFF, INDEX = raw hash byte).
- **WebP** — deferred (no stable Julia package; native port unscheduled);
  `WebpFormat` dispatch raises `ArgumentError("Unsupported file format")`,
  matching upstream `encodeImage`.

Opt-in mechanics (D014 extension of the T008 design): the three packages
are `[extras]`, not `[deps]`; `Project.toml` gains no hard dependency.
The original precompile-time loading mechanism below is superseded by D019.
`Vetra` requires each package eagerly **at module load when present**
(`Base.require` behind a try/catch in `src/formats/{png,jpeg,svg}.jl`);
environments without them load normally and get an install-hint
`ErrorException` on first use of the format, not a load failure. Rationale:
this build freezes precompiled method dispatch at the precompile-time
world, so a package first `require`d at runtime dispatches as "too new";
eager require keeps the codec callable. Recorded in NOTICE with licenses
(all MIT; JpegTurbo wraps libjpeg-turbo).

Alternatives that matter: hard `[deps]` (rejected — D008 opt-in);
deferred runtime `require` without precompile-time binding (rejected —
broken dispatch on this build, verified); native PNG port instead of
PNGFiles (rejected — PNGFiles is the stable, well-supported choice under
D008; a native libpng port is unscheduled backlog).

Compatibility impact: PNG/JPEG/SVG features require the optional packages;
everything else in T008 is dependency-free. JPEG pixels are not
byte-identical to upstream (different lossy decoder; tolerance recorded).
Evidence: tasks/T008-formats-svg.md results; test/formats_tests.jl;
test/formats_synthetic_tests.jl; docs/COMPATIBILITY.md "Images, formats,
text (T006, T008, T009)".

## D015 — T009 font parsing: native OpenType subset port (accepted, 2026-11-06)

Problem: T009 needs font parsing, metrics, kerning and glyph outlines
matching pinned upstream behavior. D008 prefers well-supported Julia
packages for codecs; a font package would be `FreeType.jl` (FreeType
bindings).

Chosen behavior: **native scalar port of upstream's OpenType subset**
(`src/fontformats/opentype.jl`, mirroring
`.reference/upstream/src/pixie/fontformats/opentype.nim`), plus the `fonts.nim`
text layer (`src/formats/fonts.jl`) and Context text state
(`src/context.jl`). Supported input: single-face TTF/glyf fonts —
cmap (platform 3, formats 4 and 12), head, hhea, maxp (0.5/1.0), hmtx,
name, OS/2 (v0/v1/v2 via upstream's 78/86/96-byte layout), post, loca
(fmt 0/1), glyf (simple + composite glyphs), legacy `kern` v0 and GPOS
pair-position (formats 1 and 2, lookup type 2). Upstream quirks are
preserved, not corrected (non-standard 14-byte cmap format-4 header,
parent-relative GPOS offsets at every level, `coverage format 2`
`startCoverageIndex` used as-is, GPOS preferred over `kern`, composite
`MORE_COMPONENTS` on bit 5, `isCCW` = glyf-winding true, 54-byte head
field offsets, `fastRuneAt` decoding without continuation-byte
validation).

FreeType.jl rejected because:
1. Its kerning API (`FT_Get_Kerning`) reads only the legacy `kern` table,
   not GPOS. Roboto — the primary T009 fixture font — has no `kern`
   table; its pinned upstream kerning (T,e = −99.0, W,o = −31.0 units)
   comes from GPOS pair positioning. A FreeType.jl route would fail the
   upstream-pinned assertions by construction.
2. Glyph outlines would then come from FreeType's native reader while
   everything else (metrics, name, OS/2, cmap dispatch) would still need
   the port — two outline sources doubles the parity surface against the
   0-mismatch rendered-image gate, and FreeType.jl is not in the project
   environment's package registry state here.

Alternatives that matter: bundle FreeType's C library and read GPOS via
FT's raw-table access (rejected — heavier than the native subset, still a
second outline source); defer fonts to a later wave (rejected — T009 is
on the critical path for T010).

Compatibility impact: CFF-outline fonts (Inter, NotoEmoji), TrueType
Collections (TTC), and SVG fonts are **not supported** —
`readTypeface` raises `ArgumentError("Unsupported font format")` for
SVG paths and `ArgumentError("Unsupported font CFF outlines")` for
CFF-only files (both messages verified against upstream behavior).
textCase uses the pinned Nim 2.2.6 unicase tables (src/fontformats/
unicase.jl). No new hard dependencies. Evidence: tasks/T009-fonts-text.
md results; test/font_tests.jl (2456 assertions, 0 failures: oracle
metric/kerning TSVs, 17 layout scenarios bit-exact, 14 rendered images
0 mismatches, synthetic mini font, malformed-byte rejections); oracle
fixtures via `sh tools/oracle/build.sh fonts` (Roboto Apache-2.0, Ubuntu
UFL, sha256 recorded in fixture meta and verified by tests).

## D016 — T011 performance gaps accepted for the initial release (accepted, 2026-11-06)

Problem: T011 requires measured (not claimed) performance and "optimize
only measured bottlenecks". The first benchmark run was unfair (the Nim
reference was built in debug; the harnesses had loop-bound and timer
bugs), so it was re-run corrected before any decision.

Measurement (steady-state median, same machine, both scalar):
- Julia vs Nim reference: fill_rects_1000 0.90/0.82 ms (tie),
  stroke_lines_1000 26.6/22.3 (1.2x), blur 0.69/0.43 (1.6x),
  shadow 1.07/0.67 (1.6x), draw_10 1.15/0.18 (6.4x),
  png_encode 29.0/10.8 (2.7x), png_decode 67.3/1.17 (~57x),
  text parse+layout+measure 1.26/1.99 (Julia **faster**).
- Julia allocations per workload are recorded in tasks/T011-release.md.

Chosen behavior: **no renderer optimization in this release**; the gaps
are accepted and recorded. Rationale: (1) AGENTS.md mandates scalar
correctness first and bars `@fastmath`/unsafe/SIMD/threads without a
recorded benchmark justifying a specific change — the measurements here
justify *looking*, but any change must land behind the 811k-assertion
parity suite and the 0-mismatch fixture gates, which is a separate,
reviewed task, not a T011 side-quest; (2) the port's contract is
behavioral parity, and it is at/above the reference on the text path and
within 1.2x on the two dominant draw workloads; (3) the PNG-decode gap
is the D014 codec choice (PNGFiles vs upstream zippy), not a renderer
defect. `draw_10` and the blend paths are the candidates if performance
work is ever commissioned.

Alternatives that matter: commission an optimization task now (rejected —
scope creep past T011's "record, then decide" bar, and risky against the
parity gates without its own design); swap the PNG codec for a faster
one (rejected — D014 prefers well-supported packages; zippy has no
mature Julia equivalent).

Evidence: tasks/T011-release.md (commands, environment, full table);
benchmark/results/{julia,nim}_2026-11-06.tsv (gitignored raw TSVs; the
numbers are recorded in the task file so a clone has them).

## D017 — Rename to Vetra and the pixie-scrub line (accepted, 2026-11-06)

Problem: the package was released under its working name; the user asked
to remove every remaining occurrence of the old name from the project,
including the git commit message.

Chosen behavior: rename everything this repository owns, keep the word
only where it literally names the upstream project or its artifacts:
the pinned GitHub URL/repo name, upstream `src/pixie/*.nim` symbol paths,
the upstream `PixieError` type, the `-d:pixieNoSimd` flag, the upstream
`const epsilon` attribution (`PIXIE_EPSILON`), and the
checksum-pinned fixture provenance lines (`.meta`/`.tsv`, asserted by
tests). Renamed: the commit message (amended + force-pushed),
`PixieExamples` -> `VetraExamples`, the `.reference/pixie` checkout dir
-> `.reference/upstream` (70 referrers incl. `scripts/fetch_upstream.jl`
and the fixture `example=` provenance labels, whose checkout prefix
follows the directory rename), `third_party/pixie.LICENSE`
-> `third_party/upstream.LICENSE`, and stale prose (NOTICE "planned",
`pixie.jl` benchmark header, AGENTS.md scaffold claims). Git history
re-initialized as a single commit on `main`, pushed to
git@github.com:skynet-core/Vetra.jl; the package uuid is unchanged
(unregistered, so no registry conflict).

Alternatives that matter: fully literal removal of every occurrence
(rejected — it would falsify the NOTICE/upstream provenance contract,
break `scripts/fetch_upstream.jl`, and sever the attribution AGENTS.md
requires).

Compatibility impact: none on the public API (the old helper module is
examples-only). Clones must use `.reference/upstream`; CI fetches it.

Evidence: full gate green after the scrub (811 407 assertions,
coverage 98.0%); case-insensitive inventory shows only the kept
categories above.

## D018 — CI benchmark scope: Julia side, main pushes (accepted, 2026-11-06)

Problem: run benchmarks in CI on every push to main, alongside the
existing unit-test jobs.

Chosen behavior: a `benchmark` job in .github/workflows/ci.yml, gated
on `push` + `refs/heads/main`, ubuntu-latest, Julia latest. It fetches
the pinned upstream (fonts), builds a throwaway env in `$RUNNER_TEMP`
(`Pkg.develop` on the checkout + `Pkg.add("PNGFiles")` per the D014
opt-in policy), runs `benchmark/run_benchmarks.jl`, and uploads
`benchmark/results/` as an artifact. No pass/fail threshold — the TSVs
are evidence, not a gate.

Alternatives that matter: also build/run the Nim reference in CI
(rejected — needs the pinned upstream checkout plus a Nim 2.2.6 toolchain
that GitHub runners don't ship; the comparison is a frozen T011 record);
run benchmarks on PRs/branches (rejected — runner timing is noisy and
the user scoped this to pushes to main); a performance regression gate
(rejected — no baseline store in CI to gate against yet; revisit with a
dedicated task if requested).

Compatibility impact: none; CI-only. The local commands in
benchmark/README.md are unchanged.

Evidence: the exact CI steps were dry-run locally end-to-end (fresh env
bootstrap + benchmark run wrote a TSV); unit tests and both benchmark
sides re-ran green the same day (811 407 assertions; medians within
noise of the T011 table).

## D019 — Discover optional codecs at runtime initialization (accepted, 2026-11-06)

Problem: ordinary `Pkg.test()` reused a Vetra cache built in an environment
without codecs. Top-level `Base.require` calls had silently skipped absent
packages during precompilation and did not run again. PNG/JPEG/SVG tests
then raised install hints even though their packages were in the test target.
The coverage gate had passed, so it did not expose this cache-dependent failure.

Chosen behavior: replace the three top-level try/require blocks with one
`Vetra.__init__` loop. For each existing codec PkgId, `Base.locate_package`
checks the current environment and `Base.require` loads an available package.
Missing codecs remain optional; errors from installed codecs are not swallowed.
Install codecs before loading Vetra, or restart after adding them. No dependency
or public API changes; this supersedes D014's precompile-time loading mechanism.

Alternatives: deleting caches, disabling precompilation, or importing codecs
in the tests would mask the runtime defect and leave applications affected.

Evidence: `test/codec_loading_tests.jl` reproduces core-only then codec-enabled
loading in separate processes sharing a temporary-depot cache. It failed on
the old code and passes with PNG round-trip, JPEG decode, and SVG rendering.
The exact user command `julia --startup-file=no --project=. -e 'using Pkg; Pkg.test()'`
and `julia --startup-file=no --project=. scripts/check.jl` both pass locally
on Julia 1.13.3; coverage is 98.0% (5235/5342 measurable source lines).

## D020 — Executable tutorial from Literate.jl (accepted, 2026-11-06)

Problem: the tutorial (a step-by-step crypto OHLC candlestick chart,
rewritten 2026-11-06 to also build an SVG backend and read it back through
`parseSvg`) must generate both executable Jupyter cells and Markdown
containing executed results, without maintaining separate examples.

Chosen behavior: `docs/tutorial.jl` is the single source. Literate.jl emits
CommonMark and `.ipynb`, with `execute=true` for both and errors propagated.
`docs/make_tutorial.jl` writes to ignored `docs/build/tutorial/`; the existing
`docs/TUTORIAL.md` URL becomes the setup/launch guide. A small tutorial-only
PNG display adapter supplies inline images without adding methods to Vetra's
public types. Existing assertions execute in both formats.

Literate and IJulia live only in `docs/Project.toml`, alongside the optional
codecs and a local Vetra development dependency. The explicit develop step
works on Julia 1.10, which does not use the newer `[sources]` table. Assets
are fetched explicitly before building. No package installation or network
fetch occurs inside notebook cells. Repo links in generated prose use GitHub
URLs so they remain valid at either output location.

Alternative: Weave.jl could produce evaluated documents too; Literate's
plain-Julia input and direct Markdown/notebook outputs fit the existing
examples without another document syntax. Generated outputs are build
artifacts rather than a second editable copy of the tutorial.

Evidence: both Literate formats executed 13 code cells/18 assertions with
eight inline images; nbclient independently executed the notebook through
IJulia with no error outputs. Plain-script execution and the package gate
also passed (docs/HANDOFF.md records commands and versions).

## D021 — Renderer performance pass: official-tips optimizations, byte-exact gate (accepted, 2026-11-06)

Problem: close the gap to the pinned scalar Nim reference (T011: draw
6.3×, blur/shadow 1.5×, stroke 1.2×) per the Julia performance-tips
manual, without changing any pinned rendering arithmetic.

Chosen behavior: the optimizations in tasks/T012-optimization.md —
flat-buffer pixel indexing in `blendRect`/`drawSmooth`/`blur`/`spread`
(replacing per-pixel bounds-checked wrappers), an opaque-source
straight copy in Normal compositing (pixel-identical by `blendNormal`'s
documented early return), loop-invariant hoisting in the compositing
closures, preallocated stroke outlines, and `@inbounds` only on loops
whose in-range proof is written in the code. Correctness is proven by
the unchanged byte-exact fixture gate (97.94% coverage), not by
tolerances.

Alternative considered and rejected: streaming span callbacks
(`eachSpan`) replacing the per-row `walk` vector — measured 6× slower
on the stroke workload in this build (closure dispatch vs iteration
over a small concrete vector); the pinned `walk` stays. Also rejected:
scalar trapezoid-edge buffers (neutral — `Segment` is isbits in a
preallocated array), and `@inbounds` in the rasterizer's pinned loops
(range-provable but not measured to matter; recorded as the next
candidate in T012).

Compatibility impact: none observable — all fixture outputs
byte-identical; `fillPath(ColorRGBX...)` gained a `blendMode` keyword
(default `NormalBlend`, prior behavior).

Evidence: 3-run harness medians vs T011 baseline vs Nim: blur 0.69 →
0.37 ms (Nim 0.43), shadow 1.07 → 0.40 ms (Nim 0.67), draw 1.15 → 0.23
ms (Nim 0.18), fill 0.90 → 0.76 ms (Nim 0.82), text 1.26 → 1.25 ms
(Nim 1.99), stroke 26.63 → 25.81 ms (Nim 22.30); PNG follow-up in the
same pass: decode 67.27 → 1.50 ms (Nim 1.17) via the kernel-function
barrier and raw-byte channel reads, encode 29.05 → 23.31 ms (Nim
10.78, codec-bound at ~2.1 ms libpng per image).

## Adding a decision

Append a short entry with status, task, problem, chosen behavior, alternatives
that matter, compatibility impact, and evidence. Supersede old entries explicitly
rather than rewriting historical rationale without a trace.
