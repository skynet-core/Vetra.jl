# T001 — Reference baseline and numerical contract

Status: see TASKS.md.
Goal: establish a runnable local scaffold and trustworthy inputs for the port.
Keep src/Vetra.jl empty.

## Inputs

AGENTS.md, upstream.toml, docs/UPSTREAM.md, docs/DECISIONS.md, test/README.md,
and the pinned source checkout.

## Work

1. Run scripts/bootstrap.jl and scripts/check.jl; record Julia version and results.
2. Fetch the pinned upstream source using scripts/fetch_upstream.jl.
3. Audit public symbols and relevant tests for colors, images, blending, paths,
   paints, context, formats, and text. Expand docs/COMPATIBILITY.md with a
   practical symbol-level inventory and mark all features unimplemented.
4. Inspect alpha conversion and blending helpers. Record channel layout, rounding,
   integer overflow/widening behavior, index mapping, bounds, and error behavior
   in docs/NUMERICAL_CONTRACT.md with source/symbol references.
5. Establish the oracle under tools/oracle/. Choose and record exact Nim/compiler
   versions, resolved dependency revisions, flags, OS, architecture, and backend.
   Characterize scalar/SIMD differences relevant to the reference policy.
6. Generate a small independent color/compositing fixture set and canonical
   raw-pixel buffers for square, line, and heart. Record provenance and checksums.
   Do not add Julia rendering algorithms or choose a codec dependency here.
7. Implement the minimal fixture reader/validator and comparison helper using
   Julia standard libraries. Test channel/row order, length/dimensions, checksum
   handling, and a deliberately mismatched buffer. Add stdlib test dependencies
   to Project.toml only as required.
8. Update decisions, compatibility inventory, and handoff. Make T002 ready only
   after the numerical contract and core fixture evidence are available.

## Acceptance criteria

- The package-load test has actually passed locally.
- The upstream checkout matches upstream.toml and the reference environment is recorded.
- Another developer can follow the exact recorded generator commands.
- Numerical choices are tied to source symbols or measured behavior.
- Canonical fixtures have dimensions, representation, provenance, and SHA-256 values.
- The comparison helper detects a known deliberate mismatch.
- No Julia graphics API or rendering implementation has been introduced.
- The handoff states which reference outputs and checks actually ran.

If Nim/toolchain access blocks reference generation, finish the source audit and
document the concrete blocker. Do not fabricate fixtures or mark this task done.

## Results (2026-10-28)

Environment: Julia 1.13.3, Nim 2.2.12 (C backend), gcc 16.2.1, Linux x86_64.

- `julia --startup-file=no --project=. scripts/bootstrap.jl` → "Environment
  ready".
- `julia --startup-file=no --project=. scripts/fetch_upstream.jl` → pinned
  checkout at `.reference/upstream/` (revision 30bb510, matches upstream.toml)
  plus pinned dependency revisions under `.reference/pkgs/`.
- `sh tools/oracle/build.sh all` → all 31 fixtures emitted, exit 0
  (5 image triples + 26 tables + checksums). Flags: `-d:pixieNoSimd`
  (scalar reference policy), default debug checks ON.
- `julia --startup-file=no --project=. -e 'using Pkg; Pkg.test()'` → 79
  assertions passed (1 smoke + 78 reference-fixture tests).
- `julia --startup-file=no --project=. scripts/check.jl` → tests passed,
  coverage gate vacuously satisfied (no measurable lines under `src/` — the
  module is intentionally empty), exit 0.

Deliverables: docs/NUMERICAL_CONTRACT.md (formulas with source/symbol
references; two distinct premul→straight conversion paths, 2708 measured
valid-domain divergent rows, e.g. a=4, c=2 → 127 vs 128),
docs/COMPATIBILITY.md (symbol-level inventory, all unimplemented),
tools/oracle/{emit_fixtures.nim,build.sh}, test/reference/ (3.6 MB, checksummed),
test/{fixtures.jl,reference_tests.jl,runtests.jl}, scripts/check.jl
(>95% src/ coverage gate per D009, parsing built-in `.cov` output).

All acceptance criteria have direct evidence above; `src/` remains
implementation-free per this task's spec.
