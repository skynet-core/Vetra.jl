# T015 / D024 — color matrix interop (opt-in ColorTypes).
#
# Expectations are hand-derived from the pinned boundary conversions:
# export uses `toStraightAlpha` (straight_alpha.tsv rows), import uses
# `rgbx(ColorRGBA)` (premultiplied_alpha.tsv rows); the fixed-point byte
# access (`N0f8 .i`) and float clamp/round are verified against exact
# values, and orientations are proven with an asymmetric (3x2) image.

using Test
using Vetra
using ColorTypes

const n8 = ColorTypes.N0f8

@testset "T015 color matrix interop" begin
    @testset "export (premultiplied -> straight RGBA{N0f8})" begin
        # 3x2 (w x h) image: distinct pixels per channel to prove [y, x]
        # orientation (row 1 = top) and channel order.
        img = newImage(3, 2)
        d = img.data
        # row 1 (3 pixels): d[1:12]; row 2: d[13:24]
        d[1:4] = UInt8[255, 128, 0, 255]   # pixel (1,1): opaque
        d[5:8] = UInt8[128, 64, 0, 128]    # pixel (2,1): half alpha
        d[9:12] = UInt8[0, 0, 0, 0]        # pixel (3,1): fully transparent
        d[13:16] = UInt8[10, 20, 30, 40]   # pixel (1,2): premultiplied, low alpha
        d[17:20] = UInt8[200, 100, 50, 255] # pixel (2,2): opaque
        m = toColors(img)
        @test m isa Matrix{RGBA{n8}}
        @test size(m) == (2, 3)           # (rows, cols) = (h, w)
        @test m[1, 1].r.i == 255 && m[1, 1].g.i == 128 &&
            m[1, 1].b.i == 0 && m[1, 1].alpha.i == 255
        # toStraightAlpha: mult = 255.0 / 128 = 1.9921875;
        # r = roundHalfAway(128 * 1.9921875) = 255; g = roundHalfAway(64 *
        # 1.9921875) = roundHalfAway(127.5) = 128 (ties away from zero).
        @test m[1, 2].r.i == 255 && m[1, 2].g.i == 128 &&
            m[1, 2].b.i == 0 && m[1, 2].alpha.i == 128
        @test m[1, 3].r.i == 0 && m[1, 3].alpha.i == 0
        # toStraightAlpha: mult = 255.0 / 40 = 6.375;
        # r = roundHalfAway(10 * 6.375) = 64; g = roundHalfAway(20 * 6.375) =
        # 128 (127.5 ties away); b = roundHalfAway(30 * 6.375) = 191 (191.25).
        @test m[2, 1].r.i == 64 && m[2, 1].g.i == 128 &&
            m[2, 1].b.i == 191 && m[2, 1].alpha.i == 40
        @test m[2, 2].r.i == 200 && m[2, 2].g.i == 100 &&
            m[2, 2].b.i == 50 && m[2, 2].alpha.i == 255
        # Export does not mutate the source image.
        @test m[1, 1] == RGBA{n8}(n8(255 // 255), n8(128 // 255),
            n8(0 // 255), n8(255 // 255))
        @test img.data == d
    end

    @testset "import (straight -> premultiplied)" begin
        # N0f8 RGBA: rgbx formula (v * a + 127) div 255, hand-derived:
        # (200, 100, 50, 128): r = (200*128+127)/255 = 100; g = (100*128+127)/
        # 255 = 50; b = (50*128+127)/255 = 25; a = 128.
        m = Matrix{RGBA{n8}}(undef, 2, 3)
        for (y, x) in Iterators.product(1:2, 1:3)
            m[y, x] = RGBA{n8}(n8(200 // 255), n8(100 // 255),
                n8(50 // 255), n8(128 // 255))
        end
        img = fromColors(m)
        @test (width(img), height(img)) == (3, 2)
        d = img.data
        @test d[1:4] == UInt8[100, 50, 25, 128]
        @test d[5:8] == UInt8[100, 50, 25, 128]
        @test d[13:16] == UInt8[100, 50, 25, 128]

        # Opaque N0f8 RGB (no alpha channel): stored as a = 255.
        m2 = Matrix{RGB{n8}}(undef, 1, 2)
        m2[1, 1] = RGB{n8}(n8(10 // 255), n8(20 // 255), n8(30 // 255))
        m2[1, 2] = RGB{n8}(n8(40 // 255), n8(50 // 255), n8(60 // 255))
        img2 = fromColors(m2)
        @test img2.data == UInt8[10, 20, 30, 255, 40, 50, 60, 255]

        # Zero-alpha RGBA: premultiplied channels must be zero.
        mz = Matrix{RGBA{n8}}(undef, 1, 1)
        mz[1, 1] = RGBA{n8}(n8(1 // 1), n8(1 // 1), n8(1 // 1), n8(0 // 255))
        @test fromColors(mz).data == UInt8[0, 0, 0, 0]

        # Float64 RGBA, 0..1: clamped and rounded to bytes; rgbx after.
        mf = Matrix{RGBA{Float64}}(undef, 1, 3)
        mf[1, 1] = RGBA{Float64}(0.5, 0.25, 1.0, 1.0)
        mf[1, 2] = RGBA{Float64}(1.5, -0.2, 0.0, 0.5)   # out-of-range clamp
        mf[1, 3] = RGBA{Float64}(1.0, 1.0, 1.0, 0.0)    # zero alpha
        imgf = fromColors(mf)
        @test imgf.data[1:4] == UInt8[128, 64, 255, 255]  # round(0.5*255)=128
        # (255, 0, 0, 128) straight -> premultiplied: r = (255*128+127)/255 = 128
        @test imgf.data[5:8] == UInt8[128, 0, 0, 128]     # clamp 1.5 -> 255 first
        @test imgf.data[9:12] == UInt8[0, 0, 0, 0]        # zero alpha clears

        # Float32 channels widen exactly to Float64 (same bytes).
        m32 = Matrix{RGBA{Float32}}(undef, 1, 1)
        m32[1, 1] = RGBA{Float32}(0.5f0, 0.25f0, 1.0f0, 1.0f0)
        @test fromColors(m32).data == UInt8[128, 64, 255, 255]
    end

    @testset "input validation" begin
        @test_throws ArgumentError fromColors(zeros(UInt8, 2, 3))
        @test_throws ArgumentError fromColors(zeros(RGB{n8}, 2, 3, 4))
        # The install hint is exercised by the core-only subprocess in
        # codec_loading_tests.jl; here ColorTypes is always loaded.
        @test toColors(newImage(2, 2)) isa Matrix{RGBA{n8}}
    end

    @testset "round trip loss bounds (documented)" begin
        img = newImage(2, 2)
        d = img.data
        d[1:4] = UInt8[255, 255, 255, 255]   # opaque: exact round trip
        d[5:8] = UInt8[0, 0, 0, 0]           # transparent: exact round trip
        d[9:12] = UInt8[128, 64, 0, 128]     # half alpha: at most 1/255 off
        d[13:16] = UInt8[1, 2, 3, 4]         # low alpha
        m = toColors(img)
        back = fromColors(m)
        @test back.data[1:4] == d[1:4]
        @test back.data[5:8] == d[5:8]
        for k in (9:12, 13:16)
            @test all(abs.(Int.(back.data[k]) .- Int.(d[k])) .<= 1)
        end
    end

    @testset "recipe: matrix -> draw -> matrix" begin
        m = Matrix{RGB{n8}}(undef, 4, 6)
        for (y, x) in Iterators.product(1:4, 1:6)
            m[y, x] = RGB{n8}(n8(((x * 40) % 255) // 255),
                n8(((y * 50) % 255) // 255), n8(((x + y) % 255) // 255))
        end
        img = fromColors(m)
        ctx = Context(img)
        ctx.fillStyle = "#FF0000"
        # Continuous coordinates: [0, 2] x [0, 2] covers pixels (1,1)-(2,2).
        fillRect(ctx, 0, 0, 2, 2)
        m2 = toColors(img)
        @test size(m2) == (4, 6)
        @test m2[1, 1].r.i == 255 && m2[1, 1].g.i == 0 && m2[1, 1].b.i == 0
        # Untouched pixels round-trip (opaque RGB import, exact export).
        @test m2[4, 6].r.i == m[4, 6].r.i &&
            m2[4, 6].g.i == m[4, 6].g.i && m2[4, 6].b.i == m[4, 6].b.i
    end

end
