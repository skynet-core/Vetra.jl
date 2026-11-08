# T014 — Friendly numeric drawing arguments

Status: see [TASKS.md](../TASKS.md). Dependencies: T013. Priority: adoption.
Goal: let beginners draw with ordinary Julia integers and floating-point values.

## Inputs and scope

Read docs/API.md, docs/NUMERICAL_CONTRACT.md, D010/D011, src/context.jl,
src/paths.jl, src/geometry.jl, and their callers/tests. Inventory the public
coordinate, transform, stroke-width, and text-size boundaries used by examples.
Add thin `Real` entry points that convert once to the existing Float32 kernels;
do not replace specialized arithmetic or change integer image dimensions/pixel
indices. Avoid broad untyped methods, method piracy, and ambiguous overloads.

## Acceptance criteria

- `fillRect(ctx, 10, 20, 100, 50)` and mixed numeric coordinates work;
  equivalent inputs match the existing Float32 calls exactly after conversion.
- Record finite/range/conversion rules, including Float32 overflow and NaN/Inf;
  preserve existing specialized semantics rather than quietly redefining them.
- Cover representative path, transform, image-drawing, and text calls; test
  overload ambiguity, invalid input, and dispatch back into concrete kernels.
- Update API and beginner examples to teach ordinary numbers while explaining
  internal Float32 precision. Existing callers/exports remain compatible.
- No per-pixel dynamic dispatch or material allocation/performance regression.

## Validation

Use the [shared validation](../docs/ROADMAP.md#shared-validation), plus focused
context/path/geometry tests with hand-derived coordinates and overload checks.
Run the tutorial blocks and existing benchmark harness before/after.

## Results and handoff

Status: done (2026-11-07).

### Changed entry points

One-line `Real` boundary wrappers (convert once with `Float32(x)`, delegate to
the specialized `Float32` kernel; each tagged `# T014`):

- `src/geometry.jl`: `Vec2(x, y)`, `rect(x, y, w, h)`, `circle(pos, radius)`,
  `rotate(angle)` (Mat3).
- `src/paths.jl`: `moveTo`, `lineTo`, `bezierCurveTo`, `quadraticCurveTo`,
  `ellipticalArcTo`, `arc`, `arcTo`, `rect`, `roundedRect`, `ellipse`,
  `circle`, `polygon` — the coordinate-form builders.
- `src/context.jl`: `isPointInPath` (2 coordinate overloads), `translate`,
  `scale`, `rotate`, `moveTo`, `lineTo`, `bezierCurveTo`, `quadraticCurveTo`,
  `arc`, `arcTo`, `rect`, `ellipse`, `roundedRect`, `circle`, `polygon`,
  `clearRect`, `fillRect`, `strokeRect`, `strokeSegment`, `drawImage` (2/4/9-
  arg forms), `fillText`, `strokeText`.
- `src/image_ops.jl`: `blur`, `spread`, `applyOpacity`, `shadow`.

Dispatch keeps `Float32` calls on the existing specialized methods (the `Real`
method is a supertype fallback), so hot paths lose nothing. Field
assignments (`ctx.lineWidth = 4`) already worked via struct-field conversion
and are unchanged. Keyword arguments (`strokeWidth = …`, gradient handles,
…) remain `Float32`-typed: Julia does not implicitly convert keyword values,
and changing them would mean duplicating each keyword method — recorded as a
documented limit in the test suite and API.md.

### Conversion rules (documented in tests)

- Ordinary numbers: `Int`, `Float64`, `Rational` convert via `Float32(x)`.
- Float64 overflow saturates to `Inf`; the rasterizer then raises
  `InexactError` exactly as with a directly-passed `Inf`. `NaN` draws nothing,
  as with direct `NaN`. No new validation — the wrapper is a pure conversion
  (verified behavior-preserving, not redefined).
- Non-numeric arguments raise `MethodError`, as before.

### Verification

- New `test/numeric_api_tests.jl` (23 assertions, included in runtests):
  byte-for-byte scene parity between plain-`Int` and `Float32`-literal runs of
  a scene exercising every new wrapper (rects, segments, transforms, all path
  builders incl. `ellipticalArcTo` and `EvenOdd` fill, hit testing, text,
  2/4/9-arg `drawImage`, blur/spread/applyOpacity/shadow); geometry
  constructor equality incl. `Rational`; allocation equality; dispatch
  candidate existence; conversion semantics; keyword limit.
- Full gate: `julia --startup-file=no --project=. scripts/check.jl` —
  **811,432 assertions passed** (T013 baseline 811,409 + 23), coverage
  **97.98% (5331→5383/5494)**; log `/tmp/opencode/t014-check.log`.
- Performance (function-scoped, per the profiling guidance): 200,000
  `fillRect` calls — Float32 0.9 µs, Int 0.81 µs, Float64 0.82 µs per call
  (within noise; no regression). Function-scoped allocation: `moveTo`+
  `lineTo` 47.2 B per two calls for both Int and Float32 arguments (identical);
  `Vec2` 0 B. Early top-level-scope probe differences were untyped-global
  measurement artifacts and were re-measured inside functions.
- Existing harness (docs env, same workloads): allocation totals unchanged
  (35,765,352 / 93,255,288 / 2,758,560 / 6,891,192 / 6,884,304 / 195,806,856 /
  50,812,272 / 42,571,536); medians within run-to-run noise of T013's run
  (fill 0.881 vs 0.860; stroke 26.00 vs 26.28; png_encode 24.10 vs 23.91;
  log `/tmp/opencode/t014-bench.log`).
- Docs updated to teach plain numbers: README quick start (executed
  run-clean in the docs env, `/tmp/opencode/vetra-quickstart.jl`),
  docs/API.md conventions, docs/GETTING_STARTED.md §2 note (all 13 tutorial
  blocks re-executed), COMPATIBILITY row. `docs/make_tutorial.jl` rebuilt
  both outputs.
- Public export set unchanged (276 names); no fixtures touched; no
  dependencies added.

### Limitations

Keyword arguments and `strokePath`/`fillPath` style options still require
`Float32` literals. No performance gain was claimed or measured for the
wrappers (they are neutral by design; the gain is ergonomic).

Next ready tasks: T015 (image interop), T016 (notebook display), T017
(docs/gallery), T020 (application benchmarks), T023 (recording design),
T027 (text design), T030 (codec design).
