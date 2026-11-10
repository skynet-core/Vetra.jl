# T029 shaping fixtures

Pinned test fonts for `test/shaping_tests.jl` (docs/TEXT_LAYOUT.md §8).
Fetched by `scripts/fetch_shaping_fixtures.jl` (URL + SHA256 verified);
tests never download — they read these files and verify the hashes
recorded in `test/reference/shaping_reference.tsv` (meta) and the
`.sha256` sidecars.

| File | Font | License |
| --- | --- | --- |
| `NotoSansArabic-Regular.ttf` | Noto Sans Arabic Regular 2.000 (glyf, hinted) | SIL OFL 1.1 |
| `NotoSansDevanagari-Regular.ttf` | Noto Sans Devanagari Regular 2.000 (glyf, hinted) | SIL OFL 1.1 |

Source URLs and SHA256 are recorded in each `.sha256` sidecar's
companion meta (the `font_*_url=`/`font_*_sha256=` lines of
`test/reference/shaping_reference.tsv`) and in
`scripts/fetch_shaping_fixtures.jl`. OFL 1.1 font license text:
https://openfontlicense.org/ (the fonts are redistributed as binary
data under their own license, like the existing T028 NotoSansJP
fixture).
