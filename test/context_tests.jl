# T005: solid Paint, stroke geometry (caps/joins/dashes), minimal Context.
# Expectations come from hand-derived region geometry (upstream paths.nim
# strokeShapes L1938-2098) for the cap/join/dash pixel checks and from the
# approved square/line fixtures (upstream square.nim / line.nim, T001
# oracle) for the example flows -- never from the code under test.

@testset "T005 strokes and context" begin
    px = (img, x, y) -> (c = getColor(img, x, y);
        (Int(c.r), Int(c.g), Int(c.b), Int(c.a)))
    # ------------------------------------------------------------- paints
    @testset "Paint and color conversion (paints.nim + chroma)" begin
        p = Paint(rgba(0xff, 0x80, 0x20, 0xff))
        @test p.color == ColorRGBA(0xff, 0x80, 0x20, 0xff)
        @test p.opacity == Float32(1)
        @test p.blendMode === NormalBlend

        @test Paint(rgb(1, 2, 3)).color == ColorRGBA(1, 2, 3, 0xff)
        # Prevalidated premul (r, g, b <= a) through the rgba pipeline:
        # a = 64; multiplier = round(255/64*255) = 1016;
        # r = (32*1016+127) div 255 = 127, g = (64*1016+127) div 255 = 255,
        # b = (48*1016+127) div 255 = 191
        @test Paint(rgbx(0x20, 0x40, 0x30, 0x40)).color ==
            ColorRGBA(127, 255, 191, 64)

        q = copy(p)
        @test q.color == p.color && q.opacity == p.opacity
        q.opacity = 0f0
        @test p.opacity == Float32(1)  # independent copy (upstream `copy`)

        # Hex parsing: #RRGGBB and #RGB tiny (chroma parseHtmlHexTiny:
        # channel = round(d / 15 * 255), e.g. #f00 -> (255, 0, 0)).
        @test parseHtmlColor("#FF5C00") == ColorRGBA(0xff, 0x5c, 0x00, 0xff)
        @test parseHtmlColor("#ff5c00") == ColorRGBA(0xff, 0x5c, 0x00, 0xff)
        @test parseHtmlColor(" #FF5C00 ") == ColorRGBA(0xff, 0x5c, 0x00, 0xff)
        @test parseHtmlColor("#F00") == ColorRGBA(0xff, 0x00, 0x00, 0xff)
        @test Paint("#FF5C00").color == parseHtmlColor("#FF5C00")
        # CSS #RGB == #RRGGBB with repeated digits: d/15*255 = d*17
        @test parseHtmlColor("#AbC") == ColorRGBA(0xaa, 0xbb, 0xcc, 0xff)

        @test_throws ArgumentError parseHtmlColor("")
        @test_throws ArgumentError parseHtmlColor("FF5C00")  # no '#'
        @test_throws ArgumentError parseHtmlColor("#FF5C0")    # length 6
        @test_throws ArgumentError parseHtmlColor("#FF5C000")  # length 8
        @test_throws ArgumentError parseHtmlColor("#12345")    # length 5
        @test_throws ArgumentError parseHtmlColor("#FF5C0G")   # not hex
        @test_throws ArgumentError Paint("#1245x7")            # bad digit
        # Named CSS colors (chroma colorNames, ported for SVG; T008):
        @test parseHtmlColor("red") == ColorRGBA(0xff, 0x00, 0x00, 0xff)
        @test parseHtmlColor("navy") == ColorRGBA(0x00, 0x00, 0x80, 0xff)
        @test parseHtmlColor("Navy") == ColorRGBA(0x00, 0x00, 0x80, 0xff) # ASCII case-insensitive
        @test_throws ArgumentError parseHtmlColor("notacolor")  # unknown name
        # rgb()/rgba() forms:
        @test parseHtmlColor("rgb(255, 0, 0)") == ColorRGBA(0xff, 0x00, 0x00, 0xff)
        @test parseHtmlColor("rgba(0, 0, 255, 0.5)") == ColorRGBA(0x00, 0x00, 0xff, 0x80)

        # convert(Paint, ...) -- upstream parseSomePaint solid cases
        @test convert(Paint, p) === p
        @test convert(Paint, rgb(9, 8, 7)).color == ColorRGBA(9, 8, 7, 0xff)
        @test convert(Paint, rgba(9, 8, 7, 6)).color == ColorRGBA(9, 8, 7, 6)
        @test convert(Paint, "#112233").color == ColorRGBA(0x11, 0x22, 0x33, 0xff)
        @test_throws ArgumentError convert(Paint, 42)
        @test_throws ArgumentError convert(Paint, Vec2(1f0, 1f0))

        # Effective premultiplied color: a = round(128/255*0.5*255) = 64,
        # then (c*a+127) div 255: (64, 32, 8) with a = 64.
        ho = Paint(rgba(0xff, 0x80, 0x20, 0x80); opacity = 0.5f0)
        @test Vetra.solidColorRGBX(ho) == ColorRGBX(0x40, 0x20, 0x08, 0x40)
    end

    @testset "fillPath (solid Paint form)" begin
        # 8x6 rect at (10,10): exact coverage region x [10,18] x y [10,16].
        img = newImage(64, 64)
        fill(img, rgba(0xff, 0xff, 0xff, 0xff))
        op = Paint(rgba(0xff, 0x00, 0x00, 0xff))
        r = newPath()
        rect(r, 10f0, 10f0, 8f0, 6f0)
        fillPath(img, r, op)
        @test px(img, 15, 13) == (255, 0, 0, 255)
        @test px(img, 11, 11) == (255, 0, 0, 255)  # corner pixel, fully inside
        @test px(img, 19, 13) == (255, 255, 255, 255)  # outside
        @test px(img, 15, 17) == (255, 255, 255, 255)  # outside

        # String path (parsePath) paints the same region.
        img2 = newImage(64, 64)
        fill(img2, rgba(0xff, 0xff, 0xff, 0xff))
        fillPath(img2, "M 10 10 L 18 10 L 18 16 L 10 16 Z", op)
        @test px(img2, 15, 13) == (255, 0, 0, 255)
        @test px(img2, 19, 13) == (255, 255, 255, 255)

        # EvenOdd arm + windingRule validation.
        img3 = newImage(64, 64)
        fill(img3, rgba(0xff, 0xff, 0xff, 0xff))
        fillPath(img3, r, op, windingRule = EvenOdd)
        @test px(img3, 15, 13) == (255, 0, 0, 255)
        @test_throws ArgumentError fillPath(img3, r, op, windingRule = WindingRule(5))

        # Transform arm: rect (0,0,4,4) moved by (8,8) covers [8,12]x[8,12].
        img4 = newImage(64, 64)
        fill(img4, rgba(0xff, 0xff, 0xff, 0xff))
        gr = newPath()
        rect(gr, 0f0, 0f0, 4f0, 4f0)
        fillPath(img4, gr, op, transform = translate(Vec2(8f0, 8f0)))
        @test px(img4, 9, 9) == (255, 0, 0, 255)
        @test px(img4, 17, 9) == (255, 255, 255, 255)

        # Bad path type.
        @test_throws ArgumentError fillPath(img, 42, op)

        # opacity is clamped in place; 0 opacity is a no-op.
        hi = Paint(rgba(0, 0, 255, 0xff); opacity = 3f0)
        img5 = newImage(64, 64)
        fill(img5, rgba(0, 0, 255, 0xff))
        fillPath(img5, r, hi)
        @test hi.opacity == Float32(1)
        @test px(img5, 15, 13) == (0, 0, 255, 255)  # clamped to opacity 1
        before = copy(img5)
        lo = Paint(rgba(255, 0, 0, 0xff); opacity = -0.5f0)
        fillPath(img5, r, lo)
        @test lo.opacity == Float32(0)
        @test img5.data == before.data  # no-op

        # Zero-alpha solid: no-op under NormalBlend, clears under Overwrite.
        img6 = newImage(64, 64)
        fill(img6, rgba(0, 255, 0, 0xff))
        fillPath(img6, r, Paint(rgba(255, 0, 0, 0)))
        @test px(img6, 15, 13) == (0, 255, 0, 255)
        fillPath(img6, r, Paint(rgba(0, 0, 0, 0); blendMode = OverwriteBlend))
        @test px(img6, 15, 13) == (0, 0, 0, 0)
        @test px(img6, 3, 3) == (0, 255, 0, 255)
    end

    # ------------------------------------------------------- strokeShapes
    @testset "strokeShapes (paths.nim L1938-2098)" begin
        seg = [Vec2(0f0, 0f0), Vec2(10f0, 0f0)]
        # 10x4 strip: makeRect hand-derivation for (0,0)->(10,0), w 4:
        # corners (0,-2) (10,-2) (10,2) (0,2) + close.
        @test strokeShapes([seg], 4f0, ButtCap, MiterJoin, 4f0, Float32[], 1f0) ==
            [[Vec2(0f0, -2f0), Vec2(10f0, -2f0), Vec2(10f0, 2f0),
              Vec2(0f0, 2f0), Vec2(0f0, -2f0)]]
        # non-positive width -> empty (upstream early return)
        @test isempty(strokeShapes([seg], 0f0, ButtCap, MiterJoin, 4f0, Float32[], 1f0))
        @test isempty(strokeShapes([seg], -2f0, ButtCap, MiterJoin, 4f0, Float32[], 1f0))
        # caps: butt = 1 polygon; round/square = cap + edge + cap
        @test length(strokeShapes([seg], 4f0, RoundCap, MiterJoin, 4f0, Float32[], 1f0)) == 3
        @test length(strokeShapes([seg], 4f0, SquareCap, MiterJoin, 4f0, Float32[], 1f0)) == 3
        # square cap geometry: edge + (-2..0) and (10..12) extension rects
        sq = strokeShapes([seg], 4f0, SquareCap, MiterJoin, 4f0, Float32[], 1f0)
        @test sq[1] == [Vec2(-2f0, -2f0), Vec2(0f0, -2f0),
            Vec2(0f0, 2f0), Vec2(-2f0, 2f0), Vec2(-2f0, -2f0)]
        @test sq[2] == [Vec2(0f0, -2f0), Vec2(10f0, -2f0),
            Vec2(10f0, 2f0), Vec2(0f0, 2f0), Vec2(0f0, -2f0)]
        @test sq[3] == [Vec2(12f0, 2f0), Vec2(10f0, 2f0),
            Vec2(10f0, -2f0), Vec2(12f0, -2f0), Vec2(12f0, 2f0)]

        # 90-degree corner at (10,10), arms to (0,10) and (10,0), w 4:
        # turn = +pi/2 -> a (0,2) -> after sign flip (0,-2) ...
        # hand-derived: la = x=12 line y in [10,12]?? computed below.
        corner = [Vec2(0f0, 10f0), Vec2(10f0, 10f0), Vec2(10f0, 0f0)]
        # MiterJoin, limit 10 (limit angle 0.20 < pi/2 -> no fallback):
        # a (0,2) -> after sign flip (0,-2) ...
        # turn = +pi/2: a (0,2) -> (0,-2)? see miter arm: a = (-a.y, a.x).
        # a = normalize(pos-prevPos)*2 (2,0) -> (0,2); b = normalize(pos-nextPos)*2
        # (0,2) -> (2,0). la = (0,12)-(10,12) [y=12]; lb = (12,0)-(12,10) [x=12];
        # at (12,12); polygon [pos+a (0,12)?? pos=(10,10): pos+a = (10,12),
        # at = (12, 12), pos+b = (12,10), pos, pos+a].
        m = strokeShapes([corner], 4f0, ButtCap, MiterJoin, 10f0, Float32[], 1f0)
        @test length(m) == 3
        @test m[2] == [Vec2(10f0, 12f0), Vec2(12f0, 12f0),
            Vec2(12f0, 10f0), Vec2(10f0, 10f0), Vec2(10f0, 12f0)]
        # miter-limit fallback: limit 1 -> limit angle pi/1?? (2*asin(1) = pi)
        # > pi/2 turn -> BevelJoin; bevel triangle [a+pos, b+pos, pos].
        be = strokeShapes([corner], 4f0, ButtCap, MiterJoin, 1f0, Float32[], 1f0)
        @test be[2] == [Vec2(10f0, 12f0), Vec2(12f0, 10f0),
            Vec2(10f0, 10f0), Vec2(10f0, 12f0)]
        # explicit BevelJoin, no fallback needed
        bv = strokeShapes([corner], 4f0, ButtCap, BevelJoin, 10f0, Float32[], 1f0)
        @test bv[2] == [Vec2(10f0, 12f0), Vec2(12f0, 10f0),
            Vec2(10f0, 10f0), Vec2(10f0, 12f0)]
        # RoundJoin: circle polygon instead of angle math; with RoundCap:
        # first cap + 2 edges + join circle + end cap = 5
        @test length(strokeShapes([corner], 4f0, RoundCap, RoundJoin, 10f0, Float32[], 1f0)) == 5
        # Bevel area below minArea (0.2) -> join dropped: w 1 -> hs 0.5,
        # areaSq = 0.25 * 0.25 * 0.25 = 0.0156 < 0.04 -> 2 edge rects only.
        @test length(strokeShapes([corner], 1f0, ButtCap, BevelJoin, 10f0, Float32[], 1f0)) == 2
        # Miter area below minArea -> quad dropped: sharp 0.1 rad turn,
        # w 0.2 -> hs 0.1, |at-pos| = hs/sin(0.05);
        # areaSq = 50*hs^4 = 0.005 < 0.04 with miterLimit 50 (angle 0.04 < 0.1).
        shp = [
            Vec2(10f0 * cos(-Float32(0.05)) , 10f0 * sin(-Float32(0.05))),
            Vec2(0f0, 0f0),
            Vec2(10f0 * cos(Float32(0.05)), 10f0 * sin(Float32(0.05)))]
        @test length(strokeShapes([shp], 0.2f0, ButtCap, MiterJoin, 50f0, Float32[], 1f0)) == 2
        @test length(strokeShapes([shp], 8f0, ButtCap, MiterJoin, 50f0, Float32[], 1f0)) == 3

        # Round join circle skipped when its area <= minArea, but upstream
        # RoundCap has no area guard, so caps still draw: 2 edges + 2 caps.
        @test length(strokeShapes([corner], 0.01f0, RoundCap, RoundJoin, 10f0, Float32[], 1f0)) == 4
        # Collinear corners produce no join (|turn| ~= pi within epsilon).
        ln = [Vec2(0f0, 0f0), Vec2(3f0, 0f0), Vec2(7f0, 0f0), Vec2(10f0, 0f0)]
        @test length(strokeShapes([ln], 4f0, ButtCap, MiterJoin, 10f0, Float32[], 1f0)) == 3

        # Closed square: 4 edges + 4 joins; no caps.
        sq2 = [Vec2(0f0, 0f0), Vec2(10f0, 0f0), Vec2(10f0, 10f0),
            Vec2(0f0, 10f0), Vec2(0f0, 0f0)]
        @test length(strokeShapes([sq2], 4f0, ButtCap, BevelJoin, 10f0, Float32[], 1f0)) == 8

        # dashes: 12-long segment, draw/gap 3/1 -> rects at [0,3] [4,7] [8,11]
        seg12 = Vector{Vec2}([Vec2(0f0, 0f0), Vec2(12f0, 0f0)])
        d1 = strokeShapes([seg12], 4f0, ButtCap, MiterJoin, 10f0, Float32[3f0, 1f0], 1f0)
        @test d1 == [
            [Vec2(0f0, -2f0), Vec2(3f0, -2f0), Vec2(3f0, 2f0), Vec2(0f0, 2f0), Vec2(0f0, -2f0)],
            [Vec2(4f0, -2f0), Vec2(7f0, -2f0), Vec2(7f0, 2f0), Vec2(4f0, 2f0), Vec2(4f0, -2f0)],
            [Vec2(8f0, -2f0), Vec2(11f0, -2f0), Vec2(11f0, 2f0), Vec2(8f0, 2f0), Vec2(8f0, -2f0)]]
        # odd dash list duplicated once: [3,1,2] -> [3,1,2,3,1,2],
        # 12 drawn in one path: [0,3] gap [4,6] gap ... -> [0,3] [4,6] [9,10]
        d2 = strokeShapes([seg12], 4f0, ButtCap, MiterJoin, 10f0, Float32[3f0, 1f0, 2f0], 1f0)
        @test length(d2) == 3
        @test d2[1] == [Vec2(0f0, -2f0), Vec2(3f0, -2f0), Vec2(3f0, 2f0), Vec2(0f0, 2f0), Vec2(0f0, -2f0)]
        @test d2[2] == [Vec2(4f0, -2f0), Vec2(6f0, -2f0), Vec2(6f0, 2f0), Vec2(4f0, 2f0), Vec2(4f0, -2f0)]
        @test d2[3] == [Vec2(9f0, -2f0), Vec2(10f0, -2f0), Vec2(10f0, 2f0), Vec2(9f0, 2f0), Vec2(9f0, -2f0)]
        # multiple dash passes: [2,1] over 12 -> 4 draws, the while loop restarts
        d3 = strokeShapes([seg12], 4f0, ButtCap, MiterJoin, 10f0, Float32[2f0, 1f0], 1f0)
        @test d3 == [
            [Vec2(0f0, -2f0), Vec2(2f0, -2f0), Vec2(2f0, 2f0), Vec2(0f0, 2f0), Vec2(0f0, -2f0)],
            [Vec2(3f0, -2f0), Vec2(5f0, -2f0), Vec2(5f0, 2f0), Vec2(3f0, 2f0), Vec2(3f0, -2f0)],
            [Vec2(6f0, -2f0), Vec2(8f0, -2f0), Vec2(8f0, 2f0), Vec2(6f0, 2f0), Vec2(6f0, -2f0)],
            [Vec2(9f0, -2f0), Vec2(11f0, -2f0), Vec2(11f0, 2f0), Vec2(9f0, 2f0), Vec2(9f0, -2f0)]]
        # caller's dash array is copied, not mutated (upstream `var dashes = dashes`)
        src = Float32[3f0, 1f0]
        strokeShapes([seg12], 4f0, ButtCap, MiterJoin, 10f0, src, 1f0)
        @test src == Float32[3f0, 1f0]
        # non-positive dash values raise (upstream "Invalid line dash value",
        # also for the odd-duplicated case)
        @test_throws ArgumentError strokeShapes([seg12], 4f0, ButtCap, MiterJoin, 10f0, Float32[0f0, 1f0], 1f0)
        @test_throws ArgumentError strokeShapes([seg12], 4f0, ButtCap, MiterJoin, 10f0, Float32[1f0, -1f0], 1f0)
        @test_throws ArgumentError strokeShapes([seg12], 4f0, ButtCap, MiterJoin, 10f0, Float32[-1f0], 1f0)
    end

    @testset "miter/angle helpers (paths.nim L1930-1936, vmath fixAngle)" begin
        L = Float32(4)
        # asin(1/4) = 0.25268033 rad (hand value)
        @test abs(miterLimitToAngle(L) - Float32(0.50536066)) < Float32(1e-6)
        @test abs(angleToMiterLimit(miterLimitToAngle(L)) - L) < Float32(1e-4)
        @test abs(angleToMiterLimit(miterLimitToAngle(Float32(10))) -
            Float32(10)) < Float32(1e-4)
        @test defaultMiterLimit == Float32(4)
        @test Vetra.fixAngle(1f0) == 1f0
        @test Vetra.fixAngle(Vetra.PI_F) == Vetra.PI_F     # > PI is false at exactly PI
        @test Vetra.fixAngle(-Vetra.PI_F) == Vetra.PI_F    # <= -PI wraps around
        @test Vetra.fixAngle(4f0) == 4f0 - Vetra.TAU_F
        @test Vetra.fixAngle(-4f0) == -4f0 + Vetra.TAU_F
        @test Vetra.fixAngle(3.2f0) == 3.2f0 - Vetra.TAU_F
        @test Vetra.fixAngle(-3.2f0) == -3.2f0 + Vetra.TAU_F
        # bumpy intersects(Line, Line)
        @test Vetra._lineIntersect(
            line(Vec2(0f0, 0f0), Vec2(1f0, 0f0)),
            line(Vec2(0.5f0, 0.5f0), Vec2(0.5f0, -0.5f0))) == (true, Vec2(0.5f0, 0f0))
        @test Vetra._lineIntersect(
            line(Vec2(0f0, 0f0), Vec2(1f0, 0f0)),
            line(Vec2(0f0, 1f0), Vec2(1f0, 1f0))) == (false, Vec2())
    end

    @testset "strokePath (paints.nim L2160-2192)" begin
        op = Paint(rgba(0xff, 0x00, 0x00, 0xff))

        # Default strokeWidth 1: a vertical at x = 10 covers x in [9.5, 10.5];
        # cell (i, j) is region [i - 1, i] x [j - 1, j].
        img = newImage(64, 64)
        fill(img, rgba(0xff, 0xff, 0xff, 0xff))
        p = newPath()
        moveTo(p, 10f0, 10f0)
        lineTo(p, 10f0, 20f0)
        strokePath(img, p, op)
        # Cell (10,15) = [9,10]x[14,15]: the [9.5,10] half is covered, so the
        # 50% red blend over white leaves the green channel between 0 and 255.
        @test 0 < px(img, 10, 15)[2] < 255
        @test px(img, 12, 15) == (255, 255, 255, 255)  # outside the strip

        # Horizontal segment at y = 12, w 4: body x [10,20] x y [10,14];
        # round caps are radius-2 circles at (10,12) and (20,12); square caps
        # extend to x [8,10] and x [20,22].
        hx = (cap) -> begin
            h = newImage(32, 32)
            fill(h, rgba(0xff, 0xff, 0xff, 0xff))
            hp = newPath()
            moveTo(hp, 10f0, 12f0)
            lineTo(hp, 20f0, 12f0)
            strokePath(h, hp, op, strokeWidth = 4f0, lineCap = cap)
            h
        end
        # Body, fully covered for every cap.
        @test px(hx(ButtCap), 15, 12) == (255, 0, 0, 255)
        @test px(hx(RoundCap), 15, 12) == (255, 0, 0, 255)
        @test px(hx(SquareCap), 15, 12) == (255, 0, 0, 255)
        # Butt: the strip stops exactly at x = 10/20.
        @test px(hx(ButtCap), 21, 12) == (255, 255, 255, 255)  # [20,21]x[11,12]
        @test px(hx(ButtCap), 9, 12) == (255, 255, 255, 255)   # [8,9]x[11,12]
        # Round: cell (21,12) = [20,21]x[11,12] is fully inside the cap circle
        # (far corner d = sqrt(2) < 2); cell (22,12) is strictly partial
        # ((21,11) d = sqrt(2) < 2, (22,11) d = sqrt(5) > 2); cells (23,12) and
        # (8,12) are outside (nearest corner d = 2 -> measure zero).
        @test px(hx(RoundCap), 21, 12) == (255, 0, 0, 255)
        @test 0 < px(hx(RoundCap), 22, 12)[2] < 255
        @test px(hx(RoundCap), 23, 12) == (255, 255, 255, 255)
        @test px(hx(RoundCap), 8, 12) == (255, 255, 255, 255)
        # Square: extensions [8,10]x[10,14] and [20,22]x[10,14].
        @test px(hx(SquareCap), 9, 12) == (255, 0, 0, 255)
        @test px(hx(SquareCap), 21, 12) == (255, 0, 0, 255)
        @test px(hx(SquareCap), 22, 12) == (255, 0, 0, 255)
        @test px(hx(SquareCap), 8, 12) == (255, 255, 255, 255)
        @test px(hx(SquareCap), 23, 12) == (255, 255, 255, 255)

        # 90-degree elbow: (20,10) -> (20,20) -> (30,20), w 4. Arms:
        # x [18,22] x y [10,20] and x [20,30] x y [18,22]; join area
        # x [18,20] x y [20,22].
        ex = (join, limit) -> begin
            e = newImage(32, 32)
            fill(e, rgba(0xff, 0xff, 0xff, 0xff))
            ep = newPath()
            moveTo(ep, 20f0, 10f0)
            lineTo(ep, 20f0, 20f0)
            lineTo(ep, 30f0, 20f0)
            strokePath(e, ep, op, strokeWidth = 4f0, lineJoin = join,
                miterLimit = limit)
            e
        end
        # Cell (20,21) = [19,20]x[20,21] is inside every join shape.
        @test px(ex(MiterJoin, 10f0), 20, 21) == (255, 0, 0, 255)
        @test px(ex(RoundJoin, 10f0), 20, 21) == (255, 0, 0, 255)
        @test px(ex(BevelJoin, 10f0), 20, 21) == (255, 0, 0, 255)
        @test px(ex(MiterJoin, 10f0), 21, 13) == (255, 0, 0, 255)  # vertical arm
        @test px(ex(MiterJoin, 10f0), 25, 20) == (255, 0, 0, 255)  # horizontal arm
        # Miter (limit 10, turn pi/2 > limit angle 2*asin(0.1) so no fallback)
        # fills the tip quad [18,20]x[20,22]; cell (19,21) is fully inside.
        @test px(ex(MiterJoin, 10f0), 19, 21) == (255, 0, 0, 255)
        # Miter limit 1 (limit angle pi) falls back to the bevel triangle
        # (18,20),(20,22),(20,20); cell (19,21) sits half under the y = x+2
        # edge -> strictly partial.
        @test 0 < px(ex(MiterJoin, 1f0), 19, 21)[2] < 255
        # Round join draws the radius-2 circle at (20,20); cell (19,21)
        # partial ((19,20) d = 1 < 2, (18,21) d = sqrt(5) > 2).
        @test 0 < px(ex(RoundJoin, 10f0), 19, 21)[2] < 255
        @test 0 < px(ex(BevelJoin, 10f0), 19, 21)[2] < 255
        # Outside the elbow for every join.
        @test px(ex(MiterJoin, 10f0), 15, 25) == (255, 255, 255, 255)
        @test px(ex(RoundJoin, 10f0), 15, 25) == (255, 255, 255, 255)

        # Zero-opacity no-op (clamp in place), zero-alpha normal no-op,
        # zero-alpha overwrite clears the stroke band.
        z = newImage(64, 64)
        fill(z, rgba(0x10, 0x20, 0x30, 0xff))
        before = copy(z)
        zop = Paint(rgba(0xff, 0, 0, 0xff); opacity = -3f0)
        strokePath(z, p, zop)
        @test zop.opacity == Float32(0)
        @test z.data == before.data

        za = newImage(64, 64)
        fill(za, rgba(0xff, 0, 0, 0xff))
        r2 = newPath()
        rect(r2, 8f0, 8f0, 8f0, 8f0)
        strokePath(za, r2, Paint(rgba(0, 0, 0, 0)), strokeWidth = 4f0)
        @test px(za, 9, 12) == (255, 0, 0, 255)  # not drawn
        strokePath(za, r2, Paint(rgba(0, 0, 0, 0); blendMode = OverwriteBlend),
            strokeWidth = 4f0)
        @test px(za, 9, 12) == (0, 0, 0, 0)      # cleared
        @test px(za, 12, 12) == (255, 0, 0, 255) # interior untouched

        # Invalid path type; string path; transformed strokes.
        @test_throws ArgumentError strokePath(z, 42, op)

        s = newImage(64, 64)
        fill(s, rgba(0xff, 0xff, 0xff, 0xff))
        strokePath(s, "M 12 12 L 20 12", Paint(rgba(0, 0, 255, 0xff)),
            strokeWidth = 2f0)
        @test px(s, 16, 12) == (0, 0, 255, 255)
        @test px(s, 16, 14) == (255, 255, 255, 255)  # [15,16]x[13,14] outside

        t = newImage(64, 64)
        fill(t, rgba(0xff, 0xff, 0xff, 0xff))
        tp = newPath()
        moveTo(tp, 0f0, 8f0)
        lineTo(tp, 4f0, 8f0)
        strokePath(t, tp, Paint(rgba(0, 0, 255, 0xff)),
            transform = translate(Vec2(10f0, 10f0)), strokeWidth = 2f0)
        # Band [0,4]x[7,9] moved to [10,14]x[17,19].
        @test px(t, 12, 18) == (0, 0, 255, 255)   # inside the moved band
        @test px(t, 2, 8) == (255, 255, 255, 255)  # untransformed position

        # dashes through the public entry point; band y [1,3]
        dd = newImage(24, 32)
        fill(dd, rgba(0xff, 0xff, 0xff, 0xff))
        dp = newPath()
        moveTo(dp, 0f0, 2f0)
        lineTo(dp, 12f0, 2f0)
        strokePath(dd, dp, op, strokeWidth = 2f0, dashes = Float32[3f0, 1f0])
        # dash [3,1] over 12 -> bands [0,3] [4,7] [8,11]
        @test px(dd, 1, 2) == (255, 0, 0, 255)             # [0,3]
        @test px(dd, 4, 2) == (255, 255, 255, 255)         # gap [3,4]
        @test px(dd, 6, 2) == (255, 0, 0, 255)             # [4,7]
        @test px(dd, 7, 2) == (255, 0, 0, 255)             # [6,7]
        @test px(dd, 8, 2) == (255, 255, 255, 255)         # gap [7,8]
        @test px(dd, 10, 2) == (255, 0, 0, 255)            # [8,11]
        @test px(dd, 12, 2) == (255, 255, 255, 255)        # past the last dash
    end

    # -------------------------------------------------------------- context
    @testset "Context state (contexts.nim L17-113)" begin
        ctx = Context(64, 64)
        @test width(ctx.image) == 64 && height(ctx.image) == 64
        @test ctx.fillStyle isa Paint && ctx.fillStyle.color == ColorRGBA(0, 0, 0, 0xff)
        @test ctx.fillStyle.opacity == Float32(1) &&
            ctx.fillStyle.blendMode === NormalBlend
        @test ctx.strokeStyle isa Paint &&
            ctx.strokeStyle.color == ColorRGBA(0, 0, 0, 0xff)
        @test ctx.fillStyle !== ctx.strokeStyle  # two independent paints
        @test ctx.lineWidth == Float32(1)
        @test ctx.miterLimit == Float32(10)
        @test ctx.lineCap === ButtCap
        @test ctx.lineJoin === MiterJoin
        @test ctx.path.commands == Float32[]
        @test getTransform(ctx) == mat3()
        @test isempty(ctx.stateStack)
        @test_throws ArgumentError Context(0, 10)

        byImg = Context(newImage(8, 8))
        @test width(byImg.image) == 8

        # Defaults draw opaque black, like upstream newContext.
        d = newImage(32, 32)
        defCtx = Context(d)
        fillRect(defCtx, rect(Vec2(4f0, 4f0), Vec2(8f0, 8f0)))
        @test px(d, 8, 8) == (0, 0, 0, 255)
        @test px(d, 2, 2)[4] == 0

        # Default stroke: lineWidth 1 butt -> sliver coverage, nothing outside.
        d2 = newImage(64, 64)
        c2 = Context(d2)
        c2.strokeStyle = rgba(0xff, 0xff, 0xff, 0xff)
        strokeSegment(c2, Segment(Vec2(10f0, 10f0), Vec2(30f0, 10f0)))
        @test px(d2, 20, 10)[4] > 0
        @test px(d2, 20, 12)[4] == 0
        @test px(d2, 40, 10)[4] == 0
        strokeSegment(c2, 10f0, 10f0, 30f0, 10f0)  # 4-float form
        @test px(d2, 20, 10)[4] > 0

        # fillStyle from a hex string (converted at draw time)
        hx = Context(16, 16)
        hx.fillStyle = "#FF5C00"
        @test hx.fillStyle == "#FF5C00"
        fillRect(hx, rect(Vec2(0f0, 0f0), Vec2(4f0, 4f0)))
        @test px(hx.image, 2, 2) == (255, 92, 0, 255)
        @test hx.fillStyle == "#FF5C00" &&
            Paint("#FF5C00").color == parseHtmlColor("#FF5C00")

        # An invalid string raises at draw time (documented deviation:
        # upstream convert happens at assignment).
        bad = Context(16, 16)
        bad.fillStyle = "#12G45"
        bad.strokeStyle = "#12G45"
        @test_throws ArgumentError fillRect(bad, rect(Vec2(0f0, 0f0), Vec2(4f0, 4f0)))
        @test_throws ArgumentError stroke(bad, newPath())

        # strokeStyle from a ColorRGB and a Paint with clamped opacity.
        cK = Context(32, 32)
        cK.strokeStyle = rgb(255, 255, 0)
        cK.lineWidth = 2f0
        strokeSegment(cK, segment(Vec2(12f0, 12f0), Vec2(16f0, 12f0)))
        @test px(cK.image, 14, 12) == (255, 255, 0, 255)

        cL = Context(32, 32)
        cLop = Paint(rgba(0xff, 0, 0, 0xff); opacity = 2f0)
        cL.fillStyle = cLop
        fillRect(cL, rect(Vec2(4f0, 4f0), Vec2(8f0, 8f0)))
        @test cLop.opacity == Float32(1)
        @test px(cL.image, 8, 8) == (255, 0, 0, 255)

        # Zero-opacity (clamped) stroke is a no-op; zero-alpha overwrite clears.
        cN = Context(32, 32)
        fill(cN.image, rgba(0xff, 0, 0, 0xff))
        cN.strokeStyle = Paint(rgba(0, 0, 255, 0xff); opacity = 0f0)
        cN.lineWidth = 4f0
        strokeSegment(cN, segment(Vec2(8f0, 8f0), Vec2(24f0, 8f0)))
        @test px(cN.image, 16, 8) == (255, 0, 0, 255)

        cZ = Context(32, 32)
        fill(cZ.image, rgba(0xff, 0, 0, 0xff))
        cZ.strokeStyle = Paint(rgba(0, 0, 0, 0))
        strokeRect(cZ, rect(Vec2(4f0, 4f0), Vec2(8f0, 8f0)))
        @test px(cZ.image, 5, 8) == (255, 0, 0, 255)
        cZ.strokeStyle = Paint(rgba(0, 0, 0, 0); blendMode = OverwriteBlend)
        strokeRect(cZ, rect(Vec2(4f0, 4f0), Vec2(8f0, 8f0)))
        @test px(cZ.image, 5, 8) == (0, 0, 0, 0)
        @test px(cZ.image, 8, 8) == (255, 0, 0, 255)
    end

    @testset "Context transforms (contexts.nim L525-560)" begin
        A = Context(8, 8)
        translate(A, 1f0, 1f0)
        scale(A, 2f0, 3f0)
        @test getTransform(A) * Vec2(1f0, 1f0) == Vec2(3f0, 4f0)

        B = Context(8, 8)
        scale(B, 2f0, 3f0)
        translate(B, 1f0, 1f0)
        @test getTransform(B) * Vec2(1f0, 1f0) == Vec2(4f0, 6f0)
        @test A.mat != B.mat  # translate-then-scale vs reverse differ

        C = Context(8, 8)
        translate(C, Vec2(1f0, 2f0))
        scale(C, Vec2(2f0, 3f0))
        transform(C, rotate(Float32(0)))  # generic post-multiply (identity)
        @test getTransform(C) * Vec2(1f0, 1f0) ==
            (translate(Vec2(1f0, 2f0)) * scale(Vec2(2f0, 3f0))) * Vec2(1f0, 1f0)

        R = Context(8, 8)
        rotate(R, Vetra.PI_F / 2f0)
        rv = getTransform(R) * Vec2(1f0, 0f0)  # cos(pi/2) is not exact 0
        @test abs(rv.x) < 1e-4 && abs(rv.y - 1f0) < 1e-4

        S = Context(8, 8)
        m = translate(Vec2(9f0, 9f0))
        setTransform(S, m)
        @test getTransform(S) === m || getTransform(S) == m
        resetTransform(S)
        @test getTransform(S) == mat3()
    end

    @testset "Context path wrappers (contexts.nim L261-365)" begin
        W = Context(8, 8)
        beginPath(W)
        @test W.path.commands == Float32[]
        moveTo(W, Vec2(1f0, 2f0))
        lineTo(W, 3f0, 4f0)
        bezierCurveTo(W, Vec2(1f0, 1f0), Vec2(2f0, 2f0), Vec2(4f0, 4f0))
        lineTo(W, Vec2(5f0, 5f0))
        quadraticCurveTo(W, 1f0, 1f0, 2f0, 2f0)
        quadraticCurveTo(W, Vec2(1f0, 1f0), Vec2(2f0, 2f0))
        arc(W, 4f0, 4f0, 1f0, 0f0, Vetra.PI_F)
        arc(W, Vec2(4f0, 4f0), 1f0, Vec2(0f0, Vetra.PI_F), ccw = true)
        arcTo(W, 1f0, 1f0, 2f0, 0f0, 0.5f0)
        arcTo(W, Vec2(1f0, 1f0), Vec2(2f0, 0f0), 0.5f0)
        closePath(W)
        rect(W, rect(Vec2(0f0, 0f0), Vec2(2f0, 2f0)))
        rect(W, 0f0, 0f0, 2f0, 2f0)
        ellipse(W, Vec2(1f0, 1f0), 2f0, 1f0)
        ellipse(W, 1f0, 1f0, 2f0, 1f0)
        roundedRect(W, 0f0, 0f0, 8f0, 8f0, 1f0, 1f0, 1f0, 1f0)
        roundedRect(W, rect(Vec2(0f0, 0f0), Vec2(8f0, 8f0)), 1f0, 1f0, 1f0, 1f0)
        circle(W, 2f0, 2f0, 1f0)
        circle(W, Circle(Vec2(2f0, 2f0), 1f0))
        polygon(W, 0f0, 0f0, 1f0, 5)
        polygon(W, Vec2(0f0, 0f0), 1f0, 5)
        @test length(W.path.commands) > 0

        # Wrapper commands match building the same path directly.
        W2 = Context(8, 8)
        beginPath(W2)
        moveTo(W2, 1f0, 2f0)
        lineTo(W2, 3f0, 4f0)
        closePath(W2)
        p2 = newPath()
        moveTo(p2, 1f0, 2f0)
        lineTo(p2, 3f0, 4f0)
        closePath(p2)
        @test W2.path.commands == p2.commands
        @test W2.path.at == p2.at && W2.path.start == p2.start
    end

    @testset "Context fill/stroke wrappers (contexts.nim L365-470)" begin
        # fill(ctx) with the current path (NonZero default and EvenOdd)
        ec = Context(32, 32)
        ec.fillStyle = rgb(0x00, 0xff, 0x00)
        beginPath(ec)
        rect(ec, 2f0, 2f0, 16f0, 16f0)
        rect(ec, 6f0, 6f0, 8f0, 8f0)
        fill(ec)  # NonZero: inner winding 2 still fills
        @test px(ec.image, 10, 10) == (0, 255, 0, 255)
        # EvenOdd hollows the doubled winding; a fresh context, since fill
        # composites (the earlier green would remain in the hole otherwise).
        ee = Context(32, 32)
        ee.fillStyle = rgb(0x00, 0xff, 0x00)
        beginPath(ee)
        rect(ee, 2f0, 2f0, 16f0, 16f0)
        rect(ee, 6f0, 6f0, 8f0, 8f0)
        fill(ee, EvenOdd)  # inner winding 2 -> hollow
        @test px(ee.image, 10, 10) == (0, 0, 0, 0)
        @test px(ee.image, 4, 4) == (0, 255, 0, 255)

        # fill(ctx, path) with an explicit path
        fp = Context(32, 32)
        fp.fillStyle = rgb(0x00, 0x00, 0xff)
        pp = newPath()
        rect(pp, 10f0, 10f0, 4f0, 4f0)
        fill(fp, pp)
        @test px(fp.image, 12, 12) == (0, 0, 255, 255)
        fill(fp, pp, NonZero)
        @test px(fp.image, 12, 12) == (0, 0, 255, 255)

        # stroke(ctx, path) and stroke(ctx) with the current path
        sp = Context(32, 32)
        sp.strokeStyle = rgb(0x22, 0x33, 0x44)
        sp.lineWidth = 2f0
        beginPath(sp)
        moveTo(sp, 8f0, 8f0)
        lineTo(sp, 20f0, 8f0)
        stroke(sp)
        @test px(sp.image, 14, 8) == (0x22, 0x33, 0x44, 0xff)
        @test px(sp.image, 24, 8)[4] == 0
        stro = newPath()
        moveTo(stro, 10f0, 16f0)
        lineTo(stro, 18f0, 16f0)
        stroke(sp, stro)
        @test px(sp.image, 14, 16) == (0x22, 0x33, 0x44, 0xff)

        # fillRect/strokeRect both forms (4-float + Rect)
        fr = Context(32, 32)
        fr.fillStyle = rgb(10, 20, 30)
        fillRect(fr, 4f0, 4f0, 6f0, 6f0)
        @test px(fr.image, 7, 7) == (10, 20, 30, 255)
        fillRect(fr, rect(Vec2(20f0, 20f0), Vec2(4f0, 4f0)))
        @test px(fr.image, 22, 22) == (10, 20, 30, 255)

        sr = Context(32, 32)
        sr.strokeStyle = rgb(30, 20, 10)
        sr.lineWidth = 4f0
        strokeRect(sr, 8f0, 8f0, 8f0, 8f0)
        @test px(sr.image, 9, 13) == (30, 20, 10, 255)  # left edge band
        @test px(sr.image, 13, 13)[4] == 0              # interior hollow
        strokeRect(sr, rect(Vec2(24f0, 24f0), Vec2(4f0, 4f0)))
        @test px(sr.image, 25, 25) == (30, 20, 10, 255)

        # clearRect (both forms): erases through the current fillStyle
        clr = Context(32, 32)
        fill(clr.image, rgba(0xff, 0xff, 0x88, 0xff))
        clr.fillStyle = rgb(0, 255, 0)  # must not affect the clear
        clearRect(clr, rect(Vec2(4f0, 4f0), Vec2(8f0, 8f0)))
        @test px(clr.image, 8, 8) == (0, 0, 0, 0)
        @test px(clr.image, 2, 2) == (255, 255, 136, 255)
        clearRect(clr, 20f0, 20f0, 4f0, 4f0)
        @test px(clr.image, 22, 22) == (0, 0, 0, 0)

        # strokeSegment via a Segment
        ss = Context(64, 64)
        ss.strokeStyle = rgb(0xff, 0x00, 0xff)
        ss.lineWidth = 4f0
        strokeSegment(ss, Segment(Vec2(20f0, 20f0), Vec2(30f0, 20f0)))
        @test px(ss.image, 25, 20) == (255, 0, 255, 255)
        @test px(ss.image, 34, 20)[4] == 0
    end

    @testset "Context save/restore (contexts.nim L88-113)" begin
        sv = Context(32, 32)
        save(sv)
        sv.fillStyle = rgb(1, 2, 3)
        sv.strokeStyle = rgb(4, 5, 6)
        sv.lineWidth = 3f0
        sv.miterLimit = 2f0
        sv.lineCap = RoundCap
        sv.lineJoin = BevelJoin
        translate(sv, 1f0, 2f0)
        restore(sv)
        @test sv.fillStyle isa Paint && sv.fillStyle.color == ColorRGBA(0, 0, 0, 255)
        @test sv.strokeStyle.color == ColorRGBA(0, 0, 0, 255)
        @test sv.lineWidth == Float32(1)
        @test sv.miterLimit == Float32(10)
        @test sv.lineCap === ButtCap
        @test sv.lineJoin === MiterJoin
        @test getTransform(sv) == mat3()
        @test isempty(sv.stateStack)

        # Two deep: unwinding restores each saved state in order.
        dv = Context(32, 32)
        dv.fillStyle = rgb(7, 8, 9)
        save(dv)
        dv.lineWidth = 5f0
        save(dv)
        dv.fillStyle = rgb(11, 12, 13)
        dv.lineWidth = 7f0
        restore(dv)
        @test dv.fillStyle == ColorRGB(7, 8, 9)
        @test dv.lineWidth == Float32(5)
        restore(dv)
        @test dv.fillStyle == ColorRGB(7, 8, 9)  # first saved state, as stored
        @test dv.lineWidth == Float32(1)

        # Paint copy semantics (upstream: save() copies the paints in ctx):
        # changing the context's paint after save must not rewrite the
        # stored state, and stored Paints are independent copies.
        iso = Context(8, 8)
        iso.fillStyle = Paint(rgba(0, 0, 0, 255))
        iso.strokeStyle = Paint(rgba(0, 0, 0, 255))
        save(iso)
        @test iso.fillStyle !== iso.strokeStyle
        iso.fillStyle.opacity = Float32(0.5)
        restore(iso)
        @test iso.fillStyle.opacity == Float32(1)

        # Non-Paint styles are stored as-is (strings stay strings).
        st = Context(8, 8)
        st.fillStyle = "#010203"
        st.strokeStyle = "#040506"
        save(st)
        st.fillStyle = rgba(1, 1, 1, 1)
        restore(st)
        @test st.fillStyle == "#010203"
        @test st.strokeStyle == "#040506"

        # The path is not part of the saved state (upstream context state).
        pth = Context(8, 8)
        beginPath(pth)
        moveTo(pth, 1f0, 1f0)
        save(pth)
        beginPath(pth)
        moveTo(pth, 5f0, 5f0)
        restore(pth)
        @test pth.path.commands != Float32[]

        # Unbalanced restore raises (documented deviation: upstream is a
        # no-op on an empty stack).
        un = Context(8, 8)
        @test_throws ArgumentError restore(un)
        save(un)
        restore(un)
        @test_throws ArgumentError restore(un)
    end

    @testset "square + line example flows (T006 fixtures, byte parity)" begin
        sq, wh = VetraRef.read_raw("square")
        isi = newImage(wh[1], wh[2])
        fill(isi, rgba(0xff, 0xff, 0xff, 0xff))
        sic = Context(isi)
        sic.fillStyle = rgba(0xff, 0, 0, 0xff)
        fillRect(sic, rect(Vec2(50, 50), Vec2(100, 100)))
        @test VetraRef.compare_pixels(isi.data, sq, wh).count == 0

        ln, wh2 = VetraRef.read_raw("line")
        ile = newImage(wh2[1], wh2[2])
        fill(ile, rgba(0xff, 0xff, 0xff, 0xff))
        ilec = Context(ile)
        ilec.strokeStyle = "#FF5C00"
        ilec.lineWidth = 10f0
        strokeSegment(ilec, segment(Vec2(25, 25), Vec2(175, 175)))
        @test VetraRef.compare_pixels(ile.data, ln, wh2).count == 0
    end
end
