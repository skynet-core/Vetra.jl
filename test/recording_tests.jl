# T024: drawing recordings and CPU replay (D030, docs/RECORDING.md).
#
# Method: identical scene functions drive a real immediate Context and a
# RecordingContext; the recorded Picture is replayed into a fresh image and
# must be byte-identical to the direct CPU drawing (replay re-executes the
# same kernel calls). Scaling and record-boundary cases use hand-derived
# expectations, never the code under test. The pinned Roboto fixture font
# is used for text scenes.

const REC_FONT_DIR = joinpath(@__DIR__, "..", ".reference", "upstream",
    "tests", "fonts")
const REC_ROBO = joinpath(REC_FONT_DIR, "Roboto-Regular_1.ttf")

@testset "T024 drawing recordings and CPU replay" begin
    """Run `scene` (a 1-arg function taking a context) on both an immediate
    Context and a RecordingContext; returns (direct, replay, picture)."""
    function ab(w, h, scene)
        img_direct = newImage(w, h)
        scene(Context(img_direct))
        rec = PictureRecorder(w, h)
        scene(rec.ctx)
        pic = finishRecording(rec)
        img_replay = newImage(w, h)
        drawPicture(img_replay, pic)
        return img_direct, img_replay, pic
    end

    @testset "basic fills and strokes" begin
        function scene(ctx)
            ctx.fillStyle = rgb(20, 30, 40)
            fillRect(ctx, 0f0, 0f0, 64f0, 64f0)
            ctx.fillStyle = Paint(rgba(255, 0, 0, 200); opacity = 0.5f0)
            p = newPath()
            rect(p, 8f0, 8f0, 24f0, 16f0)
            fill(ctx, p)
            ctx.strokeStyle = rgb(0, 200, 255)
            ctx.lineWidth = 2f0
            ctx.lineDash = Float32[4f0, 2f0]
            q = newPath()
            moveTo(q, 4f0, 60f0)
            lineTo(q, 60f0, 6f0)
            stroke(ctx, q)
            ctx.lineDash = Float32[]
            strokeSegment(ctx, 40f0, 40f0, 58f0, 58f0)
            strokeRect(ctx, 10f0, 10f0, 20f0, 20f0)
            return nothing
        end
        d, r, _ = ab(64, 64, scene)
        @test d.data == r.data
    end

    @testset "gradients (linear, radial, angular)" begin
        function scene(ctx)
            ctx.fillStyle = rgb(10, 10, 10)
            fillRect(ctx, 0f0, 0f0, 48f0, 48f0)
            lin = Paint(LinearGradientPaint)
            lin.gradientHandlePositions = [Vec2(0f0, 0f0), Vec2(48f0, 48f0)]
            lin.gradientStops = [colorStop(rgba(255, 0, 0, 255), 0f0),
                colorStop(rgba(0, 0, 255, 255), 1f0)]
            ctx.fillStyle = lin
            fillRect(ctx, 4f0, 4f0, 20f0, 20f0)
            rad = Paint(RadialGradientPaint)
            rad.gradientHandlePositions = [Vec2(36f0, 20f0), Vec2(36f0, 20f0),
                Vec2(36f0, 30f0)]
            rad.gradientStops = [colorStop(rgba(0, 255, 0, 255), 0f0),
                colorStop(rgba(0, 255, 255, 255), 1f0)]
            ctx.fillStyle = rad
            c = newPath()
            circle(c, 36f0, 20f0, 9f0)
            fill(ctx, c)
            ang = Paint(AngularGradientPaint)
            ang.gradientHandlePositions = [Vec2(24f0, 24f0), Vec2(30f0, 24f0),
                Vec2(24f0, 30f0)]
            ang.gradientStops = [colorStop(rgba(255, 255, 0, 255), 0f0),
                colorStop(rgba(255, 0, 255, 255), 1f0)]
            ctx.fillStyle = ang
            e = newPath()
            rect(e, 14f0, 30f0, 14f0, 14f0)
            fill(ctx, e)
            return nothing
        end
        d, r, _ = ab(48, 48, scene)
        @test d.data == r.data
    end

    @testset "transforms" begin
        function scene(ctx)
            ctx.fillStyle = rgb(255, 255, 255)
            fillRect(ctx, 0f0, 0f0, 64f0, 64f0)
            setTransform(ctx, mat3())
            translate(ctx, Vec2(10f0, 10f0))
            rotate(ctx, Float32(0.5))
            scale(ctx, Vec2(1.5f0, 1.0f0))
            ctx.fillStyle = rgb(0, 128, 255)
            fillRect(ctx, 0f0, 0f0, 20f0, 20f0)
            setTransform(ctx,
                translate(Vec2(40f0, 40f0)) * rotate(Float32(0.2)) *
                scale(Vec2(0.8f0, 1.2f0)))
            ctx.fillStyle = rgb(255, 128, 0)
            c = newPath()
            circle(c, 0f0, 0f0, 10f0)
            fill(ctx, c)
            resetTransform(ctx)
            ctx.fillStyle = rgb(0, 200, 0)
            fillRect(ctx, 50f0, 50f0, 10f0, 10f0)
            return nothing
        end
        d, r, _ = ab(64, 64, scene)
        @test d.data == r.data
    end

    @testset "clips (single + cumulative, image coordinates)" begin
        function scene(ctx)
            ctx.fillStyle = rgb(200, 200, 200)
            fillRect(ctx, 0f0, 0f0, 64f0, 64f0)
            clipA = newPath()
            circle(clipA, 32f0, 32f0, 24f0)
            clip(ctx, clipA)
            # Transform must NOT affect the clip (image coordinates).
            translate(ctx, Vec2(6f0, 6f0))
            ctx.fillStyle = rgb(255, 0, 0)
            fillRect(ctx, 0f0, 0f0, 64f0, 64f0)
            # Cumulative second clip (intersection).
            clipB = newPath()
            rect(clipB, 8f0, 8f0, 48f0, 48f0)
            clip(ctx, clipB)
            ctx.fillStyle = rgb(0, 0, 255)
            fillRect(ctx, 0f0, 0f0, 64f0, 64f0)
            return nothing
        end
        d, r, _ = ab(64, 64, scene)
        @test d.data == r.data
    end

    @testset "layers and globalAlpha" begin
        function scene(ctx)
            ctx.fillStyle = rgb(240, 240, 240)
            fillRect(ctx, 0f0, 0f0, 64f0, 64f0)
            saveLayer(ctx)
            ctx.fillStyle = Paint(rgba(255, 0, 0, 255); opacity = 0.6f0)
            a = newPath()
            rect(a, 6f0, 6f0, 30f0, 30f0)
            fill(ctx, a)
            ctx.fillStyle = Paint(rgba(0, 0, 255, 255); opacity = 0.6f0)
            b = newPath()
            rect(b, 20f0, 20f0, 30f0, 30f0)
            fill(ctx, b)
            restore(ctx)
            # globalAlpha != 1 wraps the stroke in a layer.
            ctx.globalAlpha = 0.4f0
            ctx.strokeStyle = rgb(0, 128, 0)
            ctx.lineWidth = 3f0
            s = newPath()
            moveTo(s, 0f0, 60f0)
            lineTo(s, 60f0, 60f0)
            stroke(ctx, s)
            ctx.globalAlpha = 1f0
            return nothing
        end
        d, r, _ = ab(64, 64, scene)
        @test d.data == r.data
    end

    @testset "saveLayer nested inside a clip" begin
        function scene(ctx)
            ctx.fillStyle = rgb(255, 255, 255)
            fillRect(ctx, 0f0, 0f0, 48f0, 48f0)
            clipC = newPath()
            circle(clipC, 24f0, 24f0, 20f0)
            clip(ctx, clipC)
            saveLayer(ctx)
            saveLayer(ctx)
            ctx.fillStyle = Paint(rgba(255, 0, 0, 255); opacity = 0.5f0)
            fillRect(ctx, 0f0, 0f0, 48f0, 48f0)
            restore(ctx)
            ctx.fillStyle = Paint(rgba(0, 255, 0, 255); opacity = 0.5f0)
            fillRect(ctx, 10f0, 10f0, 28f0, 28f0)
            restore(ctx)
            return nothing
        end
        d, r, _ = ab(48, 48, scene)
        @test d.data == r.data
    end

    @testset "drawImage (positional + src/dst rect)" begin
        src = newImage(16, 16)
        fill(src, rgb(120, 60, 200))
        # A pattern so the src/dst rect crop is observable.
        for i in 0:15
            setColor(src, i + 1, 4, rgb(255, 255, 0))
            setColor(src, 4, i + 1, rgb(255, 255, 0))
        end
        function scene(ctx)
            ctx.fillStyle = rgb(20, 20, 60)
            fillRect(ctx, 0f0, 0f0, 64f0, 64f0)
            drawImage(ctx, src, 4f0, 4f0)
            drawImage(ctx, src, 30f0, 30f0, 24f0, 24f0)
            drawImage(ctx, src, 0f0, 0f0, 8f0, 8f0, 44f0, 6f0, 14f0, 10f0)
            return nothing
        end
        d, r, _ = ab(64, 64, scene)
        @test d.data == r.data
    end

    @testset "text (fill + stroke)" begin
        function scene(ctx)
            ctx.fillStyle = rgb(250, 250, 250)
            fillRect(ctx, 0f0, 0f0, 160f0, 48f0)
            ctx.font = REC_ROBO
            ctx.fontSize = 18f0
            ctx.fillStyle = rgb(10, 20, 40)
            fillText(ctx, "Record once", 8f0, 24f0)
            ctx.strokeStyle = rgb(180, 0, 0)
            ctx.lineWidth = 0.5f0
            strokeText(ctx, "replay twice", 8f0, 44f0)
            return nothing
        end
        d, r, _ = ab(160, 48, scene)
        @test d.data == r.data
    end

    @testset "text baselines and no-font error" begin
        function scene(ctx)
            ctx.fillStyle = rgb(250, 250, 250)
            fillRect(ctx, 0f0, 0f0, 160f0, 72f0)
            ctx.font = REC_ROBO
            ctx.fontSize = 16f0
            ctx.textBaseline = MiddleBaseline
            ctx.fillStyle = rgb(10, 20, 40)
            fillText(ctx, "middle", 10f0, 18f0)
            ctx.textBaseline = IdeographicBaseline
            fillText(ctx, "ideo", 10f0, 38f0)
            ctx.textBaseline = BottomBaseline
            fillText(ctx, "bottom", 10f0, 62f0)
            return nothing
        end
        d, r, _ = ab(160, 72, scene)
        @test d.data == r.data
        # No font set: the raster error contract applies at record time.
        rec = PictureRecorder(8, 8)
        try
            fillText(rec.ctx, "x", 1f0, 1f0)
            @test false
        catch e
            @test e.msg == "No font has been set on this Context"
        end
    end

    @testset "save copies Paint fill styles in place" begin
        rec = PictureRecorder(8, 8)
        c = rec.ctx
        p = Paint(rgba(255, 0, 0, 255); opacity = 1f0)
        c.fillStyle = p
        save(c)
        c.fillStyle = p  # same object, now painted over
        p.opacity = 0.25f0  # mutate the original after save
        fillRect(c, 0f0, 0f0, 8f0, 4f0)
        restore(c)
        fillRect(c, 0f0, 4f0, 8f0, 4f0)
        pic = finishRecording(rec)
        out = newImage(8, 8); drawPicture(out, pic)
        direct = newImage(8, 8)
        ctx = Context(direct)
        ctx.fillStyle = p
        save(ctx)
        ctx.fillStyle = p
        p.opacity = 0.25f0
        fillRect(ctx, 0f0, 0f0, 8f0, 4f0)
        restore(ctx)
        fillRect(ctx, 0f0, 4f0, 8f0, 4f0)
        @test out.data == direct.data
    end

    @testset "clearRect" begin
        function scene(ctx)
            ctx.fillStyle = rgb(255, 255, 255)
            fillRect(ctx, 0f0, 0f0, 40f0, 40f0)
            clearRect(ctx, 10f0, 10f0, 20f0, 20f0)
            ctx.fillStyle = rgb(0, 128, 128)
            fillRect(ctx, 14f0, 14f0, 12f0, 12f0)
            return nothing
        end
        d, r, _ = ab(40, 40, scene)
        @test d.data == r.data
    end

    @testset "save/restore state transitions" begin
        function scene(ctx)
            ctx.fillStyle = rgb(255, 0, 0)
            fillRect(ctx, 2f0, 2f0, 10f0, 10f0)
            save(ctx)
            ctx.fillStyle = rgb(0, 255, 0)
            ctx.lineWidth = 4f0
            translate(ctx, Vec2(14f0, 14f0))
            fillRect(ctx, 0f0, 0f0, 10f0, 10f0)
            restore(ctx)
            # After restore: red, width 1, identity.
            ctx.fillStyle = rgb(0, 0, 255)
            fillRect(ctx, 2f0, 24f0, 10f0, 10f0)
            strokeRect(ctx, 24f0, 24f0, 10f0, 10f0)
            return nothing
        end
        d, r, _ = ab(40, 40, scene)
        @test d.data == r.data
    end

    @testset "multiple replays of one picture are identical" begin
        rec = PictureRecorder(32, 32)
        rec.ctx.fillStyle = rgb(255, 128, 0)
        fillRect(rec.ctx, 4f0, 4f0, 20f0, 12f0)
        rec.ctx.fillStyle = Paint(rgba(0, 0, 255, 255); opacity = 0.5f0)
        c = newPath()
        circle(c, 16f0, 16f0, 10f0)
        fill(rec.ctx, c)
        pic = finishRecording(rec)
        a = newImage(32, 32); drawPicture(a, pic)
        b = newImage(32, 32); drawPicture(b, pic)
        cc = newImage(32, 32); drawPicture(cc, pic)
        @test a.data == b.data
        @test b.data == cc.data
    end

    @testset "snapshots survive later mutation of sources" begin
        rec = PictureRecorder(32, 32)
        p = newPath()
        rect(p, 4f0, 4f0, 16f0, 16f0)
        paint = Paint(rgba(255, 0, 0, 255); opacity = 1f0)
        rec.ctx.fillStyle = paint
        fill(rec.ctx, p)
        img = newImage(8, 8)
        fill(img, rgb(0, 255, 0))
        drawImage(rec.ctx, img, 20f0, 20f0)
        pic = finishRecording(rec)
        ref = newImage(32, 32); drawPicture(ref, pic)
        # Mutate the recorded sources.
        rect(p, 0f0, 0f0, 32f0, 32f0)
        paint.opacity = 0.2f0
        fill(img, rgb(255, 255, 0))
        out = newImage(32, 32); drawPicture(out, pic)
        @test ref.data == out.data
    end

    @testset "explicit output scaling (vector, not raster enlargement)" begin
        # A 10x10 picture: red square [1.5, 5.5) x [1.5, 5.5).
        rec = PictureRecorder(10, 10)
        rec.ctx.fillStyle = rgb(255, 0, 0)
        fillRect(rec.ctx, 1.5f0, 1.5f0, 4f0, 4f0)
        pic = finishRecording(rec)
        # Replay into 20x20: the square maps to [3, 11) in 20-space. Pixel
        # centers at 2.5 (outside) and 3.5 (inside) bracket the exact edge;
        # a raster enlargement of the 10x10 would blur that boundary pixel
        # (its source row mixes a partial and a full pixel).
        big = newImage(20, 20)
        drawPicture(big, pic)
        @test getColor(big, 3, 3) == rgbx(0, 0, 0, 0)   # center 2.5
        @test getColor(big, 4, 4) == rgbx(255, 0, 0, 255)  # center 3.5
        @test getColor(big, 11, 11) == rgbx(255, 0, 0, 255)  # center 10.5
        @test getColor(big, 12, 12) == rgbx(0, 0, 0, 0)   # center 11.5
        # Replay into 5x5: the square maps to [0.75, 2.75) x [0.75, 2.75).
        # Area-justified coverage: pixel 1 (0-based) [0,1)^2 intersects the
        # square in 0.75^2 = 0.0625 of its area -> small partial alpha;
        # pixel 2 [1,2)^2 is fully inside -> full; pixel 3 [2,3)^2
        # intersects in 0.75^2 = 0.5625 -> majority alpha; pixel 4 is fully
        # outside -> zero.
        small = newImage(5, 5)
        drawPicture(small, pic)
        @test getColor(small, 1, 1).a < UInt8(128) &&
            getColor(small, 1, 1).a > UInt8(0)  # partial, area 0.0625
        @test getColor(small, 2, 2) == rgbx(255, 0, 0, 255)  # fully inside
        @test getColor(small, 3, 3).a >= UInt8(128) &&
            getColor(small, 3, 3).a < UInt8(255)  # majority, area 0.5625
        @test getColor(small, 4, 4) == rgbx(0, 0, 0, 0)  # fully outside
    end

    @testset "record-boundary errors" begin
        # TiledImagePaint fill is not recordable.
        tiled = Paint(TiledImagePaint)
        tiled.image = newImage(4, 4)
        rec = PictureRecorder(8, 8)
        rec.ctx.fillStyle = tiled
        n = length(rec.ctx.ops)
        try
            fill(rec.ctx, newPath())
            @test false
        catch e
            @test e.msg == "TiledImagePaint fills are not recordable (recording)"
        end
        @test length(rec.ctx.ops) == n  # no op appended

        # Non-solid strokeStyle is not recordable.
        lin = Paint(LinearGradientPaint)
        lin.gradientHandlePositions = [Vec2(0f0, 0f0), Vec2(1f0, 1f0)]
        lin.gradientStops = [colorStop(rgba(0, 0, 255, 255), 0f0)]
        rec2 = PictureRecorder(8, 8)
        rec2.ctx.strokeStyle = lin
        n2 = length(rec2.ctx.ops)
        try
            stroke(rec2.ctx, newPath())
            @test false
        catch e
            @test e.msg == "strokeStyle must be a solid paint (recording)"
        end
        @test length(rec2.ctx.ops) == n2

        # Unmatched restore.
        rec3 = PictureRecorder(8, 8)
        try
            restore(rec3.ctx)
            @test false
        catch e
            @test e.msg == "restore() with no saved state"
        end

        # Drawing on a finished recorder.
        rec4 = PictureRecorder(8, 8)
        finishRecording(rec4)
        try
            fillRect(rec4.ctx, 1f0, 1f0, 2f0, 2f0)
            @test false
        catch e
            @test e.msg == "recorder already finished"
        end
    end

    @testset "unclosed saveLayer content is discarded on replay" begin
        rec = PictureRecorder(16, 16)
        rec.ctx.fillStyle = rgb(255, 0, 0)
        fillRect(rec.ctx, 0f0, 0f0, 16f0, 16f0)
        saveLayer(rec.ctx)
        rec.ctx.fillStyle = rgb(0, 255, 0)
        fillRect(rec.ctx, 0f0, 0f0, 16f0, 16f0)
        # No restore: the green layer is never composited (immediate pipeline
        # loses it too).
        pic = finishRecording(rec)
        out = newImage(16, 16); drawPicture(out, pic)
        direct = newImage(16, 16)
        ctx = Context(direct)
        ctx.fillStyle = rgb(255, 0, 0)
        fillRect(ctx, 0f0, 0f0, 16f0, 16f0)
        saveLayer(ctx)
        ctx.fillStyle = rgb(0, 255, 0)
        fillRect(ctx, 0f0, 0f0, 16f0, 16f0)
        @test out.data == direct.data
    end

    @testset "Real boundary forms (T014 convention)" begin
        rec = PictureRecorder(32, 32)
        c = rec.ctx
        c.fillStyle = rgb(9, 9, 9)
        fillRect(c, 1, 1, 30, 30)
        c.strokeStyle = rgb(8, 8, 8)
        bezierCurveTo(c, 2.5, 2.5, 10.5, 1, 20, 20)
        quadraticCurveTo(c, 20.0, 10, 30, 20.5)
        arc(c, 16, 16, 5, 0, 3)
        arc(c, Vec2(2f0, 2f0), 3f0, Vec2(0f0, Float32(2pi)))
        arcTo(c, 1.5, 1.5, 29.5, 29.5, 4)
        ellipse(c, 16, 16, 6, 3)
        roundedRect(c, 4, 4, 10, 10, 2, 2, 2, 2)
        polygon(c, 24, 24, 6, 3)
        circle(c, 8, 24, 3)
        c.lineDash = Float32[3f0, 1f0]
        stroke(c, c.path)
        setLineDash(c, Float32[])
        @test getLineDash(c) == Float32[]
        c.font = REC_ROBO
        fillText(c, "x", 5, 28)
        drawImage(c, newImage(3, 3), 24, 4)
        pic = finishRecording(rec)
        @test length(pic.ops) == 4  # rect fill + stroke + text fill + image
        out = newImage(32, 32)
        drawPicture(out, pic)
        @test getColor(out, 16, 16).a == UInt8(255)
    end

    @testset "picture is self-contained (no global scratch)" begin
        rec = PictureRecorder(8, 8)
        rec.ctx.fillStyle = rgb(1, 2, 3)
        fillRect(rec.ctx, 1f0, 1f0, 6f0, 6f0)
        pic = finishRecording(rec)
        @test pic.size == Vec2(Float32(8), Float32(8))
        @test length(pic.ops) == 1
        @test pic.ops[1] isa Vetra.FillOp
        # Two independent recordings do not share op lists.
        recB = PictureRecorder(8, 8)
        recB.ctx.fillStyle = rgb(4, 5, 6)
        fillRect(recB.ctx, 2f0, 2f0, 4f0, 4f0)
        picB = finishRecording(recB)
        @test pic.ops !== picB.ops
    end
end
