# From pixels to a dashboard with Vetra.jl

Vetra turns Julia code into raster images. You describe paths, paints, text,
and transforms; it writes pixels into an `Image`. There is no window to open
or event loop to manage, which makes it useful for generated reports, asset
pipelines, thumbnails, and server-side graphics.

In this tutorial you will build a **640 × 400 activity card**: a rounded
panel, a gradient-filled chart, a dashed guide, a transformed marker, and
measured text. Then you will reuse the result as an image, try compositing
and SVG, and learn how to test and benchmark your own rendering code.

You need basic Julia, Julia **1.10 or newer**, and Git for the sample font.
Allow about 45 minutes, plus the initial package download.

## Contents

1. [Set up a reproducible workspace](#1-set-up-a-reproducible-workspace)
2. [Make the first image](#2-make-the-first-image)
3. [Understand coordinates, colors, and mutation](#3-understand-coordinates-colors-and-mutation)
4. [Build the chart with paths](#4-build-the-chart-with-paths)
5. [Add gradients, strokes, and dashes](#5-add-gradients-strokes-and-dashes)
6. [Use transforms without losing your place](#6-use-transforms-without-losing-your-place)
7. [Clip a highlight to the panel](#7-clip-a-highlight-to-the-panel)
8. [Add text and finish the card](#8-add-text-and-finish-the-card)
9. [Crop, resize, and add a shadow](#9-crop-resize-and-add-a-shadow)
10. [Experiment with compositing and layers](#10-experiment-with-compositing-and-layers)
11. [Load images, SVG, and data URLs](#11-load-images-svg-and-data-urls)
12. [Lay out a paragraph](#12-lay-out-a-paragraph)
13. [Test pixels and measure performance](#13-test-pixels-and-measure-performance)
14. [Troubleshooting and next experiments](#14-troubleshooting-and-next-experiments)

## 1. Set up a reproducible workspace

Vetra is currently installed from its repository rather than the General
registry. Start with a checkout:

```sh
git clone https://github.com/skynet-core/Vetra.jl.git
cd Vetra.jl
julia --startup-file=no
```

In that Julia REPL, create a separate environment inside the checkout:

```julia
using Pkg
Pkg.activate("artifacts/tutorial-env")
Pkg.develop(path = pwd())
Pkg.add(["PNGFiles", "JpegTurbo", "XML"])
```

`Pkg.develop` points the environment at your local source. The optional
packages enable PNG, JPEG decoding, and SVG parsing respectively; the
renderer itself does not need them. Install these **before loading Vetra**,
then exit Julia. This avoids adding packages halfway through a rendering
session.

Back in the terminal, fetch the pinned reference assets:

```sh
julia --startup-file=no --project=. scripts/fetch_upstream.jl
```

We use its Roboto font so everyone can follow the same example. The fetch
downloads source/assets into `.reference/upstream`; it does not install or
run Nim. The font's license and provenance are documented in [NOTICE](../NOTICE).
For your own application, use a compatible font file you are allowed to
distribute; a reference checkout is not a runtime requirement.

Create `artifacts/tutorial.jl`. **Append the Julia blocks in sections 2–12
in order** to that file; they share variables. Run the growing script from
the repository root:

```sh
julia --startup-file=no --project=artifacts/tutorial-env artifacts/tutorial.jl
```

Section 2 already writes a viewable BMP. Section 8 writes the finished PNG;
the later sections create separate experiments. Outputs go into
`artifacts/tutorial/`, so rerunning only replaces those tutorial outputs.

## 2. Make the first image

Think in four objects:

| Object | Responsibility |
| --- | --- |
| `Image` | Owns the pixel buffer. |
| `Context` | Remembers drawing state: transform, colors, strokes, font, clip. |
| `Path` | Describes geometry, independently of how it is painted. |
| `Paint` | Supplies a solid color, gradient, or image and its blend mode. |

Start with an opaque background and a rounded panel:

```julia
using Vetra

outdir = joinpath("artifacts", "tutorial")
mkpath(outdir)

img = newImage(640, 400)
fill(img, rgb(15, 23, 42))
ctx = Context(img)

panel = newPath()
roundedRect(panel, 24f0, 24f0, 592f0, 352f0,
    20f0, 20f0, 20f0, 20f0)
ctx.fillStyle = "#1E293B"
fill(ctx, panel)

@assert width(img) == 640 && height(img) == 400
@assert getColor(img, 1, 1) == rgbx(rgb(15, 23, 42))
writeFile(img, joinpath(outdir, "01-panel.bmp"))
```

Open `artifacts/tutorial/01-panel.bmp`. You should see a slate panel on a
dark background. BMP output uses a built-in codec, so this first milestone
works without optional packages. Vetra loads available optional codecs when
the module is initialized; no separate codec imports or cache deletion are
needed for the later sections.

`fill(img, color)` replaces the entire buffer. `fill(ctx, path)` paints a
shape using context state and compositing. Same verb, different level of
control. A new image starts transparent; here we deliberately fill it first.

The four corner radii of `roundedRect` are **top-left, top-right,
bottom-right, bottom-left**. Equal radii make a uniform rounded rectangle.

## 3. Understand coordinates, colors, and mutation

### Two coordinate systems, one image

Drawing starts at `(0, 0)` in the top-left, with x increasing rightward and
y downward. Coordinates are continuous; the first pixel's center is
`(0.5, 0.5)`. Width and height describe extents, not the coordinates of a
last pixel.

Direct pixel access uses **1-based Julia indexing**: `getColor(img, 1, 1)`
reads that first pixel. Cropping with `subImage`, however, uses **zero-based
drawing offsets**. Keep storage inspection and drawing coordinates separate.

Geometry and many drawing arguments use `Float32`. Julia's `24f0` is
`Float32(24)`, while `24.0` is `Float64`. Use `Float32(value)` at the boundary
when your data comes from a table or computation.

### Straight color in, premultiplied pixels out

`rgb(r, g, b)` and `rgba(r, g, b, a)` take integer channels from 0 to 255.
The alpha in `rgba` is also a byte: 128 means roughly half opaque, not 0.5.
Paint opacity and `ctx.globalAlpha`, on the other hand, use floats from 0 to 1.

Internally, RGB channels are multiplied by alpha. Half-opaque red is stored
as roughly `(128, 0, 0, 128)`, rather than `(255, 0, 0, 128)`:

```julia
probe = newImage(1, 1)
setColor(probe, 1, 1, rgba(255, 0, 0, 128))
pixel = getColor(probe, 1, 1)
@assert (pixel.r, pixel.g, pixel.b, pixel.a) == (128, 0, 0, 128)
```

`getColor` returns a premultiplied `ColorRGBX`. `rgbx(straight_color)`
converts into that representation; `rgba(premultiplied_color)` converts
back, with integer rounding. Do not expect arbitrary translucent colors
to survive that round trip byte-for-byte.

`img.data` is a flat `Vector{UInt8}`, laid out **RGBA, row-major**, four bytes
per pixel. It is not a Julia column-major color matrix. For 1-based `(x, y)`,
the red-channel index is `4 * ((y - 1) * width(img) + x - 1) + 1`.
Prefer `getColor` and `setColor` until you actually need buffer-level access.

### Mutation is part of the API

The API preserves camelCase names and many mutating functions **do not end
in `!`**. Do not infer ownership from Julia naming conventions alone:

| Changes an existing object | Returns a new image |
| --- | --- |
| `fill`, `fillRect`, `stroke`, `draw` | `copy`, `resize`, `subImage` |
| `transform(path, matrix)` | `rotate90`, `shadow`, `superImage` |
| `blur`, `invert`, `applyOpacity` | `magnifyBy2`, `minifyBy2` |
| `flipHorizontal`, `flipVertical`, `spread` | |

`Path`, `Paint`, `Image`, and `Context` are mutable. Geometry such as `Vec2`
and `Mat3` is immutable. `other = img` aliases the same image; use `copy(img)`
for an independent pixel buffer. `copy(paint)` copies its settings and
gradient arrays, but its source image is still shared.

## 4. Build the chart with paths

The card's chart occupies x = 56…584 and y = 144…312. Map a small data
series into that rectangle. Subtract from the bottom coordinate because
larger values should move **up** the image:

```julia
values = Float32[24, 38, 32, 58, 44, 76, 64, 88]
xs = collect(range(56f0, 584f0; length = length(values)))
ys = 312f0 .- 1.7f0 .* values

trace = newPath()
moveTo(trace, xs[1], ys[1])
for i in 2:length(values)
    lineTo(trace, xs[i], ys[i])
end

area = copy(trace)
lineTo(area, xs[end], 312f0)
lineTo(area, xs[1], 312f0)
closePath(area)
```

The open `trace` will become the chart line. Closing a copy against the
baseline creates the filled region. Keeping them separate avoids stroking
the baseline and the two vertical edges by accident.

Paths also support `quadraticCurveTo`, `bezierCurveTo`, arcs, ellipses,
circles, and SVG path strings through `parsePath`. Geometry is reusable:
you can fill and stroke the same path with different paints.

The alternative is `beginPath(ctx)`, then path commands on `ctx`, followed
by `fill(ctx)` or `stroke(ctx)`. Call `beginPath` when starting a new shape;
drawing the current path does not clear it. Explicit `Path` objects make
the ownership especially clear in a larger renderer.

## 5. Add gradients, strokes, and dashes

A linear gradient needs two handles and color stops. Here the handles run
vertically in image space, from the chart's top to its baseline:

```julia
chartPaint = Paint(LinearGradientPaint)
chartPaint.gradientHandlePositions = [Vec2(56f0, 144f0), Vec2(56f0, 312f0)]
chartPaint.gradientStops = [
    colorStop(rgba(45, 212, 191, 190), 0f0),
    colorStop(rgba(45, 212, 191, 0), 1f0),
]
fillPath(img, area, chartPaint)

save(ctx)
ctx.strokeStyle = rgba(148, 163, 184, 100)
ctx.lineWidth = 1f0
setLineDash(ctx, Float32[6, 6])
strokeSegment(ctx, 56f0, 227f0, 584f0, 227f0)
restore(ctx)

ctx.strokeStyle = "#5EEAD4"
ctx.lineWidth = 3f0
ctx.lineCap = RoundCap
ctx.lineJoin = RoundJoin
stroke(ctx, trace)
```

Notice the two drawing styles: `fillPath(img, area, chartPaint)` explicitly
supplies the paint, while `stroke(ctx, trace)` uses stored context state.
An image-level call does **not** inherit the context's transform or clip,
even if the context wraps that image.

The guide uses alternating 6-pixel dash/gap lengths. `save`/`restore`
confines its stroke settings so the chart line stays solid. Dash lengths
must be positive; an odd-length pattern is repeated to make an even cycle.

`RoundCap` rounds the endpoints; `RoundJoin` rounds corners between
segments. These are independent choices. Use `ButtCap` for flat endpoints,
or `MiterJoin` for sharp corners with a `miterLimit`.

Linear, radial, and angular gradients are available. Radial and angular
paints require three handles; do not just change the kind on this two-handle
example. `Paint(image)` and `TiledImagePaint` provide image-based fills.

## 6. Use transforms without losing your place

Draw a small diamond at the final data point. Its geometry is centered at
the origin, then rotated and translated into place:

```julia
save(ctx)
translate(ctx, xs[end], ys[end])
rotate(ctx, Float32(pi / 4))
ctx.fillStyle = "#FBBF24"
fillRect(ctx, -5f0, -5f0, 10f0, 10f0)
restore(ctx)

matrix = translate(Vec2(100f0, 50f0)) * scale(Vec2(2f0, 2f0))
mapped = matrix * Vec2(10f0, 5f0)
@assert mapped == Vec2(120f0, 60f0)
```

With `A * B`, **B acts first**. That matrix doubles the point and then
moves it. Context transforms post-multiply, so calling `translate` and
then `rotate` rotates local geometry first, then positions it.

For a full matrix, use `setTransform(ctx, matrix)` to replace the current
transform, `transform(ctx, matrix)` to compose, and `resetTransform(ctx)`
to return to identity. Angles are radians. On a y-down canvas, a positive
rotation moves a rightward direction toward the bottom of the image.

`save`/`restore` is not undo: pixels already drawn remain. It restores
drawing settings. Two important exceptions are that the **current path**
and **`textBaseline`** are not saved. Restore those explicitly if your helper
changes them. In a function that may throw, use `try`/`finally` to ensure
every `save` is paired with a `restore`.

## 7. Clip a highlight to the panel

Clipping lets a simple oversized rectangle become a neatly trimmed accent:

```julia
save(ctx)
clip(ctx, panel)
ctx.fillStyle = "#2DD4BF"
fillRect(ctx, 0f0, 24f0, 640f0, 4f0)
restore(ctx)

@assert isPointInPath(ctx, panel, 100f0, 100f0)
@assert !isPointInPath(ctx, panel, 8f0, 8f0)
```

Successive clips intersect. Saving before the clip gives you a convenient
way to return to the previous region.

**Vetra-specific detail:** `clip` treats path coordinates as image-space
coordinates; it does not apply the context transform. If you build a clip
in local coordinates, transform a copy of the path with
`transform(clipCopy, getTransform(ctx))` before clipping. Here `panel`
already uses image coordinates.

Hit testing has different transform behavior: `isPointInPath` transforms
the path with the current context matrix, but takes the queried point in
image space. It tests filled geometry, not strokes. Boundary hits follow
the pinned scanline rules; for an axis-aligned rectangle, the top and left
edges are included and the bottom and right edges are excluded.

## 8. Add text and finish the card

A context takes a **font file path**, not a system family name or CSS font
declaration. Set a font, choose a size, then position text by its baseline:

```julia
fontPath = joinpath(".reference", "upstream", "tests", "fonts",
    "Roboto-Regular_1.ttf")
@assert isfile(fontPath) "Run scripts/fetch_upstream.jl from the repository root"

ctx.font = fontPath
ctx.textBaseline = AlphabeticBaseline
ctx.fontSize = 24f0
ctx.fillStyle = "#F8FAFC"
fillText(ctx, "Activity / last 8 builds", 56f0, 76f0)

ctx.fontSize = 14f0
ctx.fillStyle = "#94A3B8"
fillText(ctx, "A small chart, drawn entirely in Julia", 56f0, 104f0)
fillText(ctx, "BUILD 01", 56f0, 346f0)

label = "BUILD 08"
labelWidth = measureText(ctx, label).width
fillText(ctx, label, 584f0 - labelWidth, 346f0)

writeFile(img, joinpath(outdir, "activity-card.png"))
println("Finished card: ", joinpath(outdir, "activity-card.png"))
```

Open the PNG: the final card has a teal area chart, a dashed horizontal
guide, an amber endpoint, and labels aligned to the chart's edges.
The plotted values are illustrative data, not benchmark measurements.

`measureText` supplies an advance/layout width for positioning; it is not
a full ink-bounding-box API. The example right-aligns the last label by
subtracting its width. Contexts also offer `LeftAlign`, `CenterAlign`, and
`RightAlign` via `textAlign`.

Supported fonts are single-face TrueType/glyf fonts, with kerning support.
The filename extension alone does not establish compatibility: CFF-outline
OpenType fonts, TTC collections, and SVG fonts are unsupported. Text is
not a browser-grade Unicode shaping engine; check the
[font compatibility details](COMPATIBILITY.md#images-formats-text-t006-t008-t009) before
planning complex-script typography.

**Try it:** change the data, then the panel padding, then the palette.
Those are three separate concerns—data mapping, geometry, and paint—and
keeping them separate makes procedural graphics easier to evolve.

## 9. Crop, resize, and add a shadow

Once rendered, the card is just an image. A thumbnail pipeline can reuse
it without replaying any drawing commands:

```julia
card = subImage(img, 24, 24, 592, 352)
thumb = resize(card, 296, 176)
turned = rotate90(thumb)
@assert width(turned) == 176 && height(turned) == 296

stage = newImage(360, 240)
fill(stage, rgb(226, 232, 240))
tile = newImage(360, 240)
draw(tile, thumb, translate(Vec2(32f0, 24f0)))
shade = shadow(tile, Vec2(0f0, 6f0), 0f0, 6f0, rgba(0, 0, 0, 100))
draw(stage, shade)
draw(stage, tile)
writeFile(stage, joinpath(outdir, "thumbnail.png"))
```

`subImage(img, x, y, w, h)` uses zero-based offsets and must stay inside
the image. `superImage` can pad a region extending outside it. `resize`
and `rotate90` return new images; they do not replace their argument.

The shadow arguments after the image are **offset, spread, blur, color**.
A shadow is derived from alpha, so the transparent margin around `tile`
is essential. Blurring a fully opaque image would not reveal the shape of
the panel. Effects stay inside their canvas; leave enough room for a blur
or offset to avoid cropping it.

`draw(dst, src, matrix)` composites onto `dst`. `drawImage(ctx, src, ...)`
is the context-facing variant, with destination-size and source-crop
overloads. `drawTiled` repeats an image; an image paint can restrict a
texture to a path.

## 10. Experiment with compositing and layers

Opacity per draw is different from opacity applied to a whole group.
In the first panel below, the overlap becomes darker because two
half-opacity circles are drawn separately. In the second, the opaque
circles are combined first, then the resulting image is faded once:

```julia
comparison = newImage(400, 160)
fill(comparison, rgb(255, 255, 255))
cc = Context(comparison)
cc.fillStyle = "#2563EB"
cc.globalAlpha = 0.5f0
for x in (65f0, 115f0)
    p = newPath()
    circle(p, x, 80f0, 40f0)
    fill(cc, p)
end

group = newImage(200, 160)
gc = Context(group)
gc.fillStyle = "#2563EB"
for x in (65f0, 115f0)
    p = newPath()
    circle(p, x, 80f0, 40f0)
    fill(gc, p)
end
applyOpacity(group, 0.5f0)
draw(comparison, group, translate(Vec2(200f0, 0f0)))
@assert getColor(comparison, 265, 80) == getColor(comparison, 290, 80)
@assert getColor(comparison, 65, 80) != getColor(comparison, 90, 80)
writeFile(comparison, joinpath(outdir, "opacity.png"))
```

This explicit offscreen image is a useful technique for badges, grouped
icons, and fading a chart as a unit. `saveLayer(ctx)` also starts a temporary
full-size image and `restore(ctx)` composites it back. Unlike a retained
scene-graph group-opacity property, `ctx.globalAlpha` applies to drawing
operations; changing it just before `restore` is not a group fade.

Blend modes answer a different question: how should source and destination
colors interact? Here is a tiny Multiply example, plus a layer-backed accent:

```julia
blendDemo = newImage(200, 120)
fill(blendDemo, rgb(240, 220, 180))
swatch = newPath()
rect(swatch, 20f0, 20f0, 100f0, 80f0)
ink = Paint(rgba(80, 140, 240, 255); blendMode = MultiplyBlend)
fillPath(blendDemo, swatch, ink)

bc = Context(blendDemo)
saveLayer(bc)
bc.fillStyle = rgba(255, 255, 255, 180)
fillRect(bc, 100f0, 40f0, 70f0, 40f0)
restore(bc)
writeFile(blendDemo, joinpath(outdir, "blend.png"))
```

`NormalBlend` is ordinary source-over compositing. Multiply tends to darken;
Screen tends to lighten. `OverwriteBlend` replaces covered destination
pixels, including their alpha. Mask modes use alpha to retain or remove
parts of an image. Start with Normal and pick another mode for a specific
visual effect rather than trying to compensate for an alpha mistake.

Compound paths offer another way to cut holes, without a mask image:

```julia
ring = newPath()
circle(ring, 80f0, 80f0, 60f0)
circle(ring, 80f0, 80f0, 30f0)
ringImage = newImage(160, 160)
fillPath(ringImage, ring, Paint("#2DD4BF"); windingRule = EvenOdd)
@assert getColor(ringImage, 80, 80).a == 0
writeFile(ringImage, joinpath(outdir, "ring.png"))
```

EvenOdd alternates inside/outside as a ray crosses boundaries, making
nested contours a convenient hole-punch. The default NonZero rule instead
counts signed crossings, so contour direction matters.

## 11. Load images, SVG, and data URLs

Use `readImage(path)` to decode an image. Reading detects the format from
its contents; `writeFile(image, path)` selects the encoder by extension.

| Format | Read | Write | Optional package |
| --- | --- | --- | --- |
| PNG | Yes | Yes | `PNGFiles` |
| BMP, QOI, PPM | Yes | Yes | None |
| JPEG | Yes | No | `JpegTurbo` |
| GIF | Yes | No | None |
| SVG | Rasterize supported subset | No SVG export | `XML` |
| WebP | No | No | — |

```julia
loaded = readImage(joinpath(outdir, "activity-card.png"))
@assert width(loaded) == width(img) && height(loaded) == height(img)
@assert loaded.data == img.data  # This particular card is fully opaque.

qoiBytes = Vector{UInt8}(codeunits(encodeImage(img, QoiFormat)))
@assert decodeImage(qoiBytes).data == img.data

payload = encodeBase64(img)
dataUrl = "data:image/png;base64," * payload
@assert decodeBase64(payload).data == img.data
@assert decodeBase64(dataUrl).data == img.data

svgSource = """
<svg xmlns="http://www.w3.org/2000/svg" width="64" height="64"
     viewBox="0 0 64 64">
  <rect x="4" y="4" width="56" height="56" rx="12" fill="#0F766E"/>
  <path d="M 18 32 L 28 42 L 46 22" fill="none"
        stroke="#FFFFFF" stroke-width="5"/>
</svg>
"""
icon = newImage(parseSvg(svgSource))
@assert width(icon) == 64 && height(icon) == 64
writeFile(icon, joinpath(outdir, "svg-icon.png"))
```

The QOI encoder returns a binary `String`; `codeunits` exposes its bytes,
and `decodeImage` takes a `Vector{UInt8}`. Do not treat that encoded string
as Unicode text. `writeFile` handles this boundary for disk output.

`encodeBase64` returns a plain PNG base64 payload, so it also needs
`PNGFiles`. Add the MIME prefix yourself for a data URL; `decodeBase64`
accepts either form. For GIF animation
frames, use `decodeGIF(bytes)` and its `frames` field rather than treating
the file as a single still image.

SVG is a supported **subset**, not a browser renderer. It handles common
shapes, paths, groups, transforms, and linear gradients; filters and several
other elements are skipped. Check [the compatibility matrix](COMPATIBILITY.md)
before importing a complex design tool export. Parsing an SVG path alone
with `parsePath` does not require XML.

PPM has no alpha channel and this implementation writes the stored RGB
channels. Flatten translucent artwork onto an opaque background first,
otherwise it can look dark. PNG handles the straight/premultiplied boundary
for you, though rounding still prevents a universal byte-exact translucent
round trip.

## 12. Lay out a paragraph

For more than a label, separate font loading, layout, and rendering. A
`Typeface` contains the parsed font; a `Font` adds size and paints;
`typeset` produces an `Arrangement` that can be rendered again:

```julia
typeface = readTypeface(fontPath)
bodyFont = newFont(typeface)
bodyFont.size = 18f0
bodyFont.paints = [Paint("#E2E8F0")]

paragraph = typeset(bodyFont,
    "Keep geometry, paint, and data separate. Your renderer becomes easier to test and reuse.";
    bounds = Vec2(272f0, 0f0))
extent = layoutBounds(paragraph)
@assert extent.x > 0f0 && extent.y > 0f0

note = newImage(320, 180)
fill(note, rgb(15, 23, 42))
fillText(note, paragraph; transform = translate(Vec2(24f0, 24f0)))
writeFile(note, joinpath(outdir, "paragraph.png"))
```

Here the width constrains wrapping; zero height leaves vertical layout
unconstrained. Arrangement rendering uses layout coordinates, unlike the
context's default alphabetic-baseline positioning. `layoutBounds` measures
layout extent, not just the visible glyph pixels.

For repeated labels, reuse the parsed typeface. A context caches typefaces
by font path; constructing fresh contexts or rereading fonts in an inner
loop defeats that reuse. Layout is still the supported font engine's
line-breaking model, not a full paragraph/shaping system.

## 13. Test pixels and measure performance

### Choose assertions that explain the intended behavior

The assertions in this tutorial check dimensions, exact opaque colors,
matrix math, and the distinction between per-draw and group opacity.
Those tell a reader *why* the output is correct. For your own renderer:

- Test interior pixels for an exact color; antialiased edges have fractional
  coverage, so “this should be fully opaque” may be the wrong expectation.
- Check geometry and transforms with hand-computable examples.
- Check transparency and dimensions after effects, not just whether a file exists.
- Keep reference pixels independent of the implementation being tested.
  Regenerating expected output from the same code can preserve a bug forever.

The repository's suite combines behavior tests and pinned upstream fixtures.
From the checkout root:

```sh
julia --startup-file=no --project=. scripts/fetch_upstream.jl
julia --startup-file=no --project=. scripts/check.jl
```

The gate runs package tests with bounds checks and requires **greater than
95% source line coverage**. Its test environment installs the codec extras.
Nim is needed to generate new oracle fixtures, not to run these tests.
See [test strategy](../test/README.md) for fixture provenance and tolerances.

### Separate rendering, encoding, and startup

There are at least three different performance questions:

1. How long does the first request take, including loading/compilation?
2. How long does a warmed-up render take?
3. How much time and memory does the encoder add?

Do not combine those into one number. In your own benchmark, put rendering
in a function, warm it up, collect several samples, and time PNG encoding
separately. Use `@allocated` in a separate pass to measure bytes, not in the
timed section. Mutating workloads need a consistent starting state on each
iteration.

Run the existing eight-workload harness using the environment you created:

```sh
julia --startup-file=no --project=artifacts/tutorial-env benchmark/run_benchmarks.jl
```

It reports first-call time, then 3 warm-ups and 21 steady-state samples,
with mean/minimum/median times and a separate allocation pass. The TSV's
`alloc_bytes_total` is the total for **21 allocation-pass calls**, not bytes
per call; divide by 21 for that figure. Same-day runs overwrite the dated
TSV under `benchmark/results/`, so copy it elsewhere when comparing runs.

Use the median as a useful summary, not a promise about another machine.
The existing harness includes work such as font parsing and image creation
in some workloads; inspect it before calling a number “pure drawing time.”
The [benchmark guide](../benchmark/README.md) and
[release measurements](../tasks/T011-release.md) explain the upstream comparison.

On pushes to `main`, GitHub Actions runs the unit-test matrix and the Julia
benchmark job. Download the `benchmark-results` artifact from the workflow
run to inspect its TSV. The benchmark job has no performance threshold;
shared-runner timing is evidence to investigate, not a stable speed guarantee.

## 14. Troubleshooting and next experiments

| Symptom | What to check |
| --- | --- |
| `MethodError` for drawing coordinates | Many methods require `Float32`; use `12f0` or `Float32(x)`. |
| PNG/JPEG/SVG asks for a package | Install the corresponding optional package in the active environment, then restart Julia. |
| Codec still unavailable after changing environments | Confirm `Base.active_project()` points to the tutorial environment and restart Julia after installing the optional package. |
| “No font has been set” or a font path is missing | Assign `ctx.font` to an existing compatible file; run the asset fetch for this tutorial. |
| A drawing unexpectedly moves or stays clipped | Balance state saves/restores; inspect `getTransform(ctx)`. Remember the clip's image-space convention. |
| Restoring state did not restore the path or text baseline | Those two are not in the saved state; manage them explicitly. |
| Transparent pixels look dark after export | Check premultiplied vs straight alpha, and flatten before PPM export. |
| `restore()` reports no saved state | A restore has no matching save; use structured state scopes. |
| SVG or fonts differ from a browser | Consult the supported subset; advanced SVG features and Unicode shaping are not implemented. |

Vetra currently renders on the CPU. GPU backends and display-list recording
are future seams, not APIs you can use today.

Good next experiments, in increasing order of scope:

1. **Turn the card into a function.** Accept values and a title, create all
   drawing state locally, and return the image. Keep file writing at the caller.
2. **Add a threshold band.** Map its values through the same y-coordinate
   formula as the chart, then draw it beneath the trace.
3. **Make a reusable icon.** Build a local-coordinate path once, then place
   copies with matrices; try EvenOdd holes and different stroke joins.
4. **Render a series of frames.** Change the data or transform each frame
   and write PNGs. Use a separate video tool to assemble them; Vetra does
   not provide an animation encoder.
5. **Measure your real workload.** Compare rendering with reused fonts and
   paths against rebuilding everything. Let the measurements choose the
   optimization.

For more recipes, see [the examples](../examples/README.md) and
[`examples/showcase.jl`](../examples/showcase.jl). For exact support and
numerical behavior, use [COMPATIBILITY.md](COMPATIBILITY.md) and
[NUMERICAL_CONTRACT.md](NUMERICAL_CONTRACT.md). The key habit is simple:
**build geometry, choose paint, manage state, then inspect the pixels.**
