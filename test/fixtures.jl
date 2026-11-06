# test/fixtures.jl
#
# Reference fixture reader and pixel comparison helpers (T001).
# Pure Julia standard library (SHA is part of the distribution); no package
# dependencies. Reads the approved fixtures in test/reference/ and provides
# the mismatch reporting required by test/README.md.

module VetraRef

using SHA

const REF = joinpath(@__DIR__, "reference")
const META_LINE = r"^([A-Za-z_0-9]+)="

const HEXD = "0123456789abcdef"

"""Lowercase hex of a byte vector (no Base.lowerhex on this build)."""
function hexdigest(d::AbstractVector{UInt8})
    s = String[]
    for b in d
        push!(s, HEXD[1 + (Int(b) >> 4)] * HEXD[1 + (Int(b) & 0x0f)])
    end
    return join(s)
end

function error_missing(tag::String, ext::String)
    error("missing reference fixture: $(joinpath(REF, tag * ext))\n" *
        "Regenerate with `sh tools/oracle/build.sh all` and copy approved " *
        "outputs to test/reference/ (see test/README.md).")
end

"""Parse `key=value` meta lines from the start of a fixture file."""
function parse_meta(lines)
    meta = Dict{String,String}()
    i = 1
    n = length(lines)
    n > 0 || error("empty fixture file")
    while i <= n
        m = match(META_LINE, lines[i])
        isnothing(m) && break
        meta[m.captures[1]] = strip(lines[i][length(m.match) + 1 : end])
        i += 1
    end
    return meta, i  # i = index of the first non-meta line (header/first row)
end

function load_meta(tag::String)
    p = joinpath(REF, tag * ".meta")
    isfile(p) || error_missing(tag, ".meta")
    meta, _ = parse_meta(readlines(p))
    return meta
end

"""Read a canonical raw pixel buffer plus (width, height) from `.meta`."""
function read_raw(tag::String)
    meta = load_meta(tag)
    p = joinpath(REF, tag * ".raw")
    isfile(p) || error_missing(tag, ".raw")
    data = read(p)
    w = parse(Int, meta["width"])
    h = parse(Int, meta["height"])
    (w > 0 && h > 0) || error("$(tag).meta declares bad dimensions $(w)x$(h)")
    n = 4 * w * h
    length(data) == n ||
        error("$(tag).raw is $(length(data)) bytes; expected $n (w*h*4)")
    return data, (w, h)
end

"""SHA-256 of the `.raw` buffer must equal `sha256_raw` recorded in `.meta`."""
function verify_checksum(tag::String)
    meta = load_meta(tag)
    p = joinpath(REF, tag * ".raw")
    isfile(p) || error_missing(tag, ".raw")
    hexdigest(sha256(read(p))) == meta["sha256_raw"]
end

"""Read a `.tsv` table: meta header, column names, and data rows."""
function read_table(tag::String)
    p = joinpath(REF, tag * ".tsv")
    isfile(p) || error_missing(tag, ".tsv")
    lines = readlines(p)
    meta, i = parse_meta(lines)
    i > length(lines) && error("no header row in $(tag).tsv")
    cols = split(lines[i], ",")
    rows = [
        split(line, ",") for line in lines[i + 1:end] if !isempty(strip(line))
    ]
    return meta, cols, rows
end

"""1-based pixel (r, g, b, a) at (x, y); channel order follows the contract."""
function pixel(data::AbstractVector{UInt8}, wh::NTuple{2,Int}, x::Int, y::Int)
    w, h = wh
    (1 <= x <= w && 1 <= y <= h) ||
        throw(BoundsError("pixel ($x, $y) outside $(w)×$(h)"))
    base = ((y - 1) * w + (x - 1)) * 4
    return (data[base + 1], data[base + 2], data[base + 3], data[base + 4])
end

struct Mismatch
    """(x, y, channel) of the first differing pixel, 1-based; channel 1=R, 4=A."""
    first_coord::NTuple{3,Int}
    """Number of differing bytes (0 means the buffers are equal)."""
    count::Int
    """Maximum absolute channel difference (0 means equal)."""
    max_abs::Int
end

"""
Compare two canonical pixel buffers of the same (w, h).
Throws ArgumentError on structural (length/dimension) mismatches.
"""
function compare_pixels(
    actual::AbstractVector{UInt8},
    expected::AbstractVector{UInt8},
    wh::NTuple{2,Int}
)
    w, h = wh
    (w > 0 && h > 0) || throw(ArgumentError("dimensions must be > 0"))
    n = 4 * w * h
    length(actual) == n || throw(ArgumentError("actual has $(length(actual)) bytes, expected $n"))
    length(expected) == n || throw(ArgumentError("expected has $(length(expected)) bytes, expected $n"))

    first = nothing
    count = 0
    maxabs = 0
    for i in 1:n
        a = actual[i]
        e = expected[i]
        if a != e
            count += 1
            d = abs(Int(a) - Int(e))
            maxabs = max(maxabs, d)
            if first === nothing
                i0 = i - 1
                first = ((i0 % (4 * w)) ÷ 4 + 1, i0 ÷ (4 * w) + 1, i0 % 4 + 1)
            end
        end
    end
    return Mismatch(isnothing(first) ? (0, 0, 0) : first, count, maxabs)
end

end # module VetraRef
