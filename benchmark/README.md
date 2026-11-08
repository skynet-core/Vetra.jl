# Benchmarks

T011 harness (recorded in tasks/T011-release.md and docs/DECISIONS.md D016):

- `run_benchmarks.jl` — the Julia port, 8 workloads (fill, stroke, blur,
  shadow, draw, PNG encode/decode, text parse+layout+measure); first
  (cold) call, 3 warm-ups, 21 steady-state iterations (mean/min/median,
  ns timer) plus a separate allocation pass (bytes).
  From the repository root:
  `julia --startup-file=no --project=/tmp/pngenv benchmark/run_benchmarks.jl`
  (replace `/tmp/pngenv` with an environment containing Vetra and PNGFiles;
  see the [tutorial setup](../docs/TUTORIAL.md#setup)).
- `bench_reference.nim` — the same workloads against pinned upstream
  pixie, built with `nim c -d:release -d:pixieNoSimd` (scalar, oracle
  paths; checks on). No per-call allocation counter in Nim — those
  columns are `n/a`.
- Results: `benchmark/results/{julia,nim}_<date>.tsv` (gitignored; the
  numbers are recorded in tasks/T011-release.md so a clone has the
  evidence). The comparison headline is the steady-state median.
- CI (D018): `.github/workflows/ci.yml` runs `run_benchmarks.jl` (Julia
  side only) on every push to `main` — it builds a throwaway env with
  `Pkg.develop` + `Pkg.add("PNGFiles")` (the D014 opt-in) in
  `$RUNNER_TEMP` and uploads the TSV as the `benchmark-results`
  artifact. The Nim reference side stays local (pinned Nim toolchain).

## Application suite (T020)

Separate from the comparison harness above; it establishes baselines for
application-style work (not a Nim comparison):

- `app_benchmarks.jl` — canvas scenes at 256px/1080p/4K, complex curved
  paths, a text-heavy card, clipping/layers, the PNG pipeline split into
  draw / boundary conversion (`toStraightAlpha`) / encode for
  flat/gradient/noise × opaque/translucent at 1080p, a 4K encode, and
  repeated render+encode at 1080p. Invariants (dimensions, pixel checks)
  are asserted before any timing. From the repository root:
  `julia --startup-file=no --project=docs benchmark/app_benchmarks.jl [run]`
  — run at least three times sequentially; outputs are
  `benchmark/results/app_<date>_r<run>.tsv` (+ `.tsv.meta` with machine and
  parameters, and five representative PNGs per run).
- `startup_benchmarks.jl` — separate fresh processes measuring cached
  package load (3 runs), first render including JIT (1), warm render (1),
  and a cold-depot run (brand-new `JULIA_DEPOT_PATH`). Output:
  `benchmark/results/startup_<date>.tsv` (+ `.tsv.meta`).
- Baselines, interpretation, and the T021/T022 optimization targets are
  recorded in [tasks/T020-application-benchmarks.md](../tasks/T020-application-benchmarks.md).
