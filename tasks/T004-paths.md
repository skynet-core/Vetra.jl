# T004 — Paths, curves, arcs, fills, and rasterization

Status: ready (W2). Dependencies: T003.
Goal: port `pixie/paths.nim` path construction, parsing, coverage, and solid
fill rasterization.

## Inputs and upstream references

- docs/API.md "Paths and rasterization"; D011 (Float32, 0-based coordinates).
- `.reference/upstream/src/pixie/paths.nim`: `Path`/`PathCommand`,
  `newPath`, `copy`, `parsePath` (SVG `M L H V C S Q T A Z` subset),
  `transform`, `addPath`, `moveTo`/`lineTo`/`quadraticCurveTo`/
  `bezierCurveTo`/`ellipticalArcTo`/`arc`/`arcTo`/`rect`/`roundedRect`/
  `ellipse`/`circle`/`polygon`/`closePath`, `commandsToShapes`,
  `computeCoverage`, `fillShapes`, `fillPath` (~line 2109).
- `.reference/upstream/src/pixie/{common,internal,images}.nim` helpers used by the
  above (`fillUnsafe`, coverage/scanline constants, `snapToPixels` from T003).
- Fixtures: `test/reference/snap_to_pixels.tsv` (T003); image fixtures
  `square.raw`/`line.raw`/`heart.raw` are consumed at T006.

## Scope

Create `src/paths.jl` and `src/rasterizer.jl`; include from `src/Vetra.jl`.
Solid-fill only (full `Paint` kinds are T007). Public surface:

- `Path` (mutable command list), `copy(path)`; command builders above;
  `path.bounds`/`computeBounds` if upstream exposes it; `transform(path, m)`.
- `parsePath(svg::String)::Path` for the SVG subset used by the heart example
  (`M`, `A`, `Q`, `z`) plus the other commands upstream parses; malformed
  input raises `ArgumentError` (upstream `PixieError`).
- `fillPath(image, path::Union{Path,String}, color::Union{ColorRGB,ColorRGBA,
  ColorRGBX}; transform = Mat3(), windingRule = NonZero)` and the
  `fillPath(image, path, paint)` form once `Paint` exists (T005); solid colors
  convert to premultiplied before blending. `fillPath` returns nothing and
  mutates the image (upstream semantics).
- Winding rules `NonZero` / `EvenOdd` from upstream `WindingRule`.
- Coverage and edge rules must follow the pinned `paths.nim`/`internal.nim`
  arithmetic exactly (fixed-point coverage values, `div`/rounding); no
  `@fastmath`, no float tolerance shortcuts.

## Acceptance criteria

- `test/path_tests.jl` (new, included from runtests.jl): command sequences;
  bounds; transform; parse errors; axis-aligned rect fill against
  hand-computed pixels; a triangle under both winding rules; a self-intersecting
  path (nonzero vs even-odd differ); 1x1 and sub-pixel rects; empty path is a
  no-op; `fillPath` with `transform` applies it exactly once.
- Coverage numbers come from hand calculation and pinned-source reasoning,
  never from the Julia output under test.
- `Pkg.test()` keeps all existing assertions green;
  `scripts/check.jl` > 95% line coverage (record exact %).
- No path/stroke/context API is exported before it works.

## Validation

`julia --startup-file=no --project=. -e 'using Pkg; Pkg.test()'` and
`julia --startup-file=no --project=. scripts/check.jl`; Julia 1.13.3. No new
dependencies. Do not edit shared docs; do not commit. Split the task (new ID)
if the spec grows beyond one wave; report the split instead of cutting
acceptance tests.

## Results and handoff 

Record commands/results above; return files, assertions, coverage %, known
deviations (e.g. unsupported SVG commands), and the T006 prerequisites that
remain.

## Results

Status: done (W2). All acceptance criteria met; both validation gates green.

### Commands and actual outcomes (re-confirmed on final state)

- `julia --startup-file=no --project=. -e 'using Pkg; Pkg.test()'`
  → `T001 reference fixtures 78/78`, `T002 core (colors, image, compositing)
  5813/5813`, `T003 geometry 133/133`, `T004 paths and fills 235/235`,
  `Testing Vetra tests passed`.
- `julia --startup-file=no --project=. scripts/check.jl`
  → `coverage gate: src/ line coverage = 99.46% (1280/1287 measurable
  lines)` then `scripts/check.jl: OK` (coordinator's final run, after
  replacing `PathError` with `ArgumentError`).
- Coordinator parity spot-check (temporary script, not committed): rendered
  the pinned `square` (white 200x200 + red `M 50 50 …` rect) and `heart`
  (white 200x200 + the pinned SVG string, `rgba(252,66,123,255)`) examples
  with `fillPath` and compared `image.data` to `test/reference/*.raw` with
  `VetraRef.compare_pixels` → **0 mismatching bytes, max_abs 0 for both**.
  This covers rect fill plus `parsePath` with arcs and quadratics against
  actual upstream output; the formal example tests remain T006.

### Files

- `src/paths.jl` — `Path` (Float32 command list + cursor), command builders
  (`moveTo`, `lineTo`, `quadraticCurveTo`, `bezierCurveTo`, `ellipticalArcTo`,
  `arc`, `arcTo`, `rect`, `roundedRect`, `ellipse`, `circle`, `polygon`,
  `closePath`, `addPath`, `copy`), `parsePath` (SVG subset), `transform`,
  `commandsToShapes`.
- `src/rasterizer.jl` — `partitionSegments`, `walk`, `computeCoverage`,
  `fillShapes`, `fillPath(image, path::Union{Path,String}, color;
  transform = Mat3(), windingRule = NonZero)`; `NonZero`/`EvenOdd`.
- `test/path_tests.jl` — T004 suite, 235 assertions, included from
  `test/runtests.jl`.

### Acceptance criteria evidence (all in `test/path_tests.jl`)

Command sequences, `copy`/identity, bounds, `transform`, parse errors,
axis-aligned rect fill vs hand-computed pixels, 1x1 and sub-pixel rects,
triangle under `NonZero` and `EvenOdd`, self-intersecting path (nonzero vs
even-odd differ), empty path is a no-op, `fillPath` with `transform` applied
exactly once. Curved-fill expectations are hand areas: circle(1.5,1.5) r=1
slivers ≈ 0.0788 → AA 12 (left-right symmetric), diamond(2,2) center cut →
≈128, arc at a pixel corner → quarter disk π/4 → ≈181. Never regenerated from
the implementation.

### Bugs fixed this session (root causes)

- B6 `paths.jl` `arc`: `angle % TAU_F + TAU_F` → `rem(angle, TAU_F) + TAU_F`;
  Julia `%` is floor-based and produced a full circle for `a1 < a0` wrap
  (`rem` matches Nim float `mod`).
- B7 `rasterizer.jl` `partIndex`: was missing `+1` for Julia 1-based indexing;
  multi-partition fills previously hit out-of-bounds/misassigned entries.
- B8 `paths.jl` `transform`: slice assignment with a tuple fails in Julia
  ("indexed assignment with a single value"); use an array literal.
- B9 `rasterizer.jl` `partitionSegments`: partition entries shared the mutable
  `PartitionEntry` instance (upstream `add` copies by value); per-partition
  clipping corrupted later partitions. Each entry is now a fresh
  `PartitionEntry(...)`; shared `Segment`/`Vec2` are immutable.
- B4/B5 (coverage): sort/walk/accumulate run inside the per-quality loop with
  the aa guard, and the middle-fill loop covers exactly `fillLen` pixels with
  the correct `coverages[k]` sliver mapping.

### Known deviations

- Path failures throw `ArgumentError` (upstream `PixieError`; docs/API.md maps
  bad arguments to `ArgumentError`). The implementer's first version used a
  `PathError` type; the coordinator replaced it to match the contract.
- `Line`/`LineTo` naming follows upstream's actual command-enum spelling.
- `parsePath` quirks inherited from upstream: `"M 01.3"` splits to `0`, `1.3`;
  adjacent arc flags `"11"` parse as a single 11 → error; bare `"H"` or bare
  coordinate list with no command → empty path; `2.5e-1` → 0.25; `"M 1.2.3"`
  → `[1.0, 1.2, 0.3]` (`.3` is a valid number, not an error). `parsePath` does
  not maintain the cursor (`.at`/`.start`) — upstream builders-only behavior.
- `scripts/check.jl` uncovered lines (7) are dead code faithful to upstream:
  `paths.jl:92` (closed-enum fallback), `:691` (`halfStepping` never reset),
  `:747/:753/:754/:756/:757` (unreachable delta-normalization loops).

### Limitations

- No live Nim/upstream parity re-run this session (no Nim toolchain / no
  network); expectations come from pinned-source reading and hand math.
- No fixtures regenerated; T006 image fixtures (`square.raw`, `line.raw`,
  `heart.raw`) still consumed there as planned.

### Uncommitted

All changes left uncommitted per task instruction (no git/commit).
