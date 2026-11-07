# ---------- PNG (T008) ----------
# Upstream reference: pixie/fileformats/png.nim (zippy-based, reference-only
# per D008). The codec itself is the opt-in `PNGFiles` package (libpng);
# this file pins the boundary conversions upstream applies:
# - decode: PNG straight RGBA -> `toPremultipliedAlpha` (our `rgbx`) into
#   the stored premultiplied image (upstream `newImage(Png)` L584-593);
# - encode: stored premultiplied -> `toStraightAlpha` (upstream
#   `encodePng(Image)` L888-897) before the 8-bit RGBA payload;
# - dimensions read the IHDR only (upstream `decodePngDimensions` L613-633).
#
# Pinned differences (recorded in COMPATIBILITY):
# - 16-bit PNGs: libpng strips to 8-bit (high byte); upstream scales
#   `(v * 255 + 32767) div 65535` (png.nim `toUint8` L251-252). No pinned
#   fixture exercises 16-bit input.
# - Encode settings: PNGFiles `save` runs with its package defaults
#   (level Z_BEST_SPEED, strategy Z_RLE, PAETH filter); the measured
#   alternative filter/strategy combinations were within run-to-run
#   noise on the benchmark workload, so no override is pinned.
# - Interlacing/palette/tRNS are handled by libpng exactly per the PNG
#   spec; upstream's own decoder (png.nim L641-756) produces identical
#   pixels for valid files.
#
# PNG support is opt-in (D014): `PNGFiles` is loaded by Vetra.__init__
# when available in the active environment; a missing package makes the PNG
# entry points raise `ErrorException` with the install hint on use.

const _PNGFILES_PKGID = Base.PkgId(
    Base.UUID("f57f5aa1-a3ce-4bc8-8ab9-96f992907883"), "PNGFiles")

"""
The `PNGFiles` module loaded by Vetra.__init__, or a clear install hint
(D014). Environments without PNGFiles load normally and get this error
only on use.
"""
function _requirePngFiles()
    try
        return Base.root_module(_PNGFILES_PKGID)
    catch
        throw(ErrorException(
            "PNG support is opt-in: add the PNGFiles package to your " *
            "environment (Pkg.add(\"PNGFiles\")) and retry"))
    end
end

"""`PNGFiles.load` (invokelatest: cross-module keyword call)."""
function _pngLoad(data::Vector{UInt8})
    m = _requirePngFiles()
    return Base.invokelatest(m.load, IOBuffer(data), expand_paletted = true)
end

"""
Decode PNG bytes into an `Image` (upstream `decodePng(data).convertToImage()`):
straight RGBA in, premultiplied stored pixels out.
"""
function decodePNG(data::Vector{UInt8})
    _requirePngFiles()
    # Keep the decoded matrix in scope after the try block.
    pixels = nothing
    try
        pixels = _pngLoad(data)
    catch
        throw(ArgumentError("Invalid PNG buffer, unable to load"))
    end
    h = size(pixels, 1)
    w = size(pixels, 2)
    image = newImage(w, h)
    # `_pngLoad` dispatches through `invokelatest`, so `pixels` reaches here
    # as `Any`; the kernel function is specialized on the concrete element
    # type (function-barrier pattern, per the performance manual), keeping
    # the per-pixel loop hot instead of a generic getindex per pixel.
    _decodePngPixels!(pixels, image.data, w, h)
    return image
end

"""
Kernel for `decodePNG`: straight 8-bit ColorTypes pixels (Gray/GrayA/RGB/
RGBA of `FixedPointNumbers.N0f8`, whose channel's `.i` field is the raw
byte — exactly what `UInt8(round(Float64(ch) * 255))` yields, verified on
the pinned fixtures) converted to premultiplied `d` bytes. Channel fields
are tested once on the concrete element type `C`, never per pixel.
"""
function _decodePngPixels!(pixels::AbstractMatrix{C}, d::Vector{UInt8}, w::Int, h::Int) where {C}
    fn = fieldnames(C)
    hasG = :g in fn
    hasB = :b in fn
    hasA = :alpha in fn
    # (y, x) ranges over the matrix; every d[..] access stays in range.
    @inbounds for y in 1:h
        row = 4 * (y - 1) * w
        for x in 1:w
            c = pixels[y, x]
            r = hasG ? c.r.i : c.value.i
            g = hasG ? c.g.i : r
            b = hasB ? c.b.i : g
            a = hasA ? c.alpha.i : UInt8(0xff)
            # chroma `rgbx(ColorRGBA)`: straight -> premultiplied,
            # `(v * a + 127) div 255`.
            ai = Int(a)
            o = row + 4 * (x - 1)
            d[o + 1] = UInt8((Int(r) * ai + 127) ÷ 255)
            d[o + 2] = UInt8((Int(g) * ai + 127) ÷ 255)
            d[o + 3] = UInt8((Int(b) * ai + 127) ÷ 255)
            d[o + 4] = a
        end
    end
    return nothing
end

"""
Encode an `Image` to PNG bytes (upstream `encodePng(Image)`): premultiplied
stored pixels are converted to straight RGBA (our `toStraightAlpha`, the
upstream `toStraightAlpha` path) before encoding.
"""
function encodePNG(image::Image)
    png = _requirePngFiles()
    d = image.data
    w = image.width
    h = image.height
    # PNGFiles.save expects a column-major (height, width, 4) RGBA array.
    # Fill its linear layout ((c-1)*w*h + x*h + y), then reshape without copying.
    out = Vector{UInt8}(undef, h * w * 4)
    plane = w * h
    @inbounds for y in 0:(h - 1)
        srow = 4 * y * w
        for x in 0:(w - 1)
            i = srow + 4 * x
            a = d[i + 4]
            k = x * h + y
            # Opaque pixels need no conversion; share the pinned formula otherwise.
            c = a == 0xff ? ColorRGBA(d[i + 1], d[i + 2], d[i + 3], a) :
                toStraightAlpha(ColorRGBX(d[i + 1], d[i + 2], d[i + 3], a))
            out[k + 1] = c.r
            out[k + plane + 1] = c.g
            out[k + 2 * plane + 1] = c.b
            out[k + 3 * plane + 1] = c.a
        end
    end
    try
        buf = IOBuffer()
        png.save(buf, reshape(out, h, w, 4))
        seekstart(buf)
        return read(buf)
    catch
        throw(ArgumentError("Unexpected error compressing PNG image data"))
    end
end

"""
Read the PNG dimensions from an IHDR header (upstream
`decodePngDimensions`): magic + first chunk checks, big-endian width/height.
No codec package needed.
"""
function decodePNGDimensions(data::Vector{UInt8})
    # 8 signature + (4 len + 4 type + 13 IHDR data + 4 CRC) + trailing room.
    length(data) < 8 + (8 + 13 + 4) + 4 &&
        throw(ArgumentError("Invalid PNG buffer, unable to load"))
    signature = UInt8[0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]
    if data[1:8] != signature
        throw(ArgumentError("Invalid PNG buffer, unable to load"))
    end
    # First chunk must be IHDR (length 13). Convert to Int before shifting:
    # this build's `UInt8 << n` wraps to UInt8, losing high bytes for
    # dimensions over 255.
    be32(q::Int) = (Int(data[q]) << 24) | (Int(data[q + 1]) << 16) |
        (Int(data[q + 2]) << 8) | Int(data[q + 3])
    len = be32(9)
    if len != 13 || data[13:16] != UInt8[0x49, 0x48, 0x44, 0x52]
        throw(ArgumentError("Invalid PNG buffer, unable to load"))
    end
    w = be32(17)
    h = be32(21)
    return (w, h)
end
