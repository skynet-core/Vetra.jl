using Literate

source = joinpath(@__DIR__, "tutorial.jl")
output = joinpath(@__DIR__, "build", "tutorial")

Literate.markdown(source, output;
    name = "TUTORIAL", flavor = Literate.CommonMarkFlavor(), execute = true)
Literate.notebook(source, output; name = "TUTORIAL", execute = true)

println("Executed Markdown and notebook written to ", output)
