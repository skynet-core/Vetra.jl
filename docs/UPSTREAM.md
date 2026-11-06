# Upstream reference

Repository: https://github.com/treeform/pixie

The single source of truth for the revision is ../upstream.toml.
Pinned source:
https://github.com/treeform/pixie/tree/30bb510877f02cbf9643e4f904e33d1c90f7910f

The inspected manifest declares version 6.1.0 and Nim >= 2.0.0.
Its dependencies are vmath, chroma, zippy, flatty, nimsimd, bumpy, and crunchy,
with minimum version constraints. Those constraints do **not** make a reference
build reproducible; record resolved commits/versions as part of T001.

## Fetch

From the project root:

```sh
julia --startup-file=no --project=. scripts/fetch_upstream.jl
```

The source lives in ignored .reference/upstream. Fetching is explicit and separate
from Julia package tests. The script reuses only a clean checkout at the pinned
commit and expected origin. If a previous download was interrupted or the
checkout differs, inspect and move that directory aside before retrying; the
script never resets it for you.

After fetching, the reference analyst should inspect upstream build/test commands,
choose a Nim toolchain, and record actual resolved dependency versions and flags.
Do not assume that a successful source checkout is a successful reference build.

## Initial source inventory

- src/pixie.nim: entry point and exports.
- common.nim, images.nim, blends.nim: types, image operations, pixel arithmetic.
- paths.nim, paints.nim, contexts.nim: geometry, rendering, paint, drawing state.
- fileformats/: BMP, GIF, JPEG, PNG, PPM, QOI, SVG, TIFF, WebP-related source.
  File presence alone does not prove encoding or decoding completeness.
- fontformats/opentype.nim, fontformats/svgfont.nim, fonts.nim: font/text work.
- simd.nim and simd/: architecture-specific implementations.
- tests/: candidate behavioral tests; audit their setup and asset provenance.

Paths in the bullets above are relative to src/pixie/ except where fully stated.

## First reference examples

| Example | Observed construction |
| --- | --- |
| examples/square.nim | 200×200 white image; red 100×100 rectangle at (50, 50) |
| examples/line.nim | 200×200 white image; #FF5C00 segment (25, 25) to (175, 175), width 10 |
| examples/heart.nim | 200×200 white image; #FC427B fill using arc and quadratic path commands |

Inspect the pinned files for exact API calls and path data. Commit URLs:

- https://github.com/treeform/pixie/blob/30bb510877f02cbf9643e4f904e33d1c90f7910f/examples/square.nim
- https://github.com/treeform/pixie/blob/30bb510877f02cbf9643e4f904e33d1c90f7910f/examples/line.nim
- https://github.com/treeform/pixie/blob/30bb510877f02cbf9643e4f904e33d1c90f7910f/examples/heart.nim

No golden images are bundled. Existing upstream PNGs may be useful inspection
material, but regenerate canonical buffers with documented provenance before
using them as definitive output for this pin.

## Attribution

The verbatim upstream MIT license is in third_party/upstream.LICENSE.
Translated source should identify the original file, symbols, and revision.
Audit licenses for fonts, sample images, and transitive dependencies separately;
the repository license is not evidence of every asset's license.
