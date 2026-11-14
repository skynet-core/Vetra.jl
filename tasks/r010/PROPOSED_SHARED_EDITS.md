# R010 revision 9 — historical shared-document proposals

Coordinator integration follows approval of `c81e15b` by both reviewers.
The current status/decision records are `TASKS.md`, `docs/HANDOFF.md` and D039;
the submission-time proposals below are retained for provenance, not current
instructions or approval status.

These edits are **proposals only**. The writer owns
`docs/CANVAS_CONTRACT.md` and `tasks/r010/**`; shared docs are
integrated by the coordinator after normative re-review passes.
Anchors below are from authoritative main `64e887c` ("Record R010
eighth-review closures and two remaining boundary corrections", on
top of `cf73d4f`; the worktree's shared-doc copies are stale and were
**not** used as anchors). No R010 approval/ready-row claim is made;
readiness rows remain gated on R010 approval per `docs/HANDOFF.md`.

## 1. `TASKS.md` (line 94, R010 row)

Current (main `64e887c`):

```
| R010 (revision 9 in progress) | Qwen3.8, `/tmp/opencode/vetra-r010`, `canvas/frontend-contract` | Proposed contract, scenario tables and boundary checker; duplicate frontend retired | 06046d0 overall approval withheld; 508 candidate + 69 coordinator assertions/version, independent 190 positive + 15 counterexample/control assertions/version; two-group table/error-domain correction assigned; prior closures preserved; no candidate merged |
```

Proposed (on the revision-9 candidate commit submission):

```
| R010 (revision 9 candidate submitted) | Qwen3.8, `/tmp/opencode/vetra-r010`, `canvas/frontend-contract` | Proposed contract, scenario tables and boundary checker; duplicate frontend retired | 06046d0 overall approval withheld (three v7 counterexamples closed; prior approvals preserved); revision 9 candidate submitted: two corrections in `docs/CANVAS_CONTRACT.md` (the final legacy source-over accept row now covers the unwrapped artistic draw — the preceding wrapped-artistic rejection governs, helper/control unchanged; the tracked handle's stored error is one sufficient exception domain — the §7 named phase-1 validation error preserved by identity alongside TransferError/BackendSubmitError, no stranding of failed state); `tasks/r010/boundary_check.jl` 524/524 on Julia 1.13.3 and 1.10.13; pending coordinator + independent normative re-review; no candidate merged |
```

## 2. `tasks/CANVAS_ROADMAP.md` (line 102, R010 row)

Current:

```
| R010 | Freeze Canvas semantics and backend/package contracts | F | R000, R040, M003 | revision 9 in progress (06046d0 overall approval withheld; two-group legacy-table/staged-validation-error correction assigned; prior closures preserved; no candidate merged) |
```

Proposed:

```
| R010 | Freeze Canvas semantics and backend/package contracts | F | R000, R040, M003 | revision 9 candidate submitted (two corrections applied — legacy accept-row coverage + stored-error domain; 524/524 boundary checks on Julia 1.13.3 and 1.10.13; pending coordinator + independent normative re-review; no candidate merged) |
```

## 3. `docs/CANVAS_DESIGN.md` (status block, line 6)

Current:

```
R010's executable interface freeze remains pending; approval is not provider/runtime evidence.
```

Proposed:

```
R010's executable interface freeze is at revision 9 (candidate
submitted, under normative re-review after the 06046d0 approval
withheld; the three v7 counterexamples are closed and prior
independent approvals preserved); approval is not provider/runtime
evidence.
```

## 4. `docs/HANDOFF.md` — new section after the revision-8 review block

Proposed section (insert after the `#### R010 revision 8 review
(2026-11-14)` block, before `#### R010 revision 7 review
(2026-11-14)`):

```
#### R010 revision 9 submission (2026-11-14)

Revision 9 (commit `<sha>`, on top of the withheld `06046d0`)
responds to the two-correction v8 review
(`/tmp/opencode/r010-v8-coordinator-review.md`) + the independent
v8 report (which accepts the repaired partial / atomic-unwritten /
BackendSubmitError staged-failure cases, the reference-checked
provider release, the pending/failed ownership distinction, the
zero-opacity Copy rejection, and the internal action/owner metadata
explanation).

- `docs/CANVAS_CONTRACT.md` carries the two corrections:
  (1) §14 revision 9 — the final source-over accept row no longer
  requires non-artistic: it now reads "unclipped, or with the
  implicit clip wrapper only when non-artistic, or inside a group
  with L == E", so the unwrapped artistic draw (root or explicit
  group) has its accept row while the preceding wrapped-artistic
  rejection governs (the legacy Paint carries the blendMode; the
  true backdrop is intact — the actual-recorder control Multiply
  over blue ⇒ black pins it). The helper behavior is unchanged — a
  table-consistency correction, not a new capability.
  (2) §8.1 revision 9 — the tracked handle's stored error is ONE
  sufficient exception domain (the original named error preserved
  by identity: the provider's BackendSubmitError; the staged
  TransferError with its :partial/:unwritten status; the §7 phase-1
  named validation error — e.g. ArgumentError — raised before any
  store), replacing the revision-8 restricted union that stranded
  :failed with no error (later waits threw nothing). §7 staged-
  failure paragraph and route (6), the single route step (4), the
  close rule and the G1/G12 rows are aligned. No retry/reset API,
  no callback framework, no production claim; upload pre-dispatch
  validation is unchanged.
- `tasks/r010/boundary_check.jl` — **524/524** on Julia 1.13.3 and
  1.10.13 (`julia --startup-file=no --project=. tasks/r010/boundary_check.jl`
  and `julia +1.10 ...` in `/tmp/opencode/vetra-r010`);
  `git diff --check 06046d0..HEAD` clean. The new pin composes the
  existing record helpers — `CommitDest([7,7,7])` +
  `commit_or_report!(dest, [1,300,3])` as the tracked staged action
  (300 is the helper's deliberate Int validation input, not a
  UInt8 buffer claim): the original ArgumentError observed and
  re-thrown by identity on direct wait, wait-all and close; zero
  stores; destination untouched; action invoked once; core staging
  retained; provider already released. All v8 pins (partial /
  atomic-unwritten / action-error stickiness, the reference-checked
  16-frame provider drain, zero-opacity Copy rejection +
  reproductions) are unchanged. Pinned canonical fixtures
  unchanged: 2×2 document 357; 64×64 document 22187 / base64 data
  21848; rect-fill record 325; fractional clear 102; `0.1f0` clear
  record 100; 100-quote string 202; `typemax(Int)` 19 digits;
  `floatmax(Float32)` 12 bytes; image-opacity `0.1f0 ⇒ 0.1`;
  inverse-DPI quotient 9.999999602635718.
- Historical reviewer probes
  (`/tmp/opencode/r010-v8-coordinator-probe.jl`,
  `/tmp/opencode/r010-independent-review-v8/probe.jl`) were used
  read-only as references; their v8 counts are not cited as v9
  evidence.
- Pending: coordinator + independent normative re-review of the v9
  contract; the GLSL ES shader-route decision and the `SomePaint`
  export remain open; shared-status integration per the writer's
  `tasks/r010/PROPOSED_SHARED_EDITS.md`.
```

## 5. `docs/DECISIONS.md` — append D039 after D038

The revision-5/6/7/8 D039 drafts were never applied and are
**superseded** by this one:

```
## D039 — R010 revision 9: failure-safe staged completion, actual
provider-root release, and the closed legacy accept coverage

Status: **proposed (writer record pending integration)**,
2026-11-14, following the two-correction v8 review of `06046d0`
(overall approval withheld by both reviewers; the three v7
counterexamples closed and all prior independent approvals
preserved).

- The single completion route (doc §8.1) has two independent
  sticky failure classes. Provider failure (BackendSubmitError
  from the forwarded provider wait): the staged action is never
  run; the core entry and the provider resources are retained (the
  work did not complete). Staged failure AFTER provider completion:
  the original named error is preserved BY IDENTITY — the
  TransferError keeping its :partial/:unwritten status, a named
  BackendSubmitError from the core dispatch, or the §7 phase-1
  named validation error (e.g. ArgumentError) raised before any
  store; repeated direct wait, wait(c) and close(c) re-raise the
  same error; the staged action is never re-run automatically; no
  resubmission of the already-completed provider work; the entry is
  never completed or retired; the core staging is retained by the
  failed entry while the provider roots are already released — the
  contract retains no released resources. The staged_done success
  flag is set only after successful staging. The tracked handle's
  stored error is ONE sufficient exception domain (no conversion
  that can strand :failed with no error; not a growing union of
  individual exception classes). The concrete staged action
  closure and the tracking-root back-reference are core-internal
  representation (opaque to the provider). §7 commit rule and
  route (6) are reconciled to the route. No retry/reset API or
  callback framework is introduced.
- Provider completion actually releases batch roots: at completion
  the provider releases the references its submission held — a
  completed provider handle retains no batch/asset roots wherever
  it is kept (scalar completion observations may remain); pending
  and failed handles retain them. Acceptance evidence checks the
  reachable references, not a release flag.
- Legacy Picture adapter (canvas_picture(r)): the disjoint
  conservative decision procedure (first match wins) rejects Copy
  fill/stroke/text at effective opacity 0 (the legacy
  fillPath/strokePath early-return on zero Paint.opacity leaves the
  destination where normalized Copy must clear — reproduced 1×1 on
  the actual recorder; the transparent-color @ unit-opacity
  control is a different route and clears); Copy at nonzero
  opacity is admitted with no implicit clip wrapper — unclipped at
  root or inside an explicit group (GroupStart.opacity carries the
  group factor 1:1); source-over non-artistic is admitted unclipped
  or through the implicit clip wrapper at root; source-over
  ARTISTIC is admitted when unwrapped (root or explicit group, L ==
  E — the legacy Paint carries the blendMode, the true backdrop is
  intact) and rejected under the implicit clip wrapper (the
  preceding reject row governs). Normalized recording support and
  existing legacy behavior are unchanged; every rejection is a
  legacy-conversion limit only.
- Compatibility impact: none (contract + task records only; no
  production code, no dependencies). Evidence: 524/524 boundary
  checks on Julia 1.13.3 and 1.10.13 (arithmetic/record/dispatch
  + 1×1 actual-legacy reproductions only); runtime acceptance
  remains with the §19 ⏳ owners; both reviews must approve
  before freeze.
```

## 6. `docs/INDEX.md`

No change proposed for revision 9: the existing nav already points
to `CANVAS_DESIGN.md` and the contract draft is referenced through
`TASKS.md`/`HANDOFF.md`. Revisit only if the coordinator wants the
contract linked directly from the index after approval.

## Integration note

Order for the coordinator on approval: apply §1 and §2 (status
rows), §3 (design status line), §4 (handoff section, filling the
`<sha>` placeholder with the revision-9 commit), §5 (decision).
The revision-5/6/7/8 D039 drafts were never applied and are
**superseded** by this D039. If re-review requests further contract
changes, the writer amends `docs/CANVAS_CONTRACT.md` and
`tasks/r010/**` in the worktree and resubmits; shared docs stay
untouched until approval.
