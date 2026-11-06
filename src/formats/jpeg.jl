# ---------- JPEG (T008) ----------
# Upstream: pixie/fileformats/jpeg.nim (stb-derived decoder, reference-only
# per D008). Pixel decoding is the opt-in `JpegTurbo` package (libjpeg-turbo);
# this file ports natively what upstream exposes around it:
# - jpegStartOfImage (L45): the 0xFFD8 marker check;
# - decodeJpegDimensions (L675-706): marker scan, SOF0/SOF2, the
#   "unsupported extended sequential DCT format" error for SOF1, and Exif
#   orientation (decodeExif L460-538) swapping width/height for
#   orientations 5..8;
# - readMarker resync (L188-222): up to 64 junk bytes between markers.
#
# JPEG is lossy: decoded pixels match libjpeg-turbo, which may differ from
# upstream's own stb-derived decoder (no pinned fixture compares the two;
# our test fixture jpeg_*.raw is the upstream decoder's output and is used
# for structure/dimension checks, not exact pixels).

const JPEG_START_OF_IMAGE = (0xff, 0xd8)

const _JPEGTURBO_PKGID = Base.PkgId(
    Base.UUID("b835a17e-a41a-41e7-81f0-2f016b05efe0"), "JpegTurbo")

"""
The loaded `JpegTurbo` module, or raise a clear install hint (D014).
JpegTurbo is required eagerly at module load when present (see end of
file); that is what makes the codec callable: this build freezes
precompiled code in the precompile-time world, and methods of a package
first required at runtime dispatch as "too new" even under
`Base.invokelatest`. Environments without it load normally and get this
error only on use.
"""
function _requireJpegTurbo()
    try
        return Base.root_module(_JPEGTURBO_PKGID)
    catch
        throw(ErrorException(
            "JPEG support is opt-in: add the JpegTurbo package to your " *
            "environment (Pkg.add(\"JpegTurbo\")) and retry"))
    end
end

"""
Decode JPEG bytes into an `Image` (upstream `decodeJpeg`): 8-bit RGB in,
opaque premultiplied pixels out (a = 255 throughout).
"""
function decodeJPEG(data::Vector{UInt8})
    m = _requireJpegTurbo()
    # Pre-declare: this build loses locals first assigned inside a try block.
    pixels = nothing
    try
        pixels = Base.invokelatest(m.jpeg_decode, data)
    catch
        throw(ArgumentError("Invalid JPEG, unable to load"))
    end
    # JpegTurbo returns `permutedims(out, (2, 1))` of the (width, height)
    # decode: a (height, width) view with pixels[row, col].
    h = size(pixels, 1)
    w = size(pixels, 2)
    image = newImage(w, h)
    d = image.data
    n8(c) = UInt8(round(Float64(c) * 255)) # exact for N0f8 (k/255)
    for y in 1:h
        for x in 1:w
            c = pixels[y, x]
            # Grayscale JPEGs yield Gray colors (a `val` field, no r/g/b).
            if isdefined(c, :val)
                v = n8(c.val)
                r = v
                g = v
                b = v
            else
                r = n8(c.r)
                g = isdefined(c, :g) ? n8(c.g) : r
                b = isdefined(c, :b) ? n8(c.b) : g
            end
            p = rgbx(ColorRGBA(r, g, b, 0xff))
            o = 4 * ((y - 1) * w + (x - 1))
            d[o + 1] = p.r
            d[o + 2] = p.g
            d[o + 3] = p.b
            d[o + 4] = p.a
        end
    end
    return image
end

# ---- native dimensions scan (upstream decodeJpegDimensions) ----

const _JPEG_MAX_MARKER_RESYNC = 64

function _jpegFail(reason::String = "unable to load")
    throw(ArgumentError("Invalid JPEG, $(reason)"))
end

"""
Upstream `readMarker` resync: find the next 0xFFxx marker, skipping up to
64 non-marker bytes (0xD9 is reported once SOS was found -- unreachable in
the dimensions scan, which stops at SOF).
"""
function _jpegReadMarker(data::Vector{UInt8}, pos::Int)
    n = length(data)
    skipped = 0
    while true
        # 1-based; upstream 0-based `pos >= len`.
        pos > n && _jpegFail("missing marker")
        marker = Int(data[pos])
        if marker != 0xff
            skipped += 1
            skipped > _JPEG_MAX_MARKER_RESYNC && _jpegFail("invalid chunk marker")
            pos += 1
            continue
        end
        while pos + 1 <= n && Int(data[pos + 1]) == 0xff
            pos += 1
        end
        pos + 1 > n && _jpegFail("missing marker id")
        pos += 1
        id = Int(data[pos])
        pos += 1
        if id == 0
            skipped += 1
            skipped > _JPEG_MAX_MARKER_RESYNC && _jpegFail("invalid chunk marker")
            continue
        end
        return id, pos
    end
end

"""Upstream `skipChunk`: skip a length-prefixed marker payload."""
function _jpegSkipChunk(data::Vector{UInt8}, pos::Int)
    n = length(data)
    pos + 1 > n && _jpegFail()
    lenField = (Int(data[pos]) << 8) | Int(data[pos + 1])
    # The chunk's last payload byte (pos + lenField - 1) must be in the
    # buffer; upstream `skipBytes` allows pos + len == state.len.
    pos + lenField - 1 > n && _jpegFail()
    return pos + lenField
end

"""Upstream `decodeDHT` on the dimensions path — validates the Huffman
chunk structure (per-table info byte, 16 counts, count sum, symbol bytes,
exact remaining length) and returns the position past the chunk. Malformed
tables raise, as upstream `failInvalid` does (upstream's foundSOS clamps
never trigger here: the scan stops at SOF)."""
function _jpegDHT(data::Vector{UInt8}, pos::Int)
    n = length(data)
    pos + 1 > n && _jpegFail()
    lenField = (Int(data[pos]) << 8) | Int(data[pos + 1])
    len = lenField - 2
    p = pos + 2
    while len > 0
        p > n && _jpegFail()
        info = Int(data[p])
        p += 1
        tableId = info & 15
        tableCurrent = info >> 4
        (tableCurrent > 1 || tableId > 3) && _jpegFail()
        numSymbols = 0
        for i in 1:16
            p > n && _jpegFail()
            numSymbols += Int(data[p])
            p += 1
        end
        numSymbols > 256 && _jpegFail()
        len -= 17
        p + numSymbols - 1 > n && _jpegFail()
        p += numSymbols
        len -= numSymbols
    end
    len != 0 && _jpegFail()
    return pos + lenField
end

"""
Upstream `decodeExif`: parse the APP1 "Exif" chunk and return the
orientation tag (1..8), or 0 when absent/invalid (the upstream
skipInvalidExif paths leave orientation at its default 0). `pos` is the
chunk's length field. Upstream's fixed reads check against the whole
buffer; the IFD/tag bounds check against the chunk end.
"""
function _jpegExifOrientation(data::Vector{UInt8}, pos::Int)
    n = length(data)
    pos + 1 > n && _jpegFail()
    lenField = (Int(data[pos]) << 8) | Int(data[pos + 1])
    chunkEnd = pos + lenField
    # Upstream `if chunkEnd > state.len: failInvalid()` (0-based exclusive
    # chunkEnd); 1-based, the last payload byte is chunkEnd - 1.
    chunkEnd - 1 > n && _jpegFail()
    p = pos + 2

    be16(q::Int) = (Int(data[q]) << 8) | Int(data[q + 1])
    rd16(le::Bool, q::Int) = le ? (Int(data[q]) | (Int(data[q + 1]) << 8)) : be16(q)
    rd32(le::Bool, q::Int) = le ?
        (Int(data[q]) | (Int(data[q + 1]) << 8) | (Int(data[q + 2]) << 16) |
            (Int(data[q + 3]) << 24)) :
        ((Int(data[q]) << 24) | (Int(data[q + 1]) << 16) |
            (Int(data[q + 2]) << 8) | Int(data[q + 3]))

    p + 5 > n && _jpegFail()
    exifHeader = String(data[p:(p + 5)])
    p += 6
    if exifHeader != "Exif\0\0"
        # Upstream: happens with progressive images; skip instead of error.
        return 0
    end

    p + 1 > n && _jpegFail()
    tiffHeader = be16(p)
    p += 2
    littleEndian = if tiffHeader == 0x4d4d
        false
    elseif tiffHeader == 0x4949
        true
    else
        return 0 # upstream skipInvalidExif
    end

    p + 1 > n && _jpegFail()
    rd16(littleEndian, p) != 0x002a && return 0
    p += 2

    p + 3 > n && _jpegFail()
    offsetToFirstIFD = rd32(littleEndian, p)
    p += 4
    offsetToFirstIFD < 8 && return 0
    p + offsetToFirstIFD - 8 > chunkEnd && return 0
    p += offsetToFirstIFD - 8

    p + 2 > chunkEnd && return 0
    numTags = rd16(littleEndian, p)
    p += 2

    orientation = 0
    for i in 0:(numTags - 1)
        # Upstream: `pos + 12 > chunkEnd` -> skipInvalidExif, which returns
        # with the orientation accumulated so far. (1-based: the 12 bytes
        # are p..p+11, so the last byte p+11 must be < chunkEnd.)
        p + 12 > chunkEnd && return orientation
        tagNumber = rd16(littleEndian, p)
        dataOffset = rd32(littleEndian, p + 8)
        p += 12
        if tagNumber == 0x0112
            orientation = (dataOffset >> 16) & 0xffff
        end
    end

    return orientation
end

"""
Upstream `decodeJpegDimensions`: scan to SOF0/SOF2, apply Exif orientation.
Returns `(width, height)`.
"""
function decodeJPEGDimensions(data::Vector{UInt8})
    orientation = 0
    imageWidth = 0
    imageHeight = 0
    pos = 1
    n = length(data)
    be16(q::Int) = (Int(data[q]) << 8) | Int(data[q + 1])

    while true
        # Upstream readMarker resync (junk counting included).
        (id, pos) = _jpegReadMarker(data, pos)

        if id == 0xd8
            # SOI
            continue
        elseif id == 0xc0 || id == 0xc2
            # SOF0 / SOF2: len (2), precision (1), height (2), width (2).
            pos + 6 > n && _jpegFail()
            imageHeight = be16(pos + 3)
            imageWidth = be16(pos + 5)
            break
        elseif id == 0xc1
            _jpegFail("unsupported extended sequential DCT format")
        elseif id in (0xd0, 0xd1, 0xd2, 0xd3, 0xd4, 0xd5, 0xd6, 0xd7)
            # Restart markers carry no length.
            continue
        elseif id == 0xe1
            # Exif/APP1
            orientation = _jpegExifOrientation(data, pos)
            pos = _jpegSkipChunk(data, pos)
        elseif id == 0xc4
            # DHT: upstream `decodeJpegDimensions` calls `decodeDHT`, which
            # validates the table structure (not a plain skip).
            pos = _jpegDHT(data, pos)
        elseif id in (0xdb, 0xdc, 0xdd, 0xe0) ||
            (0xe2 <= id <= 0xef) || id == 0xfe
            # DQT / DNL / APP0 / APP2-15 / COM: length-prefixed, skipped.
            pos = _jpegSkipChunk(data, pos)
        else
            # Upstream `failInvalid("invalid chunk " & chunkId.toHex())`.
            _jpegFail("invalid chunk $(
                _upperHex4(id))")
        end
    end

    if orientation in (5, 6, 7, 8)
        return (imageHeight, imageWidth)
    elseif orientation in (0, 1, 2, 3, 4)
        return (imageWidth, imageHeight)
    else
        _jpegFail("invalid orientation")
    end
end

# Eager optional require (world-age fix, T008): load JpegTurbo at module
# load when it is in the environment, so its methods predate the frozen
# precompile world and `decodeJPEG` is callable from precompiled code.
# Environments without it load Vetra normally; `decodeJPEG` raises the
# install hint on use. (Dimensions need no package.)
try
    Base.require(_JPEGTURBO_PKGID)
catch
end
