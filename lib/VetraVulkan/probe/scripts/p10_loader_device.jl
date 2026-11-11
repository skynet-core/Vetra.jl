#!/usr/bin/env julia
# R040 probe p10: loader / instance / device / queue discovery.
#
# - which loader library the wrapper dlopens (system libvulkan on 0.6.x)
# - instance layer/extension discovery (incl. KHRONOS validation layer)
# - physical device inventory: name, api version, driver version, type, uuid
# - queue families with compute/graphics flags and counts
# - per-device feature support relevant to the shader routes under test
#   (variable pointers, BDA, Vulkan memory model, float64/int64, ...)
# - memory types (host-coherent index, device-local index)
# - R8G8B8A8_UNORM format support (optimal tiling: transfer + color attach)
#
# Self-checks: loader dlopens, >=1 device, selected device has a
# graphics+compute queue family, format supported, layer present iff env set.
using Vulkan
import Vulkan: QUEUE_GRAPHICS_BIT, QUEUE_COMPUTE_BIT, QUEUE_TRANSFER_BIT, FORMAT_R8G8B8A8_UNORM,
               FORMAT_FEATURE_COLOR_ATTACHMENT_BIT, FORMAT_FEATURE_TRANSFER_SRC_BIT, FORMAT_FEATURE_TRANSFER_DST_BIT,
               MEMORY_PROPERTY_DEVICE_LOCAL_BIT, MEMORY_PROPERTY_HOST_VISIBLE_BIT, MEMORY_PROPERTY_HOST_COHERENT_BIT
using Libdl
include(joinpath(@__DIR__, "probe_common.jl"))
using .ProbeCommon: check, write_evidence, reset_checks, make_instance, physical_devices,
                    device_props, pick_device, query_supported_features, queue_family, memory_index,
                    instance_layers, instance_extensions, release, refcount_ok,
                    validation_clean, validation_evidence, validation_errors, validation_warnings, CHECKS

const PROBE_ROOT = dirname(@__DIR__)
const EVIDENCE = joinpath(PROBE_ROOT, "evidence")

function feature_table(f)
  D = Dict{String, Any}()
  f2 = f.features2
  structs = [f2.features::Vulkan.PhysicalDeviceFeatures,
             f2.next::Vulkan.PhysicalDeviceVulkan11Features,
             (f2.next::Vulkan.PhysicalDeviceVulkan11Features).next::Vulkan.PhysicalDeviceVulkan12Features,
             ((f2.next::Vulkan.PhysicalDeviceVulkan11Features).next::Vulkan.PhysicalDeviceVulkan12Features).next::Vulkan.PhysicalDeviceVulkan13Features]
  for s in structs
    for name in fieldnames(typeof(s))
      val = getfield(s, name)
      if val isa Bool
        D[string(name)] = val
      end
    end
  end
  D
end

function main()
  reset_checks()
  ev = Dict{String, Any}()

  # --- loader -----------------------------------------------------------------
  # Vulkan.jl 0.6.x has no artifact-loader preference: it dlopens the system
  # libvulkan (JULIA_VULKAN_LIBNAME can override the soname). Record what we
  # actually load.
  loader = Dict{String, Any}()
  resolved = Libdl.find_library(Sys.islinux() ? "libvulkan.so.1" : Sys.isapple() ? "libvulkan.dylib" : "vulkan-1.dll")
  lib = dlopen(resolved)
  try
    loader["dlopen_libvulkan"] = "ok"
    loader["resolved_path"] = resolved
    loader["env_override"] = get(ENV, "JULIA_VULKAN_LIBNAME", nothing)
  finally
    dlclose(lib)
  end
  ev["loader"] = loader
  check("system libvulkan dlopens", true, "resolved=$(resolved)")

  # --- instance ----------------------------------------------------------------
  inst, msg, layers_used = make_instance(; validation = true, api = v"1.3")
  ev["instance"] = Dict("layers_enabled" => layers_used,
                        "all_layers" => instance_layers(),
                        "all_extensions" => instance_extensions(),
                        "validation_layer_requested" => true,
                        "validation_layer_enabled" => ("VK_LAYER_KHRONOS_validation" in layers_used))
  check("validation layer enabled when requested (make_instance refuses to downgrade)",
        layers_used == ["VK_LAYER_KHRONOS_validation"],
        "enabled=$(layers_used)")

  # --- devices ------------------------------------------------------------------
  phs = physical_devices(inst)
  devices = Dict{String, Any}()
  for ph in phs
    p = device_props(ph)
    d = Dict{String, Any}()
    d["api_version"] = string(p.api_version)
    d["driver_version"] = string(p.driver_version)
    d["device_type"] = string(p.device_type)
    d["uuid"] = join(string.(Int64, reverse(collect(p.pipeline_cache_uuid))), "")
    # queue families
    qfs = Dict{String, Any}()
    qfp = unwrap(Vulkan.get_physical_device_queue_family_properties(ph))
    for (i, q) in enumerate(qfp)
      qfs[string(i - 1)] = Dict("flags" => Int(q.queue_flags),
                                "count" => Int(q.queue_count),
                                "timestamp_valid" => string(q.timestamp_valid_bits),
                                "graphics" => (Int(q.queue_flags) & Int(QUEUE_GRAPHICS_BIT)) != 0,
                                "compute" => (Int(q.queue_flags) & Int(QUEUE_COMPUTE_BIT)) != 0,
                                "transfer" => (Int(q.queue_flags) & Int(QUEUE_TRANSFER_BIT)) != 0)
    end
    d["queue_families"] = qfs
    d["features"] = feature_table(query_supported_features(ph))
    # memory types
    mp = unwrap(Vulkan.get_physical_device_memory_properties(ph))
    mems = Dict{String, Any}()
    for i in 1:mp.memory_type_count
      mt = mp.memory_types[i]
      mems[string(i - 1)] = Dict("properties" => string(mt.property_flags),
                                 "device_local" => (Int(mt.property_flags) & Int(MEMORY_PROPERTY_DEVICE_LOCAL_BIT)) != 0,
                                 "host_visible" => (Int(mt.property_flags) & Int(MEMORY_PROPERTY_HOST_VISIBLE_BIT)) != 0,
                                 "host_coherent" => (Int(mt.property_flags) & Int(MEMORY_PROPERTY_HOST_COHERENT_BIT)) != 0)
    end
    d["memory_types"] = mems
    d["heaps"] = [Int(mp.memory_heaps[i].size) for i in 1:mp.memory_heap_count]
    # format support (these are FormatFeatureFlag bits, not ImageUsageFlag bits)
    fmt = Vulkan.get_physical_device_format_properties(ph, FORMAT_R8G8B8A8_UNORM)
    fp = unwrap(fmt)
    d["format_r8g8b8a8_unorm"] = Dict(
      "optimal_features" => Int(fp.optimal_tiling_features),
      "linear_features" => Int(fp.linear_tiling_features),
      "optimal_transfer" => (Int(fp.optimal_tiling_features) & Int(FORMAT_FEATURE_TRANSFER_SRC_BIT)) != 0,
      "optimal_color_attach" => (Int(fp.optimal_tiling_features) & Int(FORMAT_FEATURE_COLOR_ATTACHMENT_BIT)) != 0)
    devices[p.device_name] = d
  end
  ev["devices"] = devices
  check("at least one physical device", length(phs) >= 1, join([device_props(ph).device_name for ph in phs], " | "))

  # --- selection: prefer discrete NVIDIA, then AMD, then software ----------------
  for cand in ("NVIDIA GeForce", "AMD Radeon", "llvmpipe")
    sel, sp = try
      pick_device(inst; name_substring = cand)
    catch
      continue
    end
    p = sp
    d = devices[p.device_name]
    ev["selected_device"] = Dict{String, Any}("name" => p.device_name,
                                 "api_version" => d["api_version"],
                                 "device_type" => d["device_type"])
    qi = queue_family(sel, QUEUE_GRAPHICS_BIT | QUEUE_COMPUTE_BIT)
    ev["selected_device"]["queue_family_index"] = qi
    ev["selected_device"]["graphics"] = d["queue_families"][string(qi)]["graphics"]
    ev["selected_device"]["compute"] = d["queue_families"][string(qi)]["compute"]
    check("selected device has graphics+compute queue family",
          d["queue_families"][string(qi)]["graphics"] && d["queue_families"][string(qi)]["compute"],
          p.device_name)
    check("selected device api >= 1.2 (BDA route)", p.api_version >= v"1.2", string(p.api_version))
    check("R8G8B8A8_UNORM supports transfer+color-attach (optimal)",
          d["format_r8g8b8a8_unorm"]["optimal_transfer"] && d["format_r8g8b8a8_unorm"]["optimal_color_attach"],
          string(d["format_r8g8b8a8_unorm"]))
    ev["per_device_features"] = devices
    break
  end
  if !haskey(ev, "selected_device")
    check("selected device", false, "no candidate device found")
    ev["per_device_features"] = devices
  end

  # --- deterministic cleanup (messenger stays alive through device cleanup) ----
  release(msg)
  GC.gc()
  release(inst)
  GC.gc()
  check("refcount clean after release (no underflow)", refcount_ok(inst) && refcount_ok(msg), "")
  ev["validation"] = validation_evidence()
  check("no validation-layer ERROR/WARNING messages through cleanup + GC", validation_clean(),
        "$(length(validation_errors())) errors, $(length(validation_warnings())) warnings")

  npass, nfail = count(x -> x[2], CHECKS), count(x -> !x[2], CHECKS)
  ev["summary"] = Dict("pass" => npass, "fail" => nfail)
  ev["checks"] = [Dict("name" => c[1], "ok" => c[2], "detail" => c[3]) for c in CHECKS]
  path = write_evidence(joinpath(EVIDENCE, "p10_loader_device.json"), ev)
  println("evidence: ", path, " | pass=", npass, " fail=", nfail)
  nfail > 0 && exit(1)
  ev
end

const _here = @__MODULE__
if _here == Main
  main()
end
