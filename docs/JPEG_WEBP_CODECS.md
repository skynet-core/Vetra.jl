# JPEG/WebP codec contracts (T030)

Status: contract only (T030). T031 implements JPEG encoding; T032
implements static WebP read/write. Until then `encodeImage(JpegFormat|
WebpFormat)` and `writeFile` for `.jpg`/`.jpeg`/`.webp` still raise
`ArgumentError("Unsupported file format")`, and `decodeImage`/
`decodeImageDimensions` still fall through to
`ArgumentError("Unsupported image file format")` on WebP bytes (the JPEG
SOI dispatch already exists, T008). No placeholder codecs are added by
this task.

Providers and mechanics are pinned by D032 (`docs/DECISIONS.md`); this
document is the behavior contract T031/T032 must satisfy.

## 1. Providers (verified 2026-11-09)

| package | version | role | license | binary | artifacts |
| --- | --- | --- | --- | --- | --- |
| `JpegTurbo` (JuliaIO) | 0.1.6 | JPEG encode + decode | MIT (pkg); libjpeg-turbo BSD (binary) | `JpegTurbo_jll` 3.2.1+0 | 18: linux x86_64/aarch64/armv7l/armv6l/i686/powerpc64le/riscv64 glibc+musl, freebsd x86_64, macos x86_64+aarch64, windows x86_64+i686 |
| `WebP` (stemann) | 0.1.3 | WebP encode + decode | MIT (pkg); libwebp BSD (binary) | `libwebp_jll` 1.6.1+0 | 18: same platform list |

Both stay opt-in: the renderer core is dependency-free; codecs are
discovered lazily on first use (D028) with an install hint when absent
(JPEG reuses `_requireJpegTurbo`; T032 adds `_requireWebP` plus a
`Project.toml` `[extras]`/test-target entry — no `__init__` change).
Julia compatibility: `JpegTurbo` 1.6.0–1, `WebP` "1" — both cover the
pinned 1.10 floor. Registry check (2026-11-09): the
General registry contains exactly one WebP package (`W/WebP`,
stemann/WebP.jl, last push 2026-06-24); no second JPEG package is needed
because the decode dependency already encodes.

## 2. JPEG encode contract (T031)

### 2.1 API

```julia
encodeJPEG(image::Image; quality::Int = 92,
    background::ColorRGB = rgb(255, 255, 255))::Vector{UInt8}
```

- `quality` is 1..100 (the libjpeg range); out of range raises
  `ArgumentError("JPEG quality must be 1..100")`. Default 92 (the
  provider's default, the recommended high-quality value).
- `background` is composited under transparent and semi-transparent
  pixels (§2.2). Default is white — a documented choice: the alternative
  (error on any `alpha < 255`) would make saving a canvas that contains
  one transparent pixel fail, which is less predictable than a
  documented composite.
- Dispatch: `encodeImage(image, JpegFormat)` → `encodeJPEG(image)` with
  no keyword arguments (upstream `encodeImage` takes none either);
  `writeFile(image, *.jpg | *.jpeg)` routes to `JpegFormat` through the
  existing extension dispatch (T008). Base64: `encodeBase64` stays
  PNG-only (upstream parity); `decodeBase64` decodes through
  `decodeImage`'s magic dispatch, so base64 JPEG payloads already work
  (T008) and base64 WebP payloads work from T032.

### 2.2 Premultiplied → straight RGB (exact integer)

Vetra stores premultiplied RGBA8. JPEG has no alpha channel; each color
channel composites over `background`:

```
out8 = clamp0..255( (p8*255 + b8*(255 - a8) + 127) div 255 )
```

(`+127 div 255` is the house half-round, T002 convention.)

- `a8 = 255` → `p8` (opaque passthrough); `a8 = 0` → `b8`. There is no
  division by alpha, so no undefined case exists.
- Hand-derived example: `p = 100, a = 200, b = 50` →
  `(25500 + 2750 + 127) div 255 = 111`.
- The provider receives a fresh `Matrix{RGB{N0f8}}` indexed `[row=y,
  col=x]` (ImageCore convention) with element values `out8/255` (exact
  in N0f8), built directly from `image.data`; no `transpose` flag
  (orientation is verified by the §2.6 round-trip).

### 2.3 Metadata and orientation

- Output is baseline (SOF0) JFIF: a JFIF APP0 with `density_unit = 1`,
  `X_density = Y_density = 72` (pixels per inch), no Adobe marker, no
  EXIF, no thumbnails. The 72 dpi density is **contract, not default**:
  files without it (libjpeg's units=0, 1×1 default, or no JFIF at all)
  make mupdf assume 96 dpi and scale the page 0.75× (measured, §6),
  which would make interop assertions size-dependent.
- Orientation is not preserved on encode (a Vetra `Image` carries no
  orientation state); `decodeJPEG` stays Exif-orientation-aware, as in
  T008.

### 2.4 Dimensions

1..65500 per side (libjpeg-turbo's `MAX_JPEG_DIMENSION`; `newImage`
already guarantees ≥ 1). Out of range raises
`ArgumentError("JPEG dimension exceeds 65500")`. The check is required,
not cosmetic: encoding a 65501×4 image **segfaults** inside
`jinit_compress_master` (C-level, uncatchable from Julia — verified by
bisecting 65500 OK vs 65501/65535/65536 crash), so the API boundary
must reject before the provider runs.

### 2.5 Errors

- `JpegTurbo` absent from the environment → the existing
  `_requireJpegTurbo()` install hint (shared with decode; the encode
  path goes through the same helper).
- Provider C-level failures are not expected to be reachable from the
  API's valid inputs; if one is, it propagates unmodified (recorded in
  T031).

### 2.6 Lossy validation policy (byte-exact is not a goal)

JPEG is lossy, so no second encoder can byte-pin expected output. T031
tests assert, per `test/README.md`:

1. **Structure** (hand-derived marker walk): SOI `ff d8`; JFIF APP0
   `ff e0` with units=1 and 72×72; SOF0 carrying the exact encoded
   dimensions; DQT/DHT/SOS present; EOI `ff d9` last two bytes.
2. **Independent-decoder interop**: PyMuPDF/mupdf (1.28.2) opens the
   file, the page rect is `(W, H)` points, the 72-dpi pixmap is `W×H`
   RGB, and the max channel delta against `JpegTurbo.jpeg_decode` of the
   same file is ≤ 8 (measured 4 on the pinned test image, §6).
3. **Round-trip quality**: PSNR floor on the fixed smooth gradient,
   ≥ 40 dB at `quality = 92` (measured 48.78 dB); a `quality = 10`
   encoding of the same image decodes to a strictly lower PSNR (the
   knob bites).
4. **Conversion invariants**: the §2.2 worked example, the opaque
   passthrough (`a = 255` → identical to the straight source), and a
   fully transparent image encodes to the solid `background`.

## 3. WebP contract (T032)

### 3.1 API

```julia
decodeWebP(data::Vector{UInt8})::Image                       # premultiplied
decodeWebPDimensions(data::Vector{UInt8})::Tuple{Int, Int}
encodeWebP(image::Image; lossy::Bool = true,
    quality::Int = 75)::Vector{UInt8}
```

- Decode dispatch: `decodeImage`/`decodeImageDimensions` gain a magic
  branch — `length(data) ≥ 30 && String(data[1:4]) == "RIFF" &&
  String(data[9:12]) == "WEBP"` — placed before the fallback error (the
  30-byte floor is RIFF + size + WEBP + one empty chunk; shorter
  payloads fall through to the existing "Unsupported image file
  format").
- Encode dispatch: `encodeImage(image, WebpFormat)` →
  `encodeWebP(image)` with no keyword arguments; `writeFile(*.webp)`
  already routes to `WebpFormat` (T008); `decodeBase64` accepts
  base64 WebP payloads from the new `decodeImage` branch.

### 3.2 Decode

- Header features via the provider's `WebPGetFeaturesInternal` (libwebp
  decoder ABI): failure raises a named `ArgumentError` (invalid WebP;
  the exact message is pinned by the T032 tests).
- **Animation is rejected before pixel decode**: `has_animation != 0`
  raises `ArgumentError("WebP animation is not supported")`. The guard
  is mandatory, not a nicety: `WebP.decode` on an animated file crashes
  the Julia process at C level — uncatchable from Julia (reproduced on
  the pinned fixture, §6).
- The provider auto-selects `RGB{N0f8}` or `RGBA{N0f8}` from
  `has_alpha`; both arrive indexed `[row=y, col=x]`.
- Straight → premultiplied uses the house formula
  `premul8 = (s8 * a8 + 127) div 255` (same as the PNG path); RGB input
  becomes `a8 = 255`.
- `decodeWebPDimensions` reports the feature dimensions without decoding
  pixels and does **not** reject animation (the dimensions are still the
  canvas size); the named error binds on pixel decode.

### 3.3 Encode

- Premultiplied → straight, per channel: `a8 > 0` →
  `s8 = min(255, (p8*255 + a8 div 2) div a8)`; `a8 = 0` → `0` (the format
  leaves color under full transparency unspecified — the §3.5 policy
  matches that).
- Always encoded as RGBA (Vetra images always carry an alpha channel; a
  fully opaque image encodes with `a = 255`). The provider picks the
  chunk types: VP8L for lossless, VP8 + VP8X for lossy-with-alpha.
- `quality` is **lossy only**, 0..100 (the provider's range and default;
  out of range raises the provider's named error). Lossless ignores
  `quality` (the provider API has no lossless quality parameter) —
  documented, not an error.
- Dimensions: 1..16383 per side (the libwebp limit); out of range
  raises a named `ArgumentError` (message pinned in T032). The check
  is required: at 16384 the provider **silently returns an empty
  vector** (verified: 16384×4 → 0 B, no error) — writing that to disk
  would be an empty, unparseable file.
- Output is a RIFF container: `RIFF` + little-endian file size − 4 +
  `WEBP` + chunk table; T032 tests walk the chunk table by hand
  (fourcc + size per chunk, contiguous to the file end).

### 3.4 Errors

- `WebP` absent → `_requireWebP()` install hint (T032 adds the
  `_requireWebP` helper — lazy discovery per D028 — the `[extras]`
  entry, and the codec-loading tests).
- Invalid or truncated WebP → the named `ArgumentError` from the feature
  scan, raised **before** the crash-prone decode.

### 3.5 Lossless vs lossy validation policy

No independent WebP decoder exists on the verification machine (checked
2026-11-09: no ffmpeg, cwebp, dwebp, ImageMagick or PIL; PyMuPDF
refuses WebP — "Failed to open file … as type webp"). Pixel ground truth
for *decode* therefore comes from pinned third-party fixtures (§6), and
*encode* is validated by round-trip policy:

- **Lossless RGBA round-trip**: alpha exact on every pixel; RGB exact on
  every pixel with `α > 0`; RGB where `α = 0` is **unspecified** (VP8L
  preserves alpha exactly but approximates color under full
  transparency — measured 81/3072 mismatches, all inside the α=0
  corner, e.g. `r 0.875 → 0.859`, §6). Tests assert exactly that
  partition, not whole-image equality.
- **Opaque (α = 255) lossless round-trip**: byte-exact (measured
  0/3072 mismatches).
- **Lossy**: dimensions exact; PSNR floor on the fixed smooth gradient
  at `quality = 75`: ≥ 35 dB (measured 37.67 dB; q95 45.11, q50 36.63,
  q10 31.99); no byte expectation. Out-of-range quality raises the
  provider's named `ArgumentError("Quality $q is not in the range from
  0 to 100.")` (verified q −1 / 101).
- **Fixture decode**: exact dimensions per §6; no pixel assertions
  (recorded limitation — no second decoder).

## 4. Codec loading, tests, and docs (both tasks)

- **Present/absent + cache reuse** (D019 protocol,
  `test/codec_loading_tests.jl` extended in T032): in the absent
  environment the new entry points raise the install hint while the core
  loads; in the codec-enabled environment sharing the depot cache, the
  round-trips run with no stale-cache skip. T031 adds no loading
  mechanism (JpegTurbo is already in the protocol).
- **Dispatch coverage**: magic-byte branches (JPEG SOI existing;
  RIFF+WEBP new), extension routing (`.jpg`/`.jpeg`/`.webp`),
  `encodeImage` format dispatch, `decodeBase64` magic dispatch
  (WebP from T032; `encodeBase64` stays PNG-only, upstream parity).
- **COMPATIBILITY.md**: T031/T032 replace the "raise, as upstream" /
  "not implemented" lines with implemented rows + evidence; GIF write
  stays raised (D014, unchanged by this contract).
- **API.md**: `encodeJPEG`, `encodeWebP`, `decodeWebP`,
  `decodeWebPDimensions` entries; the "JPEG/GIF writing and WebP are
  unsupported" line becomes provider-requirement wording.

## 5. Out of scope (v1)

- Progressive JPEG, EXIF/Adobe/ICC writing, orientation preservation on
  encode — provider capabilities the contract does not use; no API
  surface is added for them.
- WebP animation, extended chunks (ICC_PROFILE, XMP), multiframe.
- Non-PNG base64 data-URL encoding (`encodeBase64` is PNG-only, as
  upstream; decoding any format is already the `decodeBase64` behavior).
- GIF encoding (remains deferred per D014).
- Keyword arguments on `encodeImage`/`writeFile` (upstream parity):
  quality/background/lossy are on the named entry points only.

## 6. Evidence (probe log, 2026-11-09)

Scratch environment `/tmp/opencode/codecprobe` (fresh `Pkg.activate`,
Julia 1.13.3; exact commands in the task record):

- **JpegTurbo 0.1.6 / JpegTurbo_jll 3.2.1+0** — `jpeg_encode` verified
  on a fixed 64×48 gradient: q92 → 1069 B, q10 → 742 B, SOI `ffd8`, EOI
  `ffd9`. All four header variants written and parsed back: default
  JFIF (units=0, 1×1), `write_JFIF_header = false` (first marker `ffdb`
  = DQT), JFIF units=1 72×72, JFIF units=2 28×28 — SOF0 64×48 in each.
  Self round-trip max channel delta 3; PSNR(q92) 48.78 dB. Oversize
  bisect: 30000/60000/65500 OK; **65501 segfaults** in
  `jinit_compress_master` (→ the §2.4 boundary check is mandatory).
- **WebP.jl 0.1.3 / libwebp_jll 1.6.1+0** — `encode` on RGB/RGBA ×
  lossless/lossy → correct containers (VP8L / VP8 / VP8X chunks,
  `RIFF`+`WEBP`); `decode` auto-detects alpha; lossless opaque
  byte-exact; lossless with alpha exact except the α=0 corner (81/3072,
  e.g. `r 0.875 → 0.859`). `quality` is lossy-only in the provider API
  (lossless encodes ignore it); lossy PSNR on the fixed gradient:
  q75 = 37.67 dB (q95 45.11, q50 36.63, q10 31.99). Oversize:
  16384×4 → **0 B, no error** (silent provider failure → the §3.3
  boundary check).
- **Animation** — `Simple_Animated_Clock.webp` (211×211, `has_alpha = 1`,
  `has_animation = 1`): the features scan detects it; `WebP.decode`
  **crashes the process** at C level (uncatchable) → the §3.2 guard.
- **Interop** — PyMuPDF 1.28.2 (venv `/tmp/opencode/pmupdf`): mupdf
  page rect follows JFIF density — units=0/1×1 and no-JFIF both give
  48×36 pt for the 64×48 file (the 96-dpi assumption), while units=1
  72×72 and units=2 28×28 give 64×48 pt → the 72 dpi JFIF contract
  (§2.3). At 72 dpi the pixmap is exactly 64×48 RGB and the max channel
  delta vs `JpegTurbo.jpeg_decode` is 4 (no pixel > 8). mupdf refuses
  WebP.
- **Pinned fixtures** (URL, byte size, sha256; fetched 2026-11-09):
  - `https://www.gstatic.com/webp/gallery/1.webp` — 30320 B,
    `4a5afeaff8483923da964bc7896f02d0283e8bff99b5b8f82a31ae3214dab1d0`,
    lossy VP8, 368×550, no alpha (Google's canonical WebP gallery).
  - `https://www.gstatic.com/webp/gallery3/1_webp_ll.webp` — 81836 B,
    `49a902b9c35bd2031bf26234c59ff369dd3ae18a3b58247285104a23346ba2d4`,
    lossless VP8L, 301×400, with alpha.
  - `https://upload.wikimedia.org/wikipedia/commons/f/f8/Simple_Animated_Clock.webp`
    — 600504 B,
    `c020aacdd11922051d2d509a8a31f1e0edfb8bc9113689923fb638e4a9cdb886`,
    animated VP8X, 211×211 (the error-path fixture).
  Fixture placement follows the T029 protocol: bytes + URL + sha256
  recorded in the fixture meta, verified by tests.
