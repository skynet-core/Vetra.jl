#!/usr/bin/env julia
# R040 probe p60: Julia-version matrix (wrapper-level cells only).
#
# The pinned stack (SPIRV.jl rev 218b33b) declares `julia = "1.11"`, while
# Vulkan.jl 0.6.30 declares `julia = "1.10"`. This probe records, with no GPU
# execution on foreign versions:
# - Julia 1.10.13: the ACTUAL Julia-minimum blocker — the pinned SPIRV source
#   fails to precompile on 1.10 (it uses a 1.11-only Base API), discovered by
#   Pkg.develop'ing the pinned checkout in a fresh temp project and loading
#   it; separately, the 1.11-generated manifest is rejected by 1.10's Pkg
#   (a manifest-mechanics limitation, labeled as such)
# - Julia 1.13.3: the same project instantiates and `using SPIRV, Vulkan`
#   succeeds — LOAD ONLY (precompile + module load): no device, no GPU
#   execution, no workload on 1.13
#
# Each cell runs in a fresh temp project so the pinned 1.11 Manifest is never
# touched. The full GPU probes (p10-p50) run only on the pinned 1.11.9.
# Julia binaries are located through the juliaup installation
# (\$JULIAUP_HOME, default ~/.julia/juliaup) — no host-specific paths.
include(joinpath(@__DIR__, "probe_common.jl"))
using .ProbeCommon: check, write_evidence, reset_checks, run_capture, tailshort, shorten, CHECKS
using SPIRV

const PROBE_ROOT = dirname(@__DIR__)
const EVIDENCE = joinpath(PROBE_ROOT, "evidence")
const SPIRV_REV = "218b33b21e5b23d7c3c34bb07f6c114723a5e193"

"""Locate a juliaup channel binary: \$JULIAUP_HOME/julia-<maj>.<min>*/bin/julia."""
function juliaup_binary(maj, min)
  home = (haskey(ENV, "JULIAUP_HOME") ? ENV["JULIAUP_HOME"] : joinpath(ENV["HOME"], ".julia", "juliaup"))
  isdir(home) || error("juliaup home not found at $home (set JULIAUP_HOME or install juliaup)")
  cands = [joinpath(home, d, "bin", "julia") for d in readdir(home)
           if startswith(d, "julia-$maj.$min") && isfile(joinpath(home, d, "bin", "julia"))]
  isempty(cands) && error("Julia $maj.$min channel not found under $home (install it with: juliaup add $maj.$min)")
  cands[1]
end

function file_copy(src, dst)
  open(dst, "w") do io
    write(io, read(src, String))
  end
end

function run_cell(cell, binary, workdir; extra::Vector{String} = String[])
  cmd = Cmd(vcat([binary, "--startup-file=no", "--project=$workdir",
                 joinpath(PROBE_ROOT, "scripts", "p60_child.jl"), cell, workdir], extra))
  (out, err, code) = run_capture(cmd)
  parsed = Dict{String, String}()
  for l in split(out, "\n")
    m = match(r"^([A-Z_][A-Z_0-9]*)(?:=(.*))?$", strip(l))
    !isnothing(m) && (parsed[m.captures[1]] = isnothing(m.captures[2]) ? "" : m.captures[2])
  end
  (parsed = parsed, stderr = err, exit = code)
end

function main()
  reset_checks()
  ev = Dict{String, Any}()

  b110 = juliaup_binary(1, 10)
  b113 = juliaup_binary(1, 13)
  ev["binaries"] = Dict("julia_1_10" => b110, "julia_1_13" => b113,
                        "juliaup_home" => (haskey(ENV, "JULIAUP_HOME") ? ENV["JULIAUP_HOME"] : joinpath(ENV["HOME"], ".julia", "juliaup")))

  # pinned SPIRV source path: the loaded package from the pinned 1.11 env
  spirv_path = pkgdir(SPIRV)
  spirv_compat = first(line for line in split(read(joinpath(spirv_path, "Project.toml"), String), "\n")
                       if startswith(strip(line), "julia"))
  ev["spirv_julia_compat"] = Dict("project_toml" => joinpath(spirv_path, "Project.toml"),
                                  "source_path" => spirv_path,
                                  "declared" => strip(spirv_compat))
  check("SPIRV.jl (pinned rev) declares julia = \"1.11\" -> the shader route is unavailable on Julia 1.10",
        occursin("\"1.11\"", spirv_compat), spirv_compat)

  # --- Julia 1.10: the actual Julia-minimum blocker ---------------------------
  # fresh temp project (no manifest): develop the pinned SPIRV checkout and
  # load it. The pinned source precompiles against a 1.11-only Base API
  # (cached_return_type), so `using SPIRV` fails — caught by the child,
  # reported STRUCTURED (LOAD=failed + full LOAD_MSG) with a NORMAL exit.
  # The parent requires that exact known diagnostic, not any failure: a
  # resolver/install error (DEVELOP=failed) or an unrelated load error must
  # not masquerade as the Julia-minimum evidence.
  minwork = mktempdir()
  open(joinpath(minwork, "Project.toml"), "w") do io
    write(io, "name = \"R040MinTest\"\nuuid = \"11111111-2222-3333-4444-555555555555\"\nversion = \"0.1.0\"\n")
  end
  r = run_cell("julia110_min_resolve", b110, minwork, extra = [spirv_path])
  load_msg = get(r.parsed, "LOAD_MSG", "")
  ev["julia110_min"] = Dict("exit" => r.exit,
                            "develop" => get(r.parsed, "DEVELOP", ""),
                            "load" => get(r.parsed, "LOAD", ""),
                            "load_msg" => load_msg,
                            "stderr_tail" => tailshort(r.stderr, 2000))
  try
    rm(minwork; recursive = true, force = true)
  catch
  end
  known_blocker = occursin("cached_return_type", load_msg) || occursin("cached_return_type", r.stderr)
  check("Julia 1.10.13: install ok, then pinned SPIRV source fails precompile with the known 1.11-only-Base-API diagnostic (the actual Julia-min blocker)",
        r.exit == 0 && get(r.parsed, "DEVELOP", "") == "ok" && get(r.parsed, "LOAD", "") == "failed" && known_blocker,
        "exit=$(r.exit) develop=$(get(r.parsed, "DEVELOP", "")) load=$(get(r.parsed, "LOAD", "")); load_msg: $(tailshort(load_msg, 300))")

  # --- Julia 1.10: foreign-manifest mechanics (labeled, separate from compat) ---
  fwork = mktempdir()
  file_copy(joinpath(PROBE_ROOT, "Project.toml"), joinpath(fwork, "Project.toml"))
  file_copy(joinpath(PROBE_ROOT, "Manifest.toml"), joinpath(fwork, "Manifest.toml"))
  r = run_cell("julia110_foreign_manifest", b110, fwork)
  ev["julia110_manifest"] = Dict("exit" => r.exit, "result" => get(r.parsed, "RESULT", "NO_OUTPUT"),
                                 "detail" => get(r.parsed, "DETAIL", ""),
                                 "note" => "Pkg manifest-mechanics limitation (manifest generated by a different Julia), NOT a package compatibility statement")
  try
    rm(fwork; recursive = true, force = true)
  catch
  end
  check("Julia 1.10.13: 1.11-generated manifest rejected by Pkg.instantiate (mechanics, not compat)",
        r.exit == 0 && ev["julia110_manifest"]["result"] == "failed" &&
        occursin("different version of Julia", ev["julia110_manifest"]["detail"]),
        ev["julia110_manifest"]["detail"])

  # --- Julia 1.13: load only ---------------------------------------------------
  lwork = mktempdir()
  file_copy(joinpath(PROBE_ROOT, "Project.toml"), joinpath(lwork, "Project.toml"))
  file_copy(joinpath(PROBE_ROOT, "Manifest.toml"), joinpath(lwork, "Manifest.toml"))
  r = run_cell("julia113_load", b113, lwork)
  ev["julia113"] = Dict("exit" => r.exit, "result" => get(r.parsed, "RESULT", "NO_OUTPUT"),
                        "detail" => get(r.parsed, "DETAIL", ""),
                        "versions" => get(r.parsed, "VERSIONS", ""),
                        "stderr_tail" => tailshort(r.stderr, 2000))
  try
    rm(lwork; recursive = true, force = true)
  catch
  end
  check("Julia 1.13.3: project instantiate + `using SPIRV, Vulkan` (LOAD ONLY — no GPU execution)",
        r.exit == 0 && ev["julia113"]["result"] == "instantiate_ok" &&
        occursin("julia=1.13", ev["julia113"]["versions"]),
        ev["julia113"]["versions"])
  check("Julia 1.13.3: pinned SPIRV revision resolves (git rev from Manifest)",
        r.exit == 0 && ev["julia113"]["result"] == "instantiate_ok",
        ev["julia113"]["detail"])

  ev["scope_note"] = "Wrapper-level cells only: no GPU probe execution on 1.10/1.13; 1.13 is load-only (instantiate + module load + precompile), not device execution. Full GPU probes (p10-p50) run on the pinned Julia 1.11.9. Vulkan.jl 0.7.0 was not executed: SPIRV.jl 0.6.11 declares compat Vulkan = 0.6, so 0.7 would need a recorded local patch; the 0.6.30 stack passed every probe, making the 0.7 comparison unnecessary."

  npass, nfail = count(x -> x[2], CHECKS), count(x -> !x[2], CHECKS)
  ev["summary"] = Dict("pass" => npass, "fail" => nfail)
  ev["checks"] = [Dict("name" => c[1], "ok" => c[2], "detail" => c[3]) for c in CHECKS]
  path = write_evidence(joinpath(EVIDENCE, "p60_julia_matrix.json"), ev)
  println("evidence: ", path, " | pass=", npass, " fail=", nfail)
  nfail > 0 && exit(1)
  ev
end

const _here = @__MODULE__
if _here == Main
  main()
end
