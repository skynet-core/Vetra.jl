using Pkg

VERSION >= v"1.10" || error("Vetra.jl requires Julia 1.10 or newer.")
root = normpath(joinpath(@__DIR__, ".."))
Pkg.activate(root)
Pkg.instantiate()
Pkg.precompile()
println("Environment ready. Run: julia --startup-file=no --project=. scripts/check.jl")
