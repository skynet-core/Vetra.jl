# T026: PDF export of recorded drawings (D030 §6.2, src/formats/pdf_write.jl).
#
# Method: hand-derived expectations only — document structure (xref
# self-consistency, stream Lengths, MediaBox from W*72/dpi), pixel checks
# from the pinned raster formulas at pixel centers (gs samples shadings at
# pixel centers, Vetra at integer coordinates — tolerance justified per
# check), arc-flattening bounds from the Bezier approximation, and
# premul->straight image bytes from the pinned toStraightAlpha formula.
# Verifiers (pinned, verification tooling only — no package dependency):
# Ghostscript 10.06.0 (`gs`) and poppler 26.01.0 (`pdftoppm`); both are
# independent PDF parsers/renderers. The group-opacity mechanism
# (/ca ExtGState in effect at `Do` time + isolated /Group form = group-unit
# compositing) was verified empirically against both before being trusted
# (hand-derived constant-alpha case, tasks/T026-pdf-export.md).

@testset "T026 PDF export of recorded drawings" begin
    function record(w, h, scene)
        rec = PictureRecorder(w, h)
        scene(rec.ctx)
        return finishRecording(rec)
    end

    dir = mktempdir()

    function doc_bytes(doc)
        return Vector{UInt8}(doc)
    end

    function find_pat(v, pat, from)
        m = length(pat)
        for i in from:(length(v) - m + 1)
            if v[i:i + m - 1] == pat
                return i
            end
        end
        return -1
    end

    find_pat(v, pat) = find_pat(v, pat, 1)

    pat(s) = collect(UInt8, s)

    function render_gs(pdf, png, dpi)
        # Single-line backtick: this build mis-parses backtick
        # concatenation across lines. ignorestatus: a nonzero gs exit
        # must not throw (we assert on the PNG instead).
        cmd = `/usr/bin/gs -dNOPAUSE -dBATCH -dQUIET -dSAFER -sDEVICE=png16m -r$(dpi) -o $(png) $(pdf)`
        Base.run(Base.ignorestatus(cmd))
        return isfile(png)
    end

    function render_ppm(pdf, png, dpi)
        cmd = `/usr/bin/pdftoppm -r $(dpi) -png $(pdf) $(png)`
        Base.run(Base.ignorestatus(cmd))
        return isfile(png * "-1.png")
    end

    @testset "check scene: hand-derived geometry" begin
        # Scene: 200x100 at dpi 72 -> page 200x100 pt -> 200x100 px at
        # 72 dpi (1 pt = 1 px). Pixel (x, y) 1-based has center (x-0.5,
        # y-0.5) in picture units; hand-derived values below.
        function scene_check(c)
            c.fillStyle = rgb(255, 255, 255)
            fillRect(c, 0f0, 0f0, 200f0, 100f0)
            c.fillStyle = rgb(255, 0, 0)
            fillRect(c, 20f0, 20f0, 40f0, 20f0)
            lin = Paint(LinearGradientPaint)
            lin.gradientHandlePositions = [Vec2(0f0, 0f0), Vec2(200f0, 0f0)]
            lin.gradientStops = [
                colorStop(rgba(0, 0, 255, 255), 0f0),
                colorStop(rgba(0, 255, 0, 255), 1f0)]
            c.fillStyle = lin
            fillRect(c, 100f0, 10f0, 100f0, 80f0)
            rad = Paint(RadialGradientPaint)
            rad.gradientHandlePositions = [Vec2(150f0, 50f0),
                Vec2(120f0, 50f0), Vec2(150f0, 80f0)]
            rad.gradientStops = [
                colorStop(rgba(255, 255, 0, 255), 0f0),
                colorStop(rgba(0, 0, 0, 255), 1f0)]
            c.fillStyle = rad
            fillRect(c, 115f0, 15f0, 70f0, 70f0)
            c.strokeStyle = rgb(255, 0, 0)
            c.lineWidth = 4f0
            c.lineDash = Float32[10f0, 5f0]
            beginPath(c)
            moveTo(c, 10f0, 95f0)
            lineTo(c, 190f0, 95f0)
            stroke(c)
            c.lineDash = Float32[]
            c.globalAlpha = 0.5f0
            c.fillStyle = rgb(0, 128, 255)
            fillRect(c, 20f0, 60f0, 20f0, 20f0)
            c.globalAlpha = 1f0
            return nothing
        end

        function check_pixels(shot)
            # White background (no other op covers (5,5)).
            @test getColor(shot, 5, 5) == rgbx(255, 255, 255, 255)
            # Red rect interior: exact.
            @test getColor(shot, 40, 30) == rgbx(255, 0, 0, 255)
            # Linear gradient at pixel centers (t = x_c/200):
            # (105,15): t = 104.5/200 = 0.5225 -> (0, 133.2, 121.8)
            p = getColor(shot, 105, 15)
            @test abs(Int(p.r) - 0) <= 2
            @test abs(Int(p.g) - 133) <= 2
            @test abs(Int(p.b) - 122) <= 2
            # (195,50): t = 194.5/200 = 0.9725 -> (0, 248.0, 6.9)
            p = getColor(shot, 195, 50)
            @test abs(Int(p.r) - 0) <= 2
            @test abs(Int(p.g) - 248) <= 2
            @test abs(Int(p.b) - 7) <= 2
            # Radial (center (150,50), dX = dY = 30, yellow -> black):
            # gs/poppler sample radial shadings with a renderer-specific
            # sub-pixel offset (up to ~1 px; the spec does not pin shading
            # sampling), so tolerance is 10 (~1 px along the gradient).
            # (150,50): t(center) ~ 0.0236 -> 249 (±10)
            p = getColor(shot, 150, 50)
            @test abs(Int(p.r) - 249) <= 10
            @test abs(Int(p.g) - 249) <= 10
            @test Int(p.b) <= 10
            # (175,50): t = 24.5/30 = 0.8167 -> 46.7 (±10)
            p = getColor(shot, 175, 50)
            @test abs(Int(p.r) - 47) <= 10
            @test abs(Int(p.g) - 47) <= 10
            @test Int(p.b) <= 10
            # Stroke: band y in [93,97], dash [10,5] from x=10:
            # (15,95) dash0 body, (22,95) gap, (27,95) dash1 body.
            @test getColor(shot, 15, 95) == rgbx(255, 0, 0, 255)
            @test getColor(shot, 22, 95) == rgbx(255, 255, 255, 255)
            @test getColor(shot, 27, 95) == rgbx(255, 0, 0, 255)
            # Group-unit opacity: 0.5 * (0,128,255) over white
            # = (127.5, 191.5, 255). (Per-child semantics would give the
            # same here for one child, but the empirical two-child case in
            # the task record pins the group-unit behavior.)
            p = getColor(shot, 30, 70)
            @test abs(Int(p.r) - 128) <= 2
            @test abs(Int(p.g) - 191) <= 2
            @test abs(Int(p.b) - 255) <= 2
            return nothing
        end

        function run_check(verifier, pdfname, pngname)
            pic = record(200, 100, scene_check)
            pdf = joinpath(dir, pdfname)
            writePdf(pdf, pic; dpi = 72f0)
            ok = if verifier === "gs"
                render_gs(pdf, pngname, 72)
            else
                render_ppm(pdf, pngname, 72)
            end
            @test ok
            shot = readImage(pngname * (verifier === "gs" ? "" : "-1.png"))
            @test shot.width == 200 && shot.height == 100
            check_pixels(shot)
            return nothing
        end

        if isfile("/usr/bin/gs")
            run_check("gs", "check_gs.pdf", joinpath(dir, "check_gs.png"))
        else
            println("gs not present; gs render check skipped")
        end
        if isfile("/usr/bin/pdftoppm")
            run_check("ppm", "check_ppm.pdf", joinpath(dir, "check_ppm"))
        else
            println("pdftoppm not present; poppler render check skipped")
        end
    end

    @testset "document structure is self-consistent" begin
        function scene_struct(c)
            c.fillStyle = rgb(255, 0, 0)
            fillRect(c, 10f0, 10f0, 20f0, 20f0)
            lin = Paint(LinearGradientPaint)
            lin.gradientHandlePositions = [Vec2(0f0, 0f0), Vec2(50f0, 0f0)]
            lin.gradientStops = [
                colorStop(rgba(0, 0, 255, 255), 0f0),
                colorStop(rgba(0, 255, 0, 255), 1f0)]
            c.fillStyle = lin
            fillRect(c, 30f0, 10f0, 20f0, 20f0)
            return nothing
        end
        pic = record(50, 50, scene_struct)
        file = joinpath(dir, "struct.pdf")
        doc = writePdf(file, pic; dpi = 96f0)
        bytes = doc_bytes(doc)
        @test bytes[1:9] == pat("%PDF-1.4\n")
        # The returned bytes are exactly the file bytes.
        @test bytes == read(file)
        # Page size: 50 * 72 / 96 = 37.5 pt.
        @test occursin("/MediaBox [0 0 37.5 37.5]", doc)
        # Root CTM: s = 72/96 = 0.75.
        @test occursin("0.75 0 0 -0.75 0 37.5 cm", doc)
        # xref: startxref points at the xref table.
        # This build's findfirst/findlast with a vector pattern return the
        # matched range, not the start index — unwrap with `first`.
        i = first(findlast(pat("startxref\n"), bytes))
        @test i !== -1
        line = bytes[(i + 10):end]
        j = first(findfirst(pat("\n"), line))
        @test j !== -1
        xrefPos = parse(Int, String(line[1:(j - 1)]))
        @test bytes[(xrefPos + 1):(xrefPos + 4)] == pat("xref")
        # Every xref entry points at its "N 0 obj" header.
        tx = first(findfirst(pat("xref\n0 "), bytes))
        @test tx !== -1
        rest = bytes[(tx + 7):(tx + 7 + 20)]
        k = first(findfirst(pat("\n"), rest))
        nObj = parse(Int, String(rest[1:(k - 1)]))
        entStart = tx + 7 + k
        for n in 0:(nObj - 1)
            lo = entStart + n * 20
            ent = bytes[lo:(lo + 19)]
            @test length(ent) == 20
            if n == 0
                @test ent[18:20] == pat("f \n")
                continue
            end
            off = parse(Int, String(ent[1:10]))
            @test bytes[(off + 1):(off + 7)] == pat(string(n) * " 0 obj")[1:7]
            @test ent[18:20] == pat("n \n")
        end
        # Trailer size.
        @test occursin("<</Size " * string(nObj) * " /Root 1 0 R>>", doc)
        # Stream Lengths: every "/Length N>>\nstream\n" is followed by
        # exactly N data bytes, then "\nendstream". `match`'s `offset`
        # kwarg is unavailable in this build, so walk suffixes; this
        # build's String is byte-aligned (1 char = 1 byte), so the
        # character offsets index `bytes` directly.
        marker = Regex("/Length ([0-9]+)>>\\nstream\\n")
        streams = 0
        pos = 1
        while true
            mm = match(marker, doc[pos:end])
            mm === nothing && break
            abs_off = pos + mm.offset - 1
            n = parse(Int, mm.captures[1])
            start = abs_off + length(mm.match)
            chunk = bytes[start:(start + n - 1)]
            @test length(chunk) == n
            tail = bytes[(start + n):(start + n + 9)]
            @test tail == pat("\nendstream")
            streams += 1
            pos = start + n
        end
        @test streams >= 1
    end

    @testset "scale independence (same picture, two dpi values)" begin
        function scene_scale(c)
            c.fillStyle = rgb(255, 255, 255)
            fillRect(c, 0f0, 0f0, 200f0, 100f0)
            c.fillStyle = rgb(255, 0, 0)
            fillRect(c, 20f0, 20f0, 40f0, 20f0)
            c.globalAlpha = 0.5f0
            c.fillStyle = rgb(0, 128, 255)
            fillRect(c, 20f0, 60f0, 20f0, 20f0)
            c.globalAlpha = 1f0
            return nothing
        end
        pic = record(200, 100, scene_scale)
        f72 = joinpath(dir, "scale72.pdf")
        f144 = joinpath(dir, "scale144.pdf")
        d72 = writePdf(f72, pic; dpi = 72f0)
        d144 = writePdf(f144, pic; dpi = 144f0)
        # Proportional page sizes: 200x100 pt at 72 dpi vs 100x50 pt at
        # 144 dpi (same physical size — scale-independent output).
        @test occursin("/MediaBox [0 0 200.0 100.0]", d72)
        @test occursin("/MediaBox [0 0 100.0 50.0]", d144)
        if isfile("/usr/bin/pdftoppm")
            # Rendered at their respective dpi: both 200x100 px.
            @test render_ppm(f72, joinpath(dir, "s72"), 72)
            @test render_ppm(f144, joinpath(dir, "s144"), 144)
            a = readImage(joinpath(dir, "s72-1.png"))
            b = readImage(joinpath(dir, "s144-1.png"))
            @test a.width == 200 && a.height == 100
            @test b.width == 200 && b.height == 100
            # Same picture-space points at the same device pixels.
            pairs = [(40, 30), (10, 10), (30, 70), (190, 90)]
            for (x, y) in pairs
                pa = getColor(a, x, y)
                pb = getColor(b, x, y)
                @test abs(Int(pa.r) - Int(pb.r)) <= 2
                @test abs(Int(pa.g) - Int(pb.g)) <= 2
                @test abs(Int(pa.b) - Int(pb.b)) <= 2
            end
            # Red interior exact at both scales.
            @test getColor(a, 40, 30) == rgbx(255, 0, 0, 255)
            @test getColor(b, 40, 30) == rgbx(255, 0, 0, 255)
        end
    end

    @testset "arc flattening" begin
        # Stroked circle r=40 at (50,50), width 2: the Bezier
        # approximation (<=90-degree segments, k = (4/3)tan(d/4)) has a
        # radial deviation < 0.027% of r (< 0.011 px here), so the
        # coverage band [39, 41] is exact at pixel centers.
        function scene_arc(c)
            c.fillStyle = rgb(255, 255, 255)
            fillRect(c, 0f0, 0f0, 100f0, 100f0)
            c.strokeStyle = rgb(0, 0, 0)
            c.lineWidth = 2f0
            beginPath(c)
            circle(c, 50f0, 50f0, 40f0)
            stroke(c)
            return nothing
        end
        pic = record(100, 100, scene_arc)
        pdf = joinpath(dir, "arc.pdf")
        writePdf(pdf, pic; dpi = 72f0)
        # poppler integrates stroke coverage exactly, so pixel-center
        # sampling is exact; gs shifts curve-stroke antialiasing by up
        # to ~0.5 px (renderer-specific; the spec does not pin
        # rasterization), so this check uses poppler.
        png = joinpath(dir, "arc")
        if isfile("/usr/bin/pdftoppm")
            @test render_ppm(pdf, png, 72)
            shot = readImage(png * "-1.png")
            # Pixel centers 0.5 pt inside the band are full coverage;
            # 1.5 pt outside are clean white (edge pixels carry ~0.1 pt
            # of renderer-specific partial coverage).
            # (90,50): center (89.5,49.5), distance 39.503 -> in band.
            @test getColor(shot, 90, 50) == rgbx(0, 0, 0, 255)
            # (88,50): distance 37.503 -> outside (white).
            @test getColor(shot, 88, 50) == rgbx(255, 255, 255, 255)
            # (91,50): distance 40.503 -> in band.
            @test getColor(shot, 91, 50) == rgbx(0, 0, 0, 255)
            # (93,50): distance 42.503 -> outside (white).
            @test getColor(shot, 93, 50) == rgbx(255, 255, 255, 255)
            # (50,90): the bottom of the circle (distance 39.503).
            @test getColor(shot, 50, 90) == rgbx(0, 0, 0, 255)
        else
            println("pdftoppm not present; arc render check skipped")
        end
    end

    @testset "arc and quad commands" begin
        # Stroked quad (apex (50,40), hand-derived) + 180-degree arc
        # (center (50,65), r=15, bottom half — flattened to exactly two
        # <=90-degree cubic segments). Pixel centers >=0.5 pt inside the
        # stroke band are full coverage, >=1.5 pt outside are clean
        # white (renderer-specific edge fuzz is ~0.5 pt at most).
        function scene_arcq(c)
            c.fillStyle = rgb(255, 255, 255)
            fillRect(c, 0f0, 0f0, 100f0, 100f0)
            c.strokeStyle = rgb(0, 0, 0)
            c.lineWidth = 2f0
            c.lineCap = RoundCap
            c.lineJoin = RoundJoin
            beginPath(c)
            moveTo(c, 20f0, 20f0)
            quadraticCurveTo(c, 50f0, 60f0, 80f0, 20f0)
            stroke(c)
            beginPath(c)
            moveTo(c, 65f0, 65f0)
            arc(c, 50f0, 65f0, 15f0, 0f0, Float32(pi))
            stroke(c)
            return nothing
        end
        pic = record(100, 100, scene_arcq)
        pdf = joinpath(dir, "arcq.pdf")
        doc = writePdf(pdf, pic; dpi = 72f0)
        # The 180-degree arc flattens to two cubics; the quad emits its
        # exact cubic equivalent (PDF has no quadratic operator) — three
        # space-indented `c` commands total (state saves are bare `q`).
        @test count(" c\n", doc) == 3

        function check_arcq(shot)
            # Quad apex (50,40): distance 0.707 -> in band.
            @test getColor(shot, 50, 40) == rgbx(0, 0, 0, 255)
            # (50,37) / (50,43): 3.5 / 2.5 from the apex -> outside.
            @test getColor(shot, 50, 37) == rgbx(255, 255, 255, 255)
            @test getColor(shot, 50, 43) == rgbx(255, 255, 255, 255)
            # Arc bottom (50,80): distance 0.707 -> in band.
            @test getColor(shot, 50, 80) == rgbx(0, 0, 0, 255)
            # (50,81): 1.5 inside the band -> in. (50,83): 1.5 outside.
            @test getColor(shot, 50, 81) == rgbx(0, 0, 0, 255)
            @test getColor(shot, 50, 83) == rgbx(255, 255, 255, 255)
            return nothing
        end

        if isfile("/usr/bin/gs")
            png = joinpath(dir, "arcq_gs.png")
            @test render_gs(pdf, png, 72)
            check_arcq(readImage(png))
        else
            println("gs not present; arcq gs render check skipped")
        end
        if isfile("/usr/bin/pdftoppm")
            png = joinpath(dir, "arcq_ppm")
            @test render_ppm(pdf, png, 72)
            check_arcq(readImage(png * "-1.png"))
        else
            println("pdftoppm not present; arcq poppler render check skipped")
        end
    end

    @testset "even-odd solid fill" begin
        # Two clockwise rects [10,60)^2 and [30,80)^2 filled even-odd:
        # the overlap [30,60)^2 is unpainted.
        function scene_eo(c)
            c.fillStyle = rgb(255, 255, 255)
            fillRect(c, 0f0, 0f0, 100f0, 100f0)
            p = newPath()
            rect(p, 10f0, 10f0, 50f0, 50f0)
            rect(p, 30f0, 30f0, 50f0, 50f0)
            c.fillStyle = rgb(0, 0, 0)
            fill(c, p, EvenOdd)
            return nothing
        end
        pic = record(100, 100, scene_eo)
        pdf = joinpath(dir, "eo.pdf")
        writePdf(pdf, pic; dpi = 72f0)
        doc = read(pdf, String)
        @test occursin("f*", doc)
        png = joinpath(dir, "eo.png")
        if isfile("/usr/bin/gs")
            @test render_gs(pdf, png, 72)
            shot = readImage(png)
            @test getColor(shot, 20, 20) == rgbx(0, 0, 0, 255)
            @test getColor(shot, 40, 40) == rgbx(255, 255, 255, 255)
            @test getColor(shot, 70, 40) == rgbx(0, 0, 0, 255)
        end
    end

    @testset "groups: structure and clip prefix" begin
        # clip -> saveLayer -> ... -> restore: the group's form content
        # must start with the clip path + `W n`, and the form must be an
        # isolated transparency group.
        function scene_grp(c)
            clipC = newPath()
            circle(clipC, 50f0, 50f0, 30f0)
            c.fillStyle = rgb(255, 255, 255)
            fillRect(c, 0f0, 0f0, 100f0, 100f0)
            clip(c, clipC)
            c.globalAlpha = 0.5f0
            c.fillStyle = rgb(255, 0, 0)
            fillRect(c, 10f0, 10f0, 80f0, 80f0)
            c.globalAlpha = 1f0
            return nothing
        end
        pic = record(100, 100, scene_grp)
        file = joinpath(dir, "grp.pdf")
        doc = writePdf(file, pic; dpi = 72f0)
        @test occursin("/Subtype /Form", doc)
        @test occursin("/Group <</Type /Group /S /Transparency /I true>>",
            doc)
        @test occursin("/ca 0.5", doc)
        # The recorder nests: clip -> GroupStart(op=1), globalAlpha ->
        # GroupStart(op=0.5). So the page draws the clip form Fm1; Fm1's
        # content is the clip prefix plus the nested opacity form Fm2
        # drawn with /ca in effect.
        @test occursin("/Fm1 Do", doc)
        @test occursin("/GS1 gs\n/Fm2 Do", doc)
        bytes = doc_bytes(doc)
        hdr = pat("0 obj\n<</Type /XObject /Subtype /Form")
        function form_stream(fi)
            lm = match(Regex("/Length ([0-9]+)>>\\nstream\\n"),
                String(bytes[fi:(fi + 300)]))
            @test lm !== nothing
            ln = parse(Int, lm.captures[1])
            st = fi + lm.offset - 1 + length(lm.match)
            return String(bytes[st:(st + ln - 1)])
        end
        fi1 = find_pat(bytes, hdr)
        @test fi1 !== -1
        f1 = form_stream(fi1)
        # Fm1 (clip group): content starts with the circle clip
        # (4 Béziers, `ellipse` starts at (cx + rx, cy)) + `W n`, then the
        # nested group; it has no fill of its own.
        @test startswith(f1, "80.0 50.0 m")
        @test occursin("W n", f1)
        @test occursin("/GS1 gs\n/Fm2 Do", f1)
        @test !occursin("1.0 0 0 rg", f1)
        fi2 = find_pat(bytes, hdr, fi1 + 1)
        @test fi2 !== -1
        f2 = form_stream(fi2)
        # Fm2 (opacity group): inherited clip prefix, then the red fill.
        @test startswith(f2, "80.0 50.0 m")
        @test occursin("W n", f2)
        @test occursin("1.0 0 0 rg", f2)
        @test occursin("f\nQ", f2)
    end

    @testset "image op: raw RGB and SMask bytes" begin
        # 2x2 premultiplied image drawn 1:1 on a 2x2 picture:
        #   (0,0): (200,100,50,a255) -> straight (200,100,50), a 255
        #   (1,0): (0,0,0,a0)        -> straight (0,0,0),     a 0
        #   (0,1): (64,128,64,a128)  -> 64*255/128 = 127.5 ->
        #                                 roundHalfAway -> (128,255,128),
        #                                 a 128
        #   (1,1): (10,20,30,a255)   -> (10,20,30), a 255
        img = newImage(2, 2)
        img.data[1:4] = [200, 100, 50, 255]
        img.data[5:8] = [0, 0, 0, 0]
        img.data[9:12] = [64, 128, 64, 128]
        img.data[13:16] = [10, 20, 30, 255]

        function scene_img(c)
            drawImage(c, img, 0f0, 0f0)
            return nothing
        end
        pic = record(2, 2, scene_img)
        file = joinpath(dir, "img.pdf")
        doc = writePdf(file, pic; dpi = 72f0)
        bytes = doc_bytes(doc)
        # Image object: RGB stream (byte-level search — the document is
        # binary once the image data starts).
        marker = "/SMask 7 0 R /Length 12>>\nstream\n"
        mi = find_pat(bytes, pat(marker))
        @test mi !== -1
        st = mi + length(marker)
        @test bytes[st:(st + 11)] == [200, 100, 50, 0, 0, 0,
            128, 255, 128, 10, 20, 30]
        # SMask object: alpha stream.
        marker2 = "/ColorSpace /DeviceGray /BitsPerComponent 8 " *
            "/Length 4>>\nstream\n"
        ms = find_pat(bytes, pat(marker2))
        @test ms !== -1
        st2 = ms + length(marker2)
        @test bytes[st2:(st2 + 3)] == [255, 0, 128, 255]
        # The Do maps the unit square through imageMat o scale(w, h):
        # here identity o scale(2,2) -> "2.0 0.0 0.0 2.0 0.0 0.0 cm".
        @test occursin("2.0 0 0 2.0 0 0 cm\n/Im1 Do", doc)
    end

    @testset "rasterFallback: one embedded image, replay-exact bytes" begin
        function scene_fb(c)
            c.fillStyle = rgb(255, 0, 0)
            fillRect(c, 0f0, 0f0, 30f0, 20f0)
            clearRect(c, 5f0, 5f0, 10f0, 10f0)
            c.fillStyle = rgb(0, 255, 0)
            fillRect(c, 8f0, 8f0, 4f0, 4f0)
            return nothing
        end
        pic = record(30, 20, scene_fb)
        # Strict mode refuses (clearRect) ...
        f1 = joinpath(dir, "fb-strict.pdf")
        try
            writePdf(f1, pic)
            @test false
        catch e
            @test e.msg !== nothing &&
                occursin("PDF op 2 (ClearOp)", e.msg)
        end
        @test !isfile(f1)
        # ... the fallback renders the whole picture to one image.
        file = joinpath(dir, "fb.pdf")
        doc = writePdf(file, pic; rasterFallback = true)
        @test occursin("/Subtype /Image", doc)
        @test count("/Subtype /Image", doc) == 2 # RGB + SMask
        @test count("<</Type /XObject /Subtype /Form", doc) == 0
        bytes = doc_bytes(doc)
        # Expected replay pixels (hand-derived from the ops):
        # red everywhere except the cleared 10x10 at [5,15)x[5,15),
        # green 4x4 at [8,12)x[8,12).
        replayed = newImage(30, 20)
        drawPicture(replayed, pic)
        rgbData = Vector{UInt8}(undef, 3 * 30 * 20)
        alphaData = Vector{UInt8}(undef, 30 * 20)
        d = replayed.data
        for y in 0:19
            for x in 0:29
                pi = 4 * (y * 30 + x)
                c = toStraightAlpha(ColorRGBX(d[pi + 1], d[pi + 2],
                    d[pi + 3], d[pi + 4]))
                k = 3 * (y * 30 + x)
                rgbData[k + 1] = c.r
                rgbData[k + 2] = c.g
                rgbData[k + 3] = c.b
                alphaData[y * 30 + x + 1] = c.a
            end
        end
        # Hand-derived spot checks on the expected bytes.
        @test rgbData[3 * 2 * 30 + 3 * 10 + 1] == 255 # red pixel (10,2)
        @test alphaData[1 * 30 + 10] == 255
        @test alphaData[6 * 30 + 10] == 0 # cleared pixel (10,6)
        @test rgbData[3 * 9 * 30 + 3 * 9 + 1] == 0 # green pixel (9,9): r
        @test rgbData[3 * 9 * 30 + 3 * 9 + 2] == 255 # ... g
        marker = "/SMask 6 0 R /Length " * string(length(rgbData)) *
            ">>\nstream\n"
        mi = find_pat(bytes, pat(marker))
        @test mi !== -1
        st = mi + length(marker)
        @test bytes[st:(st + length(rgbData) - 1)] == rgbData
        marker2 = "/ColorSpace /DeviceGray /BitsPerComponent 8 " *
            "/Length " * string(length(alphaData)) * ">>\nstream\n"
        ms = find_pat(bytes, pat(marker2))
        @test ms !== -1
        st2 = ms + length(marker2)
        @test bytes[st2:(st2 + length(alphaData) - 1)] == alphaData
        # Page: 30 * 72/96 = 22.5 x 20 * 72/96 = 15 pt.
        @test occursin("/MediaBox [0 0 22.5 15.0]", doc)
        # gs renders the fallback: red / cleared / green regions.
        png = joinpath(dir, "fb.png")
        if isfile("/usr/bin/gs")
            @test render_gs(file, png, 96)
            shot = readImage(png)
            @test shot.width == 30 && shot.height == 20
            @test getColor(shot, 10, 2) == rgbx(255, 0, 0, 255)
            @test getColor(shot, 6, 6) == rgbx(255, 255, 255, 255) # cleared (alpha 0 -> white backdrop)
            @test getColor(shot, 10, 10) == rgbx(0, 255, 0, 255) # green
        end
    end

    @testset "strict pre-scan errors (no file written)" begin
        counter = [0]

        function err_file()
            counter[1] += 1
            return joinpath(dir, "perr-" * string(counter[1]) * ".pdf")
        end

        function expectErr(build, msgPart)
            pic = record(20, 20, build)
            file = err_file()
            try
                writePdf(file, pic)
                @test false
            catch e
                @test e.msg !== nothing && occursin(msgPart, e.msg)
            end
            @test !isfile(file)
            return nothing
        end

        function scene_clear(c)
            c.fillStyle = rgb(0, 0, 0)
            fillRect(c, 0f0, 0f0, 10f0, 10f0)
            clearRect(c, 0f0, 0f0, 5f0, 5f0)
            return nothing
        end
        expectErr(scene_clear, "PDF op 2 (ClearOp)")

        function scene_angular(c)
            ang = Paint(AngularGradientPaint)
            ang.gradientHandlePositions = [Vec2(10f0, 10f0),
                Vec2(10f0, 10f0), Vec2(16f0, 10f0)]
            ang.gradientStops = [colorStop(rgba(255, 255, 0, 255), 0f0)]
            c.fillStyle = ang
            fillRect(c, 0f0, 0f0, 20f0, 20f0)
            return nothing
        end
        expectErr(scene_angular,
            "angular gradients have no conic shading")

        function scene_imagepaint(c)
            c.fillStyle = Paint(newImage(4, 4))
            fillRect(c, 0f0, 0f0, 20f0, 20f0)
            return nothing
        end
        expectErr(scene_imagepaint,
            "ImagePaint fills are not PDF-exportable")

        function scene_blendfill(c)
            c.fillStyle = Paint(rgba(255, 0, 0, 255);
                blendMode = MultiplyBlend)
            fillRect(c, 0f0, 0f0, 20f0, 20f0)
            return nothing
        end
        expectErr(scene_blendfill, "non-Normal blend mode")

        function scene_blendstroke(c)
            c.strokeStyle = Paint(rgba(255, 0, 0, 255);
                blendMode = ScreenBlend)
            beginPath(c)
            moveTo(c, 0f0, 0f0)
            lineTo(c, 20f0, 20f0)
            stroke(c)
            return nothing
        end
        expectErr(scene_blendstroke, "non-Normal blend mode")

        function scene_eograd(c)
            lin = Paint(LinearGradientPaint)
            lin.gradientHandlePositions = [Vec2(0f0, 0f0),
                Vec2(20f0, 0f0)]
            lin.gradientStops = [colorStop(rgba(0, 0, 255, 255), 0f0)]
            p = newPath()
            rect(p, 0f0, 0f0, 20f0, 20f0)
            rect(p, 5f0, 5f0, 10f0, 10f0)
            c.fillStyle = lin
            fill(c, p, EvenOdd)
            return nothing
        end
        expectErr(scene_eograd, "even-odd gradient fills")

        function scene_singular(c)
            setTransform(c, scale(Vec2(0f0, 1f0)))
            lin = Paint(LinearGradientPaint)
            lin.gradientHandlePositions = [Vec2(0f0, 0f0),
                Vec2(10f0, 0f0)]
            lin.gradientStops = [colorStop(rgba(0, 0, 255, 255), 0f0)]
            c.fillStyle = lin
            fillRect(c, 0f0, 0f0, 10f0, 10f0)
            return nothing
        end
        expectErr(scene_singular, "singular transform")

        function scene_coincident(c)
            lin = Paint(LinearGradientPaint)
            lin.gradientHandlePositions = [Vec2(5f0, 5f0),
                Vec2(5f0, 5f0)]
            lin.gradientStops = [colorStop(rgba(0, 0, 255, 255), 0f0)]
            c.fillStyle = lin
            fillRect(c, 0f0, 0f0, 20f0, 20f0)
            return nothing
        end
        expectErr(scene_coincident, "coincident handles")

        function scene_radialdeg(c)
            rad = Paint(RadialGradientPaint)
            rad.gradientHandlePositions = [Vec2(10f0, 10f0),
                Vec2(10f0, 10f0), Vec2(10f0, 16f0)]
            rad.gradientStops = [colorStop(rgba(0, 0, 255, 255), 0f0)]
            c.fillStyle = rad
            fillRect(c, 0f0, 0f0, 20f0, 20f0)
            return nothing
        end
        expectErr(scene_radialdeg, "center == edge")

        function scene_radialskew(c)
            rad = Paint(RadialGradientPaint)
            rad.gradientHandlePositions = [Vec2(10f0, 10f0),
                Vec2(10f0, 16f0), Vec2(10f0, 10f0)]
            rad.gradientStops = [colorStop(rgba(0, 0, 255, 255), 0f0)]
            c.fillStyle = rad
            fillRect(c, 0f0, 0f0, 20f0, 20f0)
            return nothing
        end
        expectErr(scene_radialskew, "center == skew")

        function scene_nostops(c)
            lin = Paint(LinearGradientPaint)
            lin.gradientHandlePositions = [Vec2(0f0, 0f0),
                Vec2(10f0, 0f0)]
            c.fillStyle = lin
            fillRect(c, 0f0, 0f0, 20f0, 20f0)
            return nothing
        end
        expectErr(scene_nostops, "at least 1 color stop")

        function scene_stop_high(c)
            lin = Paint(LinearGradientPaint)
            lin.gradientHandlePositions = [Vec2(0f0, 0f0),
                Vec2(10f0, 0f0)]
            lin.gradientStops = [
                colorStop(rgba(0, 0, 255, 255), 0f0),
                colorStop(rgba(255, 0, 0, 255), 1.5f0)]
            c.fillStyle = lin
            fillRect(c, 0f0, 0f0, 20f0, 20f0)
            return nothing
        end
        expectErr(scene_stop_high, "outside [0, 1]")

        function scene_stop_neg(c)
            lin = Paint(LinearGradientPaint)
            lin.gradientHandlePositions = [Vec2(0f0, 0f0),
                Vec2(10f0, 0f0)]
            lin.gradientStops = [
                colorStop(rgba(255, 0, 0, 255), -0.2f0),
                colorStop(rgba(0, 0, 255, 255), 0.5f0)]
            c.fillStyle = lin
            fillRect(c, 0f0, 0f0, 20f0, 20f0)
            return nothing
        end
        expectErr(scene_stop_neg, "outside [0, 1]")

        function scene_stop_desc(c)
            lin = Paint(LinearGradientPaint)
            lin.gradientHandlePositions = [Vec2(0f0, 0f0),
                Vec2(10f0, 0f0)]
            lin.gradientStops = [
                colorStop(rgba(0, 0, 255, 255), 0.5f0),
                colorStop(rgba(255, 0, 0, 255), 0.2f0)]
            c.fillStyle = lin
            fillRect(c, 0f0, 0f0, 20f0, 20f0)
            return nothing
        end
        expectErr(scene_stop_desc, "strictly increasing")

        function scene_stop_tie(c)
            lin = Paint(LinearGradientPaint)
            lin.gradientHandlePositions = [Vec2(0f0, 0f0),
                Vec2(10f0, 0f0)]
            lin.gradientStops = [
                colorStop(rgba(0, 0, 255, 255), 0.5f0),
                colorStop(rgba(255, 0, 0, 255), 0.5f0)]
            c.fillStyle = lin
            fillRect(c, 0f0, 0f0, 20f0, 20f0)
            return nothing
        end
        expectErr(scene_stop_tie, "strictly increasing")

        function scene_stop_alpha(c)
            lin = Paint(LinearGradientPaint)
            lin.gradientHandlePositions = [Vec2(0f0, 0f0),
                Vec2(10f0, 0f0)]
            lin.gradientStops = [
                colorStop(rgba(0, 0, 255, 128), 0f0),
                colorStop(rgba(255, 0, 0, 255), 1f0)]
            c.fillStyle = lin
            fillRect(c, 0f0, 0f0, 20f0, 20f0)
            return nothing
        end
        expectErr(scene_stop_alpha, "semi-transparent gradient stops")

        function scene_nanpath(c)
            c.fillStyle = rgb(0, 0, 0)
            beginPath(c)
            moveTo(c, Float32(NaN), 0f0)
            lineTo(c, 10f0, 10f0)
            fill(c)
            return nothing
        end
        expectErr(scene_nanpath, "non-finite path coordinate")

        function scene_nanwidth(c)
            c.strokeStyle = rgb(0, 0, 0)
            c.lineWidth = Float32(NaN)
            beginPath(c)
            moveTo(c, 0f0, 0f0)
            lineTo(c, 10f0, 10f0)
            stroke(c)
            return nothing
        end
        expectErr(scene_nanwidth, "non-finite stroke width")

        function scene_nanalpha(c)
            c.globalAlpha = Float32(NaN)
            c.fillStyle = rgb(0, 0, 0)
            fillRect(c, 0f0, 0f0, 10f0, 10f0)
            return nothing
        end
        expectErr(scene_nanalpha, "non-finite group opacity")
    end

    @testset "PDF number emission: §7.3.3 (no exponent form)" begin
        # ISO 32000-1 §7.3.3 NOTE 1: a conforming writer shall not use
        # the PostScript exponential syntax; poppler 26.01.0 (pinned
        # T026 validator) rejects such content streams. Values whose
        # `string` is exponent form (|v| < 1e-4 or >= 1e16, incl. the
        # Float32 sin residuals axis-aligned radial gradient maps leave
        # in the ellipse CTM) are expanded losslessly — the same digits,
        # the decimal point relocated; no rounding or digit cap.
        # Expected strings: the exact decimals of these Float32 values
        # (hand-verified; note Float32(1e20) is not exactly 10^20).
        @test Vetra._pdfNum(0.0) == "0"
        @test Vetra._pdfNum(-0.0f0) == "0" # signed zero normalizes
        @test Vetra._pdfNum(0.5f0) == "0.5" # ordinary form byte-unchanged
        @test Vetra._pdfNum(1234.5f0) == "1234.5"
        @test Vetra._pdfNum(1f-20) ==
            "0.000000000000000000009999999682655225"
        @test Vetra._pdfNum(-1f-20) ==
            "-0.000000000000000000009999999682655225"
        @test Vetra._pdfNum(1f20) == "100000002004087730000"
        @test Vetra._pdfNum(Float32(-1.5e-7)) == "-0.0000001500000053056283"
        @test Vetra._pdfNum(Float32(3.4e38)) ==
            "339999995214436420000000000000000000000"
        for v in (1f-20, -1f-20, 1f20, Float32(-1.5e-7), Float32(3.4e38),
            0.5f0, 1234.5f0)
            s = Vetra._pdfNum(v)
            @test !occursin(r"[eE]", s)
            @test parse(Float32, s) == v # independent parse-back
        end
        # A radial gradient whose center-edge vector points in -x
        # (theta = pi) leaves Float32 sin residuals (~1e-6) in the
        # ellipse-map CTM.
        function scene_res(c)
            rad = Paint(RadialGradientPaint)
            rad.gradientHandlePositions = [Vec2(50f0, 30f0),
                Vec2(80f0, 30f0), Vec2(50f0, 60f0)]
            rad.gradientStops = [
                colorStop(rgba(255, 255, 255, 255), 0f0),
                colorStop(rgba(234, 88, 12, 255), 1f0)]
            c.fillStyle = rad
            beginPath(c)
            circle(c, 50f0, 30f0, 30f0)
            fill(c)
            return nothing
        end
        pdf = joinpath(dir, "residual.pdf")
        doc = writePdf(pdf, record(100, 60, scene_res); dpi = 72f0)
        @test !occursin(r"[0-9][eE][+-]?[0-9]", doc)
        @test occursin("-30.0 -0.", doc)
        if isfile("/usr/bin/pdftoppm")
            cmd = `pdftoppm -png -r 72 $(pdf) $(joinpath(dir, "residualpg"))`
            err = IOBuffer()
            Base.run(pipeline(cmd; stderr = err, stdout = devnull))
            @test !occursin("Syntax Error", String(err.data[1:err.size]))
            @test isfile(joinpath(dir, "residualpg-1.png"))
        else
            println("pdftoppm not present; poppler render check skipped")
        end
    end

    rm(dir; recursive = true)
end
