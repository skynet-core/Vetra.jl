# T016 — Automatic notebook image display

Status: see [TASKS.md](../TASKS.md). Dependencies: T013. Priority: adoption.
Goal: evaluating an Image displays it naturally in IJulia and Pluto.

## Inputs and scope

Read src/formats/png.jl, Vetra.__init__, test/codec_loading_tests.jl, and the
TutorialFigure adapter in docs/tutorial.jl. Add the smallest standard Julia MIME
display integration using the existing optional PNG encoder; no notebook package
or graphics backend becomes a runtime dependency.

## Acceptance criteria

- PNG-enabled sessions support `show(io, MIME"image/png"(), image)` and rich
  notebook display. Text display remains concise and useful.
- Define truthful `showable`/fallback behavior when PNGFiles is absent; plain
  REPL display must not trigger a codec install error or install packages.
- Binary MIME output decodes to the expected dimensions/pixels, does not mutate
  the image, and works after core-only precompile-cache reuse.
- Verify saved output in IJulia and Pluto; record an unavailable frontend as an
  unmet check rather than calling MIME serialization an interactive UI test.
- Replace the tutorial-only image wrapper where the new display makes it
  redundant, and rebuild Markdown/notebook outputs with inline images.

## Validation

Use the [shared validation](../docs/ROADMAP.md#shared-validation). Add present/
absent-codec subprocess tests and test the MIME stream independently. Execute
the tutorial generator plus minimal IJulia/Pluto examples in their own envs.

## Results and handoff

Status: done (2026-11-07).

- `src/formats/png.jl`: `Base.show(io, ::MIME"text/plain", image)` prints a
  one-line "Vetra image: WxH premultiplied RGBA" (the default struct display
  dumped the whole buffer); `Base.show(io, ::MIME"image/png", image)` writes
  `encodePNG` bytes; `showable` reports `true` for text always and for PNG
  only when PNGFiles is loaded (D014/D019 pattern), so core-only notebooks
  fall back to the text display instead of erroring.
- `docs/tutorial.jl`: the `TutorialFigure` adapter (and its prose) is gone;
  chart cells now end with the bare `Image`, displayed natively.
- `test/notebook_display_tests.jl` (11 assertions, in runtests): showable,
  MIME bytes == `encodePNG`, independent decode-back equality (opaque),
  non-mutation, concise text display, plain `show` dispatch.
  `test/codec_loading_tests.jl` core-only subprocess now asserts
  `showable(MIME("image/png"), image) === false` / text `=== true`.
- Independent Jupyter verification (nbclient 0.11 from
  `/tmp/opencode/tutorial-jupyter`, julia-1.13 IJulia kernel): a 1-cell
  notebook ending in `img` produced `execute_result` with mime keys
  `['image/png', 'text/plain']`; the base64 payload decoded to 191 bytes with
  a valid PNG signature; executed copy in `/tmp/opencode/t016-nb/`. Pluto was
  not installed and is not verified (recorded, per the task's allowance).
- `julia --project=docs docs/make_tutorial.jl` rebuilt both outputs with the
  two chart figures now rendered by the native display;
  `scripts/check.jl` green: 811,472 assertions, 97.97% (5462/5575).
  Log: `/tmp/opencode/t016-check.log`.
- Note: this build stores MIME method parameters as `MIME{Symbol(...)}`;
  `MIME("image/png")` equals the literal `MIME"image/png"()` (verified), so
  both forms dispatch to the same methods.

Limitations: Pluto unverified; display of non-opaque images round-trips
through straight alpha (PNG semantics, documented). Next ready: T017,
T020, T023, T027, T030.
