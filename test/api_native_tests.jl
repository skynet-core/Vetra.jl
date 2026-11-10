# M003 — Julia-native API layer.
#
# Evidence:
# - aliases are const bindings to the existing generics (`===` identity),
#   so dispatch/inference/allocation are unchanged and the legacy names
#   remain callable; allocation parity is additionally measured with
#   `@allocated` on warmed calls (M002 rule: no compilation artifacts);
# - scenes built with legacy names and native names are byte-equal;
# - Image constructor trust boundary (positive dims, overflow-safe byte
#   count, supplied-storage length; zero-PPM regression at the root);
# - array interface on a nonsquare image: [row, column], linear index,
#   bounds, iteration, setindex!, fill!, copy aliasing;
# - LinearAlgebra/Base extensions reuse the legacy formulas;
# - fromColors accepts one-based views/transposes without a copy and
#   rejects index-array views explicitly;
# - Project.toml declares weakdeps/compat for the optional providers.

using Test
using Vetra
using LinearAlgebra
using ColorTypes

const n8 = ColorTypes.N0f8
const FONT_DIR = joinpath(@__DIR__, "..", ".reference", "upstream", "tests", "fonts")
const ROBO = joinpath(FONT_DIR, "Roboto-Regular_1.ttf")

@testset "M003 Julia-native API" begin

    @testset "alias identity (const bindings, no new kernels)" begin
        snake_pairs = [
            (new_image, newImage), (minify_by2, minifyBy2),
            (magnify_by2, magnifyBy2), (rotate_90, rotate90),
            (sub_image, subImage), (super_image, superImage),
            (opaque_bounds, opaqueBounds), (stroke_shapes, strokeShapes),
            (parse_path, parsePath), (compute_bounds, computeBounds),
            (compute_paths, computePaths), (layout_bounds, layoutBounds),
            (measure_text, measureText), (length_sq, lengthSq),
            (with_fallback, withFallback), (shape_text, shapeText),
            (layout_paragraph, layoutParagraph),
            (paragraph_metrics, paragraphMetrics),
            (finish_recording, finishRecording),
            (new_font, newFont), (new_span, newSpan),
            (new_paragraph, newParagraph), (new_paint, newPaint),
            (new_path, newPath), (color_stop, colorStop),
            (parse_html_color, parseHtmlColor), (parse_svg, parseSvg),
            (parse_ttf, parseTtf), (parse_otf, parseOtf),
            (parse_open_type, parseOpenType),
            (read_image, readImage),
            (read_image_dimensions, readImageDimensions),
            (read_font, readFont), (read_typeface, readTypeface),
            (decode_ppm, decodePPM),
            (decode_ppm_dimensions, decodePPMDimensions),
            (decode_png, decodePNG),
            (decode_png_dimensions, decodePNGDimensions),
            (decode_bmp, decodeBMP),
            (decode_bmp_dimensions, decodeBMPDimensions),
            (decode_dib, decodeDIB), (decode_qoi, decodeQOI),
            (decode_qoi_dimensions, decodeQOIDimensions),
            (decode_gif, decodeGIF),
            (decode_gif_dimensions, decodeGIFDimensions),
            (decode_jpeg, decodeJPEG),
            (decode_jpeg_dimensions, decodeJPEGDimensions),
            (decode_webp, decodeWebP),
            (decode_webp_dimensions, decodeWebPDimensions),
            (decode_image, decodeImage),
            (decode_image_dimensions, decodeImageDimensions),
            (encode_ppm, encodePPM), (encode_png, encodePNG),
            (encode_bmp, encodeBMP), (encode_qoi, encodeQOI),
            (encode_jpeg, encodeJPEG), (encode_webp, encodeWebP),
            (encode_image, encodeImage), (encode_base64, encodeBase64),
            (decode_base64, decodeBase64), (to_colors, toColors),
            (from_colors, fromColors), (get_transform, getTransform),
            (get_line_dash, getLineDash), (get_rgba_smooth, getRgbaSmooth),
            (get_advance, getAdvance), (get_glyph_path, getGlyphPath),
            (get_kerning_adjustment, getKerningAdjustment),
            (get_left_side_bearing, getLeftSideBearing),
            (is_point_in_path, isPointInPath), (is_ccw, isCCW),
            (has_glyph, hasGlyph), (fallback_typeface, fallbackTypeface),
            (glyph_path_by_gid, glyphPathByGid),
            (auto_line_height, autoLineHeight),
            (default_line_height, defaultLineHeight),
            (line_gap, lineGap), (line_height, lineHeight),
            (cap_height, capHeight), (blend_alpha, blendAlpha),
            (blend_normal, blendNormal), (blend_darken, blendDarken),
            (blend_multiply, blendMultiply),
            (blend_color_burn, blendColorBurn),
            (blend_lighten, blendLighten), (blend_screen, blendScreen),
            (blend_color_dodge, blendColorDodge),
            (blend_overlay, blendOverlay),
            (blend_soft_light, blendSoftLight),
            (blend_hard_light, blendHardLight),
            (blend_difference, blendDifference),
            (blend_exclusion, blendExclusion), (blend_hue, blendHue),
            (blend_saturation, blendSaturation),
            (blend_color, blendColor),
            (blend_luminosity, blendLuminosity),
            (blend_mask, blendMask),
            (blend_subtract_mask, blendSubtractMask),
            (blend_exclude_mask, blendExcludeMask),
            (gaussian_kernel, gaussianKernel),
            (srgb_to_linear, srgbToLinear), (qoi_hash, qoiHash),
            (to_straight_alpha, toStraightAlpha),
            (to_premultiplied_alpha, toPremultipliedAlpha),
            (miter_limit_to_angle, miterLimitToAngle),
            (angle_to_miter_limit, angleToMiterLimit),
            (default_miter_limit, defaultMiterLimit),
            (fill_gradient, fillGradient), (snap_to_pixels, snapToPixels),
            (srgb, sRBG),
        ]
        bang_pairs = [
            (stroke!, stroke), (save!, save), (save_layer!, saveLayer),
            (restore!, restore), (clip!, clip), (begin_path!, beginPath),
            (close_path!, closePath), (add_path!, addPath),
            (move_to!, moveTo), (line_to!, lineTo),
            (bezier_curve_to!, bezierCurveTo),
            (quadratic_curve_to!, quadraticCurveTo),
            (elliptical_arc_to!, ellipticalArcTo), (arc_to!, arcTo),
            (arc!, arc), (rounded_rect!, roundedRect), (ellipse!, ellipse),
            (polygon!, polygon), (fill_rect!, fillRect),
            (stroke_rect!, strokeRect), (clear_rect!, clearRect),
            (stroke_segment!, strokeSegment), (set_transform!, setTransform),
            (reset_transform!, resetTransform), (set_line_dash!, setLineDash),
            (fill_path!, fillPath), (stroke_path!, strokePath),
            (fill_shapes!, fillShapes), (draw!, draw),
            (draw_tiled!, drawTiled), (draw_image!, drawImage),
            (draw_picture!, drawPicture), (fill_text!, fillText),
            (stroke_text!, strokeText), (fill_paragraph!, fillParagraph),
            (stroke_paragraph!, strokeParagraph), (blur!, blur),
            (spread!, spread), (invert!, invert),
            (flip_horizontal!, flipHorizontal),
            (flip_vertical!, flipVertical), (apply_opacity!, applyOpacity),
            (ceil!, ceil), (set_color!, setColor),
            (write_file!, writeFile), (write_ppm!, writePPM),
            (write_svg!, writeSvg), (write_pdf!, writePdf),
        ]
        for (newname, oldname) in vcat(snake_pairs, bang_pairs)
            @test newname === oldname
        end
        # fill! extends the Base generic (identical binding, so `using
        # Vetra` cannot make fill! ambiguous for Base-array users).
        @test fill! === Base.fill!
        # adapters are distinct generic functions (forwarders, not const).
        @test translate! !== translate
        @test scale! !== scale
        @test rotate! !== rotate
        @test transform! !== transform
        @test circle! !== circle
        # legacy names remain callable through the layer and keep their
        # exact legacy behavior (including return values).
        @test newImage(4, 4) isa Image
        li = newImage(4, 4)
        fill(li, rgb(1, 2, 3))
        @test getColor(li, 2, 2) == ColorRGBX(1, 2, 3, 0xff)
        c = Context(newImage(4, 4))
        strokeSegment(c, 1f0, 1f0, 3f0, 3f0)
        @test getColor(c.image, 2, 2).a > 0x00
    end

    @testset "byte equality: legacy vs native scenes" begin
        function scene_legacy()
            img = newImage(37, 23) # nonsquare
            fill(img, rgb(5, 10, 15))
            setColor(img, 1, 1, rgba(200, 100, 50, 255))
            ctx = Context(img)
            ctx.fillStyle = Paint(rgba(255, 0, 0, 255))
            ctx.strokeStyle = Paint(rgba(0, 255, 0, 255))
            ctx.lineWidth = 2f0
            fillRect(ctx, 2f0, 3f0, 10f0, 8f0)
            beginPath(ctx)
            moveTo(ctx, Vec2(5f0, 5f0))
            lineTo(ctx, Vec2(30f0, 12f0))
            lineTo(ctx, Vec2(12f0, 18f0))
            closePath(ctx)
            translate(ctx, Vec2(1f0, 2f0))
            scale(ctx, 2f0, 2f0)
            rotate(ctx, 0.1f0)
            fill(ctx)
            stroke(ctx)
            strokeSegment(ctx, 4f0, 4f0, 33f0, 20f0)
            save(ctx)
            setLineDash(ctx, Float32[3f0, 2f0])
            strokeSegment(ctx, 1f0, 21f0, 36f0, 22f0)
            clip(ctx)
            strokeSegment(ctx, 10f0, 10f0, 20f0, 14f0)
            restore(ctx)
            return img
        end

        function scene_native()
            img = new_image(37, 23)
            fill!(img, rgb(5, 10, 15))
            set_color!(img, 1, 1, rgba(200, 100, 50, 255))
            ctx = Context(img)
            ctx.fillStyle = Paint(rgba(255, 0, 0, 255))
            ctx.strokeStyle = Paint(rgba(0, 255, 0, 255))
            ctx.lineWidth = 2f0
            fill_rect!(ctx, 2f0, 3f0, 10f0, 8f0)
            begin_path!(ctx)
            move_to!(ctx, Vec2(5f0, 5f0))
            line_to!(ctx, Vec2(30f0, 12f0))
            line_to!(ctx, Vec2(12f0, 18f0))
            close_path!(ctx)
            translate!(ctx, Vec2(1f0, 2f0))
            scale!(ctx, 2f0, 2f0)
            rotate!(ctx, 0.1f0)
            fill!(ctx)
            stroke!(ctx)
            stroke_segment!(ctx, 4f0, 4f0, 33f0, 20f0)
            save!(ctx)
            set_line_dash!(ctx, Float32[3f0, 2f0])
            stroke_segment!(ctx, 1f0, 21f0, 36f0, 22f0)
            clip!(ctx)
            stroke_segment!(ctx, 10f0, 10f0, 20f0, 14f0)
            restore!(ctx)
            return img
        end

        @test scene_legacy().data == scene_native().data

        # transform adapters: same matrix state as the legacy calls.
        c1 = Context(newImage(9, 7))
        c2 = Context(newImage(9, 7))
        translate(c1, Vec2(1f0, 2f0))
        scale(c1, Vec2(2f0, 3f0))
        rotate(c1, 0.2f0)
        translate!(c2, Vec2(1f0, 2f0))
        scale!(c2, 2f0, 3f0)
        rotate!(c2, 0.2f0)
        @test getTransform(c1) == getTransform(c2)
        transform(c1, mat3())
        transform!(c2, mat3())
        @test getTransform(c1) == getTransform(c2)

        # circle! adapter vs circle mutators (path form and context form).
        p1 = newPath()
        p2 = newPath()
        circle(p1, 10f0, 10f0, 5f0)
        circle!(p2, 10f0, 10f0, 5f0)
        @test computeBounds(p1) == computeBounds(p2)
        c3 = Context(newImage(21, 15))
        c4 = Context(newImage(21, 15))
        circle(c3, 10f0, 7f0, 4f0)
        circle!(c4, 10f0, 7f0, 4f0)
        c3.fillStyle = Paint(rgb(255, 0, 0))
        c4.fillStyle = Paint(rgb(255, 0, 0))
        fill(c3)
        fill!(c4)
        @test c3.image.data == c4.image.data

        # recordings: old vs new names produce byte-equal pictures.
        function recording(scene)
            rec = PictureRecorder(31, 19)
            scene(rec.ctx)
            return finishRecording(rec)
        end
        function rec_scene_legacy(c)
            c.fillStyle = Paint(rgba(10, 20, 30, 255))
            fillRect(c, 1f0, 1f0, 20f0, 10f0)
            beginPath(c)
            moveTo(c, Vec2(2f0, 2f0))
            lineTo(c, Vec2(28f0, 17f0))
            closePath(c)
            setLineDash(c, Float32[3f0, 2f0])
            stroke(c)
            circle(c, 10f0, 10f0, 5f0)
            save(c)
            translate(c, Vec2(1f0, 1f0))
            stroke(c)
            restore(c)
        end
        function rec_scene_native(c)
            c.fillStyle = Paint(rgba(10, 20, 30, 255))
            fill_rect!(c, 1f0, 1f0, 20f0, 10f0)
            begin_path!(c)
            move_to!(c, Vec2(2f0, 2f0))
            line_to!(c, Vec2(28f0, 17f0))
            close_path!(c)
            set_line_dash!(c, Float32[3f0, 2f0])
            stroke!(c)
            circle!(c, 10f0, 10f0, 5f0)
            save!(c)
            translate!(c, Vec2(1f0, 1f0))
            stroke!(c)
            restore!(c)
        end
        a = newImage(31, 19)
        b = newImage(31, 19)
        drawPicture(a, recording(rec_scene_legacy))
        draw_picture!(b, recording(rec_scene_native))
        @test a.data == b.data

        # text on an image target.
        tf = readTypeface(ROBO)
        font = newFont(tf)
        font.size = Float32(24)
        t1 = newImage(120, 40)
        t2 = newImage(120, 40)
        fill(t1, rgb(255, 255, 255))
        fill!(t2, rgb(255, 255, 255))
        fillText(t1, font, "M003")
        fill_text!(t2, font, "M003")
        @test t1.data == t2.data
        strokeText(t1, font, "M003")
        stroke_text!(t2, font, "M003")
        @test t1.data == t2.data
    end

    @testset "adapter arities (dispatch coverage)" begin
        c = Context(newImage(13, 11))
        r = PictureRecorder(13, 11).ctx
        p = newPath()
        # Real arities and Circle-object arities
        rotate!(c, 0.2)
        translate!(r, 1.5, 2.5)
        scale!(r, 1.5, 2.5)
        rotate!(r, 0.3)
        transform!(r, mat3())
        circle!(c, 1.5, 2.5, 3.5)
        circle!(r, 1.5, 2.5, 3.5)
        circle!(p, 1.5, 2.5, 3.5)
        cc = circle(Vec2(2f0, 3f0), 1.5f0)
        circle!(c, cc)
        circle!(r, cc)
        circle!(p, cc)
        @test getTransform(c) != mat3()
        @test r.mat != mat3()
    end

    @testset "image ops: legacy vs native bytes" begin
        function img48()
            img = newImage(48, 31) # nonsquare
            for y in 1:31, x in 1:48
                setColor(img, x, y, ColorRGBX(
                    UInt8(255 * x ÷ 48), UInt8(255 * y ÷ 31),
                    UInt8((x + y) % 256), 0xff))
            end
            return img
        end

        for (oldfn, newfn) in [(flipHorizontal, flip_horizontal!),
                               (flipVertical, flip_vertical!),
                               (invert, invert!)]
            l = img48()
            n = img48()
            oldfn(l)
            newfn(n)
            @test l.data == n.data
        end
        l = img48()
        n = img48()
        spread(l, 2f0)
        spread!(n, 2f0)
        @test l.data == n.data
        l = img48()
        n = img48()
        blur(l, 2f0)
        blur!(n, 2f0)
        @test l.data == n.data
        l = img48()
        n = img48()
        applyOpacity(l, 0.5f0)
        apply_opacity!(n, 0.5f0)
        @test l.data == n.data
        l = img48()
        n = img48()
        ceil(l)
        ceil!(n)
        @test l.data == n.data

        # allocating ops
        l = img48()
        n = img48()
        @test rotate90(l).data == rotate_90(n).data
        @test minifyBy2(l).data == minify_by2(n).data
        @test magnifyBy2(l, 2).data == magnify_by2(n, 2).data
        @test resize(l, 12, 8).data == resize(n, 12, 8).data
        @test subImage(l, 4, 3, 16, 9).data == sub_image(n, 4, 3, 16, 9).data
        @test superImage(l, -2, 0, 20, 10).data ==
            super_image(n, -2, 0, 20, 10).data
        @test opaqueBounds(l) == opaque_bounds(n)
        @test shadow(l, Vec2(2f0, 2f0), 1f0, 2f0,
                     rgba(0, 0, 0, 128)).data ==
            shadow(n, Vec2(2f0, 2f0), 1f0, 2f0, rgba(0, 0, 0, 128)).data
        # draw / drawTiled (mutating, const aliases)
        d1 = img48()
        d2 = img48()
        s1 = img48()
        s2 = img48()
        draw(d1, s1, translate(Vec2(4f0, 2f0)))
        draw!(d2, s2, translate(Vec2(4f0, 2f0)))
        @test d1.data == d2.data
        d1 = img48()
        d2 = img48()
        drawTiled(d1, s1)
        draw_tiled!(d2, s2)
        @test d1.data == d2.data
    end

    @testset "Image constructor trust boundary" begin
        @test_throws ArgumentError newImage(0, 5)
        @test_throws ArgumentError newImage(5, 0)
        @test_throws ArgumentError newImage(-3, 5)
        # 4 * (1 << 61) * 2 wraps to 0 in Int; the guard must fire first.
        @test_throws ArgumentError newImage(1 << 61, 2)
        @test_throws ArgumentError Image(1 << 61, 2)
        @test_throws ArgumentError Image(0, 4, Vector{UInt8}())
        @test_throws ArgumentError Image(4, 4, Vector{UInt8}(undef, 63))
        @test_throws ArgumentError Image(4, 4, Vector{UInt8}(undef, 65))
        d = Vector{UInt8}(1:64)
        img = Image(4, 4, d)
        @test img.data === d
        @test size(img) == (4, 4)
        @test width(img) == 4 && height(img) == 4
        # Base.copy takes the validated constructor path.
        cp = Base.copy(img)
        @test cp.data == img.data && cp !== img
        # zero-PPM regression: the constructor root now rejects zero
        # dimensions (previously a broken empty Image was constructed).
        @test_throws ArgumentError decodePPM(Vector{UInt8}("P6\n0 5\n255\n"))
        @test_throws ArgumentError decodePPM(Vector{UInt8}("P6\n5 0\n255\n"))
    end

    @testset "Image array interface (nonsquare, bounds, iteration, aliasing)" begin
        img = newImage(5, 3) # 5 wide, 3 tall
        for y in 1:3, x in 1:5
            setColor(img, x, y, ColorRGBX(UInt8(4 * x), UInt8(4 * y),
                UInt8(x + y), 0xff))
        end
        @test size(img) == (3, 5)
        @test ndims(img) == 2
        @test eltype(img) === ColorRGBX
        @test length(img) == 15
        # [row, column] maps onto the stored (x, y) pixel
        for y in 1:3, x in 1:5
            @test img[y, x] == getColor(img, x, y)
            @test img[y, x] == ColorRGBX(UInt8(4 * x), UInt8(4 * y),
                UInt8(x + y), 0xff)
        end
        # linear index = row-major pixel order
        @test img[1] == getColor(img, 1, 1)
        @test img[5] == getColor(img, 5, 1)
        @test img[6] == getColor(img, 1, 2)
        @test img[15] == getColor(img, 5, 3)
        @test_throws BoundsError img[0]
        @test_throws BoundsError img[16]
        @test_throws BoundsError img[0, 1]
        @test_throws BoundsError img[1, 0]
        @test_throws BoundsError img[4, 1]
        @test_throws BoundsError img[1, 6]
        # setindex!
        img[2, 3] = ColorRGBX(0x11, 0x22, 0x33, 0x44)
        @test getColor(img, 3, 2) == ColorRGBX(0x11, 0x22, 0x33, 0x44)
        @test_throws BoundsError setindex!(img, ColorRGBX(1, 1, 1, 1), 0, 1)
        # iteration in storage order
        @test [c for c in img] ==
            [getColor(img, (k - 1) % 5 + 1, (k - 1) ÷ 5 + 1) for k in 1:15]
        # fill! (the Base interface) through all three color types
        fill!(img, rgb(7, 8, 9))
        @test all(getColor(img, x, y) == ColorRGBX(7, 8, 9, 0xff)
                  for y in 1:3, x in 1:5)
        fill!(img, rgba(1, 2, 3, 4))
        @test getColor(img, 1, 1) == rgbx(rgba(1, 2, 3, 4))
        # aliasing: setindex!/fill! mutate in place
        base = img
        img[1, 1] = ColorRGBX(0xff, 0xff, 0xff, 0xff)
        @test base[1, 1] == ColorRGBX(0xff, 0xff, 0xff, 0xff)
        # copy: deep, validated
        cp = copy(img)
        @test cp.data == img.data
        @test cp !== img && cp.data !== img.data
        cp[1, 1] = ColorRGBX(1, 1, 1, 1)
        @test getColor(img, 1, 1) == ColorRGBX(0xff, 0xff, 0xff, 0xff)
    end

    @testset "LinearAlgebra / Base extensions (legacy formulas)" begin
        a = Vec2(3f0, 4f0)
        b = Vec2(1f0, 2f0)
        @test Vetra.dot(a, b) == 11.0f0
        @test LinearAlgebra.dot(a, b) == 11.0f0
        @test LinearAlgebra.norm(a) == 5.0f0
        @test length(a) == 5.0f0 # legacy Euclidean entry
        @test LinearAlgebra.norm(a) == length(a)
        @test LinearAlgebra.normalize(b) == Vetra.normalize(b)
        @test isnan(LinearAlgebra.normalize(Vec2(0f0, 0f0)).x)
        m = Mat3((2f0, 0f0, 1f0, 0f0, 3f0, 2f0, 1f0, -1f0, 1f0))
        @test LinearAlgebra.det(m) == determinant(m)
        # hand-derived: 2 * (3*1 - (-1)*2) + 1 * (0*(-1) - 3*1) = 10 - 3
        @test det(m) == 7.0f0
        @test inv(m) == inverse(m)
        # inv(m) * m ~= identity
        p = inv(m) * m
        for (i, j) in Iterators.product(1:3, 1:3)
            want = i == j ? 1f0 : 0f0
            @test isapprox(p[i, j], want, atol = 1f-5)
        end
        # no singular guard, as upstream: NaN/Inf, not a throw
        s = Mat3((1f0, 0f0, 0f0, 0f0, 1f0, 0f0, 0f0, 0f0, 0f0))
        @test determinant(s) == 0f0
        @test isnan(inv(s)[1, 1])
        # Vec2 is deliberately not an AbstractVector
        @test !(Vec2(1f0, 2f0) isa AbstractVector)
    end

    @testset "fromColors: one-based views and transposes (M003)" begin
        big = Matrix{RGBA{n8}}(undef, 4, 5)
        for (y, x) in Iterators.product(1:4, 1:5)
            big[y, x] = RGBA{n8}(n8(x * 10 // 255), n8(y * 10 // 255),
                n8((x + y) * 5 // 255), n8(200 // 255))
        end
        # big[y, x] is straight RGBA (10x, 10y, 5(x+y), 200); the import
        # boundary is rgbx: (c * a + 127) div 255 per channel.
        # plain matrix (legacy behavior): pixel (1,1) is straight (10, 10,
        # 10, 200) -> premultiplied (2127 div 255, 2127 div 255, 2127 div
        # 255, 200) = (8, 8, 8, 200).
        img = from_colors(big)
        @test (width(img), height(img)) == (5, 4)
        @test getColor(img, 1, 1) == ColorRGBX(8, 8, 8, 200)
        # one-based unit-range view: no copy, kernel indexes logically.
        # pixel (4,2) reads big[3,4]: straight (40, 30, 35, 200) ->
        # (8127 div 255, 6127 div 255, 7127 div 255, 200) = (31, 24, 27, 200).
        v = view(big, 2:3, 1:4)
        imgv = fromColors(v)
        @test size(imgv) == (2, 4)
        @test imgv.data == fromColors(copy(v)).data
        @test getColor(imgv, 4, 2) == ColorRGBX(31, 24, 27, 200)
        # transpose (rebuilt as a permuted matrix — this platform's
        # Transpose getindex transforms elements, so no in-place read)
        t = transpose(big)
        @test size(t) == (5, 4)
        imgt = fromColors(t)
        @test size(imgt) == (5, 4)
        @test imgt.data == fromColors(permutedims(big, (2, 1))).data
        # pixel (1,2) reads big[1,2]: straight (20, 10, 15, 200) ->
        # (4127 div 255, 2127 div 255, 3127 div 255, 200) = (16, 8, 12, 200).
        @test getColor(imgt, 1, 2) == ColorRGBX(16, 8, 12, 200)
        # double transpose: back to the original orientation
        @test fromColors(transpose(transpose(big))).data ==
            fromColors(big).data
        # transpose of a view: accepted (rebuilt over the view's parent)
        tv = transpose(view(big, 1:3, 1:4))
        @test fromColors(tv).data ==
            fromColors(permutedims(view(big, 1:3, 1:4), (2, 1))).data
        # adjoint and views over transposes are rejected explicitly. The
        # lazy wrapper is constructed directly: the ambient `transpose`
        # may materialize for color matrices once a provider package
        # (PNGFiles, loaded by earlier suites in runtests) is in Main.
        @test_throws ArgumentError fromColors(adjoint(big))
        @test_throws ArgumentError fromColors(view(LinearAlgebra.Transpose(big), 1:2, 1:3))
        # float channels (legacy) through a view
        mf = Matrix{RGB{Float64}}(undef, 2, 3)
        mf[1, 1] = RGB(0.25, 0.5, 0.75)
        mf[1, 2] = RGB(0.0, 1.0, 0.5)
        mf[1, 3] = RGB(0.125, 0.125, 0.125)
        mf[2, 1] = RGB(1.0, 0.0, 0.0)
        mf[2, 2] = RGB(0.0, 0.0, 1.0)
        mf[2, 3] = RGB(0.5, 0.25, 0.125)
        @test fromColors(view(mf, 1:2, 1:3)).data == fromColors(mf).data
        # strided view: also accepted (the kernel indexes logically)
        sv = view(big, 1:2:3, 1:2:4)
        @test fromColors(sv).data == fromColors(copy(sv)).data
        # index-array views are rejected explicitly
        @test_throws ArgumentError fromColors(view(big, [2, 1], [1, 2]))
        @test_throws ArgumentError fromColors(view(big, [1, 2], [3, 4, 5]))
        # 3-D plane layouts and non-color eltypes are still rejected
        @test_throws ArgumentError fromColors(zeros(RGB{n8}, 2, 3, 4))
        @test_throws ArgumentError fromColors(zeros(UInt8, 2, 3))
    end

    @testset "inference and dispatch stability" begin
        @test @inferred(new_image(4, 4)) isa Image
        @test @inferred(Image(4, 4)) isa Image
        @test @inferred(Image(4, 4, Vector{UInt8}(undef, 64))) isa Image
        @test @inferred(Base.getindex(new_image(4, 4), 1, 1)) isa ColorRGBX
        # iterate yields (pixel, next state) until it exhausts
        @test Base.iterate(new_image(4, 4)) == (ColorRGBX(0, 0, 0, 0), 2)
        @test Base.iterate(new_image(4, 4), 16) == (ColorRGBX(0, 0, 0, 0), 17)
        @test Base.iterate(new_image(4, 4), 17) === nothing
        @test @inferred(LinearAlgebra.norm(Vec2(3f0, 4f0))) === 5.0f0
        @test @inferred(translate!(Context(new_image(4, 4)),
            Vec2(1f0, 2f0))) === nothing
        @test @inferred(circle!(newPath(), 1f0, 1f0, 1f0)) === nothing
    end

    @testset "allocation parity (warmed calls, M002 rule)" begin
        # warm up both paths (compile + cache)
        for _ in 1:3
            img = newImage(64, 40)
            fill(img, rgb(1, 2, 3))
            ctx = Context(img)
            fillRect(ctx, 1f0, 1f0, 8f0, 8f0)
            translate(ctx, Vec2(1f0, 2f0))
            img2 = new_image(64, 40)
            fill!(img2, rgb(1, 2, 3))
            ctx2 = Context(img2)
            fill_rect!(ctx2, 1f0, 1f0, 8f0, 8f0)
            translate!(ctx2, Vec2(1f0, 2f0))
            scale(ctx2, Vec2(2f0, 3f0))
            scale!(ctx2, Vec2(2f0, 3f0))
        end
        @test @allocated(newImage(64, 40)) > 0
        @test @allocated(newImage(64, 40)) == @allocated(new_image(64, 40))
        # the two constructor roots agree
        @test @allocated(Image(64, 40)) == @allocated(newImage(64, 40))
        i1 = newImage(64, 40)
        i2 = new_image(64, 40)
        @test @allocated(fill(i1, rgb(1, 2, 3))) ==
            @allocated(fill!(i2, rgb(1, 2, 3)))
        c1 = Context(newImage(64, 40))
        c2 = Context(new_image(64, 40))
        @test @allocated(fillRect(c1, 1f0, 1f0, 8f0, 8f0)) > 0
        @test @allocated(fillRect(c1, 1f0, 1f0, 8f0, 8f0)) ==
            @allocated(fill_rect!(c2, 1f0, 1f0, 8f0, 8f0))
        @test @allocated(translate(c1, Vec2(1f0, 2f0))) ==
            @allocated(translate!(c2, Vec2(1f0, 2f0)))
        @test @allocated(scale(c1, Vec2(2f0, 3f0))) ==
            @allocated(scale!(c2, Vec2(2f0, 3f0)))
        # fromColors: the view path allocates the image, not a copy of
        # the source matrix (same size, same eltype as the view).
        big = Matrix{RGBA{n8}}(undef, 4, 5)
        for (y, x) in Iterators.product(1:4, 1:5)
            big[y, x] = RGBA{n8}(n8(10 // 255), n8(20 // 255),
                n8(30 // 255), n8(200 // 255))
        end
        plain = Matrix{RGBA{n8}}(undef, 2, 4)
        v1 = view(big, 2:3, 1:4)
        v2 = view(big, 2:3, 1:4)
        for _ in 1:3
            fromColors(v1)
            fromColors(plain)
        end
        @test @allocated(fromColors(v1)) > 0
        @test @allocated(fromColors(v1)) == @allocated(fromColors(v2))
        # the view path allocates less than the copy-the-matrix path
        @test @allocated(fromColors(v1)) < @allocated(fromColors(copy(v1)))
    end

    @testset "package metadata (weakdeps + compat)" begin
        # Pkg is not loadable inside the Pkg.test sandbox; read the flat
        # Project.toml sections directly.
        function parse_project_toml(path)
            sections = Dict{String, Dict{String, String}}()
            cur = nothing
            for raw in readlines(path)
                line = strip(raw)
                (isempty(line) || startswith(line, '#')) && continue
                if startswith(line, '[')
                    cur = string(line)
                    sections[cur] = Dict{String, String}()
                    continue
                end
                if cur !== nothing && occursin('=', line)
                    k, v = split(line, '=', limit = 2)
                    sections[cur][strip(k)] = strip(strip(v), '"')
                end
            end
            return sections
        end
        proj = parse_project_toml(joinpath(@__DIR__, "..", "Project.toml"))
        @test haskey(proj, "[weakdeps]")
        weak = Dict(
            "ColorTypes" => "3da002f7-5984-5a60-b8a6-cbb66c0b333f",
            "HarfBuzz_jll" => "2e76f6c2-a576-52d4-95c1-20adfe4de566",
            "JpegTurbo" => "b835a17e-a41a-41e7-81f0-2f016b05efe0",
            "PNGFiles" => "f57f5aa1-a3ce-4bc8-8ab9-96f992907883",
            "WebP" => "e3aaa7dc-3e4b-44e0-be63-ffb868ccd7c1",
            "XML" => "72c71f33-b9b6-44de-8c94-c961784809e2")
        for (name, uuid) in weak
            @test get(proj["[weakdeps]"], name, nothing) === uuid
        end
        @test proj["[compat]"]["julia"] == "1.10"
        for name in keys(weak)
            @test haskey(proj["[compat]"], name)
        end
        # runtime deps are stdlib only (optional providers are weakdeps,
        # loaded lazily on first use, D014/D015/D019/D024/D028).
        @test sort(collect(keys(proj["[deps]"]))) == ["Libdl", "LinearAlgebra"]
    end
end
