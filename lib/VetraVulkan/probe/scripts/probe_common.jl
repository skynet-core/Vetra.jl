"""
ProbeCommon: shared helpers for the R040 Vulkan.jl / SPIRV.jl compatibility spike.

- check accumulator + minimal JSON evidence writer (no extra dependencies)
- debug-callback message capture (validation-layer assertions)
- instance/device/queue/memory/command helpers on the Vulkan.jl 0.6.x API
  (the declared-compatible stack for SPIRV.jl 0.6.11)
"""
module ProbeCommon

using Logging
using Vulkan
using Vulkan: Vk, VkCore, unwrap

# The generated CEnum constants live inside the Vulkan module and are not
# re-exported, so bring the ones the probe uses into scope explicitly.
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
  PIPELINE_STAGE_TRANSFER_BIT, PIPELINE_STAGE_VERTEX_SHADER_BIT, PIPELINE_STAGE_FRAGMENT_SHADER_BIT,
  PIPELINE_STAGE_COLOR_ATTACHMENT_OUTPUT_BIT, PIPELINE_STAGE_EARLY_FRAGMENT_TESTS_BIT,
  IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL,
  ImageSubresourceRange, ImageMemoryBarrier, MemoryBarrier, BufferMemoryBarrier,
  DEBUG_UTILS_MESSAGE_SEVERITY_VERBOSE_BIT_EXT, DEBUG_UTILS_MESSAGE_SEVERITY_INFO_BIT_EXT,
  DEBUG_UTILS_MESSAGE_SEVERITY_WARNING_BIT_EXT, DEBUG_UTILS_MESSAGE_SEVERITY_ERROR_BIT_EXT,
  DEBUG_UTILS_MESSAGE_TYPE_GENERAL_BIT_EXT, DEBUG_UTILS_MESSAGE_TYPE_VALIDATION_BIT_EXT,
  DEBUG_UTILS_MESSAGE_TYPE_PERFORMANCE_BIT_EXT

const LAYER_VALIDATION = "VK_LAYER_KHRONOS_validation"
const EXT_DEBUG_UTILS = "VK_EXT_debug_utils"

# Debug callback severity bits (VK_DEBUG_UTILS_MESSAGE_SEVERITY_*_BIT_EXT)
const SEV_VERBOSE = 0x01
const SEV_INFO = 0x02
const SEV_WARNING = 0x04
const SEV_ERROR = 0x08

# ---------------------------------------------------------------------------
# Self-checks and evidence
# ---------------------------------------------------------------------------

const CHECKS = Vector{Tuple{String, Bool, String}}()
const _CAP = Ref{Vector{Tuple{Int, Int, String}}}([])

function capture_callback(severity, msg_type, p::Ptr{VkCore.VkDebugUtilsMessengerCallbackDataEXT}, u)
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

validation_errors() = [m for m in _CAP[] if (m[1] & SEV_ERROR) != 0]
validation_warnings() = [m for m in _CAP[] if (m[1] & SEV_WARNING) != 0]
validation_messages() = _CAP[]

"""Minimal JSON writer for the evidence dicts (String/Int/Bool/Dict/Vector/Nothing)."""
function jesc(s::AbstractString)
  replace(s, "\\" => "\\\\", "\"" => "\\\"", "\n" => "\\n", "\r" => "\\r", "\t" => "\\t")
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

function sh_quote(s::AbstractString)
  "'" * replace(s, "'" => "'\"'\"'") * "'"
end

"""Run a Cmd capturing (stdout, stderr, exit_code) through an `sh -c` wrapper.
The native pipeline redirection in this host's stripped Julia build loses child
output (stdout pipes come back empty, `2>&1` in backticks mis-parses), so the
shell does the redirection instead."""
function run_capture(cmd::Cmd; env::Vector{String} = String[])
  execv = getfield(cmd, :exec)
  exe = execv[1]
  args = execv[2:end]
  out_f = tempname()
  err_f = tempname()
  script = isempty(args) ? sh_quote(exe) : sh_quote(exe) * " " * join(map(sh_quote, args), " ")
  script = script * " > " * sh_quote(out_f) * " 2> " * sh_quote(err_f) * "; echo exitcode=\$? >> " * sh_quote(err_f)
  cmd_env = getfield(cmd, :env)
  envs() = ["$k=$v" for (k, v) in ENV]
  base_env = isempty(env) ?
    (isnothing(cmd_env) ? envs() :
     (cmd_env isa AbstractString ? [cmd_env] : (isempty(cmd_env) ? envs() : collect(cmd_env)))) :
    env
  try
    read(ignorestatus(Cmd(Cmd(["sh", "-c", script]); env = base_env)), String)
  catch
  end
  out = read(out_f, String)
  errtxt = read(err_f, String)
  code = -1
  for l in reverse(split(errtxt, "\n"))
    if startswith(l, "exitcode=")
      code = parse(Int, l[10:end])
      break
    end
  end
  try
    unlink(out_f)
    unlink(err_f)
  catch
  end
  (chomp(out), errtxt, code)
end

# ---------------------------------------------------------------------------
# Instance / device
# ---------------------------------------------------------------------------

instance_layers() = [l.layer_name for l in unwrap(Vulkan.enumerate_instance_layer_properties())]
instance_extensions() = [e.extension_name for e in unwrap(Vulkan.enumerate_instance_extension_properties())]

"""Create an instance (optionally with the KHRONOS validation layer) + debug
messenger that captures messages into `validation_errors()`.
Returns (instance, messenger_or_nothing, layers_enabled)."""
function make_instance(; validation = false, api = v"1.3")
  layers = String[]
  if validation && LAYER_VALIDATION in instance_layers()
    push!(layers, LAYER_VALIDATION)
  end
  exts = String[EXT_DEBUG_UTILS]
  exts = filter(e -> e in instance_extensions(), exts)
  inst = Instance(layers, exts; application_info = ApplicationInfo(v"0.1", v"1.0", api))
  msg = isempty(exts) ? nothing : DebugUtilsMessengerEXT(inst,
    DEBUG_UTILS_MESSAGE_SEVERITY_VERBOSE_BIT_EXT | DEBUG_UTILS_MESSAGE_SEVERITY_INFO_BIT_EXT | DEBUG_UTILS_MESSAGE_SEVERITY_WARNING_BIT_EXT | DEBUG_UTILS_MESSAGE_SEVERITY_ERROR_BIT_EXT,
    DEBUG_UTILS_MESSAGE_TYPE_GENERAL_BIT_EXT | DEBUG_UTILS_MESSAGE_TYPE_VALIDATION_BIT_EXT | DEBUG_UTILS_MESSAGE_TYPE_PERFORMANCE_BIT_EXT,
    @cfunction(capture_callback, UInt32, (UInt32, UInt32, Ptr{VkCore.VkDebugUtilsMessengerCallbackDataEXT}, Ptr{Cvoid})))
  return inst, msg, layers
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
`f10/f11/f12/f13` are Symbol lists of Vulkan feature names."""
function make_device(inst, ph; f10 = Symbol[], f11 = Symbol[], f12 = Symbol[], f13 = Symbol[],
                     layers = String[], extensions = String[], qi = 0, priorities = [1.0f0])
  f13s = PhysicalDeviceVulkan13Features(f13...; next = C_NULL)
  f12s = PhysicalDeviceVulkan12Features(f12...; next = f13s)
  f11s = PhysicalDeviceVulkan11Features(f11...; next = f12s)
  f10s = PhysicalDeviceFeatures(f10...)
  base = PhysicalDeviceFeatures2(f10s; next = f11s)
  dev = Device(ph, [DeviceQueueCreateInfo(UInt32(qi), priorities)], layers, extensions; next = base)
  dev
end

"""Query the features a device supports for the given chain types (1.1/1.2/1.3).
Retries on AssertionError: the ICD can transiently return a short pNext chain
(observed once on this host after a heavy sequence of instance creations)."""
function supported_features(ph; attempts = 3)
  attempts <= 0 && error("get_physical_device_features_2 kept failing after retries")
  try
    f = unwrap(Vulkan.get_physical_device_features_2(ph, PhysicalDeviceVulkan11Features, PhysicalDeviceVulkan12Features, PhysicalDeviceVulkan13Features))
    f11 = f.next::PhysicalDeviceVulkan11Features
    f12 = f11.next::PhysicalDeviceVulkan12Features
    f13 = f12.next::PhysicalDeviceVulkan13Features
    (features2 = f, f11 = f11, f12 = f12, f13 = f13)
  catch e
    isa(e, AssertionError) || rethrow()
    supported_features(ph; attempts = attempts - 1)
  end
end

"""Map the SPIR-V capabilities a module declares to the Vulkan device features
required to run it (the derived minimum, not the upstream harness's request)."""
function features_from_capabilities(capnames::Vector{String})
  f10 = Set{Symbol}()
  f11 = Set{Symbol}()
  f12 = Set{Symbol}()
  for c in capnames
    if c == "Int64"
      push!(f10, :shader_int_64)
    elseif c == "Float64"
      push!(f10, :shader_float_64)
    elseif c == "Int8"
      push!(f10, :shader_int_16)
    elseif c == "VariablePointers"
      push!(f11, :variable_pointers)
    elseif c == "PhysicalStorageBufferAddresses"
      push!(f12, :buffer_device_address)
    elseif c == "VulkanMemoryModel"
      push!(f12, :vulkan_memory_model)
    end
  end
  (collect(f10), collect(f11), collect(f12))
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
# Buffers (BDA-capable), memory, commands
# ---------------------------------------------------------------------------

"""Create a host-coherent transfer buffer (no device-address usage).
Returns (buffer, memory)."""
function plain_buffer(dev, ph, nbytes; usage = BUFFER_USAGE_TRANSFER_SRC_BIT | BUFFER_USAGE_TRANSFER_DST_BIT)
  buf = Buffer(dev, nbytes, usage, SHARING_MODE_EXCLUSIVE, [0])
  req = unwrap(Vulkan.get_buffer_memory_requirements(dev, buf))
  idx = memory_index(ph, req.memory_type_bits, MEMORY_PROPERTY_HOST_VISIBLE_BIT | MEMORY_PROPERTY_HOST_COHERENT_BIT)
  mem = DeviceMemory(dev, req.size, idx)
  unwrap(Vulkan.bind_buffer_memory(dev, buf, mem, 0))
  (buffer = buf, memory = mem)
end

"""Create a host-coherent storage buffer with the shader-device-address usage.
Returns (buffer, memory, device_address)."""
function bda_buffer(dev, ph, nbytes)
  buf = Buffer(dev, nbytes, BUFFER_USAGE_STORAGE_BUFFER_BIT | BUFFER_USAGE_SHADER_DEVICE_ADDRESS_BIT, SHARING_MODE_EXCLUSIVE, [0])
  req = unwrap(Vulkan.get_buffer_memory_requirements(dev, buf))
  idx = memory_index(ph, req.memory_type_bits, MEMORY_PROPERTY_HOST_VISIBLE_BIT | MEMORY_PROPERTY_HOST_COHERENT_BIT)
  mem = DeviceMemory(dev, req.size, idx; next = MemoryAllocateFlagsInfo(UInt32(0); flags = MEMORY_ALLOCATE_DEVICE_ADDRESS_BIT))
  unwrap(Vulkan.bind_buffer_memory(dev, buf, mem, 0))
  addr = unwrap(Vulkan.get_buffer_device_address(dev, BufferDeviceAddressInfo(buf)))
  (buffer = buf, memory = mem, address = addr)
end

"""Copy `data` into a mapped device memory region."""
function write_mem(dev, mem, data::Vector{UInt8})
  ptr = unwrap(Vulkan.map_memory(dev, mem, 0, length(data)))
  copyto!(Base.unsafe_wrap(Vector{UInt8}, Ptr{UInt8}(ptr), length(data), own = false), data)
  Vulkan.unmap_memory(dev, mem)
  nothing
end

"""Read `nbytes` from a mapped device memory region."""
function read_mem(dev, mem, nbytes)
  ptr = unwrap(Vulkan.map_memory(dev, mem, 0, nbytes))
  v = copy(Base.unsafe_wrap(Vector{UInt8}, Ptr{UInt8}(ptr), nbytes, own = false))
  Vulkan.unmap_memory(dev, mem)
  v
end

"""Record `f(cb)` into a primary command buffer, submit it and wait for idle.
Handles are released through the wrapper refcount model (`.destructor()`),
which also decrements the parent — never mix raw vk free/destroy calls with
it, or the finalizer double-destroys."""
function with_commands(dev, qi, f)
  pool = CommandPool(dev, qi)
  cbs = unwrap(Vulkan.allocate_command_buffers(dev, CommandBufferAllocateInfo(pool, COMMAND_BUFFER_LEVEL_PRIMARY, 1)))
  (cb,) = cbs
  unwrap(Vulkan.begin_command_buffer(cb, CommandBufferBeginInfo()))
  f(cb)
  unwrap(Vulkan.end_command_buffer(cb))
  q = unwrap(Vulkan.get_device_queue(dev, qi, 0))
  unwrap(Vulkan.queue_submit(q, [SubmitInfo(Semaphore[], PipelineStageFlag[], [cb], Semaphore[])]))
  unwrap(Vulkan.queue_wait_idle(q))
  cb.destructor()
  pool.destructor()
  nothing
end

# ---------------------------------------------------------------------------
# Offscreen images
# ---------------------------------------------------------------------------

"""Create a 2D RGBA8 image usable for transfer + (optionally) color attachment.
Returns (image, view)."""
function offscreen_image(dev, ph, w, h; usage = IMAGE_USAGE_TRANSFER_SRC_BIT | IMAGE_USAGE_TRANSFER_DST_BIT, fmt = FORMAT_R8G8B8A8_UNORM)
  # Verify the exact (format, 2D, optimal, usage) combination the device supports.
  try
    unwrap(Vulkan.get_physical_device_image_format_properties(ph, fmt, IMAGE_TYPE_2D, IMAGE_TILING_OPTIMAL, usage))
  catch e
    error("Format $(fmt) with 2D/optimal/$(usage) is not supported on this device: $(sprint(showerror, e))")
  end
  img = Image(dev, IMAGE_TYPE_2D, fmt, Extent3D(UInt32(w), UInt32(h), 1), 1, 1, SAMPLE_COUNT_1_BIT,
              IMAGE_TILING_OPTIMAL, usage, SHARING_MODE_EXCLUSIVE, [0], IMAGE_LAYOUT_UNDEFINED)
  req = unwrap(Vulkan.get_image_memory_requirements(dev, img))
  idx = memory_index(ph, req.memory_type_bits, MEMORY_PROPERTY_DEVICE_LOCAL_BIT)
  mem = DeviceMemory(dev, req.size, idx)
  unwrap(Vulkan.bind_image_memory(dev, img, mem, 0))
  # The view must be created after the image memory is bound (VUID 01020).
  view = ImageView(dev, img, IMAGE_VIEW_TYPE_2D, fmt,
                   ComponentMapping(COMPONENT_SWIZZLE_R, COMPONENT_SWIZZLE_G, COMPONENT_SWIZZLE_B, COMPONENT_SWIZZLE_A),
                   ImageSubresourceRange(IMAGE_ASPECT_COLOR_BIT, 0, 1, 0, 1))
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
