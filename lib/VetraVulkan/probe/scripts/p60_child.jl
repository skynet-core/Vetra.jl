#!/usr/bin/env julia
# R040 probe p60 child: Julia-version matrix cell (wrapper-level only).
#
# argv: cell  project_copy_dir
#   julia110_instantiate : Pkg.instantiate with Julia 1.10 (expect resolver
#                          failure: SPIRV.jl requires >= 1.11)
#   julia113_instantiate : Pkg.instantiate with Julia 1.13, then load the
#                          pinned stack (`using SPIRV, Vulkan`)
#
# Runs in a COPY of the probe project (Project.toml + Manifest.toml) so the
# pinned 1.11 Manifest in the real probe directory is never touched.
# Top-level only (`using` is illegal inside a function).
# Prints CELL=, RESULT=, DETAIL=, VERSIONS=, DONE.
using Pkg

function report(xs...)
  println(xs...)
  flush(stdout)
end

function sanitize(s)
  replace(replace(s, "\n" => "\\n"), "\r" => "")
end

cell = ARGS[1]
proj = ARGS[2]
report("CELL=", cell)

result = "failed"
detail = ""
versions = ""

try
  Pkg.activate(proj)
  Pkg.instantiate()
  global result = "instantiate_ok"
catch e
  global detail = sanitize(sprint(showerror, e))
end

if cell == "julia113_instantiate" && result == "instantiate_ok"
  try
    # legal: top-level `using` inside a module-scope if-block
    if true
      using SPIRV
      using Vulkan
    end
    # package versions are the pinned ones from the copied Manifest (p00);
    # this cell only proves the stack loads + precompiles on Julia 1.13
    global versions = "julia=$(VERSION)"
  catch e
    global result = "failed"
    global detail = sanitize(sprint(showerror, e))
  end
end

report("RESULT=", result)
report("DETAIL=", detail)
report("VERSIONS=", versions)
report("DONE")
