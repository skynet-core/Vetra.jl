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

function fillRectsWork()
    ctx = freshCanvas()
    for i in 0:999
        fillRect(ctx, Float32(mod(37 * i, 246)), Float32(mod(71 * i, 246)),
            10f0, 10f0)
    end
    return nothing
end

function strokeLinesWork()
    ctx = freshCanvas()
    ctx.strokeStyle = Paint(rgba(255, 255, 0, 255))
    ctx.lineWidth = Float32(2)
    for i in 0:999
        strokeSegment(ctx, Float32(mod(7 * i, 249)), 0f0,
            Float32(mod(13 * i, 249)), 255f0)
    end
    return nothing
end

function blurWork()
    img = newImage(128, 128)
    fill(img, rgb(255, 255, 255))
    blur(img, Float32(3))
    return nothing
end

function shadowWork()
    img = newImage(128, 128)
    fill(img, rgb(255, 0, 0))
    shadow(img, Vec2(4f0, 4f0), 2f0, 4f0, rgba(0, 0, 0, 128))
    return nothing
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
    return nothing
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
    for _ in 1:10
        encodeImage(img, PngFormat)
    end
    return nothing
end

function pngDecodeWork()
    data = read("test/reference/font_basic1.png")
    for _ in 1:10
        decodeImage(data)
    end
    return nothing
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
    for _ in 1:100
        layoutBounds(font, TEXT)
    end
    for _ in 1:20
        measureText(ctx, TEXT)
    end
    return nothing
end

# --- smoke correctness (M002; expectations are hand-derived, not
#     produced by the code under test) ---

function smoke_check(cond, what)
    cond || throw(ErrorException("benchmark smoke failed: $what"))
    return nothing
end

function smoke_verify()
    # fill: the i=0 workload fill covers (0,0)-(9,9); red over black.
    img = newImage(W, W)
    fill(img, rgb(0, 0, 0))
    ctx = Context(img)
    ctx.fillStyle = Paint(rgba(255, 0, 0, 255))
    fillRect(ctx, 0f0, 0f0, 10f0, 10f0)
    smoke_check(getColor(img, 5, 5) == ColorRGBX(255, 0, 0, 255),
        "filled pixel (5,5) must be opaque red")
    smoke_check(getColor(img, 200, 200) == ColorRGBX(0, 0, 0, 255),
        "unfilled pixel (200,200) must stay opaque black")

    # blur: uniform white stays near-white at the center (the Float32
    # kernel weights sum within a few levels of 1 — observed 253
    # premultiplied — while edges darken toward the transparent
    # border).
    b = newImage(128, 128)
    fill(b, rgb(255, 255, 255))
    blur(b, Float32(3))
    cb = getColor(b, 64, 64)
    smoke_check(cb.r in 250:255 && cb.g in 250:255 && cb.b in 250:255,
        "blur of uniform white keeps the center near-white")

    # shadow: the content pixel stays red (halo lands below-right).
    s = newImage(128, 128)
    fill(s, rgb(255, 0, 0))
    shadow(s, Vec2(4f0, 4f0), 2f0, 4f0, rgba(0, 0, 0, 128))
    smoke_check(getColor(s, 64, 64) == ColorRGBX(255, 0, 0, 255),
        "shadow keeps the content pixel red")

    # draw: the red source lands at the origin over the white target.
    dst = newImage(W, W)
    fill(dst, rgb(255, 255, 255))
    src = newImage(128, 128)
    fill(src, rgb(255, 0, 0))
    draw(dst, src, translate(Vec2(0f0, 0f0)))
    smoke_check(getColor(dst, 10, 10) == ColorRGBX(255, 0, 0, 255),
        "drawn pixel (10,10) must be opaque red")

    # png round trip: encode -> decode reproduces the stored pixels.
    back = decodeImage(encodeImage(img, PngFormat))
    smoke_check(back.width == W && back.height == W,
        "png round trip keeps dimensions")
    smoke_check(back.data == img.data, "png round trip keeps pixels")

    # text: layout width of a known string is finite and positive.
    tfpath = joinpath(".reference", "upstream", "tests", "fonts",
        "Roboto-Regular_1.ttf")
    font = newFont(readTypeface(tfpath))
    font.size = Float32(24)
    bds = layoutBounds(font, TEXT)
    smoke_check(isfinite(bds.x) && bds.x > 0, "text layout width > 0")
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
