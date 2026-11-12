# Examples

For a step-by-step project with explanations, start with the
[dashboard tutorial](../docs/TUTORIAL.md).

All examples run with `julia --project=. examples/<name>.jl [input] [output]`
and default to the pinned upstream fixtures in
`.reference/upstream/tests/fileformats/`, writing under `artifacts/examples/`.

## Feature gallery (`gallery/`)

Six feature programs on the current public API, with self-checks, a batch
runner and a coverage matrix — see [gallery/README.md](gallery/README.md):

    julia --project=. examples/gallery/run_gallery.jl [outdir]
    julia --project=. examples/gallery/run_gallery.jl [outdir] --core-only

Core-only runs need nothing extra; the optional checks (PNG/JPEG/WebP/
ColorTypes/HarfBuzz) run when the providers are present, e.g. after the
documented setup of `examples/gallery/optional_env`.

## Core (no extra packages)

- `square.jl`, `line.jl`, `heart.jl` — mirrors of the pinned upstream programs
  (200x200; build logic shared in `common.jl`). Their pixels are checked
  against `test/reference/` in `test/examples_tests.jl`.
- `bmp.jl`, `qoi.jl`, `ppm.jl` — native codecs: decode the default fixture
  and re-encode it (round trip).
- `showcase.jl` — a guided tour of the API: canvas, context state, paths,
  transforms, clip + layers, gradients and blend-mode paints, image
  operations, format I/O, and text (native Roboto). Runs core-only by
  default (BMP output); section 8's PNG/JPEG/SVG parts run only when
  their opt-in packages are available (named and skipped otherwise).

## Opt-in formats (D014)

PNG, JPEG and SVG use well-supported Julia packages, added per
D014: `PNGFiles`, `JpegTurbo`, `XML`. In your environment:

    using Pkg
    Pkg.add(["PNGFiles", "JpegTurbo", "XML"])

- `png.jl` — decode and re-encode PNG.
- `jpeg.jl` — decode JPEG (Exif-aware dimensions) and write a PNG preview
  (upstream has no JPEG encoder).
- `svg.jl` — parse and rasterize SVG to a PNG.
- `gif.jl` — decodes a multi-frame GIF with the native codec and writes the
  first frame as a PNG preview (needs `PNGFiles` for the preview; upstream
  has no GIF encoder).
