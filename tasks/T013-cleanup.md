# T013 — Library cleanup and documentation consolidation

Status: done (2026-11-07). Dependencies: T012.

## Scope

User request: refactor the project and remove redundant files so the library
is clean and easy to use. Preserve the supported public API, numerical
contract, independent fixtures, provenance, and existing optimizations.

- Remove committed allocation traces and generated coverage/profiling output;
  ignore process-suffixed allocation traces so they do not return to Git.
- Remove obsolete scaffold prompts, the completed roadmap duplicated by the
  task specifications, and the superseded T007 split-task pointer.
- Remove an unused XML lookup wrapper and duplicate export; reuse the existing
  alpha conversion in PNG encoding instead of maintaining a second formula.
- Replace stale current-state/API/architecture documentation with accurate,
  concise guidance. Keep historical task and decision records as evidence.
- Preserve the new basics-to-advanced Markdown tutorial and verify its examples.

Affected callers: SVG parsing uses `_requireXml` directly; the removed
`_xmlModule` has no callers or exports. PNG encoding is called by image I/O,
base64, examples, tutorials, and benchmarks; its round trips and error paths
are covered in the format and codec-loading suites. `toStraightAlpha` also
serves QOI and has exhaustive independent arithmetic fixtures.

## Acceptance

- `julia --startup-file=no --project=. scripts/check.jl` passes with >95%
  source coverage and unchanged expected fixtures.
- Tutorial Julia blocks and the executable OHLC tutorial pass.
- PNG benchmark comparison shows no material regression from simplification;
  keep measured fast paths and do not infer new speed claims from cleanup.
- Deleted documentation has no remaining live references; generated profiler
  files are absent from the final tree and ignored on subsequent runs.
- Update TASKS.md and docs/HANDOFF.md with actual results.

## Verification

- Removed 11 redundant tracked files: eight process-specific allocation
  traces (5,515 lines of annotated source), the obsolete prompt collection,
  the completed roadmap, and the superseded T007 split pointer. Updated the
  roadmap's two task references to the governing provenance/performance docs.
- Removed 1,256 additional stale generated coverage/allocation files from
  `src/`, `test/`, and `examples/` (27,642,548 bytes). No source, fixtures,
  local environments, reference assets, or tutorial outputs were removed by
  this generated-file cleanup. Removed newly generated coverage output again
  after validation; `.gitignore` now covers process-suffixed `.mem` files.
- `julia --startup-file=no --project=. scripts/check.jl` passed on Julia
  1.13.3: **811,409 assertions**, source coverage **97.94% (5331/5443)**.
  Log: `/tmp/opencode/cleanup-check.log`. Prior coverage files were removed
  before running the gate, so the result uses this run's data.
- `julia --startup-file=no --project=docs benchmark/run_benchmarks.jl` ran
  before and after the source refactor, sequentially. PNG encode median:
  **23.906 → 24.702 ms** per ten images (+3.3%); allocation total unchanged
  at **195,806,856 bytes across the harness's allocation pass**. PNG decode:
  1.595 → 1.564 ms. These single-run measurements show no large regression,
  but do not establish a speedup or statistically exclude a small regression.
  Logs: `/tmp/opencode/cleanup-benchmark-{before,after}.log`.
- Extracted all 13 Julia blocks from `docs/GETTING_STARTED.md` into
  `/tmp/opencode/vetra-getting-started.jl`; ran
  `julia --startup-file=no --project=docs /tmp/opencode/vetra-getting-started.jl`
  after the refactor: all assertions passed. Card, curves/holes, blend, and SVG
  examples were visually inspected during tutorial development.
- `julia --startup-file=no --project=docs docs/make_tutorial.jl` passed:
  executed both Markdown and notebook outputs. Log:
  `/tmp/opencode/cleanup-tutorial-build.log`.
- Extracted the README profiling example into
  `/tmp/opencode/vetra-readme-profiling.jl`; ran
  `julia --startup-file=no --project=. /tmp/opencode/vetra-readme-profiling.jl`:
  timing/allocation labels printed, inferred types displayed, and the sampling
  profiler collected samples. Runtime debug-address-table warnings were emitted
  but the process succeeded. Log: `/tmp/opencode/cleanup-readme-profiling.log`.
- Checked local Markdown file links in 33 documents, removed-file references,
  and `git diff --check`. Public exports before/after are the same 276 names;
  independent fixtures are unchanged.

## Limits and next step

Validation used the existing Linux/Julia 1.13.3 environment. No fresh install,
cross-platform CI run, independent Jupyter-kernel rerun, or ProfileView GUI
check was performed. No dependencies or public APIs were added, no fixture
expectations changed, and no files were committed or published.
Next: user review; further optimization requires workload-specific measurements.
