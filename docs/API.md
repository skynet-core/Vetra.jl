# Public API

Vetra provides an immediate-mode CPU drawing context inspired by Canvas and
Flutter's `dart:ui`, with behavior from the pinned pixie revision. Start with
[Getting started](GETTING_STARTED.md) for executable examples; consult
[Compatibility](COMPATIBILITY.md) for supported inputs, deviations, and tests.
Names keep the upstream camelCase spelling. Future GPU and widget APIs are
not part of the current library. Display-list recording follows the
[Recording contract](RECORDING.md) (D030): recording, CPU replay, and SVG
export are implemented (T024–T025, see [Recordings](#recordings-d030-docsrecordingmd));
PDF export by T026.

## Coordinates, storage, and mutation

- Drawing coordinates: top-left origin, x right, y down, distances in pixels,
  angles in radians. Geometry uses `Float32`; pixel centers lie at `n + 0.5`.
- Context coordinate overloads accept ordinary Julia numbers (`Int`,
  `Float64`, …) as well as `Float32`; a `Real` boundary method converts once
  and delegates to the specialized `Float32` kernel, so callers pay no
  dynamic-dispatch cost (T014). Image dimensions and pixel indices remain
  `Int`. Keyword arguments (`strokeWidth = …`, gradient positions, …) are
  still typed `Float32` and need `2f0`-style literals.
- Pixel access (`getColor`, `setColor`) is 1-based. Crop offsets (`subImage`)
  and drawing coordinates start at 0.
- `Image.data` contains premultiplied RGBA `UInt8` bytes, row-major. Use
  `rgb`/`rgba` for straight colors and `rgbx` for premultiplied colors.
- `Image` has fixed dimensions and a mutable pixel buffer. `Path`, `Paint`,
  and `Context` are mutable; geometry and color structs are immutable.
- Drawing mutates its target. `blur`, `spread`, `invert`, `ceil`,
  `applyOpacity`, and flips mutate images despite having no `!` suffix.
  `copy`, `resize`, `rotate90`, `subImage`, `superImage`, and `shadow` return
  images. Use `copy(image)` when the original must survive an effect.
- Invalid arguments usually raise `ArgumentError`; checked pixel access
  raises `BoundsError`. A missing optional codec raises an install hint.

## Images and colors

`newImage(width, height)`, `width`, `height`, `inside`, `getColor`, `setColor`,
`fill(image, color)`, and `copy(image)` manage pixel buffers. `ColorRGB`,
`ColorRGBA`, and `ColorRGBX` distinguish opaque, straight, and premultiplied
colors. `toPremultipliedAlpha` and `toStraightAlpha` convert at boundaries;
`rgba(ColorRGBX)` follows a distinct upstream rounding path (see the
[numerical contract](NUMERICAL_CONTRACT.md)).

`parseHtmlColor` accepts `#RGB`, `#RRGGBB`, numeric `rgb(...)`/`rgba(...)`, and
named CSS colors. `rgba(255, 0, 0, 128)` uses byte alpha, while the string
`"rgba(255, 0, 0, 0.5)"` uses alpha from 0 to 1.

With the opt-in `ColorTypes` package (D024), `toColors(image)` exports an
image as a `Matrix{RGBA{N0f8}}` (straight alpha, `[row, col]`, row 1 = top)
and `fromColors(matrix)` imports 2-D `RGB`/`RGBA` matrices (N0f8 bytes or
0..1 floats, clamped) as a premultiplied `Image`. Both use the PNG boundary
conversions, so matrix bytes equal PNG payload bytes; 3-D plane matrices and
non-`Matrix` views are rejected with a clear error.

## Geometry and paths

- Geometry: `Vec2`, `Rect(x, y, width, height)`, `Circle`, `Segment`, `Line`,
  `Polygon`, and `Mat3`; helpers include `rect`, `circle`, `segment`, `line`,
  `dot`, `length`, `lengthSq`, `normalize`, and `snapToPixels`.
- Matrices: `mat3()` is identity; `translate(Vec2)`, `scale(Vec2)`, and
  `rotate(Float32)` create matrices. `A * B` applies B first. Unlike ordinary
  Julia matrices, `m[i, j]` indexes **column i, row j**. `inverse`,
  `determinant`, and `transpose` follow upstream arithmetic.
- Paths: `newPath()`/`Path()`, `moveTo`, `lineTo`, `quadraticCurveTo`,
  `bezierCurveTo`, `ellipticalArcTo`, `arc`, `arcTo`, `rect`, `roundedRect`,
  `ellipse`, `circle`, `polygon`, `closePath`, `addPath`, and `transform`.
- `parsePath(string)` reads SVG path commands. `computeBounds` measures
  geometry. Fill rules are `WindingRule` values `NonZero` and `EvenOdd`.
- `fillPath(image, path, paint; windingRule = NonZero, transform = mat3())`
  draws without a context. `strokePath` supplies stroke width, caps, joins,
  miter limit, and dashes through keywords (solid paints).

## Context

`Context(image)` draws into an existing image; `Context(width, height)`
creates one. Drawing settings:

| Setting | Meaning |
| --- | --- |
| `fillStyle`, `strokeStyle` | Paint, color, or supported color string |
| `globalAlpha` | Drawing opacity (0–1) |
| `lineWidth`, `miterLimit` | Stroke dimensions |
| `lineCap` | `ButtCap`, `RoundCap`, `SquareCap` |
| `lineJoin` | `MiterJoin`, `RoundJoin`, `BevelJoin` |
| `font`, `fontSize` | Font file path and size |
| `textAlign`, `textBaseline` | Text alignment and baseline |
| `lineDash` | Dash lengths; also `setLineDash`/`getLineDash` |

Drawing methods include `fillRect`, `strokeRect`, `clearRect`, `fill`,
`stroke`, `strokeSegment`, `drawImage`, `fillText`, and `strokeText`.
`beginPath` and context path builders operate on the current path; `fill`
and `stroke` also accept an explicit `Path`.

`save`/`restore` preserve drawing settings; `saveLayer`/`restore` additionally
composite an offscreen layer. An unmatched `restore` raises `ArgumentError`.
The current path and `textBaseline` are not saved (upstream semantics).
`clip` intersects with a path in image coordinates, ignoring the context
transform. `isPointInPath` tests filled geometry; `isPointInStroke` is absent.

Use `translate`, `scale`, `rotate`, `transform`, `getTransform`, `setTransform`,
and `resetTransform` for the current transform. `drawImage` supports position,
destination-size, and source-rectangle overloads; the latter preserves the
upstream implementation's behavior (see source and compatibility tests).

## Paints and compositing

`Paint(color)` creates a solid paint. For options use a straight RGBA color:
`Paint(rgba(255, 0, 0, 128); opacity = 0.5f0, blendMode = MultiplyBlend)`.
`Paint(image; imageMat = mat3())` creates an image paint. `Paint(kind)` creates
one of `SolidPaint`, `ImagePaint`, `TiledImagePaint`, `LinearGradientPaint`,
`RadialGradientPaint`, or `AngularGradientPaint`.

Paint fields are `kind`, `color`, `opacity`, `blendMode`, `image`, `imageMat`,
`gradientHandlePositions`, and `gradientStops`. Create stops with
`colorStop(color, position::Float32)`. Copying a paint copies its gradient
arrays but shares its referenced image.

`NormalBlend` is source-over. Other modes include `MultiplyBlend`,
`ScreenBlend`, `OverlayBlend`, hue/saturation/color/luminosity blends,
`OverwriteBlend`, `MaskBlend`, `SubtractMaskBlend`, and `ExcludeMaskBlend`.
`draw`/`drawTiled` composite images with a transform and blend mode.

## Fonts, text, and formats

`readTypeface`, `readFont`, `newFont`, `newSpan`, `typeset`, `layoutBounds`,
`computePaths`, `fillText`, `strokeText`, and `measureText` cover native
TTF/glyf parsing, metrics, kerning, layout, and glyph drawing. CFF outlines,
TTC collections, SVG fonts, and general Unicode shaping are unsupported.

Paragraph layout is **implemented** (T028; D031, docs/TEXT_LAYOUT.md):
additive `Paragraph`/`newParagraph`, `layoutParagraph`/`ParagraphLayout`
(lines, clusters, and the underlying `Arrangement`), `paragraphMetrics`,
`fillParagraph`/`strokeParagraph` (Image and Context), and `withFallback`
on top of the existing `Span`/`typeset` machinery — width/height/overflow
box (`ClipOverflow` default, `EllipsisOverflow`), v1 wrapping (white-space
set incl. NBSP + explicit `\n`; long unbreakable runs split
character-wise at overflow; no UAX#14 mid-word breaking), paragraph-level
line height, existing alignment enums (effective on constrained
dimensions), styled runs (existing `Span`/`Font`), fallback via the
existing `Typeface.fallbacks` chain (cycle-checked) with a
`.notdef`/zero-advance missing-glyph policy, metrics, and vendored
UAX#29-subset grapheme clusters (codepoint-indexed). Shaping and
bidirectional text are specified (shaper interface, GID → outline
mapping, UAX#9 direction model) but **implementation is provider-gated
(T029 blocked)**: no maintained Julia shaping package exists in the
registry as of 2026-11-09. Until then, RTL paragraphs raise a named
`ArgumentError` and complex scripts draw without joining. Legacy
single-line behavior is unchanged.

`readImage`/`decodeImage` detect formats by contents; `writeFile` selects by
extension, and `encodeImage` accepts a `FileFormat`. PNG read/write requires
`PNGFiles`; JPEG read/write requires `JpegTurbo`; SVG parsing requires
`XML`. BMP/QOI/PPM read/write and GIF decode are native. JPEG writing and
WebP read/write are specified by the T030 codec contracts
(docs/JPEG_WEBP_CODECS.md, D032) and implemented by T031 (JPEG encoding:
`encodeJPEG` — premultiplied→straight composite over an explicit
background, JFIF 72 dpi, quality 1..100) and T032 (static WebP:
`decodeWebP`/`decodeWebPDimensions`/`encodeWebP` — animation raises a
named error before decode). Until those ship, JPEG/WebP writes and WebP
decoding still raise; GIF writing remains unsupported (D014).
`encodeBase64` uses a PNG payload; `decodeBase64`
accepts a payload of any format `decodeImage` recognizes.

`parseSvg` plus `newImage(svg)` rasterizes the supported SVG subset. See
[Compatibility](COMPATIBILITY.md) for per-format details rather than
inferring support from a file extension.

## Recordings (D030, docs/RECORDING.md)

Drawing recordings are implemented (T024); the SVG exporter is implemented
(T025); the PDF exporter is implemented (T026).

- `PictureRecorder(width, height)` — one-shot; `recorder.ctx` is a
  `RecordingContext` mirroring the `Context` drawing methods
  (`fill`, `stroke`, `clip`, `saveLayer`, `drawImage`, `fillText`, …).
  Recording stores deep snapshots (paths, paints, images; text lowered to
  glyph outlines), so a `Picture` is self-contained.
- `finishRecording(recorder)` → `Picture`; `drawPicture(image, picture;
  tform = mat3())` replays on the CPU — default-size replay is
  byte-identical to direct drawing; other sizes scale the logical canvas
  in vector space (re-rasterized, never a raster enlargement).
- `writeSvg(file, picture; rasterFallback = false)` → the SVG document
  text. Strict by default: the first unexportable op (clearRect, angular /
  ImagePaint fills, non-Normal blends, out-of-range or unsorted gradient
  stops, non-finite geometry) raises `ArgumentError` naming the op index
  and no file is written; `rasterFallback` renders the whole picture to a
  single embedded `<image>` instead. SVG v1: solid/linear/radial fills
  (gradients exact for invertible op transforms), solid strokes (caps,
  joins, miter limit, dashes), transforms, `clipPath` (multiple clip
  children intersect), nested groups with group-unit `opacity`, embedded
  PNG data-URI images (opt-in `PNGFiles`, D014), and glyph outline paths —
  no `<text>`. See [Compatibility](COMPATIBILITY.md) for the v1 matrix and
  `rasterFallback` notes, and [docs/RECORDING.md](RECORDING.md) §6 for the
  contract.
- `writePdf(file, picture; dpi = 96f0, rasterFallback = false)` → the PDF
  document bytes. Single-page PDF 1.4; page size is `W*72/dpi × H*72/dpi`
  points, so `dpi` sets the physical scale of the same vector content
  (scale-independent). Strict by default: the first unexportable op
  (clearRect, angular / ImagePaint fills, non-Normal blends, even-odd
  gradient fills, degenerate gradients, out-of-range, non-strictly-
  increasing, or semi-transparent gradient stops, non-finite geometry,
  gradients under singular transforms) raises `ArgumentError` naming the
  op index and no file is written; `rasterFallback` renders the whole
  picture to one embedded image instead. PDF v1: solid/linear/radial
  fills (PDF shadings — gradients exact for invertible op transforms),
  solid strokes (caps, joins, miter limit, dashes), transforms,
  non-`even-odd` clips, nested groups with group-unit alpha (isolated
  Form XObjects), embedded uncompressed image XObjects with SMask, and
  glyph outline paths — no text objects, no font embedding, no
  even-odd gradient fills, no angular fills. See
  [Compatibility](COMPATIBILITY.md) for the v1 matrix and `rasterFallback`
  notes, and [docs/RECORDING.md](RECORDING.md) §6.2 for the contract.

Tiled-image fills and non-solid strokes are not recordable (record-boundary
`ArgumentError`); the immediate `Context` is unchanged and still supports
them for raster drawing.
