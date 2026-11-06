# Current handoff

Updated: 2026-11-06

## State

Local `Pkg.test()` fix (2026-11-06, D019): reproduced 5 failures and 30
errors in the format suite with the user's exact command. Vetra's cached
module had skipped top-level optional codec loads during a core-only
precompile. `Vetra.__init__` now discovers and loads available codecs in the
current environment. No cache clearing or explicit codec imports are needed.
New `test/codec_loading_tests.jl` (included in runtests) first loads the core
without codecs, then tests PNG/JPEG/SVG in a codec-enabled process sharing
the cache; it failed before the fix and passes after it.

Verified on Julia 1.13.3:
- `julia --startup-file=no --project=. -e 'using Pkg; Pkg.test()'` — passed.
- `julia --startup-file=no --project=. scripts/check.jl` — passed,
  98.0% coverage (5235/5342 measurable source lines).
DeepSeek review was attempted but blocked by insufficient account funds.
Existing tutorial work was preserved, with obsolete cache workarounds removed.
Next: review/commit when requested; this fix has not been committed or pushed.

Tutorial follow-up (2026-11-06): `docs/TUTORIAL.md` is a 14-section,
project-based guide, linked from the root and examples READMEs. It builds
an activity card and explains coordinates/alpha/mutation, paths, gradients,
transforms, clips, fonts, effects, compositing, formats, layout, tests,
and benchmarks. Examples reflect actual source APIs, including binary-string
QOI output, plain base64 payloads, image-space clips, and unsaved textBaseline.

Verification: the setup commands created `artifacts/tutorial-env`; all 13
drawing blocks were extracted verbatim into ignored `artifacts/tutorial.jl`
and passed 18 assertions with
`julia --startup-file=no --project=artifacts/tutorial-env artifacts/tutorial.jl`
on Julia 1.13.3. The images are in ignored `artifacts/tutorial/`.
The documented benchmark command
`julia --startup-file=no --project=artifacts/tutorial-env -e 'using PNGFiles; include("benchmark/run_benchmarks.jl")'`
completed all eight workloads. The command
`julia --startup-file=no --project=. scripts/check.jl` passed (98.0%,
5230/5337 measurable source lines). Local Markdown links/anchors and
`git diff --check` passed. The explicit-codec-import workaround used for
that first tutorial verification is now superseded by the D019 runtime fix.
DeepSeek review was attempted but unavailable (insufficient account funds);
API claims were checked directly against source. Next: user review; these
documentation changes have not been committed or pushed.

**T000–T011 are complete — the board is done.** The port covers: core
pixels/compositing, geometry, paths/fills, strokes + full context
(state stack, clip/saveLayer/globalAlpha, `isPointInPath`, dash patterns
in strokes), the pinned examples, the full paint/blend/image-draw layer,
mask blends, every pinned image effect, all image formats except WebP
plus the SVG pinned subset, font parsing + text layout/rendering, and the
cross-feature integration tests.
T011 finished on 2026-11-06 with the gate at **`src/` coverage 98.0%**
(5230/5337 measurable lines). Benchmarks (release Nim reference,
corrected harness) are recorded in tasks/T011-release.md: the port is
faster on the text workload and within 1.2x on fill/stroke; gaps on
draw/PNG are accepted for this release (D016 — no optimization against
the parity gate without a separate reviewed task).

CI (D018, 2026-11-06): unit tests run on every push/PR (matrix
1.10/latest x ubuntu/windows/macos); a `benchmark` job runs the Julia
side on every push to main and uploads the TSVs as an artifact.
Windows fix (same day): `.gitattributes` forces `eol=lf` on text files
and marks `*.raw` binary — CRLF conversion on Windows checkouts was
corrupting the last column of fixture `.tsv` rows (readlines-based),
red on every Windows job since the first push; verified with a
`core.autocrlf=true` clone.

Remaining (policy, not technical): registration/publishing awaits an
explicit user request; "Vetra" was checked available in the General
registry on 2026-11-06 (404 at `P/Vetra`).

The public API for every remaining wave is defined in docs/API.md
(Flutter-inspired, D011): immutable Float32 geometry (`Vec2`/`Rect`/`Circle`),
column-major `Mat3`, stateful `Context`, `Path`, `Paint`/`BlendMode`, and the
reserved `Picture` backend seam. Implemented so far (`src/`):
`ColorRGB`/`ColorRGBA`/`ColorRGBX` (+ validated `rgb`/`rgba`/`rgbx`),
`Image` (premultiplied RGBA, row-major, 1-based pixel addressing), alpha
conversions, `mix`/opacity/coverage, `blendAlpha`/`blendNormal`;
`geometry.jl` (`Vec2`, `Rect`, `Circle`, `Segment`, `Line`, `Polygon`,
`Mat3`, `snapToPixels`); `paths.jl` + `rasterizer.jl` (`Path` builders,
`parsePath`, `transform`, `computeBounds`, `NonZero`/`EvenOdd`,
`computeCoverage`, `fillShapes`, `fillPath`, `overlaps` (T010)); `blends.jl` (enum 0..19, 16
W3C blends + Overwrite, mask pixel functions, `blender` dispatcher);
`paints.jl` (all six `Paint` kinds, `ColorStop`, `newPaint`, `copy`,
gradients, non-solid `fillPath`); `image_ops.jl` (`getRgbaSmooth`,
`minifyBy2`/`magnifyBy2`, `applyOpacity`, `subImage`, `blendRect`,
`drawSmooth`, `draw`, `drawTiled`, and the T007b effects:
`gaussianKernel`, `flipHorizontal`/`flipVertical`, `rotate90`, `diff`,
`invert`, `ceil`, `blur`, `resize`, `spread`, `shadow`, `superImage`,
`opaqueBounds`); `strokes.jl`
(`strokePath`/`strokeShapes`, caps, joins, miter limit, dashes); `context.jl`
(`Context`, save/saveLayer/restore, clip, globalAlpha, transforms, path
wrappers, fill/stroke, rect helpers, `strokeSegment`, `clearRect`,
`drawImage`/`draw` 3/5/9-arg, `isPointInPath` (T010), and `ctx.lineDash`
wired into context strokes (T010);
`formats/ppm.jl` (`encodePPM`/`writePPM`, binary P6) and, for T008,
`formats/{png,jpeg,bmp,qoi,svg,gif,io}.jl` (PNG via PNGFiles, JPEG decode via
JpegTurbo, SVG via XML — all opt-in `[extras]` per D014; BMP/QOI/GIF/PPM/
base64 native; magic-byte `readImage`/`writeFile` dispatch); for T009,
`fontformats/opentype.jl` (native OpenType subset: cmap 4/12, head/hhea/maxp/
hmtx/name/OS/2/post/loca 0-1/glyf simple+composite/kern v0/GPOS pair-pos,
upstream quirks preserved), `formats/fonts.jl` (Typeface/Font/Span/
Arrangement, typeset/layout, fillText/strokeText/readTypeface/readFont,
metrics, kerning) and the Context text state in `context.jl` (font/fontSize/
textAlign/textBaseline/lineDash, `measureText`, save/restore). All three
pinned examples reproduce their `.raw` fixtures with 0 mismatching bytes
(T006 tests).
Test suite: 811 407 passing assertions (T008: 796 581 — 796 459 pinned
fixtures + 100 synthetic format branches + 22 rasterizer MaskBlend, plus 32
stroke-layering assertions in the context test file and 10 gradient
assertions in paint tests; T009 adds 2 456: provenance, oracle metric/
kerning rows, 17 layout scenarios bit-exact, 14 rendered images 0-mismatch,
context text state, textCase (pinned Nim unicase tables), fallback/
hasGlyph semantics, negative-tie rounding, malformed-byte rejections,
synthetic mini font; T010 adds 4 965: isPointInPath scanline matrix,
dash phase, clip identity-space quirk, gradient under clip + transform,
text + clip, composite and nested state stacks).
Decisions: D010 (T002 API), D011 (API), D012 (waves), D013 (T007b effects
porting choices), D014 (T008 codec packages), D015 (T009 font parsing:
native OpenType subset). No WebP codec yet; CFF/TTC/SVG fonts unsupported
by design (D015).

Reference infrastructure (all in place, evidence-backed):

- Pinned upstream at `30bb510877f02cbf9643e4f904e33d1c90f` under
  `.reference/upstream/` (see upstream.toml / docs/UPSTREAM.md) and pinned
  dependency revisions under `.reference/pkgs/` (vmath@1b6080f4,
  chroma@08b0d655, zippy@cd562ba4, flatty@9c3f14cc, nimsimd@ba71ac4e,
  bumpy@93583f6f, crunchy@98eb6526).
- Oracle: `tools/oracle/emit_fixtures.nim` + `sh tools/oracle/build.sh all`.
  Built with Nim 2.2.12 (C backend), `-d:pixieNoSimd`, runtime checks ON
  (debug build), gcc 16.2.1, Linux x86_64. Exit code 0.
- Approved fixtures under `test/reference/` (9.1 MB, 233 files): 5 image
  triples (square, line, heart, draw_translate, draw_scale2: `.raw` +
  `.meta` + `.png`), 26 arithmetic/blend tables (`.tsv`), T008 format
  fixtures (SVG/BMP/QOI/GIF/JPEG/PNG masters), T009 font fixtures (6 TSVs +
  sidecars, 14 image triples: fill/stroke, basic1-4/7/8/8b, underline1,
  strikethrough1, ctx fillText/strokeText, ubuntu1), checksum sidecars
  (`*.sha256`, `sha256_raw=` in `.meta`). Each carries provenance (repo,
  revision, deps, toolchain, flags, source symbol; font fixtures also carry
  `font=`, `font_sha256=`, `font_license=`).
- Contract: docs/NUMERICAL_CONTRACT.md (formulas with source refs, incl. the
  two distinct premul→straight conversions and the 2708 measured valid-domain
  divergent rows, e.g. a=4, c=2 → 127 vs 128).
- Gate: scripts/check.jl runs tests with `--check-bounds=yes`, coverage on,
  and enforces the D009 rule (>95% measurable-line coverage under `src/`) by
  parsing the built-in `<file>.jl.<id>.cov` output (no extra dependency).

## Verification

Commands actually run in this environment (Julia 1.13.3), latest on
2026-11-06:

- `sh tools/oracle/build.sh fonts` → all 19 font fixtures emitted, exit 0
  (14 images + 5 TSVs; TSV sidecars and image checksums added by
  build.sh; 68 font_* files approved into test/reference/).
- `julia --startup-file=no --project=. -e 'using Pkg; Pkg.test()'` →
  "Testing Vetra tests passed": `Package loads` 1, `T001 reference fixtures`
  78, `T002 core` 5 813, `T003 geometry` 133, `T004 paths and fills` 235,
  `T005 strokes and context` 219, `T006` 6 + 4, `T007a blends` 74,
  `T007a paints and gradients` 111, `T007a image/tiled paints` 67,
  `T007a draw fixture parity` 4, `T007a draw hand-derived` 40,
  `T007a sampling/resize` 68, `T007b mask and layers` 148,
  `T007b image effects` 404, `T008 file formats` 796 459,
  `T008 synthetic format branches` 100, `T008 rasterizer MaskBlend branches`
  22, `T009 fonts and text` 2 456, `T010 context integration` 4 965 —
  **811 407 assertions, 0 failures**.
- `julia --startup-file=no --project=. scripts/check.jl` → tests passed plus
  `coverage gate: src/ line coverage = 98.0% (5230/5337 measurable lines)` →
  `scripts/check.jl: OK` (gate is `> 95%` per D009). Recorded coverage:
  **98.0%** for this run (was 97.87% at T009; T010's `isPointInPath`
  `overlaps` + dash wiring add exercised paths, and the T009 review
  cleanup of dead font branches keeps coverage up; remaining uncovered
  lines are upstream-faithful dead branches and the install-hint error
  paths for the opt-in packages).
- T010 evidence (test/context_integration_tests.jl, 4 965 assertions, all
  hand-derived): `isPointInPath` inside/outside/edge matrix incl. the
  upstream edge asymmetries (bottom edge excluded — hits on `segment.to`
  are discarded; right edge excluded — past the last hit —; donut and
  same-orientation overlap for NonZero vs EvenOdd; all four overloads;
  CTM applied to the path not the point), dash phase `[5,15]`/odd-length
  `[5,15,10]` with exact ink columns, dash + `globalAlpha`,
  `ArgumentError("Invalid line dash value")` on `[0,5]`, dash + caps
  (Round/Square vs Butt control) and dash + miter join, clip identity-
  space quirk (clip-then-translate and translate-then-clip both clip away
  a translated full-canvas fill), gradient under clip + transform, text
  (fill + stroke) inside a clip, composite and nested state stacks,
  fractional fixed32 edge truncation, and `font` round-trip.
- T010 review pass (DeepSeek subagent, 2026-11-06): 11 findings - 10
  addressed (stale COMPATIBILITY status header; wrong odd-dash interval
  comments in test + task doc -> `[35,50)`; clip geometry comment;
  globalAlpha-attribution comment; stray "mask" in a comment; added
  tests for font save/restore, dash + caps/joins, and fractional
  fixed32; rasterizer header lists `overlaps`). One finding dismissed:
  `copy(ctx.lineDash)` on save matches upstream, since Nim's
  `result.lineDash = ctx.lineDash` (contexts.nim L84) copies the seq.
  Re-verified: full gate green, T010 4963/4963 (4965 after the T011
  rotation regression test), coverage 98.0%.
- T011 release audit (2026-11-06): a DeepSeek review invalidated the first
  benchmark pass (debug-mode Nim reference + harness loop/timer bugs) and
  surfaced a genuine renderer bug — the quick-start translate+rotate
  fill/stroke raised `InexactError` where upstream renders fine (negative
  `leftRectArea` from a non-abs `fract`; uint8 wrap missing on
  `*(ColorRGBX, float32)`). Both fixed in src (rasterizer.jl, Vetra.jl)
  with a pinned-oracle regression fixture `ctx_rot` (tools/oracle
  `rotation` mode; byte-exact, 0 mismatching pixels) in
  test/context_integration_tests.jl. Corrected harnesses re-recorded:
  steady-state median, release Nim reference (`-d:release
  -d:pixieNoSimd`) — the port is faster on the text workload and within
  1.2x on fill/stroke; gaps: draw 6.4x, PNG encode 2.7x, PNG decode
  ~57x (D014 codec choice). No optimization applied (recorded as D016 —
  see docs/DECISIONS.md; optimization against the parity gate is a
  separate reviewed task). README quick start rewritten + verified
  run-clean; NOTICE audit completed (translated vmath/chroma/bumpy/flatty
  packages, fixture asset provenance, open TODO line removed);
  test/README.md and benchmark/README.md updated; two stale
  COMPATIBILITY rows corrected; "Vetra" checked unregistered in the
  General registry (available). The package was renamed to Vetra.jl
  (word-boundary rename; upstream `PixieError`/`pixieNoSimd`/lowercase
  upstream refs preserved, uuid unchanged), the old scaffold git
  history was discarded for a fresh single-commit `main`, and the tree
  was pushed to git@github.com:skynet-core/Vetra.jl (user-requested).
  CI gained the fetch_upstream step. Final gate green from the new
  location: 811 407 assertions, coverage **98.0%** (5230/5337).
  Post-release scrub (same day, D017): the old name was removed from
  everything the repo owns — commit message (amended + force-pushed),
  `VetraExamples`, the `.reference/upstream` checkout dir,
  `third_party/upstream.LICENSE`, docs prose; it remains only in
  upstream facts (pinned URL/repo name, `src/pixie/*.nim` symbol paths,
  `PixieError`, `-d:pixieNoSimd`, checksum-pinned fixture provenance).
- T007a fixture evidence: all 20 `blend_*.tsv` tables × 121 rows =
  **2 420 rows, 0 mismatches** (16 W3C + Overwrite through the public
  `blendXxx`/`blender`, the three mask pixel functions directly);
  `draw_translate.raw` and `draw_scale2.raw` = **0 mismatching bytes each**.
- T007b fixture evidence: `gaussian_kernel.tsv` — 16 radii × 288 weights =
  **0 mismatches** via the public `gaussianKernel`; all effect tests are
  hand-derived from the pinned formulas (both-pass blur truncation chains,
  spread max/min pools, shadow MaskBlend composition, minify/magnify resize
  fast paths).
- T008 fixture evidence: 14 pinned SVG fixtures + 5 BMP + 2 QOI + 4 GIF +
  4 JPEG + PNG masters all match their `.raw` buffers exactly (JPEG within
  the recorded 8-per-channel tolerance vs the upstream stb fixtures);
  synthetic branches (palette/top-down BMP, GIF LCT/interlace/disposal,
  JPEG Exif/resync, QOI encode op stream, PPM 16-bit, SVG style/url fills)
  pinned from the format specs / patched upstream oracle.
- T009 fixture evidence: 14 rendered text images (fill, stroke, basic1-4,
  basic7/8/8b, underline1, strikethrough1, ctx fillText/strokeText,
  ubuntu1) — **0 mismatching bytes each** vs the pinned-upstream oracle;
  all 6 metric/kerning TSVs exact (glyph ids, advances, kerning incl.
  GPOS-only Roboto pairs T,e −99.0 / W,o −31.0 and legacy-kern Ubuntu
  −55/−22, missing-rune → 0); all 17 layout scenarios (positions,
  selection rects, bounds) bit-exact, incl. the upstream-pinned
  `layoutBounds("Word") == (56, 28)` / `("Word\n") == (56, 56)` and
  `measureText("Hello world")` @12 → width 60 (test_contexts.nim).
- T009 review pass (DeepSeek subagent, 2026-11-06): 12 findings — 8 fixed in
  source (textCase no-op → pinned Nim unicase tables in
  src/fontformats/unicase.jl; `_otCodepoints` non-ASCII mis-decode;
  `getLeftSideBearing` first-trailing-glyph → 0 as upstream; `hasGlyph`
  must not walk fallbacks; `roundHalfAway` negative ties → away from zero
  (Nim `round` verified with the pinned toolchain); `post` version nibble
  validation; name UTF-16BE surrogate/tofu/odd-byte decode; GPOS
  value-format size counts all 16 bits), 1 intentional deviation documented
  in COMPATIBILITY.md (stricter glyf instruction EOF check), 3 recorded as
  out-of-scope API gaps (no `Font.paint` accessor — `paints` field is the
  port's API; finding list in the session record).
- `julia --project=. examples/{square,line,heart}.jl` → each writes a
  120 015-byte PPM; `examples/{png,jpeg,bmp,qoi,gif,svg,ppm}.jl` → each
  decodes its pinned fixture and (re)encodes/writes a preview under
  `artifacts/examples/`; `examples/showcase.jl` → prints all 8 sections and
  writes the tour canvas to `artifacts/examples/showcase.png`
  (PNG/JPEG/SVG parts need the D014 opt-in packages). Gotcha: this build
  keeps one shared precompile cache for the path-sourced Vetra — if the
  dev-env gate runs last, the frozen load-time `require` misses the opt-in
  packages and the PNG/JPEG/SVG examples raise install hints. Rebuild in
  the example env first: `rm -rf ~/.julia/compiled/v1.13/Vetra &&
  Pkg.precompile()` with the example env activated (verified run order).
- T006 tests compare all three in-memory images to `test/reference/*.raw`:
  **0 mismatching bytes each**; the PPM RGB payloads also equal the fixture
  RGB bytes.

Not done (not applicable or deferred):

- PNG fixtures are kept as a cross-check artifact; tests compare the canonical
  `.raw` buffers (row-major RGBA uint8, checksummed), not the PNG bytes.
- Git: the whole board is a single commit on `main`, pushed to
  git@github.com:skynet-core/Vetra.jl (history re-initialized at the
  package rename; the old scaffold commit no longer exists).

## Next action

**No implementation tasks remain** — T000–T011 are all `done` (2026-11-06).

Possible follow-ups, all awaiting user direction:
1. Register/publish the package (name "Vetra" checked available in the
   General registry on 2026-11-06; version 0.0.1; policy: only on
   explicit request).
2. If speed work is ever requested, the measured baselines are in
   tasks/T011-release.md and benchmark/results/ (the only
   below-reference workload is PNG decode — PNGFiles vs upstream zippy).

There is no WIP to resume: `artifacts/wip-t007a/` and
`artifacts/checkpoints/t007a-blends-wired/` are retired (the integrated tree
is the source of truth). Waves and specs: TASKS.md; API: docs/API.md.

## Open choices

- Codec dependency policy settled as D008 and applied at T008 as D014
  (PNG/JPEG/SVG via opt-in packages; BMP/QOI/GIF/PPM/base64 native; WebP
  deferred). Font parsing settled as D015 (native OpenType subset port;
  FreeType.jl rejected — GPOS kerning coverage and single-outline-source
  parity). Optimization settled at T011 by measurement: no bottleneck
  justified `@fastmath`/SIMD/threads (recorded in
  tasks/T011-release.md).
- T002 public API settled as D010; overall API settled as D011 (Flutter-
  inspired); board semantics settled as D012 (waves); T007b effects porting
  choices (rotate90 return value, `ceil`/`diff` extending Base generics)
  settled as D013.
- Package name "Vetra" checked available in the General registry on
  2026-11-06 (404 at `P/Vetra`); registration itself awaits an explicit
  user request (policy).

## Active ownership

- Coordinator/integrator: this OpenCode session (Qwen3.8, 2026-11-05 run).
- Implementer: local `qwen3.8:27b` subagent (all coding work, user directive
  2026-10-28); one wave at a time, shared docs integrated by the coordinator.
- Working tree: /home/vasyl/Dev/skynet/julia/Vetra.jl, single commit on
  `main`, pushed to git@github.com:skynet-core/Vetra.jl.

---

## T000 record (previous handoff, kept for provenance)

T000 is complete as a scaffold. The package has an empty module and one import
smoke test.

- TOML, VS Code JSON, and CI YAML were structurally checked.
- Local Markdown links and task/script references were checked.
- Julia was not installed in the creation environment; bootstrap, tests, and
  CI have not been executed there.
