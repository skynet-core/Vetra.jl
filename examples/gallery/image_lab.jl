# image_lab.jl -- E001 gallery program 4: pixel storage and interop,
# the premultiplied/straight alpha boundary, blend math, image effects
# (invert / spread / blur / opacity / crop / rotate / resize / flip),
# native codec exact round trips, optional PNG/JPEG/WebP/ColorTypes with
# explicit matte/lossless policy (JPEG flattens alpha to the explicit
# `background` matte, bounded per block interior; WebP lossless keeps
# alpha), and the current T016 PNG MIME display for notebooks — the
# user-facing call is show(MIME"image/png", img) or a bare img; run()
# returns the check report, never the image (no future live-adapter
# claims).
#
#   julia --project=. examples/gallery/image_lab.jl [outdir]
#
# Outputs in outdir (caller-selected; default artifacts/gallery/):
#   image_lab.bmp     before/after composite (native codec)
#   image_lab.png     same composite (optional PNGFiles)
#   image_lab.webp    smooth gradient, lossless (optional WebP)
#   image_lab.jpg     smooth gradient, quality 92 (optional JpegTurbo)
#
# Generated inputs only: the 4x4 test image and the 32x32 gradient are
# built from constants in this file; no input asset is read or written
# except the pinned GIF fixture (decode demo, read-only). Every
# expectation is hand-derived from the documented contracts:
# - premul/straight: toStraightAlpha min(round(c*255/a), 255) (Float64),
#   rgbx (r*a + 127) div 255 (pinned by test/reference/straight_alpha.tsv
#   and premultiplied_alpha.tsv);
# - blends: the byte formulas of src/blends.jl (pinned by
#   test/reference/blend_*.tsv);
# - blur: separable two-pass Gaussian, per-pass floor(sum div 256) div 255,
#   kernel r = 1 pinned by test/reference/gaussian_kernel.tsv
#   ([4928, 55423, 4928]);
# - GIF: the pinned upstream fixture tests/fileformats/gif/3x5.gif,
#   first-frame bytes compared to the sha-verified test/reference raw.
# Import-safe: including this file defines helpers and run/main and
# renders nothing.
include(joinpath(@__DIR__, "gallery.jl"))
using Vetra
using .VetraGallery

"""The 4x4 test image: every cell a distinct valid premultiplied pixel
(channel <= alpha everywhere)."""
function test_image()
    img = new_image(4, 4)
    rows = [
        [255, 0, 0, 255], [0, 255, 0, 255], [0, 0, 255, 255],
        [128, 128, 128, 128],
        [50, 50, 50, 128], [0, 0, 0, 128], [128, 0, 0, 128],
        [0, 128, 0, 128],
        [200, 200, 0, 200], [0, 0, 200, 200], [200, 0, 0, 200],
        [0, 0, 0, 0],
        [100, 150, 200, 255], [5, 10, 250, 255], [250, 250, 250, 255],
        [0, 0, 0, 255]]
    for (i, px) in enumerate(rows)
        set_color!(img, (i - 1) % 4 + 1, (i - 1) ÷ 4 + 1,
            rgbx(px[1], px[2], px[3], px[4]))
    end
    return img
end

"""Opaque copy of `img` (alpha forced to 255)."""
function opaque_copy(img)
    out = new_image(img.width, img.height)
    copy!(out.data, img.data)
    for i in eachindex(out)
        out.data[4 * (i - 1) + 4] = 0xff
    end
    return out
end

"""Smooth 32x32 gradient (the lossy-codec PSNR subject)."""
function gradient_image()
    img = new_image(32, 32)
    for y in 1:32, x in 1:32
        set_color!(img, x, y,
            rgbx(UInt8(x * 7 % 256), UInt8(255 - (y * 7) % 256), 128, 255))
    end
    return img
end

"""PSNR of two images in straight-alpha space (the codec boundary)."""
function psnr_straight(a::Image, b::Image)
    sq = 0.0
    n = 0
    for i in eachindex(a)
        ca = to_straight_alpha(a[i])
        cb = to_straight_alpha(b[i])
        for f in (:r, :g, :b)
            sq += (Float64(getfield(ca, f)) -
                Float64(getfield(cb, f)))^2
            n += 1
        end
    end
    mse = sq / n
    return mse == 0.0 ? Inf : 10 * log10(255^2 / mse)
end

"""8x exact enlargement (integer scale: draw() samples pixel centers, so
opaque and valid-premul content doubles byte-exactly)."""
enlarge8(img) = resize(img, 8 * img.width, 8 * img.height)

"""The before/after composite (the written artifact)."""
function composite(ctx, img)
    ctx.fillStyle = rgb(248, 250, 252)
    fill_rect!(ctx, 0, 0, 340, 110)
    ctx.font = VetraGallery.ROBOTO
    ctx.fillStyle = rgb(15, 23, 42)
    ctx.fontSize = 14f0
    fill_text!(ctx, "image_lab: original / inverted / 50% opacity",
        20, 24)
    ctx.fontSize = 11f0
    fill_text!(ctx, "spread mask / blur row / rotated", 20, 38)
    panels = [
        img,
        begin
            a = copy(img); invert!(a); a
        end,
        begin
            a = copy(img); apply_opacity!(a, 0.5f0); a
        end,
        begin
            mask = new_image(5, 5)
            set_color!(mask, 3, 3, rgbx(0, 0, 0, 200))
            spread!(mask, 1f0)
            mask
        end,
        begin
            row = new_image(3, 1)
            set_color!(row, 1, 1, rgb(255, 0, 0))
            set_color!(row, 2, 1, rgb(0, 255, 0))
            set_color!(row, 3, 1, rgb(0, 0, 255))
            blur!(row, 1f0)
            row
        end,
        begin
            tr = new_image(2, 3)
            set_color!(tr, 1, 1, rgb(255, 0, 0))
            set_color!(tr, 2, 1, rgb(0, 255, 0))
            set_color!(tr, 1, 2, rgb(0, 0, 255))
            set_color!(tr, 2, 2, rgb(128, 128, 0))
            set_color!(tr, 1, 3, rgb(0, 128, 128))
            set_color!(tr, 2, 3, rgb(128, 0, 128))
            rotate_90(tr)
        end]
    y = 50f0
    for (i, p) in enumerate(panels)
        big = enlarge8(p)
        x = Float32(20 + (i - 1) * 54 + (44 - big.width) ÷ 2)
        draw_image!(ctx, big, x, y + Float32((44 - big.height) ÷ 2))
    end
    return nothing
end

function run(outdir::String)
    reset_checks()
    require_fonts()
    ensure_outdir(outdir)

    # ---- A: storage and interop ----
    v = zeros(UInt8, 64)
    im = Image(4, 4, v)
    check(im.data === v, "Image(w, h, bytes) borrows the supplied vector")
    v[1] = 255
    check(get_color(im, 1, 1).r == 255, "borrowed storage is live (mutation visible)")
    fresh = new_image(4, 4)
    check(fresh.data !== v && all(z -> z == 0, fresh.data),
        "new_image allocates its own zero-initialized storage")
    cp = copy(im)
    check(cp.data !== im.data && cp.data == im.data,
        "copy shares content, not storage")
    cp.data[1] = 0
    check(get_color(im, 1, 1).r == 255, "copying does not alias the source")
    check(im[2, 1] == get_color(im, 1, 2),
        "img[row, col] == getColor(x, y): row 1 = top scanline")
    check(im[5] == im[2, 1], "row-major linear index 5 is pixel (x=1, y=2)")
    check(size(im) == (4, 4), "size: (width, height)")

    # ---- B: premultiplied/straight boundary (hand-derived) ----
    check(to_straight_alpha(rgbx(50, 50, 50, 128)) ==
        rgba(100, 100, 100, 128),
        "straight(50,50,50,128) = 100 = round(50*255/128) (hand-derived)")
    check(rgbx(rgba(100, 100, 100, 128)) == rgbx(50, 50, 50, 128),
        "premul(straight(premul)) is identity on valid premultiplied")
    check(to_premultiplied_alpha(rgba(255, 0, 0, 128)) ==
        rgbx(128, 0, 0, 128),
        "premul(255,0,0,128) = 128 = (255*128+127) div 255 (hand-derived)")
    check(to_straight_alpha(rgbx(0, 0, 0, 0)) == rgba(0, 0, 0, 0),
        "a = 0 maps to fully transparent")
    check(to_straight_alpha(rgbx(255, 255, 0, 200)) ==
        rgba(255, 255, 0, 200),
        "invalid premul clamps: min(round(255*255/200), 255) = 255")

    # ---- C: blend math (documented byte formulas) ----
    check(blend_normal(rgbx(100, 100, 100, 255), rgbx(50, 50, 50, 128)) ==
        rgbx(99, 99, 99, 255),
        "source-over: 50 + 100*127 div 255 = 99 (hand-derived)")
    check(blend_normal(rgbx(1, 2, 3, 42), rgbx(9, 8, 7, 255)) ==
        rgbx(9, 8, 7, 255), "source-over: full-alpha source replaces")
    check(blend_normal(rgbx(9, 8, 7, 0), rgbx(1, 2, 3, 42)) ==
        rgbx(1, 2, 3, 42), "source-over: empty backdrop takes the source")
    check(blend_normal(rgbx(1, 2, 3, 42), rgbx(9, 8, 7, 0)) ==
        rgbx(1, 2, 3, 42), "source-over: zero-alpha source is a no-op")
    check(blend_multiply(rgbx(100, 100, 100, 255), rgbx(50, 50, 50, 255)) ==
        rgbx(19, 19, 19, 255),
        "multiply: (100*50) div 255 = 19 (hand-derived)")
    check(blend_alpha(UInt8(200), UInt8(128)) == 227,
        "alpha combine: 128 + 200*127 div 255 = 227 (hand-derived)")

    # ---- D: image effects (hand-derived byte values) ----
    a = test_image()
    invert!(a)
    check(get_color(a, 1, 1) == rgbx(0, 0, 0, 0),
        "invert: opaque black (255,0,0,255) -> alpha 0, rgb scaled to 0")
    check(get_color(a, 1, 2) == rgbx(102, 102, 102, 127),
        "invert: (50,50,50,128) -> ((205*127+127) div 255, ... , 127) = 102")
    check(get_color(a, 4, 3) == rgbx(255, 255, 255, 255),
        "invert: fully transparent becomes opaque white")
    check(get_color(a, 3, 3) == rgbx(12, 55, 55, 55),
        "invert: (200,0,0,200) -> ((55*55+127) div 255, (255*55+127) div 255, ...)")
    check(get_color(a, 4, 4) == rgbx(0, 0, 0, 0),
        "invert: opaque black stays fully transparent")

    b = test_image()
    apply_opacity!(b, 0.5f0)
    check(get_color(b, 1, 1) == rgbx(128, 0, 0, 128),
        "applyOpacity 0.5: o = round(255*0.5) = 128, c*128 div 255")
    check(get_color(b, 4, 1) == rgbx(64, 64, 64, 64),
        "applyOpacity 0.5: (128,128,128,128) -> (64,64,64,64)")

    mask = new_image(5, 5)
    set_color!(mask, 3, 3, rgbx(0, 0, 0, 200))
    spread!(mask, 1f0)
    check(get_color(mask, 2, 2).a == 200 && get_color(mask, 4, 4).a == 200,
        "spread 1: the 3x3 window around the seed takes its max alpha")
    check(get_color(mask, 1, 1).a == 0 && get_color(mask, 5, 3).a == 0,
        "spread 1: outside the window stays clear")
    check(get_color(mask, 4, 3).a == 200,
        "spread 1: the window edge row is inside")
    check(get_color(mask, 2, 2) == rgbx(0, 0, 0, 200),
        "spread: the result is an alpha-only mask (rgb zeroed)")

    row = new_image(3, 1)
    set_color!(row, 1, 1, rgb(255, 0, 0))
    set_color!(row, 2, 1, rgb(0, 255, 0))
    set_color!(row, 3, 1, rgb(0, 0, 255))
    blur!(row, 1f0)
    # Pinned kernel r=1 [4928, 55423, 4928], per-pass floor(div 256) div 255:
    # X pass: [216,19,0,235] [19,216,19,254] [0,19,216,235];
    # Y pass (h=1, the single row carries weight 55423 only):
    check(get_color(row, 1, 1) == rgbx(183, 16, 0, 199),
        "blur r=1 left: 215*55423 -> 183 (hand-derived, pinned kernel)")
    check(get_color(row, 2, 1) == rgbx(16, 183, 16, 215),
        "blur r=1 center: 215*55423/255/256 = 183 per channel (derived)")
    check(get_color(row, 3, 1) == rgbx(0, 16, 183, 199),
        "blur r=1 right: mirror of the left (derived)")

    src = test_image()
    crop = sub_image(src, 1, 1, 2, 2)
    check(crop.data == [UInt8(x) for x in
        [0x00, 0x00, 0x00, 0x80, 0x80, 0x00, 0x00, 0x80,
        0x00, 0x00, 0xc8, 0xc8, 0xc8, 0x00, 0x00, 0xc8]],
        "sub_image(1,1,2,2): 0-based crop of the (2..3, 2..3) quadrant")
    sup = super_image(src, -1, -1, 6, 6)
    check(sup.data[1:4] == [UInt8(0), UInt8(0), UInt8(0), UInt8(0)],
        "super_image: the out-of-bounds corner is transparent")
    check(get_color(sup, 2, 2) == get_color(src, 1, 1),
        "super_image: the content shifts by (-1, -1)")
    tr = new_image(2, 3)
    for (i, c) in enumerate([rgb(255, 0, 0), rgb(0, 255, 0),
        rgb(0, 0, 255), rgb(128, 128, 0), rgb(0, 128, 128),
        rgb(128, 0, 128)])
        set_color!(tr, (i - 1) % 2 + 1, (i - 1) ÷ 2 + 1, c)
    end
    rot = rotate_90(tr)
    check(size(rot) == (2, 3), "rotate_90: 2x3 (w x h) becomes 3x2")
    # out(x, y) = in(y, 4 - x): row 1 = source column 1 bottom-up
    check(get_color(rot, 1, 1) == rgbx(0, 128, 128, 255) &&
        get_color(rot, 2, 1) == rgbx(0, 0, 255, 255) &&
        get_color(rot, 3, 1) == rgbx(255, 0, 0, 255),
        "rotate_90: first row is the source's first column, bottom-up")
    check(get_color(rot, 1, 2) == rgbx(128, 0, 128, 255) &&
        get_color(rot, 2, 2) == rgbx(128, 128, 0, 255) &&
        get_color(rot, 3, 2) == rgbx(0, 255, 0, 255),
        "rotate_90: second row is the source's second column, bottom-up")
    dbl = resize(src, 8, 8)
    check(dbl.data == repeateach4(src),
        "resize 2x: integer scale duplicates each pixel exactly")
    same = resize(src, 4, 4)
    check(same.data == src.data && same.data !== src.data,
        "resize to the same size: a copy, not the source")
    fh = test_image()
    flip_horizontal!(fh)
    check(get_color(fh, 1, 1) == get_color(src, 4, 1),
        "flip_horizontal!: first column becomes the last")
    fv = test_image()
    flip_vertical!(fv)
    check(get_color(fv, 1, 1) == get_color(src, 1, 4),
        "flip_vertical!: first row becomes the last")

    # ---- E: native codecs ----
    q = decode_qoi(Vector{UInt8}(encode_qoi(opaque_copy(src))))
    check(new_image(q).data == opaque_copy(src).data,
        "QOI: opaque round trip through the public new_image(Qoi) is " *
        "byte-exact")
    q2 = decode_qoi(Vector{UInt8}(encode_qoi(src)))
    check(q2.data[13:16] == [UInt8(255), UInt8(255), UInt8(255), UInt8(128)],
        "QOI: the file is straight RGBA — pixel (4,1) (128,128,128,128) " *
        "stored premul reads back as straight (255,255,255,128)")
    check(new_image(q2).data == src.data,
        "QOI: new_image(Qoi) converts the straight file back to the " *
        "valid premul storage, byte-exact (Linear colorspace, no " *
        "sRGB-linearization pass)")
    bmp = decode_bmp(Vector{UInt8}(encode_bmp(src)))
    check(bmp.data == src.data,
        "BMP: round trip is byte-exact with alpha — the 32-bit file " *
        "boundary is straight RGBA (encode toStraightAlpha, decode " *
        "rgbx(rgba(...))); exact on valid premul storage")
    ppm = decode_ppm(Vector{UInt8}(encode_ppm(src)))
    expect_ppm = opaque_copy(src).data
    check(ppm.data == expect_ppm,
        "PPM: lossless on rgb, alpha dropped to opaque (documented)")
    gif = decode_gif(read(joinpath(
        VetraGallery.ROOT, ".reference", "upstream", "tests", "fileformats",
        "gif", "3x5.gif")))
    check(length(gif.frames) > 0 &&
        (width(gif.frames[1]), height(gif.frames[1])) == (3, 5),
        "GIF: the pinned 3x5 fixture decodes with the right dimensions")
    check(gif.frames[1].data == read(joinpath(
        VetraGallery.ROOT, "test", "reference", "gif_3x5_gif.raw")),
        "GIF: first frame matches the pinned oracle bytes")

    # ---- F: optional providers (honest availability branches) ----
    png_ok = VetraGallery.available(VetraGallery.PNG_ID)
    jpeg_ok = VetraGallery.available(VetraGallery.JPEG_ID)
    webp_ok = VetraGallery.available(VetraGallery.WEBP_ID)
    ct_ok = VetraGallery.available(VetraGallery.COLORTYPES_ID)

    grad = gradient_image()
    if png_ok
        p = decode_png(Vector{UInt8}(encode_png(src)))
        check(p.data == src.data,
            "PNG: lossless round trip is byte-exact, valid premul with alpha")
        check(showable(MIME"image/png"(), src),
            "T016: showable(MIME\"image/png\") reports PNGFiles availability")
        # The user-facing notebook call is show(MIME"image/png", img) —
        # or a bare img, which the MIME method serves. run() itself
        # returns the check report, never the image.
        buf = IOBuffer()
        snap = copy(src.data)
        show(buf, MIME"image/png"(), src)
        check(buf.data[1:buf.size] == encode_png(src),
            "T016: show to an IO is exactly the encode_png bytes")
        check(src.data == snap, "T016: show does not mutate the source")
        check(showable(MIME"text/plain"(), src),
            "T016: the text/plain fallback is always available")
    else
        check(!showable(MIME"image/png"(), src),
            "core-only: showable(MIME\"image/png\") is false")
        buf = IOBuffer()
        try
            show(buf, MIME"image/png"(), src)
            check(false, "core-only: show must raise")
        catch e
            check(e isa ErrorException &&
                occursin("PNG support is opt-in", e.msg),
                "core-only: show raises the named PNG install hint")
        end
        try
            encode_png(src)
            check(false, "core-only: encode_png must raise")
        catch e
            check(e isa ErrorException &&
                occursin("PNG support is opt-in", e.msg),
                "core-only: encode_png raises the named PNG install hint")
        end
    end
    if jpeg_ok
        j = decode_jpeg(Vector{UInt8}(encode_jpeg(grad; quality = 92)))
        check(size(j) == (32, 32), "JPEG: dimensions exact at q92")
        check(psnr_straight(grad, j) >= 40.0,
            "JPEG: PSNR >= 40 dB on the opaque smooth gradient (lossy: " *
            "no exact-equality assertion, quality bound instead)")
        # alpha flattening: JPEG has no alpha channel — encode_jpeg's
        # explicit `background` matte is flattened into an all-opaque
        # frame. Block-separated 16x1 layout (left 8 px opaque, right 8 px
        # transparent) so each 8x8 DCT block is uniform; only the two
        # boundary-adjacent pixels (x = 8, 9) carry block-edge loss.
        jm = new_image(16, 1)
        for x in 1:8
            set_color!(jm, x, 1, rgb(200, 30, 40))
        end
        for x in 9:16
            set_color!(jm, x, 1, rgba(0, 0, 0, 0))
        end
        out = decode_jpeg(
            Vector{UInt8}(encode_jpeg(jm; quality = 92,
                background = rgb(210, 190, 60))))
        check(all(get_color(out, x, 1).a == 255 for x in 1:16),
            "JPEG: the matte flatten is total — every output pixel is " *
            "fully opaque (a = 255)")
        l = get_color(out, 4, 1)
        check(max(abs(Int(l.r) - 200), abs(Int(l.g) - 30),
            abs(Int(l.b) - 40)) <= 2,
            "JPEG: opaque-block interior (4,1) within 2 channels of " *
            "(200,30,40) (measured 1; lossy bound, not equality)")
        mt = get_color(out, 12, 1)
        check(max(abs(Int(mt.r) - 210), abs(Int(mt.g) - 190),
            abs(Int(mt.b) - 60)) <= 2,
            "JPEG: matte-block interior (12,1) within 2 channels of the " *
            "background rgb(210,190,60) (measured 1; lossy bound)")
    else
        try
            encode_jpeg(grad)
            check(false, "core-only: encode_jpeg must raise")
        catch e
            check(e isa ErrorException &&
                occursin("JPEG support is opt-in", e.msg),
                "core-only: encode_jpeg raises the named JpegTurbo hint")
        end
    end
    if webp_ok
        wl = decode_webp(Vector{UInt8}(encode_webp(src; lossy = false)))
        check(wl.data == src.data,
            "WebP lossless: byte-exact round trip, alpha preserved " *
            "(no matte involved)")
        wy = decode_webp(
            Vector{UInt8}(encode_webp(grad; lossy = true, quality = 75)))
        check(size(wy) == (32, 32) && psnr_straight(grad, wy) >= 35.0,
            "WebP lossy: PSNR >= 35 dB on the gradient (quality bound)")
    else
        try
            encode_webp(src)
            check(false, "core-only: encode_webp must raise")
        catch e
            check(e isa ErrorException &&
                occursin("WebP support is opt-in", e.msg),
                "core-only: encode_webp raises the named WebP hint")
        end
    end
    if ct_ok
        m = to_colors(src)
        check(size(m) == (4, 4), "ColorTypes: the matrix is [row, col]")
        check(m[2, 1].r.i == 100,
            "ColorTypes: (50,50,50,128) exports as straight (100,...) N0f8")
        check(m[4, 1].alpha.i == 255,
            "ColorTypes: the opaque row keeps alpha 255")
        back = from_colors(m)
        check(back.data == src.data,
            "ColorTypes: from_colors(to_colors) is exact on valid premul")
        view = Base.view(m, 1:2, :)
        check(from_colors(view).width == 4,
            "ColorTypes: range views are accepted (the result is a " *
            "fresh copy, per the README matrix)")
    else
        try
            to_colors(src)
            check(false, "core-only: to_colors must raise")
        catch e
            check(e isa ErrorException &&
                occursin("Color-matrix interop is opt-in", e.msg),
                "core-only: to_colors raises the named ColorTypes hint")
        end
    end

    # ---- artifact: before/after composite ----
    canvas = new_image(340, 110)
    composite(Context(canvas), src)
    write_file!(canvas, joinpath(outdir, "image_lab.bmp"))
    if png_ok
        write_file!(canvas, joinpath(outdir, "image_lab.png"))
    end
    if webp_ok
        write_file!(grad, joinpath(outdir, "image_lab.webp"))
    end
    if jpeg_ok
        write_file!(grad, joinpath(outdir, "image_lab.jpg"))
    end
    return finish("image_lab", outdir)
end

function main()
    outdir = isempty(ARGS) ? default_outdir() : ARGS[1]
    return run(outdir)
end

# repeateach4: 2x pixel duplication per row/column (the exact-2x resize
# pattern)
function repeateach4(img::Image)
    w = img.width
    h = img.height
    d = img.data
    out = Vector{UInt8}(undef, length(d) * 4)
    for y in 0:(h - 1), x in 0:(w - 1)
        s = 4 * (y * w + x)
        for (ox, oy) in [(0, 0), (1, 0), (0, 1), (1, 1)]
            o = 4 * ((2 * y + oy) * (2 * w) + (2 * x + ox))
            for k in 0:3
                out[o + 1 + k] = d[s + 1 + k]
            end
        end
    end
    return out
end

if VetraGallery.is_entry(@__FILE__)
    main()
end
