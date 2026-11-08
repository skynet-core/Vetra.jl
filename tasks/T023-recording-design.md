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

Not started. Record the decision and capability matrix before unblocking T024.
