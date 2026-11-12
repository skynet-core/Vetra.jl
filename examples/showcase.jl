# showcase.jl -- a guided tour of the Vetra.jl API (T008).
#
#   julia --project=. examples/showcase.jl [out.png|out.bmp]
#
# Sections 1-7 and 9 are the dependency-free core (9 = T009 text, native
# OpenType subset). Section 8's default output and bmp/qoi/ppm are native;
# its PNG/JPEG/SVG parts use the opt-in packages from D014 only when they
# are available (skipped, named, otherwise):
#   Pkg.add("PNGFiles")   # PNG read/write
#   Pkg.add("JpegTurbo")  # JPEG decode
#   Pkg.add("XML")        # SVG parse
# Without arguments the final canvas is written to artifacts/examples/
# (showcase.png with PNGFiles, showcase.bmp without).
using Vetra

W, H = 320, 240

# --- 1. Images and colors ------------------------------------------------
# An Image stores premultiplied RGBA bytes, row-major, 4 bytes per pixel.
# rgb/rgba are straight colors; rgbx is premultiplied; fill() overwrites.
img = newImage(W, H)
fill(img, rgb(245, 244, 250))
ctx = Context(img) # all context drawing mutates ctx.image
println("1. canvas $(width(img))x$(height(img))")

# --- 2. Context: state, rects, segments -----------------------------------
# fillStyle/strokeStyle accept Paint, rgb/rgba/rgbx, or CSS color strings.
ctx.fillStyle = "#FF5C00"
fillRect(ctx, 12f0, 12f0, 90f0, 60f0)
ctx.strokeStyle = rgba(0, 90, 200, 255)
ctx.lineWidth = 6f0
ctx.lineCap = RoundCap
ctx.lineJoin = RoundJoin
strokeRect(ctx, 12f0, 12f0, 90f0, 60f0)
strokeSegment(ctx, 12f0, 72f0, 102f0, 132f0)
ctx.globalAlpha = Float32(0.5) # subsequent draws fade (upstream globalAlpha)
ctx.fillStyle = rgb(10, 132, 255)
fillRect(ctx, 110f0, 12f0, 40f0, 60f0)
ctx.globalAlpha = Float32(1)
println("2. fills, strokes, segments, globalAlpha")

# --- 3. Paths ---------------------------------------------------------------
# Build a Path, then fill/stroke it with the context state...
heart = newPath()
moveTo(heart, 140f0, 220f0)
bezierCurveTo(heart, 140f0, 150f0, 200f0, 150f0, 200f0, 220f0)
closePath(heart)
ctx.fillStyle = "#FC427B"
fill(ctx, heart)
# ...or directly on the image with an explicit paint.
rr = newPath()
roundedRect(rr, 200f0, 130f0, 104f0, 70f0, 16f0, 16f0, 16f0, 16f0)
strokePath(img, rr, Paint(rgba(0, 0, 0, 255));
    strokeWidth = 3f0, lineCap = RoundCap, lineJoin = RoundJoin)
el = newPath()
ellipse(el, 60f0, 190f0, 42f0, 26f0)
fill(ctx, el)
println("3. paths: bezier, roundedRect, ellipse, strokePath")

# --- 4. Transforms -------------------------------------------------------------
# setTransform composes the context CTM from the origin; matrices chain with *.
setTransform(ctx,
    translate(Vec2(24f0, 24f0)) * scale(Vec2(Float32(2), Float32(2))) *
    rotate(Float32(0.4)))
ctx.fillStyle = "#4CAF50"
fillRect(ctx, 0f0, 0f0, 30f0, 30f0)
resetTransform(ctx)
println("4. transforms: translate * scale * rotate")

# --- 5. Clipping and layers ------------------------------------------------------
clipPath = newPath()
ellipse(clipPath, 260f0, 60f0, 34f0, 34f0)
save(ctx)
clip(ctx, clipPath) # intersect the clip; draw inside a circle now
ctx.fillStyle = "#FFC107"
fillRect(ctx, 200f0, 10f0, 110f0, 110f0)
restore(ctx) # the clip goes away (upstream save/restore semantics)

saveLayer(ctx) # offscreen layer: everything composites to a temp image
ctx.fillStyle = "#9C27B0"
fillRect(ctx, 20f0, 90f0, 60f0, 60f0)
ctx.globalAlpha = Float32(0.5)
ctx.fillStyle = rgb(255, 255, 255)
fillRect(ctx, 30f0, 100f0, 40f0, 40f0)
restore(ctx) # the layer is drawn back with its state
println("5. clip + saveLayer/restore")

# --- 6. Paints: gradients and blend modes ------------------------------------------
grad = Paint(LinearGradientPaint)
grad.gradientHandlePositions = [Vec2(0f0, 0f0), Vec2(Float32(W), Float32(H))]
grad.gradientStops = [
    colorStop(rgb(255, 255, 255), 0f0),
    colorStop(rgb(30, 30, 60), 1f0),
]
band = newPath()
rect(band, 0f0, Float32(H - 30), Float32(W), 30f0)
fillPath(img, band, grad) # non-solid paints render through the mask pipeline

multi = Paint(rgba(255, 120, 0, 255); blendMode = MultiplyBlend)
dashed = newPath()
roundedRect(dashed, 130f0, 120f0, 60f0, 60f0, 12f0, 12f0, 12f0, 12f0)
fillPath(img, dashed, multi)
strokePath(img, dashed, Paint(rgba(0, 0, 0, 255));
    strokeWidth = 2f0, dashes = Float32[8f0, 4f0]) # dash pattern
println("6. gradient + MultiplyBlend paint + dashes")

# --- 7. Image operations --------------------------------------------------------------
# resize/subImage/shadow/minifyBy2/magnifyBy2 return new images;
# flip/blur/invert/applyOpacity/spread mutate their argument in place.
stamp = subImage(img, 0, 0, W ÷ 2, H ÷ 2) # crop the top-left quadrant
stamp = resize(stamp, 80, 60) # bilinear resample
stamp = rotate90(stamp) # returns the rotated image
flipHorizontal(stamp) # in place
blur(stamp, 2f0) # in place
soft = shadow(copy(stamp), Vec2(4f0, 4f0), 4f0, 8f0, rgb(0, 0, 0))
draw(img, soft, translate(Vec2(236f0, 148f0))) # composite with a transform
tiled = newImage(W, H)
fill(tiled, rgb(0, 0, 0))
inv = copy(stamp)
invert(inv) # in place
drawTiled(tiled, minifyBy2(magnifyBy2(inv)))
faded = copy(img)
applyOpacity(faded, Float32(0.4)) # in place
spread(faded, 1f0) # grow the alpha mask, in place
println("7. subImage/resize/rotate90/flip/blur/shadow/draw/drawTiled/applyOpacity/spread")

# --- 8. File formats and base64 ----------------------------------------------------------
# The default output and bmp/qoi/ppm are the native codecs (no packages);
# the opt-in formats (D014) run only when their provider is available.
outDir = joinpath(@__DIR__, "..", "artifacts", "examples")
isdir(outDir) || mkpath(outDir)
havePng = Base.locate_package(Vetra._PNGFILES_PKGID) !== nothing
haveJpeg = Base.locate_package(Vetra._JPEGTURBO_PKGID) !== nothing
haveXml = Base.locate_package(Vetra._XML_PKGID) !== nothing
# Writable formats (native codecs): extension drives the encoder.
writeFile(img, joinpath(outDir, "showcase.bmp"))
writeFile(img, joinpath(outDir, "showcase.qoi"))
writeFile(img, joinpath(outDir, "showcase.ppm"))
havePng && writeFile(img, joinpath(outDir, "showcase.png"))
# Read-only formats (no upstream encoder): decode the pinned fixtures.
ff = joinpath(@__DIR__, "..", ".reference", "upstream", "tests", "fileformats")
gif = decodeGIF(read(joinpath(ff, "gif", "3x5.gif")))
notes = ["gif $(length(gif.frames)) frame(s)"]
if haveJpeg
    jpg = readImage(joinpath(ff, "jpeg", "masters", "mandrill.jpg"))
    push!(notes, "jpeg $(width(jpg))x$(height(jpg))")
else
    push!(notes, "jpeg: opt-in JpegTurbo absent (skipped)")
end
if haveXml
    svgImg = newImage(parseSvg(read(joinpath(ff, "svg", "line01.svg"), String)))
    push!(notes, "svg $(width(svgImg))x$(height(svgImg))")
else
    push!(notes, "svg: opt-in XML absent (skipped)")
end
# base64 round trip (data URL out, image in; PNG decode is opt-in).
b64 = encodeBase64(img)
if havePng
    roundTrip = decodeBase64(b64)
    push!(notes, "base64 len $(length(b64)) round-trips: ",
        string(roundTrip.data == img.data))
else
    push!(notes, "base64 len $(length(b64)) (PNG decode: opt-in absent)")
end
println("8. formats: wrote bmp/qoi/ppm", havePng ? "/png" : "", "; read ",
    join(notes, ", "))

# --- 9. Text (T009) --------------------------------------------------------------
# ctx.font takes a font path (readTypeface; cached per path); fillText and
# strokeText render with the context paint, size, align and baseline.
# Native OpenType subset (D015): TTF/glyf only — CFF/TTC/SVG fonts raise.
ctx.font = joinpath(@__DIR__, "..", ".reference", "upstream", "tests", "fonts",
    "Roboto-Regular_1.ttf")
ctx.fontSize = 20f0
ctx.fillStyle = "#202124"
fillText(ctx, "Vetra.jl", 158f0, 34f0)
ctx.fontSize = 12f0
ctx.strokeStyle = "#C2185B"
strokeText(ctx, "kerned text", 158f0, 52f0)
m = measureText(ctx, "kerned text")
f = newFont(readTypeface(ctx.font))
f.size = 12f0
println("9. text: fill+stroke drawn; measureText width=$(m.width), " *
    "layoutBounds=", layoutBounds(f, "kerned text"))

outPath = isempty(ARGS) ? joinpath(outDir,
    "showcase." * (havePng ? "png" : "bmp")) : ARGS[1]
isdir(dirname(outPath)) || mkpath(dirname(outPath))
writeFile(img, outPath)
println("canvas -> ", outPath)
