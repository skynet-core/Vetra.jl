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

"""Include one gallery program into a fresh module (the frozen build
does not export `include`/`@__DIR__` from `import Base`, so `include`
gets a one-line shim that delegates to `Base.include(@__MODULE__, ...)`;
`@__DIR__` and `@__FILE__` are parser-level and work as-is)."""
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
