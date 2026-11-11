#!/usr/bin/env julia
# R040 probe p60 child: Julia-version matrix cell (wrapper-level only).
#
# argv: cell  project_or_workdir  [spirv_path]
#   julia110_min_resolve : on Julia 1.10, in a FRESH temp project,
#                          Pkg.develop the pinned SPIRV checkout (path dep,
#                          bypassing the registry — SPIRV is not present in
#                          this host's registry snapshot) and try
#                          `using SPIRV`. This tests the actual
#                          Julia-minimum blocker (source compat + load),
#                          not just manifest mechanics. If precompilation
#                          fails hard, the child exits nonzero: the parent
#                          records the exit code + stderr as evidence.
#   julia110_foreign_manifest : Pkg.instantiate of the 1.11-generated
#                               project+manifest copy (labeled: a Pkg
#                               mechanism limitation, not a package
#                               compatibility statement)
#   julia113_load : instantiate the same copy on Julia 1.13 and load
#                   `using SPIRV, Vulkan` — load only: NO GPU execution,
#                   no device work on 1.13.
#
# Runs in a COPY of the probe project (Project.toml + Manifest.toml) in a
# temp dir so the pinned 1.11 Manifest in the real probe directory is never
# touched. Top-level only (`using` is illegal inside a function).
# Prints CELL=, DEVELOP=, LOAD=, RESULT=, DETAIL=, VERSIONS=, DONE.
using Pkg

function report(xs...)
  println(xs...)
  flush(stdout)
end

function sanitize(s)
  replace(replace(s, "\n" => "\\n"), "\r" => "")
end

cell = ARGS[1]
workdir = ARGS[2]
report("CELL=", cell)

if cell == "julia110_min_resolve"
  spirv_path = ARGS[3]
  # fresh, isolated project (the parent created the dir; no manifest)
  Pkg.activate(workdir)
  try
    Pkg.develop(Pkg.Types.PackageSpec(; name = "SPIRV", uuid = "84138a67-b342-4d33-8200-33cfcca52eb2", path = spirv_path))
    report("DEVELOP=ok")
  catch e
    report("DEVELOP=failed")
    report("DEVELOP_MSG=", sanitize(sprint(showerror, e)))
  end
  # NOTE: on Julia 1.10 the pinned SPIRV source precompiles against a
  # 1.11-only Base API; the failure kills the process before this catch can
  # run (observed: UndefVarError: `cached_return_type`). A nonzero child exit
  # is itself the evidence in that case.
  try
    using SPIRV
    report("LOAD=ok")
    report("VERSIONS=", "julia=$(VERSION)")
  catch e
    report("LOAD=failed")
    report("LOAD_MSG=", sanitize(sprint(showerror, e))[:1:300])
  end
elseif cell == "julia110_foreign_manifest"
  try
    Pkg.activate(workdir)
    Pkg.instantiate()
    report("RESULT=instantiate_ok")
  catch e
    report("RESULT=failed")
    report("DETAIL=", sanitize(sprint(showerror, e)))
  end
else
  # julia113_load: instantiate the 1.11 project copy, then LOAD ONLY
  try
    Pkg.activate(workdir)
    Pkg.instantiate()
    if true
      using SPIRV
      using Vulkan
    end
    report("RESULT=instantiate_ok")
    report("VERSIONS=", "julia=$(VERSION)")
  catch e
    report("RESULT=failed")
    report("DETAIL=", sanitize(sprint(showerror, e)))
  end
end
report("DONE")
