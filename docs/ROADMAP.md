# Port roadmap

Status: all gates below are complete (T000-T011, 2026-11-06); the file is
kept as the original scope statement. These were planned gates, not a
promise of full parity.
Scope is anchored to upstream.toml; update the pin only as a separate documented
change with renewed fixture provenance.

## M0 — Foundation and oracle (T001–T003)

- Verify local package loading and the smoke test.
- Inventory upstream APIs and settle channel, indexing, rounding, and transform contracts.
- Build an independent reference workflow with recorded Nim dependency revisions.
- Implement colors, image storage, scalar compositing, and affine geometry.
- Cover alpha extremes, bounds, overflow, degenerate input, and transform order.

Done when the core numerical tests pass and their expected values have independent
provenance.

## M1 — First useful rendering (T004–T006)

- Paths, required curve/arc operations, coverage, fill rules, and basic strokes.
- A minimal drawing context sufficient for square and line.
- Reproduce square, line, and heart from the pinned examples.
- Save outputs and compare canonical pixel buffers against the reference.
- Heart requires SVG path commands including arcs and quadratic curves, or an
  explicitly documented equivalent construction; string-path parsing is tracked
  separately if deferred.
- Choose an output policy in docs/DECISIONS.md: PNG adapter or a documented
  temporary lossless raw/PPM export for this milestone.

Done when all three examples run locally and their pixel comparisons pass under
a documented policy. PNG byte-for-byte equality is not a rendering criterion.

## M2 — Drawing features (T007)

- Paints, gradients, sampling, blend modes, masks, clipping, image transforms.
- Blur, shadows, resizing, and other image operations found in the source audit.
- Edge cases and combinations, not just isolated happy-path screenshots.

Done when each claimed feature links to tests in docs/COMPATIBILITY.md.

## M3 — Formats and text (T008–T010)

- Decide codec and font dependency policy before implementing those backends.
- Audit formats individually for read/write support and supported subsets.
- Implement SVG, fonts, outlines, metrics, kerning, wrapping, alignment, styled text.
- Integrate complete context state/save/restore and cross-feature behavior.
- Preserve font/image asset licensing and test malformed input.

Done when the compatibility table accurately lists supported, partial, deferred,
and intentionally different behavior.

## M4 — Performance and release (T011)

- Benchmarks against the same pinned upstream workload and toolchain.
- Target measured bottlenecks; retain numerical regression tests.
- User API docs, examples, supported-platform checks, and dependency/license audit.
- Check package name/registration, versioning, and release workflow.

A claim of speed or full compatibility requires recorded measurements and tests.
Keep performance goals provisional until baselines exist.
