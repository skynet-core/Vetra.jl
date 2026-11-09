# ---------- format dispatch, file IO, base64 (T008) ----------
# Upstream: pixie.nim L11-135 (FileFormat, decodeImageDimensions,
# decodeImage, readImageDimensions, readImage, encodeImage, writeFile)
# and pixie/imagebase64.nim (encodeBase64, decodeBase64, getPayload).
#
# D014 (extended by D032/T031/T032): all seven upstream read formats are
# supported. PNG (PNGFiles), SVG (XML), JPEG (JpegTurbo) and WebP (WebP)
# are opt-in codec packages; PPM, BMP, QOI and GIF are native ports.
# Upstream only encodes PNG, BMP, QOI and PPM; T031 adds JPEG encoding
# (encodeImage JpegFormat → encodeJPEG, opt-in JpegTurbo) and T032 adds
# WebP read/write (decodeImage RIFF+WEBP branch, encodeImage WebpFormat
# → encodeWebP, opt-in WebP). Only Gif encoding still raises
# "Unsupported file format", as does writeFile for .gif.
#
# Pinned upstream quirks kept:
# - decodeImageDimensions has no XML/SVG case: SVG bytes raise
#   "Unsupported image file format" there while decodeImage renders them.
# - Magic guards in pixie.nim order: PNG len > 8, JPEG len > 2, BMP
#   len > 2, SVG len > 5, GIF len > 6, QOI len > 14 + 8, PPM len > 9.
# - readImage/readImageDimensions wrap OS IO errors in the upstream
#   PixieError (here ArgumentError) carrying the system message.
# - base64 is a small native strict RFC-4648 implementation (upstream
#   Nim uses std/base64, whose decode raises ValueError on invalid
#   input; decodeBase64 re-raises that as PixieError).

"""Upstream `FileFormat` enum (member order pinned)."""
@enum FileFormat begin
    PngFormat
    BmpFormat
    JpegFormat
    GifFormat
    QoiFormat
    PpmFormat
    WebpFormat
end

const PNG_SIGNATURE = (0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a)

"""Uppercase 2-hex-digit rendering (upstream `toHex` on a uint8)."""
function _upperHex4(v::Int)
    digits = "0123456789ABCDEF"
    return digits[1 + ((v >> 4) & 0xf)] * digits[1 + (v & 0xf)]
end

"""
Decode image bytes by magic signature (upstream `decodeImage`).
Unsupported or unrecognizable data raises
`ArgumentError("Unsupported image file format")`.
"""
function decodeImage(data::Vector{UInt8})
    if length(data) > 8 && Tuple(data[1:8]) == PNG_SIGNATURE
        return decodePNG(data)
    end
    if length(data) > 2 && Tuple(data[1:2]) == JPEG_START_OF_IMAGE
        return decodeJPEG(data)
    end
    if length(data) > 2 && data[1] == 0x42 && data[2] == 0x4d
        return decodeBMP(data)
    end
    if length(data) > 5 && (String(data[1:5]) == SVG_XML_SIGNATURE ||
            String(data[1:4]) == SVG_SIGNATURE)
        return newImage(parseSvg(String(data)))
    end
    if length(data) > 6 && String(data[1:6]) in GIF_SIGNATURES
        return newImage(decodeGIF(data))
    end
    if length(data) > 22 && String(data[1:4]) == QOI_SIGNATURE
        return newImage(decodeQOI(data))
    end
    if length(data) > 9 && String(data[1:2]) in PPM_SIGNATURES
        return decodePPM(data)
    end
    if length(data) >= 30 && String(data[1:4]) == "RIFF" &&
            String(data[9:12]) == "WEBP"
        return decodeWebP(data)
    end
    throw(ArgumentError("Unsupported image file format"))
end

"""
Decode image dimensions from bytes (upstream `decodeImageDimensions`);
returns `(width, height)`. Note: like upstream, SVG is not handled here.
"""
function decodeImageDimensions(data::Vector{UInt8})
    if length(data) > 8 && Tuple(data[1:8]) == PNG_SIGNATURE
        return decodePNGDimensions(data)
    end
    if length(data) > 2 && Tuple(data[1:2]) == JPEG_START_OF_IMAGE
        return decodeJPEGDimensions(data)
    end
    if length(data) > 2 && data[1] == 0x42 && data[2] == 0x4d
        return decodeBMPDimensions(data)
    end
    if length(data) > 6 && String(data[1:6]) in GIF_SIGNATURES
        return decodeGIFDimensions(data)
    end
    if length(data) > 22 && String(data[1:4]) == QOI_SIGNATURE
        return decodeQOIDimensions(data)
    end
    if length(data) > 9 && String(data[1:2]) in PPM_SIGNATURES
        return decodePPMDimensions(data)
    end
    if length(data) >= 30 && String(data[1:4]) == "RIFF" &&
            String(data[9:12]) == "WEBP"
        return decodeWebPDimensions(data)
    end
    throw(ArgumentError("Unsupported image file format"))
end

"""
OS error message of `e` (a `SystemError`). Standard Julia names the field
`msg`; this stripped build renames it `prefix`. Falls back to `string(e)`.
"""
function _osErrorMsg(e)
    for f in (:msg, :prefix)
        try
            return getfield(e, f)
        catch
        end
    end
    return string(e)
end

"""Read a whole file; OS errors become `ArgumentError` with the system message."""
function _readFileBytes(path::String)
    return try
        read(path) # Vector{UInt8}; `read(path, Vector{UInt8})` is unsupported here
    catch e
        throw(ArgumentError(_osErrorMsg(e)))
    end
end

"""Load an image from a file (upstream `readImage`)."""
function readImage(path::String)
    return decodeImage(_readFileBytes(path))
end

"""Decode an image's dimensions from a file (upstream `readImageDimensions`)."""
function readImageDimensions(path::String)
    return decodeImageDimensions(_readFileBytes(path))
end

"""
Encode an image to bytes (upstream `encodeImage`). PNG, BMP, QOI and PPM
are implemented natively; JpegFormat via the opt-in `JpegTurbo` package
(T031, D032) and WebpFormat via the opt-in `WebP` package (T032, D032);
GifFormat raises `ArgumentError("Unsupported file format")`, as upstream
does for GIF.
"""
function encodeImage(image::Image, format::FileFormat)
    if format === PngFormat
        return encodePNG(image)
    elseif format === BmpFormat
        return encodeBMP(image)
    elseif format === QoiFormat
        return encodeQOI(image)
    elseif format === PpmFormat
        return encodePPM(image)
    elseif format === JpegFormat
        return encodeJPEG(image)
    elseif format === WebpFormat
        return encodeWebP(image)
    else
        throw(ArgumentError("Unsupported file format"))
    end
end

"""
Write an image to a file, the format chosen by the file extension
(upstream `writeFile`). Unknown extensions raise `ArgumentError("Unsupported
file extension")`; JPEG writes via `encodeJPEG` (T031) and WebP via
`encodeWebP` (T032); the still-deferred GIF write reaches the
`encodeImage` error.
"""
function writeFile(image::Image, path::String)
    ext = lowercase(splitext(basename(path))[2])
    format = if ext == ".png"
        PngFormat
    elseif ext == ".bmp"
        BmpFormat
    elseif ext == ".jpg" || ext == ".jpeg"
        JpegFormat
    elseif ext == ".qoi"
        QoiFormat
    elseif ext == ".ppm"
        PpmFormat
    elseif ext == ".webp"
        WebpFormat
    else
        throw(ArgumentError("Unsupported file extension"))
    end
    try
        write(path, encodeImage(image, format))
    catch e
        throw(ArgumentError(_osErrorMsg(e)))
    end
    return nothing
end

"""Upstream `getPayload`: the base64 payload of plain data or a data URL."""
function _base64Payload(data::String)
    if startswith(data, "data:")
        comma = findfirst(',', data)
        comma === nothing && throw(ArgumentError("Invalid data URL"))
        return comma < length(data) ? data[comma + 1:end] : ""
    end
    return data
end

const _B64_ALPHABET =
    "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"

const _B64_VALUE = begin
    d = Dict{Char,Int}()
    for (i, c) in enumerate(_B64_ALPHABET)
        d[c] = i - 1
    end
    d
end

"""Strict RFC-4648 validation (see file header); raises `ArgumentError`."""
function _base64Validate(s::String)
    n = length(s)
    n == 0 && return
    pad = 0
    i = n
    while i > 0 && s[i] == '='
        pad += 1
        i -= 1
    end
    pad > 2 && throw(ArgumentError("Invalid base64 data"))
    n % 4 != 0 && throw(ArgumentError("Invalid base64 data"))
    for j in 1:i
        haskey(_B64_VALUE, s[j]) || throw(ArgumentError("Invalid base64 data"))
    end
end

"""RFC-4648 base64 encode, no line breaks (Nim std/base64 style)."""
function _base64Encode(data::Vector{UInt8})
    ch(v, shift) = string(_B64_ALPHABET[1 + ((v >> shift) & 0x3f)])
    out = String[]
    n = length(data)
    i = 1
    while i + 2 <= n
        v = (Int(data[i]) << 16) | (Int(data[i + 1]) << 8) | Int(data[i + 2])
        push!(out, ch(v, 18), ch(v, 12), ch(v, 6), ch(v, 0))
        i += 3
    end
    r = n - i + 1
    if r == 1
        v = Int(data[i]) << 16
        push!(out, ch(v, 18), ch(v, 12), "==")
    elseif r == 2
        v = (Int(data[i]) << 16) | (Int(data[i + 1]) << 8)
        push!(out, ch(v, 18), ch(v, 12), ch(v, 6), "=")
    end
    return join(out)
end

"""Strict RFC-4648 base64 decode; input must pass `_base64Validate`."""
function _base64Decode(s::String)
    out = Vector{UInt8}()
    acc = 0
    bits = 0
    for i in 1:length(s)
        c = s[i]
        c == '=' && continue
        acc = (acc << 6) | _B64_VALUE[c]
        bits += 6
        if bits >= 8
            bits -= 8
            push!(out, UInt8((acc >> bits) & 0xff))
        end
    end
    return out
end

"""Encode an image as PNG, then base64 (upstream `encodeBase64`)."""
function encodeBase64(image::Image)
    return _base64Encode(encodePNG(image))
end

"""
Decode a base64-encoded image, optionally wrapped in a `data:` URL
(upstream `decodeBase64`).
"""
function decodeBase64(data::String)
    payload = _base64Payload(data)
    _base64Validate(payload)
    return decodeImage(_base64Decode(payload))
end
