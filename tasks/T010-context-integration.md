# T010 — Full drawing context integration

Status: done (2026-11-06). Dependencies: T008, T009.
Goal: complete `Context` state/stack behavior and cross-feature integration so
all implemented features compose correctly (transforms, clips, layers,
opacity, dashes, text, images).

## Inputs and upstream references

- `.reference/upstream/src/pixie/contexts.nim` remainder: `saveLayer`,
  `restore`/state stack, `mask`/`layer` composition, `globalAlpha`,
  `isPointInPath`, `getLineDash`/`setLineDash`, `getTransform`/`setTransform`/
  `resetTransform`, `drawImage` overloads, text methods, `ContextState` fields.
- `.reference/upstream/src/pixie/images.nim`: `draw` blend/mask paths used by
  `saveLayer`.
- docs/API.md "Context / drawing"; D011 (stateful context, save/restore,
  unbalanced restore → `ArgumentError`).

## Scope

- Full state stack: every field listed in `ContextState` is saved/restored;
  nested `save`/`restore`, `saveLayer`, and clip-mask accumulation
  (intersection) match upstream.
- `globalAlpha` composition; dash patterns (`setLineDash`) in strokes;
  `isPointInPath`; `getTransform`/`setTransform`/`resetTransform`.
- `drawImage` convenience overloads and text integration from T009.
- Cross-feature tests: clip + transform + gradient paint; saveLayer + opacity;
  text inside a clip; dash + caps/joins; nested save/restore ordering.

## Acceptance criteria

- `test/context_integration_tests.jl` (new): state-stack matrix of
  save/restore/transform/clip cases with hand-computed expectations; nested
  saveLayer; globalAlpha; unbalanced restore raises; isPointInPath on
  inside/outside/edge points; dash phase cases; text + clip.
- `Pkg.test()` green; `scripts/check.jl` > 95% (record exact %).
- COMPATIBILITY rows for context state are accurate (coordinator integrates).
- No feature claims without a linked test.

## Validation

Commands as T004; no new dependencies unless already approved by D008 tasks.
Do not edit shared docs; do not commit.

## Results and handoff

Completed 2026-11-06.

- **Source changes** (the Context surface from T005/T007b/T009 already
  existed; T010 closed two gaps):
  - `isPointInPath` (4 overloads, upstream contexts.nim L613-635): new
    `overlaps` scanline point test in `src/rasterizer.jl` (upstream
    paths.nim L2232-2257) — horizontal scanline from (0, y) to (1000, y)
    over `shapesToSegments(shapes, true)` of `commandsToShapes(path, true,
    pixelScale(CTM))` transformed by the CTM; hits are 1/256 fixed-point
    x's with segment windings, sorted, walked with `shouldFill`; a point
    past the last hit falls through to `false` (upstream). `_ctxPathShapes`
    + overloads in `src/context.jl`; exported in `src/Vetra.jl`.
  - `ctx.lineDash` wiring in context `stroke(ctx, image, path)` — upstream
    (contexts.nim L157-177) passes `ctx.lineDash` to `strokePath`; the
    port previously omitted it (strokes ignored dashes). `strokeText`
    already passed it (T009).
- **Unported, by scope**: `isPointInStroke` (upstream contexts.nim L637)
  is not in docs/API.md, so it stays out (recorded in COMPATIBILITY.md).
- **Commands and results**:
  - `julia --startup-file=no --project=. scripts/check.jl` → **OK**:
    `Testing Vetra tests passed` — full suite green incl. new
    `T010 context integration` 4963/4963 assertions — and
    `coverage gate: src/ line coverage = 98.0% (5230/5337 measurable
    lines)` (> 95% per D009). Total suite: 811 405 assertions
    (806 442 at T009 + 4 963).
- **test/context_integration_tests.jl** (new; every expectation
  hand-derived from the pinned upstream formulas — overlaps scanline
  rules, clip identity-space quirk, blends, stroke dash phase):
  - isPointInPath matrix: inside/outside/both-edge cases with the
    upstream asymmetries (left edge inclusive via the hit walk; right
    edge exclusive as "past the last hit"; top edge included — hits at
    segment starts are kept — bottom edge excluded — hits landing
    exactly on `segment.to` are discarded by upstream's
    `if segment.to != at`); fractional fixed32 truncation pinned
    ((9.999,5) inside, (10.001,5) outside the x=10 edge); donut
    (counter-rotated hole: NonZero and
    EvenOdd both false inside the hole, true in the ring);
    same-orientation overlap (NonZero true / EvenOdd false); all four
    overloads (explicit path / current `ctx.path`, Vec2 / x,y floats);
    CTM applied to the path, not the point (translate and scale cases).
  - dash phase: `[5,15]` on a 0..75 line at width 10 ButtCap → ink
    columns 1-5/21-25/41-45/61-65 exactly, gaps white; odd-length
    `[5,15,10]` self-duplicates (draws [0,5),[20,30),[35,50),[60,65));
    dashes compose with `globalAlpha` 0.5 (halfOverWhite);
    `[0,5]` raises `ArgumentError("Invalid line dash value")`;
    lineDash round-trips through save/restore; dash + caps
    (RoundCap circles / SquareCap extension at the path ends,
    not the dash ends; ButtCap control) and dash + miter join
    (join ink at a vertex that sits in a dash gap).
  - clip identity space (upstream quirk, both orders): clip-then-translate
    and translate-then-clip of a full-canvas fill under a left-half clip
    both clip away entirely (mask built without the CTM), while
    clip without translate keeps the left half.
  - gradient paint under clip + transform: clipped/translated renders
    equal the unclipped render on covered pixels, untouched elsewhere
    (paints sample in destination space).
  - text + clip: `fillText` and `strokeText` of "Word" (Roboto @24,
    upstream-pinned layoutBounds (56,28)) under an x<30 clip — inside
    the clip the pixels equal the unclipped render, outside stay white;
    ink asserted on both sides of the clip boundary.
  - composite state stack: save → clip + translate + globalAlpha 0.5 +
    lineDash + fillRect → restore; half-red band at exactly
    [0,20)×[10,30) (halfOverWhite), all state fields back to defaults,
    and a post-restore fill proves the clip is gone; the `font` path
    round-trips through save/restore (ContextState field).
  - nested saveLayer under a clip with globalAlpha: top-half
    (128,0,0,128) premul over transparent, bottom half untouched,
    mask/layer cleared, and the upstream quirk that the inner
    fill's save/restore snapshots the 0.5 (restored, not reset to 1).
  - Unbalanced-restore and single-field state-stack coverage remains in
    test/context_tests.jl and test/context_layers_tests.jl (T005/T007b).
- **Deviations**: none new (the unbalanced-restore `ArgumentError`
  deviation is the T005 one, unchanged).
- **For T011**: benchmark `isPointInPath` (scanline over complex paths)
  and dashed context strokes if optimization is pursued; the renderer
  core remains scalar per the policy (no SIMD until correctness +
  benchmark justify it).
