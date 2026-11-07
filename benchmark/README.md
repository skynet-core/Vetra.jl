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
