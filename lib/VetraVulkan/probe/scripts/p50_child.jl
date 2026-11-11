#!/usr/bin/env julia
# R040 probe p50 child: exercise ONE error/install path and report the outcome.
#
# argv: mode [extra...]
#   no_device        : expect a meaningful error from device discovery
#                      (VK_DRIVER_FILES must point at nothing in the env;
#                      all other env inherited)
#   bogus_ext        : expect a meaningful error creating a device with a
#                      non-existent device extension
#   bad_format       : expect a meaningful error for an unsupported
#                      (format, tiling, usage) combination
#   precompile       : in an ISOLATED temp project (active via --project)
#                      with a temp first depot (JULIA_DEPOT_PATH set by the
#                      parent, read-through to the user depot):
#                      Pkg.instantiate installs the pinned stack (incl. SPIRV),
#                      the preference is set in the TEMP project only (via
#                      Preferences, without loading Vulkan in this process),
#                      and Pkg.precompile(Vulkan)/Pkg.precompile(SPIRV) run
#                      fresh precompiles with no device available. The
#                      user's compiled cache and LocalPreferences are never
#                      touched.
#
# Prints MODE=, ERROR_CAUGHT=, ERROR_TYPE=, ERROR_MSG= (single line),
# INSTALLED=, PRECOMPILE_OK_<pkg>=, PRECOMPILE_MSG_<pkg>=, DONE. The parent
# (p50_errors.jl) captures it through run_capture; a crash is recorded as an
# exit code. Created handles are released in a finally block on every path.
using Pkg

const PROBE_ROOT = dirname(@__DIR__)

function report(xs...)
  println(xs...)
  flush(stdout)
end

function sanitize(s)
  replace(replace(s, "\n" => "\\n"), "\r" => "")
end

mode = ARGS[1]
report("MODE=", mode)
inst = nothing
msg = nothing
dev = nothing
try
  if mode == "precompile"
    pref = ARGS[2]   # false / auto / true
    act = dirname(Pkg.project().path)
    man = Pkg.TOML.parsefile(joinpath(act, "Manifest.toml"))
    function mv(name)
      e = man["deps"][name]
      e = e isa Vector ? e[1] : e
      string(e["version"])
    end
    # Force a FRESH precompile in this owned env (the read-through user depot
    # holds valid .ji caches that would otherwise be reused and silently skip
    # Vulkan's @compile_workload): copy the manifest-resolved package sources
    # into the temp first depot so the source path (and .ji cache key) differs.
    # Only the exact resolved version is copied — never the whole depot dir.
    function copy_source(pkg, into)
      for depot in DEPOT_PATH[2:end]
        srcroot = joinpath(depot, "packages", pkg)
        isdir(srcroot) || continue
        for sub in readdir(srcroot)
          pt = joinpath(srcroot, sub, "Project.toml")
          isfile(pt) || continue
          string(Pkg.TOML.parsefile(pt)["version"]) == mv(pkg) || continue
          mkpath(joinpath(into, "packages", pkg))
          cp(joinpath(srcroot, sub), joinpath(into, "packages", pkg, sub))
          return sub
        end
      end
      nothing
    end
    sub_vk = copy_source("Vulkan", DEPOT_PATH[1])
    sub_sp = copy_source("SPIRV", DEPOT_PATH[1])
    sub_vk === nothing && error("manifest-resolved Vulkan $(mv("Vulkan")) source not found in the read-through depots")
    sub_sp === nothing && error("manifest-resolved SPIRV $(mv("SPIRV")) source not found in the read-through depots")
    report("SOURCES_COPIED=", "Vulkan/", sub_vk, " SPIRV/", sub_sp, " -> ", DEPOT_PATH[1])
    # The preference lives in the TEMP project's LocalPreferences.toml only
    # (the parent deletes the whole temp tree afterwards; the user's
    # preferences are never touched). Written BEFORE Pkg.instantiate so the
    # install-time precompile already runs under the requested pref.
    lp = joinpath(act, "LocalPreferences.toml")
    isfile(lp) && rm(lp)
    if pref != "auto"
      open(lp, "w") do io
        write(io, "[Vulkan]\nPRECOMPILE_DEVICE_FUNCTIONS = \"$pref\"\n")
      end
    end
    # install the pinned stack into the isolated env (temp first depot,
    # read-through to the user depot for all other packages)
    try
      Pkg.instantiate()
      report("INSTANTIATE_OK=yes")
    catch e
      report("INSTANTIATE_OK=no")
      report("INSTANTIATE_MSG=", sanitize(sprint(showerror, e)))
    end
    report("INSTALLED=", "Vulkan=", mv("Vulkan"), " SPIRV=", mv("SPIRV"), " VulkanCore=", mv("VulkanCore"))
    # explicit Pkg.precompile: re-runs the named package's precompile when its
    # cache is invalid (pref=true: the failed workload left no valid cache ->
    # rethrows the no-driver error), reports ok when the cache is valid
    # (pref=false/auto).
    for pkg in ("Vulkan", "SPIRV")
      key = uppercase(pkg)
      try
        Pkg.precompile(Pkg.PackageSpec(name = pkg))
        report("PRECOMPILE_OK_", key, "=yes")
      catch e
        report("PRECOMPILE_OK_", key, "=no")
        report("PRECOMPILE_MSG_", key, "=", sanitize(sprint(showerror, e)))
      end
    end
  else
    using Vulkan
    using Vulkan: Vk, VkCore, unwrap
    include(joinpath(PROBE_ROOT, "scripts", "probe_common.jl"))
    using .ProbeCommon: make_instance, pick_device, make_device, queue_family, offscreen_image

    import Vulkan:
      SHADER_STAGE_COMPUTE_BIT, PIPELINE_BIND_POINT_COMPUTE,
      QUEUE_GRAPHICS_BIT, QUEUE_COMPUTE_BIT,
      IMAGE_TYPE_2D, IMAGE_TILING_OPTIMAL,
      IMAGE_USAGE_TRANSFER_SRC_BIT, IMAGE_USAGE_TRANSFER_DST_BIT, IMAGE_USAGE_COLOR_ATTACHMENT_BIT,
      FORMAT_FEATURE_TRANSFER_SRC_BIT, FORMAT_FEATURE_TRANSFER_DST_BIT, FORMAT_FEATURE_COLOR_ATTACHMENT_BIT,
      FORMAT_R4G4_UNORM_PACK8, FORMAT_R4G4B4A4_UNORM_PACK16,
      FORMAT_R32_UINT, FORMAT_S8_UINT, FORMAT_R16_UINT, FORMAT_A2B10G10R10_UNORM_PACK32

    if mode == "no_device"
      global (inst, msg, _layers) = make_instance(; validation = false)
      _ = pick_device(inst)
      report("ERROR_CAUGHT=no (unexpected: a device was found)")
    elseif mode == "bogus_ext"
      global (inst, msg, _layers) = make_instance(; validation = false)
      ph, _props = pick_device(inst; name_substring = "NVIDIA GeForce")
      qi = queue_family(ph, QUEUE_GRAPHICS_BIT | QUEUE_COMPUTE_BIT)
      _ = make_device(inst, ph; qi = qi, extensions = ["VK_FAKE_ext_bogus"])
      report("ERROR_CAUGHT=no (unexpected: bogus extension accepted)")
    elseif mode == "bad_format"
      global (inst, msg, _layers) = make_instance(; validation = false)
      ph, _props = pick_device(inst; name_substring = "NVIDIA GeForce")
      qi = queue_family(ph, QUEUE_GRAPHICS_BIT | QUEUE_COMPUTE_BIT)
      global dev = make_device(inst, ph; qi = qi)
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
    else
      error("unknown mode: $mode")
    end
  end
catch e
  report("ERROR_CAUGHT=yes")
  report("ERROR_TYPE=", typeof(e).name === :ErrorException ? "ErrorException" : string(typeof(e)))
  report("ERROR_MSG=", sanitize(string(e)))
finally
  # deterministic cleanup on EVERY path (success and failure): reverse order,
  # Base.finalize (invokes + unregisters the finalizer), so no double-destroy
  # when the GC later finalizes what it reaches.
  for h in (dev, msg, inst)
    h !== nothing && Base.finalize(h)
  end
  GC.gc()
end
report("DONE")
