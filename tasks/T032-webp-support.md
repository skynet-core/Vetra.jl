# T032 — Optional static WebP reading and writing

Status: see [TASKS.md](../TASKS.md). Dependencies: T030 WebP contract/decision.
Goal: support practical web graphics with documented alpha and compression modes.

## Inputs and scope

Implement the static-image subset approved in T030, using the chosen optional
provider. Wire WebpFormat, dimensions, magic-byte decode, and extension-driven
write paths; replace the unsupported-format behavior only when real support is
available. Animation remains an explicit unsupported case unless separately scoped.

## Acceptance criteria

- Static decode/encode supports the contracted lossless/lossy modes and alpha,
  with correct row/column order, straight/premultiplied conversion, and dimensions.
- Test opaque, transparent, non-square, small, invalid, and truncated inputs;
  animated files get the documented error rather than an implicit first frame.
- Independently authored/encoded fixtures and a separate reader establish
  interoperability. Lossless checks account for the documented alpha-conversion
  boundary; lossy checks use justified quality bounds, not adjusted tolerances.
- Missing provider gives the specified install hint; core-only and existing
  codec/cache behavior remain intact. No tests need a runtime network fetch.
- Add a web-card export example and report encode/decode time and file size for
  representative images, without claiming universal superiority over PNG/JPEG.

## Validation

Use [shared validation](../docs/ROADMAP.md#shared-validation), provider-present/
absent subprocess tests, independent WebP reader checks, and corpus benchmarks.
Record format/mode coverage and platform artifact checks.

## Results and handoff

Blocked on the T030 WebP decision. Record supported modes and fixture provenance.
