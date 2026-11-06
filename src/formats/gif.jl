# ---------- GIF (T008) ----------
# Upstream: pixie/fileformats/gif.nim -- gifSignatures (L6), Gif
# (L9-12), decodeGif (L25-377), decodeGifDimensions (L379-401),
# newImage(Gif) (L403-404).
#
# Pinned behavior notes:
# - decodeGif returns all frames composited onto screen-sized canvases
#   (disposal method 2 fills with the background color; otherwise the
#   frame image is drawn at its offset). newImage(Gif) is frames[0]
#   copied -- what readImage/decodeImage use.
# - LZW decoding uses the (offset, len) table scheme upstream; the
#   special "KAWOY" case (code == table.len) repeats the previous
#   sequence plus its first index. Out-of-range palette indexes are
#   skipped (upstream's failInvalid is commented out there).
# - minCodeSize outside 2..8, frames larger than the screen, and unknown
#   block/extension types are errors.
# - The global background color is only defined when a global color table
#   exists; with disposal 2 and no global table upstream reads an
#   uninitialized value (debug builds: zero). We pin the zero value.
# - Graphics Control Extension: delay in centiseconds -> seconds
#   (delayTime.float32 / 100); transparency via fields & 1.

const GIF_SIGNATURES = ("GIF87a", "GIF89a")

"""Upstream `Gif`: decoded frames plus per-frame intervals and total duration."""
struct Gif
    frames::Vector{Image}
    intervals::Vector{Float32}
    duration::Float32
end

function _gifFail(reason::String = "unable to load")
    throw(ArgumentError("Invalid GIF buffer, $(reason)"))
end

"""1-based LE16 read."""
function gifRead16(data::Vector{UInt8}, i::Int)
    return Int(data[i]) | (Int(data[i + 1]) << 8)
end

# `_upperHex4` (upstream `toHex` on a uint8) lives in io.jl.

"""
Upstream `decodeGif`: full GIF87/89 decode (global/local color tables,
LZW, interlacing, disposal, transparency, GCE/comment/APP extensions).
"""
function decodeGIF(data::Vector{UInt8})
    length(data) < 13 && _gifFail()
    sig = String(data[1:6])
    sig in GIF_SIGNATURES || throw(ArgumentError("Invalid GIF file signature"))

    screenWidth = gifRead16(data, 7)
    screenHeight = gifRead16(data, 9)
    globalFlags = Int(data[11])
    hasGlobalColorTable = (globalFlags & 0x80) != 0
    globalColorTableSize = 1 << ((globalFlags & 0x07) + 1)
    bgColorIndex = Int(data[12])

    if hasGlobalColorTable && bgColorIndex >= globalColorTableSize
        _gifFail()
    end

    pos = 14 # 1-based
    n = length(data)

    globalColorTable = Vector{UInt8}()
    bgColor = (UInt8(0), UInt8(0), UInt8(0), UInt8(0))
    if hasGlobalColorTable
        pos + globalColorTableSize * 3 - 1 > n && _gifFail()
        globalColorTable = Vector{UInt8}(undef, 4 * globalColorTableSize)
        for i in 0:(globalColorTableSize - 1)
            o = pos + 3 * i
            globalColorTable[4 * i + 1] = data[o]
            globalColorTable[4 * i + 2] = data[o + 1]
            globalColorTable[4 * i + 3] = data[o + 2]
            globalColorTable[4 * i + 4] = 0xff
        end
        pos += globalColorTableSize * 3
        bgColor = (globalColorTable[4 * bgColorIndex + 1],
            globalColorTable[4 * bgColorIndex + 2],
            globalColorTable[4 * bgColorIndex + 3],
            globalColorTable[4 * bgColorIndex + 4])
    end

    function skipSubBlocks()
        while true
            pos > n && _gifFail()
            subBlockSize = Int(data[pos])
            pos += 1
            subBlockSize == 0 && break
            pos += subBlockSize
            pos > n && _gifFail()
        end
        return nothing
    end

    # Control extension state (applies to the next image only).
    ceFields = UInt8(0)
    ceDelayTime = 0
    ceTransparentColorIndex = UInt8(0)

    frames = Vector{Image}()
    intervals = Vector{Float32}()

    while true
        pos > n && _gifFail()
        blockType = Int(data[pos])
        pos += 1

        if blockType == 0x2c
            # Image descriptor
            pos + 9 > n && _gifFail()
            imageLeftPos = gifRead16(data, pos)
            imageTopPos = gifRead16(data, pos + 2)
            imageWidth = gifRead16(data, pos + 4)
            imageHeight = gifRead16(data, pos + 6)
            imageFlags = Int(data[pos + 8])
            hasLocalColorTable = (imageFlags & 0x80) != 0
            interlaced = (imageFlags & 0x40) != 0
            localColorTableSize = 1 << ((imageFlags & 0x07) + 1)
            pos += 9

            (imageWidth > screenWidth || imageHeight > screenHeight) &&
                throw(ArgumentError("Invalid GIF frame dimensions"))

            localColorTable = Vector{UInt8}()
            if hasLocalColorTable
                pos + localColorTableSize * 3 - 1 > n && _gifFail()
                localColorTable = Vector{UInt8}(undef, 4 * localColorTableSize)
                for i in 0:(localColorTableSize - 1)
                    o = pos + 3 * i
                    localColorTable[4 * i + 1] = data[o]
                    localColorTable[4 * i + 2] = data[o + 1]
                    localColorTable[4 * i + 3] = data[o + 2]
                    localColorTable[4 * i + 4] = 0xff
                end
                pos += localColorTableSize * 3
            end

            pos > n && _gifFail()
            minCodeSize = Int(data[pos])
            pos += 1
            (minCodeSize < 2 || minCodeSize > 8) && _gifFail()

            # Collect the LZW data sub-blocks.
            lzwData = Vector{UInt8}()
            while true
                pos > n && _gifFail()
                subBlockSize = Int(data[pos])
                pos += 1
                subBlockSize == 0 && break
                pos + subBlockSize - 1 > n && _gifFail()
                append!(lzwData, data[pos:(pos + subBlockSize - 1)])
                pos += subBlockSize
            end

            clearCode = 1 << minCodeSize
            endCode = clearCode + 1

            # LSB-first bit reader over lzwData (zippy BitStreamReader).
            byteIdx = 0
            bitPos = 0
            function readBits(count::Int)
                value = 0
                for i in 0:(count - 1)
                    if bitPos == 8
                        bitPos = 0
                        byteIdx += 1
                    end
                    byteIdx >= length(lzwData) && _gifFail()
                    value |= ((Int(lzwData[byteIdx + 1]) >> bitPos) & 1) << i
                    bitPos += 1
                end
                return value
            end

            colorIndexes = Int[]
            codeSize = minCodeSize + 1
            # table: (offset, len) sequences; entries 0..endCode unused at first.
            table = Vector{Tuple{Int,Int}}(undef, endCode + 1)
            prev = (0, 0)

            while true
                code = readBits(codeSize)
                if code == endCode
                    break
                end
                if code == clearCode
                    codeSize = minCodeSize + 1
                    resize!(table, endCode + 1)
                    prev = (0, 0)
                    continue
                end
                if length(table) == (1 << codeSize) - 1 && codeSize < 12
                    codeSize += 1
                end
                start = length(colorIndexes)
                if code < length(table)
                    if code < clearCode
                        push!(colorIndexes, code)
                        if prev[2] > 0
                            push!(table, (prev[1], prev[2] + 1))
                        end
                        prev = (start, 1)
                    else
                        (offset, len) = table[code + 1]
                        for i in 0:(len - 1)
                            push!(colorIndexes, colorIndexes[offset + i + 1])
                        end
                        push!(table, (prev[1], prev[2] + 1))
                        prev = (start, len)
                    end
                else
                    prev[2] == 0 && _gifFail()
                    for i in 0:(prev[2] - 1)
                        push!(colorIndexes, colorIndexes[prev[1] + i + 1])
                    end
                    push!(colorIndexes, colorIndexes[prev[1] + 1])
                    push!(table, (start, prev[2] + 1))
                    prev = (start, prev[2] + 1)
                end
            end

            length(colorIndexes) != imageWidth * imageHeight && _gifFail()

            image = newImage(imageWidth, imageHeight)
            d = image.data

            transparentColorIndex = -1
            if (Int(ceFields) & 1) != 0
                transparentColorIndex = Int(ceTransparentColorIndex)
            end

            colorTable = hasLocalColorTable ? localColorTable : globalColorTable
            colorTableSize = hasLocalColorTable ? localColorTableSize :
                (hasGlobalColorTable ? globalColorTableSize : 0)

            disposalMethod = (Int(ceFields) & 0x1c) >> 2
            if disposalMethod == 2
                frame = newImage(screenWidth, screenHeight)
                fd = frame.data
                for i in 1:4:length(fd)
                    fd[i] = bgColor[1]
                    fd[i + 1] = bgColor[2]
                    fd[i + 2] = bgColor[3]
                    fd[i + 3] = bgColor[4]
                end
                push!(frames, frame)
            else
                for i in 0:(imageWidth * imageHeight - 1)
                    colorIndex = colorIndexes[i + 1]
                    if colorIndex >= colorTableSize
                        # Upstream skips out-of-range indexes (failInvalid
                        # is commented out there).
                        continue
                    end
                    colorIndex == transparentColorIndex && continue
                    o4 = 4 * colorIndex
                    o = 4 * i
                    d[o + 1] = colorTable[o4 + 1]
                    d[o + 2] = colorTable[o4 + 2]
                    d[o + 3] = colorTable[o4 + 3]
                    d[o + 4] = colorTable[o4 + 4]
                end

                if interlaced
                    deinterlaced = newImage(imageWidth, imageHeight)
                    dd = deinterlaced.data
                    copyRow(dstRow::Int, srcRow::Int) = begin
                        so = 4 * (srcRow - 1) * imageWidth
                        do_ = 4 * (dstRow - 1) * imageWidth
                        for k in 0:(4 * imageWidth - 1)
                            dd[do_ + k + 1] = d[so + k + 1]
                        end
                    end
                    # Upstream: one running source row `y` across all four
                    # passes (0-based starts 0/4/2/1 = 1-based 1/5/3/2).
                    y = 1
                    for i in (1:8:imageHeight)
                        copyRow(i, y)
                        y += 1
                    end
                    for i in (5:8:imageHeight)
                        copyRow(i, y)
                        y += 1
                    end
                    for i in (3:4:imageHeight)
                        copyRow(i, y)
                        y += 1
                    end
                    for i in (2:2:imageHeight)
                        copyRow(i, y)
                        y += 1
                    end
                    image = deinterlaced
                end

                if imageWidth != screenWidth || imageHeight != screenHeight ||
                    imageTopPos != 0 || imageLeftPos != 0
                    frame = newImage(screenWidth, screenHeight)
                    draw(frame, image, translate(Vec2(Float32(imageLeftPos),
                        Float32(imageTopPos))))
                    push!(frames, frame)
                else
                    push!(frames, image)
                end
            end

            push!(intervals, Float32(ceDelayTime) / Float32(100))

            # The control extension applies to one image only.
            ceFields = UInt8(0)
            ceDelayTime = 0
            ceTransparentColorIndex = UInt8(0)

        elseif blockType == 0x21
            # Extension
            pos > n && _gifFail()
            extensionType = Int(data[pos])
            pos += 1

            if extensionType == 0xf9
                # Graphic Control Extension
                pos > n && _gifFail()
                blockSize = Int(data[pos])
                pos += 1
                blockSize != 4 && _gifFail()
                pos + blockSize - 1 > n && _gifFail()
                ceFields = data[pos]
                ceDelayTime = gifRead16(data, pos + 1)
                ceTransparentColorIndex = data[pos + 3]
                pos += blockSize
                pos += 1 # block terminator
            elseif extensionType == 0xfe
                # Comment
                skipSubBlocks()
            elseif extensionType == 0xff
                # Application specific
                pos > n && _gifFail()
                blockSize = Int(data[pos])
                pos += 1
                blockSize != 11 && _gifFail()
                pos + blockSize - 1 > n && _gifFail()
                pos += blockSize
                skipSubBlocks()
            else
                throw(ArgumentError(
                    "Unexpected GIF extension type $(
                        _upperHex4(extensionType))"))
            end

        elseif blockType == 0x3b
            # Trailer
            break
        else
            throw(ArgumentError(
                "Unexpected GIF block type $(
                    _upperHex4(blockType))"))
        end
    end

    duration = Float32(0)
    for interval in intervals
        duration += interval
    end

    return Gif(frames, intervals, duration)
end

"""Upstream `decodeGifDimensions`: header only (10 bytes minimum)."""
function decodeGIFDimensions(data::Vector{UInt8})
    length(data) < 10 && _gifFail()
    String(data[1:6]) in GIF_SIGNATURES ||
        throw(ArgumentError("Invalid GIF file signature"))
    return (gifRead16(data, 7), gifRead16(data, 9))
end

"""Upstream `newImage(Gif)`: a copy of the first frame."""
function newImage(gif::Gif)
    length(gif.frames) == 0 && _gifFail()
    return copy(gif.frames[1])
end
