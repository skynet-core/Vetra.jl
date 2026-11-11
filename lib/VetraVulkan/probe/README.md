# VetraVulkanProbe — R040 Vulkan.jl / SPIRV.jl compatibility spike

Bounded spike for the Vetra Canvas roadmap (task R040): prove that a
**Vulkan.jl + SPIRV.jl** backend route can be built in pure Julia on real
hardware, with the KHRONOS validation layer enabled, before any production
backend code is written. This directory is a **standalone probe project** —
its `Project.toml`/`Manifest.toml` are isolated from the repository root and
nothing here is a production backend (no placeholders, no Vetra core edits).

Status: **all probes pass** (Linux, host `flowx13`). Machine-readable results
live in [`evidence/`](evidence/); `test/runtests.jl` verifies them without a GPU.

## Pinned environment

| Component | Version / pin | Provenance (hashes in `evidence/p00_env.json`) |
|---|---|---|
| Julia (probe execution) | 1.11.9 | `juliaup` channel `1.11` |
| Vulkan.jl | **0.6.30** (declared compat `0.6`; latest 0.6.x) | registry, git tree in Manifest |
| VulkanCore | 1.3.1 | registry |
| SPIRV.jl | **0.6.11 @ git rev `218b33b21e5b23d7c3c34bb07f6c114723a5e193`** (reviewed pin) | git dependency in Manifest |
| SPIRV_Tools_jll | 2026.4.0+0 (spirv-val v2026.4) | artifact sha256 in p00 evidence |
| SHA | 0.7.0 | registry |
| System loader | `libvulkan.so.1.4.341` (`sha256 def4af45…`) | /usr/lib/x86_64-linux-gnu |
| Validation layer | built from source, tag `vulkan-sdk-1.4.363.1`, WSI disabled (`-DBUILD_WSI_XCB_SUPPORT=OFF -DBUILD_WSI_XLIB_SUPPORT=OFF -DBUILD_WSI_WAYLAND_SUPPORT=OFF`), prefix `/tmp/opencode/vvl/install` | `libVkLayer_khronos_validation.so sha256 5c77f945…` |

Devices seen (p10): NVIDIA GeForce RTX 3050 Ti Laptop GPU (API 1.4.351,
discrete — the probe target), AMD RADV RENOIR (1.4.335, integrated),
llvmpipe (1.4.335, CPU software ICD — *present*, not claimed as hardware proof).

## Probes

| Script | Result | Demonstrates |
|---|---|---|
| `scripts/p00_env.jl` | 7/7 | Pinned package set (incl. SPIRV rev), loader/ICD/layer inventory with sha256s, spirv-val provenance, external VVL layer recorded |
| `scripts/p10_loader_device.jl` | 6/6 | Loader dlopen, instance + validation layer enabled, device discovery (3 devices), graphics+compute queue, BDA-capable API level, R8G8B8A8 format feature check (`FORMAT_FEATURE_*` bits) |
| `scripts/p20_offscreen.jl` | 4/4 | 64×32 RGBA8 offscreen image: hand-derived upload → byte-exact readback (8192/8192), `cmd_clear_color_image` → byte-exact clear, 0 validation errors, deterministic cleanup (no double-free at GC) |
| `scripts/p30_compute.jl` | 10/10 | The full SPIRV.jl route: `@compute` of a Julia kernel → SPIR-V 1.6 → internal + external `spirv-val --target-env vulkan1.3` (vulkan1.2 negative control) → derived device features → BDA buffer upload (runtime `iters` + data) → dispatch with runtime push constants → **byte-exact readback vs an independently written Julia reference** (512/512, 512/512, 400/400 + untouched sentinel) → runtime-driven output changes between runs → 0 validation errors |
| `scripts/p40_bool_layers.jl` (+ `p40_child.jl`) | 12/12 | Upstream SPIRV.jl comment *"Validation layers seem to crash when `Bool` is returned"* — **not reproduced** on this stack: the Bool-returning module (`OpTypeFunction %bool`, `OpStore … Aligned 2`) creates pipelines, dispatches, and reads back byte-exact (true and false cases) under the KHRONOS layer with 0 validation errors/warnings; even the upstream `sizeof(Bool)=1` buffer sizing was accepted |
| `scripts/p50_errors.jl` (+ `p50_child.jl`) | 7/7 | Error paths: no device (`VK_DRIVER_FILES`→nothing ⇒ `VK_ERROR_INCOMPATIBLE_DRIVER` from `vkCreateInstance`), bogus device extension (`ERROR_EXTENSION_NOT_PRESENT`), unsupported format (`ERROR_FORMAT_NOT_SUPPORTED`, name + usage in the message); device-free precompile of Vulkan with `PRECOMPILE_DEVICE_FUNCTIONS` = `false` (workload skipped, succeeds) / `auto` (default: workload runs, no-driver failure caught, succeeds) / `true` (failure rethrown, precompile fails with a clear message) — install does **not** silently require a device |
| `scripts/p60_julia_matrix.jl` (+ `p60_child.jl`) | 4/4 | Julia version matrix (wrapper-level): 1.10.13 cannot use the pinned 1.11 environment (Pkg refuses the foreign manifest; SPIRV.jl declares `julia = "1.11"` — the shader route is unavailable on 1.10); 1.13.3 instantiates the pinned project and `using SPIRV, Vulkan` succeeds |

Shared helpers (`scripts/probe_common.jl`): check accumulator, JSON evidence
writer, debug-callback capture, instance/device/queue/memory/BDA-buffer
helpers on the Vulkan.jl 0.6.30 API, `run_capture` (sh -c based, see host
quirks), and `supported_features` (bounded retry — see flake below).

## Running

Build the validation layer once (no sudo; ~5 min):

```sh
cmake -S /tmp/opencode/vulkan-validation-layers \
  -B /tmp/opencode/vvl/build \
  -DCMAKE_INSTALL_PREFIX=/tmp/opencode/vvl/install \
  -DBUILD_WSI_XCB_SUPPORT=OFF -DBUILD_WSI_XLIB_SUPPORT=OFF -DBUILD_WSI_WAYLAND_SUPPORT=OFF \
  -DCMAKE_C_COMPILER=cc -DCMAKE_CXX_COMPILER=c++
cmake --install /tmp/opencode/vvl/build
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

Self-checks (verify the committed evidence; no GPU needed):

```sh
julia +1.11 --startup-file=no --project=lib/VetraVulkan/probe \
  lib/VetraVulkan/probe/test/runtests.jl
```

Full re-run + re-verify (regenerates all evidence first):

```sh
R040_RUN_PROBES=1 julia +1.11 --startup-file=no --project=lib/VetraVulkan/probe \
  lib/VetraVulkan/probe/test/runtests.jl
```

## Findings that constrain R010 backend work

1. **SPIRV.jl pointer indexing is 1-based** (`p[i]` → SPIR-V element `i-1`,
   confirmed against the emitted `OpAccessChain` indices). The p30 kernel
   originally treated buffer element 0 (the `iters` control word) as data and
   wrote `iters + acc` into `out[0]`; the kernel must skip the control word
   explicitly.
2. **Device features must be derived from the compiled module's declared
   capabilities**, plus: `variable_pointers` *and* `variable_pointers_storage_buffer`
   together (VUID 01431), and `maintenance4` when the module uses
   `OpExecutionMode LocalSizeId` (VUID 06434 — SPIRV.jl emits the `Id` form).
   With that set the KHRONOS layer reports **zero warnings/errors** on all
   probes.
3. **Emitted SPIR-V is version 1.6 ⇒ minimal target environment `vulkan1.3`**
   for `spirv-val --target-env` (vulkan1.2 is rejected — kept as a negative
   control in p30).
4. **Upstream "Bool crashes validation layers" comment does not reproduce**
   on Vulkan.jl 0.6.30 + KHRONOS layer 1.4.363.1 + SPIR-V 2026.4 tooling.
   Record as *not reproduced*, not as fixed; older layer/validator versions
   may still misbehave.
5. **`OpStore` of a bool is emitted with `Aligned 2`** (SPIR-V bool storage is
   4 bytes); both external spirv-val and the on-device layer accepted it, and
   the upstream 1-byte buffer sizing "worked" (first byte correct) — do not
   rely on it; size bool output buffers for 4-byte SPIR-V stores.
6. **Vulkan.jl 0.6.30 precompile without a device**: default
   `PRECOMPILE_DEVICE_FUNCTIONS = "auto"` succeeds (device workload failure is
   caught); the preference is set through the project's
   `LocalPreferences.toml` (`Vulkan.set_preferences!`) — this Pkg/Preferences
   version has no `Pkg.set_preference` and **no env-var override**.
7. **Transient pNext-chain flake**: `vkGetPhysicalDeviceFeatures2` returned a
   short chain once (Vulkan.jl `_load_next_chain` assertion), after a heavy
   sequence of instance creations. `ProbeCommon.supported_features` retries
   (bounded, AssertionError-only) and the probe is re-runnable.
8. **Handle ownership**: Vulkan.jl wrappers are refcounted; always release via
   `.destructor()` in reverse dependency order after `queue_wait_idle` — raw
   `destroy_*` while a wrapper is live double-destroys at GC (segfault).

## Host build quirks (this Julia installation)

The locally installed Julia builds (1.10.13 / 1.11.9 / 1.13.3) are stripped in
ways that shape the probe code — do not "fix" them by assuming stock Julia:

- `run_capture` shells out via `sh -c` with separate out/err files: native
  pipeline redirection loses child output in this build.
- `sh` is dash with a bug: multi-line `for … done` inside `sh -c "…"` fails
  with `word unexpected (expecting "do")` — keep generated scripts single-line.
- Missing/broken: `bool`, `readbytes`, `Pkg.version`, `Pkg.status`,
  `Pkg.set_preference`, 2-arg `Cmd(vec, env)`, `e.exit`, `getfield` with
  default, `2>&1` in backticks, `String(::Vector{String})`,
  `read(path, Vector{UInt8})`, `copy(a, b)` (file copy), `Base.copyfile`,
  `rmdir`, `Cmd(Vector{Any})`; `read(io, UInt8)` returns 1 byte (use
  `read!(io, preallocated)`); `1F` float literals broken (use `1f0`);
  `rm(dir; force=true)` does not recurse.
- String handling is unreliable for multibyte content: `length()` and
  character indexing misbehave on UTF-8 (e.g. `length("┌ x") == 3`).
  `test/runtests.jl` therefore parses evidence JSON **byte-wise**.
- Do-blocks can miscompile (closure lands as first argument) — `with_commands`
  takes its callback as an explicit argument.
- `import Vulkan: X` silently skips symbols that do not exist (e.g.
  `FORMAT_A8_UNORM` is not in the generated enum) — undefined symbols then
  fail at runtime with `UndefVarError`.

## Blocked / not verified

- **Windows, macOS, FreeBSD execution** — no such hosts available in this
  environment. The probes are Linux-specific in places (loader path,
  `icd.d`/layer manifest dirs, dash wrapper) and must be re-run there before
  R010 contracts can claim cross-platform validation.
- **Vulkan.jl 0.7.0** — not executed. SPIRV.jl 0.6.11 declares
  `compat Vulkan = "0.6"`, so 0.7 would need a recorded local patch
  (`0.7` uses `set_driver(:System/:Loader)` + `Vulkan_Loader_jll` instead of
  the `JULIA_VULKAN_*`/Preferences mechanism). The 0.6.30 stack passed every
  probe, so the comparison was unnecessary for R040's questions.
- llvmpipe/RADV devices were discovered but **not** used as probe targets
  (NVIDIA only); software-ICD shader behavior is unverified.

## Files

```
Project.toml / Manifest.toml   pinned isolated environment (uuid c35fa8e6-…)
src/VetraVulkanProbe.jl        trivial entry module so the project precompiles
scripts/probe_common.jl        shared helpers (checks, evidence, Vulkan API)
scripts/p00_env.jl … p60_julia_matrix.jl   probes
scripts/p40_child.jl, p50_child.jl, p60_child.jl   subprocess workers
evidence/*.json                machine-readable results (committed)
test/runtests.jl               self-checks over the evidence (GPU-free)
```
