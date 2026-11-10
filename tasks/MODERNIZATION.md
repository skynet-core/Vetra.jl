# Julia-native modernization

Requested 2026-11-10. Baseline: `415c7a063540ad23fc5dc1be5e11a16759a71a24`,
already committed and pushed with a clean working tree. Registration remains
user-owned. Each completed task is reviewed by the coordinator, committed, and
pushed to `origin main`; implementation is assigned to
`vllm/nvidia/Qwen3.8-27B-NVFP4`. Work sequentially in a separate worktree. Never
label pending remote checks as passing.

## Scope and completion rules

Vetra becomes an independently maintained Julia graphics library. Preserve
existing numerical/rendering regression evidence and attribution; upstream
quirks no longer prevent justified bug fixes. Keep efficient scalar kernels
unless measurements justify changes. Prefer Julia constructors, Base interfaces,
explicit mutating `!` names, conventional dependency declarations, and documented
numeric boundaries. Keep old entry points compatible during this transition.

Remove obsolete port task reports and duplicate planning documents after their
still-relevant contracts/provenance have been consolidated. Retain package
metadata, legal notices, fixtures, tests, benchmarks, reproducibility tools,
current contributor instructions, and new documentation. Git preserves history.

“Fully implemented” means every advertised feature works within its explicit
contract. No claim of universal bug-freedom or full Unicode conformance follows
from passing tests. Fix reproduced defects; record remaining limitations.

## M001 — Baseline, audit, and task contract

- Owner: coordinator (planning/validation), Qwen (read-only code audit).
- Inspect repository status, current CI failures, feature inventory, exported
  API, optional providers, test fixture requirements, and performance harness.
- Identify concrete defects and portability blockers with source locations and
  reproducible checks. Inventory safe removals and required provenance.
- Record baseline full-gate result and runtime; establish before measurements
  for APIs/kernels changed later. Investigate actual remote CI logs.
- Acceptance: baseline is recoverable, tasks have dependencies/acceptance tests,
  Qwen findings are triaged, and current failures/limits are explicit.

### Recorded baseline

- Coordinator: `julia --startup-file=no --project=. scripts/check.jl` passed on
  Julia 1.13.3, coverage 95.83% (7603/7934); log
  `/tmp/opencode/vetra-modernization-baseline.log`.
- Existing [CI run 42741112923](https://github.com/skynet-core/Vetra.jl/actions/runs/42741112923):
  Linux stable, macOS stable, and Linux benchmarks passed. Windows stable failed
  loading symbol `dlopen`; Linux 1.10 failed an allocation equality (7824 versus
  1568 bytes). No FreeBSD job. These are baseline failures, not new regressions.
- `gh api repos/skynet-core/Vetra.jl/pages` returned 404: no configured site.
- Coordinator reproduced the numeric failure locally with Julia 1.10.13:
  `julia +1.10 --startup-file=no --project=. -e 'using Test, Vetra;
  include("test/numeric_api_tests.jl")'`: 22 pass, one failure (5712 vs 1568).
- Baseline `julia --startup-file=no --project=docs benchmark/run_benchmarks.jl`
  passed on Julia 1.13.3; log
  `/tmp/opencode/vetra-modernization-bench-before.log`. Single-run steady medians
  (ms): fill 0.824, stroke 26.179, blur 0.373, shadow 0.529, draw 0.240,
  PNG encode 24.924, PNG decode 3.218, text 1.267. These are comparison data,
  not generalized speed claims.
- Qwen read-only audit completed. Triaged for M002: direct Unix loader calls
  fail on Windows; numeric allocation checks need specialization warm-up;
  coverage can use stale data and omit uncovered files. For M004: PPM accepts
  zero dimensions; cmap-12 accepts invalid/inverted Unicode ranges;
  `superImage`'s absolute-offset early exit discards some partial overlaps;
  `setLineDash` aliases caller storage (verify intended snapshot contract).
  Each latent finding requires a coordinator-reviewed regression before fixing.
- Keep API evolution in M003 and parser/correctness fixes in M004 as specified.
  Encoding return-type changes require compatibility consideration, not a
  blanket rewrite. `Libdl` is a stdlib runtime dependency and must be declared.
  FreeBSD is feasible via `vmactions/freebsd-vm`, not dependent on provisioning
  a self-hosted runner. No nonstandard Julia-semantics assumption is adopted.
- Coordinator independently reproduced PPM zero-size and `superImage` lost
  overlap, and found `newImage(1 << 61, 2)` returns an empty buffer because
  dimension multiplication overflows. Add checked size arithmetic in M003's
  constructor work. cmap-12 inverted and >U+10FFFF singleton ranges are accepted;
  the audit's billion-iteration claim is withdrawn: the existing glyph-ID guard
  already rejects that case at 65536. Validate ranges before expansion in M004.
- Additional coordinator FFI review: `_hbFace` uses `get`, not `get!`, so its
  supposed cache remains empty and every shaping call leaks new native handles.
  Reproduced in the docs environment: after `shapeText`, cache length is zero
  and two `_hbFace(tf.opentype)` calls return different handles. M004 must give
  native objects explicit ownership/cleanup and reuse live font state without
  permanently retaining every parsed font. `_hbShape` also passes a temporary
  character vector as `hb_language_t`; use `hb_language_from_string` (as the
  independent C oracle already does) and guarantee buffer cleanup on exceptions.
  Reference: https://harfbuzz.github.io/harfbuzz-hb-common.html#hb-language-from-string.
  Baseline on Julia 1.13.3, one parsed Arabic font and 100 three-codepoint calls:
  13.069/13.012/12.711 ms across three warmed runs, 177600 Julia heap bytes/run;
  native leaked allocations are not counted by Julia's allocation metric.
  Log: `/tmp/opencode/vetra-shaping-before.log`.

## M002 — Restore trustworthy tests and cross-platform CI

Depends on M001. Qwen owns workflow/scripts/test changes; coordinator reviews.

- Reproduce and fix current Julia 1.10 failures without loosening pixel or
  arithmetic expectations. Allocation checks must measure warmed function calls,
  not compilation or captured-global artifacts.
- Provision all checksum-pinned assets needed by tests in clean CI checkouts.
- Test Julia 1.10 and current stable on Linux, Windows, and macOS. Add a genuine
  FreeBSD VM job with an explicit Julia version and supported optional codecs;
  attempt full suite and expose provider/platform failures honestly.
- Add bounded benchmark smoke runs on all four OS families, asserting workload
  outputs and uploading timings/allocations plus platform/runtime metadata.
  Shared-runner timings are evidence, not hard wall-clock gates.
- Make coverage fresh-run-only; missing coverage must not silently pass. Keep
  the existing >95% gate for the full-suite coverage job.
- Acceptance: coordinator runs `julia --startup-file=no --project=.
  scripts/check.jl`, reviews failures against root causes, and obtains actual
  successful remote matrix/benchmark jobs. Infrastructure failures remain
  explicitly blocked, never hidden with `continue-on-error`.

### M002 implementation and review

Qwen commits `155ac78`/`cc211fb` integrated as `95185c3`/`8bfd7ae`.
Portable Libdl loading, warmed allocation tests, Julia 1.10 Base.IdSet import,
fresh coverage checks, six Julia/OS test jobs, FreeBSD 14.3 VM with official
checksum-pinned Julia 1.10.13, and bounded benchmark checks on all four OSes.

Coordinator review fixed invalid job-level runner context, Windows shell choice,
BSD checksum syntax, unintended .mem deletion, and shadow/input confusion in
benchmark checks. `actionlint .github/workflows/ci.yml` and `git diff --check`
pass. Coordinator full-gate runs are in progress on Julia 1.13.3 and 1.10.13.
Remote validation is pending: M002 is not yet complete.

## M003 — Julia-native public API and package integration

Depends on M002 (local implementation may proceed while remote jobs run).

- Inventory public mutators, constructors, Base-name collisions, nonconcrete
  fields, and optional-dependency loading. Choose one coherent documented naming
  convention; provide conventional `!` entry points without duplicate kernels.
- Use Julia's own interfaces for owned types where semantics fit; do not add
  unrelated wrappers or change image layout to imitate Julia matrices. Document
  pixel versus matrix coordinates and premultiplied versus straight alpha.
- Declare runtime standard-library dependencies and compatible optional package
  integration using supported Julia mechanisms. Verify clean core-only and
  provider-enabled environments and load order.
- Update exports, docstrings, examples, and focused tests together. Old callers
  continue to work, with a concise migration guide.
- Acceptance: meaningful interface/inference/dispatch regressions, complete
  gate, representative before/after allocations and timings; no unmeasured
  performance claim or sweeping mechanical rewrite.

### Coordinator's bounded API contract

- Prefer lowercase/snake-case names and `!` on public mutators. Keep legacy
  names callable; reuse generic functions via constant aliases when all methods
  have the same mutation semantics, and use typed adapters for mixed
  allocating/mutating generics. No `!` alias may advertise a pure constructor
  overload as a mutator. Include drawing, paths, image effects, context state,
  recordings, text, and IO/interop in a complete migration table.
- Add `Image(width, height)` and validate positive dimensions, checked byte-count
  multiplication, and supplied storage length at construction. Preserve compact
  row-major bytes. Make Image's Julia array access follow `[row, column]`, while
  legacy `getColor`/`setColor` retain `(x, y)`; implement the appropriate Base
  interfaces coherently rather than claiming array compatibility from `size`
  alone. Test nonsquare images, bounds, iteration, aliasing, copy, and fill!.
- Extend LinearAlgebra's own `dot`/`normalize` and provide `norm(::Vec2)` /
  `det(::Mat3)` / `inv(::Mat3)` where semantics already exist. Preserve historical
  `length(::Vec2)` only as a documented legacy Euclidean-length entry point;
  do not make Vec2 an AbstractVector with incompatible length semantics.
- Color-matrix import should accept conventional one-based AbstractMatrix views
  and transposes through existing specialized kernels, with explicit rejection
  of unsupported indexing. Do not change premultiplication rounding.
- Declare optional provider UUIDs/version compatibility in package metadata;
  retain tested lazy first-use behavior unless a supported replacement is
  demonstrated to preserve core-only load latency and application load order.
  Keep old encode return types compatible; don't silently convert binary Strings
  to byte vectors in existing methods during this naming transition.

## M004 — Correctness audit and reproduced bug fixes

Depends on M003. Scope follows M001 findings and coordinator review.

- Review image dimensions/indexing/aliasing, codec/font/parser bounds, FFI
  lifetime and error paths, recording/export mutation/validation, and paragraph
  shaping/layout edge cases. Inspect connected callers and existing tests.
- Reproduce each actionable finding first. Fix shared root causes and add small
  regressions with independently justified expectations. Do not regenerate
  expected pixels from the implementation or weaken tolerances.
- Check that advertised features are executable; document deliberate unsupported
  cases precisely. Correct LTR shaping engagement if the audit confirms the
  documented implementation gap can be closed within the provider contract.
- Acceptance: all confirmed findings fixed or explicitly blocked with evidence;
  full gate, malformed-input regressions, representative render/export checks,
  and coordinator diff review pass.

## M005 — Fresh README and interactive GitHub Pages documentation

Depends on M003/M004.

- Rewrite README around Vetra's current capabilities, reproducible installation,
  a font-independent executable quick start, optional providers, and site links.
- Build a Julia-oriented site with getting started, API/reference, feature and
  limitation inventory, examples/gallery, performance and contributor guides.
  Execute examples; use documented interfaces and portable fixture fonts.
- Reuse Literate outputs where useful; include downloadable runnable notebooks,
  search/navigation, copyable code, and an accessible interactive parameter
  example using Vetra-rendered outputs. Clearly distinguish static precomputed
  rendering from a live Julia runtime. No hosted backend required.
- Configure GitHub Actions Pages build/upload/deploy using least necessary
  permissions and enable repository Pages. User requested publication of docs,
  not package registration. Avoid deploying untrusted PR code with credentials.
- Acceptance: clean docs build, executed examples, local links/assets checked,
  browser interaction smoke check, successful deployment, and live site URLs
  fetched and inspected by coordinator.

Infrastructure prepared: coordinator enabled workflow-based Pages with
`gh api --method POST repos/skynet-core/Vetra.jl/pages -f build_type=workflow`.
Target URL is `https://skynet-core.github.io/Vetra.jl/`; no deployment yet.

## M006 — Retire obsolete port scaffolding

Depends on M005.

- Consolidate durable numerical, feature, dependency, and provenance contracts
  into maintained user/developer docs; update AGENTS.md and workflow guidance.
- Remove completed T000–T032 task files and superseded roadmaps/handoffs/reports
  after checking code, test, tool, and documentation references to each removal.
- Keep attribution in translated sources, LICENSE/NOTICE/third_party licenses,
  pinned fixture metadata, oracle tools actually needed to reproduce tests,
  and current task/validation records. Do not delete unknown ignored user files.
- Acceptance: tracked tree contains maintained library/support assets, link and
  reference checks pass, clean tests/docs/benchmarks still run, diff reviewed.

## M007 — Final independent validation and handoff

Depends on M002–M006.

- Validate final pushed revision in clean environments: full tests/coverage,
  core-only/provider-enabled loading, README and docs examples, benchmark smoke,
  and all four platform CI jobs. Verify Pages deployment for final revision.
- Review public feature claims and changes with Qwen, resolve discovered defects,
  and record exact commands, commit/run URLs, runtime versions and outcomes.
- Acceptance: every earlier criterion has evidence, outstanding external blockers
  are named, working tree is clean, and final commits are pushed. Registration
  remains the user's task. No universal “bug-free” guarantee.
