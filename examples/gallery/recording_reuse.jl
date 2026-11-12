# recording_reuse.jl -- E001 gallery program 5: build a scene once,
# replay it on a fresh canvas at two resolutions, prove the recorded
# picture owns snapshot copies of its sources (later mutation of the
# original Path / Paint / Image cannot change the replay), demonstrate
# host-owned parameter changes, the one-shot recorder contract, and the
# export policies (PDF strict vector with a raw image XObject is
# core-only; SVG of a scene containing draw_image! needs opt-in PNG
# support for the data URI).
#
#   julia --project=. examples/gallery/recording_reuse.jl [outdir]
#
# Outputs in outdir (caller-selected; default artifacts/gallery/):
#   recording_reuse_480.bmp  replay at the recorded size (CPU)
#   recording_reuse_960.bmp  replay re-rasterized at 2x (CPU)
#   recording_reuse.pdf      strict vector export (core-only path)
#   recording_reuse.svg      only with opt-in PNG support
#
# Hand-derived expectations: the accent square [50,150)^2 doubles to
# [100,300)^2 under the 2x replay; the 4 px outline stroke doubles to
# 8 px; the 16x8 stamp doubles byte-exactly (integer sampling of pixel
# centers at the exact 2x scale). Import-safe: including this file
# defines helpers and run/main and renders nothing.
include(joinpath(@__DIR__, "gallery.jl"))
using Vetra
using .VetraGallery

const W, H = 480, 300
const BG = rgbx(240, 244, 248, 255)
const BLUE = rgbx(37, 99, 235, 255)

"""Deterministic opaque 16x8 stamp (all alpha 255, so the 2x replay
sampling is byte-exact)."""
function stamp_image()
    img = new_image(16, 8)
    for y in 0:7, x in 0:15
        v = (x + 2 * y) % 4
        set_color!(img, x + 1, y + 1, [
            rgbx(220, 38, 38, 255), rgbx(37, 99, 235, 255),
            rgbx(22, 163, 74, 255), rgbx(217, 119, 6, 255)][v + 1])
    end
    return img
end

"""Caller-owned sources the scene reads (all mutable)."""
mutable struct Sources
    square::Path
    accent::Paint
    stamp::Image
end

function make_sources()
    sq = new_path()
    rect!(sq, 50f0, 50f0, 100f0, 100f0)
    accent = Paint(rgb(37, 99, 235))
    return Sources(sq, accent, stamp_image())
end

"""The reusable scene: one background fill, the accent square, a
stroked outline rect, and the image stamp. `ctx` may be a Context or a
RecordingContext (identical drawing surface, D030 §2)."""
function reuse_scene(ctx, srcs::Sources)
    ctx.fillStyle = rgb(240, 244, 248)
    fill_rect!(ctx, 0, 0, W, H)
    ctx.fillStyle = srcs.accent
    fill!(ctx, srcs.square)
    ctx.strokeStyle = rgb(37, 99, 235)
    ctx.lineWidth = 4f0
    stroke_rect!(ctx, 180f0, 60f0, 80f0, 40f0)
    draw_image!(ctx, srcs.stamp, 300f0, 150f0)
    return nothing
end

function run(outdir::String)
    reset_checks()
    require_fonts()
    ensure_outdir(outdir)

    srcs = make_sources()
    rec = PictureRecorder(W, H)
    reuse_scene(rec.ctx, srcs)
    picture = finish_recording!(rec)
    check(length(picture.ops) == 4,
        "scene records exactly 4 ops (background, square, outline, " *
        "stamp; got $(length(picture.ops)))")

    # ---- snapshot ownership: mutate every source after finish ----
    srcs.square.commands = Float32[] # the square is now an empty path
    srcs.accent.color = ColorRGBA(220, 0, 0, 255) # red, not blue
    set_color!(srcs.stamp, 1, 1, rgb(0, 0, 0)) # stamp corner repainted
    # (the original stamp data and path are what the picture snapshotted)

    direct = new_image(W, H)
    reuse_scene(Context(direct), Sources(
        let p = new_path(); rect!(p, 50f0, 50f0, 100f0, 100f0); p end,
        Paint(rgb(37, 99, 235)), stamp_image()))
    r1 = new_image(W, H)
    draw_picture!(r1, picture)
    r2 = new_image(W, H)
    draw_picture!(r2, picture)
    check(r1.data == r2.data,
        "repeated replays are byte-identical")
    check(r1.data == direct.data,
        "replay after source mutation is byte-identical to the " *
        "un-mutated direct drawing (the picture owns its snapshots)")

    # ---- 2x replay: re-rasterized, hand-derived geometry ----
    big = new_image(2 * W, 2 * H)
    draw_picture!(big, picture)
    bp(x, y) = get_color(big, x, y)
    check(get_color(r1, 149, 149) == BLUE,
        "1x: square interior (canvas 148,148 in [50,150)^2) is the accent")
    check(bp(299, 299) == BLUE, "2x: the square doubles to [100,300)^2")
    check(bp(99, 99) == BG, "2x: just outside the doubled square is background")
    check(bp(301, 201) == BG, "2x: one column past the doubled square is background")
    # outline: [180,260)x[60,100) stroked 4 -> 2x [360,520)x[120,200)
    # stroked 8: top band canvas y in [116,124)
    check(bp(441, 121) == BLUE, "2x: outline top band [116,124) is stroked")
    check(bp(441, 115) == BG, "2x: above the doubled outline is background")
    check(get_color(r1, 221, 60) == BLUE, "1x: outline top band [58,62) is stroked")
    check(get_color(r1, 221, 57) == BG, "1x: above the outline is background")
    # stamp: 16x8 at (300,150) -> 32x16 at (600,300), byte-exact doubling
    st = stamp_image()
    doubled = all(
        get_color(big, 2 * x + 601 + ox, 2 * y + 301 + oy) ==
        get_color(st, x + 1, y + 1)
        for y in 0:7 for x in 0:15
        for (ox, oy) in [(0, 0), (1, 0), (0, 1), (1, 1)])
    check(doubled, "2x: the opaque stamp doubles byte-exactly")
    check(all(
        get_color(r1, x + 301, y + 151) == get_color(st, x + 1, y + 1)
        for y in 0:7 for x in 0:15),
        "1x: the stamp region is byte-exact at the recorded scale")

    # ---- host-owned parameter change ----
    rec2 = PictureRecorder(W, H)
    srcs2 = make_sources()
    srcs2.accent = Paint(rgb(220, 38, 38))
    reuse_scene(rec2.ctx, srcs2)
    picture2 = finish_recording!(rec2)
    r3 = new_image(W, H)
    draw_picture!(r3, picture2)
    changed = 0
    for i in eachindex(r1)
        r1[i] != r3[i] && (changed += 1)
    end
    check(changed == 100 * 100,
        "parameter change: exactly the 100x100 square repaints (got $changed)")

    # ---- one-shot recorder contract ----
    try
        fill_rect!(rec.ctx, 0, 0, 10f0, 10f0)
        check(false, "one-shot: drawing after finish must raise")
    catch e
        check(e isa ArgumentError &&
            occursin("recorder already finished", e.msg),
            "one-shot: the finished recorder raises ArgumentError")
    end

    # ---- outputs and export policies ----
    write_file!(r1, joinpath(outdir, "recording_reuse_480.bmp"))
    write_file!(big, joinpath(outdir, "recording_reuse_960.bmp"))
    pdf = write_pdf!(joinpath(outdir, "recording_reuse.pdf"), picture)
    check(startswith(pdf, "%PDF-1.4"),
        "PDF: strict vector export with the image XObject is core-only")
    if VetraGallery.available(VetraGallery.PNG_ID)
        svg = write_svg!(joinpath(outdir, "recording_reuse.svg"), picture)
        check(occursin("data:image/png;base64,", svg),
            "SVG: the stamp exports as a PNG data URI")
    else
        try
            write_svg!(joinpath(outdir, "recording_reuse.svg"), picture)
            check(false, "SVG without PNG support must raise")
        catch e
            check(e isa ErrorException &&
                occursin("PNG support is opt-in", e.msg),
                "SVG without PNG support raises the named install hint")
        end
    end
    return finish("recording_reuse", outdir)
end

function main()
    outdir = isempty(ARGS) ? default_outdir() : ARGS[1]
    return run(outdir)
end

if VetraGallery.is_entry(@__FILE__)
    main()
end
