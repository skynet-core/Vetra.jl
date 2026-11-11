#!/usr/bin/env julia
# R040 probe p40: Bool-returning compute shader under the KHRONOS validation layer.
#
# SPIRV.jl's execution harness (test/execution/execute.jl) disables the
# validation layer with the comment "Validation layers seem to crash when
# `Bool` is returned." This probe reproduces that exact scenario — a kernel
# whose helper function has an OpTypeBool return and stores a runtime bool
# through a BDA pointer — with the KHRONOS layer ACTUALLY enabled (gated per
# experiment), on real hardware, and records whether it crashes, errors, or
# runs clean.
#
# The 1-byte output buffer case (upstream's sizeof(Bool)=1 sizing) is a
# DIAGNOSTIC / negative case, not a safe-storage claim: the module emits
# `OpStore ... Aligned 2` (a 2-byte access for the SPIR-V bool), so a 1-byte
# buffer is a potential out-of-bounds store. Neither the external validator
# nor the ordinary layer proves BDA access bounds; the layer's store-bounds
# detection is recorded when it fires, and its absence is recorded as an
# explicit limitation.
#
# Each execution runs in a child Julia process (scripts/p40_child.jl) so a
# layer crash is captured as an exit code instead of taking this probe down.
# Expected bool values are computed in plain Julia from the input data, never
# from the shader.
using SPIRV
using SPIRV_Tools_jll
using SHA
using Vulkan
using Vulkan: unwrap
include(joinpath(@__DIR__, "probe_common.jl"))
using .ProbeCommon: check, write_evidence, reset_checks, make_instance, pick_device,
                    query_supported_features, run_capture, run_jll, release, refcount_ok,
                    tailshort, CHECKS

const PROBE_ROOT = dirname(@__DIR__)
const EVIDENCE = joinpath(PROBE_ROOT, "evidence")

struct BoolBlock
  in_addr::UInt64
  out_addr::UInt64
end

"""The kernel in the upstream `execute()` shape: the traced helper returns a
Bool and stores it through a buffer-device-address pointer. Runtime inputs:
the bool is a comparison of two floats read from a buffer (never constant)."""
function bool_source(features)
  @compute features = features assemble = true (function (out)
    inp = SPIRV.Pointer{Vector{Float32}}(out.in_addr)
    @store out.out_addr::Bool = inp[1] > inp[2]
  end)(::BoolBlock::PushConstant) options = SPIRV.ComputeExecutionOptions(local_size = (1, 1, 1))
end

"""Two floats as 16 little-endian hex chars."""
function floats_hex(a::Float32, b::Float32)
  bs = vcat(reinterpret(UInt8, [a]), reinterpret(UInt8, [b]))
  hd = "0123456789abcdef"
  join([hd[Int(x >> 4) + 1] * hd[Int(x & 0x0f) + 1] for x in bs])
end

"""Run the child experiment; returns Dict of parsed output lines + exit code."""
function run_child(spv_path, in_hex, out_size, layer, expected)
  julia = joinpath(Sys.BINDIR, "julia")
  cmd = Cmd([julia, "--startup-file=no", "--project=$PROBE_ROOT",
             joinpath(PROBE_ROOT, "scripts", "p40_child.jl"),
             spv_path, in_hex, string(out_size), string(layer), string(expected)])
  (out, err, code) = run_capture(cmd)
  parsed = Dict{String, String}()
  for l in split(out, "\n")
    m = match(r"^([A-Z_][A-Z_0-9]*)(?:=(.*))?$", strip(l))
    !isnothing(m) && (parsed[m.captures[1]] = isnothing(m.captures[2]) ? "" : m.captures[2])
  end
  val_err_msgs = [parsed["VAL_ERROR_$i"] for i in 1:20 if haskey(parsed, "VAL_ERROR_$i")]
  (parsed = parsed, stdout = out, stderr = err, exit = code, val_err_msgs = val_err_msgs)
end

function main()
  reset_checks()
  ev = Dict{String, Any}()

  # --- compile (instance + physical device only, no logical device) -----------
  inst = nothing
  msg = nothing
  spv_path = nothing
  try
  inst, msg, _layers = make_instance(; validation = false)
  ph, props = pick_device(inst; name_substring = "NVIDIA GeForce")
  ev["device"] = props.device_name
  devf = query_supported_features(ph).features2
  features = SPIRV.SupportedFeatures(ph, v"1.2", String[], devf)
  source = bool_source(features)
  code = source.code
  ev["spirv"] = Dict("bytes" => length(code), "sha256" => string(sha256(code)))

  spv_path = joinpath(tempdir(), "r040-p40-bool.spv")
  open(spv_path, "w") do io; write(io, code); end

  # independent read of the module's shape (what the layer will validate)
  (dis, _de, dc) = run_jll(SPIRV_Tools_jll.spirv_dis(), ["--no-color", spv_path])
  dc == 0 || error("spirv-dis failed: $_de")
  ev["spirv_shape"] = Dict(
    "bool_returning_function" => occursin(r"OpTypeFunction %bool", dis),
    "opstore_bool_aligned" => let
      m = match(r"OpStore %\S+ %\S+ Aligned (\d+)", dis)
      isnothing(m) ? "" : m.captures[1]
    end,
    "binary_version" => let
      w1 = Int(code[5]) | (Int(code[6]) << 8) | (Int(code[7]) << 16) | (Int(code[8]) << 24)
      "$((w1 >> 16) & 0xFF).$((w1 >> 8) & 0xFF)"
    end)
  check("kernel emits a Bool-returning function (the upstream trigger shape)",
        ev["spirv_shape"]["bool_returning_function"] === true)

  (_o13, e13, c13) = run_jll(SPIRV_Tools_jll.spirv_val(), ["--target-env", "vulkan1.3", spv_path])
  ev["spirv_val_vulkan1_3"] = Dict("exit" => c13, "stderr" => e13)
  check("external spirv-val --target-env vulkan1.3 passes on the bool module", c13 == 0, strip(e13))
  (_o12, e12, c12) = run_jll(SPIRV_Tools_jll.spirv_val(), ["--target-env", "vulkan1.2", spv_path])
  ev["spirv_val_vulkan1_2_negative_control"] = Dict("exit" => c12, "stderr" => e12)
  check("negative control: vulkan1.2 env rejected (module is SPIR-V 1.6)", c12 != 0, strip(e12))

  finally
    msg !== nothing && release(msg)
    inst !== nothing && release(inst)
  end
  GC.gc()
  check("parent refcount clean after release", refcount_ok(inst), "")

  # --- executions (child processes) -------------------------------------------
  # in1 = 1.5, in2 = 0.5 -> 1.5 > 0.5 = true ; in1 = 0.5, in2 = 1.5 -> false.
  hex_true = floats_hex(Float32(1.5), Float32(0.5))
  hex_false = floats_hex(Float32(0.5), Float32(1.5))
  experiments = [
    ("true_layer_4byte", hex_true, 4, 1, 1),
    ("false_layer_4byte", hex_false, 4, 1, 0),
    ("true_layer_1byte_upstream_size", hex_true, 1, 1, 1),
    ("true_nolayer_4byte_control", hex_true, 4, 0, 1),
  ]
  results = Dict{String, Any}()
  for (name, inh, osz, lay, exp) in experiments
    r = run_child(spv_path, inh, osz, lay, exp)
    results[name] = r
    tail = r.stderr
    length(tail) > 2000 && (tail = tailshort(tail, 2000))
    ev[name] = Dict("out_size" => osz, "layer" => lay == 1, "expected" => exp,
                    "child_exit" => r.exit,
                    "layer_enabled" => get(r.parsed, "LAYER_ENABLED", ""),
                    "pipeline_created" => haskey(r.parsed, "PIPELINE_OK"),
                    "readback_hex" => get(r.parsed, "READBACK_HEX", ""),
                    "result" => get(r.parsed, "RESULT", "NO_OUTPUT"),
                    "validation_errors" => parse(Int, get(r.parsed, "VAL_ERRORS", "-1")),
                    "validation_warnings" => parse(Int, get(r.parsed, "VAL_WARNINGS", "-1")),
                    "validation_error_messages" => r.val_err_msgs,
                    "child_completed" => haskey(r.parsed, "CHILD_DONE"),
                    "stderr_tail" => tail)
  end

  # --- gates -------------------------------------------------------------------
  # 1) the requested layer state must be ACTUALLY enabled (child asserts it;
  #    make_instance refuses to run unvalidated when validation was requested)
  for (name, _inh, _osz, lay, _exp) in experiments
    want = lay == 1 ? "yes" : "no"
    le = ev[name]["layer_enabled"]
    cc = ev[name]["child_completed"]
    check("$name: requested layer state actually in effect (child-verified)",
          le == want && cc,
          "layer_enabled=$le completed=$cc")
  end
  # 2) every experiment must complete without a crash and MATCH the
  #    independently computed expectation (no silent skips)
  for (name, _inh, _osz, _lay, exp) in experiments
    crashed = ev[name]["child_exit"] != 0 || !ev[name]["child_completed"]
    ce = ev[name]["child_exit"]
    ct = ev[name]["stderr_tail"]
    check("$name: completed without crash", !crashed,
          crashed ? "exit=$ce stderr=$ct" : "exit=0")
    res = ev[name]["result"]
    rb = ev[name]["readback_hex"]
    check("$name: bool readback byte-exact vs independent expectation ($exp)",
          res == "MATCH", "result=$res readback=$rb")
  end
  # 3) clean 4-byte layer runs must be validation-clean (correct severity masks,
  #    classified after cleanup+GC inside the child)
  e1 = ev["true_layer_4byte"]["validation_errors"]
  e2 = ev["false_layer_4byte"]["validation_errors"]
  check("4-byte layer runs: no validation ERROR messages",
        e1 == 0 && e2 == 0,
        "errs=$e1,$e2")

  # 4) the 1-byte case is a DIAGNOSTIC: record the store-bounds outcome. The
  #    module emits a 2-byte store (Aligned 2) into a 1-byte buffer; whether
  #    the layer flags it is store-bounds validation, not a general guarantee.
  b1 = ev["true_layer_1byte_upstream_size"]
  oob_msgs = [m for m in b1["validation_error_messages"] if occursin("bound", lowercase(m)) || occursin("OOP", m) || occursin("out of bounds", lowercase(m))]
  oob_flagged = !isempty(oob_msgs)
  ev["finding_1byte"] = Dict(
    "store_aligned" => ev["spirv_shape"]["opstore_bool_aligned"],
    "buffer_bytes" => b1["out_size"],
    "validation_errors" => b1["validation_errors"],
    "store_bounds_flagged" => oob_flagged,
    "flagged_messages" => oob_msgs,
    "classification" => oob_flagged ?
      "layer store-bounds validation flagged the 2-byte store into a 1-byte buffer" :
      "NOT flagged: limitation — the ordinary layer configuration does not prove BDA access bounds; the 1-byte case remains diagnostic, not a safe-storage claim")

  crashed = [name for (name, r) in results if r.exit != 0 || !haskey(r.parsed, "CHILD_DONE")]
  ev["finding"] = Dict(
    "upstream_comment" => "Validation layers seem to crash when `Bool` is returned (SPIRV.jl test/execution/execute.jl)",
    "reproduced_crash" => !isempty(crashed),
    "crashed_experiments" => crashed)
  check("no layer crash on Bool-returning shader (all 4 experiments completed, exit 0)", isempty(crashed),
        "completed=$(length(experiments) - length(crashed))/$(length(experiments))")

  npass, nfail = count(x -> x[2], CHECKS), count(x -> !x[2], CHECKS)
  ev["summary"] = Dict("pass" => npass, "fail" => nfail)
  ev["checks"] = [Dict("name" => c[1], "ok" => c[2], "detail" => c[3]) for c in CHECKS]
  path = write_evidence(joinpath(EVIDENCE, "p40_bool_layers.json"), ev)
  println("evidence: ", path, " | pass=", npass, " fail=", nfail)
  nfail > 0 && exit(1)
  ev
end

const _here = @__MODULE__
if _here == Main
  main()
end
