# T004: paths, curves, arcs, and solid fill rasterization.
# Expectations come from hand computation (areas / fixed-point reading of the
# pinned upstream paths.nim) -- never from the code under test.

@testset "T004 paths and fills" begin
    px = (img, x, y) -> (c = getColor(img, x, y);
        (Int(c.r), Int(c.g), Int(c.b), Int(c.a)))

    @testset "command construction" begin
        p = newPath()
        @test p.commands == Float32[]
        @test p.start == Vec2() && p.at == Vec2()

        # Move=1, LineTo=2, Close=0 (upstream PathCommandKind order)
        moveTo(p, 1f0, 2f0)
        lineTo(p, 3f0, 4f0)
        closePath(p)
        @test p.commands == Float32[1.0, 1.0, 2.0, 2.0, 3.0, 4.0, 0.0]
        @test p.start == Vec2(1f0, 2f0)
        @test p.at == Vec2(1f0, 2f0) # close resets the cursor to the sub-path start

        Int(Vetra.Move) == 1 || error("enum order changed")
        @test Int(Vetra.LineTo) == 2
        @test Int(Vetra.Close) == 0
        @test Vetra.PathCommandKind(9) === Vetra.Arc

        # rect: M, 3x L, Z (clockwise from the corner)
        r = newPath()
        rect(r, 0f0, 0f0, 2f0, 1f0)
        @test r.commands == Float32[
            1.0, 0.0, 0.0,
            2.0, 2.0, 0.0, 2.0, 2.0, 1.0, 2.0, 0.0, 1.0,
            0.0]
        rect(r, rect(0f0, 0f0, 2f0, 1f0)) # Rect overload via geometry `rect`
        @test length(r.commands) == 13 * 2 # each rect: M + 3x L + Z = 13 floats

        # bezier/quadratic carry their control points verbatim
        q = newPath()
        moveTo(q, 0f0, 0f0)
        bezierCurveTo(q, 1f0, 2f0, 3f0, 4f0, 5f0, 6f0)
        quadraticCurveTo(q, 1f0, 1f0, 2f0, 2f0)
        @test q.commands == Float32[
            1.0, 0.0, 0.0, 5.0, 1.0, 2.0, 3.0, 4.0, 5.0, 6.0,
            7.0, 1.0, 1.0, 2.0, 2.0]

        # ellipse: Move + 4 Cubics + Close; circle is equal radii
        e = newPath()
        ellipse(e, 1f0, 1f0, 2f0, 1f0)
        @test length(e.commands) == 3 + 4 * 7 + 1
        # command kinds at the Move + 4 Cubics + Close positions
        @test [e.commands[k] for k in (1, 4, 11, 18, 25, 32)] ==
            Float32[1.0, 5.0, 5.0, 5.0, 5.0, 0.0]
        c = newPath()
        Vetra.circle(c, 1f0, 1f0, 3f0)
        @test length(c.commands) == 3 + 4 * 7 + 1

        # polygon: Move + (sides-1) Line + Close; vertex 0 is due north
        g = newPath()
        polygon(g, 0f0, 0f0, 1f0, 4)
        @test g.commands[1:3] == Float32[1.0, 0.0, -1.0] # north vertex
        @test length(g.commands) == 3 + 3 * 3 + 1
        @test_throws ArgumentError polygon(newPath(), 0f0, 0f0, 1f0, 2)
        @test_throws ArgumentError polygon(newPath(), 0f0, 0f0, 1f0, 0)

        # arc: radius check, zero-radius no-op, half/full circle splits
        a = newPath()
        @test_throws ArgumentError arc(a, 0f0, 0f0, -1f0, 0f0, 1f0)
        arc(a, 0f0, 0f0, 0f0, 0f0, 1f0)
        @test a.commands == Float32[] # r == 0: nothing
        a = newPath()
        arc(a, 0f0, 0f0, 1f0, 0f0, Float32(Vetra.PI_F)) # half circle
        @test a.commands[1:3] == Float32[1.0, 1.0, 0.0]
        @test length(a.commands) == 3 + 8 # one ellipticalArcTo
        a = newPath()
        arc(a, 0f0, 0f0, 1f0, 0f0, Float32(Vetra.TAU_F)) # full circle
        @test length(a.commands) == 3 + 2 * 8 # two half arcs
        a = newPath()
        arcTo(a, 1f0, 1f0, 2f0, 0f0, 0.5f0)
        @test !isempty(a.commands)
        @test_throws ArgumentError arcTo(newPath(), 0f0, 0f0, 1f0, 1f0, -1f0)

        # roundedRect radius clamp: radii cannot exceed min(w, h) / 2
        rr = newPath()
        roundedRect(rr, 0f0, 0f0, 2f0, 2f0, 9f0, 9f0, 9f0, 9f0)
        @test computeBounds(rr) == Rect(0f0, 0f0, 2f0, 2f0)
        @test length(rr.commands) > 2 * 2 # radiused, not the plain-rect 12

        # copy is independent; addPath appends
        b = newPath()
        moveTo(b, 0f0, 0f0)
        cc = copy(b)
        lineTo(b, 9f0, 9f0)
        @test b.commands != cc.commands
        addPath(cc, b)
        @test length(cc.commands) == 3 + length(b.commands)
    end

    @testset "transform" begin
        # identity leave untouched
        p = parsePath("M 1 1 L 3 1")
        transform(p, mat3())
        @test p.commands == Float32[1.0, 1.0, 1.0, 2.0, 3.0, 1.0]

        # absolute points take the full matrix, relative ones the
        # zero-translation part only
        p = parsePath("m 1 1 l 2 1")
        transform(p, translate(Vec2(1f0, 0f0)))
        @test p.commands[1] == 1.0f0 # leading RMove becomes Move
        @test p.commands[2:3] == Float32[2.0, 1.0] # (1,1) + (1,0)
        @test p.commands[4:6] == Float32[11.0, 2.0, 1.0] # RLine: delta unchanged

        # HLine / VLine coordinates transform along their axis
        p = parsePath("M 0 0 H 2 V 3")
        transform(p, scale(Vec2(2f0, 2f0)))
        @test p.commands[4:7] == Float32[3.0, 4.0, 4.0, 6.0]

        # arc radii scale by the matrix scales, endpoint by the matrix
        p = parsePath("M 1 1 A 1 1 0 0 1 3 1")
        transform(p, scale(Vec2(2f0, 2f0)))
        @test p.commands[1:3] == Float32[1.0, 2.0, 2.0]
        @test p.commands[4:6] == Float32[9.0, 2.0, 2.0] # radii 1,1 -> 2,2
        @test p.commands[10:11] == Float32[6.0, 2.0] # (3,1) -> (6,2)

        # computeBounds follows the transform
        p = parsePath("M 0 0 L 1 0 L 1 1 L 0 1 Z")
        @test computeBounds(p) == Rect(0f0, 0f0, 1f0, 1f0)
        @test computeBounds(p, translate(Vec2(2f0, 0f0))) == Rect(2f0, 0f0, 1f0, 1f0)
    end

    @testset "SVG parsing" begin
        # M/L with implicit repeat, relative h/V, Z
        @test parsePath("M 1 2 L 3 4").commands ==
            Float32[1.0, 1.0, 2.0, 2.0, 3.0, 4.0]
        @test parsePath("M 1 2 3 4").commands == # implicit LineTo
            Float32[1.0, 1.0, 2.0, 2.0, 3.0, 4.0]
        @test parsePath("M 1 2h 3V 4").commands ==
            Float32[1.0, 1.0, 2.0, 12.0, 3.0, 4.0, 4.0]
        @test parsePath("M 0 0 L 1 0 z").commands ==
            Float32[1.0, 0.0, 0.0, 2.0, 1.0, 0.0, 0.0]
        @test parsePath("H 2").commands == Float32[3.0, 2.0]

        # C/S/Q/T carry their parameters verbatim; implicit repeats stay cubic
        @test parsePath("M 0 0 C 1 1 2 2 3 3 4 4 5 5 6 6").commands ==
            Float32[1.0, 0.0, 0.0, 5.0, 1.0, 1.0, 2.0, 2.0, 3.0, 3.0, 5.0, 4.0, 4.0,
                5.0, 5.0, 6.0, 6.0]
        @test parsePath("M 1 1 S 3 3 5 5").commands ==
            Float32[1.0, 1.0, 1.0, 6.0, 3.0, 3.0, 5.0, 5.0]
        @test parsePath("M 1 1 Q 2 2 3 3 T 5 5").commands ==
            Float32[1.0, 1.0, 1.0, 7.0, 2.0, 2.0, 3.0, 3.0, 8.0, 5.0, 5.0]

        # arcs, absolute and relative, with the two arc flags
        @test parsePath("M 1 1 A 1 1 0 1 0 3 3").commands ==
            Float32[1.0, 1.0, 1.0, 9.0, 1.0, 1.0, 0.0, 1.0, 0.0, 3.0, 3.0]
        @test parsePath("M 1 1 a 1 1 0 0 1 2 0").commands ==
            Float32[1.0, 1.0, 1.0, 18.0, 1.0, 1.0, 0.0, 0.0, 1.0, 2.0, 0.0]
        # arc flags must be single digits: adjacent "11" parses as the
        # number 11 -> wrong parameter count (upstream quirk, errors)
        @test_throws ArgumentError parsePath("M 0 0 A 1 1 0 11 11 2 2")
        @test parsePath("M 0 0 A 1 1 0 1 1 2 2").commands ==
            Float32[1.0, 0.0, 0.0, 9.0, 1.0, 1.0, 0.0, 1.0, 1.0, 2.0, 2.0]

        # number edge cases
        @test parsePath("M 01.3 1 2").commands ==
            Float32[1.0, 0.0, 1.3, 2.0, 1.0, 2.0]
        @test parsePath("M 1.5e2 -3").commands ==
            Float32[1.0, 150.0, -3.0]
        @test parsePath("M 1 -1 2.5e-1 3").commands ==
            Float32[1.0, 1.0, -1.0, 2.0, 0.25, 3.0]
        @test parsePath("").commands == Float32[]
        @test parsePath("X").commands == Float32[] # garbage: nothing recorded
        @test parsePath("1 2 3 4").commands == Float32[]
        # M/L take parameters in pairs: an odd count is a parse error
        @test_throws ArgumentError parsePath("M -1 2 3")

        # malformed input
        @test_throws ArgumentError parsePath("M 1 2 X")
        @test_throws ArgumentError parsePath("M 1")
        @test_throws ArgumentError parsePath("C 1 2 3")
        # zero-parameter command with zero numbers -> zero batches -> nothing
        @test parsePath("H").commands == Float32[]
    end

    @testset "winding rules and solid fills" begin
        # fillPath is void and mutates the image
        img = newImage(1, 1)
        @test isnothing(fillPath(img, "M 0 0 L 1 0 L 1 1 L 0 1 Z", rgb(255, 255, 255)))
        @test px(img, 1, 1) == (255, 255, 255, 255)

        # 1x1 rect: the pixel is fully covered -> the solid color
        img = newImage(2, 1)
        fillPath(img, "M 0 0 L 1 0 L 1 1 L 0 1 Z", rgb(255, 5, 5))
        @test px(img, 1, 1) == (255, 5, 5, 255)
        @test px(img, 2, 1) == (0, 0, 0, 0)

        # the path object form fills identically
        p = newPath()
        rect(p, 0f0, 0f0, 1f0, 1f0)
        img = newImage(2, 1)
        fillPath(img, p, rgb(255, 5, 5))
        @test px(img, 1, 1) == (255, 5, 5, 255)

        # zero-alpha color is a no-op (upstream fillPath gate)
        img = newImage(1, 1)
        fillPath(img, "M 0 0 L 1 0 L 1 1 L 0 1 Z", rgba(255, 0, 0, 0))
        @test px(img, 1, 1) == (0, 0, 0, 0)

        # empty path / empty string are no-ops
        img = newImage(2, 2)
        fillPath(img, newPath(), rgb(255, 0, 0))
        fillPath(img, "", rgb(0, 255, 0))
        @test px(img, 1, 1) == (0, 0, 0, 0) && px(img, 2, 2) == (0, 0, 0, 0)

        # sub-pixel rect [0.25, 1.25]: the two pixels are covered by 0.75
        # and 0.25 -> alpha = area * 255 rounded: 191.25 -> 191, 63.75 -> 64;
        # red = 255 * cov / 255 = cov
        img = newImage(2, 1)
        q = newPath()
        rect(q, 0.25f0, 0f0, 1f0, 1f0)
        fillPath(img, q, rgb(255, 0, 0))
        @test px(img, 1, 1) == (191, 0, 0, 191)
        @test px(img, 2, 1) == (64, 0, 0, 64)

        # triangle (0,0)-(1,0)-(0,1): half of pixel (1,1), area 0.5 ->
        # alpha 127.5 -> 128; the color is (255,5,5,255) * 128/255
        for rule in (NonZero, EvenOdd)
            img = newImage(2, 2)
            fillPath(img, "M 0 0 L 1 0 L 0 1 Z", rgb(255, 5, 5), windingRule = rule)
            @test px(img, 1, 1) == (128, 3, 3, 128)
            @test px(img, 2, 1) == (0, 0, 0, 0)
            @test px(img, 1, 2) == (0, 0, 0, 0)
        end

        # two overlapping squares: NonZero union vs EvenOdd hole.
        # premultiplied rgba(255,255,255,128) = (128,128,128,128); a fully
        # covered pixel composites to itself over transparency.
        img = newImage(4, 2)
        fillPath(img, "M 0 0 L 2 0 L 2 2 L 0 2 Z M 1 0 L 3 0 L 3 2 L 1 2 Z",
            rgba(255, 255, 255, 128), windingRule = NonZero)
        @test [px(img, x, 1) for x in 1:4] ==
            [(128, 128, 128, 128), (128, 128, 128, 128), (128, 128, 128, 128), (0, 0, 0, 0)]
        img = newImage(4, 2)
        fillPath(img, "M 0 0 L 2 0 L 2 2 L 0 2 Z M 1 0 L 3 0 L 3 2 L 1 2 Z",
            rgba(255, 255, 255, 128), windingRule = EvenOdd)
        @test [px(img, x, 1) for x in 1:4] ==
            [(128, 128, 128, 128), (0, 0, 0, 0), (128, 128, 128, 128), (0, 0, 0, 0)]
    end

    @testset "fillPath transform and blend modes" begin
        # the transform applies exactly once: square [0,1] + (1,0) = [1,2]
        img = newImage(4, 1)
        rect_p = newPath()
        rect(rect_p, 0f0, 0f0, 1f0, 1f0)
        fillPath(img, rect_p, rgb(0, 255, 0), transform = translate(Vec2(1f0, 0f0)))
        @test [px(img, x, 1) for x in 1:4] ==
            [(0, 0, 0, 0), (0, 255, 0, 255), (0, 0, 0, 0), (0, 0, 0, 0)]

        # a scaled fill lands on the scaled span: [0,1] x 2 = [0,2]
        img = newImage(4, 1)
        fillPath(img, "M 0 0 L 1 0 L 1 1 L 0 1 Z", rgb(0, 255, 0),
            transform = scale(Vec2(2f0, 2f0)))
        @test [px(img, x, 1) for x in 1:4] ==
            [(0, 255, 0, 255), (0, 255, 0, 255), (0, 0, 0, 0), (0, 0, 0, 0)]

        # OverwriteBlend paints the premultiplied color directly (no blend)
        shapes = Vetra.commandsToShapes(parsePath("M 0 0 L 1 0 L 1 1 L 0 1 Z"), true, 1f0)
        img = newImage(2, 2)
        fill(img, rgb(255, 0, 0))
        Vetra.fillShapes(img, shapes, rgbx(128, 128, 128, 128), NonZero,
            blendMode = OverwriteBlend)
        @test px(img, 1, 1) == (128, 128, 128, 128) # direct paint over red
        @test px(img, 2, 2) == (255, 0, 0, 255) # untouched

        # NormalBlend is the default and blends over the backdrop
        img = newImage(2, 2)
        fill(img, rgb(255, 0, 0))
        fillPath(img, "M 0 0 L 1 0 L 1 1 L 0 1 Z", rgba(0, 255, 0, 128))
        # premultiplied source (0, 128, 0, 128) over red (255, 0, 0, 255),
        # k = 127: c = sc + (bc * k) div 255 per upstream blendNormal
        @test px(img, 1, 1) == (127, 128, 0, 255)
        @test px(img, 2, 2) == (255, 0, 0, 255)

        # unknown blend modes raise (20 is past the 0..19 enum)
        @test_throws ArgumentError Vetra.fillShapes(img, shapes, rgbx(128, 128, 128, 128),
            NonZero, blendMode = BlendMode(20))
    end

    @testset "curved fills stay inside their bounds" begin
        # Circle at (1.5, 1.5), r=1 (four cubic beziers). px(2,2) is the center
        # pixel (its farthest corner is 0.707 < 1) -> solid alpha. The two
        # diagonal corner pixels px(1,1) / px(3,3) each hold only a small
        # circular sliver (< ~1/4 pixel, symmetric) -> small positive alpha.
        # px(4,4) is outside the circle (nearest point 1.414 > 1 + margin) -> 0.
        img = newImage(4, 4)
        q = newPath()
        Vetra.circle(q, 1.5f0, 1.5f0, 1f0)
        fillPath(img, q, rgb(255, 0, 0))
        @test px(img, 2, 2) == (255, 0, 0, 255)
        @test 0 < px(img, 1, 1)[4] < 60
        @test px(img, 1, 1)[4] == px(img, 3, 3)[4] # symmetric slivers
        @test 0 < px(img, 3, 3)[4] < 60
        @test px(img, 4, 4) == (0, 0, 0, 0)

        # Diamond (square rotated 45 deg, circumradius 1) at (2, 2): the
        # straight edge x + y = 3 cuts px(2,2) exactly in half -> coverage of
        # about half the pixel (~128). px(1,1) left of the leftmost vertex
        # (x = 1) and px(4,4) above the topmost vertex (y = 3) -> outside.
        img = newImage(4, 4)
        q = newPath()
        polygon(q, 2f0, 2f0, 1f0, 4)
        fillPath(img, q, rgb(0, 255, 0))
        @test 100 <= px(img, 2, 2)[4] <= 156
        @test px(img, 1, 1) == (0, 0, 0, 0)
        @test px(img, 4, 4) == (0, 0, 0, 0)

        # Arc (full circle, r=1) centered on a *pixel corner* (2, 2): px(2,2)
        # then holds a quarter disk (pi/4 ~ 78% of the pixel) -> strongly
        # partial, well above half but not solid. px(4,4) is outside
        # (1.414 > 1 + margin).
        img = newImage(4, 4)
        q = newPath()
        arc(q, 2f0, 2f0, 1f0, 0f0, Float32(Vetra.TAU_F))
        fillPath(img, q, rgb(0, 0, 255))
        @test 150 <= px(img, 2, 2)[4] <= 240
        @test px(img, 4, 4) == (0, 0, 0, 0)
    end

    @testset "fillPath argument validation" begin
        img = newImage(1, 1)
        @test_throws ArgumentError fillPath(img, "M 0 0 L 1 1", "red")
        @test_throws ArgumentError fillPath(img, 42, rgb(1, 1, 1))
        @test_throws ArgumentError fillPath(img, "M 0 0 L 1 1", rgb(1, 1, 1),
            windingRule = WindingRule(2))
    end

    @testset "remaining command-builder branches" begin
        # arc into an already-started path lines to the arc start first
        a = newPath()
        moveTo(a, 9f0, 9f0)
        arc(a, 0f0, 0f0, 1f0, 0f0, Float32(Vetra.PI_F) / 2)
        @test [a.commands[1], a.commands[4], a.commands[7]] ==
            Float32[1.0, 2.0, 9.0] # Move + LineTo + Arc
        @test length(a.commands) == 3 + 3 + 8

        # a1 < a0 takes the long way: one 270deg arc, not a full circle
        a = newPath()
        arc(a, 0f0, 0f0, 1f0, Float32(Vetra.PI_F) / 2, 0f0)
        @test [a.commands[1], a.commands[4]] == Float32[1.0, 9.0]
        @test length(a.commands) == 3 + 8
        @test a.at == Vec2(1f0, 0f0)

        # arcTo: coincident corner is a no-op...
        a = newPath()
        moveTo(a, 2f0, 2f0)
        arcTo(a, 2f0, 2f0, 4f0, 4f0, 1f0)
        @test a.commands == Float32[1.0, 2.0, 2.0]
        # ...a zero radius falls back to the corner line
        a = newPath()
        moveTo(a, 0f0, 0f0)
        arcTo(a, 1f0, 0f0, 2f0, 0f0, 0f0)
        @test a.commands == Float32[1.0, 0.0, 0.0, 2.0, 1.0, 0.0]

        # counter-clockwise rect visits the other two corners first
        r = newPath()
        rect(r, 0f0, 0f0, 4f0, 3f0; clockwise = false)
        @test r.commands == Float32[
            1.0, 0.0, 0.0, 2.0, 0.0, 3.0, 2.0, 4.0, 3.0, 2.0, 4.0, 0.0, 0.0]

        # all-zero radii fall back to the plain rect; non-zero radii are
        # radiused (M + 4x(L + Cubic) + Z = 44 floats), clockwise or not
        z = newPath()
        rect(z, 0f0, 0f0, 4f0, 3f0)
        rr = newPath()
        roundedRect(rr, 0f0, 0f0, 4f0, 3f0, 0f0, 0f0, 0f0, 0f0)
        @test rr.commands == z.commands
        rr = newPath()
        roundedRect(rr, 0f0, 0f0, 4f0, 3f0, 1f0, 1f0, 1f0, 1f0;
            clockwise = false)
        @test length(rr.commands) == 3 + 4 * (3 + 7) + 1

        # a Close carrying parameters is a parse error
        @test_throws ArgumentError parsePath("M 0 0 L 1 1 Z 5")
        # a second decimal point ends the number; ".3" stays a valid one
        @test parsePath("M 1.2.3").commands == Float32[1.0, 1.2, 0.3]
        # relative curve commands parse verbatim
        @test parsePath("M 0 0 c 1 1 2 2 1 1 s 1 1 2 2 q 1 1 2 2 t 3 4").commands ==
            Float32[1.0, 0.0, 0.0,
                14.0, 1.0, 1.0, 2.0, 2.0, 1.0, 1.0,
                15.0, 1.0, 1.0, 2.0, 2.0,
                16.0, 1.0, 1.0, 2.0, 2.0,
                17.0, 3.0, 4.0]

        # transform applies to curve control points and endpoints (x2)
        p = parsePath("M 0 0 C 1 1 2 2 3 3 S 1 1 2 2 Q 1 1 2 2")
        transform(p, scale(Vec2(2f0, 2f0)))
        @test p.commands == Float32[
            1.0, 0.0, 0.0,
            5.0, 2.0, 2.0, 4.0, 4.0, 6.0, 6.0,
            6.0, 2.0, 2.0, 4.0, 4.0,
            7.0, 2.0, 2.0, 4.0, 4.0]
    end

    @testset "rasterizer internals (white-box)" begin
        # a fully clipped fill range is a no-op
        img = newImage(4, 4)
        fill(img, rgb(255, 0, 0))
        Vetra.fillRowRange(img, rgbx(0, 255, 0, 255), 0, 10, 4, 11)
        @test px(img, 1, 1) == (255, 0, 0, 255) &&
            px(img, 4, 4) == (255, 0, 0, 255)

        # a line/segment pair that does not meet returns the origin point
        @test Vetra.lineSegmentPoint(
                line(Vec2(0f0, 0f0), Vec2(1000f0, 0f0)),
                segment(Vec2(2f0, 1f0), Vec2(3f0, 2f0))) == Vec2(0f0, 0f0)

        # NaN coordinates collapse to the zero rect so the fill no-ops
        @test Vetra.computeBoundsOfSegments(
                Vetra.SegW[Vetra.SegW(
                    Vetra.Segment(Vec2(NaN32, 0f0), Vec2(1f0, 1f0)), Int16(1))]) ==
            Rect(0f0, 0f0, 0f0, 0f0)

        # a canceling touch pair (two hits on one x, windings +1/-1) is
        # consumed together: no fill span on either side, nothing painted
        hits = Vetra.Hit[
            Vetra.Hit(Int32(1), Int16(1)),
            Vetra.Hit(Int32(1), Int16(1)),
            Vetra.Hit(Int32(1), Int16(-1))]
        for rule in (NonZero, EvenOdd)
            @test Vetra.walk(hits, 3, rule) == NTuple{3, Int}[]
        end

        # Overwrite writes the coverage-scaled color exactly (0xFF -> full)
        img = newImage(4, 1)
        fill(img, rgb(255, 0, 0))
        Vetra.fillCoverageLine(img, rgbx(0, 255, 0, 255), 0, 0,
            UInt8[0x00, 0xFF, 0x00, 0x00], OverwriteBlend)
        @test px(img, 1, 1) == (255, 0, 0, 255)
        @test px(img, 2, 1) == (0, 255, 0, 255)
        @test px(img, 4, 1) == (255, 0, 0, 255)

        # area-based solid pixels: 1.0 keeps the color, 0.0 clears it
        img = newImage(2, 1)
        Vetra._blendFillPixel(img, 0, 0, rgbx(0, 0, 255, 255), 1f0, OverwriteBlend)
        @test px(img, 1, 1) == (0, 0, 255, 255)
        Vetra._blendFillPixel(img, 1, 0, rgbx(0, 0, 255, 255), 0f0, OverwriteBlend)
        @test px(img, 2, 1) == (0, 0, 0, 0)

        # unknown blend modes raise wherever coverage is applied
        @test_throws ArgumentError Vetra.fillCoverageLine(
            newImage(1, 1), rgbx(0, 255, 0, 255), 0, 0,
            UInt8[0xFF], BlendMode(20))
        @test_throws ArgumentError Vetra._blendFillPixel(
            newImage(1, 1), 0, 0, rgbx(0, 0, 255, 255), 0.5f0, BlendMode(20))
        @test_throws ArgumentError Vetra.fillHitsLine(
            newImage(1, 1), rgbx(0, 0, 255, 255), 0, 0, 1, BlendMode(20))

        # svgAngle is signed: below the x-axis is negative
        @test abs(Vetra.svgAngle(Vec2(1f0, 0f0), Vec2(0f0, 1f0)) -
            Float32(pi / 2)) < 1e-4
        @test abs(Vetra.svgAngle(Vec2(1f0, 0f0), Vec2(0f0, -1f0)) +
            Float32(pi / 2)) < 1e-4

        # endpoints farther apart than 2r force the radii up (SVG 8.3.3);
        # the sweep flag decides the delta sign
        par = Vetra.endpointToCenterArcParams(
            Vec2(0f0, 0f0), Vec2(1f0, 1f0), 0f0, false, true, Vec2(10f0, 0f0))
        @test par.radii.x > 1f0 && par.radii.y > 1f0
        @test abs(par.radii.x - 5f0) < 1e-4 # sqrt(10^2/4/1) = 5
        @test par.delta > 0f0
        par = Vetra.endpointToCenterArcParams(
            Vec2(0f0, 0f0), Vec2(1f0, 1f0), 0f0, false, false, Vec2(10f0, 0f0))
        @test par.delta < 0f0
    end

    @testset "every command kind rasterizes" begin
        # one sweep over each command family: H/V, C/S (S after a curve and
        # standalone), Q/T (T after a curve and standalone), the relative
        # m/l/h/v and c/s/q/t families (m bare-M into an open sub-path),
        # relative arcs, both sweep directions
        s = "M 2 2 H 6 V 6 L 2 6 Z"
        s *= " M 2 10 C 2 2 3 2 3 10 S 4 18 4 10 Z"
        s *= " M 2 10 S 3 2 4 10 Z"
        s *= " M 2 10 Q 3 2 4 10 T 6 10 Z"
        s *= " M 2 10 T 3 6 Z"
        s *= " M 1 1 L 3 3 M 5 5 L 7 7 Z"
        s *= " M 6 6 l 1 1 m 1 1 l 1 1 h 1 v 1 z"
        s *= " M 2 2 q 3 2 4 3 t 6 4 z"
        s *= " M 2 2 c 1 -2 2 2 2 3 s 1 1 2 1 t 1 2 z"
        s *= " M 2 2 a 1 1 0 0 1 2 0 z"
        s *= " M 6 6 a 1 1 0 0 0 2 0 z"
        s *= " M 2 10 Q 30 -30 8 10 Z" # strongly bent: multiple arc steps
        img = newImage(16, 16)
        @test isnothing(fillPath(img, s, rgb(255, 100, 0)))
        @test any(px(img, x, y)[4] > 0 for x in 1:16 for y in 1:16)
    end

    @testset "multi-partition fills" begin
        # two sub-rects in one image: 8 vertical edges -> 2 partitions.
        # Under NonZero the union is [1,9) x [1,9): a solid 8x8 block,
        # pixel-exact (axis-aligned edges, no AA).
        img = newImage(10, 10)
        fillPath(img, "M 1 1 L 9 1 L 9 9 L 1 9 Z M 2 1 L 8 1 L 8 9 L 2 9 Z",
            rgb(255, 0, 0))
        for x in 1:10
            for y in 1:10
                inside = 2 <= x <= 9 && 2 <= y <= 9
                @test px(img, x, y) == (inside ? (255, 0, 0, 255) : (0, 0, 0, 0))
            end
        end
        @test count(((xy)) -> px(img, xy[1], xy[2])[4] == 255,
            [(x, y) for x in 1:10 for y in 1:10]) == 64
    end
end
