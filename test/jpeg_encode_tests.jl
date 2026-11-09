# T031: JPEG encoding (D032, docs/JPEG_WEBP_CODECS.md §2,
# src/formats/jpeg.jl).
#
# Method, per the T030 contract §2.6: JPEG is lossy, so expected output is
# never byte-pinned. Structural checks are a hand-derived marker walk
# (SOI, JFIF APP0 with the contract's 72×72 dpi density, SOF0 dimensions,
# EOI). Pixel/quality checks are an independent-reader interop (PyMuPDF /
# mupdf — the condition is checked like T026's gs/poppler verifiers) plus
# a PSNR floor on a fixed gradient. The premultiplied→straight composite is
# tested exactly at the helper level and at tolerance level through the
# full encode/decode pipeline.

@testset "T031 JPEG encoding" begin
    # The fixed test image: a 64×48 opaque gradient, asymmetric so that a
    # transposed/rotated file fails the orientation checks (r varies with
    # x, g varies with y, b is constant).
    TW = 64
    TH = 48
    function testImage()
        img = newImage(TW, TH)
        for y in 1:TH
            for x in 1:TW
                Vetra.set_pixel(img, x, y, rgbx(
                    Int(round(255 * (x - 1) / (TW - 1))),
                    Int(round(255 * (y - 1) / (TH - 1))),
                    128, 255))
            end
        end
        return img
    end

    function throws_arg(f, msg::String)
        try
            f()
            return false
        catch e
            return e isa ArgumentError && e.msg == msg
        end
    end

    """PSNR (dB) of `a` vs `b` in 8-bit space (both opaque Images)."""
    function psnr8(a, b)
        d = 0.0
        for y in 1:height(a), x in 1:width(a)
            ca = getColor(a, x, y)
            cb = getColor(b, x, y)
            d += (Int(ca.r) - Int(cb.r))^2 +
                (Int(ca.g) - Int(cb.g))^2 + (Int(ca.b) - Int(cb.b))^2
        end
        mse = d / (width(a) * height(a) * 3)
        return 10 * log10(255.0^2 / mse)
    end

    """Max channel delta between a decoded Image and mupdf RGB samples
    (row-major bytes)."""
    function maxdeltaVsRaw(img, raw)
        mx = 0
        for y in 1:height(img), x in 1:width(img)
            i = ((y - 1) * width(img) + (x - 1)) * 3
            c = getColor(img, x, y)
            mx = max(mx, abs(Int(raw[i + 1]) - Int(c.r)),
                abs(Int(raw[i + 2]) - Int(c.g)),
                abs(Int(raw[i + 3]) - Int(c.b)))
        end
        return mx
    end

    @testset "conversion helper (exact integer, contract §2.2)" begin
        # p=100, a=200, b=50 → (25500 + 2750 + 127) div 255 = 111.
        @test Vetra._jpegComposite(100, 50, 200) == 111
        # opaque passthrough; transparent → background.
        @test Vetra._jpegComposite(200, 0, 255) == 200
        @test Vetra._jpegComposite(200, 99, 255) == 200
        @test Vetra._jpegComposite(0, 255, 0) == 255
        @test Vetra._jpegComposite(77, 255, 0) == 255
        # half alpha over white/black (255*127 + 127) div 255 = 127.
        @test Vetra._jpegComposite(0, 255, 128) == 127
        @test Vetra._jpegComposite(128, 0, 128) == 128
        # clamp: an impossible premul value stays in range.
        @test Vetra._jpegComposite(255, 255, 1) == 255
        @test Vetra._jpegComposite(0, 0, 1) == 0
    end

    @testset "structure (hand-derived marker walk)" begin
        img = testImage()
        buf = encodeJPEG(img; quality = 92)
        @test Tuple(buf[1:2]) == (0xff, 0xd8) # SOI
        @test Tuple(buf[3:4]) == (0xff, 0xe0) # JFIF APP0
        @test buf[5] == 0x00 && buf[6] == 0x10 # APP0 length 16
        @test String(buf[7:10]) == "JFIF"
        @test buf[11] == 0x00 # JFIF null terminator
        @test Int(buf[14]) == 1 # density units: 1 = pixels per inch
        @test Int(buf[15]) * 256 + Int(buf[16]) == 72 # X density
        @test Int(buf[17]) * 256 + Int(buf[18]) == 72 # Y density
        @test decodeJPEGDimensions(buf) == (64, 48) # SOF0 dimensions
        # (via the existing native marker walk, orientation-aware)
        @test Tuple(buf[end - 1:end]) == (0xff, 0xd9) # EOI
        # the default background/quality produce the same bytes (the
        # encoder is deterministic: no timestamps in the file).
        @test encodeJPEG(img) == buf
    end

    @testset "validation and errors (contract §2.1/§2.4/§2.5)" begin
        img = testImage()
        @test throws_arg(() -> encodeJPEG(img; quality = 0),
            "JPEG quality must be 1..100")
        @test throws_arg(() -> encodeJPEG(img; quality = 101),
            "JPEG quality must be 1..100")
        @test throws_arg(() -> encodeJPEG(img; quality = -5),
            "JPEG quality must be 1..100")
        # the boundaries are accepted.
        @test length(encodeJPEG(img; quality = 1)) > 0
        @test length(encodeJPEG(img; quality = 100)) > 0
        # a non-Int quality is a type error, not a silent conversion.
        @test_throws TypeError encodeJPEG(img; quality = 92.0)
        # dimension bound: 65501 must be rejected by the API before the
        # provider runs (at 65501 the provider segfaults — T030 probe).
        @test throws_arg(() -> encodeJPEG(newImage(65501, 4)),
            "JPEG dimension exceeds 65500")
        @test throws_arg(() -> encodeJPEG(newImage(4, 65501)),
            "JPEG dimension exceeds 65500")
        # the boundary dimension itself encodes.
        @test length(encodeJPEG(newImage(65500, 4))) > 0
        # an out-of-range background byte is rejected by the color
        # constructor (existing `_byte` validation).
        @test_throws ArgumentError rgb(300, 0, 0)
    end

    @testset "round-trip: dimensions, orientation, quality" begin
        img = testImage()
        back = decodeJPEG(encodeJPEG(img; quality = 92))
        @test (width(back), height(back)) == (64, 48)
        @test all(Int(getColor(back, x, y).a) == 255
            for x in 1:64 for y in 1:48) # JPEG carries no alpha
        # orientation (asymmetric gradient): the four corners pin the
        # pixel grid — any transpose or flip breaks one of them.
        tl = getColor(back, 2, 2)
        tr = getColor(back, 63, 2)
        br = getColor(back, 63, 47)
        bl = getColor(back, 2, 47)
        @test Int(tl.r) < 40 && Int(tl.g) < 40 # top-left: both dark
        @test Int(tr.r) > 200 && Int(tr.g) < 40 # top-right
        @test Int(br.r) > 200 && Int(br.g) > 180 # bottom-right
        @test Int(bl.r) < 40 && Int(bl.g) > 180 # bottom-left
        # the quality policy: PSNR floor at q92 (measured 48.78 in the
        # T030 probe), and the knob bites (q10 decodes worse).
        @test psnr8(back, img) >= 40
        @test psnr8(decodeJPEG(encodeJPEG(img; quality = 10)), img) <
            psnr8(back, img)
    end

    @testset "transparency: composited over the background, never dropped" begin
        # fully transparent → the solid background (a flat field is
        # DC-only, so the decode is near-exact).
        t = newImage(16, 16)
        back = decodeJPEG(encodeJPEG(t; background = rgb(10, 20, 30)))
        c = getColor(back, 8, 8)
        @test abs(Int(c.r) - 10) <= 3
        @test abs(Int(c.g) - 20) <= 3
        @test abs(Int(c.b) - 30) <= 3
        # default background is white.
        cw = getColor(decodeJPEG(encodeJPEG(t)), 8, 8)
        @test Int(cw.r) >= 250 && Int(cw.g) >= 250 && Int(cw.b) >= 250
        # half-alpha straight red (premul 128/128) over white is 255,
        # over black is 128 — the contract's §2.2 examples.
        function halfAlpha(bg)
            h = newImage(16, 16)
            for y in 1:16, x in 1:16
                Vetra.set_pixel(h, x, y, rgbx(128, 0, 0, 128))
            end
            return Int(getColor(decodeJPEG(encodeJPEG(h; background = bg)),
                8, 8).r)
        end
        @test halfAlpha(rgb(255, 255, 255)) == 255
        @test halfAlpha(rgb(0, 0, 0)) == 128
    end

    @testset "dispatch: encodeImage, writeFile, base64" begin
        img = testImage()
        @test encodeImage(img, JpegFormat) == encodeJPEG(img)
        mktempdir() do dir
            for ext in (".jpg", ".jpeg")
                p = joinpath(dir, "out" * ext)
                writeFile(img, p)
                @test isfile(p) && filesize(p) > 100
                @test Tuple(read(p)[1:2]) == (0xff, 0xd8)
                # the existing decode dispatches by content (SOI).
                @test decodeImageDimensions(read(p)) == (64, 48)
                back = decodeImage(read(p))
                @test (width(back), height(back)) == (64, 48)
            end
            # unknown extensions still raise (existing behavior).
            @test_throws ArgumentError writeFile(img,
                joinpath(dir, "out.unknown"))
        end
        # encodeBase64 stays PNG-only (upstream parity): the payload is a
        # PNG, not a JPEG.
        @test Tuple(Vetra._base64Decode(Vetra._base64Payload(
            encodeBase64(img)))[1:8]) == Vetra.PNG_SIGNATURE
        # decodeBase64 accepts a JPEG payload (magic dispatch).
        payload = Vetra._base64Encode(encodeJPEG(img))
        @test (width(decodeBase64(payload)),
            height(decodeBase64(payload))) == (64, 48)
    end

    @testset "mupdf interop (independent reader)" begin
        # The PyMuPDF venv is a scratch tool, like T026's gs/poppler:
        # run the check when it resolves, note it when it does not.
        # `VETRA_MUPDF_PY` names the interpreter that can import it.
        mktempdir() do dir
            pyexe = get(ENV, "VETRA_MUPDF_PY", "python3")
            probe = joinpath(dir, "probe.py")
            open(probe, "w") do f
                write(f, "import pymupdf\n")
            end
            mupdf_ok = false
            try
                buf = IOBuffer()
                proc = run(pipeline(`$(pyexe) $(probe)`; stdout = buf,
                    stderr = devnull))
                mupdf_ok = success(proc)
            catch
            end
            if mupdf_ok
                img = testImage()
                p = joinpath(dir, "interop.jpg")
                writeFile(img, p)
                py = joinpath(dir, "dump.py")
                open(py, "w") do f
                    write(f, "import pymupdf as fzt\nimport sys\n" *
                        "d = fzt.open(sys.argv[1])\n" *
                        "pg = d[0]\n" *
                        "pix = pg.get_pixmap()\n" *
                        "open(sys.argv[1] + '.mupdf.raw', 'wb')" *
                        ".write(pix.samples)\n" *
                        "print('PAGE %.3f %.3f' %\n" *
                        "      (pg.rect.width, pg.rect.height))\n" *
                        "print('PIX %d %d %d' %\n" *
                        "      (pix.width, pix.height, pix.n))\n")
                end
                outbuf = IOBuffer()
                proc = run(pipeline(`$(pyexe) $(py) $(p)`; stdout = outbuf))
                @test success(proc)
                seekstart(outbuf)
                out = read(outbuf, String)
                lines = split(out, "\n")
                @test lines[1] == "PAGE 64.000 48.000"
                @test lines[2] == "PIX 64 48 3"
                # the 72-dpi pixmap is the exact pixel grid; against
                # Vetra's own decode the max channel delta is ≤ 8
                # (contract §2.6; measured 4 in the T030 probe).
                raw = read(p * ".mupdf.raw")
                @test length(raw) == 64 * 48 * 3
                @test maxdeltaVsRaw(decodeJPEG(read(p)), raw) <= 8
            else
                println("pymupdf not resolvable; mupdf interop " *
                    "check skipped")
            end
        end
    end
end
