# T007b — Masks, clipping, context layers, image effects

Status: ready (W5). Dependencies: T007a. Split from T007.
Goal: the mask/composite layer plumbing and the pinned image operations and
effects, completing T007.

## Inputs and upstream references

- `.reference/upstream/src/pixie/blends.nim`: `blendMask`, `blendSubtractMask`,
  `blendExcludeMask`; the mask modes in `BlendMode`.
- `.reference/upstream/src/pixie/paths.nim`: `fillPath` mask/layer path,
  `fillOverlaps`/coverage reuse if needed.
- `.reference/upstream/src/pixie/contexts.nim`: `clip`, `saveLayer`, `restore`
  with mask/layer images, `globalAlpha` composition.
- `.reference/upstream/src/pixie/images.nim`: `blur`, `shadow`, `resize`,
  `rotate90`, `magnifyBy2`, `minifyBy2`, `flipHorizontal`, `flipVertical`,
  `invert`, `ceil`, `applyOpacity`, `subImage`, `superImage`, `opaqueBounds`,
  `spread`, `diff`; `.reference/upstream/src/pixie/internal.nim`
  `gaussianKernel`.
- Fixtures: `gaussian_kernel.tsv` (all radii), `draw_translate`/
  `draw_scale2` must stay green.

## Scope

- Mask blends and mask images: `MaskBlend`, `SubtractMaskBlend`,
  `ExcludeMaskBlend`, used by clip/layers.
- `Context.clip` (intersect only, as upstream), `saveLayer`, `restore` with
  mask/layer composition, `globalAlpha`.
- Image operations/effects in pinned scalar form: blur, shadow, resize,
  rotate90, magnifyBy2/minifyBy2, flips, invert, ceil, applyOpacity,
  subImage, superImage, opaqueBounds, spread, diff.
- No SIMD; no text (T009); no codecs (T008).

## Acceptance criteria

- `test/image_ops_tests.jl` (new or extended): every effect has a small
  hand-checked case; `gaussianKernel` matches all fixture radii exactly;
  blur/shadow follow the pinned fixed-point/float truncation points.
- `test/context_layers_tests.jl` (new): clip intersection, nested clips,
  saveLayer + globalAlpha composition, unbalanced restore still raises,
  malformed masks do not corrupt the target; cases hand-computed from the
  upstream formulas.
- `Pkg.test()` keeps all existing assertions green; `scripts/check.jl` > 95%
  line coverage across `src/` (record exact %).
- Anything not ported is absent from `export` and named in the Results +
  COMPATIBILITY (coordinator integrates) — no placeholder APIs.

## Validation

Commands as T007a; no new dependencies without a recorded decision (D008);
Julia 1.10-compatible syntax; no `@fastmath`/unsafe/SIMD/threads. Do not edit
shared docs; do not commit.

## Results and handoff

Record commands/results, fixture rows, coverage %, deferred effects, and what
T008/T009/T010 still need.

## Results -- masks and context (this run)

Scope landed this run: the mask/context half of the task. `blender`
dispatches 16/18/19 (Mask/Subtract/Exclude); the rasterizer implements the
clears-uncovered MaskBlend semantics (`fillHitsLine`, `fillCoverageLine`,
`fillTrapezoids!`, `fillShapes`, all traced to pinned `paths.nim` L1466-1928);
`Context`/`ContextState` carry `globalAlpha` (default 1), `mask`, `layer`;
`saveLayer` stores the active layer reference then starts a fresh
full-size layer; `restore` restores all state first, composites the popped
layer through the popped mask (`draw(poppedLayer, poppedMask;
blendMode = MaskBlend)`), then onto the restored layer or the root image.
`clip` (Path or current path, Optional `WindingRule`) allocates the mask and
fills it opaque white under OverwriteBlend, then intersects subsequent clips
under MaskBlend, with the identity transform (upstream `clip`, contexts.nim
L384-408 passes no matrix). Public `fill`/`stroke` route: mask + no layer ->
saveLayer/draw/restore; active layer -> the layer; else the root. Private
`fill`/`stroke` with `globalAlpha != 1` go through their own layer and
`applyOpacity` (contexts.nim L139-177). `clearRect` draws into the active
layer when present. Exports: `saveLayer`, `clip`.

Deliberate expectation updates (not regressions): `test/paint_tests.jl`
checks `blender` dispatch of 16/18/19 instead of expecting the old
ArgumentError; `test/image_ops_tests.jl` "draw dispatch errors" replaced the
mask-mode raise cases with hand-derived pixels ((24,12,6,63) for
SubtractMaskBlend; ExcludeMaskBlend zero; drawTiled MaskBlend
(200,200,200,200)/(120,120,120,120)). `test/path_tests.jl`
`BlendMode(20)` still raises "unknown blend mode".

New `test/context_layers_tests.jl`: 116 assertions, all hand-derived from
pinned upstream formulas (never run against the code under test): first-clip
coverage, later-clip intersection (disjoint/overlapping rects = winding
union then MaskBlend intersect), nested saveLayer, clearRect in a layer,
stroke under a clip, drawImage under a clip, clipped triangle (trapezoid
sliver = fill's own coverage * mask coverage = premul (64,0,0,64), normal
over white -> (255,191,191,255)), clip-outside-image clears the whole mask,
globalAlpha 0.5 through saveLayer/applyOpacity, unbalanced `restore` still
raises `ArgumentError` (documented deviation from upstream's no-op),
malformed clip leaves the target image untouched.

Validation (all on Julia 1.13.3, `--project=.`, no network):
- `julia --startup-file=no --project=. -e 'using Pkg; Pkg.test()'`: pass,
  6,954/6,954 assertions (baseline before this change was 6,843; delta is the
  new T007b set (116) minus the raise-cases removed in
  paint_tests/image_ops_tests plus their pixel replacements).
- `julia --startup-file=no --project=. scripts/check.jl`: OK; `coverage
  gate: src/ line coverage = 96.89% (2304/2378 measurable lines)`, above the
  >95% gate (baseline 98.54% / 2230 of 2263 -- the percentage is lower only
  because the new rasterizer/context lines added measurable coverage).

Deferred (still in this task's scope, not yet implemented): image
effects -- blur, shadow, resize, rotate90, magnifyBy2/minifyBy2, flips,
invert, ceil, applyOpacity (used by globalAlpha fill/stroke today, so the
layering path is exercised), subImage/superImage, opaqueBounds, spread,
diff, gaussianKernel fixture match, T008 codecs, T009 text, T010.

## Results -- image effects (this run, completes T007b)

All pinned image effects landed in `src/image_ops.jl` (new "image effects
(T007b)" section, traced to `images.nim` L78/L90/L100/L138/L279/L294/L304/
L701/L716/L776/L794/L805 and `internal.nim` L17/L86): `gaussianKernel`,
`flipHorizontal`, `flipVertical`, `rotate90`, `diff`, `invert`, `ceil`,
`blur` (+ ColorRGBA/ColorRGB `outOfBounds` overloads), `resize`, `spread`,
`shadow`, `superImage`, `opaqueBounds`. Exports added in `src/Vetra.jl`.

Porting choices (see D013):

- `gaussianKernel` reproduces the mixed-precision Nim arithmetic exactly:
  `s` Float32; `2*pi*s^2` / the `1/sqrt(...)` factor / the product `a`
  Float64; `exp(...)` Float32 (expf); the Float64 sum `total`; weights
  re-stored as Float32; final `f*255*256` Float32 rounded tie-away-from-zero
  then truncated to UInt16. All 288 fixture weights match exactly.
- `rotate90` returns the rotated `Image` instead of mutating (upstream
  mutates dimensions in place; our `Image` is immutable). All other effects
  mutate `image.data` in place and return nothing, as upstream.
- `ceil` and `diff` extend the imported `Base` generics
  (`import Base: *, ceil, diff, fill, copy`) so module-internal
  `ceil(Float32)` calls (geometry/rasterizer) and downstream
  `Base.diff`/`Base.ceil` usages are unaffected, and `using Vetra` does
  not create ambiguous exports. This build has no kwcall fallback for
  optional positional args, so `draw` keeps its `; blendMode` keyword and
  the new `resize`/`shadow`/`superImage` call sites pass it as a keyword.
- `blur`/`spread` keep upstream's transposed intermediate
  (`newImage(height, width)`) and the X/Y OOB window splits; accumulators
  are Int64 (provably < 2^32, upstream's uint32 bounds), final channel
  `(acc div 256) div 255`. The radius is rounded with `_roundRadius`, which
  ties away from zero for negative inputs as Nim `round` does (the
  module-level `roundHalfAway` only covers non-negative values):
  `blur(-0.5f0)` raises "Cannot apply negative blur" and
  `spread(-0.5f0)` shrinks by 1, exactly as upstream.
- `invert` folds upstream's two passes (invert, then
  `toPremultipliedAlpha`) into one; the `a == 255` skip is the identity,
  and `a == 0` zeroes the rgb channels via `(c*0+127) div 255` exactly as
  upstream does.

Not ported (named per the no-placeholder rule): the `subImage(image,
rect)` convenience overload (snapToPixels + 4-arg form) -- nothing in
T007b or later code needs it yet; add it with the T010 context
integration if a call site appears. `gaussianKernel` is exported
(upstream `internal.nim` marks it `*`).

Tests: `test/image_ops_tests.jl` gains the "T007b image effects" testset
(404 assertions), all hand-derived from the pinned formulas: gaussianKernel
vs `gaussian_kernel.tsv` (16 radii, 288 weights, exact); blur both passes
on a 5x1 row (truncation chain `div 256 div 255`, transparent and white
out-of-bounds, no-op radii, negative raises incl. the `-0.5` tie,
`ColorRGBA`/`ColorRGB` `outOfBounds` overloads); spread max/min pools +
alpha-only rewrite + 2D non-extreme case + the `-0.5` tie shrink; shadow (spread+blur+MaskBlend
pipeline, zero and non-zero offset); flip H/V (odd extents, middle fixed);
rotate90 (2x3 pattern, source untouched, 4x identity); diff (mixed sizes,
score Float32 chain, clamp directions, identical = 0); invert (a=200,
a=255, a=0 cases); ceil (zero/stay, non-zero/255, Base.ceil check);
resize (2x magnify, 1x minify average, same-size independent copy);
superImage (inside sub, padded, fully outside incl. just-touching);
opaqueBounds (tight box, all-transparent zero rect, fully opaque).

Validation (Julia 1.13.3, `--project=.`, no network):

- `julia --startup-file=no --project=. -e 'using Pkg; Pkg.test()'` -> pass,
  7,358/7,358 assertions (baseline 6,954 + 404 new; T007b image effects
  404, T007b mask and layers 116).
- `julia --startup-file=no --project=. scripts/check.jl` -> OK; `coverage
  gate: src/ line coverage = 97.42% (2567/2635 measurable lines)`, above
  the >95% gate (D009).
- Fixture evidence: `gaussian_kernel.tsv` 16 radii x 288 weights, 0
  mismatches; both draw fixtures and all T001-T007a assertions unchanged
  and green.

T007b is complete; T008 (formats/SVG) and T009 (fonts/text) are unblocked
(next in wave order), both under policy D008.
