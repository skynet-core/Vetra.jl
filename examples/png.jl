# PNG example (T008): decode and re-encode a PNG.
# PNG support is opt-in per D014: `Pkg.add("PNGFiles")` in your environment.
#   julia --project=. examples/png.jl [in.png] [out.png]
# Without arguments: decodes the pinned upstream fixture and writes a
# round-tripped PNG under artifacts/examples/.
using Vetra

inPath = isempty(ARGS) ?
    joinpath(@__DIR__, "..", ".reference", "upstream", "tests", "fileformats",
        "png", "lenna.png") : ARGS[1]
outPath = length(ARGS) >= 2 ? ARGS[2] :
    joinpath(@__DIR__, "..", "artifacts", "examples", "png_example.png")

img = readImage(inPath) # dispatches on the magic bytes
println("decoded PNG: $(width(img))x$(height(img))")
isdir(dirname(outPath)) || mkpath(dirname(outPath))
writeFile(img, outPath) # extension .png -> encodePNG
println("round-tripped -> ", outPath)
