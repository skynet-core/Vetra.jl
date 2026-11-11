# T010: full context integration — cross-feature composition of the state
# stack, clips, transforms, dashes, layers, opacity, text and gradients.
# Single-feature state matrices live in context_tests.jl (T005) and
# context_layers_tests.jl (T007b); this file covers their *composition*
# plus the T010 additions (isPointInPath, dash wiring in strokes).
#
# Every expectation is hand-derived from the pinned upstream formulas
# (contexts.nim, paths.nim overlaps/fillOverlaps, blends.nim) — never from
# the code under test.

using Test

const ROBO = joinpath(@__DIR__, "..", ".reference", "upstream", "tests",
    "fonts", "Roboto-Regular_1.ttf")

@testset "T010 context integration" begin
    pxv = (img, x, y) -> (c = getColor(img, x, y);
        (Int(c.r), Int(c.g), Int(c.b), Int(c.a)))

    white = (255, 255, 255, 255)
    red = (255, 0, 0, 255)
    # (128, 0, 0, 128) premul normal-blended over white: k = 255 - 128 =
    # 127 -> r = 128 + 255 * 127 div 255 = 255, g = b = 127, a = 255.
    halfOverWhite = (255, 127, 127, 255)

    function whiteImage(w, h)
        img = newImage(w, h)
        fill(img, rgbx(255, 255, 255, 255))
        return img
    end

    function rectPath(x, y, w, h)
        pt = newPath()
        rect(pt, Float32(x), Float32(y), Float32(w), Float32(h))
        return pt
    end

    @testset "isPointInPath: scanline point test (paths.nim overlaps)" begin
        ctx = Context(whiteImage(32, 32))

        sq = rectPath(0, 0, 10, 10)
        @test isPointInPath(ctx, sq, 5f0, 5f0)      # inside
        @test isPointInPath(ctx, sq, Vec2(5f0, 5f0))
        @test !isPointInPath(ctx, sq, 15f0, 5f0)    # past the last hit
        @test !isPointInPath(ctx, sq, -5f0, 5f0)   # before the first hit
        # Top edge: scanline hits land on the segments' starts (kept by
        # upstream). Bottom edge: hits land on segment.to and upstream
        # discards them (`if segment.to != at`) -> no hits -> outside.
        @test isPointInPath(ctx, sq, 5f0, 0f0)
        @test !isPointInPath(ctx, sq, 5f0, 10f0)
        @test isPointInPath(ctx, sq, 0f0, 5f0)     # left edge inclusive
        @test !isPointInPath(ctx, sq, 10f0, 5f0)   # right edge exclusive
        @test isPointInPath(ctx, sq, 5f0, 5f0, EvenOdd)
        @test !isPointInPath(ctx, sq, 15f0, 5f0, EvenOdd)

        # Donut: outer rect (CCW) + counter-rotated inner square 5..15.
        donut = rectPath(0, 0, 20, 20)
        hole = newPath()
        moveTo(hole, 5f0, 5f0); lineTo(hole, 5f0, 15f0)
        lineTo(hole, 15f0, 15f0); lineTo(hole, 15f0, 5f0)
        closePath(hole)
        addPath(donut, hole)
        @test !isPointInPath(ctx, donut, 12f0, 12f0)    # in the hole:
        @test !isPointInPath(ctx, donut, 12f0, 12f0,    # winding 1-1 = 0
            EvenOdd)                                    # crossings 2, even
        @test isPointInPath(ctx, donut, 3f0, 3f0)
        @test isPointInPath(ctx, donut, 3f0, 3f0, EvenOdd)

        # Same-orientation overlap (outer 0..20 + rect 12..18, addPath):
        # winding 2 inside both.
        over = rectPath(0, 0, 20, 20)
        addPath(over, rectPath(12, 12, 6, 6))
        @test isPointInPath(ctx, over, 15f0, 15f0)
        @test !isPointInPath(ctx, over, 15f0, 15f0, EvenOdd)

        # Current-path overloads (2-arg forms use ctx.path).
        beginPath(ctx)
        rect(ctx.path, 0f0, 0f0, 10f0, 10f0)
        @test isPointInPath(ctx, 5f0, 5f0)
        @test isPointInPath(ctx, Vec2(5f0, 5f0))
        @test !isPointInPath(ctx, 15f0, 5f0)

        # The CTM applies to the path, not the test point.
        setTransform(ctx, translate(Vec2(100f0, 0f0)))
        @test isPointInPath(ctx, sq, 105f0, 5f0)
        @test !isPointInPath(ctx, sq, 5f0, 5f0)
        resetTransform(ctx)
        setTransform(ctx, scale(Vec2(2f0, 2f0)))
        @test isPointInPath(ctx, sq, 15f0, 15f0)
        @test !isPointInPath(ctx, sq, 25f0, 15f0)
        resetTransform(ctx)

        # fixed32 truncation at the x = 10 edge (1/256 grid): 9.999
        # truncates below the hit (inside), 10.001 not above (outside).
        @test isPointInPath(ctx, sq, 9.999f0, 5f0)
        @test !isPointInPath(ctx, sq, 10.001f0, 5f0)
    end

    @testset "font path round-trips through save/restore (ContextState)" begin
        ctx = Context(8, 8)
        save(ctx)
        ctx.font = ROBO
        ctx.fontSize = Float32(24)
        restore(ctx)
        @test ctx.font == ""
        @test ctx.fontSize == Float32(12)
    end

    @testset "dash phase in context strokes (setLineDash wiring)" begin
        # 0-based line (0,16)-(75,16), width 10, ButtCap: band rows
        # 12..21 (1-based). Dashes [5,15] draw x in [0,5),[20,25),[40,45),
        # [60,65) -> 1-based columns 1-5, 21-25, 41-45, 61-65.
        ctx = Context(whiteImage(80, 32))
        ctx.strokeStyle = Paint(rgba(255, 0, 0, 255))
        ctx.lineWidth = Float32(10)
        setLineDash(ctx, [5f0, 15f0])
        @test getLineDash(ctx) == [5f0, 15f0]
        # M004: Nim `seq[float32]` value semantics — the context stores
        # its own copy, so neither caller mutation of the input vector
        # nor mutation of the getter's result reaches the context state.
        dashIn = Float32[5f0, 15f0]
        setLineDash(ctx, dashIn)
        dashIn[1] = 999f0
        @test getLineDash(ctx) == Float32[5f0, 15f0]
        dashOut = getLineDash(ctx)
        push!(dashOut, 1f0)
        @test getLineDash(ctx) == Float32[5f0, 15f0]
        strokeSegment(ctx, 0f0, 16f0, 75f0, 16f0)
        @test pxv(ctx.image, 3, 16) == red
        @test pxv(ctx.image, 5, 16) == red
        @test pxv(ctx.image, 6, 16) == white
        @test pxv(ctx.image, 13, 16) == white
        @test pxv(ctx.image, 23, 16) == red
        @test pxv(ctx.image, 43, 16) == red
        @test pxv(ctx.image, 63, 16) == red
        @test pxv(ctx.image, 68, 16) == white

        # Odd-length pattern duplicates itself: [5,15,10] -> [5,15,10,
        # 5,15,10] (60 total); even 0-based indices draw, so ink is
        # [0,5),[20,30),[35,50),[60,65).
        ctx2 = Context(whiteImage(80, 32))
        ctx2.strokeStyle = Paint(rgba(255, 0, 0, 255))
        ctx2.lineWidth = Float32(10)
        setLineDash(ctx2, [5f0, 15f0, 10f0])
        strokeSegment(ctx2, 0f0, 16f0, 75f0, 16f0)
        @test pxv(ctx2.image, 25, 16) == red
        @test pxv(ctx2.image, 35, 16) == white
        @test pxv(ctx2.image, 43, 16) == red
        @test pxv(ctx2.image, 63, 16) == red

        # Dashes compose with globalAlpha (layer + applyOpacity).
        ctx3 = Context(whiteImage(80, 32))
        ctx3.strokeStyle = Paint(rgba(255, 0, 0, 255))
        ctx3.lineWidth = Float32(10)
        ctx3.globalAlpha = Float32(0.5)
        setLineDash(ctx3, [5f0, 15f0])
        strokeSegment(ctx3, 0f0, 16f0, 75f0, 16f0)
        @test pxv(ctx3.image, 3, 16) == halfOverWhite
        @test pxv(ctx3.image, 13, 16) == white

        # Zero/negative dash lengths are rejected at stroke time
        # (upstream strokeShapes guard).
        ctx4 = Context(whiteImage(8, 8))
        ctx4.strokeStyle = Paint(rgba(255, 0, 0, 255))
        setLineDash(ctx4, [0f0, 5f0])
        @test_throws ArgumentError strokeSegment(ctx4, 0f0, 4f0, 8f0, 4f0)

        # lineDash is part of the state stack.
        ctx5 = Context(8, 8)
        save(ctx5)
        setLineDash(ctx5, [2f0, 2f0])
        restore(ctx5)
        @test isempty(ctx5.lineDash)

        # Dash + caps: caps sit at the path ends (upstream strokeShapes),
        # not at each dash end. Line (10,16)-(70,16), width 10, dashes
        # [5,15] (length 60): ink [10,15),[30,35),[50,55).
        cap = Context(whiteImage(80, 32))
        cap.strokeStyle = Paint(rgba(255, 0, 0, 255))
        cap.lineWidth = Float32(10)
        setLineDash(cap, [5f0, 15f0])
        cap.lineCap = RoundCap
        strokeSegment(cap, 10f0, 16f0, 70f0, 16f0)
        # The cap is the ellipse polygon (coarser than the exact circle;
        # the pinned T005 fixtures fix this rendering): center-row ink
        # starts at 1-based column 7, left of the first dash.
        @test pxv(cap.image, 7, 16) == red    # start cap ink
        @test pxv(cap.image, 74, 16) == red   # end cap circle, end in a
        @test pxv(cap.image, 13, 16) == red    # dash gap
        butt = Context(whiteImage(80, 32))
        butt.strokeStyle = Paint(rgba(255, 0, 0, 255))
        butt.lineWidth = Float32(10)
        setLineDash(butt, [5f0, 15f0])
        strokeSegment(butt, 10f0, 16f0, 70f0, 16f0)
        @test pxv(butt.image, 7, 16) == white  # no ButtCap ink
        @test pxv(butt.image, 74, 16) == white
        sqcap = Context(whiteImage(80, 32))
        sqcap.strokeStyle = Paint(rgba(255, 0, 0, 255))
        sqcap.lineWidth = Float32(10)
        setLineDash(sqcap, [5f0, 15f0])
        sqcap.lineCap = SquareCap
        strokeSegment(sqcap, 10f0, 16f0, 70f0, 16f0)
        @test pxv(sqcap.image, 7, 16) == red   # square cap extends
        @test pxv(sqcap.image, 73, 16) == red  # halfStroke past the end

        # Dash + join: the miter join at the vertex is added regardless of
        # the dash phase (upstream strokeShapes). Path (0,16)-(30,16)-
        # (30,30), width 10, dashes [5,15]: segment 1 ink [0,5),[20,25);
        # segment 2 (pattern restarts) ink y in [16,21); the vertex (30,16)
        # sits in a gap, but the miter corner x in [30,35), y in [11,16)
        # is inked by the join alone.
        jn = Context(whiteImage(40, 40))
        jn.strokeStyle = Paint(rgba(255, 0, 0, 255))
        jn.lineWidth = Float32(10)
        setLineDash(jn, [5f0, 15f0])
        p = newPath()
        moveTo(p, 0f0, 16f0); lineTo(p, 30f0, 16f0); lineTo(p, 30f0, 30f0)
        stroke(jn, p)
        @test pxv(jn.image, 33, 14) == red     # miter corner, in the gap
        @test pxv(jn.image, 22, 16) == red     # segment 1 dash
        @test pxv(jn.image, 31, 17) == red     # segment 2 dash
        @test pxv(jn.image, 22, 30) == white   # outside everything
    end

    @testset "clip uses identity space (upstream quirk); fill uses the CTM" begin
        # clip mask is built without the CTM (contexts.nim clip ->
        # fillPath with default transform); the fill geometry is
        # transformed. So a translated fill under an un-translated clip
        # is entirely clipped away.
        ctx = Context(whiteImage(40, 40))
        ctx.fillStyle = Paint(rgba(255, 0, 0, 255))
        save(ctx)
        clip(ctx, rectPath(0, 0, 20, 40))
        transform(ctx, translate(Vec2(20f0, 0f0)))
        fillRect(ctx, 0f0, 0f0, 40f0, 40f0) # geometry [20,60) x [0,40)
        restore(ctx)
        @test pxv(ctx.image, 10, 10) == white
        @test pxv(ctx.image, 30, 10) == white

        # Without the translate the same clip keeps the left half.
        save(ctx)
        clip(ctx, rectPath(0, 0, 20, 40))
        fillRect(ctx, 0f0, 0f0, 40f0, 40f0)
        restore(ctx)
        @test pxv(ctx.image, 10, 10) == red
        @test pxv(ctx.image, 30, 10) == white

        # Transform *before* the clip: the mask is still identity space.
        # Fresh context: case 2 left the left half red.
        ctx = Context(whiteImage(40, 40))
        ctx.fillStyle = Paint(rgba(255, 0, 0, 255))
        save(ctx)
        transform(ctx, translate(Vec2(20f0, 0f0)))
        clip(ctx, rectPath(0, 0, 20, 40))
        fillRect(ctx, 0f0, 0f0, 40f0, 40f0)
        restore(ctx)
        @test pxv(ctx.image, 10, 10) == white
        @test pxv(ctx.image, 30, 10) == white
        @test getTransform(ctx) == mat3()
    end

    @testset "rotated fill/stroke parity with the upstream oracle (T011 regression)" begin
        # Pinned oracle fixture (tools/oracle/emit_fixtures.nim, rotation
        # mode): 320x240 canvas rgb(245,244,250); fillRect(12,12,90,60)
        # "#FF5C00"; translate(10,40); rotate(0.3); strokeRect(0,0,60,60)
        # blue width 4. Regression for the port's leftRectArea sign (the
        # upstream vmath `fract` is abs-based, so negative pens stay
        # positive) and the uint8 wrap of `*(ColorRGBX, float32)`
        # (upstream truncates in unsigned, the port used to raise
        # InexactError here).
        ref, wh = VetraRef.read_raw("ctx_rot")
        img = newImage(320, 240)
        fill(img, rgb(245, 244, 250))
        ctx = Context(img)
        ctx.fillStyle = "#FF5C00"
        fillRect(ctx, 12f0, 12f0, 90f0, 60f0)
        translate(ctx, 10f0, 40f0)
        rotate(ctx, 0.3f0)
        ctx.strokeStyle = rgb(0, 128, 255)
        ctx.lineWidth = 4f0
        strokeRect(ctx, 0f0, 0f0, 60f0, 60f0)
        @test (width(img), height(img)) == wh
        @test VetraRef.compare_pixels(img.data, ref, wh).count == 0
    end

    @testset "gradient paint under clip + transform" begin
        function gradPaint()
            p = Paint(LinearGradientPaint)
            p.gradientHandlePositions = [Vec2(0f0, 0f0), Vec2(40f0, 0f0)]
            p.gradientStops = [colorStop(rgb(0, 0, 0), 0f0),
                colorStop(rgb(255, 255, 255), 1f0)]
            return p
        end
        # Paints are sampled in destination space, so a clipped or
        # translated render must equal the full render on the covered
        # pixels and leave the rest untouched.
        full = Context(whiteImage(40, 40))
        full.fillStyle = gradPaint()
        fillRect(full, 0f0, 0f0, 40f0, 40f0)

        left = Context(whiteImage(40, 40))
        left.fillStyle = gradPaint()
        save(left)
        clip(left, rectPath(0, 0, 20, 40))
        fillRect(left, 0f0, 0f0, 40f0, 40f0)
        restore(left)
        for x in 1:20
            @test pxv(left.image, x, 10) == pxv(full.image, x, 10)
        end
        for x in 21:40
            @test pxv(left.image, x, 10) == white
        end

        moved = Context(whiteImage(40, 40))
        moved.fillStyle = gradPaint()
        save(moved)
        clip(moved, rectPath(0, 0, 20, 40))
        transform(moved, translate(Vec2(10f0, 0f0)))
        fillRect(moved, 0f0, 0f0, 40f0, 40f0) # geometry [10,50)
        restore(moved)
        for x in 11:20
            @test pxv(moved.image, x, 10) == pxv(full.image, x, 10)
        end
        for x in 1:10
            @test pxv(moved.image, x, 10) == white
        end
        for x in 21:40
            @test pxv(moved.image, x, 10) == white
        end
    end

    @testset "text inside a clip (fill + stroke)" begin
        # Property: the clipped render equals the unclipped render inside
        # the clip rect and is untouched outside it. "Word" @24 spans
        # x in [2, 58) (layoutBounds (56, 28) is upstream-pinned), so it
        # crosses the x = 30 clip boundary.
        function textCtx(clipLeft)
            ctx = Context(whiteImage(60, 40))
            ctx.font = ROBO
            ctx.fontSize = Float32(24)
            ctx.fillStyle = Paint(rgba(0, 0, 0, 255))
            clipLeft && (save(ctx), clip(ctx, rectPath(0, 0, 30, 40)))
            fillText(ctx, "Word", 2f0, 30f0)
            clipLeft && restore(ctx)
            return ctx
        end
        full = textCtx(false)
        clipped = textCtx(true)
        inK = false
        outK = false
        for x in 31:60
            pxv(full.image, x, 20) != white && (outK = true)
        end
        for x in 1:30
            pxv(full.image, x, 20) != white && (inK = true)
        end
        @test inK # ink crosses both halves -> the clip is exercised
        @test outK
        for y in 1:40
            for x in 1:30
                @test pxv(clipped.image, x, y) == pxv(full.image, x, y)
            end
            for x in 31:60
                @test pxv(clipped.image, x, y) == white
            end
        end

        # strokeText routes through the same mask.
        sfull = Context(whiteImage(60, 40))
        sfull.font = ROBO
        sfull.fontSize = Float32(24)
        sfull.strokeStyle = Paint(rgba(0, 0, 0, 255))
        sfull.lineWidth = Float32(2)
        strokeText(sfull, "Word", 2f0, 30f0)
        sclip = Context(whiteImage(60, 40))
        sclip.font = ROBO
        sclip.fontSize = Float32(24)
        sclip.strokeStyle = Paint(rgba(0, 0, 0, 255))
        sclip.lineWidth = Float32(2)
        save(sclip)
        clip(sclip, rectPath(0, 0, 30, 40))
        strokeText(sclip, "Word", 2f0, 30f0)
        restore(sclip)
        sOutInked = false
        for x in 31:60
            for y in 1:40
                pxv(sfull.image, x, y) != white && (sOutInked = true)
            end
        end
        @test sOutInked
        for y in 1:40
            for x in 1:30
                @test pxv(sclip.image, x, y) == pxv(sfull.image, x, y)
            end
            for x in 31:60
                @test pxv(sclip.image, x, y) == white
            end
        end
    end

    @testset "composite state stack: transform + clip + alpha + dash" begin
        ctx = Context(whiteImage(40, 40))
        ctx.fillStyle = Paint(rgba(255, 0, 0, 255))
        save(ctx)
        clip(ctx, rectPath(0, 0, 20, 40))
        transform(ctx, translate(Vec2(0f0, 10f0)))
        ctx.globalAlpha = Float32(0.5)
        ctx.lineWidth = Float32(4)
        setLineDash(ctx, [4f0, 4f0])
        fillRect(ctx, 0f0, 0f0, 40f0, 20f0)
        # Geometry [0,40)x[10,30) intersected with clip [0,20)x[0,40) =
        # [0,20)x[10,30); red at 0.5 over white.
        restore(ctx)
        @test pxv(ctx.image, 10, 15) == halfOverWhite
        @test pxv(ctx.image, 10, 5) == white
        @test pxv(ctx.image, 10, 35) == white
        @test pxv(ctx.image, 30, 15) == white

        # Everything is restored: no clip, identity CTM, default state.
        @test ctx.mask === nothing
        @test ctx.layer === nothing
        @test isempty(ctx.stateStack)
        @test getTransform(ctx) == mat3()
        @test ctx.globalAlpha == Float32(1)
        @test ctx.lineWidth == Float32(1)
        @test isempty(ctx.lineDash)
        fillRect(ctx, 0f0, 0f0, 40f0, 40f0)
        @test pxv(ctx.image, 30, 15) == red # the clip is gone
    end

    @testset "nested saveLayer under a clip with globalAlpha" begin
        # Transparent root; the outer saveLayer captures globalAlpha 0.5.
        # The inner clip restricts the fill to the top half; the fill's
        # own alpha layering halves the red once.
        ctx = Context(newImage(8, 8))
        ctx.fillStyle = Paint(rgba(255, 0, 0, 255))
        ctx.globalAlpha = Float32(0.5)
        saveLayer(ctx)
        clip(ctx, rectPath(0, 0, 8, 4))
        fillRect(ctx, 0f0, 0f0, 8f0, 8f0)
        restore(ctx)
        @test pxv(ctx.image, 2, 2) == (128, 0, 0, 128) # half red, premul
        @test pxv(ctx.image, 2, 7) == (0, 0, 0, 0)    # clipped away
        @test ctx.mask === nothing
        @test ctx.layer === nothing
        @test isempty(ctx.stateStack)
        # The explicit saveLayer pushed state while globalAlpha was 0.5,
        # so the final restore brings back 0.5, not the original 1.
        @test ctx.globalAlpha == Float32(0.5)
    end
end
