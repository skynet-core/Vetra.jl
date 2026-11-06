# SVG example (T008): parse an SVG and rasterize it to an image.
# SVG parsing needs the opt-in XML package per D014: `Pkg.add("XML")`.
# Output is a PNG (SVG is a vector source; pixie rasterizes, never re-emits).
#   julia --project=. examples/svg.jl [in.svg] [out.png]
using Vetra

inPath = isempty(ARGS) ?
    joinpath(@__DIR__, "..", ".reference", "upstream", "tests", "fileformats",
        "svg", "dragon2.svg") : ARGS[1]
outPath = length(ARGS) >= 2 ? ARGS[2] :
    joinpath(@__DIR__, "..", "artifacts", "examples", "svg_preview.png")

svgText = read(inPath, String)
img = newImage(parseSvg(svgText))
println("rendered SVG: $(width(img))x$(height(img))")
isdir(dirname(outPath)) || mkpath(dirname(outPath))
writeFile(img, outPath)
println("PNG raster -> ", outPath)
