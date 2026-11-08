# T029 — Optional Unicode shaping and bidirectional text

Status: see [TASKS.md](../TASKS.md). Dependencies: T028 (and its T027 contract).
Goal: correctly position and order glyphs for the documented complex scripts.

## Inputs and scope

Implement T027's selected optional shaper/bidi integration into the additive
layout API. Native Julia still rasterizes glyph outlines. No automatic change
to legacy text behavior, mandatory font engine, or promise of every font format.

## Acceptance criteria

- Shaped glyph IDs, cluster mapping, advances, offsets, and direction match a
  pinned independent shaping reference on licensed fonts.
- Cover Arabic contextual joining, an Indic conjunct, ligatures, combining
  marks, mixed RTL/LTR numbers/punctuation, and fallback/run boundaries.
- Wrapping and shaping interact according to the contract (including reshaping
  at line breaks where needed), with consistent measurement and rendering.
- Missing optional packages give a clear explicit shaping error; existing
  unshaped/native text and core-only loading keep working.
- Document script/font limitations and demonstrate the new path in a multilingual
  card. Do not broaden CFF/TTC/color-emoji claims without separate evidence.

## Validation

Use [shared validation](../docs/ROADMAP.md#shared-validation), T027 reference
outputs, optional-dependency loading tests, and the multilingual example.
Test both glyph/cluster data and rendered placement; visual similarity alone
does not establish shaping correctness.

## Results and handoff

Blocked on T028. Record provider/version, reference corpus, and supported scripts.
