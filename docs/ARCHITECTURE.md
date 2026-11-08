# Architecture

Vetra is one Julia module with a CPU rasterizer. The pinned upstream revision
in `upstream.toml` supplies the numerical contract; the Julia implementation
does not invoke Nim at runtime.

## Source layout

| File or directory | Responsibility |
| --- | --- |
| `src/Vetra.jl` | Colors, image storage, alpha conversion, core compositing, exports, codec initialization |
| `src/geometry.jl` | Float32 vectors, affine matrices, geometry |
| `src/paths.jl` | Path commands, SVG path parsing, curve flattening |
| `src/rasterizer.jl` | Scan conversion, coverage, solid fills, filled-path hit testing |
| `src/blends.jl` | Blend modes and pixel compositing |
| `src/paints.jl` | Color parsing, gradients, image paints, painted fills |
| `src/strokes.jl` | Stroke outlines, caps, joins, dash patterns |
| `src/image_ops.jl` | Image drawing, sampling, resizing, masks, blur, shadows |
| `src/context.jl` | Drawing state, transforms, clips, layers, convenience API |
| `src/fontformats/` | OpenType parsing and pinned Unicode case tables |
| `src/formats/fonts.jl` | Typeface/font objects, text layout and rendering |
| `src/formats/` | Format-specific readers/writers, SVG adapter, image I/O dispatch |

## Data flow

`Context` builds or accepts a `Path` and supplies its transform and `Paint`.
Paths are flattened into shapes; fills compute coverage, while strokes first
build outlines. The rasterizer composites into `Image.data`, a contiguous,
row-major, premultiplied RGBA byte buffer. Gradients and image paints use
intermediate masks; context layers use additional image buffers.

Font parsing yields glyph outlines and metrics. Text layout positions those
outlines, and text rendering uses the same path machinery. Image codecs
convert between the stored premultiplied bytes and their external formats.
The PNG conversion loop is behind a function barrier so the compiler can
specialize on the optional codec's concrete pixel type.

## Dependencies and extension points

The renderer has no hard external package dependencies. PNGFiles, JpegTurbo,
and XML are opt-in packages, discovered in `__init__` for the active environment
(D014/D019). Native font parsing follows D015. Documentation dependencies
live separately in `docs/Project.toml`.

GPU backends, command recording, and widgets remain future work; there is no
implemented backend plugin interface. Keep future rendering changes behind
the existing drawing API and numerical contract rather than adding placeholders.
The [forward roadmap](ROADMAP.md) schedules recording/export design and
implementation; GPU rendering and widgets remain deferred.

## Development and validation

- [API](API.md): coordinate, alpha, mutation, and public API conventions.
- [Compatibility](COMPATIBILITY.md): supported behavior with test evidence.
- [Numerical contract](NUMERICAL_CONTRACT.md): arithmetic and rounding rules.
- [Upstream](UPSTREAM.md) and [NOTICE](../NOTICE): provenance and attribution.
- [Test strategy](../test/README.md): independent expectations and coverage gate.
- [Benchmarks](../benchmark/README.md): comparable scalar workloads.

Start with scalar correctness. Keep optimizations only after measurement and
the fixture gate; do not use fast math or unsafe indexing without the recorded
justification required by AGENTS.md. Historical work lives in `tasks/` and
[DECISIONS.md](DECISIONS.md); [HANDOFF.md](HANDOFF.md) contains only current state.
