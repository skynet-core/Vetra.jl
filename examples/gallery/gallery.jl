# Shared infrastructure for the examples/gallery/** programs (E001).
#
# Deliberately small: repository paths, the pinned font fixtures, provider
# availability with actionable setup hints, an output-directory helper and a
# check counter. The drawing scenes themselves live in the individual
# programs, which are import-safe: top-level `main` runs only when the
# program file is the entry script, never when it is included (tests,
# the batch runner).

module VetraGallery

using Vetra

export ROOT, FONT_PROVENANCE, ROBOTO, NOTO_SANS, NOTO_SANS_JP, ARABIC,
    PNG_ID, JPEG_ID, XML_ID, WEBP_ID, COLORTYPES_ID, HARBUFF_ID,
    available, require!, ensure_outdir, default_outdir, entry_script,
    is_entry, check, reset_checks, check_count, finish

# examples/gallery/gallery.jl -> repository root (two levels up).
const ROOT = normpath(joinpath(dirname(dirname(@__DIR__)), "."))

# Pinned font fixtures. Provenance: the upstream-pinned fixtures under
# .reference/upstream/tests/fonts (Apache-2.0 Roboto/Inter, Google Noto;
# see NOTICE) are fetched by scripts/fetch_upstream.jl; the OFL-1.1
# Noto Sans Arabic/Devanagari fixtures are pinned in test/fixtures/
# (T029, sha256 sidecars next to them).
const ROBOTO = joinpath(ROOT, ".reference", "upstream", "tests", "fonts",
    "Roboto-Regular_1.ttf")
const NOTO_SANS = joinpath(ROOT, ".reference", "upstream", "tests", "fonts",
    "NotoSans-Regular_4.ttf")
const NOTO_SANS_JP = joinpath(ROOT, ".reference", "upstream", "tests", "fonts",
    "NotoSansJP-Regular.ttf")
const ARABIC = joinpath(ROOT, "test", "fixtures", "NotoSansArabic-Regular.ttf")

const FONT_PROVENANCE = """
    Roboto-Regular_1.ttf, NotoSans-Regular_4.ttf, NotoSansJP-Regular.ttf:
    upstream-pinned fixtures (.reference/upstream, fetched by
    scripts/fetch_upstream.jl; Apache-2.0 / OFL, see NOTICE).
    NotoSansArabic-Regular.ttf: pinned OFL-1.1 fixture in test/fixtures/
    (sha256 sidecar; T029). No binary fonts are downloaded by the
    examples themselves."""

# Provider package IDs (D014/D028/D032/D033 lazy-loading protocol).
const PNG_ID = Vetra._PNGFILES_PKGID
const JPEG_ID = Vetra._JPEGTURBO_PKGID
const XML_ID = Vetra._XML_PKGID
const WEBP_ID = Vetra._WEBP_PKGID
const COLORTYPES_ID = Vetra._COLORTYPES_PKGID
const HARBUFF_ID = Vetra._HB_PKGID

"""True when the optional provider package is already available."""
available(id::Base.PkgId) = Base.locate_package(id) !== nothing

"""
Raise an actionable setup error when an optional provider is missing.
Providers are never auto-installed: the documented setup command builds
the isolated optional environment under examples/gallery/optional_env.
"""
function require!(id::Base.PkgId, name::String)
    available(id) && return nothing
    throw(ErrorException(
        "$name is not available in this environment (opt-in provider). " *
        "Set up the isolated example environment first, then re-run with " *
        "--project=examples/gallery/optional_env:\n  " *
        "julia --project=examples/gallery/optional_env -e 'using Pkg; " *
        "p = Base.active_project(); isfile(p) && (p = dirname(p)); " *
        "Pkg.develop(path=joinpath(dirname(p), \"..\", \"..\")); " *
        "Pkg.instantiate()'\n  " *
        "julia --project=examples/gallery/optional_env " *
        "<program.jl> [outdir]"))
end

"""
Ensure `dir` exists as a directory; raise if it is a file. Output is
caller-selected; inputs (fonts, fixtures) are never written.
"""
function ensure_outdir(dir::String)
    isfile(dir) && throw(ErrorException(
        "output directory $dir exists as a file"))
    mkpath(dir)
    return dir
end

"""Default output directory (gitignored artifacts/)."""
default_outdir() = ensure_outdir(joinpath(ROOT, "artifacts", "gallery"))

# ---------- import-safe entry guard ----------

"""Entry script path ("julia prog.jl"), or "" when julia ran without one
(-e, REPL, code included from another script). New builds expose
`JLOptions.program_file`, standard older ones `JLOptions.file`; the
frozen 1.10 build used by the CI gates exposes neither, so there we read
the process argv from `/proc/self/cmdline` and take the first existing
`.jl` argument."""
function entry_script()
    opts = Base.JLOptions()
    fs = fieldnames(typeof(opts))
    f = :program_file in fs ? :program_file :
        :file in fs ? :file : nothing
    f === nothing && return _procEntry()
    v = getfield(opts, f)
    v isa AbstractString && return v
    return v == Ptr{UInt8}(0) ? "" : unsafe_string(v)
end

"""Entry script from the process argv: the first existing `.jl` argument
(Linux; for the frozen 1.10 build where `JLOptions` has no entry field).
Note: no `try` around the field access — the frozen builds mis-scope
variables assigned inside `try` blocks."""
function _procEntry()
    Sys.islinux() || return ""
    raw = read("/proc/self/cmdline")
    args = String[]
    s = 1
    for (i, b) in enumerate(raw)
        if b == UInt8(0)
            i > s && push!(args, String(raw[s:i-1]))
            s = i + 1
        end
    end
    for a in args
        startswith(a, "-") && continue
        endswith(a, ".jl") && isfile(a) && return a
    end
    return ""
end

"""True when `file` is the script julia was started with."""
function is_entry(file::String)
    ef = entry_script()
    return !isempty(ef) && normpath(abspath(ef)) == normpath(abspath(file))
end

# ---------- check counter ----------

const _CHECKS = Ref{Int}(0)

"""
Assert-style check used by every program: counts the check and raises an
actionable ErrorException on failure (so a run either passes all of its
checks or reports the first failing one).
"""
function check(cond::Bool, msg::String)
    cond || throw(ErrorException("gallery check failed: " * msg))
    _CHECKS[] += 1
    return nothing
end

reset_checks() = (_CHECKS[] = 0)
check_count() = _CHECKS[]

"""
Print the per-program summary line and return true. Programs call this
last; the batch runner and the test suite use the printed contract.
"""
function finish(name::String, outdir::String)
    println("$(name): $(check_count()) checks passed; outputs in $outdir")
    return true
end

end # module
