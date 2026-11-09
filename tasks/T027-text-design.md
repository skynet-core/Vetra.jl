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

Status: done (2026-11-09). Design only (no source changes; the T026 gate
result stands: 96.25%, 6718/6980). Contract in `docs/TEXT_LAYOUT.md`,
decision D031 in `docs/DECISIONS.md`, API proposal in `docs/API.md`
(specified-not-implemented, per the T023 pattern). T028 unblocked (core-only,
zero new dependencies); T029 specified but blocked on the provider
decision (§6 of the doc).

## What was investigated

- **Existing surface (T009/D015)**: `Font` already carries per-run style
  (size, lineHeight, paints, textCase, underline/strikethrough,
  noKerningAdjustments); `Span(text, font)` + `typeset(spans; bounds,
  hAlign, vAlign, wrap)` already wraps on `bounds.x > 0` with explicit
  line breaks; `Typeface.fallbacks` + exported `fallbackTypeface`
  already implement a recursive per-rune fallback chain with ratio-scaled
  advances. T028 is therefore a thin additive layer (box/overflow/
  clusters/metrics/direction-hook), not a reimplementation — and the
  legacy contract is untouched (§10).
- **Package landscape (2026-11-09, General registry, flat
  `<letter>/<name>` layout, full package-name sweep)**: no maintained
  Julia shaping provider in the registry. `HarfKit.jl` and `Pango.jl`
  are **delisted** (verified absent by name and by tree sweep — nothing
  matches `Harf*`, `Pango*`, `Grapheme*`, `Bidi*`, `OpenType*`);
  `FreeType`/`FreeTypeAbstraction` exist (no shaping); `Cairo.jl` exists
  (toy text, no shaping); `BasicTextRender` is a 0.1.0 ImageCore toy.
  The JLL wrappers exist (`HarfBuzz_jll` v8.5.1+0, `Pango_jll`
  v1.58.2+0) but a JLL alone is not a usable Julia API. System:
  `libharfbuzz` shared libraries present (no `hb-shape`/`hb-view` CLI,
  no Pango tools, no Python `gi`).
- **Registry state recorded** in D031 and in the doc §6; the sweep
  method (sparse `git clone --filter=blob:none` + `git ls-tree` name
  sweep) is reproducible from the doc.

## Concrete choices (contract)

- T028 core-only: v1 wrap opportunities = the existing white-space set +
  explicit `\n`; **no UAX#14 mid-word breaking** (recorded shortcut);
  overflow = `ClipOverflow` (default) / `EllipsisOverflow` (U+2026,
  only when the glyph exists in the last run's effective font);
  paragraph-level absolute `lineHeight` with centered baselines;
  styled runs = existing `Span`/`Font`; fallback = `withFallback` over
  the existing `Typeface.fallbacks` chain + `.notdef`/zero-advance
  missing-glyph policy; clusters = vendored UAX#29 subset (GB3/9/97–99,
  ZWJ/ZWNJ, Hangul; BMP-only tables with recorded provenance;
  per-codepoint fallback outside the subset — recorded shortcut);
  cluster advance (v1) = sum of member advances, keeping legacy output
  byte-exact.
- T029 provider-gated: shaper interface (raw font bytes → per-cluster
  GID/advance/offset), GID → outline via additive `glyphPathByGid`
  (direct loca/glyf index — the pinned parser's data is sufficient for
  the mapping; complex-script fonts' GSUB is read from raw bytes by
  options (a)/(b), or needs an additive GSUB-subset reader + explicit
  D015 extension under option (c)); UAX#9 paragraph-level base
  direction with logical→visual permutation exposed; **no provider
  selected** — options (a) re-emerged binding, (b) HarfBuzz_jll + thin
  `ccall`, (c) pure-Julia UAX#9 + GSUB subset, (d) defer are recorded;
  T029 blocked until one is chosen. CFF/TTC/color fonts stay
  unsupported under every option (shaper choice ≠ outline-reader
  change).
- Test fonts: T028 reuses the pinned Roboto/NotoSansJP/Inter fixtures;
  T029 adds pinned **OFL 1.1** Noto Sans Arabic + Noto Sans Devanagari
  (independently licensed; URL+SHA256 to be recorded at fetch).
  Shaping expectations come from a pinned external reference
  (`hb-shape` from a pinned HarfBuzz revision, or an equivalent
  layout engine, or hand-derived UAX#9 steps) — never the code under
  test. Separate acceptance suites: `test/paragraph_tests.jl` (T028)
  and `test/shaping_tests.jl` (T029).

## Worked examples (reviewed in doc §7)

1. Wrapped Latin label (space-wrap, metrics, centering offset).
2. Mixed-size styled runs (shared baseline, per-run paint, line box).
3. Fallback glyphs (ratio-scaled advance; `.notdef`/zero-advance end
   policy).
4. Arabic joining (T029 expectation: joined-form GIDs ≠ isolated cmap
   mapping; T028: isolated forms, named v1 limit).
5. Indic conjunct (T029 ligature GID expectation; T028: separate
   codepoints, named limit).
6. Mixed RTL/LTR (UAX#9 L2 digit runs; T028 raises a named
   `ArgumentError` for RTL).
7. Combining marks (one cluster; v1 sum-of-advances vs T029
   zero-advance override).

## Specifications and versions recorded

UAX #29 (clusters), UAX #9 (bidi), UAX #14 (line breaking — out of v1
scope, shortcut recorded), OpenType (GSUB lookup types 1/5/6/8, GPOS
pair, cmap/hmtx/loca/glyf), Unicode data (`GraphemeBreakProperty.txt`,
`Script.txt`, BMP subset; version pinned at implementation time),
HarfBuzz documentation as reference semantics. Registry/JLL/system
tool versions recorded in §6 above. **No runtime support claims** —
nothing in this task is implemented.

## Unresolved (keeps T029 blocked)

The T029 provider decision (a/b/c/d) plus, for (b), a dependency-policy
decision (binary JLL in an otherwise stdlib-optional codebase), and,
for (c), the explicit D015 extension for the GSUB-subset reader.
