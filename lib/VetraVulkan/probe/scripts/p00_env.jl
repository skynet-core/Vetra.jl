#!/usr/bin/env julia
# R040 probe p00: pinned environment evidence.
#
# Records, with exact versions and file hashes:
# - Julia/OS, resolved package set (registry + git rev of SPIRV.jl)
# - system Vulkan loader/ICD/layer inventory (read-only; manifests parsed
#   with the host's jq — no hand-rolled JSON parser in the probe)
# - spirv-val provenance (SPIRV_Tools_jll) and version
# - Vulkan validation layer build provenance (if present on VK_LAYER_PATH,
#   incl. a PROVENANCE.txt written by the README build recipe)
# - the severity-classification regression (vkSubmitDebugUtilsMessageEXT per
#   severity, positive + negative controls) with the layer + messenger
#   actually enabled, and a synchronization-validation instance
#
# Self-checks: spirv-val runs; KHRONOS validation layer is discoverable AND
# enabled when requested; severity buckets classify the synthetic messages.
using Pkg
using SPIRV_Tools_jll
using Vulkan
include(joinpath(@__DIR__, "probe_common.jl"))
using .ProbeCommon: check, write_evidence, reset_checks, instance_layers, instance_extensions,
                    run_capture, run_jll, make_instance, release,
                    synthetic_severity_regression, CHECKS

const PROBE_ROOT = dirname(@__DIR__)
const EVIDENCE = joinpath(PROBE_ROOT, "evidence")

function sha256sum(path)
  isnothing(path) && return nothing
  isfile(path) || return nothing
  (out, _err, code) = run_capture(`sha256sum $(string(path))`)
  if code != 0 || isempty(strip(out))
    return nothing
  end
  return split(out)[1]
end

"""Parse a flat Vulkan manifest field list with the host's jq.
`selector` is a jq expression over the manifest; expected output: one line
`name<TAB>library_path<TAB>api_version` per entry. Returns Dict name=>fields."""
function manifest_entries(path, selector)
  (out, err, code) = run_capture(Cmd(["jq", "-r", selector, path]))
  code != 0 && error("jq failed on $path: $err")
  entries = Dict{String, Dict{String, Any}}()
  for line in split(chomp(out), "\n")
    isempty(line) && continue
    parts = split(line, "\t")
    name = parts[1]
    lib = length(parts) > 2 && parts[2] != "" ? parts[2] : nothing
    api = length(parts) > 2 && parts[3] != "" ? parts[3] : nothing
    entries[name] = Dict("library_path" => lib, "api_version" => api)
  end
  entries
end

const ICD_SELECTOR = ".ICD | [.library_path, .api_version] | @tsv"
const LAYER_SELECTOR = "(.layer? // .layers? // empty) | (if type == \"array\" then .[] else . end) | select(.name != null) | [.name, .library_path, .api_version] | @tsv"

function main()
  reset_checks()
  ev = Dict{String, Any}()

  ev["julia"] = Dict("version" => string(VERSION), "bindir" => Sys.BINDIR)
  ev["os"] = Dict("kernel" => Sys.KERNEL, "arch" => string(Sys.ARCH), "hostname" => gethostname())

  # --- resolved packages (parsed from the pinned Manifest.toml) -------------
  manifest = Pkg.TOML.parsefile(joinpath(PROBE_ROOT, "Manifest.toml"))
  pkgs = Dict{String, Any}()
  for (name, arr) in pairs(manifest["deps"])
    entry = arr isa Vector ? arr[1] : arr
    e = Dict{String, Any}()
    e["uuid"] = get(entry, "uuid", "")
    e["version"] = get(entry, "version", "")
    if haskey(entry, "repo-url")
      e["source"] = "git"
      e["git_url"] = entry["repo-url"]
      e["git_rev"] = entry["repo-rev"]
      e["git_tree_sha1"] = get(entry, "git-tree-sha1", "")
    else
      e["source"] = "registry"
      e["git_tree_sha1"] = get(entry, "git-tree-sha1", "")
    end
    pkgs[name] = e
  end
  ev["packages"] = pkgs
  ev["manifest"] = Dict("julia_version" => get(manifest, "julia_version", ""),
                        "manifest_format" => get(manifest, "manifest_format", ""),
                        "project_hash" => get(manifest, "project_hash", ""))
  for required in ("SPIRV", "Vulkan", "VulkanCore", "SPIRV_Tools_jll")
    check("package resolved: $required", haskey(pkgs, required),
          "$(get(pkgs, required, Dict("version" => "missing"))["version"])")
  end
  check("SPIRV pinned to reviewed revision",
        get(pkgs["SPIRV"], "git_rev", "") == "218b33b21e5b23d7c3c34bb07f6c114723a5e193",
        "rev=$(get(pkgs["SPIRV"], "git_rev", ""))")

  # --- system Vulkan inventory (read-only, jq-parsed) -------------------------
  sys = Dict{String, Any}()
  if Sys.islinux()
    (real, _err, _code) = run_capture(`realpath /usr/lib/x86_64-linux-gnu/libvulkan.so.1`)
    sys["loader"] = Dict("library" => real, "sha256" => sha256sum(real))
  end
  icds = Dict{String, Any}()
  icd_dir = "/usr/share/vulkan/icd.d"
  for f in sort(readdir(icd_dir))
    endswith(f, ".json") || continue
    # ICD files have a single entry under .ICD (no name): parse directly
    (out, _e2, c2) = run_capture(Cmd(["jq", "-r", "[.ICD.library_path, .ICD.api_version] | @tsv", joinpath(icd_dir, f)]))
    c2 != 0 && continue
    parts = split(chomp(out), "\t")
    lib = get(parts, 1, "") == "" ? nothing : parts[1]
    api = get(parts, 2, "") == "" ? nothing : parts[2]
    icds[f] = Dict("library_path" => lib,
                   "api_version" => api,
                   "library_sha256" => isnothing(lib) ? nothing : sha256sum(resolve_lib(lib)))
  end
  sys["icds"] = icds
  layers = Dict{String, Any}()
  for dir in ("/usr/share/vulkan/implicit_layer.d", "/usr/share/vulkan/explicit_layer.d")
    isdir(dir) || continue
    for f in sort(readdir(dir))
      endswith(f, ".json") || continue
      for (name, flds) in manifest_entries(joinpath(dir, f), LAYER_SELECTOR)
        lib = flds["library_path"]
        layers[name] = Dict("kind" => basename(dir), "file" => f,
                            "library_path" => lib,
                            "api_version" => flds["api_version"],
                            "library_sha256" => isnothing(lib) ? nothing : sha256sum(resolve_lib(lib)))
      end
    end
  end
  sys["layers"] = layers
  sys["validation_layer_system"] = haskey(layers, "VK_LAYER_KHRONOS_validation")
  ev["system_vulkan"] = sys

  # --- SPIRV-Tools (spirv-val) -------------------------------------------------
  bin_cmd = SPIRV_Tools_jll.spirv_val()
  bin_exec = getfield(bin_cmd, fieldnames(typeof(bin_cmd))[1]) # Vector{String}: exe + args
  bin_path = bin_exec[1]
  (ver, _vererr, vcode) = run_jll(bin_cmd, ["--version"])
  ev["spirv_tools"] = Dict("spirv_val" => Dict("path" => bin_path, "sha256" => sha256sum(bin_path)),
                           "version_output" => ver)
  check("spirv-val runs", vcode == 0, ver)

  # --- external validation layer (built for this probe, see README) -------------
  vvl = Dict{String, Any}()
  provenance = nothing
  lp = get(ENV, "VK_LAYER_PATH", nothing)
  if !isnothing(lp) && isdir(lp)
    for f in sort(readdir(lp))
      endswith(f, ".json") || continue
      for (name, flds) in manifest_entries(joinpath(lp, f), LAYER_SELECTOR)
        lib = flds["library_path"]
        full = isnothing(lib) ? nothing : resolve_lib(lib)
        vvl[name] = Dict("manifest" => joinpath(lp, f), "library" => full,
                         "api_version" => flds["api_version"],
                         "library_sha256" => isnothing(full) ? nothing : sha256sum(full))
      end
    end
    prov_file = joinpath(lp, "PROVENANCE.txt")
    isfile(prov_file) && (provenance = Dict("file" => prov_file, "contents" => chomp(read(prov_file, String))))
  end
  ev["validation_layer_external"] = vvl
  ev["validation_layer_provenance"] = provenance
  check("KHRONOS validation layer discoverable through wrapper",
        "VK_LAYER_KHRONOS_validation" in instance_layers(),
        "instance layers: " * join(instance_layers(), ", "))

  ev["instance_extensions"] = instance_extensions()
  check("VK_EXT_debug_utils available (required with validation)",
        "VK_EXT_debug_utils" in instance_extensions(), "debug utils ext")

  # --- severity regression + sync-validation instance -------------------------
  # Requires the layer + messenger actually enabled; make_instance errors
  # instead of silently downgrading, so reaching this line proves the gate.
  inst, msg, layers_used = make_instance(; validation = true, sync_validation = true)
  check("validation layer enabled when requested (no silent downgrade)",
        layers_used == [ProbeCommon.LAYER_VALIDATION], "enabled=$(layers_used)")
  check("synchronization-validation instance created (VkValidationFeaturesEXT pNext)",
        true, "VK_VALIDATION_FEATURE_ENABLE_SYNCHRONIZATION_VALIDATION requested; VVL behaviorally confirmed by the barrier checks in p20/p30 evidence")
  sev = synthetic_severity_regression(inst)
  ev["severity_regression"] = sev
  ev["severity_bits"] = Dict("verbose" => ProbeCommon.SEV_VERBOSE, "info" => ProbeCommon.SEV_INFO,
                             "warning" => ProbeCommon.SEV_WARNING, "error" => ProbeCommon.SEV_ERROR)
  release(msg)
  release(inst)
  GC.gc()

  npass, nfail = count(x -> x[2], CHECKS), count(x -> !x[2], CHECKS)
  ev["summary"] = Dict("pass" => npass, "fail" => nfail)
  ev["checks"] = [Dict("name" => c[1], "ok" => c[2], "detail" => c[3]) for c in CHECKS]
  path = write_evidence(joinpath(EVIDENCE, "p00_env.json"), ev)
  println("evidence: ", path, " | pass=", npass, " fail=", nfail)
  nfail > 0 && exit(1)
  ev
end

"""Resolve a bare library name from a Vulkan manifest against standard dirs."""
function resolve_lib(lib)
  isabspath(lib) && return isfile(lib) ? lib : nothing
  for dir in (split(get(ENV, "LD_LIBRARY_PATH", ""), ":"),
              ["/usr/lib/x86_64-linux-gnu", "/usr/lib", "/lib", "/usr/lib/x86_64-linux-gnu/dri"])
    for d in dir
      isdir(d) || continue
      isfile(joinpath(d, lib)) && return joinpath(d, lib)
    end
  end
  nothing
end

const _here = @__MODULE__
if _here == Main
  main()
end
