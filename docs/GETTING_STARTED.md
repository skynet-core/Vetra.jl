# Vetra.jl tutorial: from your first image to layered graphics

Learn Vetra by drawing a small activity card: a gradient background, a line
chart, labels, and a clipped decoration. Then save it, read it back, and
make a thumbnail and a blurred copy. Continue with curves, shapes with holes,
layers, blend modes, SVG import, and reusable drawing functions.

**Prerequisites:** basic Julia, Julia 1.10+, Git, and about 45 minutes
(plus package downloads). No graphics programming experience is needed.
Run the Julia blocks below **in order in the same session**, or concatenate
them into one script. They share variables. Shell blocks are setup commands,
not Julia code.

## Learning path

| Stage | Sections | What you will learn |
| --- | --- | --- |
| First steps | [1–2](#1-set-up) | Install, create a canvas, draw and save your first rectangle |
| Build a useful image | [3–5](#3-paint-a-gradient) | Gradients, paths, data-to-pixel mapping, and text |
| Control the drawing | [6–8](#6-use-transforms-and-clipping) | Transforms, clipping, export, images, and effects |
| Advanced composition | [9–11](#9-curves-and-shapes-with-holes) | Bézier curves, fill rules, layers, blend modes, SVG import |
| Make it reusable | [12–13](#12-write-reusable-drawing-functions) | Functions, simple checks, performance habits, troubleshooting |

You can stop after section 7 with a complete activity card. The later examples
create separate images, so you can experiment without changing that card.

**The mental model:** an `Image` is a sheet of pixels, a `Context` holds your
drawing settings, a `Path` describes a shape, and a `Paint` supplies its color
or gradient. Drawing changes pixels immediately; editing a path later does
not update a shape you already drew.

## 1. Set up

If you do not have the repository yet:

```sh
git clone https://github.com/skynet-core/Vetra.jl.git
cd Vetra.jl
```

From the repository root, prepare the existing documentation environment
and fetch the reference assets (including the tutorial's Roboto font):

```sh
julia --startup-file=no --project=docs -e 'using Pkg; Pkg.develop(path="."); Pkg.instantiate()'
julia --startup-file=no --project=. scripts/fetch_upstream.jl
julia --startup-file=no --project=docs
```

The last command opens a Julia REPL. Paste the following Julia blocks there.
Alternatively, save them in `getting_started.jl` in the repository root and
run `julia --startup-file=no --project=docs getting_started.jl`.

The docs environment includes `PNGFiles`, which supplies PNG read/write.
For your own application, add Vetra from its checkout with
`Pkg.develop(path="/absolute/path/to/Vetra.jl")` and add `PNGFiles` to that
application's environment before loading Vetra. Literate and Jupyter are
not required by the renderer.

## 2. Create an image and a drawing context

```julia
using Vetra

root = dirname(dirname(pathof(Vetra)))
outdir = joinpath(root, "artifacts", "getting-started")
mkpath(outdir)

img = newImage(640, 400)
fill(img, rgb(242, 245, 250))
ctx = Context(img)

ctx.fillStyle = "#FFFFFF"
fillRect(ctx, 24f0, 24f0, 592f0, 352f0)

writeFile(img, joinpath(outdir, "first-image.png"))
println("Tutorial images are saved in: ", outdir)
```

- `Image` owns the pixels. A new image starts transparent.
- `Context(img)` holds drawing settings and draws into that same image.
- `fill(img, color)` replaces the whole background.
- `fillRect(ctx, x, y, width, height)` draws with `ctx.fillStyle`.
- Drawing coordinates start at the **top-left**: x grows right, y grows down.
- Plain Julia numbers work for drawing calls (`12`, `0.5`); they are converted
  to the library's internal `Float32` once at the boundary. `12f0` is the
  explicit `Float32` literal — use it when you need exact float32 control.
  Image dimensions are integers.

**Check your result now:** open `first-image.png` in the printed directory.
You should see a white rectangle with a pale border. The rectangle starts
24 pixels from the left and top; its last two arguments are width and height,
not the bottom-right corner. `writeFile` saves a snapshot: call it again after
more drawing to save the updated image. Rerunning examples overwrites their
named output files.

Colors can be `rgb(r, g, b)`, `rgba(r, g, b, alpha)` with channels from
0 to 255, or hex strings such as `"#FFFFFF"`. Named CSS colors and numeric
`"rgb(...)"`/`"rgba(...)"` strings are also supported. Be careful with alpha:
the Julia function `rgba(255, 0, 0, 128)` uses byte alpha, while the string
`"rgba(255, 0, 0, 0.5)"` uses alpha from 0 to 1.
Alpha means opacity: 0 is transparent, 255 is opaque, and 128 is roughly
half-transparent. Later drawing normally appears over earlier drawing.

**Try it:** change the white rectangle to `"#FDE68A"`, save it again, then
rerun this section with white before continuing.

## 3. Paint a gradient

A `Paint` describes how to fill a shape. Here the two handles define the
start and end of a horizontal gradient; stops run from 0 to 1.
`Vec2(x, y)` represents a point. The array in `gradientStops` lists the color
at the start (0) and at the end (1); intermediate colors are interpolated.

```julia
gradient = Paint(LinearGradientPaint)
gradient.gradientHandlePositions = [Vec2(48f0, 0f0), Vec2(592f0, 0f0)]
gradient.gradientStops = [
    colorStop(rgb(225, 239, 255), 0f0),
    colorStop(rgb(233, 249, 240), 1f0),
]
ctx.fillStyle = gradient
fillRect(ctx, 48f0, 128f0, 544f0, 192f0)
```

Solid colors, image paints, and radial/angular gradients use the same
painting model. Start with solid and linear-gradient paints before adding
more elaborate effects.

## 4. Draw a chart with paths and strokes

A `Path` stores geometry. `fill(ctx, path)` paints its interior;
`stroke(ctx, path)` paints its outline. An open path is useful for a line chart.

First draw dashed guide lines. `save` and `restore` isolate temporary
settings so the chart itself will have a solid stroke.

```julia
save(ctx)
ctx.strokeStyle = rgba(90, 110, 140, 80)
ctx.lineWidth = 1f0
setLineDash(ctx, Float32[4, 6])
for y in Float32[176, 224, 272]
    strokeSegment(ctx, 48f0, y, 592f0, y)
end
restore(ctx)

values = Float32[20, 45, 35, 70, 55, 85, 75]
points = [Vec2(64f0 + Float32(i - 1) * 84f0, 304f0 - 1.6f0 * value)
          for (i, value) in enumerate(values)]

trend = newPath()
moveTo(trend, points[1])
for point in points[2:end]
    lineTo(trend, point)
end

ctx.strokeStyle = "#2563EB"
ctx.lineWidth = 4f0
ctx.lineCap = RoundCap
ctx.lineJoin = RoundJoin
stroke(ctx, trend)
```

The formula maps larger values to smaller y coordinates, so higher values
appear higher on screen. Vetra draws the chart; your code chooses data
scales, tick marks, and layout.

In the Julia code, `Float32[...]` creates a list of numbers. `enumerate`
provides both a sample's index `i` and its value; the comprehension builds one
point per sample. The first point starts the path with `moveTo`; the loop
connects the remaining points using `lineTo`. Creating a path alone does not
draw anything: `stroke` does the drawing.

For closed shapes, finish the path with `closePath`. Curves use
`quadraticCurveTo` or `bezierCurveTo`; circles, ellipses, and rectangles have
their own path builders.

## 5. Add text

Vetra takes a **font file path**, not a system font family name. This example
uses the font fetched in step 1; you can substitute your own TTF/glyf font.

```julia
fontpath = joinpath(root, ".reference", "upstream", "tests", "fonts",
    "Roboto-Regular_1.ttf")
@assert isfile(fontpath) "Run scripts/fetch_upstream.jl from the repository root"

ctx.font = fontpath
ctx.fontSize = 28f0
ctx.fillStyle = "#172033"
fillText(ctx, "Weekly activity", 48f0, 76f0)

ctx.fontSize = 16f0
ctx.fillStyle = "#526078"
fillText(ctx, "Seven samples, drawn entirely in Julia", 48f0, 104f0)
fillText(ctx, "Mon", 48f0, 352f0)

label = "Sun"
labelwidth = measureText(ctx, label).width
fillText(ctx, label, 592f0 - labelwidth, 352f0)
```

With the default alphabetic baseline, the y coordinate locates the text's
baseline, not its top edge. `measureText` helps position labels without
guessing their width. Fonts support metrics and kerning, but general Unicode
shaping and complex document layout are outside the supported subset.

## 6. Use transforms and clipping

Transforms let you draw local geometry at a different location, rotation,
or scale. Angles are in radians. This draws a small rotated blue square.

```julia
save(ctx)
translate(ctx, 570f0, 67f0)
rotate(ctx, Float32(pi / 4))
ctx.fillStyle = "#2563EB"
fillRect(ctx, -10f0, -10f0, 20f0, 20f0)
restore(ctx)
```

Clipping restricts subsequent drawing to a shape. Draw a small circular
accent beside the title, with its lower half overlaid in blue:

```julia
save(ctx)
window = newPath()
circle(window, 528f0, 67f0, 14f0)
clip(ctx, window)
ctx.fillStyle = "#DBEAFE"
fillRect(ctx, 514f0, 53f0, 28f0, 28f0)
ctx.fillStyle = rgba(37, 99, 235, 180)
fillRect(ctx, 514f0, 67f0, 28f0, 14f0)
restore(ctx)
```

`restore` removes the temporary clip and restores the previous styles and
transform. It does **not** undo pixels already drawn. Always balance it
with `save` (or `saveLayer`); an unmatched `restore` raises an error.

The transform order matters: translating then rotating here rotates the
square around its local origin and places that origin at `(570, 67)`.
Reversing these calls changes where the square lands.

**Clip coordinates:** this port builds clipping masks in image coordinates;
the context transform is not applied to the clip path. The example clips
after restoring the identity transform. Define clip paths in image coordinates
even when later drawing uses a transform.

## 7. Export and read the result

```julia
cardpath = joinpath(outdir, "activity-card.png")
writeFile(img, cardpath)
loaded = readImage(cardpath)

@assert (width(loaded), height(loaded)) == (640, 400)
@assert loaded.data == img.data
println("Open this image: ", cardpath)
```

Open the printed file in your image viewer. You should see a white card,
blue trend line over a pale gradient, dashed guides, and text labels.

`writeFile` selects the encoder from the extension: PNG, BMP, QOI, or PPM.
`readImage` detects the input format from its contents. JPEG and GIF are
read-only, WebP is unsupported, and SVG support is a parsing/rasterization
subset rather than a general SVG exporter.

The pixel equality assertion here works because our card has an opaque
background. Arbitrary translucent images can lose precision when converting
between 8-bit premultiplied storage and straight-alpha PNG pixels.

## 8. Resize, composite, and apply effects

Use `drawImage` to place an existing image in another canvas. Its destination
rectangle can also resize it. Here a 640×400 card becomes a 320×200 thumbnail.

```julia
preview = newImage(360, 240)
fill(preview, rgb(226, 232, 240))
previewctx = Context(preview)
drawImage(previewctx, loaded, 20f0, 20f0, 320f0, 200f0)
writeFile(preview, joinpath(outdir, "thumbnail.png"))

small = resize(loaded, 320, 200)
soft = copy(small)
blur(soft, 3f0)
writeFile(soft, joinpath(outdir, "blurred.png"))

@assert (width(small), height(small)) == (320, 200)
@assert soft.data != small.data
@assert loaded.data == img.data
```

`resize` returns a new image. `blur`, `flipHorizontal`, `invert`, and
`applyOpacity` modify an image in place, despite having no `!` suffix.
Use `copy` first when you need the original. `save(ctx)` saves drawing
settings, not an image backup.

## 9. Curves and shapes with holes

Now move beyond straight line segments. A cubic Bézier curve has a starting
point, two control points that pull its shape, and an ending point. The
curve starts at the path's current position; `bezierCurveTo` takes the two
control points and the endpoint, in that order.

```julia
shapes = newImage(360, 200)
fill(shapes, rgb(255, 255, 255))
shapectx = Context(shapes)

wave = newPath()
moveTo(wave, 20f0, 110f0)
bezierCurveTo(wave, 60f0, 20f0, 140f0, 180f0, 180f0, 90f0)
shapectx.strokeStyle = "#2563EB"
shapectx.lineWidth = 5f0
stroke(shapectx, wave)

ring = newPath()
circle(ring, 270f0, 100f0, 65f0)
circle(ring, 270f0, 100f0, 32f0)
fillPath(shapes, ring, Paint(rgb(124, 58, 237)); windingRule = EvenOdd)

@assert getColor(shapes, 271, 101) == rgbx(rgba(255, 255, 255, 255))
writeFile(shapes, joinpath(outdir, "curves-and-holes.png"))
```

You should see a blue curve and a purple ring with a white center. `EvenOdd`
fills alternating regions as you cross shape boundaries, so nested circles
make a hole regardless of their direction. The default `NonZero` rule takes
contour direction into account; the same-direction circles would fill the
center too.

This also introduces the lower-level `fillPath(image, path, paint; ...)`
API. It draws directly into the image with explicit settings, rather than
using the context's styles or transform. The `@assert` line checks that the
center is still white; it stops execution if the condition is false.

**Try it:** change `EvenOdd` to `NonZero` and remove the white-center
assertion for that experiment. Or move either curve control point and see
how the curve bends.

## 10. Layers, transparency, and blend modes

**Compositing** means combining images or shapes. Normally, the new shape
covers the existing pixels according to its opacity. A blend mode changes
how the new color combines with the existing color.

`saveLayer` creates a transparent offscreen image. Draw into it, then call
`restore` to composite it onto the parent image. Unlike `save`, this isolates
the group's pixels as well as saving drawing state.

```julia
layers = newImage(320, 200)
fill(layers, rgb(255, 255, 255))
layerctx = Context(layers)

saveLayer(layerctx)
leftdisk = newPath()
circle(leftdisk, 120f0, 100f0, 65f0)
layerctx.fillStyle = rgb(0, 255, 255)
fill(layerctx, leftdisk)

rightdisk = newPath()
circle(rightdisk, 200f0, 100f0, 65f0)
layerctx.fillStyle = Paint(rgba(255, 255, 0, 255); blendMode = MultiplyBlend)
fill(layerctx, rightdisk)

# The parent image is still white until the layer is restored.
@assert getColor(layers, 161, 101) == rgbx(rgba(255, 255, 255, 255))
restore(layerctx)
@assert getColor(layers, 161, 101) == rgbx(rgba(0, 255, 0, 255))
writeFile(layers, joinpath(outdir, "layers-and-blending.png"))
```

The cyan and yellow disks overlap in green. Multiply combines normalized
color channels by multiplication: cyan `(0, 1, 1)` times yellow `(1, 1, 0)`
gives green `(0, 1, 0)`. Within this layer, the second disk blends with the
first disk; the group's transparent background is not the parent's white
background. This distinction matters with other backgrounds and blend modes.

Three opacity controls serve different needs:

- `rgba(..., alpha)` sets one color's opacity, using 0–255.
- `ctx.globalAlpha = 0.5f0` scales subsequent drawing opacity, using 0–1.
  Use `save`/`restore` around a temporary change.
- To fade a whole group **after** composing its overlapping shapes, draw it
  into a separate transparent `Image`, call `applyOpacity(group, 0.5f0)`,
  then `drawImage` that image onto the destination.

Fading each shape separately can give different overlaps from fading the
finished group. Each full-size layer also needs another pixel buffer, so
use layers for actual grouping or compositing needs.

## 11. Rasterize a simple SVG

SVG describes shapes as text. Vetra can parse a supported SVG subset and
turn it into pixels; this requires the optional `XML` package, already in
the docs environment.

```julia
svgtext = """
<svg xmlns="http://www.w3.org/2000/svg" width="120" height="80" viewBox="0 0 120 80">
  <rect x="0" y="0" width="120" height="80" fill="#DBEAFE"/>
  <path d="M 20 55 L 60 15 L 100 55 Z" fill="#2563EB"/>
</svg>
"""
svgimage = newImage(parseSvg(svgtext))
@assert (width(svgimage), height(svgimage)) == (120, 80)
@assert getColor(svgimage, 61, 31) == rgbx(rgba(37, 99, 235, 255))
writeFile(svgimage, joinpath(outdir, "svg-import.png"))
```

Expect a blue triangle on a pale blue background. In the path's `d` string,
`M` moves to a point, `L` draws a line, and `Z` closes the triangle. For just
an SVG path string, use `parsePath` to obtain a `Path` for your own drawing.

Do not assume arbitrary browser SVGs will look identical: filters, various
gradient features, and other elements are outside this port's subset.
See [SVG compatibility](COMPATIBILITY.md#images-formats-text-t006-t008-t009).
`writeFile` does not export SVG or PDF; the next project in
[TUTORIAL.md](TUTORIAL.md) builds a small application-specific SVG writer.

## 12. Write reusable drawing functions

Once a drawing works, put it in a function. Pass its inputs as arguments,
create a fresh image inside, and return the image. Keep file writing outside
so callers can save, composite, or further edit the result.

This small function makes progress-bar images. The keyword argument after
`;` lets callers choose a color, with a default when omitted.

```julia
function progress_image(fraction::Real; color = rgb(37, 99, 235))
    isfinite(fraction) && 0 <= fraction <= 1 ||
        throw(ArgumentError("fraction must be finite and between 0 and 1"))
    image = newImage(240, 48)
    context = Context(image)
    context.fillStyle = rgb(226, 232, 240)
    fillRect(context, 0f0, 0f0, 240f0, 48f0)
    if fraction > 0
        context.fillStyle = color
        fillRect(context, 0f0, 0f0, 240f0 * Float32(fraction), 48f0)
    end
    return image
end

progress = progress_image(0.75)
@assert getColor(progress, 10, 24) == rgbx(rgba(37, 99, 235, 255))
@assert getColor(progress, 220, 24) == rgbx(rgba(226, 232, 240, 255))
emptybar = progress_image(0)
@assert getColor(emptybar, 10, 24) == rgbx(rgba(226, 232, 240, 255))
fullbar = progress_image(1)
@assert getColor(fullbar, 240, 24) == rgbx(rgba(37, 99, 235, 255))
writeFile(progress, joinpath(outdir, "progress.png"))
```

The output should be three-quarters blue and one-quarter gray. Input
validation gives the caller a useful error instead of drawing an invalid
bar. The assertions check ordinary input and the empty/full boundaries.

### Performance habits

- Put repeated rendering in functions, with data passed as arguments rather
  than read from changing global variables.
- Warm up a function before timing: the first call may include compilation.
- Measure drawing and PNG encoding separately to locate the expensive stage.
- Reuse fonts and geometry when they stay the same. Avoid extra full-canvas
  copies and layers unless you need them.
- Measure your actual image dimensions and scene complexity before choosing
  optimizations. Small-image benchmark results do not predict large scenes.

For example, this measures the **in-memory drawing**, not PNG writing:

```julia
function time_progress(n::Int)
    n > 0 || throw(ArgumentError("n must be positive"))
    progress_image(0.75)  # Compile and warm up before measuring.
    elapsed = @elapsed for _ in 1:n
        progress_image(0.75)
    end
    bytes = @allocated progress_image(0.75)
    println("Average seconds per image: ", elapsed / n)
    println("Allocated bytes per image: ", bytes)
    return nothing
end
time_progress(1000)
```

This is a quick diagnostic, not a rigorous comparison: garbage collection
and system load affect timings. Use the repository's
[benchmark harness](../benchmark/README.md) for its standardized workloads.

## 13. Quick reference and troubleshooting

| Goal | API or convention |
| --- | --- |
| Create a drawing target | `newImage(width, height)`, then `Context(image)` |
| Choose colors | `rgb`, `rgba`, or `"#RRGGBB"` |
| Draw shapes | Build a `Path`, then `fill` or `stroke` |
| Temporarily change settings | `save(ctx)` … `restore(ctx)` |
| Group drawing on an offscreen layer | `saveLayer(ctx)` … `restore(ctx)` |
| Place an image | `drawImage(ctx, image, x, y, width, height)` |
| Preserve an image before an effect | `copy(image)` |
| Read an individual pixel | `getColor(image, 1, 1)` is the top-left pixel |
| Crop an image | `subImage(image, 0, 0, w, h)` crops from the top-left |
| Save output | `writeFile(image, "output.png")` |

Pixel access is **1-based**, while drawing and crop coordinates start at 0.
`Image.data` is a row-major byte buffer of **premultiplied RGBA**, not a Julia
matrix of straight colors. Prefer drawing APIs and color constructors until
you need direct buffer access.

### Common problems

| Symptom | What to check |
| --- | --- |
| `Package Vetra not found` | Start Julia from the repository root with `--project=docs` after completing setup. |
| PNG support install hint | Add `PNGFiles` to the active environment, then restart Julia. |
| Font file assertion fails | Run `scripts/fetch_upstream.jl`, or provide a supported TTF font path. |
| `MethodError` for coordinates | Use `10f0` or `Float32(x)` rather than default `Float64` values for context coordinate arguments. |
| Drawing seems missing | Check draw order, opacity, coordinates, the active clip, and whether you saved the image after drawing. |
| Later shapes unexpectedly move or disappear | Check that temporary transforms and clips have matching `save`/`restore` calls. |
| A filled shape has no hole | Use `EvenOdd`, or check contour direction with `NonZero`. |
| Your original image changed after an effect | Use `copy(image)` before an in-place effect. |
| `restore() with no saved state` | Match each `restore` to one `save` or `saveLayer`. |

### Try it yourself

1. Change `values` and the two gradient colors, then rerun the drawing blocks
   starting at step 2 to create a fresh image.
2. Add a second trend line with a different `strokeStyle`.
3. Replace the circular decoration with a triangular clip path.
4. Add a third nested circle to the `EvenOdd` example and predict which
   regions will be filled before rendering.
5. Change `MultiplyBlend` to `NormalBlend` and compare the overlap.
6. Call `progress_image(0.25; color = rgb(22, 163, 74))`, then place the
   result on a larger image using `drawImage`.

Next, follow the [OHLC chart tutorial](TUTORIAL.md) for a larger project,
or copy a finished pattern from the [cookbook](cookbook.jl)
(sparkline, gauge, KPI card, candlesticks, annotation, diagram, dashboard,
social card). The full documentation map is in [INDEX.md](INDEX.md).
See the [compatibility inventory](COMPATIBILITY.md) for supported features
and edge cases, and the [API guide](API.md) for the drawing model.
