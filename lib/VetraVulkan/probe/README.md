# VetraVulkanProbe — R040 Vulkan.jl / SPIRV.jl compatibility spike

Bounded spike for the Vetra Canvas roadmap (task R040): determine what a
**Vulkan.jl + SPIRV.jl** backend route can and cannot do on real hardware,
with the KHRONOS validation layer enabled, before any production backend
code (R010) is written. This directory is a **standalone probe project** —
`Project.toml` **and `Manifest.toml` are committed and isolated** from the
repository root; nothing here is production code (no placeholders, no Vetra
core edits).

Status: **partial candidate — Linux + NVIDIA discrete GPU only.**
Compute dispatch and offscreen upload/clear are byte-exact under the
KHRONOS validation layer (sync validation enabled) with the pinned stack;
all evidence is in [`evidence/`](evidence/) and `test/runtests.jl` re-verifies
it. This is **not** a cross-platform result and does not unblock R010:
R010 stays gated on coordinator review of this probe and of the recorded
upstream defects below.

## Pinned environment

The committed `Manifest.toml` pins everything; `evidence/p00_env.json`
records sha256s / tree hashes / git revs of the exact artifacts.

| Component | Version / pin | Provenance (hashes in `evidence/p00_env.json`) |
|---|---|---|
| Julia (probe execution) | 1.11.9 | `juliaup` channel `1.11` |
| Vulkan.jl | **0.6.30** (registry tree `7c427c83…`) | Manifest |
| VulkanCore | 1.3.1 | Manifest |
| SPIRV.jl | **0.6.11 @ git rev `218b33b21e5b23d7c3c34bb07f6c114723a5e193`** (fork `serenity4/SPIRV.jl`, tree `6732b754…`) | git dependency in Manifest |
| SPIRV_Tools_jll | 2026.4.0+0 (`spirv-val`: SPIRV-Tools v2026.4, `gef96ed76`) | artifact sha256 in p00 evidence |
| SHA | 0.7.0 | Manifest |
| System loader | `/usr/lib/x86_64-linux-gnu/libvulkan.so.1.4.341` (sha256 `def4af45…`) | p00 evidence |
| Validation layer | built from source, tag `vulkan-sdk-1.4.363.1`, rev `317cff06…`, WSI off, prefix `/tmp/opencode/vvl/install` (`libVkLayer_khronos_validation.so` sha256 `5c77f945…`; provenance recorded in `evidence/p00_env.json` → `validation_layer_provenance`) | "Running" below |

Devices seen (p10): NVIDIA GeForce RTX 3050 Ti Laptop GPU (API 1.4.351,
discrete — **the probe target**), AMD RADV RENOIR (integrated),
llvmpipe (CPU software ICD — *present*, not used as target, not claimed as
hardware proof).

## Probes

All evidence below was regenerated after the corrective fixes; check counts
are pass/fail with `fail=0`.

| Script | Result | Demonstrates |
|---|---|---|
| `scripts/p00_env.jl` | 14/0 | Pinned package set (SPIRV git rev, tree hashes), loader/ICD/layer inventory with sha256s (incl. both key shapes `layer` and `layers`), spirv-val provenance, external VVL layer + `PROVENANCE.txt`, real severity enum bits (1/16/256/4096), **synthetic severity regression** (one `vkSubmitDebugUtilsMessageEXT` per severity; positive + negative bucket controls) |
| `scripts/p10_loader_device.jl` | 8/0 | Loader dlopen, instance with KHRONOS validation layer required-and-verified enabled, device discovery (3 devices), graphics+compute queues, BDA-capable API level, R8G8B8A8 format feature bits, memory-type labels from the real enum bits, 0 validation errors/warnings |
| `scripts/p20_offscreen.jl` | 5/0 | 64×32 RGBA8 offscreen image: hand-derived upload → byte-exact readback (8192/8192), `cmd_clear_color_image` → byte-exact clear (`[255,0,255,255]`), explicit layout barriers, **sync validation requested** (instance `ValidationFeaturesEXT` pNext — `VK_EXT_validation_features` is promoted, not enumerated), 0 errors/warnings, deterministic `Base.finalize` cleanup, GC-stable after release |
| `scripts/p30_compute.jl` | 15/0 | The full SPIRV.jl route: `@compute` Julia kernel → SPIR-V 1.6 → internal + external `spirv-val --target-env vulkan1.3` (vulkan1.2 negative control fails as expected) → **module-declared capabilities** (`VulkanMemoryModel`, `Int64`, `PhysicalStorageBufferAddresses`) → derived device features asserted **subset** of module caps (f11 derived set is empty — no `variable_pointers`; `maintenance4` required for `LocalSizeId`) → BDA buffer upload → dispatch → **byte-exact readback vs an independently written Julia reference** (512/512, 400/400 + untouched sentinel) → runtime-driven output change → safe `features2` chain query under 50-iteration GC stress → 0 errors/warnings |
| `scripts/p40_bool_layers.jl` (+ `p40_child.jl`) | 18/0 | Bool-returning compute module (`OpTypeFunction %bool`) under KHRONOS layer: true/false 4-byte cases byte-exact with **per-experiment layer-enabled gate** (each child verifies the layer is actually enabled — no silent downgrade) and 0 validation errors; the 1-byte-buffer case is recorded as a **validator diagnostic** (`OpStore … Aligned 2` into 1 byte is *not* flagged — a limitation, not a safe-storage claim) |
| `scripts/p50_errors.jl` (+ `p50_child.jl`) | 8/0 | Error paths: no device (`VK_DRIVER_FILES`→bogus ⇒ `VK_ERROR_INCOMPATIBLE_DRIVER` from `vkCreateInstance`), bogus device extension (`ERROR_EXTENSION_NOT_PRESENT`), unsupported format (`ERROR_FORMAT_NOT_SUPPORTED`, names format+usage); **isolated precompile environment** (temp depot, manifest-resolved Vulkan+SPIRV sources copied into it so precompile runs fresh — never reusing the user depot's `.ji` cache): `PRECOMPILE_DEVICE_FUNCTIONS=false` (workload skipped, ok) / `auto` (workload runs, no-driver failure caught, ok) / `true` (failure rethrown with `INCOMPATIBLE_DRIVER`) — workload execution proven per case from the child loader output |
| `scripts/p60_julia_matrix.jl` (+ `p60_child.jl`) | 5/0 | Julia version matrix (wrapper-level only, no GPU execution on foreign versions): **Julia 1.10.13 — the actual minimum blocker: the pinned SPIRV source fails to precompile/load** (`UndefVarError: cached_return_type`, a 1.11-only Base API; recorded as child exit + stderr); the 1.11-generated manifest is additionally rejected by 1.10's Pkg (manifest mechanics, labeled separately, not a compatibility claim); **Julia 1.13.3 — instantiate + `using SPIRV, Vulkan` (LOAD ONLY)** |

Shared helpers (`scripts/probe_common.jl`): check accumulator, JSON evidence
writer (strict control-char escaping), debug-callback capture with
**severity classification against the real enum bits** (the old probe
hardcoded 1/2/4/8; the real values are 1/16/256/4096, so its "0 errors"
claims were void), `run_capture`/`run_jll` (env **merged** via `addenv`,
never replaced — replacing env drops `PATH` and the child fails ENOENT),
instance/device/queue/memory/BDA-buffer helpers on the Vulkan.jl 0.6.30 API,
**owned-Ref `features2` chain query** (see upstream defect 1), and
`release(h) = Base.finalize(h)` (see upstream defect 2).

## Running

Build the validation layer once (no sudo; ~5 min; fully tested recipe):

```sh
git clone --depth 1 --branch vulkan-sdk-1.4.363.1 \
  https://github.com/KhronosGroup/Vulkan-ValidationLayers /tmp/opencode/vulkan-validation-layers
cmake -S /tmp/opencode/vulkan-validation-layers -B /tmp/opencode/vvl/build \
  -DCMAKE_BUILD_TYPE=Release \
  -DCMAKE_INSTALL_PREFIX=/tmp/opencode/vvl/install \
  -DBUILD_TESTS=OFF \
  -DBUILD_WSI_XCB_SUPPORT=OFF -DBUILD_WSI_XLIB_SUPPORT=OFF \
  -DBUILD_WSI_XLIB_XRANDR_SUPPORT=OFF -DBUILD_WSI_WAYLAND_SUPPORT=OFF
cmake --build /tmp/opencode/vvl/build -j"$(nproc)"
cmake --install /tmp/opencode/vvl/build
```

WSI off is required on hosts without X11/xcb development headers. Then record
provenance **inside the install's `explicit_layer.d` dir** (p00 reads it from
there and runtests asserts `tag:`/`revision:` are present):

```sh
{ echo "source: https://github.com/KhronosGroup/Vulkan-ValidationLayers"
  echo "tag: vulkan-sdk-1.4.363.1"
  echo "revision: $(git -C /tmp/opencode/vulkan-validation-layers rev-parse HEAD)"
  echo "built: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
  echo "builder: $(uname -srmo)"
  echo "deps (scripts/known_good.json):"
  # ... dep list ...
  echo "configure: <the cmake line above>"
} > /tmp/opencode/vvl/install/share/vulkan/explicit_layer.d/PROVENANCE.txt
```

Run the probes (pinned Julia; layer env required):

```sh
cd lib/VetraVulkan/probe
export VK_LAYER_PATH=/tmp/opencode/vvl/install/share/vulkan/explicit_layer.d
export LD_LIBRARY_PATH=/tmp/opencode/vvl/install/lib
julia +1.11 --startup-file=no --project=$PWD scripts/p00_env.jl
julia +1.11 --startup-file=no --project=$PWD scripts/p10_loader_device.jl
julia +1.11 --startup-file=no --project=$PWD scripts/p20_offscreen.jl
julia +1.11 --startup-file=no --project=$PWD scripts/p30_compute.jl
julia +1.11 --startup-file=no --project=$PWD scripts/p40_bool_layers.jl
julia +1.11 --startup-file=no --project=$PWD scripts/p50_errors.jl
julia +1.11 --startup-file=no --project=$PWD scripts/p60_julia_matrix.jl
```

Self-checks (verify the committed evidence + helper logic; GPU needed for
the release/refcount/synthetic-regression tests, skipped otherwise):

```sh
julia +1.11 --startup-file=no --project=lib/VetraVulkan/probe \
  lib/VetraVulkan/probe/test/runtests.jl
```

Full re-run + re-verify (regenerates all evidence first):

```sh
R040_RUN_PROBES=1 julia +1.11 --startup-file=no --project=lib/VetraVulkan/probe \
  lib/VetraVulkan/probe/test/runtests.jl
```

## Recorded upstream defects (constraints for R010)

Both verified on the pinned Vulkan.jl **0.6.30** checkout
(`~/.julia/packages/Vulkan/12azN/`), by source reading and by execution.
Recorded here, **not patched** in the shared depot.

### 1. `Vulkan.initialize` leaves the pNext chain dangling (use-after-free)

`src/prewrap/pointers.jl`: `_initialize(T::Type{<:VulkanStruct}, Tnext)`
(lines 100–106) builds `refs`, passes the same array to
`initialize_core(core_type(T), refs)` (line 105), then stores
`T(vks, refs)` (line 106). But `_initialize_core` (lines 75–85) **consumes
that shared array** — `ref = popfirst!(refs)` (line 81) per chain element —
so by line 106 `refs` is empty. The returned wrapper's `deps` field holds
nothing while `vks.pNext` points at Refs with no owner: the whole chain is
immediately GC-eligible. Repro (one-liner, verified output `deps_len=0
pNext!=C_NULL=true`):

```julia
q = Vulkan.initialize(Vulkan._PhysicalDeviceFeatures2,
                      Vulkan._PhysicalDeviceVulkan11Features,
                      Vulkan._PhysicalDeviceVulkan12Features,
                      Vulkan._PhysicalDeviceVulkan13Features)
@assert length(q.deps) == 0 && q.vks.pNext != C_NULL   # dangling chain
```

Note `initialize_core`'s own docstring (pointers.jl:91–93) says the refs
"will have to be preserved for the initialized Vulkan structure to remain
valid" — the public `initialize` violates that contract. The earlier probe
reported this as a "transient flake" and retried the assertion; that
characterization is **retracted**: it is deterministic, and R010 must build
feature chains with **owned Refs** (`ProbeCommon.feature_chain_refs`:
correct `sType`/`pNext` set at construction, called under
`GC.@preserve`, unwrapped to high-level only inside the preserve) — never
via `Vulkan.initialize` with `next=` chains it does not keep alive.

### 2. Handle finalizers are never unregistered

`src/prewrap/handles.jl`, `init_handle!` (lines 46–48):
`finalizer(x -> handle.destructor(), handle)` — and there is no public API
to remove it. The only deterministic release a user has is calling
`h.destructor()` directly; that leaves the finalizer registered, so GC runs
`try_destroy` (lines 34–44) a second time: `decrement_refcount!`
(line 30) does `atomic_sub!` on the already-zero `UInt` counter → it wraps
to 2^64−1. The `iszero` guard stops a double raw destroy in the simple case,
but the refcount state is corrupt and mixed explicit+GC release orders can
propagate a premature destroy to the parent. Safe pattern (probe
`release`, verified: device refcount 2→0, no wrap, `refcount_ok` holds):

```julia
release(h) = Base.finalize(h)   # in reverse creation order
```

R010 backends must adopt the same release discipline (and the
`refcount_ok`-style underflow check in tests).

## Corrections to the initial (713543b) report

- **Severity measurement**: the debug-callback receives the raw
  `VK_DEBUG_UTILS_MESSAGE_SEVERITY_*_BIT_EXT` values **1/16/256/4096**, not
  1/2/4/8. The initial probe's masks mis-bucketed every message, so its
  "0 validation errors/warnings" claims were void. Classification is now
  tested against the real enum plus a synthetic
  `vkSubmitDebugUtilsMessageEXT` regression with negative controls.
- **`variable_pointers`**: retracted. The compiled module declares
  `VulkanMemoryModel`, `Int64`, `PhysicalStorageBufferAddresses` only — no
  f11 capabilities are needed (p30 asserts the derived f11 set is empty).
  `maintenance4` is required (SPIRV.jl emits `OpExecutionMode LocalSizeId`).
- **Bool storage**: the 4-byte SPIR-V store case is the supported path. The
  upstream 1-byte buffer sizing "working" is recorded as a validator
  diagnostic (store `Aligned 2` into 1 byte is *not* flagged), not as
  safe-storage evidence.
- **pNext flake/retry**: not a flake — deterministic upstream defect #1; the
  bounded-retry workaround was removed in favor of owned Refs.
- **Validation enablement**: `VK_EXT_validation_features` is not enumerated
  on this driver (promoted), so sync validation is requested via the
  `ValidationFeaturesEXT` pNext at instance creation *without* the ext name,
  and each child process asserts the layer is actually enabled
  (no silent downgrade accepted).
- **"Stripped Julia build" host-quirk list**: most of those items are
  standard Julia API gaps, not host bugs. The list below was re-verified on
  this host's 1.10.13 / 1.11.9 / 1.13.3 channels and trimmed to what
  actually affected the probe code.

## Verified host/API notes (1.10.13 / 1.11.9 / 1.13.3)

- `Pkg.activeproject` is absent → use `Pkg.project().path`.
- `run(cmd; stdout=…)` is a MethodError → `run(pipeline(cmd; stdout=IOBuffer(), stderr=IOBuffer()))`.
- `setenv` **replaces** the environment (child loses `PATH` → ENOENT); `addenv` **merges** — `run_capture`/`run_jll` merge.
- `takebuffer` is not visible from a module in this build → string building without `IOBuffer`.
- `Base.pointer(::RefValue)` is a MethodError → `Base.unsafe_convert(Ptr{Cvoid}, ref)`.
- Two-argument `Cmd(vec, extra)` is absent → `Cmd(vcat(base, extra))`.
- This host's `General.toml` registry snapshot does **not** contain SPIRV →
  name-based `Pkg.add`/specs by uuid+rev fail; the probe pins SPIRV as a git
  source in the committed Manifest (p60's 1.10 cell resolves it via a
  `Pkg.develop` path dependency, which bypasses the julia-compat resolver).
- Julia 1.10 Pkg API differs (`Pkg.Types.GitRepo(url, user, token)` 3-arg,
  keyword `PackageSpec`) — only exercised statically in p60's foreign-manifest
  cell, which is labeled mechanics, not compatibility.

## Platform scope — what was executed vs what is static

**Executed (the only execution evidence): Linux x86_64**, NVIDIA discrete
GPU (RTX 3050 Ti Laptop, driver 1.4.351), system loader 1.4.341, VVL
1.4.363.1. All p10–p50 GPU results come from this configuration.

Static, source-based notes for the platforms that were **not** executed
(no hosts available here); each needs a real run before R010 may claim
cross-platform validation:

- **Windows**: VulkanCore dlopens `vulkan-1.dll` (generated
  `LibVulkan.jl`, windows branch); Vulkan.jl 0.6.x has **no JLL loader** —
  a system loader (Vulkan SDK/Install) is required, and the probe's
  manifest dirs (`icd.d`, `*/layer.d`), `realpath`, and jq inventory are
  Linux-specific and would need porting.
- **macOS**: loader name `libvulkan.dylib`; the Apple GPU surface is exposed
  through the **portability driver** mechanism (`VK_KHR_portability_enumeration`
  instance extension + `physicalDevicePortabilityEnumeration` feature), which
  the probe's device-selection/queue/feature-minimum logic does not handle;
  MoltenVK's support for the BDA/storage-buffer 1.3 surface used by p30 is
  unverified.
- **FreeBSD**: loader name `libvulkan` (other-OS branch); ports-provided
  loader/ICDs; no execution data at all.

## Blocked / not verified

- **Windows, macOS, FreeBSD execution** — no such hosts; see the platform
  scope above.
- **Vulkan.jl 0.7.0** — not executed. SPIRV.jl 0.6.11 declares
  `compat Vulkan = "0.6"`, so 0.7 would need a recorded local patch
  (0.7 switches to `set_driver`/`Vulkan_Loader_jll` instead of the
  system-loader + `JULIA_VULKAN_*` mechanism). The 0.6.30 stack passed
  every probe, making the comparison unnecessary for R040's questions.
- **llvmpipe / RADV** were discovered but not used as probe targets
  (NVIDIA only); software-ICD shader behavior is unverified.

## Files

```
Project.toml / Manifest.toml   pinned isolated environment (uuid c35fa8e6-…), Manifest committed
.gitignore                     probe-local; negates the root Manifest.toml ignore
src/VetraVulkanProbe.jl        trivial entry module so the project precompiles
scripts/probe_common.jl        shared helpers (checks, evidence, Vulkan API)
scripts/p00_env.jl … p60_julia_matrix.jl   probes
scripts/p40_child.jl, p50_child.jl, p60_child.jl   subprocess workers
evidence/*.json                machine-readable results (committed)
test/runtests.jl               self-checks over the evidence + helper logic
```
