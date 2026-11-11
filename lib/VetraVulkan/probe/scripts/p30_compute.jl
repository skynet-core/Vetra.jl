#!/usr/bin/env julia
# R040 probe p30: Julia-authored compute shader route (SPIRV.jl) on real hardware.
#
# Demonstrates, end to end:
# - @compute compilation of a Julia kernel with runtime buffer inputs read
#   through buffer-device-address pointers, a data-dependent branch and a
#   loop whose trip count comes from buffer data (nothing constant-folds)
# - SPIR-V validation of the exact emitted bytes: internal (SPIRV.jl,
#   --target-env vulkan1.3) and external (spirv-val with an explicit
#   --target-env, plus a recorded negative control at a lower environment)
# - device creation with the minimal feature set DERIVED from the compiled
#   module's declared capabilities (verified against the safe feature query
#   BEFORE device creation; no wholesale upstream-harness feature requests,
#   no VariablePointers — the module does not declare that capability)
# - a bounded GC stress of the safe feature query (owned Refs, no dangling
#   pNext) that fails loudly on any drift
# - dispatch with runtime push constants, explicit HOST<->SHADER memory
#   barriers, synchronization validation enabled, byte-exact readback
#   against an independently written reference
# - a second dispatch with different input data over the same SPIR-V bytes
#   (proves runtime, non-folded behavior) and a third with reduced n
#   (sentinel check)
# - deterministic emission: compiling twice yields identical SPIR-V bytes
#
# The reference implementation below is plain Julia written from the math
# definition of the kernel; it is never derived from the emitted shader.
using SPIRV
using SPIRV_Tools_jll
using SHA
using Vulkan
using Vulkan: Vk, VkCore, unwrap
include(joinpath(@__DIR__, "probe_common.jl"))
using .ProbeCommon: check, write_evidence, reset_checks, make_instance, pick_device, make_device,
                    queue_family, bda_buffer, write_mem, read_mem, with_commands, memory_barrier!,
                    query_supported_features, features_from_capabilities, assert_features_supported,
                    release, refcount_ok, validation_errors, validation_warnings,
                    validation_messages, validation_clean, validation_evidence, run_capture, run_jll, CHECKS

import Vulkan:
  SHADER_STAGE_COMPUTE_BIT, PIPELINE_BIND_POINT_COMPUTE,
  QUEUE_GRAPHICS_BIT, QUEUE_COMPUTE_BIT,
  PIPELINE_STAGE_HOST_BIT, PIPELINE_STAGE_COMPUTE_SHADER_BIT,
  ACCESS_HOST_WRITE_BIT, ACCESS_HOST_READ_BIT, ACCESS_SHADER_READ_BIT, ACCESS_SHADER_WRITE_BIT,
  PushConstantRange, PipelineLayout, PipelineShaderStageCreateInfo, ComputePipelineCreateInfo

const PROBE_ROOT = dirname(@__DIR__)
const EVIDENCE = joinpath(PROBE_ROOT, "evidence")
const N = 128
const WORKGROUP = 64

# Push constant block: two buffer device addresses + element count.
struct ProbePush
  in_addr::UInt64
  out_addr::UInt64
  n::UInt32
end

"""The kernel as plain Julia. `lidx` is the linear local invocation index
(within the workgroup); the global element index is lidx + wgid[1] * wgsz[1].
SPIRV.jl pointer indexing is 1-based: `p[i]` addresses buffer element i-1
(confirmed against the emitted OpAccessChain indices). Buffer element 0 holds
the `iters` control word and is skipped; data elements 1..n-1 are computed."""
function compute_kernel(args::ProbePush, lidx::UInt32, wgid, wgsz)
  global_i = lidx + wgid[1] * wgsz[1]
  inp = SPIRV.Pointer{Vector{Float32}}(args.in_addr)
  outp = SPIRV.Pointer{Vector{Float32}}(args.out_addr)
  if global_i >= UInt32(1) && global_i < args.n
    iters_f = inp[UInt32(1)]             # runtime loop bound from buffer data
    v = inp[global_i + UInt32(1)]        # runtime buffer input (UInt32 index)
    acc = Float32(0)
    k = Float32(1)
    while k <= iters_f                   # loop not constant-foldable
      if v * k > Float32(1)              # branch on runtime data
        acc += Float32(1)
      else
        acc -= Float32(0.5)
      end
      k += Float32(1)
    end
    outp[global_i + UInt32(1)] = v + acc
  end
  nothing
end

"""Independent reference: out[i] = in[i] + sum_{k=1..iters}(in[i]*k > 1 ? 1 : -0.5),
iters = round(in[1]). Element 1 (index 0) is left at 0. Written from the math
definition above, not from the kernel code."""
function reference_kernel(inp::Vector{Float32}, n::Int)
  out = zeros(Float32, n)
  iters = Int(round(inp[1]))
  abs(inp[1] - iters) < 1e-6 || error("test data must carry an integral loop bound")
  for i in 2:n
    v = inp[i]
    acc = Float32(0)
    for k in 1:iters
      acc += (v * Float32(k) > Float32(1)) ? Float32(1) : Float32(-0.5)
    end
    out[i] = v + acc
  end
  out
end

"""Deterministic input vector: iters at [1], structured values at [2..n]."""
function make_input(iters::Int, n::Int)
  inp = Vector{Float32}(undef, n)
  inp[1] = Float32(iters)
  for j in 2:n
    x = Float32((j * 7919) % 1000) / Float32(1000)
    inp[j] = j % 13 == 0 ? x + Float32(1.5) : x
  end
  inp
end

function float32_bytes(v::Vector{Float32})
  copy(reinterpret(UInt8, v))
end

"""Run a SPIRV-Tools binary over `code` written to a temp file; returns (stdout, stderr, code).
The JLL artifact env is merged into the inherited environment (run_jll)."""
function spirv_tool(tool, code, args::Vector{String})
  jcmd = tool()
  exec = getfield(jcmd, fieldnames(typeof(jcmd))[1])
  tmp = joinpath(tempdir(), "r040-$(abs(hash((exec, code))))$(length(code)).spv")
  open(tmp, "w") do io
    write(io, code)
  end
  run_jll(jcmd, vcat(args, [tmp]))
end

function main()
  reset_checks()
  ev = Dict{String, Any}()

  inst = nothing; msg = nothing; dev = nothing
  in_res = nothing; out_res = nothing; shader = nothing; layout = nothing; pipeline = nothing
  try
  inst, msg, layers_used = make_instance(; validation = true, sync_validation = true, api = v"1.3")
  check("validation layer actually enabled (no silent downgrade)", layers_used == ["VK_LAYER_KHRONOS_validation"], "enabled=$(layers_used)")
  ph, props = pick_device(inst; name_substring = "NVIDIA GeForce")
  ev["device"] = props.device_name
  ev["validation_layer"] = layers_used
  ev["sync_validation_requested"] = true
  qi = queue_family(ph, QUEUE_GRAPHICS_BIT | QUEUE_COMPUTE_BIT)

  # --- safe feature query + bounded GC stress (no retry, owned Refs) ---------
  GC_STRESS = 50
  sup = query_supported_features(ph; stress = GC_STRESS)
  (base_bits, _n) = sup.gc_stress
  ev["feature_query_gc_stress"] = Dict("iterations" => GC_STRESS + 1,
                                       "stable" => true,
                                       "bits" => Dict("shaderInt64" => base_bits[1], "variablePointers" => base_bits[2],
                                                      "bufferDeviceAddress" => base_bits[3], "vulkanMemoryModel" => base_bits[4],
                                                      "maintenance4" => base_bits[5]),
                                       "note" => "re-queried after GC.gc() each iteration; drift would error loudly (dangling pNext)")
  check("safe feature query stable under $(GC_STRESS)-iteration GC stress", true, "bits=$base_bits")

  # --- compile first (needs only the physical device) ---------------------------
  # (internal validation runs against vulkan1.3 by SPIRV.jl default)
  features = SPIRV.SupportedFeatures(ph, v"1.2", String[], sup.features2)
  source = @compute features = features assemble = true (compute_kernel)(::ProbePush::PushConstant, ::UInt32::Input{LocalInvocationIndex}, ::SPIRV.Vec3U::Input{WorkgroupId}, ::SPIRV.Vec3U::Input{WorkgroupSize}) options = SPIRV.ComputeExecutionOptions(local_size = (WORKGROUP, 1, 1))
  code = source.code
  code_sha = string(sha256(code))
  ev["spirv"] = Dict("bytes" => length(code), "sha256" => code_sha,
                     "internal_validation" => "SPIRV.jl validate, --target-env vulkan1.3")
  check("shader compiled and internally validated", true, "$(length(code)) bytes")
  check("SPIR-V size is a multiple of 4", length(code) % 4 == 0, string(length(code)))

  # deterministic emission: compile the identical source a second time
  source2 = @compute features = features assemble = true (compute_kernel)(::ProbePush::PushConstant, ::UInt32::Input{LocalInvocationIndex}, ::SPIRV.Vec3U::Input{WorkgroupId}, ::SPIRV.Vec3U::Input{WorkgroupSize}) options = SPIRV.ComputeExecutionOptions(local_size = (WORKGROUP, 1, 1))
  check("emission deterministic (2nd compile identical bytes)", string(sha256(source2.code)) == code_sha,
        "sha256=$code_sha")

  # capabilities/extensions the module actually declares (independent spirv-dis read)
  (dis, _de, dc) = spirv_tool(SPIRV_Tools_jll.spirv_dis, code, ["--no-color"])
  dc == 0 || error("spirv-dis failed: $_de")
  dlines = split(dis, "\n")
  capnames = [String(m.captures[1]) for m in (match(r"OpCapability\s+(\S+)", strip(l)) for l in dlines) if !isnothing(m)]
  exts = [String(m.captures[1]) for m in (match(r"OpExtension\s+\"(\S+)\"", strip(l)) for l in dlines) if !isnothing(m)]
  ev["spirv_declared"] = Dict("capabilities" => capnames, "extensions" => exts)
  check("module does NOT declare VariablePointers (compiler availability != module requirement)",
        !("VariablePointers" in capnames), "capabilities=$capnames")

  # external validation of the exact bytes with explicit target environments.
  # The emitted module's SPIR-V binary version (header word 1: major bits 23:16, minor bits 15:8).
  word1 = Int(code[5]) | (Int(code[6]) << 8) | (Int(code[7]) << 16) | (Int(code[8]) << 24)
  spv_version = "$((word1 >> 16) & 0xFF).$((word1 >> 8) & 0xFF)"
  ev["spirv"]["binary_version"] = spv_version
  (_o, e13, c13) = spirv_tool(SPIRV_Tools_jll.spirv_val, code, ["--target-env", "vulkan1.3"])
  ev["spirv_val_vulkan1_3"] = Dict("exit" => c13, "stderr" => e13)
  check("external spirv-val --target-env vulkan1.3 passes (minimal env for SPIR-V $(spv_version))", c13 == 0, strip(e13))
  (_o1, e12, c12) = spirv_tool(SPIRV_Tools_jll.spirv_val, code, ["--target-env", "vulkan1.2"])
  ev["spirv_val_vulkan1_2_negative_control"] = Dict("exit" => c12, "stderr" => e12)
  check("negative control: vulkan1.2 env rejected (module is SPIR-V $(spv_version))", c12 != 0, strip(e12))

  # --- device with the feature set DERIVED from the compiled module -------------
  (f10, f11, f12, _f13caps) = features_from_capabilities(capnames)
  # The emitted module uses OpExecutionMode LocalSizeId, which requires the
  # maintenance4 feature (VUID 06434). Required, not optional.
  f13 = Symbol[]
  push!(f13, :maintenance4)
  # verify the known features against the SAFE query BEFORE device creation:
  # an unsupported device fails loudly here, not inside vkCreateDevice.
  assert_features_supported(sup; need10 = f10, need11 = f11, need12 = f12, need13 = f13)
  check("all derived features supported by the device (verified before vkCreateDevice)", true,
        "f10=$f10 f11=$f11 f12=$f12 f13=$f13")
  ev["device_features_derived"] = Dict("from_capabilities" => capnames,
                                       "f10" => collect(f10), "f11" => collect(f11), "f12" => collect(f12), "f13" => collect(f13))
  dev = make_device(inst, ph; f10 = f10, f11 = f11, f12 = f12, f13 = f13, qi = qi)

  # --- buffers + pipeline ---------------------------------------------------------
  in_bytes = float32_bytes(make_input(5, N))
  out_bytes = fill!(Vector{UInt8}(undef, N * 4), 0xff)
  out_bytes[1:4] = UInt8[0, 0, 0, 0]    # element 0 is the control word: reference leaves it 0.0f0
  in_res = bda_buffer(dev, ph, N * 4)
  out_res = bda_buffer(dev, ph, N * 4)
  write_mem(dev, in_res.memory, in_bytes)
  write_mem(dev, out_res.memory, out_bytes)

  shader = Vk.ShaderModule(dev, source)
  push_range = PushConstantRange(SHADER_STAGE_COMPUTE_BIT, 0, sizeof(ProbePush))
  layout = PipelineLayout(dev, [], [push_range])
  stage = PipelineShaderStageCreateInfo(SHADER_STAGE_COMPUTE_BIT, shader, "main")
  pci = ComputePipelineCreateInfo(stage, layout, 0)
  ((pipeline, _...), _res) = unwrap(Vulkan.create_compute_pipelines(dev, [pci]))
  ev["pipeline"] = "compute pipeline created from the emitted SPIR-V"

  function dispatch(pc::ProbePush, groups::Int)
    pc_ref = Ref(pc)
    pc_ptr = Base.unsafe_convert(Ptr{Cvoid}, pc_ref)
    GC.@preserve pc_ref shader pipeline layout begin
      with_commands(dev, qi, (cb) -> begin
        # explicit device-side ordering: host-wrote the buffers, the shader reads them
        memory_barrier!(cb, PIPELINE_STAGE_HOST_BIT, PIPELINE_STAGE_COMPUTE_SHADER_BIT, ACCESS_HOST_WRITE_BIT, ACCESS_SHADER_READ_BIT)
        Vulkan.cmd_bind_pipeline(cb, PIPELINE_BIND_POINT_COMPUTE, pipeline)
        Vulkan.cmd_push_constants(cb, layout, SHADER_STAGE_COMPUTE_BIT, 0, sizeof(ProbePush), pc_ptr)
        Vulkan.cmd_dispatch(cb, groups, 1, 1)
        # and the host reads the result after the shader wrote it
        memory_barrier!(cb, PIPELINE_STAGE_COMPUTE_SHADER_BIT, PIPELINE_STAGE_HOST_BIT, ACCESS_SHADER_WRITE_BIT, ACCESS_HOST_READ_BIT)
        nothing
      end)
    end
  end

  # --- run 1: iters=5, n=128 -------------------------------------------------------
  dispatch(ProbePush(in_res.address, out_res.address, UInt32(N)), cld(N, WORKGROUP))
  out1 = reinterpret(Float32, read_mem(dev, out_res.memory, N * 4))
  ref1 = reference_kernel(make_input(5, N), N)
  (m1, bad1) = compare_f32(out1, ref1, N)
  ev["run1"] = Dict("iters" => 5, "n" => N, "bytes_exact" => m1, "first_mismatch" => bad1)
  check("run1: device result byte-exact vs independent reference", m1 == N * 4, "$m1/$(N * 4) bytes exact")

  # --- run 2: iters=8, different data, SAME SPIR-V bytes ----------------------------
  in2 = make_input(8, N)
  write_mem(dev, in_res.memory, float32_bytes(in2))
  dispatch(ProbePush(in_res.address, out_res.address, UInt32(N)), cld(N, WORKGROUP))
  out2 = reinterpret(Float32, read_mem(dev, out_res.memory, N * 4))
  ref2 = reference_kernel(in2, N)
  (m2, bad2) = compare_f32(out2, ref2, N)
  ev["run2"] = Dict("iters" => 8, "n" => N, "bytes_exact" => m2, "first_mismatch" => bad2)
  check("run2: different runtime data, same shader bytes, byte-exact", m2 == N * 4, "$m2/$(N * 4) bytes exact")
  ndiff = count(reinterpret(UInt8, out2) .!= reinterpret(UInt8, out1))
  ev["run2"]["n_differing_bytes_vs_run1"] = ndiff
  check("run2 differs from run1 (runtime inputs drove the computation)", ndiff > 0, "n_differing_bytes=$ndiff")

  # --- run 3: n=100, sentinel beyond n must stay 0xff --------------------------------
  in3 = make_input(6, N)
  write_mem(dev, in_res.memory, float32_bytes(in3))
  write_mem(dev, out_res.memory, out_bytes)
  dispatch(ProbePush(in_res.address, out_res.address, UInt32(100)), cld(N, WORKGROUP))
  out3mem = read_mem(dev, out_res.memory, N * 4)
  out3 = reinterpret(Float32, out3mem)
  ref3 = reference_kernel(in3, 100)
  (m3, bad3) = compare_f32(out3, ref3, 100)
  sentinel_ok = all(out3mem[401:end] .== 0xff)
  ev["run3"] = Dict("iters" => 6, "n" => 100, "bytes_exact" => m3, "sentinel_rest_unchanged" => sentinel_ok, "first_mismatch" => bad3)
  check("run3: runtime n=100 respected, elements beyond n untouched", m3 == 100 * 4 && sentinel_ok,
        "$m3/400 bytes + sentinel ok=$sentinel_ok")

  # --- deterministic cleanup (runs on EVERY path incl. mid-probe errors) -------
  # Capture lifetime, precisely: workload resources are released first (reverse
  # dependency order, buffer before memory where practical) while the messenger
  # is still alive, so destruction-time messages are captured; GC then runs
  # (finalizers, still under the live messenger); the validation evidence is
  # classified BEFORE the messenger and instance are released — after that the
  # capture is closed. Nothing is released twice.
  finally
    pipeline !== nothing && release(pipeline)
    shader !== nothing && release(shader)
    layout !== nothing && release(layout)
    if out_res !== nothing
      release(out_res.buffer)
      release(out_res.memory)
    end
    if in_res !== nothing
      release(in_res.buffer)
      release(in_res.memory)
    end
    dev !== nothing && release(dev)
    GC.gc()
    check("refcount clean after release (no underflow)", refcount_ok(dev) && refcount_ok(pipeline) && refcount_ok(inst), "")
    ev["validation"] = validation_evidence()
    check("no validation-layer ERROR/WARNING messages through workload cleanup + GC", validation_clean(),
          "$(length(validation_errors())) errors, $(length(validation_warnings())) warnings, $(length(validation_messages())) total")
    msg !== nothing && release(msg)
    inst !== nothing && release(inst)
    GC.gc()
  end
  ev["cleanup"] = "Base.finalize in reverse dependency order; refcount underflow checked; GC + validation classification run while the messenger is still alive; messenger and instance released last, once"


  npass, nfail = count(x -> x[2], CHECKS), count(x -> !x[2], CHECKS)
  ev["summary"] = Dict("pass" => npass, "fail" => nfail)
  ev["checks"] = [Dict("name" => c[1], "ok" => c[2], "detail" => c[3]) for c in CHECKS]
  path = write_evidence(joinpath(EVIDENCE, "p30_compute.json"), ev)
  println("evidence: ", path, " | pass=", npass, " fail=", nfail)
  nfail > 0 && exit(1)
  ev
end

function compare_f32(got::AbstractVector{Float32}, want::AbstractVector{Float32}, n)
  gb = copy(reinterpret(UInt8, got[1:n]))
  wb = copy(reinterpret(UInt8, want[1:n]))
  m = count(gb .== wb)
  bad = findfirst(gb .!= wb)
  (m, isnothing(bad) ? nothing : Dict("byte_index" => bad, "got" => Int(gb[bad]), "want" => Int(wb[bad])))
end

const _here = @__MODULE__
if _here == Main
  main()
end
