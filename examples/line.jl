# Julia mirror of .reference/upstream/examples/line.nim (PNG is T008; this
# writes binary PPM per D008).
#   julia --project=. examples/line.jl [path.ppm]
using Vetra
include(joinpath(@__DIR__, "common.jl"))
using .VetraExamples

out = isempty(ARGS) ?
    joinpath(@__DIR__, "..", "artifacts", "examples", "line.ppm") : ARGS[1]
isdir(dirname(out)) || mkpath(dirname(out))
writePPM(out, build_line())
println(out)
