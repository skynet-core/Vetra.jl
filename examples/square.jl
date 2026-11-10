# Julia mirror of .reference/upstream/examples/square.nim (PNG is T008; this
# writes binary PPM per D008).
#   julia --project=. examples/square.jl [path.ppm]
using Vetra
include(joinpath(@__DIR__, "common.jl"))
using .VetraExamples

out = isempty(ARGS) ?
    joinpath(@__DIR__, "..", "artifacts", "examples", "square.ppm") : ARGS[1]
isdir(dirname(out)) || mkpath(dirname(out))
write_ppm!(out, build_square())
println(out)
