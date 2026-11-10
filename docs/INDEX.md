# Vetra.jl documentation

The entry point to everything documented in this repository. Start with the
guide for your level; the [gallery](build/gallery.html) shows what the
recipes render.

## Navigation

Future architecture: [renderer-independent Canvas](CANVAS_DESIGN.md) and the
[parallel CPU/Vulkan/browser/document development plan](../tasks/CANVAS_ROADMAP.md).
These are design documents; the current implementation remains CPU-based.

| If you want to... | Go to |
| --- | --- |
| Install and draw a first image | [README](../README.md) quick start, then [Getting started](GETTING_STARTED.md) |
| Learn basics to advanced in one sitting | [GETTING_STARTED.md](GETTING_STARTED.md) (13 executable sections) |
| Build a complete candlestick project (axes, SVG, pixel checks) | [TUTORIAL.md](TUTORIAL.md) (the OHLC project) |
| Copy a small reproducible recipe (sparkline, gauge, KPI, candles, annotation, diagram, dashboard, social card) | [COOKBOOK](build/cookbook/COOKBOOK.md) — source: [docs/cookbook.jl](cookbook.jl) |
| See all rendered outputs | [build/gallery.html](build/gallery.html) (run the build command below first) |
| Look up the public API | [API.md](API.md) |
| Adopt snake_case names, `!` mutators and Image indexing | [MIGRATION.md](MIGRATION.md) |
| Check what is supported vs. upstream | [COMPATIBILITY.md](COMPATIBILITY.md) |
| Understand the rendering architecture | [ARCHITECTURE.md](ARCHITECTURE.md) |
| Read the numerical/rounding contract | [NUMERICAL_CONTRACT.md](NUMERICAL_CONTRACT.md) |
| See design decisions and their evidence | [DECISIONS.md](DECISIONS.md) |
| Trace provenance of the reference behavior | [UPSTREAM.md](UPSTREAM.md) |
| Browse the small per-format examples | [examples/README.md](../examples/README.md) |
| Run or read the benchmark harness | [benchmark/README.md](../benchmark/README.md) |
| Troubleshoot a symptom | [Getting started, section 13](GETTING_STARTED.md#13-quick-reference-and-troubleshooting) |

## Building the generated docs

From the repository root:

```sh
julia --startup-file=no --project=docs -e 'using Pkg; Pkg.develop(path="."); Pkg.instantiate()'
julia --startup-file=no --project=. scripts/fetch_upstream.jl
julia --startup-file=no --project=docs docs/make_tutorial.jl    # executed TUTORIAL.md/.ipynb
julia --startup-file=no --project=docs docs/make_cookbook.jl    # executed COOKBOOK.md/.ipynb + gallery
```

The third command builds the cookbook Markdown, the notebook, the named
recipe PNGs, and `docs/build/gallery.html` in one run. All generated files
live under `docs/build/` (gitignored); a clean checkout plus these commands
reproduces every gallery image. Fonts come from the pinned upstream
fixtures (Apache-licensed; see [NOTICE](../NOTICE)), so
`scripts/fetch_upstream.jl` is a prerequisite. The recipes run standalone:

```sh
julia --startup-file=no --project=docs docs/cookbook.jl
```

Publishing/hosting the site is out of scope here; see
[T019](../tasks/T019-registration-publication.md) in the roadmap.

## Reading order

1. [GETTING_STARTED.md](GETTING_STARTED.md) — the mental model and the first
   image.
2. [COOKBOOK](build/cookbook/COOKBOOK.md) — eight small patterns to copy.
3. [TUTORIAL.md](TUTORIAL.md) — one larger, complete project.
4. [API.md](API.md) and [COMPATIBILITY.md](COMPATIBILITY.md) — reference.
