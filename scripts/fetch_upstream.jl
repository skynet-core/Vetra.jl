# Downloads reference source only. Does not install Nim dependencies or run upstream code.
using TOML

function main()
    root = normpath(joinpath(@__DIR__, ".."))
    config = TOML.parsefile(joinpath(root, "upstream.toml"))
    repository = config["repository"]
    revision = config["revision"]
    checkout = joinpath(root, ".reference", "upstream")
    occursin(r"^[0-9a-f]{40}$", revision) || error("Expected a full upstream commit SHA.")
    git = Sys.which("git")
    isnothing(git) && error("Git must be installed and available on PATH.")

    if ispath(checkout) || islink(checkout)
        isdir(joinpath(checkout, ".git")) ||
            error("Existing reference directory is not a Git checkout: $checkout")
        origin = strip(read(`$git -C $checkout remote get-url origin`, String))
        origin == repository || error("Existing checkout has a different origin; left untouched.")
        head = strip(read(`$git -C $checkout rev-parse HEAD`, String))
        head == revision || error("Existing checkout is at $head, not $revision; left untouched.")
        dirty = read(`$git -C $checkout status --porcelain`, String)
        isempty(strip(dirty)) || error("Existing reference checkout has changes; left untouched.")
    else
        mkpath(dirname(checkout))
        run(`$git clone --filter=blob:none --no-checkout $repository $checkout`)
        run(`$git -C $checkout checkout --detach $revision`)
        head = strip(read(`$git -C $checkout rev-parse HEAD`, String))
        head == revision || error("Reference checkout did not resolve to the pinned revision.")
    end
    println("Reference source: ", checkout)
    println("Pinned revision:  ", revision)
    println("Read docs/UPSTREAM.md before installing dependencies or generating fixtures.")
end

main()
