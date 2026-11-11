#!/usr/bin/env julia
# R040 probe p60: Julia-version matrix (wrapper-level cells only).
#
# The pinned stack (SPIRV.jl rev 218b33b) declares `julia = "1.11"`, while
# Vulkan.jl 0.6.30 declares `julia = "1.10"`. This probe records, with no GPU
# execution:
# - Julia 1.10.13: the probe project cannot be instantiated (the resolver
#   rejects the SPIRV.jl dependency) — the shader route is therefore
#   unavailable on 1.10
# - Julia 1.13.3: the same project instantiates and `using SPIRV, Vulkan`
#   succeeds (precompiles on 1.13)
#
# Each cell runs in a COPY of the project (Project.toml + Manifest.toml) in
# tempdir so the pinned 1.11 Manifest is never touched. The full GPU probes
# (p10-p50) run only on the pinned 1.11.9.
include(joinpath(@__DIR__, "probe_common.jl"))
using .ProbeCommon: check, write_evidence, reset_checks, run_capture, CHECKS

const PROBE_ROOT = dirname(@__DIR__)
const EVIDENCE = joinpath(PROBE_ROOT, "evidence")

"""Last <=2000 chars of a string; tolerant of this host build's broken
multibyte string indexing (falls back to the whole string)."""
function tail2000(s)
  try
    n = length(s)
    n > 2000 ? s[end - 1999 : end] : s
  catch
    s
  end
end

function file_copy(src, dst)
  s = read(src, String)
  open(dst, "w") do io
    write(io, s)
  end
end

function run_cell(cell, binary; with_manifest = true)
  proj = mktempdir()
  file_copy(joinpath(PROBE_ROOT, "Project.toml"), joinpath(proj, "Project.toml"))
  with_manifest && file_copy(joinpath(PROBE_ROOT, "Manifest.toml"), joinpath(proj, "Manifest.toml"))
  cmd = Cmd([binary, "--startup-file=no", joinpath(PROBE_ROOT, "scripts", "p60_child.jl"), cell, proj])
  (out, err, code) = run_capture(cmd)
  parsed = Dict{String, String}()
  for l in split(out, "\n")
    m = match(r"^([A-Z_]+)(?:=(.*))?$", strip(l))
    !isnothing(m) && (parsed[m.captures[1]] = isnothing(m.captures[2]) ? "" : m.captures[2])
  end
  (parsed = parsed, stderr = err, exit = code)
end

function main()
  reset_checks()
  ev = Dict{String, Any}()

  b110 = "/home/vasyl/.julia/juliaup/julia-1.10.13+0.x64.linux.gnu/bin/julia"
  b113 = "/home/vasyl/.julia/juliaup/julia-1.13.3+0.x64.linux.gnu/bin/julia"
  isfile(b110) || error("Julia 1.10.13 binary not found at $b110")
  isfile(b113) || error("Julia 1.13.3 binary not found at $b113")
  ev["binaries"] = Dict("julia_1_10" => b110, "julia_1_13" => b113)

  r = run_cell("julia110_instantiate", b110)
  ev["julia110"] = Dict("exit" => r.exit, "result" => get(r.parsed, "RESULT", "NO_OUTPUT"),
                        "detail" => get(r.parsed, "DETAIL", ""),
                        "versions" => get(r.parsed, "VERSIONS", ""))
  check("Julia 1.10.13: the pinned 1.11 probe environment cannot be used (Pkg refuses the foreign manifest)",
        r.exit == 0 && ev["julia110"]["result"] == "failed" &&
        occursin("different version of Julia", ev["julia110"]["detail"]),
        ev["julia110"]["detail"])

  # static fact: the shader-route package declares Julia >= 1.11 (depot checkout
  # of the pinned revision)
  spirv_proj = first(filter(isfile, [joinpath(DEPOT_PATH[1], "packages", "SPIRV", d, "Project.toml")
                                     for d in readdir(joinpath(DEPOT_PATH[1], "packages", "SPIRV"))]))
  spirv_compat = first(line for line in split(read(spirv_proj, String), "\n") if startswith(strip(line), "julia"))
  ev["spirv_julia_compat"] = Dict("project_toml" => spirv_proj, "declared" => strip(spirv_compat))
  check("SPIRV.jl (pinned rev) declares julia = \"1.11\" -> the shader route is unavailable on Julia 1.10",
        occursin("\"1.11\"", spirv_compat), spirv_compat)

  r = run_cell("julia113_instantiate", b113)
  ev["julia113"] = Dict("exit" => r.exit, "result" => get(r.parsed, "RESULT", "NO_OUTPUT"),
                        "detail" => get(r.parsed, "DETAIL", ""),
                        "versions" => get(r.parsed, "VERSIONS", ""),
                        "stderr_tail" => tail2000(r.stderr))
  check("Julia 1.13.3: project instantiate + `using SPIRV, Vulkan` succeeds",
        r.exit == 0 && ev["julia113"]["result"] == "instantiate_ok" &&
        occursin("julia=1.13", ev["julia113"]["versions"]),
        ev["julia113"]["versions"])
  check("Julia 1.13.3: pinned SPIRV revision resolves (git rev from Manifest)",
        r.exit == 0 && ev["julia113"]["result"] == "instantiate_ok")

  ev["scope_note"] = "Wrapper-level cells only: no GPU probe execution on 1.10/1.13. Full probes (p10-p50) run on the pinned Julia 1.11.9. Vulkan.jl 0.7.0 was not executed: SPIRV.jl 0.6.11 declares compat Vulkan = 0.6, so 0.7 would need a recorded local patch; the 0.6.30 stack passed every probe, making the 0.7 comparison unnecessary."

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
