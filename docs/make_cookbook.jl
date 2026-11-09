# Build the executed cookbook (Markdown + notebook) and the gallery page.
#
#   julia --startup-file=no --project=docs docs/make_cookbook.jl
#
# Prerequisites (once): `Pkg.develop(path=".")` + `Pkg.instantiate()` in
# docs/, and `scripts/fetch_upstream.jl` for the pinned fonts. Outputs:
#   docs/build/cookbook/COOKBOOK.md      executed recipe Markdown
#   docs/build/cookbook/COOKBOOK.ipynb   executed recipe notebook
#   docs/build/cookbook/<name>.png       named recipe images
#   docs/build/gallery.html              browsable gallery entry point

using Literate

source = joinpath(@__DIR__, "cookbook.jl")
output = joinpath(@__DIR__, "build", "cookbook")

Literate.markdown(source, output;
    name = "COOKBOOK", flavor = Literate.CommonMarkFlavor(), execute = true)
Literate.notebook(source, output; name = "COOKBOOK", execute = true)

# (file, name, description) for docs/build/gallery.html. The descriptions
# double as alt text, so they say what the image shows.
const ITEMS = [
    ("sparkline.png", "Sparkline",
        "24-sample line with a soft area fill and a marker on the latest value."),
    ("gauge.png", "Radial gauge",
        "Semicircular track with a green value arc at 50%, needle, hub, and label."),
    ("kpi.png", "KPI card",
        "White card with shadow, label, large value, and a green delta pill."),
    ("candles.png", "Candlesticks",
        "Twelve deterministic OHLC bars, green up, red down, with wicks."),
    ("annotation.png", "Image annotation",
        "Synthesized landscape with two red callouts: boxes, chips, leader lines."),
    ("diagram.png", "Scientific diagram",
        "Damped sine with dashed grid, axes, tick labels, and the first maximum marked."),
    ("dashboard.png", "Dashboard thumbnail",
        "Header, sparkline, KPI card, and gauge composed into one 480x320 view."),
    ("social-card.png", "Social card",
        "1200x630 Open Graph card: brand pill, title, subtitle, sparkline panel."),
    ("record-replay-480.png", "Recorded replay (480x300)",
        "Scene recorded once as a display list and replayed at its native size."),
    ("record-replay-960.png", "Recorded replay (960x600)",
        "The same picture replayed at 2x: re-rasterized in vector space, not enlarged."),
    ("record-10-replay.png", "Replayed raster (480x300)",
        "A recorded badge scene replayed to pixels: gradient panel, clipped badge, dashed divider."),
    ("record.svg", "SVG export (vector)",
        "The same recorded picture exported with writeSvg: paths, linearGradient, clipPath, and dasharray stay editable vectors."),
    ("record-11-replay.png", "Report graphic (replayed raster)",
        "A gradient report scene exported as scale-independent vector PDFs at 96 and 288 dpi (writePdf); this is its replayed raster."),
    ("paragraph-card.png", "Paragraph card (T028)",
        "A text-heavy card: wrapped body with mixed styled runs at an absolute line height, a clipped box, and a footnote paragraph (Paragraph/layoutParagraph/fillParagraph)."),
    ("annotation-jpeg.jpg", "JPEG thumbnail (T031)",
        "The pinned mandrill photo resized to 256x256 and exported with encodeJPEG (premultiplied composited over white, JFIF 72 dpi, default quality 92): on photographic content JPEG is ~14% of the PNG size; on flat graphics it is not."),
    ("mandrill-webp.webp", "WebP export (T032)",
        "The pinned mandrill thumbnail exported with encodeWebP (lossy quality 75, default; real alpha preserved, no background compositing) — with a lossless mode for flat/transparent content."),
]

function gallery_html()
    cards = join(map(ITEMS) do (file, name, desc)
        """
        <figure>
          <img src="cookbook/$file" alt="$name: $desc">
          <figcaption><strong>$name</strong> — $desc</figcaption>
        </figure>
        """
    end, "\n")
    return """
<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Vetra.jl recipe gallery</title>
<style>
 body { font-family: system-ui, sans-serif; margin: 2rem auto; max-width: 960px;
        color: #111827; }
 .nav { font-size: 0.9rem; margin-bottom: 1rem; }
 .grid { display: flex; flex-wrap: wrap; gap: 1.25rem; }
 figure { margin: 0; max-width: 480px; flex: 1 1 400px;
          border: 1px solid #e5e7eb; border-radius: 12px; overflow: hidden; }
 figcaption { padding: 0.75rem 1rem; font-size: 0.9rem; background: #fff; }
 img { display: block; width: 100%; height: auto; background: #fff; }
</style>
</head>
<body>
<h1>Vetra.jl recipe gallery</h1>
<p class="nav">Built from a clean checkout by
 <code>julia --startup-file=no --project=docs docs/make_cookbook.jl</code>.
 <a href="cookbook/COOKBOOK.md">Executed recipes (Markdown)</a> ·
 <a href="cookbook/COOKBOOK.ipynb">Executed recipes (notebook)</a> ·
 <a href="../INDEX.md">Documentation index</a> ·
 <a href="../TUTORIAL.md">Full OHLC candlestick tutorial</a></p>
<div class="grid">
$(cards)
</div>
</body>
</html>
"""
end

gallery = joinpath(@__DIR__, "build", "gallery.html")
open(gallery, "w") do io
    write(io, gallery_html())
end

println("Executed cookbook written to ", output)
println("Gallery written to ", gallery)
