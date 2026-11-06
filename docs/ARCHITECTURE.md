# Proposed architecture

Everything below is the original design plan; the board is complete
(T000-T011, see docs/HANDOFF.md) and the module layout followed it.
The public surface is defined in docs/API.md (D011, Flutter-inspired); task
specs in tasks/ bind each wave to it.

| Area | Candidate files under src/ | Responsibility |
| --- | --- | --- |
| Foundation | colors.jl, geometry.jl, images.jl | Pixel representation, affine geometry, buffers |
| Compositing | blends.jl | Scalar premultiplied pixel arithmetic |
| Paths | paths.jl, rasterizer.jl, strokes.jl | Commands, flattening, coverage, stroke geometry |
| Painting | paints.jl | Solids, gradients, image sampling |
| Image operations | effects.jl | Masks, resizing, blur, shadows |
| Context | context.jl | Drawing state, transforms, clips, convenience methods |
| Formats | formats/ | Encoders, decoders, SVG adapter |
| Text | fonts/, text.jl | Font data, outlines, metrics, layout |
| Optional optimization | simd/ | Measured, behavior-preserving accelerated paths |

Use one public Vetra module initially; internal files can be included without
introducing a deep module hierarchy. Dependencies should flow from the
higher-level areas to foundation types. Keep codecs and font backends behind
small interfaces so their eventual dependency policy does not define the
rasterizer's design.

## Contracts to settle in T001/T002

- Stored channel order, premultiplied alpha invariant, and straight-alpha I/O.
- Pixel buffer layout and the mapping between image coordinates and Julia indices.
- Inclusive/exclusive bounds, clipping, invalid image dimensions, and overflow.
- Numeric types for geometry and transforms; exact rounding at pixel boundaries.
- Transform multiplication order, coordinate origin, and curve tolerances.
- Public argument and error conventions, including allocating vs mutating APIs.

Treat the previous discussion of Float32 geometry and fixed-point rasterization
as an investigation lead. Verify the exact pinned code before choosing Julia
types; never infer arithmetic semantics only from a type name.

## Performance approach

Establish scalar parity first. Use concrete storage and small functions with
explicit allocation behavior. Warm up Julia before timing, record allocations,
and separate first-call latency from steady-state rendering. Preserve a scalar
reference path before adding SIMD or threads. Do not call out to the
upstream reference implementation as the rendering backend.
