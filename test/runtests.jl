using Test
using Vetra

@testset "Package loads" begin
    @test Vetra isa Module
end

include("codec_loading_tests.jl")

# T001: reference fixture reader + comparison harness and its tests.
include("fixtures.jl")
using .VetraRef
include("reference_tests.jl")

# T002: colors, image storage, basic compositing (core implementation tests).
include("core_tests.jl")

# T003: geometry and affine transforms (core implementation tests).
include("geometry_tests.jl")

# T004: paths, curves, arcs, solid fills and rasterization.
include("path_tests.jl")

# T005: solid paints, strokes (caps/joins/dashes), minimal context.
include("context_tests.jl")

# T006: example byte parity (square/line/heart) and PPM P6 output.
include("examples_tests.jl")

# T007a: full blend modes (20 TSV tables), paints/gradients,
# image draw/sampling ops and the two draw fixtures.
include("paint_tests.jl")
include("image_ops_tests.jl")

# T007b: masks and layers on Context (clip, saveLayer/restore, globalAlpha).
include("context_layers_tests.jl")

# T008: file formats (PNG, JPEG, BMP, QOI, GIF, SVG, PPM): pinned upstream
# fixtures, dispatch, encode/write, round trips, base64.
include("formats_tests.jl")

# T008 coverage: synthetic format branches (palette BMPs, GIF LCT/interlace/
# disposal, JPEG Exif/resync, QOI encode ops, PPM 16-bit, SVG style/url).
include("formats_synthetic_tests.jl")

# T008 coverage: rasterizer MaskBlend fill paths and drawSmooth branches
# (upstream-oracle-pinned).
include("rasterizer_tests.jl")

# T009: fonts and text — OpenType (glyf/TTF subset, D015), metrics, kerning
# (GPOS + legacy), typeset/layout, fillText/strokeText, Context text state;
# oracle TSVs + 14 rendered images + synthetic mini font.
include("font_tests.jl")

# T010: full context integration — cross-feature composition of the state
# stack, clips, transforms, dashes, layers, opacity, text and gradients
# (hand-derived expectations; isPointInPath + dash wiring).
include("context_integration_tests.jl")
