# export_policies.jl -- E001 gallery program 6: the strict export
# policies of write_svg!/write_pdf!. Scenes with unsupported ops must
# fail fast with an error that names the op index, before any file is
# written: pre-existing destinations are preserved (sentinel check) and
# fresh destinations are never created. The raster-fallback policy then
# exports the same scene with an embedded raster, and the embedded bytes
# are checked independently: the PDF XObject is parsed out of the
# uncompressed document and compared to the CPU replay through the
# documented premul -> straight boundary (min(round(c*255/a), 255),
# hand-evaluated in integer arithmetic for sample pixels), and the SVG
# data-URI PNG decodes back to the replay.
#
#   julia --project=. examples/gallery/export_policies.jl [outdir]
#
# Outputs in outdir (caller-selected; default artifacts/gallery/):
#   export_policies.svg      strict export of the supported scene
#   export_policies.pdf      strict export of the supported scene
#   export_policies_fb.pdf   PDF raster fallback (core-only path)
#   export_policies_fb.svg   SVG raster fallback (optional PNG support)
#   export_policies_evenodd.svg  evenodd gradient: SVG-only positive case
#
# Backends are not interchangeable: the evenodd gradient scene exports
# to SVG but must fail strict PDF ("sh has no fill rule") -- the
# difference is asserted, not papered over. Import-safe: including this
# file defines helpers and run/main and renders nothing.
include(joinpath(@__DIR__, "gallery.jl"))
using Vetra
using .VetraGallery

const W, H = 64, 48
const BG = rgbx(230, 232, 236, 255)
const SQUARE = rgbx(30, 64, 175, 255)

"""The supported scene (solids, one linear gradient, one stroke)."""
function ok_scene(ctx)
    ctx.fillStyle = rgb(230, 232, 236)
    fill_rect!(ctx, 0, 0, W, H)
    ctx.fillStyle = rgb(30, 64, 175)
    fill_rect!(ctx, 8f0, 8f0, 24f0, 24f0)
    ctx.strokeStyle = rgb(15, 23, 42)
    ctx.lineWidth = 2f0
    stroke_rect!(ctx, 36f0, 28f0, 20f0, 12f0)
    lg = Paint(LinearGradientPaint)
    lg.gradientHandlePositions = [Vec2(36f0, 8f0), Vec2(56f0, 8f0)]
    lg.gradientStops = [
        color_stop(rgb(255, 255, 255), 0f0),
        color_stop(rgb(0, 0, 0), 1f0)]
    ctx.fillStyle = lg
    fill_rect!(ctx, 36f0, 8f0, 20f0, 12f0)
    return nothing
end

"""A one-background + one-failing-op scene (the failure is op 2)."""
function failing_scene(ctx, fail::Symbol)
    ctx.fillStyle = rgb(230, 232, 236)
    fill_rect!(ctx, 0, 0, W, H)
    if fail === :clear
        clear_rect!(ctx, 10f0, 10f0, 20f0, 20f0)
    elseif fail === :multiply
        mp = Paint(rgb(100, 100, 100))
        mp.blendMode = MultiplyBlend
        ctx.fillStyle = mp
        fill_rect!(ctx, 10f0, 10f0, 20f0, 20f0)
    elseif fail === :angular
        ang = Paint(AngularGradientPaint)
        ang.gradientHandlePositions = [
            Vec2(20f0, 20f0), Vec2(30f0, 20f0), Vec2(20f0, 30f0)]
        ang.gradientStops = [
            color_stop(rgb(255, 0, 0), 0f0),
            color_stop(rgb(0, 0, 255), 1f0)]
        ctx.fillStyle = ang
        fill_rect!(ctx, 10f0, 10f0, 20f0, 20f0)
    else # :evenodd_gradient
        lg = Paint(LinearGradientPaint)
        lg.gradientHandlePositions = [Vec2(0f0, 0f0), Vec2(W, 0f0)]
        lg.gradientStops = [
            color_stop(rgb(255, 255, 255), 0f0),
            color_stop(rgb(0, 0, 0), 1f0)]
        ctx.fillStyle = lg
        p = new_path()
        rect!(p, 5f0, 5f0, 30f0, 30f0)
        rect!(p, 15f0, 15f0, 30f0, 30f0)
        fill!(ctx, p, EvenOdd)
    end
    return nothing
end

"""Record `scene` at W x H."""
function record(scene)
    rec = PictureRecorder(W, H)
    scene(rec.ctx)
    return finish_recording!(rec)
end

"""Sentinel helper: writes the marker at `file`."""
function write_file_sentinel(file, name)
    io = open(file, "w")
    try
        write(io, "SENTINEL-" * name)
    finally
        close(io)
    end
    return nothing
end

"""Parse the uncompressed object streams out of the raster-fallback PDF:
returns (rgb::Vector{UInt8}, smask::Vector{UInt8})."""
function parse_pdf_streams(doc::String, W::Int, H::Int)
    d = Vector{UInt8}(doc)
    function obj_stream(n, len)
        i = findfirst(Vector{UInt8}("$n 0 obj\n"), d)
        i === nothing && throw(ErrorException("object $n not found"))
        i0 = i.stop
        s = findfirst(Vector{UInt8}("stream\n"),
            d[i0:min(i0 + len + 4000, length(d))])
        s === nothing && throw(ErrorException("object $n stream not found"))
        start = i0 + s.stop
        return d[start:start + len - 1]
    end
    return (obj_stream(5, 3 * W * H), obj_stream(6, W * H))
end

function run(outdir::String)
    reset_checks()
    require_fonts()
    ensure_outdir(outdir)

    # ---- strict export of the supported scene (both backends) ----
    pic = record(ok_scene)
    check(length(pic.ops) == 4, "supported scene: 4 ops")
    svg = write_svg!(joinpath(outdir, "export_policies.svg"), pic)
    check(occursin("<linearGradient", svg), "SVG: the gradient exports strictly")
    check(!occursin("data:image/png", svg), "SVG: no raster in the strict export")
    pdf = write_pdf!(joinpath(outdir, "export_policies.pdf"), pic)
    check(startswith(pdf, "%PDF-1.4"), "PDF: the scene exports strictly")
    check(occursin("/ShadingType 2", pdf), "PDF: linear shading exports")

    # ---- strict failures name the op and preserve destinations ----
    for (fail, name) in [(:clear, "clear"), (:multiply, "multiply"),
        (:angular, "angular")]
        f = (ctx) -> failing_scene(ctx, fail)
        for (writer, tag, needle) in
            [(write_svg!, "svg",
                fail === :clear ? "clearRect has no static-SVG equivalent" :
                fail === :multiply ? "non-Normal blend mode is not " *
                    "SVG-exportable" :
                "angular gradients are not SVG-exportable"),
                (write_pdf!, "pdf",
                    fail === :clear ? "no PDF erase operator" :
                    fail === :multiply ? "non-Normal blend mode is not " *
                        "PDF-exportable" :
                    "angular gradients have no conic")]
            dst = joinpath(outdir, tag * "_" * name * ".fail")
            write_file_sentinel(dst, tag * "_" * name)
            err = try
                writer(dst, record(f))
                nothing
            catch e
                e
            end
            check(err isa ArgumentError &&
                occursin("op 2 (", err.msg) && occursin(needle, err.msg),
                "strict $tag: $name failure names op 2 with the right reason")
            check(read(dst, String) == "SENTINEL-" * tag * "_" * name,
                "strict $tag: $name failure preserved the sentinel destination")
        end
    end

    # ---- evenodd gradient: SVG-only positive case, PDF strict failure ----
    f = (ctx) -> failing_scene(ctx, :evenodd_gradient)
    ev = write_svg!(joinpath(outdir, "export_policies_evenodd.svg"),
        record(f))
    check(occursin("fill-rule=\"evenodd\"", ev),
        "SVG: evenodd gradient exports with fill-rule (v1 allows it)")
    dst = joinpath(outdir, "pdf_evenodd.fail")
    write_file_sentinel(dst, "pdf_evenodd")
    err = try
        write_pdf!(dst, record(f))
        nothing
    catch e
        e
    end
    check(err isa ArgumentError &&
        occursin("op 2 (", err.msg) &&
        occursin("even-odd gradient fills", err.msg),
        "PDF: evenodd gradient failure names op 2 and the fill-rule limit")
    check(read(dst, String) == "SENTINEL-pdf_evenodd",
        "PDF: evenodd failure preserved the sentinel destination")

    # ---- PDF raster fallback (core-only: raw XObject + SMask) ----
    render = new_image(W, H)
    draw_picture!(render, pic)
    fb = write_pdf!(joinpath(outdir, "export_policies_fb.pdf"), pic;
        rasterFallback = true)
    (rgb, gray) = parse_pdf_streams(fb, W, H)
    check(length(rgb) == 3 * W * H && length(gray) == W * H,
        "PDF fallback: XObject and SMask carry the full pixel payloads")
    # structural: the embedded bytes equal the replay through the
    # documented boundary (premul -> straight)
    ok = true
    for i in 1:(W * H)
        c = to_straight_alpha(render[i])
        k = 3 * (i - 1)
        if rgb[k + 1] != c.r || rgb[k + 2] != c.g || rgb[k + 3] != c.b ||
            gray[i] != c.a
            ok = false
        end
    end
    check(ok, "PDF fallback: embedded RGB/SMask == replay at the boundary")
    # independent: hand-evaluated min(round(c*255/a), 255) in integer
    # arithmetic for three known premul samples (a > 0):
    # round(p/q) for positive rationals = (2p + q) div (2q)
    hand(a, c) = min((2 * 255 * c + a) ÷ (2 * a), 255)
    i1 = 1 # (1, 1): background (230,232,236,255)
    check(rgb[1:3] == [UInt8(hand(255, 230)), UInt8(hand(255, 232)),
        UInt8(hand(255, 236))] && gray[1] == 255,
        "PDF fallback: background sample hand-equals the embedded bytes")
    i2 = 593 # (17, 10): inside the square (30,64,175,255)
    k2 = 3 * (i2 - 1)
    check(rgb[k2 + 1:k2 + 3] == [UInt8(hand(255, 30)),
        UInt8(hand(255, 64)), UInt8(hand(255, 175))] && gray[i2] == 255,
        "PDF fallback: square sample hand-equals the embedded bytes")
    i3 = 552 # (40, 9): gradient column 39 (0-based), t = 3/20
    k3 = 3 * (i3 - 1)
    g3 = UInt8((2 * 255 * 17 + 20) ÷ 40) # round(255 * 17/20) = 217, ties away
    check(gray[i3] == 255 && rgb[k3 + 1:k3 + 3] ==
        [g3, g3, g3],
        "PDF fallback: gradient sample hand-equals the embedded bytes")

    # ---- SVG raster fallback (optional: PNG data URI) ----
    if VetraGallery.available(VetraGallery.PNG_ID)
        sv = write_svg!(joinpath(outdir, "export_policies_fb.svg"), pic;
            rasterFallback = true)
        b64 = match(r"data:image/png;base64,([A-Za-z0-9+/=]+)", sv)
        b64 === nothing && check(false, "SVG fallback: data URI not found")
        dec = decode_base64(String(b64[1]))
        check(dec.data == render.data,
            "SVG fallback: the embedded PNG decodes to the exact replay")
    else
        dst = joinpath(outdir, "svg_fallback.fail")
        write_file_sentinel(dst, "svg_fallback")
        err = try
            write_svg!(dst, pic; rasterFallback = true)
            nothing
        catch e
            e
        end
        check(err isa ErrorException &&
            occursin("PNG support is opt-in", err.msg),
            "SVG fallback without PNG raises the named install hint")
        check(read(dst, String) == "SENTINEL-svg_fallback",
            "SVG fallback failure preserved the sentinel destination")
    end
    return finish("export_policies", outdir)
end

function main()
    outdir = isempty(ARGS) ? default_outdir() : ARGS[1]
    return run(outdir)
end

if VetraGallery.is_entry(@__FILE__)
    main()
end
