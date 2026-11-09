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

Status: done (2026-11-09). `writePdf` implemented per D030 §6.2 in
`src/formats/pdf_write.jl` (string output; no new dependency), 202-assertion
test suite green, full gate green (96.25% src/ line coverage).

## Changes

- `src/formats/pdf_write.jl` (new): standalone PDF 1.4 writer for `Picture`.
- `src/Vetra.jl`: include + export `writePdf`.
- `test/pdf_export_tests.jl` (new, registered in `test/runtests.jl`): 202
  assertions across 10 testsets.
- `src/formats/svg_write.jl` + `test/svg_export_tests.jl`: the path-command
  buffer stores arc x-axis rotation in **degrees** (the upstream unit), so the
  SVG `A` command emits it verbatim — removed an erroneous ×180/π conversion
  (the T025 tests only exercised rotation 0, so it passed either way); the
  d-serialization test now uses 45/135-degree rotations.
- `docs/cookbook.jl` + `docs/make_cookbook.jl`: recipe 11 — a report
  graphic exported at 96 and 288 dpi (two named PDFs) plus a gallery item.
- Docs: `docs/API.md` (writePdf implemented), `docs/COMPATIBILITY.md`
  (PDF-write entry), `docs/RECORDING.md` §6.2 (matrix updated to what was
  built: uncompressed streams, function numbering, strict rows, verifiers).

## Derivations (hand-derived before implementation)

- **Coordinate mapping.** Root CTM `s 0 0 -s 0 sH cm` with
  `s = 72/dpi`: picture (top-left, y-down) → page (bottom-left, y-up),
  page size `W*s × H*s` pt. Verified by both renderers (MediaBox +
  pixel-exact geometry at dpi 72).
- **Linear gradients.** The raster samples
  `t = ((c - h1)·d)/|d|²` in canvas space with `c = T·p`; the PDF shading
  samples `s(p) = ((p - h'1)·d')/|d'|²` in element space. Matching the
  gradient direction (`d' ∥ Tᵀd`) and offset gives, exactly for every
  invertible `T`: `d' = (|d|²/|Tᵀd|²)·Tᵀd`, `h'1 = T⁻¹h1 + α·d'` with
  `α = t0 - h'1·d'/|d'|²` and `t0 = h1·d/|d|²`. (Same construction the
  SVG writer does via `gradientTransform = T⁻¹`.)
- **Radial gradients.** The raster's kernel is
  `t = |M⁻¹·c|` with `M = translate(center)·rotate(θ)·scale(dX, dY)`
  (`src/paints.jl`). So the PDF emits the unit-circle shading
  (`Coords [0 0 0 0 0 1]`) under the CTM exactly `M` — not `T` then `M`
  (the shading samples in element space, so the path must be emitted in
  `M⁻¹∘T` space; `_affinePath` handles that, flattening arcs there).
- **`sh` does not clip to the current path.** ISO 32000-2 Table 76: the
  shading paints "directly to current user space". Both pinned renderers
  empirically ignore a preceding path for `sh`, so gradient fills emit
  the path, then `W n`, then `sh`. (Even-odd gradient fills are
  pre-rejected, so `W n` is always the right clip.)
- **Gradient stop functions.** ISO 32000-2 Table 38: FunctionType
  0 = sampled, 2 = exponential, 3 = stitching (requires `Functions`,
  `Bounds`, `Encode`; no `Ranges`/`Stretch` entries), 4 = PostScript —
  and **no constant function type exists**. Confirmed against poppler
  26.01.0 `Function.cc` (`funcType 0 → SampledFunction`,
  `3 → StitchingFunction` which demands `/Encode`), mupdf 1.28.2, and
  gs 10.06.0 empirically. So multi-stop gradients are Type-3 stitchings
  of Type-2 segments with `Encode` mapping each subdomain to [0 1]; a
  single stop is Type-2 with `C0 == C1`.
- **Semi-transparent gradient stops → strict error.** A 4-component
  shading function over DeviceRGB is not portably honored: gs 10.06.0
  warns `GfxUnivariateShading: function with wrong output size` and
  drops the fill, poppler 26.01.0 silently skips it, mupdf 1.28.2 draws
  it ignoring the alpha. Per-stop alpha therefore raises; uniform
  `paint.opacity` still works via ExtGState `/ca`.
- **Group opacity (empirical pin).** A Form XObject with
  `/Group <</Type /Group /S /Transparency /I true>>` drawn with a
  `/ca` ExtGState in effect at `Do` time composites group-unit:
  children composite into an isolated buffer, then the buffer composites
  at the group alpha. Hand-crafted constant-alpha case (red rect +
  half-alpha blue rect over white): both verifiers agree — overlap
  (191,127,191) gs / (190,127,191) poppler — vs the per-child result
  (127,191,191). The page itself carries no `/Group`; only the forms do.
- **Images.** `Do` maps the image onto the unit square, so the content
  CTM is `imageMat·scale(w, h)`; streams are raw uncompressed
  DeviceRGB (premul → straight via the pinned `toStraightAlpha`) +
  DeviceGray SMask. Uncompressed because the frozen build has no stdlib
  `Compression` and D030 bars codec packages for this task.
- **Arcs.** Flattened to <=90-degree cubic segments from the pinned
  `endpointToCenterArcParams` (k = (4/3)tan(d/4)), both directly
  (`_pdfArc`) and in transformed space (`_affineArc`).
- **Quadratics.** PDF path objects are straight lines, rectangles, and
  **cubic** Béziers only (§8.5.2) — there is no quadratic operator. The
  first emission used SVG's `q`; gs, poppler, and mupdf all silently
  ignored it (blank render, no error), so quads now emit the exact cubic
  equivalent `c1 = p0 + 2/3(q - p0)`, `c2 = p2 + 2/3(q - p2)`.
- **Arc endpoint bug (caught by the behavior test).** The command
  buffer's `c0` for Arc/RArc is `(rx, ry)`, not the endpoint; the
  endpoint is `cmds[i+5], cmds[i+6]`. The first emission fed `(rx, ry)`
  as the arc end (visible as a grossly mis-shaped arc), fixed in both
  `_pdfPath` and `_affinePath`.

## Validation

- `julia --startup-file=no --project=docs -e 'using Test; using Vetra;
  include("test/pdf_export_tests.jl")'` → 202 passed, 0 failed, 0 errored.
  Testsets: hand-derived check scene under both verifiers (44), document
  structure self-consistency — xref offsets, stream Lengths, trailer
  (32), dpi scale independence (20), arc flattening (6), arc+quad
  commands (15), even-odd solid fill (5), group/clip structure (17),
  image/SMask byte-exactness (5), rasterFallback byte-exact replay +
  strict-refusal (20), strict pre-scan errors, no file written (38).
- Verifiers (independent parsers/renderers, tooling only):
  Ghostscript 10.06.0, poppler 26.01.0 (`pdftoppm`); PyMuPDF (mupdf
  1.28.2) used for pixel inspection during development.
- Full gate: `julia --startup-file=no --project=. scripts/check.jl` → all
  tests pass, src/ line coverage 96.25%.
- Tolerances: linear shading pixel checks ±2 (gs samples at pixel
  centers); radial shading ±10 — the renderers sample shadings with
  renderer-specific sub-pixel offsets up to ~1 px and the spec does not
  pin shading sampling; stroke edge pixels carry ~0.1–0.5 pt of
  renderer-specific antialiasing, so arc-band checks use pixel centers
  >=0.5 pt inside / >=1.5 pt outside the band.

## Limitations / follow-ups

- Image streams are uncompressed (FlateDecode would need a codec
  decision; D030 bars new dependencies for this task).
- No constant function type in the spec → single-stop gradients use
  Type-2 with C0 == C1.
- even-odd gradient fills, angular fills, ImagePaint fills, clearRect,
  non-Normal blends, and semi-transparent stops are strict errors (v1).
