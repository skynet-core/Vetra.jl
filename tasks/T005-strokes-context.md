# T005 — Strokes, caps, joins, dashes, and minimal context

Status: ready (W3). Dependencies: T004.
Goal: stroke geometry plus the minimal `Context` needed by the square and line
examples, including a solid-only `Paint` and hex color parsing.

## Inputs and upstream references

- docs/API.md "Context / drawing" and D011.
- `.reference/upstream/src/pixie/paths.nim`: `strokePath` (~2160),
  `strokeSegment`, stroke expansion helpers.
- `.reference/upstream/src/pixie/contexts.nim`: `Context` state (lines 17-66),
  `newContext` (53-80), `save`/`restore` (88-110), path commands (261-365),
  `fill`/`stroke`/`clip` (365-425), transforms (525-560),
  `strokeSegment` (709-720), `fillRect`/`strokeRect`/`clearRect` (425-465).
- `.reference/upstream/src/pixie/paints.nim`: minimal solid paint
  (`newPaint`, `parseSomePaint` color/string conversions).
- chroma `.reference/pkgs/chroma/src/chroma/`: `parseHtmlColor` (straight
  `ColorRGBA` in this port; there is no separate float `Color` type).
- Fixtures: image fixtures `square.raw`, `line.raw` are compared at T006.

## Scope

Create `src/strokes.jl`, `src/context.jl`, `src/paints.jl` (minimal).
Public surface:

- `Paint` with a solid color, `opacity` (Float32, default 1), and
  `blend_mode` (`NormalBlend` only until T007); constructors/converters:
  `Paint(color)`, `convert(Paint, ColorRGB|ColorRGBA|ColorRGBX|String)`, so
  `ctx.fillStyle = "#FF5C00"` works like upstream's converter.
- `Context(image)` (and `Context(width, height)`); fields `fillStyle`,
  `strokeStyle`, `lineWidth` (default 1), `miterLimit` (default 10),
  `lineCap` (`ButtCap`/`RoundCap`/`SquareCap`), `lineJoin`
  (`MiterJoin`/`RoundJoin`/`BevelJoin`), `transform::Mat3`.
- `save`/`restore` (unbalanced `restore` → `ArgumentError`), `translate`,
  `scale`, `rotate`, `transform` (post-multiply, upstream order),
  `beginPath`, the path command wrappers, `fill`, `stroke`, `clip`,
  `fillRect`, `strokeRect`, `strokeSegment`, `clearRect`.
- Stroke caps/joins/miter limit and dash support follow `paths.nim`
  (`lineDash` may land in T010 if the examples do not need it; say so).
- No image/gradient paints, no blend modes beyond `NormalBlend`, no text.

## Acceptance criteria

- `test/context_tests.jl` (new): square fill via `fillRect`; diagonal stroke
  via `strokeSegment` with `lineWidth = 10`; caps/joins at corners for all
  enum values; miter-limit fallback; save/restore restores paint + transform;
  unbalanced restore raises; transform order (`translate` then `scale` vs the
  reverse differ as expected); `fillStyle = "#FF5C00"` parses to the same
  straight color as `parseHtmlColor`.
- Expected pixels come from hand calculation / geometric reasoning, not from
  the implementation under test.
- `Pkg.test()` green; `scripts/check.jl` > 95% (record exact %).
- `square` and `line` example flows are runnable (pixel parity lands in T006).

## Validation

Commands as T004; Julia 1.13.3; no new dependencies; no `@fastmath`. Do not
edit shared docs; do not commit. Split if beyond one wave.

## Results and handoff

Status: done (2026-10-30, one wave). `Pkg.test()` fully green; `scripts/check.jl` gate passes.

### Commands and outcomes

- `julia --startup-file=no --project=. -e 'using Pkg; Pkg.test()'` → exit 0,
  "Testing Vetra tests passed": Package loads 1/1; T001 fixtures 78/78; T002 core
  5813/5813; T003 geometry 133/133; T004 paths and fills 235/235 (all 6,260
  pre-existing assertions still green); T005 strokes and context 214/214.
- `julia --startup-file=no --project=. scripts/check.jl` → "scripts/check.jl: OK";
  gate line: `coverage gate: src/ line coverage = 99.57% (1626/1633 measurable lines)`
  (required: > 95%).

### Files

- New: `src/paints.jl` (127 lines), `src/strokes.jl` (292), `src/context.jl` (378),
  `test/context_tests.jl` (739).
- Modified: `src/Vetra.jl` (+3 includes L308-310 in declaration order, +7 export
  lines L298-304), `test/runtests.jl` (+1 include).
- 1,547 lines added in total; no edits to TASKS.md, docs/, Project.toml, or
  test/reference/**; nothing committed.

### Assertions (T005: 214)

`test/context_tests.jl`, eleven test sets: Paint/`parseHtmlColor`/convert solid
forms (28); `fillPath` Paint form incl. opacity clamp and Overwrite clears (18);
`strokeShapes` polygon structure for caps/joins/miter-fallback/area guards/dashes
(29); miter/angle helpers, `fixAngle`, line intersection (13); `strokePath` pixel
checks on white bg incl. all caps, elbow joins, string/transformed/dashed strokes,
zero-opacity/zero-alpha semantics (44); Context default state and styles (26);
transform order A vs B (7); path wrappers (4); fill/stroke/fillRect/strokeRect/
clearRect wrappers (18); save/restore incl. two-deep, Paint isolation, unbalanced
restore (19); square and line flows byte-parity vs `test/reference/{square,line}.raw`
(2). Expectations are hand-derived region intervals over the established
`px(img, x, y)` = region cell `[x-1, x] x [y-1, y]` convention: full-white tuples
on filled backgrounds, alpha-0 on transparent ones, and `0 < green < 255` for
strictly partial coverage — never read back from the implementation.

### Acceptance mapping

- Square fill via `fillRect` and diagonal `strokeSegment` `lineWidth = 10` —
  both flows run in the parity test set; image data matches `square.raw` and
  `line.raw` byte-for-byte (0 mismatches via `VetraRef.compare_pixels`).
- Caps/joins for all enum values: `strokeShapes` polygon assertions plus cell
  pixel checks distinguishing Butt/Round/Square and Miter/Bevel/Round.
- Miter-limit fallback: 90-degree corner stays miter at limit 10 and falls back
  to bevel at limit 1 (`|turn| < 2*asin(1/miterLimit)`), area-guard drops covered
  too.
- save/restore restores paint + transform (two-deep unwind verified); unbalanced
  restore raises `ArgumentError`; translate-then-scale vs reverse give (3,4) vs
  (4,6) and distinct matrices.
- `fillStyle = "#FF5C00"` parses to the same straight color as `parseHtmlColor`;
  `#AbC` tiny form matches chroma `d/15*255`.

### Deviations (upstream)

1. `clip` is deferred to T010: it needs `MaskBlend` plus live mask/layer images,
   which the T004 rasterizer rejects; AGENTS.md forbids a no-op placeholder.
2. Unbalanced `restore` raises `ArgumentError` (upstream no-ops) — required by
   this task's scope.
3. Hex strings are the `#RGB`/`#RRGGBB` subset of chroma `parseHtmlColor`;
   named colors and `rgb()`/`rgba()` strings raise `ArgumentError` (unported).
4. `fillStyle`/`strokeStyle` store the value as-is and convert at draw time
   (upstream converts at assignment), so an invalid string raises on
   `fill`/`stroke`, not at assignment.
5. Context omits deferred state: no `globalAlpha`/`font`/`lineDash`/`mask`/
   `layer` (T009/T010); the transform field is named `mat` (upstream) with
   `getTransform`/`setTransform`/`resetTransform` accessors.
6. `Paint` field is `blendMode` (upstream name), not the task file's
   `blend_mode`; `defaultMiterLimit = 4` (upstream `strokePath` default)
   while `Context` defaults to `miterLimit = 10` (upstream `newContext`).

### lineDash status

Dash geometry is implemented per `paths.nim`: `strokeShapes`/`strokePath`
`dashes` — the list is copied, duplicated once when odd, any value <= 0 raises
`ArgumentError("Invalid line dash value")`, 0-based even indices draw, and the
loop restarts while distance remains. The `Context.lineDash` state field is
deferred to T010 (docs/API.md already marks it T010); this equals upstream's
empty default, which the square and line examples never use.

### What T006 still needs

- The examples' driver path: read `square.nim`/`line.nim`, render through the
  ported flows (already verified here at the image-data level) and write PPM
  output — `writePPM`/`readPPM` are unported — then byte-compare against
  upstream output.
- Remaining fixture parity (e.g. `heart`), and any examples using deferred
  state (font/text in T009, clip in T010).
