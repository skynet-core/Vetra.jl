# T008: file formats -- PNG, JPEG, BMP, QOI, GIF, SVG, PPM.
#
# Pixel expectations come from the pinned upstream fixtures under
# test/reference/ (oracle: tools/oracle/build.sh formats|svg, approved per
# test/README.md). All comparisons are exact except JPEG: D014 defers JPEG
# pixel decoding to JpegTurbo (libjpeg-turbo), a different lossy decoder than
# upstream's stb-derived one. The JPEG tests assert exact dimensions, an
# opaque premultiplied layout, and a max channel delta of 8 or less versus
# the upstream-stb fixture (recorded decision; measured on the four oracle
# fixtures: mandrill 5, progressive 5, exif_overrun 4, grayscale 1).

const UPSTREAM_FF =
    joinpath(@__DIR__, "..", ".reference", "upstream", "tests", "fileformats")

const FORMAT_FIXTURES = [
    # tag, upstream file, decoder
    ("bmp_knight_32_master_bmp", joinpath("bmp", "knight.32.master.bmp"), :bmp),
    ("bmp_knight_24_master_bmp", joinpath("bmp", "knight.24.master.bmp"), :bmp),
    ("bmp_rgb_24_master_bmp", joinpath("bmp", "rgb.24.master.bmp"), :bmp),
    ("bmp_test4x2_bmp", joinpath("bmp", "test4x2.bmp"), :bmp),
    ("bmp_test16x16_bmp", joinpath("bmp", "test16x16.bmp"), :bmp),
    ("qoi_testcard_qoi", joinpath("qoi", "testcard.qoi"), :qoi),
    ("qoi_testcard_rgba_qoi", joinpath("qoi", "testcard_rgba.qoi"), :qoi),
    ("gif_3x5_gif", joinpath("gif", "3x5.gif"), :gif),
    ("gif_audrey_gif", joinpath("gif", "audrey.gif"), :gif),
    ("gif_sunflower_gif", joinpath("gif", "sunflower.gif"), :gif),
    ("gif_newtons_cradle_gif", joinpath("gif", "newtons_cradle.gif"), :gif),
    ("jpeg_mandrill_jpg", joinpath("jpeg", "masters", "mandrill.jpg"), :jpeg),
    ("jpeg_grayscale_test_jpg",
        joinpath("jpeg", "masters", "grayscale_test.jpg"), :jpeg),
    ("jpeg_progressive_jpg", joinpath("jpeg", "masters", "progressive.jpg"), :jpeg),
    ("jpeg_exif_overrun_jpg",
        joinpath("jpeg", "masters", "exif_overrun.jpg"), :jpeg),
]

const SVG_FIXTURES = [
    # tag, upstream file, explicit (w, h) or nothing (viewBox default)
    ("svg_line01", "line01", nothing),
    ("svg_circle01", "circle01", nothing),
    ("svg_ellipse01", "ellipse01", nothing),
    ("svg_rect01", "rect01", nothing),
    ("svg_polygon01", "polygon01", nothing),
    ("svg_polyline01", "polyline01", nothing),
    ("svg_triangle01", "triangle01", nothing),
    ("svg_quad01", "quad01", nothing),
    ("svg_scale", "scale", nothing),
    ("svg_dashes", "dashes", nothing),
    ("svg_miterlimit", "miterlimit", nothing),
    ("svg_Ghostscript_Tiger", "Ghostscript_Tiger", nothing),
    ("svg_dragon2", "dragon2", nothing),
    ("svg_accessibility_outline", "accessibility-outline", (512, 512)),
]

"""Decode a format fixture with its direct codec (mirrors io.jl dispatch)."""
function _decodeFixture(kind::Symbol, bytes::Vector{UInt8})
    if kind === :bmp
        decodeBMP(bytes)
    elseif kind === :qoi
        newImage(decodeQOI(bytes))
    elseif kind === :gif
        newImage(decodeGIF(bytes))
    elseif kind === :jpeg
        decodeJPEG(bytes)
    else
        error("unknown fixture kind $kind")
    end
end

@testset "T008 file formats" begin

    @testset "BMP (5 pinned upstream fixtures, corrected masked boundary)" begin
        # The 32-bit mask fixtures are upstream oracles of the old
        # direct-store decode: the file bytes are straight (upstream's
        # encoder already applied the straight pass), but upstream's
        # masked decoder stored them directly as premul — invalid for
        # a = 0 / partial alpha. The pinned raw files stay untouched
        # (checksums above); the corrected expectation is derived from
        # them by the documented straight -> premul boundary, applied to
        # exactly the pixels with stored a < 255. Divergence counts per
        # fixture (hand-counted from the pinned raw, independent of the
        # decoder):
        BMP_SPLIT_COUNTS = Dict(
            "bmp_knight_32_master_bmp" => 36,
            "bmp_test4x2_bmp" => 4,
            "bmp_test16x16_bmp" => 256,
            "bmp_knight_24_master_bmp" => 0,
            "bmp_rgb_24_master_bmp" => 0)
        for (tag, rel, _) in
            [(t, r, k) for (t, r, k) in FORMAT_FIXTURES if k === :bmp]
            @testset "BMP $tag" begin
                ref, wh = VetraRef.read_raw(tag)
                @test VetraRef.verify_checksum(tag)
                expected = copy(ref)
                n = 0
                for i in 1:(wh[1] * wh[2])
                    a = ref[4 * (i - 1) + 4]
                    if a < 255
                        n += 1
                        for k in 0:2
                            c = Int(ref[4 * (i - 1) + 1 + k])
                            expected[4 * (i - 1) + 1 + k] =
                                UInt8((c * Int(a) + 127) ÷ 255)
                        end
                    end
                end
                @test n == BMP_SPLIT_COUNTS[tag]
                img = decodeBMP(read(joinpath(UPSTREAM_FF, rel)))
                @test (width(img), height(img)) == wh
                @test VetraRef.compare_pixels(img.data, expected, wh).count == 0
                @test decodeBMPDimensions(read(joinpath(UPSTREAM_FF, rel))) == wh
                # decodeDIB on the DIB portion (no 14-byte file header)
                data = read(joinpath(UPSTREAM_FF, rel))
                @test decodeDIB(data[15:end]).data == img.data
            end
        end

        @testset "BMP errors" begin
            # 14-byte file header + BITMAPINFOHEADER (w=1, h=1)
            function syntheticBmp(bits::Int, compression::Int)
                out = Vector{UInt8}()
                append!(out, [0x42, 0x4d, 0, 0, 0, 0, 0, 0, 0, 0])
                append!(out, [54, 0, 0, 0]) # pixel offset
                append!(out, [40, 0, 0, 0]) # biSize
                append!(out, [1, 0, 0, 0]) # width
                append!(out, [1, 0, 0, 0]) # height
                append!(out, [1, 0]) # planes
                append!(out, [UInt8(bits), 0])
                append!(out, [UInt8(compression & 0xff), (compression >> 8) & 0xff,
                    0, 0])
                append!(out, zeros(UInt8, 24)) # size/ppm/palette/important
                append!(out, UInt8[255, 0, 0, 0, 0, 0, 0, 0]) # one 32-bit pixel
                return out
            end
            @test_throws(ArgumentError, decodeBMP(UInt8[0x42, 0x4d, 0, 0]))
            @test_throws(ArgumentError, decodeBMP(UInt8[0x58, 0x58, 0, 0, 0, 0]))
            @test_throws(ArgumentError, decodeBMP(syntheticBmp(16, 0)))
            @test_throws(ArgumentError, decodeBMP(syntheticBmp(24, 1)))
            try
                decodeBMP(UInt8[0x58, 0x58, 0, 0, 0, 0])
            catch e
                @test e.msg == "Invalid BMP buffer, unable to load"
            end
            try
                decodeBMP(syntheticBmp(16, 0))
            catch e
                @test e.msg == "Unsupported BMP bit count"
            end
            try
                decodeBMP(syntheticBmp(24, 1))
            catch e
                @test e.msg == "Unsupported BMP compression format"
            end
        end
    end

    @testset "QOI (2 pinned fixtures, exact pixels)" begin
        for (tag, rel, _) in
            [(t, r, k) for (t, r, k) in FORMAT_FIXTURES if k === :qoi]
            @testset "QOI $tag" begin
                ref, wh = VetraRef.read_raw(tag)
                @test VetraRef.verify_checksum(tag)
                qoi = decodeQOI(read(joinpath(UPSTREAM_FF, rel)))
                @test (qoi.width, qoi.height) == wh
                @test qoi.channels == 4
                @test qoi.colorspace === sRBG
                @test newImage(qoi).data == ref
                @test decodeQOIDimensions(read(joinpath(UPSTREAM_FF, rel))) == wh
            end
        end

        @testset "QOI arithmetic (upstream srgbToLinear / qoiHash)" begin
            @test srgbToLinear(UInt8(0)) == UInt8(0)
            @test srgbToLinear(UInt8(255)) == UInt8(255)
            # c = 10/255 <= 0.04045: (10/255/12.92 * 255) rounds to 1
            @test srgbToLinear(UInt8(10)) == UInt8(1)
            # monotone over all 256 inputs
            prev = UInt8(0)
            for v in 1:255
                cur = srgbToLinear(UInt8(v))
                @test Int(cur) >= Int(prev)
                prev = cur
            end
            # hash(0,0,0,255) = (0 + 0 + 0 + 255*11) mod 64 = 2805 mod 64
            @test qoiHash(UInt8(0), UInt8(0), UInt8(0), UInt8(255)) == 53
        end

        @testset "QOI errors" begin
            hdr(w, h, channels, colorspace) =
                Vector{UInt8}(
                    [
                        codeunits("qoif")...,
                        0, 0, 0, UInt8(w), 0, 0, 0, UInt8(h),
                        UInt8(channels), UInt8(colorspace)
                    ])
            @test_throws(ArgumentError, decodeQOI(hdr(1, 1, 4, 0)[1:13]))
            @test_throws(ArgumentError, decodeQOI(hdr(1, 1, 2, 0)))
            @test_throws(ArgumentError, decodeQOI(hdr(1, 1, 4, 2)))
            # header only, then one stream byte: the bitstream ends before
            # the first pixel ("Underrun of QOI decoder", checked before
            # reading the byte)
            try
                decodeQOI(append!(copy(hdr(1, 1, 4, 0)), UInt8(0)))
            catch e
                @test e.msg == "Underrun of QOI decoder"
            end
            # bad padding: a valid encode, last 0x01 -> 0x02
            img = newImage(1, 1)
            img.data[1:4] = [UInt8(200), 100, 50, 0xff]
            bytes = Vector{UInt8}(encodeQOI(img))
            bytes[end] = 0x02
            try
                decodeQOI(bytes)
            catch e
                @test e.msg == "Invalid QOI padding"
            end
            @test_throws(ArgumentError, decodeQOIDimensions(hdr(1, 1, 4, 0)[1:8]))
        end
    end

    @testset "GIF (4 pinned fixtures, exact first frame)" begin
        for (tag, rel, _) in
            [(t, r, k) for (t, r, k) in FORMAT_FIXTURES if k === :gif]
            @testset "GIF $tag" begin
                ref, wh = VetraRef.read_raw(tag)
                @test VetraRef.verify_checksum(tag)
                bytes = read(joinpath(UPSTREAM_FF, rel))
                gif = decodeGIF(bytes)
                @test length(gif.frames) > 0
                @test length(gif.intervals) == length(gif.frames)
                for frame in gif.frames
                    @test (width(frame), height(frame)) == wh
                end
                @test gif.frames[1].data == ref
                @test newImage(gif).data == ref
                @test decodeGIFDimensions(bytes) == wh
            end
        end

        @testset "GIF errors" begin
            @test_throws(
                ArgumentError,
                decodeGIF(UInt8[0x47, 0x49, 0x46, 0x38, 0x39, 0x61]))
            @test_throws(
                ArgumentError,
                decodeGIF(UInt8[
                    0x58, 0x49, 0x46, 0x38, 0x39, 0x61,
                    1, 0, 1, 0, 0, 0, 0
                ]))
            # valid 1x1 header, no blocks: underrun in the block loop
            try
                decodeGIF(UInt8[
                    0x47, 0x49, 0x46, 0x38, 0x39, 0x61,
                    1, 0, 1, 0, 0, 0, 0
                ])
            catch e
                @test e.msg == "Invalid GIF buffer, unable to load"
            end
        end
    end

    @testset "PNG (upstream-encoded heart.png, exact pixels)" begin
        ref, wh = VetraRef.read_raw("heart")
        @test VetraRef.verify_checksum("heart")
        bytes = read(joinpath(VetraRef.REF, "heart.png"))
        img = decodePNG(bytes)
        @test (width(img), height(img)) == wh
        @test img.data == ref
        @test decodePNGDimensions(bytes) == wh

        @testset "PNG errors" begin
            @test_throws(ArgumentError, decodePNGDimensions(UInt8[0x89, 0x50]))
            @test_throws(ArgumentError, decodePNGDimensions(fill(UInt8(0), 60)))
            try
                decodePNG(fill(UInt8(0), 64))
            catch e
                @test e.msg == "Invalid PNG buffer, unable to load"
            end
        end
    end

    @testset "PPM (hand-derived decodes + round trips)" begin
        @testset "P6 8-bit" begin
            # 2x2; stored pixels are premultiplied, but with a=255 the rgbx
            # pass is the identity, so the decoded bytes are the samples.
            body = "P6\n2 2\n255\n"
            pixels = [
                10, 20, 30, 40, 50, 60, 70, 80, 90, 250, 251, 252
            ]
            data = Vector{UInt8}(
                [
                    codeunits(body)...,
                    UInt8.(pixels)...
                ])
            img = decodePPM(data)
            @test (width(img), height(img)) == (2, 2)
            @test img.data[1:4] == [10, 20, 30, 0xff]
            @test img.data[5:8] == [40, 50, 60, 0xff]
            @test img.data[9:12] == [70, 80, 90, 0xff]
            @test img.data[13:16] == [250, 251, 252, 0xff]
            @test decodePPMDimensions(data) == (2, 2)
        end

        @testset "P3 8-bit (comments, arbitrary whitespace)" begin
            body = "P3\n# a comment\n2 1\n255\n# another\n10 20 30\n40 50 60\n"
            img = decodePPM(Vector{UInt8}(codeunits(body)))
            @test (width(img), height(img)) == (2, 1)
            @test img.data[1:4] == [10, 20, 30, 0xff]
            @test img.data[5:8] == [40, 50, 60, 0xff]
        end

        @testset "P6 16-bit (big-endian samples, maxVal 65535)" begin
            # Upstream: channel = trunc(f32(v * (255/65535 f32) + 0.5 f32)).
            # Hand-computed: 16384 -> 63.751 + .5 -> 64; 32768 -> 127.502 +
            # .5 -> 128; 49152 -> 191.253 + .5 -> 191; 65535 -> 255.
            body = "P6\n2 1\n65535\n"
            pixels = [
                0x40, 0x00, 0x40, 0x00, 0x40, 0x00, # 16384 x3
                0x80, 0x00, 0x80, 0x00, 0x80, 0x00 # 32768 x3
            ]
            data = Vector{UInt8}([
                codeunits(body)...,
                UInt8.(pixels)...
            ])
            img = decodePPM(data)
            @test img.data[1:4] == [64, 64, 64, 0xff]
            @test img.data[5:8] == [128, 128, 128, 0xff]
        end

        @testset "PPM errors" begin
            @test_throws(ArgumentError, decodePPM(Vector{UInt8}("P6\n2")))
            @test_throws(ArgumentError, decodePPM(Vector{UInt8}("P2\n2 1\n255\n1 2 3\n")))
            @test_throws(ArgumentError, decodePPM(Vector{UInt8}("P6\n2 1\n0\n1 2 3\n1 2 3\n")))
            # pixel count mismatch: header says 2x1, only one triple present
            @test_throws(ArgumentError, decodePPM(Vector{UInt8}("P6\n2 1\n255\n1 2 3")))
            # P3 non-numeric sample
            @test_throws(ArgumentError, decodePPM(Vector{UInt8}("P3\n1 1\n255\n1 2 x\n")))
            # P3 16-bit sample above maxVal
            @test_throws(ArgumentError, decodePPM(Vector{UInt8}("P3\n1 1\n65535\n65536 0 0\n")))
            # P6 16-bit count mismatch (1 pixel = 6 bytes, header says 2)
            @test_throws(ArgumentError,
                decodePPM(vcat(
                    codeunits("P6\n2 1\n65535\n"),
                    UInt8[0, 1, 0, 1, 0, 1])))
        end

        @testset "PPM round trip (opaque image; alpha is dropped)" begin
            img = newImage(2, 2)
            d = img.data
            d[1:4] = [UInt8(255), 0, 0, 0xff]
            d[5:8] = [0, 255, 0, 0xff]
            d[9:12] = [0, 0, 255, 0xff]
            d[13:16] = [10, 20, 30, 0xff]
            @test decodePPM(Vector{UInt8}(encodePPM(img))).data == d
        end
    end

    @testset "JPEG (lossy: dimensions exact, pixels within recorded bound)" begin
        for (tag, rel, _) in
            [(t, r, k) for (t, r, k) in FORMAT_FIXTURES if k === :jpeg]
            @testset "JPEG $tag" begin
                ref, wh = VetraRef.read_raw(tag)
                @test VetraRef.verify_checksum(tag)
                bytes = read(joinpath(UPSTREAM_FF, rel))
                @test decodeJPEGDimensions(bytes) == wh
                img = decodeJPEG(bytes)
                @test (width(img), height(img)) == wh
                # opaque output: alpha 255 throughout
                a = img.data
                for k in 4:4:length(a)
                    @test a[k] == 0xff
                end
                # not a blank decode: some pixel must differ from black
                @test any(v != 0x00 for v in a[1:4:end])
                # libjpeg-turbo vs upstream stb decoder: max channel delta
                # must stay within the recorded bound of 8.
                maxd = 0
                for k in 1:length(ref)
                    dd = abs(Int(img.data[k]) - Int(ref[k]))
                    if dd > maxd
                        maxd = dd
                    end
                end
                @test maxd <= 8
            end
        end

        @testset "JPEG errors" begin
            # SOF1 (extended sequential) is unsupported, as upstream
            sof1 = UInt8[
                0xff, 0xd8, 0xff, 0xc1, 0x00, 0x0b, 0x08,
                0x00, 0x01, 0x00, 0x01, 0x01, 0x01
            ]
            try
                decodeJPEGDimensions(sof1)
            catch e
                @test e.msg ==
                    "Invalid JPEG, unsupported extended sequential DCT format"
            end
            # DLT marker: "invalid chunk C3"
            try
                decodeJPEGDimensions(UInt8[0xff, 0xd8, 0xff, 0xc3, 0x00, 0x02])
            catch e
                @test e.msg == "Invalid JPEG, invalid chunk C3"
            end
            # truncated after SOI: "missing marker"
            try
                decodeJPEGDimensions(UInt8[0xff, 0xd8])
            catch e
                @test e.msg == "Invalid JPEG, missing marker"
            end
            # pixel decode of a non-JPEG payload
            try
                decodeJPEG(vcat(UInt8[0xff, 0xd8], zeros(UInt8, 32)))
            catch e
                @test e.msg == "Invalid JPEG, unable to load"
            end
        end
    end

    @testset "SVG (14 pinned fixtures, exact pixels)" begin
        for (tag, name, wh) in SVG_FIXTURES
            @testset "SVG $tag" begin
                ref, refwh = VetraRef.read_raw(tag)
                @test VetraRef.verify_checksum(tag)
                bytes = read(joinpath(UPSTREAM_FF, "svg", name * ".svg"))
                if wh === nothing
                    img = newImage(parseSvg(String(bytes)))
                else
                    img = newImage(parseSvg(String(bytes), wh[1], wh[2]))
                end
                @test (width(img), height(img)) == refwh
                @test VetraRef.compare_pixels(img.data, ref, refwh).count == 0
            end
        end

        @testset "SVG errors" begin
            @test_throws(ArgumentError, parseSvg("<svg></svg"))
            try
                parseSvg("<svg></svg")
            catch e
                @test e.msg == "Invalid SVG data"
            end
            @test_throws(ArgumentError,
                parseSvg("<svg><rect fill-rule=\"bogus\"/></svg>"))
            @test_throws(ArgumentError,
                parseSvg("<svg><linearGradient gradientUnits=\"objectBoundingBox\"/></svg>"))
        end
    end

    @testset "dispatch: decodeImage / decodeImageDimensions" begin
        for (tag, rel, kind) in FORMAT_FIXTURES
            @testset "dispatch $tag" begin
                ref, wh = VetraRef.read_raw(tag)
                bytes = read(joinpath(UPSTREAM_FF, rel))
                img = decodeImage(bytes)
                @test (width(img), height(img)) == wh
                if kind === :jpeg
                    # lossy: check the recorded bound, not exact pixels
                    maxd = 0
                    for k in 1:length(ref)
                        dd = abs(Int(img.data[k]) - Int(ref[k]))
                        if dd > maxd
                            maxd = dd
                        end
                    end
                    @test maxd <= 8
                else
                    expected = copy(ref)
                    if kind === :bmp
                        # The 32-bit mask fixtures are upstream oracles
                        # of the old direct-store semantics; apply the
                        # documented straight -> premul boundary to the
                        # pinned raw before comparing (no-op on the
                        # 24-bit fixtures and on rgb-zero alpha pixels)
                        # — same correction as the BMP fixture testset
                        # above.
                        for i in 1:(wh[1] * wh[2])
                            a = ref[4 * (i - 1) + 4]
                            if a < 255
                                for k in 0:2
                                    c = Int(ref[4 * (i - 1) + 1 + k])
                                    expected[4 * (i - 1) + 1 + k] =
                                        UInt8((c * Int(a) + 127) ÷ 255)
                                end
                            end
                        end
                    end
                    @test img.data == expected
                end
                @test decodeImageDimensions(bytes) == wh
            end
        end

        @testset "PNG via dispatch (heart.png)" begin
            ref, wh = VetraRef.read_raw("heart")
            bytes = read(joinpath(VetraRef.REF, "heart.png"))
            @test decodeImage(bytes).data == ref
            @test decodeImageDimensions(bytes) == wh
        end

        @testset "SVG via dispatch (viewBox default)" begin
            ref, wh = VetraRef.read_raw("svg_circle01")
            bytes = read(joinpath(UPSTREAM_FF, "svg", "circle01.svg"))
            @test decodeImage(bytes).data == ref
        end

        @testset "unrecognized / unsupported" begin
            junk = UInt8[0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13]
            try
                decodeImage(junk)
            catch e
                @test e.msg == "Unsupported image file format"
            end
            @test_throws(ArgumentError, decodeImageDimensions(junk))
            # upstream quirk: decodeImageDimensions has no SVG case
            svgbytes = read(joinpath(UPSTREAM_FF, "svg", "circle01.svg"))
            try
                decodeImageDimensions(svgbytes)
            catch e
                @test e.msg == "Unsupported image file format"
            end
        end

        @testset "readImage / readImageDimensions (file form)" begin
            dir = mktempdir()
            name = joinpath(dir, "heart.png")
            write(name, read(joinpath(VetraRef.REF, "heart.png")))
            @test readImage(name).data == VetraRef.read_raw("heart")[1]
            @test readImageDimensions(name) == (200, 200)
            rm(dir; recursive = true)
            try
                readImage(joinpath(dir, "missing.png"))
            catch e
                @test e isa ArgumentError
            end
        end
    end

    @testset "encode: encodeImage / writeFile" begin
        img = newImage(2, 2)
        d = img.data
        d[1:4] = [UInt8(255), 0, 0, 0xff]
        d[5:8] = [0, 255, 0, 0xff]
        d[9:12] = [0, 0, 255, 0xff]
        d[13:16] = [10, 20, 30, 0xff]

        @testset "encodeImage dispatch" begin
            @test encodeImage(img, PngFormat) == encodePNG(img)
            @test encodeImage(img, BmpFormat) == encodeBMP(img)
            @test encodeImage(img, QoiFormat) == encodeQOI(img)
            @test encodeImage(img, PpmFormat) == encodePPM(img)
            @test encodeImage(img, JpegFormat) == encodeJPEG(img) # T031
            @test encodeImage(img, WebpFormat) == encodeWebP(img) # T032
            for fmt in (GifFormat,)
                try
                    encodeImage(img, fmt)
                catch e
                    @test e.msg == "Unsupported file format"
                end
            end
        end

        @testset "writeFile (all seven writable formats)" begin
            dir = mktempdir()
            for (ext, encoder) in [(".png", encodePNG(img)),
                                  (".bmp", encodeBMP(img)),
                                  (".qoi", encodeQOI(img)),
                                  (".ppm", encodePPM(img)),
                                  (".jpg", encodeJPEG(img)),
                                  (".jpeg", encodeJPEG(img)),
                                  (".webp", encodeWebP(img))]
                name = joinpath(dir, "t" * ext)
                writeFile(img, name)
                @test read(name) == Vector{UInt8}(encoder)
            end
            # unknown extensions still raise (existing behavior);
            # GIF has no write extension at all (D014) — the
            # GifFormat raise is covered in the encodeImage dispatch
            # testset above.
            try
                writeFile(img, joinpath(dir, "t.xyz"))
            catch e
                @test e.msg == "Unsupported file extension"
            end
            rm(dir; recursive = true)
        end

        @testset "PNG round trip" begin
            # heart (upstream-encoded reference) and a semi-transparent
            # synthetic image: premul -> straight -> premul is lossless for
            # the chosen values (a=128, c=100 -> straight 100 -> back 50).
            heart = decodePNG(read(joinpath(VetraRef.REF, "heart.png")))
            @test decodePNG(encodePNG(heart)).data == heart.data
            st = newImage(2, 2)
            s = st.data
            s[1:4] = [50, 50, 50, 0x80] # premul of (100,100,100,128)
            s[5:8] = [0, 0, 0, 0x01]
            s[9:12] = [0, 0, 0, 0]
            s[13:16] = [255, 255, 255, 0xff]
            @test decodePNG(encodePNG(st)).data == s
        end

        @testset "BMP round trip (valid V5 header, straight boundary, exact)" begin
            # E001 fix + review: upstream's encodeBmp wrote a 136-byte DIB
            # under a biSize=124 claim, so any biSize-honoring reader
            # (including decodeBMP) read pixels 12 bytes early and
            # upstream's own encode->decode assertions stayed disabled
            # (test_bmp.nim). Vetra writes a real 124-byte BITMAPV5HEADER
            # (file offset 138). The 32-bit file boundary is straight RGBA
            # (BMP/WIC 32bppBGRA, Pillow): encode applies toStraightAlpha,
            # decode's masked path applies rgbx(rgba(...)), and the pair
            # round-trips exactly on valid premultiplied storage (c <= a),
            # including a=0 cells.
            bmp = encodeBMP(img)
            b = Vector{UInt8}(bmp)
            le16(i) = Int(b[i]) | (Int(b[i + 1]) << 8)
            le32(i) = le16(i) | (Int(b[i + 2]) << 16) | (Int(b[i + 3]) << 24)
            @test le32(11) == 138 # file offset to pixel array
            @test le32(15) == 124 # biSize equals the actual header size
            @test le16(29) == 32 # BI_BITFIELDS 32 bpp
            @test length(b) == 14 + 124 + 4 * width(img) * height(img)
            @test decodeBMP(Vector{UInt8}(bmp)).data == d
            @test decodeDIB(Vector{UInt8}(bmp)[15:end]).data == d
            # external boundary: stored premul (128,0,0,128) is straight
            # (255,0,0,128) in the file, byte order R,G,B,A per the masks
            # (2x1, single bottom-up row: file pixels are image (1,1) then
            # (2,1); the pixel array starts at file byte 139)
            st = newImage(2, 1)
            s = st.data
            s[1:4] = [128, 0, 0, 128]
            s[5:8] = [0, 0, 0, 0]
            fb = Vector{UInt8}(encodeBMP(st))
            @test fb[139:142] == [UInt8(255), UInt8(0), UInt8(0), UInt8(128)]
            @test fb[143:146] == [UInt8(0), UInt8(0), UInt8(0), UInt8(0)]
            @test decodeBMP(fb).data == s
            # valid premultiplied cells (incl. an a=0 cell) survive the
            # round trip byte-exactly (toPremul(toStraight(x)) == x)
            s2 = zeros(UInt8, 16)
            s2[1:4] = [50, 50, 50, 0x80]
            s2[5:8] = [0, 0, 0, 0x80]
            s2[9:12] = [127, 64, 32, 0xbf]
            s2[13:16] = [0, 0, 0, 0x00]
            @test decodeBMP(
                Vector{UInt8}(encodeBMP(Image(2, 2, copy(s2))))).data == s2
        end

        @testset "BMP handcrafted V5 decode (independent of the encoder)" begin
            # 1x3 bottom-up file, straight RGBA bytes (R,G,B,A per the
            # masks): file row 0 = image (1,3), row 1 = (1,2), row 2 = (1,1).
            out = Vector{UInt8}()
            addle32(v) = append!(out, [UInt8(v & 0xff),
                UInt8((v >> 8) & 0xff), UInt8((v >> 16) & 0xff),
                UInt8((v >> 24) & 0xff)])
            addle16(v) = append!(out, [UInt8(v & 0xff),
                UInt8((v >> 8) & 0xff)])
            append!(out, [0x42, 0x4d])
            addle32(14 + 124 + 12) # file size (3 pixels, no row padding)
            addle32(0) # reserved
            addle32(138) # pixel offset
            addle32(124) # biSize
            addle32(1) # width
            addle32(3) # height
            addle16(1) # planes
            addle16(32) # bits
            addle32(3) # BI_BITFIELDS
            addle32(12) # raw bitmap size
            addle32(2835) # resolution x
            addle32(2835) # resolution y
            addle32(0) # palette size
            addle32(0) # important colors
            addle32(0x000000ff) # red mask
            addle32(0x0000ff00) # green mask
            addle32(0x00ff0000) # blue mask
            addle32(0xff000000) # alpha mask
            addle32(0x73524742) # LCS_sRGB
            append!(out, zeros(UInt8, 64)) # V4/V5 fields
            append!(out, [77, 88, 99, 255]) # (1,3): opaque
            append!(out, [255, 255, 255, 0]) # (1,2): zero alpha, white straight
            append!(out, [100, 150, 200, 128]) # (1,1): partial alpha
            @test length(out) == 14 + 124 + 12
            im = decodeBMP(out)
            @test (width(im), height(im)) == (1, 3)
            # straight -> premul by hand ((c * a + 127) div 255):
            # (100,150,200,128) -> (50,75,100,128); (255,255,255,0) -> (0,0,0,0);
            # (77,88,99,255) unchanged.
            @test im.data[1:4] == [UInt8(50), UInt8(75), UInt8(100), UInt8(128)]
            @test im.data[5:8] == [UInt8(0), UInt8(0), UInt8(0), UInt8(0)]
            @test im.data[9:12] == [UInt8(77), UInt8(88), UInt8(99), UInt8(255)]
        end

        @testset "BMP external reader interop (Pillow, guarded like poppler)" begin
            # First interpreter that imports PIL, probed quietly (a
            # missing PIL is not a traceback to surface): PATH
            # python3, then the distro /usr/bin/python3.
            pilpy = nothing
            for py in ("python3", "/usr/bin/python3")
                w = Sys.which(py)
                isnothing(w) && continue
                if success(pipeline(`$w -c "import PIL"`,
                        stdout = devnull, stderr = devnull))
                    pilpy = w
                    break
                end
            end
            if pilpy !== nothing
                mktempdir() do dir
                    st = newImage(2, 1)
                    s = st.data
                    s[1:4] = [128, 0, 0, 128] # stored premul of straight (255,0,0,128)
                    s[5:8] = [0, 0, 0, 0]
                    f = joinpath(dir, "boundary.bmp")
                    open(f, "w") do io
                        write(io, encodeBMP(st))
                    end
                    # The file path is a separate argv (sys.argv[1]),
                    # never interpolated into the Python source
                    # (backslashes / apostrophes in paths).
                    out = read(`$pilpy -c "from PIL import Image; import sys; im = Image.open(sys.argv[1]); print(im.mode); print([im.getpixel((x, y)) for y in range(im.height) for x in range(im.width)])" $(f)`, String)
                    # Pillow decodes 32-bit BMP alpha as straight RGBA:
                    @test occursin("RGBA", out)
                    @test occursin("(255, 0, 0, 128)", out)
                    @test occursin("(0, 0, 0, 0)", out)
                end
            else
                println("no Python with Pillow found; BMP external-reader " *
                    "interop not checked")
            end
        end

        @testset "QOI round trip (opaque image)" begin
            @test newImage(decodeQOI(Vector{UInt8}(encodeQOI(img)))).data == d
        end

        @testset "PPM round trip (opaque image)" begin
            @test decodePPM(Vector{UInt8}(encodePPM(img))).data == d
        end
    end

    @testset "base64 (upstream imagebase64.nim)" begin
        heart = decodePNG(read(joinpath(VetraRef.REF, "heart.png")))
        @testset "encode/decode round trip" begin
            enc = encodeBase64(heart)
            @test decodeBase64(enc).data == heart.data
            @test decodeBase64(
                "data:image/png;base64," * enc).data == heart.data
            @test decodeBase64("data:," * enc).data == heart.data
        end

        @testset "strict errors" begin
            for bad in ("abc", "abcde", "ab!d", "abcd====")
                try
                    decodeBase64(bad)
                catch e
                    @test e.msg == "Invalid base64 data"
                end
            end
            try
                decodeBase64("data:image/png;base64 no comma")
            catch e
                @test e.msg == "Invalid data URL"
            end
            # empty payload is valid base64; dispatch then rejects the bytes
            try
                decodeBase64("data:,")
            catch e
                @test e.msg == "Unsupported image file format"
            end
        end
    end

end # T008 file formats
