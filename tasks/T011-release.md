# T011 — Benchmarks, optimization, documentation, release audit

Status: done (2026-11-06). Dependencies: T010.
Goal: measure, optimize only what the measurements justify, finish user docs,
and complete the release/licensing audit.

## Inputs and upstream references

- docs/ROADMAP.md M4; AGENTS.md performance rules (scalar parity first, no
  `@fastmath`/SIMD/threads without a recorded benchmark).
- Pinned upstream toolchain and examples; benchmark workload must be the same
  for the Julia and Nim reference runs (record commands and versions).
- `benchmark/` directory and any existing benchmark harness.
- D007 backend strategy, D008 dependencies, D009 coverage gate, D011 API.

## Scope

- Benchmark harness: warm-up, steady-state, allocations, first-call latency
  separated; cover fill, stroke, blur/shadow, draw, PNG encode/decode,
  text metrics.
- Run the pinned Nim reference on the same workload; record environment and
  revision. Only optimize measured bottlenecks, with regression tests kept.
- Documentation: README quick start + API examples, supported/unsupported
  matrix, limitations, license/NOTICE audit, CI (test + coverage + Julia 1.10
  and current stable), package name/registration/versioning check.
- Re-run the full gate and record the final coverage %; verify every
  COMPATIBILITY "supported" row links to a test.

## Acceptance criteria

- Recorded benchmark numbers (Julia vs Nim, same workload) and allocation
  figures; no unmeasured performance claims.
- Any optimization is behind the same behavior tests and does not lower
  coverage; SIMD/threads only with a recorded benchmark decision.
- Docs build/read correctly; links resolve; CI config runs the same commands
  as `scripts/check.jl`.
- License audit complete for code, fixtures, fonts, and any codec package.
- `Pkg.test()` and `scripts/check.jl` green at the end; exact coverage %
  recorded in HANDOFF and the task results.

## Validation

Commands as T004 plus the benchmark harness; record exact machine/toolchain.
Do not publish, push, or register the package without explicit user request.
Do not edit shared docs; do not commit.

## Results and handoff

Completed 2026-11-06. A first measurement pass was invalidated by a
review (debug-mode Nim reference, 20-vs-21 sample means, 1 ms timer,
9-vs-10/99-vs-100 iteration asymmetry) and the harnesses were fixed
before the record below; the reviewer also surfaced a genuine renderer
bug (see "Regression found and fixed").

### Regression found and fixed (T011)

The README quick start (translate + rotate + fill/stroke) crashed with
`InexactError: trunc(UInt8, -15)` while the pinned upstream renders it
fine. Root causes, both fixed:
- `src/rasterizer.jl` trapezoid pass: `leftRectArea = prevPen -
  trunc(prevPen)` — upstream uses `prevPen.fractional`, i.e. vmath
  `fract`, which is abs-based (`-3.14 -> 0.14`); a negative pen (possible
  under rotated transforms) produced negative coverage. Now
  `abs(prevPen) - trunc(abs(prevPen))`.
- `src/Vetra.jl` `*(ColorRGBX, float32)`: upstream computes in uint32
  and truncates to uint8 (out-of-range areas wrap); the port raised
  `InexactError`. Now wraps with `& 0xff`.

Pinned-oracle regression fixture: `tools/oracle/emit_fixtures.nim`
gains a `rotation` mode emitting `ctx_rot` (320×240 quick-start case:
fillRect + translate + rotate + strokeRect) — `sh
tools/oracle/build.sh rotation`, approved into test/reference/
(ctx_rot.raw/.png/.meta + sha256 sidecar). test/context_integration_tests.jl
"rotated fill/stroke parity with the upstream oracle" compares
byte-exact (0 mismatching pixels).

### Benchmarks (recorded, corrected harness)

Workloads (identical in both harnesses; fixed deterministic sizes):
256×256 black canvas (image-level fill on both sides); `fill_rects_1000`
(1000 context fillRects, 10×10, positions `(37i mod 246, 71i mod 246)`,
red); `stroke_lines_1000` (1000 context strokeSegments width 2,
`(7i mod 249, 0) -> (13i mod 249, 255)`, yellow); `blur_128_r3`;
`shadow_128` (offset (4,4), spread 2, blur 4, rgba(0,0,0,128));
`draw_10` (10× draw of a 128×128 red image at
`((13i mod 128), (29i mod 128))` onto 256×256 white);
`png_encode_256_x10` (x+y gradient image); `png_decode_basic1_x10`
(test/reference/font_basic1.png, 200×100);
`text_parse_layout_x100_measure_x20` (Roboto @24,
"The quick brown fox jumps over the lazy dog 0123456789"; the typeface
parse is inside the workload on both sides, hence the name).
Each workload: first (cold) call, 3 warm-ups discarded, 21 steady-state
iterations (mean/min/median, ns-resolution timer), plus a separate
allocation pass (bytes; this build's @allocated returns bytes only, and
Nim has no per-call counter, so the comparison headline is the median).

Environment (both sides, same machine): AMD Ryzen 9 5980HS, 16 cores,
Ubuntu 26.04.1, x86_64. Julia 1.13.3 (precompiled; first calls are
post-precompile cold, so first-call is not a fair cross-language
metric — the median is). Nim 2.2.6, C backend (gcc 15.2.0),
`-d:release -d:pixieNoSimd` (scalar parity; checks stay on in release).
PNGFiles for the Julia PNG workloads (opt-in, D014); upstream zippy for
the Nim side.

Commands:
- `rm -rf ~/.julia/compiled/v1.13/Vetra && julia --startup-file=no \
  --project=/tmp/pngenv benchmark/run_benchmarks.jl`
- `nim c -d:release -d:pixieNoSimd --path:.reference/upstream/src \
  --path:.reference/pkgs/{vmath,chroma,zippy,flatty,nimsimd,bumpy,crunchy}/src \
  -o:artifacts/benchmarks/pixie_ref benchmark/bench_reference.nim && \
  artifacts/benchmarks/pixie_ref`

Steady-state results (median ms; mean in parentheses; raw TSVs in
benchmark/results/{julia,nim}_2026-11-06.tsv, gitignored — numbers
recorded here per the "clone must have the evidence" rule):

| workload | Julia (median / mean ms) | Nim reference (median / mean ms) |
| --- | --- | --- |
| fill_rects_1000 | 0.90 / 0.89 | 0.82 / 0.87 |
| stroke_lines_1000 | 26.63 / 28.38 | 22.30 / 22.34 |
| blur_128_r3 | 0.69 / 0.69 | 0.43 / 0.42 |
| shadow_128 | 1.07 / 1.09 | 0.67 / 0.67 |
| draw_10 | 1.15 / 1.16 | 0.18 / 0.18 |
| png_encode_256_x10 | 29.05 / 29.52 | 10.78 / 10.85 |
| png_decode_basic1_x10 | 67.27 / 69.61 | 1.17 / 1.18 |
| text_parse_layout_x100_measure_x20 | 1.26 / 1.97 | 1.99 / 1.99 |

Julia allocation bytes per steady+alloc pass (21+21 calls): fill
35.8 MB, stroke 93.9 MB, blur 2.8 MB, shadow 6.9 MB, draw 6.9 MB,
png_encode 195.8 MB, png_decode 987.1 MB, text 42.6 MB.

First-call (ms, for the record): Julia fill 1.31, stroke 26.4, blur
0.63, shadow 1.06, draw 1.17, png_encode 941.2 (PNGFiles cold dispatch),
png_decode 119.2, text 24.5; Nim fill 1.26, stroke 22.9, blur 0.48,
shadow 0.72, draw 0.19, png_encode 11.2, png_decode 1.25, text 2.58.

### Optimization decision: none (D016)

The port is faster on the text workload and within 1.2x on fill/stroke;
the measured gaps are draw (6.4x), PNG encode (2.7x) and PNG decode
(~57x — the D014 codec choice, not a renderer defect). No `@fastmath`,
SIMD, threading or other optimization is applied in this release; the
gap is accepted and recorded as D016 (docs/DECISIONS.md) — optimizing
against the 811k-assertion parity gate is a separate, reviewed task.

### Documentation and release audit

- README.md rewritten from the bootstrap stub: install-from-checkout
  command (the package is unregistered), opt-in codec environment
  recipe (precompile-cache caveat), quick-start snippet (verified
  run-clean, incl. the T011 rotation regression), font subset notes,
  tests/coverage commands, benchmark pointer, license. All referenced
  files verified to exist.
- Supported/unsupported matrix: docs/COMPATIBILITY.md (per-symbol, with
  evidence); two stale rows (mask-blend dispatch, clip/mask layers)
  corrected during the audit. Limitations: WebP codec, CFF/TTC/SVG
  fonts, isPointInStroke (not in docs/API.md), unicode shaping beyond
  upstream — all recorded with reasons.
- CI (.github/workflows/ci.yml) runs exactly `scripts/check.jl` (tests +
  >95% coverage gate) on Julia 1.10 and current stable ('1') on
  ubuntu/windows/macos — matches the local gate command.
- NOTICE audit: T010 range; translated third-party packages listed
  (vmath/chroma/bumpy/flatty/nimsimd/zippy, all MIT); fixture
  provenance paragraph (all test/reference/ fixtures generated from the
  pinned upstream repo incl. its bundled test assets, e.g. the
  Ghostscript-Tiger SVG and USC-SIPI mandrill image, which carry no
  per-asset notices upstream); codec packages and fonts (Roboto
  Apache-2.0, Ubuntu UFL, sha256) listed. The open "additional images
  need records" line is removed — every shipped asset class is covered.
- test/README.md rewritten (it still described the pre-T001
  package-load smoke test).
- Package name/registration: "Vetra" is not registered in the Julia
  General registry (checked `P/Vetra` on the main branch, 2026-11-06 —
  404), so the name is available when the user requests registration.
  Version is 0.0.1; registration/publishing deferred per policy
  (explicit user request only).
- COMPATIBILITY evidence audit: every "implemented" row links a test
  file or pinned fixture set (scripted scan).
- Final gate: `julia --startup-file=no --project=. scripts/check.jl` →
  **OK**, all suites green (see docs/HANDOFF.md for the assertion total
  and per-suite breakdown),
  `coverage gate: src/ line coverage = 98.0% (5230/5337 measurable
  lines)` → recorded final coverage **98.0%** (re-verified after the
  rotation regression test was added).

Remaining release blockers: none technical. Registration, pushing and
publishing await explicit user request (policy).
