# T007a: blend modes (all 20 pinned TSV tables), the Paint kinds, gradient
# fills, image/tiled paints and the non-solid fillPath pipeline.
# Expected values: the pinned blend_*.tsv fixtures (11x11 valid-premultiplied
# grid = 121 rows per table) plus hand-computed gradient/paint values --
# never from the code under test.

@testset "T007a blends" begin
    """Message of the error `f` throws ("" when it does not)."""
    function caughtErrMsg(f)
        try
            f()
            return ""
        catch e
            return sprint(showerror, e)
        end
    end

    @testset "BlendMode enum order (upstream blends.nim, 0..19)" begin
        @test NormalBlend.value == 0
        @test DarkenBlend.value == 1
        @test MultiplyBlend.value == 2
        @test ColorBurnBlend.value == 3
        @test LightenBlend.value == 4
        @test ScreenBlend.value == 5
        @test ColorDodgeBlend.value == 6
        @test OverlayBlend.value == 7
        @test SoftLightBlend.value == 8
        @test HardLightBlend.value == 9
        @test DifferenceBlend.value == 10
        @test ExclusionBlend.value == 11
        @test HueBlend.value == 12
        @test SaturationBlend.value == 13
        @test ColorBlend.value == 14
        @test LuminosityBlend.value == 15
        @test MaskBlend.value == 16
        @test OverwriteBlend.value == 17
        @test SubtractMaskBlend.value == 18
        @test ExcludeMaskBlend.value == 19
    end

    @testset "blender dispatch and unknown modes" begin
        b0 = rgbx(1, 1, 1, 1)
        s0 = rgbx(2, 2, 2, 2)
        @test blender(NormalBlend)(b0, s0) == blendNormal(b0, s0)
        # Overwrite returns the source verbatim
        @test blender(OverwriteBlend)(rgbx(9, 8, 7, 3), rgbx(4, 4, 4, 4)) == rgbx(4, 4, 4, 4)
        # The three mask modes dispatch to their pixel functions (T007b)
        @test blender(MaskBlend)(b0, s0) == blendMask(b0, s0)
        @test blender(SubtractMaskBlend)(b0, s0) == blendSubtractMask(b0, s0)
        @test blender(ExcludeMaskBlend)(b0, s0) == blendExcludeMask(b0, s0)
        # unknown non-mask modes raise only when the returned closure runs
        @test_throws ArgumentError blender(BlendMode(20))(b0, s0)
        @test occursin("unknown blend mode",
            caughtErrMsg(() -> blender(BlendMode(20))(b0, s0)))
    end

    """Rows of a blend_*.tsv table where `f(backdrop, source) != result`."""
    function paintBadRows(tag::String, f)
        _, _, rows = VetraRef.read_table(tag)
        bad = String[]
        for row in rows
            bd = rgbx(parse(UInt8, row[1]), parse(UInt8, row[2]),
                parse(UInt8, row[3]), parse(UInt8, row[4]))
            sc = rgbx(parse(UInt8, row[5]), parse(UInt8, row[6]),
                parse(UInt8, row[7]), parse(UInt8, row[8]))
            got = f(bd, sc)
            if (got.r, got.g, got.b, got.a) !=
                (parse(UInt8, row[9]), parse(UInt8, row[10]),
                 parse(UInt8, row[11]), parse(UInt8, row[12]))
                push!(bad, row[1])
            end
        end
        return bad
    end

    @testset "$tag (121 rows)" for (tag, mode) in [
        ("blend_normal", NormalBlend),
        ("blend_darken", DarkenBlend),
        ("blend_multiply", MultiplyBlend),
        ("blend_color_burn", ColorBurnBlend),
        ("blend_lighten", LightenBlend),
        ("blend_screen", ScreenBlend),
        ("blend_color_dodge", ColorDodgeBlend),
        ("blend_overlay", OverlayBlend),
        ("blend_soft_light", SoftLightBlend),
        ("blend_hard_light", HardLightBlend),
        ("blend_difference", DifferenceBlend),
        ("blend_exclusion", ExclusionBlend),
        ("blend_hue", HueBlend),
        ("blend_saturation", SaturationBlend),
        ("blend_color", ColorBlend),
        ("blend_luminosity", LuminosityBlend),
        ("blend_overwrite", OverwriteBlend),
    ]
        _, _, rows = VetraRef.read_table(tag)
        @test length(rows) == 121   # 11x11 valid-premultiplied grid
        @test paintBadRows(tag, blender(mode)) == []
    end

    @testset "$tag (121 rows)" for (tag, f) in [
        ("blend_mask", blendMask),
        ("blend_subtract_mask", blendSubtractMask),
        ("blend_exclude_mask", blendExcludeMask),
    ]
        _, _, rows = VetraRef.read_table(tag)
        @test length(rows) == 121
        @test paintBadRows(tag, f) == []
    end

    @testset "hand-checked blend values" begin
        # multiply over an opaque white backdrop: (255-sa)*sv + sa*255 div 255
        # = 155 + sv per channel -- hand-computed from the formula.
        @test Vetra.blendMultiply(rgbx(255, 255, 255, 255),
            rgbx(100, 50, 25, 100)) == rgbx(255, 205, 180, 255)
        # masks: backdrop * source.a div 255 (128*128 div 255 = 64)
        @test Vetra.blendMask(rgbx(100, 50, 25, 128),
            rgbx(255, 255, 255, 128)) == rgbx(50, 25, 12, 64)
        # a = 128*(255-128) div 255 = 63 -> channels * 63 div 255
        @test Vetra.blendSubtractMask(rgbx(100, 50, 25, 128),
            rgbx(0, 0, 0, 128)) == rgbx(24, 12, 6, 63)
        # a = 128 - 100 = 28 -> source channels * 28 div 255
        @test Vetra.blendExcludeMask(rgbx(100, 50, 25, 128),
            rgbx(200, 100, 50, 100)) == rgbx(21, 10, 5, 28)
    end

    @testset "solid paint effective color (solidColorRGBX)" begin
        # a = round(200/255*255) = 200; (c*200+127) div 255 per channel
        @test Vetra.solidColorRGBX(Paint(rgba(200, 100, 50, 200))) ==
            rgbx(157, 78, 39, 200)
        # opacity 0.5: a = 100; (200*100+127) div 255 = 78, ...
        @test Vetra.solidColorRGBX(Paint(rgba(200, 100, 50, 200); opacity = 0.5f0)) ==
            rgbx(78, 39, 20, 100)
        # zero alpha -> zero paint
        @test Vetra.solidColorRGBX(Paint(rgba(200, 100, 50, 0))) ==
            rgbx(0, 0, 0, 0)
    end
end

@testset "T007a paints and gradients" begin
    pxv = (img, x, y) -> (c = getColor(img, x, y);
        (Int(c.r), Int(c.g), Int(c.b), Int(c.a)))

    @testset "newPaint defaults (upstream newPaint)" begin
        for kind in (SolidPaint, ImagePaint, TiledImagePaint,
                     LinearGradientPaint, RadialGradientPaint,
                     AngularGradientPaint)
            @testset "PaintKind($(kind.value))" begin
                p = Vetra.newPaint(kind)
                @test p.kind === kind
                @test p.color == ColorRGBA(0, 0, 0, 0)
                @test p.opacity == Float32(1)
                @test p.blendMode === NormalBlend
                @test p.image === nothing
                @test p.imageMat == mat3()
                @test p.gradientHandlePositions == Vec2[]
                @test p.gradientStops == ColorStop[]
                # `Paint(kind)` is the same `newPaint` entry point
                @test Paint(kind).kind === kind
            end
        end
    end

    @testset "copy independence" begin
        p = Paint(rgba(1, 2, 3, 4); opacity = 0.25f0, blendMode = MultiplyBlend)
        p.gradientHandlePositions = [Vec2(1f0, 2f0), Vec2(3f0, 4f0)]
        p.gradientStops = [colorStop(rgb(9, 8, 7), 0f0)]
        c = copy(p)
        @test c !== p
        @test c.kind === p.kind && c.color == p.color && c.blendMode === p.blendMode
        @test c.gradientStops == p.gradientStops &&
            c.gradientHandlePositions == p.gradientHandlePositions
        # mutating the copy must not touch the original
        c.opacity = Float32(1)
        c.blendMode = OverwriteBlend
        c.imageMat = translate(Vec2(9f0, 9f0))
        push!(c.gradientHandlePositions, Vec2(9f0, 9f0))
        push!(c.gradientStops, colorStop(rgb(1, 1, 1), 1f0))
        c.color = rgba(0, 0, 0, 0)
        @test p.opacity == 0.25f0
        @test p.blendMode === MultiplyBlend
        @test p.imageMat == mat3()
        @test length(p.gradientHandlePositions) == 2
        @test length(p.gradientStops) == 1
        @test p.color == ColorRGBA(1, 2, 3, 4)
    end

    @testset "colorStop" begin
        s = colorStop(rgb(1, 2, 3), 0.5f0)
        @test s.color == ColorRGBA(1, 2, 3, 0xff)
        @test s.position == Float32(0.5)
        @test colorStop(rgba(4, 5, 6, 7), 0f0).color == ColorRGBA(4, 5, 6, 7)
        @test colorStop(rgbx(10, 9, 8, 255), 1f0).color == ColorRGBA(10, 9, 8, 255)
        @test colorStop("#123456", 0.25f0).color == ColorRGBA(0x12, 0x34, 0x56, 0xff)
        @test_throws ArgumentError colorStop(42, 0f0)
        @test_throws ArgumentError colorStop(Vec2(1f0, 1f0), 0f0)
    end

    function bwStops()
        return [colorStop(rgb(0, 0, 0), 0f0), colorStop(rgb(255, 255, 255), 1f0)]
    end

    @testset "gradientColor: stop clamping and midpoint" begin
        p = Paint(LinearGradientPaint)
        p.gradientHandlePositions = [Vec2(0f0, 0f0), Vec2(4f0, 0f0)]
        p.gradientStops = bwStops()
        # before the first stop -> first stop (black)
        @test Vetra.gradientColor(p, Float32(-0.5)) == rgbx(0, 0, 0, 255)
        # after the last stop -> last stop (white)
        @test Vetra.gradientColor(p, Float32(1.5)) == rgbx(255, 255, 255, 255)
        # midpoint: 0.5 -> 0.5*255 = 127.5 -> round-half-away 128
        @test Vetra.gradientColor(p, 0.5f0) == rgbx(128, 128, 128, 255)
        # opacity scales alpha then rounds: 0.5 -> a = 128, c = round(0.5*128) = 64
        p.opacity = 0.5f0
        @test Vetra.gradientColor(p, 0.5f0) == rgbx(64, 64, 64, 128)
    end

    @testset "linear gradient (4x4 black -> white, hand-derived row)" begin
        g = newImage(4, 4)
        p = Paint(LinearGradientPaint)
        p.gradientHandlePositions = [Vec2(0f0, 0f0), Vec2(4f0, 0f0)]
        p.gradientStops = bwStops()
        fillGradient(g, p)
        # t = x/4: 0 -> 0; 0.25 -> 63.75 -> 64; 0.5 -> 127.5 -> 128;
        # 0.75 -> 191.25 -> 191 (round ties away from zero)
        for (x, v) in [(1, 0), (2, 64), (3, 128), (4, 191)]
            @test pxv(g, x, 1) == (v, v, v, 255)
        end
        @test pxv(g, 2, 4) == (64, 64, 64, 255)  # horizontal: rows identical
        # fillGradient clamps opacity in place (upstream `paint.opacity = clamp(...)`)
        p.opacity = 5f0
        g2 = newImage(2, 2)
        fillGradient(g2, p)
        @test p.opacity == Float32(1)
    end

    @testset "linear gradient vertical branch (1x3)" begin
        g = newImage(1, 3)
        p = Paint(LinearGradientPaint)
        p.gradientHandlePositions = [Vec2(0f0, 0f0), Vec2(0f0, 3f0)]
        p.gradientStops = bwStops()
        fillGradient(g, p)
        # t = y/3: 0 -> 0; 1/3 -> 85; 2/3 -> 170
        @test pxv(g, 1, 1) == (0, 0, 0, 255)
        @test pxv(g, 1, 2) == (85, 85, 85, 255)
        @test pxv(g, 1, 3) == (170, 170, 170, 255)
    end

    @testset "linear gradient with opacity 0.5" begin
        g = newImage(4, 1)
        p = Paint(LinearGradientPaint)
        p.gradientHandlePositions = [Vec2(0f0, 0f0), Vec2(4f0, 0f0)]
        p.gradientStops = bwStops()
        p.opacity = 0.5f0
        fillGradient(g, p)
        # c = t, a = 0.5 -> 128; premul (round(t*255)*128+127) div 255:
        # t=0 -> 0; 0.25 -> 64 -> (64*128+127) div 255 = 32;
        # 0.5 -> 128 -> 64; 0.75 -> 191 -> (191*128+127) div 255 = 96
        @test pxv(g, 1, 1) == (0, 0, 0, 128)
        @test pxv(g, 2, 1) == (32, 32, 32, 128)
        @test pxv(g, 3, 1) == (64, 64, 64, 128)
        @test pxv(g, 4, 1) == (96, 96, 96, 128)
        @test p.opacity == Float32(0.5)
    end

    @testset "zero-opacity gradient is a no-op" begin
        g = newImage(2, 2)
        fill(g, rgbx(9, 8, 7, 3))
        p = Paint(LinearGradientPaint)
        p.gradientHandlePositions = [Vec2(0f0, 0f0), Vec2(4f0, 0f0)]
        p.gradientStops = bwStops()
        p.opacity = 0f0
        fillGradient(g, p)
        @test pxv(g, 1, 1) == (9, 8, 7, 3)
    end

    @testset "radial gradient (center, edge, clamp -- hand-derived)" begin
        g = newImage(5, 5)
        p = Paint(RadialGradientPaint)
        # center (2,2), edge (0,2), skew (2,4): unit-circle radius 2 in both
        # axes, no rotation -> t = |(x-2, y-2)| / 2
        p.gradientHandlePositions = [
            Vec2(2f0, 2f0), Vec2(0f0, 2f0), Vec2(2f0, 4f0)]
        p.gradientStops = bwStops()
        fillGradient(g, p)
        @test pxv(g, 3, 3) == (0, 0, 0, 255)   # center: t = 0 (first stop)
        @test pxv(g, 2, 3) == (128, 128, 128, 255)  # t = 0.5 -> 127.5 -> 128
        @test pxv(g, 4, 4) == (180, 180, 180, 255)  # t = sqrt(0.5) -> 180.3 -> 180
        # on the unit circle in all four directions: t = 1 (last stop)
        @test pxv(g, 1, 3) == (255, 255, 255, 255)
        @test pxv(g, 5, 3) == (255, 255, 255, 255)
        @test pxv(g, 3, 1) == (255, 255, 255, 255)
        @test pxv(g, 3, 5) == (255, 255, 255, 255)
        # outside the circle: t = sqrt(2) > 1 -> clamped to the last stop
        @test pxv(g, 1, 1) == (255, 255, 255, 255)
        @test pxv(g, 1, 5) == (255, 255, 255, 255)
    end

    @testset "angular gradient (center, ring -- hand-derived)" begin
        g = newImage(5, 5)
        p = Paint(AngularGradientPaint)
        # center (2,2), edge (3,2): gradientAngle = 0
        # t = fixAngle(a + pi/2) / (2 pi) + 0.5 with a = angle(p - center)
        p.gradientHandlePositions = [
            Vec2(2f0, 2f0), Vec2(3f0, 2f0), Vec2(2f0, 0f0)]
        p.gradientStops = bwStops()
        fillGradient(g, p)
        # (3,2)->a=0     -> t = 0.75 -> 191.25 -> 191
        @test pxv(g, 4, 3) == (191, 191, 191, 255)
        # (1,2)->a=pi    -> t = 0.25 -> 64
        @test pxv(g, 2, 3) == (64, 64, 64, 255)
        # (2,1)->a=-pi/2 -> t = 0.5 -> 128
        @test pxv(g, 3, 2) == (128, 128, 128, 255)
        # (2,3)->a=pi/2  -> t = 1.0  -> white (last stop)
        @test pxv(g, 3, 4) == (255, 255, 255, 255)
        # corners: (0,0)->a=-3pi/4 -> t = 0.375 -> 96;  (4,0)->a=-pi/4 -> t = 0.625 -> 159
        @test pxv(g, 1, 1) == (96, 96, 96, 255)
        @test pxv(g, 5, 1) == (159, 159, 159, 255)
        # (0,4)->a=3pi/4 -> fix -> -3pi/4 -> t = 0.125 -> 32
        @test pxv(g, 1, 5) == (32, 32, 32, 255)
        # (4,4)->a=pi/4 -> a+pi/2 = 3pi/4 -> t = 0.875 -> 223
        @test pxv(g, 5, 5) == (223, 223, 223, 255)
    end

    @testset "fillGradient argument validation" begin
        img = newImage(1, 1)
        linear = Paint(LinearGradientPaint)
        linear.gradientHandlePositions = [Vec2(0f0, 0f0), Vec2(1f0, 0f0)]
        linear.gradientStops = bwStops()
        # wrong handle counts
        lin3 = copy(linear)
        push!(lin3.gradientHandlePositions, Vec2(2f0, 0f0))
        @test_throws ArgumentError fillGradient(img, lin3)
        rad = Paint(RadialGradientPaint)
        rad.gradientHandlePositions = [Vec2(0f0, 0f0), Vec2(1f0, 0f0)]
        rad.gradientStops = bwStops()
        @test_throws ArgumentError fillGradient(img, rad)
        ang = Paint(AngularGradientPaint)
        ang.gradientHandlePositions = [Vec2(0f0, 0f0), Vec2(1f0, 0f0)]
        ang.gradientStops = bwStops()
        @test_throws ArgumentError fillGradient(img, ang)
        # no stops
        empty = copy(linear)
        empty.gradientStops = ColorStop[]
        @test_throws ArgumentError fillGradient(img, empty)
        # non-gradient paint
        @test_throws ArgumentError fillGradient(img, Paint(rgba(1, 2, 3, 4)))
    end
end

@testset "T007a image and tiled paints via fillPath (non-solid branch)" begin
    pxv = (img, x, y) -> (c = getColor(img, x, y);
        (Int(c.r), Int(c.g), Int(c.b), Int(c.a)))

    # 2x2 with distinct premultiplied pixels (opaque, valid premul)
    pimg = newImage(2, 2)
    setColor(pimg, 1, 1, rgbx(10, 20, 30, 255))
    setColor(pimg, 2, 1, rgbx(40, 50, 60, 255))
    setColor(pimg, 1, 2, rgbx(70, 80, 90, 255))
    setColor(pimg, 2, 2, rgbx(100, 110, 120, 255))
    # 2x2 semi-opaque (valid premul)
    simg = newImage(2, 2)
    setColor(simg, 1, 1, rgbx(10, 20, 30, 128))
    setColor(simg, 2, 1, rgbx(40, 50, 60, 128))
    setColor(simg, 1, 2, rgbx(70, 80, 90, 128))
    setColor(simg, 2, 2, rgbx(10, 10, 10, 100))

    function rectPath(w::Float32, h::Float32)
        pt = newPath()
        rect(pt, 0f0, 0f0, w, h)
        return pt
    end

    @testset "ImagePaint: opaque copy (source-over, a = 255)" begin
        d = newImage(2, 2)
        fill(d, rgbx(255, 255, 255, 255))
        p = Paint(pimg)
        @test p.kind === ImagePaint
        fillPath(d, rectPath(2f0, 2f0), p)
        @test pxv(d, 1, 1) == (10, 20, 30, 255)
        @test pxv(d, 2, 1) == (40, 50, 60, 255)
        @test pxv(d, 1, 2) == (70, 80, 90, 255)
        @test pxv(d, 2, 2) == (100, 110, 120, 255)
    end

    @testset "ImagePaint: semi-opaque over white (hand-derived)" begin
        d = newImage(2, 2)
        fill(d, rgbx(255, 255, 255, 255))
        fillPath(d, rectPath(2f0, 2f0), Paint(simg))
        # blendNormal(white, s): c = s + (255 * (255 - sa)) div 255; a -> 255
        @test pxv(d, 1, 1) == (137, 147, 157, 255)  # 10/20/30 + 127
        @test pxv(d, 2, 1) == (167, 177, 187, 255)
        @test pxv(d, 1, 2) == (197, 207, 217, 255)
        @test pxv(d, 2, 2) == (165, 165, 165, 255)  # sa = 100 -> + 155
    end

    @testset "ImagePaint: translation, only the overlap pixel" begin
        d = newImage(2, 2)
        fill(d, rgbx(255, 255, 255, 255))
        p = Paint(pimg; imageMat = translate(Vec2(1f0, 1f0)))
        fillPath(d, rectPath(2f0, 2f0), p)
        # blendRect blit (pinned by draw_translate.meta: src(0,0) lands on the
        # pos pixel, region extends pos..pos+size): src(0,0) lands at (2,2)
        @test pxv(d, 2, 2) == (10, 20, 30, 255)
        @test pxv(d, 1, 1) == (255, 255, 255, 255)  # outside the blit
        @test pxv(d, 2, 1) == (255, 255, 255, 255)
        @test pxv(d, 1, 2) == (255, 255, 255, 255)
    end

    @testset "ImagePaint: scale 2x samples out-of-bounds (magnified corner)" begin
        d = newImage(2, 2)
        fill(d, rgbx(255, 255, 255, 255))
        p = Paint(pimg; imageMat = scale(Vec2(2f0, 2f0)))
        fillPath(d, rectPath(2f0, 2f0), p)
        # magnifyBy2 duplicates each source pixel 2x2; only src pixel (1,1)
        # covers the whole 2x2 destination
        for y in 1:2
            for x in 1:2
                @test pxv(d, x, y) == (10, 20, 30, 255)
            end
        end
    end

    @testset "TiledImagePaint: identity pattern (4x2 over 2x1 source)" begin
        strip = newImage(2, 1)
        setColor(strip, 1, 1, rgbx(10, 20, 30, 255))
        setColor(strip, 2, 1, rgbx(70, 80, 90, 255))
        d = newImage(4, 2)  # transparent backdrop
        p = Paint(TiledImagePaint)
        p.image = strip
        @test p.kind === TiledImagePaint
        fillPath(d, rectPath(4f0, 2f0), p)
        for y in 1:2
            @test pxv(d, 1, y) == (10, 20, 30, 255)
            @test pxv(d, 2, y) == (70, 80, 90, 255)
            @test pxv(d, 3, y) == (10, 20, 30, 255)
            @test pxv(d, 4, y) == (70, 80, 90, 255)
        end
    end

    @testset "TiledImagePaint: translation wraps the pattern" begin
        strip = newImage(2, 1)
        setColor(strip, 1, 1, rgbx(10, 20, 30, 255))
        setColor(strip, 2, 1, rgbx(70, 80, 90, 255))
        d = newImage(4, 2)
        p = Paint(TiledImagePaint)
        p.image = strip
        p.imageMat = translate(Vec2(1f0, 0f0))
        fillPath(d, rectPath(4f0, 2f0), p)
        for y in 1:2
            @test pxv(d, 1, y) == (70, 80, 90, 255)  # negative x wraps
            @test pxv(d, 2, y) == (10, 20, 30, 255)
            @test pxv(d, 3, y) == (70, 80, 90, 255)
            @test pxv(d, 4, y) == (10, 20, 30, 255)
        end
    end

    @testset "non-solid + OverwriteBlend (image and gradient)" begin
        # image paint: the fill lands verbatim, ignoring the backdrop
        d = newImage(2, 2)
        fill(d, rgbx(255, 255, 255, 255))
        p = Paint(simg; blendMode = OverwriteBlend)
        fillPath(d, rectPath(2f0, 2f0), p)
        @test pxv(d, 1, 1) == (10, 20, 30, 128)
        @test pxv(d, 2, 2) == (10, 10, 10, 100)

        # gradient paint with opacity 0.5: values land unblended
        d2 = newImage(4, 1)
        fill(d2, rgbx(255, 255, 255, 255))
        gp = Paint(LinearGradientPaint)
        gp.gradientHandlePositions = [Vec2(0f0, 0f0), Vec2(4f0, 0f0)]
        gp.gradientStops = [colorStop(rgb(0, 0, 0), 0f0),
            colorStop(rgb(255, 255, 255), 1f0)]
        gp.opacity = 0.5f0
        gp.blendMode = OverwriteBlend
        fillPath(d2, rectPath(4f0, 1f0), gp)
        # t -> 64/128/191/255 (rounded), then blendMask * mask.a(128) with
        # truncating // (pinned by the blend_mask TSV table), verbatim copy:
        # 64*128//255 = 32; 128*128//255 = 64; 191*128//255 = 95; 128 stays
        @test pxv(d2, 1, 1) == (0, 0, 0, 128)
        @test pxv(d2, 2, 1) == (32, 32, 32, 128)
        @test pxv(d2, 3, 1) == (64, 64, 64, 128)
        @test pxv(d2, 4, 1) == (95, 95, 95, 128)
    end

    @testset "solid paint + OverwriteBlend on a small rect" begin
        d = newImage(2, 2)
        fill(d, rgbx(255, 255, 255, 255))
        fillPath(d, rectPath(2f0, 2f0),
            Paint(rgba(200, 100, 50, 255); blendMode = OverwriteBlend))
        @test pxv(d, 1, 1) == (200, 100, 50, 255)
        @test pxv(d, 2, 2) == (200, 100, 50, 255)
    end

    @testset "non-solid fillPath with opacity 0.5 (mask-opacity path)" begin
        d = newImage(4, 1)
        fill(d, rgbx(255, 255, 255, 255))
        gp = Paint(LinearGradientPaint)
        gp.gradientHandlePositions = [Vec2(0f0, 0f0), Vec2(4f0, 0f0)]
        gp.gradientStops = [colorStop(rgb(0, 0, 0), 0f0),
            colorStop(rgb(255, 255, 255), 1f0)]
        gp.opacity = 0.5f0
        fillPath(d, rectPath(4f0, 1f0), gp)
        # mask (white) * 0.5 -> a 128; fill * 128 div 255:
        # 0 -> 0, 64 -> 32, 128 -> 64, 191 -> 95; then over white (k = 127):
        # 0+127, 32+127, 64+127, 95+127; a -> 255
        @test pxv(d, 1, 1) == (127, 127, 127, 255)
        @test pxv(d, 2, 1) == (159, 159, 159, 255)
        @test pxv(d, 3, 1) == (191, 191, 191, 255)
        @test pxv(d, 4, 1) == (222, 222, 222, 255)
    end

    @testset "invalid paints / arguments raise" begin
        d = newImage(2, 2)
        # ImagePaint / TiledImagePaint without an image
        p = Paint(ImagePaint)
        @test_throws ArgumentError fillPath(d, rectPath(2f0, 2f0), p)
        p = Paint(TiledImagePaint)
        @test_throws ArgumentError fillPath(d, rectPath(2f0, 2f0), p)
        # a gradient paint used as an image paint kind is nonsensical but the
        # kind dispatch still requires a paint kind for the branch:
        d2 = newImage(1, 1)
        solid = Paint(rgba(1, 2, 3, 4))
        @test solid.kind === SolidPaint
        @test_throws ArgumentError fillPath(d2, 42, solid)  # bad path type
    end

    @testset "Paint(kind) and convert(Paint, ...) (parseSomePaint solids)" begin
        @test newPaint(SolidPaint).kind === SolidPaint
        @test Paint("#123456").color == ColorRGBA(0x12, 0x34, 0x56, 0xff)
        @test convert(Paint, "#123").color == ColorRGBA(0x11, 0x22, 0x33, 0xff)
        @test_throws ArgumentError convert(Paint, 42)
        @test_throws ArgumentError parseHtmlColor("123456")  # no '#'
        @test_throws ArgumentError parseHtmlColor("#12")     # bad length
        @test_throws ArgumentError parseHtmlColor("#123x56") # bad digit
    end

    @testset "T008: gradient branch coverage (oracle/hand-derived)" begin
        bwStops() = [colorStop(rgb(0, 0, 0), 0f0),
            colorStop(rgb(255, 255, 255), 1f0)]
        # Diagonal linear gradient: the per-pixel branch. t = (x0 + y0) / 8
        # with 0-based pixel coords; c = round(t * 255) per channel.
        g = newImage(4, 4)
        p = Paint(LinearGradientPaint)
        p.gradientHandlePositions = [Vec2(0f0, 0f0), Vec2(4f0, 4f0)]
        p.gradientStops = bwStops()
        fillGradient(g, p)
        @test pxv(g, 1, 1) == (0, 0, 0, 255)      # t = 0
        @test pxv(g, 2, 2) == (64, 64, 64, 255)   # t = 1/4
        @test pxv(g, 4, 4) == (191, 191, 191, 255) # t = 3/4
        @test pxv(g, 1, 4) == (96, 96, 96, 255)   # t = 3/8

        # Zero-stop gradients raise (linear takes 2 handles; the
        # radial/angular kinds take 3).
        for kind in (LinearGradientPaint, RadialGradientPaint,
            AngularGradientPaint)
            zp = Paint(kind)
            zp.gradientHandlePositions = kind === LinearGradientPaint ?
                [Vec2(0f0, 0f0), Vec2(1f0, 1f0)] :
                [Vec2(0f0, 0f0), Vec2(1f0, 1f0), Vec2(1f0, -1f0)]
            @testset "zero stops $kind" begin
                try
                    fillGradient(newImage(2, 2), zp)
                    @test false
                catch e
                    @test e.msg == "Gradient must have at least 1 color stop"
                end
            end
        end

        # Opacity 0 returns without filling (radial + angular).
        for kind in (RadialGradientPaint, AngularGradientPaint)
            zp = Paint(kind)
            zp.gradientHandlePositions =
                [Vec2(0f0, 0f0), Vec2(1f0, 1f0), Vec2(1f0, -1f0)]
            zp.gradientStops = [ColorStop(rgba(255, 0, 0, 255), 0f0)]
            zp.opacity = 0f0
            img = newImage(2, 2)
            fillGradient(img, zp)
            @test all(v -> v == 0x00, img.data)
        end

        # rgb() component parse failure surfaces the SVG convention.
        try
            parseHtmlColor("rgb(1, 2, x)")
            @test false
        catch e
            @test e.msg == "Invalid SVG data"
        end
    end
end
