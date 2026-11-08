# T031 — Optional JPEG encoding

Status: see [TASKS.md](../TASKS.md). Dependencies: T030 JPEG contract/decision.
Goal: write JPEG thumbnails and photographic output from Vetra images.

## Inputs and scope

Implement T030 using the selected optional provider, existing JPEG decoder,
format dispatch, and codec loading pattern. Add only the specified options;
do not expose provider internals as an unbounded public keyword API.

## Acceptance criteria

- Public encoder and `.jpg`/`.jpeg` write/encode dispatch work with explicit
  quality and the agreed transparency/background behavior.
- Correct channel order, orientation, dimensions, quality validation, and
  error handling, including absent codec and malformed/unsupported arguments.
- An independent JPEG reader opens produced files. Use separately justified
  structural and lossy pixel/quality checks; do not require arbitrary JPEG
  byte equality or silently discard alpha.
- Existing JPEG decoding, PNG/base64 behavior, and core-only loading stay valid.
- Provide an annotation/thumbnail export recipe and compare runtime/output size
  on photographic and flat graphics, noting where JPEG is unsuitable.

## Validation

Use [shared validation](../docs/ROADMAP.md#shared-validation), optional-provider
subprocess tests, independent-reader checks, and codec corpus benchmarks.
Record the agreed lossy comparison policy before evaluating test output.

## Results and handoff

Blocked on the T030 JPEG decision. Record integration and interoperability results.
