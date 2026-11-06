# BMP example (T008): decode and re-encode a BMP (32-bit, top-down).
# No opt-in package: the codec is a native port.
#   julia --project=. examples/bmp.jl [in.bmp] [out.bmp]
using Vetra

inPath = isempty(ARGS) ?
    joinpath(@__DIR__, "..", ".reference", "upstream", "tests", "fileformats",
        "bmp", "knight.24.master.bmp") : ARGS[1]
outPath = length(ARGS) >= 2 ? ARGS[2] :
    joinpath(@__DIR__, "..", "artifacts", "examples", "bmp_example.bmp")

img = readImage(inPath)
println("decoded BMP: $(width(img))x$(height(img))")
isdir(dirname(outPath)) || mkpath(dirname(outPath))
writeFile(img, outPath) # extension .bmp -> encodeBMP
println("round-tripped -> ", outPath)
