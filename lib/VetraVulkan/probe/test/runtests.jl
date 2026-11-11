#!/usr/bin/env julia
# R040 probe self-checks.
#
# Two parts:
# 1. Helper-logic tests: exercise the NEW probe_common helpers directly
#    (severity classification against the real Vulkan enum values,
#    run_capture env-merge + nonzero exit + stdout/stderr, run_jll, the JSON
#    writer/reader round-trip, and — when a Vulkan device is present — the
#    Base.finalize release path with a refcount-underflow check and the
#    synthetic severity regression). These do NOT read the probes' own
#    reported booleans; they prove the measurement mechanics.
# 2. Evidence verification: the committed evidence artifacts under
#    ../evidence/ (plus the Project.toml/Manifest pins) must have all-pass
#    check lists, and the key R040 claims must hold in the data.
#
# Re-run the probes themselves (needs the GPU + layer env from the README)
# with R040_RUN_PROBES=1, then this file re-verifies the fresh evidence.

const PROBE_ROOT = joinpath(@__DIR__, "..")
const EVIDENCE = joinpath(PROBE_ROOT, "evidence")
const SPIRV_REV = "218b33b21e5b23d7c3c34bb07f6c114723a5e193"

# ---------------------------------------------------------------------------
# Minimal JSON reader for the evidence files (objects, arrays, strings,
# numbers, true/false/null). The probe environment is pinned without a JSON
# package; the reader only needs to handle the flat shapes the probes emit.
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
        append!(out, codeunits(string(Char(cp))))
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
# Part 1: helper-logic tests (independent of the probes' reported booleans)
# ---------------------------------------------------------------------------

using Test
include(joinpath(PROBE_ROOT, "scripts", "probe_common.jl"))
using .ProbeCommon: SEV_VERBOSE, SEV_INFO, SEV_WARNING, SEV_ERROR, classify,
    run_capture, run_jll, write_evidence, manifest_source_dir,
    make_instance, physical_devices, pick_device, make_device, release, refcount,
    refcount_ok, synthetic_severity_regression, plain_buffer, map_with, with_commands,
    sync_hazard_control, validation_clean, validation_errors
using Pkg

@testset "R040 Vulkan probe" begin
@testset "severity classification vs the real Vulkan enum" begin
  using Vulkan
  @test ProbeCommon.SEV_VERBOSE  == Int(Vulkan.DEBUG_UTILS_MESSAGE_SEVERITY_VERBOSE_BIT_EXT.val)
  @test ProbeCommon.SEV_INFO     == Int(Vulkan.DEBUG_UTILS_MESSAGE_SEVERITY_INFO_BIT_EXT.val)
  @test ProbeCommon.SEV_WARNING  == Int(Vulkan.DEBUG_UTILS_MESSAGE_SEVERITY_WARNING_BIT_EXT.val)
  @test ProbeCommon.SEV_ERROR    == Int(Vulkan.DEBUG_UTILS_MESSAGE_SEVERITY_ERROR_BIT_EXT.val)
  # bit semantics: the buckets must not overlap (the original 1/2/4/8 masks
  # mis-classified everything because the real values are 1/16/256/4096)
  @test ProbeCommon.classify(ProbeCommon.SEV_ERROR) == :error
  @test ProbeCommon.classify(ProbeCommon.SEV_WARNING) == :warning
  @test ProbeCommon.classify(ProbeCommon.SEV_INFO) == :info
  @test ProbeCommon.classify(ProbeCommon.SEV_VERBOSE) == :verbose
  @test ProbeCommon.classify(0) == :none
end

@testset "run_capture: exit code, stdout/stderr, env merge" begin
  julia = joinpath(Sys.BINDIR, "julia")
  # nonzero exit + both streams
  (out, err, code) = ProbeCommon.run_capture(
    Cmd([julia, "--startup-file=no", "-e", "println(stdout, \"OUTLINE\"); println(stderr, \"ERRLINE\"); exit(7)"]))
  @test code == 7
  @test occursin("OUTLINE", out)
  @test occursin("ERRLINE", err)
  # env override is merged into the INHERITED environment: the child must see
  # both the added key AND the inherited PATH (replacing env drops PATH)
  (out2, err2, code2) = ProbeCommon.run_capture(
    Cmd([julia, "--startup-file=no", "-e", "println(get(ENV, \"R040_HELPER_KEY\", \"NOKEY\")); println(isnothing(get(ENV, \"PATH\", nothing)) ? \"NOPATH\" : \"HASPATH\")"]);
    env = ["R040_HELPER_KEY" => "merged"])
  @test code2 == 0
  @test occursin("merged", out2)
  @test occursin("HASPATH", out2)
  @test !occursin("NOPATH", out2)
end

@testset "run_jll: artifact env merged, tool runs" begin
  using SPIRV_Tools_jll
  (out, _err, code) = ProbeCommon.run_jll(SPIRV_Tools_jll.spirv_val(), ["--version"])
  @test code == 0
  @test occursin("SPIRV-Tools", out)
end

@testset "JSON writer/reader round-trip" begin
  data = Dict("a" => 1, "b" => true, "c" => nothing, "d" => "x\"y\nz",
              "e" => [1, 2, 3], "f" => Dict("g" => "deep"),
              "ctrl" => "\x1b[0mANSI\x01")
  p = joinpath(tempdir(), "r040-roundtrip-$(rand(UInt)).json")
  try
    ProbeCommon.write_evidence(p, data)
    back = json_load(p)
    @test back["a"] == 1
    @test back["b"] === true
    @test back["c"] === nothing
    @test back["d"] == "x\"y\nz"
    @test back["e"] == [1, 2, 3]
    @test back["f"]["g"] == "deep"
    @test back["ctrl"] == "\x1b[0mANSI\x01"
  finally
    isfile(p) && rm(p)
  end
end

@testset "manifest_source_dir: exact uuid+tree-hash identity" begin
  act = dirname(Pkg.project().path)
  mvk = manifest_source_dir(joinpath(act, "Manifest.toml"), "Vulkan")
  msp = manifest_source_dir(joinpath(act, "Manifest.toml"), "SPIRV")
  # the exact pinned checkout resolves by slug (uuid+tree hash), exists, and
  # matches the committed pins — a version-string scan could not guarantee
  # this (two revisions can share a version)
  @test isdir(mvk.dir)
  @test endswith(mvk.dir, joinpath("packages", "Vulkan", mvk.slug))
  @test startswith(mvk.version, "0.6.")
  @test isdir(msp.dir)
  @test endswith(msp.dir, joinpath("packages", "SPIRV", msp.slug))
  @test msp.git_rev == SPIRV_REV
end

@testset "GPU helpers: release + refcount + synthetic severity regression" begin
  # skipped on hosts without a usable Vulkan loader/device
  gpu_available = true
  inst = nothing
  msg = nothing
  try
    (inst, msg, _layers) = make_instance(; validation = false)
    _phs = physical_devices(inst)
    isempty(_phs) && (gpu_available = false)
  catch
    gpu_available = false
  end
  if gpu_available
    ph, _props = pick_device(inst)
    dev = make_device(inst, ph; qi = 0)
    using Vulkan
    q = unwrap(Vulkan.get_device_queue(dev, 0, 0))
    # reverse-order release; the refcount model must not underflow (a UInt
    # underflow would read near 2^64)
    release(q)
    release(dev)
    @test refcount_ok(dev)
    @test refcount_ok(inst)
    # --- fault injection: partial-failure cleanup must restore the parent's
    #     refcount IMMEDIATELY (before any GC), not eventually ---
    dev2 = make_device(inst, ph; qi = 0)
    rc0 = refcount(dev2)
    @test rc0 < (UInt(1) << 32)   # a sane baseline
    # fault memory_index -> plain_buffer must release the buffer it created
    @eval ProbeCommon function memory_index(ph, bits::Integer, props)
      error("injected-fault")
    end
    try
      @test_throws ErrorException plain_buffer(dev2, ph, 256)
      @test refcount(dev2) == rc0   # immediately — no GC.gc() in between
      # map_with: a callback error must leave the memory UNMAPPED
      b = nothing
      try
        @eval ProbeCommon function memory_index(ph, bits::Integer, props)
          mp = unwrap(Vulkan.get_physical_device_memory_properties(ph))
          for i in 1:mp.memory_type_count
            ((Int(bits) >> (i - 1)) & 1 == 1) || continue
            if mp.memory_types[i].property_flags & props == props
              return i - 1
            end
          end
          error("No device memory type for bits=$(bits) props=$(props)")
        end
        b = plain_buffer(dev2, ph, 64)
        @test_throws ErrorException map_with(dev2, b.memory, 64, m -> error("map-callback-fault"))
        back = map_with(dev2, b.memory, 64, m -> (fill!(m, 7); copy(m)))
        @test all(back .== 7)   # remapped fine -> the earlier error unmapped it
      finally
        b !== nothing && (release(b.buffer), release(b.memory))
      end
      # with_commands: a record failure must release pool+cb, and the device
      # must stay usable with the refcount restored
      rc1 = refcount(dev2)
      @test_throws ErrorException with_commands(dev2, 0, cb -> error("record-fault"))
      @test refcount(dev2) == rc1
      with_commands(dev2, 0, cb -> nothing)
      @test refcount(dev2) == rc1
    finally
      # restore the original memory_index (same-signature redefinition)
      @eval ProbeCommon function memory_index(ph, bits::Integer, props)
        mp = unwrap(Vulkan.get_physical_device_memory_properties(ph))
        for i in 1:mp.memory_type_count
          ((Int(bits) >> (i - 1)) & 1 == 1) || continue
          if mp.memory_types[i].property_flags & props == props
            return i - 1
          end
        end
        error("No device memory type for bits=$(bits) props=$(props)")
      end
      release(dev2)
    end
    @test refcount_ok(dev2)
    # --- capture isolation: an earlier workload error must survive BOTH sync
    #     controls (the controls' own instances share the global capture), the
    #     ON control must still flag its hazard, and a FAILED control must
    #     restore the caller's capture (no loss on the exception path) ---
    empty!(ProbeCommon._CAP[])   # this sub-block owns the capture window
    push!(ProbeCommon._CAP[], (SEV_ERROR, 2, "seeded-earlier-workload-error"))
    @test !validation_clean()   # the seed is a visible error before any control
    waw_on = sync_hazard_control(; sync_validation = true)
    waw_off = sync_hazard_control(; sync_validation = false)
    @test waw_on >= 1
    @test waw_off == 0
    @test length(ProbeCommon._CAP[]) == 1
    @test occursin("seeded-earlier-workload-error", ProbeCommon._CAP[][1][3])
    @test !validation_clean()   # the seed survived both controls
    @eval ProbeCommon function memory_index(ph, bits::Integer, props)
      error("injected-fault")
    end
    try
      @test_throws ErrorException sync_hazard_control(; sync_validation = false)
      @test length(ProbeCommon._CAP[]) == 1
      @test occursin("seeded-earlier-workload-error", ProbeCommon._CAP[][1][3])
    finally
      @eval ProbeCommon function memory_index(ph, bits::Integer, props)
        mp = unwrap(Vulkan.get_physical_device_memory_properties(ph))
        for i in 1:mp.memory_type_count
          ((Int(bits) >> (i - 1)) & 1 == 1) || continue
          if mp.memory_types[i].property_flags & props == props
            return i - 1
          end
        end
        error("No device memory type for bits=$(bits) props=$(props)")
      end
    end
    # the synthetic severity regression must also preserve the caller's capture
    sev = synthetic_severity_regression(inst)
    @test all(getindex.(values(sev), "received"))
    @test sev["error"]["raw_severity"] == SEV_ERROR
    @test sev["warning"]["raw_severity"] == SEV_WARNING
    @test !sev["info"]["in_error_bucket"]
    @test !sev["info"]["in_warning_bucket"]
    @test !sev["verbose"]["in_error_bucket"]
    @test length(ProbeCommon._CAP[]) == 1
    @test occursin("seeded-earlier-workload-error", ProbeCommon._CAP[][1][3])
    empty!(ProbeCommon._CAP[])
    release(msg)
    release(inst)
    GC.gc()
    @test refcount_ok(inst)
  else
    @test_skip "no Vulkan device on this host; GPU helper tests skipped"
  end
end

# ---------------------------------------------------------------------------
# Optional: re-run the probe scripts, then verify the fresh evidence
# ---------------------------------------------------------------------------

RERUN = get(ENV, "R040_RUN_PROBES", "") != ""

if RERUN
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
# Part 2: evidence verification
# ---------------------------------------------------------------------------

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
  # severity regression actually ran with the real enum values
  @test p["severity_bits"]["verbose"] == 1
  @test p["severity_bits"]["info"] == 16
  @test p["severity_bits"]["warning"] == 256
  @test p["severity_bits"]["error"] == 4096
  for sev in ("verbose", "info", "warning", "error")
    @test p["severity_regression"][sev]["received"] === true
  end
  # VVL build provenance recorded (tag + revision from the README recipe)
  @test !isnothing(p["validation_layer_provenance"])
  @test occursin("revision:", p["validation_layer_provenance"]["contents"])
  @test occursin("tag:", p["validation_layer_provenance"]["contents"])
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
  # memory-type labels use the real enum bits: device-local and
  # host-visible+host-coherent types both exist on the selected device
  sel = p["devices"][p["selected_device"]["name"]]
  mems = [m for m in values(sel["memory_types"])]
  @test any(m -> m["device_local"] === true, mems)
  @test any(m -> m["host_visible"] === true && m["host_coherent"] === true, mems)
  @test isempty(p["validation"]["errors"])
  @test isempty(p["validation"]["warnings"])
end

@testset "R040 probe: p20 offscreen" begin
  p = ev("p20_offscreen.json")
  @test all_checks_pass(p)
  @test p["upload_readback"]["bytes_exact"] == 8192
  @test p["upload_readback"]["all_exact"] === true
  @test p["clear_readback"]["all_exact"] === true
  @test p["clear_readback"]["first_pixel"] == [255, 0, 255, 255]
  @test p["sync_validation_requested"] === true
  @test p["validation_layer"] == ["VK_LAYER_KHRONOS_validation"]
  # bounded positive/negative sync control: the hazard is flagged ONLY when sync
  # validation is actually active — proves the feature, not just the request
  @test p["sync_validation_control"]["waw_detected_sync_on"] >= 1
  @test p["sync_validation_control"]["waw_detected_sync_off"] == 0
  @test isempty(p["validation"]["errors"])
  @test isempty(p["validation"]["warnings"])
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
  # variable-pointers claim retracted: the derived set has no f11 features
  # and the module's declared capabilities contain no VariablePointers
  @test p["device_features_derived"]["f11"] == []
  @test !("VariablePointers" in p["spirv_declared"]["capabilities"])
  @test "maintenance4" in p["device_features_derived"]["f13"]
  # safe feature query under bounded GC stress
  @test p["feature_query_gc_stress"]["stable"] === true
  @test p["feature_query_gc_stress"]["bits"]["maintenance4"] == 1
  @test p["sync_validation_requested"] === true
  @test isempty(p["validation"]["errors"])
  @test isempty(p["validation"]["warnings"])
end

@testset "R040 probe: p40 bool under layers" begin
  p = ev("p40_bool_layers.json")
  @test all_checks_pass(p)
  for (name, want_layer) in (("true_layer_4byte", "yes"),
                             ("false_layer_4byte", "yes"),
                             ("true_layer_1byte_upstream_size", "yes"),
                             ("true_nolayer_4byte_control", "no"))
    @test p[name]["child_exit"] == 0
    @test p[name]["child_completed"] === true
    @test p[name]["result"] == "MATCH"
    @test p[name]["layer_enabled"] == want_layer
  end
  @test p["true_layer_4byte"]["validation_errors"] == 0
  @test p["false_layer_4byte"]["validation_errors"] == 0
  @test p["finding"]["reproduced_crash"] === false
  @test p["spirv_shape"]["bool_returning_function"] === true
  # 1-byte case is a recorded diagnostic, not a safe-storage claim
  @test p["finding_1byte"]["store_aligned"] == "2"
  @test p["finding_1byte"]["buffer_bytes"] == 1
  @test occursin("diagnostic", p["finding_1byte"]["classification"])
end

@testset "R040 probe: p50 error paths" begin
  p = ev("p50_errors.json")
  @test all_checks_pass(p)
  @test occursin("INCOMPATIBLE_DRIVER", p["no_device"]["error_msg"])
  @test occursin("EXTENSION_NOT_PRESENT", p["bogus_ext"]["error_msg"])
  @test occursin("not supported on this device", p["bad_format"]["error_msg"])
  # isolated precompile env: sources copied by EXACT uuid+tree-hash identity
  # (not a version-string match), workload proven per pref
  @test startswith(p["precompile_false"]["sources_exact"], "Vulkan/")
  @test occursin("SPIRV/", p["precompile_false"]["sources_exact"])
  @test p["precompile_false"]["instantiate_ok"] == "yes"
  @test p["precompile_false"]["vulkan_precompile_ok"] == "yes"
  @test p["precompile_false"]["spirv_precompile_ok"] == "yes"
  @test p["precompile_false"]["workload_ran"] === false
  @test p["precompile_auto"]["instantiate_ok"] == "yes"
  @test p["precompile_auto"]["vulkan_precompile_ok"] == "yes"
  @test p["precompile_auto"]["workload_ran"] === true
  @test p["precompile_true"]["vulkan_precompile_ok"] == "no"
  @test occursin("INCOMPATIBLE_DRIVER", p["precompile_true"]["precompile_msg"]) ||
        occursin("failed to precompile", p["precompile_true"]["precompile_msg"])
  @test occursin("SPIRV", p["precompile_false"]["installed"])
end

@testset "R040 probe: p60 julia matrix" begin
  p = ev("p60_julia_matrix.json")
  @test all_checks_pass(p)
  # the actual Julia-min blocker, recorded as a STRUCTURED failure: the child
  # catches the 1.11-only-Base-API precompile error, reports it, and exits
  # normally — the parent requires that exact known diagnostic (a resolver or
  # unrelated load failure must not masquerade as the evidence)
  @test p["julia110_min"]["exit"] == 0
  @test p["julia110_min"]["develop"] == "ok"
  @test p["julia110_min"]["load"] == "failed"
  @test occursin("cached_return_type", p["julia110_min"]["load_msg"]) ||
        occursin("cached_return_type", p["julia110_min"]["stderr_tail"])
  # the separately-labeled foreign-manifest mechanics limitation
  @test p["julia110_manifest"]["result"] == "failed"
  @test occursin("different version of Julia", p["julia110_manifest"]["detail"])
  @test occursin("\"1.11\"", p["spirv_julia_compat"]["declared"])
  # 1.13 is LOAD ONLY (no GPU execution)
  @test p["julia113"]["result"] == "instantiate_ok"
  @test occursin("julia=1.13", p["julia113"]["versions"])
  @test occursin("load-only", p["scope_note"])
end
end
