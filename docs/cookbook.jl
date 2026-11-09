# Cookbook: small reproducible Vetra.jl recipes
#
# Every recipe below is a plain Julia function that takes deterministic
# inputs (no randomness, no network, no system fonts) and returns an
# `Image`. Each section draws one recipe, asserts on concrete pixels,
# saves a named PNG under `docs/build/cookbook/`, and displays the result.
#
# Font setup is explicit: the two typefaces come from the pinned upstream
# fixtures (Apache-licensed; provenance in [NOTICE](../../../NOTICE)) and are
# fetched by `scripts/fetch_upstream.jl`. Substitute any TTF/glyf font path
# you own.
#
# Run this file directly:
#
#     julia --startup-file=no --project=docs docs/cookbook.jl
#
# or build the executed Markdown + notebook + gallery with
# `docs/make_cookbook.jl`.

using Vetra

root = dirname(dirname(pathof(Vetra)))
fontdir = joinpath(root, ".reference", "upstream", "tests", "fonts")
@assert isdir(fontdir) "Run `julia --project=. scripts/fetch_upstream.jl` from the repository root first"
ROBOTO = joinpath(fontdir, "Roboto-Regular_1.ttf")
NOTO_SANS = joinpath(fontdir, "NotoSans-Regular_4.ttf")
outdir = joinpath(root, "docs", "build", "cookbook")
mkpath(outdir)

# Named exports so the gallery links are stable across reruns.
function save_named(img, name)
    path = joinpath(outdir, name)
    writeFile(img, path)
    @assert isfile(path) && filesize(path) > 500
    return path
end

# Shared deterministic sample series (a rising 24-sample walk).
values = [42, 48, 45, 52, 61, 58, 66, 72, 69, 78, 74, 83,
          90, 86, 95, 102, 98, 108, 117, 112, 121, 128, 124, 133]

#
# ## 1. Sparkline
#
# A sparkline is a miniature line chart: one stroke, a soft area under it,
# and a marker on the latest sample. Expected result: a blue line trending
# upward on a white 320x96 card.

function sparkline_image(samples;
    color = rgb(37, 99, 235),
    background = rgb(255, 255, 255),
    width = 320, height = 96)
    length(samples) >= 2 || throw(ArgumentError("need at least two samples"))
    img = newImage(width, height)
    ctx = Context(img)
    if background !== nothing
        ctx.fillStyle = background
        fillRect(ctx, 0, 0, width, height)
    end
    pad = Float32(12)
    vmin, vmax = minimum(samples), maximum(samples)
    span = vmax - vmin
    span == 0 && (span = 1)
    px(i) = pad + Float32(i - 1) / (length(samples) - 1) * (width - 2pad)
    py(v) = pad + (vmax - v) / span * (height - 2pad)
    ## Soft area under the line.
    area = newPath()
    moveTo(area, px(1), height - pad)
    for i in 1:length(samples)
        lineTo(area, px(i), py(samples[i]))
    end
    lineTo(area, px(length(samples)), height - pad)
    closePath(area)
    ctx.fillStyle = rgba(color.r, color.g, color.b, 36)
    fill(ctx, area)
    ## The line itself.
    line = newPath()
    moveTo(line, px(1), py(samples[1]))
    for i in 2:length(samples)
        lineTo(line, px(i), py(samples[i]))
    end
    ctx.strokeStyle = color
    ctx.lineWidth = 3
    ctx.lineCap = RoundCap
    ctx.lineJoin = RoundJoin
    stroke(ctx, line)
    ## Marker on the latest sample.
    last = newPath()
    circle(last, px(length(samples)), py(samples[end]), 4.5)
    ctx.fillStyle = color
    fill(ctx, last)
    return img
end

spark = sparkline_image(values)
@assert (width(spark), height(spark)) == (320, 96)
@assert getColor(spark, 2, 2) == rgbx(255, 255, 255, 255)
@assert getColor(spark, 308, 12) == rgbx(37, 99, 235, 255)   # last-sample marker
tinted = getColor(spark, 160, 70)                            # area fill under the line
@assert tinted.r < 230 && tinted.b > 248
save_named(spark, "sparkline.png")

spark

#
# ## 2. Radial gauge
#
# A speedometer-style gauge: a gray semicircular track, a colored value arc,
# a needle, and a percentage label. The arc sweeps from left (angle pi)
# through the top to right (angle 2*pi). Expected result: at 0.5 the value
# arc reaches exactly the top and the right half of the track stays gray.

function gauge_image(fraction;
    color = rgb(22, 163, 74),
    track = rgb(226, 232, 240),
    background = rgb(255, 255, 255),
    width = 240, height = 240)
    0 <= fraction <= 1 || throw(ArgumentError("fraction must be in [0, 1]"))
    img = newImage(width, height)
    ctx = Context(img)
    ctx.fillStyle = background
    fillRect(ctx, 0, 0, width, height)
    cx, cy = Float32(width / 2), Float32(130)
    r, lw = Float32(70), Float32(22)
    ctx.lineCap = RoundCap
    ctx.lineWidth = lw
    ctx.strokeStyle = track
    tpath = newPath()
    arc(tpath, cx, cy, r, pi, 2pi)
    stroke(ctx, tpath)
    ctx.strokeStyle = color
    vpath = newPath()
    arc(vpath, cx, cy, r, pi, pi + pi * Float32(fraction))
    stroke(ctx, vpath)
    ang = pi + pi * Float32(fraction)
    ctx.strokeStyle = rgb(51, 65, 85)
    ctx.lineWidth = 4
    strokeSegment(ctx, cx, cy, cx + (r - 20) * cos(ang), cy + (r - 20) * sin(ang))
    hub = newPath()
    circle(hub, cx, cy, 8)
    ctx.fillStyle = rgb(51, 65, 85)
    fill(ctx, hub)
    ctx.font = NOTO_SANS
    ctx.fontSize = 34
    ctx.fillStyle = rgb(17, 24, 39)
    ctx.textAlign = CenterAlign
    ctx.textBaseline = MiddleBaseline
    fillText(ctx, string(Int(round(fraction * 100)), "%"), cx, cy + 48)
    ctx.textAlign = LeftAlign
    ctx.textBaseline = AlphabeticBaseline
    return img
end

gauge = gauge_image(0.5)
@assert (width(gauge), height(gauge)) == (240, 240)
@assert getColor(gauge, 120, 60) == rgbx(22, 163, 74, 255)   # value arc reaches the top
@assert getColor(gauge, 190, 130) == rgbx(226, 232, 240, 255) # right end stays track gray
@assert getColor(gauge, 50, 130) == rgbx(22, 163, 74, 255)   # left end is under the value arc
@assert getColor(gauge, 120, 90) == rgbx(51, 65, 85, 255)    # needle points up at 0.5
save_named(gauge, "gauge.png")

gauge

#
# ## 3. KPI card
#
# A key-performance-indicator card: a white rounded card with a soft shadow,
# a label, a large value, and a delta pill. Expected result: the card corner
# is rounded (background shows through), the interior is white, and the
# green pill sits at the right edge.

function kpi_image(value, label, delta; up = true,
    width = 320, height = 160)
    img = newImage(width, height)
    ctx = Context(img)
    ctx.fillStyle = rgb(241, 245, 249)
    fillRect(ctx, 0, 0, width, height)
    ## Card on its own layer, then shadowed.
    card = newImage(width, height)
    cardctx = Context(card)
    cardshape = newPath()
    roundedRect(cardshape, 12, 12, width - 24, height - 24, 16, 16, 16, 16)
    cardctx.fillStyle = rgb(255, 255, 255)
    fill(cardctx, cardshape)
    drawImage(ctx, shadow(card, Vec2(0, 2), 1, 8, rgba(15, 23, 42, 40)), 0, 0)
    drawImage(ctx, card, 0, 0)
    ctx.font = ROBOTO
    ctx.fontSize = 14
    ctx.fillStyle = rgb(71, 85, 105)
    fillText(ctx, label, 32, 44)
    ctx.font = NOTO_SANS
    ctx.fontSize = 44
    ctx.fillStyle = rgb(17, 24, 39)
    fillText(ctx, value, 32, 92)
    pill = newPath()
    roundedRect(pill, width - 96, 78, 64, 26, 13, 13, 13, 13)
    ctx.fillStyle = up ? rgb(220, 252, 231) : rgb(254, 226, 226)
    fill(ctx, pill)
    ctx.font = ROBOTO
    ctx.fontSize = 13
    ctx.fillStyle = up ? rgb(22, 101, 52) : rgb(153, 27, 27)
    ctx.textAlign = CenterAlign
    ctx.textBaseline = MiddleBaseline
    fillText(ctx, delta, width - 64, 91)
    ctx.textAlign = LeftAlign
    ctx.textBaseline = AlphabeticBaseline
    return img
end

kpi = kpi_image("1,284", "Daily active users", "+8.2%")
@assert (width(kpi), height(kpi)) == (320, 160)
@assert getColor(kpi, 2, 2) == rgbx(241, 245, 249, 255)   # page background
@assert getColor(kpi, 20, 20) == rgbx(255, 255, 255, 255) # card interior
@assert getColor(kpi, 232, 82).g > 240                    # green delta pill
save_named(kpi, "kpi.png")

kpi

#
# ## 4. Candlesticks (minimal)
#
# Twelve deterministic OHLC bars: green for close >= open, red otherwise,
# with a 2px wick from low to high. The full candlestick project (axes,
# price labels, SVG export, pixel checks) is the
# [OHLC tutorial](../../TUTORIAL.md); this is the smallest reproducible version.

ohlc = [
    (100, 106, 98, 104), (104, 107, 99, 101), (101, 108, 100, 106),
    (106, 109, 102, 103), (103, 112, 102, 110), (110, 113, 105, 107),
    (107, 116, 106, 114), (114, 117, 109, 111), (111, 120, 110, 118),
    (118, 121, 112, 115), (115, 124, 114, 122), (122, 126, 118, 124),
]

function candles_image(bars; width = 480, height = 280,
    up = rgb(22, 163, 74), down = rgb(220, 38, 38))
    img = newImage(width, height)
    ctx = Context(img)
    ctx.fillStyle = rgb(255, 255, 255)
    fillRect(ctx, 0, 0, width, height)
    pad = Float32(24)
    vmin = minimum(l for (_, _, l, _) in bars)
    vmax = maximum(h for (_, h, _, _) in bars)
    px(i) = pad + Float32(i - 1) * (width - 2pad) / (length(bars) - 1)
    py(v) = pad + (vmax - v) / (vmax - vmin) * (height - 2pad)
    for (i, (o, h, l, c)) in enumerate(bars)
        x = px(i)
        ctx.strokeStyle = c >= o ? up : down
        ctx.lineWidth = 2
        strokeSegment(ctx, x, py(h), x, py(l))
        top, bot = min(py(o), py(c)), max(py(o), py(c))
        bot - top < 2 && (bot = top + 2)
        ctx.fillStyle = c >= o ? up : down
        fillRect(ctx, x - 8, top, 16, bot - top)
    end
    return img
end

candles = candles_image(ohlc)
@assert (width(candles), height(candles)) == (480, 280)
@assert getColor(candles, 24, 223) == rgbx(22, 163, 74, 255)  # bar 1 body (up)
@assert getColor(candles, 63, 218) == rgbx(220, 38, 38, 255)  # bar 2 body (down)
@assert getColor(candles, 24, 195) == rgbx(22, 163, 74, 255)  # bar 1 wick
save_named(candles, "candles.png")

candles

#
# ## 5. Image annotation
#
# Draw callouts on an existing image: a bounding box, a labeled chip, and a
# leader line. The "photo" is synthesized so the recipe is reproducible.
# Expected result: two red callouts on a landscape scene, one on the sun,
# one on the mountain peak.

function annotated_scene()
    img = newImage(320, 240)
    ctx = Context(img)
    sky = Paint(LinearGradientPaint)
    sky.gradientHandlePositions = [Vec2(0, 0), Vec2(0, 240)]
    sky.gradientStops = [
        colorStop(rgb(56, 189, 248), 0f0),
        colorStop(rgb(224, 242, 254), 1f0),
    ]
    ctx.fillStyle = sky
    fillRect(ctx, 0, 0, 320, 240)
    sun = newPath()
    circle(sun, 240, 70, 26)
    ctx.fillStyle = rgb(253, 224, 71)
    fill(ctx, sun)
    mountain = newPath()
    moveTo(mountain, 30, 190)
    lineTo(mountain, 110, 84)
    lineTo(mountain, 190, 190)
    closePath(mountain)
    ctx.fillStyle = rgb(71, 85, 105)
    fill(ctx, mountain)
    ctx.fillStyle = rgb(134, 239, 172)
    fillRect(ctx, 0, 190, 320, 50)
    return img
end

function callout(img, label, box, chip)
    x, y, w, h = box
    cx, cy = chip
    ctx = Context(img)
    ctx.font = ROBOTO
    ctx.fontSize = 12
    chipw = measureText(ctx, label).width + 14
    ctx.strokeStyle = rgb(220, 38, 38)
    ctx.lineWidth = 2
    strokeRect(ctx, x, y, w, h)
    ctx.lineWidth = 1
    strokeSegment(ctx, cx + chipw, cy + 10, x + w / 2, y + h / 2)
    chipshape = newPath()
    roundedRect(chipshape, cx, cy, chipw, 20, 9, 9, 9, 9)
    ctx.fillStyle = rgb(220, 38, 38)
    fill(ctx, chipshape)
    ctx.fillStyle = rgb(255, 255, 255)
    ctx.textAlign = CenterAlign
    ctx.textBaseline = MiddleBaseline
    fillText(ctx, label, cx + chipw / 2, cy + 10)
    ctx.textAlign = LeftAlign
    ctx.textBaseline = AlphabeticBaseline
end

scene = annotated_scene()
callout(scene, "Sun", (208, 38, 64, 64), (96, 16))
callout(scene, "Peak", (82, 78, 56, 56), (14, 40))
@assert (width(scene), height(scene)) == (320, 240)
@assert getColor(scene, 210, 38).r > 200   # box 1 top edge
@assert getColor(scene, 84, 78).r > 200    # box 2 top edge
@assert getColor(scene, 100, 20).g < 60    # chip 1 fill
save_named(scene, "annotation.png")

scene

#
# ## 6. Scientific diagram
#
# A labeled plot of the damped sine y = exp(-x/6) * sin(x) on [0, 3*pi]:
# dashed grid, solid axes with ticks and labels, a 3px curve, and a marker
# on the first maximum (tan(x) = 6, so x = arctan(6) ~= 1.4056,
# y ~= 0.7811). Expected result: the curve peaks just left of x = 1.4
# and decays toward zero.

function diagram_image()
    W, H = 480, 320
    img = newImage(W, H)
    ctx = Context(img)
    ctx.fillStyle = rgb(255, 255, 255)
    fillRect(ctx, 0, 0, W, H)
    left, right = Float32(56), Float32(456)
    top, bottom = Float32(36), Float32(272)
    xmin, xmax = Float32(0), Float32(3 * pi)
    px(v) = left + (v - xmin) / (xmax - xmin) * (right - left)
    py(v) = top + (1 - v) / 2 * (bottom - top)
    ctx.strokeStyle = rgb(226, 232, 240)
    ctx.lineWidth = 1
    setLineDash(ctx, Float32[4, 5])
    for gx in 0:6
        strokeSegment(ctx, px(gx * pi / 2), top, px(gx * pi / 2), bottom)
    end
    for gy in Float32[-1, -0.5, 0, 0.5, 1]
        strokeSegment(ctx, left, py(gy), right, py(gy))
    end
    setLineDash(ctx, Float32[])
    ctx.strokeStyle = rgb(51, 65, 85)
    ctx.lineWidth = 2
    strokeSegment(ctx, left, top, left, bottom)
    strokeSegment(ctx, left, bottom, right, bottom)
    ctx.font = ROBOTO
    ctx.fontSize = 11
    ctx.fillStyle = rgb(71, 85, 105)
    ctx.textAlign = CenterAlign
    ctx.textBaseline = TopBaseline
    for (gx, name) in enumerate(["0.0", "1.6", "3.1", "4.7", "6.3", "7.9", "9.4"])
        strokeSegment(ctx, px((gx - 1) * pi / 2), bottom, px((gx - 1) * pi / 2), bottom + 6)
        fillText(ctx, name, px((gx - 1) * pi / 2), bottom + 10)
    end
    ctx.textAlign = RightAlign
    ctx.textBaseline = MiddleBaseline
    for label in ["1.0", "0.5", "0.0", "-0.5", "-1.0"]
        v = parse(Float32, label)
        strokeSegment(ctx, left - 6, py(v), left, py(v))
        fillText(ctx, label, left - 10, py(v))
    end
    ctx.textAlign = LeftAlign
    curve = newPath()
    n = 240
    for k in 0:n
        x = xmin + (xmax - xmin) * k / n
        y = exp(-x / 6) * sin(x)
        k == 0 ? moveTo(curve, px(x), py(y)) : lineTo(curve, px(x), py(y))
    end
    ctx.strokeStyle = rgb(37, 99, 235)
    ctx.lineWidth = 3
    ctx.lineJoin = RoundJoin
    stroke(ctx, curve)
    x0 = Float32(1.4056)
    y0 = exp(-x0 / 6) * sin(x0)
    marker = newPath()
    circle(marker, px(x0), py(y0), 4)
    ctx.fillStyle = rgb(37, 99, 235)
    fill(ctx, marker)
    ctx.font = ROBOTO
    ctx.fontSize = 12
    ctx.fillStyle = rgb(51, 65, 85)
    ctx.textBaseline = AlphabeticBaseline
    fillText(ctx, "y = exp(-x/6) * sin(x)", left, 24)
    fillText(ctx, "first maximum", px(x0) + 10, py(y0) - 10)
    return img
end

diagram = diagram_image()
@assert (width(diagram), height(diagram)) == (480, 320)
@assert getColor(diagram, 116, 62) == rgbx(37, 99, 235, 255)  # first-maximum marker
@assert getColor(diagram, 300, 272) == rgbx(51, 65, 85, 255)  # bottom axis
save_named(diagram, "diagram.png")

diagram

#
# ## 7. Dashboard thumbnail
#
# Compose the earlier recipes into one 480x320 thumbnail: a header, the
# gauge on the right, a 200-wide sparkline top-left, and the KPI card
# scaled 320x160 -> 200x100 (exact 2:1 ratio, so no distortion). Expected
# result: three widgets on a gray page with a white header bar.

function dashboard_image(samples)
    W, H = 480, 320
    img = newImage(W, H)
    ctx = Context(img)
    ctx.fillStyle = rgb(241, 245, 249)
    fillRect(ctx, 0, 0, W, H)
    ctx.fillStyle = rgb(255, 255, 255)
    fillRect(ctx, 0, 0, W, 48)
    ctx.font = NOTO_SANS
    ctx.fontSize = 18
    ctx.fillStyle = rgb(17, 24, 39)
    fillText(ctx, "Ops dashboard", 16, 30)
    pill = newPath()
    roundedRect(pill, W - 76, 12, 60, 24, 12, 12, 12, 12)
    ctx.fillStyle = rgb(220, 252, 231)
    fill(ctx, pill)
    ctx.font = ROBOTO
    ctx.fontSize = 12
    ctx.fillStyle = rgb(22, 101, 52)
    ctx.textAlign = CenterAlign
    ctx.textBaseline = MiddleBaseline
    fillText(ctx, "live", W - 46, 24)
    ctx.textAlign = LeftAlign
    ctx.textBaseline = AlphabeticBaseline
    drawImage(ctx, gauge_image(0.5; background = rgb(241, 245, 249)), 232, 64)
    drawImage(ctx, sparkline_image(samples; width = 200, height = 88), 16, 64)
    drawImage(ctx, kpi_image("1,284", "Daily active users", "+8.2%"),
        16, 168, 200, 100)
    return img
end

dash = dashboard_image(values)
@assert (width(dash), height(dash)) == (480, 320)
@assert getColor(dash, 2, 2) == rgbx(255, 255, 255, 255)       # header
@assert getColor(dash, 282, 194) == rgbx(22, 163, 74, 255)     # gauge value arc end
kp = getColor(dash, 30, 200)                                   # KPI card, resampled
@assert kp.r > 240 && kp.g > 240 && kp.b > 240
save_named(dash, "dashboard.png")

dash

#
# ## 8. Social card
#
# A 1200x630 link-preview card (Open Graph size): dark diagonal gradient,
# brand pill, title, subtitle, a frosted panel with a sparkline, and a
# footer. Expected result: the pill is solid blue at the top-left, the
# panel is only slightly brighter than the dark background, and the
# gradient darkens toward the top-left corner.

function social_card_image(title, subtitle, samples)
    W, H = 1200, 630
    img = newImage(W, H)
    ctx = Context(img)
    bg = Paint(LinearGradientPaint)
    bg.gradientHandlePositions = [Vec2(0, 0), Vec2(W, H)]
    bg.gradientStops = [
        colorStop(rgb(15, 23, 42), 0f0),
        colorStop(rgb(30, 41, 59), 1f0),
    ]
    ctx.fillStyle = bg
    fillRect(ctx, 0, 0, W, H)
    pill = newPath()
    roundedRect(pill, 48, 48, 176, 56, 28, 28, 28, 28)
    ctx.fillStyle = rgb(37, 99, 235)
    fill(ctx, pill)
    ctx.font = NOTO_SANS
    ctx.fontSize = 26
    ctx.fillStyle = rgb(255, 255, 255)
    ctx.textAlign = CenterAlign
    ctx.textBaseline = MiddleBaseline
    fillText(ctx, "Vetra.jl", 48 + 88, 48 + 28)
    ctx.textAlign = LeftAlign
    ctx.textBaseline = AlphabeticBaseline
    ctx.font = NOTO_SANS
    ctx.fontSize = 56
    ctx.fillStyle = rgb(248, 250, 252)
    fillText(ctx, title, 48, 260)
    ctx.font = ROBOTO
    ctx.fontSize = 26
    ctx.fillStyle = rgb(148, 163, 184)
    fillText(ctx, subtitle, 48, 320)
    panel = newPath()
    roundedRect(panel, 816, 420, 336, 164, 20, 20, 20, 20)
    ctx.fillStyle = rgba(255, 255, 255, 24)
    fill(ctx, panel)
    drawImage(ctx, sparkline_image(samples; background = nothing,
        width = 288, height = 96), 840, 452)
    ctx.font = ROBOTO
    ctx.fontSize = 18
    ctx.fillStyle = rgb(100, 116, 139)
    fillText(ctx, "Rendered natively in Julia - no external chart library", 48, 560)
    return img
end

card = social_card_image("Render charts in Julia", "Vetra.jl is a native port of pixie", values)
@assert (width(card), height(card)) == (1200, 630)
@assert getColor(card, 70, 60) == rgbx(37, 99, 235, 255)   # brand pill
corner = getColor(card, 20, 20)                            # top-left gradient
@assert corner.r < 20 && corner.b < 50
panel = getColor(card, 830, 435)                           # frosted panel over the gradient
@assert 40 < panel.r < 60
save_named(card, "social-card.png")

card

#
# ## 9. Record once, replay at two sizes
#
# A `PictureRecorder` captures a scene as a display list instead of pixels
# (T023 contract, D030): the same scene function draws on an immediate
# `Context` or on the recorder's context. The picture replays into any
# image, and scaling happens in vector space - the 960x600 replay below is
# re-rasterized, not an enlarged copy of the 480x300 raster.

function spark_scene(ctx)
    ctx.fillStyle = rgb(248, 250, 252)
    fillRect(ctx, 0, 0, 480, 300)
    ctx.strokeStyle = rgb(37, 99, 235)
    ctx.lineWidth = 3f0
    beginPath(ctx)
    for (i, v) in enumerate(values)
        x = 20 + (i - 1) * 18
        y = 260 - v * 1.6
        if i == 1
            moveTo(ctx, x, y)
        else
            lineTo(ctx, x, y)
        end
    end
    stroke(ctx)
    ctx.fillStyle = rgb(37, 99, 235)
    circle(ctx, 20 + 22 * 18, 260 - values[end] * 1.6, 6)
    fill(ctx)
    ctx.font = ROBOTO
    ctx.fontSize = 16f0
    ctx.fillStyle = rgb(15, 23, 42)
    fillText(ctx, "24 samples", 20, 40)
    return nothing
end

# Direct (raster) reference.
direct = newImage(480, 300)
spark_scene(Context(direct))

# Record once.
recorder = PictureRecorder(480, 300)
spark_scene(recorder.ctx)
picture = finishRecording(recorder)
# Four ops: background FillOp, sparkline StrokeOp, end-dot FillOp, label FillOp.
@assert length(picture.ops) == 4

# Replay at the recorded size: byte-identical to the direct drawing.
replay = newImage(480, 300)
drawPicture(replay, picture)
@assert replay.data == direct.data

# Replay at 2x: re-rasterized in vector space. The end dot (picture-space
# center (416, 47.2), radius 6) lands at (832, 94.4), radius 12; pixel
# center (831.5, 93.5) is fully inside it and (1.5, 1.5) is background.
zoom = newImage(960, 600)
drawPicture(zoom, picture)
@assert getColor(zoom, 832, 94) == rgbx(37, 99, 235, 255)
@assert getColor(zoom, 2, 2) == rgbx(248, 250, 252, 255)
save_named(replay, "record-replay-480.png")
save_named(zoom, "record-replay-960.png")

zoom

#
# ## 10. Record, replay, and export as SVG
#
# The same recorded picture from recipe 9's world renders three ways:
# as pixels (direct), as pixels (replay - byte-identical), and as an
# editable standalone SVG (`writeSvg`, T025). The SVG keeps every op as
# geometry: paths stay paths, the gradient stays a `<linearGradient>`,
# the dashed line keeps its dash array, and the clip stays a `<clipPath>`.

# The scene: a dark background, a blue->green gradient panel (its
# canvas-anchored handles export verbatim), a yellow badge clipped to a
# circle (the clip survives into the SVG), a round-capped dashed divider,
# and a text label (exported as glyph outline paths, per D030).

function badge_scene(ctx)
    ctx.fillStyle = rgb(15, 23, 42)
    fillRect(ctx, 0, 0, 480, 300)
    lin = Paint(LinearGradientPaint)
    lin.gradientHandlePositions = [Vec2(20f0, 60f0), Vec2(320f0, 220f0)]
    lin.gradientStops = [
        colorStop(rgba(59, 130, 246, 255), 0f0),
        colorStop(rgba(16, 185, 129, 255), 1f0)]
    ctx.fillStyle = lin
    fillRect(ctx, 20, 60, 300, 160)
    badge = newPath()
    circle(badge, 390f0, 140f0, 70f0)
    save(ctx)
    clip(ctx, badge)
    ctx.fillStyle = rgb(251, 191, 36)
    fillRect(ctx, 320, 70, 140, 140)
    restore(ctx)
    ctx.strokeStyle = rgb(148, 163, 184)
    ctx.lineWidth = 2f0
    ctx.lineCap = RoundCap
    ctx.lineDash = Float32[6f0, 4f0]
    beginPath(ctx)
    moveTo(ctx, 20f0, 250f0)
    lineTo(ctx, 460f0, 250f0)
    stroke(ctx)
    ctx.lineDash = Float32[]
    ctx.font = ROBOTO
    ctx.fontSize = 18f0
    ctx.fillStyle = rgb(226, 232, 240)
    fillText(ctx, "record -> replay -> svg", 20, 40)
    return nothing
end

direct = newImage(480, 300)
badge_scene(Context(direct))
recorder = PictureRecorder(480, 300)
badge_scene(recorder.ctx)
picture = finishRecording(recorder)
replay = newImage(480, 300)
drawPicture(replay, picture)
@assert replay.data == direct.data

# Export the vector document.
svg_file = joinpath(outdir, "record.svg")
svg_doc = writeSvg(svg_file, picture)
@assert occursin("<linearGradient", svg_doc)
@assert occursin("clipPath", svg_doc)
@assert occursin("stroke-dasharray=\"6.0 4.0\"", svg_doc)
@assert occursin("viewBox=\"0 0 480 300\"", svg_doc)

save_named(replay, "record-10-replay.png")

# The SVG next to the raster: open `record.svg` in any browser or editor
# to see the same scene as vectors.
replay

#
# ## 11. Record and export as PDF (scale-independent)
#
# The same recorded picture exports as a single-page vector PDF
# (`writePdf`, T026): paths stay paths, the gradients stay PDF shadings,
# dashes keep their dash array, and text stays glyph outline paths. Page
# units are points, and `dpi` picks the physical scale — so the same
# picture exports at any size with identical vector content.

# A small report graphic: a linear-gradient panel, a radial-gradient
# dial, a dashed baseline, and a label.

function report_scene(ctx)
    ctx.fillStyle = rgb(248, 250, 252)
    fillRect(ctx, 0, 0, 480, 300)
    lin = Paint(LinearGradientPaint)
    lin.gradientHandlePositions = [Vec2(0f0, 0f0), Vec2(0f0, 240f0)]
    lin.gradientStops = [
        colorStop(rgba(37, 99, 235, 255), 0f0),
        colorStop(rgba(16, 185, 129, 255), 1f0)]
    ctx.fillStyle = lin
    fillRect(ctx, 40, 60, 120, 180)
    rad = Paint(RadialGradientPaint)
    rad.gradientHandlePositions = [Vec2(300f0, 150f0), Vec2(230f0, 150f0),
        Vec2(300f0, 220f0)]
    rad.gradientStops = [
        colorStop(rgba(251, 191, 36, 255), 0f0),
        colorStop(rgba(244, 63, 94, 255), 1f0)]
    ctx.fillStyle = rad
    beginPath(ctx)
    circle(ctx, 300, 150, 70)
    fill(ctx)
    ctx.strokeStyle = rgb(51, 65, 85)
    ctx.lineWidth = 2f0
    ctx.lineCap = RoundCap
    ctx.lineDash = Float32[8f0, 4f0]
    beginPath(ctx)
    moveTo(ctx, 40f0, 270f0)
    lineTo(ctx, 440f0, 270f0)
    stroke(ctx)
    ctx.lineDash = Float32[]
    ctx.font = ROBOTO
    ctx.fontSize = 20f0
    ctx.fillStyle = rgb(15, 23, 42)
    fillText(ctx, "report @ any dpi", 40, 40)
    return nothing
end

direct = newImage(480, 300)
report_scene(Context(direct))
recorder = PictureRecorder(480, 300)
report_scene(recorder.ctx)
picture = finishRecording(recorder)
replay = newImage(480, 300)
drawPicture(replay, picture)
@assert replay.data == direct.data

# Two exports of the same picture: 96 dpi and 288 dpi. The 288-dpi page
# is a quarter of the point size; each re-rasterized at its own dpi is
# the identical 480x300 picture.
doc96 = writePdf(joinpath(outdir, "record-11-96.pdf"), picture;
    dpi = 96f0)
doc288 = writePdf(joinpath(outdir, "record-11-288.pdf"), picture;
    dpi = 288f0)
@assert occursin("/MediaBox [0 0 360.0 225.0]", doc96)
@assert occursin("/MediaBox [0 0 120.0 75.0]", doc288)
@assert occursin("/ShadingType 2", doc96)
@assert occursin("/ShadingType 3", doc288)

save_named(replay, "record-11-replay.png")

# The replayed raster stands in for the PDFs in the gallery; the two
# vector files (record-11-96.pdf, record-11-288.pdf) live next to it in
# docs/build/cookbook/.
replay

#
# ## 12. Paragraph card (wrapped, styled, T028)
#
# A text-heavy card composed with the new Paragraph API (D031,
# docs/TEXT_LAYOUT.md): a body paragraph with mixed styled runs wrapped
# into a 296px box at an absolute line height, and a smaller footnote
# paragraph below it. The title still uses the legacy single-line
# fillText — both text paths coexist. Expected: the page background, the
# white card, the body ink strictly inside its box, and no ink in the
# gap between the body and the footnote.

function paragraph_card_image()
    width = 360
    height = 250
    img = newImage(width, height)
    ctx = Context(img)
    ctx.fillStyle = rgb(241, 245, 249)
    fillRect(ctx, 0, 0, width, height)
    card = newImage(width, height)
    cardctx = Context(card)
    cardshape = newPath()
    roundedRect(cardshape, 12, 12, width - 24, height - 24, 16, 16, 16, 16)
    cardctx.fillStyle = rgb(255, 255, 255)
    fill(cardctx, cardshape)
    drawImage(ctx, shadow(card, Vec2(0, 2), 1, 8, rgba(15, 23, 42, 40)), 0, 0)
    drawImage(ctx, card, 0, 0)
    ## Title: legacy single-line text (T009 path).
    ctx.font = ROBOTO
    ctx.fontSize = 18f0
    ctx.fillStyle = rgb(15, 23, 42)
    fillText(ctx, "Release notes", 32, 40)
    ## Body: styled runs wrapped into the box (T028 path).
    tfR = readTypeface(ROBOTO)
    tfN = readTypeface(NOTO_SANS)
    fA = Font(tfR, Float32(15), autoLineHeight,
        [Paint(rgba(51, 65, 85, 255))], NormalCase, false, false, false)
    fStrong = Font(tfN, Float32(15), autoLineHeight,
        [Paint(rgba(30, 64, 175, 255))], NormalCase, false, false, false)
    body = newParagraph([
        newSpan("Vetra.jl now lays out ", fA),
        newSpan("paragraphs", fStrong),
        newSpan(" with wrapped lines, styled runs, ordered font fallback,\n" *
            "grapheme clusters, and a clipped box.", fA)],
        width = 296, height = 110, lineHeight = 22,
        hAlign = LeftAlign, vAlign = TopAlign, overflow = ClipOverflow)
    lbody = layoutParagraph(body)
    fillParagraph(ctx, lbody, 32, 56)
    ## Footnote: a second, smaller paragraph.
    fFoot = Font(tfR, Float32(12), autoLineHeight,
        [Paint(rgba(100, 116, 139, 255))], NormalCase, false, false, false)
    fnote = newParagraph(
        "Text stays native outlines; nothing is rasterized at layout time.",
        fFoot, width = 296, hAlign = LeftAlign, overflow = ClipOverflow)
    fillParagraph(ctx, layoutParagraph(fnote), 32, 208)
    return img
end

card = paragraph_card_image()
@assert (width(card), height(card)) == (360, 250)
@assert getColor(card, 2, 2) == rgbx(241, 245, 249, 255)  # page background
@assert getColor(card, 20, 20) == rgbx(255, 255, 255, 255) # card interior
lcard = layoutParagraph(newParagraph("with wrapped lines, styled runs, " *
    "ordered font fallback,\ngrapheme clusters, and a clipped box.",
    Font(readTypeface(ROBOTO), Float32(15), autoLineHeight,
        [Paint(rgba(51, 65, 85, 255))], NormalCase, false, false, false),
    width = 296, lineHeight = 22))
@assert length(lcard.lines) >= 2                    # the body wraps
@assert lcard.lines[end].width <= Float32(296)      # and honors the box
## Ink-count helper: pixels on the white card that deviate from white
## (functions dodge this build's top-level soft scope).
function inkCount(img, x0, x1, y0, y1)
    n = 0
    for y in y0:y1
        for x in x0:x1
            c = getColor(img, x, y)
            if c.r < 250 || c.g < 250 || c.b < 250
                n += 1
            end
        end
    end
    return n
end
## Body ink lives inside the box [32, 328] x [56, 145] (4 lines x 22px);
## the band between the body's 110px box and the footnote is card white
## (the body is clipped to its box, so this is box-guaranteed).
@assert inkCount(card, 32, 328, 56, 145) > 200
@assert inkCount(card, 32, 328, 167, 207) == 0
## The 296px box clips horizontally: card white just outside it.
@assert inkCount(card, 14, 30, 56, 145) == 0
@assert inkCount(card, 330, 336, 56, 145) == 0
## The footnote drew below the band.
@assert inkCount(card, 32, 328, 208, 230) > 0
save_named(card, "paragraph-card.png")

card

#
# ## 13. JPEG thumbnail export (T031)
#
# JPEG is the photographic format: lossy, small, no alpha. `encodeJPEG`
# composites any transparent pixels over a `background` (default white) —
# nothing is dropped silently. On the pinned mandrill photo the JPEG
# thumbnail is ~14% of the PNG size; on a flat gradient scene it is
# *bigger* than the PNG — that is where JPEG is unsuitable (DCT ringing,
# no alpha, blocky edges).

function jpegSize(img, q)
    t0 = time_ns()
    b = encodeJPEG(img; quality = q)
    return length(b), (time_ns() - t0) / 1e6
end

## Photographic case: the pinned mandrill photo (upstream test data),
## reduced to a 256×256 thumbnail with the existing resize.
mandrill = readImage(joinpath(root, ".reference", "upstream",
    "examples", "data", "mandrill.png"))
@assert (width(mandrill), height(mandrill)) == (512, 512)
thumbImg = resize(mandrill, 256, 256)
@assert (width(thumbImg), height(thumbImg)) == (256, 256)
photoJpg, photoMs = jpegSize(thumbImg, 85)
photoPng = length(encodePNG(thumbImg))
println("mandrill thumbnail (256x256): PNG ", photoPng,
    " B vs JPEG q85 ", photoJpg, " B in ",
    round(photoMs, digits = 1), " ms")
@assert photoJpg < photoPng * 0.25 # photographic: JPEG wins big

## Flat-graphics case: a fresh plain gradient scene (no callout text) —
## smooth colors and hard edges are where JPEG loses to PNG.
function flatScene()
    img = newImage(320, 240)
    ctx = Context(img)
    sky = Paint(LinearGradientPaint)
    sky.gradientHandlePositions = [Vec2(0, 0), Vec2(0, 240)]
    sky.gradientStops = [
        colorStop(rgb(56, 189, 248), 0f0),
        colorStop(rgb(224, 242, 254), 1f0),
    ]
    ctx.fillStyle = sky
    fillRect(ctx, 0, 0, 320, 240)
    sun = newPath()
    circle(sun, 240, 70, 26)
    ctx.fillStyle = rgb(253, 224, 71)
    fill(ctx, sun)
    ctx.fillStyle = rgb(134, 239, 172)
    fillRect(ctx, 0, 190, 320, 50)
    return img
end
flat = flatScene()
flatJpg, _ = jpegSize(flat, 85)
flatPng = length(encodePNG(flat))
println("flat gradient scene (320x240): PNG ", flatPng,
    " B vs JPEG q85 ", flatJpg, " B")
@assert flatJpg >= flatPng # flat graphics: JPEG is unsuitable

thumb = joinpath(outdir, "annotation-jpeg.jpg")
writeFile(thumbImg, thumb)
@assert isfile(thumb) && filesize(thumb) > 500
back = readImage(thumb)
@assert (width(back), height(back)) == (256, 256)
@assert all(Int(getColor(back, x, y).a) == 255
    for x in 1:16 for y in 1:16) # opaque JPEG output

back

#
# That is the whole cookbook. The named PNGs above are what
# `docs/make_cookbook.jl` collects into `docs/build/gallery.html`, and the
# executed Markdown/notebook versions live next to them in
# `docs/build/cookbook/`.
