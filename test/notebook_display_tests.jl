# T016 — automatic notebook image display (MIME show methods).
#
# Expectations: the PNG MIME stream equals `encodePNG` byte-for-byte and
# decodes back to the same image (opaque input); the text display is a
# concise one-liner (never the pixel buffer); display does not mutate the
# source image. The core-only `showable` fallback is exercised in
# test/codec_loading_tests.jl (subprocess without PNGFiles).

using Test
using Vetra

@testset "T016 notebook image display" begin
    img = newImage(6, 4)
    fill(img, rgb(200, 30, 60))
    setColor(img, 3, 2, rgbx(10, 20, 30, 255))

    @testset "PNG MIME" begin
        @test showable(MIME"image/png"(), img) === true
        buf = IOBuffer()
        show(buf, MIME"image/png"(), img)
        bytes = take!(buf)
        @test bytes == encodePNG(img)
        back = decodePNG(bytes)
        @test (width(back), height(back)) == (6, 4)
        @test back.data == img.data          # opaque image: exact round trip
        # Displaying must not mutate the source.
        @test getColor(img, 3, 2) == rgbx(10, 20, 30, 255)
    end

    @testset "text display" begin
        @test showable(MIME"text/plain"(), img) === true
        buf = IOBuffer()
        show(buf, MIME"text/plain"(), img)
        text = String(take!(buf))
        @test occursin("6x4", text)
        @test occursin("premultiplied RGBA", text)
        @test !occursin("0xc8", text)        # no raw buffer dump
        @test length(text) < 60
    end

    @testset "plain show() dispatch" begin
        buf = IOBuffer()
        show(buf, MIME"text/plain"(), img)
        @test occursin("Vetra image", String(take!(buf)))
    end

end
