# T028 — Wrapping, styled runs, and font fallback

Status: see [TASKS.md](../TASKS.md). Dependencies: T027.
Goal: render useful multi-line labels and paragraphs through an additive API.

## Inputs and scope

Implement the basic layout portion of T027, using native parsed outlines and
metrics. Cover paragraph width, explicit breaks, documented wrapping rules,
styled runs, alignment, line heights, and ordered font fallback. Reuse existing
Font/Span/Arrangement functionality where it already meets the contract.

## Acceptance criteria

- Existing pinned layout/kerning/text images are unchanged under legacy calls.
- New layout returns usable line/glyph bounds and renders consistently with its
  measurement; support empty text, trailing newlines, narrow widths, long words,
  mixed sizes/styles, missing glyphs, and fallback cycles/termination.
- Tests distinguish grapheme boundaries from code units per T027; document the
  basic path's unshaped-script limitations rather than claiming general Unicode.
- Independent metrics/hand-derived line placement establish expected output;
  actual image tests cover alignment, clipping, and transparency integration.
- Add a text-heavy report/card example and measure large-paragraph performance.

## Validation

Use [shared validation](../docs/ROADMAP.md#shared-validation), all existing font
fixtures, and T027's new independent cases. Execute the paragraph example and
T020 text-heavy benchmarks; record metrics and rendered evidence.

## Results and handoff

Blocked on T027. Record the exact wrapping/fallback feature subset delivered.
