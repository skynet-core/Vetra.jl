# Shared image builders behind examples/{square,line,heart}.jl and
# test/examples_tests.jl. They mirror the pinned upstream programs
# .reference/upstream/examples/{square,line,heart}.nim exactly (upstream wrote
# PNG; PPM is this milestone's output policy, D008, and PNG is T008).

module VetraExamples
using Vetra

export build_square, build_line, build_heart

"""200x200 white, red `fillRect` (50, 50), size 100x100 (upstream square.nim)."""
function build_square()
    image = newImage(200, 200)
    fill(image, rgba(255, 255, 255, 255))
    ctx = Context(image)
    ctx.fillStyle = rgba(255, 0, 0, 255)
    fillRect(ctx, rect(Vec2(50, 50), Vec2(100, 100)))
    return image
end

"""200x200 white, `#FF5C00` segment (25, 25) -> (175, 175), width 10 (line.nim)."""
function build_line()
    image = newImage(200, 200)
    fill(image, rgba(255, 255, 255, 255))
    ctx = Context(image)
    ctx.strokeStyle = "#FF5C00"
    ctx.lineWidth = 10f0
    strokeSegment(ctx, segment(Vec2(25, 25), Vec2(175, 175)))
    return image
end

"""200x200 white, `#FC427B` heart from the upstream SVG path (heart.nim)."""
function build_heart()
    image = newImage(200, 200)
    fill(image, rgba(255, 255, 255, 255))
    fillPath(image, """
        M 20 60
        A 40 40 90 0 1 100 60
        A 40 40 90 0 1 180 60
        Q 180 120 100 180
        Q 20 120 20 60
        z
        """, Paint(parseHtmlColor("#FC427B")))
    return image
end
end # module VetraExamples
