# Task board

Status values: `ready`, `blocked`, `in_progress`, `done`.
A future task is blocked until its listed prerequisites and design decisions are
resolved. Mark readiness explicitly when completing its prerequisites.

| ID | Task | Wave | Depends on | Status |
| --- | --- | --- | --- | --- |
| T000 | Create empty project and agent workflow | — | — | done (structural checks only) |
| T001 | [Reference baseline and numerical contract](tasks/T001-reference-baseline.md) | — | T000 | done |
| T002 | [Colors, image storage, and basic compositing](tasks/T002-core-images.md) | — | T001 | done |
| T003 | [Geometry and affine transforms](tasks/T003-geometry.md) | W1 | T002 | done |
| T004 | [Paths, curves, arcs, fills, and rasterization](tasks/T004-paths.md) | W2 | T003 | done |
| T005 | [Strokes, caps, joins, dashes, and minimal context](tasks/T005-strokes-context.md) | W3 | T004 | done |
| T006 | [Square, line, heart examples and pixel comparisons](tasks/T006-examples.md) | W4 | T005; output policy (D008) | done |
| T007a | [Blend modes, paint kinds, image drawing](tasks/T007a-paints-blends.md) | W5 | T006 | done |
| T007b | [Masks, clipping, context layers, image effects](tasks/T007b-masks-effects.md) | W5 | T007a | done |
| T008 | [Image formats and SVG](tasks/T008-formats-svg.md) | W6 | T007b; codec policy (D008) | done (D014) |
| T009 | [Font parsing and text layout](tasks/T009-fonts-text.md) | W6 | T007b; font policy (D008) | done (D015) |
| T010 | [Full drawing context integration](tasks/T010-context-integration.md) | W7 | T008, T009 | done |
| T011 | [Benchmarks, optimization, documentation, release audit](tasks/T011-release.md) | W8 | T010 | done |

User directive (2026-10-27): the port must be completable as a full feature
set, must keep rendering backends swappable (CPU now; Vulkan/OpenGL later)
and prefer well-supported Julia packages, and must test everything with code
coverage strictly above 95%. Recorded as D007–D009; they bind all tasks.

Every task now has a focused specification in tasks/ (written 2026-10-28 when
D011/D012 unblocked the board). Readiness means "specified and its decisions
resolved"; execution order is the Wave column, and shared files have one
integrator. Split a task into a new ID if its spec grows beyond one wave.

## Active ownership

- Coordinator/integrator: OpenCode session (Qwen3.8) of 2026-11-04
  (previous: DeepSeek V4.1 session of 2026-10-28).
- Implementer for all coding work: local `qwen3.8:27b` via the OpenCode
  subagent tool (user directive 2026-10-28). The coordinator writes/reviews
  specs, shared docs, and integration; the implementer owns `src/` and
  `test/` for its task.
- Task: T007b complete and integrated (masks/clip/layers on 2026-10-30,
  image effects 2026-11-04); T008 (formats/SVG) complete and integrated on
  2026-11-05 (D014); T009 (fonts/text) complete and integrated on
  2026-11-06 (D015); T010 (context integration: isPointInPath, dash
  wiring in strokes, cross-feature composition tests) complete and
  integrated on 2026-11-06; T011 (benchmarks/docs/release audit) complete
  on 2026-11-06. **The board is done** — all tasks T000–T011 are `done`.
- Working tree: main checkout of /home/vasyl/Dev/skynet/julia/Vetra.jl
  (single commit on `main`, pushed to git@github.com:skynet-core/Vetra.jl;
  history re-initialized at the package rename, D017).
- Shared-file ownership: the implementer does not edit TASKS.md,
  docs/HANDOFF.md, docs/DECISIONS.md, docs/COMPATIBILITY.md, or
  docs/API.md; it returns a summary and the coordinator integrates.
- Clear this claim when handing off.

## Completion evidence

- Post-board local test fix (2026-11-06, D019): codec discovery moved from
  precompile-time code into runtime initialization. A subprocess regression
  reproduces core-only cache reuse in a codec-enabled environment. The user's
  exact `Pkg.test()` command and `scripts/check.jl` pass on Julia 1.13.3;
  coverage is 98.0% (5235/5342). Next: review/commit when requested.

- Post-board tutorial (2026-11-06): [docs/TUTORIAL.md](docs/TUTORIAL.md)
  builds an activity card, then covers image processing, compositing, SVG,
  text layout, testing, and benchmarking. Linked from README and examples.
  All 13 drawing blocks executed together with 18 assertions on Julia 1.13.3;
  the documented benchmark command completed all eight workloads and the
  full gate passed at 98.0% coverage. Next: user review of the tutorial;
  no implementation task opened.

- T000: package scaffold, agent documents, VS Code tasks, CI definition, upstream
  pin, and license notices created. Static validation only; no Julia runtime was
  available. T001 includes the first local Julia verification.
- T001: fixtures, contract, oracle, gate, and 79 passing assertions — see
  tasks/T001-reference-baseline.md "Results" and docs/HANDOFF.md (all commands
  and outcomes recorded 2026-10-28).
- T002: full public core in src/Vetra.jl; 5 892 test assertions pass
  (exhaustive fixture sweeps, incl. 8 blendNormal wrap cells); `scripts/check.jl`
  green with `src/` coverage 100.0% (89/89 measurable lines) on 2026-10-28 —
  see tasks/T002-core-images.md "Results".
- T007a: full `BlendMode` enum (0..19), 16 W3C blends + Overwrite, every
  `Paint` kind and `fillGradient`, non-solid `fillPath`, `draw`/`drawTiled`,
  and `Context.drawImage`; 6 843 assertions pass (359 new), `scripts/check.jl`
  green with `src/` coverage 98.54% (2230/2263) on 2026-10-30. All 20
  `blend_*.tsv` tables (2 420 rows) and both draw fixtures match exactly —
  see tasks/T007a-paints-blends.md "Results". Mask blends, clip/layers,
  globalAlpha, and image effects landed in T007b (below).
- T007b: mask blends dispatched, `Context.clip`/`saveLayer`/`restore` and
  `globalAlpha` ported, and every pinned image effect
  (`gaussianKernel`, `flipHorizontal`/`flipVertical`, `rotate90`, `diff`,
  `invert`, `ceil`, `blur`, `resize`, `spread`, `shadow`, `superImage`,
  `opaqueBounds`); 7 358 assertions pass (404 new image-effects),
  `scripts/check.jl` green with `src/` coverage 97.42% (2567/2635) on
  2026-11-04 — see tasks/T007b-masks-effects.md "Results".
- T008: every image format except WebP (PNG via `PNGFiles`, JPEG via
  `JpegTurbo` decode-only, native BMP/QOI/GIF/PPM/base64, SVG pinned
  subset), magic-byte `readImage`/`writeFile` dispatch, per-format examples
  (`examples/{png,jpeg,bmp,qoi,svg,gif,ppm}.jl`) and the API tour
  (`examples/showcase.jl`); all Pinned-fixture pixel comparisons exact
  (JPEG within the recorded 8-per-channel tolerance), `scripts/check.jl`
  green with `src/` coverage 98.72% (4158/4212) on 2026-11-05 — see
  tasks/T008-formats-svg.md "Results" and docs/DECISIONS.md D014.
