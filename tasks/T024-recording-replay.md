# T024 — Drawing recordings and CPU replay

Status: see [TASKS.md](../TASKS.md). Dependencies: T023.
Goal: record supported drawing operations once and replay them into Images.

## Inputs and scope

Implement exactly the approved T023 API using the existing Julia rendering
kernels. Likely ownership: a recording module, Context integration where
specified, exports, focused tests, and examples. Avoid a generic plugin registry,
scene graph, or window/event abstraction.

## Acceptance criteria

- Record/replay every command in the approved matrix, including supported state
  transitions; immutable snapshots survive later mutation of source objects.
- Default-size replay matches direct CPU drawing on independent fixture-backed
  examples. Test multiple replays, nested state, transforms, clips, layers,
  gradients, image drawing, and text boundaries specified by T023.
- Explicit output scaling has tested geometry/coverage expectations; it is not
  implemented as enlarging an already-rasterized image.
- Unsupported commands fail at the specified boundary, with no partial result
  mistaken for a complete recording. Existing Context callers remain unchanged.
- Document ownership and benchmark record cost versus repeated replay cost,
  allocations, and direct drawing for a representative scene.

## Validation

Use [shared validation](../docs/ROADMAP.md#shared-validation) and T023's
independent cases; include new tests explicitly in test/runtests.jl. Add a
record-once/replay-at-two-sizes example with assertions and visible output.

## Results and handoff

Blocked on T023. Record supported command coverage and replay evidence.
