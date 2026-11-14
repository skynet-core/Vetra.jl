# R010 — Freeze the frontend/backend contract (revision 9)

Status: **done, approved by coordinator and independent review**, 2026-11-14,
candidate `c81e15b`; integration verification is recorded in
[`docs/HANDOFF.md`](../../docs/HANDOFF.md#r010-revision-9-review-2026-11-14).
Both Julia versions pass 524 candidate, 103 coordinator and 271 independent
assertions. The full integration gate passes on Julia 1.13.3 (96.07% coverage,
gallery 79/79). Approval is contract-only (D039). The submission report below is
retained as historical writer evidence. Writer: Qwen3.8, branch
`canvas/frontend-contract`, worktree `/tmp/opencode/vetra-r010`.
Revision history: v1 = `d0d956f`; v2 = `9d66e97`; v3 = `870e8c7`;
v4 = `9998b87` + `bbfabe5`; v5 = `65d6f88`; v6 = `66b3ff7` (each
rejected by both reviewers); v7 = `7b1e8e4` (rejected by both
reviewers — three-group revision-8 assignment); v8 = `06046d0`
(**overall approval withheld** by both reviewers — the three v7
counterexamples are closed; two small corrections assigned); v9 = this
commit on top of v8 (no force-push, no push, no self-approval).

Dependencies: R000 (done), R040 (bounded Linux/NVIDIA probe approved,
D037), M003/M004 (done). This task freezes reviewed contracts; it
implements no production backend, adds no dependencies, runs no new GPU
probe and makes no device/browser-execution claim.

## Review input (v8 → v9)

- `/tmp/opencode/r010-v8-coordinator-review.md` — the consolidated
  **two-correction** revision-9 assignment, authoritative. Confirms
  the three v7 counterexamples are closed (coordinator probe: 69
  positive assertions/version — 26 preserved recording/completion
  boundaries, 27 staged-failure checks, 10 provider-reference checks,
  6 legacy-conversion checks/controls); candidate 508/508 on both
  Julia versions.
- `/tmp/opencode/r010-independent-review-v8/review.md` — independent
  report: **accepts the repaired partial / atomic-unwritten /
  BackendSubmitError staged-failure cases, the actual retained
  destination/source closure fields, the release of completed
  provider batches, pending/failed provider ownership, and the
  now-explicit internal action/owner metadata** ("accepted the
  internal owner/action explanation — do not rework it"); all 121
  preserved positives pass; the remaining finding is the §7 named
  phase-1 validation error that the restricted stored-error union
  cannot hold (ArgumentError → MethodError at the assignment, `:failed`
  stranded with `error === nothing`, later waits throw `nothing`);
  the coordinator separately owns the legacy-table acceptance hole.
  Per version: 190 positive + 15 counterexample/control assertions.
- Reviewer scratch probes (`/tmp/opencode/r010-v8-coordinator-probe.jl`,
  `/tmp/opencode/r010-independent-review-v8/probe.jl`) — v8 evidence
  only; **not edited**. The v8 counts are **not** cited as v9
  evidence. The independent probe's `CommitDest([7,7,7])` +
  `commit_or_report!(dest, [1,300,3])` composition is the v9
  distinguishing case (300 is the record helper's deliberate Int
  validation input — NOT a UInt8 production-buffer claim; upload
  pre-dispatch validation is unchanged).
- Re-read for v9: `src/paints.jl` `fillPath` (L924-927: opacity
  clamped, `paint.opacity == 0 ⇒ return nothing` — the zero-opacity
  Copy rejection basis, unchanged from v8), main at `cf73d4f` + the
  coordinator v8-review record (`64e887c`: TASKS.md R010 row
  "revision 9 in progress", HANDOFF, ROADMAP — consistent with this
  revision).

## Preserved approvals (do NOT reopen)

- v8 closures accepted by both reviewers: the staged-failure
  state machine (partial / atomic-unwritten / action error — the
  original error object preserved by identity on repeated direct
  wait, wait-all and close; host data stays partial or rolled back as
  reported; stores not repeated; BackendSubmitError from the staged
  action sticky; failed core staging retained while the
  already-completed provider batch is released); the 16-direct-wait
  drain of both tracking roots with every externally retained
  completed provider handle `batch === nothing`; pending/failed
  provider batches retaining their actual asset bytes; failed close
  not disposing them; the zero-opacity Copy conservative rejection
  (actual legacy replay still leaves blue; transparent color at unit
  opacity clears; existing legacy behavior unchanged).
- v7 approved boundaries (independent v7 report + coordinator
  closures), all intact: positional zero-based and shifted raw
  matrices in both scan orientations; the single raw shape authority;
  Float32 image opacity and the exact 16-byte widening control;
  supplied `initial.id` 41 with the separate next counter 42 through
  construction/resize; the exact inverse-DPI quotient and its
  register row; the upload-owned tracked handle and the inert no-op
  (the original group-4 correction); the earlier canonical bytes,
  saved-request validation, adapter exchange/allocation, matte,
  partial-write reporting, geometry and math.
- The recording scope reduction (narrow seal/remap/placement evidence,
  no replay visitor) and the internal action/owner representation
  explanation (doc §8.1: the concrete closure + root back-reference
  are core-internal, opaque to the provider) — accepted, not
  reworked.

## What v9 changes vs v8 (two corrections only)

1. **The final legacy accept row no longer omits unwrapped artistic
   draws.** The v8 final source-over accept row required a
   **non-artistic** paint, so an unclipped red Multiply fill at root
   (and a source-over artistic child inside an explicit group with
   `L == E`) matched **no** accept row — although the helper admits
   both (it rejects artistic only together with the implicit clip
   wrapper) and the actual-legacy control proves the unclipped direct
   draw preserving (Multiply over blue ⇒ black). The v9 row is
   adjusted so the **preceding** wrapped-artistic rejection governs:
   the accept row covers "unclipped, or with the implicit clip wrapper
   **only when non-artistic**, or inside a group with `L == E`", and
   names the artistic case (the legacy `Paint` carries the
   `blendMode`; the true backdrop is intact — reproduced). This is a
   table-consistency correction — **no helper change, no new
   converter capability, no restored wrapped-artistic conversion**
   (the wrapped-artistic rejection row is untouched).
2. **The stored-error domain holds §7's named phase-1 validation
   errors.** §7 applies the two-phase commit rule — phase-1 named
   validation error (`ArgumentError`) before any store, phase-2
   `TransferError` after — to every in-place output, **explicitly
   including staged borrow writeback at wait** (the §7 staged-borrow
   sentence and the single commit rule). The v8 staged catch accepted
   any exception but the `error` field was
   `Union{BackendSubmitError, TransferError, Nothing}`: storing the
   helper's `commit_or_report!(dest, [1, 300, 3])`
   `ArgumentError` raised a `MethodError` **after** `state` had
   become `:failed`, leaving `error === nothing` — every later
   wait/wait-all/close threw `nothing` (not success, but the original
   diagnostic was lost). The v9 field is **one sufficient
   stored-exception domain** (`error::Any` in the executable sketch;
   the doc names it the sticky failure — the **original named error,
   preserved by identity**: the provider's `BackendSubmitError`; the
   staged `TransferError` with its `:partial`/`:unwritten` status;
   the §7 phase-1 named validation error raised before any store) —
   not another growing union of individual exception classes, and no
   conversion that can strand `:failed` with no error. §7 (the staged
   failure paragraph and route (6)), §8.1 (the struct, the single
   route step (4), the close rule), G1 and G12 rows, and this record
   are aligned. The checker adds the narrow existing-helper
   composition: the original `ArgumentError` observed and re-thrown
   **by identity**, **zero stores**, the destination untouched, the
   action invoked **once**, the **same error** on all three routes
   (direct wait, wait-all, close), the core staging retained and the
   provider already released. No arbitrary public callback framework,
   no new retry/reset API, no production claim; upload pre-dispatch
   validation is unchanged.

## The 2 corrections → clause → §19 scenario → check → owner

| # | Issue (v8 reviews) | Normative clause (v9) | §19 scenario | Executed check | Downstream owner |
| --- | --- | --- | --- | --- | --- |
| 1 | The v8 final source-over accept row required non-artistic — an unwrapped Multiply at root and source-over artistic children in explicit groups (`L == E`) had no accept row, while the helper and the actual-legacy control accept them | §14 revision 9 (the final accept row now reads "unclipped, or with the implicit clip wrapper **only when non-artistic** … or inside a group with `L == E`" — the preceding wrapped-artistic reject governs; the artistic case named: the legacy `Paint` carries the `blendMode`, the true backdrop is intact; retraction list extended with the revision-8 final row) | G5 "canvas_picture(r) on the convertible subset" + "on non-representable ops" rows (updated) | ✓ record (helper unchanged — the unclipped-artistic and grouped-artistic admissions still pass, the wrapped-artistic rejection still raises) + ✓ math (the existing actual-recorder control — Multiply over blue ⇒ black — still pins the unwrapped case) | ⏳ R020 (adapter implementation + conformance) |
| 2 | The staged catch accepted any exception but `error::Union{BackendSubmitError, TransferError, Nothing}` cannot store §7's named phase-1 `ArgumentError` — storing it raised `MethodError` after `:failed`, stranding `error === nothing`; later wait/wait-all/close threw `nothing` | §8.1 revision 9 (the struct's `error` is **one sufficient stored-exception domain** — the original named error preserved by identity, no conversion; the single route step (4) names all three staged failure sources; the close rule and §7 staged-failure paragraph / route (6) aligned) | G1 "staged failure (`:partial` / `:unwritten` / action error / phase-1 validation) → repeated wait / wait(c) / close" row (extended) + G12 "staged upload → wait(upload's tracked frontend handle)" failure clause (extended) | ✓ tracker record: `commit_or_report!(CommitDest([7,7,7]), [1,300,3])` as the tracked staged action — the original `ArgumentError("…channel outside 0..255")` observed and re-thrown **by identity** on all three routes; destination untouched with **zero stores**; action invoked **once**; `staged_done` false; core staging retained; provider `:complete` with `batch === nothing` (already released); close stays open; the v8 partial / atomic-unwritten / action-error pins unchanged | ⏳ R021 (canvas lifecycle), ⏳ R022 (writeback runtime) |

## Executed boundary evidence (v9 checker)

`tasks/r010/boundary_check.jl` — **524 assertions** (the v8 file had
508: +16 — the phase-1 validation-error composition across the three
routes; the table correction is a doc-only wording change verified by
the existing helper/control checks), all marked ✓ rows of §19, on both
Julia versions (exact commands, run in `/tmp/opencode/vetra-r010`):

```
julia --startup-file=no --project=. tasks/r010/boundary_check.jl
julia +1.10 --startup-file=no --project=. tasks/r010/boundary_check.jl
git diff --check
```

- **Julia 1.13.3 (PATH default): 524/524 pass.**
- **Julia 1.10.13 (`julia +1.10`): 524/524 pass.**
- `git diff --check 06046d0..HEAD`: clean (no whitespace errors).

Coverage (testsets executed, labels matched to the actual checks): G1
protocol dispatch + the §8.1 revision-9 single completion route over
core-owned tracked frontend handles (field-less backend via the five
methods only; direct `wait(handle)` retires per frame and the provider
releases its batch root at completion — 16-frame drain leaves zero
core entries, zero provider-tracked handles, and zero batch
references reachable from an externally kept completed handle
(reference-checked, not flag-checked); wait-all through the same
route; **sticky provider failure** (failed handle keeps its batch,
close re-raises, provider never closed) and **sticky staged failure
with the original named error by identity** — partial (`[1,7,7]`,
stores unchanged after repeated waits), atomic (rollback to `[7,7,7]`),
action error (invoked exactly once), **and phase-1 validation
(ArgumentError preserved by identity on wait/wait-all/close, zero
stores, destination untouched)**; inert core no-op negative control;
the tracked §7 upload handle); G3 W3C compositing reference
(separable + vector nonseparable, burn/dodge backdrop exceptions,
overlay-vs-backdrop direction, artistic-before-additive); G5 §14
placement under the actual Vetra `Mat3` (origin/corner/ambient
anchors + rejected v4 order control) + the narrow
owned-CanvasRecording machine (seal group balance + the revision-7
seal boundary — asset-byte deep copies, op container ownership,
uncaptured-reference rejection in both id classes — + the one 1:1
remap + mapping/clip arithmetics with the single-mapping control; no
replay visitor) + the disjoint conservative legacy-lowering decision
procedure (revision 9 — zero-opacity Copy rejection; every reject
row raises the named `ArgumentError`; the accept rows admit, incl.
grouped Copy at nonzero opacity, clipped root source-over
non-artistic, **unwrapped source-over artistic**, draw-image
opacity) + the actual-recorder 1×1 wrapper counterexamples (clipped
Copy ⇒ blue left vs required clear; clipped Multiply ⇒ red vs
required black; zero-opacity Copy ⇒ blue left vs required clear;
unclipped controls ⇒ black / clear / transparent-color clear); §5.7
exact-rational hue anchor (independent of kernel output); G8 main
anchors + pinned kernels (rgbx/toStraightAlpha byte-exact,
Screen+Lighter ⇒ 117, matte 154, gray composite-first-then-luma); G9
readback identity vs the SAVED request (nine rejection classes,
saved-vs-current submission count, consume-once, context loss,
timeout retention); G10 browser document (`initial.id` preserved on
construction AND destructive resize — deliberately unequal 41/42;
separate already-reserved counter; future-id rejection;
empty-resize namespace continuity; captured-id insertion with
deliberately non-consecutive ids; consumer integrity check; canonical
byte accounting vs pinned fixtures; upload dispatch id; the §7
ordered upload route — `:submit` then `:upload`, tracked frontend
handle, retired on the single route; upload-only submission +
execution-ack; destructive resize; fresh-scope disposal); G11 the §7
table (raw-route positional axes through `axes(M)` — zero-based
`OffsetMatrix` imports in both scan orientations; top-level transpose
peel with orientation flip, adjoint rejection, index-array view
rejection, the narrowed `vec` advice + channel-packed scramble pin;
column-major positional import, declared scan orders, straight/gray/
float conversions, two-phase dest validation, truthful `:col`
reporting); G12 pre-dispatch upload validation (target untouched,
pending drawing untouched) + the §7 commit rule (`:partial` unless
atomic guarantee; failed commit leaves staging unreconciled) +
idempotent opaque staging + the staged-upload negative control (inert
no-op flush does not complete the upload; the tracked handle does —
writeback exactly once, idempotent); G13 storage-adapter surface
(zero-based regions, explicit alloc) + the normative consumer trace;
G14 the one input-size invariant (inverse DPI: the exact widened
quotient 9.999999602635718 pinned; 6 @ 0.6f0 rejected; the
literal-Float32 `Int(6 / 0.6f0) == 10` control; round-trip); G15 the
full wire records (10 tags, exact field sets — Float32 numeric
policy: `0.1f0 ⇒ 0.1` clear fixture AND the image-opacity `0.1f0 ⇒
0.1` pin; byte-Int gradient stops; fractional image srcRect and
effect regions — canonical serialization fixtures, fallback
embedding its original).

## Canonical schema fixture verification (pinned literals)

Independently derived (scratch work, then executed in the checker) —
all preserved unchanged from v8:

- 2×2 initial document = **357** bytes (exact canonical literal
  asserted, G10 — the captured id is 1 with the counter already at 2);
- 64×64 straight-RGBA8 initial: base64 `data` alone = **21848**
  bytes, full canonical document = **22187** bytes (G10);
- clip-free rect-fill record = **325** bytes (exact literal, G15);
- fractional clear record = **102** bytes (exact literal, G15);
- `0.1f0` clear record = **100** bytes (exact literal, G15 — the
  Float32 numeric policy: `0.1`, not the widened
  `0.10000000149011612`);
- 100-quote string ⇒ **202** bytes; `typemax(Int)` ⇒ **19** digits;
  `floatmax(Float32)` ⇒ `3.4028235e38` (**12** bytes) — all asserted.
- v7/v8 pins kept: the image record with `opacity = 0.1f0`
  serializes `"opacity":0.1`; the exact widened inverse-DPI quotient
  `9.999999602635718`; the pinned legacy pixels for the
  zero-opacity Copy reproduction (`UInt8[0,0,255,255]` /
  `UInt8[0,0,0,0]`).
- New (v9): no new canonical fixtures — the phase-1 validation
  composition is a state-machine check on the existing
  `CommitDest`/`commit_or_report!` helpers (destination
  `[7,7,7]` untouched, `stores == 0`).

## Evidence levels (distinguished, per the scope corrections)

- **Normative correction** — the v9 contract text resolving the two
  corrections (clauses cited in the mapping table). Pending
  coordinator + independent normative re-review; no approval is
  claimed.
- **Executed boundary evidence** — the 524 checker assertions above
  (arithmetic/record/dispatch only, **plus** the 1×1 actual-legacy
  pixel reproductions — the real `PictureRecorder`/`Picture`/
  `drawPicture`, imported as pinned primitives, not re-implemented).
  They prove the frozen *math and records*, not frontend/backend
  runtime behavior.
- **Preserved approval** — the v8 closures (staged-failure state
  machine, reference-checked provider release, zero-opacity Copy
  rejection) and the v7 approved boundaries (groups 5–8, the
  original group-4 correction, the recording scope reduction) are
  accepted and untouched; their evidence carries over.
- **Pending runtime task** — every ⏳ row: implementation +
  conformance proof in R011/R013/R020/R021/R022/R023/R032/R033/
  R045/R050/R053 (+ provider tasks). R010 approval does not make any
  of them ready-to-pass; readiness rows follow R010 approval per main
  HANDOFF.md.

## Remaining decisions (not resolved here)

- **GLSL ES route** (doc §11 shader-route record + §18.1): option (a)
  provider-owned GLSL ES 3.00 sources remains the explicit
  *proposal for review*, not an approved policy; coordinator must
  approve before R053/R055 kernels.
- **`SomePaint` export** (doc §3/§18.5): R021 exports the existing
  union `Paint | ColorRGB | ColorRGBA | ColorRGBX | String`.
- The doc's D037 false/`auto` policy and the E001 feature examples
  are preserved unchanged.

## Limits

- Contract-only: no frontend/backend runtime. The revision-9
  completion state machine (incl. the stored-error domain) and the
  reference-checked provider release are **records** of the frozen
  route on the checker's deferred provider spy — the real canvas
  lifecycle is ⏳ R021, the real staged writeback is ⏳ R022, the
  browser document machine is ⏳ R050/R053.
- `lowering_admit!` is a **decision procedure**, not an executed
  converter — it raises/admits but emits no `Picture`;
  `canvas_picture` itself is ⏳ R020. The v9 table correction is
  wording at the same boundary — the helper behavior and the
  wrapped-artistic rejection are unchanged.
- The stored-error domain is `Any` in the executable sketch so the
  original named error (any §7/§8 named failure) is preserved by
  identity without a conversion that can strand `:failed` with no
  error; the frozen public surface is the handle's `wait` behavior
  and the struct fields (the doc's `error::Any` names the three
  failure sources). This is not an arbitrary public callback
  framework — the staged action is core-owned, and no retry/reset
  API is introduced.
- The `300` fixture is the record helper's deliberate Int
  validation input (the `CommitDest` model stores `Vector{Int}`) —
  not a claim that a canonical `UInt8` provider buffer contains 300;
  upload pre-dispatch validation (invalid input fails before any
  provider call) is unchanged.
- No push, no self-approval: both reviewers must approve the v9
  candidate before the contract freezes.

## Next

Coordinator + independent normative re-review of the v9 candidate;
shared docs integrate per `PROPOSED_SHARED_EDITS.md` only on approval.
