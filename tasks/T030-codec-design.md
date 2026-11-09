# T030 — JPEG/WebP codec contracts and dependency decision

Status: see [TASKS.md](../TASKS.md). Dependencies: T013. Priority: web images.
Goal: choose maintainable optional codec paths before adding format APIs.

## Inputs and scope

Read D014/D019, src/formats/{jpeg,io,png}.jl, codec-loading tests, and Project.toml.
Investigate the installed JPEG package's encoding support and maintained WebP
packages, platform artifacts, licenses, and Julia 1.10 support. Extend D014 with
an explicit decision; retain native Julia rendering and opt-in codec loading.

## Acceptance criteria

- Specify JPEG straight-RGB conversion, transparent-input behavior (explicit
  background or error), quality defaults, orientation/metadata, and write dispatch.
- Specify a static-image WebP subset: read/write, lossless/lossy modes, alpha,
  quality defaults, unsupported animation, dimensions, and clear errors.
- Select providers based on current maintenance/availability and verified APIs;
  if no suitable provider meets the contract, leave that implementation blocked
  with the concrete limitation rather than creating a placeholder codec.
- Define independently sourced fixtures, interoperability tools, and error/quality
  comparison policies. Lossy validation cannot be byte-exact by assumption.
- Plan present/absent codec and cache-reuse tests plus compatibility docs, covering
  extensions, magic-byte dispatch, exported symbols, and base64 interactions.

## Validation

Use isolated scratch environments for API feasibility and encode/decode probes;
record exact package/tool versions and commands. Check license/artifact support
for supported platforms; design completion requires a viable concrete plan.

## Results and handoff

Status: done (2026-11-09). Design only — no source changes, no new
dependencies; the gate is unchanged from T028 (96.29%, 7013/7283) and no
placeholder codecs were added. The contract is
docs/JPEG_WEBP_CODECS.md; the provider decision is D032 (docs/
DECISIONS.md), amending D014's JPEG ("no encoder, as upstream") and WebP
("deferred") bullets.

### Provider selection (criteria: maintenance, availability, verified
API, artifacts, license, Julia 1.10)

- **JPEG encode = `JpegTurbo` 0.1.6** (JuliaIO/JpegTurbo.jl, MIT;
  `JpegTurbo_jll` 3.2.1+0, libjpeg-turbo BSD-2, 18 platform artifacts:
  linux x86_64/aarch64/armv7l/armv6l/i686/powerpc64le/riscv64 glibc+
  musl, freebsd x86_64, macos x86_64+aarch64, windows x86_64+i686; julia
  compat 1.6.0–1). Already the opt-in T008 decode dependency → zero new
  deps. `jpeg_encode(img::Matrix{<:Colorant}; quality=92,
  write_JFIF_header, density_unit, X_density, Y_density, ...)` verified.
- **WebP = `WebP.jl` 0.1.3** (stemann/WebP.jl, MIT, last push
  2026-06-24; registry julia compat "1"; deps CEnum/ColorTypes/FileIO/
  FixedPointNumbers/ImageCore — all MIT) + **`libwebp_jll` 1.6.1+0**
  (libwebp BSD, 18 platform artifacts, same list). The General
  registry contains exactly one WebP package (2026-11-09 sweep), so no
  alternative candidate existed. New opt-in extra (T032 adds the
  `[extras]` entry + the `_requireWebP` install-hint helper, lazy
  discovery per D028 — no `__init__` change).
- Alternatives rejected (D032): native WebP port (VP8/VP8L+alpha+RIFF
  surface; the D014 "no stable package" rationale no longer holds);
  direct `ccall` to libwebp_jll (duplicates the thin tested wrapper);
  a second JPEG encoder (the decode dependency already encodes).

### Contract highlights (docs/JPEG_WEBP_CODECS.md)

- `encodeJPEG(image; quality=92, background=white)`: exact integer
  premultiplied→straight composite `out8 = clamp((p8*255 + b8*(255-a8)
  + 127) div 255)` (no division by alpha); JFIF baseline with
  **contract-mandated 72×72 dpi density** (see interop below); quality
  1..100 named-error bounded; dimension bound 65500 (the provider
  segfaults at 65501 — bisected); no EXIF/Adobe
  written; orientation not preserved on encode (decode stays
  Exif-orientation-aware, T008).
- `decodeWebP`/`decodeWebPDimensions`/`encodeWebP(image; lossy=true,
  quality=75)`: decode = feature scan → **animation rejected with a
  named `ArgumentError` before pixel decode** → provider auto
  RGB/RGBA → house straight→premultiplied `(s8*a8 + 127) div 255`.
  Encode = premultiplied→straight `(p8*255 + a8 div 2) div a8`, always
  RGBA, lossless ignores quality (provider API has no lossless quality
  parameter), dimension bound 16383 (the provider silently returns an
  empty vector at 16384 — verified).
- Lossy validation is never byte-exact: JPEG = hand-derived marker
  structure + independent-decoder interop + PSNR floor; WebP = pinned
  third-party fixtures for decode dimensions + round-trip exactness
  partition (lossless: alpha exact everywhere, RGB exact where α>0,
  RGB under α=0 unspecified; lossy: dimensions + PSNR floor).
- Test/docs plan: D019 present/absent + shared-cache protocol extended
  to WebP (T032); RIFF+WEBP magic dispatch in `decodeImage`/
  `decodeImageDimensions`; `encodeBase64` stays PNG-only (upstream
  parity), `decodeBase64` gains WebP via the magic dispatch.

### Probe evidence (isolated scratch env, 2026-11-09)

Scratch project `/tmp/opencode/codecprobe` (Julia 1.13.3,
`Pkg.activate(@__DIR__)`, `Pkg.add(["JpegTurbo","WebP","ColorTypes",
"FixedPointNumbers","SHA"])`; resolved: JpegTurbo 0.1.6, WebP 0.1.3,
JpegTurbo_jll 3.2.1+0, libwebp_jll 1.6.1+0 — versions read from the
scratch Manifest). Commands (all from `/tmp/opencode/codecprobe`):

- `julia --startup-file=no probe.jl` — fixed 64×48 gradient
  (r = x/63, g = y/47, b = 0.5; 9×9 α=0 corner):
  `JpegTurbo.jpeg_encode(rgb; quality=92)` → 1069 B, SOI `ffd8`, EOI
  `ffd9`; q10 → 742 B; PSNR(q92 self round-trip) = 48.78 dB; WebP
  encode/decode matrix: RGB lossless → 88 B VP8L, RGB lossy → 230 B
  VP8, RGBA lossless → 132 B VP8L, RGBA lossy → 292 B VP8X; all decode
  back at (48, 64) with auto alpha detection.
- `julia --startup-file=no jfif_probe.jl` — the four JFIF variants:
  default (units=0, 1×1), `write_JFIF_header=false` (first marker
  `ffdb`), units=1 72×72, units=2 28×28; SOF0 = 64×48 in all;
  self-round-trip max channel delta = 3.
- mupdf (PyMuPDF 1.28.2, venv `/tmp/opencode/pmupdf`): page rect follows
  JFIF density — units=0/1×1 → 48×36 pt, no-JFIF → 48×36 pt (the 96-dpi
  assumption), units=1 72×72 → 64×48 pt, units=2 28×28 → 64×48 pt.
  Hence the 72 dpi contract: interop assertions become size-independent.
- `julia --startup-file=no jfif_compare.jl` — mupdf 72-dpi pixmap (64×
  48 RGB) vs `JpegTurbo.jpeg_decode` of the same file: max channel
  delta = 4, no pixel > 8 (contract tolerance: ≤ 8).
- `julia --startup-file=no webp_exact.jl` — lossless RGBA round-trip:
  81/3072 mismatches, all inside the α=0 corner (first: (56,40),
  r 0.875 → 0.859, g/b exact); opaque-only lossless: 0/3072; RGB
  lossless: 0/3072. → the §3.5 exactness partition.
- `julia --startup-file=no webp_lossy_probe.jl` — lossy PSNR on the
  fixed gradient: q10 = 31.99, q50 = 36.63, q75 = 37.67, q95 = 45.11
  dB (sizes 146/194/230/342 B) → the ≥ 35 dB q75 floor; provider
  quality-range errors are named and catchable
  (`ArgumentError("Quality $q is not in the range from 0 to 100.")`,
  q = −1/101); **16384×4 encodes to 0 B with no error** (silent
  provider failure) → the encodeWebP boundary check is mandatory.
- `julia --startup-file=no jpeg_bisect.jl` — JPEG oversize bisect:
  30000/60000/65500 wide encode OK (8125/15625/17001 B); **65501
  segfaults** in `jinit_compress_master` (same at 65535/65536;
  uncatchable from Julia) → the encodeJPEG boundary check is mandatory;
  the contract bound is 65500 (libjpeg-turbo MAX_JPEG_DIMENSION), not
  the naive 65535.
- `julia --startup-file=no webp_files.jl` — gstatic fixtures decode at
  the expected sizes (lossy 1.webp → 368×550 RGB; lossless
  1_webp_ll.webp → 301×400 RGBA; auto-detect matches explicit types).
- `julia --startup-file=no anim_probe.jl` — animated WebP: features
  scan reports `has_animation=1, has_alpha=1, 211×211`;
  `WebP.decode` on the same bytes **crashes the Julia process at C
  level** (uncatchable; segfault through the libwebp decoder). → the
  pre-decode animation guard is mandatory.
- WebP interop check: `fz.open("gs_lossy.webp")` → `FileDataError:
  Failed to open file … as type webp` — mupdf has no WebP support; no
  ffmpeg/cwebp/dwebp/ImageMagick/PIL on the machine (checked) →
  recorded limitation, fixtures + round-trip policy stand in.

### Pinned fixtures (URL, bytes, sha256; fetched 2026-11-09)

- `https://www.gstatic.com/webp/gallery/1.webp` — 30320 B,
  `4a5afeaff8483923da964bc7896f02d0283e8bff99b5b8f82a31ae3214dab1d0`,
  lossy VP8, 368×550, no alpha.
- `https://www.gstatic.com/webp/gallery3/1_webp_ll.webp` — 81836 B,
  `49a902b9c35bd2031bf26234c59ff369dd3ae18a3b58247285104a23346ba2d4`,
  lossless VP8L, 301×400, with alpha.
- `https://upload.wikimedia.org/wikipedia/commons/f/f8/Simple_Animated_Clock.webp`
  — 600504 B,
  `c020aacdd11922051d2d509a8a31f1e0edfb8bc9113689923fb638e4a9cdb886`,
  animated VP8X, 211×211 (error-path fixture).

Fixture placement for T032 follows the T029 protocol: bytes + URL +
sha256 in fixture meta, verified by tests. The gstatic gallery is
Google's canonical WebP test corpus (the same source WebP.jl's own test
suite downloads); it is an independent third party, not the code under
test.

### Limitations and notes

- No independent WebP pixel decoder is available on the verification
  machine; WebP *decode* assertions are limited to dimensions +
  structure (recorded above). If ffmpeg/cwebp/dwebp ever land in CI, the
  interop section of the contract should be extended, not silently.
- Lossy JPEG/WebP outputs are validated by PSNR floors and
  independent-decoder tolerance, never by byte pinning; the floors
  (≥ 40 dB JPEG q92; WebP lossy q75 value recorded by T032) are set from
  the measured values with margin, on the fixed test images only.
- `encodeBase64` remains PNG-only (upstream parity); the contract
  explicitly does not add non-PNG data-URL encoders.

Next: T031 (JPEG encoding — first ready row) implements
`encodeJPEG` per contract §2 with the structure + mupdf interop + PSNR
tests; T032 (static WebP) implements §3 with the fixture + round-trip
partition + animation-guard tests and the D019 loading-test extension.
T029 remains blocked on the D031 §6 provider decision; T019 awaits an
explicit publication request.
