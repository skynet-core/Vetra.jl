# T020 application benchmark suite (separate from the T011 comparison harness).
#
# Representative-application workloads at 256px / 1080p / 4K, plus complex
# paths, text-heavy cards, clipping/layers, repeated render+encode, and the
# PNG pipeline split into draw / boundary conversion / encode stages.
#
#   julia --startup-file=no --project=<env-with-Vetra-and-PNGFiles> \
#       benchmark/app_benchmarks.jl [run_index]
#
# Run at least three times in sequence (run_index 1, 2, 3) so each output
# file name is unique:
#   benchmark/results/app_<date>_r<index>.tsv (+ .meta sidecar)
#
# Method notes (recorded in tasks/T020-application-benchmarks.md):
# - Every workload first renders a deterministic result and checks simple
#   independent invariants (dimensions, pixel counts, corner values) BEFORE
#   any timing, so a no-op or broken workload fails loudly.
# - Per workload: 3 warm-ups (discarded), then 7 steady-state samples
#   (mean/min/median, ns timer) plus a separate allocation pass reporting
#   bytes PER IMAGE (single-item @allocated), never unlabeled totals.
# - PNG encode is reported per image class: flat / gradient / noise,
#   opaque / translucent. The boundary conversion (premultiplied ->
#   straight alpha) is timed separately as a full-buffer toStraightAlpha
#   pass; encode(opaque) therefore isolates the codec stage, and
#   encode(translucent) - encode(opaque) shows the boundary+entropy cost.
# - Text uses the pinned Roboto fixture (scripts/fetch_upstream.jl).
# - Machine/version/parameter details go to the .meta sidecar.

using Vetra
using Dates

const N_WARMUP = 3
const N_SAMPLE = 7
const OUTDIR = joinpath("benchmark", "results")
const RUN = length(ARGS) >= 1 ? parse(Int, ARGS[1]) : 1

fontdir = joinpath(".reference", "upstream", "tests", "fonts")
ROBOTO = joinpath(fontdir, "Roboto-Regular_1.ttf")
isfile(ROBOTO) ||
    error("Run `julia --project=. scripts/fetch_upstream.jl` from the repository root first")

rows = Tuple{String, String, Int64, Float64, Float64, Float64, Int64, Int64}[]
# (workload, stage, n, mean_ms, min_ms, median_ms, alloc_bytes_per_item, file_bytes)

"""Sample `f` after warm-up; report per-item allocation and (optionally) a
file-size probe for the item produced on the final sample."""
function bench!(workload::String, stage::String, f; file = 0)
    for _ in 1:N_WARMUP
        f()
    end
    samples = Vector{Float64}(undef, N_SAMPLE)
    for k in 1:N_SAMPLE
        t0 = time_ns()
        f()
        samples[k] = (time_ns() - t0) / 1e6
    end
    alloc = @allocated f()
    push!(rows, (workload, stage, N_SAMPLE,
        sum(samples) / N_SAMPLE, minimum(samples),
        sort(samples)[div(N_SAMPLE + 1, 2)], alloc, file))
    println(rpad(workload * "/" * stage, 42),
        " n=$N_SAMPLE  mean=$(round(sum(samples) / N_SAMPLE, digits = 3)) ms  " *
        "min=$(round(minimum(samples), digits = 3))  " *
        "median=$(round(sort(samples)[div(N_SAMPLE + 1, 2)], digits = 3))  " *
        "alloc=$(alloc) B")
    return nothing
end

# ---------- scene builders (deterministic; plain numbers per T014) ----------

"""Representative card scene: gradient background, white panel, shapes, one
stroked curve, and labels. Geometry scales with the canvas; stroke widths
and font sizes stay fixed (as in a real application)."""
function card_scene(w, h)
    img = newImage(w, h)
    ctx = Context(img)
    bg = Paint(LinearGradientPaint)
    bg.gradientHandlePositions = [Vec2(0, 0), Vec2(w, h)]
    bg.gradientStops = [
        colorStop(rgb(225, 239, 255), 0f0),
        colorStop(rgb(233, 249, 240), 1f0),
    ]
    ctx.fillStyle = bg
    fillRect(ctx, 0, 0, w, h)
    s = w / 640
    ctx.fillStyle = rgb(255, 255, 255)
    panel = newPath()
    roundedRect(panel, 24s, 24s, 592s, 352s, 16s, 16s, 16s, 16s)
    fill(ctx, panel)
    ctx.fillStyle = "#2563EB"
    dot = newPath()
    circle(dot, 560s, 60s, 14s)
    fill(ctx, dot)
    trend = newPath()
    values = [20, 45, 35, 70, 55, 85, 75]
    first = true
    for (i, v) in enumerate(values)
        p = Vec2(64s + (i - 1) * 84s, 304s - 1.6 * v)
        first ? moveTo(trend, p) : lineTo(trend, p)
        first = false
    end
    ctx.strokeStyle = "#2563EB"
    ctx.lineWidth = 4
    ctx.lineCap = RoundCap
    ctx.lineJoin = RoundJoin
    stroke(ctx, trend)
    ctx.font = ROBOTO
    ctx.fillStyle = "#172033"
    ctx.fontSize = 28
    fillText(ctx, "Weekly activity", 48s, 76s)
    ctx.fontSize = 16
    ctx.fillStyle = "#526078"
    fillText(ctx, "Seven samples, drawn in Julia", 48s, 104s)
    fillText(ctx, "Mon", 48s, 352s)
    fillText(ctx, "Sun", 592s - measureText(ctx, "Sun").width, 352s)
    return img
end

"""Complex curved/stroked scene at 1280x720: 200 quadratic strokes, 100 arc
strokes, and 50 filled bezier shapes, deterministic placement."""
function complex_paths_scene()
    w, h = 1280, 720
    img = newImage(w, h)
    fill(img, rgb(250, 250, 252))
    ctx = Context(img)
    for i in 0:199
        p = newPath()
        x0 = 20 + mod(37i, w - 40)
        y0 = 20 + mod(71i, h - 40)
        moveTo(p, x0, y0)
        quadraticCurveTo(p, x0 + 60, y0 + 40, x0 + 120, y0 + mod(11i, 80))
        ctx.strokeStyle = rgba(37, 99, 235, 200)
        ctx.lineWidth = 1 + mod(i, 3)
        ctx.lineCap = RoundCap
        stroke(ctx, p)
    end
    for i in 0:99
        p = newPath()
        arc(p, 60 + mod(53i, w - 120), 60 + mod(97i, h - 120),
            12 + mod(i, 40), pi / 4, 3pi / 2)
        ctx.strokeStyle = rgba(22, 163, 74, 160)
        ctx.lineWidth = 2
        stroke(ctx, p)
    end
    for i in 0:49
        p = newPath()
        x = 40 + mod(149i, w - 160)
        y = 40 + mod(197i, h - 160)
        moveTo(p, x, y)
        bezierCurveTo(p, x + 30, y - 50, x + 80, y - 50, x + 110, y)
        bezierCurveTo(p, x + 80, y + 50, x + 30, y + 50, x, y)
        ctx.fillStyle = rgba(244, 63, 94, 120)
        fill(ctx, p)
    end
    return img
end

"""Text-heavy card at 1280x720: 24 lines of labels plus 100 measureText."""
function text_card_scene()
    w, h = 1280, 720
    img = newImage(w, h)
    fill(img, rgb(255, 255, 255))
    ctx = Context(img)
    ctx.font = ROBOTO
    ctx.fillStyle = rgb(32, 33, 36)
    words = ["alpha", "bravo", "charlie", "delta", "echo", "foxtrot",
        "golf", "hotel", "india", "juliet"]
    for i in 1:24
        ctx.fontSize = 18 + mod(i, 3) * 4
        ctx.fillStyle = i % 2 == 0 ? rgb(71, 85, 105) : rgb(32, 33, 36)
        fillText(ctx, "row $(i): " * words[mod(i - 1, 10) + 1] * " " *
            words[mod(i, 10) + 1] * " " * words[mod(i + 3, 10) + 1],
            48, 48 + (i - 1) * 26)
        measureText(ctx, words[mod(i, 10) + 1])
    end
    return img
end

"""Clipping + layers at 1280x720: 12 nested saveLayer groups, each with a
circular clip, gradient fill, and MultiplyBlend overlay."""
function clip_layers_scene()
    w, h = 1280, 720
    img = newImage(w, h)
    fill(img, rgb(255, 255, 255))
    ctx = Context(img)
    for i in 0:11
        saveLayer(ctx)
        cx, cy = 160 + 90 * (i % 4), 160 + 140 * div(i, 4)
        window = newPath()
        circle(window, cx, cy, 90)
        clip(ctx, window)
        grad = Paint(LinearGradientPaint)
        grad.gradientHandlePositions = [Vec2(cx - 90, cy - 90), Vec2(cx + 90, cy + 90)]
        grad.gradientStops = [
            colorStop(rgb(0, 255, 255), 0f0),
            colorStop(rgb(255, 255, 0), 1f0),
        ]
        ctx.fillStyle = grad
        fillRect(ctx, cx - 90, cy - 90, 180, 180)
        ctx.fillStyle = Paint(rgba(255, 0, 255, 255); blendMode = MultiplyBlend)
        half = newPath()
        circle(half, cx + 30, cy + 30, 90)
        fill(ctx, half)
        restore(ctx)
    end
    return img
end

# ---------- PNG image classes (flat / gradient / noise, opaque / translucent) ----------

function make_class(kind::String, w, h; alpha = 255)
    img = newImage(w, h)
    d = img.data
    for y in 0:(h - 1)
        for x in 0:(w - 1)
            o = 4 * (y * w + x) + 1
            if kind == "flat"
                d[o] = d[o + 1] = d[o + 2] = UInt8(96)
            elseif kind == "gradient"
                d[o] = UInt8(mod(x + y, 256))
                d[o + 1] = UInt8(0)
                d[o + 2] = UInt8(mod(x - y + 256, 256))
            else  # deterministic LCG noise (no RNG state, no package)
                t = 1103515245 * (x + 1) + 12345 + y * 7919
                d[o] = UInt8(t % 256)
                d[o + 1] = UInt8(div(t, 256) % 256)
                d[o + 2] = UInt8(div(t, 65536) % 256)
            end
            d[o + 3] = UInt8(alpha)
        end
    end
    return img
end

"""The encoder's per-pixel boundary pass (premultiplied -> straight), timed
standalone so it is not attributed to the codec stage."""
function boundary_pass(img)
    d = img.data
    out = Vector{UInt8}(undef, length(d))
    n = div(length(d), 4)
    @inbounds for i in 1:n
        o = 4 * (i - 1) + 1
        c = toStraightAlpha(ColorRGBX(d[o], d[o + 1], d[o + 2], d[o + 3]))
        out[o] = c.r
        out[o + 1] = c.g
        out[o + 2] = c.b
        out[o + 3] = c.a
    end
    return out
end

# ---------- invariants (checked before any timing) ----------

function check!(img, w, h; note = "")
    @assert (width(img), height(img)) == (w, h) "dims for $note"
    nz = count(!iszero, img.data[4:4:end])  # nonzero alpha bytes
    @assert nz > 0 "nonempty $note"
    return nothing
end

println("vetra.jl application benchmarks (julia $(VERSION), run $(RUN))")

# 1. Canvas scenes at three sizes (draw stage).
for (w, h, tag) in ((256, 256, "canvas_256"), (1920, 1080, "canvas_1080p"),
    (3840, 2160, "canvas_4k"))
    probe = card_scene(w, h)
    check!(probe, w, h; note = tag)
    @assert getColor(probe, 3, 3) != rgbx(255, 255, 255, 255) "$tag corner not covered"
    bench!(tag, "draw", () -> card_scene(w, h))
end

# 2. Complex curved/stroked paths (draw stage).
probe = complex_paths_scene()
check!(probe, 1280, 720; note = "paths_complex")
@assert count(v -> v > 150, probe.data[1:3:end]) > 0 "paths_complex: no red-channel ink"
bench!("paths_complex", "draw", complex_paths_scene)

# 3. Text-heavy card (draw stage; includes fillText + measureText).
probe = text_card_scene()
check!(probe, 1280, 720; note = "text_card")
@assert count(v -> v < 100, probe.data[1:3:end]) > 0 "text_card: no dark text pixels"
bench!("text_card", "draw", text_card_scene)

# 4. Clipping + layers (draw stage).
probe = clip_layers_scene()
check!(probe, 1280, 720; note = "clip_layers")
# cyan x magenta multiply -> pure blue: check r-byte low, b-byte high
rbytes = probe.data[1:4:end]
bbytes = probe.data[3:4:end]
@assert count(p -> p[2] > 200 && p[1] < 60, zip(rbytes, bbytes)) > 0 "clip_layers: no multiply-blend blue"
bench!("clip_layers", "draw", clip_layers_scene)

# 5. PNG pipeline by image class at 1080p: boundary conversion, encode,
#    file size. Opaque isolates the codec; translucent adds the boundary
#    pass + entropy.
for (kind, alpha, tag) in (("flat", 255, "png_flat_opaque"),
    ("flat", 128, "png_flat_alpha"),
    ("gradient", 255, "png_gradient_opaque"),
    ("gradient", 128, "png_gradient_alpha"),
    ("noise", 255, "png_noise_opaque"),
    ("noise", 128, "png_noise_alpha"))
    img = make_class(kind, 1920, 1080; alpha = alpha)
    check!(img, 1920, 1080; note = tag)
    if kind == "flat"
        uniform = all(i -> img.data[i] == img.data[mod(i - 1, 4) + 1],
            1:4:length(img.data))
        @assert uniform "$tag flat image not uniform"
    end
    if kind == "gradient"
        @assert img.data[1] != img.data[4 * (1920 * 1080 - 1) + 1] "$tag gradient corners equal"
    end
    if kind == "noise"
        vals = img.data[1:4:4 * 1000]
        @assert maximum(vals) - minimum(vals) > 20 "$tag noise has no variation"
    end
    bench!(tag, "draw_fill", () -> make_class(kind, 1920, 1080; alpha = alpha))
    if alpha < 255
        bench!(tag, "boundary_toStraightAlpha", () -> boundary_pass(img))
    end
    bytes = encodeImage(img, PngFormat)
    file = length(bytes)
    bench!(tag, "encode_png", () -> encodeImage(img, PngFormat); file = file)
end

# 6. 4K encode only (file-size / codec headline at the largest canvas).
img4k = make_class("gradient", 3840, 2160; alpha = 255)
check!(img4k, 3840, 2160; note = "png_4k")
bytes4k = encodeImage(img4k, PngFormat)
bench!("png_4k", "encode_png", () -> encodeImage(img4k, PngFormat); file = length(bytes4k))

# 7. Repeated render+encode at 1080p, stages reported separately.
function render_then_encode()
    img = card_scene(1920, 1080)
    return encodeImage(img, PngFormat)
end
probeimg = card_scene(1920, 1080)
check!(probeimg, 1920, 1080; note = "repeat")
bench!("repeat_1080p", "draw", () -> card_scene(1920, 1080))
rebytes = encodeImage(probeimg, PngFormat)
bench!("repeat_1080p", "encode_png", () -> encodeImage(probeimg, PngFormat);
    file = length(rebytes))
bench!("repeat_1080p", "draw_plus_encode", render_then_encode)

# ---------- output ----------

mkpath(OUTDIR)
base = joinpath(OUTDIR, "app_$(Dates.format(Date(now()), "yyyy-mm-dd"))_r$(RUN)")

# Representative outputs for visual inspection (gitignored, like the TSVs).
writeFile(card_scene(1920, 1080), base * "_canvas_1080p.png")
writeFile(complex_paths_scene(), base * "_paths_complex.png")
writeFile(text_card_scene(), base * "_text_card.png")
writeFile(clip_layers_scene(), base * "_clip_layers.png")
writeFile(make_class("noise", 1920, 1080; alpha = 128), base * "_noise_alpha.png")

open(base * ".tsv", "w") do io
    print(io, "workload\tstage\tn\tmean_ms\tmin_ms\tmedian_ms\t" *
        "alloc_bytes_per_item\tfile_bytes\n")
    for (wl, st, n, m, mn, med, a, f) in rows
        println(io, wl, "\t", st, "\t", n, "\t", round(m, digits = 3),
            "\t", round(mn, digits = 3), "\t", round(med, digits = 3),
            "\t", a, "\t", (f > 0 ? f : "-"))
    end
end

function cpu_model()
    try
        return Sys.cpu_info()[1].model
    catch e
        return "unknown"
    end
end

function os_release()
    try
        return strip(read("/proc/sys/kernel/osrelease", String))
    catch e
        return "unknown"
    end
end

open(base * ".tsv.meta", "w") do io
    println(io, "julia_version=$(VERSION)")
    println(io, "date=$(Dates.format(now(), "yyyy-mm-dd HH:MM:SS"))")
    println(io, "os=$(Sys.KERNEL) $(os_release())")
    println(io, "cpu=$(cpu_model())")
    println(io, "cpu_cores=$(Sys.CPU_THREADS)")
    println(io, "word_size=$(Sys.WORD_SIZE)")
    println(io, "n_warmup=$N_WARMUP n_sample=$N_SAMPLE")
    println(io, "representative PNGs: $(base)_canvas_1080p.png, _paths_complex.png,")
    println(io, "  _text_card.png, _clip_layers.png, _noise_alpha.png")
    println(io, "scenes: canvas 256x256/1920x1080/3840x2160; paths 1280x720 " *
        "(200 quadratic + 100 arc strokes, 50 filled beziers); text 1280x720 " *
        "(24 lines, 100 measureText); clip/layers 1280x720 (12 layers, circular " *
        "clip, gradient + MultiplyBlend); png classes 1920x1080 flat/gradient/noise " *
        "alpha 255/128; 4k encode 3840x2160; repeat 1920x1080")
    println(io, "run_index=$RUN")
end
println("wrote ", base, ".tsv (+ .tsv.meta)")
