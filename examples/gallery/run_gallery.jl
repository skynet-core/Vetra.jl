# run_gallery.jl -- E001 batch runner for the feature gallery.
#
#   julia --project=. examples/gallery/run_gallery.jl [outdir]
#       runs all six programs in-process, in the current environment,
#       into outdir (default artifacts/gallery/) and prints the coverage
#       summary. Re-running is safe: outputs are regenerated, inputs
#       (fonts, fixtures) are never touched.
#
#   julia --project=. examples/gallery/run_gallery.jl [outdir] --core-only
#       additionally re-runs every program in a core-only subprocess
#       (scratch depot + JULIA_LOAD_PATH=@:@stdlib, the isolation pattern
#       pinned by test/codec_loading_tests.jl), proving each program's
#       core-only branch (named opt-in errors, no optional package ever
#       loaded) end to end.
#
# Import-safe: including this file defines run_all and main and runs
# nothing.
include(joinpath(@__DIR__, "gallery.jl"))
using Vetra
using .VetraGallery

const PROGRAMS = [
    "drawing_atlas", "plot_dashboard", "typography", "image_lab",
    "recording_reuse", "export_policies"]

"""Feature coverage table printed by the runner (the coverage matrix
also lives in examples/gallery/README.md)."""
const COVERAGE = [
    ("paths / fill rules / caps / joins / dashes / transforms", "drawing_atlas"),
    ("linear + radial gradients (raster, SVG, PDF)", "drawing_atlas"),
    ("clips, group opacity, isolated layers", "drawing_atlas"),
    ("recorded replay at 1x (byte-exact) and 2x (pinned semantics)", "drawing_atlas"),
    ("plot mapping with large-offset Float64 data", "plot_dashboard"),
    ("plot-area clipping, heatmap, bars, legends", "plot_dashboard"),
    ("glyph metrics / kerning from pinned advances", "typography"),
    ("styled wrapped paragraphs, ellipsis (U+2026)", "typography"),
    ("cross-font fallback + notdef policy", "typography"),
    ("opt-in HarfBuzz shaping, RTL bidi (pinned gids)", "typography"),
    ("premul/straight boundary, blend math", "image_lab"),
    ("crop / rotate / resize / flip / invert / spread / blur / opacity", "image_lab"),
    ("native exact codecs: QOI, BMP, PPM, GIF (pinned fixture)", "image_lab"),
    ("optional PNG / JPEG / WebP with quality bounds, ColorTypes", "image_lab"),
    ("T016 notebook PNG MIME display (showable/show)", "image_lab"),
    ("snapshot ownership (mutate sources, replay unchanged)", "recording_reuse"),
    ("re-rasterization at 2x with hand-derived geometry", "recording_reuse"),
    ("one-shot recorder contract, parameter changes", "recording_reuse"),
    ("strict export failures naming the op index", "export_policies"),
    ("sentinel destination preservation (no partial writes)", "export_policies"),
    ("PDF raster fallback: parsed XObject vs replay boundary", "export_policies"),
    ("SVG raster fallback: data-URI PNG vs replay (optional)", "export_policies"),
]

"""Run one program through its documented CLI in a subprocess (the
batch runner exercises the real commands, not in-process includes)."""
function run_program(name::String, outdir::String, env::Vector{Pair{String,String}} = Pair{String,String}[])
    root = VetraGallery.ROOT
    project = Base.active_project() === nothing ?
        root : Base.active_project()
    cmd = `$(Base.julia_cmd()) --startup-file=no --project=$(project) $(joinpath(root, "examples", "gallery", name * ".jl")) $(joinpath(outdir, name))`
    c = pipeline(addenv(cmd, env...); stdout = stdout, stderr = stderr)
    return success(c)
end

function run_all(outdir::String)
    VetraGallery.ensure_outdir(outdir)
    ok = true
    for name in PROGRAMS
        passed = run_program(name, outdir)
        println("  ", name, ": ", passed ? "pass" : "FAIL")
        passed || (ok = false)
    end
    ok || throw(ErrorException("a gallery program failed"))
    println()
    println("feature coverage (", join(PROGRAMS, ", "), ")")
    for (feature, program) in COVERAGE
        println("  [", program, "] ", feature)
    end
    return nothing
end

"""Core-only re-run of one program (codec_loading_tests.jl pattern):
--project is the repository root (its environment depends only on
Vetra's core), plus a scratch depot and a restricted load path, so the
optional providers are absent and each program's core-only branch must
hold."""
function core_only_run(name::String, outdir::String, depot::String)
    root = VetraGallery.ROOT
    loadpath = Sys.iswindows() ? "@;@stdlib" : "@:@stdlib"
    depots = join([depot, DEPOT_PATH...], Sys.iswindows() ? ';' : ':')
    cmd = `$(Base.julia_cmd()) --startup-file=no --project=$(root) $(joinpath(root, "examples", "gallery", name * ".jl")) $(joinpath(outdir, name * "_core"))`
    c = pipeline(addenv(cmd, "JULIA_DEPOT_PATH" => depots,
        "JULIA_LOAD_PATH" => loadpath); stdout = stdout, stderr = stderr)
    return success(c)
end

function main()
    # args are fully parsed before any output directory is resolved or
    # created (default_outdir is a pure path helper; run_all ensures).
    core = false
    outdirs = String[]
    for arg in ARGS
        if arg == "--core-only"
            core = true
        else
            push!(outdirs, arg)
        end
    end
    outdir = isempty(outdirs) ? default_outdir() : outdirs[1]
    println("gallery batch run -> ", outdir)
    run_all(outdir)
    if core
        println()
        println("core-only subprocess re-runs (optional providers absent):")
        mktempdir() do depot
            ok = true
            for name in PROGRAMS
                passed = core_only_run(name, outdir, depot)
                println("  ", name, ": ", passed ? "pass" : "FAIL")
                passed || (ok = false)
            end
            ok || throw(ErrorException("core-only re-run failed"))
        end
    end
    return nothing
end

if VetraGallery.is_entry(@__FILE__)
    main()
end
