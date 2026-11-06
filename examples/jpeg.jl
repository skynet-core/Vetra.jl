# JPEG example (T008): decode a JPEG (pixels via JpegTurbo, opt-in per D014:
# `Pkg.add("JpegTurbo")`). Upstream pixie has no JPEG encoder either, so the
# result is shown as a PNG preview.
#   julia --project=. examples/jpeg.jl [in.jpg] [out.png]
using Vetra

inPath = isempty(ARGS) ?
    joinpath(@__DIR__, "..", ".reference", "upstream", "tests", "fileformats",
        "jpeg", "masters", "mandrill.jpg") : ARGS[1]
outPath = length(ARGS) >= 2 ? ARGS[2] :
    joinpath(@__DIR__, "..", "artifacts", "examples", "jpeg_preview.png")

w, h = readImageDimensions(inPath) # Exif orientation applied
println("decoded JPEG: $(w)x$(h)")
img = readImage(inPath)
isdir(dirname(outPath)) || mkpath(dirname(outPath))
writeFile(img, outPath)
println("PNG preview -> ", outPath)
