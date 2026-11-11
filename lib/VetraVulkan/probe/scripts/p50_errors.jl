#!/usr/bin/env julia
# R040 probe p50: error paths and device-free install behavior.
#
# Records, with the KHRONOS layer build on VK_LAYER_PATH (inherited):
# - no-device: with VK_DRIVER_FILES pointed at nothing, device discovery
#   fails with a meaningful error (not a segfault or silent success).
#   All other environment variables (PATH, LD_LIBRARY_PATH, VK_LAYER_PATH)
#   are INHERITED — only VK_DRIVER_FILES is overridden (addenv merge).
# - bogus device extension: vkCreateDevice with a non-existent extension
#   fails with a meaningful Vulkan error
# - unsupported format: image creation for a (format, tiling, usage) the
#   device does not support fails with a meaningful error
# - device-free precompile: in an ISOLATED temp project + temp first depot
#   (read-through to the user depot), Pkg.instantiate installs the pinned
#   stack (incl. SPIRV) and Pkg.precompile runs Vulkan's @compile_workload
#   with no device available, for PRECOMPILE_DEVICE_FUNCTIONS =
#   false / auto (default) / true. Preferences live in the temp project
#   only; the user's depot compiled cache and LocalPreferences are never
#   touched, and nothing shared is deleted.
#
# Each scenario runs in a child Julia process (scripts/p50_child.jl) so a
# failure is captured as structured output, not a probe crash.
include(joinpath(@__DIR__, "probe_common.jl"))
using .ProbeCommon: check, write_evidence, reset_checks, run_capture, CHECKS

const PROBE_ROOT = dirname(@__DIR__)
const EVIDENCE = joinpath(PROBE_ROOT, "evidence")
const BOGUS_ICD = joinpath(tempdir(), "r040-nonexistent-icd.json")

function run_child(mode, env::Vector{Pair{String,String}}, extra::Vector{String} = String[],
                   project::String = PROBE_ROOT)
  julia = joinpath(Sys.BINDIR, "julia")
  cmd = Cmd(vcat([julia, "--startup-file=no", "--project=$project",
                  joinpath(PROBE_ROOT, "scripts", "p50_child.jl"), mode], extra))
  (out, err, code) = run_capture(cmd; env = env)
  parsed = Dict{String, String}()
  for l in split(out, "\n")
    m = match(r"^([A-Z_][A-Z_0-9]*)(?:=(.*))?$", strip(l))
    !isnothing(m) && (parsed[m.captures[1]] = isnothing(m.captures[2]) ? "" : m.captures[2])
  end
  tail = err
  length(tail) > 2000 && (tail = last(tail, 2000))
  (parsed = parsed, stderr = tail, stderr_full = err, exit = code)
end

function main()
  reset_checks()
  ev = Dict{String, Any}()
  ev["bogus_icd_file"] = BOGUS_ICD
  isfile(BOGUS_ICD) && error("bogus ICD path must not exist")

  # --- no device -----------------------------------------------------------------
  r = run_child("no_device", ["VK_DRIVER_FILES" => BOGUS_ICD])
  ev["no_device"] = Dict("exit" => r.exit, "error_caught" => get(r.parsed, "ERROR_CAUGHT", ""),
                          "error_type" => get(r.parsed, "ERROR_TYPE", ""),
                          "error_msg" => get(r.parsed, "ERROR_MSG", ""),
                          "stderr_tail" => r.stderr,
                          "env_note" => "VK_DRIVER_FILES overridden; PATH/LD_LIBRARY_PATH/VK_LAYER_PATH inherited (addenv merge)")
  msg = get(r.parsed, "ERROR_MSG", "")
  check("no-device: meaningful error (loader fails instance creation with INCOMPATIBLE_DRIVER)",
        r.exit == 0 && get(r.parsed, "ERROR_CAUGHT", "") == "yes" &&
        (occursin("INCOMPATIBLE_DRIVER", msg) || occursin("No Vulkan physical devices found", msg)),
        msg)

  # --- bogus device extension ------------------------------------------------------
  r = run_child("bogus_ext", Pair{String,String}[])
  ev["bogus_ext"] = Dict("exit" => r.exit, "error_caught" => get(r.parsed, "ERROR_CAUGHT", ""),
                          "error_type" => get(r.parsed, "ERROR_TYPE", ""),
                          "error_msg" => get(r.parsed, "ERROR_MSG", ""),
                          "stderr_tail" => r.stderr)
  msg = get(r.parsed, "ERROR_MSG", "")
  check("bogus device extension: meaningful Vulkan error (EXTENSION_NOT_PRESENT)",
        r.exit == 0 && get(r.parsed, "ERROR_CAUGHT", "") == "yes" && occursin("EXTENSION_NOT_PRESENT", msg),
        msg)

  # --- unsupported format -----------------------------------------------------------
  r = run_child("bad_format", Pair{String,String}[])
  ev["bad_format"] = Dict("exit" => r.exit, "error_caught" => get(r.parsed, "ERROR_CAUGHT", ""),
                           "error_msg" => get(r.parsed, "ERROR_MSG", ""),
                           "stderr_tail" => r.stderr)
  msg = get(r.parsed, "ERROR_MSG", "")
  check("unsupported format: meaningful error naming the format/usage",
        r.exit == 0 && get(r.parsed, "ERROR_CAUGHT", "") == "yes" && occursin("not supported on this device", msg),
        msg)

  # --- device-free precompile in an ISOLATED environment ----------------------------
  # temp project (owned copy of the pinned Project.toml) + temp first depot
  # (read-through to the user depot): the user's compiled cache and
  # LocalPreferences are never touched or deleted.
  for pref in ("false", "auto", "true")
    tmpdir = mktempdir()
    tmpproj = joinpath(tmpdir, "project")
    tmpdepot = joinpath(tmpdir, "depot")
    mkdir(tmpproj)
    try
      open(joinpath(tmpproj, "Project.toml"), "w") do io
        write(io, read(joinpath(PROBE_ROOT, "Project.toml"), String))
      end
      open(joinpath(tmpproj, "Manifest.toml"), "w") do io
        write(io, read(joinpath(PROBE_ROOT, "Manifest.toml"), String))
      end
      # the temp project copies the probe's name (VetraVulkanProbe) but has no
      # src/: give it a trivial module so Pkg.instantiate/precompile is clean.
      mkdir(joinpath(tmpproj, "src"))
      open(joinpath(tmpproj, "src", "VetraVulkanProbe.jl"), "w") do io
        write(io, "module VetraVulkanProbe\nend\n")
      end
      env = Pair{String,String}["JULIA_DEPOT_PATH" => tmpdepot * ":" * DEPOT_PATH[1],
                                 "VK_DRIVER_FILES" => BOGUS_ICD]
      r = run_child("precompile", env, [pref], tmpproj)
      ev["precompile_$pref"] = Dict("exit" => r.exit,
                                    "instantiate_ok" => get(r.parsed, "INSTANTIATE_OK", ""),
                                    "sources_exact" => get(r.parsed, "SOURCES_EXACT", ""),
                                    "vulkan_precompile_ok" => get(r.parsed, "PRECOMPILE_OK_VULKAN", ""),
                                    "spirv_precompile_ok" => get(r.parsed, "PRECOMPILE_OK_SPIRV", ""),
                                    "precompile_msg" => get(r.parsed, "PRECOMPILE_MSG_VULKAN", get(r.parsed, "PRECOMPILE_MSG_SPIRV", "")),
                                    "installed" => get(r.parsed, "INSTALLED", ""),
                                    "workload_ran" => occursin("Found no drivers", r.stderr_full) || occursin("INCOMPATIBLE_DRIVER", r.stderr_full),
                                    "stderr_tail" => r.stderr)
    finally
      rm(tmpdir; recursive = true, force = true)
    end
  end
  ev["precompile_semantics"] = "Isolated temp project + temp first depot (read-through to the user depot); the preference is written to the temp project's LocalPreferences.toml BEFORE Pkg.instantiate, so the install-time precompile already runs under it. The copied sources are identified by uuid + git-tree-sha1 (the Base.version_slug depot dir) — exact pinned identity, not a version-string match — and must land at the exact slug path in the temp depot so Pkg resolves them there. Vulkan.jl 0.6.30 @compile_workload gates the device workload on preference PRECOMPILE_DEVICE_FUNCTIONS (default auto). auto: workload runs, its no-driver failure is caught+logged (loader 'Found no drivers' visible), precompile succeeds; false: workload skipped; true: failure rethrown, Pkg.precompile(Vulkan) fails with INCOMPATIBLE_DRIVER."
  pf = ev["precompile_false"]
  pa = ev["precompile_auto"]
  pt = ev["precompile_true"]
  check("precompile without device, pref=false: succeeds, device workload skipped",
        occursin("Vulkan/", pf["sources_exact"]) && occursin("SPIRV/", pf["sources_exact"]) &&
        occursin("tree=", pf["sources_exact"]) && occursin("rev=", pf["sources_exact"]) &&
        pf["instantiate_ok"] == "yes" && pf["vulkan_precompile_ok"] == "yes" &&
        pf["spirv_precompile_ok"] == "yes" && pf["exit"] == 0 && pf["workload_ran"] === false,
        "sources=$(pf["sources_exact"])")
  check("precompile without device, pref=auto (default): succeeds, device failure caught",
        occursin("Vulkan/", pa["sources_exact"]) && occursin("SPIRV/", pa["sources_exact"]) &&
        pa["instantiate_ok"] == "yes" && pa["vulkan_precompile_ok"] == "yes" &&
        pa["spirv_precompile_ok"] == "yes" && pa["exit"] == 0 && pa["workload_ran"] === true,
        "sources=$(pa["sources_exact"])")
  check("precompile without device, pref=true: fails with a clear no-driver message",
        pt["vulkan_precompile_ok"] == "no" &&
        (occursin("INCOMPATIBLE_DRIVER", pt["precompile_msg"]) ||
         occursin("failed to precompile", pt["precompile_msg"])),
        pt["precompile_msg"])
  check("optional provider install incl. SPIRV in the isolated env",
        occursin("SPIRV", pf["installed"]) && occursin("Vulkan", pf["installed"]),
        pf["installed"])
  check("install/precompile does not silently require a device (auto and false succeed)",
        pa["vulkan_precompile_ok"] == "yes" && pf["vulkan_precompile_ok"] == "yes")

  npass, nfail = count(x -> x[2], CHECKS), count(x -> !x[2], CHECKS)
  ev["summary"] = Dict("pass" => npass, "fail" => nfail)
  ev["checks"] = [Dict("name" => c[1], "ok" => c[2], "detail" => c[3]) for c in CHECKS]
  path = write_evidence(joinpath(EVIDENCE, "p50_errors.json"), ev)
  println("evidence: ", path, " | pass=", npass, " fail=", nfail)
  nfail > 0 && exit(1)
  ev
end

const _here = @__MODULE__
if _here == Main
  main()
end
