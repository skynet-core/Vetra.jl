# Compatibility inventory

Status: **T010 — everything implemented**: colors, images, geometry, paths,
fills/strokes, every `Paint` kind and blend mode, image drawing, the full
context (state stack, mask/clip/layers, `globalAlpha`, `isPointInPath`,
dash patterns in strokes), image effects, all codecs except WebP, SVG
(pinned subset), base64, fonts/text, and the pinned + per-format examples
(D010–D015; evidence below and in tasks/T002–T010). The inventory comes
from the pinned source at 30bb510 (see upstream.toml); "Julia status" is
`not implemented` until a linked task delivers tests and (where relevant)
fixture evidence.

Scope note: `pixie.nim` re-exports `bumpy`, `chroma`, `vmath` wholesale;
those third-party APIs are reference material, not a parity obligation beyond
what the pixie modules themselves use (see docs/NUMERICAL_CONTRACT.md).

## Foundation (T002) and geometry (T003)

| Upstream symbol(s) | Area | Julia status | Evidence |
| --- | --- | --- | --- |
| `Vec2` (`GVec2[float32]`), `+ - * /` scalar/vector, `dot`, `length`, `lengthSq`, `normalize`, `perpendicular` | `vmath` | **implemented** (T003, D011). Float32; zero `normalize` yields NaN like upstream | test/geometry_tests.jl "Vec2" (hand-computed values + literal expectations) |
| `Rect`, `Circle`, `Segment`, `Line`, `Polygon`; `rect`, `xy`, `wh`, `circle`, `segment`, `line`; `*`/`/` scalar, `+`, `or` (=`\|`), `and` (=`&`) | `bumpy` | **implemented** (T003, D011). Upstream `(x,y,w,h)` layout; intersection not clamped; `left/top/right/bottom` are Julia sugar | test/geometry_tests.jl "Rect", "Circle, Segment, Line, Polygon" |
| `Mat3`, `mat3`, `translate`, `scale`, `rotate`, `*`(Mat3,Mat3), `*`(Mat3,Vec2), `determinant`, `transpose`, `inverse` | `vmath` | **implemented** (T003, D011). Column-major 1-based `m[i,j]`, `A*B` applies B first, no singular-inverse guard (matches upstream) | test/geometry_tests.jl "Mat3"; hand-computed matrices |
| `snapToPixels(Rect)` | `pixie/common.nim` | **implemented** (T003) | fixture snap_to_pixels.tsv — all 135 rows exact Float32 |
| `Image`, `newImage`, `copy`, `dataIndex`, `inside`, `fill`, `getColor`/`setColor` (T002 subset) | `pixie/common.nim`, `pixie/images.nim` | **implemented** (T002, D010). `dataIndex` is ported as internal `pixel_index` (1-based) and is not part of the public API | test/core_tests.jl "image storage and access"; fixtures: (n/a) — invariants tested directly |
| `mix`, `*`(ColorRGBX, float32), `*`(ColorRGBX, uint8) | `pixie/common.nim` | **implemented** (T002, D010) | fixtures: mix.tsv, color_opacity.tsv, rgbx_coverage.tsv — all rows exact |
| `toStraightAlpha`, `toPremultipliedAlpha` | `pixie/internal.nim`, chroma `transformations.nim` | **implemented** (T002, D010); both premul→straight paths kept distinct per NUMERICAL_CONTRACT | fixtures: straight_alpha.tsv (32 896 valid rows exact), premultiplied_alpha.tsv (65 536 rows exact) |
| `blendNormal`, `blendAlpha` (source-over) | `pixie/blends.nim` | **implemented** (T002, D010); channel sums wrap mod 256 mirroring upstream | fixtures: blend_normal.tsv (121 cells exact, incl. wrap cells), blend_alpha.tsv (65 536 rows exact); test/core_tests.jl pins two wrap cells |

## All other blend modes (T007a)

| Upstream symbol(s) | Area | Julia status | Evidence |
| --- | --- | --- | --- |
| `BlendMode` (0..19), `blendDarken`, `blendMultiply`, `blendColorBurn`, `blendLighten`, `blendScreen`, `blendColorDodge`, `blendOverlay`, `blendSoftLight`, `blendHardLight`, `blendDifference`, `blendExclusion`, `blendHue`, `blendSaturation`, `blendColor`, `blendLuminosity`, overwrite (`source`) | `pixie/blends.nim` | **implemented** (T007a). Integer and chroma-float pipelines ported exactly, including upstream `.uint8` truncation wrap; `blender(mode)` dispatches all 17 non-mask modes | test/paint_tests.jl "blends"; fixtures: all 16 W3C + overwrite `blend_*.tsv` — 17 tables × 121 rows exact |
| `blendMask`, `blendSubtractMask`, `blendExcludeMask` | `pixie/blends.nim` | pixel functions **implemented and fixture-exact** (T007a); `blender(16/18/19)` dispatches them (T007b), so fills/draws use the clip-region mask semantics | test/paint_tests.jl mask-table comparisons (`mask`, `subtract_mask`, `exclude_mask` fixtures); test/context_layers_tests.jl |

## Paths, filling, rasterization (T004)

| Upstream symbol(s) | Area | Julia status | Evidence |
| --- | --- | --- | --- |
| `Path`, `newPath`, `copy`, `addPath`, `closePath`, `moveTo`, `lineTo`, `quadraticCurveTo`, `bezierCurveTo`, `ellipticalArcTo`, `arc`, `arcTo`, `rect`, `roundedRect`, `ellipse`, `circle`, `polygon`, `transform(path, m)` | `pixie/paths.nim` | **implemented** (T004, D011) | test/path_tests.jl "command construction", "transform", "remaining command-builder branches"; command-stream and hand-computed geometry |
| `parsePath` (SVG `M L H V C S Q T A Z`, absolute + relative) | `pixie/paths.nim` | **implemented** (T004); upstream parser quirks preserved (recorded in tasks/T004-paths.md); malformed input raises `ArgumentError` | test/path_tests.jl "SVG parsing" |
| `commandsToShapes`, `computeBounds`, `WindingRule` (`NonZero`/`EvenOdd`) | `pixie/paths.nim` | **implemented** (T004); `commandsToShapes` is internal (not exported), matching upstream visibility | test/path_tests.jl "winding rules and solid fills", "multi-partition fills" |
| `fillShapes`, `fillPath` (all `Paint` kinds), fixed-point coverage/AA, blend-mode dispatch | `pixie/paths.nim` | **implemented** (T004 solid; T007a image/tiled/gradient). `Path`/SVG-string paths; non-solid paints build the upstream mask/fill images and composite with the paint's blend mode. Clip/mask layers are T007b | test/path_tests.jl solid-fill sets; test/paint_tests.jl "image and tiled paints via fillPath"; `square.raw`/`heart.raw` 0 mismatches; clip/mask layers implemented (T007b) |

## Strokes and context (T005, T010)

| Upstream symbol(s) | Area | Julia status | Evidence |
| --- | --- | --- | --- |
| `strokePath`, `strokeShapes`, `strokeSegment`, caps (`ButtCap`/`RoundCap`/`SquareCap`), joins (`MiterJoin`/`RoundJoin`/`BevelJoin`), miter limit, dashes | `pixie/paths.nim` | **implemented** (T005; `Context.lineDash` wiring T010); solid paints; odd-length dash patterns duplicate themselves, zero/negative lengths raise `ArgumentError("Invalid line dash value")` at stroke time | test/context_tests.jl stroke sets; `line.raw` parity 0 mismatches; test/context_integration_tests.jl dash phase testsets |
| `Context`, `fillStyle`, `strokeStyle`, `lineWidth`, `miterLimit`, `lineCap`, `lineJoin`, `transform`/`getTransform`/`setTransform`/`resetTransform`, `save`/`restore`, path wrappers, `fill`, `stroke`, `fillRect`, `strokeRect`, `clearRect`, `strokeSegment`, `drawImage`/`draw` (3/5/9-arg) | `pixie/contexts.nim` | **implemented** (T005; `drawImage` T007a). Unbalanced `restore` raises `ArgumentError` (documented deviation from upstream's no-op) | test/context_tests.jl context/state/transform/wrapper tests; test/image_ops_tests.jl drawImage wrappers; square flow parity |
| `clip`, `globalAlpha`, `saveLayer`, mask/layer composition, `isPointInPath` (4 overloads), `lineDash` state | `pixie/contexts.nim`, `pixie/paths.nim` | **implemented** (clip/layers/globalAlpha T007b; `isPointInPath` + dash wiring T010). Quirks preserved: `clip`'s mask is built in identity space (the CTM is not applied, regardless of save/transform order); `isPointInPath` discards scanline hits landing exactly on `segment.to` (bottom-edge exclusion), and a point past the last hit falls through to `false`; `isPointInStroke` exists upstream but is **not ported** (outside docs/API.md scope) | test/context_layers_tests.jl; test/context_integration_tests.jl (isPointInPath matrix, dash phase, clip + transform, text + clip, composite state stack) |

## Paints and gradients (T007a)

| Upstream symbol(s) | Area | Julia status | Evidence |
| --- | --- | --- | --- |
| `PaintKind`, `Paint`, `ColorStop`, `newPaint`, `copy`, `colorStop`, `Paint(color/image/kind)`, mutable `color`/`opacity`/`blendMode`/`image`/`imageMat`/gradient fields | `pixie/paints.nim` | **implemented** (T005 solid; T007a every kind). `color`/stop colors are straight `ColorRGBA` per D010; `opacity` clamped 0..1 in place at draw entry; `copy` is independent | test/paint_tests.jl "newPaint defaults", "copy independence", "colorStop" |
| `gradientColor` (internal), `fillGradientLinear`/`Radial`/`Angular`/`fillGradient` | `pixie/paints.nim` | **implemented** (T007a); upstream stop clamping, float32 `lerp`, opacity-before-premultiply, and handle-count errors preserved | test/paint_tests.jl gradient endpoints/midpoints, radial/angular hand checks |
| `parseHtmlColor` (`#RGB`/`#RRGGBB`), `parseSomePaint` | chroma, `pixie/paints.nim` | **partially implemented** (T005, unchanged in T007a): hex subset only; `rgb()`/`rgba()`/named colors raise `ArgumentError` | test/context_tests.jl hex parsing; recorded deviation |

## Image operations and effects (T007a, T007b)

| Upstream symbol(s) | Area | Julia status | Evidence |
| --- | --- | --- | --- |
| `draw`, `drawTiled`, `getRgbaSmooth`, `magnifyBy2`, `minifyBy2`, `applyOpacity`, `subImage`, internal `blendRect`/`drawSmooth` | `pixie/images.nim` | **implemented** (T007a). Scalar; fast integer `blendRect` path and smooth inverse-transform sampling path; filter-by-2 normalization | test/image_ops_tests.jl; `draw_translate.raw`/`draw_scale2.raw` 0 mismatching bytes |
| `blur`, `shadow`, `resize`, `rotate90`, `flipHorizontal`/`flipVertical`, `invert`, `ceil`, `superImage`, `opaqueBounds`, `spread`, `diff`, `gaussianKernel` | `pixie/images.nim`, `pixie/internal.nim` | **implemented** (T007b, 2026-11-04). Scalar; pinned mixed-precision `gaussianKernel` (all 288 fixture weights exact), separable two-pass `blur`/`spread` with the transposed intermediate, MaskBlend `shadow`, `resize` via `draw` fast paths; `rotate90` returns the rotated image instead of mutating (D013); `ceil`/`diff` extend the Base generics (D013); the `subImage(image, rect)` overload is not ported (no call site yet) | test/image_ops_tests.jl "T007b image effects" (404 assertions, hand-derived); `gaussian_kernel.tsv` 16 radii × 288 weights, 0 mismatches |

## Images, formats, text (T006, T008, T009)

Optional PNG/JPEG/SVG packages are discovered and loaded during runtime
module initialization (D019), including when the precompile cache was built
in a core-only environment. Absent packages still produce install hints on
format use; installed packages that fail to load propagate their actual error.
Evidence: `test/codec_loading_tests.jl` covers core-only cache reuse followed
by PNG, JPEG, and SVG operations in the codec-enabled test environment.

- Examples: square, line, heart (`examples/*.jl`, shared builders in
  `examples/common.jl`) — **implemented** (T006); each matches its pinned
  `.raw` fixture with 0 mismatching bytes, and the `.ppm` payload equals the
  fixture RGB bytes. Per-format examples `png.jl`, `jpeg.jl`, `bmp.jl`,
  `qoi.jl`, `gif.jl`, `svg.jl`, `ppm.jl` and the API tour `showcase.jl` —
  **implemented** (T008); all verified run-clean against the pinned fixtures
  (see tasks/T008-formats-svg.md results). Evidence: test/examples_tests.jl.
- PPM: `encodePPM` / `writePPM` / `decodePPM` / `decodePPMDimensions`
  (`pixie/fileformats/ppm.nim`) — **implemented** (T006 write; T008 read):
  binary P6 and ASCII P3, 8- and 16-bit maxval; decode returns straight
  alpha-255 RGBX. Deviation: out-of-range P3 samples (above the declared
  maxval) are rejected with `ArgumentError`; upstream release mode
  truncates them (the pinned debug oracle would RangeDefect). Evidence:
  test/formats_tests.jl, test/formats_synthetic_tests.jl.
- PNG: `decodePNG` / `encodePNG` / `decodePNGDimensions`
  (`pixie/fileformats/png.nim`) — **implemented** (T008) via the opt-in
  `PNGFiles` package (D014); missing package raises an install hint, not a
  dependency error. Decoded pixels match the pinned `.raw` masters exactly.
  Evidence: test/formats_tests.jl.
- BMP: `decodeBMP` / `decodeDIB` / `encodeBMP` / `decodeBMPDimensions`
  (`pixie/fileformats/bmp.nim`) — **implemented** (T008), native port:
  1/4/8/24/32-bit, bottom-up and top-down (negative height), BITMAPV3HEADER
  alpha; encode writes 32-bit top-down. Evidence: test/formats_tests.jl
  (5 pinned fixtures), test/formats_synthetic_tests.jl.
- QOI: `decodeQOI` / `encodeQOI` / `decodeQOIDimensions`
  (`pixie/fileformats/qoi.nim`) — **implemented** (T008), native port.
  Upstream quirk preserved: op tags RGB=0xFE / RGBA=0xFF, INDEX is the raw
  hash byte, and the encoder emits the upstream op-selection chain
  (pinned stream `qoif...0x09,0xc2,0xff` for the 10x1 vector). Evidence:
  test/formats_tests.jl, test/formats_synthetic_tests.jl.
- GIF: `decodeGIF` / `decodeGIFDimensions` (`pixie/fileformats/gif.nim`) —
  **decode only** (T008), native port (upstream has no GIF encoder): GCT/LCT,
  interlaced, disposal methods, graphic-control and comment extensions,
  out-of-range palette indices skip to transparent. Evidence:
  test/formats_tests.jl (4 pinned fixtures), test/formats_synthetic_tests.jl.
- JPEG: `decodeJPEG` / `decodeJPEGDimensions`
  (`pixie/fileformats/jpeg.nim`) — **decode only** (T008) via the opt-in
  `JpegTurbo` package (D014): marker scan with resync, FF-stuffing, Exif
  orientation 1-8 (dimensions orientation-aware); pixels differ from the
  upstream stb-derived fixtures by at most 8 per channel (recorded,
  measured on the 4 oracle fixtures). Evidence: test/formats_tests.jl.
- base64: `encodeBase64` / `decodeBase64`
  (`pixie/imagebase64.nim`) — **implemented** (T008), native port: strict
  RFC-4648 validation, data-URL passthrough, PNG payload. Evidence:
  test/formats_tests.jl, test/formats_synthetic_tests.jl.
- WebP: `pixie/fileformats/webp.nim` — **not implemented** (deferred; no
  stable Julia package, native port not scheduled; `WebpFormat` dispatch
  raises "Unsupported file format" as upstream).
- Dispatch: `decodeImage` / `encodeImage` / `readImage` / `readImageDimensions`
  / `writeFile` (`pixie/pixie.nim`) — **implemented** (T008): magic-byte
  dispatch for PNG/JPEG/BMP/QOI/GIF/PPM/SVG, extension-driven write for
  PNG/BMP/QOI/PPM (JPEG/GIF/WebP writes raise, as upstream).
- SVG: `parseSvg` + `newImage(svg)` (`pixie/fileformats/svg.nim`) —
  **implemented** (T008), the pinned subset: viewBox, `rect` (incl.
  rx/ry), `circle`, `ellipse`, `line`, `polyline`, `polygon`, `path`
  (full `parsePath` grammar), `g` with property inheritance; `defs`,
  `title`, `desc`, `filter`, `radialGradient` are skipped as upstream;
  `linearGradient` fills via `url(#id)`; transforms translate/rotate/
  scale/matrix (others raise); style attributes accept the upstream camelCase
  `fillOpacity`/`strokeOpacity` quirk. Rendering uses `fillShapes`/
  `strokeShapes` (first element overwrites, later composite). Requires the
  opt-in `XML` package (D014). Evidence: test/formats_tests.jl
  (14 pinned fixtures), test/formats_synthetic_tests.jl.
- Fonts and text: `newFont`, `readFont`/`readTypeface`, `parseTtf`/
  `parseOtf`/`parseOpenType`, `fillText`/`strokeText` (Image and Context),
  `measureText`/`TextMetrics`, `typeset`/`layoutBounds`/`computePaths`/
  `computeBounds`, metrics (`scale`, `ascent`, `descent`, `lineGap`,
  `lineHeight`, `capHeight`, `defaultLineHeight`), `getGlyphPath`,
  `getAdvance`, `getLeftSideBearing`, `getKerningAdjustment`, `hasGlyph`,
  `name`, Context text state (`font`, `fontSize`, `textAlign`,
  `textBaseline`, `setLineDash`/`getLineDash`; `pixie/fonts.nim` +
  `pixie/fontformats/opentype.nim` + `pixie/contexts.nim`) —
  **implemented** (T009, D015): native scalar port of upstream's OpenType
  subset — TTF/glyf single-face fonts only (cmap formats 4/12 platform 3,
  head, hhea, maxp 0.5/1.0, hmtx, name, OS/2 v0-2, post, loca fmt 0/1,
  glyf simple + composite, `kern` v0, GPOS pair-position fmt 1/2 via
  lookup type 2). Upstream quirks preserved, incl. the 14-byte cmap
  format-4 header, GPOS-over-`kern` precedence, font-level `lineGap`
  mixed with typeface ascent in the baseline, and `fastRuneAt`-style rune
  decoding (truncated UTF-8 → U+FFFD, no continuation validation).
  **Not supported** (raise `ArgumentError`): CFF-outline fonts
  ("Unsupported font CFF outlines"), TTC collections, SVG fonts
  ("Unsupported font format"); text wrapping beyond upstream's
  single-run line-break algorithm and Unicode shaping are out of scope.
  Error mapping: upstream `PixieError` → `ArgumentError`, messages
  verbatim. One intentional deviation (stricter than upstream): the glyf
  instruction-length EOF check bounds the actual instruction range, where
  upstream's `eofCheck(instructionLength)` bounds from buffer start
  (opentype.nim L2209) — malformed fonts that pass upstream raise here.
  Evidence: test/font_tests.jl (2456 assertions: oracle
  metric/kerning TSVs, 17 layout scenarios bit-exact, 14 rendered images
  0 byte mismatches, textCase via the pinned Nim unicase tables,
  fallback/hasGlyph semantics, negative-tie rounding, synthetic mini font
  (incl. maxp 0.5, post version nibbles, name surrogate/tofu decoding),
  malformed-byte rejections); fixtures from `sh tools/oracle/build.sh fonts`
  (68 files under test/reference/font_*; Roboto Apache-2.0 + Ubuntu UFL,
  sha256 recorded in fixture meta and verified by tests).

## SIMD

`pixie/simd.nim`, `pixie/simd/{sse2,avx,avx2,neon}.nim` — **deferred**;
scalar semantics are the reference contract (docs/NUMERICAL_CONTRACT.md).

## Evidence for a supported claim

Record upstream symbol/file and pinned revision, Julia API, supported inputs,
test location, fixture IDs, comparison policy, and known deviations. A partial
feature should name its missing subset. Tests that merely load a module do not
establish compatibility.

For codecs, distinguish decoding and encoding. For text, distinguish parsing,
glyph outline rendering, metrics/kerning, and layout. Do not claim general SVG
or Unicode shaping support based on one example.
