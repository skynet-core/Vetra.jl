# T026 — PDF export of recorded drawings

Status: see [TASKS.md](../TASKS.md). Dependencies: T024.
Goal: export scalable graphics suitable for reports and publications.

## Inputs and scope

Use T023's PDF dependency/text/embedding decision and T024 recordings. Implement
the bounded single-page export contract first; do not add a report-layout engine.
Reuse recording semantics and validation cases with SVG where appropriate.

## Acceptance criteria

- Valid standalone PDF with explicit page size, drawing-unit conversion, correct
  top-left drawing to PDF coordinate mapping, resources, and transparency.
- Preserve supported paths, strokes, transforms, clips, gradients, and text
  outlines/embeddings. Embedded fonts obey the chosen licensing policy.
- Unsupported effects and raster fallback follow the approved matrix explicitly.
- An independent PDF parser/render tool opens the file; rendered dimensions and
  hand-derived geometry pass, with documented AA/text comparison tolerances.
- A report-graphic example demonstrates scale-independent output. Optional
  dependency absence leaves raster-only usage unaffected with a clear hint.

## Validation

Run [shared validation](../docs/ROADMAP.md#shared-validation), optional-package
load tests, independent PDF structure/raster checks, and the example. Record
verifier versions and attribution for external assets/reference outputs.

## Results and handoff

Blocked on T024. Record supported PDF features and any explicitly rasterized cases.
