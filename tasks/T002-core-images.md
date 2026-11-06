# T002 — Colors, image storage, basic compositing

Status: see TASKS.md. Depends on T001.

## Goal

Implement the smallest native Julia core with evidence-backed arithmetic and no
path rasterizer, image codec, fonts, or optimization backend.

## Work

- Read the numerical contract and relevant pinned common/images/blends sources.
- Choose concrete color/image types, pixel storage, coordinate mapping, and
  mutating vs allocating APIs. Record decisions before depending on them.
- Implement construction, dimensions, checked access, copy, fill, straight and
  premultiplied conversion, and the source-over behavior required for M1.
- Test alpha 0, 1, 254, 255; valid premultiplied bounds; representative channels;
  conversion boundaries; clipping/bounds; bad dimensions; aliasing/copy behavior;
  and overflow-safe size calculations.
- Use independently justified expectations and T001 fixtures. Exhaustively test
  small channel arithmetic domains where practical.
- Export only implemented APIs, update the compatibility table, and document use.

## Acceptance criteria

- Focused unit tests and scripts/check.jl pass.
- Arithmetic matches the selected upstream backend and documented rounding.
- Image storage invariants and index conventions are documented and tested.
- Unsupported operations are absent from the public API.
- No new external dependency is introduced without a task-relevant decision.
- Handoff lists implemented APIs, verification, and remaining limitations.

## Results (2026-10-28)

Status: **done.** Implemented in `src/Vetra.jl` (single file, ~180 lines of code):
`ColorRGB`/`ColorRGBA`/`ColorRGBX` (+`rgb`/`rgba`/`rgbx` ctor family with
0..255 validation), `Image` + `newImage`/`width`/`height`/`copy`/`inside`/
`getColor`/`setColor`/`fill`, both alpha-conversion paths
(`toStraightAlpha`, `toPremultipliedAlpha`), and compositing
(`mix`, `*` opacity, `*` coverage, `blendAlpha`, `blendNormal`). Storage is
premultiplied RGBA, row-major, 4 bytes/px, 1-based coordinates; `fill` accepts
all three color types and converts straight→premul at the boundary.

Decisions recorded as D010 (types, 1-based indexing, storage, both conversion
paths, `roundHalfAway` tie direction, `blendNormal` mod-256 wrap).

Verification actually run in this environment (Julia 1.13.3, no network):

- `julia --startup-file=no --project=. -e 'using Pkg; Pkg.test()'` →
  "Testing Vetra tests passed". Summary: `Package loads` 1, `T001 reference
  fixtures` 78, `T002 core (colors, image, compositing)` **5813 — all pass**
  (5 892 total assertions; exhaustive sweeps: 65 536 premul + 32 896 valid
  straight rows ×2 paths, 768 mix samples, 2 816 opacity, 2 048 coverage,
  65 536 blendAlpha, 121 blendNormal cells incl. 8 wrap cells, plus
  image invariants).
- `julia --startup-file=no --project=. scripts/check.jl` → tests passed plus
  `coverage gate: src/ line coverage = 100.0% (89/89 measurable lines)`,
  `scripts/check.jl: OK` — satisfies the D009 `> 95%` gate.

Known deviations (documented in D010 / NUMERICAL_CONTRACT / COMPATIBILITY):
- `ArgumentError`/`BoundsError` on invalid inputs where upstream doc-comments
  describe no-ops (safer; not a numerics change).
- `blendNormal` channel sums wrap mod 256 on invalid-premul input, mirroring
  upstream `uint8` addition (upstream fixtures confirm this: e.g. white over
  (255,255,255,254) → (0,0,0,255)); never fires on valid premultiplied input.
- This Julia build's `round` ties to even; port uses `roundHalfAway`
  (ties away from zero) to match upstream, per D010.

Remaining (explicitly out of scope here): paths/rasterization (T003+),
codecs, fonts, SIMD — none in the public API. No new external dependency
added.
