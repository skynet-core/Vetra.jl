#!/usr/bin/env julia
# R040 probe p40 child: execute ONE bool-returning SPIR-V module under (or
# without) the KHRONOS validation layer and report what happened.
#
# argv: spv_path input_hex out_size layer expected
#   spv_path   : path to the .spv to execute
#   input_hex  : 16 hex chars = 2 floats little-endian (the runtime data)
#   out_size   : output buffer size in bytes (1 = upstream sizeof(Bool), 4 = SPIR-V bool size)
#   layer      : 0/1, enable the KHRONOS validation layer
#   expected   : 0/1, independently computed expected bool (in1 > in2)
#
# Prints "READBACK=...", "VAL_ERRORS=n", "VAL_WARNINGS=n", "CHILD_DONE" on a
# normal finish. The parent (p40_bool_layers.jl) captures this through
# run_capture so a layer crash is recorded as an exit code, not fatal here.
using SPIRV
using SPIRV_Tools_jll
using Vulkan
using Vulkan: Vk, VkCore, unwrap
include(joinpath(@__DIR__, "probe_common.jl"))
using .ProbeCommon: make_instance, pick_device, make_device, queue_family, bda_buffer, write_mem,
                    read_mem, with_commands, supported_features, features_from_capabilities,
                    validation_errors, validation_warnings, run_capture

import Vulkan:
  SHADER_STAGE_COMPUTE_BIT, PIPELINE_BIND_POINT_COMPUTE,
  QUEUE_GRAPHICS_BIT, QUEUE_COMPUTE_BIT,
  PushConstantRange, PipelineLayout, PipelineShaderStageCreateInfo, ComputePipelineCreateInfo

const PROBE_ROOT = dirname(@__DIR__)

"""println + flush: the host build's file-redirected stdout flushes
unreliably, so every status line is flushed before the parent reads it."""
function report(xs...)
  println(xs...)
  flush(stdout)
end

struct BoolBlock
  in_addr::UInt64
  out_addr::UInt64
end

function main()
  spv_path, input_hex, out_size, layer, expected = ARGS[1], ARGS[2], parse(Int, ARGS[3]), parse(Int, ARGS[4]), parse(Int, ARGS[5])
  sz = filesize(spv_path)
  code = Vector{UInt8}(undef, sz)
  open(spv_path) do io
    read!(io, code)
  end
  pad = cld(length(code), 4) * 4 - length(code)
  pad > 0 && append!(code, zeros(UInt8, pad))

  inst, msg, layers_used = make_instance(; validation = layer == 1)
  report("LAYER_ENABLED=", layer == 1 && !isempty(layers_used) ? "yes" : "no (requested)")
  ph, props = pick_device(inst; name_substring = "NVIDIA GeForce")

  # derive the minimal feature set from the module's declared capabilities
  bin = SPIRV_Tools_jll.spirv_dis()
  execv = getfield(bin, :exec)
  tmp = joinpath(tempdir(), "r040-p40-child.spv")
  open(tmp, "w") do io; write(io, code); end
  (dis, _e, rc) = run_capture(setenv(Cmd(vcat(execv, ["--no-color", tmp])), bin.env))
  rc == 0 || error("spirv-dis failed in child: $rc")
  dlines = split(dis, "\n")
  capnames = [String(m.captures[1]) for m in (match(r"OpCapability\s+(\S+)", strip(l)) for l in dlines) if !isnothing(m)]
  (f10, f11, f12) = features_from_capabilities(capnames)
  push!(f11, :variable_pointers)
  push!(f11, :variable_pointers_storage_buffer)
  f13 = Symbol[]
  sup = supported_features(ph)
  sup.f13.maintenance4 != 0 && push!(f13, :maintenance4)

  qi = queue_family(ph, QUEUE_GRAPHICS_BIT | QUEUE_COMPUTE_BIT)
  dev = make_device(inst, ph; f10 = f10, f11 = f11, f12 = f12, f13 = f13, layers = layers_used, qi = qi)

  # runtime input: two floats, the bool is their comparison (not constant)
  in_bytes = [parse(UInt8, input_hex[i:i + 1], base = 16) for i in 1:2:16]
  in_res = bda_buffer(dev, ph, 8)
  out_res = bda_buffer(dev, ph, out_size)
  write_mem(dev, in_res.memory, in_bytes)

  shader = Vk.ShaderModule(dev, length(code), reinterpret(UInt32, code))
  push_range = PushConstantRange(SHADER_STAGE_COMPUTE_BIT, 0, sizeof(BoolBlock))
  layout = PipelineLayout(dev, [], [push_range])
  stage = PipelineShaderStageCreateInfo(SHADER_STAGE_COMPUTE_BIT, shader, "main")
  pci = ComputePipelineCreateInfo(stage, layout, 0)
  ((pipeline, _...), _res) = unwrap(Vulkan.create_compute_pipelines(dev, [pci]))
  report("PIPELINE_OK")

  pc = BoolBlock(in_res.address, out_res.address)
  pc_ref = Ref(pc)
  pc_ptr = Base.unsafe_convert(Ptr{Cvoid}, pc_ref)
  GC.@preserve pc_ref shader pipeline layout begin
    with_commands(dev, qi, (cb) -> begin
      Vulkan.cmd_bind_pipeline(cb, PIPELINE_BIND_POINT_COMPUTE, pipeline)
      Vulkan.cmd_push_constants(cb, layout, SHADER_STAGE_COMPUTE_BIT, 0, sizeof(BoolBlock), pc_ptr)
      Vulkan.cmd_dispatch(cb, 1, 1, 1)
      nothing
    end)
  end

  out_bytes = read_mem(dev, out_res.memory, out_size)
  hd = "0123456789abcdef"
  hex = join([hd[Int(b >> 4) + 1] * hd[Int(b & 0x0f) + 1] for b in out_bytes])
  report("READBACK_HEX=", hex)
  report("READBACK_LEN=", length(out_bytes))
  val = length(out_bytes) >= 4 ? reinterpret(UInt32, Vector{UInt8}(vcat(out_bytes, zeros(UInt8, 4 - length(out_bytes)))))[1] : UInt32(out_bytes[1])
  ok = val == expected
  report("RESULT=", ok ? "MATCH" : "MISMATCH expected=$expected got=$(val & 0xff)")

  errs = validation_errors()
  warns = validation_warnings()
  report("VAL_ERRORS=", length(errs))
  for (sev, mtype, m) in errs
    report("VAL_ERROR: ", m)
  end
  report("VAL_WARNINGS=", length(warns))
  for (sev, mtype, m) in warns
    report("VAL_WARNING: ", m)
  end

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
  report("CHILD_DONE")
end

main()
