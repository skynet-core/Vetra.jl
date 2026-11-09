# T032: static WebP read/write (D032, docs/JPEG_WEBP_CODECS.md §3,
# src/formats/webp.jl).
#
# Decode expectations come from the pinned upstream corpus
# (`.reference/upstream/tests/fileformats/webp/` — 129 libwebp test
# files, per that directory's SOURCE.txt) and the exact dimension list
# in upstream `tests/test_webp.nim` (12 named files). The animated
# fixture is pinned in test/reference with its sha256 in the meta.
# Encode validation follows contract §3.5: lossless is byte-exact in
# the premultiplied API (opaque and the alpha partition below), lossy
# is dimensions + a PSNR floor only. Recorded limitation (contract
# §3.5): no independent WebP pixel decoder exists on the verification
# machine, so corpus decode gets dimension/classification assertions,
# not pixel assertions.

@testset "T032 static WebP" begin
    root = dirname(@__DIR__)
    corpus = joinpath(root, ".reference", "upstream", "tests",
        "fileformats", "webp")
    reffix = joinpath(root, "test", "reference")

    function throws_arg(f, msg::String)
        try
            f()
            return false
        catch e
            return e isa ArgumentError && e.msg == msg
        end
    end

    function corpusFile(name)
        return Vector{UInt8}(read(joinpath(corpus, name)))
    end

    # The fixed test image: a 64×48 opaque gradient, asymmetric so a
    # transposed/rotated round trip fails (r varies with x, g with y,
    # b is constant).
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

    function alphaImage()
        # 16×16 with valid premultiplied pixels in three regions:
        # - top-left 8×8: fully transparent (p = 0, a = 0);
        # - bottom-left 8×8: straight (200, 100, 50) at a = 128, stored
        #   premultiplied as (100, 50, 25, 128) — (c*a + 127) div 255:
        #   (200*128 + 127) div 255 = 100, (100*128 + 127) div 255 = 50,
        #   (50*128 + 127) div 255 = 25;
        # - right half: an opaque checker.
        img = newImage(16, 16)
        for y in 1:16, x in 1:16
            if x <= 8 && y <= 8
                Vetra.set_pixel(img, x, y, rgbx(0, 0, 0, 0))
            elseif x <= 8
                Vetra.set_pixel(img, x, y, rgbx(100, 50, 25, 128))
            else
                Vetra.set_pixel(img, x, y, rgbx(
                    mod(x + y, 2) == 0 ? 255 : 0, 128, 64, 255))
            end
        end
        return img
    end

    """Count of differing channels (r, g, b, a) between two images."""
    function diffChannels(a, b)
        cnt = 0
        for y in 1:height(a), x in 1:width(a)
            ca = getColor(a, x, y)
            cb = getColor(b, x, y)
            for (va, vb) in [(Int(ca.r), Int(cb.r)), (Int(ca.g), Int(cb.g)),
                    (Int(ca.b), Int(cb.b)), (Int(ca.a), Int(cb.a))]
                va != vb && (cnt += 1)
            end
        end
        return cnt
    end

    """PSNR (dB) between two images in 8-bit RGB space."""
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

    """Contract §3.5 partition counters on a lossless round trip:
    (alpha mismatches, RGB mismatches where alpha > 0, nonzero RGB
    where alpha = 0). Hard-scoped (testset bodies are soft scope)."""
    function partitionCounts(orig, back)
        bad_alpha = 0
        bad_rgb = 0
        bad_zero = 0
        for y in 1:height(orig), x in 1:width(orig)
            o = getColor(orig, x, y)
            c = getColor(back, x, y)
            Int(o.a) != Int(c.a) && (bad_alpha += 1)
            if Int(o.a) > 0
                (Int(o.r), Int(o.g), Int(o.b)) !=
                    (Int(c.r), Int(c.g), Int(c.b)) && (bad_rgb += 1)
            else
                (Int(c.r), Int(c.g), Int(c.b)) != (0, 0, 0) &&
                    (bad_zero += 1)
            end
        end
        return bad_alpha, bad_rgb, bad_zero
    end

    """Hand walk of a RIFF chunk table: (chunk ids, end position)."""
    function walkChunks(buf)
        pos = 12
        ids = String[]
        while pos + 8 <= length(buf)
            push!(ids, String(buf[pos + 1:pos + 4]))
            sz = Int(buf[pos + 5]) + Int(buf[pos + 6]) * 256 +
                Int(buf[pos + 7]) * 256 * 256 + Int(buf[pos + 8]) * 256 * 256 * 256
            pos += 8 + sz + (mod(sz, 2) == 1 ? 1 : 0)
        end
        return ids, pos
    end

    """Counts of a == 0 and a == 255 pixels (hard-scoped; the testset
    body is soft scope in this build)."""
    function alphaCounts(img)
        n0 = 0
        n255 = 0
        for y in 1:height(img), x in 1:width(img)
            a = Int(getColor(img, x, y).a)
            a == 0 && (n0 += 1)
            a == 255 && (n255 += 1)
        end
        return n0, n255
    end

    @testset "dimensions: 12 exact upstream expectations" begin
        # Each value is a checkDimensions(...) call in
        # .reference/upstream/tests/test_webp.nim.
        @test decodeWebPDimensions(corpusFile("small_1x1.webp")) == (1, 1)
        @test decodeWebPDimensions(corpusFile("small_1x13.webp")) == (1, 13)
        @test decodeWebPDimensions(corpusFile("small_13x1.webp")) == (13, 1)
        @test decodeWebPDimensions(corpusFile("small_31x13.webp")) == (31, 13)
        @test decodeWebPDimensions(corpusFile("test.webp")) == (128, 128)
        @test decodeWebPDimensions(
            corpusFile("lossy_q0_f100.webp")) == (128, 128)
        @test decodeWebPDimensions(corpusFile("lossless1.webp")) == (1000, 307)
        @test decodeWebPDimensions(
            corpusFile("lossy_alpha1.webp")) == (1000, 307)
        @test decodeWebPDimensions(
            corpusFile("alpha_no_compression.webp")) == (16, 16)
        @test decodeWebPDimensions(
            corpusFile("one_color_no_palette.webp")) == (100, 100)
        @test decodeWebPDimensions(corpusFile("near_lossless_75.webp")) ==
            (256, 256)
        @test decodeWebPDimensions(
            corpusFile("vp80-00-comprehensive-016.webp")) == (176, 144)
    end

    @testset "corpus: all 129 pinned libwebp fixtures decode" begin
        # Upstream test_webp.nim asserts WebpSuiteFiles.len == 129, that
        # the info dimensions equal the dimensions-scan dimensions for
        # every file, and that every static file pixel-decodes.
        names = String[]
        for (d, _, fs) in walkdir(corpus)
            for f in sort(fs)
                endswith(f, ".webp") || continue
                push!(names, f)
                data = Vector{UInt8}(read(joinpath(d, f)))
                (w, h) = decodeWebPDimensions(data)
                @test w > 0 && h > 0
                img = decodeWebP(data)
                @test (width(img), height(img)) == (w, h)
            end
        end
        @test length(names) == 129
        # Corpus-wide alpha classification (T032 probe: every file
        # decoded; 89 have no alpha, 40 carry semi/transparent
        # pixels). Two hand-checked fixtures pin each side of the
        # conversion: RGB input decodes to a = 255, and the
        # fully-transparent "one color" file keeps a = 0.
        for f in ("small_1x1.webp", "test.webp",
            "vp80-00-comprehensive-016.webp")
            img = decodeWebP(corpusFile(f))
            @test all(Int(getColor(img, x, y).a) == 255 for
                x in 1:width(img) for y in 1:height(img))
        end
        img = decodeWebP(corpusFile("one_color_no_palette.webp"))
        @test all(Int(getColor(img, x, y).a) == 0 for x in 1:100
            for y in 1:100)
        # lossless1 mixes fully transparent and opaque pixels
        # (lossless alpha is exact: 211284 of 307000 decode to a = 0).
        img = decodeWebP(corpusFile("lossless1.webp"))
        n0, n255 = alphaCounts(img)
        @test n0 > 0 && n255 > 0
    end

    @testset "animation: named error before decode; dimensions still report" begin
        # Pinned fixture (test/reference/webp_animated_clock.*): the
        # meta records source URL, byte length, and sha256.
        meta_path = joinpath(reffix, "webp_animated_clock.meta")
        @test isfile(meta_path)
        data = Vector{UInt8}(read(joinpath(reffix,
            "webp_animated_clock.webp")))
        meta = Dict{String, String}()
        for l in readlines(meta_path)
            m = match(r"^([A-Za-z_0-9]+)=", l)
            isnothing(m) && continue
            meta[m.captures[1]] = l[length(m.match) + 1:end]
        end
        @test length(data) == parse(Int, meta["byte_length"])
        if isdefined(Main, :sha256) && isdefined(Main, :VetraRef)
            @test VetraRef.hexdigest(sha256(data)) == meta["sha256_file"]
        else
            println("SHA not loaded; animated-fixture checksum " *
                "verification skipped")
        end
        # The canvas size is still reported (211×211, recorded in the
        # meta; upstream reports the same file's dimensions without
        # rejecting it).
        @test decodeWebPDimensions(data) == (211, 211)
        # Pixel decode raises the named error instead of the
        # first-frame default or a process crash.
        @test throws_arg(() -> decodeWebP(data),
            "WebP animation is not supported")
    end

    @testset "invalid and truncated input" begin
        # Fixed non-WebP bytes (deterministic, no network): the feature
        # scan fails and the named error is raised before any pixel
        # decode.
        garbage = Vector{UInt8}(undef, 64)
        s = "This is definitely not a WebP file, no RIFF and no WEBP."
        for i in 1:64
            garbage[i] = s[mod(i - 1, length(s)) + 1]
        end
        @test throws_arg(() -> decodeWebP(garbage),
            "Invalid WebP, unable to load")
        @test throws_arg(() -> decodeWebPDimensions(garbage),
            "Invalid WebP, unable to load")
        # A valid file cut off mid-header: the feature scan fails.
        small = corpusFile("small_1x1.webp")
        @test throws_arg(() -> decodeWebP(small[1:10]),
            "Invalid WebP, unable to load")
        @test throws_arg(() -> decodeWebPDimensions(small[1:10]),
            "Invalid WebP, unable to load")
        # Cut off inside the (only) chunk: libwebp's feature scan
        # validates the chunk data, so this fails too — the scan
        # guards the pixel decode in both truncation cases.
        @test throws_arg(() -> decodeWebP(small[1:20]),
            "Invalid WebP, unable to load")
        @test throws_arg(() -> decodeWebPDimensions(small[1:20]),
            "Invalid WebP, unable to load")
    end

    @testset "magic dispatch boundaries" begin
        # RIFF + WEBP under the 30-byte floor falls through to the
        # existing unsupported-format error (contract §3.1).
        short = vcat(UInt8.(collect("RIFF")), 0x00, 0x00, 0x00, 0x00,
            UInt8.(collect("WEBP")), UInt8.(collect("VP8L")))
        @test length(short) < 30
        @test throws_arg(() -> decodeImage(short),
            "Unsupported image file format")
        @test throws_arg(() -> decodeImageDimensions(short),
            "Unsupported image file format")
        # At/above the floor the WebP branch engages.
        img = testImage()
        buf = encodeWebP(img; lossy = false)
        @test (width(decodeImage(buf)), height(decodeImage(buf))) == (64, 48)
        @test decodeImageDimensions(buf) == (64, 48)
    end

    @testset "conversion helpers (exact integer, contract §3.3)" begin
        # (p8*255 + a8 div 2) div a8, clamped; a8 = 0 → 0.
        @test Vetra._webpUnpremul(100, 200) == 128   # 25600 div 200
        @test Vetra._webpUnpremul(200, 255) == 200  # opaque passthrough
        @test Vetra._webpUnpremul(0, 255) == 0
        @test Vetra._webpUnpremul(128, 128) == 255  # 32704 div 128 = 256, clamped
        @test Vetra._webpUnpremul(7, 1) == 255      # 1785 div 1, clamped
        @test Vetra._webpUnpremul(0, 0) == 0
        @test Vetra._webpUnpremul(200, 0) == 0      # color under a = 0 is dropped
        # premul → straight → premul is the identity on valid premul
        # pixels (p8 ≤ a8): the half-rounded divisions compose exactly.
        @test (Vetra._webpUnpremul(100, 128) * 128 + 127) ÷ 255 == 100
        @test (Vetra._webpUnpremul(50, 128) * 128 + 127) ÷ 255 == 50
        @test (Vetra._webpUnpremul(25, 128) * 128 + 127) ÷ 255 == 25
    end

    @testset "lossless round-trip: byte-exact partition" begin
        img = testImage()
        back = decodeWebP(encodeWebP(img; lossy = false))
        # Opaque (a = 255) lossless: byte-exact, including orientation
        # (the gradient is asymmetric).
        @test (width(back), height(back)) == (64, 48)
        @test diffChannels(back, img) == 0
        tl = getColor(back, 2, 2)
        tr = getColor(back, 63, 2)
        br = getColor(back, 63, 47)
        bl = getColor(back, 2, 47)
        @test Int(tl.r) < 40 && Int(tl.g) < 40
        @test Int(tr.r) > 200 && Int(tr.g) < 40
        @test Int(br.r) > 200 && Int(br.g) > 180
        @test Int(bl.r) < 40 && Int(bl.g) > 180

        aimg = alphaImage()
        aback = decodeWebP(encodeWebP(aimg; lossy = false))
        @test (width(aback), height(aback)) == (16, 16)
        # Contract §3.5 partition, in the premultiplied API:
        # - alpha exact on every pixel;
        # - RGB exact on every pixel with alpha > 0;
        # - RGB is 0 on every pixel with alpha = 0 (the format leaves
        #   the straight color under full transparency unspecified, but
        #   premultiplied channels are forced to 0 by the multiply).
        bad_alpha, bad_rgb, bad_zero = partitionCounts(aimg, aback)
        @test bad_alpha == 0
        @test bad_rgb == 0
        @test bad_zero == 0
    end

    @testset "lossy: dimensions and PSNR floor, never bytes" begin
        img = testImage()
        buf = encodeWebP(img; lossy = true, quality = 75)
        @test length(buf) > 30
        back = decodeWebP(buf)
        @test (width(back), height(back)) == (64, 48)
        @test all(Int(getColor(back, x, y).a) == 255 for x in 1:64
            for y in 1:48)
        # Contract §3.5: PSNR floor on the fixed gradient at q75 —
        # ≥ 35 dB (T030 probe measured 37.67; q95 45.11, q50 36.63,
        # q10 31.99). The knob bites: q10 is strictly worse than q75.
        @test psnr8(back, img) >= 35
        @test psnr8(decodeWebP(encodeWebP(img; lossy = true,
            quality = 10)), img) < psnr8(back, img)
        # lossless ignores quality (provider API has no lossless
        # quality parameter): same bytes for any quality value.
        @test encodeWebP(img; lossy = false, quality = 10) ==
            encodeWebP(img; lossy = false, quality = 90)
    end

    @testset "RIFF structure (hand walk of the chunk table)" begin
        img = testImage()
        aimg = alphaImage()
        ll = encodeWebP(img; lossy = false)
        @test String(ll[1:4]) == "RIFF"
        riff = Int(ll[5]) + Int(ll[6]) * 256 + Int(ll[7]) * 256 * 256 +
            Int(ll[8]) * 256 * 256 * 256
        @test riff == length(ll) - 8   # RIFF: bytes after the size field
        @test String(ll[9:12]) == "WEBP"
        ids, pos = walkChunks(ll)
        @test ids == ["VP8L"] && pos == length(ll)
        # Lossy opaque content: a single VP8 chunk (libwebp drops the
        # all-opaque alpha).
        lo = encodeWebP(img; lossy = true, quality = 75)
        ids2, pos2 = walkChunks(lo)
        @test ids2 == ["VP8 "] && pos2 == length(lo)
        # Lossy content with real alpha: VP8X + ALPH + VP8 (the WebP
        # extended file; observed libwebp_jll 1.6.1 order).
        la = encodeWebP(aimg; lossy = true, quality = 75)
        ids3, pos3 = walkChunks(la)
        @test ids3 == ["VP8X", "ALPH", "VP8 "] && pos3 == length(la)
        # Lossless carries the alpha inside VP8L (no ALPH chunk).
        la_ll = encodeWebP(aimg; lossy = false)
        ids4, pos4 = walkChunks(la_ll)
        @test ids4 == ["VP8L"] && pos4 == length(la_ll)
    end

    @testset "validation and errors (contract §3.3/§3.4)" begin
        img = testImage()
        # The dimension bound rejects before the provider runs (at
        # 16384 the provider silently returns an empty vector — T030
        # probe).
        @test throws_arg(() -> encodeWebP(newImage(16384, 4)),
            "WebP dimension exceeds 16383")
        @test throws_arg(() -> encodeWebP(newImage(4, 16384)),
            "WebP dimension exceeds 16383")
        # The bound itself encodes (lossy, for speed) and round-trips.
        big = encodeWebP(newImage(16383, 4); lossy = true, quality = 75)
        @test length(big) > 0
        @test decodeWebPDimensions(big) == (16383, 4)
        # Lossy quality is the provider's 0..100 range with the
        # provider's named error; 0 and 100 are accepted.
        @test throws_arg(() -> encodeWebP(img; lossy = true, quality = 101),
            "Quality 101 is not in the range from 0 to 100.")
        @test throws_arg(() -> encodeWebP(img; lossy = true, quality = -1),
            "Quality -1 is not in the range from 0 to 100.")
        @test length(encodeWebP(img; lossy = true, quality = 0)) > 0
        @test length(encodeWebP(img; lossy = true, quality = 100)) > 0
        # A non-Int quality is a type error, not a silent conversion.
        @test_throws TypeError encodeWebP(img; lossy = true, quality = 75.0)
        # Small and non-square images (mirroring upstream's small
        # fixtures): encode → decode → exact dimensions.
        for (w, h) in [(1, 1), (1, 13), (13, 1), (31, 13), (3, 4)]
            s = newImage(w, h)
            fill(s, rgb(200, 30, 60))
            @test decodeWebPDimensions(
                encodeWebP(s; lossy = false)) == (w, h)
            @test (width(decodeWebP(encodeWebP(s; lossy = false))),
                height(decodeWebP(encodeWebP(s; lossy = false)))) == (w, h)
        end
    end

    @testset "dispatch: encodeImage, writeFile, base64" begin
        img = testImage()
        @test encodeImage(img, WebpFormat) == encodeWebP(img)
        mktempdir() do dir
            p = joinpath(dir, "out.webp")
            writeFile(img, p)
            # writeFile uses the API defaults (lossy, quality 75) and
            # the encoder is deterministic.
            @test read(p) == encodeWebP(img)
            @test String(read(p)[1:4]) == "RIFF"
            @test String(read(p)[9:12]) == "WEBP"
            @test decodeImageDimensions(read(p)) == (64, 48)
            @test (width(readImage(p)), height(readImage(p))) == (64, 48)
            # GIF writing still raises (D014, unchanged).
            try
                encodeImage(img, GifFormat)
                error("GIF encoding should be unsupported")
            catch e
                @test e.msg == "Unsupported file format"
            end
        end
        # decodeBase64 accepts a WebP payload through the magic dispatch.
        payload = Vetra._base64Encode(encodeWebP(img; lossy = false))
        @test (width(decodeBase64(payload)), height(decodeBase64(
            payload))) == (64, 48)
        # encodeBase64 stays PNG-only (upstream parity): its payload is
        # a PNG, not a WebP.
        @test Tuple(Vetra._base64Decode(
            Vetra._base64Payload(encodeBase64(img)))[1:8]) ==
            Vetra.PNG_SIGNATURE
    end
end
