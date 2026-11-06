# PPM example (T008): decode and re-encode a PPM (P6 binary).
# No opt-in package: the codec is a native port (P6 write since T006).
#   julia --project=. examples/ppm.jl [in.ppm] [out.ppm]
using Vetra

inPath = isempty(ARGS) ?
    joinpath(@__DIR__, "..", ".reference", "upstream", "tests", "fileformats",
        "ppm", "feep.p6.ppm") : ARGS[1]
outPath = length(ARGS) >= 2 ? ARGS[2] :
    joinpath(@__DIR__, "..", "artifacts", "examples", "ppm_example.ppm")

img = readImage(inPath)
println("decoded PPM: $(width(img))x$(height(img))")
isdir(dirname(outPath)) || mkpath(dirname(outPath))
writeFile(img, outPath) # extension .ppm -> encodePPM
println("round-tripped -> ", outPath)
