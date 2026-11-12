# Feature gallery

Six executable programs that demonstrate the current public Vetra API on
deterministic, offline inputs. Every program self-checks with
hand-derived or pinned-oracle expectations (never pixels captured from
the code under test), is import-safe (including it renders nothing),
and writes only to a caller-selected output directory.

## Running

```
# one program (current environment; optional features activate if present)
julia --project=. examples/gallery/<name>.jl [outdir]

# all six + the coverage summary (current environment)
julia --project=. examples/gallery/run_gallery.jl [outdir]

# all six, plus a core-only subprocess re-run of each (proves the
# optional branches raise their named install hints, nothing is
# silently skipped-as-passed)
julia --project=. examples/gallery/run_gallery.jl [outdir] --core-only
```

`outdir` defaults to `artifacts/gallery/`. Fonts come from the pinned
fixtures; no binary is downloaded by the programs themselves.

## Environments

Core-only runs need nothing: the repository environment resolves Vetra
from its core dependencies. To enable the optional features (PNG, JPEG,
WebP, ColorTypes matrix interop, HarfBuzz shaping, XML) in an isolated
environment that never touches the repository `Project.toml`/`Manifest.toml`:

```
julia --project=examples/gallery/optional_env -e 'using Pkg; \
    p = Base.active_project(); isfile(p) && (p = dirname(p)); \
    Pkg.develop(path=joinpath(dirname(p), "..", "..")); \
    Pkg.instantiate()'
julia --project=examples/gallery/optional_env examples/gallery/run_gallery.jl
```

No program ever calls `Pkg.add` at runtime; when a provider is absent the
affected checks assert the named install-hint error instead of skipping.

## Coverage matrix

Feature → program, renderer, optional dependency, and what is checked.
"Core" means the check runs without any optional provider.

| Feature | Program | Renderer | Optional dep | Checks |
| --- | --- | --- | --- | --- |
| Paths, fill rules (even-odd/non-zero) | drawing_atlas | CPU, SVG, PDF | – | hand-derived interior pixels, byte replay |
| Caps (butt/round/square), joins (miter/round/bevel), dashes | drawing_atlas | CPU, SVG, PDF | – | hand-derived stroke extents |
| Transforms (translate/rotate) | drawing_atlas | CPU, SVG, PDF | – | hand-derived corner pixels |
| Linear + radial gradients | drawing_atlas | CPU, SVG, PDF | – | hand-lerped stops, no exponent numbers |
| Clips, group opacity, isolated layers | drawing_atlas | CPU, SVG, PDF | – | hand-derived composites |
| Recorded replay 1x (byte-exact) / 2x (pinned raster semantics) | drawing_atlas | CPU | – | op count, byte identity, derived samples |
| Plot mapping (large-offset Float64 data, Float32 narrowing) | plot_dashboard | CPU, SVG, PDF | – | forward/inverse mapping, spacing facts |
| Plot-area clip, heatmap, bars, legends, layout | plot_dashboard | CPU, SVG, PDF | – | hand-lerped colors, clip cuts |
| Glyph metrics / kerning from pinned advances | typography | CPU | – | pinned TSV advances + rounding contract |
| Stroke text (glyph outlines) | typography | CPU, SVG, PDF | – | ink bands, outline exports |
| Styled wrapped paragraphs | typography | CPU | – | line count + width from pinned advances |
| Ellipsis overflow (U+2026) | typography | CPU | – | truncation decision from pinned advances |
| Cross-font fallback + notdef | typography | CPU | – | cmap presence, outline, .notdef advance |
| Opt-in shaping + RTL bidi | typography | CPU | HarfBuzz_jll | pinned gids/advances, cluster reversal; named hint in core |
| Premultiplied/straight alpha boundary | image_lab | CPU | – | hand-derived byte values |
| Blend math (normal/multiply/alpha) | image_lab | CPU | – | documented byte formulas |
| Crop / rotate / resize / flip / invert / spread / blur / opacity | image_lab | CPU | – | hand-derived permutations + pinned blur kernel |
| Native codecs QOI / BMP / PPM / GIF | image_lab | CPU | – | byte-exact round trips + pinned GIF fixture |
| PNG / JPEG / WebP | image_lab | CPU | PNGFiles / JpegTurbo / WebP | exact (lossless) or PSNR bounds (lossy), matte policy |
| ColorTypes matrix interop | image_lab | CPU | ColorTypes | straight bytes, round trip, no-copy views |
| Notebook PNG MIME display (T016) | image_lab | CPU | PNGFiles | showable/show bytes; text fallback in core |
| Snapshot ownership (mutate sources → replay unchanged) | recording_reuse | CPU, PDF | – | byte-identical replay after mutation |
| Re-rasterization at 2x (hand-derived geometry) | recording_reuse | CPU | – | doubled square/outline/stamp |
| One-shot recorder contract | recording_reuse | CPU | – | ArgumentError after finish |
| Parameter change (host-owned redraw) | recording_reuse | CPU | – | exactly the changed region repaints |
| Strict export failures (name the op index) | export_policies | SVG, PDF | – | clearRect / multiply / angular / evenodd-gradient |
| Sentinel destination preservation (no partial writes) | export_policies | SVG, PDF | – | pre-existing file intact after failure |
| PDF raster fallback (raw XObject + SMask) | export_policies | PDF | – | parsed bytes == replay at the documented boundary |
| SVG raster fallback (PNG data URI) | export_policies | SVG | PNGFiles | decodes to the exact replay; named hint in core |

## Limitations (stated, not hidden)

- **No GPU/browser backend exists** in this milestone. "CPU, SVG, PDF"
  are the real renderers; nothing here claims Vulkan or browser Canvas2D.
- **SVG-in-browser is not Canvas2D.** The SVG exports are static vector
  documents (with a PNG data-URI for image stamps when `PNGFiles` is
  present); they are not a live, interactive canvas.
- **Pure-LTR shaping limit.** `shape_text` with auto script/direction
  engages only for unambiguous runs; the RTL paragraph path
  (`layout_paragraph` with `dir = RightToLeft`) always requires the
  opt-in HarfBuzz provider. In core-only environments both raise the
  named install hint (checked, not skipped).
- **Scaled-replay gradient semantics are pinned.** On a re-rasterized
  (e.g. 2x) replay, geometry scales but a gradient pattern samples the
  picture-space handles in image space (untransformed). Vector exports
  instead map the gradient by `T⁻¹`. Asserted as documented behavior,
  not treated as a bug.
- **Lossy codecs are bounded, not exact.** JPEG (q92) and lossy WebP
  (q75) are checked with PSNR floors on a smooth gradient; only the
  lossless paths (PNG, WebP lossless, native QOI/BMP/PPM/GIF) assert
  byte-exact round trips.

## Files

- `gallery.jl` — shared module: pinned font paths, provider
  availability, output-directory helper, entry guard, check counter.
- `drawing_atlas.jl`, `plot_dashboard.jl`, `typography.jl`, `image_lab.jl`,
  `recording_reuse.jl`, `export_policies.jl` — the six programs.
- `run_gallery.jl` — batch runner (+ `--core-only` subprocess re-runs).
- `optional_env/` — isolated optional-provider environment.
