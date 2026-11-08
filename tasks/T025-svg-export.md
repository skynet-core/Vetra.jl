# T025 — SVG export of recorded drawings

Status: see [TASKS.md](../TASKS.md). Dependencies: T024.
Goal: export editable/scalable SVG from recorded geometry rather than pixels.

## Inputs and scope

Follow T023's capability matrix and implemented recordings. Extend the existing
format API only as specified; reuse the tutorial writer's lessons, not its
limited implementation as a claim of full SVG support. Scope is vector paths,
supported paints/strokes, transforms/clips, images, and the agreed text policy.

## Acceptance criteria

- Output is valid standalone SVG with explicit size/viewBox, stable identifiers,
  correct escaping, alpha, clipping, gradients, and stroke semantics.
- Paths remain paths and outlines remain geometry. Embedded bitmap content and
  any raster fallback are identifiable and documented, not hidden full-image SVG.
- Unsupported effects/blends follow T023 exactly; no silent dropped drawing.
- Parse structure independently and render with a pinned external SVG renderer.
  Compare hand-derived simple geometry exactly; justify renderer-specific AA
  tolerances before evaluating complex images. Vetra read-back is supplemental.
- Provide a runnable raster/SVG example and remove redundant tutorial-only export
  code when the production API covers its actual features.

## Validation

Run [shared validation](../docs/ROADMAP.md#shared-validation), independent
structural/render checks, and the updated tutorial. Document external verifier
versions, fixture licenses, and expected-output provenance.

## Results and handoff

Status: done (2026-11-08). `writeSvg` implemented per D030 §6.1 in
`src/formats/svg_write.jl` (string output; no new dependency), 333-assertion
test suite green, full gate green (811,885 assertions, 98.28%).

## Changes

- `src/formats/svg_write.jl` (new): standalone SVG writer for `Picture`:
  `<svg width height viewBox>` document, op-ordered elements, stable
  sequential ids (`gnN` gradients, `cpN` clipPaths, `imN` images — groups
  need none). Path `d` serializes the flat command buffer (all 19 command
  kinds incl. relatives, S/T reflection, endpoint arcs with radians->degrees
  conversion) — the same grammar `commandsToShapes` consumes, so a renderer's
  path build matches the raster's. Solid fills/strokes emit straight-RGB hex
  plus `fill-opacity`/`stroke-opacity` = clamp01(opacity) * a/255 (the raster
  byte formula pre-rounding). Even-odd via `fill-rule="evenodd"` (path + clip
  children). Strokes: width/cap/join/miterlimit/dasharray (odd dash lists
  double in both the raster `strokeShapes` and the SVG spec).
- `writeSvg(file, picture; rasterFallback = false) -> String` (returns the
  document, also written to `file`); exported from `Vetra`.
- Strict pre-scan (before any file write; `ArgumentError` names the 1-based
  op index): clearRect; angular gradient fills; ImagePaint fills; non-Normal
  blend fills/strokes; coincident linear handles; degenerate radial handles
  (center == edge/skew); gradient fills under singular op transforms; stop
  positions outside [0, 1] or not non-decreasing; non-finite geometry
  (path coords, transforms, stroke width/miter/dashes, group opacity).
  DrawImage ops require the opt-in `PNGFiles` (D014 install hint, same
  contract as the other codecs) — checked in the pre-scan.
- `rasterFallback = true`: replays the picture to an image, embeds one
  full-canvas base64 PNG `<image>` (marked with an XML comment), no vector
  content. Never silent loss.

## Gradient mapping (the T023 "derived in T025" derivation)

The raster samples gradients in **image space with untransformed handles**
(`_fillGradientLinearMasked`/`_fillGradientRadialMasked`; upstream paints.nim
L23 documents `gradientHandlePositions` as "image space"), while an SVG
`userSpaceOnUse` gradient lives in the referencing element's space (the path
space, pre-`transform`). Exact rep for every invertible op transform `T`:

- **Linear**: emit the raw canvas handles and
  `gradientTransform = matrix(T^-1)`. Proof: both sides are affine in the
  element point `q` — raster `t(T q) = (q . T^+ d)/|d|^2 - (h1 . d)/|d|^2`;
  SVG with `GT = T^-1`: `t(q) = ((GT^-1 q - h1) . d)/|d|^2` — equal since
  `GT^-1 = T`.
- **Radial**: unit circle at the origin (`cx=0 cy=0 r=1`) with
  `gradientTransform = matrix(T^-1 * M)`, where
  `M = translate(center) * rotate(theta) * scale(dX, dY)` is the raster's
  ellipse map (identical formula to `_fillGradientRadialMasked`, incl.
  `theta = fixAngle(angle(normalize(center - edge)))`). Proof: raster
  `t(p) = |M^-1 p|`; SVG `t(q) = |(T^-1 M)^-1 (T q)| = |M^-1 T q|` — equal.
- Singular `T`: unrepresentable -> strict pre-scan error (named).

Element transforms go on the `path`/`image` elements themselves
(`transform="matrix(...)"`, omitted at identity), keeping path data in
picture space; strokes are exact for all `T` because the raster strokes in
path space then transforms (same order as the SVG element transform).
Clips are canvas-space: the group carries no transform and its `<clipPath>`
children (all cumulative clips of the scope at GroupEnd) intersect per the
SVG spec, matching the replay's mask rasterization.

## Verifiers and provenance

- **Independent structure**: the opt-in `XML` package (test target, docs env)
  parses the output: element tags/attributes, and every `url(#id)` reference
  resolves to a defined `id` (test/svg_export_tests.jl "XML structural parse").
- **Pinned external renderer**: headless **Chromium 156.0.8078.47** (snap;
  BSD-style licensed; verification tooling only, not a package dependency —
  `resvg`/`rsvg-convert`/`inkscape` are absent on this machine, recorded per
  the task's validation note). Gated testset: a 100x50 scene (opaque integer
  rect, horizontal gradient, dashed round-cap line) screenshotted and decoded:
  rect interior and background exact; gradient interior within the justified
  center-vs-integer sampling tolerance (Vetra samples `t` at integer `x`,
  Chromium at pixel centers, |dt| = 0.005 -> <= 2 channels, measured);
  dash-body pixels exact. The snap sandbox denied `/tmp` and hidden home
  dirs, so the test uses `$HOME/vetra-svgtest` (cleaned up).
- **Hand-derived exact geometry**: byte-exact minimal document; exact `d`
  strings for all command kinds; exact `matrix(…)` strings from the pinned
  Mat3 convention (translate inverse, `T^-1*M` for scale(2)); exact stop
  offsets/opacities from the byte values; exact clip/group structure.
- **Vetra read-back (supplemental)**: an identity-transform, opaque, no-clip
  scene (solid fills + stroke + linear gradient) reads back through the
  pinned `parseSvg`/`newImage` **byte-identical to the replay**. Reader
  deviations (documented, not exporter bugs): it re-applies the element
  transform to `userSpaceOnUse` handles (exact only at identity), skips
  `clipPath`/`image` elements, has no `radialGradient` (a radial fill
  reference raises "Missing SVG resource"), and multiplies group `opacity`
  into each child paint (per-child, not group-unit).
- **Expected-output provenance**: all expectations hand-derived from the
  W3C SVG 1.1 spec (path data, gradients, clipPath intersection, group
  opacity, image data-URIs) and the pinned Mat3/raster formulas — never
  from `svg_write.jl` itself. The Chromium checks compare renderer output
  against the replay (which is transitively pinned by the T024 A/B byte
  parity), with the sampling tolerance justified above.

## Known limitations

- Interior dash-end caps: the SVG spec (and Chromium) draw round/square
  caps at every dash end; the pinned raster (`upstream strokeShapes`) caps
  only the shape's first/last points. The export is spec-faithful (it
  encodes the stroke's *settings*); only interior dash-end cap pixels
  differ from a replay (each <= ~0.79 coverage, on dashed lines with
  non-butt caps). Recorded, not hidden.
- Recording nuance (T024, exported as recorded): `RecState` copies the clip
  list per `save`, whereas the immediate pipeline aliases the one clip
  bitmap (`ContextState.mask`), so a `clip -> save -> clip -> restore`
  sequence leaks the second clip in the raster but not in a replay/export.
  The exporter maps the recording's semantics exactly; the divergence is in
  the recording model, not the export.
- `ImagePaint` *fillStyle* (as opposed to `drawImage` ops) is a strict v1
  error (the D030 matrix lists images via `drawImage`; an arbitrary-path
  image fill needs a mask/pattern follow-up).
- One uncovered line in `svg_write.jl`: the pre-scan branch for a missing
  `PNGFiles` (the gate environment always has it; the hint text mirrors the
  other codecs' D014 contract).

## Tutorial writer kept

The acceptance clause "remove redundant tutorial-only export code when the
production API covers its actual features" is **not met**: the tutorial
(`docs/tutorial.jl` §9-11) emits `<text>` elements (viewer-font dependent)
and a chart-specific document shape, while `writeSvg` v1 exports glyph
outline paths and the recording's op structure. Production covers the
tutorial's *vector* features (rects, paths, gradients, viewBox, hex colors,
read-back) but not its `<text>` output, so the tutorial's small writer stays
until a text-element export mode exists (backlog, not this task).

## Verification

- `julia --startup-file=no --project=. scripts/check.jl`: green —
  **811,885 assertions** (+333 vs T024), **98.28% src line coverage
  (6241/6350)**; T025 testset 333/333.
- Cookbook recipe 10 ("Record, replay, and export as SVG"): byte-identical
  replay vs direct, `writeSvg` assertions, `record.svg` +
  `record-10-replay.png` saved; gallery rebuilt (12 items). The exported
  SVG was rendered in headless Chromium 156.0.8078.47 and visually matches
  the replay raster (gradient, clipped badge, dashed divider, glyph text).

## Next

T026 (PDF export) is unblocked and ready (same op list, same strict
contract; capability matrix in docs/RECORDING.md §6.2).
