# Release notes (draft) — Vetra 0.1.0

Prepared for T018 (adoption release readiness). This is a **draft**, not a
published release: no tag is cut and nothing is registered (that is T019,
which needs an explicit user request). The version in `Project.toml` is
bumped to `0.1.0` so the release metadata is ready.

## Summary

Vetra.jl is a native Julia port of [treeform/pixie](https://github.com/treeform/pixie),
a 2-D canvas renderer. This release makes the package pleasant to install,
learn, and use in everyday Julia code, on top of the already-complete
rendering core.

## What is pinned (compatibility, not new behavior)

The renderer reproduces the behavior of the **pinned upstream revision**,
recorded in `upstream.toml` (pixie `30bb5108…`, declared 6.1.0). That pin is
the source of truth for:

- All drawing, path, fill/stroke, transform, clip, layer, and blend behavior.
- Color arithmetic and the premultiplied-alpha boundary conversions.
- The native codec subset (PNG/BMP/QOI/PPM; JPEG/GIF decode) and the
  native OpenType (TTF/glyf) text subset.

These are verified by a ~811k-assertion test suite against pinned oracle
fixtures (`test/`, `scripts/check.jl`). The compatibility inventory,
including per-feature status and evidence, is in
[COMPATIBILITY.md](COMPATIBILITY.md). Pinning the revision does **not**
promise that the Julia port is universally faster or slower than upstream;
measured comparisons are linked below, not asserted.

## New in this release (opt-in / additive, beyond the pin)

These are additions made during the adoption milestone (T014–T017). They do
not change pinned rendering behavior; they are new, mostly opt-in, conveniences.

- **Ordinary-number arguments (T014).** Drawing coordinate entry points now
  accept `Int`/`Float64` as well as `Float32`; a thin `Real` boundary
  converts once and delegates to the specialized `Float32` kernels, so the
  fast path is unchanged. Keyword arguments remain `Float32`-typed
  (documented limit). See [T014](../tasks/T014-numeric-api.md).
- **Color-matrix interop (T015, opt-in).** With the `ColorTypes` package in
  your environment, `toColors(image)` exports a `Matrix{RGBA{N0f8}}`
  (straight alpha) and `fromColors(matrix)` imports 2-D `RGB`/`RGBA`
  matrices (N0f8 bytes or 0..1 floats) as a premultiplied `Image`. Both
  reuse the PNG boundary conversions, so matrix bytes equal PNG payload
  bytes. Core loads without ColorTypes; use raises an install hint.
  See [T015](../tasks/T015-image-interoperability.md) and D024.
- **Notebook image display (T016).** `Image` has native `show` methods: a
  concise `text/plain` line and an `image/png` MIME (via opt-in PNGFiles).
  `showable` reports PNG availability, so core-only notebooks fall back to
  text instead of erroring. Verified through a real IJulia kernel. See
  [T016](../tasks/T016-notebook-display.md).
- **Docs, gallery, and recipes (T017).** A documentation entry point
  ([INDEX.md](INDEX.md)), a browsable gallery (`docs/build/gallery.html`),
  and an executable cookbook ([cookbook.jl](cookbook.jl)) with eight
  reproducible recipes: sparkline, radial gauge, KPI card, candlesticks,
  image annotation, scientific diagram, dashboard thumbnail, and social
  card. Built by `docs/make_cookbook.jl` (Literate, no new dependency).
  See [T017](../tasks/T017-docs-gallery-recipes.md) and D025.
- **Opt-in codec packages (D014, earlier).** PNG/JPEG/SVG read-write is
  enabled by adding `PNGFiles`, `JpegTurbo`, and `XML` to your environment.
  The core renderer has **no required dependencies**.

## Measurements (linked, not promised)

- Rendering/codec benchmark medians vs. the pinned Nim reference:
  [README benchmarks](../README.md#benchmarks) and
  [T012](../tasks/T012-optimization.md). PNG decode was optimized from
  67.3 ms to ~1.5 ms per 200x100 image (T012); encode remains codec-bound.
- T015 color-matrix conversion: 256x256 `toColors` ~0.80 ms, `fromColors`
  ~0.19 ms, allocation limited to the output buffers
  ([T015](../tasks/T015-image-interoperability.md)).
- T014 numeric dispatch is allocation-neutral on the `Float32` fast path
  ([T014](../tasks/T014-numeric-api.md)).
- Full-suite cost: ~811k assertions, `src/` line coverage 97.97%
  ([T018](../tasks/T018-release-readiness.md) gate log).

These are single-machine measurements at the pinned revision; they are not
a guarantee for arbitrary inputs, platforms, or future Julia versions.

## Installation

The package is **not yet registered** in the Julia General registry (checked
`P/Vetra`, 404, 2026-11-07). Until T019 registers it, install from a
checkout:

```sh
git clone https://github.com/skynet-core/Vetra.jl.git
julia -e 'using Pkg; Pkg.add(path="/path/to/Vetra.jl")'
```

For the opt-in codecs, add them to your application environment before
loading Vetra:

```sh
julia -e 'using Pkg; Pkg.activate("/path/to/myenv", shared=true);
           Pkg.add(path="/path/to/Vetra.jl");
           Pkg.add(["PNGFiles", "JpegTurbo", "XML"])'
```

After T019 registration, these become the standard registry syntax:

```julia
using Pkg
Pkg.add("Vetra")            # core renderer
Pkg.add(["PNGFiles"])       # opt-in PNG read/write
```

## Julia compatibility

- `Project.toml` declares `julia = "1.10"` (lower bound). Developed and
  tested on Julia 1.13.3 (local) and the CI matrix below.
- **CI matrix** (`.github/workflows/ci.yml`): Julia `1.10` and current
  stable (`1`) on `ubuntu-latest`; Julia `1` on `windows-latest` and
  `macos-latest`. It runs `scripts/fetch_upstream.jl` then
  `scripts/check.jl` (tests + coverage gate).
- **Local evidence for this task:** the fresh-depot install/load tests and
  the full `scripts/check.jl` gate were run on Julia 1.13.3 / Linux
  (records in [T018](../tasks/T018-release-readiness.md)). The Julia 1.10
  and Windows/macOS legs are defined in CI but were **not** re-run locally
  for this task; they rely on the CI matrix, which requires a push
  (deferred to T019, explicit request only).

## Release checklist (status)

- [x] Install from checkout in a fresh project/depot (core-only and
  optional-integration) — verified, see [T018](../tasks/T018-release-readiness.md).
- [x] Dependencies have appropriate compat bounds (`julia = "1.10"`); test
  extras are declared under `[extras]`/`[targets] test`.
- [x] Package-load and namespace checks pass (279 public exports; the six
  that shadow Base — `ceil`, `copy`, `diff`, `fill`, `length`, `transpose` —
  are intentional upstream pixie names, always callable as `Base.<name>`).
- [x] Licenses cover all shipped assets (`NOTICE` updated for ColorTypes /
  FixedPointNumbers and the cookbook's Noto Sans font; core is MIT,
  upstream pixie MIT in `third_party/upstream.LICENSE`).
- [x] Docs build from a clean setup (`rm -rf docs/build` then the
  `make_tutorial.jl` / `make_cookbook.jl` commands; fonts fetched by
  `scripts/fetch_upstream.jl`, no reliance on developer-machine state).
- [x] Release notes distinguish pinned compatibility from new optional
  features and link measurements.
- [ ] Registration and publication — **deferred to T019**, requires an
  explicit user request.
- [ ] Julia 1.10 + Windows/macOS CI legs re-run — requires a push (T019).

## Registration instructions (for T019)

1. Keep `name = "Vetra"`, `uuid = "273bb84c-244c-4f17-9eb9-5a651004d3c7"`,
   `version = "0.1.0"`.
2. Re-verify the name is still unregistered at execution time
   (historical 404s are not current evidence).
3. Tag the release commit `v0.1.0`.
4. Register with the official registry tooling, e.g.:
   ```julia
   using Pkg
   Pkg.add("RegistryTools")
   RegistryTools.register("General", "Vetra",
       "273bb84c-244c-4f17-9eb9-5a651004d3c7",
       "https://github.com/skynet-core/Vetra.jl.git", "v0.1.0")
   ```
   (or a `Pkg.register` + `Pkg.add` flow, per current Julia guidance).
5. Publish the tag and confirm the CI matrix passes on the tag.
6. Update the README install block to registry syntax and re-run the
   fresh-install checks against the registered version.
