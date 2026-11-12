# plot_dashboard.jl -- E001 gallery program 2: a consumer example of
# plotting on the current public API (no plotting framework added).
#
#   julia --project=. examples/gallery/plot_dashboard.jl [outdir]
#
# Outputs in outdir (caller-selected; default artifacts/gallery/):
#   plot_dashboard.bmp   CPU raster (native codec)
#   plot_dashboard.svg   strict vector export of the recorded scene
#   plot_dashboard.pdf   strict single-page vector export (96 dpi)
#
# Demonstrated: line + scatter panel with axes/ticks/labels and plot-area
# clipping, a value-mapped heatmap, a bar panel, legend, and a three-panel
# layout. The data carries a large Float64 offset (> 2^24, where Float32
# resolution is 2): it is mapped to local coordinates in Float64 before
# any Float32 geometry is built, and both the forward mapping and its
# inverse are checked against hand-derived values.
#
# Import-safe: including this file defines the scene helpers and
# run/main and renders nothing.
include(joinpath(@__DIR__, "gallery.jl"))
using Vetra
using .VetraGallery

const W, H = 640, 400

# Deterministic data with a large offset, held in Float64 (never rounded
# to Float32 before mapping).
const X_DATA = Float64[20_000_000 + v for v in [0, 10, 25, 42, 60, 78, 95]]
const Y_DATA = Float64[50_000_000 + v for v in [12, 18, 8, 25, 30, 15, 22]]
const X_MIN, X_MAX = 20_000_000.0, 20_000_095.0
const Y_MIN, Y_MAX = 50_000_008.0, 50_000_030.0

# Line panel plot area (0-based canvas units); y grows downward, so the
# data minimum sits at the bottom (LY1) and the maximum at the top (LY0).
const LX0, LX1, LY0, LY1 = 60.0, 260.0, 70.0, 210.0

"""Forward mapping, data -> local pixels, in Float64 (large offsets live
here); the Float32 narrowing happens once, at geometry construction."""
function plot_px(v::Float64, vmin::Float64, vmax::Float64, p0, p1)
    return Float32(p0 + (v - vmin) / (vmax - vmin) * (p1 - p0))
end

"""Inverse mapping, local pixel -> data, in Float64."""
function plot_data(px::Float32, p0::Float64, p1::Float64, vmin::Float64,
    vmax::Float64)
    return vmin + (Float64(px) - p0) / (p1 - p0) * (vmax - vmin)
end

"""Heatmap cell color: blue -> red lerp on the integer value scale
(hand-derived: v=10 -> (106,0,149), v=14 -> (149,0,106))."""
function heat_color(v::Int, vmax::Int)
    f = Float64(v) / Float64(vmax)
    return rgb(UInt8(round(255 * f)), 0, UInt8(round(255 * (1 - f))))
end

function dashboard_scene(ctx)
    BG = rgb(248, 250, 252)
    PANEL = rgb(255, 255, 255)
    AXIS = rgb(100, 116, 139)
    LINEC = rgb(37, 99, 235)
    BARC = rgb(16, 185, 129)

    ctx.fillStyle = BG
    fill_rect!(ctx, 0, 0, W, H)

    # ---- layout: three white panels + header ----
    for (px, py, pw, ph) in [(40, 60, 240, 170), (310, 60, 260, 170),
        (310, 240, 260, 150)]
        ctx.fillStyle = PANEL
        fill_rect!(ctx, px, py, pw, ph)
    end
    ctx.font = VetraGallery.ROBOTO
    ctx.fontSize = 16f0
    ctx.fillStyle = rgb(15, 23, 42)
    fill_text!(ctx, "Synthetic ops dashboard", 40, 40)

    # ---- legend (top-right, inside the heatmap panel header) ----
    ctx.fillStyle = LINEC
    fill_rect!(ctx, 330, 68, 12, 12)
    ctx.fillStyle = rgb(202, 0, 80)
    fill_rect!(ctx, 430, 68, 12, 12)
    ctx.fontSize = 12f0
    ctx.fillStyle = rgb(71, 85, 105)
    fill_text!(ctx, "series", 348, 80)
    fill_text!(ctx, "heat", 448, 80)

    # ---- panel 1: line + scatter with axes, ticks, labels, clip ----
    ctx.font = VetraGallery.ROBOTO
    ctx.fontSize = 11f0
    ctx.fillStyle = rgb(15, 23, 42)
    fill_text!(ctx, "Count (large-offset data)", 60, 52)
    # plot-area clip so the out-of-range point never draws past the grid
    save!(ctx)
    clip_rect = new_path()
    rect!(clip_rect, Float32(LX0), Float32(LY0),
        Float32(LX1 - LX0), Float32(LY1 - LY0))
    clip!(ctx, clip_rect)
    # axes
    ctx.strokeStyle = AXIS
    ctx.lineWidth = 1f0
    stroke_rect!(ctx, Float32(LX0), Float32(LY0), Float32(LX1 - LX0),
        Float32(LY1 - LY0))
    # x tick marks at 0 / 50 / 95 of the data range (labels go outside
    # the clip, below)
    for tv in [X_MIN, 20_000_050.0, X_MAX]
        tx = plot_px(tv, X_MIN, X_MAX, LX0, LX1)
        begin_path!(ctx)
        move_to!(ctx, tx, Float32(LY1))
        line_to!(ctx, tx, Float32(LY1 - 4))
        stroke!(ctx)
    end
    # the line path: 7 data points + one out-of-range point (ymax + 10)
    # that the clip must cut off
    linec = new_path()
    first = true
    for (xv, yv) in zip(X_DATA, Y_DATA)
        x = plot_px(xv, X_MIN, X_MAX, LX0, LX1)
        y = plot_px(yv, Y_MIN, Y_MAX, Float64(LY1), Float64(LY0))
        if first
            move_to!(linec, x, y)
            first = false
        else
            line_to!(linec, x, y)
        end
    end
    line_to!(linec, plot_px(X_MAX, X_MIN, X_MAX, LX0, LX1),
        plot_px(Y_MAX + 10, Y_MIN, Y_MAX, Float64(LY1), Float64(LY0)))
    ctx.strokeStyle = LINEC
    ctx.lineWidth = 2f0
    stroke!(ctx, linec)
    # scatter markers
    for (xv, yv) in zip(X_DATA, Y_DATA)
        x = plot_px(xv, X_MIN, X_MAX, LX0, LX1)
        y = plot_px(yv, Y_MIN, Y_MAX, Float64(LY1), Float64(LY0))
        dot = new_path()
        circle!(dot, x, y, 3f0)
        ctx.fillStyle = LINEC
        fill!(ctx, dot)
    end
    restore!(ctx)
    # tick labels (outside the clip: below and left)
    ctx.fillStyle = rgb(71, 85, 105)
    for (tv, lab) in [(X_MIN, "20M"), (20_000_050.0, "20.05M"),
        (X_MAX, "20.095M")]
        tx = plot_px(tv, X_MIN, X_MAX, LX0, LX1)
        ctx.textAlign = CenterAlign
        fill_text!(ctx, lab, tx, Float32(LY1) + 14f0)
        ctx.textAlign = LeftAlign
    end
    for (tv, lab) in [(Y_MIN, "50.0008M"), (Y_MAX, "50.0030M")]
        ty = plot_px(tv, Y_MIN, Y_MAX, Float64(LY1), Float64(LY0))
        ctx.textAlign = RightAlign
        fill_text!(ctx, lab, Float32(LX0) - 6f0, ty + 4f0)
        ctx.textAlign = LeftAlign
    end

    # ---- panel 2: heatmap, 5x5 grid, values 0..24 (row-major) ----
    for yrow in 0:4
        for xcol in 0:4
            v = yrow * 5 + xcol
            hx = 320 + 48 * xcol
            hy = 100 + 24 * yrow
            ctx.fillStyle = heat_color(v, 24)
            fill_rect!(ctx, hx, hy, 44, 22)
        end
    end

    # ---- panel 3: bars, values {12, 20, 7} over a 25 scale ----
    ctx.fillStyle = rgb(15, 23, 42)
    ctx.font = VetraGallery.ROBOTO
    ctx.fontSize = 11f0
    fill_text!(ctx, "Latency buckets", 330, 258)
    ctx.strokeStyle = AXIS
    ctx.lineWidth = 1f0
    stroke_segment!(ctx, 340f0, 370f0, 540f0, 370f0)
    for (i, val) in enumerate([12, 20, 7])
        bh = Int(round(Float64(val) / 25 * 100))
        bx = 340 + 60 * i
        ctx.fillStyle = BARC
        fill_rect!(ctx, bx, 370 - bh, 40, bh)
    end
    return nothing
end

function run(outdir::String)
    reset_checks()
    require_fonts()
    ensure_outdir(outdir)

    # ---- the large-offset discipline (independent Float32 facts) ----
    # At 2e7 (in [2^24, 2^25)) Float32 spacing is 2, so odd data deltas are
    # not representable: datum 20000025 collapses to 20000024, while the
    # even-spaced 20000042 survives. Mapping raw values in Float32 would
    # quantize the data; subtracting the offset in Float64 first does not.
    check(Float32(20_000_025) == 20_000_024f0,
        "Float32: odd datum 20000025 collapses to 20000024 (spacing 2)")
    check(Float32(20_000_042) == 20_000_042f0,
        "Float32: even datum 20000042 is representable")
    check(Float64(X_MIN) + 25 == 20_000_025.0,
        "Float64: the offset+delta survives exactly before mapping")
    # forward mapping: hand-derived endpoints
    check(plot_px(X_MIN, X_MIN, X_MAX, LX0, LX1) == 60f0,
        "mapping: first x datum lands exactly on the left axis")
    check(plot_px(X_MAX, X_MIN, X_MAX, LX0, LX1) == 260f0,
        "mapping: last x datum lands exactly on the right axis")
    y1 = plot_px(Y_DATA[1], Y_MIN, Y_MAX, LY1, LY0)
    check(abs(Float64(y1) - 184.54545f0) < 0.01f0,
        "mapping: y=50012 -> 210 - (4/22)*140 = 184.545...")
    check(plot_px(Y_MAX, Y_MIN, Y_MAX, Float64(LY1), Float64(LY0)) == 70f0,
        "mapping: y max lands exactly on the top")
    # inverse mapping round trip (exact in Float64)
    check(plot_data(plot_px(X_MAX, X_MIN, X_MAX, LX0, LX1), LX0, LX1,
            X_MIN, X_MAX) == 20_000_095.0,
        "inverse: pixel 260 maps back to exactly 20000095")
    check(plot_data(60f0, LX0, LX1, X_MIN, X_MAX) == 20_000_000.0,
        "inverse: pixel 60 maps back to exactly 20000000")

    direct = new_image(W, H)
    dashboard_scene(Context(direct))

    rec = PictureRecorder(W, H)
    dashboard_scene(rec.ctx)
    picture = finish_recording!(rec)
    replay = new_image(W, H)
    draw_picture!(replay, picture)
    check(replay.data == direct.data,
        "replay at the recorded size is byte-identical to direct drawing")

    px(x, y) = get_color(direct, x, y)
    LINEC = rgbx(37, 99, 235, 255)
    # scatter markers (r=3): datum 1 at canvas (60, 184.545) (left edge),
    # datum 5 (the y maximum) at (186.32, 70) (top edge), datum 7 at
    # (260, 120.91) (right edge)
    check(px(61, 185) == LINEC, "scatter: first datum marker interior")
    check(px(187, 72) == LINEC,
        "scatter: max-y datum marker interior (clipped at the top edge)")
    check(px(259, 121) == LINEC,
        "scatter: last datum marker interior (clipped at the right edge)")
    # clip: the out-of-range datum (X_MAX, Y_MAX+10) maps to (260, 6.4);
    # its segment along x=260 must be cut at the plot-area top (y=70).
    # Canvas (259..260, 64..65) is on that segment, inside the white
    # panel, above the clip.
    check(px(260, 65) == rgbx(255, 255, 255, 255),
        "clip: the out-of-range segment is cut at the plot area")
    # heatmap cell interiors (value scale 0..24, blue->red lerp)
    check(px(343, 112) == rgbx(0, 0, 255, 255),
        "heatmap: v=0 cell is pure blue")
    check(px(343, 160) == rgbx(106, 0, 149, 255),
        "heatmap: v=10 cell is the hand-lerped (106,0,149)")
    check(px(535, 160) == rgbx(149, 0, 106, 255),
        "heatmap: v=14 cell is the hand-lerped (149,0,106)")
    check(px(535, 208) == rgbx(255, 0, 0, 255),
        "heatmap: v=24 cell is pure red")
    # bars (values 12/20/7 on a 25 scale, baseline y=370): heights
    # 48/80/28, bars at x 400/460/520
    BARC = rgbx(16, 185, 129, 255)
    check(px(421, 347) == BARC, "bars: 12/25 bar body")
    check(px(481, 331) == BARC, "bars: 20/25 bar body")
    check(px(541, 357) == BARC, "bars: 7/25 bar body")
    check(px(421, 372) != BARC, "bars: below the baseline is not bar")
    write_file!(direct, joinpath(outdir, "plot_dashboard.bmp"))

    # strict vector exports (text lowers to glyph outlines at record time;
    # no images in the scene -> core-only)
    svg = write_svg!(joinpath(outdir, "plot_dashboard.svg"), picture)
    check(occursin("viewBox=\"0 0 640 400\"", svg), "SVG: logical canvas")
    check(occursin("clipPath", svg), "SVG: plot-area clip exported")
    pdf = write_pdf!(joinpath(outdir, "plot_dashboard.pdf"), picture)
    check(startswith(pdf, "%PDF-1.4"), "PDF: document header")
    check(occursin("W n", pdf), "PDF: plot-area clip exported")
    return finish("plot_dashboard", outdir)
end

function main()
    outdir = isempty(ARGS) ? default_outdir() : ARGS[1]
    return run(outdir)
end

if VetraGallery.is_entry(@__FILE__)
    main()
end
