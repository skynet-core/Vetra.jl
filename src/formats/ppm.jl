# ---------- PPM output (T006) ----------
# Upstream: pixie/fileformats/ppm.nim `encodePpm` (L166-186): header
# "P6\n{width} {height}\n255\n" followed by one RGB triple per pixel in
# row-major order. The channels are written exactly as stored; the image's
# stored pixels are premultiplied RGBA, so the PPM carries premultiplied r, g,
# b and the alpha channel is ignored. Decode-side (`decodePpm`) is not needed
# for this task (T008/T012 territory).

"""
Upstream `encodePpm`: binary P6 payload for `image` --
`"P6\\n{w} {h}\\n255\\n"` plus the stored r, g, b of every pixel in row-major
order (alpha dropped).
"""
function encodePPM(image::Image)
    d = image.data
    n = length(d)
    rgb = Vector{UInt8}(undef, n - n ÷ 4)
    j = 1
    for i in 1:4:n
        rgb[j] = d[i]
        rgb[j + 1] = d[i + 1]
        rgb[j + 2] = d[i + 2]
        j += 3
    end
    return "P6\n$(image.width) $(image.height)\n255\n" * String(rgb)
end

"""Write `image` to `path` as binary PPM (P6), upstream `encodePpm` output."""
function writePPM(path::String, image::Image)
    write(path, encodePPM(image))
    return nothing
end

# ---------- PPM input (T008) ----------
# Upstream: pixie/fileformats/ppm.nim -- ppmSignatures (L9), decodeHeader
# (L20-49), decodeP6Data (L51-83), decodeP3Data (L100-123), decodePpm
# (L126-148), decodePpmDimensions (L150-164).
#
# Pinned arithmetic notes:
# - `valueMultiplier = (255 / maxVal).float32` (Float32 division), and each
#   channel is `(v * multiplier + 0.5).uint8` -- Float32 math, truncation
#   (upstream float->uint8 cast); with maxVal = 255 this is the identity.
# - P6 16-bit samples (maxVal > 255) are big-endian.
# - P3 samples go through the P6 path after re-encoding: 8-bit as the char
#   value, 16-bit as big-endian uint16 bytes, inline `#` comments dropped.
# - The header state machine: `#` starts a comment until `\n`; the first
#   whitespace after a field closes it; invalid PPM raises `ArgumentError`
#   (upstream `PixieError`).

"""Upstream `ppmSignatures`."""
const PPM_SIGNATURES = ("P3", "P6")

const PPM_WS = (' ', '\t', '\r', '\n', '\v', '\f') # Nim std `Whitespace`

"""
Upstream `decodeHeader`: read version, width, height, maxVal as whitespace
separated fields, skipping `#` comments; returns (fields, firstDataByte)
where firstDataByte is the 1-based index after the whitespace closing the
fourth field.
"""
function ppmHeader(data::Vector{UInt8})
    commentMode = false
    readWhitespace = false
    fields = String[]
    field = String[]
    i = 1
    while length(fields) < 4
        i > length(data) && throw(ArgumentError("Invalid PPM file header"))
        c = Char(data[i])
        if c == '#'
            commentMode = true
        elseif c == '\n'
            commentMode = false
        end
        if !commentMode
            if c in PPM_WS && !readWhitespace
                push!(fields, join(field))
                readWhitespace = true
                empty!(field)
            elseif !(c in PPM_WS)
                push!(field, string(c))
                readWhitespace = false
            end
        end
        i += 1
    end
    return fields, i
end

"""
Upstream `decodeP6Data` (8- and 16-bit) as premultiplied RGBX bytes. The
pixel count comes from the remaining byte length, as upstream; `decodePPM`
validates it against width * height.
"""
function ppmDecodeP6(data::Vector{UInt8}, offset::Int, maxVal::Int)
    needsUint16 = maxVal > 0xFF
    bytesPerPixel = needsUint16 ? 6 : 3
    remaining = length(data) - offset + 1
    if remaining % bytesPerPixel != 0
        throw(ArgumentError("Invalid PPM data"))
    end
    count = remaining ÷ bytesPerPixel
    multiplier = Float32(255) / Float32(maxVal)
    chan(v::Float32) = UInt8(floor(v * multiplier + Float32(0.5)))
    pixels = Vector{UInt8}(undef, 4 * count)
    j = offset
    for k in 0:(count - 1)
        if needsUint16
            # Int before shifting: this build's `UInt8 << 8` wraps to 0.
            r = Float32((Int(data[j]) << 8) | Int(data[j + 1]))
            g = Float32((Int(data[j + 2]) << 8) | Int(data[j + 3]))
            b = Float32((Int(data[j + 4]) << 8) | Int(data[j + 5]))
            j += 6
        else
            r = Float32(data[j]); g = Float32(data[j + 1]); b = Float32(data[j + 2])
            j += 3
        end
        o = 4 * k
        pixels[o + 1] = chan(r)
        pixels[o + 2] = chan(g)
        pixels[o + 3] = chan(b)
        pixels[o + 4] = 0xff
    end
    return pixels
end

"""Upstream `decodeP3Data`: re-encode ASCII samples, then take the P6 path."""
function ppmDecodeP3(data::Vector{UInt8}, offset::Int, maxVal::Int)
    body = data[offset:end]
    out = Vector{UInt8}()
    # Upstream `splitLines`: LF, CRLF and lone CR all end a line.
    for raw in split(String(body), r"[\r\n]+")
        line = raw
        hashAt = findfirst('#', line)
        hashAt !== nothing && (line = line[1:(hashAt - 1)])
        # Upstream `splitWhitespace`: Nim Whitespace set minus the newline
        # already used to split lines.
        for sample in split(line, r"[\t \v\f]+")
            isempty(sample) && continue
            v = nothing # pre-declare: this build loses try-assigned locals
            try
                v = parse(UInt, sample)
            catch
                throw(ArgumentError("Invalid PPM data"))
            end
            if maxVal > 0xFF
                v > 0xFFFF && throw(ArgumentError("Invalid PPM data"))
                push!(out, UInt8(v >> 8), UInt8(v & 0xFF)) # big-endian uint16
            else
                v > 0xFF && throw(ArgumentError("Invalid PPM data"))
                push!(out, UInt8(v))
            end
        end
    end
    return out
end

"""
Decode PPM (P3/P6) data into an `Image` (upstream `decodePpm`). Invalid
headers, maxVal outside 1..65535, or mismatched pixel counts raise
`ArgumentError` (upstream `PixieError`).
"""
function decodePPM(data::Vector{UInt8})
    fields, offset = ppmHeader(data)
    version = fields[1]
    w = h = maxVal = 0
    # Upstream validates the three integers in the header read itself.
    try
        w = parse(Int, fields[2])
        h = parse(Int, fields[3])
        maxVal = parse(Int, fields[4])
    catch
        throw(ArgumentError("Invalid PPM data"))
    end
    version in PPM_SIGNATURES || throw(ArgumentError("Invalid PPM data"))
    (maxVal <= 0 || maxVal > 0xFFFF) && throw(ArgumentError("Invalid PPM data"))
    pixels = if version == "P3"
        ppmDecodeP6(ppmDecodeP3(data, offset, maxVal), 1, maxVal)
    else
        ppmDecodeP6(data, offset, maxVal)
    end
    length(pixels) != 4 * w * h && throw(ArgumentError("Invalid PPM data"))
    return Image(w, h, pixels)
end

"""Upstream `decodePpmDimensions`: header only, returns (width, height)."""
function decodePPMDimensions(data::Vector{UInt8})
    fields, _ = ppmHeader(data)
    w = h = 0
    try
        w = parse(Int, fields[2])
        h = parse(Int, fields[3])
        parse(Int, fields[4])
    catch
        throw(ArgumentError("Invalid PPM data"))
    end
    return (w, h)
end
