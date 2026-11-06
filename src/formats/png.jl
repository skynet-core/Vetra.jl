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

"""`PNGFiles.save`."""
function _pngSave(buf::IOBuffer, out)
    m = _requirePngFiles()
    m.save(buf, out)
    return nothing
end

"""
Decode PNG bytes into an `Image` (upstream `decodePng(data).convertToImage()`):
straight RGBA in, premultiplied stored pixels out.
"""
function decodePNG(data::Vector{UInt8})
    _requirePngFiles()
    # PNGFiles `load` yields a (w, h) matrix of ColorTypes colors
    # (Gray/GrayA/RGB/RGBA, 8-bit fixed-point; palette expanded).
    # Pre-declare `pixels`: this build loses locals first assigned inside a
    # try block (verified; see T008 notes).
    pixels = nothing
    try
        pixels = _pngLoad(data)
    catch
        throw(ArgumentError("Invalid PNG buffer, unable to load"))
    end
    # PNGFiles returns a (height, width) matrix: pixels[row, col].
    h = size(pixels, 1)
    w = size(pixels, 2)
    image = newImage(w, h)
    d = image.data
    n8(c) = UInt8(round(Float64(c) * 255)) # exact for N0f8 (k/255)
    for y in 1:h
        for x in 1:w
            c = pixels[y, x]
            r = n8(c.r)
            # Channel layout per upstream `writePixels` (png.nim L262):
            # gray, gray+alpha, rgb, rgba -> straight RGBA.
            g = isdefined(c, :g) ? n8(c.g) : r
            b = isdefined(c, :b) ? n8(c.b) : g
            a = isdefined(c, :alpha) ? n8(c.alpha) : 0xff
            p = rgbx(ColorRGBA(r, g, b, a))
            o = 4 * ((y - 1) * w + (x - 1))
            d[o + 1] = p.r
            d[o + 2] = p.g
            d[o + 3] = p.b
            d[o + 4] = p.a
        end
    end
    return image
end

"""
Encode an `Image` to PNG bytes (upstream `encodePng(Image)`): premultiplied
stored pixels are converted to straight RGBA (our `toStraightAlpha`, the
upstream `toStraightAlpha` path) before encoding.
"""
function encodePNG(image::Image)
    _requirePngFiles()
    d = image.data
    # PNGFiles.save expects a column-major (height, width, 4) RGBA array
    # (verified: first dimension is the row). Fill it directly rather than
    # reshaping a row-major byte buffer (Julia is column-major).
    out = Array{UInt8, 3}(undef, image.height, image.width, 4)
    for y in 0:(image.height - 1)
        for x in 0:(image.width - 1)
            i = 4 * (y * image.width + x)
            c = toStraightAlpha(ColorRGBX(d[i + 1], d[i + 2], d[i + 3], d[i + 4]))
            out[y + 1, x + 1, 1] = c.r
            out[y + 1, x + 1, 2] = c.g
            out[y + 1, x + 1, 3] = c.b
            out[y + 1, x + 1, 4] = c.a
        end
    end
    try
        buf = IOBuffer()
        _pngSave(buf, out)
        seekstart(buf)
        return read(buf) # Vector{UInt8} in this build
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
