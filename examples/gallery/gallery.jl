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
    available, require!, require_fonts, ensure_outdir, default_outdir,
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

# The pinned inputs every program reads (fonts + the GIF fixture). The
# .reference checkout is gitignored and fetched explicitly; the
# test/fixtures files are committed.
const PINNED_INPUTS = (ROBOTO,
    joinpath(ROOT, "test", "fixtures", "NotoSansArabic-Regular.ttf"),
    joinpath(ROOT, "test", "fixtures", "NotoSansDevanagari-Regular.ttf"),
    joinpath(ROOT, ".reference", "upstream", "tests", "fileformats",
        "gif", "3x5.gif"))

"""Verify the pinned inputs exist; raise with the fetch command when the
.git-ignored `.reference` checkout (or a committed fixture) is missing,
so a fresh clone gets an actionable message instead of a SystemError."""
function require_fonts()
    missing = String[]
    for p in PINNED_INPUTS
        isfile(p) || push!(missing, p)
    end
    isempty(missing) && return nothing
    throw(ErrorException(
        "Missing pinned example inputs: " * join(missing, ", ") * ". " *
        "The .reference checkout (fonts, file-format fixtures) is " *
        "gitignored; fetch it first, from the repository root:\n  " *
        "julia --project=. scripts/fetch_upstream.jl\n  " *
        "(provenance: docs/UPSTREAM.md, upstream.toml). The " *
        "test/fixtures Noto files are committed with sha256 sidecars."))
end

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
        "Set up the isolated example environment first, from the " *
        "repository root:\n  " *
        "julia --project=examples/gallery/optional_env -e 'using Pkg; " *
        "Pkg.develop(path = \".\"); Pkg.instantiate()'\n  " *
        "then re-run with --project=examples/gallery/optional_env " *
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

"""Default output directory (gitignored artifacts/). Pure path helper —
no side effects; the caller's outdir is parsed before anything is
created (run() calls ensure_outdir)."""
default_outdir() = joinpath(ROOT, "artifacts", "gallery")

# ---------- import-safe entry guard ----------

"""True when `file` is the script julia was started with.
`Base.PROGRAM_FILE` is the entry path for `julia prog.jl` and "" for
`-e`, REPL and code included from another script — including `-e` with
an existing `.jl` path in `ARGS`, which is an argument, not the entry.
Verified on both gate Julia versions (1.10.13 and 1.13.3)."""
function is_entry(file::String)
    pf = Base.PROGRAM_FILE
    return !isempty(pf) && normpath(abspath(pf)) == normpath(abspath(file))
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
