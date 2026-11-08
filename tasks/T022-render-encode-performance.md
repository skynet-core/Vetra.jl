# T022 — Repeated-render allocations and PNG throughput

Status: see [TASKS.md](../TASKS.md). Dependencies: T020.
Goal: reduce measured allocation hotspots and improve PNG-heavy application work.

## Inputs and scope

Use T020 targets and the existing scalar contract, D014, T012/T013, image_ops,
rasterizer, paints, and PNG boundary code. Work on measured bottlenecks only:
function barriers, unnecessary temporaries/copies, reusable caller-owned geometry,
and codec-boundary conversions. Investigate encoding settings with both time and
file size, across representative images. No global mutable scratch buffers or
mandatory replacement renderer/codec. Split into focused follow-up tasks if
the baseline identifies unrelated changes too large for one pass.

## Acceptance criteria

- Report allocation bytes per image and repeated-render throughput against T020;
  independently evaluate PNG throughput and encoded sizes for its image corpus.
- Meet the recorded targets or explicitly leave unmet items blocked/deferred;
  one faster gradient does not establish an improved general encoder.
- Keep premultiplied/straight boundaries, rounding, layout, mutation behavior,
  existing output contracts, errors, and fixture tolerances intact.
- Preserve the core-only codec behavior and no unwanted input/output aliasing.
  Buffer reuse must have defined ownership and independent-call behavior.
- Before/after benchmarks show supported gains and any regressions; rejected
  experiments are removed rather than retained as unused options.

## Validation

Run [shared validation](../docs/ROADMAP.md#shared-validation) and T020 workloads
sequentially before/after. Add focused regression tests for changed behavior
boundaries using independent expectations, not implementation snapshots.

## Results and handoff

Status: done (2026-11-07). Draw-allocation targets met (one full-canvas
buffer removed per non-solid gradient fill); PNG encode allocation
explicitly deferred as codec-bound (isolation below).

### Diagnosis (T020 targets)

- Per-image draw allocation: 26.5 MB @1080p, 101 MB @4K, 182 MB
  @clip_layers-12. The repeatable gradient-fill pipeline allocated two
  full-canvas buffers per non-solid fill: the coverage `mask` plus a
  `fillImg` canvas the gradient was drawn into before
  `applyOpacity` + MaskBlend cut-out + Normal composite.
- PNG encode allocation: 24.9–38.8 MB @1080p, 124 MB @4K. Measured
  decomposition (1080p flat opaque): 23.8 MB total = 7.9 MB straight-alpha
  staging buffer + ~15.8 MB PNGFiles/libpng-internal (row buffer, filter
  scratch, zlib state) + 10 KB payload.
- Boundary pass for translucent images (`toStraightAlpha`): one 7.9 MB
  output buffer per conversion — the allocation minimum, since the
  output contract forbids input/output aliasing and the conversion is
  per-pixel (premul -> straight needs a fresh write).

### Changes (src/paints.jl)

Non-solid gradient paints (`LinearGradientPaint`, `RadialGradientPaint`,
`AngularGradientPaint`) now take a fused single-buffer path in
`fillPath`: `_fillGradientMasked` samples the gradient and performs the
exact former arithmetic (applyOpacity's `o = roundHalfAway(255 *
opacity)` scaling, blendMask's `UInt8(ch * k / 255)` cut-out, the paint's
blend) over one reused row scratch (4*width bytes, owned by the call —
no global buffers), so only the coverage mask is allocated:

0. stop positions are validated finite before any destination write —
   non-finite positions made `gradientColor` throw (an accidental
   `InexactError`) mid-canvas, which in the fused path would leave
   `image` partially mutated; the old 2-buffer pipeline always left the
   destination untouched on error, so the fused path now throws a
   deliberate `ArgumentError` up front instead (same observable
   all-or-nothing contract);
1. geometry loop samples the gradient into the row (horizontal hoists
   one sample per column into a second raw row; vertical/general sample
   per row; radial/angular per pixel with the upstream matrix/angle
   formulas, `t` inlined to the same Float32 op order);
2. `_cutRowOut!` applies the mask cut-out in place (the horizontal
   branch cuts non-destructively from the raw row — re-sampling the
   gradient per row would be wasteful, reusing the mutated row would
   compound the cut-out);
3. `_blendRowInto!` composites the row with blendRect's exact per-pixel
   branches (NormalBlend opaque-copy fast path, OverwriteBlend straight
   copy, generic `blender(mode)` call), mode branch hoisted out of the
   pixel loop.

A single merged sample+cut+blend loop was measured ~5 ms slower at 1080p
than the separate passes; the 3-pass shape is ~4 ms over the original
2-buffer pipeline in the 1080p microbench but removes the second
full-canvas buffer. ImagePaint/TiledImagePaint keep the original
2-buffer pipeline unchanged. Design recorded as D029.

### Correctness

- A/B byte-exact corpus: 4204 scenes (3 gradient kinds x linear
  horizontal/vertical/diagonal x 4 paths (rect/circle/even-odd/transformed
  bezier) x 17 blend modes x 4 opacities x 3 backgrounds, plus
  ImagePaint/TiledImagePaint controls and globalAlpha layer scenes),
  dumped as raw bytes with the original 2-buffer pipeline vs the fused
  path: **4204/4204 byte-identical** (`/tmp/opencode/t022-ab-{old,new}`,
  script `/tmp/opencode/t022-ab.jl`). The corpus caught two real
  regressions during development: an alpha channel left uncut in the
  first fused version (2284/4204 scenes differ) and a horizontal
  double cut-out after the 3-pass restructure (compounded per row).
- Full oracle gate `scripts/check.jl`: green, 811k+ assertions, coverage
  98.01% (5662/5777 measurable lines).
- Focused regression testset (test/paint_tests.jl, "T022 fused non-solid
  gradient fill", 42 assertions): hand-derived expectations from the
  documented arithmetic — Float32 `t`, stop interpolation,
  roundHalfAway opacity edges and tie neighbors (1, 0.5, 0.499, 0.501,
  0.002, 0.9991, 0.001), Normal/Overwrite/Multiply/MaskBlend branches
  (incl. MaskBlend over a translucent backdrop and the rounded-zero
  opacity clear), partial coverage × opacity (white-box), multi-row
  horizontal at opacity 0.5 (pins the double-cut regression), coverage
  boundary, all validation errors incl. non-finite stops (ArgumentError
  + destination untouched).
- Independent review (openai/gpt-6-astra subagent, 2026-11-08): no
  must-fix pixel-arithmetic findings (confirmed the two integer
  divisions of applyOpacity→blendMask are preserved, all blend-mode
  branches, horizontal raw-row handling, scratch ownership, and the
  canvas_4k regression as an accepted tradeoff). Its three should-fix
  items were implemented: stop-position validation (error-path
  all-or-nothing contract), tests pinning the horizontal double-cut
  regression and the mask-family/translucent/tie gaps, and stale
  comment fixes (the "one pass" / "~10 ms" claims were reworded to the
  measured 3-pass / ~5 ms facts).

### Before/after (T020 protocol; r1–r5 original vs r12–r14 fused, medians)

| workload/stage | before | after | gain |
| --- | --- | --- | --- |
| canvas_1080p/draw | 62.2 ms / 25 MB | 59.1 ms / 17 MB | -3.1 ms, -8 MB |
| canvas_4k/draw | 238.3 ms / 96 MB | 251.8 ms / 64 MB | +13.6 ms, -32 MB |
| clip_layers/draw | 353.1 ms / 173 MB | 335.0 ms / 131 MB | -18.1 ms, -42 MB |
| repeat_1080p/draw | 53.2 ms / 25 MB | 55.6 ms / 17 MB | +2.4 ms, -8 MB |
| repeat_1080p/draw_plus_encode | 94.5 ms / 49 MB | 102.1 ms / 41 MB | +7.7 ms, -8 MB |
| png_*/draw_fill, encode, boundary | unchanged (7/23–37 MB) | same | n/a |

Draw-allocation targets (26.5/101/182 MB): met at 17/64/131 MB (-36%/
-36%/-28%). Wall time is roughly neutral: canvas_4k/draw is the one
consistent regression (+12–15 ms across all 3 final runs vs the 232–245
ms spread of all 5 baseline runs — non-overlapping, not noise); 1080p,
clip_layers, and the repeat workloads are within baseline spread.
Rejected intermediate shapes (merged single-pass; 2-pass with cut-out in
the composite pass) were measured out and removed — no unused options
retained in src.

### PNG side (codec-bound isolation)

PNG encode allocation is not reducible within the task constraints:
the ~15.8 MB of the 23.8 MB encode total is inside PNGFiles/libpng
(codec-owned row/filter/zlib temporaries). Reducing it would require
either a global mutable scratch buffer (forbidden by the task) or
replacing/wrapping the codec (forbidden: "no mandatory replacement
renderer/codec"). The addressable remainder — the toStraightAlpha
boundary pass — is already at one output buffer per conversion (the
no-aliasing contract minimum); its 16–20 ms wall time is scalar
per-pixel conversion cost. Opaque encode wall time (36 ms flat @1080p)
matches the T020 codec floor; no encode-setting change affects
time-vs-size across the flat/gradient/noise corpus (payload sizes
dominated by content entropy, not settings). This sub-target is
deferred with that isolation rather than blocked (the check ran and
explained the ceiling).

### Verification commands

- `julia --startup-file=no --project=. scripts/check.jl` — green, 98.01%
  (log `/tmp/opencode/t022-gate4.log`).
- A/B corpus: `julia --project=docs /tmp/opencode/t022-ab.jl <dir>` with
  the original dispatch vs the fused dispatch; `diff -rq` — 4204/4204
  identical.
- App suite: `julia --project=docs benchmark/app_benchmarks.jl 12..14`
  (baseline r1–r5 preserved in `benchmark/results/`).
- Encode decomposition: `@allocated encodePNG` on a 1080p flat canvas —
  23.8 MB; boundary loop — one 7.9 MB buffer.

### Limitations and next

- canvas_4k wall-time regression (+5%) recorded as the cost of the
  allocation win; further per-pass tuning (SIMD, wider scratch) is
  backlog per the scalar-first rule, not pursued here.
- PNG encode/boundary sub-targets deferred (codec-bound; isolation
  above). Boundary-pass SIMD could be a standalone micro-task if the
  16–20 ms translucent stage becomes important.
- Single machine (local), per T020 protocol. Next ready: T023 (recording
  design) or T027 (text design) or T030 (codec design).
