# typography.jl -- E001 gallery program 3: fonts, glyph outlines,
# kerning, paragraphs (styled spans, ellipsis), cross-font fallback and
# opt-in HarfBuzz shaping (Arabic + RTL), on the pinned fixture fonts.
#
#   julia --project=. examples/gallery/typography.jl [outdir]
#
# Outputs in outdir (caller-selected; default artifacts/gallery/):
#   typography.bmp  CPU raster of the full scene
#   typography.svg  strict vector export of the recorded text scene
#   typography.pdf  strict single-page vector export (96 dpi)
#
# The recorded scene uses only fill_text!/stroke_text! (text lowers to
# glyph-outline paths at record time, D030 §3); paragraphs, the fallback
# glyph and the shaped RTL line are CPU-raster panels. Every numeric
# expectation below is hand-derived from the pinned fixture data:
# per-rune advances from test/reference/font_roboto_metrics.tsv
# (unitsPerEm = 2048), the (W, o) kern of -31 from
# test/reference/font_roboto_kerning.tsv, the shaping gids/advances
# (424/59/36, 412/373/1093 units) from
# test/reference/shaping_reference.tsv and the NotoSans unitsPerEm = 1000
# from the pinned head tables. The layout rounding contract (selection
# rects round cumulative positions and per-rune advances; line width is
# the max of x + w) is pinned by test/paragraph_tests.jl.
#
# Import-safe: including this file defines scene helpers and run/main and
# renders nothing.
include(joinpath(@__DIR__, "gallery.jl"))
using Vetra
using .VetraGallery

const W, H = 560, 440
const BG = rgbx(248, 250, 252, 255)
const INK = rgbx(15, 23, 42, 255)
const BLUE = rgbx(37, 99, 235, 255)

# Pinned Roboto advances, font units (font_roboto_metrics.tsv).
const ADV = Dict(
    UInt32(72) => 1460.0, # H
    UInt32(87) => 1817.0, # W
    UInt32(77) => 1788.0, # M
    UInt32(109) => 1795.0, # m
    UInt32(101) => 1085.0, # e
    UInt32(108) => 497.0, # l
    UInt32(111) => 1168.0, # o
    UInt32(115) => 1056.0, # s
    UInt32(32) => 507.0, # space
    UInt32(0x2026) => 1370.0) # ellipsis

"""Record-safe panels (A: metrics/kerning, B: stroke text)."""
function text_panels(ctx)
    ctx.fillStyle = rgb(248, 250, 252)
    fill_rect!(ctx, 0, 0, W, H)
    ctx.font = VetraGallery.ROBOTO
    ctx.fillStyle = rgb(15, 23, 42)
    ctx.fontSize = 20f0
    fill_text!(ctx, "Typography on the public API", 30, 42)

    # panel A
    ctx.fontSize = 12f0
    fill_text!(ctx, "Hello @24   Works @24 (kerned W,o)", 30, 82)
    ctx.fontSize = 24f0
    fill_text!(ctx, "Hello", 30, 112)
    fill_text!(ctx, "Works", 30, 152)

    # panel B
    ctx.fontSize = 12f0
    fill_text!(ctx, "VETRA @60 stroked, width 3", 30, 182)
    ctx.strokeStyle = rgb(15, 23, 42)
    ctx.lineWidth = 3f0
    ctx.fontSize = 60f0
    stroke_text!(ctx, "VETRA", 30, 235)
    return nothing
end

"""The full CPU scene (all panels)."""
function scene(img::Image, tf::Typeface, tfA::Typeface, tfd::Typeface)
    ctx = Context(img)
    text_panels(ctx)

    # panel C: styled paragraph, width 140 at (270, 75). Paragraphs
    # render through each span font's own paints, so the colors are set
    # on the fonts, not on the context.
    ctx.fillStyle = rgb(71, 85, 105)
    ctx.font = VetraGallery.ROBOTO
    ctx.fontSize = 12f0
    fill_text!(ctx, "spans: Hello @24 + world @36, width 140", 270, 62)
    f24 = new_font(tf); f24.size = 24f0
    f24.paints = [Paint(rgb(15, 23, 42))]
    f36 = new_font(tf); f36.size = 36f0
    f36.paints = [Paint(rgb(37, 99, 235))]
    layC = layout_paragraph(
        new_paragraph([new_span("Hello ", f24), new_span("world", f36)];
            width = 140f0))
    fill_paragraph!(ctx, layC, 270, 75)

    # panel D: ellipsis paragraph at (270, 192)
    fill_text!(ctx, "ellipsis: MMMMM m @12 in a 10 px box", 270, 186)
    f12 = new_font(tf); f12.size = 12f0
    layD = layout_paragraph(
        new_paragraph("MMMMM m", f12; width = 10f0,
            overflow = EllipsisOverflow))
    fill_paragraph!(img, layD, 270, 192)

    # panel E: cross-font fallback glyph at baseline (60, 340)
    fill_text!(ctx, "U+0915 via Roboto -> Devanagari fallback", 30, 272)
    fill_text!(ctx, "U+05D0: absent in both -> .notdef metrics", 30, 356)
    fb = with_fallback(tf, [tfd])
    p = get_glyph_path(fb, UInt32(0x0915))
    s = 48f0 / scale(tfd)
    transform(p, translate(Vec2(60f0, 340f0)) * scale(Vec2(s, s)))
    ctx.fillStyle = rgb(190, 24, 93)
    fill!(ctx, p)

    # panel F: opt-in shaping panel
    if VetraGallery.available(VetraGallery.HARBUFF_ID)
        fill_text!(ctx, "shaped (HarfBuzz): RTL 'katab' @32", 270, 302)
        fA = new_font(tfA); fA.size = 32f0
        layF = layout_paragraph(new_paragraph("كتب", fA; dir = RightToLeft))
        fill_paragraph!(img, layF, 270, 315)
        fill_text!(ctx, "gids 424 59 36 (pinned)", 270, 400)
    else
        fill_text!(ctx, "shaping: opt-in (HarfBuzz_jll absent here)",
            270, 302)
        fill_text!(ctx, "RTL paragraphs and shape_text raise the",
            270, 320)
        fill_text!(ctx, "named install hint in core-only environments",
            270, 334)
    end
    return nothing
end

function run(outdir::String)
    reset_checks()
    ensure_outdir(outdir)

    tf = read_typeface(VetraGallery.ROBOTO)
    tfA = read_typeface(joinpath(VetraGallery.ROOT, "test", "fixtures",
        "NotoSansArabic-Regular.ttf"))
    tfd = read_typeface(joinpath(VetraGallery.ROOT, "test", "fixtures",
        "NotoSansDevanagari-Regular.ttf"))

    # ---- panel A: metrics and kerning (pinned-advance math) ----
    ctx = Context(new_image(W, H))
    ctx.font = VetraGallery.ROBOTO
    ctx.fontSize = 24f0
    check(measure_text(ctx, "Hello").width == 55.0f0,
        "Hello @24: width 55.0 from pinned advances (41 + 14 rects)")
    check(measure_text(ctx, "Works").width == 67.0f0,
        "Works @24: width 67.0 encodes the pinned -31 W,o kern " *
        "(71.0 un-kerned)")
    check(get_advance(tf, UInt32(72)) == 1460.0,
        "pinned advance: H = 1460 font units")
    check(get_advance(tf, UInt32(72)) / 2048 * 24 == 17.109375f0,
        "H @24 = 17.109375 px (exact binary fraction)")
    check(get_advance(tf, UInt32(111)) / 2048 * 24 == 13.6875f0,
        "o @24 = 13.6875 px (exact binary fraction)")

    # ---- panel C: styled paragraph ----
    f24 = new_font(tf); f24.size = 24f0
    f36 = new_font(tf); f36.size = 36f0
    layC = layout_paragraph(
        new_paragraph([new_span("Hello ", f24), new_span("world", f36)];
            width = 140f0))
    mC = paragraph_metrics(layC)
    # hand-derived: line 1 "Hello " = 5214 units -> 61.10 px; line 2
    # "world" = 5052 units -> 88.70 px; 61.10 + 88.70 > 140 -> wrap,
    # 88.70 <= 140 -> exactly 2 lines. Line width = round(88.6953) = 89.
    check(61.1015625 + 88.6953125 > 140 && 88.6953125 <= 140,
        "wrap decision from pinned advances (149.80 > 140 >= 88.70)")
    check(mC.lineCount == 2, "styled paragraph: 2 lines (derived)")
    check(mC.width == 89.0f0, "styled paragraph: width 89.0 (derived)")
    # line boxes from the pinned hhea (ascent 1900, descent -500 units):
    # @24 -> round(28.125) = 28 px; @36 -> round(42.1875) = 42 px.
    check(ascent(tf) == 1900.0 && descent(tf) == -500.0,
        "pinned hhea: Roboto ascent 1900 / descent -500")

    # ---- panel D: ellipsis (pinned advances) ----
    f12 = new_font(tf); f12.size = 12f0
    layD = layout_paragraph(
        new_paragraph("MMMMM m", f12; width = 10f0,
            overflow = EllipsisOverflow))
    mD = paragraph_metrics(layD)
    # M@12 = 1788/2048*12 = 10.45 > 10 -> one M per line (5), the space
    # line fits (507 units -> 2.97 px), and the final "m" line (10.49)
    # is replaced by the ellipsis (1370 units -> 8.03 px <= 10): 7 lines.
    check(1788 / 2048 * 12 > 10 && 1370 / 2048 * 12 <= 10,
        "ellipsis decision from pinned advances (10.45 > 10, 8.03 <= 10)")
    check(mD.lineCount == 7, "ellipsis: 7 lines (derived)")
    check(layD.arrangement.runes[end] == UInt32(0x2026),
        "ellipsis: the last line carries U+2026")

    # ---- panel E: fallback and notdef ----
    check(!has_glyph(tf, UInt32(0x0915)),
        "Roboto lacks U+0915 (Devanagari KA)")
    check(has_glyph(tfd, UInt32(0x0915)),
        "NotoSansDevanagari has U+0915")
    fb = with_fallback(tf, [tfd])
    check(fallback_typeface(fb, UInt32(0x0915)) === tfd,
        "the fallback chain resolves U+0915 to NotoSansDevanagari")
    check(isempty(get_glyph_path(tf, UInt32(0x0915)).commands),
        "Roboto's U+0915 outline is empty (no cmap entry)")
    pg = get_glyph_path(fb, UInt32(0x0915))
    check(length(pg.commands) > 50,
        "fallback glyph outline is non-trivial ($(length(pg.commands)) cmds)")
    check(scale(tfd) == 1000.0, "NotoSansDevanagari unitsPerEm = 1000")
    nf = get_glyph_path(tf, UInt32(0x05D0))
    check(isempty(nf.commands),
        "U+05D0 absent in Roboto: empty (notdef) outline")
    check(get_advance(tf, UInt32(0x05D0)) == 908.0,
        "U+05D0 still advances by Roboto's .notdef (908 units)")

    # ---- panel F: opt-in shaping ----
    if VetraGallery.available(VetraGallery.HARBUFF_ID)
        function scriptTag(s::String)
            t = UInt32(0)
            for c in s
                t = (t << 8) | UInt32(c)
            end
            return t
        end
        sh = shape_text(tfA, UInt32[0x0643, 0x062a, 0x0628];
            script = scriptTag("Arab"), direction = RightToLeft,
            language = "ar")
        check([sh[i][1].gid for i in eachindex(sh)] == [424, 59, 36],
            "shaped 'katab' gids match the pinned reference")
        check([sh[i][1].advance for i in eachindex(sh)] ==
            [412.0f0, 373.0f0, 1093.0f0],
            "shaped advances match the pinned reference (font units)")
        check(scale(tfA) == 1000.0, "NotoSansArabic unitsPerEm = 1000")
        fA = new_font(tfA); fA.size = 32f0
        layR = layout_paragraph(new_paragraph("كتب", fA; dir = RightToLeft))
        check(layR.shaped[1] == [3, 2, 1],
            "RTL line reverses cluster order (pinned)")
        # width = the pinned advances summed in Float32 at font size
        # (as test/shaping_tests.jl does): ~60.096 px
        sA = 32f0 / 1000f0
        check(paragraph_metrics(layR).width == 412f0 * sA + 373f0 * sA +
            1093f0 * sA,
            "RTL line width from the pinned advances (412/373/1093)")
    else
        try
            shape_text(tfA, UInt32[0x0643])
            check(false, "core-only: shape_text must raise")
        catch e
            check(e isa ErrorException &&
                occursin("Shaping support is opt-in", e.msg),
                "core-only: shape_text raises the named install hint")
        end
        try
            layout_paragraph(new_paragraph("x", let
                    fA = new_font(tfA); fA.size = 32f0; fA
                end; dir = RightToLeft))
            check(false, "core-only: RTL layout must raise")
        catch e
            check(e isa ErrorException &&
                occursin("Shaping support is opt-in", e.msg),
                "core-only: RTL paragraph raises the named install hint")
        end
    end

    # ---- raster + recorded scene (panels A and B) ----
    img = new_image(W, H)
    scene(img, tf, tfA, tfd)

    rec = PictureRecorder(W, H)
    text_panels(rec.ctx)
    picture = finish_recording!(rec)
    # background + header + 2 panel A labels/text + 1 panel B label +
    # VETRA stroke = 7 ops
    check(length(picture.ops) == 7,
        "recorded text scene is exactly 7 ops (got $(length(picture.ops)))")
    replay = new_image(W, H)
    draw_picture!(replay, picture)
    direct = new_image(W, H)
    text_panels(Context(direct))
    check(replay.data == direct.data,
        "replay of the recorded text scene is byte-identical to direct")

    # ink containment (panel boxes from the hand-derived metrics):
    inband(img, x0, y0, x1, y1, test) = begin
        n = 0
        for y in y0:y1, x in x0:x1
            test(get_color(img, x, y)) && (n += 1)
        end
        return n
    end
    notbg(c) = c != BG
    # panel B: "VETRA"@60 stroked at baseline y=235; line box 55.66 up,
    # 14.64 down + 1.5 stroke margin -> canvas y [178, 251]; x from 30
    # to 30 + 184.16 (pinned V/E/T/R/A advances, no kern) + margin.
    nB = inband(img, 20, 170, 380, 260, notbg)
    check(nB > 1000 && nB < 380 * 90,
        "stroke text: ink present in the VETRA panel band")
    check(inband(img, 1, 1, 28, 440, notbg) == 0,
        "stroke text: no ink left of the panel origin")
    # panel C: line 1 box canvas y [75, 103) (28 px), line 2 [103, 145)
    # (42 px); box x [270, 410).
    nC1 = inband(img, 271, 76, 410, 103, c -> c == INK)
    nC2 = inband(img, 271, 104, 410, 145, c -> c == BLUE)
    check(nC1 > 50 && nC2 > 100,
        "styled paragraph: both bands carry their span color")
    check(inband(img, 271, 76, 410, 103, c -> c == BLUE) == 0,
        "styled paragraph: no blue ink on line 1")
    check(inband(img, 271, 104, 410, 145, c -> c == INK) == 0,
        "styled paragraph: no black ink on line 2")
    # panel E: the fallback glyph ink (magenta) stays in its panel
    nE = inband(img, 40, 270, 150, 360, c -> c.r > 150 && c.g < 100)
    check(nE > 100, "fallback: Devanagari glyph rendered (magenta ink)")
    # panel F: the sub-band rows 340..383 hold only shaped-text ink
    # (the note lines in core-only runs end above it).
    nF = inband(img, 271, 340, 335, 383, notbg)
    if VetraGallery.available(VetraGallery.HARBUFF_ID)
        check(nF > 50, "shaped: RTL line ink present in the panel sub-band")
    else
        check(nF == 0, "core-only: nothing renders in the shaped sub-band")
    end

    # ---- outputs ----
    write_file!(img, joinpath(outdir, "typography.bmp"))
    svg = write_svg!(joinpath(outdir, "typography.svg"), picture)
    check(occursin("<path", svg), "strict SVG: glyph outline paths")
    check(!occursin(r"[0-9][eE][+-]?[0-9]", svg),
        "strict SVG: no exponent-notation numbers")
    pdf = write_pdf!(joinpath(outdir, "typography.pdf"), picture)
    check(startswith(pdf, "%PDF-1.4"), "strict PDF: document header")
    check(!occursin(r"[0-9][eE][+-]?[0-9]", pdf),
        "strict PDF: no exponent-notation numbers")
    return finish("typography", outdir)
end

function main()
    outdir = isempty(ARGS) ? default_outdir() : ARGS[1]
    return run(outdir)
end

if VetraGallery.is_entry(@__FILE__)
    main()
end
