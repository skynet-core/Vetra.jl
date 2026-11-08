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
                    Vetra._XML_PKGID, Vetra._COLORTYPES_PKGID)
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
            """
        for (env, code) in ((root, core), (project, codecs))
            cmd = `$(Base.julia_cmd()) --startup-file=no --project=$env -e $code`
            passed = success(pipeline(addenv(cmd, "JULIA_DEPOT_PATH" => depots,
                "JULIA_LOAD_PATH" => loadpath); stdout = stdout, stderr = stderr))
            @test passed
        end
    end
end
