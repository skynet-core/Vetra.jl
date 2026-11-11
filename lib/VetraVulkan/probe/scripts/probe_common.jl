"""
ProbeCommon: shared helpers for the R040 Vulkan.jl / SPIRV.jl compatibility spike.

- check accumulator + minimal JSON evidence writer (no extra dependencies)
- debug-callback message capture; severity classification uses the ACTUAL
  VK_DEBUG_UTILS_MESSAGE_SEVERITY_*_BIT_EXT enum values (regression-tested
  with vkSubmitDebugUtilsMessageEXT, see `synthetic_severity_regression`)
- instance/device/queue/memory/command helpers on the Vulkan.jl 0.6.x API
  (the declared-compatible stack for SPIRV.jl 0.6.11)
- deterministic handle release through `release` (= Base.finalize: the
  registered finalizer is invoked once and unregistered). Calling
  `h.destructor()` directly is UNSAFE here: it decrements the refcount but
  leaves the finalizer armed, so the GC later destroys a second time
  (underflow on the parent chain).
- safe PhysicalDeviceFeatures2 chain query built from probe-owned Refs.
  Vulkan.jl 0.6.30's `initialize(T, next...)` is unsound: `_initialize_core`
  drains the chain Refs (popfirst!) before `_initialize` returns, leaving
  raw pNext pointers dangling (see README "Recorded upstream defects").
"""
module ProbeCommon

using Logging
using UUIDs
using Pkg
using Vulkan
using Vulkan: Vk, VkCore, unwrap

import Vulkan:
  FORMAT_R8G8B8A8_UNORM,
  IMAGE_TYPE_2D, IMAGE_VIEW_TYPE_2D, IMAGE_TILING_OPTIMAL, IMAGE_LAYOUT_UNDEFINED, IMAGE_LAYOUT_GENERAL,
  IMAGE_USAGE_TRANSFER_SRC_BIT, IMAGE_USAGE_TRANSFER_DST_BIT, IMAGE_USAGE_COLOR_ATTACHMENT_BIT,
  IMAGE_ASPECT_COLOR_BIT, SAMPLE_COUNT_1_BIT,
  COMPONENT_SWIZZLE_R, COMPONENT_SWIZZLE_G, COMPONENT_SWIZZLE_B, COMPONENT_SWIZZLE_A,
  SHARING_MODE_EXCLUSIVE,
  BUFFER_USAGE_STORAGE_BUFFER_BIT, BUFFER_USAGE_SHADER_DEVICE_ADDRESS_BIT,
  BUFFER_USAGE_TRANSFER_SRC_BIT, BUFFER_USAGE_TRANSFER_DST_BIT,
  MEMORY_PROPERTY_DEVICE_LOCAL_BIT, MEMORY_PROPERTY_HOST_VISIBLE_BIT, MEMORY_PROPERTY_HOST_COHERENT_BIT,
  MEMORY_ALLOCATE_DEVICE_ADDRESS_BIT,
  COMMAND_BUFFER_LEVEL_PRIMARY,
  QUEUE_GRAPHICS_BIT, QUEUE_COMPUTE_BIT, QUEUE_TRANSFER_BIT,
  ACCESS_TRANSFER_READ_BIT, ACCESS_TRANSFER_WRITE_BIT,
  ACCESS_HOST_READ_BIT, ACCESS_HOST_WRITE_BIT,
  ACCESS_SHADER_READ_BIT, ACCESS_SHADER_WRITE_BIT,
  PIPELINE_STAGE_TRANSFER_BIT, PIPELINE_STAGE_VERTEX_SHADER_BIT, PIPELINE_STAGE_FRAGMENT_SHADER_BIT,
  PIPELINE_STAGE_COLOR_ATTACHMENT_OUTPUT_BIT, PIPELINE_STAGE_EARLY_FRAGMENT_TESTS_BIT,
  PIPELINE_STAGE_COMPUTE_SHADER_BIT, PIPELINE_STAGE_HOST_BIT,
  IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL,
  ImageSubresourceRange, ImageMemoryBarrier, MemoryBarrier, BufferMemoryBarrier,
  DEBUG_UTILS_MESSAGE_SEVERITY_VERBOSE_BIT_EXT, DEBUG_UTILS_MESSAGE_SEVERITY_INFO_BIT_EXT,
  DEBUG_UTILS_MESSAGE_SEVERITY_WARNING_BIT_EXT, DEBUG_UTILS_MESSAGE_SEVERITY_ERROR_BIT_EXT,
  DEBUG_UTILS_MESSAGE_TYPE_GENERAL_BIT_EXT, DEBUG_UTILS_MESSAGE_TYPE_VALIDATION_BIT_EXT,
  DEBUG_UTILS_MESSAGE_TYPE_PERFORMANCE_BIT_EXT

const LAYER_VALIDATION = "VK_LAYER_KHRONOS_validation"
const EXT_DEBUG_UTILS = "VK_EXT_debug_utils"
const EXT_VALIDATION_FEATURES = "VK_EXT_validation_features"

# Severity bits as the callback actually receives them. Derived from the
# enum values, not hardcoded: synthetic_severity_regression proves the
# callback delivers exactly these.
const SEV_VERBOSE  = Int(DEBUG_UTILS_MESSAGE_SEVERITY_VERBOSE_BIT_EXT.val)   # 1
const SEV_INFO     = Int(DEBUG_UTILS_MESSAGE_SEVERITY_INFO_BIT_EXT.val)     # 16
const SEV_WARNING  = Int(DEBUG_UTILS_MESSAGE_SEVERITY_WARNING_BIT_EXT.val)  # 256
const SEV_ERROR    = Int(DEBUG_UTILS_MESSAGE_SEVERITY_ERROR_BIT_EXT.val)    # 4096

# ---------------------------------------------------------------------------
# Self-checks and evidence
# ---------------------------------------------------------------------------

const CHECKS = Vector{Tuple{String, Bool, String}}()
const _CAP = Ref{Vector{Tuple{Int, Int, String}}}([])

"""Capture a debug-utils callback message. `severity`/`msg_type` arrive as the
raw bit values the loader passes (see the regression in p00 evidence)."""
function capture_callback(severity::UInt32, msg_type::UInt32, p::Ptr{VkCore.VkDebugUtilsMessengerCallbackDataEXT}, u)
  p == C_NULL && return UInt32(0)
  d = unsafe_load(p)
  push!(_CAP[], (Int(severity), Int(msg_type), unsafe_string(d.pMessage)))
  # Loader device-sorting chatter is not a finding; keep it out of the logs.
  unsafe_string(d.pMessageIdName) == "Loader Message" && return UInt32(0)
  write(stderr, "[vk ", unsafe_string(d.pMessageIdName), "] ", unsafe_string(d.pMessage), "\n")
  flush(stderr)
  UInt32(0)
end

function check(name, cond, detail::AbstractString = "")
  ok = cond ? true : false
  push!(CHECKS, (name, ok, detail))
  println((ok ? "  PASS  " : "  FAIL  "), name, isempty(detail) ? "" : "  | " * detail)
  ok
end

function reset_checks()
  empty!(CHECKS)
  empty!(_CAP[])
  nothing
end

checks() = CHECKS

"""Classify a raw callback severity value against the ACTUAL enum bits
(VK_DEBUG_UTILS_MESSAGE_SEVERITY_*_BIT_EXT). The old probe hardcoded
1/2/4/8; the real values are 1/16/256/4096, so every message was
mis-bucketed and all '0 errors' claims were void."""
function classify(sev::Int)
  (sev & SEV_ERROR) != 0 && return :error
  (sev & SEV_WARNING) != 0 && return :warning
  (sev & SEV_INFO) != 0 && return :info
  (sev & SEV_VERBOSE) != 0 && return :verbose
  :none
end

validation_errors() = [m for m in _CAP[] if classify(m[1]) == :error]
validation_warnings() = [m for m in _CAP[] if classify(m[1]) == :warning]
validation_messages() = _CAP[]

"""True when no validation ERROR or WARNING message was captured.
Call it AFTER resource cleanup + GC.gc() so destruction-time messages are
counted too. INFO/VERBOSE chatter is recorded in evidence but not gated."""
validation_clean() = isempty(validation_errors()) && isempty(validation_warnings())

"""Evidence block: all captured messages with their actual severity values."""
validation_evidence() = Dict(
  "errors" => [Dict("severity" => m[1], "id" => m[2], "message" => m[3]) for m in validation_errors()],
  "warnings" => [Dict("severity" => m[1], "id" => m[2], "message" => m[3]) for m in validation_warnings()],
  "info_verbose" => [Dict("severity" => m[1], "id" => m[2], "message" => m[3]) for m in _CAP[] if m[1] < SEV_WARNING],
  "n_messages" => length(_CAP[]),
  "severity_bits" => Dict("verbose" => SEV_VERBOSE, "info" => SEV_INFO, "warning" => SEV_WARNING, "error" => SEV_ERROR))

"""Regression for the severity classification: submit one synthetic message
per severity through vkSubmitDebugUtilsMessageEXT and verify the callback
received the actual enum value and the error/warning buckets classify it
correctly (positive + negative controls). Requires an instance with the
debug-utils extension and a live messenger. Records checks."""
function synthetic_severity_regression(inst)
  res = Dict{String, Any}()
  # the per-severity window is owned by this regression, but the caller's
  # capture is preserved (restored in the finally, even on failure)
  saved = copy(_CAP[])
  empty!(_CAP[])
  try
    for (name, sev) in (("verbose", DEBUG_UTILS_MESSAGE_SEVERITY_VERBOSE_BIT_EXT),
                        ("info", DEBUG_UTILS_MESSAGE_SEVERITY_INFO_BIT_EXT),
                        ("warning", DEBUG_UTILS_MESSAGE_SEVERITY_WARNING_BIT_EXT),
                        ("error", DEBUG_UTILS_MESSAGE_SEVERITY_ERROR_BIT_EXT))
      empty!(_CAP[])
      data = Vulkan._DebugUtilsMessengerCallbackDataEXT(9001, "synthetic-sev-$name", String[], String[], String[]; message_id_name = "R040_SYN")
      GC.@preserve data begin
        Vulkan._submit_debug_utils_message_ext(inst, sev, DEBUG_UTILS_MESSAGE_TYPE_VALIDATION_BIT_EXT, data)
      end
      got = _CAP[]
      received = length(got) == 1 && got[1][3] == "synthetic-sev-$name" && got[1][1] == Int(sev.val)
      in_err = !isempty(validation_errors())
      in_warn = !isempty(validation_warnings())
      res[name] = Dict("received" => received, "raw_severity" => Int(sev.val), "in_error_bucket" => in_err, "in_warning_bucket" => in_warn)
      empty!(_CAP[])
    end
    check("synthetic regression: VERBOSE captured with raw value $SEV_VERBOSE", res["verbose"]["received"] && res["verbose"]["in_error_bucket"] === false && res["verbose"]["in_warning_bucket"] === false)
    check("synthetic regression: INFO captured with raw value $SEV_INFO", res["info"]["received"] && res["info"]["in_error_bucket"] === false && res["info"]["in_warning_bucket"] === false)
    check("synthetic regression: WARNING captured with raw value $SEV_WARNING", res["warning"]["received"] && res["warning"]["in_warning_bucket"] && res["warning"]["in_error_bucket"] === false)
    check("synthetic regression: ERROR captured with raw value $SEV_ERROR", res["error"]["received"] && res["error"]["in_error_bucket"])
  finally
    _CAP[] = saved
  end
  res
end

"""Minimal JSON writer for the evidence dicts (String/Int/Bool/Dict/Vector/Nothing)."""
function jesc(s::AbstractString)
  parts = String[]
  for c in s
    if c == '"'
      push!(parts, "\\\"")
    elseif c == '\\'
      push!(parts, "\\\\")
    elseif c == '\n'
      push!(parts, "\\n")
    elseif c == '\r'
      push!(parts, "\\r")
    elseif c == '\t'
      push!(parts, "\\t")
    elseif c < ' '
      push!(parts, "\\u" * lpad(string(codepoint(c); base = 16), 4, '0'))
    else
      push!(parts, string(c))
    end
  end
  join(parts)
end


function jval(x, ind)
  pad = " "^(2 * (ind + 1))
  pad0 = "  "^ind
  if x isa AbstractString
    return "\"" * jesc(x) * "\""
  elseif x isa Bool
    return x ? "true" : "false"
  elseif x === nothing
    return "null"
  elseif x isa Integer
    return string(x)
  elseif x isa AbstractFloat
    return isfinite(x) ? string(x) : "null"
  elseif x isa AbstractVector
    isempty(x) && return "[]"
    lines = [pad * jval(v, ind + 1) for v in x]
    return "[\n" * join(lines, ",\n") * "\n" * pad0 * "]"
  elseif x isa AbstractDict
    isempty(x) && return "{}"
    lines = [pad * "\"" * jesc(string(k)) * "\": " * jval(v, ind + 1) for (k, v) in pairs(x)]
    return "{\n" * join(lines, ",\n") * "\n" * pad0 * "}"
  else
    return "\"" * jesc(string(x)) * "\""
  end
end

function write_evidence(path, data::AbstractDict)
  p = dirname(abspath(path))
  isdir(p) || mkdir(p)
  open(path, "w") do io
    println(io, jval(data, 0))
  end
  abspath(path)
end

"""Run a Cmd and capture (stdout, stderr, exit_code) with the standard
run/pipeline/IOBuffer machinery. `env` pairs are ADDED to the inherited
environment (addenv): never replace it, or PATH/LD_LIBRARY_PATH/VK_LAYER_PATH
disappear and the child (or its no-device assertion) is not controlled."""
function run_capture(cmd::Cmd; env::Vector{Pair{String, String}} = Pair{String, String}[])
  c = cmd
  for p in env
    c = addenv(c, p)
  end
  out = IOBuffer(); err = IOBuffer()
  proc = run(pipeline(ignorestatus(c), stdout = out, stderr = err))
  seekstart(out); ostr = read(out, String)
  seekstart(err); estr = read(err, String)
  (chomp(ostr), estr, proc.exitcode)
end

"""Run a JLL-provided tool. `jllcmd.env` is a Vector{String} snapshot of the
inherited env with artifact paths merged in; each entry is re-applied with
addenv so the child environment is the parent's plus the artifact paths."""
function run_jll(jllcmd::Cmd, args::Vector{String})
  envpairs = Pair{String, String}[]
  for x in jllcmd.env
    kv = split(x, "=", limit = 2)
    length(kv) == 2 && push!(envpairs, Pair(kv[1], kv[2]))
  end
  exec = getfield(jllcmd, :exec)
  run_capture(Cmd(vcat(exec, args)); env = envpairs)
end

"""Resolve the EXACT depot source dir for a package pinned in `manifest_path`.

The depot directory name is `Base.version_slug(uuid, tree_sha1)` — a hash of
the package UUID plus its git tree SHA1 (registry `tree_hash`, git
`git_tree_sha1`), NOT the version string. Two git revisions can share a
version; only the tree hash pins the exact source. Returns a named tuple
`(dir, slug, version, tree_sha1, git_rev)` with `dir=nothing` when no depot
holds that exact checkout. `skip_first_depot` lets a probe running in an
isolated temp first-depot resolve against the read-through depots."""
function manifest_source_dir(manifest_path::AbstractString, name::AbstractString; skip_first_depot = false)
  man = Pkg.TOML.parsefile(manifest_path)
  e = man["deps"][name][1]
  uuid = UUID(e["uuid"])
  tree = e["git-tree-sha1"]
  sha = Base.SHA1(UInt8[parse(UInt8, tree[i:i+1]; base = 16) for i in 1:2:40])
  slug = Base.version_slug(uuid, sha)
  depots = skip_first_depot ? DEPOT_PATH[2:end] : DEPOT_PATH
  found = nothing
  for depot in depots
    p = joinpath(depot, "packages", name, slug)
    isdir(p) && (found = p)
  end
  (dir = found, slug = slug, version = e["version"], tree_sha1 = tree,
   git_rev = get(e, "repo-rev", ""))
end

# ---------------------------------------------------------------------------
# Instance / device
# ---------------------------------------------------------------------------

instance_layers() = [l.layer_name for l in unwrap(Vulkan.enumerate_instance_layer_properties())]
instance_extensions() = [e.extension_name for e in unwrap(Vulkan.enumerate_instance_extension_properties())]

"""Create an instance + debug messenger that captures messages into
`validation_errors()`/`validation_warnings()`.
With `validation=true` the KHRONOS layer AND the messenger are REQUIRED:
a missing layer or debug extension errors out (no silent downgrade — an
unvalidated run must never masquerade as a validated one).
With `sync_validation=true`, VALIDATION_FEATURE_ENABLE_SYNCHRONIZATION_
VALIDATION is requested. `VK_EXT_validation_features` is a LAYER-PROVIDED
instance extension (not core-promoted), so it is enumerated under the
KHRONOS layer and enabled by name, with the VkValidationFeaturesEXT pNext
chain carried at instance creation. (It is deprecated by `VK_EXT_layer_settings`;
this pinned layer 1.4.363 still provides it.)
Returns (instance, messenger, layers_enabled)."""
function make_instance(; validation = false, sync_validation = false, api = v"1.3")
  layers = String[]
  exts = String[EXT_DEBUG_UTILS]
  if validation
    LAYER_VALIDATION in instance_layers() ||
      error("VK_LAYER_KHRONOS_validation is not discoverable: set VK_LAYER_PATH to a validation-layer install (README recipe) and LD_LIBRARY_PATH to its lib dir. Refusing to run unvalidated.")
    EXT_DEBUG_UTILS in instance_extensions() ||
      error("VK_EXT_debug_utils is not available: the messenger required together with validation is impossible on this loader.")
    push!(layers, LAYER_VALIDATION)
  end
  next = C_NULL
  if sync_validation
    layer_exts = [e.extension_name for e in
                  unwrap(Vulkan.enumerate_instance_extension_properties(; layer_name = LAYER_VALIDATION))]
    EXT_VALIDATION_FEATURES in layer_exts ||
      error("VK_EXT_validation_features is not provided by the KHRONOS layer here (superseded by VK_EXT_layer_settings in newer layers); cannot request sync validation. Refusing to run.")
    push!(exts, EXT_VALIDATION_FEATURES)
    next = Vulkan.ValidationFeaturesEXT([Vulkan.VALIDATION_FEATURE_ENABLE_SYNCHRONIZATION_VALIDATION_EXT], String[])
  end
  inst = Instance(layers, exts; application_info = ApplicationInfo(v"0.1", v"1.0", api), next = next)
  local msg
  try
    msg = DebugUtilsMessengerEXT(inst,
      DEBUG_UTILS_MESSAGE_SEVERITY_VERBOSE_BIT_EXT | DEBUG_UTILS_MESSAGE_SEVERITY_INFO_BIT_EXT |
        DEBUG_UTILS_MESSAGE_SEVERITY_WARNING_BIT_EXT | DEBUG_UTILS_MESSAGE_SEVERITY_ERROR_BIT_EXT,
      DEBUG_UTILS_MESSAGE_TYPE_GENERAL_BIT_EXT | DEBUG_UTILS_MESSAGE_TYPE_VALIDATION_BIT_EXT |
        DEBUG_UTILS_MESSAGE_TYPE_PERFORMANCE_BIT_EXT,
      @cfunction(capture_callback, UInt32, (UInt32, UInt32, Ptr{VkCore.VkDebugUtilsMessengerCallbackDataEXT}, Ptr{Cvoid})))
  catch
    release(inst)
    rethrow()
  end
  return (inst, msg, layers)
end

physical_devices(inst) = unwrap(Vulkan.enumerate_physical_devices(inst))

function device_props(ph)
  unwrap(Vulkan.get_physical_device_properties(ph))
end

"""First physical device matching `name_substring` (case-insensitive), else the
first device. Returns (physical_device, properties). Errors with a meaningful
message when no device exists."""
function pick_device(inst; name_substring = nothing, device_type = nothing)
  phs = physical_devices(inst)
  isempty(phs) && error("No Vulkan physical devices found on this host: the loader is present but discovered zero ICDs. Install a Vulkan driver (or a software ICD such as Lavapipe) or point VK_DRIVER_FILES/VK_ICD_FILENAMES at one.")
  cands = phs
  if !isnothing(name_substring)
    cands = [ph for ph in phs if occursin(Regex(name_substring, "i"), device_props(ph).device_name)]
  end
  if !isnothing(device_type)
    cands = [ph for ph in cands if device_props(ph).device_type == device_type]
  end
  isempty(cands) && error("No physical device matching $(name_substring); available: ", join([device_props(ph).device_name for ph in phs], ", "))
  ph = cands[1]
  return ph, device_props(ph)
end

"""Create a logical device with an explicit feature chain.
`f10/f11/f12/f13` are Symbol lists of Vulkan feature names. Device-level
layers are deprecated since 1.1 and are NOT passed: the KHRONOS layer is
enabled at the instance instead."""
function make_device(inst, ph; f10 = Symbol[], f11 = Symbol[], f12 = Symbol[], f13 = Symbol[],
                     extensions = String[], qi = 0, priorities = [1.0f0])
  f13s = PhysicalDeviceVulkan13Features(f13...; next = C_NULL)
  f12s = PhysicalDeviceVulkan12Features(f12...; next = f13s)
  f11s = PhysicalDeviceVulkan11Features(f11...; next = f12s)
  f10s = PhysicalDeviceFeatures(f10...)
  base = PhysicalDeviceFeatures2(f10s; next = f11s)
  dev = Device(ph, [DeviceQueueCreateInfo(UInt32(qi), priorities)], String[], extensions; next = base)
  dev
end

# ---------------------------------------------------------------------------
# Safe features2 chain query (owned Refs — no reliance on `Vulkan.initialize`)
# ---------------------------------------------------------------------------

const _F2  = VkCore.VkPhysicalDeviceFeatures2
const _F11 = VkCore.VkPhysicalDeviceVulkan11Features
const _F12 = VkCore.VkPhysicalDeviceVulkan12Features
const _F13 = VkCore.VkPhysicalDeviceVulkan13Features
const _FE  = VkCore.VkPhysicalDeviceFeatures

"""Own the Refs for the Features2 -> 1.1 -> 1.2 -> 1.3 query chain.
Returned Refs must be kept alive (GC.@preserve) across the query."""
function feature_chain_refs()
  r13 = Ref(_F13(VkCore.VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_VULKAN_1_3_FEATURES, Ptr{Cvoid}(C_NULL), ntuple(_ -> UInt32(0), 15)...))
  r12 = Ref(_F12(VkCore.VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_VULKAN_1_2_FEATURES, Base.unsafe_convert(Ptr{Cvoid}, r13), ntuple(_ -> UInt32(0), 47)...))
  r11 = Ref(_F11(VkCore.VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_VULKAN_1_1_FEATURES, Base.unsafe_convert(Ptr{Cvoid}, r12), ntuple(_ -> UInt32(0), 12)...))
  r2 = Ref(_F2(VkCore.VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_FEATURES_2, Base.unsafe_convert(Ptr{Cvoid}, r11), _FE(ntuple(_ -> UInt32(0), 55)...)))
  (r2, r11, r12, r13)
end

"""Query supported features SAFELY: probe-owned Refs, raw
vkGetPhysicalDeviceFeatures2, GC.@preserve around the query, no retry loop.
Returns the high-level chain (consumable by SPIRV.SupportedFeatures via
Vk.unchain) plus the raw per-struct readbacks.
`stress` re-queries after GC.gc() `stress` more times and errors if any
derived feature bit drifts (that would indicate a dangling pNext read).
Derived bits: shaderInt64 (1.0), variablePointers (1.1), bufferDeviceAddress
and vulkanMemoryModel (1.2), maintenance4 (1.3)."""
function query_supported_features(ph; stress = 0)
  (r2, r11, r12, r13) = feature_chain_refs()
  derived() = (Int(r2[].features.shaderInt64), Int(r11[].variablePointers),
               Int(r12[].bufferDeviceAddress), Int(r12[].vulkanMemoryModel),
               Int(r13[].maintenance4))
  GC.@preserve r2 r11 r12 r13 begin
    base = nothing
    for i in 0:stress
      i > 0 && GC.gc()
      VkCore.vkGetPhysicalDeviceFeatures2(ph.vks, Base.unsafe_convert(Ptr{_F2}, r2))
      if i == 0
        base = derived()
      else
        derived() == base ||
          error("GC stress: feature query drifted at iteration $i: $(derived()) != $(base) (dangling pNext chain?)")
      end
    end
    # Unwrap into the value-based high-level chain while the Refs are alive.
    features2 = Vulkan.PhysicalDeviceFeatures2(
      Vulkan._PhysicalDeviceFeatures2(r2[], Any[Base.unsafe_convert(Ptr{Cvoid}, r11)]),
      Vulkan.PhysicalDeviceVulkan11Features, Vulkan.PhysicalDeviceVulkan12Features, Vulkan.PhysicalDeviceVulkan13Features)
    (features2 = features2, f10 = r2[].features, f11 = r11[], f12 = r12[], f13 = r13[], gc_stress = (base, stress))
  end
end

"""Map the SPIR-V capabilities a module declares to the Vulkan device features
required to run it. Unknown capability -> explicit error (a silent ignore
would create a device that cannot run the module). Returns (f10, f11, f12, f13)."""
function features_from_capabilities(capnames::Vector{String})
  f10 = Set{Symbol}(); f11 = Set{Symbol}(); f12 = Set{Symbol}(); f13 = Set{Symbol}()
  for c in capnames
    if c == "Int64"
      push!(f10, :shader_int_64)
    elseif c == "Float64"
      push!(f10, :shader_float_64)
    elseif c == "VariablePointers"
      push!(f11, :variable_pointers)
    elseif c == "PhysicalStorageBufferAddresses"
      push!(f12, :buffer_device_address)
    elseif c == "VulkanMemoryModel"
      push!(f12, :vulkan_memory_model)
    elseif c == "Int8"
      push!(f12, :shader_int_8)
    elseif c == "Float16"
      push!(f12, :shader_float_16)
    else
      error("capability $c has no mapped Vulkan device feature in this probe; extend features_from_capabilities before enabling it")
    end
  end
  (collect(f10), collect(f11), collect(f12), collect(f13))
end

"""Assert the device actually supports the features this probe requests.
Call BEFORE make_device so an unsupported device fails with a clear message
instead of a device-creation error deep in the wrapper."""
function assert_features_supported(sup; need10 = Symbol[], need11 = Symbol[], need12 = Symbol[], need13 = Symbol[])
  raw = Dict{Symbol, Int}(
    :shader_int_64 => Int(sup.f10.shaderInt64), :shader_float_64 => Int(sup.f10.shaderFloat64),
    :variable_pointers => Int(sup.f11.variablePointers),
    :buffer_device_address => Int(sup.f12.bufferDeviceAddress), :vulkan_memory_model => Int(sup.f12.vulkanMemoryModel),
    :shader_int_8 => Int(sup.f12.shaderInt8), :shader_float_16 => Int(sup.f12.shaderFloat16),
    :maintenance4 => Int(sup.f13.maintenance4))
  missing = Symbol[]
  for s in vcat(need10, need11, need12, need13)
    get(raw, s, 0) == 0 && push!(missing, s)
  end
  isempty(missing) || error("device does not support required feature(s): $missing (queried: $raw)")
  true
end

function queue_family(ph, flags)
  Vulkan.find_queue_family(ph, flags)
end

"""Index of a device memory type usable with `bits` satisfying `props` (0-based)."""
function memory_index(ph, bits::Integer, props)
  mp = unwrap(Vulkan.get_physical_device_memory_properties(ph))
  for i in 1:mp.memory_type_count
    ((Int(bits) >> (i - 1)) & 1 == 1) || continue
    if mp.memory_types[i].property_flags & props == props
      return i - 1
    end
  end
  error("No device memory type for bits=$(bits) props=$(props)")
end

# ---------------------------------------------------------------------------
# Handle release (refcount model)
# ---------------------------------------------------------------------------

"""Deterministically release a handle: invoke the registered finalizer once
and unregister it, so the GC cannot run it again. The refcount model then
propagates to the parent exactly once. Release in reverse creation order."""
release(h) = Base.finalize(h)

"""Current refcount of a handle (nothing if the field is absent)."""
function refcount(h)
  try
    getfield(h, :refcount)[]
  catch
    nothing
  end
end

"""True if the refcount has not wrapped (a UInt underflow would read near
2^64). Call after release sequences; an underflow means the handle was
released more times than its parents allow."""
function refcount_ok(h)
  rc = refcount(h)
  isnothing(rc) && return true
  rc < (UInt(1) << 62)
end

# ---------------------------------------------------------------------------
# Buffers (BDA-capable), memory, commands
# ---------------------------------------------------------------------------

"""Create a host-coherent transfer buffer (no device-address usage).
Returns (buffer, memory). On partial failure the created handles are
released (reverse creation order) and the error is rethrown — no leaked
refcount on the parent device."""
function plain_buffer(dev, ph, nbytes; usage = BUFFER_USAGE_TRANSFER_SRC_BIT | BUFFER_USAGE_TRANSFER_DST_BIT)
  buf = Buffer(dev, nbytes, usage, SHARING_MODE_EXCLUSIVE, [0])
  mem = nothing
  try
    req = unwrap(Vulkan.get_buffer_memory_requirements(dev, buf))
    idx = memory_index(ph, req.memory_type_bits, MEMORY_PROPERTY_HOST_VISIBLE_BIT | MEMORY_PROPERTY_HOST_COHERENT_BIT)
    mem = DeviceMemory(dev, req.size, idx)
    unwrap(Vulkan.bind_buffer_memory(dev, buf, mem, 0))
  catch
    mem !== nothing && release(mem)
    release(buf)
    rethrow()
  end
  (buffer = buf, memory = mem)
end

"""Create a host-coherent storage buffer with the shader-device-address usage.
Returns (buffer, memory, device_address). On partial failure the created
handles are released (reverse creation order) and the error is rethrown."""
function bda_buffer(dev, ph, nbytes)
  buf = Buffer(dev, nbytes, BUFFER_USAGE_STORAGE_BUFFER_BIT | BUFFER_USAGE_SHADER_DEVICE_ADDRESS_BIT, SHARING_MODE_EXCLUSIVE, [0])
  mem = nothing
  try
    req = unwrap(Vulkan.get_buffer_memory_requirements(dev, buf))
    idx = memory_index(ph, req.memory_type_bits, MEMORY_PROPERTY_HOST_VISIBLE_BIT | MEMORY_PROPERTY_HOST_COHERENT_BIT)
    mem = DeviceMemory(dev, req.size, idx; next = MemoryAllocateFlagsInfo(UInt32(0); flags = MEMORY_ALLOCATE_DEVICE_ADDRESS_BIT))
    unwrap(Vulkan.bind_buffer_memory(dev, buf, mem, 0))
    addr = unwrap(Vulkan.get_buffer_device_address(dev, BufferDeviceAddressInfo(buf)))
    (buffer = buf, memory = mem, address = addr)
  catch
    mem !== nothing && release(mem)
    release(buf)
    rethrow()
  end
end

"""Map memory, run `f(mapped_bytes)`, unmap, and return `f`'s result.
The unmap happens even if `f` throws (a mapped range left open breaks later
map calls)."""
function map_with(dev, mem, nbytes, f)
  ptr = unwrap(Vulkan.map_memory(dev, mem, 0, nbytes))
  try
    f(Base.unsafe_wrap(Vector{UInt8}, Ptr{UInt8}(ptr), nbytes, own = false))
  finally
    Vulkan.unmap_memory(dev, mem)
  end
end

"""Copy `data` into a mapped device memory region."""
write_mem(dev, mem, data::Vector{UInt8}) = map_with(dev, mem, length(data), m -> copyto!(m, data))

"""Read `nbytes` from a mapped device memory region."""
read_mem(dev, mem, nbytes) = map_with(dev, mem, nbytes, m -> copy(m))

"""One-shot vkCmdPipelineBarrier with a single VkMemoryBarrier (Vulkan 1.0
form: stage masks are passed to the call, access masks to the barrier)."""
function memory_barrier!(cb, src_stage, dst_stage, src_access, dst_access)
  mb = MemoryBarrier(; src_access_mask = src_access, dst_access_mask = dst_access)
  Vulkan.cmd_pipeline_barrier(cb, [mb], BufferMemoryBarrier[], ImageMemoryBarrier[];
                              src_stage_mask = src_stage, dst_stage_mask = dst_stage)
  nothing
end

"""Record `f(cb)` into a primary command buffer, submit it and wait for idle.
Releases the queue, command buffer and pool through `release` in a finally
block, so error paths do not leak or double-free. Submission boundaries are
synchronized by the queue_wait_idle here; DEVICE-side ordering (host writes
vs GPU reads, GPU writes vs host reads, transfer vs compute) must be
expressed with explicit barriers — queue idleness is never assumed as a
memory dependency inside a submission."""
function with_commands(dev, qi, f)
  pool = CommandPool(dev, qi)
  cb = nothing
  q = nothing
  try
    cbs = unwrap(Vulkan.allocate_command_buffers(dev, CommandBufferAllocateInfo(pool, COMMAND_BUFFER_LEVEL_PRIMARY, 1)))
    (cb,) = cbs
    unwrap(Vulkan.begin_command_buffer(cb, CommandBufferBeginInfo()))
    f(cb)
    unwrap(Vulkan.end_command_buffer(cb))
    q = unwrap(Vulkan.get_device_queue(dev, qi, 0))
    unwrap(Vulkan.queue_submit(q, [SubmitInfo(Semaphore[], PipelineStageFlag[], [cb], Semaphore[])]))
    unwrap(Vulkan.queue_wait_idle(q))
  finally
    q !== nothing && release(q)
    cb !== nothing && release(cb)
    release(pool)
    refcount_ok(pool) || error("CommandPool refcount wrapped after cleanup")
  end
  nothing
end

"""Bounded synchronization-validation control (positive + negative).
Two `vkCmdFillBuffer` writes to the same range in ONE command buffer with no
barrier between them — a genuine WRITE_AFTER_WRITE hazard. Runs on its own
instance/device, but that instance shares the global `_CAP` with the
caller's workload: the caller's capture is saved up front and restored in
the finally (even on failure), so the control's intentional hazard errors
never erase or contaminate the workload's validation status. The count is
taken from the control's own window before the restore. Returns the number
of WRITE_AFTER_WRITE errors seen."""
function sync_hazard_control(; sync_validation)
  saved = copy(_CAP[])
  empty!(_CAP[])
  inst = nothing; msg = nothing; dev = nothing; r = nothing; waw = 0
  try
    (inst, msg, _layers) = make_instance(; validation = true, sync_validation = sync_validation)
    ph, _p = pick_device(inst; name_substring = "NVIDIA GeForce")
    qi = queue_family(ph, QUEUE_COMPUTE_BIT)
    dev = make_device(inst, ph; qi = qi)
    r = plain_buffer(dev, ph, 256)
    with_commands(dev, qi, (cb) -> begin
      Vulkan.cmd_fill_buffer(cb, r.buffer, 0, 256, UInt32(1))
      Vulkan.cmd_fill_buffer(cb, r.buffer, 0, 256, UInt32(2))
      nothing
    end)
  finally
    # release exactly once, on every path: buffer before memory, then device,
    # then the messenger (still alive through destruction so destruction-time
    # messages are captured), then the instance; GC runs before the caller's
    # capture is restored
    if r !== nothing
      release(r.buffer)
      release(r.memory)
    end
    dev !== nothing && release(dev)
    msg !== nothing && release(msg)
    inst !== nothing && release(inst)
    GC.gc()
    waw = count(m -> occursin("WRITE_AFTER_WRITE", m[3]), validation_errors())
    _CAP[] = saved
  end
  waw
end

# ---------------------------------------------------------------------------
# Offscreen images
# ---------------------------------------------------------------------------

"""Create a 2D RGBA8 image usable for transfer + (optionally) color attachment.
Returns (image, view, memory)."""
function offscreen_image(dev, ph, w, h; usage = IMAGE_USAGE_TRANSFER_SRC_BIT | IMAGE_USAGE_TRANSFER_DST_BIT, fmt = FORMAT_R8G8B8A8_UNORM)
  # Verify the exact (format, 2D, optimal, usage) combination the device supports.
  try
    unwrap(Vulkan.get_physical_device_image_format_properties(ph, fmt, IMAGE_TYPE_2D, IMAGE_TILING_OPTIMAL, usage))
  catch e
    error("Format $(fmt) with 2D/optimal/$(usage) is not supported on this device: $(sprint(showerror, e))")
  end
  img = Image(dev, IMAGE_TYPE_2D, fmt, Extent3D(UInt32(w), UInt32(h), 1), 1, 1, SAMPLE_COUNT_1_BIT,
              IMAGE_TILING_OPTIMAL, usage, SHARING_MODE_EXCLUSIVE, [0], IMAGE_LAYOUT_UNDEFINED)
  mem = nothing
  view = nothing
  try
    req = unwrap(Vulkan.get_image_memory_requirements(dev, img))
    idx = memory_index(ph, req.memory_type_bits, MEMORY_PROPERTY_DEVICE_LOCAL_BIT)
    mem = DeviceMemory(dev, req.size, idx)
    unwrap(Vulkan.bind_image_memory(dev, img, mem, 0))
    # The view must be created after the image memory is bound (VUID 01020).
    view = ImageView(dev, img, IMAGE_VIEW_TYPE_2D, fmt,
                     ComponentMapping(COMPONENT_SWIZZLE_R, COMPONENT_SWIZZLE_G, COMPONENT_SWIZZLE_B, COMPONENT_SWIZZLE_A),
                     ImageSubresourceRange(IMAGE_ASPECT_COLOR_BIT, 0, 1, 0, 1))
  catch
    view !== nothing && release(view)
    mem !== nothing && release(mem)
    release(img)
    rethrow()
  end
  (image = img, view = view, memory = mem)
end

"""Transition an image (all layers, mip 0) from UNDEFINED to GENERAL so it can
be used for transfers, clears and (via barriers) rendering."""
function to_general_layout(dev, qi, img, w, h)
  barrier = ImageMemoryBarrier(ACCESS_TRANSFER_READ_BIT | ACCESS_TRANSFER_WRITE_BIT,
                               ACCESS_TRANSFER_READ_BIT | ACCESS_TRANSFER_WRITE_BIT,
                               IMAGE_LAYOUT_UNDEFINED, IMAGE_LAYOUT_GENERAL,
                               UInt32(qi), UInt32(qi), img,
                               ImageSubresourceRange(IMAGE_ASPECT_COLOR_BIT, 0, 1, 0, 1))
  with_commands(dev, qi, (cb) -> Vulkan.cmd_pipeline_barrier(cb,
    MemoryBarrier[], BufferMemoryBarrier[], [barrier];
    src_stage_mask = PIPELINE_STAGE_TRANSFER_BIT, dst_stage_mask = PIPELINE_STAGE_TRANSFER_BIT))
  nothing
end

const VERSION_TAG = "vetra-r040-probe"

end # module
