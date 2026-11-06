# T007a: image drawing ops -- draw fixture parity (draw_translate.raw,
# draw_scale2.raw, 0 mismatching bytes), drawTiled, getRgbaSmooth,
# minifyBy2/magnifyBy2, applyOpacity, subImage, blendRect, and the
# Context.drawImage wrappers. All hand-derived values come from the pinned
# upstream formulas (images.nim/common.nim) or the fixture constructions --
# never from the code under test.

@testset "T007a draw fixture parity (exact bytes)" begin
    @testset "draw_translate (fast blendRect path)" begin
        dst = newImage(8, 6)
        fill(dst, rgbx(255, 255, 255, 255))
        src = newImage(4, 3)
        fill(src, rgbx(100, 50, 25, 128))
        draw(dst, src, translate(Vec2(Float32(2), Float32(1))))
        ref, wh = VetraRef.read_raw("draw_translate")
        @test wh == (8, 6)
        @test VetraRef.compare_pixels(dst.data, ref, wh).count == 0
    end

    @testset "draw_scale2 (smooth path, 2x scale)" begin
        dst = newImage(16, 12)
        fill(dst, rgbx(255, 255, 255, 255))
        src = newImage(2, 2)
        fill(src, rgbx(255, 0, 0, 255))
        draw(dst, src, translate(Vec2(Float32(6), Float32(8))) *
            scale(Vec2(Float32(2), Float32(2))))
        ref, wh = VetraRef.read_raw("draw_scale2")
        @test wh == (16, 12)
        @test VetraRef.compare_pixels(dst.data, ref, wh).count == 0
    end
end

@testset "T007a draw hand-derived cases" begin
    pxv = (img, x, y) -> (c = getColor(img, x, y);
        (Int(c.r), Int(c.g), Int(c.b), Int(c.a)))

    """Message of the error `f` throws ("" when it does not)."""
    function caughtErrMsg(f)
        try
            f()
            return ""
        catch e
            return sprint(showerror, e)
        end
    end

    @testset "blendRect fast path" begin
        b = newImage(2, 2)
        setColor(b, 1, 1, rgbx(10, 20, 30, 255))
        setColor(b, 2, 1, rgbx(40, 50, 60, 255))
        setColor(b, 1, 2, rgbx(70, 80, 90, 255))
        setColor(b, 2, 2, rgbx(100, 110, 120, 255))
        # identity: full copy (a = 255 -> source-over returns the source)
        c0 = newImage(2, 2)
        draw(c0, b)
        @test pxv(c0, 1, 1) == (10, 20, 30, 255)
        @test pxv(c0, 2, 2) == (100, 110, 120, 255)

        # opaque Overwrite at (1,1): only pixel (2,2) of a changes;
        # blendRect blits b(0,0) onto a (pos) (draw_translate.meta rule)
        c = newImage(2, 2)
        fill(c, rgbx(255, 255, 255, 255))
        draw(c, b, translate(Vec2(Float32(1), Float32(1)));
            blendMode = OverwriteBlend)
        @test pxv(c, 2, 2) == (10, 20, 30, 255)
        @test pxv(c, 1, 1) == (255, 255, 255, 255)

        # semi-opaque Normal over white: c = s + 255*127 div 255
        d = newImage(3, 3)
        fill(d, rgbx(255, 255, 255, 255))
        e = newImage(1, 1)
        fill(e, rgbx(10, 20, 30, 128))
        draw(d, e, translate(Vec2(Float32(1), Float32(1))))
        @test pxv(d, 2, 2) == (137, 147, 157, 255)
        @test pxv(d, 1, 1) == (255, 255, 255, 255)
    end

    @testset "drawSmooth fractional translation (bilinear edge, hand-derived)" begin
        # 1x1 opaque red at (0.5, 0.0) over a white 2x1: each column sees a
        # half-blend with the transparent side, then over the white backdrop.
        dst = newImage(2, 1)
        fill(dst, rgbx(255, 255, 255, 255))
        src = newImage(1, 1)
        fill(src, rgbx(255, 0, 0, 255))
        draw(dst, src, translate(Vec2(Float32(0.5), Float32(0))))
        # mix(a, b, 0.5) = (a*127 + b*128 + 127) div 255 per channel
        # (upstream common.nim). Left: mix(0, red) -> r = 128, a = 128;
        # right: mix(red, 0) -> r = (255*127 + 127) div 255 = 127, a = 127.
        # Then Normal over white: c = s + (255 * k) div 255, k = 255 - s.a:
        # left  -> 255, g = 0 + 127   (255, 127, 127, 255)
        # right -> 255, g = 0 + 128   (255, 128, 128, 255)
        @test pxv(dst, 1, 1) == (255, 127, 127, 255)
        @test pxv(dst, 2, 1) == (255, 128, 128, 255)
    end

    @testset "drawTiled (wrapped sampling, hand-derived)" begin
        strip = newImage(2, 1)
        setColor(strip, 1, 1, rgbx(10, 20, 30, 255))
        setColor(strip, 2, 1, rgbx(70, 80, 90, 255))
        # identity: the 2x1 pattern repeats across both rows
        d = newImage(4, 2)
        drawTiled(d, strip)
        for y in 1:2
            @test pxv(d, 1, y) == (10, 20, 30, 255)
            @test pxv(d, 2, y) == (70, 80, 90, 255)
            @test pxv(d, 3, y) == (10, 20, 30, 255)
            @test pxv(d, 4, y) == (70, 80, 90, 255)
        end
        # translated by 1: the pattern shifts, negative x wraps
        d2 = newImage(4, 1)
        drawTiled(d2, strip, translate(Vec2(Float32(1), Float32(0))))
        @test pxv(d2, 1, 1) == (70, 80, 90, 255)
        @test pxv(d2, 2, 1) == (10, 20, 30, 255)
        @test pxv(d2, 3, 1) == (70, 80, 90, 255)
        @test pxv(d2, 4, 1) == (10, 20, 30, 255)
        # scale 2x: magnify duplicates each pixel 2 -> both rows A A B B
        d3 = newImage(4, 2)
        drawTiled(d3, strip, scale(Vec2(Float32(2), Float32(2))))
        for y in 1:2
            @test pxv(d3, 1, y) == (10, 20, 30, 255)
            @test pxv(d3, 2, y) == (10, 20, 30, 255)
            @test pxv(d3, 3, y) == (70, 80, 90, 255)
            @test pxv(d3, 4, y) == (70, 80, 90, 255)
        end
        # scale 0.5: minify averages the 1x2 block (height 1 -> odd row
        # arm), then the 1x1 result tiles everywhere:
        # (10+70+2) div 4 = 0x14, (20+80+2) div 4 = 25,
        # (30+90+2) div 4 = 30, (255+255+2) div 4 = 128 -> then the odd-row
        # arm mixes the same pair * 0.5 -> (20, 25, 30, 128)
        d4 = newImage(2, 2)
        drawTiled(d4, strip, scale(Vec2(Float32(0.5), Float32(0.5))))
        for y in 1:2
            @test pxv(d4, 1, y) == (20, 25, 30, 128)
            @test pxv(d4, 2, y) == (20, 25, 30, 128)
        end
    end

    @testset "draw dispatch errors" begin
        a = newImage(2, 2)
        b = newImage(2, 2)
        # unknown blend mode -> "unknown blend mode"
        @test_throws ArgumentError draw(a, b, mat3(); blendMode = BlendMode(20))
        @test occursin("unknown blend mode",
            caughtErrMsg(() -> draw(a, b, mat3(); blendMode = BlendMode(20))))
        # mask pixel modes dispatch through blender (T007b), hand-derived:
        # subtract: a = 128 * (255 - 128) div 255 = 63; 100*63 div 255 = 24
        # etc. (same hand-check as the blendSubtractMask table)
        d = newImage(1, 1)
        fill(d, rgbx(100, 50, 25, 128))
        s = newImage(1, 1)
        fill(s, rgbx(20, 40, 60, 128))
        draw(d, s, mat3(); blendMode = SubtractMaskBlend)
        @test pxv(d, 1, 1) == (24, 12, 6, 63)
        d = newImage(1, 1)
        fill(d, rgbx(100, 50, 25, 128))
        draw(d, s, mat3(); blendMode = ExcludeMaskBlend)
        @test pxv(d, 1, 1) == (0, 0, 0, 0)   # alpha band 128 - 128 = 0
        # tiled: blendMask scales the white backdrop by the pattern alpha
        t = newImage(2, 1)
        setColor(t, 1, 1, rgbx(200, 200, 200, 200))
        setColor(t, 2, 1, rgbx(120, 120, 120, 120))
        d = newImage(2, 1)
        fill(d, rgbx(255, 255, 255, 255))
        drawTiled(d, t; blendMode = MaskBlend)
        @test pxv(d, 1, 1) == (200, 200, 200, 200)
        @test pxv(d, 2, 1) == (120, 120, 120, 120)
        @test_throws ArgumentError Vetra.blendRect(a, b, (0, 0), BlendMode(20))
        @test occursin("unknown blend mode",
            caughtErrMsg(() -> Vetra.blendRect(a, b, (0, 0), BlendMode(20))))
    end
end

@testset "T007a sampling and resize ops" begin
    pxv = (img, x, y) -> (c = getColor(img, x, y);
        (Int(c.r), Int(c.g), Int(c.b), Int(c.a)))

    # 2x2 with distinct premultiplied pixels (upstream `image[x, y]` grid)
    g = newImage(2, 2)
    setColor(g, 1, 1, rgbx(10, 20, 30, 255))
    setColor(g, 2, 1, rgbx(40, 50, 60, 255))
    setColor(g, 1, 2, rgbx(70, 80, 90, 255))
    setColor(g, 2, 2, rgbx(100, 110, 120, 255))

    @testset "getRgbaSmooth (float coords, 0-based)" begin
        # integer coords -> the exact pixel (no mix); pixel (x, y) 1-based is
        # float (x - 1, y - 1)
        @test Vetra.getRgbaSmooth(g, 0f0, 1f0) == rgbx(70, 80, 90, 255)
        @test Vetra.getRgbaSmooth(g, 1f0, 0f0) == rgbx(40, 50, 60, 255)
        # half pixel: mix each row x-then-y with t = 0.5 (x = 128):
        # row1: (10,20,30)->(40,50,60) -> (25, 35, 45, 255)
        # row2: (70,80,90)->(100,110,120) -> (85, 95, 105, 255)
        # blend rows with t = 0.5 -> (55.6, 65.6, 75.6) -> (55, 65, 75)
        @test Vetra.getRgbaSmooth(g, 0.5f0, 0.5f0) == rgbx(55, 65, 75, 255)
        # out-of-bounds reads are transparent
        @test Vetra.getRgbaSmooth(g, 3f0, 1f0) == rgbx(0, 0, 0, 0)
        @test Vetra.getRgbaSmooth(g, 1f0, 3f0) == rgbx(0, 0, 0, 0)
        @test Vetra.getRgbaSmooth(g, -1f0, 1f0) == rgbx(0, 0, 0, 0)
        # wrapped sampling reads modulo the image: (2, 0) -> pixel (1, 1)...
        @test Vetra.getRgbaSmooth(g, 2f0, 0f0, true) == rgbx(10, 20, 30, 255)
        # ...and -1 wraps modulo the extent like +1: (-1, 1) == (1, 1) 0-based
        @test Vetra.getRgbaSmooth(g, -1f0, 1f0, true) == rgbx(100, 110, 120, 255)
    end

    @testset "minifyBy2" begin
        a = newImage(2, 2)
        setColor(a, 1, 1, rgbx(4, 8, 12, 16))
        setColor(a, 2, 1, rgbx(20, 24, 28, 32))
        setColor(a, 1, 2, rgbx(60, 64, 68, 72))
        setColor(a, 2, 2, rgbx(40, 44, 48, 52))
        m = minifyBy2(a)
        @test (width(m), height(m)) == (1, 1)
        # (sum + 2) div 4 per channel: (124+2) div 4 = 31 etc.
        @test pxv(m, 1, 1) == (31, 35, 39, 43)

        # odd 3x3 red grid: center block sum, odd column mix*0.5,
        # odd row mix*0.5, odd corner p * 0.25
        # in:   10  20  30
        #       40  50  60
        #       90 100 120        (opaque red channel values)
        b = newImage(3, 3)
        for (y, row) in enumerate([[10, 20, 30], [40, 50, 60], [90, 100, 120]])
            for (x, v) in enumerate(row)
                setColor(b, x, y, rgbx(v, 0, 0, 255))
            end
        end
        m2 = minifyBy2(b)
        @test (width(m2), height(m2)) == (2, 2)
        # center: (10+20+50+40+2) div 4 = 30 (a = 255)
        # odd col: mix(30, 60, 0.5) = 45 -> *0.5 -> 23 (a: 255 -> 128)
        @test pxv(m2, 1, 1) == (30, 0, 0, 255)
        @test pxv(m2, 2, 1) == (23, 0, 0, 128)
        # odd row: mix(90, 100, 0.5) = 95 -> *0.5 -> 48
        # corner: 120 * 0.25 -> 30 (a: 255 * round(0.25*255 = 64) div 255 = 64)
        @test pxv(m2, 1, 2) == (48, 0, 0, 128)
        @test pxv(m2, 2, 2) == (30, 0, 0, 64)

        # power = 2: uniform values survive two averaging passes:
        # (4v + 2) div 4 = v for v in (4, 8, 13, 16)
        c4 = newImage(4, 4)
        fill(c4, rgbx(4, 8, 13, 16))
        m3 = minifyBy2(c4, 2)
        @test (width(m3), height(m3)) == (1, 1)
        @test pxv(m3, 1, 1) == (4, 8, 13, 16)

        @test minifyBy2(a, 0) !== a && minifyBy2(a, 0).data == a.data
        @test_throws ArgumentError minifyBy2(a, -1)
    end

    @testset "magnifyBy2" begin
        a = newImage(2, 2)
        setColor(a, 1, 1, rgbx(1, 2, 3, 4))
        setColor(a, 2, 1, rgbx(5, 6, 7, 8))
        setColor(a, 1, 2, rgbx(9, 10, 11, 12))
        setColor(a, 2, 2, rgbx(13, 14, 15, 16))
        mg = magnifyBy2(a)
        @test (width(mg), height(mg)) == (4, 4)
        @test pxv(mg, 1, 1) == (1, 2, 3, 4)
        @test pxv(mg, 2, 2) == (1, 2, 3, 4)  # duplicated block
        # output (col 3, row 3) -> source pixel (2, 2)
        @test pxv(mg, 3, 3) == (13, 14, 15, 16)
        @test pxv(mg, 3, 1) == (5, 6, 7, 8)   # output (col 3, row 1) -> source (2, 1)
        @test pxv(mg, 4, 4) == (13, 14, 15, 16)
        # power = 2: 1x1 duplicates to 4x4
        one = newImage(1, 1)
        fill(one, rgbx(7, 7, 7, 7))
        mg2 = magnifyBy2(one, 2)
        @test (width(mg2), height(mg2)) == (4, 4)
        @test pxv(mg2, 4, 4) == (7, 7, 7, 7)
        @test magnifyBy2(a, 0) !== a && magnifyBy2(a, 0).data == a.data
        @test_throws ArgumentError magnifyBy2(a, -1)
    end

    @testset "applyOpacity" begin
        a = newImage(1, 1)
        fill(a, rgbx(4, 8, 16, 255))
        o = copy(a)
        applyOpacity(o, 0.5f0)
        # c * round(255 * 0.5) div 255 = c * 128 div 255
        @test pxv(o, 1, 1) == (2, 4, 8, 128)
        o = copy(a)
        applyOpacity(o, 0.25f0)
        # x = round(255 * 0.25) = 64 -> (c * 64) div 255
        @test pxv(o, 1, 1) == (1, 2, 4, 64)
        o = copy(a)
        applyOpacity(o, 1.0f0)
        @test pxv(o, 1, 1) == (4, 8, 16, 255)  # identity
        o = copy(a)
        applyOpacity(o, 0f0)
        @test pxv(o, 1, 1) == (0, 0, 0, 0)     # cleared
    end

    @testset "subImage" begin
        a = newImage(4, 3)
        for y in 1:3
            for x in 1:4
                setColor(a, x, y, rgbx(x * 10, y * 10, x + y, 255))
            end
        end
        # 0-based origin (1, 0): rows 1..2, cols 2..3 (1-based)
        s = subImage(a, 1, 0, 2, 2)
        @test (width(s), height(s)) == (2, 2)
        @test pxv(s, 1, 1) == (20, 10, 3, 255)
        @test pxv(s, 2, 1) == (30, 10, 4, 255)
        @test pxv(s, 1, 2) == (20, 20, 4, 255)
        @test pxv(s, 2, 2) == (30, 20, 5, 255)
        # the whole image
        w = subImage(a, 0, 0, 4, 3)
        @test w.data == a.data
        # invalid params raise (upstream PixieError)
        @test_throws ArgumentError subImage(a, -1, 0, 1, 1)
        @test_throws ArgumentError subImage(a, 3, 0, 2, 1)  # x + w > width
        @test_throws ArgumentError subImage(a, 0, -1, 1, 1)
        @test_throws ArgumentError subImage(a, 0, 2, 1, 2)  # y + h > height
        @test_throws ArgumentError subImage(a, 0, 0, 0, 1)  # zero size
    end

    @testset "blendRect branches" begin
        # MaskBlend: uncovered areas cleared, covered area scaled by mask a
        a = newImage(4, 4)
        fill(a, rgbx(255, 255, 255, 255))
        mask = newImage(2, 2)
        fill(mask, rgbx(128, 128, 128, 128))
        Vetra.blendRect(a, mask, (1, 1), MaskBlend)
        @test pxv(a, 2, 2) == (128, 128, 128, 128)  # 255 * 128 div 255
        @test pxv(a, 3, 2) == (128, 128, 128, 128)
        @test pxv(a, 3, 3) == (128, 128, 128, 128)
        @test pxv(a, 1, 2) == (0, 0, 0, 0)          # uncovered -> cleared
        @test pxv(a, 3, 4) == (0, 0, 0, 0)
        @test pxv(a, 1, 1) == (0, 0, 0, 0)
        @test pxv(a, 4, 4) == (0, 0, 0, 0)

        # fully outside + MaskBlend clears the whole destination
        b = newImage(4, 4)
        fill(b, rgbx(255, 255, 255, 255))
        Vetra.blendRect(b, mask, (10, 10), MaskBlend)
        @test pxv(b, 1, 1) == (0, 0, 0, 0)
        # fully outside + NormalBlend is a no-op
        c = newImage(4, 4)
        fill(c, rgbx(255, 255, 255, 255))
        Vetra.blendRect(c, mask, (10, 10), NormalBlend)
        @test pxv(c, 1, 1) == (255, 255, 255, 255)

        # partial negative overlap: only the in-bounds square copies (a = 255)
        d = newImage(4, 4)
        fill(d, rgbx(255, 255, 255, 255))
        e = newImage(2, 2)
        fill(e, rgbx(10, 20, 30, 255))
        Vetra.blendRect(d, e, (-1, -1), NormalBlend)
        @test pxv(d, 1, 1) == (10, 20, 30, 255)
        @test pxv(d, 2, 1) == (255, 255, 255, 255)
        @test pxv(d, 1, 2) == (255, 255, 255, 255)
        # non-W3C dispatch: multiply = s + b * (255 - s.a) div 255; with the
        # opaque source (255) the backdrop term is zero -> source verbatim
        f = newImage(1, 1)
        fill(f, rgbx(255, 255, 255, 255))
        Vetra.blendRect(f, e, (0, 0), MultiplyBlend)
        @test pxv(f, 1, 1) == (10, 20, 30, 255)
        # semi-opaque source: 155 + src channel (upstream formula)
        f2 = newImage(1, 1)
        fill(f2, rgbx(255, 255, 255, 255))
        e2 = newImage(1, 1)
        fill(e2, rgbx(100, 50, 25, 100))
        Vetra.blendRect(f2, e2, (0, 0), MultiplyBlend)
        @test pxv(f2, 1, 1) == (255, 205, 180, 255)
    end

    @testset "drawImage (Context wrappers, hand-derived)" begin
        # 2-arg form: identity scale, opaque source lands verbatim via
        # the ImagePaint fillPath path
        ctx = Context(newImage(4, 4))
        fill(ctx.image, rgbx(255, 255, 255, 255))
        src = newImage(2, 2)
        setColor(src, 1, 1, rgbx(10, 20, 30, 255))
        setColor(src, 2, 1, rgbx(40, 50, 60, 255))
        setColor(src, 1, 2, rgbx(70, 80, 90, 255))
        setColor(src, 2, 2, rgbx(100, 110, 120, 255))
        drawImage(ctx, src, Float32(1), Float32(1))
        @test pxv(ctx.image, 2, 2) == (10, 20, 30, 255)
        @test pxv(ctx.image, 3, 3) == (100, 110, 120, 255)
        @test pxv(ctx.image, 1, 1) == (255, 255, 255, 255)
        @test pxv(ctx.image, 4, 1) == (255, 255, 255, 255)
        # the fill style is restored afterwards
        @test ctx.fillStyle isa Paint &&
            ctx.fillStyle.color == ColorRGBA(0, 0, 0, 0xff)

        # 9-arg form: subImage(source, 0-based origin) then blit at (dx, dy);
        # sx = sy = 1 selects src2 1-based block (2..3, 2..3)
        src2 = newImage(4, 4)
        for y in 1:4
            for x in 1:4
                setColor(src2, x, y, rgbx((x - 1) * 10 + 1, 0, (y - 1) * 10 + 1, 255))
            end
        end
        ctx2 = Context(newImage(4, 4))
        fill(ctx2.image, rgbx(255, 255, 255, 255))
        drawImage(ctx2, src2,
            1f0, 1f0, 2f0, 2f0,   # sx, sy, sw, sh (0-based origin)
            0f0, 0f0, 2f0, 2f0)  # dx, dy, dw, dh
        @test pxv(ctx2.image, 1, 1) == (11, 0, 11, 255)   # src2 (2, 2)
        @test pxv(ctx2.image, 2, 1) == (21, 0, 11, 255)   # src2 (3, 2)
        @test pxv(ctx2.image, 1, 2) == (11, 0, 21, 255)   # src2 (2, 3)
        @test pxv(ctx2.image, 2, 2) == (21, 0, 21, 255)   # src2 (3, 3)
        @test pxv(ctx2.image, 3, 3) == (255, 255, 255, 255)
    end
end

# T007b: image effects -- gaussianKernel fixture parity (radii 1..16) and
# hand-derived cases for blur (pinned truncation points), spread, shadow,
# flip, rotate90, resize, superImage, opaqueBounds, diff, invert, ceil.
# All expected values come from the pinned upstream formulas
# (images.nim/internal.nim) and gaussian_kernel.tsv, never from the code
# under test.

@testset "T007b image effects" begin
    pxv = (img, x, y) -> (c = getColor(img, x, y);
        (Int(c.r), Int(c.g), Int(c.b), Int(c.a)))

    @testset "gaussianKernel (fixture parity, radii 1..16)" begin
        meta, cols, rows = VetraRef.read_table("gaussian_kernel")
        @test cols == ["radius", "weights..."]
        @test meta["source"] == "pixie internal.nim gaussianKernel"
        @test length(rows) == 16
        nWeights = 0
        for row in rows
            r = parse(Int, row[1])
            k = gaussianKernel(r)
            @test length(k) == 2 * r + 1
            for (i, cell) in enumerate(row[2:end])
                @test k[i] == parse(UInt16, cell)
                nWeights += 1
            end
        end
        @test nWeights == 288
    end

    @testset "flipHorizontal / flipVertical (in place)" begin
        a = newImage(3, 2)
        setColor(a, 1, 1, rgbx(10, 0, 0, 255))
        setColor(a, 2, 1, rgbx(20, 0, 0, 255))
        setColor(a, 3, 1, rgbx(30, 0, 0, 255))
        setColor(a, 1, 2, rgbx(0, 10, 0, 255))
        setColor(a, 2, 2, rgbx(0, 20, 0, 255))
        setColor(a, 3, 2, rgbx(0, 30, 0, 255))
        flipHorizontal(a)
        # halfWidth = 3 div 2 = 1: only the outer columns swap, middle stays
        @test pxv(a, 1, 1) == (30, 0, 0, 255)
        @test pxv(a, 2, 1) == (20, 0, 0, 255)
        @test pxv(a, 3, 1) == (10, 0, 0, 255)
        @test pxv(a, 1, 2) == (0, 30, 0, 255)
        @test pxv(a, 2, 2) == (0, 20, 0, 255)
        @test pxv(a, 3, 2) == (0, 10, 0, 255)

        b = newImage(2, 3)
        setColor(b, 1, 1, rgbx(1, 0, 0, 255))
        setColor(b, 2, 1, rgbx(2, 0, 0, 255))
        setColor(b, 1, 2, rgbx(3, 0, 0, 255))
        setColor(b, 2, 2, rgbx(4, 0, 0, 255))
        setColor(b, 1, 3, rgbx(5, 0, 0, 255))
        setColor(b, 2, 3, rgbx(6, 0, 0, 255))
        flipVertical(b)
        # halfHeight = 3 div 2 = 1: outer rows swap, middle row stays
        @test pxv(b, 1, 1) == (5, 0, 0, 255)
        @test pxv(b, 2, 1) == (6, 0, 0, 255)
        @test pxv(b, 1, 2) == (3, 0, 0, 255)
        @test pxv(b, 2, 2) == (4, 0, 0, 255)
        @test pxv(b, 1, 3) == (1, 0, 0, 255)
        @test pxv(b, 2, 3) == (2, 0, 0, 255)
    end

    @testset "rotate90 (returns the rotated image; source untouched)" begin
        a = newImage(2, 3)
        setColor(a, 1, 1, rgbx(1, 0, 0, 255))
        setColor(a, 2, 1, rgbx(2, 0, 0, 255))
        setColor(a, 1, 2, rgbx(3, 0, 0, 255))
        setColor(a, 2, 2, rgbx(4, 0, 0, 255))
        setColor(a, 1, 3, rgbx(5, 0, 0, 255))
        setColor(a, 2, 3, rgbx(6, 0, 0, 255))
        r = rotate90(a)
        @test (width(r), height(r)) == (3, 2)
        # rotated(x, y) = original(y, h - x + 1)
        @test pxv(r, 1, 1) == (5, 0, 0, 255)
        @test pxv(r, 2, 1) == (3, 0, 0, 255)
        @test pxv(r, 3, 1) == (1, 0, 0, 255)
        @test pxv(r, 1, 2) == (6, 0, 0, 255)
        @test pxv(r, 2, 2) == (4, 0, 0, 255)
        @test pxv(r, 3, 2) == (2, 0, 0, 255)
        @test pxv(a, 1, 1) == (1, 0, 0, 255)
        # four rotations give the original buffer back
        @test rotate90(rotate90(rotate90(rotate90(a)))).data == a.data
    end

    @testset "diff (hand-derived score and image)" begin
        master = newImage(2, 2)
        setColor(master, 1, 1, rgbx(100, 50, 25, 200))
        setColor(master, 2, 1, rgbx(0, 0, 0, 255))
        setColor(master, 1, 2, rgbx(255, 255, 255, 255))
        setColor(master, 2, 2, rgbx(0, 0, 0, 0))
        img = newImage(1, 1)
        setColor(img, 1, 1, rgbx(50, 100, 150, 100))
        score, d = diff(master, img)
        @test (width(d), height(d)) == (2, 2)
        # (1,1): |200-100| = 100; Δrgb = 50 - 50 - 125 = -125 -> g = 0, b = 125
        @test pxv(d, 1, 1) == (100, 0, 125, 255)
        # (2,1): vs transparent -> Δa = 255
        @test pxv(d, 2, 1) == (255, 0, 0, 255)
        # (1,2): Δrgb = +765 clamps to g = 255, b = 0
        @test pxv(d, 1, 2) == (255, 255, 0, 255)
        @test pxv(d, 2, 2) == (0, 0, 0, 255)
        # score = 100 * (325 + 255 + 1020 + 0) / (4 * 4 * 255), Float32
        @test score == Float32(100) * Float32(1600) / Float32(4080)
        # identical images score 0
        s2, _ = diff(master, copy(master))
        @test s2 == Float32(0)
    end

    @testset "invert (in place, re-premultiplied)" begin
        a = newImage(3, 1)
        setColor(a, 1, 1, rgbx(50, 100, 150, 200))
        setColor(a, 2, 1, rgbx(10, 20, 30, 255))
        setColor(a, 3, 1, rgbx(0, 0, 0, 0))
        invert(a)
        # 255-c, then (c * a + 127) div 255 with a = 55:
        # (205*55+127) div 255 = 44, (155*55+127) div 255 = 33,
        # (105*55+127) div 255 = 23
        @test pxv(a, 1, 1) == (44, 33, 23, 55)
        # a = 255 - 255 = 0: (c * 0 + 127) div 255 = 0 (straight channels
        # with no alpha are nothing)
        @test pxv(a, 2, 1) == (0, 0, 0, 0)
        # a = 255 - 0 = 255: re-premultiply is the identity
        @test pxv(a, 3, 1) == (255, 255, 255, 255)
    end

    @testset "ceil (in place; Base.ceil untouched)" begin
        a = newImage(2, 1)
        setColor(a, 1, 1, rgbx(0, 12, 255, 0))
        setColor(a, 2, 1, rgbx(1, 0, 0, 1))
        ceil(a)
        @test pxv(a, 1, 1) == (0, 255, 255, 0)
        @test pxv(a, 2, 1) == (255, 0, 0, 255)
        @test ceil(Float32(1.2)) == Float32(2)
    end

    @testset "blur (pinned truncation, hand-derived)" begin
        # 5x1 opaque black row; the r=1 kernel is (4928, 55423, 4928) per
        # the fixture. Both passes run on the single row, so the Y pass
        # multiplies the X-pass alpha by 55423 again:
        # X pass: edge 255*60351 div 256 div 255 = 235, interior
        # 255*65279 div 256 div 255 = 254;
        # Y pass: 235*55423 div 256 div 255 = 199, 254*55423 div 256 div
        # 255 = 215.
        a = newImage(5, 1)
        fill(a, rgbx(0, 0, 0, 255))
        blur(a, 1f0)
        @test pxv(a, 1, 1) == (0, 0, 0, 199)
        @test pxv(a, 2, 1) == (0, 0, 0, 215)
        @test pxv(a, 3, 1) == (0, 0, 0, 215)
        @test pxv(a, 4, 1) == (0, 0, 0, 215)
        @test pxv(a, 5, 1) == (0, 0, 0, 199)

        # out-of-bounds samples read as white: X-pass edge is
        # (19, 19, 19, 254) (255*4928 div 256 div 255 = 19), then the Y
        # pass mixes the white OOB rows in: edge rgb
        # (19*55423 + 2*255*4928) div 256 div 255 = 54, interior
        # 2*255*4928 div 256 div 255 = 38; alpha 254 in both cases.
        b = newImage(5, 1)
        fill(b, rgbx(0, 0, 0, 255))
        blur(b, 1f0, rgbx(255, 255, 255, 255))
        @test pxv(b, 1, 1) == (54, 54, 54, 254)
        @test pxv(b, 3, 1) == (38, 38, 38, 254)
        @test pxv(b, 5, 1) == (54, 54, 54, 254)

        # radius 0 (and anything rounding to 0) is a no-op
        c = newImage(2, 1)
        fill(c, rgbx(10, 20, 30, 40))
        blur(c, 0f0)
        @test pxv(c, 1, 1) == (10, 20, 30, 40)
        blur(c, 0.4f0)
        @test pxv(c, 2, 1) == (10, 20, 30, 40)
        # a negative radius raises; Nim `round` ties away from zero, so
        # -0.5 rounds to -1 (raises) rather than to 0 (silent no-op)
        @test_throws ArgumentError blur(c, -1f0)
        @test_throws ArgumentError blur(c, Float32(-0.5))

        # rgba/rgb out-of-bounds inputs convert to premultiplied like the
        # default rgbx path (same result, no extra arithmetic)
        d = newImage(1, 1)
        fill(d, rgbx(255, 0, 0, 255))
        blur(d, 1f0, rgba(255, 255, 255, 255))
        d2 = newImage(1, 1)
        fill(d2, rgbx(255, 0, 0, 255))
        blur(d2, 1f0, rgbx(255, 255, 255, 255))
        @test d.data == d2.data
        d3 = newImage(1, 1)
        fill(d3, rgbx(255, 0, 0, 255))
        blur(d3, 1f0, rgb(255, 255, 255))
        @test d3.data == d2.data
    end

    @testset "spread (max/min alpha pool, alpha-only result)" begin
        # positive: the center's 255 reaches all three pixels and RGB is
        # zeroed by the rewrite
        a = newImage(3, 1)
        setColor(a, 1, 1, rgbx(0, 0, 0, 0))
        setColor(a, 2, 1, rgbx(100, 50, 25, 255))
        setColor(a, 3, 1, rgbx(0, 0, 0, 0))
        spread(a, 1f0)
        @test pxv(a, 1, 1) == (0, 0, 0, 255)
        @test pxv(a, 2, 1) == (0, 0, 0, 255)
        @test pxv(a, 3, 1) == (0, 0, 0, 255)
        # negative: the 0 reaches all pixels
        b = newImage(3, 1)
        setColor(b, 1, 1, rgbx(0, 0, 0, 255))
        setColor(b, 2, 1, rgbx(0, 0, 0, 0))
        setColor(b, 3, 1, rgbx(0, 0, 0, 255))
        spread(b, -1f0)
        @test pxv(b, 1, 1) == (0, 0, 0, 0)
        @test pxv(b, 2, 1) == (0, 0, 0, 0)
        @test pxv(b, 3, 1) == (0, 0, 0, 0)
        # zero spread is a no-op (colors preserved)
        c = newImage(1, 1)
        fill(c, rgbx(10, 20, 30, 40))
        spread(c, 0f0)
        @test pxv(c, 1, 1) == (10, 20, 30, 40)
        # -0.5 rounds to -1 (ties away from zero) and shrinks like -1
        e = newImage(3, 1)
        setColor(e, 1, 1, rgbx(0, 0, 0, 255))
        setColor(e, 2, 1, rgbx(0, 0, 0, 0))
        setColor(e, 3, 1, rgbx(0, 0, 0, 255))
        spread(e, Float32(-0.5))
        @test pxv(e, 1, 1) == (0, 0, 0, 0)
        @test pxv(e, 3, 1) == (0, 0, 0, 0)
        # 2D, non-extreme value: the center's alpha pools to the whole 3x3
        d = newImage(3, 3)
        setColor(d, 2, 2, rgbx(0, 0, 0, 100))
        spread(d, 1f0)
        @test pxv(d, 1, 1) == (0, 0, 0, 100)
        @test pxv(d, 3, 3) == (0, 0, 0, 100)
        @test pxv(d, 2, 2) == (0, 0, 0, 100)
    end

    @testset "shadow (spread + blur + MaskBlend pipeline, hand-derived)" begin
        # single opaque white pixel in a 5x1 row; blur r=1 kernel
        # (4928, 55423, 4928), both passes: X pass gives
        # [0, 255*4928 div 256 div 255 = 19, 255*55423 div 256 div 255
        # = 216, 19, 0]; the Y pass multiplies by 55423 again ->
        # mask alpha [0, 16, 183, 16, 0]
        a = newImage(5, 1)
        setColor(a, 3, 1, rgbx(255, 255, 255, 255))
        sh = shadow(a, Vec2(0f0, 0f0), 0f0, 1f0, rgbx(100, 200, 50, 255))
        @test (width(sh), height(sh)) == (5, 1)
        @test pxv(sh, 1, 1) == (0, 0, 0, 0)
        # backdrop channel * mask alpha div 255: 100*16 div 255 = 6,
        # 200*16 div 255 = 12, 50*16 div 255 = 3
        @test pxv(sh, 2, 1) == (6, 12, 3, 16)
        # 100*183 div 255 = 71, 200*183 div 255 = 143, 50*183 div 255 = 35
        @test pxv(sh, 3, 1) == (71, 143, 35, 183)
        @test pxv(sh, 4, 1) == (6, 12, 3, 16)
        @test pxv(sh, 5, 1) == (0, 0, 0, 0)
        # non-zero offset shifts the mask (integer translate fast path);
        # zero spread/blur leave it otherwise untouched
        b = newImage(2, 2)
        fill(b, rgbx(0, 0, 0, 255))
        sh2 = shadow(b, Vec2(Float32(1), 0f0), 0f0, 0f0,
            rgbx(255, 255, 255, 255))
        @test pxv(sh2, 1, 1) == (0, 0, 0, 0)
        @test pxv(sh2, 2, 1) == (255, 255, 255, 255)
        @test pxv(sh2, 1, 2) == (0, 0, 0, 0)
        @test pxv(sh2, 2, 2) == (255, 255, 255, 255)
    end

    @testset "resize (via draw, hand-derived)" begin
        src = newImage(2, 2)
        setColor(src, 1, 1, rgbx(10, 20, 30, 255))
        setColor(src, 2, 1, rgbx(40, 50, 60, 255))
        setColor(src, 1, 2, rgbx(70, 80, 90, 255))
        setColor(src, 2, 2, rgbx(100, 110, 120, 255))
        # 2x upscale: magnify fast path duplicates each pixel
        up = resize(src, 4, 4)
        @test (width(up), height(up)) == (4, 4)
        @test pxv(up, 1, 1) == (10, 20, 30, 255)
        @test pxv(up, 2, 1) == (10, 20, 30, 255)
        @test pxv(up, 3, 1) == (40, 50, 60, 255)
        @test pxv(up, 4, 1) == (40, 50, 60, 255)
        @test pxv(up, 1, 3) == (70, 80, 90, 255)
        @test pxv(up, 2, 4) == (70, 80, 90, 255)
        @test pxv(up, 3, 3) == (100, 110, 120, 255)
        @test pxv(up, 4, 4) == (100, 110, 120, 255)
        # downscale to 1x1: minify fast path averages (a+b+c+d+2) div 4
        avg = resize(src, 1, 1)
        @test pxv(avg, 1, 1) == (55, 65, 75, 255)
        # same size returns an independent copy
        same = resize(src, 2, 2)
        setColor(src, 1, 1, rgbx(1, 1, 1, 1))
        @test pxv(same, 1, 1) == (10, 20, 30, 255)
    end

    @testset "superImage (sub / padded / empty)" begin
        img = newImage(4, 4)
        for y in 1:4
            for x in 1:4
                setColor(img, x, y, rgbx(10 * (x - 1), 0, 10 * (y - 1), 255))
            end
        end
        # fully inside -> subImage (0-based origin (1, 1) = 1-based (2, 2))
        s = superImage(img, 1, 1, 2, 2)
        @test (width(s), height(s)) == (2, 2)
        @test pxv(s, 1, 1) == (10, 0, 10, 255)
        @test pxv(s, 2, 2) == (20, 0, 20, 255)
        # padded: 6x2 canvas, source drawn at (-x, -y) = (1, 1)
        p = superImage(img, -1, -1, 6, 2)
        @test (width(p), height(p)) == (6, 2)
        @test pxv(p, 1, 1) == (0, 0, 0, 0)
        @test pxv(p, 1, 2) == (0, 0, 0, 0)
        @test pxv(p, 2, 2) == (0, 0, 0, 255)
        @test pxv(p, 4, 2) == (20, 0, 0, 255)
        @test pxv(p, 5, 2) == (30, 0, 0, 255)
        @test pxv(p, 6, 2) == (0, 0, 0, 0)
        # fully outside (|origin| >= extent) -> empty canvas, including
        # the just-touching case
        e = superImage(img, 10, 10, 2, 2)
        @test pxv(e, 1, 1) == (0, 0, 0, 0)
        e2 = superImage(img, -4, 0, 2, 2)
        @test pxv(e2, 1, 1) == (0, 0, 0, 0)
    end

    @testset "opaqueBounds" begin
        img = newImage(4, 4)
        setColor(img, 2, 1, rgbx(0, 0, 0, 255))
        setColor(img, 3, 1, rgbx(0, 0, 0, 255))
        setColor(img, 2, 2, rgbx(0, 0, 0, 255))
        setColor(img, 3, 2, rgbx(0, 0, 0, 255))
        @test opaqueBounds(img) == rect(1f0, 0f0, 2f0, 2f0)
        # fully transparent -> zero rect
        @test opaqueBounds(newImage(3, 3)) == rect(0f0, 0f0, 0f0, 0f0)
        # fully opaque -> the whole size
        f = newImage(2, 3)
        fill(f, rgbx(0, 0, 0, 255))
        @test opaqueBounds(f) == rect(0f0, 0f0, 2f0, 3f0)
    end
end
