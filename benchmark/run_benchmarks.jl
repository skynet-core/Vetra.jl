# T011 benchmark harness (Julia side).
#
# Workloads are defined identically in benchmark/bench_reference.nim (pinned
# upstream Nim) -- keep the two in lockstep if either changes.
#
#   julia --startup-file=no --project=/tmp/pngenv benchmark/run_benchmarks.jl
#
# (the example env carries the opt-in PNGFiles package; without it the
# png_* workloads raise the install hint)
#
# Per workload: first call (cold, its own first invocation), 3 warm-up
# iterations (discarded), 21 steady-state iterations (mean/min/median wall
# time) plus a separate allocation pass (bytes; this build's @allocated
# returns bytes only, so no allocation count — same as the Nim side,
# which reports "n/a"). The median is the comparison headline (the mean
# is noisy under GC/JIT). Results go to
# benchmark/results/julia_<date>.tsv plus a stdout summary.
#
# CI smoke (M002): VETRA_BENCH_SMOKE=1 runs the same workloads with
# reduced steady-state iterations (5, 1 warm-up), asserts workload
# outputs against independently derived expectations, and records
# platform/runtime metadata in the TSV (julia_<date>_smoke.tsv).
# Shared-runner timings are evidence, not a hard wall-clock gate.

using Vetra
using Dates

const SMOKE = get(ENV, "VETRA_BENCH_SMOKE", "0") == "1"
const N_STEADY = SMOKE ? 5 : 21
const N_WARMUP = SMOKE ? 1 : 3

const PLATFORM_OS = Sys.iswindows() ? "windows" : Sys.isapple() ? "macos" :
    Sys.isfreebsd() ? "freebsd" : Sys.islinux() ? "linux" : string(Sys.KERNEL)

results = Dict{String, Tuple}() # name -> (first_s, mean_s, min_s, median_s, bytes)

function bench!(name, f)
    t0 = time_ns()
    f() # first (cold) call
    first = (time_ns() - t0) / 1e9
    for _ in 1:N_WARMUP
        f()
    end
    samples_ns = Vector{Int64}(undef, N_STEADY)
    for k in 1:N_STEADY
        t0 = time_ns()
        f()
        samples_ns[k] = time_ns() - t0
    end
    total_bytes = 0
    for _ in 1:N_STEADY # separate pass: @allocated bookkeeping is not
        total_bytes += @allocated f() # timed
    end
    sorted = sort(copy(samples_ns))
    results[name] = (first, sum(samples_ns) / N_STEADY / 1e9,
        minimum(samples_ns) / 1e9, sorted[div(N_STEADY + 1, 2)] / 1e9,
        total_bytes)
    println(
        name,
        "\tfirst_call_ms=", round(first * 1000, digits = 3),
        "\tsteady_mean_ms=", round(sum(samples_ns) / N_STEADY / 1e6, digits = 3),
        "\tsteady_min_ms=", round(minimum(samples_ns) / 1e6, digits = 3),
        "\tsteady_median_ms=", round(sorted[div(N_STEADY + 1, 2)] / 1e6,
            digits = 3),
        "\talloc_bytes=", total_bytes)
    return nothing
end

# --- workload builders (match bench_reference.nim exactly) ---

const W = 256

function freshCanvas()
    img = newImage(W, W)
    fill(img, rgb(0, 0, 0))
    ctx = Context(img)
    ctx.fillStyle = Paint(rgba(255, 0, 0, 255))
    return ctx
end

# Each workload returns the image/bytes/metrics it already produces, so
# the smoke check below (M002) verifies the actual workload outputs
# instead of re-drawn stand-ins. `bench!` discards the return value.

function fillRectsWork()
    ctx = freshCanvas()
    for i in 0:999
        fillRect(ctx, Float32(mod(37 * i, 246)), Float32(mod(71 * i, 246)),
            10f0, 10f0)
    end
    return ctx.image
end

function strokeLinesWork()
    ctx = freshCanvas()
    ctx.strokeStyle = Paint(rgba(255, 255, 0, 255))
    ctx.lineWidth = Float32(2)
    for i in 0:999
        strokeSegment(ctx, Float32(mod(7 * i, 249)), 0f0,
            Float32(mod(13 * i, 249)), 255f0)
    end
    return ctx.image
end

function blurWork()
    img = newImage(128, 128)
    fill(img, rgb(255, 255, 255))
    blur(img, Float32(3))
    return img
end

function shadowWork()
    img = newImage(128, 128)
    fill(img, rgb(255, 0, 0))
    return shadow(img, Vec2(4f0, 4f0), 2f0, 4f0, rgba(0, 0, 0, 128))
end

function drawWork()
    dst = newImage(W, W)
    fill(dst, rgb(255, 255, 255))
    src = newImage(128, 128)
    fill(src, rgb(255, 0, 0))
    for i in 0:9
        draw(dst, src, translate(Vec2(Float32(mod(13 * i, 128)),
            Float32(mod(29 * i, 128)))))
    end
    return dst
end

function gradientImage()
    img = newImage(W, W)
    d = img.data
    for y in 0:(W - 1)
        for x in 0:(W - 1)
            o = 4 * (y * W + x) + 1
            d[o] = UInt8(mod(x + y, 256))
            d[o + 1] = UInt8(0)
            d[o + 2] = UInt8(mod(x - y + 256, 256))
            d[o + 3] = UInt8(255)
        end
    end
    return img
end

function pngEncodeWork()
    img = gradientImage()
    bytes = encodeImage(img, PngFormat)
    for _ in 2:10
        bytes = encodeImage(img, PngFormat)
    end
    return (img, bytes)
end

function pngDecodeWork()
    data = read("test/reference/font_basic1.png")
    img = decodeImage(data)
    for _ in 2:10
        img = decodeImage(data)
    end
    return img
end

const TEXT = "The quick brown fox jumps over the lazy dog 0123456789"

function textWork()
    tfpath = joinpath(".reference", "upstream", "tests", "fonts",
        "Roboto-Regular_1.ttf")
    font = newFont(readTypeface(tfpath))
    font.size = Float32(24)
    ctx = Context(16, 16)
    ctx.font = tfpath
    ctx.fontSize = Float32(24)
    bds = layoutBounds(font, TEXT)
    for _ in 2:100
        bds = layoutBounds(font, TEXT)
    end
    m = measureText(ctx, TEXT)
    for _ in 2:20
        m = measureText(ctx, TEXT)
    end
    return (bds, m)
end

# --- smoke correctness (M002): each check calls the actual workload
#     above (outside the timing) and asserts independently justified
#     invariants — premultiplied color algebra, the i=0 workload
#     geometry, kernel mathematics, and the pinned oracle fixture —
#     never values observed from the code under test. ---

function smoke_check(cond, what)
    cond || throw(ErrorException("benchmark smoke failed: $what"))
    return nothing
end

function smoke_verify()
    # fill_rects: the i=0 fill covers (0,0)-(9,9); opaque red over an
    # opaque black canvas stays on the black→red premultiplied line
    # (g = b = 0, r <= a) for every pixel.
    img = fillRectsWork()
    smoke_check(img.width == W && img.height == W, "fill: canvas size")
    d = img.data
    for k in 1:4:length(d)
        smoke_check(d[k + 1] == 0 && d[k + 2] == 0 && d[k] <= d[k + 3],
            "fill: a pixel left the black/red premultiplied line")
    end
    smoke_check(getColor(img, 5, 5) == ColorRGBX(255, 0, 0, 255),
        "fill: the i=0 fill covers (5,5) with opaque red")

    # stroke_lines: the i=0 segment is the full-height vertical line
    # at x=0; yellow over black stays on the r == g, b == 0
    # premultiplied line.
    s = strokeLinesWork()
    smoke_check(s.width == W && s.height == W, "stroke: canvas size")
    d = s.data
    for k in 1:4:length(d)
        smoke_check(d[k] == d[k + 1] && d[k + 2] == 0 && d[k] <= d[k + 3],
            "stroke: a pixel left the black/yellow premultiplied line")
    end
    smoke_check(getColor(s, 1, 128).r > 0,
        "stroke: the i=0 line reaches the first column")

    # blur: white stays gray (r == g == b); the interior is attenuated
    # only by float32 rounding of the (sum-1) kernel weights, while the
    # corner bleeds toward the transparent border.
    b = blurWork()
    d = b.data
    for k in 1:4:length(d)
        smoke_check(d[k] == d[k + 1] == d[k + 2] && d[k] <= d[k + 3],
            "blur: a pixel left the gray premultiplied line")
    end
    center = getColor(b, 64, 64)
    smoke_check(center.r in 245:255, "blur: the interior stays near-white")
    smoke_check(getColor(b, 1, 1).r < center.r,
        "blur: the corner is darker than the interior")

    # shadow: per the pinned blendMask contract (upstream blends.nim
    # L227), the result is the rgba(0,0,0,128) canvas scaled by the
    # shifted/spread/blurred content alpha — pure black, alpha <= 128,
    # ~128 deep inside the content, near 0 at the corner outside it.
    sh = shadowWork()
    smoke_check(sh.width == 128 && sh.height == 128, "shadow: canvas size")
    d = sh.data
    for k in 1:4:length(d)
        smoke_check(d[k] == 0 && d[k + 1] == 0 && d[k + 2] == 0 &&
            d[k + 3] <= 128,
            "shadow: a pixel is not black with alpha <= 128")
    end
    smoke_check(getColor(sh, 64, 64).a in 125:128,
        "shadow: the deep interior keeps the full canvas alpha")
    smoke_check(getColor(sh, 1, 1).a <= 124,
        "shadow: the corner outside the content is near-transparent")

    # draw: the i=0 draw places the 128×128 red block at the origin over
    # opaque white; integer offsets keep every pixel exactly opaque
    # white or exactly opaque red.
    dr = drawWork()
    d = dr.data
    for k in 1:4:length(d)
        exact = d[k + 3] == 255 && ((d[k] == 255 && d[k + 1] == 255 &&
                d[k + 2] == 255) || (d[k] == 255 && d[k + 1] == 0 &&
                d[k + 2] == 0))
        smoke_check(exact, "draw: a pixel is not opaque white or red")
    end
    smoke_check(getColor(dr, 10, 10) == ColorRGBX(255, 0, 0, 255),
        "draw: the i=0 block covers (10,10)")

    # png_encode: a lossless codec round trip reproduces the
    # workload's own canvas byte-for-byte.
    (gimg, bytes) = pngEncodeWork()
    back = decodeImage(bytes)
    smoke_check(back.width == gimg.width && back.height == gimg.height,
        "png encode: the round trip keeps dimensions")
    smoke_check(back.data == gimg.data, "png encode: the round trip keeps pixels")

    # png_decode: the pinned fixture must equal the pinned oracle bytes
    # (font_basic1.raw: 200×100, row-major premultiplied RGBA, per the
    # .meta contract).
    p = pngDecodeWork()
    smoke_check(p.width == 200 && p.height == 100, "png decode: fixture size")
    smoke_check(p.data == read("test/reference/font_basic1.raw"),
        "png decode: fixture pixels match the pinned oracle")

    # text: layout width is positive, finite, and monotone in the text
    # (all Roboto advances of the remaining 38 characters are > 0).
    (bds, m) = textWork()
    smoke_check(isfinite(bds.x) && bds.x > 0, "text: layout width > 0")
    smoke_check(m.width > 0 && isfinite(m.width),
        "text: measureText width > 0")
    tfpath = joinpath(".reference", "upstream", "tests", "fonts",
        "Roboto-Regular_1.ttf")
    font = newFont(readTypeface(tfpath))
    font.size = Float32(24)
    smoke_check(bds.x > layoutBounds(font, "The quick").x,
        "text: the width is monotone in the text")
    return nothing
end

# --- run ---

println("vetra.jl benchmarks (julia $(VERSION))")
println("platform: os=$PLATFORM_OS arch=$(Sys.ARCH) " *
    "smoke=$(SMOKE ? 1 : 0) n_steady=$N_STEADY n_warmup=$N_WARMUP")
println("workloads: W=256 canvas, 1000 fills/strokes, blur r3 @128, " *
    "shadow(4,4,s2,b4) @128, 10 draws @128src, png 10x, text x100+20")
SMOKE && smoke_verify()

bench!("fill_rects_1000", fillRectsWork)
bench!("stroke_lines_1000", strokeLinesWork)
bench!("blur_128_r3", blurWork)
bench!("shadow_128", shadowWork)
bench!("draw_10", drawWork)
bench!("png_encode_256_x10", pngEncodeWork)
bench!("png_decode_basic1_x10", pngDecodeWork)
bench!("text_parse_layout_x100_measure_x20", textWork)

# --- write TSV ---

outfile = joinpath("benchmark", "results",
    "julia_" * string(Date(now())) * (SMOKE ? "_smoke" : "") * ".tsv")
isdir(joinpath("benchmark", "results")) ||
    mkdir(joinpath("benchmark", "results"))
open(outfile, "w") do io
    SMOKE &&
        print(io, "# julia=$(VERSION) os=$PLATFORM_OS arch=$(Sys.ARCH) " *
            "n_steady=$N_STEADY n_warmup=$N_WARMUP date=$(string(Date(now())))\n")
    print(io, "workload\tfirst_call_ms\tsteady_mean_ms\tsteady_min_ms\t" *
        "steady_median_ms\talloc_bytes_total\n")
    for (name, (f, m, mn, med, b)) in sort(collect(pairs(results)))
        println(io, name, "\t", round(f * 1000, digits = 3),
            "\t", round(m * 1000, digits = 3),
            "\t", round(mn * 1000, digits = 3),
            "\t", round(med * 1000, digits = 3), "\t", b)
    end
end
println("wrote ", outfile)
