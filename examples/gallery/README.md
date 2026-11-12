# Feature gallery

Six executable programs that demonstrate the current public Vetra API on
deterministic, offline inputs. Every program self-checks with
hand-derived or pinned-oracle expectations (never pixels captured from
the code under test), is import-safe (including it renders nothing),
and writes only to a caller-selected output directory.

## Running

One-time, from the repository root — the pinned reference checkout
(fonts, file-format fixtures; provenance in docs/UPSTREAM.md, pinned by
upstream.toml) is gitignored and fetched explicitly:

```
julia --project=. scripts/fetch_upstream.jl
```

The Noto Sans Arabic/Devanagari fonts are the committed `test/fixtures/`
files (sha256 sidecars). Every program raises an actionable error
naming the missing input and this command if it runs without them.

```
# one program (current environment; optional features activate if present)
julia --project=. examples/gallery/<name>.jl [outdir]

# all six + the coverage summary (current environment)
julia --project=. examples/gallery/run_gallery.jl [outdir]

# all six, plus a core-only subprocess re-run of each (a preflight
# first proves all six optional providers are absent from the
# isolated environment; then each program's core-only branch — named
# install hints, no silent skip-as-pass — is checked end to end)
julia --project=. examples/gallery/run_gallery.jl [outdir] --core-only
```

`outdir` defaults to `artifacts/gallery/`; programs never download
anything themselves.

## Environments

Core-only runs need the repository environment (Vetra + its core
dependencies) plus the pinned inputs from Running above. To enable the
optional features (PNG, JPEG, WebP, ColorTypes matrix interop, HarfBuzz
shaping, XML) in an isolated environment that never touches the
repository `Project.toml`/`Manifest.toml`, from the repository root:

```
julia --project=examples/gallery/optional_env -e 'using Pkg; Pkg.develop(path="."); Pkg.instantiate()'
julia --project=examples/gallery/optional_env examples/gallery/run_gallery.jl
```

No program ever calls `Pkg.add` at runtime; when a provider is absent the
affected checks assert the named install-hint error instead of skipping.

## Notebook display (T016)

`image_lab` exercises the current notebook contract: a bare `Image` in a
cell is served by `show(MIME"image/png", img)` (PNGFiles present), with
a text/plain fallback in core. Minimal runnable call, from the
repository root, in the optional environment from above:

```julia
include("examples/gallery/image_lab.jl")  # import-safe: no rendering
img = test_image()                        # 4x4 Image, valid premultiplied
img                                       # a notebook cell displays the PNG
```

This documents the display path only — no live-adapter or
interactivity claim; `run()` returns the check report, never the image.

## VS Code / Jupyter notebooks

`image_lab.ipynb` (this directory) is a clean, unexecuted notebook
that includes `image_lab.jl` from its package location
(`pkgdir(Vetra)` — no host-specific paths) and asserts the T016
contract with hand-derived expectations: MIME payload byte identity,
source preservation, independent premultiplied pixels, and the PNG
round trip. The display cells use image functions only (`enlarge8`,
`invert!`, `apply_opacity!`, `rotate_90`) — no font fixtures, so it
runs without the gitignored `.reference` checkout.

One-time, from the repository root — an isolated project under the
already-gitignored `artifacts/` directory (the pattern of
`optional_env` above, with only the two packages the notebook needs;
`Pkg.develop` before `Pkg.add` so the local Vetra is never resolved
from the registry; the repository `Project.toml`/`Manifest.toml` are
never touched):

```
mkdir -p artifacts/notebook-env
julia --project=artifacts/notebook-env -e 'using Pkg; Pkg.develop(path = "."); Pkg.add(["IJulia", "PNGFiles"]); Pkg.instantiate()'
julia --project=artifacts/notebook-env -e 'using IJulia; IJulia.installkernel("VetraNotebook", "--project=$(dirname(Base.active_project()))")'
```

The `$(...)` in the install command is Julia string interpolation
(the absolute env path), not a shell expansion — it works even when
the checkout path contains spaces. The kernelspec is registered in
your normal Jupyter data directory.

Then in VS Code (prerequisite: the Microsoft Jupyter extension
`ms-toolsai.jupyter` installed): open this repository, open
`examples/gallery/image_lab.ipynb`, and pick the kernel via
`Notebook: Select Notebook Kernel` → `Select Another Kernel...` →
`Jupyter Kernels` → `VetraNotebook` (a version suffix such as
`VetraNotebook 1.13` may be shown), and run all cells. Expected: the
contract cells finish with no error (a failed `@assert` errors the
cell), and the two display cells render the 32×32 test image and the
200×64 original / inverted / 50% opacity / rotated strip. Kernel
selection follows the official Jupyter kernel management
documentation
(https://code.visualstudio.com/docs/datascience/jupyter-kernel-management).
This direct-kernel path needs no Python and no PDF tooling.

If the picker does not offer `VetraNotebook`: start a local Jupyter
server (this path requires a Jupyter installation, e.g.
`python -m jupyter server --ip=127.0.0.1 --port=8899 --no-browser` —
the default token stays intact and the server prints a token URL),
then in VS Code use `Select Another Kernel...` →
`Existing Jupyter Server` → `Enter URL of running server` and paste
the full token URL; select the `VetraNotebook` kernelspec.

## Coverage matrix

Feature → program, renderer, optional dependency, and what is checked.
"Core" means the check runs without any optional provider.

| Feature | Program | Renderer | Optional dep | Checks |
| --- | --- | --- | --- | --- |
| Paths, fill rules (even-odd/non-zero) | drawing_atlas | CPU, SVG, PDF | – | hand-derived interior pixels, byte replay |
| Caps (butt/round/square), joins (miter/round/bevel), dashes | drawing_atlas | CPU, SVG, PDF | – | hand-derived stroke extents |
| Transforms (translate/rotate) | drawing_atlas | CPU, SVG, PDF | – | hand-derived corner pixels |
| Linear + radial gradients | drawing_atlas | CPU, SVG, PDF | – | hand-lerped stops; no exponent numbers in the PDF (ISO 32000-1 §7.3.3) |
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
| PNG / JPEG / WebP | image_lab | CPU | PNGFiles / JpegTurbo / WebP | exact (lossless) or PSNR bounds (lossy); JPEG alpha flattened to the explicit matte |
| ColorTypes matrix interop | image_lab | CPU | ColorTypes | straight bytes, round trip, range views accepted (result is a copy) |
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

- **Renderer scope.** CPU raster, SVG and PDF are the renderers
  implemented and exercised here. The renderer-independent canvas
  design targets GPU (Vulkan.jl, offscreen first) and browser Canvas2D
  later in this milestone (docs/CANVAS_DESIGN.md renderer table);
  neither backend exists yet, and nothing in these programs claims one.
- **SVG-in-browser is not Canvas2D.** The SVG exports are static vector
  documents (with a PNG data-URI for image stamps when `PNGFiles` is
  present); they are not a live, interactive canvas.
- **Dash-row cross-renderer difference.** The atlas square-capped dash
  row (dashes [12,6], stroke width 8) renders with the gaps preserved
  on CPU — the documented interior dash-end cap deviation
  (docs/RECORDING.md §6.1, T025) — while a standard renderer's square
  caps extend every dash end by 4 px and bridge the 6 px gap, so the
  same row appears nearly solid in the SVG/PDF exports. Both outputs
  are correct for their semantics; the visible difference is stated,
  not papered over.
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
