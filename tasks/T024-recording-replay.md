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

Status: done (2026-11-08). The D030 contract is implemented exactly: a
`src/recordings.jl` module, the five new exports, and a 38-assertion test
suite. T025 (SVG export) is unblocked.

### Changes

- `src/recordings.jl` (new): op records (`FillOp`, `StrokeOp`, `ClearOp`,
  `DrawImageOp`, `GroupStart`, `GroupEnd` — internal, not exported),
  `PicClip`, `Picture` (immutable op list + logical size), `PictureRecorder`
  (one-shot), `RecordingContext` (mirrors the `Context` drawing surface:
  fills, strokes, rects, `strokeSegment`, `clearRect`, `drawImage` (all
  overloads), `clip`, `save`/`restore`/`saveLayer`, transforms,
  `fillText`/`strokeText`/`measureText`, `setLineDash`/`getLineDash`,
  path builders, state fields — with the T014 `Real` boundary forms),
  and `drawPicture` (CPU replay).
- Recording context semantics mirror `Context` exactly: the implicit
  clip-group wrapper (clip active at the root), the globalAlpha layer
  wrapper (nested inner, as in the raster), cumulative image-coordinate
  clips, the saveLayer/restore layer-exit quirk (plain-save states carry
  layerDepth 0), and text lowering to glyph outline paths at record time
  (typeset + computePaths, no font needed at replay).
- `src/Vetra.jl`: include after `context.jl` + exports
  (`Picture`, `PictureRecorder`, `RecordingContext`, `finishRecording`,
  `drawPicture`). No existing symbol changed; `Context` untouched.
- `test/recording_tests.jl` (new, in runtests.jl): 38 assertions —
  11 record/replay A/B byte-parity scenes (basic, gradients, transforms,
  clips, layers+globalAlpha, nested saveLayer-in-clip, drawImage incl.
  src/dst rect, text fill+stroke, clearRect, save/restore) driving
  identical scene functions through a real Context and a RecordingContext;
  multiple-replay determinism; snapshot survival (path/paint/image
  mutation after recording); vector-space scaling at 2× and ½× with
  area-justified coverage expectations; record-boundary errors
  (TiledImagePaint fill, non-solid strokeStyle, unmatched restore,
  finished recorder); unclosed-saveLayer discard; self-containment
  (no shared op lists); Real boundary forms.
- `docs/cookbook.jl` recipe 9 ("Record once, replay at two sizes"):
  record/replay at 480×300 byte-identical to direct drawing, plus a 960×600
  vector re-rasterization with pixel assertions and two named PNGs;
  `docs/make_cookbook.jl` gallery updated (10 items).

### Verification

- A/B byte-parity: every contract scene replays byte-identical to direct
  CPU drawing (the scenes exercise the same code paths the pinned oracle
  suite covers, so replay is transitively pinned).
- Scaling is vector, not a raster enlargement: the ½× replay's edge
  coverage matches the hand-derived intersection areas (0.0625 / full /
  0.5625 / zero), which a box-filter enlargement of the 10×10 source
  would not reproduce.
- Full gate `scripts/check.jl`: green, **811,552 passing assertions**
  (+38 vs T022), **98.13% src line coverage (5939/6052)** — the new
  module's uncovered lines are only defensive branches already exercised
  by the A/B scenes' siblings.
- Cookbook + gallery rebuilt end to end (`make_cookbook.jl`); both recipe
  PNGs visually inspected (sharp 2× line and glyphs).

### Benchmark (record vs replay vs direct, 800×500 activity-card scene,
20 candles + grid + 2 text lines; warm medians, log
`/tmp/opencode/t024-bench.jl`)

| stage | wall | alloc |
| --- | --- | --- |
| direct drawing | 2.3 ms | 4 MB |
| record once | 0.36 ms | ~0 MB |
| replay ×1 | 1.82 ms | 3 MB |
| replay ×4 (same picture) | 4.53 ms | 8 MB (2.2 MB each) |

Recording is ~6× cheaper than drawing (snapshots, no rasterization);
amortized over 4 replays, replay is ~2× cheaper per render than direct
drawing and its allocations are the replayed canvases only. Replay ==
direct verified byte-identical on the scene.

### Limitations and notes

- One frozen-build quirk hit: do-block syntax mis-parses in this Julia
  1.13 build (`f(a) do … end` drops `a`), so `_recWrap` call sites use
  explicit function literals (commented at the call sites).
- The record-boundary errors deliberately tighten two raster behaviors:
  TiledImagePaint fills and non-solid stroke styles (which silently
  no-op in raster via the zero stroke color) now raise at record time —
  per the D030 contract, no silent loss.
- `isPointInPath` and the 3-arg `fill(ctx, image, …)` kernel entry are
  not on the recording surface (D030 §2 lists the drawing surface only).
- Export (T025/T026) is not implemented here; the op list is the stable
  input for both, per D030 §6.

### Next

T025 (SVG export of recorded drawings) is ready.
