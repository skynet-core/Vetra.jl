# Public API design (Flutter-inspired)

Status: binding for T003 onward (D011). T002 (colors, `Image`, compositing) is
already implemented as described in D010 and is not changed by this document.

Principle: **Flutter/dart:ui supplies the API shape and ergonomics; the pinned
pixie sources supply the semantics and numerics.** Where the two disagree, the
port follows pixie and documents the mapping here. Names keep upstream
chroma/pixie/vmath spelling (camelCase, e.g. `newImage`, `fillRect`) so every
public symbol stays traceable to the reference tree.

## Mapping from Flutter / dart:ui

| Flutter / dart:ui | Vetra.jl | Note |
| --- | --- | --- |
| `Offset` | `Vec2` | vmath name; immutable `Float32` x/y; point *and* delta |
| `Size` | `Vec2` (width/height usage) | no separate type until a task needs one |
| `Rect` (LTRB) | `Rect(x, y, w, h)` | upstream bumpy layout; `left/top/right/bottom` accessors are derived |
| `RRect` | `RoundedRect` | T004, only if upstream `roundedRect` needs the value type |
| `Matrix4` | `Mat3` | affine 3x3, column-major; `A * B` applies B first (same as Matrix4) |
| `Canvas` | `Context` | immediate-mode, draws into an `Image`; stateful (`fillStyle`, `strokeStyle`, transform, clip) like HTML canvas |
| `Paint` | `Paint` | mutable value object; `blend_mode`, `opacity`, solid/image/gradient kinds |
| `Path` | `Path` | same command vocabulary; `PathFillRule` = upstream `WindingRule` |
| `BlendMode` | `BlendMode` | W3C modes; upstream enum names (`NormalBlend` = Flutter `srcOver`) |
| `ui.Image` | `Image` | **mutable** premultiplied RGBA buffer (draw target), not immutable |
| `Picture` / `PictureRecorder` | —— | reserved backend seam (D007); not implemented yet |
| `Paragraph` / `TextStyle` | `Font` + `Context.fillText` | Flutter text-layout names reserved for T009 if widget-style layout is added |
| `ClipOp.intersect` | `clip(path)` | upstream always intersects; no `difference` clip yet |

## Conventions

- **Coordinates**: continuous, origin at the top-left, x right, y down, angles
  in radians, distances in pixels. Geometry is `Float32` (upstream vmath
  `Vec2`/`Mat3` are `Float32`). Pixel centers are at `n + 0.5`.
- **Image pixel access** (`getColor`/`setColor`, T002) stays 1-based
  integer pixel addressing (D010); it is a storage-inspection API, not the
  drawing coordinate system. Drawing always uses the continuous coordinates
  above.
- **Color storage**: premultiplied RGBA `UInt8`, row-major, in `Image.data`.
  Constructors accept straight alpha; conversion happens at the storage
  boundary.
- **Mutability**: geometry and `Paint` are value types; `Path`, `Context` and
  `Image` are mutable. Drawing mutates the target image; `copy(image)` is the
  isolation primitive.
- **Errors**: bad arguments → `ArgumentError`; out-of-range pixel/array access
  → `BoundsError`; unbalanced `Context.restore` → `ArgumentError` (upstream
  raises `PixieError`; the Julia mapping is recorded per task).
- **No placeholder APIs**: a symbol appears in `export` only when implemented
  and tested. Unimplemented Flutter concepts stay in this table, not in code.

## Geometry (T003)

```julia
struct Vec2; x::Float32; y::Float32; end
struct Rect; x::Float32; y::Float32; w::Float32; h::Float32; end
struct Circle; pos::Vec2; radius::Float32; end
struct Segment; at::Vec2; to::Vec2; end          # bumpy, used by strokes
struct Line; a::Vec2; b::Vec2; end
const Polygon = Vector{Vec2}
struct Mat3; ... end                              # 9 Float32, column-major
```

- `Vec2`: `+`, `-`, unary `-`, `*`/`/` by scalar, `dot`, `length`, `lengthSq`,
  `normalize`, `perpendicular`; `Vec2(x, y)` and `Vec2()` = zero.
- `Rect`: `x/y/w/h` fields (upstream bumpy layout); `rect(x,y,w,h)`,
  `rect(pos, size)`, `xy`, `wh`, `+`, `*`//`/` by scalar, `|`/`&` union and
  intersection (upstream `or`/`and`); derived `left/top/right/bottom`
  accessors are the only Flutter-style sugar. Anything else (contains,
  inflate, …) is added by the task that needs it, not speculatively.
- `Mat3`: `mat3()` identity; `translate(v)`, `scale(v)`, `rotate(angle)`,
  `inverse`, `transpose`, `determinant`, `m[i, j]` (1-based indices, column
  first), `m * v` (affine point transform), `m * n` (composition: `n` first).
- `transform(m, v)` / `transform(m, rect)` helpers for explicit calls.
- Test expectations: hand-computed matrices plus upstream vmath source
  semantics; transform composition is checked against
  `Matrix * Point` order and the `draw_translate`/`draw_scale2` fixtures are
  exercised once paths exist (T004/T006).

## Paths and rasterization (T004)

- `Path()` (upstream `newPath`), `copy(path)`; commands `moveTo`, `lineTo`,
  `quadraticCurveTo`, `bezierCurveTo`, `arc`, `arcTo`, `rect`, `roundedRect`,
  `ellipse`, `circle`, `polygon`, `closePath`, `addPath`; `transform(path, m)`;
  `parsePath(string)`.
- `PathFillRule` (`NonZero`, `EvenOdd`) mirrors upstream `WindingRule`.
- Rasterization: `fillPath(image, path, paint, fillRule)` and the `Context`
  wrappers `fill`/`clip`; coverage values come from `computeCoverage`
  (fixture `snap_to_pixels.tsv` governs rectangle snapping/rounding).
- Path handles are validated (no segments after `close` unless reopened);
  numeric expectations come from the pinned `paths.nim` algorithms.

## Context / drawing (T005, T010)

- `Context(image)` (upstream `newContext`; also `Context(width, height)`).
- State: `fillStyle`, `strokeStyle` (`Paint`), `globalAlpha`, `lineWidth`,
  `miterLimit`, `lineCap` (`ButtCap`/`RoundCap`/`SquareCap`), `lineJoin`
  (`MiterJoin`/`RoundJoin`/`BevelJoin`), `transform` (`Mat3`), `font`,
  `fontSize`, `textAlign`, `textBaseline`, `lineDash` (T010).
- Methods: `save`, `restore`, `saveLayer`, `translate`, `scale`, `rotate`,
  `transform`, `setTransform`, `getTransform`, `resetTransform`, `clip`,
  `beginPath`, path commands, `fill`, `stroke`, `fillRect`, `strokeRect`,
  `clearRect`, `draw`/`drawImage`, `fillText`, `strokeText`, `measureText`,
  `isPointInPath` (T010).
- `save`/`restore` copies paint/transform/clip state; unbalanced `restore`
  raises `ArgumentError`. Winding/clip semantics follow upstream `contexts.nim`.

## Paint and blend modes (T007)

- `Paint(kind)`: kinds `SolidPaint`, `ImagePaint`, `TiledImagePaint`,
  `LinearGradientPaint`, `RadialGradientPaint`, `AngularGradientPaint`
  (upstream `paints.nim`); fields `blend_mode`, `opacity`, `color`, `image`,
  `image_transform`, `gradient_handles`, `gradient_stops` (upstream names
  adapted to Julia fields); `colorStop(paint, position, color)`.
- `BlendMode` enum: upstream order `NormalBlend, DarkenBlend, MultiplyBlend,
  ColorBurnBlend, LightenBlend, ScreenBlend, ColorDodgeBlend, OverlayBlend,
  SoftLightBlend, HardLightBlend, DifferenceBlend, ExclusionBlend, HueBlend,
  SaturationBlend, ColorBlend, LuminosityBlend, MaskBlend, OverwriteBlend,
  SubtractMaskBlend, ExcludeMaskBlend`.
- Image operations (`draw`, `drawTiled`, `blur`, `shadow`, `resize`, rotations,
  `flipHorizontal`/`flipVertical`, `invert`, `ceil`, `applyOpacity`,
  `subImage`, `superImage`, `opaqueBounds`, `spread`, `diff`) keep upstream
  names; `Paint` sampling mirrors `paints.nim`/`images.nim`.

## Text and formats (T008, T009)

- Fonts: `Font`/`Typeface`, `readFont(path|bytes)`, `measureText`,
  `layoutBounds`, `defaultLineHeight`, `fillText`/`strokeText` and the `Context`
  text state above; Flutter `TextStyle`/`Paragraph` concepts are deferred until
  wrapping/alignment needs them (T009 decides).
- Formats: codec policy is D008. Public read/write functions keep upstream
  names (`readImage`, `writeImage`, PNG/PPM/QOI/… per task); SVG via
  `parseSvg`; unsupported formats are absent from the API, not stubbed.

## Backend seam (D007)

`Context` writes into a contiguous premultiplied `UInt8` RGBA `Image`. A GPU or
display-list backend implements the same pixel operations behind the same
public calls; `Picture`/`PictureRecorder` are the reserved recording seam and
will be added only when a task needs them.
