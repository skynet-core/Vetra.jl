# T020 — Representative application benchmarks

Status: see [TASKS.md](../TASKS.md). Dependencies: T013. Priority: performance.
Goal: establish trustworthy baselines before optimizing latency or throughput.

## Inputs and scope

Read benchmark/, T012/T013, README profiling guidance, and application recipes.
Keep the eight existing Julia/Nim comparison workloads unchanged. Add a separate
application suite covering 256px, 1080p, and 4K canvases; complex curved/stroked
paths; text-heavy cards; clipping/layers; and repeated rendering/encoding.
Use deterministic, bounded inputs with documented dimensions and complexity.

## Acceptance criteria

- Measure process startup/package load/first render in separate fresh processes;
  distinguish cold depot, cached package loading, compilation, and warm drawing.
- Report drawing, boundary conversion, and PNG encoding separately; include
  opaque/translucent and flat/gradient/noisy images, file sizes, and allocations
  per image rather than unlabeled totals across multiple iterations.
- Run at least three independent runs sequentially; preserve raw samples,
  versions, machine details, parameters, and variability with unique output names.
- Assert output dimensions and independent simple visual/math invariants before
  timing. Benchmark code must not silently measure no-op or invalid workloads.
- Publish baseline bottlenecks and concrete measurable targets for T021/T022;
  do not attribute package time to an internal codec stage without isolating it.

## Validation

Run the existing harness via [shared validation](../docs/ROADMAP.md#shared-validation)
and document/run the new application-suite command. Check that the result schema
and all workload names/samples are present; inspect representative output images.

## Results and handoff

Status: done (2026-11-07). Baselines recorded below; T021/T022 unblocked.

### New suite

- `benchmark/app_benchmarks.jl` — application workloads, run with
  `julia --startup-file=no --project=docs benchmark/app_benchmarks.jl [run_index]`
  (3 runs done sequentially; raw TSVs + `.tsv.meta` + 5 representative PNGs
  per run under gitignored `benchmark/results/app_2026-11-07_r{1,2,3}.*`).
  Every workload renders a deterministic scene and asserts independent
  invariants (dimensions, corner/ink/blend pixel checks) before timing;
  per-workload 3 warm-ups, 7 samples, separate allocation pass reporting
  bytes per item; PNG pipeline split into draw / boundary
  (`toStraightAlpha` full-buffer pass, timed standalone) / encode stages,
  across flat/gradient/noise × opaque/translucent at 1080p plus a 4K encode.
- `benchmark/startup_benchmarks.jl` — fresh-process protocol:
  `julia --startup-file=no --project=docs benchmark/startup_benchmarks.jl`.
  A pixel-asserted 256x256 probe measures, in separate fresh processes:
  cached load (3 runs), cold-depot load (1 run, brand-new
  `JULIA_DEPOT_PATH`), first render (JIT), warm render. Parent-measured
  total wall time included. Output: `benchmark/results/startup_2026-11-07.tsv`.
- The eight T011 Julia/Nim comparison workloads in `run_benchmarks.jl` are
  unchanged; it still runs via the shared validation command.

### Baselines (medians, ms; machine AMD Ryzen 9 5980HS 16 threads, Linux
7.0.0-42, Julia 1.13.3, precompiled; r1–r3 spread in parentheses)

| workload / stage | median | alloc/item | notes |
| --- | --- | --- | --- |
| canvas_256/draw | 2.4 | 2.4 MB | representative card scene |
| canvas_1080p/draw | 61–66 | 26.5 MB | same scene, 1920x1080 |
| canvas_4k/draw | 238–251 | 101 MB | 3840x2160 |
| paths_complex/draw | 14.5–17.2 | 21.5 MB | 200 quad + 100 arc strokes + 50 filled beziers @1280x720 |
| text_card/draw | 5.5–6.0 | 11.3 MB | 24 lines + 100 measureText @1280x720 |
| clip_layers/draw | 349–353 | 182 MB | 12 saveLayer groups, circular clip, gradient + MultiplyBlend |
| png_flat_opaque/encode | 36.0 | 24.9 MB | codec floor; 9 KB file |
| png_flat_alpha/encode | 46–56 | 24.9 MB | + boundary pass 16–27 ms (noisy, small workload) |
| png_gradient_opaque/encode | 75–89 | 30.0 MB | 1.28 MB file |
| png_gradient_alpha/encode | 69–70 | 27.8 MB | 699 KB file |
| png_noise_opaque/encode | 83–96 | 33.3 MB | 2.09 MB file |
| png_noise_alpha/encode | 110–123 | 38.8 MB | 3.13 MB file |
| png_4k/encode | 386–418 | 124 MB | 5.11 MB file |
| repeat_1080p/draw | 54–62 | 26.5 MB | per render |
| repeat_1080p/encode | 36–38 | 25.0 MB | per encode |
| repeat_1080p/draw+encode | 89–98 | 51.5 MB | stages additive |
| startup cached load | 579–587 | — | fresh process, precompiled |
| startup first render | 2468–2548 | — | JIT of first method instances |
| startup warm render | 38–40 | — | steady state |
| startup cold depot | 4328 total | — | new JULIA_DEPOT_PATH incl. precompile |

Interpretation (recorded for T021/T022):
- First-render latency (~2.5 s) is dominated by JIT compilation of first
  method instances, not package load (~0.58 s cached); cold-depot total is
  ~4.3 s because the pinned Manifest avoids a registry fetch (precompile
  only).
- Drawing allocation scales with canvas: 26.5 MB per 1080p scene, 101 MB
  per 4K scene; clip_layers is the allocation hotspot (182 MB from 12
  full-size layer buffers + gradient paints).
- PNG encode is codec-bound for flat content (36 ms / 9 KB at 1080p is the
  codec floor, so boundary work must not be attributed to it); translucent
  content adds the 16–20 ms boundary pass; encode allocation is 25–39 MB
  per 1080p image (straight-alpha output buffer + codec temporaries).
- Text (6 ms / 11 MB) and complex paths (15 ms / 22 MB) are not
  bottlenecks at these scene sizes.

### Targets for T021 / T022 (measurable, from this baseline)

- T021: reduce cached load (579–587 ms) and/or first render (2468–2548 ms)
  in a repeatable way without moving cost to an unreported install/first-use
  stage; warm render (38–40 ms) is the steady-state reference.
- T022: reduce per-image draw allocation (26.5 MB @1080p, 101 MB @4K,
  182 MB @clip_layers-12) and PNG encode allocation (24.9–38.8 MB @1080p,
  124 MB @4K); for translucent images the boundary pass (16–20 ms,
  8.3 MB) is addressable; opaque encode wall time (36 ms flat) is the
  codec floor — gains must be measured against it, not attributed to it.

### Verification

- 3 independent app runs + 1 startup protocol run executed sequentially;
  raw samples, versions (Julia 1.13.3, PNGFiles 0.4.5), machine details,
  parameters, and run-to-run spread preserved with unique names
  (`app_2026-11-07_r{1,2,3}.tsv[.meta]`, `startup_2026-11-07.tsv[.meta]`).
- Result schema and workload names checked: all 27 app rows per run and all
  4 startup rows present; representative outputs visually inspected
  (canvas_1080p, paths_complex, text_card, clip_layers, noise_alpha).
- Two build quirks hit and worked around (recorded): a multi-line `@assert`
  with the message on the next line mis-parses in this build (kept messages
  on one line / used a precomputed condition); `Sys.cpu_info()` returns
  `Vector{CPUinfo}` (`.model` field) and `Sys.Uname`/`OS_NAME`/`CPU_info`
  are absent here (meta falls back to `/proc` + fields with a bound catch).

### Limitations

Single machine (local); cold-depot run reuses the pinned docs Manifest, so
it measures precompile + first use, not registry resolution. Julia 1.10
and other OSes not benchmarked (CI legs, T019). Next: T021 (startup),
T022 (allocations/PNG throughput).
