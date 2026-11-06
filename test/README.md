# Test strategy

The suite runs via `test/runtests.jl` (explicit includes per feature, so
each file runs in the default `Pkg.test()`), and the gate is
`julia --startup-file=no --project=. scripts/check.jl` (all tests + the
>95% `src/` coverage gate per D009). Current totals: ~811k assertions
(see docs/HANDOFF.md for the per-suite breakdown).

## Layers

1. **Core behavior** — pixel arithmetic, geometry, paths/fills, strokes,
   context state, paints/blends, image ops/effects (test/*_tests.jl per
   task; expectations hand-derived from the pinned upstream formulas).
2. **Reference parity** — byte-exact comparisons against fixtures under
   `test/reference/`, generated independently by the pinned upstream
   oracle (`tools/oracle/build.sh`; provenance in each `.meta`).
3. **Examples** — the pinned upstream examples reproduce their `.raw`
   fixtures with 0 mismatching bytes (test/examples_tests.jl).

## Reference data contract

- Canonical pixels: row-major RGBA, UInt8 channels, premultiplied alpha,
  rows top-to-bottom, width × height × 4 bytes.
- `.raw` = canonical buffer; `.png` = cross-check render; `.meta` =
  dimensions, layout, alpha convention, upstream repo/revision,
  dependency pins, toolchain, build flags, generator; `sha256_raw=` in
  the meta and `*.sha256` sidecars pin the checksums (fixtures.jl
  verifies them on load).
- Default: exact channel equality. Tolerance needs a case-specific
  reason and recorded decision (the only one in use: JPEG decode vs
  upstream stb fixtures, max channel delta 8, D014).
- `VetraRef.compare_pixels` reports the first differing
  coordinate/channel, mismatch count and max absolute error.

## Fixture rules

- Keep actual outputs and diffs in ignored `artifacts/`; reviewed
  expectations belong in `test/reference/`. Never overwrite an expected
  result during a test.
- Generate fixtures with the oracle (`sh tools/oracle/build.sh <mode>`),
  review the output, then copy the finished `.raw`/`.png`/`.meta`
  (plus checksum sidecars) into `test/reference/`.
- Tests must not require a live network or a local Nim install; the
  oracle runs are recorded here so fixtures stay reproducible.
