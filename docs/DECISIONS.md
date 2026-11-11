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
- **JPEG** — decode via `JpegTurbo` (opt-in package). Pixels are compared
  against the upstream stb-derived fixtures with a recorded max channel
  delta of 8 (measured: mandrill 5, progressive 5, exif_overrun 4,
  grayscale 1); dimensions are exact and Exif-orientation-aware. Encoding
  was added by T031 per D032 (same opt-in package, contract
  docs/JPEG_WEBP_CODECS.md §2).
- **SVG** — XML parse via the `XML` package (opt-in) feeding the native
  `svg.nim`-subset port (`parseSvg` + `newImage(svg)`).
- **BMP, QOI, GIF, PPM, base64** — native scalar ports, no packages
  (GIF decode-only, as upstream; QOI preserves the upstream op-tag
  quirk: RGB=0xFE, RGBA=0xFF, INDEX = raw hash byte).
- **WebP** — deferred at T008 (no stable Julia package at the time;
  native port unscheduled). Superseded by D032 (T030): static WebP
  read/write via the opt-in `WebP.jl` package (libwebp_jll), contract
  docs/JPEG_WEBP_CODECS.md §3, implemented by T032 (`decodeWebP`/
  `decodeWebPDimensions`/`encodeWebP`; animation raises a named error
  before pixel decode; only GIF writing still raises "Unsupported file
  format", matching upstream).

Opt-in mechanics (D014 extension of the T008 design): the three packages
(four after D032 adds `WebP.jl` for T032) are `[extras]`, not `[deps]`;
`Project.toml` gains no hard dependency.
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

## D022 — Consolidate the completed library and correct current guidance (accepted, 2026-11-07)

Problem: generated allocation traces were committed beside source files,
the handoff duplicated completed task records and retained obsolete setup
instructions, and some public documentation described planned rather than
implemented APIs.

Chosen behavior: remove generated traces and obsolete scaffold/split-roadmap
documents, ignore process-suffixed allocation traces, and keep current API,
architecture, task board, and handoff guidance concise. Retain independent
fixtures, licenses, upstream pins, and historical task/decision records.
PNG encoding reuses `toStraightAlpha` with its existing opaque fast path;
remove the unused `_xmlModule` wrapper and duplicate `computeBounds` export.

Clarification of D021/T012: the measured callback regression does not prove
a compiler cause; linear Array indexing is not inherently an `ind2sub`
operation; PNGFiles.save time is not isolated libpng time. Local profiling
difficulties do not establish that Julia's profiler is unusable. Current
guidance distinguishes measurements from these earlier hypotheses.

Compatibility impact: no intended public API or rendering changes. Existing
named/rgb/rgba color support is now accurately documented. Verification and
benchmark evidence are recorded in [T013](../tasks/T013-cleanup.md).

## D023 — Forward roadmap for adoption and advanced graphics (accepted, 2026-11-07)

Problem: after the pinned-scope port and cleanup, agents need actionable tasks
for the user-requested usability, interoperability, output, text, and performance
improvements rather than an unprioritized wish list.

Chosen behavior: docs/ROADMAP.md sets priorities and shared validation;
TASKS.md tracks T014–T032 with individual specifications. Begin with numeric
ergonomics, image-array interoperability, notebook display, and documentation/
recipes. Release preparation is separate from registration/publication.
Application baselines precede optimizations; recording, text/shaping, and codec
design contracts precede their implementation. GPU rendering and a widget/event
framework remain deferred. Default execution is one ready task at a time.

Compatibility impact: this decision adds a plan, not public symbols or runtime
features. Existing scalar/pinned behavior, core dependency policy, >95% coverage,
and provenance requirements remain in force. New optional integrations must
record their API/dependency decisions; this roadmap selects no provider and
does not silently supersede D014/D015 or authorize publishing.

Evidence: user request to add all recommended improvements to an agent-ready
roadmap. Planning validation checks links, IDs, acyclic dependencies, and ready
status consistency; implementation evidence belongs to each future task.

## D024 — Color-matrix interop via opt-in ColorTypes (accepted, 2026-11-07, T015)

Problem: users in the Julia imaging ecosystem work with standard color
matrices, not premultiplied byte buffers; the conversion boundary had to be
settled before code could depend on it.

Chosen behavior: `toColors(image) -> Matrix{RGBA{N0f8}}` (straight alpha,
`[row, col]`, row 1 = top) and `fromColors(matrix) -> Image` accepting 2-D
`RGB`/`RGBA` of `N0f8` (exact bytes) or `Float64`/`Float32` (0..1, clamped,
ties-away rounding via `UInt8(round(v * 255))`). Both directions reuse the
pinned PNG boundary conversions (`toStraightAlpha` out, `rgbx(ColorRGBA)` in),
so matrix bytes equal PNG payload bytes. Concrete `Matrix` inputs only (views
must be `copy`ed); 3-D plane layouts and unsupported eltypes raise
`ArgumentError`. `ColorTypes` is opt-in (D014/D019 discovery pattern); the
core renderer stays dependency-free. No FileIO dispatch (recorded follow-up).

Alternatives: mandatory ColorTypes dependency (rejected — D008/D014 keep the
core free); 3-D plane format support (deferred — adds a second indexing
contract without a measured need); `ImageCore`/`Images.jl` adapters (deferred
— their abstractions are heavier than ColorTypes matrices).

Compatibility impact: additive API (`toColors`, `fromColors`); round-trips
through intermediate alpha can shift channels by at most 1 (documented,
NUMERICAL_CONTRACT paths). Evidence: test/colormatrices_tests.jl (29
assertions), core-only hint in test/codec_loading_tests.jl; 256x256
toColors 0.80 ms / fromColors 0.19 ms with allocation limited to the output
buffers (function-barrier kernels, `reinterpret` byte construction).

## D025 — Docs tooling: reuse Literate + a hand-written gallery (accepted, 2026-11-07, T017)

Problem: T017 needs a locally buildable, browsable documentation entry point
with a visual gallery of reproducible recipes. The task asks for "the smallest
suitable docs tooling" and for its docs-only dependencies to be recorded.

Chosen behavior: no new documentation framework. The cookbook is a single
Literate.jl source (`docs/cookbook.jl`, prose `# ` + executable blocks) built
by `docs/make_cookbook.jl` — the exact pattern the OHLC tutorial already uses
(`docs/make_tutorial.jl`, D020) — emitting executed `COOKBOOK.md` and
`COOKBOOK.ipynb`. The gallery is a hand-written static `docs/build/gallery.html`
generated by a small `gallery_html()` function in the same build script (no
MkDocs/Jekyll/Documenter, no new package). `docs/INDEX.md` is the tracked
browsable entry point with a navigation table linking installation,
beginner guide, tutorial, API, capabilities, cookbook, gallery, and
troubleshooting. All generated outputs live under gitignored `docs/build/`.

Dependencies: the docs environment already has Literate (D020) and the opt-in
codecs (D014). No new dependency is added by T017.

Alternatives: a hosted Markdown framework (MkDocs/Documenter) — rejected,
adds a build toolchain and network/registry dependency to a docs-only task;
a separate gallery renderer (e.g. a second Literate pass) — rejected, the
hand-written HTML is ~30 lines and keeps the build to one command.

Compatibility impact: documentation only; no `src/`, `test/`, or `Project.toml`
change. Provenance of the two typefaces (Roboto-Regular, NotoSans) is the
pinned upstream Apache-licensed fixture fetched by
`scripts/fetch_upstream.jl`, recorded in `docs/INDEX.md` and the cookbook
header. Evidence: `docs/make_cookbook.jl` executed end to end; all 8 recipe
PNGs, the gallery, and the Markdown/notebook link check pass from a clean
`docs/build/`; full gate unchanged (docs-only).

## D026 — Release candidate at 0.1.0; install-from-checkout nuance (accepted, 2026-11-07, T018)

Problem: T018 must prepare release metadata without publishing, and the
install-from-checkout path had an unrecorded behavior that affects what a
user actually gets.

Chosen behavior: `Project.toml` version set to `0.1.0` (the first
adoption release) with a draft `docs/RELEASE_NOTES.md`; no tag, no
registration (that is T019, explicit request only). Recorded that
`Pkg.add(path=<git checkout>)` installs at **git HEAD** (last committed
state), so uncommitted roadmap work is not picked up by that path; a
non-git snapshot installs via `Pkg.develop(path=)`. The release-candidate
verification used a working-tree snapshot (no `.git`) installed via
`Pkg.develop` in a clean depot.

Alternatives: keep the version at `0.0.1` (rejected — that is a dev
placeholder; `0.1.0` is the natural first registered version); register now
(rejected — policy requires an explicit user request, T019).

Compatibility impact: metadata only; no runtime or API change. The fresh
clean-depot install (core-only and optional-integration) and the full
`scripts/check.jl` gate (811,472 assertions, 97.97% coverage) pass on the
0.1.0 candidate. Julia 1.10 and Windows/macOS legs remain CI-only,
unre-run locally (recorded as unmet). Evidence: tasks/T018-release-readiness.md
(fresh-depot logs `/tmp/opencode/t018-fresh-gate2.log`,
`/tmp/opencode/t018-main-fresh.log`), docs/RELEASE_NOTES.md.

## D027 — Application benchmark methodology: stage-isolated PNG pipeline, fresh-process startup protocol (accepted, 2026-11-07, T020)

Problem: T021/T022 need trustworthy baselines before optimization, and the
T011 harness measures renderer primitives, not application patterns. A
naive "render + save" timing would attribute codec cost to the renderer.

Chosen behavior: `benchmark/app_benchmarks.jl` times each pipeline stage
separately — draw, boundary conversion (a standalone full-buffer
`toStraightAlpha` pass; `encode(opaque)` is therefore the codec floor, and
`encode(translucent) - encode(opaque)` shows boundary+entropy cost — and
encode — across flat/gradient/noise images, with per-item allocation bytes,
file sizes, and invariants asserted before timing. Startup is measured in
separate fresh processes (3 cached runs + 1 cold `JULIA_DEPOT_PATH` run)
with parent-measured wall time plus the probe's self-measured load / first
render / warm stages. The eight T011 comparison workloads are unchanged.

Alternatives: timing `encodePNG` alone and splitting it after the fact
(rejected — cannot isolate the boundary stage without a second codec pass);
a BenchmarkTools dependency (rejected — the repo pattern is plain
`time_ns`/`@allocated` scripts, and T020 adds no dependency).

Compatibility impact: none at runtime; benchmark/ additions only. Baseline
(headline medians, Julia 1.13.3, Ryzen 9 5980HS): canvas 1080p draw ~62 ms
(26.5 MB), 4K draw ~240 ms (101 MB), clip/layers ~350 ms (182 MB), 1080p
opaque flat encode ~36 ms (codec floor), translucent noise encode ~120 ms,
4K encode ~400 ms; startup cached load ~580 ms, first render ~2.5 s, warm
~38 ms, cold depot ~4.3 s. Targets for T021/T022 are recorded in
tasks/T020-application-benchmarks.md.

## D028 — Lazy codec discovery + precompiled draw entries (accepted, 2026-11-07, T021)

Problem: T020 baselines showed `using Vetra` costs ~580 ms in a
codec-enabled environment and the first render ~2.5 s. Decomposition:
`__init__` eagerly `Base.require`s every present optional codec
(JpegTurbo ~371 ms + PNGFiles ~257 ms, measured per package), and the first
fillRect/stroke/fillText calls JIT-compile the whole draw pipeline
(mask/rasterizer/text layout) at first use.

Chosen behavior: (1) codecs are discovered lazily — `__init__` no longer
requires them; each `_require*` checks `Base.locate_package` (never loads)
and `Base.require`s on first use, preserving D014/D019 install hints, and
`Base.showable(MIME"image/png")` is a locate-only check. (2) World-age
safety: every call that can cross a lazy-require boundary uses
`Base.invokelatest` (`png.save`, `xml.parse`, the ColorTypes kernels),
because a method instance compiled before the `require` cannot dispatch to
methods defined after it (observed failure: "method too new" on
`encodePNG` in a fresh process). (3) Precompile statements for 16 common
entry points (`fillRect`/`fill`/`stroke`/`strokeSegment`/`fillText`/
`measureText`/`drawImage`/`save`/`restore`/`saveLayer`/`clip`/`getColor`/
`encodeImage` etc.) move the first-render JIT to install time — no sysimage,
no new dependency.

Measured effect (fresh processes, T020 protocol, 3 cached + 1 cold run
before/after): cached load 579–587 ms -> 19–20 ms; first render
2468–2548 ms -> 28–32 ms; warm render 38–40 ms -> 30–32 ms; total cached
process ~3.3 s -> ~0.23 s. Reported install-stage cost: precompile+load
wall 1.7 s -> 3.8 s; cache .so 2.4 MB -> 6.2 MB (9.2 MB -> 6.6 MB total
artifact). Steady-state app-suite workloads unchanged within run spread
(r4/r5 vs r1–r3). Full gate green (811,472 assertions, 97.99%).

Alternatives: sysimage (rejected — requires a custom build for ordinary
users); keeping eager `__init__` discovery and precompiling only (rejected —
the codec load is the dominant `using` cost and most users never touch a
codec); per-codec `Base.require` at first use without `invokelatest`
(rejected — world-age failure observed).

Compatibility impact: `using Vetra` no longer loads optional packages
(side-effect reduction); a process that adds a codec package at runtime and
then uses it works without restart (strictly better than D019's
"restart after adding"). Install hints, core-only behavior, and D019's
stale-cache scenario all preserved (codec_loading_tests 2/2). This supersedes
D019's eager `__init__` loop (the runtime-discovery property is retained, the
eager-load timing is not).

## D029 — Fused single-buffer gradient fill (accepted, 2026-11-07, T022)

Problem: T020 baselines showed repeated non-solid gradient fills allocate two
full-canvas buffers per fill — the coverage `mask` plus a `fillImg` canvas the
gradient is drawn into before `applyOpacity` + MaskBlend cut-out + Normal
composite (26.5 MB @1080p, 101 MB @4K, 182 MB @clip_layers-12 draw allocation).

Chosen behavior: gradient paints (linear/radial/angular) composite in place
from the coverage mask alone. The former pipeline's exact arithmetic
(applyOpacity's `o = roundHalfAway(255 * opacity)` scaling, blendMask's
`UInt8(ch * k / 255)` cut-out, the paint's blend) runs in three simple passes
over one row scratch (4*width bytes, owned by the call — no global buffers):
the geometry loop samples the gradient into the row (horizontal hoists one
sample per column into a second raw row, since the cut-out mutates the row in
place), `_cutRowOut!` applies the cut-out, `_blendRowInto!` composites with
blendRect's exact per-pixel branches (NormalBlend opaque-copy fast path,
OverwriteBlend straight copy, generic `blender(mode)`), mode branch hoisted
out of the pixel loop. ImagePaint/TiledImagePaint keep the 2-buffer pipeline
unchanged (their source is a full canvas that must exist). Stop positions are
validated finite before any destination write: non-finite positions made
`gradientColor` throw an accidental `InexactError` mid-fill (which the fused
path would have allowed to commit partial rows to the destination); the fused
path now throws a deliberate `ArgumentError` up front, preserving the
all-or-nothing error contract of the old pipeline.

Measured effect (T020 protocol, 5 baseline vs 3 final runs, medians): draw
allocation 25->17 MB @1080p, 96->64 MB @4K, 173->131 MB @clip_layers
(-24% to -36%); canvas_1080p/clip_layers wall time -3 to -5 ms,
repeat_1080p neutral. One consistent regression: canvas_4k/draw +12-15 ms
(+5%) across all final runs vs a non-overlapping baseline spread — accepted as
the cost of the allocation win (a full-canvas buffer eliminated per fill
reduces GC pressure and heap high-water mark on allocation-sensitive
workloads). Byte-exact: a 4204-scene A/B corpus (3 gradient kinds x
horizontal/vertical/diagonal linear x 4 paths x 17 blend modes x 4 opacities x
3 backgrounds, plus image/tiled controls and globalAlpha layers) is
byte-identical between the original 2-buffer pipeline and the fused path; the
corpus caught two real regressions during development (alpha channel left
uncut; horizontal double cut-out after the 3-pass restructure). Full gate
green at 98.01% (5662/5777 measurable lines); 42-assertion hand-derived
regression testset (incl. the multi-row horizontal double-cut pin,
MaskBlend-over-translucent and rounded-zero-opacity cases, partial-coverage
× opacity, opacity tie/neighbors, and the non-finite-stop error contract).
Independent review (openai/gpt-6-astra, 2026-11-08): no must-fix
pixel-arithmetic findings; three should-fix items (stop validation,
regression-pinning tests, stale comments) implemented.

Alternatives: a single merged sample+cut+blend loop (rejected — measured ~5 ms
slower at 1080p; the merged body defeats the compiler's simple-pass
scheduling); 2-pass with the cut-out fused into the composite pass (rejected —
the composite pass becomes as heavy as two of the original passes, total
~51 ms vs ~50.5); keeping the 2-buffer pipeline and reusing a caller-owned
`fillImg` (rejected — would push the buffer through the public
`fill`/`fillPath` API, changing the no-aliasing output contract for the
benefit of one call site).

Compatibility impact: output pixels, error messages, premultiplied
boundaries, rounding, and the ImagePaint/TiledImagePaint pipeline are
unchanged; one fewer allocation per non-solid gradient fill. The row scratch
is call-local (independent-call behavior, no shared mutable state).

## D030 — Recording contract: kernel-level display list, snapshot ops, strict
vector export (accepted, 2026-11-08, T023)

Problem: T024–T026 (CPU replay, SVG export, PDF export) need a bounded
recording contract before coding, and the contract must not disrupt the
immediate `Context` API or bend the D007 backend seam.

Chosen behavior (full text in docs/RECORDING.md): a recording is a list of
**core-kernel invocations** in call order (`FillOp`/`StrokeOp`/`DrawImageOp`
from `fillPath`/`strokePath`/`draw`, plus group ops for layers and the
globalAlpha wrapper), captured by a one-shot `PictureRecorder(w, h)` with a
`RecordingContext` that mirrors the `Context` drawing surface. Every op
stores deep snapshots (path command buffer, paint with copied gradient
arrays and copied image payload, stroke settings, tform, cumulative clip
list, text pre-lowered to glyph outline paths at record time), so a
`Picture` is self-contained and later mutation of source objects is
irrelevant. CPU replay re-executes the kernel list — default-size replay is
byte-identical to direct drawing by construction, and non-default sizes
scale the logical canvas in vector space (never a raster enlargement).
Record-boundary errors fail fast: TiledImagePaint fills and non-solid stroke
styles raise `ArgumentError` at the call, no op appended. Export v1 is
**strict**: SVG (solid/linear/radial, transforms, clipPath, nested groups,
group-unit `opacity`, base64 PNG images, glyph outlines — no angular
gradients, no clearRect, no non-Normal blends) and PDF (single page,
ShadingType 2/3 with the ellipse-to-circle CTM trick, Form XObject
transparency groups, FlateDecode RGB images via stdlib Compression, same
unsupported rows) each raise before writing any file, with `rasterFallback
= true` as the documented opt-in whole-picture raster. Text is outlines
everywhere (no font embedding, no licensing surface); no new dependencies
(SVG export is string output; PDF is stdlib only).

Alternatives: recording `Context`-method calls instead of kernel invocations
(rejected — replay would have to re-derive the context wrappers, duplicating
semantics); per-op raster fallback in export (rejected — re-creating
clip/blend context per op is a second renderer; whole-picture fallback is
simple and honest); `mix-blend-mode` in SVG v1 (rejected — renderer support
varies; silent loss is forbidden and a documented follow-up is safer); font
embedding for PDF text (rejected for v1 — outlines are already computed at
record time and avoid the licensing surface).

Compatibility impact: design only — no public symbols, no raster behavior
change, no new dependencies. Extends the D011 reserved
Picture/PictureRecorder seam and the D007 "per-pixel operations a backend
executes" phrasing (a display list is that op list with the CPU backend as
reference). Existing `Context` callers are untouched; recording is opt-in.

Evidence: docs/RECORDING.md (contract, capability matrix, canonical
validation scenes); task record tasks/T023-recording-design.md.

## D031 — Paragraph layout and shaping contract; T028 core-only, T029
provider-gated (accepted, 2026-11-09, T027)

Problem: T028–T029 need a bounded text contract that adds wrapping,
styled runs, fallback, cluster indices, shaping, and bidi without
silently changing the pinned T009 font/layout API (`typeset`/
`measureText`/`layoutBounds`/`computePaths`/`fillText`/`strokeText`
stay byte-exact, per docs/TEXT_LAYOUT.md §10).

Chosen behavior (full text in docs/TEXT_LAYOUT.md): **T028 ships
core-only with zero new dependencies** — an additive `Paragraph`/
`ParagraphLayout` layer over the existing `typeset` machinery (width/
height/overflow box, v1 wrap opportunities = white-space set + explicit
`\n` with no UAX#14 mid-word breaking, paragraph-level line height,
existing alignment enums, styled runs = existing `Span`/`Font`,
fallback = the existing `Typeface.fallbacks` chain formalized by
`withFallback` + a `.notdef`/zero-advance missing-glyph policy,
metrics, and vendored UAX#29-subset grapheme clusters with a
documented per-codepoint fallback). **T029 is specified but
provider-gated**: the shaper interface (raw font bytes + codepoints +
script/language/direction → per-cluster GID/advance/offset; GID →
native outline by direct loca/glyf index via additive
`glyphPathByGid`), UAX#9 direction model (paragraph-level base
direction, logical cluster indices, visual permutation exposed), and
behavior requirements (Arabic joining, Indic conjuncts, combining
marks, missing glyphs) are fixed by contract, but **no provider is
adopted**: the General registry (checked 2026-11-09) has no maintained
Julia shaping package (`HarfKit.jl`/`Pango.jl` delisted; full package-
name sweep of the registry tree; FreeType/Cairo exist but do not
shape), so options (a) re-emerged binding, (b) `HarfBuzz_jll` (v8.5.1+0)
+ thin `ccall` bindings, (c) pure-Julia UAX#9 + GSUB-subset shaper
(needs an explicit D015 extension for a GSUB reader), (d) defer are
recorded and T029 stays blocked until one is chosen. T028 renders LTR
only; RTL raises a named `ArgumentError`. Test fonts: existing pinned
fixtures for T028; new pinned OFL Noto Sans Arabic + Noto Sans
Devanagari for T029; shaping expectations from a pinned external
reference (`hb-shape` or equivalent) or hand derivation — never from
the code under test.

Alternatives that matter: a full UAX#29/UAX#14 reimplementation in core
(rejected — table surface and CJK/emoji correctness cost outweigh the
v1 use cases; the shortcut is recorded in the doc); adopting
`HarfBuzz_jll` + own bindings immediately (rejected without a
separate dependency-policy decision — it is a binary dependency,
D030-style minimalism applies); making T029 optional-shaper with a
silent unshaped fallback (rejected — silent no-join Arabic is exactly
the "silent loss" the export contract forbids; the named error is the
honest v1 state).

Compatibility impact: design only — no public symbols, no raster
behavior change, no new dependencies. Also supersedes D030's
"FlateDecode RGB images via stdlib Compression" note for the PDF
writer: the frozen build has no stdlib `Compression` and T026 shipped
uncompressed streams (recorded in tasks/T026-pdf-export.md and
docs/RECORDING.md §6.2).

Evidence: docs/TEXT_LAYOUT.md (contract, registry sweep, provider
options, worked examples, reference protocol); task record
tasks/T027-text-design.md.

## D032 — JPEG/WebP encode providers and codec contracts (accepted,
2026-11-09, T030)

Problem: T031 (JPEG encoding) and T032 (static WebP read/write) need
maintainable, artifact-backed codec paths that are Julia 1.10 compatible
and do not add hard dependencies (D008/D014/D019). D014 deferred WebP
("no stable Julia package") and left JPEG decode-only "as upstream"; both
needed an explicit decision before the format APIs exist.

Chosen behavior (full text in docs/JPEG_WEBP_CODECS.md):
- **JPEG encode = `JpegTurbo` 0.1.6** — the same opt-in package as T008
  decode (no new dependency; `jpeg_encode` verified in an isolated
  scratch environment). `encodeJPEG(image; quality = 92,
  background = white)`: exact integer premultiplied→straight composite
  (§2.2), JFIF with explicit 72×72 dpi density as contract (§2.3 —
  without it, independent tools like mupdf assume 96 dpi and scale the
  page 0.75×, measured), quality 1..100, dimension bound 65500 (the
  provider segfaults at 65501 — bisected, so the API boundary must
  reject first).
- **WebP = `WebP.jl` 0.1.3 + `libwebp_jll` 1.6.1+0** — a new opt-in
  extra (the registry's only WebP package; MIT; julia compat "1"; 18
  platform artifacts). Static subset only: `decodeWebP`/
  `decodeWebPDimensions` (feature scan first; **animation is rejected
  with a named `ArgumentError` before pixel decode** — the provider's
  decode crashes the Julia process at C level on animated files,
  reproduced on a pinned fixture) and `encodeWebP(image; lossy = true,
  quality = 75)` always RGBA (lossless ignores `quality` — the provider
  API has no lossless quality parameter), dimension bound 16383.
- **Validation without a second decoder** (no WebP tooling on the
  machine; mupdf refuses WebP): pinned Google gstatic gallery fixtures
  (sha256 recorded) for decode dimensions; lossless round-trips exact
  for opaque pixels and for alpha (VP8L approximates RGB under α=0 —
  measured 81/3072 mismatches, all in the α=0 corner); lossy validation
  is dimensions + a PSNR floor only. JPEG interop uses PyMuPDF/mupdf
  1.28.2 as the independent decoder (max channel delta ≤ 8, measured
  4; PSNR floor, measured 48.78 dB at q92 on the pinned gradient).
- Test/docs plan: extend the D019 present/absent + shared-cache
  protocol to WebP; RIFF+WEBP magic dispatch; COMPATIBILITY/API rows
  land with T031/T032.

Alternatives that matter: a native WebP port (rejected — VP8/VP8L +
alpha + RIFF is a far larger surface than the QOI/BMP/GIF ports, and
D014's "no stable package" rationale no longer holds as of the
2026-11-09 registry check); direct `ccall` to `libwebp_jll` without
WebP.jl (rejected — duplicates a thin, tested, registry-shipped wrapper
layer); a different JPEG encoder (rejected — JpegTurbo is already the
pinned opt-in decode dependency, so encoding comes with it).

Compatibility impact: design only — no public symbols, no source
changes, no dependency changes until T031/T032. Amends D014's JPEG
("no encoder, as upstream") and WebP ("deferred") bullets to point
here. The `ArgumentError("Unsupported file format")` behavior for
`.jpg`/`.jpeg`/`.webp` writes and the WebP decode fall-through remain
until T031/T032 ship.

Evidence: docs/JPEG_WEBP_CODECS.md (contract + probe log §6); scratch
probes in `/tmp/opencode/codecprobe` (JpegTurbo 0.1.6, WebP 0.1.3,
JpegTurbo_jll 3.2.1+0, libwebp_jll 1.6.1+0, PyMuPDF 1.28.2; commands
recorded); task record tasks/T030-codec-design.md.

## D033 — T029 shaping provider: HarfBuzz_jll + thin ccall bindings
(accepted, 2026-11-09, T029; selects option (b) of D031 §6)

Problem: T029 needs an external shaper per docs/TEXT_LAYOUT.md §5/§8.
D031 §6 (2026-11-09 registry sweep) found no maintained Julia
shaping package in the General registry (`HarfKit`/`Pango` delisted);
option (b) — a JLL binary + our own thin `ccall` surface — was a
candidate pending a dependency-policy decision (this one).

Chosen behavior (implementation in src/formats/shaping.jl, T029):
- **Provider = `HarfBuzz_jll` 100.15001.0+0** (JLL wrapper registry;
  MIT; artifact 1.7 MiB; 18 platform wrappers; bundles harfbuzz
  15.1.0; julia compat "1.6.0-1"; deps are artifact-only JLLs —
  Fontconfig/FreeType2/Glib/Graphite2/Cairo/Libffi — no build
  system). It is an **opt-in extra** (D014/D032 pattern): lazy
  `require` on first shaped call with an install hint; core-only
  and legacy LTR paths are byte-unchanged and load it never.
- **Thin ccall surface** (~12 symbols): `hb_blob_create` →
  `hb_face_create(blob, 0)` → `hb_font_create` → buffer
  (`set_direction`/`set_script`/`set_language`/`add`) → `hb_shape`
  → `hb_buffer_get_glyph_infos`/`_positions` → destroy. Verified
  ABI (C `offsetof`/`sizeof` against both the 12.3.2 system lib and
  the 15.1.0 artifact — identical for everything used):
  `hb_glyph_info_t` = 5×uint32 (codepoint/gid@0, mask@4,
  cluster@8); `hb_glyph_position_t` = 5×int32 (x_advance@0,
  y_advance@4, x_offset@8, y_offset@12); `hb_direction_t`
  LTR=4, RTL=5; `hb_script_t` = 4-byte tag. Note:
  `hb_face_create` takes an `hb_blob_t*` in all modern versions —
  the legacy raw-bytes signature segfaults on both 12.3.2 and
  15.1.0. `hb_face_get_glyph_count` (not `hb_face_count_glyphs`)
  in both.
- **ccall library expression must be a global String path** in this
  build (`const JLLLIB = HarfBuzz_jll.libharfbuzz`; locals and
  `Ptr` globals are rejected/misbehave — recorded probe finding).
- **Reference protocol (§8 option 2)**: expectations come from the
  system libharfbuzz **12.3.2** through a plain C driver
  (`tools/oracle/hb_refshape.c`, no Julia in the loop), pinned to
  `test/reference/shaping_reference.tsv` (+ sha256 sidecar) over the
  pinned OFL fonts `NotoSansArabic-Regular.ttf` /
  `NotoSansDevanagari-Regular.ttf` (`test/fixtures/`, sha256
  sidecars, `scripts/fetch_shaping_fixtures.jl`). The JLL 15.1.0
  and the 12.3.2 reference agree on **all 10 pinned cases**
  (gid/cluster/advance/offset identical; recorded in the task
  record), so the tests pin the 12.3.2 reference while running on
  whatever harfbuzz the JLL bundles.
- **Integration (contract §5)**: `shapeText` returns per-cluster
  `Vector{Vector{ShapedGlyph}}` (gid, advance, xOffset, yOffset —
  font units, like `getAdvance`); `glyphPathByGid(tf, gid)` reads
  glyf by index via the existing internal reader (no cmap).
  `ParagraphLayout` gains `shaped` (the logical→visual
  permutation); engagement: `RightToLeft` paragraphs require the
  provider (named `ArgumentError` without it — replaces the T028
  "RTL requires the T029 shaper" gate), LTR text containing
  strong-RTL codepoints shapes when the provider is present and
  keeps the T028 documented isolated-forms rendering when absent.

Alternatives that matter: (a) a General-registry HarfBuzz binding —
none maintained exists as of the 2026-11-09 sweep, and `HarfKit`'s
repo is delisted/stale; (c) a pure-Julia GSUB-subset shaper —
rejected here: far larger surface, Indic coverage is the risk, and
the registry check that motivated it predates the JLL artifact
verification done for this decision; (d) defer — superseded by the
user selecting option (b) on 2026-11-09.

Compatibility impact: one new opt-in extra (`HarfBuzz_jll`) in
`Project.toml` `[extras]`/`[targets]` + the docs environment;
additive `ShapedGlyph`, `shapeText`, `glyphPathByGid`, the
`ParagraphLayout.shaped` field, and `newParagraph` no longer throws
for RTL (it defers to layout time). No public symbol or legacy
behavior changes; T009–T028 fixtures stay byte-exact.

Evidence: probe log in tasks/T029-unicode-shaping.md (dual-library
shaping of the 10 pinned cases, ABI `offsetof`/`sizeof` C check
against both versions, symbol-table diff of the 12 used symbols);
`test/shaping_tests.jl` (binding vs pinned reference, bidi
permutation, missing-glyph policy, RTL/LTR paragraph layout and
render); codec-loading protocol extended to HarfBuzz.

## D034 — Independent 2D Canvas and optional rendering backends

Status: **R000 planning approved; implementation contracts await
R010 review** (2026-11-10). Design and agent work plan:
[Canvas](CANVAS_DESIGN.md), [R000–R099](../tasks/CANVAS_ROADMAP.md).

The user requested a renderer-independent Canvas covering CPU, GPU through
**Vulkan.jl**, browser Canvas APIs, existing image formats, Jupyter notebooks and
PDF. 3D is a future milestone. This supersedes the old roadmap's GPU deferral;
it does not claim any new backend is implemented.

Direction:

- SOLID is enforced through separated responsibilities, small public versioned
  protocols and provider-owned multiple dispatch. New backends/codecs/storage/
  media/display integrations require no core source/metadata/registry edits;
  R013 proves this with external packages and reusable conformance tests. New
  semantic primitives still require reviewed contract evolution.
- Design for use beneath future GUI and plotting libraries: host-owned event
  loops/surfaces, headless metrics, reusable recordings/assets, geometric hit
  tests, conservative invalidation and accurate world→local mapping before
  Float32 render geometry. R014 tests external consumers; widgets, event routing,
  plot models/scales and statistical processing remain consumer responsibilities.
- Pixel storage and execution are independent: host Matrix/Vector and optional
  StaticArrays integrate through explicit layouts, copy/borrow/writeback and
  CPU/GPU transfer boundaries (R022/R023). Immutable static arrays are inputs or
  newly constructed outputs, not writable targets; float storage does not imply
  higher internal render precision.
- Temporal media is a separate optional frame pipeline (R064–R069): decode and
  edit existing GIF/WebP/MP4 frames, encode, record and concatenate with explicit
  timing/loop/color/alpha and metadata policies. This supersedes GIF-encode and
  animation deferrals for the new milestone, while preserving the unsafe-static-
  WebP rejection guard. Provider/codec choices await runtime probes and review.
- Media source review identifies WebP inline-helper/library/ABI boundaries and
  VideoIO duration/seek probes; it does not establish a CFR-only limitation.
  R064 also resolves the inspected FFmpeg build's nonfree distribution constraint
  before selecting dependencies. Preserve streaming and explicit timing/matte/
  track policies; no blanket lossless concatenation or whole-output-buffer API.
- One Julia-native frontend/state/layout contract emits owned, backend-neutral
  commands/assets. Concrete backend types execute through multiple dispatch;
  pixel kernels do not dynamically branch on backend choice.
- Reuse the CPU kernels, existing recordings, glyph layout and SVG/PDF writers.
  Distinguish render backends from codecs and notebook display adapters; do not
  implement a separate renderer for each image file format.
- Heavy GPU/browser integrations stay optional. R040 verifies Vulkan.jl's real
  wrapper/shader/platform requirements before R010 freezes package boundaries;
  a backend's higher Julia minimum must not silently raise the CPU core minimum.
- Reviewed [Vulkan research](CANVAS_RESEARCH.md) leaves shader selection open:
  experimental SPIRV.jl exists but the inspected Vulkan compat differs from 0.7;
  OpenCL Kernel SPIR-V does not establish a Vulkan compute route. Require actual
  Vulkan-environment shader execution and complementary runtime validation.
- New Canvas semantics are explicit for coordinate spaces, alpha, sampling,
  clipping, state, clear, compositing and resource lifetime. Existing Context
  compatibility is reviewed separately, not silently changed to match a browser.
- Strict capability errors are the default. Equivalent lowerings and opt-in
  raster fallback are reported and tested; no hidden CPU rendering in GPU claims.
- Parallel streams have separate worktrees/owned paths and shared-interface
  review gates. The coordinator independently validates and approves each task.
- Final task R099 publishes an executed, genuinely interactive browser tutorial
  via GitHub Pages CI. R098 supplies the illustrated, executable README.
  Native Vulkan examples do not pretend to execute on a static web page.

Evidence so far: current source inventory and M002's passing four-platform CPU
tests/benchmarks (run 42811680553). Vulkan/browser execution, complete Canvas
conformance and the new tutorial remain future task criteria. Research sources
and compatibility probes are recorded in the design/plan, not inferred from
the CPU evidence. Package registration remains user-owned.

## D035 — Additive Julia-native API with explicit storage order (M003)

Status: **accepted and independently validated**; evidence in `docs/HANDOFF.md`.
Supersedes D024's concrete-Matrix-only import restriction and the legacy-only
naming convention without removing legacy callers or changing rendering kernels.

- Prefer snake_case and `!` mutators. Alias mutation-homogeneous generics;
  use typed adapters when a legacy generic mixes constructors and mutators.
  Recorder finalization consumes state and is named `finish_recording!`.
- Share Base/LinearAlgebra generics for owned-type methods; `dot` and `normalize`
  must not become competing exports. Preserve Vec2's legacy magnitude `length`
  without making it an AbstractVector.
- Keep `Image(width, height, data)`'s three fields and row-major premultiplied
  RGBA bytes. Inner constructors reject invalid dimensions, overflow and wrong
  buffer lengths. The supplied vector remains borrowed; callers must not resize it.
  No unchecked public constructor or redundant stored byte count is needed.
- Expose `[row, column]`, row-major linear access/iteration/`eachindex`, and
  coherent size/axes/begin/end. Image remains duck-typed, not an AbstractMatrix;
  pretending column-major storage would misrepresent its linear indices.
- Validate one-based axes before color-import reads. Accept range-selected
  views without a source copy and materialize top-level transposes; reject
  unsupported wrappers explicitly. Preserve alpha conversion and rounding.
- Runtime dependencies remain standard libraries; declare optional provider
  UUIDs/compatibility while retaining D028's lazy first-use loading.

Evidence: `test/api_native_tests.jl`, existing kernel/reference suites, coordinator
load-order probes and before/after benchmark smoke. No new Canvas backend is
implied by these additive interfaces.

## D036 — Correctness boundaries and HarfBuzz ownership (M004)

Status: **accepted and independently validated**, 2026-11-11. Evidence in
`docs/HANDOFF.md`; broader text/layout changes remain R012's responsibility.

- Fix independently reproduced behavior rather than preserve the upstream crop
  early-exit bug. Use overflow-safe containment on both crop APIs. Dash setters
  and getters copy storage for Context and RecordingContext.
- Keep cmap-12's standard 16-byte header and add range/length validation before
  expansion. Reject the candidate's omitted-language-field layout; tests use
  independent OpenType specification bytes.
- Cache one HarfBuzz (blob, face, font) triple per live `OtcOpenType` in a
  WeakKeyDict. A finalizer holding only native pointers releases font, face and
  blob; the cache does not strongly retain every parsed font. Blob mode 0 is
  DUPLICATE: HarfBuzz owns its byte copy. `GC.@preserve` keeps the owner alive
  for the complete native-use interval. This adds no thread-safety guarantee.
- Intern language via `hb_language_from_string`; require non-empty ASCII input
  without introducing a BCP47 parser. Native buffer cleanup is in `finally`.
  Constructors use their documented empty-object failure contracts, and
  `hb_buffer_allocation_successful` is checked before input, after adding input
  and after shaping. NULL-only checks are insufficient for these APIs.
- Keep D033's documented pure-LTR paragraph engagement limit. R012 reviews the
  broader text contract; documentation publication stays at final R099.

The coordinator verified the OpenType 1.9.1 layout and HarfBuzz 15.1.0 source,
then injected failures and GC through the existing native function table in
isolated probes. RSS/Julia allocation measurements alone are not lifetime proofs.

## Adding a decision

Append a short entry with status, task, problem, chosen behavior, alternatives
that matter, compatibility impact, and evidence. Supersede old entries explicitly
rather than rewriting historical rationale without a trace.
