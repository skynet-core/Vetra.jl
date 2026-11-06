# Benchmarks

T011 harness (recorded in tasks/T011-release.md and docs/DECISIONS.md D016):

- `run_benchmarks.jl` — the Julia port, 8 workloads (fill, stroke, blur,
  shadow, draw, PNG encode/decode, text parse+layout+measure); first
  (cold) call, 3 warm-ups, 21 steady-state iterations (mean/min/median,
  ns timer) plus a separate allocation pass (bytes).
  `julia --startup-file=no --project=/tmp/pngenv run_benchmarks.jl`
  (the example env carries opt-in PNGFiles; delete
  `~/.julia/compiled/v1.13/Vetra` first if the package was precompiled
  in another env).
- `bench_reference.nim` — the same workloads against pinned upstream
  pixie, built with `nim c -d:release -d:pixieNoSimd` (scalar, oracle
  paths; checks on). No per-call allocation counter in Nim — those
  columns are `n/a`.
- Results: `benchmark/results/{julia,nim}_<date>.tsv` (gitignored; the
  numbers are recorded in tasks/T011-release.md so a clone has the
  evidence). The comparison headline is the steady-state median.
