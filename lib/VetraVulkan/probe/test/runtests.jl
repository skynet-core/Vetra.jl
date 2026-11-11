#!/usr/bin/env julia
# R040 probe self-checks.
#
# Verifies the committed evidence artifacts under ../evidence/ (plus the
# Project.toml pins) with no GPU required: every probe's own check list
# (recorded in each evidence file's "checks"/"summary") must be all-pass, and
# the key claims of the R040 spec must hold in the data.
#
# Re-run the probes themselves (needs the GPU + layer env from the README)
# with R040_RUN_PROBES=1, then this file re-verifies the fresh evidence.

const PROBE_ROOT = joinpath(@__DIR__, "..")
const EVIDENCE = joinpath(PROBE_ROOT, "evidence")
const SPIRV_REV = "218b33b21e5b23d7c3c34bb07f6c114723a5e193"

# ---------------------------------------------------------------------------
# Minimal JSON reader (objects, arrays, strings, numbers, true/false/null).
# Parses the raw bytes (UTF-8 evidence strings stay intact). The probe
# environment is pinned without a JSON package on purpose.
# ---------------------------------------------------------------------------

mutable struct JParser
  b::Vector{UInt8}
  i::Int
end

function jskip(p::JParser)
  while p.i <= length(p.b) && p.b[p.i] in (0x09, 0x0a, 0x0d, 0x20)
    p.i += 1
  end
end

const JSON_ESC = Dict{UInt8, UInt8}(0x22 => 0x22, 0x5c => 0x5c, 0x2f => 0x2f,
                                    0x62 => 0x08, 0x66 => 0x0c, 0x6e => 0x0a,
                                    0x72 => 0x0d, 0x74 => 0x09)

"""Decode JSON escape sequences in raw string-body bytes.
Byte-level on purpose: this host build mangles Char indexing on
multibyte UTF-8 strings (length() and s[i] misbehave), so the whole
parser stays in byte space and only produces a String at the end."""
function junescape(raw::Vector{UInt8})
  out = Vector{UInt8}()
  i = 1
  n = length(raw)
  while i <= n
    c = raw[i]
    if c == 0x5c && i < n
      e = raw[i + 1]
      if e == 0x75   # 'u'
        cp = parse(UInt16, String(raw[i + 2:i + 5]); base = 16)
        append!(out, codeunits(Char(cp)))
        i += 6
      else
        v = get(JSON_ESC, e, nothing)
        v === nothing && error("bad escape byte $(e)")
        push!(out, v)
        i += 2
      end
    else
      push!(out, c)
      i += 1
    end
  end
  String(out)
end

function jstring(p::JParser)
  p.b[p.i] == 0x22 || error("expected string at byte $(p.i)")
  p.i += 1
  start = p.i
  while p.i <= length(p.b)
    if p.b[p.i] == 0x22
      raw = copy(p.b[start:(p.i - 1)])
      p.i += 1
      return junescape(raw)
    elseif p.b[p.i] == 0x5c
      p.i += 2   # escape pair; decoded in junescape
    else
      p.i += 1
    end
  end
  error("unterminated string")
end

function jnumber(p::JParser)
  j = p.i
  while p.i <= length(p.b) && (p.b[p.i] in 0x30:0x39 || p.b[p.i] in (0x2d, 0x2b, 0x2e))
    p.i += 1
  end
  str = String(p.b[j:(p.i - 1)])
  if occursin('.', str) || occursin('e', str) || occursin('E', str)
    parse(Float64, str)
  else
    parse(Int64, str)
  end
end

function jvalue(p::JParser)
  jskip(p)
  p.i > length(p.b) && error("unexpected end of JSON")
  c = p.b[p.i]
  if c == 0x7b   # '{'
    p.i += 1
    d = Dict{Any, Any}()
    jskip(p)
    p.i <= length(p.b) && p.b[p.i] == 0x7d && (p.i += 1; return d)
    while true
      jskip(p)
      k = jstring(p)
      jskip(p)
      p.b[p.i] == 0x3a || error("expected ':' at byte $(p.i)")
      p.i += 1
      d[k] = jvalue(p)
      jskip(p)
      if p.b[p.i] == 0x2c
        p.i += 1
      elseif p.b[p.i] == 0x7d
        p.i += 1
        return d
      else
        error("expected ',' or '}' at byte $(p.i)")
      end
    end
  elseif c == 0x5b   # '['
    p.i += 1
    a = Any[]
    jskip(p)
    p.i <= length(p.b) && p.b[p.i] == 0x5d && (p.i += 1; return a)
    while true
      push!(a, jvalue(p))
      jskip(p)
      if p.b[p.i] == 0x2c
        p.i += 1
      elseif p.b[p.i] == 0x5d
        p.i += 1
        return a
      else
        error("expected ',' or ']' at byte $(p.i)")
      end
    end
  elseif c == 0x22   # '"'
    return jstring(p)
  elseif c == 0x74   # 't'
  String(p.b[p.i:(p.i + 3)]) == "true" || error("bad literal at byte $(p.i)")
    p.i += 4
    return true
  elseif c == 0x66   # 'f'
    String(p.b[p.i:(p.i + 4)]) == "false" || error("bad literal at byte $(p.i)")
    p.i += 5
    return false
  elseif c == 0x6e   # 'n'
    String(p.b[p.i:(p.i + 3)]) == "null" || error("bad literal at byte $(p.i)")
    p.i += 4
    return nothing
  else
    return jnumber(p)
  end
end

function json_load(path)
  p = JParser(codeunits(read(path, String)), 1)
  jvalue(p)
end

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

function count_nulls(x)
  if x === nothing
    return 1
  elseif x isa AbstractDict
    return sum(count_nulls, values(x))
  elseif x isa AbstractArray
    return sum(count_nulls, x)
  end
  0
end

ev(f) = json_load(joinpath(EVIDENCE, f))

all_checks_pass(d) = d["summary"]["fail"] == 0 && d["summary"]["pass"] > 0 &&
  all(c["ok"] === true for c in d["checks"])

# ---------------------------------------------------------------------------
# Optional: re-run the probe scripts, then verify the fresh evidence
# ---------------------------------------------------------------------------

const RERUN = get(ENV, "R040_RUN_PROBES", "") != ""

if RERUN
  include(joinpath(PROBE_ROOT, "scripts", "probe_common.jl"))
  for script in ("p00_env.jl", "p10_loader_device.jl", "p20_offscreen.jl",
                 "p30_compute.jl", "p40_bool_layers.jl", "p50_errors.jl", "p60_julia_matrix.jl")
    cmd = Cmd([joinpath(Sys.BINDIR, "julia"), "--startup-file=no", "--project=$PROBE_ROOT",
               joinpath(PROBE_ROOT, "scripts", script)])
    (_o, e, rc) = ProbeCommon.run_capture(cmd)
    @info "re-ran $script (exit=$rc)"
    if rc != 0
      @error "probe $script failed" stderr=e
      error("probe re-run failed: $script")
    end
  end
end

# ---------------------------------------------------------------------------
# Checks
# ---------------------------------------------------------------------------

using Test

@testset "R040 probe: pins" begin
  projs = read(joinpath(PROBE_ROOT, "Project.toml"), String)
  manifest = read(joinpath(PROBE_ROOT, "Manifest.toml"), String)
  @test occursin(SPIRV_REV, manifest)
  @test occursin("Vulkan", projs)
  @test occursin("SPIRV", projs)
  @test occursin("SPIRV_Tools_jll", projs)
  @test occursin("julia = \"1.11\"", projs)
end

@testset "R040 probe: p00 environment evidence" begin
  p = ev("p00_env.json")
  @test all_checks_pass(p)
  @test count_nulls(p) == 0
  @test p["packages"]["SPIRV"]["git_rev"] == SPIRV_REV
  @test startswith(p["packages"]["Vulkan"]["version"], "0.6.")
  @test !isempty(p["system_vulkan"]["loader"]["sha256"])
  @test !isempty(p["system_vulkan"]["loader"]["library"])
  @test !isempty(p["validation_layer_external"]["VK_LAYER_KHRONOS_validation"]["library_sha256"])
  @test !isempty(p["spirv_tools"]["spirv_val"]["sha256"])
  @test !isempty(p["manifest"]["project_hash"])
end

@testset "R040 probe: p10 loader/device" begin
  p = ev("p10_loader_device.json")
  @test all_checks_pass(p)
  @test p["instance"]["validation_layer_enabled"] === true
  @test "VK_LAYER_KHRONOS_validation" in p["instance"]["layers_enabled"]
  @test length(p["devices"]) >= 1
  @test p["selected_device"]["graphics"] === true
  @test p["selected_device"]["compute"] === true
  @test p["loader"]["dlopen_libvulkan"] == "ok"
end

@testset "R040 probe: p20 offscreen" begin
  p = ev("p20_offscreen.json")
  @test all_checks_pass(p)
  @test p["upload_readback"]["bytes_exact"] == 8192
  @test p["upload_readback"]["all_exact"] === true
  @test p["clear_readback"]["all_exact"] === true
  @test p["clear_readback"]["first_pixel"] == [255, 0, 255, 255]
  @test isempty(p["validation"]["errors"])
end

@testset "R040 probe: p30 compute" begin
  p = ev("p30_compute.json")
  @test all_checks_pass(p)
  @test p["run1"]["bytes_exact"] == 512
  @test p["run2"]["bytes_exact"] == 512
  @test p["run3"]["bytes_exact"] == 400
  @test p["run3"]["sentinel_rest_unchanged"] === true
  @test p["run2"]["n_differing_bytes_vs_run1"] > 0
  @test p["spirv_val_vulkan1_3"]["exit"] == 0
  @test p["spirv_val_vulkan1_2_negative_control"]["exit"] != 0
  @test isempty(p["validation"]["errors"])
end

@testset "R040 probe: p40 bool under layers" begin
  p = ev("p40_bool_layers.json")
  @test all_checks_pass(p)
  for name in ("true_layer_4byte", "false_layer_4byte", "true_layer_1byte_upstream_size", "true_nolayer_4byte_control")
    @test p[name]["child_exit"] == 0
    @test p[name]["child_completed"] === true
    @test p[name]["result"] == "MATCH"
    @test p[name]["validation_errors"] == 0
  end
  @test p["finding"]["reproduced_crash"] === false
  @test p["spirv_shape"]["bool_returning_function"] === true
end

@testset "R040 probe: p50 error paths" begin
  p = ev("p50_errors.json")
  @test all_checks_pass(p)
  @test occursin("INCOMPATIBLE_DRIVER", p["no_device"]["error_msg"])
  @test occursin("EXTENSION_NOT_PRESENT", p["bogus_ext"]["error_msg"])
  @test occursin("not supported on this device", p["bad_format"]["error_msg"])
  @test p["precompile_false"]["precompile_ok"] == "yes"
  @test p["precompile_false"]["workload_ran"] === false
  @test p["precompile_auto"]["precompile_ok"] == "yes"
  @test p["precompile_auto"]["workload_ran"] === true
  @test p["precompile_true"]["precompile_ok"] == "no"
  @test occursin("INCOMPATIBLE_DRIVER", p["precompile_true"]["precompile_msg"])
end

@testset "R040 probe: p60 julia matrix" begin
  p = ev("p60_julia_matrix.json")
  @test all_checks_pass(p)
  @test p["julia110"]["result"] == "failed"
  @test occursin("different version of Julia", p["julia110"]["detail"])
  @test occursin("\"1.11\"", p["spirv_julia_compat"]["declared"])
  @test p["julia113"]["result"] == "instantiate_ok"
  @test occursin("julia=1.13", p["julia113"]["versions"])
end
