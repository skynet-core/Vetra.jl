# Recording contract (T023, D030)

Status: **design only**. No symbols in this document are exported until
T024/T025/T026 implement them (D011: planned APIs live in the docs, not in
`export`). Raster behavior is unchanged by this contract.

Goal: the smallest coherent geometry-recording contract — record supported
drawing operations once (a display list), replay them on the CPU into
`Image`s, and export them as SVG/PDF — without a plugin registry, scene
graph, or GUI engine.

## 1. Recording model

A recording is a **list of core-kernel invocations** in call order, not a
list of `Context` method calls. The kernels are the vector-level operations
the immediate pipeline already composes from `Context` calls:

| kernel | recorded as |
| --- | --- |
| `fillPath(image, path, paint; transform, windingRule)` | `FillOp(path, paint, tform, windingRule)` |
| `strokePath(image, path, paint; transform, …)` | `StrokeOp(path, paint, tform, width, cap, join, miterLimit, dashes)` |
| `draw(image, src; tform, blendMode)` (what `drawImage` lowers to) | `DrawImageOp(image, imageMat, blend)` |
| `applyOpacity` on a layer (the `globalAlpha` wrapper) | `GroupOp` opacity field |
| `saveLayer`/`restore` (layer compositing) | `GroupOp` start/end pair |

`Context`-level wrappers fall out of these primitives: `fillRect`/`strokeRect`
record as rect-path fill/stroke ops; `drawImage` records as an `ImagePaint`
fill (the Context computes the same `imageMat = ctx.mat * translate * scale`
it uses today); the `globalAlpha ≠ 1` wrapper records as a group with the
opacity; `clip` records as a cumulative vector clip on the current group.

Why kernel-level (not `Context`-call-level) recording:

- **CPU replay is byte-parity by construction.** Replay re-executes exactly
  the kernel calls the immediate pipeline would have made, in the same
  order, so replay into a default-size image equals direct drawing for the
  same scene (T024 acceptance: fixture-backed A/B dumps, as in T022).
- **Export is a mapping problem**, not a re-derivation: each op maps to
  SVG/PDF syntax (§5–§6). There is no second semantics layer to keep in
  sync with `src/context.jl`.

## 2. Public API proposal (implemented in T024–T026)

```julia
# T024
PictureRecorder(width::Int, height::Int)   # one-shot; logical canvas size
r.ctx::RecordingContext                    # the drawing surface
finishRecording(r::PictureRecorder) -> Picture  # consumes r (further use throws)

struct Picture
    ops        # immutable op list (layout documented in T024)
    size::Vec2 # logical canvas, Int components
end

drawPicture(image::Image, picture::Picture; tform::Mat3 = mat3())

# T025
writeSvg(file::String, picture::Picture; rasterFallback::Bool = false) -> String
# T026
writePdf(file::String, picture::Picture; dpi::Float32 = Float32(96),
    rasterFallback::Bool = false) -> String
```

`RecordingContext` mirrors the existing `Context` surface used by drawing:
`fill`, `stroke`, `fillRect`, `strokeRect`, `clearRect`, `drawImage`
(all overloads), `clip`, `save`, `restore`, `saveLayer`,
`fillText`, `strokeText`, `measureText`, the transform methods
(`translate`, `scale`, `rotate`, `transform`, `setTransform`,
`getTransform`, `resetTransform`), and the state fields (`fillStyle`,
`strokeStyle`, `globalAlpha`, `lineWidth`, `lineCap`, `lineJoin`,
`miterLimit`, `lineDash`, `font`, `fontSize`, `textAlign`, `textBaseline`).
Signatures match `Context` (including the T014 `Real` boundary convention,
applied in T024 to the recording context the same way).

Coordinate space: 0-based continuous `Float32`, y-down (D011). The recorder
does not allocate a pixel buffer at record time — recording cost is the op
list plus the snapshots (§3).

## 3. Snapshots, lifetime, ownership

At the record boundary, each op stores **deep copies**:

- `Path`: `copy(path)` (the flat command buffer) — later `moveTo`/`lineTo`
  on the source path does not affect the recording.
- `Paint`: `copy(paint)` (gradient arrays deep-copied); for `ImagePaint`
  the referenced image is additionally copied (`copy(image)`), so the
  recording is self-contained: mutating or freeing the source image after
  `finishRecording` is safe.
- Stroke settings: value types (width, caps, joins, miter limit, dash copy).
- `globalAlpha`, `tform`: values at call time (snapshot model — no
  separate state-change ops).
- Text: `typeset` + `computePaths` run **at record time**; the op stores
  the glyph outline `Path`s (one per span) with the effective solid paint.
  Replay and export never need the font file, the `Typeface`, or metrics.
- Clips: each clip stores `copy(path)` + `windingRule`; the effective clip
  list of a scope is referenced by subsequent ops in that scope (cumulative
  intersection, image coordinates — the raster `clip` ignores the context
  transform, and so does the recording).

Lifetime rules:

- `PictureRecorder` is one-shot: `finishRecording` returns the `Picture` and
  the recorder becomes unusable (state documented; reuse throws
  `ArgumentError`).
- `Picture` owns everything it references; it is immutable.
- No global mutable state: two recorders may record concurrently (op lists
  and snapshots are independent allocations).
- Deterministic ordering: ops append in call order; nested groups flatten
  depth-first; `restore` emits the group-end op at its call position.

## 4. Replay (`drawPicture`)

- Default size: `drawPicture(img, picture)` with `size(img) == picture.size`
  re-executes the kernel list with identity canvas mapping — byte-identical
  to direct CPU drawing of the same scene.
- Scaling: if the target image differs in size, the **logical canvas is
  scaled in vector space** by `(imgW / picW, imgH / picH)` (independent
  axes; aspect change allowed) before replay. Geometry and coverage are
  re-rasterized at the target resolution — replay is never an enlargement
  of an already-rasterized image (T024 acceptance). The `tform` keyword
  composes on top of the canvas mapping.
- Replay targets may be any `Image`; premultiplied storage, rounding, and
  blend semantics are the existing kernel contract (unchanged).

## 5. Record-boundary errors (fail fast, no partial op)

The recording context raises `ArgumentError` **at the unsupported call**,
before appending an op, with the message naming the command:

- `TiledImagePaint` as `fillStyle` — tiling has no bounded vector
  representation; v1 records solid, image, and gradient paints only.
  (CPU raster still supports it; recording is the stricter surface.)
- Non-solid `strokeStyle` — the raster stroke contract is solid paints
  only; recording mirrors it instead of inventing gradient strokes.
- `fillText`/`strokeText` with an unloaded `ctx.font` — same boundary as
  the raster `fillText`.

Everything the raster `Context` accepts otherwise (all 20 blend modes as
fill paint modes, masks-family blends, partial opacity, degenerate-but-
finite gradient stops per the T022 contract) records successfully. Export
support is a separate matrix (§6): an op that records fine may still be
unexportable in v1, which is an **export-time** decision, not a
record-time one.

## 6. Export capability matrix (v1)

Shared error contract: default is **strict** — the writer scans the op
list first; the first unexportable op raises `ArgumentError` (op index +
command + reason) and **no file is written**. `rasterFallback = true`
instead renders the whole picture to an image at the requested size and
emits a single full-canvas embedded image (documented: the output is a
raster, not editable; no per-op vector content). Never silent loss.

### 6.1 SVG (T025)

Document: standalone `<?xml?>` + `<svg width height viewBox>` (viewBox pins
the logical units = pixels), all elements in op order.

| element | v1 | mapping |
| --- | --- | --- |
| solid fill, NormalBlend | ✓ | `<path fill fill-opacity>` (hex or `rgba()` — reader-compatible) |
| linear gradient fill, NormalBlend | ✓ | `<linearGradient gradientUnits="userSpaceOnUse">`, stops from `gradientStops` |
| radial gradient fill, NormalBlend | ✓ | `<radialGradient>` with `rx/ry` + `gradientTransform` for the elliptical skew (derived in T025) |
| angular gradient fill | ✗ | no conic fill in SVG 1.1/2 → strict error / fallback |
| solid stroke (any cap/join/miter/dash) | ✓ | `stroke`, `stroke-width`, `stroke-linecap/-linejoin`, `stroke-miterlimit`, `stroke-dasharray` |
| transforms | ✓ | `transform="matrix(…)"` (the recorded op tform) |
| clips (cumulative) | ✓ | one `<clipPath>` per scope with all clip subpaths (SVG intersects multiple children) |
| layers (saveLayer/restore) | ✓ | nested `<g>` |
| group opacity (globalAlpha) | ✓ | `<g opacity>` — SVG group opacity is group-unit compositing, matching the raster layer+applyOpacity wrapper exactly |
| images (drawImage) | ✓ | `<image>` with `href="data:image/png;base64,…"`, `preserveAspectRatio="none"` for the src-rect/dst-rect case |
| text | ✓ | glyph outline `<path>`s (no `<text>` — viewer font availability is non-deterministic) |
| clearRect | ✗ | static SVG composition has no eraser → strict error / fallback |
| non-Normal blend modes | ✗ | v1 does not emit `mix-blend-mode` (renderer support varies); mapping is a documented follow-up, not a silent guess |

Dependencies: string output only (no new package). PNG embedding needs
`PNGFiles` (existing opt-in, D014); if absent, image ops raise the install
hint, not a silent drop. Read-back verification uses the existing pinned
SVG reader (supplemental — it skips text and requires gradients as direct
`<g>` children, so the exporter emits that shape).

### 6.2 PDF (T026)

Document: single-page PDF 1.4, content units = picture units mapped to
points via `dpi` (page size = `picture.size * 72 / dpi` pt). The page
content stream is wrapped in one root Form XObject with
`/Group /S /Transparency` so a transparent page renders transparent.

| element | v1 | mechanism |
| --- | --- | --- |
| solid fill/stroke, NormalBlend | ✓ | path operators + `rg`/`RG`/`g`/`G`; opacity via ExtGState `ca`/`CA` |
| linear gradient | ✓ | `/ShadingType 2` axial shading (function `/FunctionType 2`) |
| radial gradient (incl. elliptical) | ✓ | `/ShadingType 3`; the elliptical case is drawn under a CTM that maps the ellipse to a unit circle (path + shading in the same transformed space; derived in T026) |
| angular gradient | ✗ | no conic shading in the PDF spec → strict error / fallback |
| transforms | ✓ | CTM (`cm`) |
| clips (cumulative) | ✓ | successive `W n` clip-path operators (intersecting) |
| layers + group opacity | ✓ | Form XObjects with `/Group` (group-unit, matching raster layer compositing) |
| images | ✓ | `/DeviceRGB` XObject, `/FlateDecode` via stdlib `Compression.jl` (no new dependency, no opt-in); premul → straight at the boundary |
| text | ✓ | glyph outline paths (same policy as SVG) |
| clearRect | ✗ | no erase operator in v1 → strict error / fallback |
| non-Normal blend modes | ✗ | v1 is normal compositing only → strict error / fallback |

Dependencies: **none new** — stdlib `Compression` for `FlateDecode`
(zlib format, which is exactly what `Compression.compress` emits). No
font embedding anywhere (text is outlines), so no font licensing surface.
`qpdf --check` (structural) plus an external renderer (mupdf `mutool draw`
or Ghostscript, validation tooling only) are the independent references;
neither is a package dependency.

## 7. Why this does not disrupt the immediate API

- `Context`, the kernels, and all existing entry points are untouched;
  recording is opt-in via `PictureRecorder`.
- Nothing requires already-rasterized images to become vectors: vectors
  come from the recorded ops; `Image`s enter the recording only as
  embedded bitmap payloads (drawImage / ImagePaint).
- The D007 backend seam is extended, not bent: a display list is exactly
  "per-pixel operations a backend executes" with the CPU backend as
  reference — a future GPU adapter can consume the same op list without
  touching this contract (a design note, not a T024 promise).

## 8. Canonical validation scenes (independent references for T024–T026)

Five scenes, each hand-derived before implementation (never from the code
under test). They are the acceptance references for the three
implementation tasks:

1. **Activity card** (the tutorial's chart shape): opaque background rect,
   dashed grid lines, translucent candle fills + opaque strokes, axis text
   labels. — records every v1 op kind at least once.
2. **Transformed/clipped path**: `setTransform(translate·rotate·scale)`,
   circular `clip`, even-odd rect-with-hole filled with a diagonal linear
   gradient. — pins op tform snapshot, cumulative clip in image
   coordinates, gradient under transform.
3. **Overlapping translucent layers**: `saveLayer`, two overlapping 50%-
   opacity fills, `restore`, then a `globalAlpha = 0.5` stroke. — pins
   group semantics (layer isolation + group-unit opacity) against direct
   drawing.
4. **Image scene**: positional `drawImage` and src-rect/dst-rect
   `drawImage` over a radial gradient background. — pins image snapshot
   copies and the export embedding paths.
5. **Glyph text**: `fillText` + `strokeText` from a pinned TTF with mixed
   `textAlign`/`textBaseline`. — pins record-time outline conversion.

Per-task acceptance:

- **T024**: replay of scenes 1–5 into a default-size image is byte-identical
  to direct CPU drawing (raw-byte A/B dumps, T022 method); scaled replays
  have hand-derived geometry/coverage expectations; unsupported commands
  (TiledImagePaint fill, gradient strokeStyle) raise at the record boundary
  with no op appended; recording cost vs repeated replay vs direct drawing
  is benchmarked and recorded; all new tests in `test/runtests.jl`.
- **T025**: output of scenes 1–5 parses as XML (independent structure
  check), renders with a pinned external SVG renderer (hand-derived
  coordinates exact for simple geometry; AA tolerances justified before
  evaluating complex content), and reads back through the existing Vetra
  SVG reader as a supplemental check. Scene 4's angular-gradient and
  clearRect variants prove the strict error contract (no file written).
- **T026**: output of scenes 1–5 passes `qpdf --check`, renders in an
  external PDF renderer with hand-derived page-size/geometry checks,
  demonstrates scale independence (same vector at two `dpi` values →
  proportional output), and proves the strict error contract for the
  unsupported rows of §6.2.

## 9. Sources

- Existing contract inputs: D007 (backend seam), D011 (API shape, the
  reserved `Picture`/`PictureRecorder` seam), `docs/API.md`
  (Context state/clip/layer semantics, paint copying, text),
  `src/context.jl` (`fill`/`stroke` globalAlpha wrappers L438–518, `clip`
  L528–544, `clearRect` L551–565, `drawImage` L607+), `src/paths.jl`
  (flat command buffer + `Base.copy`), `src/paints.jl` (`Base.copy`),
  `src/formats/fonts.jl` (`typeset`, `computePaths`),
  `docs/tutorial.jl` §9–11 (the limited tutorial SVG writer its lessons —
  two-decimal coordinates, hex colors, viewBox — are reused, not its
  implementation), T008 (pinned SVG reader subset).
- Export references: W3C SVG 1.1/2 (path data, `clipPath`,
  `linearGradient`/`radialGradient`, `image`, `g opacity`); ISO
  32000-1:2008 §8 (paint), §10.5 (XObjects/Form), §11.6 (shadings),
  transparency group rules; resvg (MIT, external renderer candidate for
  T025 — supports the v1 SVG subset, its `mix-blend-mode` gaps match the
  v1 NormalBlend-only decision); qpdf + mupdf/Ghostscript (T026
  validation tooling only).
