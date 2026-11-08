# Executable OHLC chart tutorial

New to the drawing API? Start with the [basics-to-advanced Markdown guide](GETTING_STARTED.md)
for shapes, gradients, text, clipping, images, PNG export, layers, and blending.

Draw a 24-hour crypto candlestick (OHLC) chart with Vetra, render it to
PNG, then build a small SVG backend step by step and prove the result by
reading the SVG back through the library's own parser.

The full tutorial lives in **[tutorial.jl](tutorial.jl)**, a
[Literate.jl](https://fredrikekre.github.io/Literate.jl/) source file. Its
prose becomes Markdown and its Julia blocks become executable notebook
cells. Both generated formats include the results and inline chart images.

## Setup

From the repository root, with Julia 1.10+ and Git installed:

```sh
julia --startup-file=no --project=docs -e 'using Pkg; Pkg.develop(path="."); Pkg.instantiate()'
julia --startup-file=no --project=. scripts/fetch_upstream.jl
```

The separate `docs/Project.toml` environment contains Literate, IJulia,
Vetra, and the optional codec packages. `Pkg.develop` selects this
checkout; no registration is required. The fetch supplies the Roboto font
used for axis labels; see [NOTICE](../NOTICE) for its provenance.

## Generate and execute both formats

```sh
julia --startup-file=no --project=docs docs/make_tutorial.jl
```

This executes every code cell and assertion **for each format** and stops
on errors. Generated files:

- [Executed Markdown](build/tutorial/TUTORIAL.md), with PNG sidecars in
  the same directory. Open it in any Markdown previewer.
- [Jupyter notebook](build/tutorial/TUTORIAL.ipynb), with outputs and
  images embedded in the file.

The links work after building locally. `docs/build/` is gitignored; ship
the Markdown together with its PNG sidecars, or the single notebook as a
portable view with saved outputs. Interactive reruns need the checkout,
its documentation environment, and the fetched font.

Markdown itself is static: rebuilding executes its code and refreshes the
results in place. Notebook cells can be edited and run interactively.
Generation uses Literate's executor and does not require a running Jupyter
server.

## Run interactively in Jupyter

From the repository root:

```sh
julia --startup-file=no --project=docs -e 'using IJulia; notebook(dir="docs/build/tutorial")'
```

IJulia uses an existing Jupyter installation or offers to install one.
Open `TUTORIAL.ipynb`, pick the Julia kernel, then **Restart Kernel and
Run All**. The default kernel runs with `--project=@.`; with the notebook
inside `docs/build/tutorial/` it finds the parent `docs/Project.toml`, so
keep it there for interactive runs.

Cells share drawing state; run them top to bottom. Results appear under
each cell, and image exports go to `artifacts/tutorial/`. The source
locates the checkout via `pathof(Vetra)`, so file writes do not depend on
the kernel's working directory.

To run the same examples as a plain Julia script:

```sh
julia --startup-file=no --project=docs docs/tutorial.jl
```

## Edit and rebuild

Edit **`docs/tutorial.jl`**, never the generated files:

- Lines starting with `# ` are prose.
- Plain Julia lines are executable code.
- `##` starts a comment that stays inside the rendered code block.
- A closing bare `Image` expression in a cell gives it a PNG display in
  both formats (Vetra's built-in `show` methods, T016).

Rerun `docs/make_tutorial.jl` afterwards; it overwrites both generated
outputs. The benchmark and full-suite commands in section 12 remain shell
recipes — generating the tutorial does not launch them.

## Verification

Verified on Julia 1.13.3 with Literate 2.21.0 and IJulia 1.34.4:

- Literate executed both formats end to end: all code cells, all
  assertions, and the PNG displays completed.
- The generated notebook was independently re-executed through the IJulia
  kernel (Jupyter `nbclient`), with no error outputs.

For environment errors, rerun the setup commands; for a missing font, run
`scripts/fetch_upstream.jl`; for a notebook on the wrong environment, check
`Base.active_project()` in the kernel — it should point at
`docs/Project.toml`.

## Next

- Copy a single finished pattern (sparkline, gauge, KPI card, candles,
  annotation, diagram, dashboard, social card) from the
  [cookbook](cookbook.jl); its rendered previews are in
  [INDEX.md](INDEX.md) → [gallery](build/gallery.html).
- The full documentation map is in [INDEX.md](INDEX.md).
