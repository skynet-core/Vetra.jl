# T030 — JPEG/WebP codec contracts and dependency decision

Status: see [TASKS.md](../TASKS.md). Dependencies: T013. Priority: web images.
Goal: choose maintainable optional codec paths before adding format APIs.

## Inputs and scope

Read D014/D019, src/formats/{jpeg,io,png}.jl, codec-loading tests, and Project.toml.
Investigate the installed JPEG package's encoding support and maintained WebP
packages, platform artifacts, licenses, and Julia 1.10 support. Extend D014 with
an explicit decision; retain native Julia rendering and opt-in codec loading.

## Acceptance criteria

- Specify JPEG straight-RGB conversion, transparent-input behavior (explicit
  background or error), quality defaults, orientation/metadata, and write dispatch.
- Specify a static-image WebP subset: read/write, lossless/lossy modes, alpha,
  quality defaults, unsupported animation, dimensions, and clear errors.
- Select providers based on current maintenance/availability and verified APIs;
  if no suitable provider meets the contract, leave that implementation blocked
  with the concrete limitation rather than creating a placeholder codec.
- Define independently sourced fixtures, interoperability tools, and error/quality
  comparison policies. Lossy validation cannot be byte-exact by assumption.
- Plan present/absent codec and cache-reuse tests plus compatibility docs, covering
  extensions, magic-byte dispatch, exported symbols, and base64 interactions.

## Validation

Use isolated scratch environments for API feasibility and encode/decode probes;
record exact package/tool versions and commands. Check license/artifact support
for supported platforms; design completion requires a viable concrete plan.

## Results and handoff

Not started. Record a codec-specific blocker if only one of JPEG/WebP is feasible.
