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

Blocked on T024. Record supported export cases, limitations, and verifier output.
