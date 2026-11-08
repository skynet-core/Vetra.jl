# Roadmap: adoption, interoperability, and advanced graphics

Approved for planning by the user on 2026-11-07 (D023). This is the forward
roadmap after T013, not a claim that these features already exist. The
[task board](../TASKS.md) is the source of truth for status and dependencies;
each linked task specifies scope, acceptance evidence, and likely files.

## Priorities

### 1. Make the existing library easy to adopt

- **T014:** ordinary numeric arguments at drawing boundaries.
- **T015:** conversion to/from standard Julia color matrices.
- **T016:** automatic IJulia/Pluto image display using optional PNG support.
- **T017:** browsable documentation, visual gallery, and runnable recipes:
  candlesticks, sparklines, gauges, KPI cards, annotations, scientific diagrams,
  dashboard thumbnails, and social-preview cards.
- **T018:** release readiness, clean-environment installation, documentation
  build, and packaging checks.
- **T019:** actual registration/publication, after T018 and an explicit request
  to publish. Preparing this roadmap does not publish a package or website.

The intended first adoption release includes T014–T018; it does not wait for
vector export, typography, or every performance experiment below.

### 2. Measure real applications, then optimize

- **T020:** reproducible larger-canvas, complex-path, text-heavy, and batch
  workloads, separating cold start, drawing, and encoding.
- **T021:** reduce load/first-render latency using those measurements.
- **T022:** reduce repeated-drawing allocations and improve PNG throughput.

Keep the existing eight scalar Nim-comparison workloads intact. New workload
results must name versions, dimensions, sample counts, allocations, and output
size. No speed claim follows from code cleanup alone.

### 3. Add reusable drawing and vector output

- **T023:** design a bounded recording API and export capability matrix.
- **T024:** implement immutable/snapshotted drawing recordings and CPU replay.
- **T025:** SVG export from recorded geometry.
- **T026:** PDF export from recorded geometry.

Record geometry before rasterization: an `Image` alone cannot recover paths
or text. Export limitations must be explicit, especially blending, effects,
clipping, and fonts. A new backend must not replace the native Julia renderer.

### 4. Broaden typography and web-image formats

- **T027:** define text-layout and optional shaping contracts/dependencies.
- **T028:** wrapping, styled runs, paragraph alignment, and font fallback.
- **T029:** opt-in shaping and bidirectional text for the documented scripts.
- **T030:** select and document optional codec dependencies and their contracts.
- **T031:** JPEG encoding.
- **T032:** WebP decoding/encoding, with a documented static-image subset.

Default pinned text/rendering behavior stays stable. New shaping and codecs
need separate expected outputs and provenance, not changes to old fixtures.

### Deferred

GPU rendering and a widget/window/event framework remain deferred. Revisit
GPU work only with an application benchmark showing that CPU rendering is the
bottleneck; reconsider widgets only with an actual interaction/layout use case.
Do not start either from a general "continue" request. More elaborate plotting
APIs should follow usage of the recipes rather than precede it.

## Agent execution contract

1. Read AGENTS.md, TASKS.md, docs/HANDOFF.md, then the selected task spec.
   The first ready task is **T014**. Claim one task and mark it `in_progress`.
2. Complete that task, not the whole roadmap. Design tasks produce a recorded
   decision/API contract before their dependent implementation tasks are ready.
   If a task exceeds one coherent change, split it and update dependencies.
3. Check callers, exports, optional integrations, tests, docs, and fixtures.
   Preserve existing numerical behavior and file provenance. Core rendering
   remains Julia 1.10-compatible and free of mandatory codec/font dependencies.
4. Record any new optional-package/API decision before implementing it. D014
   and D015 remain binding until explicitly extended by that decision; no
   particular external provider is selected by this roadmap.
5. Include focused tests in `test/runtests.jl`; optional integrations must be
   exercised both absent and present, including precompile-cache reuse where
   applicable. If adding `ext/`, extend coverage measurement to cover its code
   under the same >95% requirement rather than hiding it outside `src/`.
6. Record actual verification, limitations, and the next ready task in the
   task's Results section and HANDOFF. Unblock dependent tasks only when every
   prerequisite is done. Commit or publish only when separately requested.

Default to one implementation writer. If parallel work is explicitly requested,
use separate worktrees and nonoverlapping file ownership per
[AGENT_WORKFLOW.md](AGENT_WORKFLOW.md). Ready tasks are alternatives to claim,
not an instruction to launch parallel agents. Shared Project.toml, exports,
test includes, and documentation changes need coordinated integration.

## Shared validation

From the repository root (fetch fixtures separately if missing):

```sh
julia --startup-file=no --project=. scripts/fetch_upstream.jl
julia --startup-file=no --project=. scripts/check.jl
julia --startup-file=no --project=docs -e 'using Pkg; Pkg.develop(path="."); Pkg.instantiate()'
julia --startup-file=no --project=docs docs/make_tutorial.jl
julia --startup-file=no --project=docs docs/make_cookbook.jl
julia --startup-file=no --project=docs benchmark/run_benchmarks.jl
git diff --check
```

Run the full gate for code changes and tutorials for changed user-facing examples.
Benchmark when a task touches rendering, conversion, encoding, loading, or a hot
API boundary. Run tests and timing comparisons sequentially, not concurrently.
Use the same environment and workloads before/after; retain raw logs and report
run-to-run variability. New capabilities use independently justified math,
format specifications, or pinned external references, never self-generated
expected pixels. Design/documentation-only tasks validate links, dependencies,
and code examples without claiming implementation or runtime validation.
