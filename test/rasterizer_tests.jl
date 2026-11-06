# T008 coverage: rasterizer MaskBlend fill paths (fillShapes) and the
# drawSmooth blend branches. Every expected buffer is pinned against the
# upstream oracle: the same scenarios run through the pinned treeform/pixie
# (nim 2.2.6, -d:pixieNoSimd, scalar) fillShapes/drawSmooth, plus
# hand-derivation from blends.nim (blendMask scales the backdrop by
# source.a only) and the mask "clears-uncovered" rule (rasterizer.nim).

@testset "T008 rasterizer MaskBlend branches" begin
    pxv = (img, i) -> (o = 4 * (i - 1);
        (Int(img.data[o + 1]), Int(img.data[o + 2]), Int(img.data[o + 3]),
            Int(img.data[o + 4])))
    white(w, h) = (img = newImage(w, h);
        for i in 1:4:length(img.data)
            img.data[i:i + 3] = [0xff, 0xff, 0xff, 0xff]
        end;
        img)
    # Premultiplied source: rgbx(rgba(128, 0, 128, 128)) = (64, 0, 64, 128).
    # blendMask(white, s) = (255 * s.a div 255) per channel.
    src = rgbx(rgba(128, 0, 128, 128))
    hit = (128, 128, 128, 128) # full-hit mask pixel over white
    zero = (0, 0, 0, 0)

    @testset "fast-path mask (pixel-aligned span, semi-transparent source)" begin
        img = white(4, 4)
        sq = [Vec2(1, 1), Vec2(3, 1), Vec2(3, 3), Vec2(1, 3)]
        fillShapes(img, [sq], src, NonZero; blendMode = MaskBlend)
        exp = [zero, zero, zero, zero,
            zero, hit, hit, zero,
            zero, hit, hit, zero,
            zero, zero, zero, zero]
        @test [pxv(img, i) for i in 1:16] == exp
    end

    @testset "trapezoid + non-AA walk mask (overlapping rects, NonZero)" begin
        # Union of rect (0,0)-(2,3) and rect (1,1)-(3,3): row 0 fills
        # [0,2); rows 1-2 fill [0,3). The overlapping rows fail the
        # trapezoid winding check and fall to the integer hit walk.
        img = white(4, 3)
        A = [Vec2(0, 0), Vec2(2, 0), Vec2(2, 3), Vec2(0, 3)]
        B = [Vec2(1, 1), Vec2(3, 1), Vec2(3, 3), Vec2(1, 3)]
        fillShapes(img, [A, B], src, NonZero; blendMode = MaskBlend)
        exp = [hit, hit, zero, zero,
            hit, hit, hit, zero,
            hit, hit, hit, zero]
        @test [pxv(img, i) for i in 1:12] == exp
    end

    @testset "AA coverage mask (fractional rect)" begin
        # Rect [0.5, 1.5) x [0, 3): pixel 0 has half coverage per row ->
        # (64, 64, 64, 64) over white; pixel 1..3 are cleared (oracle-pinned).
        img = white(4, 3)
        F = [Vec2(Float32(0.5), Float32(0)), Vec2(Float32(1.5), Float32(0)),
            Vec2(Float32(1.5), Float32(3)), Vec2(Float32(0.5), Float32(3))]
        fillShapes(img, [F], src, NonZero; blendMode = MaskBlend)
        half = (64, 64, 64, 64)
        exp = [half, half, zero, zero, half, half, zero, zero,
            half, half, zero, zero]
        @test [pxv(img, i) for i in 1:12] == exp
    end

    @testset "pathWidth == 0 mask clears the whole image" begin
        img = white(4, 2)
        O = [Vec2(5, 0), Vec2(6, 0), Vec2(6, 2), Vec2(5, 2)]
        fillShapes(img, [O], src, NonZero; blendMode = MaskBlend)
        @test all(p -> p == zero, [pxv(img, i) for i in 1:8])
    end

    @testset "drawSmooth blend branches (2x2 opaque red at (2, 1) on 6x4)" begin
        probe(mode) = (a = white(6, 4);
            b = newImage(2, 2);
            for i in 1:4:length(b.data)
                b.data[i:i + 3] = [0xff, 0, 0, 0xff]
            end;
            Vetra.drawSmooth(a, b, translate(Vec2(2, 1)), mode);
            [pxv(a, i) for i in 1:24])
        red = (255, 0, 0, 255)
        w = (255, 255, 255, 255)
        placed = [9, 10, 15, 16] # 1-based pixels (2,1),(3,1),(2,2),(3,2)
        @test probe(NormalBlend)[placed] == [red, red, red, red]
        @test probe(OverwriteBlend)[placed] == [red, red, red, red]
        @test probe(MultiplyBlend)[placed] == [red, red, red, red]
        # Mask: blendMask(white, opaque sample) = white inside, clear outside.
        m = probe(MaskBlend)
        @test m[placed] == [w, w, w, w]
        @test all(p -> p == zero, (m[i] for i in 1:24 if !(i in placed)))
        # A W3C-mode blend goes through the generic blender branch.
        mu = probe(MultiplyBlend)
        @test mu[9] == red
    end

    @testset "spread (radius 1 grows the alpha mask)" begin
        img = newImage(4, 2)
        img.data[4] = 0xff # pixel (1, 1), 1-based
        s = copy(img)
        spread(s, 1f0)
        d = s.data
        for i in 1:8 # 4x2 = 8 pixels
            o = 4 * (i - 1)
            if i in (1, 2, 5, 6)
                @test Int(d[o + 4]) == 0xff
                @test Int(d[o + 1]) == 0
            else
                @test Int(d[o + 4]) == 0x00
            end
        end
    end
end
