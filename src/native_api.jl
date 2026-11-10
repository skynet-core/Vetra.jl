# ---------- Julia-native naming layer (M003) ----------
# Idiomatic entry points over the existing kernels: snake_case aliases
# for the legacy camelCase names, and `!` for mutating operations.
# Every alias is a `const` binding to the existing generic function — no
# method is duplicated, so dispatch, inference, allocation, and behavior
# are unchanged, and the legacy names remain callable. docs/MIGRATION.md
# has the full table.
#
# Naming rules (bounded contract, tasks/MODERNIZATION.md):
# - a `!` name covers exactly the mutating generics; a generic that mixes
#   mutating and allocating methods gets a typed adapter (translate!,
#   scale!, rotate!, transform!, circle!) instead of a const alias, so no
#   `!` name advertises a pure or allocating overload;
# - `fill!` is defined on the Base generic `fill!` (identical binding) so
#   `using Vetra` cannot make `fill!` ambiguous for Base-array users;
# - allocating/pure entry points get snake_case names without `!`.

# --- mutating entry points (bang API) ---

# `fill` extends the Base generic; `fill!` extends Base.fill! the same way,
# forwarding to the existing Image / Context / RecordingContext methods.
Base.fill!(image::Image, color::ColorRGBX) = fill(image, color)
Base.fill!(image::Image, color::ColorRGBA) = fill(image, color)
Base.fill!(image::Image, color::ColorRGB) = fill(image, color)
Base.fill!(ctx::Context, image::Image, path::Path, windingRule = NonZero) =
    fill(ctx, image, path, windingRule)
Base.fill!(ctx::Context, path::Path, windingRule = NonZero) =
    fill(ctx, path, windingRule)
Base.fill!(ctx::Context, windingRule = NonZero) = fill(ctx, windingRule)
Base.fill!(rctx::RecordingContext, path::Path, windingRule = NonZero) =
    fill(rctx, path, windingRule)

const stroke! = stroke
const save! = save
const save_layer! = saveLayer
const restore! = restore
const clip! = clip
const begin_path! = beginPath
const close_path! = closePath
const add_path! = addPath
const move_to! = moveTo
const line_to! = lineTo
const bezier_curve_to! = bezierCurveTo
const quadratic_curve_to! = quadraticCurveTo
const elliptical_arc_to! = ellipticalArcTo
const arc_to! = arcTo
const arc! = arc
const rounded_rect! = roundedRect
const ellipse! = ellipse
const polygon! = polygon
const fill_rect! = fillRect
const stroke_rect! = strokeRect
const clear_rect! = clearRect
const stroke_segment! = strokeSegment
const set_transform! = setTransform
const reset_transform! = resetTransform
const set_line_dash! = setLineDash
const fill_path! = fillPath
const stroke_path! = strokePath
const fill_shapes! = fillShapes
const draw! = draw
const draw_tiled! = drawTiled
const draw_image! = drawImage
const draw_picture! = drawPicture
const fill_text! = fillText
const stroke_text! = strokeText
const fill_paragraph! = fillParagraph
const stroke_paragraph! = strokeParagraph
const blur! = blur
const spread! = spread
const invert! = invert
const flip_horizontal! = flipHorizontal
const flip_vertical! = flipVertical
const apply_opacity! = applyOpacity
const ceil! = ceil
const set_color! = setColor
const write_file! = writeFile
const write_ppm! = writePPM
const write_svg! = writeSvg
const write_pdf! = writePdf

# --- typed adapters: generics that mix mutating and allocating methods ---
# Context/RecordingContext mutators only; the geometry constructors
# translate(v) / scale(v) / rotate(angle) and the pure transform(m, v) /
# transform(m, r) / transform(path, mat) stay un-banged.

function translate!(ctx::Context, v::Vec2)
    return translate(ctx, v)
end
function translate!(ctx::Context, x::Real, y::Real)
    return translate(ctx, x, y)
end
function translate!(rctx::RecordingContext, v::Vec2)
    return translate(rctx, v)
end
function translate!(rctx::RecordingContext, x::Real, y::Real)
    return translate(rctx, x, y)
end

function scale!(ctx::Context, v::Vec2)
    return scale(ctx, v)
end
function scale!(ctx::Context, x::Real, y::Real)
    return scale(ctx, x, y)
end
function scale!(rctx::RecordingContext, v::Vec2)
    return scale(rctx, v)
end
function scale!(rctx::RecordingContext, x::Real, y::Real)
    return scale(rctx, x, y)
end

# rotate! extends LinearAlgebra.rotate! (identical binding, so `using Vetra`
# together with `using LinearAlgebra` stays unambiguous); the geometry
# constructor rotate(angle) stays un-banged.
LinearAlgebra.rotate!(ctx::Context, angle::Real) = rotate(ctx, angle)
LinearAlgebra.rotate!(rctx::RecordingContext, angle::Real) = rotate(rctx, angle)

function transform!(ctx::Context, m::Mat3)
    return transform(ctx, m)
end
function transform!(rctx::RecordingContext, m::Mat3)
    return transform(rctx, m)
end

# circle! covers the Path / Context / RecordingContext mutators only; the
# geometry constructor circle(pos, radius) stays un-banged.
function circle!(ctx::Context, cx::Float32, cy::Float32, r::Float32)
    return circle(ctx, cx, cy, r)
end
function circle!(ctx::Context, cx::Real, cy::Real, r::Real)
    return circle(ctx, cx, cy, r)
end
function circle!(ctx::Context, c::Circle)
    return circle(ctx, c)
end
function circle!(path::Path, cx::Float32, cy::Float32, r::Float32)
    return circle(path, cx, cy, r)
end
function circle!(path::Path, c::Circle)
    return circle(path, c)
end
function circle!(path::Path, cx::Real, cy::Real, r::Real)
    return circle(path, cx, cy, r)
end
function circle!(rctx::RecordingContext, cx::Float32, cy::Float32, r::Float32)
    return circle(rctx, cx, cy, r)
end
function circle!(rctx::RecordingContext, cx::Real, cy::Real, r::Real)
    return circle(rctx, cx, cy, r)
end
function circle!(rctx::RecordingContext, c::Circle)
    return circle(rctx, c)
end

# --- allocating / pure entry points (snake_case, no bang) ---

const new_image = newImage
const minify_by2 = minifyBy2
const magnify_by2 = magnifyBy2
const rotate_90 = rotate90
const sub_image = subImage
const super_image = superImage
const opaque_bounds = opaqueBounds
const stroke_shapes = strokeShapes
const parse_path = parsePath
const compute_bounds = computeBounds
const compute_paths = computePaths
const layout_bounds = layoutBounds
const measure_text = measureText
const length_sq = lengthSq
const with_fallback = withFallback
const shape_text = shapeText
const layout_paragraph = layoutParagraph
const paragraph_metrics = paragraphMetrics
const finish_recording = finishRecording
const new_font = newFont
const new_span = newSpan
const new_paragraph = newParagraph
const new_paint = newPaint
const new_path = newPath
const color_stop = colorStop
const parse_html_color = parseHtmlColor
const parse_svg = parseSvg
const parse_ttf = parseTtf
const parse_otf = parseOtf
const parse_open_type = parseOpenType
const read_image = readImage
const read_image_dimensions = readImageDimensions
const read_font = readFont
const read_typeface = readTypeface
const decode_ppm = decodePPM
const decode_ppm_dimensions = decodePPMDimensions
const decode_png = decodePNG
const decode_png_dimensions = decodePNGDimensions
const decode_bmp = decodeBMP
const decode_bmp_dimensions = decodeBMPDimensions
const decode_dib = decodeDIB
const decode_qoi = decodeQOI
const decode_qoi_dimensions = decodeQOIDimensions
const decode_gif = decodeGIF
const decode_gif_dimensions = decodeGIFDimensions
const decode_jpeg = decodeJPEG
const decode_jpeg_dimensions = decodeJPEGDimensions
const decode_webp = decodeWebP
const decode_webp_dimensions = decodeWebPDimensions
const decode_image = decodeImage
const decode_image_dimensions = decodeImageDimensions
const encode_ppm = encodePPM
const encode_png = encodePNG
const encode_bmp = encodeBMP
const encode_qoi = encodeQOI
const encode_jpeg = encodeJPEG
const encode_webp = encodeWebP
const encode_image = encodeImage
const encode_base64 = encodeBase64
const decode_base64 = decodeBase64
const to_colors = toColors
const from_colors = fromColors
const get_transform = getTransform
const get_line_dash = getLineDash
const get_rgba_smooth = getRgbaSmooth
const get_advance = getAdvance
const get_glyph_path = getGlyphPath
const get_kerning_adjustment = getKerningAdjustment
const get_left_side_bearing = getLeftSideBearing
const is_point_in_path = isPointInPath
const is_ccw = isCCW
const has_glyph = hasGlyph
const fallback_typeface = fallbackTypeface
const glyph_path_by_gid = glyphPathByGid
const auto_line_height = autoLineHeight
const default_line_height = defaultLineHeight
const line_gap = lineGap
const line_height = lineHeight
const cap_height = capHeight
const blend_alpha = blendAlpha
const blend_normal = blendNormal
const blend_darken = blendDarken
const blend_multiply = blendMultiply
const blend_color_burn = blendColorBurn
const blend_lighten = blendLighten
const blend_screen = blendScreen
const blend_color_dodge = blendColorDodge
const blend_overlay = blendOverlay
const blend_soft_light = blendSoftLight
const blend_hard_light = blendHardLight
const blend_difference = blendDifference
const blend_exclusion = blendExclusion
const blend_hue = blendHue
const blend_saturation = blendSaturation
const blend_color = blendColor
const blend_luminosity = blendLuminosity
const blend_mask = blendMask
const blend_subtract_mask = blendSubtractMask
const blend_exclude_mask = blendExcludeMask
const gaussian_kernel = gaussianKernel
const srgb_to_linear = srgbToLinear
const qoi_hash = qoiHash
const to_straight_alpha = toStraightAlpha
const to_premultiplied_alpha = toPremultipliedAlpha
const miter_limit_to_angle = miterLimitToAngle
const angle_to_miter_limit = angleToMiterLimit
const default_miter_limit = defaultMiterLimit
const fill_gradient = fillGradient
const snap_to_pixels = snapToPixels
const srgb = sRBG
