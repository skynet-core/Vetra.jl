# T023 — Recording and vector-export design

Status: see [TASKS.md](../TASKS.md). Dependencies: T013. Priority: vector output.
Goal: settle the smallest coherent geometry-recording contract before coding.

## Inputs and scope

Read D007/D011, docs/API.md, Context state/clip/layer semantics, Paint copying,
font outlines, and the tutorial's small SVG writer. Specify a bounded recording
API, CPU replay, and SVG/PDF capability matrix. Produce a design decision and
public API proposal, not exported placeholder functions or a general GUI engine.

## Acceptance criteria

- Define supported commands for paths, solid/gradient fills, solid strokes,
  transforms, images, clips, layers, and text, with clear unsupported cases.
- Define recording lifetime, mutation snapshots for paths/paints/images/fonts,
  copy/ownership, coordinate units, replay scaling, and deterministic ordering.
- Explain how a recording is created without disrupting the existing immediate
  Context API or requiring already-rasterized images to become vectors.
- Specify export behavior for blends/effects unsupported by the output format:
  explicit error or documented opt-in raster fallback, never silent loss.
- Choose text-outline versus embedding policy, image embedding, page sizing,
  and any optional PDF dependencies with licensing/Julia compatibility rationale.
- Define independent references and acceptance checks for T024–T026; explicitly
  extend D007/API guidance while leaving existing raster behavior unchanged.

## Validation

Walk the contract through the activity card, a transformed/clipped path,
overlapping translucent layers, an image, and glyph text. Check feasibility
against SVG/PDF specifications and record sources. Validate links/API examples;
do not claim an implemented renderer or exporter from the design alone.

## Results and handoff

Status: done (2026-11-08). Design only — no source changes, no exports.
Contract in [docs/RECORDING.md](../docs/RECORDING.md), decision D030,
API proposal in [docs/API.md](../docs/API.md) §Recordings. T024 unblocked.

### Decisions (summary)

- **Recording model**: a display list of core-kernel invocations
  (`fillPath`/`strokePath`/`draw` + group ops), not Context-method calls.
  CPU replay re-executes the kernel list, so default-size replay is
  byte-identical to direct drawing by construction; export is a mapping
  problem over the same ops. Chosen over Context-call recording (would
  duplicate the context wrapper semantics) and over per-op raster
  fallback (a second renderer).
- **API**: one-shot `PictureRecorder(w, h)` with a `RecordingContext`
  mirroring the Context drawing surface; `finishRecording` → immutable,
  self-contained `Picture`; `drawPicture(image, picture; tform)`;
  `writeSvg`/`writePdf` (T025/T026). Extends D011's reserved
  Picture/PictureRecorder seam; `Context` and all raster entry points
  untouched.
- **Snapshots**: deep copies at the record boundary — path command
  buffers, paints (gradient arrays + image payload), stroke settings,
  per-op tform, cumulative clip lists; `fillText`/`strokeText` lower to
  glyph outline paths at record time (no font needed at replay/export —
  the text policy for both formats).
- **Replay scaling**: logical canvas scaled in vector space by
  (imgW/picW, imgH/picH), re-rasterized — never a raster enlargement.
- **Record-boundary errors**: TiledImagePaint fills and non-solid stroke
  styles raise `ArgumentError` at the call, no op appended (fail fast,
  no partial recording).
- **Export v1, strict by default**: first unexportable op raises before
  any file is written; documented opt-in `rasterFallback` renders the
  whole picture to one embedded image. SVG: solid/linear/radial fills,
  solid strokes, transforms, clipPath, nested groups, group-unit opacity,
  base64 PNG images, glyph outlines (no angular gradients, no clearRect,
  no non-Normal blends, no tiling). PDF: single page, ShadingType 2/3
  (elliptical radial via an ellipse-to-circle CTM), Form XObject
  transparency groups, FlateDecode RGB images via stdlib
  `Compression.jl` (same unsupported rows). No new dependencies
  (SVG export is string output; read-back uses the existing opt-in XML).
- **T024–T026 references**: five canonical validation scenes (activity
  card; transformed/clipped path; overlapping translucent layers; image
  scene; glyph text) with hand-derived expectations, per-task acceptance
  checks, and independent references (W3C SVG, ISO 32000-1, resvg as
  external SVG renderer candidate, qpdf + mupdf/Ghostscript for PDF,
  Vetra's pinned SVG reader supplemental).

### Verification

- Contract walked through all five scenes: every op kind maps to a
  supported primitive or a named strict-error row; no scene requires
  silent loss or a raster dependency at record time.
- `git diff --check` clean; local links in RECORDING.md/API.md/DECISIONS.md
  checked (relative paths exist: docs/RECORDING.md, docs/API.md,
  docs/COMPATIBILITY.md, tasks/T023-…). No source changes, so the
  scripts/check.jl gate result stands from T022 (811k+ assertions,
  98.01%); no implemented renderer or exporter is claimed.

### Next

T024 (recording implementation + CPU replay) is ready; T027 and T030
remain ready in parallel chains.
