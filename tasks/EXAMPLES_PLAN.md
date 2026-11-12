# Feature-driven example programs

User request (2026-11-12): review the work, propose improvements, and have
Qwen3.8 implement examples demonstrating the library across backends/renderers.
Reproducible library bugs discovered while developing them must be fixed and
regression-tested, not hidden with example-specific workarounds.

## E001 — executable examples on the current public API

**Done, independently approved 2026-11-12:** writer `873939f`, integrated through
`254be96`. All six programs and optional/core-only CLI runs pass. Both required
Julia gates pass (1.10: 96.11%, 1.13: 96.07%; 79 gallery tests each). Review
fixed BMP header/alpha interoperability, PDF numeric serialization and strict/
fallback image orientation; D038 and `docs/HANDOFF.md` record independent
Pillow/Poppler/Chromium evidence and commands. Run instructions and the feature
matrix are in [the gallery README](../examples/gallery/README.md).
The backend extensions below remain attached to their dependency-ready tasks.

Owner: Qwen3.8, `examples/feature-gallery`, worktree
`/tmp/opencode/vetra-feature-gallery`. Base: `7a54ea9`. Coordinator reviews,
validates and integrates. This independent consumer task does not change R010's
unreviewed Canvas contracts or add dependencies to core.

Implement all six programs under `examples/gallery/`. Prefer a small shared
scene module over duplicate drawing code; reuse existing helpers when suitable.
Use public snake_case APIs. Every program has a documented command, deterministic
input, useful output in a caller-selected directory, and meaningful assertions.
Imports must not render or write files. Re-running a program must not overwrite
input assets. Defaults work offline once the documented providers/fonts exist.

| Program | Demonstration | Current outputs/checks |
| --- | --- | --- |
| `drawing_atlas.jl` | Paths, fill rules, caps/joins/dashes, transforms, linear/radial gradients, clips and group opacity | Same reusable scene through direct CPU drawing and recorded CPU replay, SVG and PDF; exact direct/replay pixels plus hand-derived interior samples |
| `plot_dashboard.jl` | Line/scatter plot and heatmap with axes/labels, clipping, legends and layout | CPU/SVG/PDF; map large-offset Float64 data to local coordinates before Float32 geometry, verify known endpoints and inverse mapping; a consumer example, not a new plotting API |
| `typography.jl` | Native font outlines/metrics, styled wrapped paragraphs, ellipsis, fallback and opt-in Arabic/RTL shaping | CPU and supported recorded SVG/PDF text routes; explicit pinned font paths/provenance, real shaped glyph/line/cluster checks; state the existing pure-LTR shaping limit |
| `image_lab.jl` | Straight/premultiplied alpha, ColorTypes matrix import/export, borrowed bytes versus copies, crop/resize/rotate, masks/blends and effects | Generated inputs, before/after CPU images, native codec exact roundtrips; optional PNG/JPEG/static WebP with explicit matte/lossless policy, no lossy exact-equality assertion; demonstrate current PNG MIME display for notebooks without claiming the future live adapter |
| `recording_reuse.jl` | Build once, mutate original source assets, replay at two resolutions; host-owned redraw and parameter changes | CPU/SVG/PDF where supported; verify recorded asset ownership and rerasterization, no external GUI framework or invented lifecycle API |
| `export_policies.jl` | Strict vector export and explicit raster fallback | An intentionally unsupported operation must fail with a useful error and preserve an existing destination; opt-in fallback produces a real SVG/PDF with embedded raster, with independently justified bounds/alpha checks |

Provide a small batch runner and a coverage table linking features to programs,
available renderers, optional dependencies, checks and limitations. Core-only
runs must genuinely avoid optional packages; opt-in runs fail with actionable
setup instructions instead of reporting skipped work as passed. Use an isolated
example environment/setup command, never `Pkg.add` during program execution.
Read existing display/export contracts before choosing assertions or scenes.

Add focused automated example tests to `test/runtests.jl`; independent expected
values come from math/contracts, not generated snapshots treated as ground truth.
Run the real programs as well as their helpers. Inspect rendered artifacts.
Fix outdated existing example instructions encountered along the way, including
the unconditional optional-provider use in `examples/showcase.jl`.

Library bug fixes belong in separate bounded commits with reproduction and a
regression test. Writer may edit connected `src/` methods and focused tests for
actual E001 failures; coordinate any public-contract or root-dependency change
first. Keep provenance and existing reference fixtures intact. Required gate:
`julia --startup-file=no --project=. scripts/check.jl` (Julia 1.10 compatible).

## Backend extensions of these programs

These are implementation obligations attached to existing roadmap tasks, not
dummy examples pretending unavailable providers exist. Port the same scenes and
checks to the reviewed Canvas API once its dependencies land:

- **R030/R041–R045:** CPU/Vulkan side-by-side atlas and dashboard, explicit
  GPU readback, capability checks, unsupported-feature failure, independent
  comparisons and validated lifecycle. Record actual device/driver/features.
- **R050–R052:** browser Canvas2D scene explorer with transform/clip/paint controls,
  actual browser rendering and captures; HTML accessibility and keyboard controls.
- **R022/R023/R060:** extend image lab to Matrix/Vector/StaticArray storage and
  CPU/GPU processor choice, copy/borrow semantics and explicit transfer ownership.
- **R061–R063:** run reusable scenes through new PDF/SVG providers, preserving
  strict/fallback policy and actual document interoperability checks.
- **R070/R071:** notebook dashboard with real MIME display and live parameter
  update; distinguish rendered browser output from an embedded static image.
- **R064–R069:** `media_editor.jl`: decode GIF/WebP/MP4, select/edit frames, overlay
  drawings, concatenate and encode/record. Verify rational timing, dimensions,
  loops and matte policy; preserve sources and reject unsupported tracks clearly.
- **R014:** extend the dashboard/reuse examples into real external GUI/plotting
  consumer proofs with host-owned events, resize/DPI and precise inverse mapping.

Qwen implements these extensions in their dependency-ready tasks; the
coordinator independently reviews each. R098 assembles the illustrated README
from executed artifacts. R099 publishes the interactive tutorial **last**.

## Review improvements to enforce

1. Reuse scene construction across targets; do not compare unrelated pictures.
2. Pair visual artifacts with semantic assertions and renderer-specific limits.
3. Preserve validation messages and fail loudly on unavailable capabilities.
4. Keep the SPIRV.jl prototype's feature requirements separate from future Vulkan
   backend minima; portability claims require execution on each claimed target.
