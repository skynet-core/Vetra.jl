# Compatibility inventory

Status: **pinned-scope port complete (T010), optimized in T012**: colors, images, geometry, paths,
fills/strokes, every `Paint` kind and blend mode, image drawing, the full
context (state stack, mask/clip/layers, `globalAlpha`, `isPointInPath`,
dash patterns in strokes), image effects, all codecs (WebP read/write
added by T032), SVG
(pinned subset), base64, fonts/text, and the pinned + per-format examples
(D010–D015; evidence below and in tasks/T002–T010). The inventory comes
from the pinned source at 30bb510 (see upstream.toml). Supported subsets and
intentional omissions are listed below; completion does not imply unrestricted
SVG, font, or third-party API compatibility.

Scope note: `pixie.nim` re-exports `bumpy`, `chroma`, `vmath` wholesale;
those third-party APIs are reference material, not a parity obligation beyond
what the pixie modules themselves use (see docs/NUMERICAL_CONTRACT.md).

## Foundation (T002) and geometry (T003)

### Julia-native additions (M003)

The [migration guide](MIGRATION.md) documents additive snake_case names, typed
bang adapters and shared Base/LinearAlgebra bindings. `Image` retains three-field
row-major storage with validated constructors and `[row, column]` access;
linear indexing, mutation and iteration share storage order. It is deliberately
not an `AbstractMatrix`. Invalid dimensions/lengths now raise `ArgumentError`,
including zero-size PPM images previously accepted accidentally. Evidence:
`test/api_native_tests.jl`, plus coordinator validation in [Handoff](HANDOFF.md).

### Correctness fixes (M004)

- `superImage`/`super_image` now retain negative-offset partial overlaps rather
  than following the upstream absolute-offset early exit. Both crop APIs use
  overflow-safe bounds: far-outside superimages are transparent, invalid
  subimages raise `ArgumentError`, including Int-limit offsets.
- cmap format 12 retains the standard **16-byte** header (including language).
  Before expansion, reject inverted/non-Unicode ranges, glyph runs beyond uint16,
  declared lengths too short for the groups and truncated subtables. No altered
  header layout is adopted; the rejected candidate's 12-byte claim was false.
- Context and RecordingContext dash setters/getters copy vectors, preventing
  caller/getter aliases from mutating saved drawing state.
- HarfBuzz state is reused per live font without permanently retaining parsed
  fonts. Native bytes are copied; the owner is preserved through native use;
  buffers are released on errors as well as success. Published empty-object and
  allocation-failure states are checked. Explicit language input must be non-empty
  ASCII (not a full BCP47 validator). D033's pure-LTR paragraph limitation remains.

Evidence: existing image/font/context/recording/shaping suites plus **113
independent coordinator probes per Julia version**, including published-sentinel
and staged native-failure injection with GC/cleanup checks. See [Handoff](HANDOFF.md)
for exact gates and benchmark evidence; native leak freedom is not inferred from
Julia heap-allocation counters.

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
| `parseHtmlColor`, `parseSomePaint` | chroma, `pixie/paints.nim` | **implemented**: `#RGB`/`#RRGGBB`, numeric `rgb()`/`rgba()`, case-insensitive named CSS colors; unknown names and malformed input raise `ArgumentError` | test/context_tests.jl hex, named-color, and rgb/rgba parsing tests; T013 corrects the stale hex-only inventory |
| ordinary-number drawing arguments (Int/Float64 coordinates, `Vec2`/`Rect` constructors, blur/spread/opacity/shadow radii) | — (port addition, T014) | **implemented**: `Real` boundary overloads convert once to `Float32` and delegate to the specialized kernels (upstream Nim implicit conversions are approximated; keyword arguments such as `strokeWidth` remain `Float32`-typed) | test/numeric_api_tests.jl: byte-for-byte scene parity (plain vs `Float32` literals), conversion semantics, zero-extra-allocation dispatch |
| `toColors` / `fromColors` (ColorTypes matrices) | — (T015/D024, extended M003) | **implemented** (opt-in `ColorTypes`): export `Matrix{RGBA{N0f8}}` straight, `[row, col]`; import 2-D `RGB`/`RGBA` of N0f8 bytes or 0..1 floats (clamped); PNG-boundary conversions both ways. One-based range/strided views accepted without a source copy; top-level transposes materialized. Offset axes, index-array views, adjoints, views over transposes and 3-D planes rejected | test/colormatrices_tests.jl: orientation, channel order, premul/straight, round-trip bounds; test/api_native_tests.jl: views/axes/transpose; test/codec_loading_tests.jl core-only hint |

## Image operations and effects (T007a, T007b)

| Upstream symbol(s) | Area | Julia status | Evidence |
| --- | --- | --- | --- |
| `draw`, `drawTiled`, `getRgbaSmooth`, `magnifyBy2`, `minifyBy2`, `applyOpacity`, `subImage`, internal `blendRect`/`drawSmooth` | `pixie/images.nim` | **implemented** (T007a). Scalar; fast integer `blendRect` path and smooth inverse-transform sampling path; filter-by-2 normalization | test/image_ops_tests.jl; `draw_translate.raw`/`draw_scale2.raw` 0 mismatching bytes |
| `blur`, `shadow`, `resize`, `rotate90`, `flipHorizontal`/`flipVertical`, `invert`, `ceil`, `superImage`, `opaqueBounds`, `spread`, `diff`, `gaussianKernel` | `pixie/images.nim`, `pixie/internal.nim` | **implemented** (T007b, 2026-11-04). Scalar; pinned mixed-precision `gaussianKernel` (all 288 fixture weights exact), separable two-pass `blur`/`spread` with the transposed intermediate, MaskBlend `shadow`, `resize` via `draw` fast paths; `rotate90` returns the rotated image instead of mutating (D013); `ceil`/`diff` extend the Base generics (D013); the `subImage(image, rect)` overload is not ported (no call site yet) | test/image_ops_tests.jl "T007b image effects" (404 assertions, hand-derived); `gaussian_kernel.tsv` 16 radii × 288 weights, 0 mismatches |

## Images, formats, text (T006, T008, T009)

Optional PNG/JPEG/SVG/WebP packages are discovered lazily on first
use (D028, superseding D019's eager module-initialization load),
including when the
precompile cache was built in a core-only environment. Absent packages
still produce install hints on format use (decode and encode alike);
installed packages that fail to load propagate their actual error.
Evidence: `test/codec_loading_tests.jl` covers core-only cache reuse
followed by PNG, JPEG (decode and encode), WebP (decode and encode),
and SVG operations in the codec-enabled test environment.

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
  1/4/8/24/32-bit, bottom-up and top-down (negative height), masked alpha.
  E001/D038 corrects the encoder to a 124-byte BITMAPV5HEADER, pixel offset
  138, and 32-bit **bottom-up** rows. Masked file pixels are straight RGBA;
  decoding premultiplies into `Image`, encoding unpremultiplies. This deliberately
  differs from upstream's direct-store masked decoder and malformed 136-byte
  header. Pinned raw fixtures remain unchanged; corrected expectations apply
  independently specified `(channel * alpha + 127) ÷ 255` to their straight
  channels. Evidence: test/formats_tests.jl (5 pinned fixtures, handcrafted V5,
  optional Pillow interoperability), test/formats_synthetic_tests.jl and the
  independent 65,536-pixel check recorded in docs/HANDOFF.md.
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
  (`pixie/fileformats/jpeg.nim`) — **decode** (T008) via the opt-in
  `JpegTurbo` package (D014): marker scan with resync, FF-stuffing, Exif
  orientation 1-8 (dimensions orientation-aware); pixels differ from the
  upstream stb-derived fixtures by at most 8 per channel (recorded,
  measured on the 4 oracle fixtures). Evidence: test/formats_tests.jl.
  **Encoding is implemented** (T031, D032, docs/JPEG_WEBP_CODECS.md §2):
  `encodeJPEG` via the same opt-in `JpegTurbo` — premultiplied→straight
  composite over an explicit `background` (default white, exact integer
  formula), JFIF with contract-mandated 72×72 dpi density, quality
  1..100 (default 92), no EXIF/Adobe written, dimension bound 65500
  (the provider segfaults at 65501 — rejected before encode).
  Validation: hand-derived marker structure, PyMuPDF/mupdf 1.28.2
  independent-reader interop (page rect = dimensions at 72 dpi; max
  channel delta ≤ 8, measured 4) and a PSNR floor (≥ 40 dB at q92,
  measured 48.78 dB) — lossy, so never byte-exact. Also fixed a latent
  world-age defect in `decodeJPEG` found while validating: the
  N0f8→Float64 conversion now runs in an `invokelatest` kernel (D028
  pattern), so first-use JPEG decode in a fresh process works.
  Evidence: test/jpeg_encode_tests.jl (61 assertions incl. mupdf
  interop), test/formats_tests.jl (encode dispatch + six writable
  formats).
- base64: `encodeBase64` / `decodeBase64`
  (`pixie/imagebase64.nim`) — **implemented** (T008), native port: strict
  RFC-4648 validation, data-URL passthrough, PNG payload. Evidence:
  test/formats_tests.jl, test/formats_synthetic_tests.jl.
- WebP: `pixie/fileformats/webp.nim` — **implemented, static subset**
  (T032, D032, docs/JPEG_WEBP_CODECS.md §3; the T008 "deferred — no
  stable Julia package" wording is superseded: `WebP.jl` 0.1.3 +
  `libwebp_jll` 1.6.1+0, opt-in). Static read/write:
  `decodeWebP`/`decodeWebPDimensions` (success-checked feature scan
  first — the provider's own auto-decode ignores the scan return value;
  premultiplied conversion, RGB input → `a = 255`) and `encodeWebP`
  (always RGBA; lossy quality 0..100 default 75; lossless ignores
  quality — provider API; dimension bound 16383, the provider silently
  returns an empty vector at 16384). Animation raises a named
  `ArgumentError` **before** pixel decode (the provider decode crashes
  the process on animated input — verified on the pinned fixture).
  Validation: the 129-file pinned upstream libwebp corpus decodes at
  the upstream `test_webp.nim` dimensions (12 exact expectations),
  with corpus-wide alpha classification; lossless round-trips are
  byte-exact in the premultiplied API (alpha exact everywhere; RGB
  exact where `α > 0`; RGB forced to 0 where `α = 0` — the format
  leaves the straight color under full transparency unspecified,
  unobservable in premul); lossy validation is dimensions + PSNR
  floor, never bytes (no independent WebP decoder on the verification
  machine — recorded limitation). Evidence: test/webp_tests.jl
  (353 assertions incl. the corpus), test/formats_tests.jl (dispatch),
  test/codec_loading_tests.jl (opt-in loading).
- Dispatch: `decodeImage` / `encodeImage` / `readImage` / `readImageDimensions`
  / `writeFile` (`pixie/pixie.nim`) — **implemented** (T008): magic-byte
  dispatch for PNG/JPEG/BMP/QOI/GIF/PPM/SVG/WebP, extension-driven write
  for PNG/BMP/QOI/PPM/JPEG (T031)/WebP (T032) — only GIF writing still
  raises "Unsupported file format" (as upstream); WebP decode uses the
  RIFF+WEBP magic branch added in T032.
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

 - SVG write: `writeSvg(file, picture; rasterFallback)` (`Picture`
   recordings, T025) — **new capability** (no upstream writer; W3C SVG 1.1
   is the export reference; contract in docs/RECORDING.md §6.1). v1 exports:
   solid/linear/radial fills (Normal blend only), solid strokes (all
   caps/joins/miter limits/dash arrays — odd dash lists double, as in the
   raster), transforms as `matrix(…)` on the element, cumulative clips as
   one intersecting `clipPath` per group scope, nested groups with
   group-unit `opacity`, embedded images as base64 PNG data-URIs (opt-in
   `PNGFiles`, D014), text as glyph outline paths (no `<text>`), explicit
   `width`/`height`/`viewBox`. Strict by default: clearRect, angular /
   ImagePaint fills, non-Normal blends, coincident/degenerate gradient
   handles, stop positions outside [0, 1] or unsorted, non-finite
   geometry, and gradient fills under singular transforms each raise
   `ArgumentError` naming the op index before any file is written;
   `rasterFallback = true` renders the whole picture to one embedded
   `<image>` (identifiable by its data-URI; the PNGFiles opt-in applies).
   Gradient fills are exact for every invertible op transform via
   `gradientTransform` (linear: raw handles + `T^-1`; radial: unit circle +
   `T^-1 * M`, the raster's ellipse map). Known renderer difference: the
   SVG spec (and e.g. Chromium) draw round/square caps at interior dash
   ends, which the pinned raster does not (upstream `strokeShapes` caps
   only the shape ends) — the export is spec-faithful; only interior
   dash-end cap pixels differ from the replay. Read-back through the
   pinned reader is supplemental: it re-applies the element transform to
   `userSpaceOnUse` handles (exact at identity transforms), skips
   `clipPath`/`radialGradient`/`image` (radial fills raise "Missing SVG
   resource"), and multiplies group `opacity` into each child paint
   (per-child, not group-unit). Evidence: test/svg_export_tests.jl
   (333 assertions incl. a byte-exact document, hand-derived matrix /
   gradientTransform values, an independent XML structural parse, the
   pinned-reader read-back, and a headless-Chromium 156.0.8078.47 render
   with exact hand-derived geometry checks).
 - PDF write: `writePdf(file, picture; dpi = 96f0, rasterFallback)`
   (`Picture` recordings, T026) — **new capability** (no upstream
   writer; ISO 32000-2:2020 (PDF 1.4) is the export reference; contract
   in docs/RECORDING.md §6.2). Single page sized `W*72/dpi × H*72/dpi`
   pt, picture units mapped to points (top-left, y-down) by the root
   CTM — the export is scale-independent in `dpi`. v1 exports:
   solid/linear/radial fills (Normal blend only) as PDF shadings,
   solid strokes (all caps/joins/miter limits/dash arrays — odd dash
   lists double, as in the raster), transforms via `cm`, cumulative
   non-even-odd clips via `W n`, nested groups with group-unit alpha
   as isolated Form XObjects (`/Group /S /Transparency /I true` plus
   the group's `/ca` ExtGState in effect at `Do` time), embedded
   images as raw uncompressed RGB XObjects with a DeviceGray SMask
   (no codec dependencies; FlateDecode is a possible follow-up), text
   as glyph outline paths (no text objects, no font embedding),
   elliptical arcs flattened to <=90-degree cubic segments via the
   pinned `endpointToCenterArcParams` (k = (4/3)tan(d/4)), and
   quadratic segments emitted as the exact cubic equivalent (PDF has
   no quadratic path operator). Gradient stops: in-range, strictly
   increasing, opaque, as a FunctionType 3 stitching of Type 2
   segments (ISO 32000-2 defines no constant function type, so a
   single stop uses Type 2 with C0 == C1). Strict by default:
   clearRect, angular / ImagePaint fills, non-Normal blends, even-odd
   gradient fills, coincident/degenerate gradient handles, stop
   positions outside [0, 1], non-strictly-increasing or
   semi-transparent gradient stops, non-finite geometry, and gradient
   fills under singular transforms each raise `ArgumentError` naming
   the op index before any file is written; `rasterFallback = true`
    renders the whole picture to one embedded full-page image.
    E001/D038 fixes numeric serialization: ISO 32000-1 §7.3.3 forbids exponent
    notation. Finite floating-point numbers are expanded to decimal without
    rounding away small values or losing fractional large coordinates. SVG
    attributes retain their permitted exponent notation. Regression evidence:
    test/pdf_export_tests.jl, independent float-pattern checks and Poppler
    rendering recorded in docs/HANDOFF.md.
    E001 also corrects previously vertically flipped strict image operations
    and raster fallback. Placement matrices now account for PDF's implicit
    top-down-sample-to-y-up-unit-square transform (§8.9.4); RGB and alpha stay
    aligned. Asymmetric image, scale, rotation and alpha checks use rendered
    output, not just embedded stream bytes (D038, docs/RECORDING.md §6.2).
   Gradient fills are exact for every invertible op transform (linear:
   repelled element-space handles; radial: the CTM is exactly the
   raster's ellipse map, with the path emitted in `M^-1 o T` space).
   Known renderer differences: (a) `sh` paints the whole (clipped)
   user space, not the current path (ISO 32000-2 Table 76), so
   gradient fills clip with `W n` first; (b) the spec (and e.g.
   Chromium for SVG) draws round/square caps at interior dash ends,
   which the pinned raster does not — the export is spec-faithful;
   only interior dash-end cap pixels differ from the replay; (c)
   per-stop gradient alpha is not portably honored (a 4-component
   shading function over DeviceRGB is dropped or ignored by the
   pinned renderers), so it is a strict v1 error — uniform
   `paint.opacity` works via ExtGState `/ca`. Evidence:
   test/pdf_export_tests.jl (202 assertions: self-consistent document
   structure — xref offsets, stream Lengths, trailer — hand-derived
   geometry at pixel centers under gs 10.06.0 and
   poppler/pdftoppm 26.01.0, dpi scale independence, arc/quad
   flattening, group-clip structure, byte-exact image and SMask
   streams, byte-exact rasterFallback replay, strict errors with no
   file written). Radial shading pixel checks carry a +/-10 tolerance
   because the renderers sample shadings with renderer-specific
   sub-pixel offsets (the spec does not pin shading sampling); the
   group-unit alpha mechanism was pinned empirically against both
   verifiers on a hand-derived constant-alpha case before being
   trusted.
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
  single-run line-break algorithm and Unicode shaping stay out of scope
  for the legacy API (the additive T028 paragraph layer reuses the same
  line-break engine — see its row below).
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
 - Paragraph layout: `Paragraph`/`newParagraph`, `layoutParagraph`/
   `ParagraphLayout` (lines, clusters, `Arrangement`), `paragraphMetrics`,
   `fillParagraph`/`strokeParagraph` (Image and Context), `withFallback`
   (`src/formats/paragraph.jl`; D031, docs/TEXT_LAYOUT.md) — **implemented**
   (T028): additive over the T009 `Span`/`typeset` machinery (the layout
   pass is the pinned `typeset`; legacy `typeset`/`measureText`/
   `layoutBounds`/`computePaths`/`fillText`/`strokeText` are byte-unchanged,
   their suites green). Width/height box with `ClipOverflow` (default) /
   `EllipsisOverflow` (U+2026 when it fits the last line, plain clip
   otherwise), paragraph-level absolute `lineHeight`, existing alignment
   enums (effective only on constrained dimensions), styled runs (existing
   `Span`/`Font`), ordered font fallback via `withFallback` over
   `Typeface.fallbacks` (cycle-checked; `.notdef`/zero-advance missing
   glyph), and vendored UAX#29-subset grapheme clusters (BMP
   `Grapheme_Extend` + `Mc` tables, Unicode 16.0.0 provenance; ZWJ joins
   both sides, ZWNJ joins left only, Hangul `L V* T*`, control sequences).
   **Not supported** (v1, documented limits): UAX#14 mid-word/justified
   breaking (long unbreakable runs split character-wise at overflow — the
   pinned engine behavior), Unicode shaping and bidirectional text
   (superseded by the additive T029 shaper below — RTL no longer raises;
   complex scripts in pure-LTR paragraphs still draw unshaped, a named
   v1 engagement limit), regional indicators/skin tones/emoji beyond
   the cluster subset (one cluster per codepoint). Evidence:
   test/paragraph_tests.jl (22,761 assertions: hand-derived line boxes
   from Roboto hhea/hmtx, cluster cases, wrap/NBSP/char-split invariants,
   alignment offsets, clip + ellipsis pixel checks, image + context
   render, fallback cycles/termination); large-paragraph timing in
   tasks/T028-paragraph-layout.md.
 - Optional Unicode shaping and bidirectional text: `shapeText`/
   `ShapedGlyph`, `glyphPathByGid` (additive GID -> outline), and the
   `ParagraphLayout.shaped` logical->visual permutation
   (`src/formats/shaping.jl`; D033, docs/TEXT_LAYOUT.md §5/§7) —
   **implemented** (T029): an opt-in shaper over the
   `HarfBuzz_jll` artifact (harfbuzz 15.1.0) via a thin `ccall` surface
   (blob/face/font/buffer/`hb_shape`), loaded lazily on first shaped
   call (core-only and legacy-LTR installs never load it; a missing
   provider raises the explicit `ErrorException("Shaping support is
   opt-in: ...")`). Engagement: `RightToLeft` paragraphs and LTR
   paragraphs containing strong-RTL codepoints shape; pure-LTR complex
   scripts keep the T028 isolated-forms `typeset` rendering (named
   limit). Bidi is a documented UAX#9 simplification: strong runs take
   their own direction, neutrals/WS/controls/astral take the base,
   L2E digit runs keep LTR order under an RTL base, punctuation
   mirrors (Bidi_Mirroring), and the logical->visual permutation is
   exposed on `ParagraphLayout.shaped` (cluster indices stay logical).
   RTL placement uses the harfbuzz cairo-bridge pen model (forward pen
   in buffer order for both directions). Coverage pinned against an
   independent reference: system libharfbuzz **12.3.2** through the C
   driver `tools/oracle/hb_refshape.c` (no Julia in the loop), 10 cases
   in `test/reference/shaping_reference.tsv` over the pinned
   `NotoSansArabic-Regular.ttf` / `NotoSansDevanagari-Regular.ttf`
   (OFL 1.1, `test/fixtures/`) and `Roboto-Regular_1.ttf` (Apache-2.0);
   the JLL 15.1.0 and the 12.3.2 reference agree on all 10 cases.
   Demonstrates Arabic contextual joining (joined GIDs differ from the
   isolated cmap), a Devanagari conjunct (k + virama + ssa -> one
   ligature GID), a Latin ligature (Roboto `fi` -> one GID), combining
   marks (cluster merge, no silent drop), mixed RTL/LTR digits,
   missing-glyph -> `.notdef` (gid 0) with the font's `.notdef`
   advance, and RTL/LTR wrapping + alignment. **Not supported** (v1,
   documented limits): explicit bidi controls (RLO/LRI/...) inside
   text, full UAX#9 neutral-run analysis beyond segment reversal,
   vertical text, CFF/TTC/color fonts (rejected at parse, as T028),
   and shaped `EllipsisOverflow` (renders as plain clip — the ellipsis
   pass is `typeset`-based). Evidence: test/shaping_tests.jl (223
   assertions: 10 cases vs the pinned reference, `glyphPathByGid`,
   punctuation mirroring, hand-derived bidi permutations, RTL
   placement (cairo-bridge pen model), joined-vs-isolated forms,
   Indic conjuncts, ligatures, combining/missing glyphs, engagement);
   codec_loading_tests.jl (core-only + provider legs); the
   multilingual cookbook card (recipe 15).
   - Also fixed (T029): the T028 vendored UAX#29 cluster tables
     (`_CLUSTER_EXTEND`/`_CLUSTER_MC` in `paragraph.jl`) had a range
     misalignment that put base letters (Devanagari 0905/0915/0936,
     Myanmar 1000..100B) inside both tables; regenerated from the
     pinned Unicode 16.0.0 sources by
     `tools/oracle/gen_cluster_tables.py` and round-trip verified
     codepoint-exact (220 extend / 112 mc BMP ranges).

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
