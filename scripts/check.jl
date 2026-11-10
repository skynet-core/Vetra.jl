using Pkg

VERSION >= v"1.10" || error("Vetra.jl requires Julia 1.10 or newer.")
root = normpath(joinpath(@__DIR__, ".."))
Pkg.activate(root)
Pkg.instantiate()

# D009 coverage gate: line coverage strictly above 95% for code under src/.
# Parses Julia's built-in --code-coverage per-file output: <file>.jl.<id>.cov,
# one line per source line as `<7-wide hit count or '-'> <source>`
# ("-" = not measurable: comment, blank, or docstring). No extra package
# dependency is required.
#
# Coverage is fresh-run-only (M002): every coverage artifact under src/
# is removed before the test run, so the gate can never read data from a
# previous run; after the run, every src/ Julia file (each one is
# `include`d by src/Vetra.jl, so a loaded package covers them all) must
# have produced a .cov. Missing coverage or zero measurable lines is a
# hard failure, never a silent exclusion. (Allocation-profile `.mem`
# files are unrelated to coverage and are left untouched.)
srcdir = joinpath(root, "src")

function coverage_artifacts(srcdir::String)
    out = String[]
    for (dir, _, files) in walkdir(srcdir)
        for f in files
            match(r"^.*\.jl(\.\d+)?\.cov$", f) !== nothing &&
                push!(out, joinpath(dir, f))
        end
    end
    return out
end

for p in coverage_artifacts(srcdir)
    rm(p)
end

# Pkg.test throws a PkgError when the test run fails.
Pkg.test(; coverage=true, julia_args=["--startup-file=no", "--check-bounds=yes"])

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
    return bysrc
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

covfiles = latest_cov_files(srcdir)

srcfiles = String[]
for (dir, _, files) in walkdir(srcdir)
    for f in files
        endswith(f, ".jl") && push!(srcfiles, joinpath(dir, f))
    end
end
missing_cov = sort([s for s in srcfiles if !haskey(covfiles, s)])
!isempty(missing_cov) &&
    error("coverage gate failed: no fresh coverage for: ",
        join(missing_cov, ", "))

covered, total = measurable_line_counts(values(covfiles))
if total == 0
    error("coverage gate failed: no measurable lines under src/")
else
    pct = 100.0 * covered / total
    println("coverage gate: src/ line coverage = $(round(pct, digits=2))% ($(covered)/$(total) measurable lines)")
    pct > 95.0 || error("coverage gate failed: src/ coverage $(round(pct, digits=2))% is not > 95%")
end
println("scripts/check.jl: OK")
