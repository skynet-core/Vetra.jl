# T027 — Paragraph layout and shaping contract

Status: see [TASKS.md](../TASKS.md). Dependencies: T013. Priority: typography.
Goal: define richer text without silently changing the pinned font/layout API.

## Inputs and scope

Read D015, src/formats/fonts.jl, src/fontformats/, Context text state, and the
existing font/layout oracle tests. Specify an additive paragraph/styled-run API
and an optional shaping/bidi integration. Inspect maintained package choices,
version support, and licensing during execution; no provider is preselected.

## Acceptance criteria

- Define width constraints, wrapping opportunities, explicit line breaks,
  overflow, line height, alignment, styled runs, font fallback, and metrics.
- Define grapheme/cluster indices, missing glyphs, script/language/direction,
  bidi ordering, and mapping shaped glyph IDs/advances/offsets to native outlines.
- Keep legacy typeset/measure/render behavior and tests as the default contract;
  identify any necessary explicit extension to D015 before implementation.
- Record whether supported native font data suffices for the selected shaping
  path; CFF/TTC/color fonts do not become supported merely by selecting a shaper.
- Choose independently licensed test fonts and pinned shaping/reference tools.
  Define separate acceptance suites for basic layout (T028) and shaping (T029).
- Provide a feasible minimal dependency/loading strategy, including core-only
  behavior and coverage. Unresolved essential choices keep dependent tasks blocked.

## Validation

Review worked examples: wrapped Latin labels, mixed-size styled runs, fallback
glyphs, Arabic joining, an Indic conjunct, mixed RTL/LTR text, and combining marks.
Record applicable Unicode/OpenType specifications and tool versions; no runtime
support claims until implementation and independent tests exist.

## Results and handoff

Not started. Record the contract/policy decision and concrete integration choice.
