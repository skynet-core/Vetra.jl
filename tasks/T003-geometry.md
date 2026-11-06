# T003 — Geometry and affine transforms

Status: ready (W1). Dependencies: T002.
Goal: port the geometry types and affine math the renderer needs, with
upstream vmath/bumpy semantics and hand-derived tests.

## Inputs and upstream references

- docs/API.md "Geometry" and D011 (Float32, 0-based continuous drawing
  coordinates, column-major `Mat3`, `A * B` applies B first, immutable value
  types).
- `.reference/pkgs/vmath/src/vmath.nim`: `GVec2` (storage/ops),
  `GMat3` (`[]`, `*` at ~1291, `*`(Mat3,Vec2) at ~1310, `determinant`,
  `inverse` at ~1467, `transpose`, `scale`/`translate`/`rotate` at ~1541-1590).
- `.reference/pkgs/bumpy/src/bumpy.nim`: `Rect`/`Circle`/`Segment`/`Line`/
  `Polygon` declarations (~1-40), `rect`, `xy`/`wh`, `*`, `/`, `+`, `or`, `and`,
  `circle`, `line`, `segment`.
- Vetra usage: `.reference/upstream/src/pixie/{paths,contexts,images}.nim` — port
  only the symbols those modules reference.

## Scope

Create `src/geometry.jl` (~150-250 lines), `include("geometry.jl")` from
`src/Vetra.jl` (after `import Base`, before colors), and export the public
types/functions.

- `Vec2` (Float32 x,y): `Vec2()` zero; `+ - * /` scalar ops with upstream
  operand rules; `dot`, `length`, `lengthSq`, `normalize` (`v / length(v)`;
  zero vector yields NaN, no guard — mirror upstream), `perpendicular`.
- `Rect` (Float32 x,y,w,h): constructors `rect(x,y,w,h)`, `rect(pos,size)`;
  `xy`/`wh`; `*`//`` by scalar; `+` (offsets, keeps size); `|` (`or`, union)
  and `&` (`and`, intersection) with exact upstream formulas (intersection may
  produce non-positive w/h — do not clamp); derived `left/top/right/bottom`.
- `Circle` (pos, radius), `Segment` (at, to), `Line` (a, b),
  `Polygon = Vector{Vec2}`; constructors `circle`, `segment`, `line`.
- `Mat3`: 9 Float32 values, column-major storage; `mat3()` = identity;
  `m[i, j]` with 1-based Julia indices addressing column i, row j;
  `translate(Vec2)`, `scale(Vec2)`, `rotate(angle)` matrix constructors
  (radians; exact upstream `cos`/`sin` layout); `m * v` affine point
  transform (`x' = m[1,1]x + m[2,1]y + m[3,1]`, `y' = m[1,2]x + m[2,2]y +
  m[3,2]`); `m * n` with upstream order (B applied first, verified at
  vmath.nim ~1291); `determinant`, `transpose`, `inverse` (no singular guard
  upstream: 1/det yields Inf/NaN — mirror, document in the docstring);
  `transform(m, v)` and `transform(m, rect)` helpers (rect: transform all four
  corners, return their bounding box).
- `snapToPixels(rect)` from `.reference/upstream/src/pixie/common.nim` lines
  92-101 (`x=floor(xMin)`, `w=ceil(xMax)-x`, same for y/h); test it
  exhaustively against `test/reference/snap_to_pixels.tsv` (135 rows; parse
  fields as `Float32`).
- Do not add path/stroke/paint APIs here.
- Julia gotcha: extend Base operators with explicit `import Base: +, -, /, *,
  length, ==, zero, one` (a bare `function +(...)` would shadow Base arithmetic
  inside this module on the project toolchain, as already done for `*` in
  `src/Vetra.jl`). Keep the existing T002 behavior untouched.

## Acceptance criteria

- `test/geometry_tests.jl` (new, included from `test/runtests.jl` after the
  T002 block) covers: identity/constructors; vector arithmetic and
  `normalize`/zero behavior; Rect union/intersection including touching and
  disjoint rects; `Mat3` element layout; translation/scale/rotation values
  from hand math (e.g. rotate(pi/2) maps (1,0) → (0,1)); composition order
  (`A*B*p == A*(B*p)`); inverse round-trip within 1e-5; singular inverse
  yields non-finite values (not an exception); rect transform bounds;
  `snapToPixels` matches all 135 `snap_to_pixels.tsv` rows exactly.
- No dependency on the code under test for expectations: expected matrices
  and points are hand-computed and written as literals in the tests.
- `julia --startup-file=no --project=. -e 'using Pkg; Pkg.test()'` passes
  (T002's 5 892 assertions must stay green).
- `julia --startup-file=no --project=. scripts/check.jl` passes with line
  coverage > 95% across `src/` (record the exact %).
- `docs/COMPATIBILITY.md` gains a "Geometry (T003)" row (the coordinator
  integrates shared docs; report the row text instead of editing it).

## Validation

Exact commands as above; Julia 1.13.3. No new dependencies, no `@fastmath`,
no unsafe indexing. Julia 1.10-compatible syntax. Do not edit shared docs
(TASKS.md, docs/HANDOFF.md, docs/DECISIONS.md, docs/COMPATIBILITY.md,
docs/API.md); do not commit.

## Results and handoff

Implementer: local `qwen3.8:27b` (delegated 2026-10-28); integrated and verified
by the coordinator (OpenCode session, DeepSeek V4.1).

Files: `src/geometry.jl` (new, included by `src/Vetra.jl` after
`import Base`), `test/geometry_tests.jl` (new, included from
`test/runtests.jl`); exports added to `src/Vetra.jl`.

Commands and outcomes (Julia 1.13.3):

```
julia --startup-file=no --project=. scripts/check.jl
Test Summary: | Pass  Total  Time
Package loads |    1      1  0.0s
T001 reference fixtures |   78     78  0.4s
T002 core (colors, image, compositing) | 5813   5813  0.5s
T003 geometry |  133    133  0.3s
     Testing Vetra tests passed
coverage gate: src/ line coverage = 100.0% (208/208 measurable lines)
scripts/check.jl: OK
```

Deviations / notes: `Mat3` stores vmath's own flat element order with a
`data::NTuple{9,Float32}` field; intersection is `&` (qualified
`Base.:&` definition; infix `&(...)` parses as address-of) and union is `|`.
The implementer's first run had 4 failing assertions, all test-evidence bugs
(determinant of `translate*scale` is 6; transpose rows were indexed row-major;
the fixture parser helper accepted only `String`, not `SubString`); fixed in
the test file, not by changing implementation or fixtures. No open blockers.
