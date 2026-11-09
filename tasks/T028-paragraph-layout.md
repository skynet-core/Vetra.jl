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

Status: done (2026-11-09). Implemented `src/formats/paragraph.jl` (additive,
zero new dependencies; LTR only) and `withFallback` in `src/formats/fonts.jl`;
`test/paragraph_tests.jl` (22,760 assertions) registered in
`test/runtests.jl`; cookbook recipe 12 (`paragraph-card.png`, 14 gallery
items). Full gate green: **96.29% coverage (7013/7283)**; every legacy
suite (incl. T009 fonts/text 2456, T010 context 4965) byte-unchanged.

### Public API

- `newParagraph(text, font; ...)` / `newParagraph(spans; ...)` → `Paragraph`
  (spans, width, height, lineHeight, hAlign, vAlign, overflow, dir).
  `width`/`height` 0 = unconstrained. RTL raises
  `ArgumentError("RTL requires the T029 shaper")`.
- `layoutParagraph(p)` → `ParagraphLayout` (paragraph, clusters, lines,
  the underlying `Arrangement`, per-cluster rune ranges).
- `paragraphMetrics(l)` → `ParagraphMetrics(width, height, lineCount,
  maxAscent, minDescent)` (unclipped layout facts).
- `fillParagraph` / `strokeParagraph` on `Image` and `Context` targets.
- `withFallback(tf, chain)` → new `Typeface` (cycle-checked).

### Feature subset delivered (vs T027 §2)

- **Layout pass = the pinned `typeset`** (reuse, not reimplementation):
  absolute `lineHeight` applied by copying each run's `Font`; alignment
  forced to Left/Top on zero dimensions (§2.5 amendment).
- **Box/overflow**: `ClipOverflow` (default) — drawing is clipped to the
  box by rendering through a box-sized scratch; `EllipsisOverflow` —
  trailing clusters are dropped (fewest first, re-laid-out per trial) until
  the last line with an appended U+2026 fits; the ellipsis glyph must
  exist in the last kept span's effective font (after fallback) or the
  trial is skipped; if no trial fits, the original layout is returned and
  the clip binds (plain clip). Only the last line ellipsizes (v1).
- **Clusters**: vendored UAX#29 subset (GB3 control sequences, GB9a/9b
  Extend/Mc, GB9d ZWJ, GB8 narrow Hangul) with BMP `Grapheme_Extend` +
  `Mc` tables (Unicode 16.0.0, provenance in the source header). ZWJ joins
  both neighbours; ZWNJ joins left only; one cluster per codepoint outside
  the subset (documented fallback).
- **Fallback**: `withFallback` formalizes the `Typeface.fallbacks` chain
  with cycle detection (base graph + candidates + shared descendants).
  Missing glyph = `.notdef`/zero-advance (pinned engine policy).
- **Metrics**: line box = the pinned vertical pass's used ascent/descent
  (max over runs); `height` = sum of line boxes.

### Contract amendments recorded in docs/TEXT_LAYOUT.md

- §2.1: NBSP is an **ordinary wrap position** (the pinned engine's
  `_canWrap` ≡ `_otIsWsRune`; only U+0020 SPACE is exempt from
  overflow-triggered wrapping). Long unbreakable runs **split
  character-wise at overflow** (not "overflow the box"). Span boundaries
  are not wrap positions.
- §2.5: alignment is effective only on constrained dimensions.
- §2.8: cluster indices are **codepoints** (this build's `String`
  `length`/iteration unit); `String[i]`/`s[a:b]` are byte-based with
  boundary checks, so `paragraph.jl` converts via `_charStarts`.
- §3.1/§3.2: tables provenance fixed to `Grapheme_Extend`/`Mc` from
  `DerivedCoreProperties-16.0.0.txt`/`UnicodeData-16.0.0.txt`; the frozen
  build's stdlib `Unicode` module has no category API and
  `Unicode.graphemes` uses *likely*-grapheme semantics (differs on ZWJ
  attachment), so it is intentionally not used.

### Large-paragraph performance (log `/tmp/opencode/t028-bench.jl`)

Deterministic 20,000-word paragraph (~121 KB text) wrapped at 800 px,
absolute `lineHeight` 20, warm medians, invariants (line count, box
honor, cluster partition) checked before timing:

| stage | wall (median) |
| --- | --- |
| `layoutParagraph` | ~24 ms |
| legacy `typeset` (same spans) | ~14 ms |
| `fillParagraph` (3.28 M ink px) | ~1.14 s |

The paragraph layer adds ~10 ms of cluster/line/metrics work over the
pinned engine; rendering cost is the shared glyph-fill path (same as
legacy `fillText`), dominated by rasterization, not layout.

### Limitations and notes

- Unshaped scripts (Arabic/Indic) draw without joining/positioning;
  RTL raises a named `ArgumentError` (T029). These are documented v1
  limits, not claims of general Unicode support.
- `EllipsisOverflow` only fires when the last line's content exceeds the
  box (character-wise splitting means most wrapped text never overflows
  horizontally); the common case is `ClipOverflow`.
- The cluster→line assignment anchors control-only clusters (e.g. a lone
  `\t`) to the neighbouring retained rune's line.
- Frozen-build quirks handled: `String` codepoint `length` vs byte
  `[]`/slicing (via `_charStarts`), `IdSet` for typeface identity,
  soft-scope accumulation in the cookbook moved into functions.
- No new dependencies; LTR only.

Next: T030 (JPEG/WebP codec contracts) is the first ready task. T029
remains blocked on the provider decision (D031 §6). T019 awaits an
explicit publication request.
