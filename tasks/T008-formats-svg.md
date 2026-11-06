# T008 — Image formats and SVG

Status: ready (W6). Dependencies: T007 and the codec policy (D008).
Goal: read/write the formats pixie supports, within the D008 policy, plus the
SVG subset needed by examples and general use.

## Inputs and upstream references

- `.reference/upstream/src/pixie/fileformats/` (`png`, `ppm`, `bmp`, `qoi`,
  `webp`, `gif`, `jpeg`), `imagebase64.nim`, `svg.nim`; zippy/flatty/crunchy
  are the upstream codec dependencies (pinned, reference only).
- D008: prefer well-supported Julia packages for codecs when stable; keep the
  renderer core dependency-free; decide per format and record the decision.
- Fixtures: `test/reference/*.png` (cross-check artifacts; canonical `.raw`
  buffers are the pixel truth), `heart.raw` for the SVG path subset.
- `writePPM` from T006 is the starting minimal writer.

## Scope

- Decide per format (PNG, PPM, BMP, QOI, WebP, GIF, JPEG, base64) whether to
  use a Julia package, a native port, or defer; record each as a decision
  entry (coordinator integrates DECISIONS.md). Dependency use must be opt-in
  per D008 and must not affect the rasterizer.
- Implement at least: PPM read/write (native), PNG decode + encode (package or
  native), base64 encode/decode, and SVG `parseSvg` for the shapes the pinned
  `svg.nim` supports (rect, circle, ellipse, path, simple groups/transforms).
- Public API keeps upstream names (`readImage`, `writeImage`, `parseSvg`);
  distinguish read/write support in COMPATIBILITY; unsupported formats are
  absent, not stubbed.
- Malformed input handling: clear `ArgumentError`/`ErrorException` messages;
  no silent partial decodes.

## Acceptance criteria

- `test/formats_tests.jl` (new): PPM round-trip; PNG decode of a pinned PNG
  matches its `.raw` pixel buffer exactly; PNG encode→decode round-trip;
  base64 round-trip against upstream-derived vectors; SVG parse of the heart
  path commands; malformed headers rejected.
- Optional formats deferred by decision are listed with a reason; no
  half-working codecs exported.
- `Pkg.test()` green; `scripts/check.jl` > 95% (record exact %). If a package
  is added, `Project.toml` dependency + `[extras]`/test target are updated and
  the license is recorded in NOTICE.
- Split into a new task ID if the format set exceeds one wave.

## Validation

Commands as T004; network may be unavailable — record that limitation and
leave package work blocked with a concrete reason rather than fabricating
fixtures. Do not edit shared docs; do not commit.

## Results and handoff

Record commands/results per format, dependencies/licenses, coverage %, and
deferred formats.

## Results — formats and SVG (this run, 2026-11-05)

Formats landed (src/formats/):
- PNG — decode + encode via `PNGFiles` (opt-in, D014). Pinned fixtures
  match their `.raw` masters exactly; encode→decode round trips exact.
- JPEG — decode only via `JpegTurbo` (opt-in, D014): marker scan with
  resync/FF-stuffing, Exif orientation 1–8 (dimensions orientation-aware,
  invalid orientation rejected); pixels within 8 per channel of the
  upstream stb-derived fixtures (measured: mandrill 5, progressive 5,
  exif_overrun 4, grayscale 1). No encoder (upstream parity).
- BMP — native port: 1/4/8/24/32-bit, bottom-up + top-down (negative
  height via signed int32 read), BITMAPV3HEADER alpha masks; encodeBMP
  writes 32-bit top-down. 5 pinned fixtures exact.
- QOI — native port, decode + encode. Upstream quirk preserved (op tags
  RGB=0xFE/RGBA=0xFF, INDEX = raw hash byte); encoder op-selection pinned
  by a 10x1 vector whose exact stream is asserted.
- GIF — decode only (native): GCT/LCT, interlace, disposal methods,
  graphic-control + comment extensions, out-of-range indices skip to
  transparent. 4 pinned fixtures exact.
- PPM — native: P6 write (T006) + P3/P6, 8/16-bit decode; header errors
  rejected. Out-of-range P3 samples are rejected (deviation from
  upstream release-mode truncation; recorded in COMPATIBILITY).
- base64 — native: strict RFC-4648 validate/encode/decode, data-URL
  passthrough, PNG payload; all remainder branches covered.
- SVG — `parseSvg` + `newImage(svg)` of the pinned subset (viewBox;
  rect/circle/ellipse/line/polyline/polygon/path/g; defs/title/desc/
  filter/radialGradient skipped; linearGradient `url(#id)` fills;
  translate/rotate/scale/matrix transforms; upstream camelCase
  `fillOpacity`/`strokeOpacity` style quirk). XML parse via the opt-in
  `XML` package (D014). 14 pinned fixtures match `.raw` exactly.
- Dispatch — `decodeImage`/`decodeImageDimensions`/`readImage`/
  `readImageDimensions` (magic bytes), `encodeImage`/`writeFile`
  (extension; WebP raises "Unsupported file format", as upstream).

Tests: test/formats_tests.jl (pinned fixtures, dispatch, round trips,
base64, malformed input) + test/formats_synthetic_tests.jl (hand-built
byte streams for the branches the fixtures miss: palette/top-down/V3 BMP,
GIF LCT/interlace/disposal/extensions, JPEG Exif/resync, QOI decode+
encode ops, PPM 16-bit, SVG style/gradient/url) + test/rasterizer_tests.jl
(MaskBlend fillShapes paths and drawSmooth branches, oracle-pinned) +
T008 testsets in test/paint_tests.jl / test/context_layers_tests.jl.
Expected pixels come from the pinned fixtures, the patched upstream
oracle (/tmp/oracelprobe-src, nim 2.2.6 -d:pixieNoSimd), or hand-derived
spec math — never the code under test.

Examples: examples/{png,jpeg,bmp,qoi,svg,gif,ppm}.jl (each decodes its
pinned fixture by default, `[input] [output]` args, writes under
artifacts/examples/) and examples/showcase.jl (API tour: context state,
paths, transforms, clip/layers, gradient + blend-mode paints, image ops,
format I/O, base64). All verified run-clean in an environment with the
D014 opt-in packages.

Validation: `julia --startup-file=no --project=. scripts/check.jl` —
Pkg.test green, `src/` line coverage 98.72% (4158/4212 measurable), above
the 95% gate (D009). Dependencies are `[extras]` only (D014 opt-in);
licenses recorded in NOTICE (PNGFiles MIT, JpegTurbo MIT, XML MIT).

Deferred: WebP (no stable Julia package; native port unscheduled) and
text/fonts (T009). Next task: T009.
