# test/reference_tests.jl
#
# T001 reference fixture tests: metadata, dimensions, checksums, channel
# order, row/column orientation, and the comparison helper (including a
# deliberate mismatch). Expected values are hand-computed from
# docs/NUMERICAL_CONTRACT.md formulas or directly from the construction of
# the upstream examples (both independent of the Julia code under test).

using Test
using SHA
using .VetraRef

const IMAGE_TAGS = ("square", "line", "heart", "draw_translate", "draw_scale2")

@testset "T001 reference fixtures" begin

    @testset "canonical buffers: $tag" for tag in IMAGE_TAGS
        data, (w, h) = VetraRef.read_raw(tag)
        @test w > 0 && h > 0
        @test length(data) == 4 * w * h            # dimensions × RGBA layout
        @test VetraRef.verify_checksum(tag)         # sha256 vs recorded meta
    end

    @testset "declared dimensions match construction" begin
        _, d = VetraRef.read_raw("square")
        @test d == (200, 200)   # examples/square.nim: newImage(200, 200)
        _, d = VetraRef.read_raw("draw_translate")
        @test d == (8, 6)       # synthetic: dst newImage(8, 6)
        _, d = VetraRef.read_raw("draw_scale2")
        @test d == (16, 12)     # synthetic: dst newImage(16, 12)
    end

    @testset "channel order and orientation (hand-checked values)" begin
        # square: white 200x200, red 100x100 filled at (50,50). blendNormal
        # with source.a == 255 returns the source pixel verbatim; pixels
        # outside the rect keep the white backdrop.
        s, sh = VetraRef.read_raw("square")
        @test VetraRef.pixel(s, sh, 1, 1) == (255, 255, 255, 255)
        @test VetraRef.pixel(s, sh, 100, 100) == (255, 0, 0, 255)

        # line: stroke (25,25)-(175,175) width 10, color #FF5C00 opaque;
        # (100,100) is on the segment (distance 0 < 5) -> full coverage.
        l, lh = VetraRef.read_raw("line")
        @test VetraRef.pixel(l, lh, 1, 1) == (255, 255, 255, 255)
        @test VetraRef.pixel(l, lh, 101, 101) == (255, 92, 0, 255)

        # heart: white backdrop, #FC427B fill; (100,120) is well inside the
        # silhouette (between the top dip ~y=60 and the bottom tip y=180).
        hrt, hh = VetraRef.read_raw("heart")
        @test VetraRef.pixel(hrt, hh, 1, 1) == (255, 255, 255, 255)
        @test VetraRef.pixel(hrt, hh, 100, 120) == (252, 66, 123, 255)

        # draw_translate: 4x3 source (100,50,25,128) at (2,1) 0-based over
        # white 8x6. blendNormal with k = 127: r = 100 + 255*127 div 255 = 227,
        # g = 50 + 127 = 177, b = 25 + 127 = 152, a = 128 + 127 = 255.
        # The source spans 1-based x in 3..6, y in 2..4, so each neighbor
        # check pins one axis (a transposed buffer would fail them):
        dt, dh = VetraRef.read_raw("draw_translate")
        @test VetraRef.pixel(dt, dh, 3, 2) == (227, 177, 152, 255)
        @test VetraRef.pixel(dt, dh, 2, 2) == (255, 255, 255, 255)  # left
        @test VetraRef.pixel(dt, dh, 3, 1) == (255, 255, 255, 255)  # above
        @test VetraRef.pixel(dt, dh, 3, 5) == (255, 255, 255, 255)  # below
        @test VetraRef.pixel(dt, dh, 2, 3) == (255, 255, 255, 255)  # transposed

        # draw_scale2: 2x2 red 2x-scaled to 4x4 at (6,8) 0-based; (7..10,
        # 9..12) 1-based fully covered, outside white.
        ds, dsd = VetraRef.read_raw("draw_scale2")
        @test VetraRef.pixel(ds, dsd, 1, 1) == (255, 255, 255, 255)
        @test VetraRef.pixel(ds, dsd, 7, 9) == (255, 0, 0, 255)
        @test VetraRef.pixel(ds, dsd, 10, 12) == (255, 0, 0, 255)
        @test VetraRef.pixel(ds, dsd, 11, 12) == (255, 255, 255, 255)
    end

    @testset "arithmetic tables (hand-checked rows)" begin
        # premultiplied: (c * a + 127) div 255
        # row a=128, c=200: (200*128 + 127) div 255 = 25727 div 255 = 100
        meta, cols, rows = VetraRef.read_table("premultiplied_alpha")
        @test cols == ["straight_c", "channel_a", "result"]
        r = rows[128 * 256 + 200 + 1]
        @test r == ["128", "200", "100"]
        # a=0: all channels 0 (0*a + 127) div 255 = 0
        @test rows[1][3] == "0" && rows[0 * 256 + 255 + 1][3] == "0"

        # straight alpha: the two upstream conversion paths (documented in
        # docs/NUMERICAL_CONTRACT.md). Hand-checked rows:
        # a=1, c=1: chroma m=round(255*255)=65025 -> (1*65025+127) div 255 = 255;
        #           pixie min(round(1*255), 255) = 255 (agree)
        # a=2, c=1: chroma m=round(127.5*255)=32513 -> (32513+127) div 255 = 128;
        #           pixie min(round(1*127.5), 255) = 128 (agree: both round 127.5)
        m2, c2, r2 = VetraRef.read_table("straight_alpha")
        @test c2 == ["backdrop_a", "channel", "chroma_rgba_path", "pixie_toStraightAlpha_path"]
        @test r2[1 * 256 + 1 + 1][3:4] == ["255", "255"]   # a=1, c=1
        @test r2[2 * 256 + 1 + 1][3:4] == ["128", "128"]   # a=2, c=1
        # measured divergence in the valid domain (a=4, c=2):
        # chroma: m=round(255/4*255)=16256 -> (2*16256+127) div 255 = 32639 div 255 = 127
        # pixie:  min(round(2 * f32(255/4)), 255) = round(127.5) = 128
        @test r2[4 * 256 + 2 + 1][3:4] == ["127", "128"]

        # mix: pair 0 (black->white), i = 128
        # x = round(f32(128/255) * 255) = 128
        # c = (0 * (255-128) + 255 * 128 + 127) div 255 = 32767 div 255 = 128
        # (all channels, incl. alpha)
        m3, _, r3 = VetraRef.read_table("mix")
        row = r3[128 + 1]
        @test row[1:4] == ["0", "0", "0", "0"]
        @test row[5:8] == ["255", "255", "255", "255"]
        @test row[9] == "0.5019608"
        @test row[10:13] == ["128", "128", "128", "128"]

        # color * opacity: validPremul[3] = white, i = 128
        # x = 128 -> (255*128 + 127) div 255 = 32767 div 255 = 128 (all channels)
        m4, _, r4 = VetraRef.read_table("color_opacity")
        @test r4[3 * 256 + 128 + 1][6:9] == ["128", "128", "128", "128"]

        # rgbx * coverage: color list idx 3 = (127, 255-127, 127 div 2, 255)
        # coverage = 128:
        # r: (127*128+127) div 255 = 16383 div 255 = 64   (255*64 = 16320 <= 16383 < 16575)
        # g: (128*128+127) div 255 = 16511 div 255 = 64   (16320 <= 16511 < 16575)
        # b: (63*128+127) div 255 = 8191 div 255 = 32     (255*32 = 8160 <= 8191 < 8415)
        # a: (255*128+127) div 255 = 32767 div 255 = 128  (255*128 = 32640 <= 32767)
        m5, _, r5 = VetraRef.read_table("rgbx_coverage")
        @test r5[3 * 256 + 128 + 1][1:4] == ["127", "128", "63", "255"]
        @test r5[3 * 256 + 128 + 1][6:9] == ["64", "64", "32", "128"]

        # blendAlpha: sa + (ba * (255 - sa)) div 255; ba=100, sa=100
        # 100 + (100 * 155) div 255 = 100 + 15500 div 255 = 100 + 60 = 160
        m6, _, r6 = VetraRef.read_table("blend_alpha")
        @test r6[100 * 256 + 100 + 1] == ["100", "100", "160"]
        # ba=255, sa=100: 100 + (255*155) div 255 = 100 + 155 = 255
        @test r6[255 * 256 + 100 + 1] == ["255", "100", "255"]

        # blendNormal: validPremul grid (11 colors).
        # white backdrop, source (100,50,25,100): k = 255-100 = 155
        # r = 100 + (255*155) div 255 = 255; g = 50 + 155 = 205; b = 25 + 155 = 180;
        # a = blendAlpha(255, 100) = 100 + (255*155) div 255 = 255
        m7, _, r7 = VetraRef.read_table("blend_normal")
        @test r7[3 * 11 + 7 + 1][9:12] == ["255", "205", "180", "255"]
        # opaque source (a = 255) is returned verbatim (early-out, no arithmetic)
        @test r7[3 * 11 + 4 + 1][9:12] == ["0", "0", "0", "255"]

        # gaussian kernel: symmetric weights, peak at the center index
        m8, _, r8 = VetraRef.read_table("gaussian_kernel")
        for radius in (1, 3, 8, 16)
            row = r8[findfirst(x -> x[1] == string(radius), r8)]
            wts = [parse(Int, c) for c in row[2:end]]
            @test length(wts) == 2 * radius + 1
            @test wts[radius + 1] == maximum(wts)
            @test all(wts[i] == wts[2 * radius + 2 - i] for i in 1:radius)
            @test all(0 <= w <= 65280 for w in wts)
        end

        # snapToPixels: floor the min, ceil the max (bumpy snapToPixels)
        m9, _, r9 = VetraRef.read_table("snap_to_pixels")
        # (x=10.5, y=5.5, w=1, h=1) -> x=floor(10.5)=10, w=ceil(11.5)-10=2, y=5, h=2
        row = r9[findfirst(x ->
            x[1] == "10.5" && x[2] == "5.5" && x[3] == "1.0" && x[4] == "1.0", r9)]
        @test row[5:8] == ["10.0", "5.0", "2.0", "2.0"]
        # (x=5.0, y=9.1, w=10.5, h=1.0) -> x=5, w=ceil(15.5)-5=11, y=9, h=ceil(10.1)-9=2
        row = r9[findfirst(x ->
            x[1] == "5.0" && x[2] == "9.1" && x[3] == "10.5" && x[4] == "1.0", r9)]
        @test row[5:8] == ["5.0", "9.0", "11.0", "2.0"]
    end

    @testset "helper behavior: deliberate and structural mismatches" begin
        data, wh = VetraRef.read_raw("heart")
        corrupted = copy(data)
        x, y, ch = 13, 13, 2
        i = ((y - 1) * wh[1] + (x - 1)) * 4 + ch
        corrupted[i] = corrupted[i] == 255 ? 0x00 : 0xff
        r = VetraRef.compare_pixels(corrupted, data, wh)
        @test r.count == 1
        @test r.first_coord == (x, y, ch)
        @test r.max_abs > 0
        @test VetraRef.hexdigest(sha256(corrupted)) != VetraRef.load_meta("heart")["sha256_raw"]

        # structural: truncated buffer must not compare silently
        @test_throws ArgumentError VetraRef.compare_pixels(data[1:end - 1], data, wh)
        @test_throws ArgumentError VetraRef.compare_pixels(data, data, (0, 4))
        # pixel() bounds checking
        @test_throws BoundsError VetraRef.pixel(data, wh, 0, 1)
        @test_throws BoundsError VetraRef.pixel(data, wh, wh[1] + 1, 1)

        # equality case
        r = VetraRef.compare_pixels(data, data, wh)
        @test r.count == 0 && r.max_abs == 0
    end

end # testset
