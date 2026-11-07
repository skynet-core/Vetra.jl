# Current handoff

Updated: 2026-11-07

## State

T000–T013 are complete, including the user-requested cleanup;
see [the task record](../tasks/T013-cleanup.md) for scope and acceptance.
The current session owns the working-tree changes. Nothing has been committed
or published by this session.

## Changes

- Added [GETTING_STARTED.md](GETTING_STARTED.md), a basics-to-advanced Markdown
  guide with 13 runnable blocks, exercises, expected outputs, and troubleshooting.
- Removed committed allocation traces and obsolete scaffold documentation;
  ignored process-suffixed allocation output and removed stale generated traces.
- Simplified PNG encoding by sharing `toStraightAlpha`, retaining its opaque
  fast path. Removed an unused XML wrapper and a duplicate export.
- Consolidated API, architecture, task board, and current handoff documentation.
  Historical acceptance evidence remains in task records and decisions.

## Verification

- Extracted all 13 guide blocks to
  `/tmp/opencode/vetra-getting-started.jl` and ran
  `julia --startup-file=no --project=docs /tmp/opencode/vetra-getting-started.jl`.
  All assertions passed on Julia 1.13.3 before and after cleanup; card,
  curves/holes, blending, and SVG outputs were visually inspected.
- `julia --startup-file=no --project=. scripts/check.jl` passed:
  **811,409 assertions**, **97.94% coverage (5331/5443)** with fresh coverage
  output. Log: `/tmp/opencode/cleanup-check.log`.
- `julia --startup-file=no --project=docs docs/make_tutorial.jl` passed:
  both Markdown and notebook executed. README profiling example also ran and
  collected samples; the old claim that sampling was unusable is superseded.
- Local Markdown file links checked in 33 documents; public exports unchanged
  (276 names); `git diff --check` passed. Fixtures are unchanged.
- Benchmark before/after logs: `/tmp/opencode/cleanup-benchmark-{before,after}.log`.
  PNG encode workload median 23.906 → 24.702 ms, identical allocation total;
  these single-run measurements are a regression check, not a new speed claim.

## Working commands

From the repository root:

```sh
julia --startup-file=no --project=. scripts/fetch_upstream.jl
julia --startup-file=no --project=. scripts/check.jl
julia --startup-file=no --project=docs -e 'using Pkg; Pkg.develop(path="."); Pkg.instantiate()'
julia --startup-file=no --project=docs docs/make_tutorial.jl
julia --startup-file=no --project=docs benchmark/run_benchmarks.jl
```

Reference assets are under ignored `.reference/`; tests do not fetch them.
Tutorial output goes to ignored `docs/build/` and `artifacts/`; benchmark
TSVs go to ignored `benchmark/results/`. Optional codecs are discovered at
runtime; install them before loading Vetra, or restart Julia after installation.

## Next step and limits

User review of the uncommitted diff. Registration/publishing requires
an explicit request. GPU backends, general Unicode shaping, unrestricted SVG,
and WebP remain outside the implemented scope; see [Compatibility](COMPATIBILITY.md).
Fresh installation, cross-platform CI, independent notebook-kernel execution,
and the ProfileView GUI were not rerun. Historical release evidence is in
[T011](../tasks/T011-release.md), [T012](../tasks/T012-optimization.md), and
[DECISIONS.md](DECISIONS.md).
