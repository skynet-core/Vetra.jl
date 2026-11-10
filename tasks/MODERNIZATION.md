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
- Detailed Qwen audit: pending.

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
