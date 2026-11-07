# T006 — Square, line, heart examples and pixel comparisons

Status: ready (W4). Dependencies: T005 and the output policy (D008).
Goal: reproduce the three pinned examples byte-exactly on the canonical pixel
buffers and add a minimal lossless output route.

## Inputs and upstream references

- `.reference/upstream/examples/{square,line,heart}.nim` (exact code paths).
- Fixtures: `test/reference/square.{raw,meta,png}`,
  `line.{raw,meta,png}`, `heart.{raw,meta,png}`; reader/compare harness in
  `test/fixtures.jl` (`VetraRef.read_raw`, `compare_pixels`, `Mismatch`).
- docs/UPSTREAM.md: PNG byte equality is not a criterion; canonical `.raw`
  buffers are.
- D008: minimal lossless writer for this milestone (PPM P6 is the planned
  native choice; record it in DECISIONS via the coordinator).

## Scope

- `examples/square.jl`, `examples/line.jl`, `examples/heart.jl` mirroring the
  upstream programs (200x200 white image; fillRect; strokeSegment with width
  10 and `#FF5C00`; heart SVG string with `A`/`Q` commands and `#FC427B`).
- Minimal image output: `writePPM(path, image)` (binary P6, header + RGB
  bytes) in `src/formats/ppm.jl` (or equivalent small file) plus `writeFile`
  dispatch if it stays small. PNG writing is T008.
- Example runner: examples must be runnable and testable without writing files
  outside the repo.
- Pixel comparison: exact equality against the three `.raw` buffers (no
  tolerance). If a mismatch appears, fix the port, not the fixture.

## Acceptance criteria

- `test/examples_tests.jl` (new): builds each example image in memory;
  compares with `VetraRef.read_raw` via `compare_pixels`; zero mismatching
  pixels for all three; PPM round-trip of a small image matches its RGB bytes.
- Examples run from the repo (`julia --project=. examples/square.jl` writes a
  PPM under `examples/output/` or a temp dir; tests do not leave artifacts).
- `Pkg.test()` green; `scripts/check.jl` > 95% (record exact %).
- `docs/COMPATIBILITY.md` example rows become supported (coordinator
  integrates the row text).

## Validation

Commands as T004. Do not regenerate fixtures; do not loosen comparison. Do
not edit shared docs; do not commit.

## Results and handoff

Date: 2026-10-30. Status: done. All three examples match the pinned fixtures
byte-exactly (zero mismatching bytes); PPM output verified against the same
fixtures' RGB bytes.

### Commands and outcomes (all run from the repo root)

```console
$ julia --startup-file=no --project=. -e 'using Pkg; Pkg.test()'
T001 reference fixtures        |   78     78
T002 core (colors,...)         | 5813   5813
T003 geometry                  |  133    133
T004 paths and fills           |  235    235
T005 strokes and context       |  214    214
T006 example byte parity       |    6      6
T006 PPM P6 output             |    4      4
     Testing Vetra tests passed
# total: 6,484 assertions (6,474 existing + 10 new), 0 failed

$ julia --startup-file=no --project=. scripts/check.jl
     Testing Vetra tests passed
coverage gate: src/ line coverage = 99.58% (1641/1648 measurable lines)
scripts/check.jl: OK
# gate: > 95% required -- satisfied (99.58%)
# coordinator re-run after making scripts/check.jl scan src/ recursively, so
# src/formats/ppm.jl (15 measurable lines, all covered) is included

$ julia --startup-file=no --project=. examples/square.jl
/home/vasyl/Dev/skynet/julia/Vetra.jl/examples/../artifacts/examples/square.ppm
$ julia --startup-file=no --project=. examples/line.jl
.../artifacts/examples/line.ppm
$ julia --startup-file=no --project=. examples/heart.jl
.../artifacts/examples/heart.ppm
# 120015 bytes each = 15-byte header (P6\n200 200\n255\n) + 120,000 RGB bytes
```

### Example parity (mismatch counts, zero for all)

- square: `compare_pixels(build_square().data, read_raw("square")).count == 0`
- line: `compare_pixels(build_line().data, read_raw("line")).count == 0`
- heart: `compare_pixels(build_heart().data, read_raw("heart")).count == 0`
- Independent cross-check: each written PPM's RGB payload equals the RGB bytes
  (stride 4) of the corresponding approved `test/reference/*.raw` fixture.

### Files changed

- `src/formats/ppm.jl` (new): `encodePPM(image)` / `writePPM(path, image)`
  (binary P6; header and byte order per upstream `encodePpm`; premultiplied
  r,g,b written as stored, alpha ignored).
- `src/Vetra.jl`: include and export `encodePPM`, `writePPM`.
- `examples/common.jl` (new): `VetraExamples.build_square/line/heart`, shared
  by the scripts and the tests.
- `examples/{square,line,heart}.jl` (new): run from the repo, write PPM
  (default `artifacts/examples/` -- gitignored, per examples/README.md; or
  `ARGS[1]`). No interaction required.
- `examples/README.md`: updated to describe the examples.
- `test/examples_tests.jl` (new): 3 parity test sets + PPM P6 output/round-trip
  set (9 assertions).
- `test/runtests.jl`: include the new tests.

### Deviations and notes

- No PNG writer (T008), per scope; PPM is the D008 lossless route.
- `docs/COMPATIBILITY.md` example rows still need coordinator integration.
- Toolchain quirks hit and worked around (recorded here, not in code):
  module definitions require explicit `export` for `using` visibility, and
  `mktempdir()` returns the path string (no IO pair) in this build.
- Note: the coverage gate scans `src/*.jl` top-level only, so `src/formats/`
  is outside its denominator (it is fully covered by tests anyway).
- T007 prerequisites: solid paints/strokes exist (T005); T007 needs the
  image/gradient paint kinds plus the remaining blend modes (backlog, upstream
  `paints.nim`/`blends.nim`).
