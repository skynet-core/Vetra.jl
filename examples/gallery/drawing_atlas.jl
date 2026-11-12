# drawing_atlas.jl -- E001 gallery program 1: paths, fill rules,
# caps/joins/dashes, transforms, linear/radial gradients, clips and group
# opacity, drawn once through one reusable scene function.
#
#   julia --project=. examples/gallery/drawing_atlas.jl [outdir]
#
# Outputs in outdir (caller-selected; default artifacts/gallery/):
#   drawing_atlas.bmp  raster of the direct CPU drawing (native codec)
#   drawing_atlas.svg  strict vector export of the recorded scene
#   drawing_atlas.pdf  strict single-page vector export (96 dpi)
#
# Checks: direct vs recorded replay byte parity, 2x vector-space replay
# geometry, and hand-derived interior pixel samples (each derived from the
# documented coordinate/blend/gradient contracts, never from a rendered
# output). Import-safe: including this file defines atlas_scene/run/main
# and renders nothing.
include(joinpath(@__DIR__, "gallery.jl"))
using Vetra
using .VetraGallery

const W, H = 560, 440
const BG = rgbx(248, 250, 252, 255)
const RED = rgbx(220, 38, 38, 255)
const BLUE = rgbx(37, 99, 235, 255)
const GREEN = rgbx(22, 163, 74, 255)
const INK = rgbx(15, 23, 42, 255)
const ORANGE = rgbx(249, 115, 22, 255)

"""
The atlas scene. `ctx` is any Context or RecordingContext with the
identical drawing surface (D030 §2): the same call list is replayed on
both, so the recorded picture must equal the direct render.

All coordinates are 0-based canvas units; the hand-derived checks in
`run` address 1-based pixels with at least a 1 px margin from every
geometry edge so coverage is unambiguously 0 or 1.
"""
function atlas_scene(ctx)
    # background
    ctx.fillStyle = rgb(248, 250, 252)
    fill_rect!(ctx, 0, 0, W, H)

    # fill rules: two overlapping rects as one path (0-based extents)
    ee = new_path()
    rect!(ee, 30f0, 20f0, 110f0, 110f0)
    rect!(ee, 85f0, 75f0, 110f0, 110f0)
    ctx.fillStyle = rgb(220, 38, 38)
    fill!(ctx, ee, EvenOdd) # overlap [85,140]x[75,130] is a hole
    nz = new_path()
    rect!(nz, 200f0, 20f0, 110f0, 110f0)
    rect!(nz, 250f0, 75f0, 110f0, 110f0)
    ctx.fillStyle = rgb(37, 99, 235)
    fill!(ctx, nz, NonZero) # overlap [250,310]x[75,130] is filled

    # transform: fill a rect under translate . rotate (snapshot model)
    set_transform!(ctx, translate(Vec2(400f0, 30f0)) * rotate(Float32(0.5)))
    ctx.fillStyle = rgb(22, 163, 74)
    fill_rect!(ctx, 0, 0, 80f0, 80f0)
    reset_transform!(ctx)

    # caps and dashes: three horizontal strokes, width 8, (40,y)-(200,y)
    ctx.strokeStyle = rgb(15, 23, 42)
    ctx.lineWidth = 8f0
    ctx.lineCap = ButtCap
    stroke_segment!(ctx, 40f0, 205f0, 200f0, 205f0)
    ctx.lineCap = RoundCap
    stroke_segment!(ctx, 40f0, 225f0, 200f0, 225f0)
    ctx.lineCap = SquareCap
    set_line_dash!(ctx, Float32[12f0, 6f0])
    stroke_segment!(ctx, 40f0, 245f0, 200f0, 245f0)
    set_line_dash!(ctx, Float32[])

    # joins: three V polylines, width 8, 90-degree apices at y=270
    v1 = new_path()
    move_to!(v1, 240f0, 310f0)
    line_to!(v1, 270f0, 270f0)
    line_to!(v1, 300f0, 310f0)
    ctx.lineJoin = MiterJoin
    stroke!(ctx, v1)
    v2 = new_path()
    move_to!(v2, 330f0, 310f0)
    line_to!(v2, 360f0, 270f0)
    line_to!(v2, 390f0, 310f0)
    ctx.lineJoin = RoundJoin
    stroke!(ctx, v2)
    v3 = new_path()
    move_to!(v3, 420f0, 310f0)
    line_to!(v3, 450f0, 270f0)
    line_to!(v3, 480f0, 310f0)
    ctx.lineJoin = BevelJoin
    stroke!(ctx, v3)

    # linear gradient (handles on one horizontal line, opaque stops)
    lg = Paint(LinearGradientPaint)
    lg.gradientHandlePositions = [Vec2(30f0, 340f0), Vec2(230f0, 340f0)]
    lg.gradientStops = [
        color_stop(rgb(255, 255, 255), 0f0),
        color_stop(rgb(0, 0, 0), 1f0),
    ]
    ctx.fillStyle = lg
    fill_rect!(ctx, 30, 340, 200, 40)

    # radial gradient: unit circle mapped to center (330,360), radius 35
    rg = Paint(RadialGradientPaint)
    rg.gradientHandlePositions = [
        Vec2(330f0, 360f0), Vec2(365f0, 360f0), Vec2(330f0, 325f0)
    ]
    rg.gradientStops = [
        color_stop(rgb(255, 255, 255), 0f0),
        color_stop(rgb(234, 88, 12), 1f0),
    ]
    circle = new_path()
    circle!(circle, 330f0, 360f0, 35f0)
    ctx.fillStyle = rg
    fill!(ctx, circle)

    # clip: orange rect clipped to a circle (cumulative vector clip)
    save!(ctx)
    clip_circle = new_path()
    circle!(clip_circle, 450f0, 360f0, 30f0)
    clip!(ctx, clip_circle)
    ctx.fillStyle = ORANGE
    fill_rect!(ctx, 420, 330, 60, 60)
    restore!(ctx)

    # group opacity (globalAlpha wrapper = layer + applyOpacity, recorded
    # as a group with opacity)
    ctx.globalAlpha = Float32(0.5)
    ctx.fillStyle = rgb(255, 120, 0)
    fill_rect!(ctx, 30, 405, 80, 30)
    ctx.globalAlpha = Float32(1)

    # isolated layer vs direct control: two 50%-alpha rects overlapping;
    # in the layer they composite on transparent, directly on the white
    # background (group-unit vs sequential source-over)
    save_layer!(ctx)
    ctx.fillStyle = rgba(0, 0, 255, 128)
    fill_rect!(ctx, 140, 405, 80, 30)
    ctx.fillStyle = rgba(255, 0, 0, 128)
    fill_rect!(ctx, 170, 405, 80, 30)
    restore!(ctx)
    ctx.fillStyle = rgba(0, 0, 255, 128)
    fill_rect!(ctx, 270, 405, 80, 30)
    ctx.fillStyle = rgba(255, 0, 0, 128)
    fill_rect!(ctx, 300, 405, 80, 30)
    return nothing
end

function run(outdir::String)
    reset_checks()
    ensure_outdir(outdir)

    direct = new_image(W, H)
    atlas_scene(Context(direct))

    rec = PictureRecorder(W, H)
    atlas_scene(rec.ctx)
    picture = finish_recording!(rec)
    # Hand-derived from the D030 §2/§4 op model: 1 background + 2 fill-rule
    # + 1 transformed + 6 stroke + 2 gradient + 3 clip group
    # (GroupStart/FillOp/GroupEnd) + 3 globalAlpha group + 4 isolated-layer
    # group + 2 direct fills = 24 ops.
    check(length(picture.ops) == 24,
        "scene records exactly 24 ops (got $(length(picture.ops)))")

    replay = new_image(W, H)
    draw_picture!(replay, picture)
    check(replay.data == direct.data,
        "replay at the recorded size is byte-identical to direct CPU drawing")

    px(x, y) = get_color(direct, x, y)
    # evenodd (red): overlap hole [85,140]x[75,130]
    check(px(51, 41) == RED, "evenodd: interior of first rect is red")
    check(px(111, 101) == BG, "evenodd: overlap is a hole (background)")
    check(px(171, 141) == RED, "evenodd: interior of second rect is red")
    check(px(21, 41) == BG, "evenodd: outside both rects is background")
    # nonzero (blue): overlap [250,310]x[75,130] filled
    check(px(281, 101) == BLUE, "nonzero: overlap is filled")
    check(px(221, 41) == BLUE, "nonzero: interior of first rect is blue")
    check(px(101, 196) == BG,
        "nonzero: between the fill-rule band and the strokes")
    # transformed rect: corners (400,30),(470.2,68.4),(431.8,138.6),
    # (361.6,100.2); center (415.93,84.28)
    check(px(416, 85) == GREEN, "transform: rect center is green")
    check(px(399, 29) == BG, "transform: above-left of the origin corner")
    check(px(473, 61) == BG, "transform: beyond the far corner")
    # butt stroke (40,205)-(200,205), width 8: band y in [201,209], no caps
    check(px(42, 206) == INK, "butt: body of the stroke")
    check(px(39, 206) == BG, "butt: no cap extension past the start")
    check(px(203, 206) == BG, "butt: no cap extension past the end")
    # round stroke at y=225: cap circles r=4 at (40,225)/(200,225)
    check(px(39, 226) == INK, "round: inside the start cap (margin >= 1.7)")
    check(px(36, 226) == BG, "round: outside the start cap (distance 4.03)")
    check(px(121, 226) == INK, "round: body of the stroke")
    check(px(207, 226) == BG, "round: outside the end cap (distance 6)")
    # square-capped dashed stroke at y=245, dashes [12,6] from x=40:
    # on [36,52], off [52,58], on [58,70], ...
    check(px(38, 246) == INK, "square: cap extension past the start")
    check(px(56, 246) == BG, "dashes: interior of the first gap")
    check(px(62, 246) == INK, "dashes: second dash body")
    # joins at 90-degree apices (vertex at y=270, width 8):
    # miter tip reaches y=264.34 (4/sin45); round reaches 266 (r=4);
    # bevel cuts at y=267.17
    check(px(271, 266) == INK, "miter: tip region is ink (derived 264.34)")
    check(px(361, 266) == BG, "round: above the r=4 arc is background")
    check(px(451, 266) == BG, "bevel: above the 267.17 cut is background")
    check(px(253, 299) == INK, "joins: arm body (miter V)")
    check(px(343, 299) == INK, "joins: arm body (round V)")
    check(px(433, 299) == INK, "joins: arm body (bevel V)")
    # linear gradient, column x sampled at t=(x-30)/200 (integer column,
    # documented raster sampling):
    check(px(31, 361) == rgbx(255, 255, 255, 255), "linear: t=0 is stop 0")
    check(px(131, 361) == rgbx(128, 128, 128, 255),
        "linear: t=0.5 lerps white->black to (128,128,128)")
    check(px(230, 361) == rgbx(1, 1, 1, 255),
        "linear: t=199/200 rounds to (1,1,1)")
    # radial gradient, t = distance from (330,360) / 35:
    check(px(331, 361) == rgbx(255, 255, 255, 255), "radial: center is white")
    check(px(364, 361) == rgbx(235, 98, 26, 255),
        "radial: t=33/35 hand-lerps to (235,98,26)")
    check(px(369, 361) == BG, "radial: outside r=35 is background")
    # clip: circle r=30 at (450,360) over an orange rect [420,480]x[330,390]
    check(px(451, 361) == ORANGE, "clip: interior of the circle")
    check(px(479, 361) == ORANGE, "clip: 29.0 px from the center is inside")
    check(px(476, 336) == BG, "clip: inside the rect but outside the circle")
    check(px(416, 361) == BG, "clip: left of the circle")
    # group opacity: layer(orange opaque) * applyOpacity(0.5):
    # o = round(255*0.5) = 128 -> premul (128,60,0,128); source-over on
    # the BG (248,250,252): (128 + 248*127/255, 60 + 250*127/255,
    # 0 + 252*127/255, 255) = (251,184,125,255)
    check(px(41, 416) == rgbx(251, 184, 125, 255),
        "group opacity: 50% layer composite is hand-derived")
    # isolated layer: blue (0,0,128,128) then red (128,0,0,128) on
    # transparent: overlap (128,0,63,191); over the BG (k=64):
    # (128 + 248*64/255, 0 + 250*64/255, 63 + 252*64/255, 255)
    # = (190,62,126,255)
    check(px(151, 416) == rgbx(123, 124, 253, 255),
        "layer: single 50% blue over the background")
    check(px(191, 416) == rgbx(190, 62, 126, 255),
        "layer: isolated overlap is hand-derived")
    # direct control (no layer): same rects straight on the background:
    # BG <- blue (123,124,253,255) <- red: (128 + 123*127/255,
    # 0 + 124*127/255, 0 + 253*127/255, 255) = (189,61,126,255)
    check(px(281, 416) == rgbx(123, 124, 253, 255),
        "control: single 50% blue over the background")
    check(px(321, 416) == rgbx(189, 61, 126, 255),
        "control: sequential overlap differs from the isolated layer")

    # 2x vector-space replay (re-rasterized, never a raster enlargement):
    # every picture-space region doubles; margin-1 checks double to margin-2
    zoom = new_image(2 * W, 2 * H)
    draw_picture!(zoom, picture)
    zpx(x, y) = get_color(zoom, x, y)
    check(zpx(102, 82) == RED, "2x replay: red interior scales")
    check(zpx(222, 202) == BG, "2x replay: evenodd hole interior scales")
    check(zpx(262, 410) == INK,
        "2x replay: stroke body (picture row 204.5 inside [201,209])")
    check(zpx(402, 411) == BG,
        "2x replay: outside the scaled butt end (picture x >= 200.5)")
    # Pinned raster gradient semantics (D030 §4, RECORDING.md): replay
    # re-executes the kernels with the scaled canvas mapping; geometry
    # scales, but the gradient pattern samples the picture-space handles
    # in image space (untransformed). The vector exports instead map the
    # gradient by T^-1, so a scaled SVG shows the stretched gradient.
    check(zpx(51, 721) == BG, "2x replay: left of the scaled gradient rect")
    check(zpx(61, 721) == rgbx(217, 217, 217, 255),
        "2x replay: zoom column 60 samples t=(60-30)/200=0.15 (derived)")
    check(zpx(131, 721) == rgbx(128, 128, 128, 255),
        "2x replay: zoom column 130 samples t=0.5 (derived)")
    check(zpx(301, 721) == rgbx(0, 0, 0, 255),
        "2x replay: t clamps to the last stop past zoom column 230")
    check(zpx(461, 721) == BG, "2x replay: right of the scaled gradient rect")
    check(zpx(661, 721) == rgbx(234, 88, 12, 255),
        "2x replay: radial pattern clamps to its last stop (derived)")
    write_file!(direct, joinpath(outdir, "drawing_atlas.bmp"))

    # strict vector exports (no package needed for this scene: solid +
    # linear/radial fills, solid strokes, transforms, one clip, groups)
    svg = write_svg!(joinpath(outdir, "drawing_atlas.svg"), picture)
    check(occursin("<linearGradient", svg) && occursin("<radialGradient", svg),
        "strict SVG: both gradients exported")
    check(occursin("clipPath", svg), "strict SVG: clip exported")
    check(occursin("stroke-dasharray", svg), "strict SVG: dashes exported")
    check(occursin("opacity=\"", svg), "strict SVG: group opacity exported")
    pdf = write_pdf!(joinpath(outdir, "drawing_atlas.pdf"), picture)
    check(startswith(pdf, "%PDF-1.4"), "strict PDF: PDF 1.4 document")
    check(occursin("/ShadingType 2", pdf) && occursin("/ShadingType 3", pdf),
        "strict PDF: linear + radial shadings exported")
    check(occursin("W n", pdf), "strict PDF: clip exported")
    return finish("drawing_atlas", outdir)
end

function main()
    outdir = isempty(ARGS) ? default_outdir() : ARGS[1]
    return run(outdir)
end

if VetraGallery.is_entry(@__FILE__)
    main()
end
