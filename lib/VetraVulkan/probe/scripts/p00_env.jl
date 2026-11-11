#!/usr/bin/env julia
# R040 probe p00: pinned environment evidence.
#
# Records, with exact versions and file hashes:
# - Julia/OS, resolved package set (registry + git rev of SPIRV.jl)
# - system Vulkan loader/ICD/layer inventory (read-only)
# - spirv-val provenance (SPIRV_Tools_jll) and version
# - Vulkan validation layer build provenance (if present on VK_LAYER_PATH)
#
# Self-checks: spirv-val runs; KHRONOS validation layer is discoverable.
using Pkg
using SPIRV_Tools_jll
using Vulkan
include(joinpath(@__DIR__, "probe_common.jl"))
using .ProbeCommon: check, write_evidence, reset_checks, instance_layers, instance_extensions, run_capture, CHECKS

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

# ---------------------------------------------------------------------------
# Minimal JSON reader for the flat Vulkan .json manifests (only the fields we
# need: top-level object, nested objects, strings). Keeps the probe free of
# any JSON package dependency.
# ---------------------------------------------------------------------------

function parse_json_object(s)
  @assert startswith(s, "{")
  rest = s[2:end]
  obj = Dict{String, Any}()
  while true
    rest = strip(rest)
    isempty(rest) && error("unterminated object in: $s")
    if rest[1] == '}'
      rest = rest[2:end]
      break
    end
    key, rest = parse_json_string(rest)
    rest = strip(rest)
    rest[1] == ':' || error("expected ':' while parsing manifest: $rest")
    rest = strip(rest[2:end])
    val, rest = parse_json_value(rest)
    obj[key] = val
    rest = strip(rest)
    if rest[1] == ','
      rest = rest[2:end]
    elseif rest[1] == '}'
      rest = rest[2:end]
      break
    else
      error("expected ',' or '}' while parsing manifest: $rest")
    end
  end
  return (obj, rest)
end

function parse_json_string(s)
  s[1] == '"' || error("expected string: $s")
  i = findnext('"', s, 2)
  i === nothing && error("unterminated string in: $s")
  return (s[2:(i - 1)], s[(i + 1):end])
end

function parse_json_value(s)
  if s[1] == '{'
    obj, rest = parse_json_object(s)
    return (obj, rest)
  end
  s[1] == '"' && return parse_json_string(s)
  if s[1] == '['
    depth = 0
    in_str = false
    for (i, c) in enumerate(s)
      c == '"' && (in_str = !in_str)
      in_str && continue
      c == '[' && (depth += 1)
      c == ']' && (depth -= 1)
      depth == 0 && return (Any[], s[i + 1:end])
    end
    error("unterminated array in: $s")
  end
  for (lit, val) in (("true", true), ("false", false), ("null", nothing))
    startswith(s, lit) && return (val, s[length(lit) + 1:end])
  end
  m = match(r"^-?[\d.eE+]+", s)
  isnothing(m) && error("cannot parse JSON value: $s")
  str = m.match
  val = occursin(('.', 'e', 'E'), str) ? parse(Float64, str) : parse(Int64, str)
  return (val, s[length(str) + 1:end])
end

function json_read(path)
  (obj, _rest) = parse_json_object(read(path, String))
  obj
end

# ---------------------------------------------------------------------------

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

  # --- system Vulkan inventory (read-only) ------------------------------------
  sys = Dict{String, Any}()
  if Sys.islinux()
    (real, _err, _code) = run_capture(`realpath /usr/lib/x86_64-linux-gnu/libvulkan.so.1`)
    sys["loader"] = Dict("library" => real, "sha256" => sha256sum(real))
  end
  icds = Dict{String, Any}()
  icd_dir = "/usr/share/vulkan/icd.d"
  for f in sort(readdir(icd_dir))
    endswith(f, ".json") || continue
    d = json_read(joinpath(icd_dir, f))
    icd = get(d, "ICD", Dict())
    lib = get(icd, "library_path", nothing)
    icds[f] = Dict("library_path" => lib,
                   "api_version" => get(icd, "api_version", get(d, "api_version", nothing)),
                   "library_sha256" => isnothing(lib) ? nothing : sha256sum(resolve_lib(lib)))
  end
  sys["icds"] = icds
  layers = Dict{String, Any}()
  for dir in ("/usr/share/vulkan/implicit_layer.d", "/usr/share/vulkan/explicit_layer.d")
    isdir(dir) || continue
    for f in sort(readdir(dir))
      endswith(f, ".json") || continue
      d = json_read(joinpath(dir, f))
      lay = get(d, "layer", nothing)
      for l in (isnothing(lay) ? Any[] : (lay isa Dict ? [lay] : lay))
        lib = get(l, "library_path", nothing)
        layers[get(l, "name", f)] = Dict("kind" => basename(dir), "file" => f,
                                         "library_path" => lib,
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
  ver_cmd = setenv(Cmd(vcat(bin_exec, ["--version"])), bin_cmd.env)
  (ver, _vererr, vcode) = run_capture(ver_cmd)
  ev["spirv_tools"] = Dict("spirv_val" => Dict("path" => bin_path, "sha256" => sha256sum(bin_path)),
                           "version_output" => ver)
  check("spirv-val runs", vcode == 0, ver)

  # --- external validation layer (built for this probe, see README) -------------
  vvl = Dict{String, Any}()
  lp = get(ENV, "VK_LAYER_PATH", nothing)
  if !isnothing(lp) && isdir(lp)
    for f in sort(readdir(lp))
      endswith(f, ".json") || continue
      d = json_read(joinpath(lp, f))
      lay = get(d, "layer", nothing)
      for l in (isnothing(lay) ? Any[] : (lay isa Dict ? [lay] : lay))
        lib = get(l, "library_path", nothing)
        full = isnothing(lib) ? nothing : resolve_lib(lib)
        vvl[get(l, "name", f)] = Dict("manifest" => joinpath(lp, f), "library" => full,
                                      "library_sha256" => isnothing(full) ? nothing : sha256sum(full))
      end
    end
  end
  ev["validation_layer_external"] = vvl
  check("KHRONOS validation layer discoverable through wrapper",
        "VK_LAYER_KHRONOS_validation" in instance_layers(),
        "instance layers: " * join(instance_layers(), ", "))

  ev["instance_extensions"] = instance_extensions()

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
