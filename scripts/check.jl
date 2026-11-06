using Pkg

VERSION >= v"1.10" || error("Vetra.jl requires Julia 1.10 or newer.")
root = normpath(joinpath(@__DIR__, ".."))
Pkg.activate(root)
Pkg.instantiate()
# Pkg.test throws a PkgError when the test run fails.
Pkg.test(; coverage=true, julia_args=["--startup-file=no", "--check-bounds=yes"])

# D009 coverage gate: line coverage strictly above 95% for code under src/.
# Parses Julia's built-in --code-coverage per-file output: <file>.jl.<id>.cov,
# one line per source line as `<7-wide hit count or '-'> <source>`
# ("-" = not measurable: comment, blank, or docstring). No extra package
# dependency is required.
srcdir = joinpath(root, "src")

function latest_cov_files(srcdir::String)
    bysrc = Dict{String, String}()
    for (dir, _, files) in walkdir(srcdir)
        for f in files
            m = match(r"^(.+\.jl)\.\d+\.cov$", f)
            isnothing(m) && continue
            src = joinpath(dir, String(m.captures[1]))
            isfile(src) || continue # stale .cov from a renamed/deleted file
            p = joinpath(dir, f)
            if !haskey(bysrc, src) || mtime(p) > mtime(bysrc[src])
                bysrc[src] = p
            end
        end
    end
    return values(bysrc)
end

function measurable_line_counts(files)
    covered = 0
    total = 0
    for f in files
        for line in eachline(open(f))
            m = match(r"^\s*(\d+|-)", line)
            isnothing(m) && continue
            m.captures[1] == "-" && continue  # not measurable
            total += 1
            if parse(Int, m.captures[1]) > 0
                covered += 1
            end
        end
    end
    return covered, total
end

covered, total = measurable_line_counts(latest_cov_files(srcdir))
if total == 0
    println("coverage gate: no measurable lines under src/ yet; gate vacuously satisfied")
else
    pct = 100.0 * covered / total
    println("coverage gate: src/ line coverage = $(round(pct, digits=2))% ($(covered)/$(total) measurable lines)")
    pct > 95.0 || error("coverage gate failed: src/ coverage $(round(pct, digits=2))% is not > 95%")
end
println("scripts/check.jl: OK")
