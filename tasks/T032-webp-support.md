# T032 — Optional static WebP reading and writing

Status: see [TASKS.md](../TASKS.md). Dependencies: T030 WebP contract/decision.
Goal: support practical web graphics with documented alpha and compression modes.

## Inputs and scope

Implement the static-image subset approved in T030, using the chosen optional
provider. Wire WebpFormat, dimensions, magic-byte decode, and extension-driven
write paths; replace the unsupported-format behavior only when real support is
available. Animation remains an explicit unsupported case unless separately scoped.

## Acceptance criteria

- Static decode/encode supports the contracted lossless/lossy modes and alpha,
  with correct row/column order, straight/premultiplied conversion, and dimensions.
- Test opaque, transparent, non-square, small, invalid, and truncated inputs;
  animated files get the documented error rather than an implicit first frame.
- Independently authored/encoded fixtures and a separate reader establish
  interoperability. Lossless checks account for the documented alpha-conversion
  boundary; lossy checks use justified quality bounds, not adjusted tolerances.
- Missing provider gives the specified install hint; core-only and existing
  codec/cache behavior remain intact. No tests need a runtime network fetch.
- Add a web-card export example and report encode/decode time and file size for
  representative images, without claiming universal superiority over PNG/JPEG.

## Validation

Use [shared validation](../docs/ROADMAP.md#shared-validation), provider-present/
absent subprocess tests, independent WebP reader checks, and corpus benchmarks.
Record format/mode coverage and platform artifact checks.

## Results and handoff

Status: done (2026-11-09). Implemented per the T030 WebP contract
(docs/JPEG_WEBP_CODECS.md §3, D032); one new opt-in extra (`WebP.jl`
0.1.3 + `libwebp_jll` 1.6.1+0, already in the depot from the T030
probes), zero new hard dependencies.

### Changes

- `src/formats/webp.jl` (new):
  - `_WEBP_PKGID` + `_requireWebP()` — lazy discovery (D028) with the
    install hint "WebP support is opt-in: add the WebP package …".
  - `_WEBP_MAX_DIMENSION = 16383` — the provider silently returns an
    empty vector at 16384 (T030 probe), so the API boundary rejects
    first with `ArgumentError("WebP dimension exceeds 16383")`.
  - `_webpFeatures(m, data)` — `WebPGetFeaturesInternal` through the
    provider's Wrapper with the return value **success-checked**
    (`rv == 0` = OK; observed 3 and 7 on invalid input; libwebp_jll
    1.6.1). The provider's own auto-decode ignores that return value
    and proceeds into the pixel decode with an unreadable feature
    struct on bad input — the guard is mandatory, not a nicety.
    Invalid/truncated data → `ArgumentError("Invalid WebP, unable to
    load")` (the house JPEG phrasing).
  - `decodeWebP(data)` — feature scan → **animation rejected with
    `ArgumentError("WebP animation is not supported")` before pixel
    decode** (the provider decode segfaults the process at C level on
    animated input — uncatchable, T030 repro) → typed decode
    (`RGBA{N0f8}` / `RGB{N0f8}` per `has_alpha`, both under
    `Base.invokelatest`) → the `_decodeWebPPixels!` kernel converts
    straight → premultiplied with the house `(s8*a8 + 127) div 255`;
    RGB input becomes `a = 255`. The kernel is under `invokelatest`
    for D028 world-age safety (the `N0f8 → Float64` conversion is
    defined by FixedPointNumbers, which the decode call itself may
    require — the same latent defect T031 found in `decodeJPEG`).
  - `decodeWebPDimensions(data)` — feature scan only; animation is
    **not** rejected here (the canvas dimensions are still the
    file's, per contract §3.2).
  - `_webpUnpremul(p8, a8)` — contract §3.3: `a8 = 0` → `0`; else
    `clamp((p8*255 + a8 div 2) div a8, 0, 255)` (exact for `a8 = 255`).
  - `_encodeWebPMatrix!` kernel (premul → straight, always RGBA,
    `[row=y, col=x]`, under `invokelatest`, the `toColors` pattern) +
    `encodeWebP(image; lossy = true, quality = 75)` →
    `Base.invokelatest(m.encode, mat; lossy, quality)`. `quality` is
    lossy-only 0..100 with the provider's named
    `ArgumentError("Quality $q is not in the range from 0 to 100.")`
    pass-through; lossless ignores it (provider API).
- `src/formats/io.jl`: RIFF+WEBP magic branch in `decodeImage` and
  `decodeImageDimensions` — `length(data) ≥ 30 && "RIFF" && "WEBP"`
  before the fallback error (the 30-byte floor is contract §3.1;
  shorter payloads keep raising "Unsupported image file format");
  `encodeImage` WebpFormat → `encodeWebP`; docstrings updated (only
  GIF writing still raises).
- `src/Vetra.jl`: `include("formats/webp.jl")` + exports
  `decodeWebP`, `decodeWebPDimensions`, `encodeWebP`.
- `Project.toml`: `[extras]` + test target gain `WebP`
  (e3aaa7dc-3e4b-44e0-be63-ffb868ccd7c1). `docs/Project.toml` gains
  the `WebP` dep (cookbook recipe 14 needs it; resolved 0.1.3 +
  libwebp_jll 1.6.1+0).
- `test/webp_tests.jl` (new, 353 assertions, registered in
  `runtests.jl`) — see "Test suite" below.
- `test/formats_tests.jl`: `.webp` moves from the "unencodable" try/
  catch loop into the writable list (seven writable extensions,
  byte-equal to `encodeWebP`); `encodeImage(img, WebpFormat) ==
  encodeWebP(img)`; the GIF raise stays as a real assertion. Suite
  count restored to the T031 baseline 796459 (net zero: +2 writable
  asserts, −2 old-loop asserts).
- `test/codec_loading_tests.jl`: absent env → `_WEBP_PKGID` in the
  locate-none list, `decodeWebP`/`encodeWebP` raise the install hint;
  codec-enabled env → `decodeWebPDimensions(encodeWebP(image)) ==
  (2, 3)` and lossless round-trip byte-equality.
- Cookbook recipe 14 (`mandrill-webp.webp`, 16 gallery items): web-
  card export — mandrill thumbnail lossless + lossy q75 sizes/times,
  a transparent rounded card (PNG vs WebP lossless), file write +
  decode time. Reports the numbers without claiming universal
  superiority (per the acceptance criteria).

### Test suite (test/webp_tests.jl)

- **Dimensions, 12 exact upstream expectations** — the
  `checkDimensions(...)` values from
  `.reference/upstream/tests/test_webp.nim` (small_1x1 1×1, small_1x13
  1×13, small_13x1 13×1, small_31x13 31×13, test 128×128,
  lossy_q0_f100 128×128, lossless1 1000×307, lossy_alpha1 1000×307,
  alpha_no_compression 16×16, one_color_no_palette 100×100,
  near_lossless_75 256×256, vp80-00-comprehensive-016 176×144).
- **Corpus, all 129 pinned libwebp fixtures** — every file
  feature-scans, pixel-decodes, and decodes at its feature dimensions
  (upstream asserts the same invariants + `WebpSuiteFiles.len == 129`);
  corpus alpha classification pinned on three hand-checked files
  (`small_1x1`/`test`/`vp80-00-comprehensive-016` all `a = 255`;
  `one_color_no_palette` all `a = 0`; `lossless1` mixes a = 0 and
  a = 255 — 211284 of 307000 transparent per the T032 probe).
- **Animation** — the pinned `test/reference/webp_animated_clock.*`
  fixture (Wikimedia `Simple_Animated_Clock.webp`, 600504 B, sha256 in
  the meta, verified when the SHA package is loaded):
  `decodeWebPDimensions` reports (211, 211); `decodeWebP` raises the
  named error instead of an implicit first frame.
- **Invalid/truncated** — fixed non-WebP bytes and a valid file cut at
  10 and 20 bytes all raise "Invalid WebP, unable to load" from both
  entry points (the feature scan fails in both truncation cases —
  libwebp validates the chunk data, not just the header).
- **Magic dispatch boundaries** — a 16-byte RIFF+WEBP payload
  (under the 30-byte floor) falls through to "Unsupported image file
  format" from `decodeImage`/`decodeImageDimensions`; at/above the
  floor the WebP branch decodes.
- **Conversion helpers** — `_webpUnpremul` exact values (half-rounded
  divide, clamp at (128,128) → 255, (7,1) → 255, `a = 0` → 0, opaque
  passthrough) + the premul→straight→premul identity on the stored
  semi-transparent row.
- **Lossless round-trip partition** — the opaque 64×48 asymmetric
  gradient is byte-exact (0 channel diffs, four-corner orientation
  pin); the 16×16 alpha image asserts the contract §3.5 partition:
  alpha exact everywhere, RGB exact where α > 0, RGB == 0 where α = 0
  (straight color under full transparency is format-unspecified —
  unobservable in the premultiplied API).
- **Lossy** — dimensions exact, opaque output, PSNR ≥ 35 dB at q75
  (measured 37.67 in the T030 probe), q10 strictly worse, lossless
  ignores quality (same bytes at q10/q90).
- **RIFF structure** — hand walk of the chunk table: `RIFF` + size −
  8 + `WEBP`, contiguous to the end; lossless → `["VP8L"]`; lossy
  fully-opaque → `["VP8 "]`; lossy with real alpha → `["VP8X",
  "ALPH", "VP8 "]` (observed libwebp_jll 1.6.1 order).
- **Validation** — 16384×4 and 4×16384 named errors before the
  provider; 16383×4 encodes and round-trips; provider quality errors
  at −1/101; boundaries 0/100 accepted; non-Int quality → `TypeError`;
  small/non-square 1×1, 1×13, 13×1, 31×13, 3×4 encode→decode exact.
- **Dispatch** — `encodeImage(WebpFormat) == encodeWebP`; `.webp`
  write + re-read (deterministic encoder); GIF write still raises;
  `decodeBase64` accepts a WebP payload; `encodeBase64` stays
  PNG-payloaded (upstream parity).

### Fixture provenance

- Decode corpus: the pinned upstream tree —
  `.reference/upstream/tests/fileformats/webp/` (129 files; per that
  directory's SOURCE.txt, copied by treeform/pixie from the WebM
  Project libwebp test data; the two oversized upstream files were
  intentionally omitted upstream). In-repo, independently of the code
  under test.
- Animation fixture: Wikimedia Commons `Simple_Animated_Clock.webp`
  (URL + byte length + sha256 in `test/reference/webp_animated_clock.
  meta`; verified by the test when SHA is loaded). Pinned in-repo —
  no test needs a runtime network fetch.
- "Separate reader" limitation (contract §3.5, recorded): libwebp is
  the only C WebP decode ecosystem on this machine (no ffmpeg, cwebp,
  dwebp, ImageMagick, or PIL; mupdf refuses WebP — "Failed to open
  file … as type webp"), so decode validation is dimensions/
  classification against the independent upstream corpus, not a second
  decoder's pixels.

### Verification

- Focused: `julia --startup-file=no --project=docs -e 'using Test,
  Vetra; include("test/webp_tests.jl")'` → **352/352** in the docs env
  (the animated-fixture sha256 check prints its skip note there — no
  SHA package); the same suite under `Pkg.test` (gate env, SHA loaded)
  → **353/353** with the checksum verified.
- `test/formats_tests.jl` (with `fixtures.jl`) → 796459/796459
  (T031 baseline count exactly).
- Full gate: `julia --startup-file=no --project=. scripts/check.jl`
  (with `VETRA_MUPDF_PY=/tmp/opencode/pmupdf/bin/python`) → all suites
  pass: Optional codecs 2/2 (WebP present/absent protocol), T008
  796459, T031 61, T032 353; **coverage 96.32% (7110/7382)**;
  `scripts/check.jl: OK`.
- Cookbook: `julia --startup-file=no --project=docs
  docs/make_cookbook.jl` builds clean; `mandrill-webp.webp` (19162 B,
  256×256, lossy q75) written + gallery rebuilt with 16 items.

### Benchmark (warm medians, 11 runs after 2 warmups; log
`/tmp/opencode/t032_bench.jl`)

| image | WebP lossy q75 | WebP lossless | PNG | JPEG q85 |
| --- | --- | --- | --- | --- |
| mandrill 512×512 (photo) | 76648 B, 27.79 ms | 579344 B, 145.72 ms | 732157 B, 17.26 ms | 105142 B, 2.79 ms |
| mandrill 256×256 (thumbnail) | 19162 B, 6.41 ms | 136458 B, 77.28 ms | 180278 B, 3.72 ms | 26559 B, 0.82 ms |

Decode (warm medians): mandrill 512 lossy 5.96 ms, 512 lossless 5.14
ms, 256 lossy 1.49 ms. Transparent 256×256 card: PNG 1740 B vs WebP
lossless 394 B. On photographic content WebP lossy q75 is ~0.72× the
JPEG q85 size (256) / ~0.73× (512) but encodes ~10× slower; on
transparent flat content lossless WebP is ~4.4× smaller than PNG.
These are representative measurements, not a universal claim (recipe
14 reports, does not assert, the comparison).

### Limitations

- No independent WebP pixel decoder on the verification machine →
  corpus decode assertions are dimensions/classification only
  (contract §3.5, recorded above). If ffmpeg/cwebp/dwebp ever land in
  CI, extend the interop section, don't silently add it.
- Animated WebP is rejected, not supported (the provider decode
  crashes the process at C level on animated input — the guard is the
  feature).
- WebP encode is always RGBA; fully-opaque content gets a VP8-only
  file (libwebp drops the all-255 alpha) — the chunk-table test pins
  that.
- The animated fixture's checksum verification is conditional on the
  SHA package being loaded (always true under `Pkg.test`; the focused
  docs-env run prints the skip note).
- Fresh-install on Julia 1.10 / cross-platform CI for the new extra
  unverified (historical limitation, now shared by WebP's 18
  artifacts, same platform list as the other codec binaries).

Next: no ready rows — T029 remains blocked on the D031 §6 provider
decision; T019 awaits an explicit publication request. The T014–T032
roadmap is complete.
