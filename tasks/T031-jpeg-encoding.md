# T031 — Optional JPEG encoding

Status: see [TASKS.md](../TASKS.md). Dependencies: T030 JPEG contract/decision.
Goal: write JPEG thumbnails and photographic output from Vetra images.

## Inputs and scope

Implement T030 using the selected optional provider, existing JPEG decoder,
format dispatch, and codec loading pattern. Add only the specified options;
do not expose provider internals as an unbounded public keyword API.

## Acceptance criteria

- Public encoder and `.jpg`/`.jpeg` write/encode dispatch work with explicit
  quality and the agreed transparency/background behavior.
- Correct channel order, orientation, dimensions, quality validation, and
  error handling, including absent codec and malformed/unsupported arguments.
- An independent JPEG reader opens produced files. Use separately justified
  structural and lossy pixel/quality checks; do not require arbitrary JPEG
  byte equality or silently discard alpha.
- Existing JPEG decoding, PNG/base64 behavior, and core-only loading stay valid.
- Provide an annotation/thumbnail export recipe and compare runtime/output size
  on photographic and flat graphics, noting where JPEG is unsuitable.

## Validation

Use [shared validation](../docs/ROADMAP.md#shared-validation), optional-provider
subprocess tests, independent-reader checks, and codec corpus benchmarks.
Record the agreed lossy comparison policy before evaluating test output.

## Results and handoff

Status: done (2026-11-09). Implemented per the T030 contract
(docs/JPEG_WEBP_CODECS.md §2, D032); zero new dependencies (JpegTurbo
was already the opt-in decode package).

### Changes

- `src/formats/jpeg.jl`:
  - `_JPEG_MAX_DIMENSION = 65500` (libjpeg-turbo MAX_JPEG_DIMENSION;
    bisected: 65500 encodes OK, 65501 segfaults in
    `jinit_compress_master` — uncatchable C-level, so the API boundary
    must reject first).
  - `_jpegComposite(p8, b8, a8)` — the contract's exact integer
    premultiplied→straight-over-background formula
    `clamp((p8*255 + b8*(255-a8) + 127) div 255)`; no division by alpha.
  - `_encodeJPEGMatrix!` kernel (Vetra-side, `invokelatest` — D028
    world-age safety, the `toColors` pattern) building the
    `Matrix{RGB{N0f8}}` the provider expects (`[row=y, col=x]`, no
    transpose — orientation verified by the tests).
  - `encodeJPEG(image::Image; quality::Int = 92, background::ColorRGB =
    rgb(255,255,255))` → `Vector{UInt8}`; validation order: require
    package → quality 1..100 (named `ArgumentError`) → dimension bound
    (named `ArgumentError`) → encode with `density_unit=1,
    X_density=72, Y_density=72` (contract JFIF).
  - **Latent bug fixed**: `decodeJPEG`'s pixel loop called
    `Float64(::N0f8)` inline; on a fresh process where the first codec
    call is a JPEG decode, FixedPointNumbers is required by that very
    call and the pre-require world can't dispatch →
    `MethodError: ... method too new`. The loop is now a
    `_decodeJPEGPixels!` kernel invoked with `Base.invokelatest`
    (output byte-identical; T008's 796459-assertion suite green).
    Repro before the fix: in a codec-enabled env (e.g.
    `--project=docs`), `using Vetra; readImage("x.jpg")` as the first
    codec call.
- `src/formats/io.jl`: `encodeImage` JpegFormat branch → `encodeJPEG`
  (upstream parity: no keyword passthrough); `writeFile` unchanged
  (extension dispatch already routed `.jpg`/`.jpeg`); docstrings
  updated.
- `src/Vetra.jl`: export `encodeJPEG`.
- `test/formats_tests.jl`: the "unencodable" loops no longer include
  JPEG — `encodeImage(img, JpegFormat) == encodeJPEG(img)` and
  `.jpg`/`.jpeg` join the six writable formats (byte-equal to
  `encodeJPEG`). NOTE: the old try/catch checks had silently stopped
  asserting (no exception → no `@test` executed), dropping the suite
  796459 → 796456; the update restores the count with real
  assertions. `.webp` stays in the raising loop (T032).
- `test/codec_loading_tests.jl`: absent env → `encodeJPEG` raises the
  install hint ("JPEG support is opt-in"); codec-enabled env →
  `decodeJPEGDimensions(encodeJPEG(image)) == (2, 3)`.
- `test/jpeg_encode_tests.jl` (new, 61 assertions, registered in
  `runtests.jl`): conversion-helper exactness (contract §2.2 worked
  examples + clamp); marker structure (SOI, JFIF units=1 72×72, SOF0
  dimensions via `decodeJPEGDimensions`, EOI, determinism); quality
  validation (0/101/−5 named errors, 1/100 accepted, 92.0 →
  TypeError); dimension validation (65501×4 and 4×65501 named errors
  before the provider runs, 65500×4 encodes); round-trip (dimensions,
  opaque alpha, four-corner orientation pin, PSNR ≥ 40 dB at q92,
  q10 < q92); transparency (fully transparent → solid background
  (10,20,30), default white, half-alpha §2.2 examples exact: 255 over
  white, 128 over black); dispatch (`encodeImage == encodeJPEG`,
  `.jpg`/`.jpeg` write + re-decode, unknown ext raises,
  `encodeBase64` still PNG-payloaded, `decodeBase64` accepts a JPEG
  payload); mupdf interop (independent reader).
- Cookbook recipe 13 (`annotation-jpeg.jpg`, 15 gallery items):
  mandrill thumbnail export + photographic-vs-flat size comparison.

### Interop protocol (per contract §2.6)

`mupdf` (PyMuPDF 1.28.2) is a scratch tool like T026's gs/poppler: the
test runs it when `VETRA_MUPDF_PY` (default `python3`) can import
pymupdf, and prints "pymupdf not resolvable; mupdf interop check
skipped" otherwise. On this machine:
`VETRA_MUPDF_PY=/tmp/opencode/pmupdf/bin/python` (venv, ephemeral —
recorded limitation: the gate runs the interop when the venv exists,
skips with a note when it doesn't). Interop asserts: page rect
`64.000 48.000` pt (= the encoded dimensions, per the 72 dpi JFIF
contract), 72-dpi pixmap `64 48 3`, and max channel delta ≤ 8 against
Vetra's own decode (measured 4).

Frozen-build quirk hit: **ASCII `div` is a ParseError** in this build
(`x div y` fails to parse; `x ÷ y` works) — all code uses `÷`
(existing house style); docstrings may say "div". Also `read(Process,
String)` returns empty — subprocess output is captured via
`pipeline(cmd; stdout = IOBuffer())`.

### Benchmark (warm medians, 11 runs after 2 warmups; log
`/tmp/opencode/t031_bench.jl`)

| image | JPEG q85 | PNG | ratio |
| --- | --- | --- | --- |
| mandrill 512×512 (photo) | 105142 B, 3.39 ms | 732157 B, 17.13 ms | 0.144 |
| mandrill 256×256 (thumbnail) | 26559 B, 0.82 ms | 180278 B, 3.83 ms | 0.147 |
| flat 320×240 gradient scene | 4333 B, 0.84 ms | 2411 B, 1.24 ms | 1.797 |

JPEG wins big on photographic content (~7× smaller, ~4× faster) and
loses on flat graphics (1.8× bigger) — the recipe notes the
unsuitable case; cookbook asserts `photoJpg < photoPng * 0.25` and
`flatJpg >= flatPng` (both deterministic — libjpeg/PNG encoders are
deterministic for fixed inputs).

### Verification

- Focused: `julia --startup-file=no --project=docs -e 'using Test,
  Vetra; include("test/jpeg_encode_tests.jl")'` → 61/61 (with
  `VETRA_MUPDF_PY` set); 56/56 + skip note without it.
- `test/formats_tests.jl` (with `fixtures.jl`): 796459/796459.
- Full gate: `julia --startup-file=no --project=. scripts/check.jl`
  (with `VETRA_MUPDF_PY=/tmp/opencode/pmupdf/bin/python`) → all suites
  pass, **coverage 96.31% (7039/7309)** (up from 96.29% at T028),
  `scripts/check.jl: OK`. Baseline bisect: the gate on the pre-change
  tree (stash) gives T008 = 796459 and 96.29% — the post-change T008
  count matches the baseline exactly (the dispatch-test update restored
  the three assertions that the new JPEG dispatch had silently
  removed).
- Cookbook: `julia --startup-file=no --project=docs docs/make_cookbook.jl`
  builds clean; `annotation-jpeg.jpg` (36501 B, 256×256 mandrill at the
  default q92 — the q85 sizes above are the comparison numbers)
  visually inspected.

### Limitations

- mupdf interop is conditional (scratch venv); a machine without
  PyMuPDF skips it with a printed note, like the gs/poppler checks.
- JPEG files carry no orientation metadata (contract §2.3); decoding
  stays Exif-orientation-aware (T008, unchanged).
- 65501+ inputs are rejected by the API; the provider crash at that
  size is the reason (recorded, not "fixed" — it is inside
  libjpeg-turbo).

Next: T032 (static WebP read/write) is the first ready row. T029
remains blocked on the D031 §6 provider decision; T019 awaits an
explicit publication request.
