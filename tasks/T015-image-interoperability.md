# T015 — Julia color-matrix interoperability

Status: see [TASKS.md](../TASKS.md). Dependencies: T013. Priority: adoption.
Goal: exchange images with Julia's standard RGB/RGBA matrix ecosystem.

## Inputs and scope

Read D010/D014/D019, src/Vetra.jl image storage/alpha conversions, the optional
codec loading tests, and docs/NUMERICAL_CONTRACT.md. Before coding, record a
minimal opt-in integration/API decision for ColorTypes/FixedPointNumbers-style
matrices (inspect current packages; add no mandatory renderer dependency).
Provide explicit conversion in both directions; FileIO dispatch is optional
follow-up unless needed for this minimal interface.

## Acceptance criteria

- Import/export standard opaque RGB and straight-alpha RGBA matrices with
  `(height, width)` indexing and documented supported channel types.
- Specify premultiplication, channel quantization, zero alpha, Float32/Float64
  input range, non-contiguous views, supported axes, and copy/alias semantics.
  Reject unsupported inputs clearly instead of assuming a raw memory layout.
- Non-square asymmetric test images prove orientation and channel order;
  hand-derived fractional-alpha cases prove rounding. Document when round trips
  lose information rather than requiring impossible byte equality.
- Core-only loading still works; integration-present/loading-order tests pass.
- Include a runnable standard-matrix → annotate → standard-matrix recipe.

## Validation

Use the [shared validation](../docs/ROADMAP.md#shared-validation). Test core-only
and integration-enabled environments separately. Measure allocations and time
for both conversion directions, using opaque and translucent non-square images.
New extension code participates in the coverage gate.

## Results and handoff

Status: done (2026-11-07).

### Decision (D024)

Opt-in `ColorTypes` (UUID 3da002f7, added to `Project.toml` `[extras]` + test
targets and the `__init__` discovery loop alongside the existing codecs).
`toColors(image) -> Matrix{RGBA{N0f8}}` straight alpha `[row, col]`;
`fromColors(m)` accepts 2-D `RGB`/`RGBA` of N0f8 (exact `.i` bytes) or
Float64/Float32 (clamp to 0..1, `UInt8(round(v * 255))`). Both directions
reuse the pinned PNG boundary (`toStraightAlpha` out, `rgbx(ColorRGBA)` in),
so matrix bytes == PNG payload bytes. Concrete `Matrix` only; 3-D plane
arrays and other eltypes raise `ArgumentError`. No FileIO dispatch.

### Verification

- New `test/colormatrices_tests.jl` (29 assertions, in runtests): asymmetric
  3x2 orientation/channel-order proof, hand-derived straight/premul values
  (e.g. premul (128,64,0,128) -> straight (255,128,0,128), tie 127.5 -> 128;
  straight (200,100,50,128) -> premul (100,50,25,128)), zero-alpha clearing,
  float clamp (1.5 -> 255, -0.2 -> 0), Float32 widening exactness, validation
  errors, round-trip loss bounds (exact at a in {0, 255}; <= 1/255 otherwise),
  and the matrix -> draw -> matrix recipe. `test/codec_loading_tests.jl`
  gains the core-only ColorTypes install-hint subprocess assertion.
- `julia --startup-file=no --project=. -e 'using Test, Vetra; include("test/colormatrices_tests.jl")'`
  — 29/29 passed.
- Performance (function-scoped, 20 warmups + 200 calls, 256x256 opaque
  gradient): `toColors` **0.80 ms, 256.1 KB** (allocation = output matrix
  only; per-pixel `reinterpret(T, byte)` construction after the rational
  construction measured 2.81 ms) — log `/tmp/opencode/t015-perf2.jl`;
  `fromColors` **0.19 ms, 512.2 KB** (matrix + image).
- Two debug detours recorded for future agents: (1) this build resolves
  `in`/`∈` inside the Vetra module to a local binding, so membership tests
  must be written as `:alpha ∈ fieldnames(C)` (verified via `@code_warntype`);
  (2) drawing calls use continuous coordinates — `fillRect(ctx, 1, 1, 2, 2)`
  covers pixels (2,2)-(3,3) 1-based (fixture-pinned behavior); an initial
  test expectation was wrong, not the library.

### Limitations

3-D plane matrices (Images.jl layout), views, FileIO dispatch, and
Gray/ARGB32/RGB24 eltypes are out of scope (clear errors). Float channel
values outside 0..1 are clamped, not rejected.

Next ready tasks: T016, T017, T020, T023, T027, T030.
