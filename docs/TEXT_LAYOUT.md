# Text layout and shaping contract (T027, D031)

Status: **design only** (T027, 2026-11-09). T028 (paragraph layout, core-only)
is unblocked by this document; T029 (shaping/bidi) is specified by §5–§6 but
remains **blocked on the provider decision** (§6.4). No source changes — the
T026 gate result stands (96.25%, 6718/6980).

Goal: richer text (wrapped paragraphs, styled runs, fallback, shaping,
bidi) without silently changing the pinned font/layout API. Everything here
is additive; the T009 `typeset`/`measureText`/`layoutBounds`/`computePaths`/
`fillText`/`strokeText` behavior and all its tests remain the default
contract.

## 1. What exists today (T009, D015)

- `Typeface` — pinned TTF/glyf subset: cmap 4/12 (platform 3), head, hhea,
  maxp, hmtx, name, OS/2, post, loca, glyf (simple + composite), `kern` v0,
  GPOS pair-positioning (fmt 1/2 via lookup type 2). CFF outlines, TTC
  collections, SVG fonts raise `ArgumentError`. `Typeface.fallbacks`
  (recursive) + exported `fallbackTypeface` already implement a
  per-rune fallback chain; `getGlyphPath`/`getAdvance`/
  `getKerningAdjustment` consult it (advance ratio-scaled to the main
  typeface).
- `Font(typeface, size, lineHeight, paints, textCase, underline,
  strikethrough, noKerningAdjustments)` — the existing styled-run carrier
  (per-run size, line height, paint, case, decorations).
- `Span(text, font)`; `typeset(spans; bounds, hAlign, vAlign, wrap)` —
  layout with wrapping when `bounds.x > 0`, explicit line breaks, per-run
  fonts, `selectionRects` per rune. `layoutBounds`, `computePaths` (one
  path per span, decorations included).
- Context: `fillText`/`strokeText`/`measureText` (single line,
  `textAlign`/`textBaseline`).

Known gaps this contract fills: no paragraph box (width/height/overflow),
no grapheme-cluster indices, no per-paragraph line height/leading, no
metrics object, no missing-glyph policy beyond the typeface chain, no
shaping, LTR only.

## 2. Paragraph API (T028 — core-only, **no new dependencies**)

```julia
struct OverflowPolicy; end
ClipOverflow()      # default: drawing is clipped to the paragraph box
EllipsisOverflow()  # trailing cluster(s) replaced by U+2026 when it fits

struct Paragraph
    spans::Vector{Span}        # styled runs (existing Span/Font)
    width::Float32             # 0 = no wrap (single line)
    height::Float32            # 0 = unconstrained
    lineHeight::Float32        # absolute px, or autoLineHeight
    hAlign::HorizontalAlignment
    vAlign::VerticalAlignment
    overflow::OverflowPolicy
    dir::TextDirection        # LeftToRight in T028; see §5 for T029
end

newParagraph(text::String, font::Font; ...)      # single run
newParagraph(spans::Vector{Span}; ...)           # styled runs

struct Cluster   # grapheme cluster (UAX#29, vendored subset — §3.2)
    span::Int    # 1-based span index
    first::Int   # 1-based char index into that span's text
    last::Int    # exclusive
end

struct ParagraphLine
    clusters::UnitRange{Int}     # cluster range within ParagraphLayout
    ascent::Float32
    descent::Float32
    width::Float32
end

struct ParagraphLayout
    paragraph::Paragraph
    clusters::Vector{Cluster}
    lines::Vector{ParagraphLine}
    arrangement::Arrangement     # the existing typeset output
    # cluster → arrangement rune indices, and advance of the cluster
end

layoutParagraph(p::Paragraph) -> ParagraphLayout
paragraphMetrics(l::ParagraphLayout) ->
    ParagraphMetrics(width, height, lineCount, maxAscent, minDescent)
fillParagraph(image::Image, l::ParagraphLayout)
fillParagraph(ctx::Context, l::ParagraphLayout, x::Real, y::Real)
strokeParagraph(image::Image, l::ParagraphLayout)
```

`layoutParagraph` is implemented as a thin layer over the existing
`typeset` machinery (reuse, not reimplementation): the layout pass runs as
today; the new code adds (a) the cluster pass, (b) overflow/ellipsis,
(c) paragraph-level `lineHeight`/leading and vertical centering, (d)
metrics, (e) the direction hook (§5). Legacy `typeset` keeps its
exact rune-based behavior — cluster indexing is parallel data, not a
replacement.

### 2.1 Width constraint and wrapping

- `width > 0` wraps; `width == 0` forces a single line.
- **Wrap opportunities (v1)**: the existing white-space set
  (`_otIsWsRune` — TAB..CR, SPACE, NBSP… — NBSP is a *no-wrap* space: it
  advances but never breaks), explicit `\n` (hard break), and the end of
  a span. **No mid-word (UAX#14) breaking in v1** — a long unbreakable
  run overflows the box and the overflow policy applies.
  `shortcut: no UAX#14 line-breaking, add when a CJK/justified use case
  lands (T028 follow-up or a new task).`
- Whitespace handling matches upstream: space advances use the font's
  space glyph; trailing space at a line end is excluded from the line
  width (existing behavior).

### 2.2 Explicit line breaks

`\n` starts a new line (existing). An empty paragraph (all whitespace)
lays out one empty line (ascent/descent from the run's font).

### 2.3 Overflow

- `ClipOverflow` (default): `fillParagraph`/`strokeParagraph` clip
  drawing to the box; `paragraphMetrics` reports the *unclipped*
  content size (metrics are layout facts, not rendering facts).
- `EllipsisOverflow`: when the last line overflows, replace trailing
  clusters with U+2026 (one cluster) if the ellipsis glyph exists in the
  last span's effective font (after fallback); if it does not, fall back
  to plain clipping. Only the last line ellipsizes (v1).

### 2.4 Line height and leading

- `autoLineHeight` (default): line box = the run's `Font.lineHeight`
  semantics (existing `autoLineHeight = -1` sentinel, typeface
  `hhea`-derived).
- Absolute `lineHeight > 0`: every line box is exactly `lineHeight` px;
  the line's glyphs sit on the line's baseline, placed at
  `ascent = lineHeight - (maxAscent + minDescent)/2` from the line top
  (vertical centering of the font's used metrics).
- Multi-run lines: the line ascent/descent is the max over its runs;
  all runs share one baseline per line.

### 2.5 Alignment

`hAlign` (Left/Center/Right — existing enums) per line within the box;
`vAlign` (Top/Center/Bottom — existing) for the whole line block within
`height`. Existing `typeset` already implements both; the paragraph
layer keeps them identical.

### 2.6 Styled runs

Runs are the existing `Span(text, font)`: per-run typeface, size,
line-height sentinel, paints, `textCase`, `underline`, `strikethrough`,
`noKerningAdjustments`. Rendering applies each run's `Font.paints[1]`
(fill) or `strokeStyle` (stroke) — no new style machinery. Baseline
sharing across mixed sizes is §2.4.

### 2.7 Font fallback

- The existing `Typeface.fallbacks` chain is the mechanism; v1 adds
  `withFallback(tf::Typeface, chain::Vector{Typeface}) -> Typeface`
  (additive constructor; the field is already mutable) so the chain does
  not depend on poking the struct.
- Missing glyph policy (per codepoint, after span font + chain):
  - glyph found in a fallback typeface → drawn from that typeface,
    advance scaled by `scale(main)/scale(fallback)` (existing
    `getGlyphPath`/`getAdvance` contract).
  - no typeface has the glyph → `.notdef` (GID 0) of the span's own
    typeface when present, else zero-advance (a documented invisible
    gap; no crash, no silent reordering).
- Kerning/GPOS adjustments are zero across typeface boundaries
  (existing `getKerningAdjustment` contract).

### 2.8 Cluster indices

- Cluster indices address *characters* (UTF-8 code units, 1-based,
  `last` exclusive) within a span — the same indexing `String` uses.
  `Cluster` is stable across layout: identical spans + paragraph
  parameters → identical clusters (deterministic, no RNG).
- Cluster advance (v1 core) = the sum of the codepoint advances of the
  members (exactly what `typeset` does today — byte-exact for legacy
  text); T029 shapers override per-cluster advances (§5.2).
- Selection/ellipsis operate on whole clusters (never split one).

### 2.9 Metrics

`ParagraphMetrics(width, height, lineCount, maxAscent, minDescent)` —
`width` = max line width (unclipped), `height` = sum of line box
heights, ascents/desents per §2.4. All Float32, in pixels at the
runs' sizes.

## 3. Grapheme clusters (v1 core)

### 3.1 Scope

UAX#29 (Grapheme Cluster Boundary) is **not** fully re-implemented. The
core implements the subset that keeps real text correct:

- GB3 (never break before/after CR/LF/controlled breaks) — existing
  `_otIsWsRune` + explicit codepoint set;
- GB97–GB99 (do not break before/after combining marks `Mn/Mc/Me`, and
  do not break `Control × Extend` sequences) — the vendored
  Grapheme_Extended_Joinable (`Extend`) + Grapheme_Blocking_Controls
  tables (compact BMP ranges, a few dozen lines) + full Mn/Mc/Me
  property from the Unicode standard library's `Unicode` module where
  available, vendored BMP ranges otherwise;
- GB9 (do not break Hangul `L V*` / `L V* T*`);
- ZWJ/ZWNJ (U+200C/U+200D): no break after ZWJ, break after ZWNJ unless
  followed by Extend/spacing (documented approximation of GB9d/9f);
- everything else (emoji multi-codepoint sequences beyond the above,
  regional indicators, SpacingMark in non-BMP): **one cluster per
  codepoint** (documented fallback; v1 text rendering is unaffected —
  each codepoint still draws with its own advance).

`shortcut: v1 cluster subset (no full UAX#29, no SpacingMark), extend
when a script use case needs it.`

### 3.2 Provenance

Tables are generated from the pinned Unicode version's
`GraphemeBreakProperty.txt` / `GraphemeBreakLikely.txt` (BMP only) and
checked by tests against hand-derived cases (see §7, test font T-F2).
They are data, not code logic: changing the Unicode version is a
recorded test-fixture change, never a silent behavior change.

## 4. Dependency and loading strategy

- **T028**: zero new dependencies, zero new loading surface. Paragraph
  layout is part of the core (fonts are already core per D015).
  Coverage: `test/paragraph_tests.jl` included in `test/runtests.jl`;
  all expectations hand-derived (metrics from the pinned fonts' hmtx/
  hhea tables, cluster cases from §3.2 data) — never from the code under
  test.
- **T029**: opt-in, provider-dependent (see §6). Until a provider is
  recorded, T029 does not ship a loading path; core-only installs are
  unaffected.

## 5. Shaping and bidi contract (T029 — specified, blocked)

### 5.1 Shaper interface

A shaper consumes, per cluster run: the font's **raw file bytes** (the
pinned fixture — not Vetra's parsed subset), the codepoints, a script,
language and base direction; and produces, per cluster:

```julia
struct ShapedGlyph
    gid::Int          # font glyph ID (GID space of the raw font)
    advance::Float32  # in font units, scaled like getAdvance
    xOffset::Float32  # bearing, font units
    yOffset::Float32
end
shaper output: Vector{Vector{ShapedGlyph}}   # per cluster
```

**GID → native outline mapping** (additive, no cmap involved):
`glyphPathByGid(tf::Typeface, gid::Int) -> Path` reads the glyf table by
index (loca → offset → simple/composite, the existing internal reader);
`gid` out of range or 0 → `.notdef`; CFF/TTC fonts (already rejected at
parse) stay rejected. Advances/offsets replace the per-codepoint
advances in `ParagraphLayout` (§2.8); cluster selection rects use the
shaped extents.

### 5.2 Behavior requirements

- **Arabic**: initial/medial/final forms (GSUB contextual
  single-substitution) — the worked example §7.4 must show joined forms
  whose GIDs differ from the isolated codepoint mapping.
- **Indic conjuncts** (§7.5): reordering + half-forms for the pinned
  Devanagari fixture (GSUB lookup types 1/5/6/8 subset as needed by the
  chosen provider — the contract pins *expected output*, not the GSUB
  subset).
- **Combining marks**: zero-advance stacking in the shaped output
  (overriding §2.8's sum-of-advances).
- **Missing glyphs**: the shaper keeps the codepoint; the GID mapping
  falls back to `.notdef` (§5.1) — no silent cluster drop.

### 5.3 Direction (UAX#9)

- `TextDirection ∈ {LeftToRight, RightToLeft}` per paragraph (v1: no
  explicit overrides RLO/LRI inside text — documented limit).
- The shaper/provider receives the base direction; the layout maps
  clusters to **visual order** per UAX#9 (L2E for digit runs, mirror
  punctuation, neutral resolution) before drawing. Cluster indices
  (§2.8) remain *logical*; `ParagraphLayout` exposes the logical→visual
  permutation so selection/ellipsis stay addressable in logical order.
- T028 renders LTR only; RTL paragraphs in T028 raise
  `ArgumentError("RTL requires the T029 shaper")` — an explicit,
  named limit, not silent mis-ordering.

### 5.4 Script/language

v1: script detection from the first non-neutral codepoint of each run
(vendored Script property BMP ranges, same provenance protocol as §3.2);
language defaults to the script's default. No per-codepoint overrides in
v1.

## 6. Provider decision (the T029 gate)

**Registry state (checked 2026-11-09, General tree, flat
`<letter>/<name>` layout):** no maintained Julia shaping provider
exists in the registry. `HarfKit.jl` and `Pango.jl` (the previous
HarfBuzz/Pango bindings) are **delisted**; `FreeType`/
`FreeTypeAbstraction` exist (no shaping); `Cairo.jl` (toy text, no
shaping) exists; nothing matches `Harf*/Pango*/Grapheme*/Bidi*`
(package-name sweep of the full tree). The system has `libharfbuzz`
shared libraries (no `hb-shape` CLI, no Pango tools, no Python `gi`).

Options (none selected — T029 stays blocked until one is recorded as a
decision):

- **(a) Re-emerged/upstreamed Julia HarfBuzz binding** — wait for or
  find a maintained package (the previous ones' repos still exist;
  adoption of a community re-release is acceptable). Pro: standard
  shaper, full UAX#9. Con: availability/Julia 1.10 compat unverified.
- **(b) JLL HarfBuzz + our own thin bindings** — `HarfBuzz_jll`
  (v8.5.1+0 exists in the JLL wrapper registry) + a small `Libc`
  `ccall` surface (hb_buffer, hb_shape, hb_face). Pro: pinned, no
  package risk. Con: binary dependency + FFI surface — a D030-style
  decision is required first (codec dependency policy).
- **(c) Pure-Julia minimal shaper** — UAX#9 core algorithm + a GSUB
  single-substitution/contextual subset sufficient for the §5.2
  behavior list, validated against a pinned external reference
  (protocol §8). Pro: zero dependencies, matches house style. Con:
  largest implementation surface; Indic coverage is the risk.
- **(d) Defer** — T029 stays blocked; T028 ships LTR-only.

**Native font data sufficiency (§acceptance):** the pinned font parser
(TTF/glyf subset, §1) is sufficient for T028 and for the **GID →
outline mapping** of any provider (§5.1 needs only loca/glyf by index,
which exists). Complex-script fonts must additionally carry GSUB data —
option (a)/(b) read GSUB from the raw bytes (no parser change needed);
option (c) needs an additive GSUB-subset reader, which is an explicit
extension to D015 (recorded when (c) is chosen). CFF/TTC/color fonts
remain unsupported under all options — selecting a shaper does not
change the outline reader.

## 7. Worked examples (contract traces; all expectations
independently derived at implementation time)

1. **Wrapped Latin label** — "The quick brown fox jumps" at 16 px,
   width 120, `ClipOverflow`: lines break at the last space that fits
   (hand-derived from the pinned font's hmtx advances); metrics
   `lineCount = 2`, `width = max(line widths)`; a center-aligned line
   is offset by `(120 - lineW)/2`.
2. **Mixed-size styled runs** — spans (14 px, black) + (24 px, blue):
   one line; line box height from the absolute `lineHeight`; the 24-px
   run's baseline shared; per-run paint on render.
3. **Fallback glyphs** — run font Roboto, chain [NotoSansJP]; a
   codepoint absent from Roboto but present in NotoSansJP renders from
   NotoSansJP with the ratio-scaled advance (§2.7); a codepoint absent
   from both renders `.notdef`/zero-advance.
4. **Arabic joining** (T029, option-agnostic expectation) — the
   sequence "كتب" must shape to final/initial/medial forms (GIDs
   ≠ the isolated cmap mapping); without a shaper (T028) the same text
   draws isolated forms — the difference is the documented, named v1
   limit.
5. **Indic conjunct** (T029) — a Devanagari conjunct (e.g. "क + ् +
   ष" → "कष") must shape to the conjunct ligature GID; T028 draws the
   codepoints separately (documented limit).
6. **Mixed RTL/LTR** (T029) — base direction RTL with an embedded digit
   run: digits keep LTR order, the rest reverses per UAX#9 L2; T028
   raises `ArgumentError` (§5.3).
7. **Combining marks** — "e + U+0301": one cluster (§3); v1 core
   advance = sum of member advances (byte-exact legacy); T029
   override = zero-advance mark on the base (§5.2).

## 8. Test fonts and reference protocol

- **T028 fixtures** (existing, pinned): `Roboto-Regular_1.ttf` (Latin),
  `NotoSansJP-Regular.ttf` (fallback/CJK), `Inter-Regular.ttf`.
- **T029 fixtures** (new, independently licensed, OFL 1.1 — same license
  family as the existing Noto fixture, maintained by Google/Notofonts,
  distinct from the ported upstream project): `Noto Sans Arabic` and
  `Noto Sans Devanagari` (Regular), fetched pinned (URL + SHA256
  recorded in the task record; fetched through the
  `scripts/fetch_upstream.jl` pattern into `test/fixtures/`).
- **Shaping reference protocol**: expected glyph sequences/advances
  come from a pinned external reference, never from the code under
  test. Preference order: (1) `hb-shape` built from the pinned HarfBuzz
  revision; (2) any maintained external layout engine (Pango-based)
  with recorded version; (3) hand derivation (UAX#9 steps written out)
  for small sequences. The reference tool version is recorded in the
  T029 task record alongside the fixture hashes.
- **Acceptance suites (separate, per the acceptance criteria)**:
  `test/paragraph_tests.jl` (T028 — layout/wrap/fallback/clusters/
  metrics/overflow, hand-derived expectations) and
  `test/shaping_tests.jl` (T029 — per-script shaping against the
  reference protocol, bidi permutation tables, missing-glyph policy).

## 9. Specifications and versions

- Unicode Standard (pinned at implementation time; v1 tables generated
  from the pinned version's `GraphemeBreakProperty.txt`/
  `Script.txt`, BMP subset).
- UAX #29 (Grapheme Cluster Boundary) — §3.
- UAX #14 (Line Breaking) — out of v1 scope (§2.1 shortcut).
- UAX #9 (Bidi Algorithm) — §5.3 (T029).
- OpenType specification: GSUB (contextual single substitution,
  ligature, reordering, lookup 1/5/6/8), GPOS (pair positioning —
  already implemented in T009), cmap, hmtx, loca/glyf.
- HarfBuzz documentation (buffer/shaping model) as the reference
  semantics for §5, regardless of provider.

## 10. Legacy contract statement

`typeset`, `measureText`, `layoutBounds`, `computePaths`, `fillText`,
`strokeText`, `Font`, `Span`, `Typeface` (incl. `fallbackTypeface` and
the `fallbacks` field) keep their exact pinned behavior and test
coverage. T028 is additive on top; nothing in this document changes a
byte of existing rendered output for existing inputs. Any D015
extension (option (c)'s GSUB-subset reader) is recorded as its own
decision before implementation.
