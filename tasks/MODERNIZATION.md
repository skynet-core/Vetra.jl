# Julia-native modernization

**Superseded in part by the user's Canvas milestone:** see
[Canvas architecture](../docs/CANVAS_DESIGN.md) and
[R000–R099 development plan](CANVAS_ROADMAP.md). M003 and prerequisite
M004 correctness work are complete. M005 documentation is folded into the
final R099 task; M006 cleanup becomes R086; M007 integrated validation becomes
R090. Their original order below is historical, not the active execution order.

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
pass. Coordinator Julia 1.10.13 gate passed (95.86%, 7697/8029); benchmark
smoke passed. Concurrent local full gates exposed a shared Chromium fixture
directory: the stable run failed when the other run removed it. Fixed with
`mktempdir(homedir(); prefix="vetra-svgtest-")`; concurrent coordinator reruns
passed: Julia 1.13.3 95.82% (7603/7935), Julia 1.10.13 95.86% (7697/8029).
Exact commands: `julia --startup-file=no --project=. scripts/check.jl` and
`julia +1.10 --startup-file=no --project=. scripts/check.jl` in separate worktrees.
Logs: `/tmp/opencode/vetra-m002-concurrent-{stable,1.10}.log`.

[Remote run 42809642886](https://github.com/skynet-core/Vetra.jl/actions/runs/42809642886):
all six Linux/Windows/macOS test jobs and three benchmark jobs passed. FreeBSD
VM boot and checksum-verified Julia installation passed; fixture fetch failed
because Git was absent. Added VM preparation (`pkg install -y git ca_root_nss`).
**M002 complete:** [remote rerun 42811680553](https://github.com/skynet-core/Vetra.jl/actions/runs/42811680553)
passed all 10 jobs at revision `d2d44fa`. Full tests/coverage passed on Julia
1.10.13 and stable on Linux, Windows, macOS; FreeBSD 14.3 x86_64 passed the full
Julia 1.10.13 gate (95.32%, 7653/8029). Stable CI coverage was 95.26%
(7559/7935); local external-renderer checks explain the higher local coverage.
All four benchmark artifacts exist, nonempty and unexpired, verified with
`gh api repos/skynet-core/Vetra.jl/actions/runs/42811680553/artifacts`.
Full CI log: `/tmp/opencode/vetra-m002-ci-success.log`.

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

### Coordinator review of candidate `c1ea06e` (2026-11-10)

Initial status: **corrections requested**. Independently reproduced:

1. `Image(-1, 2, UInt8[], 0)` bypasses validation. Use a validated inner
   constructor and the existing three fields; ordinary `new` works on both
   supported Julia versions. Remeasure allocations after removing `nbytes`.
2. `fromColors` enters its kernel for non-one-based axes. Reject unsupported
   axes before reads, including through wrappers; range-view checks are not an
   axes check.
3. `ceil!(1.2)` wrongly calls pure Base rounding. Path `transform`, gradient
   fill and recorder finalization mutate, and `rect` mixes constructors with
   mutators. Correct typed adapters, bang names, exports and migration claims;
   include the missing snake-case pixel getter.
4. `fill!(PictureRecorder(8, 8).ctx)` has no method despite legacy support.
   Cover current-path and winding-rule overloads with a recorded-output test.
5. `using Vetra, LinearAlgebra` still makes unqualified `dot` and `normalize`
   ambiguous. Share the standard-library bindings, preserving qualified legacy
   calls, and verify both load orders in fresh processes.
6. `size(img, 1)`, `img[end]`, `eachindex(img)` and linear assignment fail.
   Complete the documented duck-typed interface with consistent storage-order
   indexing and nonsquare-image tests.

### Completion evidence (2026-11-10)

**Done, independently approved.** Qwen's final `0c88c91` follows `e0d1ff8`
(six correction groups), `62afa30` (row-major eachindex) and `0c88c91`
(dimension-aware axes and begin/end). Coordinator integrated the four commits
through `901b9d7`; validated source/tests/package metadata are identical.

- Exact final `scripts/check.jl` gates pass: Julia 1.13.3 **95.84%
  (7735/8071)**; Julia 1.10.13 **95.88% (7838/8175)**. Native API suite:
  **383/383** each; independent corrected-case probes: **42/42** each.
- Eight fresh-process core/provider and LinearAlgebra load-order combinations
  passed; the complete gates exercise all six optional providers.
- Both before/after benchmark smoke runs passed output assertions. Six workloads
  have equal allocation totals; PNG encode/decode totals are slightly lower.
  Fill/stroke totals exactly match baseline, eliminating the rejected fourth-field
  regression. Timings are recorded without a speed claim.
- API, migration, compatibility, decision and example documentation is aligned.
  Exact commands, logs, benchmark table and PyMuPDF skip are in
  `docs/HANDOFF.md`. Remote run `42913541720` at `f8b2dfe` passed all 10 jobs,
  including Linux/Windows/macOS/FreeBSD tests and benchmarks; four benchmark
  artifacts are present. M004 subsequently completed (see below).

## M004 — Correctness audit and reproduced bug fixes

Depends on M003. Scope follows M001 findings and coordinator review.

Assigned 2026-11-11 to Qwen3.8 in `/tmp/opencode/vetra-m004`, branch
`modernization/correctness`, base `9826b7e`. Own existing image/context/font/
shaping/paragraph implementation and their tests. R040 is a disjoint probe writer;
shared docs, exports, root metadata and final integration remain coordinator-owned.
M003 already closes zero-PPM/constructor validation; retain those regressions.

Review history (resolved by final approval below), 2026-11-11: first candidate
`e88aceb` rejected. Its cmap-12 change removed
the required uint32 language field from the assumed layout (both source and new
fixture), regressing valid subtables. Restore the 16-byte standard header and
validate ranges against independent spec-built bytes. The weak HarfBuzz cache
also needs explicit GC preservation through native calls; blob mode 0 is
DUPLICATE, not READONLY. Coordinator reproduced the cmap regression and checked
the primary OpenType specification and installed HarfBuzz header. Corrections
are assigned to the same writer; implementer gate passes are not approval.
The documented pure-LTR engagement limit stays deferred to R012.

Correction `e91a5a1`: header/range probes pass (6/6 coordinator checks), and
GC preservation/blob-copy claims are corrected. Further bounded correction is
required: detect HarfBuzz's documented empty-buffer allocation-failure sentinel,
not just NULL. Coordinator fault injection reproduced silent empty output;
add failure/recovery coverage and remove an invalid assumption that a dead
ephemeral font cannot be finalized before an explicit `GC.gc()`.
Additional reproduced image-bound finding: positive Int-limit crop offsets wrap
the endpoint sum and incorrectly enter `subImage`. Fix overflow-safe containment
and bounds in both crop functions; retain transparent far-outside results and
explicit invalid-subimage errors. Assigned to the same M004 writer.

**Completed and independently approved 2026-11-11:** final `52a40b9`, integrated
through `7b6e7c0` after the two correction rounds above. Source/tests match the
validated candidate. Full coordinator gates: Julia 1.13.3 **95.79% (7762/8103)**;
Julia 1.10.13 **95.83% (7865/8207)**. Independent probes: **113/113 each**,
including native buffer failure injection at three stages with exactly-once
cleanup, GC inside native-use intervals, spec-built cmap bytes and Int-limit
crop cases. Targeted before/after shaping/crop benchmarks completed; exact
commands/results and the unavailable PyMuPDF check are in `docs/HANDOFF.md`.
Remote CI run 43002436891 passed 9/10 jobs; current-Julia Windows failed the
pre-existing constructor allocation-parity test, also seen on baseline 9826b7e.
All four benchmark artifacts are present. A bounded Qwen follow-up in
`modernization/windows-allocation` investigates the gate; remote verification
remains open (see handoff). Follow-up `6eff5cd` is independently approved and
integrated as `e879026`: pool-sized allocation workload, exact equality retained,
both full gates and 304 independent probes/version passed; Windows CI pending.
Pure-LTR paragraph engagement retains D033's
named limitation for R012; R040 continues and R099 remains the final task.

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
