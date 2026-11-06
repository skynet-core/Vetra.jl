# T002: colors, image storage, and basic compositing.
# Expectations come from the pinned upstream fixtures (test/reference/) or
# from the hand-checked formulas in docs/NUMERICAL_CONTRACT.md -- never from
# the code under test.

@testset "T002 core (colors, image, compositing)" begin
    @testset "color types and constructors" begin
        x = rgbx(1, 2, 3, 4)
        @test x isa Vetra.ColorRGBX
        @test (x.r, x.g, x.b, x.a) == (0x01, 0x02, 0x03, 0x04)
        @test all(c -> c isa UInt8, (x.r, x.g, x.b, x.a))
        a = rgba(1, 2, 3, 4)
        @test (a.r, a.g, a.b, a.a) == (1, 2, 3, 4)
        b = rgb(1, 2, 3)
        @test (b.r, b.g, b.b) == (1, 2, 3)
        # upstream takes small ints; out-of-range must be rejected, not wrapped
        @test_throws ArgumentError rgb(256, 0, 0)
        @test_throws ArgumentError rgba(0, 0, 0, -1)
        @test_throws ArgumentError rgbx(1, 2, 3, 511)
        @test rgb(0xff, 0, 0) == rgb(UInt8(255), UInt8(0), UInt8(0))
    end

    @testset "straight <-> premultiplied vs upstream fixtures (exhaustive)" begin
        _, _, pr = VetraRef.read_table("premultiplied_alpha")
        @test length(pr) == 256 * 256
        bad_pre = [
            row for row in pr
            if Vetra.rgbx(Vetra.rgba(parse(UInt8, row[1]), 0, 0, parse(UInt8, row[2]))).r != parse(UInt8, row[3])
            || Vetra.toPremultipliedAlpha(Vetra.rgba(parse(UInt8, row[1]), 0, 0, parse(UInt8, row[2]))).r != parse(UInt8, row[3])
        ]
        @test bad_pre == []

        _, _, sr = VetraRef.read_table("straight_alpha")
        valid = [row for row in sr if row[3] != "invalid"]
        @test length(valid) == 256 * 257 ÷ 2
        function str_ok(row)
            a = parse(UInt8, row[1])
            c = parse(UInt8, row[2])
            p = Vetra.rgbx(c, 0, 0, a)
            return Vetra.rgba(p).r == parse(UInt8, row[3]) &&
                Vetra.toStraightAlpha(p).r == parse(UInt8, row[4])
        end
        @test all(str_ok, valid)

        # documented agreement point and first measured divergence
        @test Vetra.rgba(Vetra.rgbx(1, 0, 0, 1)).r == 255
        @test Vetra.toStraightAlpha(Vetra.rgbx(1, 0, 0, 1)).r == 255
        @test Vetra.rgba(Vetra.rgbx(1, 0, 0, 2)).r == 128
        @test Vetra.toStraightAlpha(Vetra.rgbx(1, 0, 0, 2)).r == 128
        @test Vetra.rgba(Vetra.rgbx(2, 0, 0, 4)).r == 127
        @test Vetra.toStraightAlpha(Vetra.rgbx(2, 0, 0, 4)).r == 128
        # a = 0: chroma leaves channels untouched; pixie table row is all zero
        @test Vetra.rgba(Vetra.rgbx(9, 8, 7, 0)) == Vetra.rgba(9, 8, 7, 0)
        @test Vetra.toStraightAlpha(Vetra.rgbx(9, 8, 7, 0)) == Vetra.rgba(0, 0, 0, 0)
        # a = 255: no-op on either path
        @test Vetra.rgba(Vetra.rgbx(9, 8, 7, 255)) == Vetra.rgba(9, 8, 7, 255)
        @test Vetra.toStraightAlpha(Vetra.rgbx(9, 8, 7, 255)) == Vetra.rgba(9, 8, 7, 255)
    end

    @testset "mix vs upstream fixture (3 pairs x 256 t)" begin
        _, _, rows = VetraRef.read_table("mix")
        @test length(rows) == 3 * 256
        # same pairs the oracle iterated (emit_fixtures.nim)
        pairs = [(0, 0, 0, 0, 255, 255, 255, 255),
                 (200, 100, 50, 255, 50, 200, 100, 128),
                 (1, 2, 3, 4, 254, 253, 252, 251)]
        for (k, p) in enumerate(pairs)
            for i in 0:255
                r = rows[(k - 1) * 256 + i + 1]
                a = Vetra.rgbx(p[1], p[2], p[3], p[4])
                b = Vetra.rgbx(p[5], p[6], p[7], p[8])
                t = Float32(i) / Float32(255)
                got = Vetra.mix(a, b, t)
                @test (got.r, got.g, got.b, got.a) ==
                    (parse(UInt8, r[10]), parse(UInt8, r[11]),
                     parse(UInt8, r[12]), parse(UInt8, r[13]))
            end
        end
    end

    @testset "color * opacity vs upstream fixture (11 colors x 256)" begin
        _, _, rows = VetraRef.read_table("color_opacity")
        @test length(rows) == 11 * 256
        colors = [(0, 0, 0, 0),
                  (1, 1, 1, 1),
                  (5, 3, 2, 10),
                  (255, 255, 255, 255),
                  (0, 0, 0, 255),
                  (255, 255, 255, 254),
                  (200, 100, 50, 255),
                  (100, 50, 25, 100),
                  (64, 128, 64, 128),
                  (128, 0, 128, 128),
                  (255, 128, 64, 192)]
        for (k, c) in enumerate(colors)
            for i in 0:255
                r = rows[(k - 1) * 256 + i + 1]
                got = Vetra.rgbx(c...) * (Float32(i) / Float32(255))
                @test (got.r, got.g, got.b, got.a) ==
                    (parse(UInt8, r[6]), parse(UInt8, r[7]),
                     parse(UInt8, r[8]), parse(UInt8, r[9]))
            end
        end
    end

    @testset "rgbx * coverage vs upstream fixture (8 colors x 256)" begin
        _, _, rows = VetraRef.read_table("rgbx_coverage")
        @test length(rows) == 8 * 256
        for (k, cval) in enumerate([0, 1, 64, 127, 128, 200, 254, 255])
            for o in 0:255
                r = rows[(k - 1) * 256 + o + 1]
                c = Vetra.rgbx(cval, 255 - cval, cval ÷ 2, 255)
                got = c * UInt8(o)
                @test (got.r, got.g, got.b, got.a) ==
                    (parse(UInt8, r[6]), parse(UInt8, r[7]),
                     parse(UInt8, r[8]), parse(UInt8, r[9]))
            end
        end
    end

    @testset "blendAlpha vs upstream fixture (exhaustive 256x256)" begin
        _, _, rows = VetraRef.read_table("blend_alpha")
        @test length(rows) == 256 * 256
        bad = [
            row for row in rows
            if UInt8(Vetra.blendAlpha(parse(UInt8, row[1]), parse(UInt8, row[2]))) != parse(UInt8, row[3])
        ]
        @test bad == []
        @test Vetra.blendAlpha(UInt8(0), UInt8(128)) == 128
        @test Vetra.blendAlpha(UInt8(255), UInt8(255)) == 255
    end

    @testset "blendNormal vs upstream fixture (11x11 valid premul grid)" begin
        _, _, rows = VetraRef.read_table("blend_normal")
        @test length(rows) == 11 * 11
        valid = [(0, 0, 0, 0),
                 (1, 1, 1, 1),
                 (5, 3, 2, 10),
                 (255, 255, 255, 255),
                 (0, 0, 0, 255),
                 (255, 255, 255, 254),
                 (200, 100, 50, 255),
                 (100, 50, 25, 100),
                 (64, 128, 64, 128),
                 (128, 0, 128, 128),
                 (255, 128, 64, 192)]
        for (i0, b) in enumerate(valid)
            for (j0, s) in enumerate(valid)
                r = rows[(i0 - 1) * 11 + j0]
                got = Vetra.blendNormal(Vetra.rgbx(b[1], b[2], b[3], b[4]),
                    Vetra.rgbx(s[1], s[2], s[3], s[4]))
                @test (got.r, got.g, got.b, got.a) ==
                    (parse(UInt8, r[9]), parse(UInt8, r[10]),
                     parse(UInt8, r[11]), parse(UInt8, r[12]))
            end
        end
        # early-out semantics (hand-checked against blend_normal.tsv)
        @test Vetra.blendNormal(Vetra.rgbx(255, 255, 255, 255),
            Vetra.rgbx(100, 50, 25, 100)) == Vetra.rgbx(255, 205, 180, 255)
        @test Vetra.blendNormal(Vetra.rgbx(255, 255, 255, 255),
            Vetra.rgbx(100, 50, 25, 255)) == Vetra.rgbx(100, 50, 25, 255)
        # upstream wraps channel sums mod 256 on invalid-premul inputs
        # (both cells read straight from blend_normal.tsv)
        @test Vetra.blendNormal(Vetra.rgbx(5, 3, 2, 10),
            Vetra.rgbx(255, 128, 64, 192)) == Vetra.rgbx(0, 128, 64, 194)
        @test Vetra.blendNormal(Vetra.rgbx(255, 255, 255, 255),
            Vetra.rgbx(255, 255, 255, 254)) == Vetra.rgbx(0, 0, 0, 255)
    end

    @testset "image storage and access" begin
        img = newImage(4, 3)
        @test (Vetra.width(img), Vetra.height(img)) == (4, 3)
        @test length(img.data) == 4 * 4 * 3
        # row-major, rows top to bottom, 4 bytes per pixel, R,G,B,A
        fill(img, rgbx(9, 8, 7, 3))
        for (x, y) in [(1, 1), (4, 1), (1, 3), (4, 3)]
            @test getColor(img, x, y) == rgbx(9, 8, 7, 3)
        end
        base = ((2 - 1) * 4 + (3 - 1)) * 4  # (x=3, y=2) 0-based offset
        @test img.data[base + 1:base + 4] == [9, 8, 7, 3]
        # inside is 1-based; the contract documents the translation
        @test inside(img, 1, 1) && inside(img, 4, 3)
        @test !inside(img, 0, 1) && !inside(img, 5, 1) && !inside(img, 1, 4)
        # bounds errors instead of out-of-bounds reads
        @test_throws BoundsError getColor(img, 0, 1)
        @test_throws BoundsError getColor(img, 5, 1)
        @test_throws BoundsError getColor(img, 1, 4)
        @test_throws BoundsError setColor(img, 5, 1, rgbx(1, 1, 1, 1))
        # bad dimensions reject before allocating
        @test_throws ArgumentError newImage(0, 3)
        @test_throws ArgumentError newImage(3, 0)
        @test_throws ArgumentError newImage(-1, 3)
        # copy isolates storage (upstream copies the data buffer)
        other = copy(img)
        @test other !== img
        @test (Vetra.width(other), Vetra.height(other)) == (4, 3)
        setColor(other, 2, 2, rgb(255, 0, 0))
        @test getColor(img, 2, 2) == rgbx(9, 8, 7, 3)
        @test getColor(other, 2, 2) == rgbx(255, 0, 0, 255)
        # setColor converts straight-alpha colors to the premul storage format
        fill(img, rgba(200, 100, 50, 128))
        @test getColor(img, 1, 1) == rgbx(100, 50, 25, 128)
        setColor(img, 1, 1, rgba(255, 255, 255, 128))
        @test getColor(img, 1, 1) == rgbx(128, 128, 128, 128)
        setColor(img, 1, 1, rgba(255, 0, 0, 2))
        @test getColor(img, 1, 1) == rgbx(2, 0, 0, 2)
        # fill with a straight color stores premultiplied (asRgbx upstream)
        fill(img, rgba(100, 200, 50, 128))
        @test getColor(img, 1, 1) == rgbx(50, 100, 25, 128)
        # every stored byte matches the premultiplied fill color
        @test img.data == [UInt8([50, 100, 25, 128][i % 4 + 1]) for i in 0:47]
    end
end
