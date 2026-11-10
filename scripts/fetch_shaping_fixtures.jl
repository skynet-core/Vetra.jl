# Downloads the T029 shaping test fonts into test/fixtures/ (URL + SHA256
# pinned). Tests never download; this script is the one-time fetch.
#
# Usage: julia --startup-file=no --project=. scripts/fetch_shaping_fixtures.jl

const FIXTURES = joinpath(@__DIR__, "..", "test", "fixtures")

const PINNED = [
    (
        "NotoSansArabic-Regular.ttf",
        "https://github.com/googlefonts/noto-fonts/raw/main/archive/hinted/NotoSansArabic/NotoSansArabic-Regular.ttf",
        "7ff958cd705f9e56a9e2755b9405dbb45b52cdd8a387a2bb2050083b0e488830",
    ),
    (
        "NotoSansDevanagari-Regular.ttf",
        "https://github.com/googlefonts/noto-fonts/raw/main/archive/hinted/NotoSansDevanagari/NotoSansDevanagari-Regular.ttf",
        "71f9677a5234afe51b39240b7b0f3478b8f818c5f912413609aeb904322a2855",
    ),
]

using SHA

function hexdigest(d::AbstractVector{UInt8})
    const HEXD = "0123456789abcdef"
    s = String[]
    for b in d
        push!(s, HEXD[1 + (Int(b) >> 4)] * HEXD[1 + (Int(b) & 0x0f)])
    end
    return join(s)
end

function main()
    mkpath(FIXTURES)
    for (name, url, want) in PINNED
        path = joinpath(FIXTURES, name)
        sidecar = path * ".sha256"
        if isfile(path) && hexdigest(sha256(read(path))) == want
            println("ok (unchanged):  ", name)
            continue
        end
        println("fetching: ", url)
        buf = IOBuffer()
        run(pipeline(`curl -sL --fail -o - $url`; stdout = buf))
        seekstart(buf)
        data = read(buf, String)
        data = Vector{UInt8}(data)
        got = hexdigest(sha256(data))
        got == want ||
            error("$name: sha256 $got != pinned $want — left untouched.")
        write(path, data)
        write(sidecar, got * "  " * name * "\n")
        println("pinned: ", name, " (", length(data), " bytes)")
    end
end

main()
