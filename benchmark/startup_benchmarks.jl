# T020 startup benchmark: process startup, package load, first render, and
# warm render measured in separate fresh Julia processes.
#
#   julia --startup-file=no --project=docs benchmark/startup_benchmarks.jl [label]
#
# An optional label suffixes the output (e.g. "before" / "after") so before
# and after runs keep unique names:
#   benchmark/results/startup_<date>[_label].tsv
#
# Modes:
# - "cached" (3 runs): the usual depot; Vetra is precompiled, so load_ms is
#   cached package load only.
# - "cold" (1 run): a brand-new empty JULIA_DEPOT_PATH; the process must
#   fetch the registry (network), install, and precompile Vetra + its
#   environment before anything else, so total_wall includes all of it.
#
# The probe renders a small deterministic scene (fillRect + stroked circle)
# and asserts its pixels before timing any later stage, so a broken Vetra
# load fails loudly instead of measuring a no-op.
#
# Output: benchmark/results/startup_<date>.tsv (+ .tsv.meta) with one row
# per run: run, mode, total_wall_ms (parent-measured), load_ms,
# first_render_ms, warm_render_ms.

using Pkg
using Dates

const OUTDIR = joinpath("benchmark", "results")
const N_CACHED = 3
const LABEL = length(ARGS) >= 1 ? ARGS[1] : ""

const PROBE = raw"""
t0 = time_ns()
using Vetra
t1 = time_ns()
function render()
    img = newImage(256, 256)
    ctx = Context(img)
    ctx.fillStyle = "#2563EB"
    fillRect(ctx, 8, 8, 240, 240)
    p = newPath()
    circle(p, 128, 128, 60)
    ctx.strokeStyle = rgb(255, 255, 255)
    ctx.lineWidth = 4
    ctx.lineCap = RoundCap
    stroke(ctx, p)
    return img
end
img = render()
t2 = time_ns()
@assert width(img) == 256 "probe: wrong width"
@assert getColor(img, 129, 69) == rgbx(255, 255, 255, 255) "probe: circle missing"
@assert getColor(img, 10, 10) == rgbx(37, 99, 235, 255) "probe: fill missing"
render()
t3 = time_ns()
println("LOAD_MS=$(div(t1 - t0, 1_000_000))")
println("FIRST_RENDER_MS=$(div(t2 - t1, 1_000_000))")
println("WARM_RENDER_MS=$(div(t3 - t2, 1_000_000))")
"""

function run_probe(; depot = nothing, label)
    root = normpath(joinpath(@__DIR__, ".."))
    env = joinpath(root, "docs")
    probe = joinpath(tempdir(), "t020-probe-$label.jl")
    write(probe, PROBE)
    cmd = `$(Base.julia_cmd()) --startup-file=no --project=$env $probe`
    if depot !== nothing
        mkpath(depot)
        cmd = addenv(cmd, "JULIA_DEPOT_PATH" => depot)
    end
    buf = IOBuffer()
    t0 = time_ns()
    ok = success(pipeline(cmd; stdout = buf, stderr = stderr))
    total = (time_ns() - t0) / 1e6
    txt = String(take!(buf))
    print(txt)  # transcript stays visible next to the TSV
    ok || error("probe failed for run $(label): nonzero exit")
    load = parse(Int, match(r"LOAD_MS=(\d+)", txt).captures[1])
    first = parse(Int, match(r"FIRST_RENDER_MS=(\d+)", txt).captures[1])
    warm = parse(Int, match(r"WARM_RENDER_MS=(\d+)", txt).captures[1])
    return (total, load, first, warm)
end

rows = Tuple{Int64, String, Float64, Int64, Int64, Int64}[]
for k in 1:N_CACHED
    (total, load, first, warm) = run_probe(label = "cached$k")
    println("run $k (cached): total=$(round(total, digits = 1)) ms, " *
        "load=$(load) first=$(first) warm=$(warm)")
    push!(rows, (k, "cached", total, load, first, warm))
end
colddepot = joinpath(tempdir(), "t020-cold-$(round(time_ns() / 1e9))")
(total, load, first, warm) = run_probe(depot = colddepot, label = "cold")
println("run $(N_CACHED + 1) (cold depot): total=$(round(total, digits = 1)) ms, " *
    "load=$(load) first=$(first) warm=$(warm)")
push!(rows, (N_CACHED + 1, "cold", total, load, first, warm))

mkpath(OUTDIR)
base = joinpath(OUTDIR, "startup_$(Dates.format(Date(now()), "yyyy-mm-dd"))$(LABEL == "" ? "" : "_" * LABEL)")
open(base * ".tsv", "w") do io
    print(io, "run\tmode\ttotal_wall_ms\tload_ms\tfirst_render_ms\twarm_render_ms\n")
    for (k, mode, total, load, first, warm) in rows
        println(io, k, "\t", mode, "\t", round(total, digits = 1),
            "\t", load, "\t", first, "\t", warm)
    end
end
function cpu_model()
    try
        return Sys.cpu_info()[1].model
    catch e
        return "unknown"
    end
end
open(base * ".tsv.meta", "w") do io
    println(io, "julia_version=$(VERSION)")
    println(io, "date=$(Dates.format(now(), "yyyy-mm-dd HH:MM:SS"))")
    println(io, "os=$(Sys.KERNEL)")
    println(io, "cpu=$(cpu_model())")
    println(io, "cpu_cores=$(Sys.CPU_THREADS)")
    println(io, "n_cached_runs=$N_CACHED")
    println(io, "probe scene: 256x256 fillRect + stroked circle, pixel-asserted")
    println(io, "total_wall_ms = parent-measured subprocess wall time (includes the")
    println(io, "Julia interpreter startup; for the cold run also the registry fetch")
    println(io, "+ precompile). load_ms/first_render_ms/warm_render_ms are the")
    println(io, "probe's self-measured stages inside the subprocess.")
    println(io, "cold_depot=$(colddepot)")
end
println("wrote ", base, ".tsv (+ .tsv.meta)")
