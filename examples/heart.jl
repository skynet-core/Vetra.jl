# Julia mirror of .reference/upstream/examples/heart.nim (PNG is T008; this
# writes binary PPM per D008).
#   julia --project=. examples/heart.jl [path.ppm]
using Vetra
include(joinpath(@__DIR__, "common.jl"))
using .VetraExamples

out = isempty(ARGS) ?
    joinpath(@__DIR__, "..", "artifacts", "examples", "heart.ppm") : ARGS[1]
isdir(dirname(out)) || mkpath(dirname(out))
writePPM(out, build_heart())
println(out)
