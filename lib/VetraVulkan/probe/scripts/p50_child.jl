#!/usr/bin/env julia
# R040 probe p50 child: exercise ONE error/install path and report the outcome.
#
# argv: mode [extra...]
#   no_device        : expect a meaningful error from device discovery
#                      (VK_DRIVER_FILES must point at nothing in the env)
#   bogus_ext        : expect a meaningful error creating a device with a
#                      non-existent device extension
#   bad_format       : expect a meaningful error for an unsupported
#                      (format, tiling, usage) combination
#   precompile       : Pkg.precompile of Vulkan under the current env
#                      (VK_DRIVER_FILES absent or bogus,
#                       JULIA_VULKAN_PRECOMPILE_DEVICE_FUNCTIONS set by parent)
#
# Prints MODE=, ERROR_CAUGHT=, ERROR_TYPE=, ERROR_MSG= (single line),
# PRECOMPILE_OK=/PRECOMPILE_FAIL=, DONE. The parent (p50_errors.jl) captures
# it through run_capture; a crash is recorded as an exit code.
using Pkg
using Vulkan
using Vulkan: Vk, VkCore, unwrap
include(joinpath(@__DIR__, "probe_common.jl"))
using .ProbeCommon: make_instance, pick_device, make_device, queue_family, offscreen_image

import Vulkan:
  SHADER_STAGE_COMPUTE_BIT, PIPELINE_BIND_POINT_COMPUTE,
  QUEUE_GRAPHICS_BIT, QUEUE_COMPUTE_BIT,
  IMAGE_TYPE_2D, IMAGE_TILING_OPTIMAL,
  IMAGE_USAGE_TRANSFER_SRC_BIT, IMAGE_USAGE_TRANSFER_DST_BIT, IMAGE_USAGE_COLOR_ATTACHMENT_BIT,
  FORMAT_FEATURE_TRANSFER_SRC_BIT, FORMAT_FEATURE_TRANSFER_DST_BIT, FORMAT_FEATURE_COLOR_ATTACHMENT_BIT,
  FORMAT_R4G4_UNORM_PACK8, FORMAT_R4G4B4A4_UNORM_PACK16,
  FORMAT_R32_UINT, FORMAT_S8_UINT, FORMAT_R16_UINT, FORMAT_A2B10G10R10_UNORM_PACK32

const PROBE_ROOT = dirname(@__DIR__)

function report(xs...)
  println(xs...)
  flush(stdout)
end

function sanitize(s)
  replace(replace(s, "\n" => "\\n"), "\r" => "")
end

function main()
  mode = ARGS[1]
  report("MODE=", mode)
  try
    if mode == "no_device"
      inst, msg, layers = make_instance(; validation = false)
      _ = pick_device(inst)
      report("ERROR_CAUGHT=no (unexpected: a device was found)")
      isnothing(msg) || msg.destructor()
      inst.destructor()
    elseif mode == "bogus_ext"
      inst, msg, layers = make_instance(; validation = false)
      ph, _props = pick_device(inst; name_substring = "NVIDIA GeForce")
      qi = queue_family(ph, QUEUE_GRAPHICS_BIT | QUEUE_COMPUTE_BIT)
      _ = make_device(inst, ph; layers = layers, qi = qi, extensions = ["VK_FAKE_ext_bogus"])
      report("ERROR_CAUGHT=no (unexpected: bogus extension accepted)")
      isnothing(msg) || msg.destructor()
      inst.destructor()
    elseif mode == "bad_format"
      inst, msg, layers = make_instance(; validation = false)
      ph, _props = pick_device(inst; name_substring = "NVIDIA GeForce")
      qi = queue_family(ph, QUEUE_GRAPHICS_BIT | QUEUE_COMPUTE_BIT)
      dev = make_device(inst, ph; layers = layers, qi = qi)
      usage = IMAGE_USAGE_TRANSFER_SRC_BIT | IMAGE_USAGE_TRANSFER_DST_BIT | IMAGE_USAGE_COLOR_ATTACHMENT_BIT
      needed = FORMAT_FEATURE_TRANSFER_SRC_BIT | FORMAT_FEATURE_TRANSFER_DST_BIT | FORMAT_FEATURE_COLOR_ATTACHMENT_BIT
      # find a format the device genuinely lacks the needed features for
      candidates = [FORMAT_R4G4_UNORM_PACK8, FORMAT_R4G4B4A4_UNORM_PACK16,
                    FORMAT_R32_UINT, FORMAT_S8_UINT, FORMAT_R16_UINT, FORMAT_A2B10G10R10_UNORM_PACK32]
      bad = nothing
      for fmt in candidates
        fp = unwrap(Vulkan.get_physical_device_format_properties(ph, fmt))
        if fp.optimal_tiling_features & needed != needed
          bad = (fmt, fp)
          break
        end
      end
      bad === nothing && error("no unsupported-format candidate found on this device; pick better candidates")
      _ = offscreen_image(dev, ph, 4, 4; usage = usage, fmt = bad[1])
      report("ERROR_CAUGHT=no (unexpected: unsupported format accepted)")
      dev.destructor()
      isnothing(msg) || msg.destructor()
      inst.destructor()
    elseif mode == "precompile"
      pref = ARGS[2]   # false / auto / true
      # 0.6.x mechanism: project-level LocalPreferences.toml via set_preferences!,
      # which refuses to overwrite an existing value — remove a stale file first;
      # no file means the default ("auto").
      lp = joinpath(PROBE_ROOT, "LocalPreferences.toml")
      isfile(lp) && rm(lp)
      pref != "auto" && Vulkan.set_preferences!("PRECOMPILE_DEVICE_FUNCTIONS" => pref)
      try
        # force re-precompilation: Pkg skips packages whose cache is up to date,
        # which would never re-run the device-dependent @compile_workload
        cc = joinpath(DEPOT_PATH[1], "compiled", "v$(VERSION.major).$(VERSION.minor)", "Vulkan")
        if isdir(cc)   # this build's rm(dir; force) does not recurse
          for f in readdir(cc)
            p = joinpath(cc, f)
            isdir(p) ? rm(p; force = true) : rm(p)
          end
          rm(cc)
        end
        try
          Pkg.precompile(Pkg.PackageSpec(name = "Vulkan"))
          report("PRECOMPILE_OK=yes")
        catch e
          report("PRECOMPILE_OK=no")
          report("PRECOMPILE_MSG=", sanitize(sprint(showerror, e)))
        end
      finally
        isfile(lp) && rm(lp)   # restore default state (auto)
      end
    else
      error("unknown mode: $mode")
    end
  catch e
    report("ERROR_CAUGHT=yes")
    report("ERROR_TYPE=", typeof(e).name === :ErrorException ? "ErrorException" : string(typeof(e)))
    report("ERROR_MSG=", sanitize(string(e)))
  end
  report("DONE")
end

main()
