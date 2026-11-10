@testset "Optional codecs after a core-only precompile" begin
    root = dirname(@__DIR__)
    project = dirname(Base.active_project())
    mktempdir() do depot
        # Isolate compiled caches while reusing the installed test dependencies.
        depots = join([depot; DEPOT_PATH], Sys.iswindows() ? ';' : ':')
        loadpath = Sys.iswindows() ? "@;@stdlib" : "@:@stdlib"
        core = """
            using Vetra
            for id in (Vetra._PNGFILES_PKGID, Vetra._JPEGTURBO_PKGID,
                    Vetra._XML_PKGID, Vetra._COLORTYPES_PKGID,
                    Vetra._WEBP_PKGID, Vetra._HB_PKGID)
                @assert Base.locate_package(id) === nothing
            end
            @assert width(newImage(2, 3)) == 2
            try
                encodePNG(newImage(2, 3))
                error("PNG should require its optional package")
            catch e
                @assert e isa ErrorException && occursin("PNG support is opt-in", e.msg)
            end
            try
                toColors(newImage(2, 3))
                error("color interop should require its optional package")
            catch e
                @assert e isa ErrorException &&
                    occursin("Color-matrix interop is opt-in", e.msg)
            end
            # T031: JPEG encoding shares the opt-in package + hint.
            try
                encodeJPEG(newImage(2, 3))
                error("JPEG encode should require its optional package")
            catch e
                @assert e isa ErrorException &&
                    occursin("JPEG support is opt-in", e.msg)
            end
            # T032: WebP read/write share the opt-in package + hint.
            try
                decodeWebP(UInt8[0x00])
                error("WebP decode should require its optional package")
            catch e
                @assert e isa ErrorException &&
                    occursin("WebP support is opt-in", e.msg)
            end
            try
                encodeWebP(newImage(2, 3))
                error("WebP encode should require its optional package")
            catch e
                @assert e isa ErrorException &&
                    occursin("WebP support is opt-in", e.msg)
            end
            # T029: RTL layout engages the opt-in shaper at layout time.
            tfHB = readTypeface($(repr(joinpath(root, "test", "fixtures",
                "NotoSansArabic-Regular.ttf"))))
            fHB = newFont(tfHB)
            try
                layoutParagraph(newParagraph("كتب", fHB;
                    dir = RightToLeft))
                error("shaping should require its optional package")
            catch e
                @assert e isa ErrorException &&
                    occursin("Shaping support is opt-in", e.msg)
            end
            # and shapeText itself names the missing provider
            try
                shapeText(tfHB, UInt32[0x0643])
                error("shapeText should require its optional package")
            catch e
                @assert e isa ErrorException &&
                    occursin("Shaping support is opt-in", e.msg)
            end
            # T016: display falls back to text in a core-only environment.
            @assert Base.showable(MIME("image/png"), newImage(2, 3)) === false
            @assert Base.showable(MIME("text/plain"), newImage(2, 3)) === true
            """
        codecs = """
            using Vetra
            image = newImage(2, 3)
            fill(image, rgb(10, 20, 30))
            @assert decodePNG(encodePNG(image)).data == image.data
            svg = newImage(parseSvg("<svg viewBox='0 0 2 3'><rect width='2' height='3' fill='#123456'/></svg>"))
            @assert width(svg) == 2 && height(svg) == 3
            jpeg = readImage($(repr(joinpath(root, ".reference", "upstream",
                "tests", "fileformats", "jpeg", "masters", "mandrill.jpg"))))
            @assert width(jpeg) > 0
            # T031: the encoder round-trips dimensions through the
            # existing decoder in the codec-enabled environment.
            @assert decodeJPEGDimensions(encodeJPEG(image)) == (2, 3)
            # T032: WebP round-trips in the codec-enabled environment —
            # losslessly byte-exact on opaque content.
            @assert decodeWebPDimensions(encodeWebP(image)) == (2, 3)
            @assert decodeWebP(encodeWebP(image; lossy = false)).data ==
                image.data
            # T029: the opt-in shaper works in the codec-enabled
            # environment — pinned reference gids for "كتب" (Arab, RTL)
            tfHB = readTypeface($(repr(joinpath(root, "test", "fixtures",
                "NotoSansArabic-Regular.ttf"))))
            out = shapeText(tfHB, UInt32[0x0643, 0x062a, 0x0628];
                script = 0x41726162, direction = RightToLeft,
                language = "ar")
            @assert [g.gid for cl in out for g in cl] == [424, 59, 36]
            @assert layoutParagraph(newParagraph("كتب", newFont(tfHB);
                dir = RightToLeft)).shaped[1] == [3, 2, 1]
            """
        for (env, code) in ((root, core), (project, codecs))
            cmd = `$(Base.julia_cmd()) --startup-file=no --project=$env -e $code`
            passed = success(pipeline(addenv(cmd, "JULIA_DEPOT_PATH" => depots,
                "JULIA_LOAD_PATH" => loadpath); stdout = stdout, stderr = stderr))
            @test passed
        end
    end
end
