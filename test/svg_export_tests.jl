# T025: SVG export of recorded drawings (D030 §6.1, src/formats/svg_write.jl).
#
# Method: hand-derived expectations only — exact documents for minimal
# scenes, matrix strings from the pinned Mat3 convention (m[i, j] = column
# i, row j; SVG `matrix(a b c d e f)` = x' = ax + cy + e, y' = bx + dy + f),
# gradientTransform values from the raster gradient formulas
# (docs/RECORDING.md §6.1, derivation in tasks/T025-svg-export.md).
# Structure is checked independently with the opt-in XML package; read-back
# through Vetra's pinned SVG reader is supplemental; external rendering uses
# headless Chromium when present (verifier tooling, not a dependency).

@testset "T025 SVG export of recorded drawings" begin
    function record(w, h, scene)
        rec = PictureRecorder(w, h)
        scene(rec.ctx)
        return finishRecording(rec)
    end

    dir = mktempdir()

    @testset "minimal document is byte-exact" begin
        function scene_minimal(c)
            c.fillStyle = rgb(255, 0, 0)
            fillRect(c, 10f0, 20f0, 30f0, 20f0)
            return nothing
        end
        file = joinpath(dir, "minimal.svg")
        doc = writeSvg(file, record(100, 50, scene_minimal))
        expected =
            "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n" *
            "<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"100\" " *
            "height=\"50\" viewBox=\"0 0 100 50\">\n" *
            "<path d=\"M 10.0 20.0 L 40.0 20.0 L 40.0 40.0 " *
            "L 10.0 40.0 Z\" fill=\"#ff0000\"/>\n" *
            "</svg>\n"
        @test doc == expected
        @test read(file, String) == doc
    end

    @testset "empty picture" begin
        function scene_empty(c)
            return nothing
        end
        doc = writeSvg(joinpath(dir, "empty.svg"), record(10, 10, scene_empty))
        @test doc ==
            "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n" *
            "<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"10\" " *
            "height=\"10\" viewBox=\"0 0 10 10\">\n</svg>\n"
    end

    @testset "path d serialization (all command kinds)" begin
        function scene_allcmds(c)
            p = parsePath(
                "M 1 2 L 3 4 H 5 V 6 C 7 8 9 10 11 12 " *
                "S 13 14 15 16 Q 17 18 19 20 T 21 22 " *
                "A 23 24 45 1 0 25 26 Z " *
                "m 27 28 l 29 30 h 31 v 32 c 33 34 35 36 37 38 " *
                "s 39 40 41 42 q 43 44 45 46 t 47 48 " *
                "a 49 50 135 0 1 51 52")
            c.fillStyle = rgb(0, 0, 0)
            fill(c, p)
            return nothing
        end
        doc = writeSvg(joinpath(dir, "allcmds.svg"), record(120, 120,
            scene_allcmds))
        expected_d =
            "M 1.0 2.0 L 3.0 4.0 H 5.0 V 6.0 " *
            "C 7.0 8.0 9.0 10.0 11.0 12.0 " *
            "S 13.0 14.0 15.0 16.0 " *
            "Q 17.0 18.0 19.0 20.0 T 21.0 22.0 " *
            "A 23.0 24.0 45.0 1 0 25.0 26.0 Z " *
            "m 27.0 28.0 l 29.0 30.0 h 31.0 v 32.0 " *
            "c 33.0 34.0 35.0 36.0 37.0 38.0 " *
            "s 39.0 40.0 41.0 42.0 " *
            "q 43.0 44.0 45.0 46.0 t 47.0 48.0 " *
            "a 49.0 50.0 135.0 0 1 51.0 52.0"
        @test occursin("<path d=\"" * expected_d *
            "\" fill=\"#000000\"/>", doc)
    end

    @testset "solid fill alpha and opacity" begin
        function scene_alpha(c)
            c.fillStyle = Paint(rgba(0, 0, 255, 128); opacity = 0.5f0)
            fillRect(c, 0f0, 0f0, 20f0, 20f0)
            return nothing
        end
        doc = writeSvg(joinpath(dir, "alpha.svg"), record(20, 20,
            scene_alpha))
        @test occursin("fill=\"#0000ff\"", doc)
        # 0.5 * 128/255 = 64/255 (Float32)
        m = match(Regex("fill-opacity=\"([^\"]+)\""), doc)
        @test abs(parse(Float64, m.captures[1]) - 64 / 255) < 1e-6
    end

    @testset "linear gradient: handles, stops, transform" begin
        stops = [
            colorStop(rgba(0, 0, 255, 255), 0f0),
            colorStop(rgba(0, 255, 0, 128), 0.5f0),
            colorStop(rgba(255, 0, 0, 255), 1f0)]
        handles = [Vec2(0f0, 0f0), Vec2(100f0, 0f0)]

        function scene_lin(c)
            lin = Paint(LinearGradientPaint)
            lin.gradientHandlePositions = handles
            lin.gradientStops = stops
            c.fillStyle = lin
            fillRect(c, 0f0, 0f0, 100f0, 100f0)
            return nothing
        end

        # Identity transform: raw canvas handles, no gradientTransform.
        doc = writeSvg(joinpath(dir, "lin-id.svg"), record(100, 100,
            scene_lin))
        @test occursin(
            "<linearGradient id=\"gn1\" gradientUnits=\"userSpaceOnUse\" " *
            "x1=\"0.0\" y1=\"0.0\" x2=\"100.0\" y2=\"0.0\">", doc)
        @test occursin(
            "<stop offset=\"0.0\" stop-color=\"#0000ff\"/>", doc)
        m = match(Regex("<stop offset=\"0\\.5\" stop-color=\"#00ff00\" " *
            "stop-opacity=\"([^\"]+)\"/>"), doc)
        @test m !== nothing
        @test abs(parse(Float64, m.captures[1]) - 128 / 255) < 1e-6
        @test occursin("<stop offset=\"1.0\" stop-color=\"#ff0000\"/>",
            doc)
        # translate(10, 5): gradientTransform = inverse = (-10, -5); the
        # element transform goes on the path, not the handles.
        function scene_lin_t(c)
            translate(c, 10f0, 5f0)
            scene_lin(c)
            return nothing
        end
        doc2 = writeSvg(joinpath(dir, "lin-t.svg"), record(100, 100,
            scene_lin_t))
        @test occursin(
            "gradientTransform=\"matrix(1.0 0.0 0.0 1.0 -10.0 -5.0)\"",
            doc2)
        @test occursin(
            "<path d=\"M 0.0 0.0 L 100.0 0.0 L 100.0 100.0 " *
            "L 0.0 100.0 Z\" transform=\"matrix(1.0 0.0 0.0 1.0 " *
            "10.0 5.0)\" fill=\"url(#gn1)\"", doc2)
    end

    @testset "radial gradient: ellipse map and gradientTransform" begin
        handles = [Vec2(50f0, 25f0), Vec2(30f0, 25f0),
            Vec2(50f0, 45f0)]
        stops = [
            colorStop(rgba(255, 255, 0, 255), 0f0),
            colorStop(rgba(0, 0, 255, 255), 1f0)]

        function scene_rad(c)
            # center (50, 25), edge (30, 25) -> dX 20, theta 0;
            # skew (50, 45) -> dY 20. M = T * R(0) * S(20, 20), exact.
            rad = Paint(RadialGradientPaint)
            rad.gradientHandlePositions = handles
            rad.gradientStops = stops
            c.fillStyle = rad
            fillRect(c, 0f0, 0f0, 100f0, 100f0)
            return nothing
        end

        doc = writeSvg(joinpath(dir, "rad-id.svg"), record(100, 100,
            scene_rad))
        @test occursin(
            "<radialGradient id=\"gn1\" gradientUnits=\"userSpaceOnUse\" " *
            "cx=\"0\" cy=\"0\" r=\"1\" " *
            "gradientTransform=\"matrix(20.0 0.0 0.0 20.0 50.0 25.0)\">",
            doc)
        # Uniform scale(2): GT = T^-1 * M = S(0.5) * M, exact.
        function scene_rad_t(c)
            setTransform(c, scale(Vec2(2f0, 2f0)))
            scene_rad(c)
            return nothing
        end
        doc2 = writeSvg(joinpath(dir, "rad-t.svg"), record(100, 100,
            scene_rad_t))
        @test occursin(
            "gradientTransform=\"matrix(10.0 0.0 0.0 10.0 25.0 12.5)\"",
            doc2)
    end

    @testset "stroke attributes" begin
        function scene_dash(c)
            c.strokeStyle = rgb(1, 2, 3)
            c.lineWidth = 2f0
            c.lineCap = RoundCap
            c.lineJoin = BevelJoin
            c.miterLimit = 4f0
            c.lineDash = Float32[3f0, 2f0]
            beginPath(c)
            moveTo(c, 2f0, 10f0)
            lineTo(c, 58f0, 10f0)
            stroke(c)
            return nothing
        end
        doc = writeSvg(joinpath(dir, "stroke.svg"), record(60, 20,
            scene_dash))
        @test occursin(
            "<path d=\"M 2.0 10.0 L 58.0 10.0\" fill=\"none\" " *
            "stroke=\"#010203\" stroke-width=\"2.0\" " *
            "stroke-linecap=\"round\" stroke-linejoin=\"bevel\" " *
            "stroke-miterlimit=\"4.0\" " *
            "stroke-dasharray=\"3.0 2.0\"/>", doc)
        # Defaults: butt cap, miter join, miterLimit 10, no dashes.
        function scene_plain(c)
            c.strokeStyle = rgb(9, 9, 9)
            c.lineCap = SquareCap
            beginPath(c)
            moveTo(c, 2f0, 10f0)
            lineTo(c, 58f0, 10f0)
            stroke(c)
            return nothing
        end
        doc2 = writeSvg(joinpath(dir, "stroke2.svg"), record(60, 20,
            scene_plain))
        @test occursin(
            "stroke=\"#090909\" stroke-width=\"1.0\" " *
            "stroke-linecap=\"square\" stroke-linejoin=\"miter\" " *
            "stroke-miterlimit=\"10.0\"/>", doc2)
        @test !occursin("dasharray", doc2)
        # Stroke under a transform: matrix on the path, not the stroke.
        function scene_rot(c)
            rotate(c, Float32(0.5))
            scene_plain(c)
            return nothing
        end
        doc3 = writeSvg(joinpath(dir, "stroke3.svg"), record(60, 20,
            scene_rot))
        @test occursin("transform=\"matrix(", doc3)
    end

    @testset "winding rules: fill-rule and clip children" begin
        function scene_eo(c)
            p = newPath()
            rect(p, 0f0, 0f0, 20f0, 20f0)
            rect(p, 5f0, 5f0, 10f0, 10f0)
            clipC = newPath()
            circle(clipC, 10f0, 10f0, 9f0)
            clip(c, clipC, EvenOdd)
            c.fillStyle = rgb(0, 128, 0)
            fill(c, p, EvenOdd)
            return nothing
        end
        doc = writeSvg(joinpath(dir, "evenodd.svg"), record(20, 20,
            scene_eo))
        @test occursin("fill-rule=\"evenodd\"", doc)
        @test count("fill-rule=\"evenodd\"", doc) == 2 # path + clip child
    end

    @testset "groups: opacity, nested, clip structure" begin
        function scene_groups(c)
            clipC = newPath()
            circle(clipC, 30f0, 30f0, 20f0)
            c.fillStyle = rgb(240, 240, 240)
            fillRect(c, 0f0, 0f0, 60f0, 60f0)
            clip(c, clipC)
            saveLayer(c)
            c.fillStyle = rgb(255, 0, 0)
            fillRect(c, 0f0, 0f0, 60f0, 60f0)
            restore(c)
            c.globalAlpha = 0.5f0
            c.fillStyle = rgb(0, 0, 255)
            fillRect(c, 10f0, 10f0, 10f0, 10f0)
            c.globalAlpha = 1f0
            return nothing
        end
        doc = writeSvg(joinpath(dir, "groups.svg"), record(60, 60,
            scene_groups))
        # The globalAlpha wrapper is a group with opacity 0.5; with a clip
        # active at the root it is nested inside the implicit clip group,
        # and every GroupEnd carries the ambient clip list (the pinned
        # double-clip quirk). cp ids are assigned in GroupEnd order:
        # the saveLayer scope ends first (cp1), then the alpha group
        # (cp2), then the implicit outer group (cp3).
        @test occursin("<g clip-path=\"url(#cp1)\">", doc)
        @test occursin("<g clip-path=\"url(#cp3)\">", doc)
        @test occursin(
            "<g opacity=\"0.5\" clip-path=\"url(#cp2)\">", doc)
        @test occursin("<clipPath id=\"cp3\">", doc)
        @test occursin("<clipPath id=\"cp2\">", doc)
        @test occursin("<clipPath id=\"cp1\">", doc)
        # The bare background fill is outside any group.
        @test occursin(
            "<path d=\"M 0.0 0.0 L 60.0 0.0 L 60.0 60.0 L 0.0 60.0 Z\" " *
            "fill=\"#f0f0f0\"/>", doc)
    end

    @testset "image ops: data URI and matrix" begin
        src = newImage(8, 8)
        fill(src, rgb(120, 60, 200))

        function scene_img(c)
            c.fillStyle = rgb(20, 20, 60)
            fillRect(c, 0f0, 0f0, 40f0, 40f0)
            drawImage(c, src, 5f0, 5f0)
            return nothing
        end

        doc = writeSvg(joinpath(dir, "image.svg"), record(40, 40,
            scene_img))
        @test occursin(
            "<image x=\"0\" y=\"0\" width=\"8\" height=\"8\" " *
            "preserveAspectRatio=\"none\" " *
            "href=\"data:image/png;base64,", doc)
        @test occursin(
            "transform=\"matrix(1.0 0.0 0.0 1.0 5.0 5.0)\"/>", doc)
        # The payload is a valid 8x8 PNG (independent IHDR check:
        # signature + big-endian width/height at bytes 16..23).
        m = match(Regex("base64,([A-Za-z0-9+/=]+)\""), doc)
        @test m !== nothing
        raw = Vetra._base64Decode(String(m.captures[1]))
        @test raw[1:8] == [0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a,
            0x0a]
        @test raw[17:20] == [0x00, 0x00, 0x00, 0x08]
        @test raw[21:24] == [0x00, 0x00, 0x00, 0x08]
        # Under scale(2): imageMat = T * translate(5, 5) * scale(1, 1).
        function scene_img_t(c)
            setTransform(c, scale(Vec2(2f0, 2f0)))
            drawImage(c, src, 5f0, 5f0)
            return nothing
        end
        doc2 = writeSvg(joinpath(dir, "image2.svg"), record(40, 40,
            scene_img_t))
        @test occursin(
            "transform=\"matrix(2.0 0.0 0.0 2.0 10.0 10.0)\"", doc2)
    end

    @testset "stable identifiers and return value" begin
        handles = [Vec2(0f0, 0f0), Vec2(10f0, 0f0)]
        stops = [colorStop(rgba(255, 0, 0, 255), 0f0)]

        function scene_ids(c)
            lin = Paint(LinearGradientPaint)
            lin.gradientHandlePositions = handles
            lin.gradientStops = stops
            c.fillStyle = lin
            fillRect(c, 0f0, 0f0, 10f0, 10f0)
            c.fillStyle = rgb(0, 255, 0)
            fillRect(c, 20f0, 0f0, 10f0, 10f0)
            return nothing
        end

        file = joinpath(dir, "ids.svg")
        doc = writeSvg(file, record(40, 40, scene_ids))
        @test read(file, String) == doc
        @test occursin("id=\"gn1\"", doc)
        @test !occursin("gn2", doc) # one gradient per picture
    end

    @testset "rasterFallback" begin
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
        f1 = joinpath(dir, "fb-strict.svg")
        try
            writeSvg(f1, pic)
            @test false
        catch e
            @test e.msg ===
                "SVG op 2 (ClearOp): clearRect has no static-SVG " *
                "equivalent; use rasterFallback = true"
        end
        @test !isfile(f1)
        # ... the fallback renders the whole picture to one image.
        file = joinpath(dir, "fb.svg")
        doc = writeSvg(file, pic; rasterFallback = true)
        @test !occursin("<path", doc)
        @test occursin(
            "<!-- Vetra rasterFallback: whole-picture raster (D030) -->",
            doc)
        @test occursin(
            "<image x=\"0\" y=\"0\" width=\"30\" height=\"20\" " *
            "href=\"data:image/png;base64,", doc)
        # The embedded raster is the replay itself (codec-exact PNG).
        m = match(Regex("base64,([A-Za-z0-9+/=]+)\""), doc)
        @test m !== nothing
        embedded = decodePNG(Vetra._base64Decode(String(m.captures[1])))
        replayed = newImage(30, 20)
        drawPicture(replayed, pic)
        @test embedded.data == replayed.data
    end

    @testset "strict pre-scan errors (no file written)" begin
        counter = [0]

        function err_file()
            counter[1] += 1
            return joinpath(dir, "err-" * string(counter[1]) * ".svg")
        end

        function expectErr(build, msgPart)
            pic = record(20, 20, build)
            file = err_file()
            try
                writeSvg(file, pic)
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
        expectErr(scene_clear, "SVG op 2 (ClearOp)")

        handles = [Vec2(0f0, 0f0), Vec2(10f0, 0f0)]
        stops1 = [colorStop(rgba(0, 0, 255, 255), 0f0)]

        function scene_angular(c)
            ang = Paint(AngularGradientPaint)
            ang.gradientHandlePositions = [Vec2(10f0, 10f0),
                Vec2(10f0, 10f0), Vec2(16f0, 10f0)]
            ang.gradientStops = stops1
            c.fillStyle = ang
            fillRect(c, 0f0, 0f0, 20f0, 20f0)
            return nothing
        end
        expectErr(scene_angular, "angular gradients are not SVG-exportable")

        function scene_imagepaint(c)
            c.fillStyle = Paint(newImage(4, 4))
            fillRect(c, 0f0, 0f0, 20f0, 20f0)
            return nothing
        end
        expectErr(scene_imagepaint,
            "ImagePaint fills are not SVG-exportable")

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

        function scene_singular(c)
            setTransform(c, scale(Vec2(0f0, 1f0)))
            lin = Paint(LinearGradientPaint)
            lin.gradientHandlePositions = handles
            lin.gradientStops = stops1
            c.fillStyle = lin
            fillRect(c, 0f0, 0f0, 10f0, 10f0)
            return nothing
        end
        expectErr(scene_singular, "singular transform")

        function scene_coincident(c)
            lin = Paint(LinearGradientPaint)
            lin.gradientHandlePositions = [Vec2(5f0, 5f0),
                Vec2(5f0, 5f0)]
            lin.gradientStops = stops1
            c.fillStyle = lin
            fillRect(c, 0f0, 0f0, 20f0, 20f0)
            return nothing
        end
        expectErr(scene_coincident, "coincident handles")

        function scene_radialdeg(c)
            rad = Paint(RadialGradientPaint)
            rad.gradientHandlePositions = [Vec2(10f0, 10f0),
                Vec2(10f0, 10f0), Vec2(10f0, 16f0)]
            rad.gradientStops = stops1
            c.fillStyle = rad
            fillRect(c, 0f0, 0f0, 20f0, 20f0)
            return nothing
        end
        expectErr(scene_radialdeg, "center == edge")

        function scene_stop_high(c)
            lin = Paint(LinearGradientPaint)
            lin.gradientHandlePositions = handles
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
            lin.gradientHandlePositions = handles
            lin.gradientStops = [
                colorStop(rgba(255, 0, 0, 255), -0.2f0),
                colorStop(rgba(0, 0, 255, 255), 0.5f0)]
            c.fillStyle = lin
            fillRect(c, 0f0, 0f0, 20f0, 20f0)
            return nothing
        end
        expectErr(scene_stop_neg, "outside [0, 1]")

        function scene_stop_unsorted(c)
            lin = Paint(LinearGradientPaint)
            lin.gradientHandlePositions = handles
            lin.gradientStops = [
                colorStop(rgba(0, 0, 255, 255), 0.5f0),
                colorStop(rgba(255, 0, 0, 255), 0.2f0)]
            c.fillStyle = lin
            fillRect(c, 0f0, 0f0, 20f0, 20f0)
            return nothing
        end
        expectErr(scene_stop_unsorted, "non-decreasing")

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

    @testset "XML structural parse (independent)" begin
        function scene_xml(c)
            clipC = newPath()
            circle(clipC, 30f0, 30f0, 25f0)
            c.fillStyle = rgb(240, 240, 240)
            fillRect(c, 0f0, 0f0, 60f0, 60f0)
            clip(c, clipC)
            c.globalAlpha = 0.5f0
            c.fillStyle = rgb(255, 0, 0)
            fillRect(c, 10f0, 10f0, 10f0, 10f0)
            c.globalAlpha = 1f0
            c.strokeStyle = rgb(0, 255, 0)
            c.lineDash = Float32[2f0, 2f0]
            beginPath(c)
            moveTo(c, 0f0, 50f0)
            lineTo(c, 50f0, 50f0)
            stroke(c)
            return nothing
        end
        doc = writeSvg(joinpath(dir, "xml.svg"), record(60, 60,
            scene_xml))
        # The XML package's immediate Node tree (same shape the pinned
        # SVG reader consumes): `.tag`, `.attributes`, `.children`.
        XML = Vetra._requireXml()
        parsed = XML.parse(doc, XML.Node)
        root = nothing
        for ch in parsed.children
            ch.tag !== nothing && (root = ch; break)
        end
        @test root !== nothing
        @test String(root.tag) == "svg"
        attrs = Dict((String(k), String(v)) for (k, v) in root.attributes)
        @test attrs["width"] == "60"
        @test attrs["viewBox"] == "0 0 60 60"
        elements = [el for el in root.children if el.tag !== nothing]
        tags = [String(el.tag) for el in elements]
        @test tags == ["path", "g", "g"]
        # Every url(#id) reference resolves to an id in the document.
        ids = String[]
        refs = String[]

        function walk(el)
            a = el.attributes
            if a !== nothing
                for (k, v) in a
                    String(k) == "id" && push!(ids, String(v))
                    sv = String(v)
                    startswith(sv, "url(#") && push!(refs, sv[6:end - 1])
                end
            end
            ch = el.children
            if ch !== nothing
                for c in ch
                    c.tag !== nothing && walk(c)
                end
            end
            return nothing
        end
        walk(root)
        @test !isempty(refs)
        for r in refs
            @test r in ids
        end
    end

    @testset "read-back through the pinned Vetra SVG reader" begin
        # Identity transforms, opaque colors, no groups/clips: the
        # reader's linear-gradient + fill/stroke handling is exact for
        # this shape, so the read-back must equal the replay pixel for
        # pixel. (Reader deviations — gradient transform re-application,
        # clip-path and radialGradient skips, per-child group opacity —
        # are documented in tasks/T025-svg-export.md.)
        handles = [Vec2(0f0, 0f0), Vec2(100f0, 100f0)]
        stops = [
            colorStop(rgba(255, 0, 0, 255), 0f0),
            colorStop(rgba(0, 0, 255, 255), 1f0)]

        function scene_rb(c)
            c.fillStyle = rgb(250, 250, 250)
            fillRect(c, 0f0, 0f0, 100f0, 100f0)
            lin = Paint(LinearGradientPaint)
            lin.gradientHandlePositions = handles
            lin.gradientStops = stops
            c.fillStyle = lin
            fillRect(c, 10f0, 10f0, 80f0, 80f0)
            c.strokeStyle = rgb(1, 2, 3)
            c.lineWidth = 2f0
            beginPath(c)
            moveTo(c, 20f0, 20f0)
            lineTo(c, 80f0, 80f0)
            stroke(c)
            return nothing
        end
        file = joinpath(dir, "readback.svg")
        pic = record(100, 100, scene_rb)
        writeSvg(file, pic)
        svg = parseSvg(read(file, String))
        readback = newImage(svg)
        replayed = newImage(100, 100)
        drawPicture(replayed, pic)
        @test readback.data == replayed.data
    end

    @testset "chromium external render (pinned verifier)" begin
        # The Command is built in its own function: this build's parser
        # mis-handles backtick commands inside try blocks.
        function screenshot(chromium, svgf, pngf)
            # String command (no shell metacharacters; paths are ours):
            # this build mis-parses backtick command concatenations.
            # Single-line backtick: this build mis-parses backtick
            # concatenation across lines, and Base.popen is stripped.
            # ignorestatus: a nonzero chromium exit must not throw.
            cmd = `/usr/bin/timeout 60 $(chromium) --headless --no-sandbox --disable-gpu --hide-scrollbars --window-size=100,50 --screenshot=$(pngf) file://$(svgf)`
            Base.run(Base.ignorestatus(cmd))
            return true
        end

        function check_chromium(chromium)
            # Non-hidden home subdir: the snap chromium sandbox denied
            # hidden directories (ERR_ACCESS_DENIED). The directory name
            # is unique per process, so concurrent test runs that share
            # the home directory (separate worktrees) can no longer
            # delete each other's fixture files.
            workdir = mktempdir(homedir(); prefix = "vetra-svgtest-")
            try
                lin = Paint(LinearGradientPaint)
                lin.gradientHandlePositions = [Vec2(0f0, 0f0),
                    Vec2(100f0, 0f0)]
                lin.gradientStops = [
                    colorStop(rgba(0, 0, 255, 255), 0f0),
                    colorStop(rgba(0, 255, 0, 255), 1f0)]

                function scene_chrome(c)
                    # Opaque integer rects (no AA), a horizontal gradient
                    # (Vetra samples at integer x, chromium at pixel
                    # centers -> |dt| = 0.005 -> <= ~1.5/channel), and a
                    # dashed round-cap line (dash bodies exact; interior
                    # dash-end caps are drawn by the SVG spec / chromium
                    # but not by the pinned raster — a documented
                    # upstream quirk, recorded in the task file).
                    c.fillStyle = rgb(255, 0, 0)
                    fillRect(c, 10f0, 20f0, 30f0, 20f0)
                    c.fillStyle = lin
                    fillRect(c, 40f0, 10f0, 60f0, 30f0)
                    c.strokeStyle = rgb(1, 2, 3)
                    c.lineWidth = 2f0
                    c.lineCap = RoundCap
                    c.lineDash = Float32[3f0, 2f0]
                    beginPath(c)
                    moveTo(c, 5f0, 45f0)
                    lineTo(c, 95f0, 45f0)
                    stroke(c)
                    return nothing
                end

                pic = record(100, 50, scene_chrome)
                svgf = joinpath(workdir, "t025-chrome.svg")
                writeSvg(svgf, pic)
                pngf = joinpath(workdir, "t025-chrome.png")
                @test screenshot(chromium, svgf, pngf)
                @test isfile(pngf)
                shot = readImage(pngf)
                @test shot.width == 100 && shot.height == 50
                # Red rect interior: exact.
                for x in 12:39
                    @test getColor(shot, x, 22).r == 255
                    @test getColor(shot, x, 22).g == 0
                    @test getColor(shot, x, 22).b == 0
                end
                # Page background (transparent SVG over white): exact.
                @test getColor(shot, 3, 3) == rgbx(255, 255, 255, 255)
                # Gradient interior: within the justified sampling
                # tolerance (measured max 2 channels).
                replayed = newImage(100, 50)
                drawPicture(replayed, pic)
                for x in 45:95
                    v = getColor(replayed, x, 15)
                    s = getColor(shot, x, 15)
                    @test abs(Int(v.r) - Int(s.r)) <= 2
                    @test abs(Int(v.g) - Int(s.g)) <= 2
                    @test abs(Int(v.b) - Int(s.b)) <= 2
                end
                # Dashed line body (dash 1, x 0-based 10..12; row y=44
                # 0-based is fully covered): exact.
                for x in 11:13
                    @test getColor(shot, x, 45).r == 1
                    @test getColor(shot, x, 45).g == 2
                    @test getColor(shot, x, 45).b == 3
                end
            finally
                rm(workdir; recursive = true)
            end
            return nothing
        end

        chromium = "/usr/bin/chromium-browser"
        if !isfile(chromium)
            println("chromium not present; external render not checked")
        else
            check_chromium(chromium)
        end
    end

    @testset "no exponent notation in emitted numbers (E001)" begin
        # A radial gradient whose center-edge vector points in -x
        # (theta = pi) leaves Float32 sin residuals (~1e-6) in the
        # ellipse-map off-diagonals. The SVG 1.1 number grammar has no
        # exponent form, so the writer emits fixed-point decimals
        # (reproduction: Chromium-strict parsers reject `3.059797e-6`).
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
        doc = writeSvg(joinpath(dir, "residual.svg"),
            record(100, 60, scene_res))
        @test !occursin(r"[0-9][eE][+-]?[0-9]", doc)
        @test occursin("matrix(-30.0 -0.", doc)
    end

    rm(dir; recursive = true)
end
