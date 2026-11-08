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

# T022: non-solid gradient paints are cut out of the coverage mask and
# blended in one pass (no fill canvas). Expected pixels are hand-derived
# from the documented arithmetic — Float32 `t`, stop interpolation,
# roundHalfAway, applyOpacity + MaskBlend cut-out, the paint's blend —
# never from the code under test.
@testset "T022 fused non-solid gradient fill" begin
    # Opaque red @0 -> opaque blue @1; both stops opaque, so premul ==
    # straight: t=0 -> (255,0,0,255), t=0.5 -> 127.5 -> (128,0,128,255),
    # t=1 -> (0,0,255,255).
    function fgStops()
        [ColorStop(rgba(255, 0, 0, 255), 0f0),
            ColorStop(rgba(0, 0, 255, 255), 1f0)]
    end

    function fgLinear(opacity, blend, h1, h2)
        p = Paint(LinearGradientPaint)
        p.opacity = opacity
        p.blendMode = blend
        p.gradientHandlePositions = [h1, h2]
        p.gradientStops = fgStops()
        return p
    end

    function fgFresh(w, h; white = false)
        img = newImage(w, h)
        white && fill(img, rgb(255, 255, 255))
        return img
    end

    function fgFullRect(w, h)
        p = newPath()
        rect(p, 0f0, 0f0, Float32(w), Float32(h))
        return p
    end

    # Linear, horizontal handles (0,0)->(10,0): t = x/10; x=0 -> t=0,
    # x=5 -> t=0.5 (50f0/100f0 exact).
    @testset "linear horizontal" begin
        img = fgFresh(10, 1)
        fillPath(img, fgFullRect(10, 1),
            fgLinear(1f0, NormalBlend, Vec2(0f0, 0f0), Vec2(10f0, 0f0)))
        @test getColor(img, 1, 1) == rgbx(255, 0, 0, 255)
        @test getColor(img, 6, 1) == rgbx(128, 0, 128, 255)
    end

    # Multi-row horizontal with opacity 0.5 (o = 128, full coverage
    # k = 128): every row must be the SAME cut-out, (128,0,0,128) at t=0.
    # A double cut-out (scaling an already-cut row again) would give
    # row 2 = 128*128 div 255 = 64 — this pins that regression.
    @testset "linear horizontal multi-row" begin
        img = fgFresh(4, 2)
        fillPath(img, fgFullRect(4, 2),
            fgLinear(0.5f0, NormalBlend, Vec2(0f0, 0f0), Vec2(4f0, 0f0)))
        @test getColor(img, 1, 1) == rgbx(128, 0, 0, 128)
        @test getColor(img, 1, 2) == rgbx(128, 0, 0, 128)
    end

    # Linear, vertical handles (0,0)->(0,10): t = y/10.
    @testset "linear vertical" begin
        img = fgFresh(1, 10)
        fillPath(img, fgFullRect(1, 10),
            fgLinear(1f0, NormalBlend, Vec2(0f0, 0f0), Vec2(0f0, 10f0)))
        @test getColor(img, 1, 1) == rgbx(255, 0, 0, 255)
        @test getColor(img, 1, 6) == rgbx(128, 0, 128, 255)
    end

    # Linear, general handles (0,0)->(8,8): t = (x+y)/16.
    @testset "linear general" begin
        img = fgFresh(16, 16)
        fillPath(img, fgFullRect(16, 16),
            fgLinear(1f0, NormalBlend, Vec2(0f0, 0f0), Vec2(8f0, 8f0)))
        @test getColor(img, 1, 1) == rgbx(255, 0, 0, 255)    # t=0
        @test getColor(img, 9, 1) == rgbx(128, 0, 128, 255) # t=0.5
        @test getColor(img, 5, 5) == rgbx(128, 0, 128, 255) # t=0.5
        @test getColor(img, 9, 9) == rgbx(0, 0, 255, 255)   # t=1
    end

    # Radial: center (8,8), edge (16,8), skew (8,16) -> t=0 at the center
    # and t=0.5 at (12,8) (exact 0.5f0 in the normalized space).
    @testset "radial" begin
        p = Paint(RadialGradientPaint)
        p.gradientHandlePositions = [Vec2(8f0, 8f0), Vec2(16f0, 8f0),
            Vec2(8f0, 16f0)]
        p.gradientStops = fgStops()
        img = fgFresh(16, 16)
        fillPath(img, fgFullRect(16, 16), p)
        @test getColor(img, 9, 9) == rgbx(255, 0, 0, 255)
        @test getColor(img, 13, 9) == rgbx(128, 0, 128, 255)
    end

    # Angular: center (8,8), edge (16,8) (gradientAngle 0). Right of
    # center a = 0 -> t = 0.75 ((1-t)*255 = 63.75 -> 64, t*255 = 191.25
    # -> 191); above center a = -pi/2 -> t = 0.5; left of center
    # a = pi -> fixAngle(3pi/2) = -pi/2 (range (-pi, pi]) -> t = 0.25
    # ((1-t)*255 = 191.25 -> 191, t*255 = 63.75 -> 64).
    @testset "angular" begin
        p = Paint(AngularGradientPaint)
        p.gradientHandlePositions = [Vec2(8f0, 8f0), Vec2(16f0, 8f0),
            Vec2(8f0, 16f0)]
        p.gradientStops = fgStops()
        img = fgFresh(16, 16)
        fillPath(img, fgFullRect(16, 16), p)
        @test getColor(img, 13, 9) == rgbx(64, 0, 191, 255)
        @test getColor(img, 9, 5) == rgbx(128, 0, 128, 255)
        @test getColor(img, 5, 9) == rgbx(191, 0, 64, 255)
    end

    # Opacity rounding: o = roundHalfAway(255 * opacity) scales the full
    # coverage (255) to k = o, so the opaque-red t=0 sample becomes
    # (o, 0, 0, o). o=0 leaves the backdrop untouched.
    @testset "opacity" begin
        for (op, expected) in
            ((1f0, rgbx(255, 0, 0, 255)),
                (0.5f0, rgbx(128, 0, 0, 128)),
                (0.499f0, rgbx(127, 0, 0, 127)),
                (0.501f0, rgbx(128, 0, 0, 128)),
                (0.002f0, rgbx(1, 0, 0, 1)),
                (0.9991f0, rgbx(255, 0, 0, 255)))
            img = fgFresh(10, 1)
            fillPath(img, fgFullRect(10, 1),
                fgLinear(op, NormalBlend, Vec2(0f0, 0f0), Vec2(10f0, 0f0)))
            @test getColor(img, 1, 1) == expected
        end
        img = fgFresh(10, 1; white = true)
        fillPath(img, fgFullRect(10, 1),
            fgLinear(0.001f0, NormalBlend, Vec2(0f0, 0f0), Vec2(10f0, 0f0)))
        @test getColor(img, 1, 1) == rgbx(255, 255, 255, 255)
    end

    # Blend modes reach the fused pass: Overwrite writes the cut-out
    # source verbatim (clears white); Multiply over white with an opaque
    # red source is red ((255-255)*sv + 0 + 255*sv) div 255 per channel).
    @testset "blend modes" begin
        img = fgFresh(10, 1; white = true)
        fillPath(img, fgFullRect(10, 1),
            fgLinear(1f0, OverwriteBlend, Vec2(0f0, 0f0), Vec2(10f0, 0f0)))
        @test getColor(img, 1, 1) == rgbx(255, 0, 0, 255)
        img = fgFresh(10, 1; white = true)
        fillPath(img, fgFullRect(10, 1),
            fgLinear(1f0, MultiplyBlend, Vec2(0f0, 0f0), Vec2(10f0, 0f0)))
        @test getColor(img, 1, 1) == rgbx(255, 0, 0, 255)
    end

    # Mask-family paint blend modes reach the generic branch. MaskBlend
    # scales the backdrop by the source alpha: translucent premul
    # backdrop (100,50,25,200) x cut-out source (128,0,0,128) at
    # opacity 0.5 (o = k = 128, full coverage) -> (100*128/255,
    # 50*128/255, 25*128/255, 200*128/255) = (50,25,12,100).
    @testset "mask blend mode" begin
        img = newImage(10, 1)
        fill(img, rgbx(100, 50, 25, 200))
        fillPath(img, fgFullRect(10, 1),
            fgLinear(0.5f0, MaskBlend, Vec2(0f0, 0f0), Vec2(10f0, 0f0)))
        @test getColor(img, 1, 1) == rgbx(50, 25, 12, 100)
        # Opacity rounded to zero (o = 0) with MaskBlend clears the
        # backdrop (source alpha 0 scales it to 0).
        img = fgFresh(10, 1; white = true)
        fillPath(img, fgFullRect(10, 1),
            fgLinear(0.001f0, MaskBlend, Vec2(0f0, 0f0), Vec2(10f0, 0f0)))
        @test getColor(img, 1, 1) == rgbx(0, 0, 0, 0)
    end

    # Translucent premultiplied backdrop under NormalBlend: dst
    # (100,50,25,200), src (128,0,0,128) (t=0, o = k = 128) ->
    # k = 255-128 = 127: R = 128 + 100*127/255 = 177,
    # G = 0 + 50*127/255 = 24, B = 0 + 25*127/255 = 12,
    # A = 128 + 200*127/255 = 227.
    @testset "translucent backdrop" begin
        img = newImage(10, 1)
        fill(img, rgbx(100, 50, 25, 200))
        fillPath(img, fgFullRect(10, 1),
            fgLinear(0.5f0, NormalBlend, Vec2(0f0, 0f0), Vec2(10f0, 0f0)))
        @test getColor(img, 1, 1) == rgbx(177, 24, 12, 227)
    end

    # Partial coverage x opacity (white-box): coverage 255 and 128 with
    # o = 128 -> k = 128 and 128*128/255 = 64; handles (0,0)->(2,0) give
    # t=0 red (255,0,0,255) and t=0.5 mid (128,0,128,255), cut to
    # (128,0,0,128) and (128*64/255, 0, 128*64/255, 64) = (32,0,32,64)
    # over a transparent backdrop.
    @testset "partial coverage times opacity" begin
        mask = newImage(2, 1)
        setColor(mask, 1, 1, rgbx(255, 255, 255, 255))
        setColor(mask, 2, 1, rgbx(255, 255, 255, 128))
        img = newImage(2, 1)
        p = fgLinear(Float32(1), NormalBlend, Vec2(0f0, 0f0), Vec2(2f0, 0f0))
        Vetra._fillGradientMasked(img, mask, p, Vetra.blender(NormalBlend), 128)
        @test getColor(img, 1, 1) == rgbx(128, 0, 0, 128)
        @test getColor(img, 2, 1) == rgbx(32, 0, 32, 64)
    end

    # Coverage boundary: outside the path the backdrop is untouched.
    @testset "mask coverage boundary" begin
        img = fgFresh(16, 16; white = true)
        p = newPath()
        rect(p, 0f0, 0f0, 8f0, 8f0)
        fillPath(img, p,
            fgLinear(1f0, NormalBlend, Vec2(0f0, 0f0), Vec2(8f0, 0f0)))
        @test getColor(img, 1, 1) == rgbx(255, 0, 0, 255)
        @test getColor(img, 16, 16) == rgbx(255, 255, 255, 255)
    end

    # Error boundaries (same messages as the pre-T022 pipeline).
    @testset "validation" begin
        img = fgFresh(2, 2)
        p3 = fgLinear(1f0, NormalBlend, Vec2(0f0, 0f0), Vec2(4f0, 0f0))
        p3.gradientHandlePositions =
            [Vec2(0f0, 0f0), Vec2(4f0, 0f0), Vec2(2f0, 2f0)]
        try
            fillPath(img, fgFullRect(2, 2), p3)
            @test false
        catch e
            @test e.msg == "Linear gradient requires 2 handles"
        end
        p0 = fgLinear(1f0, NormalBlend, Vec2(0f0, 0f0), Vec2(4f0, 0f0))
        p0.gradientStops = ColorStop[]
        try
            fillPath(img, fgFullRect(2, 2), p0)
            @test false
        catch e
            @test e.msg == "Gradient must have at least 1 color stop"
        end
        r2 = Paint(RadialGradientPaint)
        r2.gradientHandlePositions = [Vec2(0f0, 0f0), Vec2(1f0, 0f0)]
        r2.gradientStops = fgStops()
        try
            fillPath(img, fgFullRect(2, 2), r2)
            @test false
        catch e
            @test e.msg == "Radial gradient requires 3 handles"
        end
        a2 = Paint(AngularGradientPaint)
        a2.gradientHandlePositions = [Vec2(0f0, 0f0), Vec2(1f0, 0f0)]
        a2.gradientStops = fgStops()
        try
            fillPath(img, fgFullRect(2, 2), a2)
            @test false
        catch e
            @test e.msg == "Angular gradient requires 2 handles"
        end
        # Zero stops for the radial/angular fused variants (same message as
        # the pre-T022 pipeline, reached via fillPath).
        for kind in (RadialGradientPaint, AngularGradientPaint)
            zs = Paint(kind)
            zs.gradientHandlePositions =
                [Vec2(0f0, 0f0), Vec2(1f0, 0f0), Vec2(1f0, 1f0)]
            try
                fillPath(img, fgFullRect(2, 2), zs)
                @test false
            catch e
                @test e.msg == "Gradient must have at least 1 color stop"
            end
        end
        # Non-finite stop positions: deliberate early error (the old
        # 2-buffer pipeline threw an accidental InexactError mid-fill);
        # the destination must stay untouched either way.
        for pos in (NaN32, Float32(Inf))
            img = fgFresh(2, 2)
            pnf = fgLinear(1f0, NormalBlend, Vec2(0f0, 0f0), Vec2(4f0, 0f0))
            pnf.gradientStops = [ColorStop(rgba(255, 0, 0, 255), 0f0),
                ColorStop(rgba(0, 0, 255, 255), pos)]
            try
                fillPath(img, fgFullRect(2, 2), pnf)
                @test false
            catch e
                @test e.msg == "Gradient stop positions must be finite"
            end
            @test all(v -> v == 0x00, img.data)
        end
        # Dispatcher parity with `fillGradient` (a solid paint is not a
        # gradient): white-box call of the fused dispatch.
        @test_throws ArgumentError Vetra._fillGradientMasked(
            img, fgFresh(2, 2), Paint(rgba(1, 2, 3, 4)),
            Vetra.blender(NormalBlend), 255)
    end
end
