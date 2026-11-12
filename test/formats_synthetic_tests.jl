# T008 coverage: synthetic format branches.
#
# Hand-built byte streams exercising the codec branches the pinned upstream
# fixtures do not reach (palette BMPs, top-down, GIF LCT/interlace/disposal,
# JPEG Exif/resync, QOI encode ops, PPM 16-bit, SVG style/gradient/url
# branches). Expected values are pinned three ways, per test/README.md:
# upstream-fixture-derived (the f*-exif dimensions), upstream-oracle-verified
# (GIF LZW byte streams decoded by the pinned Nim decoder; see T008 handoff),
# or hand-derived from the format specifications (BMP/QOI/PPM/JPEG headers).

@testset "T008 synthetic format branches" begin
    le16(v::Int) = UInt8[v & 0xff, (v >> 8) & 0xff]
    le32(v::Int) = UInt8[v & 0xff, (v >> 8) & 0xff, (v >> 16) & 0xff,
        (v >> 24) & 0xff]
    be16(v::Int) = UInt8[(v >> 8) & 0xff, v & 0xff]
    be32(v::Int) = UInt8[(v >> 24) & 0xff, (v >> 16) & 0xff, (v >> 8) & 0xff,
        v & 0xff]
    px = (img, i) -> (o = 4 * (i - 1);
        (Int(img.data[o + 1]), Int(img.data[o + 2]), Int(img.data[o + 3]),
            Int(img.data[o + 4])))

    @testset "BMP synthetic bit depths, palettes, top-down" begin
        # 8-bit 2x2: palette BGRA [blue, green, red, white]; file rows are
        # bottom-up and padded to 4 bytes: row0=[3,2], row1=[1,0].
        bmp8 = vcat(UInt8[0x42, 0x4d], le32(78), le32(0), le32(70),
            le32(40), le32(2), le32(2), le16(1), le16(8), le32(0), le32(0),
            le32(0), le32(0), le32(4), le32(0),
            UInt8[0, 0, 255, 0, 0, 255, 0, 0, 255, 0, 0, 0, 255, 255, 255, 0],
            UInt8[3, 2, 0, 0, 1, 0, 0, 0])
        img = decodeBMP(bmp8)
        @test [px(img, i) for i in 1:4] ==
            [(0, 255, 0, 255), (255, 0, 0, 255), (255, 255, 255, 255),
                (0, 0, 255, 255)]

        # 4-bit 2x1: one byte 0x21 (high nibble 2, low nibble 1), padded.
        bmp4 = vcat(UInt8[0x42, 0x4d], le32(74), le32(0), le32(70),
            le32(40), le32(2), le32(1), le16(1), le16(4), le32(0), le32(0),
            le32(0), le32(0), le32(4), le32(0),
            UInt8[0, 0, 255, 0, 0, 255, 0, 0, 255, 0, 0, 0, 255, 255, 255, 0],
            UInt8[0x21, 0, 0, 0])
        @test [px(decodeBMP(bmp4), i) for i in 1:2] ==
            [(0, 0, 255, 255), (0, 255, 0, 255)]

        # 1-bit 4x1: 0b10110000 (MSB first) over [e1, e0].
        bmp1 = vcat(UInt8[0x42, 0x4d], le32(63), le32(0), le32(62),
            le32(40), le32(4), le32(1), le16(1), le16(1), le32(0), le32(0),
            le32(0), le32(0), le32(2), le32(0),
            UInt8[10, 20, 30, 0, 200, 150, 100, 0], UInt8[0b10110000])
        @test [px(decodeBMP(bmp1), i) for i in 1:4] ==
            [(100, 150, 200, 255), (30, 20, 10, 255), (100, 150, 200, 255),
                (100, 150, 200, 255)]

        # 24-bit top-down (negative height): file rows are already top to
        # bottom; width 2 gives 2 bytes of row padding.
        bmpTop = vcat(UInt8[0x42, 0x4d], le32(70), le32(0), le32(54),
            le32(40), le32(2), le32(-2), le16(1), le16(24), le32(0),
            le32(0), le32(0), le32(0), le32(0), le32(0),
            UInt8[3, 2, 1, 6, 5, 4, 0, 0, 9, 8, 7, 12, 11, 10, 0, 0])
        @test [px(decodeBMP(bmpTop), i) for i in 1:4] ==
            [(1, 2, 3, 255), (4, 5, 6, 255), (7, 8, 9, 255), (10, 11, 12, 255)]
        @test decodeBMPDimensions(bmpTop) == (2, 2)

        # 32-bit BITMAPV3HEADER (biSize 108) with a nonzero file
        # alphaMask (byte 3 of the pixel): useAlpha, so the pixel bytes
        # are straight RGBA at the file boundary. The BI_RGB default
        # masks read byte2=red, byte1=green, byte0=blue, so the stored
        # straight (64,32,16,128) decodes to premultiplied
        # ((64*128+127) div 255, (32*128+127) div 255,
        # (16*128+127) div 255, 128) = (32,16,8,128).
        bmp32a = vcat(UInt8[0x42, 0x4d], le32(126), le32(0), le32(122),
            le32(108), le32(1), le32(1), le16(1), le16(32), le32(0),
            le32(4), le32(0), le32(0), le32(0), le32(0),
            zeros(UInt8, 12), le32(Int(0xff000000)), zeros(UInt8, 52),
            UInt8[0x10, 0x20, 0x40, 0x80])
        @test px(decodeBMP(bmp32a), 1) == (32, 16, 8, 128)
    end

    @testset "GIF synthetic: tables, interlace, disposal, extensions" begin
        gifHdr = vcat(codeunits("GIF89a"), le16(2), le16(2),
            UInt8[0x80, 0, 0], UInt8[255, 0, 0, 0, 255, 0])

        # Comment extension (0x21 0xfe) is skipped, then a 1x1 frame,
        # palette index 0 (red). LZW [4, 0, 5] @3-bit = [0x44, 0x01]
        # (oracle-verified against the pinned upstream decoder).
        g = vcat(gifHdr,
            UInt8[0x21, 0xfe, 2, 0x48, 0x69, 0,
                0x2c, 0, 0, 0, 0, 1, 0, 1, 0, 0x00, 2, 2, 0x44, 0x01, 0, 0x3b])
        gif = decodeGIF(g)
        @test px(gif.frames[1], 1) == (255, 0, 0, 255)
        @test length(gif.intervals) == 1

        # Unknown extension type.
        try
            decodeGIF(vcat(gifHdr, UInt8[0x21, 0x01, 3, 0x48, 0x69, 0]))
        catch e
            @test e.msg == "Unexpected GIF extension type 01"
        end

        # Unknown block type.
        try
            decodeGIF(vcat(gifHdr, UInt8[0x00, 0x3b]))
        catch e
            @test e.msg == "Unexpected GIF block type 00"
        end

        # Background color index outside the GCT.
        try
            decodeGIF(vcat(codeunits("GIF89a"), le16(2), le16(2),
                UInt8[0x80, 5, 0], UInt8[255, 0, 0, 0, 255, 0],
                UInt8[0x3b]))
        catch e
            @test e.msg == "Invalid GIF buffer, unable to load"
        end

        # Local color table truncated at end of buffer.
        try
            decodeGIF(vcat(codeunits("GIF89a"), le16(2), le16(2),
                UInt8[0x00, 0, 0],
                UInt8[0x2c, 0, 0, 0, 0, 1, 0, 1, 0, 0x81]))
        catch e
            @test e.msg == "Invalid GIF buffer, unable to load"
        end

        # Interlaced 2x2, GCT [red, green]: LZW [4, 0, 1, 0, 1, 5] =
        # [0x44, 0x10, 0x05] (oracle-verified). Deinterlaced rows are
        # [red, green] twice.
        gi = vcat(gifHdr,
            UInt8[0x2c, 0, 0, 0, 0, 2, 0, 2, 0, 0x40],
            UInt8[2, 3, 0x44, 0x10, 0x05, 0], 0x3b)
        gif = decodeGIF(gi)
        @test [px(gif.frames[1], i) for i in 1:4] ==
            [(255, 0, 0, 255), (0, 255, 0, 255), (255, 0, 0, 255),
                (0, 255, 0, 255)]

        # Interlaced 1x4, 4-entry GCT (packed 0x81 per the upstream
        # 2^(field+1) formula): the LZW stream carries the rows in pass
        # order [idx0, idx2, idx1, idx3] = [4, 0, 2, 1, 3, 5] codes =
        # [0x84, 0x32, 0x05] (oracle-verified). A correct deinterlace restores
        # idx0..idx3 top to bottom; this distinct-row case catches
        # pass-offset/order errors the 2x2 identity mapping cannot.
        g4 = vcat(codeunits("GIF89a"), le16(1), le16(4),
            UInt8[0x81, 0, 0],
            UInt8[10, 11, 12, 40, 41, 42, 70, 71, 72, 100, 101, 102],
            UInt8[0x2c, 0, 0, 0, 0, 1, 0, 4, 0, 0x40, 2],
            UInt8[3, 0x84, 0x32, 0x05, 0], 0x3b)
        @test [px(decodeGIF(g4).frames[1], i) for i in 1:4] ==
            [(10, 11, 12, 255), (40, 41, 42, 255), (70, 71, 72, 255),
                (100, 101, 102, 255)]

        # 1x1 local color table (4 entries), pixel = LCT index 3.
        # LZW [4, 3, 5] = [0x5c, 0x01] (oracle-verified).
        gl = vcat(codeunits("GIF89a"), le16(1), le16(1), UInt8[0x00, 0, 0],
            UInt8[0x2c, 0, 0, 0, 0, 1, 0, 1, 0, 0x81],
            UInt8[1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12],
            UInt8[2, 2, 0x5c, 0x01, 0], 0x3b)
        @test px(decodeGIF(gl).frames[1], 1) == (10, 11, 12, 255)

        # Disposal method 2 + transparency: GCT [black, red], GCE sets
        # transparent index 1; the frame index 1 is transparent, so the
        # disposal-2 background (black) remains. LZW [4, 1, 5] =
        # [0x4c, 0x01] (oracle-verified).
        gd = vcat(codeunits("GIF89a"), le16(1), le16(1), UInt8[0x80, 0, 0],
            UInt8[0, 0, 0, 255, 0, 0],
            UInt8[0x21, 0xf9, 4, 0x09, 0, 0, 1, 0],
            UInt8[0x2c, 0, 0, 0, 0, 1, 0, 1, 0, 0x00],
            UInt8[2, 2, 0x4c, 0x01, 0], 0x3b)
        @test px(decodeGIF(gd).frames[1], 1) == (0, 0, 0, 255)

        # Out-of-range palette index is skipped (upstream: failInvalid
        # commented out) -> transparent pixel. LZW [4, 3, 5] = [0x5c, 0x01]
        # over a 2-entry GCT.
        go = vcat(gifHdr,
            UInt8[0x2c, 0, 0, 0, 0, 1, 0, 1, 0, 0x00],
            UInt8[2, 2, 0x5c, 0x01, 0], 0x3b)
        @test px(decodeGIF(go).frames[1], 1) == (0, 0, 0, 0)
    end

    @testset "JPEG synthetic: marker scan, resync, Exif" begin
        sof(w, h) = vcat(UInt8[0xff, 0xc0], be16(8), UInt8[0x08], be16(h),
            be16(w), UInt8[0x03])
        soi = UInt8[0xff, 0xd8]
        eoi = UInt8[0xff, 0xd9]

        # A non-SOF marker (APP0/JFIF) before SOF0 is skipped.
        @test decodeJPEGDimensions(
            vcat(soi, UInt8[0xff, 0xe0], be16(9),
                codeunits("JFIF\0"), UInt8[0, 2], sof(80, 40), eoi)) == (80, 40)

        # Big-endian (MM) Exif with orientation 5 swaps the stored 80x40.
        # len 34 = 2 (field) + 32 (payload); the chunk is self-consistent,
        # so the scan lands exactly on the SOF (no resync involved).
        exif(w::Int) = vcat(UInt8[0xff, 0xe1], be16(34),
            codeunits("Exif\0\0"), codeunits("MM"), be16(Int(0x002a)), be32(8),
            be16(1), be16(Int(0x0112)), be16(3), be32(2), be16(w), be16(0),
            be32(0))
        @test decodeJPEGDimensions(vcat(soi, exif(5), sof(80, 40), eoi)) ==
            (40, 80)
        # Orientation outside 1..8 is rejected.
        try
            decodeJPEGDimensions(vcat(soi, exif(9), sof(80, 40), eoi))
        catch e
            @test e.msg == "Invalid JPEG, invalid orientation"
        end

        # DHT is structurally validated (upstream `decodeDHT`), not skipped.
        # Well-formed table (1 symbol) before SOF0 is accepted.
        dhtOk = vcat(UInt8[0xff, 0xc4], be16(20), UInt8[0x00],
            vcat(UInt8[0x01], zeros(UInt8, 15)), UInt8[0])
        @test decodeJPEGDimensions(
            vcat(soi, dhtOk, sof(80, 40), eoi)) == (80, 40)
        # Bad table id (4) is rejected.
        try
            decodeJPEGDimensions(vcat(soi,
                vcat(UInt8[0xff, 0xc4], be16(20), UInt8[0x14],
                    vcat(UInt8[0x01], zeros(UInt8, 15)), UInt8[0]),
                sof(80, 40), eoi))
        catch e
            @test e.msg == "Invalid JPEG, unable to load"
        end
        # Count sum above 256 is rejected.
        try
            decodeJPEGDimensions(vcat(soi,
                vcat(UInt8[0xff, 0xc4], be16(276), UInt8[0x00],
                    vcat(UInt8[0xff, 0x02], zeros(UInt8, 14)),
                    zeros(UInt8, 257)),
                sof(80, 40), eoi))
        catch e
            @test e.msg == "Invalid JPEG, unable to load"
        end

        # Resync: up to 64 junk bytes between markers are skipped...
        @test decodeJPEGDimensions(
            vcat(soi, zeros(UInt8, 64), sof(40, 20), eoi)) == (40, 20)
        # ...more than that fails.
        try
            decodeJPEGDimensions(vcat(soi, zeros(UInt8, 65), sof(40, 20), eoi))
        catch e
            @test e.msg == "Invalid JPEG, invalid chunk marker"
        end
        # FF-stuffing (0xFF 0x00) between markers.
        @test decodeJPEGDimensions(
            vcat(soi, UInt8[0xff, 0x00], UInt8[0xff, 0x00], sof(40, 20),
                eoi)) == (40, 20)

        # Pinned upstream Exif masters: f1..f8 all decode to (40, 80).
        for i in 1:8
            @test decodeJPEGDimensions(
                read(joinpath(UPSTREAM_FF, "jpeg", "masters",
                    "f$i-exif.jpg"))) == (40, 80)
        end
    end

    @testset "QOI synthetic: decode ops and encode ops" begin
        qoiHdr(w, h, ch, cs) = vcat(codeunits("qoif"), be32(w), be32(h),
            UInt8[ch, cs])
        padding = vcat(zeros(UInt8, 7), UInt8[0x01])

        # INDEX: RGB(10,20,30) then index byte 9 (hash(10,20,30,255) = 9).
        q = vcat(qoiHdr(2, 1, 4, 1), UInt8[0xfe, 10, 20, 30, 9], padding)
        @test [px(newImage(decodeQOI(q)), i) for i in 1:2] ==
            [(10, 20, 30, 255), (10, 20, 30, 255)]

        # 0x36 has op tag 0x00 -> INDEX byte 0x36 (empty table slot).
        q = vcat(qoiHdr(1, 2, 4, 1), UInt8[0xfe, 100, 100, 100, 0x36], padding)
        @test [px(newImage(decodeQOI(q)), i) for i in 1:2] ==
            [(100, 100, 100, 255), (0, 0, 0, 0)]

        # LUMA: b0 = 0xB5 (vg = 53 - 32 = 21), b1 = 0x03.
        q = vcat(qoiHdr(1, 2, 4, 1), UInt8[0xfe, 50, 50, 50, 0xb5, 0x03],
            padding)
        @test [px(newImage(decodeQOI(q)), i) for i in 1:2] ==
            [(50, 50, 50, 255), (63, 71, 66, 255)]

        # RUN: 0xC0 encodes run = 0; the pixel still repeats once here.
        q = vcat(qoiHdr(1, 2, 4, 1), UInt8[0xfe, 1, 2, 3, 0xc0], padding)
        @test [px(newImage(decodeQOI(q)), i) for i in 1:2] ==
            [(1, 2, 3, 255), (1, 2, 3, 255)]

        # sRBG colorspace decodes through srgbToLinear (100 -> 32).
        q = vcat(qoiHdr(1, 1, 4, 0), UInt8[0xfe, 100, 100, 100], padding)
        @test px(newImage(decodeQOI(q)), 1) == (32, 32, 32, 255)

        # Encoding an sRBG Qoi linearizes the pixels (header says Linear).
        back = newImage(decodeQOI(
            Vector{UInt8}(encodeQOI(Qoi(1, 1, 3, sRBG,
                UInt8[100, 100, 100, 255])))))
        @test px(back, 1) == (32, 32, 32, 255)

        # Encode op coverage: A=(10,20,30), B=(11,19,30), C=(14,22,33),
        # D=(10,20,30,128); [A,A,A,B,C,A,A,A,A,D] emits, in order:
        # RGB, RUN(1), DIFF, LUMA, INDEX(9), RUN(2), RGBA.
        img = newImage(10, 1)
        d = img.data
        seq = [(10, 20, 30, 255), (10, 20, 30, 255), (10, 20, 30, 255),
            (11, 19, 30, 255), (14, 22, 33, 255), (10, 20, 30, 255),
            (10, 20, 30, 255), (10, 20, 30, 255), (10, 20, 30, 255),
            (10, 20, 30, 128)]
        for i in 1:10
            p = rgbx(rgba(seq[i][1], seq[i][2], seq[i][3], seq[i][4]))
            d[4 * (i - 1) + 1:4 * (i - 1) + 4] =
                [p.r, p.g, p.b, p.a]
        end
        enc = Vector{UInt8}(encodeQOI(img))
        @test enc[15:29] == UInt8[0xfe, 10, 20, 30, 0xc1, 0x76, 0xa3, 0x88,
            0x09, 0xc2, 0xff, 10, 20, 30, 128]
        @test length(enc) == 14 + 15 + 8
        @test newImage(decodeQOI(enc)).data == d

        # Header bytes are masked per byte: widths/heights >= 256 previously
        # raised InexactError(UInt8, 256) in the be32 writer.
        wide = Vector{UInt8}(encodeQOI(newImage(256, 1)))
        @test wide[5:8] == UInt8[0x00, 0x00, 0x01, 0x00] # be32(256)
        @test newImage(decodeQOI(wide)).width == 256
    end

    @testset "PPM synthetic: 16-bit P3, header errors, dispatch" begin
        img = decodePPM(
            Vector{UInt8}(codeunits("P3\n1 1\n65535\n32768 32768 32768\n")))
        @test px(img, 1) == (128, 128, 128, 255)

        try
            decodePPM(Vector{UInt8}(
                "P6\n2 abc\n255\n1 2 3 4 5 6 7 8 9 10 11 12"))
        catch e
            @test e.msg == "Invalid PPM data"
        end
        try
            decodePPMDimensions(
                Vector{UInt8}("P6\n2 abc\n"))
        catch e
            @test e.msg == "Invalid PPM file header"
        end

        # io.jl dispatch for PPM.
        ppmBytes = vcat(codeunits("P6\n1 1\n255\n"), UInt8[10, 20, 30])
        @test px(decodeImage(ppmBytes), 1) == (10, 20, 30, 255)
        @test decodeImageDimensions(ppmBytes) == (1, 1)
    end

    @testset "io synthetic: base64 single-remainder branch" begin
        # A 3x1 image whose libpng payload is 151 bytes (151 % 3 == 1)
        # exercises the base64 "== " remainder branch.
        img = newImage(3, 1)
        for i in 1:3
            img.data[4 * (i - 1) + 1] = UInt8(255 - 2 * (i - 1))
            img.data[4 * (i - 1) + 4] = 0xff
        end
        @test length(encodePNG(img)) % 3 == 1
        enc = encodeBase64(img)
        @test enc[end - 1:end] == "=="
        @test decodeBase64(enc).data == img.data
    end

    @testset "PNG synthetic: invalid payload" begin
        try
            decodePNG(vcat(UInt8[0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a,
                0x0a], zeros(UInt8, 40)))
        catch e
            @test e.msg == "Invalid PNG buffer, unable to load"
        end
    end

    @testset "SVG synthetic: properties, gradients, url fills" begin
        svgProps(attrs) = (svg = "<svg viewBox=\"0 0 4 4\" xmlns=\"http://www.w3.org/2000/svg\"><rect x=\"0\" y=\"0\" width=\"4\" height=\"4\" $attrs/></svg>";
            parseSvg(svg).elements[1][2])

        # Every style key (upstream quirk: fillOpacity/strokeOpacity are
        # camelCase in style values).
        pr = svgProps("style=\"fill-rule: nonzero; fill: #FF0000; stroke: #00FF00; stroke-width: 2; stroke-linecap: butt; stroke-linejoin: miter; stroke-miterlimit: 4; stroke-dasharray: 2 4; display: none; opacity: 0.8; fillOpacity: 0.5; strokeOpacity: 0.7\"")
        @test pr.fill == "#FF0000"
        @test pr.fillRule === NonZero
        @test pr.display === false
        @test pr.opacity == Float32(0.8)
        @test pr.fillOpacity == Float32(0.5)
        @test pr.strokeOpacity == Float32(0.7)
        @test pr.strokeWidth == Float32(2)
        @test pr.stroke == rgbx(rgba(0, 255, 0, 255))
        @test pr.strokeLineCap === ButtCap
        @test pr.strokeLineJoin === MiterJoin
        @test pr.strokeMiterLimit == Float32(4)
        @test pr.strokeDashArray == [2f0, 4f0]

        # currentColor over an (inherited) transparent stroke -> opaque
        # black; square/round from style.
        pr = svgProps("stroke='currentColor'")
        @test pr.stroke == rgbx(rgba(0, 0, 0, 255))
        pr = svgProps("style=\"stroke: #00FF00; stroke-linecap: square; stroke-linejoin: round\"")
        @test pr.strokeLineCap === SquareCap
        @test pr.strokeLineJoin === RoundJoin

        # px-suffixed width; a width set on a transparent stroke makes the
        # stroke opaque black.
        pr = svgProps("stroke-width='10px'")
        @test pr.strokeWidth == Float32(10)
        @test pr.stroke == rgbx(rgba(0, 0, 0, 255))

        # inherit keeps the previous value; bogus values raise.
        @test svgProps("stroke-linecap='inherit'").strokeLineCap === ButtCap
        @test svgProps("stroke-linejoin='inherit'").strokeLineJoin === MiterJoin
        for (cap, join) in [("bogus", "miter"), ("butt", "bogus")]
            try
                svgProps("stroke-linecap='$cap' stroke-linejoin='$join'")
                @test false # must raise
            catch e
                @test e.msg == "Invalid stroke-linecap value $cap" ||
                    e.msg == "Invalid stroke-linejoin value $join"
            end
        end

        # Unsupported transform.
        try
            parseSvg("<svg viewBox=\"0 0 4 4\"><rect transform='skewX(10)' x='0' y='0' width='1' height='1'/></svg>")
        catch e
            @test e.msg == "Unsupported SVG transform: skewX(10)"
        end

        # matrix(a b c d e f) maps (x, y) -> (ax + cy + e, bx + dy + f)
        # (SVG spec); a shear needs b != c to catch a transposed tuple.
        pr = svgProps("transform='matrix(1,2,3,4,5,6)'")
        @test pr.transform.data ==
            (1f0, 2f0, 0f0, 3f0, 4f0, 0f0, 5f0, 6f0, 1f0)
        @test pr.transform * Vec2(Float32(1), Float32(0)) ==
            Vec2(Float32(6), Float32(8))

        # Upstream quirk: a child's stroke-dasharray appends onto the
        # inherited list (and must not mutate the parent's).
        svg = parseSvg("<svg viewBox=\"0 0 4 4\" xmlns=\"http://www.w3.org/2000/svg\"><g stroke-dasharray=\"1 2\"><rect x=\"0\" y=\"0\" width=\"4\" height=\"4\" stroke-dasharray=\"3 4\"/></g></svg>")
        @test svg.elements[1][2].strokeDashArray == [1f0, 2f0, 3f0, 4f0]
        svg = parseSvg("<svg viewBox=\"0 0 4 4\" xmlns=\"http://www.w3.org/2000/svg\"><g stroke-dasharray=\"1 2\"><rect x=\"0\" y=\"0\" width=\"4\" height=\"4\"/><rect x=\"0\" y=\"0\" width=\"4\" height=\"4\"/></g></svg>")
        @test svg.elements[1][2].strokeDashArray == [1f0, 2f0]
        @test svg.elements[2][2].strokeDashArray == [1f0, 2f0]

        # Space-only points fail; space-separated points parse.
        try
            parseSvg("<svg viewBox=\"0 0 4 4\"><polyline points=' '/></svg>")
            @test false
        catch e
            @test e.msg == "Invalid SVG data"
        end
        @test length(parseSvg(
            "<svg viewBox=\"0 0 4 4\"><polyline points='0 0 4 4 2 2'/></svg>"
        ).elements) == 1

        # ry-only rect (rx inherits ry), zero-size rect, skipped tags.
        @test length(parseSvg(
            "<svg viewBox=\"0 0 4 4\"><rect x='0' y='0' width='4' height='4' ry='1'/></svg>"
        ).elements) == 1
        @test length(parseSvg(
            "<svg viewBox=\"0 0 4 4\"><rect x='0' y='0' width='0' height='4'/></svg>"
        ).elements) == 0
        sv = parseSvg("<svg viewBox=\"0 0 4 4\"><radialGradient id='r'/><rect x='0' y='0' width='4' height='4' fill='#FF0000'/></svg>")
        @test length(sv.linearGradients) == 0
        @test length(sv.elements) == 1
        sv = parseSvg("<svg viewBox=\"0 0 4 4\"><defs><linearGradient id='d'/></defs><rect x='0' y='0' width='4' height='4' fill='#FF0000'/></svg>")
        @test length(sv.linearGradients) == 0
        @test length(sv.elements) == 1
        @test length(parseSvg(
            "<svg viewBox=\"0 0 4 4\"><filter id='f'/><rect x='0' y='0' width='4' height='4' fill='#FF0000'/></svg>"
        ).elements) == 1

        # Parse failures.
        for bad in ["<svg viewBox=\"0 0 4 4\"><path d='M x y'/></svg>",
            "<svg viewBox='0 0 abc 4'><rect x='0' y='0' width='1' height='1'/></svg>",
            "<svg viewBox='a 0 4 4'><rect x='0' y='0' width='1' height='1'/></svg>",
            "not xml at all <&&>"]
            try
                parseSvg(bad)
                @test false
            catch e
                @test e.msg == "Invalid SVG data"
            end
        end
        try
            parseSvg(SvgNode("g", [], []), 4, 4)
            @test false
        catch e
            @test e.msg == "Invalid SVG data"
        end

        # Gradient parse branches.
        for (units, tr) in [("objectBoundingBox", ""),
            ("userSpaceOnUse", "gradientTransform='rotate(1)'")]
            try
                parseSvg("<svg viewBox='0 0 4 4'><linearGradient id='g' gradientUnits='$units' $tr x1='0' y1='0' x2='4' y2='0'><stop offset='0' stop-color='#FF0000'/></linearGradient></svg>")
                @test false
            catch e
                @test e.msg == "Unsupported gradient units: objectBoundingBox" ||
                    e.msg == "Unsupported gradient transform: rotate(1)"
            end
        end
        try
            parseSvg("<svg viewBox='0 0 4 4'><linearGradient id='g' gradientUnits='userSpaceOnUse' x1='0' y1='0' x2='4' y2='0'><stop offset='0'/></linearGradient></svg>")
            @test false
        catch e
            @test e.msg == "Invalid SVG gradient, missing stop-color"
        end

        # url() fill rendering and errors.
        try
            newImage(parseSvg("<svg viewBox='0 0 4 4'><linearGradient id='g' gradientUnits='userSpaceOnUse' x1='0' y1='0' x2='4' y2='0'><stop offset='0' stop-color='#FF0000'/></linearGradient><rect x='0' y='0' width='4' height='4' fill='url(#g'/></svg>"))
            @test false
        catch e
            @test e.msg == "Malformed fill: url(#g"
        end
        try
            newImage(parseSvg("<svg viewBox='0 0 4 4'><linearGradient id='g' gradientUnits='userSpaceOnUse' x1='0' y1='0' x2='4' y2='0'><stop offset='0' stop-color='#FF0000'/></linearGradient><rect x='0' y='0' width='4' height='4' fill='url(#nope)'/></svg>"))
            @test false
        catch e
            @test e.msg == "Missing SVG resource nope"
        end
    end
end
