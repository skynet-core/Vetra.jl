# T006: the three pinned examples reproduce their upstream .raw fixtures
# byte-exactly, and the PPM P6 writer emits the upstream header/payload.

include(joinpath(@__DIR__, "..", "examples", "common.jl"))
using .VetraExamples

@testset "T006 example byte parity (pinned fixtures, no tolerance)" begin
    @testset "square (upstream examples/square.nim)" begin
        ref, wh = VetraRef.read_raw("square")
        img = build_square()
        @test (width(img), height(img)) == wh
        @test VetraRef.compare_pixels(img.data, ref, wh).count == 0
    end

    @testset "line (upstream examples/line.nim)" begin
        ref, wh = VetraRef.read_raw("line")
        img = build_line()
        @test (width(img), height(img)) == wh
        @test VetraRef.compare_pixels(img.data, ref, wh).count == 0
    end

    @testset "heart (upstream examples/heart.nim)" begin
        ref, wh = VetraRef.read_raw("heart")
        img = build_heart()
        @test (width(img), height(img)) == wh
        @test VetraRef.compare_pixels(img.data, ref, wh).count == 0
    end
end

@testset "T006 PPM P6 output (upstream encodePpm)" begin
    # 2x3 with distinct premultiplied RGBA values; pixel (2, 3) stays the
    # zero-filled newImage pixel: channels written as stored, alpha dropped.
    img = newImage(2, 3)
    setColor(img, 1, 1, rgbx(10, 20, 30, 0xff))
    setColor(img, 2, 1, rgbx(1, 2, 3, 7))
    setColor(img, 1, 2, rgbx(0, 255, 5, 60))
    setColor(img, 2, 2, rgbx(9, 8, 7, 1))
    setColor(img, 1, 3, rgbx(254, 253, 252, 128))

    header = "P6\n2 3\n255\n"
    buf = encodePPM(img)
    @test startswith(buf, header)
    payload = Vector{UInt8}(buf)[length(header) + 1 : end]
    @test length(payload) == 3 * width(img) * height(img)

    stored_rgb = UInt8[]
    d = img.data
    for i in 1:4:length(d)
        push!(stored_rgb, d[i])
        push!(stored_rgb, d[i + 1])
        push!(stored_rgb, d[i + 2])
    end
    @test payload == stored_rgb

    # Round trip through a file: writePPM output is the encodePPM buffer.
    dir = mktempdir()
    name = joinpath(dir, "t.ppm")
    writePPM(name, img)
    @test read(name) == Vector{UInt8}(buf)
    rm(dir; recursive = true)
end
