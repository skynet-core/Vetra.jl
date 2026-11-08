# T021 — Package and first-render latency

Status: see [TASKS.md](../TASKS.md). Dependencies: T020.
Goal: improve time to a useful image in scripts, notebooks, and short-lived jobs.

## Inputs and scope

Use T020's separate load/compile/render measurements. Inspect src/Vetra.jl
initialization, optional-codec discovery, and type specialization. Try the
smallest measured loading/precompile changes first; a custom sysimage must not
be required for ordinary users. Record a dependency decision before adding any
precompile package. Preserve D019 optional-codec cache behavior and error hints.

## Acceptance criteria

- Demonstrate a repeatable improvement against T020's recorded latency target
  for core-only and/or the identified codec-enabled bottleneck, without moving
  equivalent cost to an unreported installation or first-use stage.
- Report startup, precompile time/cache size, first render, and steady-state
  effects separately; keep allocations and loading correctness visible.
- Core-only loading and optional-codec reuse tests pass. Package installation
  never downloads reference fonts/assets or runs a tutorial workload implicitly.
- Retain only supported, Julia 1.10-compatible changes with reproducible evidence;
  if no candidate meets the target, report findings and leave the target open.

## Validation

Run [shared validation](../docs/ROADMAP.md#shared-validation) and T020's cold/
cached process protocol before and after, at least three independent runs.
Exercise absent/present-codec cache orders and measure the existing warm harness.

## Results and handoff

Status: done (2026-11-07). Target met: repeatable first-render and load
improvement, cost moved to the reported install/precompile stage.

### Diagnosis (fresh-process decomposition, before changes)

- `using Vetra` in a codec-enabled env (docs): ~580 ms. Core-only env:
  ~9 ms. The difference is D019's eager `__init__` loop requiring every
  present optional package: JpegTurbo ~371 ms + PNGFiles ~257 ms + XML
  ~7 ms + ColorTypes ~0 ms (measured per package).
- First render of a trivial 256x256 scene: ~2.5 s — JIT compilation of the
  draw pipeline (mask/rasterizer/text) on the first `fillRect`/`stroke`
  call, regardless of argument types or call context (top-level, named
  function, or closure).
- Warm render: ~38 ms.

### Changes

1. **Lazy codec discovery** (supersedes D019's eager loop): `__init__` no
   longer requires optional packages; each `_require*` does
   `Base.locate_package` (never loads) + `Base.require` on first use;
   install hints unchanged; `Base.showable(MIME"image/png")` is now a
   locate-only check (no load side effect). Bonus: adding a codec at
   runtime now works without a restart (D019 required restart).
2. **World-age safety**: `Base.invokelatest` at every call that can cross a
   lazy-require boundary — `png.save` (encodePNG), `xml.parse`
   (parseSvg), the ColorTypes kernels (`toColors`/`fromColors`). Without it,
   a method instance compiled before the in-call `require` fails with
   "method too new" (observed: fresh-process `encodePNG` after `using
   Vetra`). Decode paths already used `invokelatest` (T012-era).
3. **Precompile statements** (16 common entry points: `Context`, `newImage`,
   `fillRect` x2, `fill`, `stroke`, `strokeSegment`, `fillText`,
   `measureText`, `drawImage`, `save`, `restore`, `saveLayer`, `clip`,
   `getColor`, `encodeImage`) at the end of `src/Vetra.jl` — moves the
   first-render JIT to precompile time. No sysimage, no new dependency.

### Before/after (T020 protocol: 3 cached + 1 cold fresh-process run)

| stage | before (T020) | after | ratio |
| --- | --- | --- | --- |
| cached package load | 579–587 ms | 19–20 ms | ~29x |
| first render (256x256) | 2468–2548 ms | 28–32 ms | ~80x |
| warm render | 38–40 ms | 30–32 ms | ~1.2x |
| total cached process | ~3.3 s | ~0.23 s | ~14x |
| cold-depot total | 4328 ms | 3877 ms | ~1.1x |

Reported install-stage cost (must be paid once per machine):
precompile+load wall 1.7 s -> 3.8 s; cache artifacts .ji 386 KB -> 400 KB,
.so 2.4 MB -> 6.2 MB. Cold-depot first use improves because the precompiled
pipeline offsets the heavier precompile.

Outputs: `benchmark/results/startup_2026-11-07_before.tsv` (T020 baseline,
preserved), `startup_2026-11-07_after.tsv` (+ .meta),
`startup_2026-11-07.tsv` (original). Startup script gains an optional label
argument for unique before/after names.

### Verification

- Full gate `scripts/check.jl`: green, **811,472 assertions, 97.99%**
  (5458/5575). `codec_loading_tests` 2/2 (core-only hints + codec-enabled
  round trip in fresh subprocesses), `notebook_display_tests` 11/11
  (showable locate-only), `colormatrices_tests` 29/29. Logs:
  `/tmp/opencode/t021-gate{,2,3}.log`.
- Fresh-process lazy-path proofs (no preload of the optional package):
  `encodePNG`/`decodePNG` round trip, `parseSvg`, `readImage` (JPEG),
  `toColors`/`fromColors` exact round trip — all pass in one new process.
- Steady-state regression check: app-suite runs r4/r5 vs T020 r1–r3 — all
  workloads within the 3-run spread (e.g. text_card 5.9–10.4–5.5 ms;
  clip_layers 353–321–320 ms); no systematic change. Logs:
  `/tmp/opencode/t021-app-r{4,5}.log`, TSVs `app_2026-11-07_r{4,5}.tsv`.
- Install hygiene: the precompile block performs no file I/O, downloads no
  fonts/assets, and runs no tutorial workloads (compilation only).

### Residual notes for T022

- Steady-state drawing allocation is unchanged (precompile doesn't alter
  per-call allocations): canvas_1080p 26.5 MB, canvas_4k 101 MB,
  clip_layers 182 MB; PNG encode 24.9–38.8 MB @1080p, 124 MB @4K.
- The `boundary_toStraightAlpha` stage (16–22 ms @1080p, 8.3 MB) is now the
  only non-codec part of translucent PNG encoding.

Next ready: T022 (allocations/PNG throughput), T023/T027/T030 (design).
