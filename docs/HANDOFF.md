# Current handoff

## Latest request: Canvas architecture and parallel implementation plan

R000 is **done (approved 2026-11-10)**: `docs/CANVAS_DESIGN.md` and
`tasks/CANVAS_ROADMAP.md` define
renderer-independent Canvas, CPU/Vulkan.jl/browser/document execution, existing
codecs and Jupyter integration. Independent architecture/task-plan review has
passed; source review and final independent media consistency review are complete
with no blocking findings.
Coordinator owns these documents. Qwen's bounded M003 implementation in
`modernization/native-api` is now approved and integrated. On 2026-11-11 the user
requested implementation start; M004 is now independently approved and integrated,
and R040's bounded Linux/NVIDIA probe is now approved and integrated (D037).
E001 feature examples are independently approved and integrated (D038, below).
Future backend streams are gated by
R010's contract review. Final milestone task R099 publishes the real interactive
tutorial via GitHub Pages CI; R098 prepares the illustrated README.

User additions incorporated into the plan: GIF/WebP/MP4 existing-frame editing,
decode/encode/record/concatenate (R064–R069), and Matrix/Vector/StaticArray storage
independent of CPU/GPU execution (R022/R023). Array contracts cover copy/borrow,
views/layout/alpha, explicit GPU→host snapshot, immutable static output versus
mutable targets, and explicit processor changes. Media contracts cover composed
frames, timing/loops, selection/seeking, re-encoding, original-file preservation
and explicit handling of unsupported audio tracks.

Further user direction: SOLID and zero-core-change extension are explicit public
protocol requirements (§3.7), with R013 external-package conformance. Future GUI/
plotting-core adoption is specified in §3.8 and verified by R014 external consumer
prototypes. Contracts include headless text/bounds queries, host event-loop and
surface ownership, reusable recordings, conservative invalidation and high-range
world→local mapping before Float32 narrowing. There are now 43 task specs.

Media research was steered to include existing-frame editing. Independent plan
re-review returned **approved** after confirming every correction and independently
checking all 43 specs/98 edges. Coordinator applied findings 1–10: R013 writer dependency, explicit `(canvas, i, t, dt)`
recording callback, optional StaticArrays checks, CPU array-target invariants,
R070 drawn-GPU dependency, non-vacuous media CI status, connected-browser capture
ownership, a pinned PNGFiles consumer test, importable companion test support and
Q's integration-consumer paths. The remaining non-blocking R070 media-view note
now explicitly uses a pinned prerecorded fixture, with engine-generated media
integration in R099 after R069; it adds no premature encoder dependency.
Approval covers architecture/task documents only, not providers or execution.
Next: review the active R010 contract draft using the approved
bounded Vulkan constraints. M003/M004 and the Windows allocation-gate follow-up
are approved with passing four-platform CI (evidence below). Other-platform GPU
runtime acceptance remains open; R040 does not establish a production backend.
R099 remains the final task.

### New request: close verification gaps and build GPU/WebGL showcases

2026-11-12: user asks how to help resolve Jupyter/PyMuPDF verification gaps and
requests GPU-enabled projects and a browser WebGL showcase. Coordinator treats
this as runnable Vetra projects: native Vulkan plus a distinct **WebGL2**
provider, not Canvas2D relabeled as GPU. `docs/CANVAS_DESIGN.md` and R053–R055
in `tasks/CANVAS_ROADMAP.md` define the added scope. Shared E001 scenes become
interactive atlas/dashboard/image-effects projects with provider/timing display,
pan/zoom, resize, pause and export. Local execution precedes R099 publication.
Hardware, software and unknown WebGL execution must be reported distinctly;
the browser GLSL ES shader-authoring/lowering route requires a reviewed decision
against Julia algorithm ownership before kernel implementation.

The amended roadmap independently checks **46 matching specs / 110 edges**,
acyclic with every task leading to R099. Native GPU remains Vulkan.jl; no 3D.

- **R010 assigned:** Qwen3.8 in `/tmp/opencode/vetra-r010`, branch
  `canvas/frontend-contract`, base `b631410`; owns `docs/CANVAS_CONTRACT.md`
  and isolated supporting sketches/checks under `tasks/r010/`. Coordinator owns
  shared design/status integration. Draft must cover the new WebGL2 provider
  alongside CPU/Vulkan/Canvas2D/PDF; no production dummy backends.
- **V001 verification assigned:** Qwen3.8 in `/tmp/opencode/vetra-v001/`,
  main repository read-only. Isolated Python environment for PyMuPDF/Jupyter,
  isolated Julia IJulia/PNG environment; execute a real notebook kernel, verify
  its image MIME output and target actual VS Code notebook display. JupyterLab
  execution is supplemental evidence rather than VS Code proof. Run the
  previously skipped `VETRA_MUPDF_PY` JPEG interoperability leg and independently
  render asymmetric PDFs with PyMuPDF. Return exact commands, versions, outputs
  and any concrete frontend blocker. No global installs or root dependencies.

User confirmed the acceptance target: **VS Code notebooks; Chromium on Linux;
NVIDIA RTX 3090**. Both writers received this direction. Current agent-host
`nvidia-smi --query-gpu=name,driver_version --format=csv,noheader` reports
**RTX 3050 Ti Laptop GPU, driver 615.71.09**; those results cannot establish
RTX 3090 execution. `/snap/bin/code` is available, but actual VS Code UI/kernel
validation remains V001's task; preserve the user's existing profile/settings.
Provide a ready notebook and exact kernel-selection steps if the target UI
requires a user-run check. GPU/backend acceptance on the RTX 3090 will require
an actual run there; browser hardware acceleration must also be checked.

E001 push `b631410` passed **all 10 CI jobs** at
[run 43288151394](https://github.com/skynet-core/Vetra.jl/actions/runs/43288151394):
Linux/Windows/macOS/FreeBSD tests and four non-expired benchmark artifacts.
This CPU CI evidence does not establish GPU/WebGL runtime support.

#### R010 revision 6 review (2026-11-14)

Candidate `66b3ff7` is **rejected by both reviewers**.
Candidate worktree was clean at submission; no candidate is integrated. Explicit
CanvasRecording capture/replay signatures replace the opaque-submission capture
promise. The boundary checker grew from 2,833 to 3,358 lines.

Coordinator reran from `/tmp/opencode/vetra-r010`:

```sh
julia --startup-file=no --project=. tasks/r010/boundary_check.jl
julia +1.10 --startup-file=no --project=. tasks/r010/boundary_check.jl
julia --startup-file=no --project=. /tmp/opencode/r010-v6-coordinator-probe.jl
julia +1.10 --startup-file=no --project=. /tmp/opencode/r010-v6-coordinator-probe.jl
git diff --check 65d6f88..66b3ff7
```

Both Julia versions pass **389/389** candidate checks and **20 positive + 14
counterexample/control assertions** in the coordinator probe. Whitespace passes.
Math/placement, image-draw ID remapping, asset-byte copying, group balancing,
clipped Copy rejection and wait-all core-root retirement have positive evidence.
Remaining findings:

- The new replay helper fails on clears and nonempty clips, and leaves image-paint
  IDs unchanged. Seal ownership checks cover asset bytes but not aliased paths;
  full replay evidence claims are too broad. Target ambient-clip replay semantics
  also need to be explicit.
- The legacy adapter still accepts clipped artistic Multiply: the actual legacy
  recorder produces red over blue where the normalized rule requires black.
  Its accept/reject table has overlapping rules.
- Direct `wait(handle)` does not notify core retirement; repeated direct waits
  leave completed handles tracked. The spy provider retains batches/assets even
  after successful close, while its test checks only the emptied core vector.

Independent review passes **89 positive assertions (46 preserved + 43 new) + 17
counterexample/control assertions** per version. Coordinator reran the final
probe successfully on Julia 1.13.3 and 1.10.13:

```sh
julia --startup-file=no --project=/tmp/opencode/vetra-r010 /tmp/opencode/r010-independent-review-v6/probe.jl
julia +1.10 --startup-file=no --project=/tmp/opencode/vetra-r010 /tmp/opencode/r010-independent-review-v6/probe.jl
```

The review records earlier probe development: image opacity failed an expected
positive assertion and became a confirmed counterexample; a scratch-only no-op
wait assumption was corrected to inspect the no-op record under the documented
inert-wait rule. No candidate checks or expectations were changed by reviewers.

Verified closures include commit prose, fractional source/effect geometry,
inverse-DPI policy, offset raw vectors/views and most numeric mappings. Remaining
independent corrections:

- G12 still promises staged upload completion through an empty drawing flush;
  use the upload's tracked frontend handle or wait(canvas), keeping no-op inert.
- Raw snapshot shape clauses conflict; zero-based raw matrices still fail in
  both scan orientations despite working offset-vector and element-matrix cases.
- Image opacity still widens Float32, adding 16 canonical bytes for 0.1f0.
- Resize-with-initial replaces the captured asset's ID with the next counter.
- The inverse-DPI approximation is wrong and its claimed G14 scenario is absent.

Consolidated packet: `/tmp/opencode/r010-v6-coordinator-review.md`, **eight groups**,
assigned to a fresh Qwen3.8 context for revision 7 in the same owned worktree.
Prefer narrow recording/reference/placement checks to the expanded replay visitor;
keep its scenarios pending with their owners. Freeze one tracked frontend completion
route for direct waits, wait(canvas) and staged uploads. Both reviews must approve
before freeze/merge; production frontend/backend execution remains downstream.

#### R010 revision 5 review (2026-11-14)

Qwen submitted `65d6f88` after two interrupted writer runs; candidate worktree
was clean at submission. **Rejected by both reviewers.** No candidate is
integrated. The boundary checker is now 2,833 lines.

Coordinator reran, from `/tmp/opencode/vetra-r010`:

```sh
julia --startup-file=no --project=. tasks/r010/boundary_check.jl
julia +1.10 --startup-file=no --project=. tasks/r010/boundary_check.jl
julia --startup-file=no --project=. /tmp/opencode/r010-v5-coordinator-probe.jl
julia +1.10 --startup-file=no --project=. /tmp/opencode/r010-v5-coordinator-probe.jl
git diff --check bbfabe5..65d6f88
```

Checker **336/336** and coordinator **16 positive math/placement assertions +
14 counterexample/control assertions** pass on Julia 1.13.3 and 1.10.13;
whitespace check passes. Placement, burn/dodge endpoints and artistic-before-
Lighter math corrections are independently confirmed. The hue value remains
correct, although its written derivation has a 7/100 versus 7/10 typo.

Remaining coordinator findings:

- Lossless capture is defined as `flush!` plus batch accessors, but `flush!`
  returns an opaque submission with no public batch retrieval. New-feature
  recording/replay with frontend placement remains unspecified.
- Reusing legacy clip wrappers with Copy→OverwriteBlend changes pixels: the
  actual legacy recorder leaves blue where a clipped transparent Copy must clear.
- Completed submission retirement is unspecified; the checker retains all
  completed handles/batches even after successful close, contradicting bounded
  lifetime claims. Keep pending/failed handles without retaining successful history.

Independent review verifies **46 positive assertions + 15 counterexample/control
assertions** per version. Coordinator reran both commands successfully:

```sh
julia --startup-file=no --project=/tmp/opencode/vetra-r010 /tmp/opencode/r010-independent-review-v5/probe.jl
julia +1.10 --startup-file=no --project=/tmp/opencode/vetra-r010 /tmp/opencode/r010-independent-review-v5/probe.jl
```

Canonical adapter exchange/allocation and saved-request payload validation are
closed at the contract/boundary level. Actual base64 accounting, matte conversion,
partial-store reporting and forward DPI arithmetic improve. Remaining findings:

- Valid uploads lack explicit ordering after pending drawing, and upload-only
  work is not fully connected to admission, ACKs, tracking and staged completion.
- Blanket `vec(Matrix)` advice scrambles channel-packed raw arrays; shape clauses
  conflict and raw helpers do not consistently honor axes/view policies.
- A failed-commit paragraph still promises unchanged host storage. Canonical
  wire numbers lack a uniform type/promotion policy, changing exact byte lengths.
- Document helpers replace core asset IDs with local IDs and reset them on resize.
  Fractional image source/effect geometry rules conflict with integer mapping.
  Inverse DPI division lacks the Float64 promotion already used by its helper.

Consolidated packet: `/tmp/opencode/r010-v5-coordinator-review.md`, **11 groups**,
assigned to Qwen for revision 6 in the same owned worktree. Require a usable owned
normalized recording contract independent of opaque submission handles, explicit
legacy conversion limits, completed-handle retirement, and consistent ordered
upload/array/wire/DPI clauses. Correct existing narrow helpers and scenario traces;
runtime frontend/backend implementation stays downstream. Both reviewers must
approve before freeze or merge.

#### R010 revision 4 review (2026-11-13)

Candidate `9998b87` plus SHA-record follow-up `bbfabe5` is **rejected by both
reviewers**. No candidate is merged. The duplicate 4,660-line frontend is deleted;
a 1,942-line checker
now labels arithmetic/record/dispatch evidence separately from pending runtime
acceptance. Group entry alpha and all-submission tracking rules improve.

Coordinator reran `tasks/r010/boundary_check.jl` from `/tmp/opencode/vetra-r010`
with `julia --startup-file=no --project=.` and `julia +1.10 --startup-file=no
--project=.`: **213/213** pass on Julia 1.13.3 and 1.10.13. The separate
`/tmp/opencode/r010-v4-coordinator-probe.jl` passes **4 positive arithmetic** and
**11 defect/control assertions** per version. Exact rational derivation confirms
the disputed hue `(87,0,64,192)` anchor independently of Vetra's output.

Remaining coordinator blockers: unchanged legacy PicOp records cannot represent
the promised full-Canvas recording conversion (group composition, effects, image
sampling and dash phase); the normative placement matrix scales translation;
the checker has incorrect burn/dodge endpoints and bypasses artistic blending
for Lighter. Small signature/sketch contradictions also remain. The corrected
group/ownership rules and retired mock are contract progress, not runtime proof.
Independent review passes **18 positive boundary assertions + 25
counterexample/control assertions** per version. Coordinator independently reran:

```sh
julia --startup-file=no --project=/tmp/opencode/vetra-r010 /tmp/opencode/r010-independent-review-v4/probe.jl
julia +1.10 --startup-file=no --project=/tmp/opencode/vetra-r010 /tmp/opencode/r010-independent-review-v4/probe.jl
```

Both commands pass with those counts on Julia 1.13.3 and 1.10.13. Remaining
independent blockers are normative/interface defects, not missing runtime code:

- Public upload dispatch omits the core-assigned asset identity; wire submission
  and execution-ACK records are missing. Serialized byte accounting undercounts
  base64, escaping and numeric fields: a 64×64 import counts 16,816 units while
  its base64 data alone occupies 21,848 bytes.
- Adapter output clauses disagree on canonical premultiplied versus converted
  data; allocation lacks explicit type/dimensions and a consistent public filling
  route. Direct method calls do not prove consumer integration.
- Array layout/alpha clauses conflict, transparent grayscale ignores matte,
  and owned staging incorrectly promises atomic indexed writeback. Validation
  failures leave targets unchanged; actual commit failures may be partial.
- DPI byte counts, multiplication precision and the optional resize signature
  disagree. Response checks accept invalid encoding/dimensions/data and compare
  submission identity against mutable completion state rather than the saved
  request. Fractional clear, gradient, text and stroke wire mappings need correction.

Consolidated packet: `/tmp/opencode/r010-v4-coordinator-review.md`, **12 correction
groups**, assigned to a fresh Qwen3.8 writer context for revision 5 in the same
worktree and owned paths. Require one authoritative definition per boundary;
remove contradictory duplicate clauses instead of appending another correction
layer. Preserve the contract-only scope, verified improvements and every scenario's
downstream acceptance owner. Both reviewers must approve before freeze or merge.

#### R010 revision 3 review (2026-11-13)

Candidate `870e8c7` is **rejected by both reviewers**.
Neither it nor its rejected predecessors is integrated. The model
imports actual Vetra primitives but grew again, from 3,787 to **4,660 lines**.
Coordinator independently reran `tasks/r010/check_contract_model.jl` in
`/tmp/opencode/vetra-r010` with `julia --startup-file=no --project=.` and
`julia +1.10 --startup-file=no --project=.`: **444/444** pass on both versions.

With those same commands, `/tmp/opencode/r010-v3-coordinator-probe.jl` verifies
**8 positive assertions** (same-batch image captures, saved image/Copy styles,
coverage/destination-atop/additive anchors) and **23 defect-confirming assertions**
on Julia 1.13.3 and 1.10.13. Initial scratch assertions were corrected to the
actual Hue/Saturation exception type before successful reruns. Remaining issues:

- Explicit flush followed by wait(canvas)/snapshot does not wait prior work;
  close forgets all but the latest submission. New drawing can overwrite a
  failed handle and let close succeed.
- The contract now explicitly endorses the rejected 0.25 group-opacity result
  instead of fixing it. Group composition bypasses capability preflight, and
  invalid image style leaves a partially entered group.
- Nonseparable artistic modes fail in the composed pipeline. Raster fallback
  discards original operation data for zero-filled placeholders and breaks
  balanced group restore.
- Picture capture drops assets; replay loses destination translation. Asset
  storage retains every copied capture even after completion/close.
- The duplicate frontend remains expanded; proposed edits wrongly describe
  main's R010 row as ready/missing. Some asset-version prose contradicts the new
  fresh-ID rule. The claim that every prior counterexample is closed is rejected.

Independent review additionally verifies **22 positive closure assertions** and
**34 defect-confirming assertions** on each Julia version. Coordinator reran:

```sh
julia --startup-file=no --project=/tmp/opencode/vetra-r010 /tmp/opencode/r010-independent-review-v3/probe.jl
julia +1.10 --startup-file=no --project=/tmp/opencode/vetra-r010 /tmp/opencode/r010-independent-review-v3/probe.jl
```

Both pass with those exact counts. Genuine raw-matrix/gray/vector imports,
some typed/public readback routes, external import/borrow dispatch, element-array
DPI and public resize improve; D037 `false`/`auto` packaging prose is corrected.
Remaining independent blockers:

- Browser snapshots reuse stale ACKs after context loss or without fresh
  responses; submission wait needs no execution acknowledgment. Draw/upload IDs
  collide, geometry/initial content bypass retention limits, resize keeps stale
  recovery content, and disposal retains submissions/assets. The wire section
  still lacks concrete command and transport-message records.
- Array routes disagree on vector scan order, ordered offset axes, destination
  shape, straight/premultiplied conversion and float/gray output. Ordinary Julia
  matrices are incorrectly described as row-major.
- Invalid uploads partly mutate targets; upload completion omits staged writeback;
  raw UInt8 views receive 1 instead of 255; repeated opaque writeback compounds
  red 128→192. External adapter output/allocation consumers are still missing.
- Raw/adapter high-DPI constructors discard validated logical sizes and bind
  storage smaller than the declared physical target.

Consolidated packet: `/tmp/opencode/r010-v3-coordinator-review.md`, **15 groups**,
assigned to Qwen for revision 4. **Scope correction:** the coordinator's prior
request for every mock failure to become an executable frontend acceptance case
encouraged duplicate implementation beyond R010. Retire that mock; freeze precise
semantics, records, public dispatch and scenario tables, with a small checker for
actual numeric/record/dispatch boundaries. Keep shared-scene/extension sketches
explicitly labeled; runtime acceptance belongs to R020/R021/R022/R013 and the
backend tasks. Deleting a mock is not a runtime fix and cannot close its scenario.
The group correction explicitly freezes entry alpha/composition on the group,
starts child alpha at 1/composition at SourceOver, and restores parent state.
The alpha-0.5 single-child case must have net alpha 0.5.

Preserve all independently verified improvements. Both reviewers must trace and
approve the corrected normative contract; no downstream implementation is approved.

#### R010 revision 2 review (2026-11-13)

Qwen submitted `9d66e97` on `canvas/frontend-contract`, on top of rejected
`d0d956f`. **Rejected by coordinator and independent reviewer.**
Neither candidate is integrated. The four-file candidate contains a 3,787-line
model, up from 1,522 lines despite the requested reduction.

Coordinator independently ran, from `/tmp/opencode/vetra-r010`, both
`julia --startup-file=no --project=. tasks/r010/check_contract_model.jl` and
`julia +1.10 --startup-file=no --project=. tasks/r010/check_contract_model.jl`:
**801/801** pass on Julia 1.13.3 and 1.10.13. Running
`/tmp/opencode/r010-v2-coordinator-counterexamples.jl` with the same two Julia
commands confirms defects with **20 assertions per version**:

- Drawing an image, mutating it, and drawing again before one flush loses the
  first capture: both commands resolve the latest asset version.
- Saving an image paint then restoring raises `KeyError`; saved OverwriteBlend
  loses its Copy composition override. Layer-entry alpha 0.5 becomes 0.25
  because both child and group carry it.
- Half-covered opaque red becomes `(64,0,0,128)` instead of `(128,0,0,128)`;
  destination-atop uses the wrong output alpha; additive blending sums straight
  RGB rather than premultiplied contributions.
- Failed completion is forgotten on repeated wait. Retrying failed close can
  close successfully with zero executed operations and no pending work.
- An external provider implementing all five documented required methods fails
  on private backend-field access. Failed image preflight also mutates capture
  state. The model's redefined matrix translation disagrees with actual Vetra.

Independent v2 review confirms additional blockers:

- The normative browser wire/recovery section was removed, while the inventory
  and task record still claim it exists. Session-only ACKs authorize later
  snapshots without matching completion, survive context loss, and accept future
  sessions. Explicit uploads are absent from recovery data; retained drawing is
  unbounded and closed sessions remain globally rooted.
- Storage-adapter methods are disconnected from Canvas construction/writeback.
  Raw initial pixels bypass public target binding. Typed Matrix/Vector snapshots
  return Image, raw output lacks a layout keyword, array upload is missing, and
  snapshot! bypasses public GPU/browser readback.
- Genuine nonsquare raw matrices, grayscale vectors, pixel vectors and correctly
  shaped destinations fail. The claimed raw-matrix fixture was a vector; staged
  view writeback does not occur. High-DPI array input allocates inconsistent byte
  storage, and resize bypasses the public provider method with no scale update.
- D037 packaging is mostly corrected, but `auto` precompilation is not device-free:
  it runs the device workload and catches unavailable-driver failure. Only `false`
  skips it (approved probe README, p50 evidence).

Independent probe commands, also rerun successfully by the coordinator:

```sh
julia --startup-file=no /tmp/opencode/r010-independent-review-v2/probe.jl
julia +1.10 --startup-file=no /tmp/opencode/r010-independent-review-v2/probe.jl
```

Both pass **27 defect-confirming assertions** (Julia 1.13.3 and 1.10.13).
These and the coordinator's 20 assertions are negative evidence, not acceptance.
The independent review closes the earlier conversion/matte/partial-transfer
rules at the stated-rule level and confirms the corrected ready wave; actual
adapter routes remain broken. Physical rounding and most package constraints
are corrected; browser recovery, storage integration and DPI transitions are not.

Consolidated packet: `/tmp/opencode/r010-v2-coordinator-review.md`, **15 correction
groups**, returned to the same Qwen writer for revision 3 in the existing owned
worktree. Require a substantially smaller contract proof using actual Vetra
primitives, public-only provider/adapter dispatch and independent positive checks
for each counterexample. Moving the duplicate frontend into more files or deleting
difficult cases does not satisfy the reduction. No production implementation is
assigned here. Both reviews must approve the next candidate before freeze;
passing model counts are not semantic acceptance evidence.

#### R010 first contract review (2026-11-13)

Qwen submitted `d0d956f` on `canvas/frontend-contract` (four new files, no
production changes). **Not approved or integrated.** Coordinator independently
reran `tasks/r010/check_contract_model.jl` in `/tmp/opencode/vetra-r010` with
`julia --startup-file=no --project=.` and `julia +1.10 --startup-file=no --project=.`:
**91/91 pass on Julia 1.13.3 and 1.10.13**. These checks do not establish that the
contract is complete or internally consistent.

Coordinator counterexamples in `/tmp/opencode/r010-coord-counterexamples.jl`
reproduce defects with **19 assertions on each Julia version** (asserting the
observed defects, not acceptance):

- Ordinary fill/clear commands have no clip snapshot. The model emits an opaque
  fill even at global alpha zero; mutable paints also change sealed commands
  and saved state after the fact. The required ownership/state boundary is absent.
- Strict preflight accepts fallback-level capabilities and ignores unsupported
  stroke blends; failed layer preflight leaves modified saved state.
- The PDF model loses pages without manual flush and creates extra pages on
  repeated flush. Closing a canvas silently leaves buffered drawing unsubmitted.
- Asset IDs/versions restart after every flush, giving different images identical
  advertised cache keys on the same device.

Contract-level blockers also include narrowing required painted strokes/tiled
paints/Porter–Duff composition to legacy gaps instead of freezing their semantics;
missing target-binding and physical-size/resize rules; and incomplete public
extension seams. The approved R032 task explicitly consumes R010's Porter–Duff
coefficient table. Deferring that table while calling v1 frozen is not acceptable.

The required independent reviewer also **blocked approval**, corroborating the
command/ownership/preflight failures and identifying:

- WebGL restoration from only the last incremental batch loses previous drawing;
  retaining recovery data only in Julia cannot restore standalone offline HTML.
- No public custom pixel-storage adapter seam; explicit raw Matrix channels,
  allocating Vector snapshots and array upload routes are missing.
- `UInt8(N0f8(0.5))` throws, while `UInt8(N0f8(1.0))` is 1 rather than the
  required byte 255. The draft's quantization formula is incorrect.
- A default black matte contradicts explicitly selected transparent-to-opaque
  conversion. Generic staged array writes cannot promise atomic commit after a
  later `setindex!` fails; report partial transfer truthfully.
- Physical sizing/rounding, resize/DPI transitions and the D037-informed optional
  package/compatibility boundary are not frozen sufficiently for implementers.

Independent probe `/tmp/opencode/r010-independent-review/probe.jl` confirms
defects with **16/16 assertions on Julia 1.13.3**, also rerun successfully by
the coordinator. Both probes are negative evidence, not acceptance suites.
Full correction packet: `/tmp/opencode/r010-coordinator-review.md` (**13 items**,
11 must-fix contract groups plus model/evidence and readiness corrections).
Returned to Qwen in the same owned worktree for a bounded correction commit;
shared documents and production code remain coordinator-owned. The next
candidate requires coordinator and independent re-review before approval.
The submitted model's large duplicate frontend and placeholder readbacks are
not a production skeleton. Shader authoring remains an explicit proposed
decision before R053 kernels, not an approved policy exception.

After R010 approval, **R011/R012/R020/R064/R080** become dependency-ready (M004
already complete); R021, R053, R061 and R063 retain their additional dependencies.
This corrects the coordinator's initial three-task list, which omitted R064 and
R080. No downstream task is authorized by this rejected draft.

#### V001 independent verification (2026-11-12)

Coordinator independently executed the existing notebook through a real IJulia
kernel using nbclient 0.11.0 / Julia 1.13.3. Added five failing-on-error Julia
assertions for PNG MIME byte identity, source preservation and three specified
premultiplied pixels. Pillow 13.0.0 decoded all three output PNGs: **14/14**
hand-derived pixel assertions passed (two 4×4 outputs and one 340×110 composite).
Executed evidence: `/tmp/opencode/v001-coord-notebook/executed.ipynb`, kernel
`vetrav001-1.13`, discovered with
`JUPYTER_DATA_DIR=/tmp/opencode/vetra-v001/jupyter-data`. Writer's JupyterLab
Chromium screenshot was visually reviewed; this is not VS Code frontend proof.

Previously skipped external JPEG leg now independently passes **61/61**:

```sh
VETRA_MUPDF_PY=/tmp/opencode/vetra-v001/pyvenv/bin/python \
  julia --startup-file=no --project=/tmp/opencode/vetra-v001/julia_env \
  -e 'using Test, Vetra; include("test/jpeg_encode_tests.jl")'
```

Log: `/tmp/opencode/v001-coord-jpeg.log`; Python 3.14.4, PyMuPDF 2.1.
Coordinator also rendered the E001 strict/fallback/rotated PDFs at 96 dpi with
PyMuPDF: **7/7** independent color/orientation samples each, plus **4/4** opaque
gallery-placement samples. The rotated sample expectations were already correct:
red `(24,8)`, green `(24,16)`, blue `(16,8)`, yellow `(16,16)`, magenta `(8,8)`,
cyan `(8,16)`. The writer's alleged stale handbook table did not exist; that
conclusion was rejected. Gallery partial-alpha sample `(11,25)` is `(226,226,226)`
versus Poppler/Chromium `(227,227,227)`. This difference is recorded; its rounding
cause has not been independently source-traced and no tolerance was changed.

VS Code UI execution remains **unverified**. The writer's inferred account/
tunnel requirement was rejected: the actual `bin/code-tunnel serve-web` entry
point starts a loopback server with a generated connection token without an
account. A bounded coordinator HTTP probe reached its server-download response;
it did not execute a notebook UI. Scratch data is in
`/tmp/opencode/v001-coord-code/`; processes were terminated after the probes.
The user's VS Code profile/settings were not modified. Portable notebook and
minimal VS Code setup instructions are assigned to Qwen in separate worktree
`/tmp/opencode/vetra-v001-notebook`, branch `examples/vscode-notebook`;
writer candidates `3baa0c3` / `52d4945` were reviewed and integrated through
`1c88768`. The notebook uses `pkgdir(Vetra)` and public `take!` byte extraction,
requires no font fixtures, and is committed without outputs. Its README uses an
isolated ignored environment and officially documented VS Code kernel-selection
steps, including an optional local-server token URL.

Coordinator rebuilt a minimal Vetra/IJulia/PNGFiles environment from the setup
instructions (only the scratch environment/data paths differ) and executed the
integrated notebook via nbclient: **11 notebook assertions**, **two PNG outputs**
and **9/9 independent Pillow pixels** pass; source bytes remain unchanged.
Exact rerun:

```sh
JUPYTER_DATA_DIR=/tmp/opencode/v001-coord-portable/jupyter-data \
  /tmp/opencode/vetra-v001/pyvenv/bin/python \
  /tmp/opencode/v001-coord-portable/verify.py
```

Evidence: `/tmp/opencode/v001-coord-portable/executed.ipynb`; Julia 1.13.3.
Separately, all notebook code cells and **11 assertions** passed with
`julia +1.10 --startup-file=no --project=/tmp/opencode/v001-coord-portable/env110`
using only Vetra/PNGFiles; that check is cell compatibility, not an IJulia 1.10
frontend run. No VS Code UI or RTX 3090 execution is claimed.

The required `julia --startup-file=no --project=. scripts/check.jl` initially
stopped before testing in main: its pre-existing ignored Manifest lacks the
direct LinearAlgebra dependency. Log: `/tmp/opencode/v001-coord-gate.log`.
The local Manifest was preserved; the same command **passed** in clean detached
worktree `/tmp/opencode/vetra-v001-coord-gate` at `1c88768`, with pinned reference
inputs shared read-only: **96.07% (7805/8124)** source coverage and gallery
**79/79**. Log: `/tmp/opencode/v001-coord-clean-gate.log`.
V001's portable delivery and kernel/external-reader evidence are approved;
`git diff --check` passes. No runtime library changes were needed.
R010 continues independently; VS Code user-side display acceptance stays open.

### Latest user request: review and executable feature programs (2026-11-12)

User requested review/improvements and Qwen3.8 implementation of examples that
exercise the full library across backends/renderers, with fixes for bugs exposed
while building them. Scope and acceptance: `tasks/EXAMPLES_PLAN.md`.
E001 was assigned to Qwen in `/tmp/opencode/vetra-feature-gallery`, branch
`examples/feature-gallery`, base `7a54ea9`; owns `examples/gallery/`, related
example instructions, `test/gallery_examples_tests.jl` and its explicit runner
include. Connected reproduced library bugs may be fixed in separate commits;
shared contracts, dependencies and status documents remain coordinator-owned.

Six programs: drawing atlas, plotting dashboard, typography, image lab,
recording reuse and strict/fallback export policies. Current real targets are
CPU drawing/replay, SVG and PDF; the image lab also demonstrates existing PNG
MIME display. The same programs are extended by the planned Canvas providers
and the media editor when their roadmap dependencies are implemented. R099
publication stays last. Every runnable example requires semantic assertions,
real outputs, honest provider requirements and source-preserving I/O.

#### E001 approval (2026-11-12)

**Approved and integrated through `254be96`**, final writer `873939f`.
All six programs are executable under `examples/gallery/`; current targets are
CPU direct/replay, SVG, PDF and optional codec/MIME paths. D038 records the
BMP straight-alpha/header correction, lossless PDF decimal serialization and
strict/fallback image-orientation correction found during independent rendering.

Final required checks (identical integration source, isolated worktrees):

- `/tmp/opencode/vetra-e001-integration`:
  `julia +1.10 --startup-file=no --project=. scripts/check.jl` — passed,
  **96.11% (7907/8227)**, gallery **79/79**.
- `/tmp/opencode/vetra-e001-coord-final113`:
  `julia --startup-file=no --project=. scripts/check.jl` — Julia 1.13.3 passed,
  **96.07% (7805/8124)**, gallery **79/79**.
- Logs: `/tmp/opencode/e001-coord-orientation-gate{110,113}.log`.
- Independent PDF numeric probes: **24,014 checks/version**; BMP boundary:
  **65,536 pixel combinations**, independent integer decode expectations and
  Pillow encode verification against the unchanged alpha oracle.
- All six optional-provider and core-only CLI runs passed, with explicit
  six-provider absence preflight. Poppler rendered all twelve documents;
  the final CTM fix additionally passed asymmetric strict/fallback/rotation
  checks and five gallery color/alpha samples. Five SVG scenes rendered in
  Chromium; the fallback passed the same five expected samples.

Main now contains exactly the reviewed implementation. Coordinator additionally
updated compatibility, decision, recording-contract and status documentation;
`git diff --check` passes. Integration was pushed as `b631410`; all ten remote
CI jobs passed (run and artifacts above).
At E001 approval, live Jupyter execution was not performed and PyMuPDF
interoperability was skipped; V001's later independent checks above close those
kernel/reader gaps, with VS Code UI still unverified. Existing
dash-cap/scaled-gradient renderer differences are documented. Future GPU,
browser Canvas2D and media extensions retain their roadmap dependencies; R099
publication remains last. R010 contract work is active.

#### E001 review history: first candidate (2026-11-12)

Candidate `bde2e75` (preceded by BMP `51760ee` and number formatting `6bf893c`)
was **rejected**. The same Qwen writer corrected these findings:

- **BMP external alpha boundary:** independent Pillow 12.1.1 decodes the
  candidate's encoded premultiplied red `(128,0,0,128)` as straight
  `(128,0,0,128)`, rather than `(255,0,0,128)`. The 124-byte header correction
  is justified; storing premultiplied file bytes to match the existing decoder
  is not. Correct encoder and decoder boundaries with independent byte fixtures;
  preserve pinned oracle provenance and explain justified divergence.
- **Numeric serialization:** `_pdfNum(1f-20)` and `_n(1f-20)` become zero;
  `1f20` still emits exponent notation. PDF ISO 32000-1 §7.3.3 explicitly
  forbids exponent notation, while SVG 1.1 XML number attributes allow it.
  Require lossless decimal expansion for PDF, remove the unjustified SVG
  workaround and retract the reversed specification claims.
- **Entry detection:** both Julia 1.10.13 and 1.13.3 have `PROGRAM_FILE`.
  Under `-e`, passing an existing `.jl` argument falsely triggers the candidate's
  `/proc/self/cmdline` scanner on both versions. Replace it with the documented
  entry path, remove unsupported frozen-build/try-scope claims, and test CLI,
  include and `-e` invocation. Fix runner string equality and premature default
  output-directory creation.
- **Example correctness:** QOI straight bytes must enter `Image` through
  `new_image(q)`. Explicit raster fallback must export the same unsupported
  scene, with independently checked transparent/partial/opaque samples;
  also test fresh destination preservation. Correct copying/matte claims,
  demonstrate actual notebook-returned images, and document font setup.

Independent review worktree: `/tmp/opencode/vetra-e001-coord-c0`, detached at
`bde2e75`. Reproductions: `/tmp/opencode/e001-c0-coord-bmp.log` and
`/tmp/opencode/e001-c0-alpha.bmp`; official PDF specification downloaded to
`/tmp/opencode/PDF32000_2008.pdf` (text lines 1196–1220). SVG source:
<https://www.w3.org/TR/SVG11/types.html#DataTypeNumber>.

Coordinator ran `julia --startup-file=no --project=.
examples/gallery/run_gallery.jl /tmp/opencode/e001-c0-core-artifacts` in the
review tree: six programs passed **60/26/35/59/17/27** internal checks in the
current environment (not a proof of provider isolation). Log:
`/tmp/opencode/e001-c0-coord-gallery.log`. Raster contact sheet was visually
inspected; all six produced PDFs rendered with `pdftoppm -singlefile
-scale-to 800 -png` with exit 0 and empty stderr. Those checks do not cover
the independently reproduced alpha/number edge failures. Writer-reported full
gates remain unapproved; run fresh independent gates on the corrected candidate.

R040 integration push `489d30e` passed all **10 CPU CI jobs** in
[run 43148162586](https://github.com/skynet-core/Vetra.jl/actions/runs/43148162586),
including Linux/Windows/macOS/FreeBSD tests and four non-expired platform
benchmark artifacts. This adds no cross-platform Vulkan runtime evidence.

#### E001 review history: correction candidates

Candidate `65a7006` was also **rejected**. Independent source
review confirms substantial corrections, but `_pdfNum(1234567.125)` and its
Float32 equivalent throw `ArgumentError: can't repeat a string -7 times`.
The same failure is reproduced through `write_pdf!` with a 32×32 recording
containing an off-canvas rectangle at that coordinate; the fresh destination
is correctly left uncreated. Decimal expansion omitted the case where the
decimal point falls inside the significand digits. New tests also interpolate
raw paths into Julia/Python source, which breaks Windows path escaping.
These fixes, precise decimal/upstream attribution, core-provider absence
assertions and the notebook invocation snippet are assigned to the same writer.

The BMP boundary correction independently passes in detached review worktree
`/tmp/opencode/vetra-e001-coord-c1`: a handcrafted top-down V5 covers **65,536**
straight color/alpha combinations. Decoding matches independent integer
premultiplication; encode/decode preserves those stored bytes; Pillow 12.1.1
decodes the encoded output exactly against the unchanged pinned
`straight_alpha.tsv` oracle. **4/4 assertions on each of Julia 1.10.13 and
1.13.3**, plus both independent Python checks. Commands:

```sh
/usr/bin/python3 /tmp/opencode/e001-coord-bmp.py prepare
julia +1.10 --startup-file=no --project=. /tmp/opencode/e001-coord-bmp.jl
julia --startup-file=no --project=. /tmp/opencode/e001-coord-bmp.jl
/usr/bin/python3 /tmp/opencode/e001-coord-bmp.py verify
```

The initial coordinator harness used the wrong binary-string decode argument
and ties-to-even expectation; it was corrected to the documented byte-vector
API and pinned independent alpha oracle before recording these passing results.
Writer-reported full gates for `65a7006` (96.11%/96.07%) do not cover the newly
reproduced PDF failure. Fresh independent full gates await the next correction.

Final writer correction `e2bcfba` addresses the decimal-point interior case,
Windows-safe test paths, source attribution and explicit core-provider absence
preflight. Coordinator integration candidate is detached **`748d5e1`** (main
`489d30e` merged with the writer branch), in `/tmp/opencode/vetra-e001-integration`.
Main had not advanced to this candidate at that review stage. Separate identical tree
`/tmp/opencode/vetra-e001-coord-final113` isolates the concurrent coverage gate.

Independent `/tmp/opencode/e001-coord-numbers.jl` passed **24,014/24,014** on each
of Julia 1.10.13 and 1.13.3: finite Float32/Float64 bit patterns spanning signs,
exponents and significands, decimal grammar, parse-back at both precisions,
subnormal/extreme values and a real million-coordinate export. Poppler rendered
that 32×32 PDF with empty stderr and correct red/background sample pixels.
The BMP interop probe also passes on the final integration source.

Both required `scripts/check.jl` gates passed: Julia 1.10.13 **96.11%
(7907/8227)**, Julia 1.13.3 **96.07% (7805/8124)**, gallery **79/79** each; logs:
`/tmp/opencode/e001-coord-final-gate110.log` and `...-gate113.log`.
The documented optional environment setup succeeded with Julia 1.10 without
changing tracked metadata (`/tmp/opencode/e001-coord-optional-setup.log`).
Actual optional-provider batch plus core-only CLI re-runs passed:
`julia --startup-file=no --project=examples/gallery/optional_env
examples/gallery/run_gallery.jl /tmp/opencode/e001-coord-final-artifacts --core-only`;
log `/tmp/opencode/e001-coord-final-cli.log`. Optional counts:
**60/26/37/67/17/33**; core-only counts **60/26/34/56/17/34**, with the six-provider
absence preflight passing. All twelve optional/core PDFs rendered with Poppler
at 96 dpi, exit 0 and empty stderr. Five representative SVGs rendered in
headless Chromium; the asymmetric fallback SVG passed five independent pixel
samples including partial/zero alpha on white. Optional Arabic typography and
the atlas were visually inspected.

**Approval was blocked by a newly exposed PDF orientation bug.** The
fallback PDF's raster is vertically flipped: at 96 dpi, gallery pixel `(1,1)`
is white instead of background `(230,232,236)`, and `(39,31)` is background
instead of accent `(30,64,175)` (coordinates here are zero-based Pillow).
`/tmp/opencode/e001-coord-image-orientation.jl` independently confirms both
strict ImageOp and raster fallback invert a six-color 16×24 asymmetric stamp
on a 32×32 page. Outputs are in `/tmp/opencode/e001-coord-orientation/`.
The old fallback test is vertically symmetric, so even its external renderer
checks cannot detect this error. Qwen is correcting both coordinate paths and
adding asymmetric rendered regressions. PDF 32000-1 §8.9.4 explicitly defines
the image-to-unit-square transform `[1/w 0 0 -1/h 0 1]`; source text is at
`/tmp/opencode/PDF32000_2008.txt`, lines 13937–13966. Correct raw image bytes
alone do not establish rendered placement. D038 will include the reviewed
orientation correction once validated; no candidate had been integrated then.

Final orientation correction **`873939f`** was independently validated in
detached candidate **`254be96`**, now integrated. Independent source review confirms
both placement matrices now compose §8.9.4 correctly. Re-running
`/tmp/opencode/e001-coord-image-orientation.jl` adds a 90-degree rotated case:
strict, fallback and rotation each render the six expected colored blocks and
white background correctly with Poppler at 96 dpi (empty stderr). The corrected
gallery fallback independently passes all five expected samples, including
partial alpha `(227,227,227)` over white and uncovered white pixels. Actual
`export_policies.jl` optional CLI passes **33 checks**, log
`/tmp/opencode/e001-coord-orientation-gallery.log`; rendered artifacts in the
matching directory. RGB and alpha streams are unchanged by this CTM-only fix.

Required full gates run on identical `254be96` source in the two isolated review
trees. Julia 1.10.13 passed **96.11% (7907/8227)**, gallery **79/79**, log
`/tmp/opencode/e001-coord-orientation-gate110.log`; Julia 1.13.3 passed
**96.07% (7805/8124)**, gallery **79/79**, log `...-gate113.log`.
Both final gates and external render checks support the approval above.

R040 writer's final correction `db47824` was independently reviewed in
`/tmp/opencode/vetra-r040-coord-c3`. Self-checks **174/174**, independent actual
debug-callback capture survival **13/13**; p00/p10/p20/p30/p40/p60 checks passed
**14/8/7/15/18/5** respectively. Captured workload errors survive both hazard
controls, failed-control setup and synthetic severity checks; the controls'
intentional errors do not contaminate workload validation. Logs are
`/tmp/opencode/r040-c3-coord-{tests,capture,p00,p10,p20,p30,p40,p60}.log`.
The independent p50 rerun passed **8/8** (log
`/tmp/opencode/r040-c3-coord-p50.log`). The root Julia 1.13.3 gate passed:
`julia --startup-file=no --project=. scripts/check.jl`, **95.79% (7762/8103)**
coverage; log `/tmp/opencode/r040-coord-root-gate113.log`. PyMuPDF interoperability
was skipped because that module is unavailable.
Root integration candidate was detached `440276d` in
`/tmp/opencode/vetra-r040-integration`: prior main plus R040 commits, exact
probe-tree match to `db47824`. Coordinator approved this bounded probe and
fast-forwarded main through `440276d`; all source/evidence matches the reviewed
candidate. Integration commits: `3d1f9a9`, `12f781d`, `9374696`, `440276d`.
Coordinator subsequently updated only the probe README's approval status and
clarified direct-destructor misuse versus `Base.finalize`; scripts, tests,
pins and committed evidence remain byte-identical to `db47824`.

Independent commands in `/tmp/opencode/vetra-r040-coord-c3` used:

```sh
export VK_LAYER_PATH=/tmp/opencode/vvl/install/share/vulkan/explicit_layer.d
export LD_LIBRARY_PATH=/tmp/opencode/vvl/install/lib
julia +1.11 --startup-file=no --project=lib/VetraVulkan/probe lib/VetraVulkan/probe/test/runtests.jl
# Each p00_env, p10_loader_device, p20_offscreen, p30_compute,
# p40_bool_layers, p50_errors and p60_julia_matrix script was run separately:
julia +1.11 --startup-file=no --project=lib/VetraVulkan/probe lib/VetraVulkan/probe/scripts/p20_offscreen.jl
julia +1.11 --startup-file=no --project=lib/VetraVulkan/probe /tmp/opencode/r040-c3-coord-capture.jl /tmp/opencode/vetra-r040-coord-c3/lib/VetraVulkan/probe
```

All seven probe commands exited successfully, with **14/8/7/15/18/8/5** checks.
The capture-survival probe submits an actual debug-utils error, verifies survival
through both hazard controls and failed setup, then through synthetic severity
checks (**13/13**). The intentional errors are positive controls, not workload
failures. The original false-clean result is resolved. D037 records the pins,
native ownership constraints, independent provider minimum and explicit platform
blockers. R010 is ready; no renderer or other-platform support is inferred.

### Implementation wave started 2026-11-11

Pinned base: `9826b7e`. Qwen3.8 writers have disjoint ownership:

- **M004 (done)**, `/tmp/opencode/vetra-m004`, branch `modernization/correctness`:
  reproduce/fix crop overlap, cmap-12 bounds, dash ownership, HarfBuzz handle
  lifetime/language/buffer cleanup and confirmed paragraph-shaping gaps. M003
  already fixed constructor/zero-PPM validation. Keep independent expectations,
  lazy optional providers and Julia 1.10 compatibility; both full gates passed.
- **R040 (bounded probe approved)**, `/tmp/opencode/vetra-r040`, branch `canvas/vulkan-probe`:
  isolated `lib/VetraVulkan/probe/` stack, discovery, clear/readback, nonconstant
  Julia-authored shaders, SPIR-V plus runtime validation and platform evidence.
  Investigate declared-compatible SPIRV/Vulkan first; missing drivers/devices or
  incompatible toolchains are explicit blockers, not inferred support. Initial
  candidate `713543b` was rejected after independent review (history below);
  final `db47824` is approved and integrated as described above.

Coordinator owns shared docs/metadata/exports and integration; writers do not
push or approve their own work. No overlapping Canvas implementation is assigned.

#### M004 review history (resolved by final approval below)

M004 first submission `e88aceb` was **rejected**. Coordinator reproduced a
new cmap-12 regression: a standard 16-byte header with language=0 and one group
U+10000–U+10002 → glyphs 1–3 parses on main but returns an empty mapping on the
candidate. The implementation and its new fixture both omitted the required
language field. Microsoft OpenType 1.9.1's cmap specification (source revision
`810414e13e39f68adfb5f12d525e6b50c850fbbc`) confirms the original header offsets.
Qwen must restore those offsets, retain independently justified range validation
and repair the fixture. Passing candidate gates do not establish correctness.

The HarfBuzz review also requires `GC.@preserve` across native handle use with
the new weak cache/finalizer, plus accurate failure/cleanup handling and tests.
Installed `hb-blob.h` confirms mode 0 is DUPLICATE, not the report's READONLY;
retain the safe copy-per-live-font behavior and correct that ownership claim.
Numbered corrections were returned to Qwen; full coordinator gates await the
corrected candidate. The documented pure-LTR paragraph limitation remains for
R012's contract review. R040 continues independently; no backend approval follows
from these CPU fixes.

Correction `e91a5a1` restores the standard cmap header; coordinator's six
independent valid/invalid-range/truncation checks pass. Blob-copy documentation
and GC preservation are corrected. Approval still awaits native-failure handling:
HarfBuzz 15.1.0's `hb_buffer_create` never returns NULL on allocation failure;
it returns an empty sentinel with `hb_buffer_allocation_successful == false`.
Coordinator substituted `hb_buffer_get_empty` into the existing create-function
pointer slot (restored in `finally`) and reproduced silent empty shaping output
for three Arabic codepoints. Qwen must detect the published failure state and
test cleanup/recovery. The lifecycle test must also allow collection after its
ephemeral owner leaves scope rather than assert a particular GC schedule.
Coordinator also reproduced crop-bound overflow on `e91a5a1`:
`super_image(Image(3,2), typemax(Int), 0, 1, 1)` (and the y variant) takes the
inside/subimage branch after integer wrap, then raises BoundsError rather than
returning transparent pixels. Qwen is correcting containment/bounds arithmetic
in both `superImage` and `subImage`, with Int-limit and partial-overlap tests.

### M004 final approval and independent evidence (2026-11-11)

**Final candidate `52a40b9` approved**, following the rejected assumptions and
correction rounds above; integrated as `7b9ebda`, `a9f6997`, `7b6e7c0`.
Validated source/tests match the integration exactly. Crop predicates now avoid
endpoint overflow; HarfBuzz constructors/failure checks use published sentinels
and buffer allocation status, with deterministic buffer cleanup and preserved
font ownership. cmap header remains standard. See D036 and compatibility notes.

Coordinator full gates in detached `/tmp/opencode/vetra-m004-coord{113,110}`:

| Check | Julia 1.13.3 | Julia 1.10.13 |
| --- | --- | --- |
| `scripts/check.jl` | exit 0; **95.79% (7762/8103)** | exit 0; **95.83% (7865/8207)** |
| Independent crop/cmap/dash probes | **96/96** | **96/96** |
| Independent native failure/GC probes | **17/17** | **17/17** |

```sh
julia --startup-file=no --project=. scripts/check.jl
julia +1.10 --startup-file=no --project=. scripts/check.jl
julia --startup-file=no --project=/tmp/opencode/m004-coord-env113 /tmp/opencode/m004-coord-probes.jl /tmp/opencode/vetra-m004-coord113
julia +1.10 --startup-file=no --project=/tmp/opencode/m004-coord-env110 /tmp/opencode/m004-coord-probes.jl /tmp/opencode/vetra-m004-coord110
```

Logs: `/tmp/opencode/m004-coord-gate{113,110}.log` and
`/tmp/opencode/m004-coord-probes{113,110}.log`. Full suites include the 302-test
shaping suite and 383 native-API tests, plus existing rendering/export/provider
checks. PyMuPDF interop was skipped because the module is unavailable.

The native probes inject failure at each allocation-status checkpoint (before
input, after input and after shaping), force GC inside the native-use interval,
assert exactly one buffer destroy on each path, verify owner survival during
use and collection afterward, and verify correct Arabic glyphs after recovery.
Function pointers are always restored. This supplements the published-empty-
sentinel regression in the committed suite; no real system OOM was induced.

Independent targeted performance runs on Linux Julia 1.13.3, baseline `9826b7e`
and final `52a40b9`, same provider versions, three warmed samples:

| Workload | Calls | Before median ms / Julia bytes | After median ms / Julia bytes |
| --- | ---: | ---: | ---: |
| Arabic shaping, same live font | 100 | 14.494 / 177600 | 0.203 / 131200 |
| Interior crop | 1000 | 25.857 / 32072000 | 23.280 / 32072000 |
| Already-overlapping padded crop | 1000 | 7.592 / 32072000 | 3.851 / 32072000 |
| Formerly discarded overlap | 1000 | 12.250 / 160072000 | 13.015 / 160072000 |

```sh
julia --startup-file=no --project=/tmp/opencode/m004-coord-env-before /tmp/opencode/m004-coord-perf.jl /tmp/opencode/vetra-m004-before
julia --startup-file=no --project=/tmp/opencode/m004-coord-env113 /tmp/opencode/m004-coord-perf.jl /tmp/opencode/vetra-m004-coord113
```

Logs: `/tmp/opencode/m004-coord-perf-{before,after}.log`. These are bounded
workload observations, not general speed claims or native-allocation counts.
The formerly discarded overlap now draws actual source pixels; its old output
was wrong.

#### Remote CI and Windows follow-up

Pushed implementation/evidence through `a69027a`. Coordinator watched
`gh run watch 43002436891 --exit-status` (exit 1), then inspected jobs and failed
logs. [Run 43002436891](https://github.com/skynet-core/Vetra.jl/actions/runs/43002436891)
passed **9/10 jobs**: Linux/macOS both Julia versions, Windows 1.10, FreeBSD
tests and all platform benchmarks. All four benchmark artifacts are present
and unexpired (`gh api repos/skynet-core/Vetra.jl/actions/runs/43002436891/artifacts`).
Current-Julia Windows failed `test/api_native_tests.jl:774`: constructor allocation
parity, 10359 vs 10343 bytes. The prior documentation-only push `9826b7e` also
failed this gate in run 42914342763 (lines 774/776: 10327 vs 10359 and 10343 vs
10327). Earlier M003 run 42913541720 remains genuine passing evidence, but does
not establish stability of this allocation check.

Logs: `/tmp/opencode/m004-ci-43002436891-{watch,failed}.log` and
`/tmp/opencode/m003-ci-42914342763-failed.log`. Qwen completed the bounded
investigation and test correction in `/tmp/opencode/vetra-windows-allocation`, branch
`modernization/windows-allocation`, base `a69027a`; no blind tolerance loosening.
Coordinator independently reviewed and validated the candidate before pushing;
remote verification subsequently passed (below). R040 continues independently.

Windows follow-up candidate `6eff5cd` changes only the allocation-parity
workload from 64×40 to 24×16, retaining exact equality and the existing drawing
operations. Coordinator verified that `new_image === newImage` and both routes
use the same `Image` constructor. Julia 1.13.3 source confirms large buffers
are charged via `memory_block_usable_size` (`src/gc-stock.c:3932`), with Windows
aligned allocation measured using `_msize` minus the alignment offset
(`src/gc-common.c:121–149`). Pool-sized storage instead uses fixed size classes;
1536 payload bytes plus the header remain below the 2024-byte pool ceiling
(`src/genericmemory.c:30–48`, `src/julia_internal.h:605`). This removes the
allocator-slack dependency rather than increasing a tolerance.

Coordinator probes `/tmp/opencode/winalloc-coord-probe.jl` passed **304/304**
per version, including 100 repeated measurements of all three constructor
routes and an extra-copy negative control. Actual Linux measurements:
Julia 1.13.3 **1664 vs 3296 bytes**, Julia 1.10.13 **1632 vs 3264 bytes**
(constructor versus extra copy). Equality is within a runtime, not across
versions. Logs `/tmp/opencode/winalloc-coord-probe{113,110}.log`.
Both full gates passed on exact candidate `6eff5cd` in the reused coordinator
worktrees: **95.79% (7762/8103)** on Julia 1.13.3 and **95.83% (7865/8207)**
on Julia 1.10.13. Each includes all 383 API tests and 302 shaping tests;
PyMuPDF interop was skipped because the module is unavailable.

```sh
# /tmp/opencode/vetra-m004-coord113 at 6eff5cd
julia --startup-file=no --project=. scripts/check.jl
# /tmp/opencode/vetra-m004-coord110 at 6eff5cd
julia +1.10 --startup-file=no --project=. scripts/check.jl
julia --startup-file=no --project=/tmp/opencode/m004-coord-env113 /tmp/opencode/winalloc-coord-probe.jl /tmp/opencode/vetra-m004-coord113
julia +1.10 --startup-file=no --project=/tmp/opencode/m004-coord-env110 /tmp/opencode/winalloc-coord-probe.jl /tmp/opencode/vetra-m004-coord110
```

Full-gate logs: `/tmp/opencode/winalloc-coord-gate{113,110}.log`.
Candidate independently approved and integrated as `e879026`; the coordinator
shortened only its explanatory test comment, retaining detailed evidence here.
Executable test logic matches the validated candidate. This does not approve
the separate R040 candidate.

**Remote verification passed:** `c31626ad8e8735cae8c2d734573e3b64dd8e5495`
passed all **10 jobs** in
[run 43019390200](https://github.com/skynet-core/Vetra.jl/actions/runs/43019390200).
Both Windows Julia lanes now pass; Linux/macOS both lanes and FreeBSD 14.3 /
Julia 1.10.13 pass, alongside all platform benchmarks. The four benchmark
artifacts (Windows, macOS, Ubuntu, FreeBSD) are present and unexpired.
Coordinator verified `gh run watch 43019390200 --exit-status` (exit 0),
`gh run view 43019390200 --json conclusion,headSha,url,jobs`, and
`gh api repos/skynet-core/Vetra.jl/actions/runs/43019390200/artifacts`.
Watch log: `/tmp/opencode/winalloc-ci-43019390200-watch.log`.
M004 remote verification and the Windows follow-up are closed.

### R040 first-candidate review: not approved

Qwen submitted `713543b` (22 files under `lib/VetraVulkan/probe/`) with Linux
NVIDIA execution evidence. Coordinator used detached worktree
`/tmp/opencode/vetra-r040-coordinator`, without changing the writer's tree.

- **Clean checkout fails:** the documented GPU-free self-check raises ENOENT
  for `Manifest.toml`, which is absent from the commit. Log:
  `/tmp/opencode/r040-coord-clean-check.log`. Coordinator copied the writer's
  ignored Manifest solely to proceed with diagnostic execution; that does not
  make the committed candidate reproducible.
- **Validation false negatives:** `probe_common.jl` uses ERROR=8, WARNING=4,
  INFO=2, whereas the actual Vulkan constants are 4096, 256 and 16. Injecting
  actual error/warning flags into the captured messages yields zero classified
  errors and warnings. All original clean-validation counts need rechecking.
  Requested validation must also fail if the layer/messenger is unavailable;
  checks must include cleanup and finalization rather than stop before them.
- **Feature-query ownership:** pinned Vulkan 0.6.30's
  `src/prewrap/pointers.jl` `_initialize_core` consumes its `refs` vector with
  `popfirst!`; `_initialize` then stores the emptied vector as dependencies.
  Coordinator observed an initialized feature-query structure with non-null
  pNext and **zero retained dependency owners**. Retrying AssertionError does
  not fix this lifetime defect or establish an ICD transient. A rooted query
  path or explicitly recorded local patch, with GC checks, is required.
- **Minimum-feature claim disproved:** original p30 passed locally. Coordinator
  then corrected severity masks and removed both variable-pointer feature
  requests; the same SPIR-V and all three readbacks still passed, 10/10 checks.
  These features are not demonstrated requirements of this emitted module.
  The Int8 capability mapping and p10 memory-property labels also use incorrect
  features/bits; corrections must use actual enums and primary contracts.
- **Cleanup needs correction:** manual wrapper `.destructor()` calls leave
  registered finalizers in place; the pinned wrapper decrements an unsigned
  refcount on every call. Review explicit finalization, dependency order and
  exception-path cleanup, including memory mapping and submission. Check memory
  dependencies with synchronization validation, not readback success alone.
- **Unsupported host claims:** standard Julia do-block callback ordering,
  UTF-8 character count versus byte indexing and ordinary `rm` semantics are
  mislabeled as broken/stripped builds. Coordinator verified normal subprocess
  stdout/stderr capture and exit status, do-block ordering and UTF-8 length on
  Julia 1.11.9 (5/5). Remove the false claims and unnecessary shell workarounds.
- **Isolation/coverage gaps:** precompile probes delete shared depot cache and
  project preferences; move these to an isolated temporary environment. The
  1.10 foreign-manifest failure is not a shader compatibility test, and the
  first SPIRV depot directory is not necessarily the pinned revision. Bool
  probes must require the requested layer and fail rather than skip mismatches.
  Complete the fresh layer build recipe and distinguish platform source
  investigations from unavailable Windows/macOS/FreeBSD execution.

Independent commands (in the coordinator tree, with the diagnostic Manifest):

```sh
VK_LAYER_PATH=/tmp/opencode/vvl/install/share/vulkan/explicit_layer.d LD_LIBRARY_PATH=/tmp/opencode/vvl/install/lib julia +1.11 --startup-file=no --project=lib/VetraVulkan/probe lib/VetraVulkan/probe/scripts/p20_offscreen.jl
VK_LAYER_PATH=/tmp/opencode/vvl/install/share/vulkan/explicit_layer.d LD_LIBRARY_PATH=/tmp/opencode/vvl/install/lib julia +1.11 --startup-file=no --project=lib/VetraVulkan/probe lib/VetraVulkan/probe/scripts/p30_compute.jl
```

Logs: `/tmp/opencode/r040-coord-p20.log` (8192/8192 upload bytes and exact clear),
`/tmp/opencode/r040-coord-p30.log` (original 10/10), and
`/tmp/opencode/r040-coord-p30-minimal.log` (10/10 after the two diagnostic edits
described above). These establish bounded execution, not approval of the original
validation/ownership claims. Corrections were returned to the existing Qwen
writer. R010 remains gated; no R040 code has been merged or pushed.

### R040 correction `2ac65cc`: partial validation, further corrections assigned

The committed Manifest and corrected severity masks resolve the original
reproducibility/filtering blockers. Coordinator used a fresh detached worktree
`/tmp/opencode/vetra-r040-coord-c1` at this exact candidate:

- `test/runtests.jl`: **143/143**, including actual debug-callback severity
  controls. Log `/tmp/opencode/r040-c1-coord-tests.log`.
- `p20_offscreen.jl`: **5/5**, 8192/8192 upload bytes and exact magenta clear,
  zero classified validation errors/warnings through the successful cleanup.
  Log `/tmp/opencode/r040-c1-coord-p20.log`.
- `p30_compute.jl`: **15/15**, same independently checked compute results,
  50 GC-stressed rooted feature queries, no variable-pointer device features,
  zero classified validation errors/warnings. Log
  `/tmp/opencode/r040-c1-coord-p30.log`.
- `p40_bool_layers.jl`: **18/18**, requested layer states verified, true/false
  readbacks exact, no reproduced layer crash. The 1-byte case remains a
  diagnostic, not proof of safe buffer bounds. Log
  `/tmp/opencode/r040-c1-coord-p40.log`.
- Fresh CMake build-directory configuration from the README succeeded and
  built the known-good dependencies. Log `/tmp/opencode/r040-c1-coord-vvl-config.log`.
- Independent synchronization-validation controls **2/2**: two overlapping
  buffer fills without a barrier produce WRITE_AFTER_WRITE only when sync
  validation is enabled. Probe `/tmp/opencode/r040-c1-coord-sync.jl`, log
  `/tmp/opencode/r040-c1-coord-sync.log`.

Commands use Julia 1.11.9, `--startup-file=no --project=lib/VetraVulkan/probe`,
`VK_LAYER_PATH=/tmp/opencode/vvl/install/share/vulkan/explicit_layer.d` and
`LD_LIBRARY_PATH=/tmp/opencode/vvl/install/lib`, in the coordinator worktree.
The independent 1.10 child was invoked via `julia +1.10` with a fresh temporary
project and the pinned SPIRV source path.

Remaining findings returned to the same writer:

1. `p60_child.jl:62` catches the genuine `cached_return_type` source-compatibility
   failure, then throws **BoundsError** by slicing a 121-codeunit message at
   `1:300`. Parent checks accept any nonzero exit as compatibility evidence.
   Capture the real error safely and reject unrelated diagnostic/process failures.
   Full independent log `/tmp/opencode/r040-c1-coord-110child.log`.
2. Partial resource-construction failures still lack deterministic cleanup.
   Injecting a memory-type-selection error after buffer creation raises the
   device refcount **1→2**, restored only by later GC. Log
   `/tmp/opencode/r040-c1-coord-failure-cleanup.log`. Guard acquired resources
   and assert immediate parent-count restoration on bounded failure paths.
3. `VK_EXT_validation_features` is a layer-provided instance extension,
   deprecated by `VK_EXT_layer_settings`, not promoted to core. Coordinator
   enumerated it by specifying the validation layer. Sync validation works,
   but the explanation must be corrected. MoltenVK portability enumeration
   needs an instance extension plus `VK_INSTANCE_CREATE_ENUMERATE_PORTABILITY_BIT_KHR`,
   not the invented `physicalDevicePortabilityEnumeration` feature; advertised
   `VK_KHR_portability_subset` must be enabled on the selected device.
4. Isolated precompile source copying selects by version string, which does not
   uniquely identify a pinned Git revision. Resolve and verify the exact manifest
   source/tree. Remove residual unsupported host/API claims and distinguish API
   version from driver version in the platform notes.

Independent p50 re-execution passed **8/8**: no-device, bogus-extension and
unsupported-format errors; isolated precompile succeeds for `false`/`auto` and
fails with the expected no-driver diagnostic for `true`. Log:
`/tmp/opencode/r040-c1-coord-p50.log`. The source-selection provenance correction
above remains required despite these successful executions. Linux evidence can be accepted
with explicit unavailable-platform blockers once the remaining correctness and
provenance issues are resolved; no cross-platform execution is claimed. R010
continues to await approved constraints, and no R040 code is integrated.

### R040 correction `a45f9cb`: validation capture regression

Coordinator checked exact candidate `a45f9cb` in detached worktree
`/tmp/opencode/vetra-r040-coord-c2`. Its self-checks passed **174/174**
(`/tmp/opencode/r040-c2-coord-tests.log`), using:

```sh
VK_LAYER_PATH=/tmp/opencode/vvl/install/share/vulkan/explicit_layer.d LD_LIBRARY_PATH=/tmp/opencode/vvl/install/lib julia +1.11 --startup-file=no --project=lib/VetraVulkan/probe lib/VetraVulkan/probe/test/runtests.jl
```

**Not approved:** the newly added `sync_hazard_control` empties shared `_CAP`.
`p20_offscreen.jl` calls both controls after the real upload/clear workload,
before classifying validation. A separate instance does not isolate this global
capture. Coordinator seeded an error, observed one classified error, called the
sync-disabled control, and observed **zero errors and `validation_clean=true`**.
Log: `/tmp/opencode/r040-c2-coord-capture-loss.log`. The reproduction deliberately
asserted the bad outcome; its exit success is evidence of the bug, not acceptance.
The writer must preserve caller capture on success/failure, isolate intentional
control errors, and add a regression retaining the seeded workload error through
both controls. Other capture resets and messenger lifetime through cleanup/GC
are included in this bounded correction.

The writer also reintroduced false build-specific Julia claims. Coordinator
verified **8/8 standard semantics checks** on Julia 1.11.9: pattern-first
`occursin`, character-safe `first`/`last` on short and multibyte strings,
`throw(e)` inside a catch, and binding-less catch syntax all work normally.
Current `occursin` call sites use the correct standard order and must not be
inverted. Remove false host warnings and language-semantic portability tests;
retain actual helper regression tests. The existing Qwen session has been
resumed for these corrections. No R040 code is integrated or pushed; R010
remains gated and non-Linux execution remains unverified.

Vulkan source research is **reviewed for planning**, with coordinator qualifications
recorded in `docs/CANVAS_RESEARCH.md`: SPIRV.jl exists (experimental,
Julia 1.11 / Vulkan 0.6 declared compat), LLVM translator's OpenCL Kernel output
does not establish Vulkan compute compatibility, Vulkan 0.7 defaults to System
loader, and SPIR-V validation cannot replace runtime layers. FreeBSD Lavapipe-JLL
limitations are route-specific, not proof all system Vulkan is unavailable.
The corrected report was received; coordinator additionally checked pinned stage
exports, Vulkan extension, execution harness and CI definition. SPIRV.jl is the
first candidate to probe, not a finalized choice; neither a one-line compat fix,
the companion Julia minimum nor software/hardware platform support is established.
R040 now checks nonconstant device work, actual minimum features and the upstream
disabled-validation concern. Hardware evidence remains required; R040 runtime
evidence awaits submission and independent review.

Browser/notebook source research is also **reviewed for planning**. Independently
checked BCD/IJulia/JupyterLab sources are in `docs/CANVAS_RESEARCH.md`: Safari
filters are preference-gated, Firefox has the standard convertToBlob name as
well as an alias, current conic entries are unflagged, untrusted SVG is rejected
by the inspected JupyterLab renderer, and no default MP4 MIME factory was found.
The corrected report was received and incorporated with coordinator qualifications:
native Canvas can draw full turns (WHATWG steps checked), exact independent simple
pixel assertions remain, optional vector MIME is retained, and renderer-module
unit tests do not replace actual kernel/frontend checks. Mapping formulas remain
conformance-gated proposals. Plan amendments require a static fallback inside
HTML, trust/frontend tests, correct HTML/JSON escaping, new Canvas semantics and
independent affine/composition/numeric checks. No new browser/kernel execution
was performed.

Media source review is **complete for planning**, with the accepted subset and
rejected proposals recorded in `docs/CANVAS_RESEARCH.md`. Coordinator verified
exact libwebp upstream provenance and its exported Internal constructors/ABI
helpers, VideoIO rational reader position and explicit-index writer/duration
behavior, and FFmpeg artifact/source provenance. Limited Linux symbol/tool and
sample-metadata checks are explicitly separated from provider acceptance: no
resolved VideoIO environment, animation FFI lifecycle or four-OS media test ran.
The odd-size MP4 sample is YUV444; the VFR sample's stream duration differs from
the final frame end. Neither supports the report's broad timing/dimension claims.
The inspected FFmpeg build enables nonfree components; R064 owns distribution-
compatible provider/build selection. No dependencies were added. R064–R069 retain
streaming, explicit matte/retiming/track policies and staged-output contracts.
The final independent review approved these amendments and rechecked the
43-task/98-edge graph without shifting any implementation or ownership gate.

Latest architecture amendment checks passed: inline Python task/spec/DAG/release-closure
and local link validation found 43 matching tasks, 98 dependency edges, all tasks leading
to final R099, and 24 valid local links including the research record;
`git diff --check` passed. No Julia runtime
gate run for these documentation-only changes; provider/backend acceptance is
still unverified by this planning work.

Existing M005 docs, M006 cleanup and M007 final validation are folded into
R099/R086/R090; M003/M004 remain prerequisites. All proposed backend interfaces
must remain labeled as plans until implemented and validated.

## Active direction: Julia-native modernization

### M003 completed: review and validation (2026-11-10)

**Approved and integrated:** Qwen's final `0c88c91`, following three reviewed
correction rounds. Integration commits are `ae9faf6`, `5716ae2`, `bdf39a5` and
`901b9d7`; source, tests, examples and package metadata match the validated
candidate exactly. M004 subsequently completed (see above); registration remains user-owned.

Qwen submitted `c1ea06e` on `modernization/native-api`, based on `d2d44fa`.
**Initial candidate rejected.** Coordinator read the diff and connected methods,
then reproduced six correction groups: unchecked four-argument Image creation;
missing one-based axes validation before color-import kernels; incorrectly
classified/missing native mutators; missing current-path `fill!` on recordings;
separate `dot`/`normalize` exports still conflicting with LinearAlgebra; and
missing dimension/end/eachindex/linear-assignment methods on the Image interface.

A standard inner constructor using `new` worked under both Julia 1.13.3 and
1.10.13; the reported platform limitation does not justify a fourth Image field
or an unchecked constructor. Exact minimum-version probe (exit 0):

```sh
julia +1.10 --startup-file=no -e 'println(VERSION); struct ConstructorProbe; x::Int; function ConstructorProbe(x::Int); x > 0 || throw(ArgumentError("positive")); new(x); end; end; @assert ConstructorProbe(1).x == 1; println("inner constructor works");'
```

Other focused probes used the candidate's `--project=.` and the existing
`--project=/tmp/opencode/m002env` environment, with `pathof(Vetra)` verified.
Expressions and outcomes are recorded in the M003 task review. A safe zero-based
matrix wrapper entered `fromColors` and failed only after three element reads.
No expected fixtures were modified.

Numbered corrections were returned to the same Qwen writer, including regression
tests, corrected migration documentation, both Julia gates and remeasurement of
the reported +16-byte context allocations after restoring the three-field Image.
Subsequent corrections `e0d1ff8` and `62afa30` restore the validated three-field
constructor, shared LinearAlgebra bindings, correct mutator inventory, early
axes checks and row-major linear `eachindex`. Coordinator ran the exact `62afa30`
full gates in detached worktrees `/tmp/opencode/vetra-m003-coord-{113,110}`:

- `julia --startup-file=no --project=. scripts/check.jl`: exit 0,
  **95.84% (7734/8070)**, `/tmp/opencode/m003-coord-gate113.log`.
- `julia +1.10 --startup-file=no --project=. scripts/check.jl`: exit 0,
  **95.88% (7837/8174)**, `/tmp/opencode/m003-coord-gate110.log`.
- Focused `test/api_native_tests.jl`: **375/375** on both versions; logs
  `/tmp/opencode/m003-coord-focused{113,110}.log`.
- `python3 /tmp/opencode/m003-coord-loading.py`: all eight fresh-process
  version × core/provider × load-order combinations pass. Candidate paths were
  asserted; `JULIA_LOAD_PATH=@:@stdlib` excludes global provider leakage.
- Independent `/tmp/opencode/m003-coord-probes.jl`: **37 pass, 5 errors** on
  both versions. `axes(img,d)` is missing, so dimensional `begin`/`end` also fail;
  Qwen is adding that method and nonsquare read/write regressions. The other
  corrected groups passed, including rejection of offset axes before any reads.

Final correction `0c88c91` adds dimension-aware `axes` with nonsquare begin/end
read/write tests. Coordinator verified the diff and reran the exact final source:

| Check | Julia 1.13.3 | Julia 1.10.13 |
| --- | --- | --- |
| Full `scripts/check.jl` gate | exit 0; **95.84% (7735/8071)** | exit 0; **95.88% (7838/8175)** |
| Native API suite within the gate | **383/383** | **383/383** |
| Independent corrected-case probes | **42/42** | **42/42** |

Exact commands, run in the corresponding detached worktree:

```sh
julia --startup-file=no --project=. scripts/check.jl
julia +1.10 --startup-file=no --project=. scripts/check.jl
julia --startup-file=no --project=/tmp/opencode/m003-coord-env113 /tmp/opencode/m003-coord-probes.jl /tmp/opencode/vetra-m003-coord-113
julia +1.10 --startup-file=no --project=/tmp/opencode/m003-coord-env110 /tmp/opencode/m003-coord-probes.jl /tmp/opencode/vetra-m003-coord-110
```

Logs: `/tmp/opencode/m003-coord-final-gate{113,110}.log` and
`/tmp/opencode/m003-coord-final-probes{113,110}.log`. Full gates also exercise
all six optional providers after core-only precompilation. PyMuPDF interop was
skipped because the module is unavailable. Source/test/migration corrections
are Qwen's; shared evidence and integration are coordinator-owned.

Coordinator benchmark comparison used Linux Julia 1.13.3, the same resolved
provider versions, baseline `9d6bdc8` and final candidate `0c88c91`. Both
eight-workload output-checking smoke runs passed. In the respective worktrees:

```sh
VETRA_BENCH_SMOKE=1 julia --startup-file=no --project=/tmp/opencode/m003-coord-env-before -e 'using Vetra; @assert dirname(dirname(pathof(Vetra))) == pwd(); include("benchmark/run_benchmarks.jl")'
VETRA_BENCH_SMOKE=1 julia --startup-file=no --project=/tmp/opencode/m003-coord-env113 -e 'using Vetra; @assert dirname(dirname(pathof(Vetra))) == pwd(); include("benchmark/run_benchmarks.jl")'
```

| Workload | Before median ms | After median ms | Before bytes | After bytes |
| --- | ---: | ---: | ---: | ---: |
| fill_rects_1000 | 0.954 | 0.927 | 8515560 | 8515560 |
| stroke_lines_1000 | 26.750 | 28.755 | 22203640 | 22203640 |
| blur_128_r3 | 0.383 | 0.375 | 656800 | 656800 |
| shadow_128 | 0.406 | 0.423 | 1640760 | 1640760 |
| draw_10 | 0.235 | 0.357 | 1639120 | 1639120 |
| png_encode_256_x10 | 26.321 | 28.370 | 47522280 | 47511880 |
| png_decode_basic1_x10 | 2.915 | 2.892 | 13901360 | 13880560 |
| text_parse_layout_x100_measure_x20 | 1.273 | 1.283 | 10136080 | 10136080 |

Logs: `/tmp/opencode/m003-coord-bench-{before,after}.log`; TSVs in each
worktree's `benchmark/results/julia_2026-11-10_smoke.tsv`. No allocation total
increased: six match, PNG totals are slightly lower (the implementer's all-eight
equality was not reproduced). The earlier +16-byte fill/stroke regression is
gone. Shared-host five-sample timings are observations, not a speed claim:
draw's minimum stayed 0.232→0.231 ms despite the median variation. No kernel
optimization is inferred.

M003 remote validation is complete at `f8b2dfe`: [run 42913541720](https://github.com/skynet-core/Vetra.jl/actions/runs/42913541720)
passed **all 10 jobs**. Julia 1.10 and stable tests passed on Linux, Windows and
macOS; FreeBSD 14.3 / Julia 1.10.13 passed tests and benchmark smoke. All four
platform benchmark artifacts are present and unexpired. Coordinator verified
with `gh run watch 42913541720 --exit-status` (exit 0),
`gh run view 42913541720 --json conclusion,url,jobs` and
`gh api repos/skynet-core/Vetra.jl/actions/runs/42913541720/artifacts`.

2026-11-10: user requested independent Julia-native identity/API, obsolete
port-document cleanup, rewritten interactive GitHub Pages documentation, and
working Linux/Windows/macOS/FreeBSD tests and benchmarks. Follow
the original `tasks/MODERNIZATION.md` M001–M007 sequence, since superseded by
the Canvas plan above. GPT-6 Astra validates; Qwen3.8 implements. M001–M004
are now complete. The following records the earlier M002/M003 integration:
Baseline `415c7a0` was clean and already pushed. Existing remote CI fails;
Pages workflow hosting is enabled but there is no deployment yet.
M002 implementation and review fixes are integrated (`95185c3`, `8bfd7ae`).
Coordinator full gates now pass concurrently on Julia 1.13.3 (95.82%) and
1.10.13 (95.86%), after fixing a shared Chromium fixture directory. Benchmark
smoke passes. Qwen's sole implementation worktree is now `julia-native-api`
(branch `modernization/native-api`); old M002 worktree is validation-only.
Remote run 42809642886 passed all six Linux/Windows/macOS tests and three
benchmark jobs. FreeBSD booted/installed Julia, then failed for missing Git;
VM preparation is fixed; run 42811680553 passed all 10 jobs, including FreeBSD's
full test/coverage gate (95.32%) and benchmark smoke. Four OS-specific benchmark
artifacts are present. M002 acceptance is satisfied at revision `d2d44fa`.
Keep registration user-owned. Preserve licenses, attribution, regression
fixtures and test/benchmark/docs infrastructure during cleanup.

The historical handoff below is evidence to consolidate, not the active plan.

Updated: 2026-11-10

## State

T000–T022 are complete. The adoption milestone (T014–T018, D024–D026)
finished on 2026-11-07: friendly numeric arguments, opt-in ColorTypes
interop, native notebook display, docs/gallery/cookbook, and a verified
0.1.0 release candidate (nothing published). T020 established the
application performance baselines (`benchmark/app_benchmarks.jl` +
`benchmark/startup_benchmarks.jl`, three sequential runs with raw TSVs,
machine meta, and representative PNGs). T021 then cut startup and
first-render latency (D028): lazy codec discovery (`__init__` no longer
requires the optional packages — `using Vetra` in a codec-enabled env went
~580 ms -> ~20 ms), `invokelatest` at the lazy-require boundary (world-age
safety), and 16 precompile entry points (first render ~2.5 s -> ~30 ms).
Cost moved to the reported install stage: precompile+load 1.7 s -> 3.8 s,
cache .so 2.4 MB -> 6.2 MB. T022 cut repeated-render allocations (D029):
non-solid gradient fills (linear/radial/angular) replaced the 2-buffer
mask+fillImg pipeline with a fused single-buffer path — one call-owned row
scratch (4*width bytes) through geometry sampling, `_cutRowOut!`
(applyOpacity+MaskBlend arithmetic), and `_blendRowInto!` (blendRect's
exact per-pixel branches); ImagePaint/TiledImagePaint unchanged. Byte-exact
against a 4204-scene A/B corpus of the original pipeline. Draw allocation
vs T020 targets: 25->17 MB @1080p, 96->64 MB @4K, 173->131 MB
@clip_layers; wall time neutral overall with one recorded canvas_4k +5%
regression. PNG encode allocation deferred as codec-bound (23.8 MB @1080p
= 7.9 MB staging + ~15.8 MB PNGFiles/libpng internals + payload; the
toStraightAlpha boundary pass is already at the no-aliasing 1-buffer
minimum). T023 settled the recording contract (D030, docs/RECORDING.md):
design only — a kernel-level display list recorded by a one-shot
`PictureRecorder`/`RecordingContext`, deep snapshots at the record boundary
(text lowered to glyph outlines), vector-space replay scaling, fail-fast
record-boundary errors, and strict v1 SVG/PDF export matrices with a
documented whole-picture raster fallback. T024 implemented it
(`src/recordings.jl` + 5 exports + `drawPicture`): record/replay is
byte-identical to direct CPU drawing on 11 contract scenes, scaling is
vector (area-justified coverage, not a raster enlargement), snapshots
survive source mutation, and record-boundary errors fail fast. T025 added
SVG export (`src/formats/svg_write.jl` + `writeSvg`): strict pre-scan with
named errors and no partial file, exact gradient mapping via
`gradientTransform` (linear: raw canvas handles + T^-1; radial: unit circle
+ T^-1·M, the raster ellipse map), clipPaths per group scope, group-unit
opacity, base64-PNG data-URI images (opt-in PNGFiles), and a documented
whole-picture `rasterFallback`. Verified byte-exactly against hand-derived
documents, independently with XML, read back through the pinned SVG reader
(byte-identical for the supported shape), and rendered in headless
Chromium 156.0.8078.47 with exact geometry checks. T026 added PDF export
(`src/formats/pdf_write.jl` + `writePdf`): single-page PDF 1.4,
scale-independent via `dpi` (page = picture size × 72/dpi pt), strict
pre-scan with named errors and no partial file, gradients as PDF
shadings (linear: repelled element-space handles; radial: CTM exactly
the raster ellipse map, path in M^-1∘T space; stops as FunctionType-3
stitching — the spec defines no constant function type), `W n` clip
before `sh` (shading paints the whole clipped user space, ISO Table
76), group-unit alpha via isolated Form XObjects + `/ca` ExtGState at
`Do` time (pinned empirically against both verifiers), raw uncompressed
RGB + SMask images, glyph outline text, arcs flattened via the pinned
`endpointToCenterArcParams`, quadratics as exact cubic equivalents (PDF
has no quadratic path operator), and a documented whole-picture
`rasterFallback`; the SVG arc x-axis rotation emission was fixed to
degrees verbatim along the way. Verified with hand-derived geometry
under gs 10.06.0 + poppler/pdftoppm 26.01.0. Full gate:
**95.83% coverage (7603/7934)** (T029). No ready rows: T019 awaits an
explicit publication request (user-owned — the user registers the
package directly). T013–T032
are committed and pushed to origin main (protocol: commit+push after each
task); the package is unregistered (General `P/Vetra` = 404, re-checked
2026-11-07).

## Changes

- Planned adoption work, notebook/image interoperability, documentation/recipes,
  release preparation and registration, application benchmarks, performance,
  recording/replay, SVG/PDF export, typography/shaping, and JPEG/WebP codecs.
- Each task defines scope, likely touchpoints, acceptance criteria, validation,
  and handoff requirements. Design prerequisites gate advanced implementation;
  GPU rendering and widget frameworks remain deferred.
### Prior completed work (T013 and tutorial)

- Added [GETTING_STARTED.md](GETTING_STARTED.md), a basics-to-advanced Markdown
  guide with 13 runnable blocks, exercises, expected outputs, and troubleshooting.
- Removed committed allocation traces and obsolete scaffold documentation;
  ignored process-suffixed allocation output and removed stale generated traces.
- Simplified PNG encoding by sharing `toStraightAlpha`, retaining its opaque
  fast path. Removed an unused XML wrapper and a duplicate export.
- Consolidated API, architecture, task board, and current handoff documentation.
  Historical acceptance evidence remains in task records and decisions.

## Verification

Roadmap planning: local file links passed in 53 Markdown documents; all 19 new
specs have acceptance/validation/handoff sections and matching prerequisites.
The dependency graph is acyclic, all eight ready tasks have completed
prerequisites, decision IDs are unique, and `git diff --check` passed.
No source/runtime changes; the results below are prior implementation evidence,
not new runs for this documentation edit.

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
julia --startup-file=no --project=docs docs/make_cookbook.jl
julia --startup-file=no --project=docs docs/cookbook.jl
julia --startup-file=no --project=docs benchmark/run_benchmarks.jl
```

Reference assets are under ignored `.reference/`; tests do not fetch them.
Tutorial and cookbook output (executed Markdown, notebooks, recipe PNGs, and
`docs/build/gallery.html`) go to ignored `docs/build/`; the OHLC project's
named exports go to ignored `artifacts/`; benchmark TSVs go to ignored
`benchmark/results/`. Optional codecs are discovered at runtime; install
them before loading Vetra, or restart Julia after installation.

## Next step and limits

No active implementation task. The roadmap is complete except T019
(registration/publication), which is user-owned — the user registers the
package directly ("no, I'll register myself"), so it needs an explicit
publication request. T029 (shaping/bidi) is done: option (b) of D031 §6
selected and recorded as D033 — an opt-in `HarfBuzz_jll` (harfbuzz
15.1.0) shaper behind a thin `ccall` surface (blob/face/font/buffer/
`hb_shape`), loaded lazily on first shaped call (core-only and
legacy-LTR installs never load it; a missing provider raises the
explicit `ErrorException("Shaping support is opt-in: ...")`). Public
API: `shapeText(tf, codepoints; script, direction, language)` →
per-cluster `Vector{Vector{ShapedGlyph}}`, additive `glyphPathByGid`
(GID → outline, no cmap; 0/out-of-range → `.notdef`), and
`ParagraphLayout.shaped` (logical → visual permutation). Engagement:
`RightToLeft` paragraphs and LTR paragraphs with strong-RTL content
shape (Arabic contextual joining, Devanagari conjuncts, Roboto `fi`
ligature, combining-mark cluster merge, L2E digit runs, mirrored
punctuation, `.notdef` missing-glyph policy); pure-LTR complex scripts
keep the T028 isolated-forms rendering (named v1 limit). Bidi is a
documented UAX#9 simplification; RTL placement follows harfbuzz's
cairo-bridge pen model. Reference: system libharfbuzz 12.3.2 via the C
driver `tools/oracle/hb_refshape.c`, 10 cases pinned in
`test/reference/shaping_reference.tsv` over the OFL
NotoSansArabic/NotoSansDevanagari fixtures (`test/fixtures/`) +
upstream-pinned Roboto; JLL 15.1.0 ≡ 12.3.2 on all 10 (probe log in
tasks/T029-unicode-shaping.md). Evidence: `test/shaping_tests.jl` (223
assertions), the codec-loading legs, cookbook recipe 15
(multilingual card). T029 also fixed the T028 vendored UAX#29 cluster
tables (a range misalignment had put base letters inside both
`_CLUSTER_EXTEND`/`_CLUSTER_MC`); they are regenerated codepoint-exact
from Unicode 16.0.0 (`tools/oracle/gen_cluster_tables.py`). T032 shipped the WebP half: `decodeWebP`/`decodeWebPDimensions`/
`encodeWebP` per the T030 contract (docs/JPEG_WEBP_CODECS.md §3, D032)
via the opt-in `WebP.jl` 0.1.3 + `libwebp_jll` 1.6.1+0 extra — success-
checked feature scan first (the provider's auto-decode ignores the
scan's return value), animation rejected with a named `ArgumentError`
**before** pixel decode (the provider decode crashes the process at C
level on animated input), always-RGBA encode with the 16383 dimension
bound (the provider silently returns 0 bytes at 16384), lossless
round-trips byte-exact in the premultiplied API, lossy validated by
dimensions + PSNR floor (≥ 35 dB at q75, measured 37.67). Decode
evidence: the 129-file pinned upstream libwebp corpus at the upstream
`test_webp.nim` dimensions (12 exact expectations) + corpus-wide
decode/alpha classification; the animation-error path uses the pinned
Wikimedia fixture (sha256 in its meta). Record: no independent WebP
pixel decoder on the machine (contract §3.5 limitation). D028 lazy
loading protocol extended to WebP (absent → install hint, present →
round-trip). T031 shipped the JPEG half before it: `encodeJPEG`
(contract §2) over the existing opt-in `JpegTurbo` dependency, with
mupdf 1.28.2 independent-reader interop (max channel delta ≤ 8,
measured 4) and the PSNR floor (measured 48.78 dB at q92) — plus a
latent world-age fix in `decodeJPEG` (first-use decode in a fresh
process now works).
Protocol (user, 2026-11-08): commit and push to `origin main` after each
completed task.
Planned features are not implemented capabilities; see
[Compatibility](COMPATIBILITY.md). Fresh installation on Julia 1.10,
cross-platform CI (Windows/macOS), and the ProfileView GUI were not rerun;
Pluto was not installed, so T016 verification used IJulia only. Historical
release evidence is in [T011](../tasks/T011-release.md),
[T012](../tasks/T012-optimization.md),
[T018](../tasks/T018-release-readiness.md), and
[DECISIONS.md](DECISIONS.md).

## Recent verification (T014–T032)

- T014 `test/numeric_api_tests.jl` (23 assertions, byte-for-byte Int-vs-Float32
  scene parity); T015 `test/colormatrices_tests.jl` (29) + core-only ColorTypes
  hint in `test/codec_loading_tests.jl`; T016 `test/notebook_display_tests.jl`
  (11) + a real IJulia/nbclient kernel run (execute_result mime keys
  `image/png` + `text/plain`, valid 191-byte PNG).
- Full gate after each: T014 811,432 / 97.98%, T015 811,461 / 97.99%,
  T016 811,472 / 97.97%. T017 is docs-only; gate re-run unchanged at
  811,472 / 97.97%. Log: `/tmp/opencode/t017-check.log`.
- T017: `make_cookbook.jl` executed end to end (COOKBOOK.md/.ipynb, 8 named
  PNGs, gallery.html); clean `rm -rf docs/build` rebuild reproduced all
  images; 0 broken relative links across README, INDEX, GETTING_STARTED,
  TUTORIAL, ROADMAP, build/cookbook/COOKBOOK.md, and gallery.html; all 8
  rendered recipes visually inspected.
- T018: fresh clean-depot installs (core-only and optional-integration)
  from a working-tree release candidate; full `scripts/check.jl` gate green
  in a clean environment (811,472 assertions, 97.97%); namespace check
  (279 exports; 6 intentional Base shadows); NOTICE updated; version 0.1.0
  loads clean. Logs: `/tmp/opencode/t018-{fresh-gate2,main-fresh}.log`.
- T020: `benchmark/app_benchmarks.jl` (27 workload/stage rows, 3
  sequential runs, invariants before timing, representative PNGs inspected)
  + `benchmark/startup_benchmarks.jl` (fresh-process protocol, 3 cached + 1
  cold-depot runs). Raw outputs in `benchmark/results/app_2026-11-07_r*.tsv`
  and `startup_2026-11-07.tsv`; baseline table and T021/T022 targets in
  `tasks/T020-application-benchmarks.md`.
- T021: before/after startup protocol
  (`benchmark/results/startup_2026-11-07_{before,after}.tsv`): cached load
  579–587 -> 19–20 ms, first render 2468–2548 -> 28–32 ms, warm 38–40 ->
  30–32 ms, cold-depot total 4328 -> 3877 ms. Reported install-stage cost:
  precompile+load 1.7 -> 3.8 s, cache .so 2.4 -> 6.2 MB. Fresh-process lazy
  codec proofs (encodePNG/parseSvg/readImage JPEG/toColors-fromColors, no
  preload) all pass. Steady-state app suite r4/r5 within r1–r3 spread. Gate
  811,472 assertions / 97.99% (5458/5570); logs
  `/tmp/opencode/t021-{gate3,app-r4,app-r5,startup-after}.log`.
- T022: fused single-buffer gradient fill (D029). Byte-exact 4204-scene A/B
  corpus (3 gradient kinds × linear horizontal/vertical/diagonal × 4 paths ×
  17 blend modes × 4 opacities × 3 backgrounds, plus image/tiled controls and
  globalAlpha layers) — the original 2-buffer pipeline vs the fused path,
  dumped as raw bytes, **4204/4204 identical**; the corpus caught two real
  regressions during development (alpha left uncut; horizontal double
  cut-out). Independent review (openai/gpt-6-astra, 2026-11-08): no
  must-fix pixel findings; three should-fix items implemented — finite
  stop-position validation before any destination write (preserves the
  old pipeline's all-or-nothing error contract; non-finite stops now
  throw a deliberate ArgumentError), tests pinning the horizontal
  double-cut regression plus mask-family/translucent/tie-neighbor gaps,
  and stale comment fixes. Full gate green: **98.01% coverage
  (5662/5777)**; 42-assertion hand-derived regression testset ("T022
  fused non-solid gradient fill").
  App suite r1–r5 (baseline) vs r12–r14 (fused), medians: draw allocation
  25→17 MB @1080p, 96→64 MB @4K, 173→131 MB @clip_layers; wall time neutral
  overall, canvas_4k/draw a consistent +12–15 ms (+5%) regression recorded
  as the cost. PNG encode allocation deferred as codec-bound (23.8 MB @1080p
  = 7.9 MB staging + ~15.8 MB PNGFiles/libpng internals + 10 KB payload;
  toStraightAlpha boundary pass already at the no-aliasing 1-buffer minimum).
  Logs: `/tmp/opencode/t022-gate4.log`,
  `/tmp/opencode/t022-app-r1{2,3,4}.log`; raw TSVs
  `benchmark/results/app_2026-11-07_r{12,13,14}.tsv`.
- T023: recording contract (D030). Design only — `docs/RECORDING.md`
  (kernel-level display list, `PictureRecorder`/`RecordingContext`, deep
  snapshots, vector-space replay scaling, strict v1 SVG/PDF export matrices
  + whole-picture rasterFallback, five canonical validation scenes and
  per-task references for T024–T026), the D030 decision entry, and the
  docs/API.md §Recordings proposal (marked specified-not-implemented).
  Contract walked through all five scenes; `git diff --check` clean; no
  source changes, so the T022 gate result stands (98.01%, 5662/5777).
  T024 unblocked; committed and pushed per the commit+publish-after-each-
  task protocol.
- T024: `src/recordings.jl` (op records, one-shot
  `PictureRecorder`/`RecordingContext` mirroring the `Context` drawing
  surface, `drawPicture` replay) + 5 exports + `test/recording_tests.jl`
  (38 assertions). Record/replay byte-parity vs direct CPU drawing on 11
  contract scenes (fills/strokes, gradients, transforms, clips,
  layers+globalAlpha, nested saveLayer-in-clip, drawImage incl. src/dst
  rect, text, clearRect, save/restore); vector-space scaling (2× and ½×)
  with area-justified coverage; snapshots survive source mutation;
  record-boundary errors (TiledImagePaint fill, non-solid strokeStyle,
  unmatched restore, finished recorder). Cookbook recipe 9 (record once /
  replay at 480×300 + 960×600) with both PNGs visually inspected; gallery
  rebuilt. Full gate green: **811,552 assertions, 98.13% (5939/6052)**.
  Benchmark (800×500 activity card): record 0.36 ms vs direct 2.3 ms;
  replay ×4 amortizes to ~1.1 ms/render; replay == direct byte-identical.
  Frozen-build quirk: do-block syntax mis-parses, so `_recWrap` call sites
  use explicit function literals.
- T025: `src/formats/svg_write.jl` + `writeSvg` export (D030 §6.1
  contract) + `test/svg_export_tests.jl` (333 assertions). Strict pre-scan
  (clearRect, angular/ImagePaint fills, non-Normal blends, degenerate /
  out-of-range / unsorted gradient stops, non-finite geometry,
  singular-transform gradients → named `ArgumentError`, no file written);
  exact gradient mapping via `gradientTransform` (linear: raw canvas
  handles + T^-1; radial: unit circle + T^-1·M, the raster's ellipse map —
  both proven affine-exact for every invertible T); `clipPath` per group
  scope (intersecting children), group-unit `opacity`, base64-PNG data-URI
  images (opt-in PNGFiles), whole-picture `rasterFallback`.
  Verification: byte-exact minimal document; exact `d` strings for all 19
  path command kinds; hand-derived `matrix(…)`/`gradientTransform` values;
  independent XML structural parse (all `url(#id)` refs resolve); pinned
  SVG reader read-back byte-identical to the replay (identity-transform
  scene); headless Chromium 156.0.8078.47 (snap; verifier tooling only,
  no resvg on this machine) render with exact rect/background/dash-body
  geometry and the justified ≤2-channel gradient sampling tolerance
  (Vetra samples at integer x, Chromium at pixel centers). Known renderer
  difference documented: interior dash-end caps (SVG spec vs pinned
  raster). Cookbook recipe 10 (record → replay → SVG) + 12-item gallery.
  Frozen-build quirks hit: `Base.base64encode`/`takebuf`/`popen`/
  `ignorestderr` are stripped (pinned `_base64Encode`/`IOBuffer.data`/
  string commands used), backtick concatenation mis-parses, and a shared
  counter reassigned from `pop!` restarted after a group close.
  Full gate green: **811,885 assertions, 98.28% (6241/6350)**.
- T026: `src/formats/pdf_write.jl` + `writePdf` export (D030 §6.2
  contract) + `test/pdf_export_tests.jl` (202 assertions, 10 testsets).
  Strict pre-scan (clearRect, angular/ImagePaint fills, non-Normal
  blends, even-odd gradient fills, degenerate / out-of-range /
  non-strictly-increasing / semi-transparent gradient stops, non-finite
  geometry, singular-transform gradients → named `ArgumentError`, no
  file written; pre-scan skipped under `rasterFallback`); gradients as
  PDF shadings — linear with repelled element-space handles
  (`d' = (|d|²/|Tᵀd|²)·Tᵀd`, `h'1 = T⁻¹h1 + α·d'`, exact for every
  invertible T), radial under the CTM exactly equal to the raster's
  ellipse map with the path emitted in `M^-1∘T` space; stops as
  FunctionType-3 stitchings of Type-2 segments (`Encode` required; the
  spec defines no constant type, so a single stop is Type-2 with
  C0 == C1 — numbering settled against ISO 32000-2 Table 38 + poppler
  26.01.0 `Function.cc` + mupdf 1.28.2 + gs empirically); `W n` clip
  before `sh` (`sh` paints the whole clipped user space, ISO Table 76 —
  confirmed in both renderers); group-unit alpha via isolated Form
  XObjects (`/Group /S /Transparency /I true`) + the group's `/ca`
  ExtGState in effect at `Do` time, pinned empirically against both
  verifiers on a hand-crafted constant-alpha case (overlap
  (191,127,191) gs / (190,127,191) poppler vs per-child
  (127,191,191)); raw uncompressed RGB + DeviceGray SMask images
  (`Do` maps the image to the unit square → CTM = imageMat·scale(w,h);
  FlateDecode deferred — no codec dependencies allowed); arcs flattened
  via the pinned `endpointToCenterArcParams` (k = (4/3)tan(d/4));
  quadratics as exact cubic equivalents (PDF has no quadratic path
  operator — the first emission used SVG's `q`, which gs/poppler/mupdf
  all silently ignore). Verification: self-consistent document
  structure (xref offsets, stream Lengths, trailer); hand-derived
  geometry at pixel centers under gs 10.06.0 + poppler/pdftoppm
  26.01.0 (verifier tooling only); dpi scale independence (96 vs 144,
  proportional pages, identical re-rasterizations); byte-exact image
  and rasterFallback streams; strict errors with no file written.
  Tolerances documented: radial shading ±10 (renderer-specific
  sub-pixel sampling offsets up to ~1 px; the spec does not pin shading
  sampling), stroke-band pixel checks use centers >=0.5 pt inside /
  >=1.5 pt outside (renderer antialiasing fuzz). Also fixed the SVG arc
  x-axis rotation emission (the path buffer stores degrees; the T025
  conversion ×180/π was wrong, uncaught because T025 tested rotation 0
  only). Cookbook recipe 11 (report graphic exported at 96/288 dpi, two
  named PDFs) + 13-item gallery; both PDFs render-verified. Frozen-build
  quirks hit: `position(io)` is 0-based (xref offsets need no +1),
  range slices with expression starts need parentheses
  (`v[a + n:(b)]` mis-parses), vector-pattern and regex
  `findfirst`/`findlast`/`findall` return the matched range (unwrap
  with `first`), `match`'s `offset` kwarg is stripped (walk suffixes),
  `SubString` has no `.length` field (use `length(s)`), `String*Int`
  needs `string`, and a `return` directly in a `@testset` body exits the
  enclosing testset's whole body (kept testset bodies
  `return`-free). Full gate green: **96.25% (6718/6980)** (coverage
  down from 98.28% because the new writer's relative-command branches —
  unreachable via the public path API, kept for parity with the SVG
  writer — are exercised only structurally).
- T027: paragraph layout and shaping contract (D031, `docs/TEXT_LAYOUT.md`;
  design only, no source changes — the T026 gate result stands).
  Investigated the 2026 package landscape: the General registry (full
  package-name sweep, 2026-11-09) has **no maintained Julia shaping
  provider** — `HarfKit.jl`/`Pango.jl` are delisted, `FreeType`/`Cairo`
  do not shape, JLL wrappers exist (`HarfBuzz_jll` v8.5.1+0) but a JLL
  alone is not an API; system `libharfbuzz` present but no CLI tools.
  Contract: **T028 core-only** (zero new dependencies) — additive
  `Paragraph`/`ParagraphLayout`/`fillParagraph` over the existing
  `Span`/`typeset` machinery (the existing `Font` already carries
  per-run style, `Typeface.fallbacks` already does recursive per-rune
  fallback — T028 adds box/overflow, paragraph line height, v1 wrap
  opportunities [white-space + explicit `\n`, no UAX#14 — recorded
  shortcut], `withFallback`, `.notdef`/zero-advance missing-glyph
  policy, metrics, vendored UAX#29-subset grapheme clusters [BMP,
  recorded provenance; per-codepoint fallback outside the subset]).
  **T029 specified but provider-gated**: shaper interface (raw font
  bytes + codepoints + script/language/direction → per-cluster
  GID/advance/offset), additive `glyphPathByGid` (GID → outline by
  direct loca/glyf index — pinned parser data sufficient; CFF/TTC stay
  unsupported under every option), UAX#9 paragraph-level base direction
  with logical→visual permutation exposed; options (a) re-emerged
  binding / (b) HarfBuzz_jll + thin `ccall` / (c) pure-Julia UAX#9 +
  GSUB-subset (needs an explicit D015 extension) / (d) defer recorded;
  **T029 blocked until one is chosen** (no provider preselected per the
  task spec). Test fonts: existing pinned fixtures for T028; new pinned
  OFL 1.1 Noto Sans Arabic + Devanagari for T029; shaping expectations
  from a pinned external reference (`hb-shape`/equivalent) or hand
  derivation — never the code under test; separate suites
  `test/paragraph_tests.jl` (T028) / `test/shaping_tests.jl` (T029).
  Seven worked examples traced in the doc (wrapped Latin, mixed-size
  runs, fallback, Arabic joining, Indic conjunct, mixed RTL/LTR,
  combining marks). API proposal in docs/API.md marked
  specified-not-implemented.
- T028: paragraph layout implemented (`src/formats/paragraph.jl` +
  `withFallback` in `src/formats/fonts.jl`; `test/paragraph_tests.jl`,
  22,760 assertions; cookbook recipe 12 `paragraph-card.png`).
  **Reuse confirmed in practice**: the layout pass is the pinned
  `typeset` (absolute `lineHeight` applied by copying each run's `Font`,
  alignment forced Left/Top on zero dimensions); the new code adds the
  box/overflow (Clip via a box-sized scratch blit so context
  transform/clip/globalAlpha/mask apply; Ellipsis drops trailing
  clusters — fewest first, re-laid-out per trial — until the last line
  with U+2026 fits, glyph-existence checked on the ellipsis span's
  effective font, plain clip otherwise), the cluster pass (vendored
  UAX#29 subset: BMP `Grapheme_Extend` + `Mc` tables, Unicode 16.0.0
  provenance; ZWJ joins both sides, ZWNJ left only, narrow Hangul
  `L V* T*`, GB3 control sequences; stdlib `Unicode.graphemes`
  deliberately not used — likely-cluster semantics differ and it is
  version-gated), line/metrics objects, and rendering. **Frozen-build
  String quirk hit and worked around**: `length(s)`/iteration are
  codepoint-based but `s[i]`/`s[a:b]` are byte-based with boundary
  checks — cluster indices are codepoints; `_charStarts` converts for
  slicing. `withFallback` does real cycle detection (a diamond DAG with
  shared descendants is allowed; a candidate reaching the base graph or
  an earlier candidate raises `ArgumentError`); `fallbackTypeface` is
  guaranteed to terminate. Contract amendments recorded in
  docs/TEXT_LAYOUT.md: NBSP is an ordinary wrap position (not no-wrap),
  long unbreakable runs split character-wise at overflow (the pinned
  engine behavior — a wrapping paragraph never overflows its box
  horizontally except dangling end-of-line SPACE), alignment is
  ineffective on zero dimensions, cluster indices are codepoints.
  Legacy `typeset`/render suites byte-unchanged. Large-paragraph timing:
  20,000 words @ 800 px — layout ~24 ms (pinned engine ~14 ms of it),
  fill ~1.14 s for 3.28 M ink px (shared glyph-fill cost, log
  `/tmp/opencode/t028-bench.jl`). Gate green: **96.29% (7013/7283)**.
- T030: JPEG/WebP codec contracts + provider decision
  (docs/JPEG_WEBP_CODECS.md, D032 amending D014; design only, no source
  changes — gate unchanged at **96.29% (7013/7283)**).
  **Providers verified in isolated scratch environments**
  (`/tmp/opencode/codecprobe`, commands + versions in the task record):
  JPEG encode = `JpegTurbo` 0.1.6 (JpegTurbo_jll 3.2.1+0; the existing
  opt-in decode dependency — zero new deps; `jpeg_encode` confirmed with
  quality/JFIF-header/density kwargs); WebP = `WebP.jl` 0.1.3 +
  `libwebp_jll` 1.6.1+0 (the registry's only WebP package, MIT, pushed
  2026-06-24, 18 platform artifacts; new opt-in extra for T032).
  **Contract decisions**: `encodeJPEG(image; quality=92,
  background=white)` — exact integer premultiplied→straight composite
  (`out8 = clamp((p8*255 + b8*(255-a8) + 127) div 255)`, no division by
  alpha), JFIF with **contract-mandated 72×72 dpi** (without it mupdf
  assumes 96 dpi and scales the page 0.75× — measured on all four
  header variants), quality 1..100, no EXIF/Adobe, dimension bound
  65500 (the provider segfaults at 65501 — bisected); `encodeWebP(image;
  lossy=true, quality=75)` always RGBA (lossless ignores quality —
  provider API), dimension bound 16383 (the provider silently returns
  an empty vector at 16384 — verified);
  WebP decode = feature scan first, **animation rejected with a named
  `ArgumentError` before pixel decode** (reproduced: `WebP.decode` on an
  animated file crashes the Julia process at C level — uncatchable),
  straight→premultiplied via the house formula. **Validation policy
  (lossy is never byte-exact)**: JPEG = hand-derived marker structure +
  PyMuPDF/mupdf 1.28.2 interop (page rect = SOF at 72 dpi; pixmap max
  channel delta ≤ 8, measured 4; PSNR floor, measured 48.78 dB at q92) +
  conversion worked examples; WebP = pinned Google gstatic gallery
  fixtures (lossy VP8 368×550, lossless VP8L 301×400) + Wikimedia
  animated fixture, all with URL + byte size + sha256, plus the
  round-trip exactness partition (lossless: alpha exact everywhere, RGB
  exact where α>0, unspecified where α=0 — measured 81/3072 mismatches,
  all in the α=0 corner). Recorded limitation: no independent WebP
  decoder on the verification machine (no ffmpeg/cwebp/dwebp/ImageMagick/
  PIL; mupdf refuses WebP) → WebP decode pixels are fixture-dimension-only
  assertions. **Test plan**: extend the D019 present/absent + shared-cache
  codec-loading protocol to WebP; RIFF+WEBP magic dispatch in
  `decodeImage`/`decodeImageDimensions`; `encodeBase64` stays PNG-only
  (upstream parity), `decodeBase64` gains WebP via the magic dispatch.
  T031/T032 unblocked; COMPATIBILITY/API rows updated to
  specified-not-implemented.
- T031: JPEG encoding implemented (`encodeJPEG` in
  `src/formats/jpeg.jl`; `encodeImage`/`writeFile` JpegFormat dispatch in
  `src/formats/io.jl`; export; `test/jpeg_encode_tests.jl`, 61
  assertions; cookbook recipe 13). Contract §2 in full: exact integer
  premultiplied→straight composite over `background` (default white;
  `out8 = clamp((p8*255 + b8*(255-a8) + 127) div 255)` — no division by
  alpha, so no undefined case), JFIF baseline with the contract's
  72×72 dpi density, quality 1..100 (default 92; out-of-range is a named
  `ArgumentError`, non-Int is a `TypeError`), dimension bound 65500
  (named error — bisected: the provider segfaults at 65501 in
  `jinit_compress_master`, uncatchable). The pixel loop runs in a
  Vetra-side kernel called via `Base.invokelatest` (D028 world-age
  safety, same pattern as `toColors`). **Latent bug found + fixed**:
  `decodeJPEG`'s inline `N0f8 → Float64` conversion hit the same
  world-age wall on a fresh process (first codec call = JPEG decode
  → `MethodError: Float64(::N0f8) ... method too new`); the conversion
  is now in a `_decodeJPEGPixels!` kernel under `invokelatest`
  (byte-identical output — T008 fixtures green). **Validation**:
  hand-derived marker walk (SOI, JFIF units=1 72×72, SOF0 via the
  existing native dimensions scan, EOI); mupdf 1.28.2 interop
  (conditional on `VETRA_MUPDF_PY`; page rect = 64×48 pt, 72-dpi pixmap
  = 64×48, max channel delta 4 ≤ 8); PSNR 48.78 dB at q92 ≥ 40 floor,
  q10 strictly worse; transparent → solid background exact
  (10,20,30); half-alpha §2.2 examples exact (255 over white, 128 over
  black); `encodeImage(JpegFormat) == encodeJPEG(img)` (deterministic);
  six writable extensions incl. `.jpg`/`.jpeg`; `encodeBase64` stays
  PNG-only while `decodeBase64` accepts a JPEG payload. **T008 dispatch
  tests updated** (JPEG out of the "unencodable" loop, into the
  writable list — the try/catch assertions were silently vanishing,
  dropping the suite count 796459 → 796456; restored with real
  assertions). Codec-loading protocol extended: absent environment →
  `encodeJPEG` raises the install hint; codec-enabled →
  `decodeJPEGDimensions(encodeJPEG(img)) == (2, 3)`. **Benchmark**
  (warm medians, log `/tmp/opencode/t031_bench.jl`): mandrill 512×512
  photo — JPEG q85 105142 B / 3.39 ms vs PNG 732157 B / 17.13 ms
  (0.144×); 256×256 thumbnail — 26559 B / 0.82 ms vs 180278 B /
  3.83 ms (0.147×); flat 320×240 gradient scene — JPEG 4333 B vs PNG
  2411 B (1.797× — the unsuitable case, noted in recipe 13). Gate
  green: **96.31% coverage (7039/7309)**; T008 suite back to 796459.
 - T032: static WebP read/write implemented (`decodeWebP`/
   `decodeWebPDimensions`/`encodeWebP` in `src/formats/webp.jl`;
   RIFF+WEBP magic branches in `decodeImage`/`decodeImageDimensions`;
   `encodeImage` WebpFormat + `writeFile` `.webp`; exports;
   `test/webp_tests.jl`, 353 assertions; cookbook recipe 14). Per the
   T030 contract §3: success-checked `WebPGetFeaturesInternal` scan
   first (the provider's own auto-decode ignores the scan's return
   value — unsafe on invalid data; observed rv: 0 = OK, 3/7 =
   failure), animation rejected with the named
   `ArgumentError("WebP animation is not supported")` **before** pixel
   decode (the provider decode crashes the process at C level on
   animated input — the pinned Wikimedia fixture exercises the path;
   `decodeWebPDimensions` still reports the 211×211 canvas), invalid/
   truncated input → `ArgumentError("Invalid WebP, unable to load")`,
   always-RGBA encode (premul→straight `(p8*255 + a8 div 2) div a8`,
   clamped; `a8 = 0` → 0), dimension bound 16383 (the provider silently
   returns 0 bytes at 16384 — rejected first), lossy quality 0..100
   (the provider's named error; lossless ignores quality). **Decode
   evidence**: the 129-file pinned upstream libwebp corpus
   (`.reference/upstream/tests/fileformats/webp/`, per its SOURCE.txt)
   feature-scans and pixel-decodes at the feature dimensions for every
   file (provider matrices are `[row=y, col=x]` — confirmed corpus-
   wide); the 12 exact dimension expectations from upstream
   `test_webp.nim` all match; corpus alpha classification (89 files
   RGB → `a = 255`, 40 carry semi/transparent pixels — e.g.
   `one_color_no_palette` fully transparent, `lossless1` mixes 211284
   a=0 pixels with opaque). **Encode evidence**: lossless round-trips
   are byte-exact in the premultiplied API (opaque exact; alpha exact
   everywhere; RGB where α>0 exact; RGB where α=0 forced to 0 — the
   contract's straight-domain α=0 non-determinism, measured 81/3072,
   is unobservable in premul); lossy q75 PSNR ≥ 35 dB on the fixed
   gradient (measured 37.67; the knob bites, q10 worse); hand-walked
   RIFF chunk table (VP8L lossless; single VP8 for lossy fully-opaque;
   VP8X+ALPH+VP8 for lossy with real alpha — observed libwebp_jll
   1.6.1 order). **Loading**: D028 lazy protocol extended (absent →
   "WebP support is opt-in" hint; present → lossless byte-exact +
   dimension round-trips); T008 dispatch tests updated to the seven
   writable formats (count restored: 796459). Recorded limitation
   (contract §3.5): no independent WebP pixel decoder on the machine
   (no ffmpeg/cwebp/dwebp/ImageMagick/PIL; mupdf refuses WebP) →
   corpus decode gets dimension/classification assertions only.
   **Benchmark** (warm medians, log `/tmp/opencode/t032_bench.jl`):
   mandrill 512×512 photo — WebP lossy q75 76648 B / 27.79 ms,
   lossless 579344 B / 145.72 ms vs PNG 732157 B / 17.26 ms, JPEG q85
   105142 B / 2.79 ms; 256×256 thumbnail — lossy q75 19162 B / 6.41 ms,
   lossless 136458 B / 77.28 ms vs PNG 180278 B / 3.72 ms, JPEG q85
   26559 B / 0.82 ms; decode 512 lossy 5.96 ms, 512 lossless 5.14 ms,
   256 lossy 1.49 ms; transparent 256×256 card — PNG 1740 B vs WebP
   lossless 394 B (recipe 14 reports the numbers without claiming
   universal superiority). Gate green: **96.32% coverage (7110/7382)**;
   T008 suite 796459.
  - T029: optional shaping and bidi implemented
    (`src/formats/shaping.jl`; `shapeText`/`ShapedGlyph`,
    `glyphPathByGid`; `ParagraphLayout.shaped` + RTL engagement in
    `paragraph.jl`; `test/shaping_tests.jl`, 223 assertions; cookbook
    recipe 15). Provider: opt-in `HarfBuzz_jll` 100.15001.0+0
    (harfbuzz 15.1.0) behind a 15-symbol `ccall` surface, loaded lazily
    (D033; D028 protocol — absent → the named `ErrorException("Shaping
    support is opt-in: ...")` on RTL `layoutParagraph` and on
    `shapeText`; present → the pinned outputs). **Reference evidence**
    (protocol §8 option 2): system libharfbuzz 12.3.2 through the C
    driver `tools/oracle/hb_refshape.c` — 10 pinned cases in
    `test/reference/shaping_reference.tsv` over the OFL
    `NotoSansArabic-Regular.ttf`/`NotoSansDevanagari-Regular.ttf`
    (`test/fixtures/`, sha256 sidecars + `scripts/
    fetch_shaping_fixtures.jl`) and upstream-pinned `Roboto-Regular_1.ttf`;
    the JLL 15.1.0 provider agrees with the 12.3.2 reference on all 10
    cases (gid/cluster/advance/offset; probe log in
    tasks/T029-unicode-shaping.md). Demonstrated: Arabic contextual
    joining (shaped GIDs 424/59/36 ≠ isolated cmap 420/56/34),
    script sensitivity (Arab vs Zinh rows), Devanagari conjuncts
    (k+virama+ssa → one GID 179; the reference akshara word keeps
    clusters 0/1/4), the Roboto `fi` ligature (one GID 444; `ff` does
    not ligate), combining-mark cluster merge, missing-glyph →
    `.notdef` (gid 0, the font's 600-unit advance) with no silent
    cluster drop, L2E digit order under an RTL base, mirrored
    punctuation, RTL placement per the cairo-bridge pen model
    (right-aligned ink on the box edge), and RTL wrap with per-line
    re-shaping. **Table fix carried from T028**: the vendored UAX#29
    cluster tables had a range misalignment (base letters — Devanagari
    0905/0915/0936, Myanmar 1000..100B — inside both tables, so
    "akshara" (0905 0915 094d 0936 0930) clustered as one grapheme);
    regenerated from Unicode 16.0.0 by
    `tools/oracle/gen_cluster_tables.py`, round-trip verified
    codepoint-exact (220 extend / 112 mc BMP ranges); one T028
    expectation corrected ("ka+virama+ssa" = 2 UAX#29 clusters;
    conjunct formation is shaper-level, not grapheme-level). Gate
    green: **95.83% coverage (7603/7934)**; all legacy suites
    byte-unchanged (T028 paragraph suite 22,761 with the corrected
    expectation).
