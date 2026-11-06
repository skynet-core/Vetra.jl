# T007b: masks and layers on Context -- clip (intersection semantics),
# saveLayer/restore composition, globalAlpha layering, and the
# clears-uncovered rasterizer paths they drive. Every expectation is
# hand-derived from the pinned upstream formulas (blends.nim, images.nim,
# paths.nim L1466-1928) -- never from the code under test.

@testset "T007b mask and layers" begin
    pxv = (img, x, y) -> (c = getColor(img, x, y);
        (Int(c.r), Int(c.g), Int(c.b), Int(c.a)))

    white = (255, 255, 255, 255)
    red = (255, 0, 0, 255)
    blue = (0, 0, 255, 255)
    # (128, 0, 0, 128) normal-blended over white: k = 255 - 128 = 127 ->
    # r = 128 + 255 * 127 div 255 = 255, g = 127, b = 127, a = 128 + 127
    halfOverWhite = (255, 127, 127, 255)
    # A clipped sliver pixel carries the fill's own AA coverage AND the
    # clip mask's coverage, both 1/2: red*128/255 = (128,0,0,128) premul,
    # blendMask with mask (128,128,128,128) -> (128*128 div 255, 0, 0, 64) =
    # (64,0,0,64), normal over white: k = 191 -> (64+191, 0+191, 0+191, 255)
    sliverOverWhite = (255, 191, 191, 255)

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

    @testset "first clip (4x4 white, rect at (1,1,2,2))" begin
        ctx = Context(whiteImage(4, 4))
        ctx.fillStyle = Paint(rgba(255, 0, 0, 255))
        pt = rectPath(1, 1, 2, 2)
        clip(ctx, pt)
        fill(ctx, pt)
        @test ctx.mask !== nothing          # the clip stays active
        @test pxv(ctx.image, 2, 2) == red   # inside the clip
        @test pxv(ctx.image, 3, 2) == red
        @test pxv(ctx.image, 2, 3) == red
        @test pxv(ctx.image, 3, 3) == red
        @test pxv(ctx.image, 1, 1) == white # outside the clip
        @test pxv(ctx.image, 1, 4) == white
        @test pxv(ctx.image, 4, 4) == white
    end

    @testset "clip via the current path (2-arg form) and fill(ctx)" begin
        ctx = Context(whiteImage(4, 4))
        ctx.fillStyle = Paint(rgba(255, 0, 0, 255))
        rect(ctx, 1f0, 1f0, 2f0, 2f0)
        clip(ctx)
        fill(ctx)
        @test pxv(ctx.image, 2, 2) == red
        @test pxv(ctx.image, 3, 3) == red
        @test pxv(ctx.image, 1, 1) == white
    end

    @testset "second clip intersects (not replaces, not unions)" begin
        ctx = Context(whiteImage(4, 4))
        ctx.fillStyle = Paint(rgba(255, 0, 0, 255))
        clip(ctx, rectPath(0, 0, 4, 2))    # rows 1-2, all cols
        clip(ctx, rectPath(2, 0, 2, 4))    # cols 3-4, rows 1-4
        fill(ctx, rectPath(0, 0, 4, 4))
        @test pxv(ctx.image, 3, 1) == red  # intersection
        @test pxv(ctx.image, 4, 1) == red
        @test pxv(ctx.image, 3, 2) == red
        @test pxv(ctx.image, 4, 2) == red
        @test pxv(ctx.image, 1, 1) == white   # first clip only -> cleared
        @test pxv(ctx.image, 2, 2) == white
        @test pxv(ctx.image, 3, 3) == white   # second clip only -> cleared
        @test pxv(ctx.image, 1, 3) == white
    end

    @testset "restore removes the clip" begin
        ctx = Context(whiteImage(4, 4))
        ctx.fillStyle = Paint(rgba(255, 0, 0, 255))
        save(ctx)
        clip(ctx, rectPath(0, 0, 4, 2))
        restore(ctx)
        @test ctx.mask === nothing
        @test isempty(ctx.stateStack)
        fill(ctx, rectPath(0, 0, 4, 4))
        for y in 1:4
            for x in 1:4
                @test pxv(ctx.image, x, y) == red
            end
        end
    end

    @testset "save copies the mask, so restore revives the pre-clip region" begin
        ctx = Context(whiteImage(4, 4))
        ctx.fillStyle = Paint(rgba(255, 0, 0, 255))
        clip(ctx, rectPath(0, 0, 4, 2))    # rows 1-2
        save(ctx)
        clip(ctx, rectPath(0, 0, 2, 4))    # intersect to cols 1-2 x rows 1-2
        restore(ctx)
        fill(ctx, rectPath(0, 0, 4, 4))
        @test pxv(ctx.image, 1, 1) == red  # rows 1-2 revived in full...
        @test pxv(ctx.image, 4, 1) == red
        @test pxv(ctx.image, 1, 2) == red
        @test pxv(ctx.image, 2, 2) == red
        @test pxv(ctx.image, 1, 3) == white# ...not the intersection
        @test pxv(ctx.image, 4, 3) == white
    end

    @testset "globalAlpha 0.5 (layer + applyOpacity + restore)" begin
        ctx = Context(whiteImage(4, 4))
        ctx.fillStyle = Paint(rgba(255, 0, 0, 255))
        ctx.globalAlpha = Float32(0.5)
        fill(ctx, rectPath(1, 1, 2, 2))
        # layer: red; applyOpacity o = roundHalfAway(0.5 * 255) = 128 ->
        # (255*128 div 255, 0, 0, 128) = (128, 0, 0, 128); normal over white
        @test pxv(ctx.image, 2, 2) == halfOverWhite
        @test pxv(ctx.image, 3, 3) == halfOverWhite
        @test pxv(ctx.image, 1, 1) == white  # outside the rect, untouched
        @test pxv(ctx.image, 4, 4) == white
        # The fill's own saveLayer snapshotted the *current* 0.5, so restore
        # brings back 0.5, not the pre-fill value: upstream-faithful behavior.
        @test ctx.globalAlpha == Float32(0.5)
    end

    @testset "globalAlpha round-trips through save/restore" begin
        ctx = Context(4, 4)
        ctx.globalAlpha = Float32(0.25)
        save(ctx)
        ctx.globalAlpha = Float32(1)
        restore(ctx)
        @test ctx.globalAlpha == Float32(0.25)
        @test ctx.mask === nothing
        @test ctx.layer === nothing
    end

    @testset "nested saveLayer composites onto the outer layer" begin
        ctx = Context(newImage(8, 8))      # transparent root
        saveLayer(ctx)                     # L1
        ctx.fillStyle = Paint(rgba(255, 0, 0, 255))
        fillRect(ctx, 0f0, 0f0, 4f0, 8f0)  # left half of L1
        saveLayer(ctx)                     # L2
        ctx.fillStyle = Paint(rgba(0, 0, 255, 255))
        fillRect(ctx, 4f0, 0f0, 4f0, 8f0)  # right half of L2
        restore(ctx)
        restore(ctx)
        @test ctx.layer === nothing
        @test isempty(ctx.stateStack)
        @test pxv(ctx.image, 1, 1) == red
        @test pxv(ctx.image, 4, 4) == red
        @test pxv(ctx.image, 5, 4) == blue
        @test pxv(ctx.image, 8, 8) == blue
    end

    @testset "clearRect erases inside the active layer" begin
        ctx = Context(newImage(8, 8))
        saveLayer(ctx)
        ctx.fillStyle = Paint(rgba(255, 0, 0, 255))
        fillRect(ctx, 0f0, 0f0, 8f0, 8f0)
        clearRect(ctx, 2f0, 2f0, 4f0, 4f0)   # 0-based block (2..5, 2..5)
        restore(ctx)
        @test pxv(ctx.image, 1, 1) == red
        @test pxv(ctx.image, 4, 4) == (0, 0, 0, 0)
        @test pxv(ctx.image, 7, 7) == red
    end

    @testset "stroke under a clip (band x mask intersection)" begin
        ctx = Context(whiteImage(8, 8))
        clip(ctx, rectPath(0, 0, 8, 4))      # rows 1-4
        ctx.strokeStyle = Paint(rgba(0, 0, 255, 255))
        ctx.lineWidth = Float32(4)
        strokeSegment(ctx, 0f0, 1f0, 8f0, 1f0)   # band rows 1-3 (1-based)
        @test pxv(ctx.image, 4, 1) == blue
        @test pxv(ctx.image, 4, 2) == blue
        @test pxv(ctx.image, 4, 3) == blue
        @test pxv(ctx.image, 4, 4) == white      # band but outside the clip
        @test pxv(ctx.image, 4, 5) == white
        @test pxv(ctx.image, 1, 1) == blue       # the whole row width
    end

    @testset "drawImage under a clip" begin
        ctx = Context(whiteImage(4, 4))
        clip(ctx, rectPath(0, 0, 2, 4))        # cols 1-2
        src = newImage(2, 1)
        setColor(src, 1, 1, rgbx(10, 20, 30, 255))
        setColor(src, 2, 1, rgbx(70, 80, 90, 255))
        drawImage(ctx, src, 0f0, 0f0)
        @test pxv(ctx.image, 1, 1) == (10, 20, 30, 255)
        @test pxv(ctx.image, 2, 1) == (70, 80, 90, 255)
        @test pxv(ctx.image, 3, 1) == white     # clipped out
        @test pxv(ctx.image, 1, 3) == white
    end

    @testset "clipped triangle (AA edges, trapezoid + coverage mask paths)" begin
        ctx = Context(whiteImage(4, 4))
        ctx.fillStyle = Paint(rgba(255, 0, 0, 255))
        tri = parsePath("M 0 0 L 4 0 L 0 4 Z")
        clip(ctx, tri)
        fill(ctx, tri)
        # The diagonal x = 4 - y gives each row y (1-based) a sliver pixel
        # at x = 1 + y with area 1/2. That pixel's fill coverage (128) AND
        # the mask's coverage (128) both apply -> (255,191,191,255):
        #   row 1: red red red  sliver     row 2: red red sliver white
        #   row 3: red sliver white white  row 4: sliver white white white
        @test pxv(ctx.image, 1, 1) == red
        @test pxv(ctx.image, 3, 1) == red
        @test pxv(ctx.image, 4, 1) == sliverOverWhite
        @test pxv(ctx.image, 1, 2) == red
        @test pxv(ctx.image, 3, 2) == sliverOverWhite
        @test pxv(ctx.image, 4, 2) == white
        @test pxv(ctx.image, 1, 3) == red
        @test pxv(ctx.image, 2, 3) == sliverOverWhite
        @test pxv(ctx.image, 3, 3) == white
        @test pxv(ctx.image, 1, 4) == sliverOverWhite
        @test pxv(ctx.image, 2, 4) == white
    end

    @testset "clip of two disjoint rects (trapezoid gap clears)" begin
        ctx = Context(whiteImage(4, 4))
        ctx.fillStyle = Paint(rgba(255, 0, 0, 255))
        clip(ctx, parsePath("M 0 0 H 1 V 1 H 0 Z M 2 0 H 3 V 1 H 2 Z"))
        fill(ctx, rectPath(0, 0, 4, 4))
        @test pxv(ctx.image, 1, 1) == red    # rect 1
        @test pxv(ctx.image, 2, 1) == white  # the gap between the rects
        @test pxv(ctx.image, 3, 1) == red    # rect 2
        @test pxv(ctx.image, 4, 1) == white  # past the last span
        @test pxv(ctx.image, 1, 2) == white  # below the path's bounds
        @test pxv(ctx.image, 4, 4) == white
    end

    @testset "clip of overlapping rects (multi-hit mask walk)" begin
        ctx = Context(whiteImage(4, 4))
        ctx.fillStyle = Paint(rgba(255, 0, 0, 255))
        clip(ctx, parsePath("M 0 0 H 2 V 1 H 0 Z M 1 0 H 3 V 1 H 1 Z"))
        fill(ctx, rectPath(0, 0, 4, 4))
        # First clip of a self-overlapping path: the clip region is the
        # non-zero winding *union* of the two rects, x in [0,3), y in [0,1),
        # so px (1,1), (2,1), (3,1) are covered; the multi-hit walk still
        # exercises the gap/end clears for x >= 3 and the rows below.
        @test pxv(ctx.image, 1, 1) == red
        @test pxv(ctx.image, 2, 1) == red
        @test pxv(ctx.image, 3, 1) == red
        @test pxv(ctx.image, 4, 1) == white
        @test pxv(ctx.image, 3, 2) == white
    end

    @testset "clip outside the image horizontally clears the whole mask" begin
        ctx = Context(whiteImage(4, 4))
        clip(ctx, rectPath(10, 0, 2, 2))
        @test ctx.mask !== nothing
        fill(ctx, rectPath(0, 0, 4, 4))
        for y in 1:4
            for x in 1:4
                @test pxv(ctx.image, x, y) == white
            end
        end
    end

    @testset "unbalanced restore (saveLayer path)" begin
        ctx = Context(4, 4)
        @test_throws ArgumentError restore(ctx)
        saveLayer(ctx)
        @test ctx.layer !== nothing
        restore(ctx)
        @test ctx.layer === nothing
        @test isempty(ctx.stateStack)
        @test_throws ArgumentError restore(ctx)
    end

    @testset "malformed clip raises without corrupting the target" begin
        img = whiteImage(4, 4)
        ctx = Context(img)
        before = copy(img.data)
        @test_throws ArgumentError clip(ctx, rectPath(0, 0, 2, 2), WindingRule(2))
        @test img.data == before
    end

    @testset "T008: stroke layering (globalAlpha + mask routing, oracle-pinned)" begin
        # 4x4 white; red stroke width 5, (0,1)-(4,1), globalAlpha 0.5:
        # full-coverage rows -> (255, 127, 127, 255); the partial bottom row
        # (coverage 51/255) -> (255, 204, 204, 255). Pinned against the
        # upstream oracle (contexts.nim stroke + applyOpacity + blendNormal).
        img = whiteImage(4, 4)
        ctx = Context(img)
        ctx.strokeStyle = "red"
        ctx.lineWidth = 5f0
        ctx.globalAlpha = Float32(0.5)
        strokeSegment(ctx, segment(Vec2(0, 1), Vec2(4, 1)))
        for i in 1:12 # rows 1-3, all 4 columns (row-major)
            @test pxv(img, (i - 1) % 4 + 1, div(i - 1, 4) + 1) ==
                (255, 127, 127, 255)
        end
        for i in 13:16 # row 4, all 4 columns
            @test pxv(img, i - 12, 4) == (255, 204, 204, 255)
        end

        # Mask routing: clip to the left half; the stroke is drawn into a
        # layer and masked back. Left half: opaque red rows 1-3, partial
        # row 4; right half untouched.
        img = whiteImage(4, 4)
        ctx = Context(img)
        clip(ctx, rectPath(0, 0, 2, 4))
        ctx.strokeStyle = "red"
        ctx.lineWidth = 5f0
        strokeSegment(ctx, segment(Vec2(0, 1), Vec2(4, 1)))
        for y in 1:3 # rows 1-3: left half opaque red, right half white
            @test pxv(img, 1, y) == (255, 0, 0, 255)
            @test pxv(img, 2, y) == (255, 0, 0, 255)
            @test pxv(img, 3, y) == white
            @test pxv(img, 4, y) == white
        end
        @test pxv(img, 1, 4) == (255, 153, 153, 255) # row 4: partial band
        @test pxv(img, 2, 4) == (255, 153, 153, 255)
        @test pxv(img, 3, 4) == white
        @test pxv(img, 4, 4) == white
    end
end
