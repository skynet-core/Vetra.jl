# Architecture

Vetra is a Julia 2D graphics library with a CPU rasterizer, recordings,
image codecs, text layout and vector export. It does not invoke Nim at runtime.
Historical reference fixtures retain the provenance in `upstream.toml`.

The proposed next architecture is a renderer-independent Canvas with CPU,
Vulkan.jl, browser Canvas2D and document backends. See
[Canvas design](CANVAS_DESIGN.md) and the
[parallel development plan](../tasks/CANVAS_ROADMAP.md). These interfaces and
backends are planned; the source layout below describes the current library.

The proposed public extension contracts follow SOLID through Julia multiple
dispatch and composition. External providers must integrate without core edits
(R013). GUI/plotting consumers will own their domain models and event loops over
Vetra's shared drawing, text, surface and export contracts (R014).

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
| `src/recordings.jl` | Owned operation snapshots, recording context and CPU replay |
| `src/fontformats/` | OpenType parsing and pinned Unicode case tables |
| `src/formats/fonts.jl` | Typeface/font objects, text layout and rendering |
| `src/formats/paragraph.jl`, `shaping.jl` | Paragraph layout and optional HarfBuzz shaping |
| `src/formats/svg_write.jl`, `pdf_write.jl` | Strict vector exporters with explicit raster fallback |
| `src/formats/` | Format-specific readers/writers, SVG adapter, image I/O dispatch |
| `src/colormatrices.jl` | Opt-in Julia color-matrix conversion |

## Data flow

`Context` builds or accepts a `Path` and supplies its transform and `Paint`.
Paths are flattened into shapes; fills compute coverage, while strokes first
build outlines. The rasterizer composites into `Image.data`, a contiguous,
row-major, premultiplied RGBA byte buffer. Gradient fills fuse coverage and
paint sampling; image paints and context layers use intermediate image buffers.

Font parsing yields glyph outlines and metrics. Text layout positions those
outlines, and text rendering uses the same path machinery. Image codecs
convert between the stored premultiplied bytes and their external formats.
The PNG conversion loop is behind a function barrier so the compiler can
specialize on the optional codec's concrete pixel type.

## Dependencies and extension points

The core declares the Libdl standard library for portable native-library
loading. PNGFiles, JpegTurbo, XML, WebP, ColorTypes and HarfBuzz_jll are optional
providers, discovered lazily on first relevant use (D028 supersedes the older
eager-init description). Native font parsing follows D015. Documentation
dependencies live separately in `docs/Project.toml`.

Recordings and SVG/PDF export are implemented. A general Canvas/backend protocol,
native GPU rendering and a browser runtime are not yet implemented. The new
design reuses these existing components, makes new Canvas semantics explicit,
and retains legacy behavior where promised. Heavy backend dependencies must
remain optional; 3D and a widget framework are outside this milestone.

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
