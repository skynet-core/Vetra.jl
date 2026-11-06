# ---------- QOI (T008) ----------
# Upstream: pixie/fileformats/qoi.nim -- qoiSignature (L6), Colorspace/Qoi
# (L16-27), hash (L29), srgbToLinear (L32-53), newImage(Qoi) (L60-66),
# convertToImage (L68-82), decodeQoi (L84-168), decodeQoiDimensions
# (L170-186), encodeQoi(Qoi) (L188-259), encodeQoi(Image) (L261-273).
#
# Pinned behavior notes:
# - All per-channel math is wrapping UInt8 (Nim uint8 arithmetic).
# - srgbToLinear is Float32 (Nim float32 literals), `round` ties away from
#   zero (our roundHalfAway), pow in float32.
# - decodeQoi validates: signature, channels in {3,4}, colorspace in {0,1},
#   "Underrun of QOI decoder" when the bitstream ends before w*h pixels
#   (checked as p > len - 8), and the 8-byte padding (seven 0x00 then
#   0x01, else "Invalid QOI padding").
# - encodeQoi always writes the colorspace as Linear; sRGB input colors
#   are linearized per pixel (linearPixel).
# - decodeImage uses decodeQoi(data).convertToImage(); the pixels are the
#   same as newImage(Qoi) (convertToImage only avoids the copy).

"""Upstream `qoiSignature`."""
const QOI_SIGNATURE = "qoif"

"""Upstream `Colorspace` enum."""
@enum QoiColorspace begin
    sRBG
    Linear
end

"""
Upstream `Qoi`: raw QOI pixels in straight alpha RGBA, 4 bytes per pixel,
row-major. `data` is the premultiplied-free source of `newImage`.
"""
struct Qoi
    width::Int
    height::Int
    channels::Int
    colorspace::QoiColorspace
    data::Vector{UInt8}
end

const QOI_INDEX_LEN = 64
const QOI_OP_RGB = 0xfe
const QOI_OP_RGBA = 0xff
const QOI_OP_MASK2 = 0xc0
const QOI_OP_INDEX = 0x00
const QOI_OP_DIFF = 0x40
const QOI_OP_LUMA = 0x80
const QOI_OP_RUN = 0xc0

"""Wrapping Int -> UInt8 (Nim uint8 arithmetic wraps on overflow/underflow)."""
wrap8(v::Int) = UInt8(v & 0xff)

"""Upstream `hash`: index slot for a straight RGBA pixel."""
function qoiHash(r::UInt8, g::UInt8, b::UInt8, a::UInt8)
    return (Int(r) * 3 + Int(g) * 5 + Int(b) * 7 + Int(a) * 11) % 64
end

"""
Upstream `srgbToLinear(value: uint8)`: float32 sRGB->linear, rounded
away from zero into 0..255.
"""
function srgbToLinear(value::UInt8)
    c = Float32(Int(value)) / Float32(255)
    # All Float32, as upstream (Nim float32 literals + powf).
    linear = if c <= Float32(0.04045)
        c / Float32(12.92)
    else
        ((c + Float32(0.055)) / Float32(1.055)) ^ Float32(2.4)
    end
    return UInt8(roundHalfAway(linear * Float32(255)))
end

"""Upstream `newImage(Qoi)`: straight RGBA -> (sRGB linearized) premultiplied."""
function newImage(qoi::Qoi)
    image = newImage(qoi.width, qoi.height)
    d = image.data
    s = qoi.data
    for i in 0:(qoi.width * qoi.height - 1)
        o = 4 * i
        r = s[o + 1]
        g = s[o + 2]
        b = s[o + 3]
        a = s[o + 4]
        if qoi.colorspace === sRBG
            r = srgbToLinear(r)
            g = srgbToLinear(g)
            b = srgbToLinear(b)
        end
        p = rgbx(ColorRGBA(r, g, b, a))
        d[o + 1] = p.r
        d[o + 2] = p.g
        d[o + 3] = p.b
        d[o + 4] = p.a
    end
    return image
end

"""Upstream `decodeQoi`: full QOI bitstream decode into straight RGBA."""
function decodeQOI(data::Vector{UInt8})
    length(data) <= 14 && throw(ArgumentError("Invalid QOI header"))
    String(data[1:4]) != QOI_SIGNATURE && throw(ArgumentError("Invalid QOI header"))

    be32(i::Int) = (Int(data[i]) << 24) | (Int(data[i + 1]) << 16) |
        (Int(data[i + 2]) << 8) | Int(data[i + 3])
    width = be32(5)
    height = be32(9)
    channels = Int(data[13])
    colorspace = Int(data[14])

    (channels in (3, 4) && colorspace in (0, 1)) || throw(ArgumentError("Invalid QOI header"))
    (width * height > 0xffffffff) &&
        throw(ArgumentError("QOI is too large to decode"))

    qoi = Qoi(width, height, channels, QoiColorspace(colorspace),
        Vector{UInt8}(undef, 4 * width * height))
    s = qoi.data

    # Upstream `var index: Index`: Nim zero-initializes local arrays, so
    # every slot starts fully transparent (0,0,0,0) -- unlike the QOI
    # reference implementation, which seeds slot 0 with alpha 255.
    index = Array{NTuple{4,UInt8}}(undef, 64)
    for i in 1:64
        index[i] = (UInt8(0), UInt8(0), UInt8(0), UInt8(0))
    end
    p = 15 # 1-based bitstream start (upstream: 14)
    n = length(data)
    run = 0
    r = UInt8(0); g = UInt8(0); b = UInt8(0); a = UInt8(255)

    for dst in 0:(width * height - 1)
        # Upstream 0-based `p > len - 8`; ours is 1-based.
        if p - 1 > n - 8
            throw(ArgumentError("Underrun of QOI decoder"))
        end
        if run > 0
            run -= 1
        else
            b0 = data[p]
            p += 1
            if b0 == QOI_OP_RGB
                r = data[p]
                g = data[p + 1]
                b = data[p + 2]
                p += 3
            elseif b0 == QOI_OP_RGBA
                r = data[p]
                g = data[p + 1]
                b = data[p + 2]
                a = data[p + 3]
                p += 4
            else
                op = b0 & QOI_OP_MASK2
                if op == QOI_OP_INDEX
                    entry = index[Int(b0) + 1]
                    r, g, b, a = entry
                elseif op == QOI_OP_DIFF
                    # Wrapping uint8 arithmetic, as upstream (Nim uint8 ops
                    # wrap; Julia's UInt8(negative Int) throws, so mask).
                    r += wrap8((Int(b0 >> 4) & 0x03) - 2)
                    g += wrap8((Int(b0 >> 2) & 0x03) - 2)
                    b += wrap8(Int(b0 & 0x03) - 2)
                elseif op == QOI_OP_LUMA
                    b1 = data[p]
                    vg = (Int(b0 & 0x3f) - 32)
                    r += wrap8(vg - 8 + Int((b1 >> 4) & 0x0f))
                    g += wrap8(vg)
                    b += wrap8(vg - 8 + Int(b1 & 0x0f))
                    p += 1
                elseif op == QOI_OP_RUN
                    run = Int(b0 & 0x3f)
                else
                    throw(ArgumentError("Unexpected QOI op"))
                end
            end
            # Upstream writes the index after every non-run-continued op,
            # including RGB/RGBA and RUN (the run write is a no-op since px
            # is unchanged and its slot already holds px).
            index[qoiHash(r, g, b, a) + 1] = (r, g, b, a)
        end
        o = 4 * dst
        s[o + 1] = r
        s[o + 2] = g
        s[o + 3] = b
        s[o + 4] = a
    end

    # Padding: seven 0x00, one 0x01. (Upstream 0-based `p < len`.)
    while p <= n
        c = data[p]
        if c == 0x00
            # discard
        elseif c == 0x01
            break
        else
            throw(ArgumentError("Invalid QOI padding"))
        end
        p += 1
    end

    return qoi
end

"""Upstream `decodeQoiDimensions`: header only (12 bytes minimum)."""
function decodeQOIDimensions(data::Vector{UInt8})
    length(data) <= 12 && throw(ArgumentError("Invalid QOI header"))
    String(data[1:4]) != QOI_SIGNATURE && throw(ArgumentError("Invalid QOI header"))
    be32(i::Int) = (Int(data[i]) << 24) | (Int(data[i + 1]) << 16) |
        (Int(data[i + 2]) << 8) | Int(data[i + 3])
    return (be32(5), be32(9))
end

"""Upstream `encodeQoi(Qoi)`: straight RGBA pixels to the QOI file format."""
function encodeQOI(qoi::Qoi)
    (qoi.width * qoi.height > 0xffffffff) &&
        throw(ArgumentError("QOI is too large to encode"))
    out = Vector{UInt8}()
    append!(out, codeunits(QOI_SIGNATURE))
    # & 0xff on every byte: the raw shifts exceed UInt8 for values >= 256.
    pushbe32(v::Int) = push!(out, UInt8((v >> 24) & 0xff),
        UInt8((v >> 16) & 0xff), UInt8((v >> 8) & 0xff), UInt8(v & 0xff))
    pushbe32(qoi.width)
    pushbe32(qoi.height)
    push!(out, UInt8(qoi.channels))
    push!(out, UInt8(Linear))

    s = qoi.data
    index = Array{NTuple{4,UInt8}}(undef, 64)
    for i in 1:64
        index[i] = (UInt8(0), UInt8(0), UInt8(0), UInt8(0))
    end
    run = 0
    pr = UInt8(0); pg = UInt8(0); pb = UInt8(0); pa = UInt8(255)

    for off in 0:(qoi.width * qoi.height - 1)
        o = 4 * off
        r = s[o + 1]
        g = s[o + 2]
        b = s[o + 3]
        a = s[o + 4]
        # linearPixel: sRGB input is linearized (header says Linear out).
        if qoi.colorspace === sRBG
            r = srgbToLinear(r)
            g = srgbToLinear(g)
            b = srgbToLinear(b)
        end
        if r == pr && g == pg && b == pb && a == pa
            run += 1
            if run == 62 || off == qoi.width * qoi.height - 1
                push!(out, UInt8(QOI_OP_RUN | (run - 1)))
                run = 0
            end
        else
            if run > 0
                push!(out, UInt8(QOI_OP_RUN | (run - 1)))
                run = 0
            end
            i = qoiHash(r, g, b, a)
            if index[i + 1] == (r, g, b, a)
                push!(out, UInt8(QOI_OP_INDEX | i))
            else
                index[i + 1] = (r, g, b, a)
                if a == pa
                    vr = Int(r) - Int(pr)
                    vg = Int(g) - Int(pg)
                    vb = Int(b) - Int(pb)
                    vgr = vr - vg
                    vgb = vb - vg
                    if (vr > -3) && (vr < 2) && (vg > -3) && (vg < 2) &&
                        (vb > -3) && (vb < 2)
                        push!(out, UInt8(QOI_OP_DIFF | ((vr + 2) << 4) |
                            ((vg + 2) << 2) | (vb + 2)))
                    elseif vgr > -9 && vgr < 8 && vg > -33 && vg < 32 &&
                        vgb > -9 && vgb < 8
                        push!(out, UInt8(QOI_OP_LUMA | (vg + 32)))
                        push!(out, UInt8(((vgr + 8) << 4) | (vgb + 8)))
                    else
                        push!(out, UInt8(QOI_OP_RGB), r, g, b)
                    end
                else
                    push!(out, UInt8(QOI_OP_RGBA), r, g, b, a)
                end
            end
            pr, pg, pb, pa = r, g, b, a
        end
    end

    push!(out, zeros(UInt8, 7)...)
    push!(out, 0x01)
    return String(out)
end

"""
Upstream `encodeQoi(Image)`: premultiplied image to straight RGBA (the
upstream toStraightAlpha path) encoded as a Linear 4-channel QOI.
"""
function encodeQOI(image::Image)
    qoi = Qoi(image.width, image.height, 4, Linear,
        Vector{UInt8}(undef, length(image.data)))
    d = image.data
    s = qoi.data
    for k in 0:(image.width * image.height - 1)
        i = 4 * k
        c = toStraightAlpha(
            ColorRGBX(d[i + 1], d[i + 2], d[i + 3], d[i + 4]))
        s[i + 1] = c.r
        s[i + 2] = c.g
        s[i + 3] = c.b
        s[i + 4] = c.a
    end
    return encodeQOI(qoi)
end
