# T009 — Font parsing and text layout

Status: done (2026-11-06, D015). Dependencies: T007 and the font policy
(D008).
Goal: parse fonts, compute metrics/kerning, and render/lay out text matching
pinned pixie behavior for the supported subset.

## Inputs and upstream references

- `.reference/upstream/src/pixie/fonts.nim`: `Font`, `Typeface`, `newFont`,
  `readFont`, `parseOtf`, `parseTtf`, `parseSvgFont`, `fillText`,
  `strokeText`, `layoutBounds`, `measureText`, `defaultLineHeight`, metrics,
  kerning, wrapping, alignment.
- `.reference/upstream/src/pixie/contexts.nim` text state: `font`, `fontSize`
  (default 12), `textAlign`, `textBaseline`, `fillText`/`strokeText`/
  `measureText`; examples: `.reference/upstream/examples/text.nim` if present.
- D008: `FreeType.jl` (or another well-supported package) is the preferred
  parser/metrics route; a native TTF/OTF port is allowed only if justified.
  Decide and record before coding (coordinator integrates DECISIONS.md).
- No text fixtures exist yet: add them via a **new** oracle emitter run with a
  bundled open-license font (e.g. DejaVu Sans), recording font file hash,
  license, revision, and emitter code under `tools/oracle/`. Fixtures must be
  generated from pinned upstream, never from the Julia port.

## Scope

- Font loading from file/bytes; glyph outlines; advance widths; kerning;
  line height; `measureText`; `fillText`/`strokeText` with current paint,
  transform, align/baseline; `layoutBounds`.
- SVG fonts only if the pinned source supports them and a task decision says
  so; otherwise document unsupported.
- Text state in `Context` (font path/size/align/baseline) with save/restore.
- Wrapping/alignment beyond upstream behavior is out of scope.

## Acceptance criteria

- New fixtures: metrics table (advance/kerning/bounds) and at least two
  rendered text images (fill and stroke), committed with provenance and
  checksums per test/README.md.
- `test/font_tests.jl` (new): metric rows exact (or a documented tolerance only
  if the pinned oracle itself is float-unstable — justify); rendered text
  images compared with `compare_pixels` (0 mismatches); malformed font bytes
  rejected.
- `Pkg.test()` green; `scripts/check.jl` > 95% (record exact %). Font asset
  license/NOTICE updated.
- Split if the surface exceeds one wave; report the split.

## Validation

Commands as T004; note network availability for package fetch. Do not edit
shared docs; do not commit.

## Results and handoff

Completed 2026-11-06. Decision D015 (docs/DECISIONS.md): native OpenType
subset port; FreeType.jl rejected (its `FT_Get_Kerning` reads only legacy
`kern`, not GPOS — Roboto's pinned kerning comes from GPOS; and a second
outline source would double the parity surface against the 0-mismatch
gate).

- **Font files used**: pinned upstream test fonts — Roboto-Regular_1.ttf
  (Apache-2.0, sha256 79e851404657dac2106b3d22ad256d47824a9a5765458edb72c9102a45816d95)
  and Ubuntu-Regular_1.ttf (UFL, sha256
  3128df86a31805618436d0ae5651ba4285d0c9de0a39057d025f64ee33bceb64).
  Recorded in NOTICE and in every fixture's meta (`font_sha256`,
  `font_license`); the suite re-hashes the on-disk files against those
  values. (DejaVu was the spec's example; the pinned upstream fonts are
  the oracle's own fixtures, so upstream-pinned assertions like
  `layoutBounds("Word") == (56, 28)` apply directly.)
- **Fixture provenance**: new `emitFonts()` in
  `tools/oracle/emit_fixtures.nim` (fonts mode, included in all), run with
  the pinned Nim toolchain against pinned upstream —
  `export PATH=/tmp/opencode/conda-nim/nim/bin:$PATH && sh
  tools/oracle/build.sh fonts`. Emits 6 TSVs (per-rune glyph ids +
  advances, kerning pairs incl. missing-rune probes, typeset
  positions/selection rects for 17 layout scenarios, layout bounds;
  floats as IEEE-754 hex for bit-exact comparison) and 14 rendered
  images mirroring upstream test blocks (fill/stroke, basic1-4/7/8/8b,
  underline1, strikethrough1, ctx fillText/strokeText, ubuntu1). 68 files
  approved to test/reference/font_* (tsv + sha256 sidecars; raw/png/meta
  per image) with checksums per test/README.md.
- **Commands and results**:
  - `julia --startup-file=no --project=. scripts/check.jl` → **OK**:
    `Testing Vetra tests passed` (T009: 2456/2456 assertions; full suite
    green, T008's 796,459 format assertions still pass) and
    `coverage gate: src/ line coverage = 97.87% (5188/5301 measurable
    lines)` (> 95%).
  - Oracle cross-check (independent scripts in /tmp/opencode): all 17
    layout scenarios bit-exact (positions + rects + bounds), all
    metric/kerning TSV rows exact, all 14 rendered images 0 byte
    mismatches; upstream-pinned values reproduced (Roboto T,e kern
    −99.0, W,o −31.0; Ubuntu −55/−22; `Word` bounds (56,28), `Word\n`
    (56,56); `measureText("Hello world")` @12 → width 60).
  - Review pass (DeepSeek subagent, 2026-11-06): 12 findings; 8 fixed in
    source (textCase was a silent no-op → now the pinned Nim 2.2.6
    unicase tables ported to src/fontformats/unicase.jl; `_otCodepoints`
    mis-decoded non-ASCII → plain code-point walk; `getLeftSideBearing`
    first trailing glyph → 0 as upstream; `hasGlyph` no longer walks
    fallbacks; `roundHalfAway` ties away from zero for negatives — Nim
    `round` verified with the pinned toolchain; `post` version nibbles
    validated; name text decodes surrogate pairs / tofu / trailing odd
    byte per flatty `fromUTF16BE`; GPOS value-format size counts all 16
    bits) + regression tests for each; 1 intentional deviation recorded
    (stricter glyf instruction EOF check than upstream's
    `eofCheck(instructionLength)` — COMPATIBILITY.md); `Font.paint`
    accessor not added (`paints` field is the port's API per D011).
- **Implementation**: `src/fontformats/opentype.jl` (subset parser: cmap
  4/12 platform 3 with upstream's non-standard 14-byte format-4 header,
  head/hhea/maxp/hmtx/name/OS/2/post/loca 0-1/glyf simple+composite/kern
  v0/GPOS pair-pos 1-2, parent-relative offsets preserved),
  `src/formats/fonts.jl` (Typeface/Font/Span/Arrangement, typeset/layout,
  fillText/strokeText/readTypeface/readFont, `fastRuneAt`-mirroring code
  point walk), `src/context.jl` (text state + save/restore — font,
  fontSize, textAlign, lineDash saved; textBaseline deliberately not,
  matching upstream ContextState).
- **Unsupported text features** (documented, raise `ArgumentError` with
  upstream messages): CFF-outline fonts ("Unsupported font CFF outlines" —
  Inter/NotoEmoji), TrueType Collections (TTC), SVG fonts ("Unsupported
  font format"); text wrapping/alignment beyond upstream's single-run
  line-break algorithm; no Unicode shaping beyond upstream.
- Next task: T010 (full drawing context integration).
