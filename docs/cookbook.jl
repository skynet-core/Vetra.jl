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
# That is the whole cookbook. The named PNGs above are what
# `docs/make_cookbook.jl` collects into `docs/build/gallery.html`, and the
# executed Markdown/notebook versions live next to them in
# `docs/build/cookbook/`.
