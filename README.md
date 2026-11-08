# Vetra.jl

A native Julia port of [treeform/pixie](https://github.com/treeform/pixie) —
a fast 2D CPU rasterizer with an immediate-mode context API (transforms,
clips, layers, dashes, gradients, text). The port tracks the pinned upstream
revision recorded in `upstream.toml`; behavior (including upstream quirks)
is the reference contract, not "what looks nicer".

**Status: feature-complete vs the pinned upstream subset** (T000–T010).
What is supported and what is deliberately not:
[docs/COMPATIBILITY.md](docs/COMPATIBILITY.md) (per-symbol matrix with test
evidence), [docs/API.md](docs/API.md) (the port's API),
[docs/NUMERICAL_CONTRACT.md](docs/NUMERICAL_CONTRACT.md) (scalar Float32
arithmetic contract).

## Quick start

**New to Vetra?** Start with the [beginner Markdown guide](docs/GETTING_STARTED.md):
draw an activity card while learning shapes, gradients, text, clipping,
image compositing, and PNG export. Continue to curves, fill rules, layers,
blend modes, SVG import, and reusable drawing functions. Its code blocks run
in order in one session, with exercises and troubleshooting along the way.

Then follow the [hands-on chart tutorial](docs/TUTORIAL.md): draw a
crypto OHLC candlestick chart step by step, render it to PNG, and build a
small SVG backend. Executed Markdown and a Jupyter notebook with inline
images generate from one Literate.jl source.

For copy-paste patterns (sparkline, gauge, KPI card, candlesticks, image
annotation, scientific diagram, dashboard thumbnail, social card), use the
[cookbook](docs/cookbook.jl) and its rendered
[gallery](docs/build/gallery.html). All documentation entry points are
listed in [docs/INDEX.md](docs/INDEX.md).

Requires Julia **1.10+** (developed and tested on 1.10 and 1.13). The
package is not yet registered (see docs/HANDOFF.md), so add it from a
checkout:

```sh
julia -e 'using Pkg; Pkg.add(path="/path/to/Vetra.jl")'
```

For the opt-in codecs (PNG/JPEG/SVG), add their packages to your application
environment before loading Vetra. Available codecs are loaded at runtime,
including when Vetra reuses a cache built without them:

```sh
julia -e 'using Pkg; Pkg.activate("/path/to/myenv", shared=true);
           Pkg.add(path="/path/to/Vetra.jl");
           Pkg.add(["PNGFiles", "JpegTurbo", "XML"])'
```

```julia
using Vetra

img = newImage(320, 240)          # premultiplied RGBA, 1-based pixels
fill(img, rgb(245, 244, 250))     # straight colors via rgb/rgba/rgbx

ctx = Context(img)                # all context drawing mutates ctx.image
ctx.fillStyle = "#FF5C00"
fillRect(ctx, 12, 12, 90, 60)     # ordinary numbers work; Float32 inside
translate(ctx, 10, 40)
rotate(ctx, 0.3)
ctx.strokeStyle = rgb(0, 128, 255)
ctx.lineWidth = 4
strokeRect(ctx, 0, 0, 60, 60)

ctx.font = "path/to/Roboto-Regular.ttf"  # a TTF/glyf font path (see below)
ctx.fontSize = 24
fillText(ctx, "Hello, Vetra", 12, 120)

writeFile(img, "out.png")         # PNG/BMP/QOI/PPM write; magic-byte read
```

A guided tour of the whole API (all of the above plus paths, gradients,
layers, effects, formats and text, verified run-clean):
`julia examples/showcase.jl out.png` — sections 1-7 and 9 need no extra
packages; section 8 (PNG/JPEG/SVG) needs the opt-in packages below. The
in-repo examples default to fonts/files under `.reference/` (the pinned
upstream checkout; `scripts/fetch_upstream.jl` re-creates it if missing).

## Opt-in codec packages

PNG, JPEG (decode) and SVG (parse) are backed by well-supported Julia
packages that are **extras, not hard dependencies** — the renderer core
loads without them, and each format raises an install hint on first use
(decision D014):

```julia
Pkg.add("PNGFiles")    # PNG read/write
Pkg.add("JpegTurbo")   # JPEG decode
Pkg.add("XML")         # SVG parse
```

BMP, QOI, GIF (decode-only), PPM and base64 are native ports with no
dependencies. WebP is not supported (upstream parity; raises
`ArgumentError("Unsupported file format")`).

## Fonts

Text uses a native OpenType subset port (decision D015): single-face
TTF/glyf fonts (cmap 4/12, `kern` v0 + GPOS pair-position, simple +
composite glyphs). CFF-outline fonts, TTC collections and SVG fonts raise
`ArgumentError` by design. `ctx.font` takes a font file path and is cached
per path; `readTypeface`/`parseTtf` load directly from bytes.

## Color-matrix interop (opt-in ColorTypes)

Exchange images with the standard Julia color-matrix ecosystem
(decision D024): `toColors(img)` returns a `Matrix{RGBA{N0f8}}` of
straight-alpha colors (`[row, col]`, row 1 = top), and `fromColors(m)`
imports a 2-D matrix of `RGB`/`RGBA` colors (N0f8 bytes or 0..1 floats,
clamped) as a premultiplied `Image`. Both use the same boundary
conversions as PNG export/decode, so matrix bytes equal PNG payload
bytes. `Pkg.add("ColorTypes")` enables it; the core loads without it.

## Tests and coverage

```sh
julia --startup-file=no --project=. -e 'using Pkg; Pkg.test()'
julia --startup-file=no --project=. scripts/check.jl   # tests + >95% coverage gate
```

The suite contains ~811k assertions, including byte-exact comparisons
against pinned upstream oracle fixtures (`test/reference/`, generated by
`tools/oracle/build.sh` with the pinned Nim toolchain) and upstream test
values.

## Benchmarks

`benchmark/run_benchmarks.jl` (Julia) and `benchmark/bench_reference.nim`
(pinned upstream, same workloads) measure fill, stroke, blur/shadow, draw,
PNG encode/decode and text metrics — first call, warm-up and steady state
separated. Results land in `benchmark/results/`. T012 (2026-11-06)
optimized the renderer per Julia's performance-tips manual; the pinned
scalar Nim reference is the comparison target (recorded in
`tasks/T011-release.md`, re-verified the same day):

| workload | Julia before (T011) | Julia after (T012) | Nim reference |
| --- | --- | --- | --- |
| fill_rects_1000 | 0.90 ms | **0.76 ms** | 0.82 ms |
| stroke_lines_1000 | 26.63 ms | 26.12 ms | 22.30 ms |
| blur_128_r3 | 0.69 ms | **0.36 ms** | 0.43 ms |
| shadow_128 | 1.07 ms | **0.40 ms** | 0.67 ms |
| draw_10 | 1.15 ms | **0.23 ms** | 0.18 ms |
| png_encode_256_x10 | 29.05 ms | **23.31 ms** | 10.78 ms |
| png_decode_basic1_x10 | 67.27 ms | **1.50 ms** | 1.17 ms |
| text_parse_layout_x100_measure_x20 | 1.26 ms | **1.25 ms** | 1.99 ms |

Historical steady-state medians in milliseconds (median of three run medians,
same machine; Nim values from T011). Julia was faster on fill, blur, shadow,
and text in these workloads, and slower on stroke, draw, and PNG I/O.
The PNG decode function barrier removed substantial per-pixel dynamic dispatch.
PNG encoding still spends substantial time in `PNGFiles.save`; those timings
include package conversion and I/O as well as libpng compression, and do not
establish a codec performance floor. The remaining stroke/draw gaps have not
been attributed conclusively. These are scalar-reference comparisons, not
claims about every image size, scene, or SIMD-enabled upstream build.
Full records, the rejected alternatives, and method notes:
`tasks/T012-optimization.md` and `docs/DECISIONS.md` D021.

## Profiling

Measure warmed-up functions with inputs passed as arguments. This keeps
compilation and untyped global variables out of the drawing measurement:

```julia
using Vetra, Profile, InteractiveUtils

function draw_batch!(ctx, n)
    for _ in 1:n
        fillRect(ctx, 10f0, 10f0, 10f0, 10f0)
    end
    return nothing
end

ctx = Context(256, 256)
ctx.fillStyle = rgba(255, 0, 0, 255)
draw_batch!(ctx, 200)
seconds = @elapsed draw_batch!(ctx, 1000)
bytes = @allocated draw_batch!(ctx, 1)
println(seconds * 1e6 / 1000, " µs per call")
println(bytes, " bytes per call")

@code_warntype draw_batch!(ctx, 1)
Profile.clear()
@profile draw_batch!(ctx, 100_000)
Profile.print(format = :flat, sortedby = :count)
```

`@code_warntype` shows inferred types; `Profile.print` displays sampled hot
spots. For an interactive flame graph, install ProfileView in a profiling
environment and run `using ProfileView; ProfileView.view()` after sampling.
If a short workload yields no samples, increase its repetitions. T012 recorded
local sampling difficulties; their cause was not established and does not
imply a limitation of Julia's profiler.

For line-level allocation traces, run
`julia --startup-file=no --project=. --track-allocation=user myscript.jl`
and inspect the generated `*.mem` files. Warm up first and call
`Profile.clear_malloc_data()` before the measured workload to reset allocation
counters. A `-` is not a measured allocation count; it should not be interpreted
as proof of zero allocation. Generated coverage and allocation files are ignored.

For repeatable end-to-end comparisons use the [benchmark harness](benchmark/README.md).
See Julia's [performance tips](https://docs.julialang.org/en/v1/manual/performance-tips/)
for function barriers, type stability, and measurement guidance.

## Roadmap and contributing

The [forward roadmap](docs/ROADMAP.md) covers easier numeric arguments, Julia
image interoperability, notebook display, a visual cookbook, release preparation,
application benchmarks, recording with SVG/PDF export, richer text, and JPEG/WebP.
These are planned additions; current support is listed in
[Compatibility](docs/COMPATIBILITY.md).

Agents and contributors should start with [AGENTS.md](AGENTS.md), the
[task board](TASKS.md), and the [handoff](docs/HANDOFF.md), then claim one ready
task. Each spec includes dependencies, scope, acceptance criteria, and checks.

## License

MIT (see `LICENSE`); upstream pixie is MIT (third_party/upstream.LICENSE).
Fonts and fixture provenance: [NOTICE](NOTICE).
