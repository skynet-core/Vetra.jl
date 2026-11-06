# QOI example (T008): decode and re-encode a QOI image.
# No opt-in package: the codec is a native port.
#   julia --project=. examples/qoi.jl [in.qoi] [out.qoi]
using Vetra

inPath = isempty(ARGS) ?
    joinpath(@__DIR__, "..", ".reference", "upstream", "tests", "fileformats",
        "qoi", "testcard.qoi") : ARGS[1]
outPath = length(ARGS) >= 2 ? ARGS[2] :
    joinpath(@__DIR__, "..", "artifacts", "examples", "qoi_example.qoi")

img = readImage(inPath)
println("decoded QOI: $(width(img))x$(height(img))")
isdir(dirname(outPath)) || mkpath(dirname(outPath))
writeFile(img, outPath) # extension .qoi -> encodeQOI
println("round-tripped -> ", outPath)
