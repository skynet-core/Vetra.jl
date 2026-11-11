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
# - device creation with the minimal derived feature set (no wholesale
#   upstream-harness feature requests)
# - dispatch with runtime push constants, synchronization, byte-exact
#   readback against an independently written reference
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
                    queue_family, bda_buffer, write_mem, read_mem, with_commands,
                    supported_features, features_from_capabilities, validation_errors, validation_messages, CHECKS, run_capture

import Vulkan:
  SHADER_STAGE_COMPUTE_BIT, PIPELINE_BIND_POINT_COMPUTE,
  QUEUE_GRAPHICS_BIT, QUEUE_COMPUTE_BIT,
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

"""Run a SPIRV-Tools binary over `code` written to a temp file; returns (stdout, stderr, code)."""
function spirv_tool(tool, code, args::Vector{String})
  bin = tool()
  exec = getfield(bin, fieldnames(typeof(bin))[1])
  tmp = joinpath(tempdir(), "r040-$(abs(hash((exec, code))))$(length(code)).spv")
  open(tmp, "w") do io
    write(io, code)
  end
  run_capture(setenv(Cmd(vcat(exec, args, [tmp])), bin.env))
end

function main()
  reset_checks()
  ev = Dict{String, Any}()

  inst, msg, layers_used = make_instance(; validation = true, api = v"1.3")
  ph, props = pick_device(inst; name_substring = "NVIDIA GeForce")
  ev["device"] = props.device_name
  ev["validation_layer"] = layers_used
  qi = queue_family(ph, QUEUE_GRAPHICS_BIT | QUEUE_COMPUTE_BIT)

  # --- compile first (needs only the physical device) ---------------------------
  # (internal validation runs against vulkan1.3 by SPIRV.jl default)
  sup = supported_features(ph)
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
  (f10, f11, f12) = features_from_capabilities(capnames)
  # SPIRV.jl needs variable pointers for traced Julia code even when the module
  # itself carries no VariablePointers capability.
  push!(f11, :variable_pointers)
  push!(f11, :variable_pointers_storage_buffer)   # VUID 01431: required with variablePointers
  # The emitted module uses OpExecutionMode LocalSizeId, which requires the
  # maintenance4 feature (VUID 06434); enable it when the device supports it.
  f13 = Symbol[]
  if sup.f13.maintenance4 != 0
    push!(f13, :maintenance4)
  end
  ev["device_features_derived"] = Dict("from_capabilities" => capnames,
                                       "f10" => collect(f10), "f11" => collect(f11), "f12" => collect(f12), "f13" => collect(f13))
  dev = make_device(inst, ph; f10 = f10, f11 = f11, f12 = f12, f13 = f13, layers = layers_used, qi = qi)

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
        Vulkan.cmd_bind_pipeline(cb, PIPELINE_BIND_POINT_COMPUTE, pipeline)
        Vulkan.cmd_push_constants(cb, layout, SHADER_STAGE_COMPUTE_BIT, 0, sizeof(ProbePush), pc_ptr)
        Vulkan.cmd_dispatch(cb, groups, 1, 1)
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

  # --- validation layer cleanliness ---------------------------------------------------
  errs = validation_errors()
  ev["validation"] = Dict("errors" => [m[3] for m in errs], "n_messages" => length(validation_messages()))
  check("no validation-layer ERROR messages", isempty(errs), "errors=$(length(errs))")

  # --- cleanup --------------------------------------------------------------------------
  pipeline.destructor()
  shader.destructor()
  layout.destructor()
  out_res.memory.destructor()
  out_res.buffer.destructor()
  in_res.memory.destructor()
  in_res.buffer.destructor()
  dev.destructor()
  isnothing(msg) || msg.destructor()
  inst.destructor()
  ev["cleanup"] = "explicit .destructor() in reverse dependency order after queue_wait_idle"

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
