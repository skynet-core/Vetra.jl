# # From candles to SVG: a crypto OHLC chart with Vetra
#
# Vetra turns Julia code into raster images: you describe paths, paints and
# text, and it writes pixels into an `Image`. This tutorial draws a
# **24-hour BTC-USD candlestick (OHLC) chart** with the library, renders it
# to PNG, then builds a small **vector backend** step by step so the same
# chart is also saved as an `SVG` file — and proves that SVG by reading it
# back through the library's own parser.
#
# Two capability notes up front, because they shape the plan:
#
# - Vetra **reads** SVG (a pinned subset) but does **not** write it, matching
#   the upstream rasterizer it ports: `writeFile` supports PNG, BMP, QOI and
#   PPM. The tutorial therefore *renders* the chart with Vetra (PNG) and
#   *exports* it with a ~60-line writer built in section 9. That writer is
#   the project's backend-seam idea (D007) in miniature: the same geometry
#   feeds two backends.
# - The candle data is a **deterministic synthetic walk** (seeded RNG, no
#   network). Swap in real exchange data — the same `open/high/low/close`
#   numbers — whenever you like.
#
# You need Julia **1.10+** and Git. Allow about 40 minutes plus package
# downloads.
#
# ## Contents
#
# 1. [Set up the documentation environment](#1-set-up-the-documentation-environment)
# 2. [Generate deterministic OHLC data](#2-generate-deterministic-ohlc-data)
# 3. [Canvas and the data-to-pixel mapping](#3-canvas-and-the-data-to-pixel-mapping)
# 4. [Grid and the price axis](#4-grid-and-the-price-axis)
# 5. [Draw the candles](#5-draw-the-candles)
# 6. [Add the volume panel](#6-add-the-volume-panel)
# 7. [Title, timestamps, and the final price](#7-title-timestamps-and-the-final-price)
# 8. [Render the raster version](#8-render-the-raster-version)
# 9. [Build the SVG backend, part 1: documents and shapes](#9-build-the-svg-backend-part-1-documents-and-shapes)
# 10. [Emit the whole chart as SVG](#10-emit-the-whole-chart-as-svg)
# 11. [Prove the SVG: read it back through Vetra](#11-prove-the-svg-read-it-back-through-vetra)
# 12. [Test and benchmark habits for chart code](#12-test-and-benchmark-habits-for-chart-code)
# 13. [Troubleshooting and next charts](#13-troubleshooting-and-next-charts)
#
# ## 1. Set up the documentation environment
#
# The tutorial lives in the `docs/` environment, which carries the optional
# codecs alongside Vetra. From the repository root:
#
# ```sh
# julia --startup-file=no --project=docs -e 'using Pkg; Pkg.develop(path="."); Pkg.instantiate()'
# julia --startup-file=no --project=. scripts/fetch_upstream.jl
# ```
#
# The fetch supplies the Roboto font used for the axis labels
# (provenance in [NOTICE](https://github.com/skynet-core/Vetra.jl/blob/main/NOTICE)).
# `Pkg.develop` links this checkout; no registration is required.
#
# Every code block in this notebook runs from the repository root. Image
# exports land in `artifacts/tutorial/` (gitignored); the SVG round trip in
# section 11 stays in memory.
#
# A short display adapter gives chart figures a PNG representation in both
# Markdown and notebook outputs. It keeps the rendering code itself clean.

using Vetra

struct TutorialFigure
    image::Image
end
Base.show(io::IO, ::MIME"image/png", figure::TutorialFigure) =
    write(io, encodePNG(figure.image))
Base.show(io::IO, ::MIME"text/plain", figure::TutorialFigure) =
    print(io, "Vetra image: ", width(figure.image), " × ", height(figure.image))

root = dirname(dirname(pathof(Vetra)))
outdir = joinpath(root, "artifacts", "tutorial")
mkpath(outdir)
fontPath = joinpath(root, ".reference", "upstream", "tests", "fonts",
    "Roboto-Regular_1.ttf")
@assert isfile(fontPath) "Run scripts/fetch_upstream.jl from the repository root first"

#
# ## 2. Generate deterministic OHLC data
#
# A candle records `open`, `high`, `low`, `close` for one period, plus a
# volume. The helper below walks a price from 97 420 USD through 24 hourly
# steps: each close is a small random drift from the open, and the high/low
# extend beyond the open–close range by random wicks. The walk lives in a
# function because the loop reassigns `price` — inside a notebook cell that
# would shadow the outer variable. The fixed seed makes every reader's
# chart identical — a requirement for tutorial assertions.

using Random

struct OHLC
    open::Float64
    high::Float64
    low::Float64
    close::Float64
    volume::Float64
end

function makeCandles(rng, n, startPrice)
    out = Vector{OHLC}(undef, n)
    price = startPrice
    for i in 1:n
        open = price
        close = open * (1 + 0.004 * randn(rng))
        high = max(open, close) * (1 + abs(randn(rng)) * 0.0015)
        low = min(open, close) * (1 - abs(randn(rng)) * 0.0015)
        vol = 120 + 900 * rand(rng)
        out[i] = OHLC(open, high, low, close, vol)
        price = close
    end
    return out
end

rng = Random.Xoshiro(0x5eed_c0de)
candles = makeCandles(rng, 24, 97420.0)

for c in candles[1:4]
    println("O=$(round(c.open, digits=2))  H=$(round(c.high, digits=2))  ",
        "L=$(round(c.low, digits=2))  C=$(round(c.close, digits=2))  ",
        "V=$(round(c.volume, digits=1))")
end
@assert all(c -> c.high >= max(c.open, c.close) && c.low <= min(c.open, c.close), candles)
@assert length(candles) == 24

#
# Green candles close above their open (price rose over the period); red
# candles close below it. We will branch on that when painting.
#
# ## 3. Canvas and the data-to-pixel mapping
#
# Every chart is one function: **data space → screen space**. Get the
# mapping right and every later element — grid, candles, labels — is plain
# geometry. The canvas is 800 × 500 with these regions:
#
# - title band: y = 0…36
# - price plot: y = 48…332, x = 8…720 (price labels use the right gutter)
# - volume plot: y = 352…432
# - legend row: y = 442…454; timestamp row: y ≈ 470
#
# Two mapping functions do all the coordinate work:
#
# - `yFor(price)` maps a USD value into the price plot, **inverted** —
#   higher prices are higher on screen, so larger values get smaller y.
# - `xCenter(i)` places candle *i* in the middle of its time slot.

W, H = 800, 500
img = newImage(W, H)
fill(img, rgb(15, 23, 42))
ctx = Context(img)

const PLOT_LEFT = Float32(8)
const PLOT_RIGHT = Float32(720)
const PRICE_TOP = Float32(48)
const PRICE_BOTTOM = Float32(332)
const VOL_TOP = Float32(352)
const VOL_BOTTOM = Float32(432)
const N = length(candles)

# Leave headroom above and below the data range (2% each side).
dataLow = minimum(c -> c.low, candles)
dataHigh = maximum(c -> c.high, candles)
span = dataHigh - dataLow
plotLow = dataLow - 0.02 * span
plotHigh = dataHigh + 0.02 * span
volMax = maximum(c -> c.volume, candles)

# Everything draws in Float32: keep the ratio in Float64, wrap the result.
yFor(p) = Float32(PRICE_TOP + (plotHigh - p) / (plotHigh - plotLow) *
    (PRICE_BOTTOM - PRICE_TOP))
slot = (PLOT_RIGHT - PLOT_LEFT) / Float32(N)
xCenter(i) = PLOT_LEFT + slot * Float32(i - 0.5)
bodyW = slot * Float32(0.62)

@assert yFor(dataHigh) < yFor(dataLow) "higher prices must sit higher on screen"
@assert abs(yFor((dataHigh + dataLow) / 2) -
    Float32((PRICE_TOP + PRICE_BOTTOM) / 2)) < 1f0
@assert xCenter(1) < xCenter(N) && xCenter(1) >= PLOT_LEFT
@assert bodyW < slot

#
# `yFor` is the function to stare at: the `(plotHigh - p)` numerator
# inverts the axis, and the whole expression lands inside the price plot.
# All positions below are `Float32`, matching the drawing API.
#
# ## 4. Grid and the price axis
#
# Five horizontal grid lines split the price plot. The same five values
# become the labels in the right gutter, right-aligned against the plot's
# edge. The lines are faint and dashed — `setLineDash` drives the context
# strokes, and `restore` confines both the dash pattern and the stroke
# color to this section.

ticks = 5
for k in 0:ticks
    p = plotLow + span * k / Float64(ticks)
    y = yFor(p)
    save(ctx)
    ctx.strokeStyle = rgba(148, 163, 184, 60)
    ctx.lineWidth = 1f0
    setLineDash(ctx, Float32[4f0, 4f0])
    strokeSegment(ctx, PLOT_LEFT, y, PLOT_RIGHT, y)
    restore(ctx)

    ctx.font = fontPath
    ctx.fontSize = 13f0
    ctx.fillStyle = "#94A3B8"
    ctx.textAlign = RightAlign
    label = "\$" * string(round(p / 1000, digits = 2)) * "k"
    fillText(ctx, label, 792f0, y + 4f0)
    ctx.textAlign = LeftAlign
end

gridLabel = measureText(ctx, "\$97.42k")
@assert gridLabel.width > 20f0
@assert getColor(img, 760, 10) == rgbx(rgb(15, 23, 42)) "title band is untouched"

#
# `fillText` positions relative to the **alphabetic baseline** by default;
# the `+ 4f0` nudges each label down so it sits optically on its grid line.
# The `k` abbreviation keeps the gutter narrow.
#
# ## 5. Draw the candles
#
# Each candle is two primitives: a **wick** — the high–low segment — and a
# **body** — the open–close rectangle. Up candles are green, down candles
# red. A body whose open and close coincide (a "doji") gets a 1-pixel
# minimum height so it stays visible. The wick is drawn first, under the
# body, so the body's fill wins where they overlap.

UP = rgb(34, 197, 94)
DOWN = rgb(239, 68, 68)
colorOf(c) = c.close >= c.open ? UP : DOWN

upIdx = findfirst(c -> c.close >= c.open, candles)
downIdx = findfirst(c -> c.close < c.open, candles)

for (i, c) in enumerate(candles)
    x = xCenter(i)
    yTop = yFor(max(c.open, c.close))
    yBot = yFor(min(c.open, c.close))
    col = colorOf(c)
    save(ctx)
    ctx.strokeStyle = col
    ctx.lineWidth = 1f0
    strokeSegment(ctx, x, yFor(c.high), x, yFor(c.low))
    restore(ctx)

    body = newPath()
    rect(body, x - bodyW / 2, yTop, bodyW, max(yBot - yTop, 1f0))
    ctx.fillStyle = col
    fill(ctx, body)
end

# Spot-check the body centers of one up and one down candle. The interior
# of an 18-pixel body is flat (opaque fills overwrite), so exact colors
# hold; wick centers are antialiased and get checked against the read-back
# instead (section 11), where both sides rasterize identically.
for (i, expected) in [(upIdx, UP), (downIdx, DOWN)]
    c = candles[i]
    yc = (yFor(max(c.open, c.close)) + yFor(min(c.open, c.close))) / 2
    @assert getColor(img, round(Int, xCenter(i)), round(Int, yc)) == rgbx(expected)
    @assert getColor(img, round(Int, xCenter(i)) - 2, round(Int, yc)) == rgbx(expected)
end

#
# The assertions pick candle centers from the *data*, not hard-coded
# pixels — if the mapping in section 3 drifts, they fail. Wick centers
# are checked too: a high wick pixel must carry the candle's color.
#
# ## 6. Add the volume panel
#
# Volume bars share the x mapping with the candles but get their own y
# range. `globalAlpha` fades every bar in one state change; the alpha
# makes the grid color show through, which is what reads as "secondary
# data" on a chart.

for (i, c) in enumerate(candles)
    x = xCenter(i)
    barH = Float32(c.volume / volMax * (VOL_BOTTOM - VOL_TOP))
    ctx.globalAlpha = Float32(0.35)
    ctx.fillStyle = colorOf(c)
    bar = newPath()
    rect(bar, x - bodyW / 2, VOL_BOTTOM - barH, bodyW, barH)
    fill(ctx, bar)
    ctx.globalAlpha = Float32(1)
end

vix = upIdx
barH = Float32(candles[vix].volume / volMax * (VOL_BOTTOM - VOL_TOP))
vy = round(Int, VOL_BOTTOM - barH / 2)
probe = getColor(img, round(Int, xCenter(vix)), vy)
@assert 23 < probe.g < 197 "volume bar must be a blend, not solid or background"
@assert getColor(img, round(Int, xCenter(vix)), 340) == rgbx(rgb(15, 23, 42))

#
# The probe pixel's green channel sits strictly between the background
# (23) and solid up-green (197): that *is* the fade. The alpha stays 255
# because the canvas underneath is opaque — translucency over an opaque
# background shows up in RGB, not in A. The empty space above the bar is
# still bare background.
#
# ## 7. Title, timestamps, and the final price
#
# The header carries the pair name and the last close, colored by the
# direction of the final candle. Time labels appear every 4 hours under
# their candle. A two-swatch legend records the up/down colors.

last = candles[end]
ctx.font = fontPath
ctx.fontSize = 18f0
ctx.fillStyle = "#F8FAFC"
fillText(ctx, "BTC-USD · 1h candles", 8f0, 26f0)

ctx.fontSize = 16f0
ctx.fillStyle = colorOf(last)
finalLabel = string(round(last.close, digits = 2))
fillText(ctx, finalLabel, 792f0 - measureText(ctx, finalLabel).width, 26f0)

ctx.fontSize = 12f0
ctx.fillStyle = "#64748B"
ctx.textAlign = CenterAlign
for i in 1:4:24
    fillText(ctx, "h" * string(i - 1), xCenter(i), 470f0)
end
ctx.textAlign = LeftAlign

# Legend: swatch + caption, twice, in the band above the time row.
for (k, (col, cap)) in enumerate([(UP, "up (close ≥ open)"), (DOWN, "down (close < open)")])
    lx = 8f0 + (k - 1) * 170f0
    sw = newPath()
    rect(sw, lx, 442f0, 12f0, 12f0)
    ctx.fillStyle = col
    fill(ctx, sw)
    ctx.fillStyle = "#94A3B8"
    fillText(ctx, cap, lx + 18f0, 452f0)
end

@assert getColor(img, 12, 448) == rgbx(UP) "legend swatch 1 is the up color"
@assert getColor(img, 182, 448) == rgbx(DOWN) "legend swatch 2 is the down color"

#
# ## 8. Render the raster version
#
# The chart is complete as pixels. `writeFile` picks the encoder from the
# extension (PNG needs the opt-in `PNGFiles`, installed in this
# environment); the figure below is the same buffer as a data view.

pngPath = joinpath(outdir, "btc-chart.png")
writeFile(img, pngPath)
@assert isfile(pngPath) && filesize(pngPath) > 10_000
TutorialFigure(img)

#
# That is the finished chart rendered by Vetra. Sections 9–11 take the
# *same numbers* into a vector document.
#
# ## 9. Build the SVG backend, part 1: documents and shapes
#
# SVG is a text format: a document is a sequence of shape and text
# elements with presentation attributes. The writer below collects lines
# in an `IOBuffer`. Three design choices matter:
#
# - Coordinates are formatted with two decimals — enough for pixel-scale
#   charts, small in the file.
# - Colors reuse Vetra's `ColorRGB` and are converted to `#RRGGBB` hex,
#   which the library's own SVG reader parses back (section 11).
# - Every shape function mirrors the raster call that drew the same thing:
#   a candle body is `writeRect` here, `fill` on a rect `Path` there.

struct SvgDoc
    buf::IOBuffer
    width::Int
    height::Int
end

function SvgDoc(width::Int, height::Int)
    buf = IOBuffer()
    print(buf, """<?xml version="1.0" encoding="UTF-8"?>
<svg xmlns="http://www.w3.org/2000/svg" width="$width" height="$height"
     viewBox="0 0 $width $height">
""")
    return SvgDoc(buf, width, height)
end

function finish(doc::SvgDoc)
    print(doc.buf, "</svg>\n")
    return String(take!(doc.buf))
end

# The stdlib hex table (uppercase) maps both nibbles; lowercase the result.
HEXD = "0123456789ABCDEF"
svgHex(n::UInt8) = lowercase(
    string(HEXD[(Int(n) >> 4) + 1], HEXD[(Int(n) & 0x0f) + 1]))
svgColor(c::ColorRGB) = "#" * svgHex(c.r) * svgHex(c.g) * svgHex(c.b)

# Two-decimal coordinates: round to a centipixel integer, then split the
# string into whole and fractional parts.
function fmt2(v::Float32)
    r = Int(round(v * 100))
    neg = r < 0
    s = string(neg ? -r : r)
    while length(s) < 3
        s = "0" * s
    end
    out = s[1:length(s) - 2] * "." * s[length(s) - 1:end]
    return neg ? "-" * out : out
end

function writeRect(doc::SvgDoc, x::Float32, y::Float32, w::Float32, h::Float32;
    fill::ColorRGB, opacity::Float32 = 1f0)
    attrs = "x=\"$(fmt2(x))\" y=\"$(fmt2(y))\""
    attrs *= " width=\"$(fmt2(w))\" height=\"$(fmt2(h))\""
    attrs *= " fill=\"$(svgColor(fill))\""
    opacity < 1f0 && (attrs *= " fill-opacity=\"$(fmt2(opacity))\"")
    print(doc.buf, "  <rect $attrs/>\n")
end

function writeLine(doc::SvgDoc, x1::Float32, y1::Float32, x2::Float32, y2::Float32;
    stroke::ColorRGB, width::Float32 = 1f0, opacity::Float32 = 1f0,
    dash::Vector{Float32} = Float32[])
    attrs = "x1=\"$(fmt2(x1))\" y1=\"$(fmt2(y1))\""
    attrs *= " x2=\"$(fmt2(x2))\" y2=\"$(fmt2(y2))\""
    attrs *= " stroke=\"$(svgColor(stroke))\" stroke-width=\"$(fmt2(width))\""
    opacity < 1f0 && (attrs *= " stroke-opacity=\"$(fmt2(opacity))\"")
    !isempty(dash) &&
        (attrs *= " stroke-dasharray=\"$(join(map(fmt2, dash), " "))\"")
    print(doc.buf, "  <line $attrs/>\n")
end

doc = SvgDoc(W, H)
writeRect(doc, 0f0, 0f0, Float32(W), Float32(H); fill = rgb(15, 23, 42))
writeRect(doc, xCenter(upIdx) - bodyW / 2,
    yFor(max(candles[upIdx].open, candles[upIdx].close)),
    bodyW, max(yFor(min(candles[upIdx].open, candles[upIdx].close)) -
        yFor(max(candles[upIdx].open, candles[upIdx].close)), 1f0);
    fill = UP)
writeLine(doc, xCenter(upIdx), yFor(candles[upIdx].high),
    xCenter(upIdx), yFor(candles[upIdx].low); stroke = UP)
sample = finish(doc)
@assert startswith(sample, "<?xml") && endswith(sample, "</svg>\n")
@assert occursin("viewBox=\"0 0 800 500\"", sample)
println(sample)

#
# The `viewBox` is required by the library's SVG reader and also pins the
# coordinate system, so the file scales cleanly in browsers.
#
# ## 10. Emit the whole chart as SVG
#
# The candle loop mirrors section 5 exactly: same `yFor`/`xCenter`, same
# up/down color. The grid mirrors section 4 (note `stroke-opacity`, not a
# faded color — transparency in SVG is an attribute). Text uses `writeText`;
# the reader in section 11 skips those elements, which is fine, because
# they are the only thing a raster round trip cannot check.

# Text content is XML: escape the characters that would end the element.
# Ampersand first, so the escapes themselves are not re-escaped.
xmlEsc(s::String) = replace(s, "&" => "&amp;", "<" => "&lt;", ">" => "&gt;")

function writeText(doc::SvgDoc, s::String, x::Float32, y::Float32;
    fill::ColorRGB, size::Float32 = 13f0, anchor::String = "start")
    attrs = "x=\"$(fmt2(x))\" y=\"$(fmt2(y))\""
    attrs *= " fill=\"$(svgColor(fill))\" font-size=\"$(fmt2(size))\""
    anchor != "start" && (attrs *= " text-anchor=\"$anchor\"")
    print(doc.buf, "  <text $attrs>", xmlEsc(s), "</text>\n")
end

chart = SvgDoc(W, H)
writeRect(chart, 0f0, 0f0, Float32(W), Float32(H); fill = rgb(15, 23, 42))

# Grid + price labels (section 4).
for k in 0:ticks
    p = plotLow + span * k / Float64(ticks)
    y = yFor(p)
    writeLine(chart, PLOT_LEFT, y, PLOT_RIGHT, y;
        stroke = rgb(148, 163, 184), opacity = 60f0 / 255f0,
        dash = Float32[4f0, 4f0])
    label = "\$" * string(round(p / 1000, digits = 2)) * "k"
    writeText(chart, label, 792f0, y + 4f0;
        fill = rgb(148, 163, 184), anchor = "end")
end

# Volume bars (section 6).
for (i, c) in enumerate(candles)
    x = xCenter(i)
    vH = Float32(c.volume / volMax * (VOL_BOTTOM - VOL_TOP))
    writeRect(chart, x - bodyW / 2, VOL_BOTTOM - vH, bodyW, vH;
        fill = colorOf(c), opacity = 0.35f0)
end

# Candles (section 5): wick under body, per candle.
for (i, c) in enumerate(candles)
    x = xCenter(i)
    yTop = yFor(max(c.open, c.close))
    yBot = yFor(min(c.open, c.close))
    writeLine(chart, x, yFor(c.high), x, yFor(c.low); stroke = colorOf(c))
    writeRect(chart, x - bodyW / 2, yTop, bodyW, max(yBot - yTop, 1f0);
        fill = colorOf(c))
end

# Header, timestamps, legend (section 7). `text-anchor="end"` is the
# vector twin of the right alignment measured with `measureText` on canvas.
writeText(chart, "BTC-USD · 1h candles", 8f0, 26f0;
    fill = rgb(248, 250, 252), size = 18f0)
writeText(chart, string(round(last.close, digits = 2)), 792f0, 26f0;
    fill = colorOf(last), size = 16f0, anchor = "end")
for i in 1:4:24
    writeText(chart, "h" * string(i - 1), xCenter(i), 470f0;
        fill = rgb(100, 116, 139), size = 12f0, anchor = "middle")
end
for (k, (col, cap)) in enumerate([(UP, "up (close ≥ open)"), (DOWN, "down (close < open)")])
    lx = 8f0 + (k - 1) * 170f0
    writeRect(chart, lx, 442f0, 12f0, 12f0; fill = col)
    writeText(chart, cap, lx + 18f0, 452f0;
        fill = rgb(148, 163, 184), size = 12f0)
end

svgString = finish(chart)
svgPath = joinpath(outdir, "btc-chart.svg")
write(svgPath, svgString)
@assert isfile(svgPath)
svgLines = split(svgString, "\n")
@assert count(l -> occursin("<rect ", l), svgLines) >= 24 + 24 "every candle and volume bar is a rect"
@assert count(l -> occursin("<line ", l), svgLines) >= 24 + ticks
println("wrote ", svgPath, " (", filesize(svgPath), " bytes)")

#
# The element count asserts are the cheapest possible regression tests for
# a generated document: a loop that silently drops a candle changes the
# count, not the bytes.
#
# ## 11. Prove the SVG: read it back through Vetra
#
# The library's SVG reader implements the pinned subset — shapes, colors,
# stroke widths, opacity and dash arrays (it skips `<text>`). That makes it
# a ready-made **checker**: rasterize the SVG we just wrote and compare
# pixels against the raster chart from section 8. Text is exempt from the
# comparison; everything drawn with a shape is not.

readback = newImage(parseSvg(svgString))
@assert (width(readback), height(readback)) == (W, H)

# Opaque pixels: candle bodies, wick tops, legend swatches, background.
@assert getColor(readback, round(Int, xCenter(upIdx)),
    round(Int, (yFor(max(candles[upIdx].open, candles[upIdx].close)) +
        yFor(min(candles[upIdx].open, candles[upIdx].close))) / 2)) ==
    getColor(img, round(Int, xCenter(upIdx)),
        round(Int, (yFor(max(candles[upIdx].open, candles[upIdx].close)) +
            yFor(min(candles[upIdx].open, candles[upIdx].close))) / 2))
@assert getColor(readback, round(Int, xCenter(downIdx)),
    round(Int, yFor(candles[downIdx].high))) ==
    getColor(img, round(Int, xCenter(downIdx)), round(Int, yFor(candles[downIdx].high)))
@assert getColor(readback, 12, 448) == rgbx(UP)
@assert getColor(readback, 182, 448) == rgbx(DOWN)
@assert getColor(readback, 5, 5) == rgbx(rgb(15, 23, 42))

# Dashed grid: the lowest tick sits at y = 332; the dash pattern starts at
# x = 8, so pixel column 11 (center 11.5) is "on" and column 15 is "off".
# The dash *geometry* must be exact. The color may differ by 1 in a
# channel: the SVG reader applies upstream's float `stroke-opacity`
# rounding, while context strokes use byte alpha — a documented ±1 ulp
# difference, not a writer bug.
bottomY = round(Int, yFor(plotLow))
on = getColor(readback, 11, bottomY)
off = getColor(readback, 15, bottomY)
@assert on != rgbx(rgb(15, 23, 42))
@assert off == rgbx(rgb(15, 23, 42))
for ch in ((on.r, getColor(img, 11, bottomY).r),
           (on.g, getColor(img, 11, bottomY).g),
           (on.b, getColor(img, 11, bottomY).b))
    @assert abs(Int(ch[1]) - Int(ch[2])) <= 1
end
TutorialFigure(readback)

#
# The readback is what the library renders from our SVG — grid dashes,
# candle wicks, bodies and legend included. If your writer's attribute
# names or coordinate mapping drift from the raster path, one of these
# comparisons fails before a human ever opens the file. (Open
# `btc-chart.svg` in a browser to see the full document, including the
# text elements this reader skips.)
#
# ## 12. Test and benchmark habits for chart code
#
# The assertions above are the pattern worth stealing:
#
# - **Assert from the data, not from constants.** Candle-center checks use
#   `xCenter`/`yFor`, so a broken mapping fails loudly.
# - **Check the states you care about.** Translucent volume (`0 < a < 255`),
#   opaque bodies, untouched background.
# - **For generated documents, count elements first**, then spot-read
#   pixels by rendering the document through whatever parser you have.
# - **Keep the writer and the checker honest with each other** by feeding
#   both from the same mapping functions — here `yFor` serves sections 4–8
#   *and* 10.
#
# The repository's full suite is behavior tests plus pinned upstream
# fixtures; run it from the checkout root:
#
# ```sh
# julia --startup-file=no --project=. scripts/check.jl
# ```
#
# For performance, keep the section 8 lesson: separating the three costs —
# first-call load, the render loop, and encoding — is what the T011
# harness in `benchmark/run_benchmarks.jl` does, and its results are
# recorded in [tasks/T011-release.md](https://github.com/skynet-core/Vetra.jl/blob/main/tasks/T011-release.md).
# A chart loop over thousands of candles is exactly the kind of workload to
# measure before "optimizing" it.
#
# ## 13. Troubleshooting and next charts
#
# | Symptom | What to check |
# | --- | --- |
# | `MethodError` for drawing coordinates | Most draw calls want `Float32`; use `12f0` or `Float32(x)`. |
# | PNG write asks for a package | `PNGFiles` is opt-in (D014); it is installed in this tutorial's `docs` environment. |
# | SVG read-back ignores labels | `<text>` is outside the pinned subset; shape geometry is what round-trips. |
# | `Invalid SVG data` when parsing | The reader requires a `viewBox`; unsupported elements raise. |
# | “No font has been set” | Assign `ctx.font` a path to a compatible TTF/glyf font. |
# | Chart shifts after editing | Re-check `xCenter`/`yFor` and any `save`/`restore` balance; remember the path and `textBaseline` are not saved state. |
#
# Next charts, in increasing order of scope:
#
# 1. **Moving average.** Plot a 5-candle simple moving average as a
#    `Path` of `moveTo`/`lineTo` (raster) and a single `<path d="…">`
#    (SVG) — the first true path element in the vector output.
# 2. **Log scale.** Replace `yFor` with a log-space mapping; the grid tick
#    labels then need their own rounding.
# 3. **Crosshair tooltip.** Use `isPointInPath` to hit-test candles under a
#    cursor position and render a callout box with `saveLayer` for the
#    shadow.
# 4. **Two symbols.** Draw BTC and ETH on shared volume with separate
#    scales — and emit each as its own `<g>` in the SVG.
# 5. **Real data.** Replace the seeded walk with exchange OHLC rows (same
#    fields); nothing else in the tutorial changes.
#
# The habit to keep from this tutorial: **map data to geometry once, then
# send that geometry to every backend you need.** Vetra's raster `Context`
# was the first; the ~60-line `SvgDoc` was the second. The project's
# backend seam (D007) exists so the third one — whatever display or GPU
# surface you eventually need — starts from the same chart code.
