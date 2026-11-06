# T007a — Blend modes, paint kinds, image drawing

Status: done (W5, integrated 2026-10-30). Dependencies: T006. Split from T007.
Goal: complete the paint pipeline short of masks/effects: every W3C blend
mode, every `Paint` kind, image sampling, and image drawing.

## Inputs and upstream references

- `.reference/upstream/src/pixie/paints.nim`: `PaintKind`, `Paint`, `ColorStop`,
  `newPaint`, `copy`, `parseSomePaint`, `fillGradient`, the Solid/Image/
  TiledImage/gradient branches of `fillPath`.
- `.reference/upstream/src/pixie/blends.nim`: `blendDarken`, `blendMultiply`,
  `blendColorBurn`, `blendLighten`, `blendScreen`, `blendColorDodge`,
  `blendOverlay`, `blendSoftLight`, `blendHardLight`, `blendDifference`,
  `blendExclusion`, `blendHue`, `blendSaturation`, `blendColor`,
  `blendLuminosity`, `blendOverwrite`. (Mask blends are T007b.)
- `.reference/upstream/src/pixie/images.nim`: `draw`, `drawTiled`, pixel sampling
  and transform handling they use.
- Fixtures: `blend_*.tsv` (all 20 modes; use the 16 W3C + overwrite here),
  `draw_translate.{raw,meta}`, `draw_scale2.{raw,meta}`; `mix`/`blend_normal`
  regressions already exist (T002).

## Scope

- `BlendMode` full upstream enum order (including the four mask modes so the
  enum is stable), with the 16 W3C blend functions + `blendOverwrite`
  implemented. Mask-mode dispatch must raise a clear `ArgumentError` until
  T007b (no silent fallback).
- `Paint` kinds: Solid, Image, TiledImage, LinearGradient, RadialGradient,
  AngularGradient; `colorStop`; `newPaint` if upstream exposes it; gradient
  handles/stops and image transform fields; color/string constructors.
- `fillPath(image, path, paint)` non-solid branch: build the upstream
  mask/fill images and composite with the paint's blend mode, ported exactly.
- `draw(image, src, transform)`, `drawTiled`, and the `Context` `drawImage`/
  `draw` wrappers that do not need masks.
- `parseSomePaint`: keep the implemented `#RGB`/`#RRGGBB` subset; add
  `rgb()`/`rgba()`/named colors only if the pinned parser's exact behavior is
  ported and tested, otherwise leave them raising and record it.
- No masks/clip/saveLayer/globalAlpha (T007b), no effects, no text.

## Acceptance criteria

- `test/paint_tests.jl` (new): every implemented blend table (`blend_*.tsv`)
  compared exhaustively; gradient endpoints/midpoints hand-checked; image and
  tiled paint sampling at known coordinates (including out-of-bounds); color
  stop ordering/clamping; non-solid fillPath on a small hand-derived case.
- `test/image_ops_tests.jl` (new, draw part): `draw_translate.raw` and
  `draw_scale2.raw` reproduced exactly (0 mismatching bytes), including the
  `snapToPixels` path; malformed/invalid transforms report errors.
- `Pkg.test()` keeps all 6,484 existing assertions green;
  `scripts/check.jl` > 95% line coverage across `src/` (record exact %).
- Every exported symbol has a linked test; mask modes are exported but raise
  with a message naming T007b, or are absent until T007b (state which).

## Validation

`julia --startup-file=no --project=. -e 'using Pkg; Pkg.test()'` and
`julia --startup-file=no --project=. scripts/check.jl`; Julia 1.13.3. No new
dependencies without a recorded decision (D008); no `@fastmath`, unsafe
indexing, SIMD, or threads. Do not edit shared docs; do not commit.

## Results and handoff

**Interrupted 2026-10-30 04:34** at the user's request (reboot), before
completion. Partial work saved in `artifacts/wip-t007a/`:
`blends.jl` (new: full `BlendMode` enum 0..19, 16 W3C blends + Overwrite,
`blender` dispatch with mask modes raising for T007b) and `rasterizer.jl`
(WIP: `BlendMode` moved out, fill paths dispatch via `blender`). The module
did not precompile because `Vetra.jl` never included `blends.jl`; `src/` was
then restored from the last green T006 coverage snapshot and re-verified at
6 484 assertions / 99.58%. `paints.jl`, `Vetra.jl`, and tests were untouched.
Resume steps are in `artifacts/wip-t007a/README.md` and docs/HANDOFF.md.
No results/coverage numbers are claimed for T007a yet.

Record commands/results, fixture rows compared, coverage %, deviations, and
what T007b/T008/T009 still need.

## Results (test-coverage session, 2026-10-30)

Commands (from repo root, `main`, no commits made):

- `julia --startup-file=no --project=. -e 'using Pkg; Pkg.test()'`
  → **pass** (`Testing Vetra tests passed`, exit 0).
- `julia --startup-file=no --project=. scripts/check.jl`
  → `coverage gate: src/ line coverage = 98.54% (2230/2263 measurable lines)`
  → `scripts/check.jl: OK` (gate: > 95%).

Assertion counts (per testset, final run): Package loads 1; T001 78; T002
5813; T003 133; T004 235; T005 214; T006 6 + 4; T007a blends **77**;
T007a paints and gradients **111**; T007a image/tiled paints **57**;
T007a draw fixture parity **4**; T007a draw hand-derived **42**;
T007a sampling/resize **68**. Total 6,843 = 6,484 pre-existing (all green)
+ **359 new T007a assertions**.

Fixtures compared: all 20 `blend_*.tsv` tables × 121 rows = **2,420 rows
0-mismatch** (16 W3C + Overwrite via `blender` dispatch; the 3 mask pixel
functions vs their TSVs). `draw_translate.raw` and `draw_scale2.raw`:
**0 mismatching bytes** each (exact parity, no tolerance).

Deviations from plan:

- One genuine src bug fixed: `src/geometry.jl angle(v::Vec2)` called
  bare `atan2`, which is not in this Julia 1.13.3 build's export surface
  (runtime `UndefVarError` — radial/angular `fillGradient` was dead at
  runtime). Changed to `atan(v.y, v.x)` — the same two-arg form already
  used by `strokes.jl _angle`, verified quadrant-equivalent (π/4, −π/2, π,
  0). After the fix: all 20 blend TSV tables (2,420 rows) and both draw
  fixtures re-verified 0-mismatch; T001–T006 unchanged.
- All other failures during the session were test-expectation errors,
  corrected against pinned upstream: integer `draw`/`blendRect` placement
  (`src(0,0)` lands on the pos pixel — rule pinned by `draw_translate.meta`),
  `mix`/`blendMask` truncating division (pinned by the TSV tables and
  common.nim formulas), `minifyBy2` odd-row/column arms, `subImage`/
  9-arg `drawImage` 0-based origins, and a Julia-1.13 `enumerate(Int)`
  quirk that silently built a 1-column input in the minifyBy2 test.
  No fixtures, tolerances, or src semantics changed beyond the `angle` line.

Still needed by successors: T007b (mask blends — `blender`/`draw`/`drawTiled`
dispatch currently raise "T007b" for the 3 mask modes; clip, saveLayer,
globalAlpha, image effects); T008 (formats: codec policy D008); T009 (fonts:
font policy D008); T010 context integration on top.

## Coordinator integration (2026-10-30)

- Reviewed the new tests: every expected value is fixture- or hand-derived
  (no values taken from the code under test); no tolerance or fixture changes.
- Visibility aligned with the pinned source: `gradientColor`,
  `fillGradientLinear/Radial/Angular`, `blendRect`, `drawSmooth`,
  `solidColorRGBX`, `angle`, `fixAngle` are internal (not exported); tests use
  `Vetra.` qualification. Re-ran the gate after the trim: 6 843 assertions,
  `src/` coverage **98.54% (2230/2263)**, `scripts/check.jl: OK`.
- `blend_alpha.tsv` remains exhaustively covered by T002; all other 20 blend
  tables are covered here. `parseSomePaint` stays the `#RGB`/`#RRGGBB` subset;
  `rgb()`/`rgba()`/named color strings still raise (unchanged subset).
- Follow-up work is T007b only; T008/T009 depend on it.
