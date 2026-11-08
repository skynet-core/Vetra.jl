# T014 — friendly numeric drawing arguments.
#
# The `Real` boundary wrappers convert once to `Float32` and delegate to the
# specialized kernels. The reference scene below is drawn twice: once with
# ordinary `Int` arguments and once with `Float32` literals. All parameter
# arithmetic stays exact in both domains, so the two canvases must end up
# byte-identical.

using Test
using Vetra

const ROBO = joinpath(@__DIR__, "..", ".reference", "upstream", "tests",
    "fonts", "Roboto-Regular_1.ttf")

@testset "T014 numeric API" begin

    function draw_scene(ctx, stamp, font, x, y, w, h, cx, cy, r, t)
        # Rectangles and segments (4/5-arg coordinate forms).
        fillRect(ctx, x, y, w, h)
        strokeRect(ctx, x + 1, y + 1, w - 2, h - 2)
        clearRect(ctx, x + 2, y + 2, 2, 2)
        strokeSegment(ctx, x, y + h, x + w, y + 1)

        # Transforms (context + geometry constructors).
        save(ctx)
        translate(ctx, cx, cy)
        rotate(ctx, 0.5)
        scale(ctx, 2, 3)
        setTransform(ctx, translate(Vec2(1, 2)) * rotate(0.25))
        fillRect(ctx, 0, 0, t, t)
        resetTransform(ctx)
        restore(ctx)

        # Path commands via the context wrappers.
        beginPath(ctx)
        moveTo(ctx, x, y)
        lineTo(ctx, x + 20, y + 10)
        quadraticCurveTo(ctx, x + 30, y, x + 40, y + 10)
        bezierCurveTo(ctx, x + 50, y + 20, x + 60, y, x + 70, y + 10)
        arc(ctx, cx, cy, r, 0, 3, ccw = true)
        arcTo(ctx, cx + r, cy + r, cx + 2 * r, cy, r)
        rect(ctx, x, y + 30, w - 10, 12)
        roundedRect(ctx, x, y + 50, 20, 12, 3, 3, 3, 3)
        ellipse(ctx, cx + r, cy + r, t, t + 2)
        circle(ctx, cx + 2 * r, cy, t)
        polygon(ctx, cx, cy + 2 * r, t, 5)
        fill(ctx)
        stroke(ctx)

        # Path commands on a bare Path, composed into the context path.
        p = newPath()
        moveTo(p, x, y + 60)
        lineTo(p, x + w - 4, y + 60)
        quadraticCurveTo(p, x + w, y + 62, x + w - 2, y + 64)
        bezierCurveTo(p, x + w - 4, y + 66, x + w - 8, y + 64,
            x + w - 10, y + 62)
        ellipticalArcTo(p, t, t, 0, true, true, x + w - 12, y + 60)
        addPath(ctx.path, p)
        lineTo(ctx, x + 1, y + 70)
        closePath(ctx)
        fill(ctx, EvenOdd)

        # Hit testing (returned for assertions outside the scene):
        # (x + 36, y + 63) lies inside the closed sliver subpath above;
        # (2, 2) is outside every part of the path.
        hit = isPointInPath(ctx, x + 36, y + 63)
        miss = isPointInPath(ctx, 2, 2)

        # Text.
        ctx.font = font
        ctx.fontSize = 16
        fillText(ctx, "T014", x, y + 90)
        strokeText(ctx, "numeric", x + 60, y + 90)

        # Image drawing (2-, 4-, and 9-arg forms).
        drawImage(ctx, stamp, x, y + 100)
        drawImage(ctx, stamp, x + w - 40, y + 100, 40, 24)
        drawImage(ctx, stamp, 0, 0, 20, 12, x + 40, y + 130, 16, 10)

        return (hit, miss)
    end

    function make_scene(; float)
        n(v) = float ? Float32(v) : v
        img = newImage(320, 320)
        fill(img, rgb(20, 30, 40))
        stamp = newImage(24, 16)
        fill(stamp, rgb(120, 90, 60))
        blur(stamp, n(2))          # Real radius
        spread(stamp, n(1))
        applyOpacity(stamp, n(0.5))
        stamp = shadow(stamp, Vec2(n(2), n(1)), n(1), n(2), rgb(10, 10, 10))
        ctx = Context(img)
        ctx.fillStyle = "#4A90D9"
        ctx.strokeStyle = rgb(240, 200, 40)
        ctx.lineWidth = n(3)
        (hit, miss) = draw_scene(ctx, stamp, ROBO, n(24), n(24), n(120),
            n(96), n(200), n(60), n(12), n(8))
        @test hit
        @test !miss
        return img
    end

    @testset "plain numbers match Float32 literals byte-for-byte" begin
        plain = make_scene(float = false)
        literal = make_scene(float = true)
        @test plain.data == literal.data
        @test getColor(plain, 30, 30) == getColor(literal, 30, 30)
    end

    @testset "geometry constructors" begin
        @test Vec2(1, 2) == Vec2(1f0, 2f0)
        @test Vec2(1 // 2, 3 // 2) == Vec2(0.5f0, 1.5f0)
        @test rect(1, 2, 3, 4) == Rect(1f0, 2f0, 3f0, 4f0)
        @test circle(Vec2(5, 5), 3) == Circle(Vec2(5f0, 5f0), 3f0)
        @test rotate(0.5) == rotate(0.5f0)
        a = @allocated Vec2(1, 2)
        b = @allocated Vec2(1f0, 2f0)
        @test a == b
    end

    @testset "dispatch and allocation" begin
        ctx = Context(32, 32)
        a = @allocated fillRect(ctx, 10, 10, 10, 10)
        b = @allocated fillRect(ctx, 10f0, 10f0, 10f0, 10f0)
        @test a == b
        # Both candidate methods exist (Float32 kernel + Real boundary).
        rect4 = filter(methods(fillRect)) do m
            p = m.sig.parameters
            length(p) == 6 && p[2] == Context
        end
        @test any(m -> m.sig.parameters[3] == Float32, rect4)
        @test any(m -> m.sig.parameters[3] == Real, rect4)
    end

    @testset "conversion semantics" begin
        ctx = Context(16, 16)
        # The wrapper is a pure conversion: behavior beyond it is identical to
        # passing the converted value to the existing Float32 API. Overflow
        # saturates to Inf (a rasterizer InexactError, as with direct Inf);
        # NaN silently draws nothing, as with direct NaN.
        fill(ctx.image, rgb(9, 9, 9))
        @test_throws InexactError fillRect(ctx, 1e40, 2, 2, 2)
        base = copy(ctx.image.data)
        fillRect(ctx, 2, 1e40, 2, 2) # InexactError: nothing drawn
        @test ctx.image.data == base
        ctx2 = Context(16, 16)
        fillRect(ctx2, NaN, 2, 2, 2)
        @test ctx2.image.data == zeros(UInt8, 16 * 16 * 4)
        # Non-numeric arguments raise MethodError, as before.
        @test_throws MethodError fillRect(ctx, "a", 1, 1, 1)
        @test_throws MethodError blur(newImage(4, 4), "2")
        @test_throws MethodError Vec2("1", 2)
    end

    @testset "keyword arguments are not converted (documented limit)" begin
        ctx = Context(16, 16)
        p = newPath()
        rect(p, 2, 2, 8, 8)
        # Keyword arguments are not implicitly converted by dispatch, so
        # `strokeWidth = 2` still needs `2f0`.
        threw = false
        try
            strokePath(ctx.image, p, Paint(rgba(1, 2, 3, 255));
                strokeWidth = 2)
        catch e
            threw = e isa Union{MethodError, TypeError}
        end
        @test threw
        strokePath(ctx.image, p, Paint(rgba(1, 2, 3, 255));
            strokeWidth = 2f0)
        @test count(!iszero, ctx.image.data) > 0
    end

end
