# ---------- BMP (T008) ----------
# Upstream: pixie/fileformats/bmp.nim -- bmpSignature (L10), decodeDib
# (L19-217), decodeBmp (L219-228), decodeBmpDimensions (L230-250),
# encodeDib (L252-280), encodeBmp (L282-295).
#
# Pinned behavior notes:
# - decodeDib supports BITMAPINFOHEADER (40), BITMAPV2HEADER (108) and
#   BITMAPV3HEADER (124); 1/4/8/24/32 bits; BI_RGB (0) and BI_BITFIELDS (3).
# - 32-bit pixels use the R/G/B/A bit masks; when alphaMask != 0 the
#   masked bytes are straight RGBA (the BMP file boundary) and are
#   converted to premultiplied storage, otherwise the pixel is opaque
#   and goes through straight->premultiplied like the other bit depths.
# - Rows are padded to 4-byte boundaries relative to the pixel-data start.
# - Bottom-up rows by default; top-down (negative height) is handled by the
#   same storage plus a final flipVertical.
# - Upstream's encodeDib writes a 136-byte DIB that claims biSize = 124, so
#   upstream's own decodeBmp of an encodeBmp file reads pixels 12 bytes
#   early; upstream disabled its encode->decode round-trip assertions for
#   this reason (test_bmp.nim, commented blocks). Vetra fixes the encoder
#   (2026-11-12, E001) with a valid 124-byte BITMAPV5HEADER.
# - Divergence from upstream at the 32-bit file boundary (recorded
#   2026-11-12, E001 review): upstream's encoder already wrote straight
#   RGBA (encodeDib's chroma rgba() pass), but its masked decode stored
#   the file bytes directly as premultiplied storage — wrong for partial
#   and zero alpha. The BMP 32-bit format carries straight RGB plus an
#   alpha mask (WIC's primary V5 output format is
#   GUID_WICPixelFormat32bppBGRA; Pillow decodes 32-bit BMP alpha as
#   straight RGBA). Vetra keeps the straight encode and fixes the masked
#   decode (rgbx(rgba(...)) straight -> premul), so files interoperate.
#   The pair still round-trips exactly: for valid premultiplied storage
#   (c <= a), toPremul(toStraight(c, a)) == c (round error < 1/2 channel,
#   cancelled by the (c' * a + 127) div 255). The pinned 32-bit mask
#   fixtures (knight.32, test4x2, test16x16) are upstream oracles of the
#   old direct-store decode; test/formats_tests.jl derives the corrected
#   expectation from the untouched pinned raw (only pixels with stored
#   a < 255 differ) and pins the divergence count explicitly.

const BMP_SIGNATURE = "BM"

function _bmpFail(reason = "unable to load")
    throw(ArgumentError("Invalid BMP buffer, $(reason)"))
end

"""
Upstream `colorMaskShift`: shift the masked bits down to the low byte.
Nim's `firstSetBit` is 1-based, so `shr (firstSetBit - 1)` is the
trailing-zero count.
"""
function bmpMaskShift(color::UInt32, mask::UInt32)
    # Upstream `.uint8` truncates (wide masks keep their low byte); the
    # UInt8() constructor would raise InexactError.
    return UInt8(Int((color & mask) >> trailing_zeros(mask)) & 0xff)
end

"""
Upstream `decodeDib`: DIB bytes (no 14-byte file header). `lpBitmapInfo`
mirrors upstream's clipboard-DIB flag (adds 12 to the pixel offset for
BI_BITFIELDS V3/V5 headers -- see the file-header quirk note).
"""
function decodeDIB(data::Vector{UInt8}; lpBitmapInfo::Bool = false)
    length(data) >= 40 || _bmpFail()

    # BITMAPINFOHEADER (little-endian; 1-based offsets)
    le16(i::Int) = Int(data[i]) | (Int(data[i + 1]) << 8)
    le32(i::Int) = Int(data[i]) | (Int(data[i + 1]) << 8) |
        (Int(data[i + 2]) << 16) | (Int(data[i + 3]) << 24)
    # width/height are signed int32 upstream: a negative height marks
    # top-down storage (without sign extension it would parse as a ~4G
    # allocation).
    # This build infers 0x80000000 as UInt32 and 0x100000000 as UInt64, so
    # use Int shifts instead.
    ile32(i::Int) = let v = le32(i)
        if v >= (1 << 31)
            v - (1 << 32)
        else
            v
        end
    end
    headerSize = le32(1) & 0x7fffffff
    width = ile32(5)
    height = ile32(9)
    planes = le16(13)
    bits = le16(15)
    compression = le32(17) & 0x7fffffff
    colorPaletteSize = le32(33) & 0x7fffffff

    headerSize in (40, 108, 124) || _bmpFail()
    planes == 1 || _bmpFail()
    bits in (1, 4, 8, 24, 32) || throw(ArgumentError("Unsupported BMP bit count"))
    compression in (0, 3) || throw(ArgumentError("Unsupported BMP compression format"))

    redMask = 0x00ff0000
    greenMask = 0x0000ff00
    blueMask = 0x000000ff
    alphaMask = 0xff000000
    flipVert = false
    useAlpha = false

    if compression == 3
        length(data) >= 52 || _bmpFail()
        redMask = le32(41)
        greenMask = le32(45)
        blueMask = le32(49)
        (redMask == 0 || blueMask == 0 || greenMask == 0) && _bmpFail()
    end

    if headerSize > 40
        length(data) >= 56 || _bmpFail()
        alphaMask = le32(53)
        useAlpha = alphaMask != 0
    end

    (colorPaletteSize < 0 || colorPaletteSize > 256) && _bmpFail()
    if bits in (1, 4, 8) && colorPaletteSize == 0
        colorPaletteSize = 1 << bits
    end

    # Color palette (BGRA quadruples, alpha ignored upstream).
    colorPalette = Vector{UInt8}(undef, 4 * colorPaletteSize)
    if colorPaletteSize > 0
        length(data) >= headerSize + colorPaletteSize * 4 || _bmpFail()
        offset = headerSize + 1
        for i in 0:(colorPaletteSize - 1)
            # Upstream 0-based check `offset + 3 > len - 2`.
            offset - 1 + 3 > length(data) - 2 && _bmpFail()
            colorPalette[4 * i + 1] = data[offset + 2] # r
            colorPalette[4 * i + 2] = data[offset + 1] # g
            colorPalette[4 * i + 3] = data[offset] # b
            colorPalette[4 * i + 4] = 0xff
            offset += 4
        end
    end

    if height < 0
        height = -height
        flipVert = true
    end

    image = newImage(width, height)
    d = image.data

    startOffset = headerSize + colorPaletteSize * 4
    if compression == 3 && (headerSize == 40 || lpBitmapInfo)
        startOffset += 12
    end

    # Pixel rows are stored bottom-up by default: file row y goes to image
    # row height - y - 1; the flipVertical below fixes top-down inputs.
    # `off` is the 1-based data index of the next pixel byte.
    off = startOffset + 1
    n = length(data)

    if bits == 1
        haveBits = 0
        colorBits = UInt8(0)
        for y in 0:(height - 1)
            haveBits = 0
            padding = (off - 1 - startOffset) % 4
            if padding > 0
                off += 4 - padding
            end
            for x in 0:(width - 1)
                if haveBits == 0
                    off > n && _bmpFail()
                    colorBits = data[off]
                    haveBits = 8
                    off += 1
                end
                rgba = if (colorBits & 0x80) == 0
                    (colorPalette[1], colorPalette[2], colorPalette[3])
                else
                    (colorPalette[5], colorPalette[6], colorPalette[7])
                end
                colorBits <<= 1
                haveBits -= 1
                i = 4 * ((height - y - 1) * width + x)
                d[i + 1] = rgba[1]
                d[i + 2] = rgba[2]
                d[i + 3] = rgba[3]
                d[i + 4] = 0xff
            end
        end
    elseif bits == 4
        haveBits = 0
        colorBits = UInt8(0)
        for y in 0:(height - 1)
            haveBits = 0
            padding = (off - 1 - startOffset) % 4
            if padding > 0
                off += 4 - padding
            end
            for x in 0:(width - 1)
                if haveBits == 0
                    off > n && _bmpFail()
                    colorBits = data[off]
                    haveBits = 8
                    off += 1
                end
                index = Int((colorBits & 0xf0) >> 4)
                index >= colorPaletteSize && _bmpFail()
                i4 = 4 * index
                colorBits <<= 4
                haveBits -= 4
                i = 4 * ((height - y - 1) * width + x)
                d[i + 1] = colorPalette[i4 + 1]
                d[i + 2] = colorPalette[i4 + 2]
                d[i + 3] = colorPalette[i4 + 3]
                d[i + 4] = 0xff
            end
        end
    elseif bits == 8
        for y in 0:(height - 1)
            padding = (off - 1 - startOffset) % 4
            if padding > 0
                off += 4 - padding
            end
            for x in 0:(width - 1)
                off > n && _bmpFail()
                index = Int(data[off])
                off += 1
                index >= colorPaletteSize && _bmpFail()
                i4 = 4 * index
                i = 4 * ((height - y - 1) * width + x)
                d[i + 1] = colorPalette[i4 + 1]
                d[i + 2] = colorPalette[i4 + 2]
                d[i + 3] = colorPalette[i4 + 3]
                d[i + 4] = 0xff
            end
        end
    elseif bits == 24
        for y in 0:(height - 1)
            padding = (off - 1 - startOffset) % 4
            if padding > 0
                off += 4 - padding
            end
            for x in 0:(width - 1)
                off - 1 + 2 >= n && _bmpFail()
                r = data[off + 2]
                g = data[off + 1]
                b = data[off]
                off += 3
                i = 4 * ((height - y - 1) * width + x)
                d[i + 1] = r
                d[i + 2] = g
                d[i + 3] = b
                d[i + 4] = 0xff
            end
        end
    else # bits == 32
        le32off(i::Int) = Int(data[i]) | (Int(data[i + 1]) << 8) |
            (Int(data[i + 2]) << 16) | (Int(data[i + 3]) << 24)
        for y in 0:(height - 1)
            for x in 0:(width - 1)
                off + 2 >= n && _bmpFail()
                color = le32off(off)
                if useAlpha
                    r = bmpMaskShift(UInt32(color), UInt32(redMask))
                    g = bmpMaskShift(UInt32(color), UInt32(greenMask))
                    b = bmpMaskShift(UInt32(color), UInt32(blueMask))
                    a = bmpMaskShift(UInt32(color), UInt32(alphaMask))
                    off += 4
                    i = 4 * ((height - y - 1) * width + x)
                    # File boundary (BMP/WIC 32bppBGRA, Pillow): the masked
                    # bytes are straight RGBA; convert to premultiplied
                    # storage (a = 0 -> transparent, rgb dropped — see
                    # the file note on the upstream divergence).
                    p = rgbx(rgba(r, g, b, a))
                    d[i + 1] = p.r
                    d[i + 2] = p.g
                    d[i + 3] = p.b
                    d[i + 4] = p.a
                else
                    r = bmpMaskShift(UInt32(color), UInt32(redMask))
                    g = bmpMaskShift(UInt32(color), UInt32(greenMask))
                    b = bmpMaskShift(UInt32(color), UInt32(blueMask))
                    off += 4
                    i = 4 * ((height - y - 1) * width + x)
                    p = rgbx(rgba(r, g, b, 0xff))
                    d[i + 1] = p.r
                    d[i + 2] = p.g
                    d[i + 3] = p.b
                    d[i + 4] = p.a
                end
            end
        end
    end

    if flipVert
        flipVertical(image)
    end

    return image
end

"""Upstream `decodeBmp`: 14-byte file header ("BM") then the DIB."""
function decodeBMP(data::Vector{UInt8})
    length(data) < 14 && _bmpFail()
    (data[1] != 0x42 || data[2] != 0x4d) && _bmpFail() # "BM"
    return decodeDIB(data[15:end])
end

"""Upstream `decodeBmpDimensions`: file header plus BITMAPINFOHEADER size/w/h."""
function decodeBMPDimensions(data::Vector{UInt8})
    length(data) < 26 && _bmpFail()
    (data[1] != 0x42 || data[2] != 0x4d) && _bmpFail()
    le32(i::Int) = Int(data[i]) | (Int(data[i + 1]) << 8) |
        (Int(data[i + 2]) << 16) | (Int(data[i + 3]) << 24)
    ile32(i::Int) = let v = le32(i)
        if v >= (1 << 31)
            v - (1 << 32)
        else
            v
        end
    end
    w = ile32(19)
    h = abs(ile32(23))
    return (w, h)
end

"""
Upstream `encodeDib`, corrected: a valid 124-byte BITMAPV5 header (biSize
equals the actual size — upstream wrote 136 bytes under the 124 claim),
32-bit BI_BITFIELDS pixels with the standard masks, straight RGBA at the
file boundary (toStraightAlpha — see the file-header note), rows
bottom-up.
"""
function encodeDIB(image::Image)
    out = Vector{UInt8}()
    addle32(v::Integer) = append!(out, [UInt8(v & 0xff), UInt8((v >> 8) & 0xff),
        UInt8((v >> 16) & 0xff), UInt8((v >> 24) & 0xff)])
    addle16(v::Integer) = append!(out, [UInt8(v & 0xff), UInt8((v >> 8) & 0xff)])

    addle32(124) # size of this header
    addle32(UInt32(image.width & 0xffffffff))
    addle32(UInt32(image.height & 0xffffffff))
    addle16(1) # planes
    addle16(32) # bits per pixel
    addle32(3) # BI_BITFIELDS
    addle32(32) # raw bitmap size
    addle32(2835) # print resolution x
    addle32(2835) # print resolution y
    addle32(0) # colors in palette
    addle32(0) # important colors
    addle32(0x000000ff) # red mask
    addle32(0x0000ff00) # green mask
    addle32(0x00ff0000) # blue mask
    addle32(0xff000000) # alpha mask
    addle32(0x73524742) # LCS_sRGB
    append!(out, zeros(UInt8, 64)) # V4/V5 fields (zero-filled) -> 124 total

    d = image.data
    # Rows are written bottom-up: file row y is image row h - y - 1
    # (upstream `image[x, image.height - y - 1]`).
    # File boundary (BMP/WIC 32bppBGRA, Pillow): the file carries straight
    # RGBA, so stored premultiplied bytes go through toStraightAlpha
    # before writing (a = 0 -> all-zero pixel); decodeDIB's masked path
    # applies the inverse, and the pair round-trips exactly on valid
    # premultiplied storage (see the file note on the upstream divergence).
    for y in 0:(image.height - 1)
        for x in 0:(image.width - 1)
            i = 4 * ((image.height - 1 - y) * image.width + x)
            p = toStraightAlpha(ColorRGBX(d[i + 1], d[i + 2],
                d[i + 3], d[i + 4]))
            append!(out, [p.r, p.g, p.b, p.a])
        end
    end

    return String(out)
end

"""
Upstream `encodeBmp`, corrected: "BM" file header (size patched at the end)
plus the DIB; the pixel offset field is 14 + 124 = 138 (upstream wrote 150
to match its 136-byte header).
"""
function encodeBMP(image::Image)
    out = Vector{UInt8}()
    append!(out, UInt8['B', 'M'])
    push!(out, 0, 0, 0, 0) # file size (patched below)
    push!(out, 0, 0, 0, 0) # reserved
    push!(out, 138, 0, 0, 0) # offset to pixel array (14 + 124-byte V5 header)
    dib = encodeDIB(image)
    append!(out, codeunits(dib))
    # Patch the file size at offset 2 (little-endian).
    v = UInt32(length(out))
    out[3] = UInt8(v & 0xff)
    out[4] = UInt8((v >> 8) & 0xff)
    out[5] = UInt8((v >> 16) & 0xff)
    out[6] = UInt8((v >> 24) & 0xff)
    return String(out)
end
