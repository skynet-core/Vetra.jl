# GIF example (T008): decode a GIF and inspect its frames.
# No opt-in package: the codec is a native port. Upstream pixie has no GIF
# encoder, so the first frame is shown as a PNG preview.
#   julia --project=. examples/gif.jl [in.gif] [out.png]
using Vetra

inPath = isempty(ARGS) ?
    joinpath(@__DIR__, "..", ".reference", "upstream", "tests", "fileformats",
        "gif", "newtons_cradle.gif") : ARGS[1]
outPath = length(ARGS) >= 2 ? ARGS[2] :
    joinpath(@__DIR__, "..", "artifacts", "examples", "gif_preview.png")

gif = decodeGIF(read(inPath))
println("decoded GIF: $(length(gif.frames)) frame(s), " *
    "$(width(gif.frames[1]))x$(height(gif.frames[1]))")
img = gif.frames[1]
isdir(dirname(outPath)) || mkpath(dirname(outPath))
writeFile(img, outPath)
println("first frame -> PNG preview ", outPath)
