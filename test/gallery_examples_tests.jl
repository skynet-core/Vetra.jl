# E001: feature gallery examples (examples/gallery/**).
#
# The programs carry their own hand-derived/pinned assertions; this file
# tests the harness contract around them:
# - import safety: including a program defines its API and renders and
#   writes nothing (the entry guard);
# - end-to-end: each program's run(outdir) succeeds in this (optional)
#   environment and produces its documented artifacts;
# - core-only: each program re-runs in an isolated subprocess (scratch
#   depot + JULIA_LOAD_PATH=@:@stdlib + --project = repository root, the
#   pattern pinned by codec_loading_tests.jl) where the optional
#   providers are absent, so the programs' core-only branches (named
#   install hints, no optional artifacts) must hold end to end.

const GALLERY_PROGRAMS = [
    "drawing_atlas", "plot_dashboard", "typography", "image_lab",
    "recording_reuse", "export_policies"]

"""Include one gallery program into a fresh module. Ordinary Julia
module semantics: a bare `Module(...)` does not inherit Base imports,
so the `include` call at the top of every program would not resolve;
the one-line shim binds it to `Base.include(@__MODULE__, ...)`.
`@__DIR__` and `@__FILE__` are parser-level and work as-is."""
function import_program(name::String, path::String)
    mod = Module(Symbol("gallery_" * name))
    Core.eval(mod, :(import Base))
    Core.eval(mod, :(include(p::AbstractString) =
        Base.include(@__MODULE__, p)))
    return Base.include(mod, path), mod
end

@testset "E001 feature gallery examples" begin
    root = dirname(@__DIR__)
    gallery = joinpath(root, "examples", "gallery")

    @testset "import safety: include defines the API, renders nothing" begin
        gallery_files = Set(readdir(gallery))
        default_outdir_existed =
            isdir(joinpath(root, "artifacts", "gallery"))
        for name in GALLERY_PROGRAMS
            _, mod = import_program(name, joinpath(gallery, name * ".jl"))
            @test isdefined(mod, :run)
            @test isdefined(mod, :main)
        end
        @test Set(readdir(gallery)) == gallery_files
        @test isdir(joinpath(root, "artifacts", "gallery")) ==
            default_outdir_existed
    end

    @testset "entry guard: real CLI / include / -e invocations" begin
        # The guard is Base.PROGRAM_FILE (entry path; "" for -e, REPL
        # and included code). Each mode is verified with a real process
        # invocation (not an in-process emulation). Paths reach the
        # child as command-line arguments or repr-quoted literals —
        # never interpolated raw into generated Julia source, where
        # backslashes would become escapes on Windows.
        prog = joinpath(gallery, "plot_dashboard.jl")
        mktempdir() do dir
            # CLI: the program is the entry script -> main runs
            out1 = joinpath(dir, "cli")
            cmd = `$(Base.julia_cmd()) --startup-file=no --project=$(root) $(prog) $(out1)`
            @test success(pipeline(cmd; stdout = stderr, stderr = stderr))
            @test isfile(joinpath(out1, "plot_dashboard.bmp"))
            # include from a driver script: not the entry -> no render
            # at include time; the explicit run() still works
            drv = joinpath(dir, "driver.jl")
            out2 = joinpath(dir, "include")
            open(drv, "w") do f
                println(f, "include(", repr(prog), ")")
                println(f, "if VetraGallery.is_entry(", repr(prog), ")")
                println(f, "    error(\"entry guard false positive\")")
                println(f, "end")
                println(f, "run(", repr(out2), ")")
            end
            cmd2 = `$(Base.julia_cmd()) --startup-file=no --project=$(root) $(drv)`
            @test success(pipeline(cmd2; stdout = stderr, stderr = stderr))
            @test isfile(joinpath(out2, "plot_dashboard.bmp"))
            # -e with existing .jl paths in ARGS: arguments, not the
            # entry (PROGRAM_FILE == ""); the paths are passed via
            # ARGS, not embedded in the -e source
            cmd3 = `$(Base.julia_cmd()) --startup-file=no --project=$(root)
                -e "include(ARGS[1]); @assert Base.PROGRAM_FILE == \"\"; @assert !VetraGallery.is_entry(ARGS[2])"
                $(joinpath(gallery, "gallery.jl")) $(prog)`
            @test success(pipeline(cmd3; stdout = stderr, stderr = stderr))
        end
    end

    @testset "end-to-end runs (optional-provider environment)" begin
        dir = mktempdir()
        try
            artifacts = Dict(
                "drawing_atlas" => ["drawing_atlas.bmp", "drawing_atlas.svg",
                    "drawing_atlas.pdf"],
                "plot_dashboard" => ["plot_dashboard.bmp",
                    "plot_dashboard.svg", "plot_dashboard.pdf"],
                "typography" => ["typography.bmp", "typography.svg",
                    "typography.pdf"],
                "image_lab" => ["image_lab.bmp", "image_lab.png",
                    "image_lab.jpg", "image_lab.webp"],
                "recording_reuse" => ["recording_reuse_480.bmp",
                    "recording_reuse_960.bmp", "recording_reuse.pdf",
                    "recording_reuse.svg"],
                "export_policies" => ["export_policies.svg",
                    "export_policies.pdf", "export_policies_fb.pdf",
                    "export_policies_fb.svg",
                    "export_policies_evenodd.svg"])
            for name in GALLERY_PROGRAMS
                @testset "$name" begin
                    _, mod = import_program(name, joinpath(gallery, name * ".jl"))
                    out = joinpath(dir, name)
                    mod.run(out)
                    for f in artifacts[name]
                        @test isfile(joinpath(out, f))
                    end
                end
            end
        finally
            rm(dir; recursive = true)
        end
    end

    @testset "core-only subprocess legs (optional providers absent)" begin
        mktempdir() do depot
            depots = join([depot; DEPOT_PATH], Sys.iswindows() ? ';' : ':')
            loadpath = Sys.iswindows() ? "@;@stdlib" : "@:@stdlib"
            # Preflight in the identical isolated environment: none of
            # the six optional providers may be locatable (same
            # assertion pattern as codec_loading_tests.jl). If a
            # polluted root Manifest/depot makes one present, this
            # fails honestly instead of labeling an optional run
            # "core-only". The preflight is a generated script (no
            # paths, no -e quoting) run under the identical env.
            pre_script = joinpath(depot, "core_env_preflight.jl")
            open(pre_script, "w") do f
                write(f,
                    "using Vetra\n" *
                    "ids = (Vetra._PNGFILES_PKGID, Vetra._JPEGTURBO_PKGID,\n" *
                    "    Vetra._XML_PKGID, Vetra._COLORTYPES_PKGID,\n" *
                    "    Vetra._WEBP_PKGID, Vetra._HB_PKGID)\n" *
                    "bad = [string(id.name) for id in ids if\n" *
                    "    Base.locate_package(id) !== nothing]\n" *
                    "isempty(bad) || error(\"core-only environment not core-only: \" *\n" *
                    "    \"optional provider locatable: \" * join(bad, \", \"))\n" *
                    "println(\"core-only preflight: all 6 providers absent\")\n")
            end
            pre = `$(Base.julia_cmd()) --startup-file=no --project=$(root) $(pre_script)`
            @test success(pipeline(addenv(pre, "JULIA_DEPOT_PATH" => depots,
                    "JULIA_LOAD_PATH" => loadpath);
                stdout = stderr, stderr = stderr))
            for name in GALLERY_PROGRAMS
                @testset "$name" begin
                    out = joinpath(depot, name)
                    mkdir(out)
                    cmd = `$(Base.julia_cmd()) --startup-file=no --project=$(root) $(joinpath(gallery, name * ".jl")) $(out)`
                    passed = success(pipeline(
                        addenv(cmd, "JULIA_DEPOT_PATH" => depots,
                            "JULIA_LOAD_PATH" => loadpath);
                        stdout = stderr, stderr = stderr))
                    @test passed
                    core_artifact = name === "recording_reuse" ?
                        "recording_reuse_480.bmp" :
                        name === "export_policies" ?
                        "export_policies.pdf" : name * ".bmp"
                    @test isfile(joinpath(out, core_artifact))
                    # the core-only leg must not produce optional artifacts
                    for f in ["$(name).png", "$(name).jpg", "$(name).webp"]
                        @test !isfile(joinpath(out, f))
                    end
                end
            end
        end
    end

    @testset "batch runner CLI" begin
        dir = mktempdir()
        try
            cmd = `$(Base.julia_cmd()) --startup-file=no --project=$(root) $(joinpath(gallery, "run_gallery.jl")) $(dir)`
            passed = success(pipeline(cmd; stdout = stderr, stderr = stderr))
            @test passed
            for name in GALLERY_PROGRAMS
                @test isdir(joinpath(dir, name))
            end
        finally
            rm(dir; recursive = true)
        end
    end
end
