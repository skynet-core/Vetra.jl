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
The `JpegTurbo` module loaded by Vetra.__init__, or a clear install hint
(D014). Environments without JpegTurbo load normally and get this error
only on use.
"""
function _requireJpegTurbo()
    if Base.locate_package(_JPEGTURBO_PKGID) === nothing
        throw(ErrorException(
            "JPEG support is opt-in: add the JpegTurbo package to your " *
            "environment (Pkg.add(\"JpegTurbo\")) and retry"))
    end
    return Base.require(_JPEGTURBO_PKGID)
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
    Base.invokelatest(_decodeJPEGPixels!, image, pixels, w, h)
    return image
end

"""Kernel for `decodeJPEG`: the provider's `[row, col]` color matrix into
premultiplied `image` bytes (opaque, `a = 255` — JPEG carries no alpha;
grayscale yields `Gray` colors with a `val` field). Called with
`Base.invokelatest`: the `N0f8 → Float64` conversion is defined by
FixedPointNumbers, which may be required (lazy discovery, D028) by this
very decode call.
"""
function _decodeJPEGPixels!(image::Image, pixels, w::Int, h::Int)
    d = image.data
    for y in 1:h
        for x in 1:w
            c = pixels[y, x]
            if isdefined(c, :val)
                r = UInt8(round(Float64(c.val) * 255))
                g = r
                b = r
            else
                r = UInt8(round(Float64(c.r) * 255))
                g = isdefined(c, :g) ? UInt8(round(Float64(c.g) * 255)) : r
                b = isdefined(c, :b) ? UInt8(round(Float64(c.b) * 255)) : g
            end
            o = 4 * ((y - 1) * w + (x - 1))
            d[o + 1] = r
            d[o + 2] = g
            d[o + 3] = b
            d[o + 4] = 0xff
        end
    end
    return nothing
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

# ---- encode (T031, D032, docs/JPEG_WEBP_CODECS.md §2) ----

"""libjpeg-turbo's MAX_JPEG_DIMENSION: the provider segfaults in
`jinit_compress_master` at 65501 (C-level, uncatchable — bisected in the
T030 probe), so the API boundary rejects before encoding."""
const _JPEG_MAX_DIMENSION = 65500

"""Contract §2.2: composite a premultiplied channel `p8` over background
`b8` with alpha `a8`. Exact integer, no division by alpha:
`(p8*255 + b8*(255-a8) + 127) div 255`, clamped to 0..255 (`a8 = 255` →
`p8`, `a8 = 0` → `b8`)."""
function _jpegComposite(p8::Int, b8::Int, a8::Int)
    v = (p8 * 255 + b8 * (255 - a8) + 127) ÷ 255
    return clamp(v, 0, 255)
end

"""Kernel for `encodeJPEG`: composite the premultiplied `d` bytes over the
background into the straight `RGB{N0f8}` matrix `out` (contract §2.2). The
channel type is read once from the matrix eltype (function barrier, as in
`toColors`); call via `Base.invokelatest` because ColorTypes may be
required (lazy discovery, D028) by this very call.
"""
function _encodeJPEGMatrix!(out::Matrix{C}, d::Vector{UInt8}, w::Int, h::Int,
    br::Int, bg::Int, bb::Int) where {C}
    T = C.parameters[1]
    for y in 1:h
        row = 4 * (y - 1) * w
        for x in 1:w
            i = row + 4 * (x - 1)
            a = Int(d[i + 4])
            out[y, x] = C(
                T(_jpegComposite(Int(d[i + 1]), br, a) / 255),
                T(_jpegComposite(Int(d[i + 2]), bg, a) / 255),
                T(_jpegComposite(Int(d[i + 3]), bb, a) / 255))
        end
    end
    return nothing
end

"""
Encode an `Image` as JPEG bytes (T031, D032 — docs/JPEG_WEBP_CODECS.md
§2). Straight RGB is composited over `background` (default white — the
contract's transparency policy; alpha is never silently dropped).
Output is baseline JFIF with the contract-mandated 72×72 dpi density
(§2.3), no EXIF/Adobe; `quality` is 1..100 (default 92, the provider
default) and dimensions must be ≤ 65500 per side (§2.4). Out-of-range
arguments raise named `ArgumentError`s; without `JpegTurbo` the existing
install hint applies.
"""
function encodeJPEG(image::Image; quality::Int = 92,
    background::ColorRGB = rgb(255, 255, 255))
    m = _requireJpegTurbo()
    CT = _requireColorTypes()
    (1 <= quality <= 100) ||
        throw(ArgumentError("JPEG quality must be 1..100"))
    (image.width <= _JPEG_MAX_DIMENSION &&
        image.height <= _JPEG_MAX_DIMENSION) ||
        throw(ArgumentError("JPEG dimension exceeds 65500"))
    w = image.width
    h = image.height
    # Provider matrix: ImageCore `[row=y, col=x]`, N0f8 values exact.
    mat = Matrix{CT.RGB{CT.N0f8}}(undef, h, w)
    Base.invokelatest(_encodeJPEGMatrix!, mat, image.data, w, h,
        Int(background.r), Int(background.g), Int(background.b))
    return Base.invokelatest(m.jpeg_encode, mat; quality = quality,
        density_unit = 1, X_density = 72, Y_density = 72)
end
