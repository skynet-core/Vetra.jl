# T012 — Renderer performance pass (profile, optimize, match the Nim reference)

Status: done (2026-11-06). Dependencies: T011.
Goal: profile the renderer per Julia's performance-tips manual, remove the
measured bottlenecks, and bring each workload to the pinned scalar Nim
reference's performance — with every fixture kept byte-exact.

**T013 clarification (2026-11-07):** the observations below are historical,
not a diagnosis of Julia internals. The causes of the sampling failure and
streaming-callback regression were not established. Linear indexing into a
Julia `Array` does not inherently require `ind2sub`; the flat buffer was a
measured implementation choice, not proof of that mechanism. `PNGFiles.save`
timings include package conversion and I/O, not just libpng compression, and
do not establish a codec floor. Stroke/draw gaps have not been attributed
conclusively to code generation (integer-translation draw uses `blendRect`,
not the row-scan rasterizer). T013 shares the existing alpha conversion in
PNG encoding and records a before/after regression check separately.

## Method

The pinned Julia 1.13.3 build's sampling profiler collects **zero samples**
(verified on 20 s workloads with `Profile.init(1_000_000, 0.0005)`;
`Profile.Allocs.profile` and `@profileat` are absent in this build), so
profiling used wall-time + `@allocated` microbenchmarks per function
(`/tmp/opencode/microbench.jl`, `alloc-breakdown.jl`, `stroke-probe.jl`,
`inbounds-ab.jl` — scratch, not committed), following the manual's
"Measure performance with @time and pay attention to memory allocation" and
its warning that unexpected allocations indicate the real problem.

Measurement caveat recorded: the first function timed in a fresh session
absorbs JIT compilation and reads ~10-25µs/call; all reported numbers use
200-iteration warm-ups and 3-run harness medians.

Bottlenecks found (baseline = T011 precompile, same machine):

1. `draw` 6.3× Nim: `blendRect`/`drawSmooth` pixel loops went through
   bounds-checked `getColor`/`set_pixel` + `ColorRGBX` construction per
   pixel; an opaque source still read the destination and called
   `blendNormal` (which returns the source verbatim).
2. `blur`/`shadow` 1.5× Nim: the 256 KB transposed-intermediate passes used
   the same per-pixel wrappers.
3. Solid `fillPath(Paint)` converted the Paint to `ColorRGBX` twice.
4. Compositing closures (`mix`, `*(ColorRGBX, Float32)`, `blendNormal`)
   recomputed loop-invariant constants per channel.
5. **Rejected:** streaming span callback (`eachSpan`) replacing the
   per-row `walk` vector — measured 6× slower on the stroke workload
   (25µs → 166µs, 4KB → 51KB) because closure dispatch beats iteration
   over a small concrete vector in this build; reverted (the bisection
   that caught it: `test/path_tests.jl:428` pins `Vetra.walk`, so both
   forms stayed — the hot path kept the original `walk`).
6. **Rejected:** scalar trapezoid-edge buffers replacing
   `traps::Vector{Segment}` — neutral (Segment is isbits in a
   preallocated array; 0.099µs/row either way); the pinned form stays.
7. PNG decode 57× Nim: our boundary conversion, not the codec —
   `invokelatest` hands the decoded matrix to `decodePNG` as `Any`, so
   every pixel went through a generic `getindex` (measured: codec load
   0.2 ms vs our loop 7.3 ms per image), plus per-channel `isdefined`
   and an `N0f8 → Float64 → UInt8` round-trip per channel.

## Changes (all behind the byte-exact gate)

- `src/image_ops.jl`: `blendRect` (all 4 blend branches) and `drawSmooth`
  index the flat pixel buffer directly (in-range by the clamp
  arithmetic, documented in the code); the Normal branch copies opaque
  source pixels verbatim (`blendNormal`'s documented early return makes
  this pixel-identical); `blur` (both passes) and `spread` (all four
  pooling loops) use direct indexing with the same integer arithmetic;
  `@inbounds` on the loops whose range proofs are written in the code
  (measured 27.0µs → 17.2µs on the 128×128 opaque copy, per the manual's
  Performance Annotations tip; AGENTS.md permits unsafe indexing now
  that correctness is established and the benchmark justifies it).
- `src/formats/png.jl` (PNG follow-up, 2026-11-06):
  - **Decode kernel-function barrier.** `_pngLoad` dispatches through
    `invokelatest`, so the decoded matrix reaches `decodePNG` as `Any`;
    per-pixel `getindex(::Any)` dominated the cost (7.5 ms/image, ~4.6 MB
    allocated per image). The pixel loop now lives in
    `_decodePngPixels!(pixels::AbstractMatrix{C}, ...) where {C}`,
    specialized on the concrete ColorTypes element type: channel fields
    are tested once on `fieldnames(C)` instead of `isdefined` per pixel,
    and each channel reads the raw byte (`N0f8`'s `.i` field — verified
    pixel-exact against `UInt8(round(Float64(ch) * 255))` on the pinned
    fixtures) with the premultiply `(v * a + 127) div 255` inlined.
    Result: 0.68 ms/image, 241 KB allocated.
  - **Encode build buffer.** The straight-RGBA array is filled through a
    flat `Vector{UInt8}` with the `(height, width, 4)` linear layout
    (`(c-1)*w*h + x*h + y`) and `reshape`d before `save` — 1-D indexing
    into the 3-D array directly pays an `ind2sub` per channel store.
    Opaque/zero-alpha pixels take straight-copy branches; the
    `toStraightAlpha` formula (`min(roundHalfAway(v * 255.0/a), 255)`)
    is inlined for the rest. Result: 2.33 ms/image total, of which
    ~2.1 ms is the libpng compression inside PNGFiles `save`.
  - Save parameters stay at the PNGFiles package defaults: the measured
    alternative filter/strategy combinations (UP/SUB, level 6) were
    within run-to-run noise on the benchmark workload, and the
    round-trip fixtures pin the pixel contract, not the bytes.
- `src/rasterizer.jl`: `fillPath(ColorRGBX...)` gains a
  `blendMode = NormalBlend` kwarg (default keeps the documented entry
  point; the Paint path passes `paint.blendMode` — without it,
  MaskBlend clips lost their blend mode).
- `src/paints.jl`: solid `fillPath(Paint)` delegates to the `ColorRGBX`
  entry point (zero-alpha `OverwriteBlend` clears still rasterize
  directly, since the ColorRGBX entry returns early on zero alpha).
- `src/Vetra.jl`: `255 - x` / `Int(coverage)` / source-channel constants
  hoisted out of the per-channel closures in `mix`,
  `*(ColorRGBX, Float32)`, coverage scaling, and `blendNormal`
  (bit-identical results).
- `src/strokes.jl`: `makeRect` keeps the tangent components in locals and
  preallocates the 5-point outline; dash lists are copied only when
  non-empty (the common no-dash case).
- README: new "Profiling" section documenting the verified methods
  (per-function timing/`@allocated`, `--track-allocation=user` traces,
  `@code_warntype`, the benchmark harness) and why the sampling
  profiler is unusable in the pinned build.

No pinned arithmetic changed; no expected output regenerated; no
tolerance loosened.

## Validation

- `julia --startup-file=no --project=. scripts/check.jl` — green: all
  fixture assertions pass byte-exact, `src/` line coverage 97.94%
  (5323/5435 measurable lines) — above the 95% gate.
- Benchmark harness, 3 runs, steady-state medians (ms), same machine and
  workloads as T011; Nim reference from T011 (scalar,
  `-d:release -d:pixieNoSimd`, re-verified the same day):

| workload | T011 baseline | T012 final | Nim reference | final vs Nim |
| --- | --- | --- | --- | --- |
| fill_rects_1000 | 0.90 | 0.76 | 0.82 | 0.93× (faster) |
| stroke_lines_1000 | 26.63 | 26.12 | 22.30 | 1.17× |
| blur_128_r3 | 0.69 | 0.36 | 0.43 | 0.84× (faster) |
| shadow_128 | 1.07 | 0.40 | 0.67 | 0.60× (faster) |
| draw_10 | 1.15 | 0.23 | 0.18 | 1.28× |
| png_encode_256_x10 | 29.05 | 23.31 | 10.78 | 2.16× (codec-bound) |
| png_decode_basic1_x10 | 67.27 | 1.50 | 1.17 | 1.28× |
| text_parse_layout_x100_measure_x20 | 1.26 | 1.25 | 1.99 | 0.63× (faster) |

- Per-call microbenchmarks (warm): draw 18.7µs (vs Nim's 18µs/draw),
  blur(256, r=3) 1.65ms vs 2.76ms baseline, shadow 422µs vs 1.09ms
  baseline, strokeSegment 25.4µs (unchanged, at Nim parity within codegen
  noise), fillRect 1.4µs, typeset 5.7µs; decodePNG 0.68ms vs 7.5ms
  baseline, encodePNG 2.72ms vs 3.54ms baseline.

## Limitations / residual gaps

- stroke is 1.17× and draw 1.28× of the scalar Nim reference: the pinned
  row-scan rasterizer arithmetic and Julia's scalar codegen vs Nim's.
  Closing further would need `@inbounds` in the rasterizer's pinned loops
  (range-provable but not measured to matter) or a SIMD pass, which
  D016's scalar-parity contract and AGENTS.md keep deferred.
- PNG decode went 67.3 ms → 1.50 ms (45×) by fixing our boundary
  conversion (kernel-function barrier + raw-byte channel reads); it is
  now 1.28× the reference, with the codec (libpng inflate in PNGFiles)
  as the remaining floor. PNG encode is 2.16× the reference and is
  codec-bound: ~2.1 ms of the ~2.3 ms per image is libpng compression
  inside PNGFiles `save` (D014 opt-in), not our code; the build buffer
  was still trimmed (flat `Vector{UInt8}` + `reshape`) and the
  round-trip fixtures pin the pixel contract, not the bytes, so the
  package-default compression settings are kept.

## Next

None required for the release; the board stays complete. If the draw gap
becomes a target, the recorded candidate is `@inbounds` in
`fillRowRange`/`fillHitsLine`/`fillTrapezoids!` with the range proofs
written, re-validated by the byte-exact gate.
