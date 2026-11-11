#!/usr/bin/env julia
# R040 probe p50: error paths and device-free install behavior.
#
# Records, with the KHRONOS layer build on VK_LAYER_PATH (inherited):
# - no-device: with VK_DRIVER_FILES pointed at nothing, device discovery
#   fails with a meaningful error (not a segfault or silent success)
# - bogus device extension: vkCreateDevice with a non-existent extension
#   fails with a meaningful Vulkan error
# - unsupported format: image creation for a (format, tiling, usage) the
#   device does not support fails with a meaningful error
# - device-free precompile: `Pkg.precompile` of Vulkan with no device
#   available, for PRECOMPILE_DEVICE_FUNCTIONS = false / auto (default) /
#   true. Install must not silently require a device; the default (auto)
#   must succeed without one, and `true` must fail with a clear message.
#
# Each scenario runs in a child Julia process (scripts/p50_child.jl) so a
# failure is captured as structured output, not a probe crash.
include(joinpath(@__DIR__, "probe_common.jl"))
using .ProbeCommon: check, write_evidence, reset_checks, run_capture, CHECKS

const PROBE_ROOT = dirname(@__DIR__)
const EVIDENCE = joinpath(PROBE_ROOT, "evidence")
const BOGUS_ICD = joinpath(tempdir(), "r040-nonexistent-icd.json")

function run_child(mode, env::Vector{String}, extra::Vector{String} = String[])
  julia = joinpath(Sys.BINDIR, "julia")
  cmd = Cmd(vcat([julia, "--startup-file=no", "--project=$PROBE_ROOT",
                  joinpath(PROBE_ROOT, "scripts", "p50_child.jl"), mode], extra))
  (out, err, code) = run_capture(cmd; env = env)
  parsed = Dict{String, String}()
  for l in split(out, "\n")
    m = match(r"^([A-Z_]+)(?:=(.*))?$", strip(l))
    !isnothing(m) && (parsed[m.captures[1]] = isnothing(m.captures[2]) ? "" : m.captures[2])
  end
  tail = err
  length(tail) > 2000 && (tail = tail[end - 1999 : end])
  (parsed = parsed, stderr = tail, exit = code)
end

function main()
  reset_checks()
  ev = Dict{String, Any}()
  ev["bogus_icd_file"] = BOGUS_ICD
  isfile(BOGUS_ICD) && error("bogus ICD path must not exist")

  # --- no device -----------------------------------------------------------------
  r = run_child("no_device", ["VK_DRIVER_FILES=$BOGUS_ICD"])
  ev["no_device"] = Dict("exit" => r.exit, "error_caught" => get(r.parsed, "ERROR_CAUGHT", ""),
                         "error_type" => get(r.parsed, "ERROR_TYPE", ""),
                         "error_msg" => get(r.parsed, "ERROR_MSG", ""),
                         "stderr_tail" => r.stderr,
                         "note" => "VK_DRIVER_FILES pointed at nothing, so the loader had no ICD; vkCreateInstance failed with a meaningful VulkanError instead of a silent success or segfault")
  msg = get(r.parsed, "ERROR_MSG", "")
  check("no-device: meaningful error (loader fails instance creation with INCOMPATIBLE_DRIVER)",
        r.exit == 0 && get(r.parsed, "ERROR_CAUGHT", "") == "yes" &&
        (occursin("INCOMPATIBLE_DRIVER", msg) || occursin("No Vulkan physical devices found", msg)),
        msg)

  # --- bogus device extension ------------------------------------------------------
  r = run_child("bogus_ext", String[])
  ev["bogus_ext"] = Dict("exit" => r.exit, "error_caught" => get(r.parsed, "ERROR_CAUGHT", ""),
                         "error_type" => get(r.parsed, "ERROR_TYPE", ""),
                         "error_msg" => get(r.parsed, "ERROR_MSG", ""),
                         "stderr_tail" => r.stderr)
  msg = get(r.parsed, "ERROR_MSG", "")
  check("bogus device extension: meaningful Vulkan error (EXTENSION_NOT_PRESENT)",
        r.exit == 0 && get(r.parsed, "ERROR_CAUGHT", "") == "yes" && occursin("EXTENSION_NOT_PRESENT", msg),
        msg)

  # --- unsupported format -----------------------------------------------------------
  r = run_child("bad_format", String[])
  ev["bad_format"] = Dict("exit" => r.exit, "error_caught" => get(r.parsed, "ERROR_CAUGHT", ""),
                          "error_msg" => get(r.parsed, "ERROR_MSG", ""),
                          "stderr_tail" => r.stderr)
  msg = get(r.parsed, "ERROR_MSG", "")
  check("unsupported format: meaningful error naming the format/usage",
        r.exit == 0 && get(r.parsed, "ERROR_CAUGHT", "") == "yes" && occursin("not supported on this device", msg),
        msg)

  # --- device-free precompile ---------------------------------------------------------
  for pref in ("false", "auto", "true")
    r = run_child("precompile", ["VK_DRIVER_FILES=$BOGUS_ICD"], [pref])
    ev["precompile_$pref"] = Dict("exit" => r.exit,
                                  "precompile_ok" => get(r.parsed, "PRECOMPILE_OK", ""),
                                  "precompile_msg" => get(r.parsed, "PRECOMPILE_MSG", ""),
                                  "workload_ran" => occursin("Found no drivers", r.stderr) || occursin("INCOMPATIBLE_DRIVER", r.stderr),
                                  "stderr_tail" => r.stderr)
  end
  ev["precompile_semantics"] = "Vulkan.jl 0.6.30 @compile_workload gates the device workload on preference PRECOMPILE_DEVICE_FUNCTIONS (default auto), set through the project's LocalPreferences.toml via Vulkan.set_preferences! (this Pkg has no set_preference; this Preferences version has no env-var override). auto: workload runs, its failure is caught+logged, precompile succeeds; false: workload skipped; true: failure rethrown, precompile fails."
  check("precompile without device, pref=false: succeeds, device workload skipped",
        ev["precompile_false"]["precompile_ok"] == "yes" && ev["precompile_false"]["exit"] == 0 &&
        ev["precompile_false"]["workload_ran"] === false,
        ev["precompile_false"]["precompile_msg"])
  check("precompile without device, pref=auto (default): succeeds, device failure caught",
        ev["precompile_auto"]["precompile_ok"] == "yes" && ev["precompile_auto"]["exit"] == 0 &&
        ev["precompile_auto"]["workload_ran"] === true,
        ev["precompile_auto"]["precompile_msg"])
  check("precompile without device, pref=true: fails with a clear no-driver message",
        ev["precompile_true"]["precompile_ok"] == "no" &&
        (occursin("INCOMPATIBLE_DRIVER", ev["precompile_true"]["precompile_msg"]) ||
         occursin("failed to precompile", ev["precompile_true"]["precompile_msg"])),
        ev["precompile_true"]["precompile_msg"])
  check("install/precompile does not silently require a device (auto and false succeed)",
        ev["precompile_auto"]["precompile_ok"] == "yes" && ev["precompile_false"]["precompile_ok"] == "yes")

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
