# Migrating to the Julia-native API (M003)

Vetra's public API is now idiomatic Julia: **snake_case** entry points, with
**`!`** on the ones that mutate state. The legacy camelCase names from the
pinned treeform/pixie port **remain callable and behave exactly as before**;
this layer is additive.

## What the new names are

- Most new names are **`const` bindings to the same generic function** as the
  legacy name (`fill_rect! === fillRect`). There are no duplicated kernels:
  dispatch, inference, allocation, and results are identical, and the legacy
  name keeps working.
- A generic that mixes mutating and allocating methods gets a **typed
  adapter** instead of a const alias, so no `!` name ever advertises a pure
  or allocating overload: `ceil!` (Image-only), `rect!`, `translate!`,
  `scale!`, `rotate!`, `transform!` (context/recording/path forms),
  `circle!`.
- `fill!` and `rotate!` are defined as **methods of the Base / LinearAlgebra
  generics** (identical bindings), so `using Vetra` cannot make them
  ambiguous for users of `Base.fill!` or `LinearAlgebra.rotate!`.
- `dot` and `normalize` **are** the actual LinearAlgebra generics (imported
  into Vetra before the `Vec2` methods are defined), so `using Vetra,
  LinearAlgebra` resolves both to the identical binding in either load
  order.

## Image constructor and array interface

`Image(width, height)` and `Image(width, height, data)` are validated
**inner constructors** and the only construction path (the `Image` layout
stays 3 fields: `width`, `height`, `data`). They check positive dimensions,
a range-checked `4 * width * height` byte count (the guard fires before the
multiplication, which wraps instead of throwing on this platform), and — for
supplied storage — an exact data length. `newImage` delegates to the 2-arg
constructor; every internal construction site (`Base.copy`, the decoders,
...) goes through the same validated constructors. (The zero-dimension PPM
decode is now rejected here, at the constructor root.)

`Image` exposes a duck-typed 2-D interface (it is deliberately **not** an
`AbstractMatrix`):

| call | meaning |
|---|---|
| `img[row, column]` | matrix order — row 1 is the top scanline; returns `ColorRGBX` |
| `img[i]` | pixel `i` in row-major order (1 = top-left) |
| `img[begin]` / `img[end]` | first / last linear index — the top-left / bottom-right pixel |
| `img[row, column] = c` | set a `ColorRGBX` pixel (in place) |
| `img[i] = c` | linear-order mutation (inverse of `img[i]`; valid for every `i` in `eachindex(img)`) |
| `for c in img` | pixels in storage order, top-left first |
| `fill!(img, c)` | fill the whole image (all three color types) |
| `size(img)` / `size(img, d)` | `(height, width)`; `d = 1` → height, `d = 2` → width, `d > 2` → 1, `d <= 0` → `ArgumentError` (standard dimension convention) |
| `axes(img)` / `ndims(img)` / `eltype(img)` / `length(img)` | `(OneTo(height), OneTo(width))`, `2`, `ColorRGBX`, `width * height` |
| `eachindex(img)` | the row-major linear indices `1:width*height` — the same order as `img[i]` and the storage-order iteration |
| `copy(img)` | deep copy (validated) |

All orders are consistent: `img[row, column]` maps to linear index
`(row - 1) * width + column`, which is exactly what `eachindex` yields, so
vectorized `img[i]` reads and `img[i] = c` writes over `eachindex` are
row-major (top-left first). Out-of-range linear or `row, column` access
raises `BoundsError`; `size(img, d > 2)` returns 1 and `size(img, d <= 0)`
raises `ArgumentError`, as for standard matrices. Storage itself is never
changed by this interface.

**Coordinate conventions.** Array-style access is `img[row, column]`; the
legacy `getColor(img, x, y)` / `setColor(img, x, y, c)` keep 1-based
`(x, y)` order — `img[y, x] == getColor(img, x, y)`. `subImage` /
`superImage` keep the upstream 0-based `(x, y, w, h)` parameters.

**Premultiplied vs straight alpha.** `Image` stores premultiplied-alpha
RGBA bytes. `toColors` exports straight-alpha `RGBA{N0f8}` (the PNG export
boundary); `fromColors` imports straight `RGB`/`RGBA` (bytes or 0..1
floats) and stores them premultiplied (the PNG decode boundary).

## Vec2 / Mat3 standard-library entry points

`Vec2` is deliberately **not** an `AbstractVector`. The upstream vmath
`length(v)` (Euclidean, Float32) remains the legacy entry point; the
idiomatic quantities go through the standard libraries, reusing the same
formulas:

| call | legacy equivalent |
|---|---|
| `dot(a, b)` (LinearAlgebra generic) | `dot(a, b)` — identical binding |
| `LinearAlgebra.norm(v)` | `length(v)` |
| `normalize(v)` (LinearAlgebra generic) | `normalize(v)` — identical binding |
| `LinearAlgebra.det(m)` | `determinant(m)` |
| `inv(m)` (Base) | `inverse(m)` |
| `rotate!(ctx, angle)` (LinearAlgebra generic) | `rotate(ctx, angle)` |

`normalize` of the zero `Vec2` still yields NaN components (no guard, as
upstream); a singular `Mat3` still yields ±Inf/NaN from `inv` (no guard, as
upstream).

## `fromColors` widening

`fromColors` / `from_colors` accept any one-based `AbstractMatrix` of
ColorTypes `RGB`/`RGBA`: plain matrices, `view`s (contiguous or strided,
no copy), and top-level `transpose`s (materialized as a permuted matrix).
Inputs with **non-one-based axes**, views selected by **index arrays**,
**adjoints**, and **views built over a transpose** raise an explicit
`ArgumentError`; `copy` them first. 3-D plane layouts are still rejected.
The premultiplication rounding is unchanged.

## Naming table

"New" is the idiomatic name; the legacy name stays callable.

### Images and pixel access

| legacy | new | kind |
|---|---|---|
| `newImage` | `new_image` | allocating (also: `Image(w, h)`, `Image(w, h, data)` constructors) |
| `minifyBy2` | `minify_by2` | allocating |
| `magnifyBy2` | `magnify_by2` | allocating |
| `rotate90` | `rotate_90` | allocating |
| `subImage` | `sub_image` | allocating (0-based params) |
| `superImage` | `super_image` | allocating (0-based params) |
| `opaqueBounds` | `opaque_bounds` | allocating |
| `strokeShapes` | `stroke_shapes` | pure |
| `getRgbaSmooth` | `get_rgba_smooth` | pure |
| `gaussianKernel` | `gaussian_kernel` | pure |
| `resize`, `shadow`, `diff`, `mix`, `width`, `height`, `inside`, `copy` | unchanged | already snake |
| `fill` (image) | `fill!` | mutating |
| `getColor` / `setColor` | `get_color` / `set_color!` | `get_color` pure, `(x, y)` order; `set_color!` mutating |
| `flipHorizontal` / `flipVertical` | `flip_horizontal!` / `flip_vertical!` | mutating |
| `invert` | `invert!` | mutating |
| `blur` | `blur!` | mutating |
| `spread` | `spread!` | mutating |
| `applyOpacity` | `apply_opacity!` | mutating |
| `ceil` | `ceil!` | mutating (Image-only adapter) |
| `draw`, `drawTiled`, `drawImage` | `draw!`, `draw_tiled!`, `draw_image!` | mutating |

### Geometry

| legacy | new | kind |
|---|---|---|
| `dot`, `length`, `normalize`, `perpendicular`, `mat3`, `determinant`, `inverse`, `transpose`, `snapToPixels` | `dot`, `length`, `normalize`, `perpendicular`, `mat3`, `determinant`, `inverse`, `transpose`, `snap_to_pixels` | pure (see the Vec2/Mat3 table above for the standard-library entry points) |
| `lengthSq` | `length_sq` | pure |
| `translate`, `scale`, `rotate` (geometry constructors), `transform(m, v)` / `transform(m, r)` | unchanged | allocating / pure |
| `xy`, `wh`, `left`, `top`, `right`, `bottom`, `circle(pos, r)`, `segment`, `line`, `rect(x, y, w, h)` / `rect(pos, size)` | unchanged | pure / allocating |

### Paths

| legacy | new | kind |
|---|---|---|
| `newPath` | `new_path` | allocating |
| `parsePath` | `parse_path` | pure |
| `computeBounds` | `compute_bounds` | pure |
| `addPath`, `beginPath`, `closePath`, `moveTo`, `lineTo`, `bezierCurveTo`, `quadraticCurveTo`, `ellipticalArcTo`, `arcTo`, `arc`, `roundedRect`, `ellipse`, `polygon` | `add_path!`, `begin_path!`, `close_path!`, `move_to!`, `line_to!`, `bezier_curve_to!`, `quadratic_curve_to!`, `elliptical_arc_to!`, `arc_to!`, `arc!`, `rounded_rect!`, `ellipse!`, `polygon!` | mutating (Path / Context / RecordingContext) |
| `circle` (path/context form) | `circle!` | mutating (typed adapter — the geometry constructor `circle(pos, r)` stays un-banged) |
| `rect` (path/context/recording form) | `rect!` | mutating (typed adapter; the `clockwise` keyword is preserved on the Path form — the `rect(x, y, w, h)` / `rect(pos, size)` constructors stay un-banged) |
| `transform(path, mat)` | `transform!(path, mat)` | mutating (typed adapter — the point/rect forms stay un-banged) |
| `fillPath`, `strokePath`, `fillShapes` | `fill_path!`, `stroke_path!`, `fill_shapes!` | mutating |
| `isPointInPath` | `is_point_in_path` | pure |

### Context state

| legacy | new | kind |
|---|---|---|
| `save`, `saveLayer`, `restore`, `clip` | `save!`, `save_layer!`, `restore!`, `clip!` | mutating |
| `setTransform`, `resetTransform`, `setLineDash` | `set_transform!`, `reset_transform!`, `set_line_dash!` | mutating |
| `getTransform`, `getLineDash` | `get_transform`, `get_line_dash` | pure |
| `translate`, `scale`, `rotate`, `transform` (context/recording form) | `translate!`, `scale!`, `rotate!`, `transform!` | mutating (typed adapters) |
| `fill` (context form), `stroke` | `fill!`, `stroke!` | mutating |
| `fillRect`, `strokeRect`, `clearRect`, `strokeSegment` | `fill_rect!`, `stroke_rect!`, `clear_rect!`, `stroke_segment!` | mutating |

### Colors and blends

| legacy | new | kind |
|---|---|---|
| `rgb`, `rgba`, `rgbx` | unchanged | allocating |
| `toStraightAlpha`, `toPremultipliedAlpha` | `to_straight_alpha`, `to_premultiplied_alpha` | pure |
| `blendAlpha`, `blendNormal` | `blend_alpha`, `blend_normal` | pure |
| `blendDarken` … `blendExcludeMask` (17 functions) | `blend_darken` … `blend_exclude_mask` | pure |
| `blender`, `mix` | unchanged | pure |
| `sRBG`, `Linear` | `srgb`, `Linear` | constants |
| `srgbToLinear`, `qoiHash` | `srgb_to_linear`, `qoi_hash` | pure |

### Paints

| legacy | new | kind |
|---|---|---|
| `newPaint`, `colorStop`, `parseHtmlColor` | `new_paint`, `color_stop`, `parse_html_color` | pure |
| `fillGradient` | `fill_gradient!` | mutating (fills the image) |

### Text

| legacy | new | kind |
|---|---|---|
| `newFont`, `newSpan`, `readFont`, `readTypeface` | `new_font`, `new_span`, `read_font`, `read_typeface` | allocating |
| `parseTtf`, `parseOtf`, `parseOpenType` | `parse_ttf`, `parse_otf`, `parse_open_type` | pure |
| `typeset`, `name` | unchanged | pure |
| `layoutBounds`, `measureText`, `computePaths` | `layout_bounds`, `measure_text`, `compute_paths` | pure |
| `fillText`, `strokeText` | `fill_text!`, `stroke_text!` | mutating |
| `autoLineHeight`, `defaultLineHeight`, `lineGap`, `lineHeight`, `capHeight` | `auto_line_height`, `default_line_height`, `line_gap`, `line_height`, `cap_height` | pure |
| `hasGlyph`, `fallbackTypeface`, `getGlyphPath`, `getAdvance`, `glyphPathByGid`, `getKerningAdjustment`, `getLeftSideBearing`, `isCCW`, `withFallback`, `shapeText` | `has_glyph`, `fallback_typeface`, `get_glyph_path`, `get_advance`, `glyph_path_by_gid`, `get_kerning_adjustment`, `get_left_side_bearing`, `is_ccw`, `with_fallback`, `shape_text` | pure |
| `newParagraph`, `layoutParagraph`, `paragraphMetrics` | `new_paragraph`, `layout_paragraph`, `paragraph_metrics` | allocating / pure |
| `fillParagraph`, `strokeParagraph` | `fill_paragraph!`, `stroke_paragraph!` | mutating |

### Recordings

| legacy | new | kind |
|---|---|---|
| `PictureRecorder`, `RecordingContext` | unchanged | constructors |
| `finishRecording` | `finish_recording!` | mutating — returns a `Picture` and **consumes** the recorder (drawing on it afterwards raises `ArgumentError`) |
| `drawPicture` | `draw_picture!` | mutating |

### IO and interop

| legacy | new | kind |
|---|---|---|
| `readImage`, `readImageDimensions` | `read_image`, `read_image_dimensions` | allocating |
| `decodePPM`, `decodePPMDimensions`, `decodePNG`, `decodePNGDimensions`, `decodeBMP`, `decodeBMPDimensions`, `decodeDIB`, `decodeQOI`, `decodeQOIDimensions`, `decodeGIF`, `decodeGIFDimensions`, `decodeJPEG`, `decodeJPEGDimensions`, `decodeWebP`, `decodeWebPDimensions`, `decodeImage`, `decodeImageDimensions` | `decode_ppm`, `decode_ppm_dimensions`, `decode_png`, `decode_png_dimensions`, `decode_bmp`, `decode_bmp_dimensions`, `decode_dib`, `decode_qoi`, `decode_qoi_dimensions`, `decode_gif`, `decode_gif_dimensions`, `decode_jpeg`, `decode_jpeg_dimensions`, `decode_webp`, `decode_webp_dimensions`, `decode_image`, `decode_image_dimensions` | pure / allocating |
| `encodePPM`, `encodePNG`, `encodeBMP`, `encodeQOI`, `encodeJPEG`, `encodeWebP`, `encodeImage`, `encodeBase64`, `decodeBase64` | `encode_ppm`, `encode_png`, `encode_bmp`, `encode_qoi`, `encode_jpeg`, `encode_webp`, `encode_image`, `encode_base64`, `decode_base64` | pure — **return types are unchanged** (no silent `String` → `Vector{UInt8}` conversions) |
| `writeFile`, `writePPM`, `writeSvg`, `writePdf` | `write_file!`, `write_ppm!`, `write_svg!`, `write_pdf!` | mutating (file output) |
| `parseSvg`, `parseHtmlColor` | `parse_svg`, `parse_html_color` | pure |
| `toColors`, `fromColors` | `to_colors`, `from_colors` | allocating |
| `miterLimitToAngle`, `angleToMiterLimit`, `defaultMiterLimit` | `miter_limit_to_angle`, `angle_to_miter_limit`, `default_miter_limit` | pure |

### Constants (no rename)

PascalCase singletons are already Julia-idiomatic and keep their names:
file formats (`PngFormat`, `BmpFormat`, `JpegFormat`, `GifFormat`,
`QoiFormat`, `PpmFormat`, `WebpFormat`), blend modes (`NormalBlend` …
`ExcludeMaskBlend`), line caps (`ButtCap`, `RoundCap`, `SquareCap`), line
joins (`MiterJoin`, `RoundJoin`, `BevelJoin`), alignments (`LeftAlign`,
`CenterAlign`, `RightAlign`, `TopAlign`, `MiddleAlign`, `BottomAlign`),
text case (`NormalCase`, `UpperCase`, `LowerCase`, `TitleCase`),
baselines (`TopBaseline` … `BottomBaseline`), overflow (`ClipOverflow`,
`EllipsisOverflow`), direction (`LeftToRight`, `RightToLeft`), winding
(`NonZero`, `EvenOdd`). The one exception is `sRBG` → `srgb`.

Struct and type names (`Image`, `Vec2`, `Mat3`, `Context`, `Path`,
`Paint`, `Picture`, `Font`, `Paragraph`, …) and struct field access
(`ctx.fillStyle`, `img.data`, …) are unchanged.

## Package metadata

`Project.toml` now declares the optional providers as **weakdeps** with
**compat** bounds (`ColorTypes`, `PNGFiles`, `XML`, `JpegTurbo`, `WebP`,
`HarfBuzz_jll`) and the runtime standard-library dependencies
(`Libdl`, `LinearAlgebra`). Loading stays lazy: a core-only environment
loads Vetra without any provider, and each opt-in feature raises its
install hint on first use, exactly as before.
