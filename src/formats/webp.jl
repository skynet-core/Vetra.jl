# ---------- static WebP codec (T032, D032, docs/JPEG_WEBP_CODECS.md §3) ----------
# Upstream `pixie/fileformats/webp.nim` is a native decoder; the T008 port
# deferred WebP (D014), and D032 routes static read/write through the opt-in
# `WebP.jl` package (libwebp binary) instead of a native port.
#
# Verified provider facts (T030/T032 probes):
# - `WebP.decode(data)` auto-detects RGB/RGBA from its feature scan but
#   ignores the scan's return value — on invalid data it proceeds into the
#   pixel decode with an unreadable feature struct. Vetra success-checks
#   the scan itself first (`_webpFeatures`).
# - Animated input crashes the Julia process at C level inside the provider
#   decode (reproduced on the pinned Wikimedia fixture) — the
#   `has_animation` guard must fire before any pixel decode.
# - Provider matrices are indexed `[row=y, col=x]` (size = (height, width)),
#   the same convention as JpegTurbo — verified on the whole 129-file
#   pinned corpus.
# - `encode` at dimension ≥ 16384 silently returns an empty vector —
#   `_WEBP_MAX_DIMENSION` rejects before the provider runs.
#
# Alpha boundary: decode converts straight → premultiplied with the house
# `(s8 * a8 + 127) div 255`; encode converts premultiplied → straight with
# the contract's half-rounded divide (below). RGB input becomes `a8 = 255`.

const _WEBP_PKGID = Base.PkgId(
    Base.UUID("e3aaa7dc-3e4b-44e0-be63-ffb868ccd7c1"), "WebP")

"""
The `WebP` module, loaded on first use (lazy discovery, D028), or a clear
install hint (D032). Environments without WebP load normally and get this
error only on use.
"""
function _requireWebP()
    if Base.locate_package(_WEBP_PKGID) === nothing
        throw(ErrorException(
            "WebP support is opt-in: add the WebP package to your " *
            "environment (Pkg.add(\"WebP\")) and retry"))
    end
    return Base.require(_WEBP_PKGID)
end

"""libwebp's per-side maximum: at 16384 the provider silently returns an
empty vector (T030 probe, verified), so the API boundary rejects first."""
const _WEBP_MAX_DIMENSION = 16383

"""
libwebp feature scan through the provider's Wrapper (the same ccall the
provider's own auto-detect makes, but with the return value success-checked
— the provider ignores it). Returns `(width, height, has_alpha,
has_animation)`; invalid data raises
`ArgumentError("Invalid WebP, unable to load")`. Observed return values
(T032 probe, libwebp_jll 1.6.1): 0 = OK; nonzero (3, 7) = failure.
"""
function _webpFeatures(m, data::Vector{UInt8})
    ref = Ref{m.Wrapper.WebPBitstreamFeatures}()
    rv = m.Wrapper.WebPGetFeaturesInternal(
        pointer(data), length(data), ref, m.Wrapper.WEBP_DECODER_ABI_VERSION)
    if Int(rv) != 0
        throw(ArgumentError("Invalid WebP, unable to load"))
    end
    fe = ref[]
    return Int(fe.width), Int(fe.height), fe.has_alpha != 0,
        fe.has_animation != 0
end

"""
Decode WebP bytes into an `Image` (upstream `readImage`, static subset):
premultiplied pixels out; RGB input becomes `a = 255`. The feature scan
runs first; animation raises
`ArgumentError("WebP animation is not supported")` before pixel decode.
"""
function decodeWebP(data::Vector{UInt8})
    m = _requireWebP()
    w, h, has_alpha, has_animation =
        Base.invokelatest(_webpFeatures, m, data)
    has_animation &&
        throw(ArgumentError("WebP animation is not supported"))
    pixels = if has_alpha
        Base.invokelatest(m.decode, m.RGBA{m.N0f8}, data)
    else
        Base.invokelatest(m.decode, m.RGB{m.N0f8}, data)
    end
    image = newImage(w, h)
    Base.invokelatest(_decodeWebPPixels!, image, pixels, has_alpha, w, h)
    return image
end

"""
Kernel for `decodeWebP`: the provider's `[row, col]` straight-alpha color
matrix into premultiplied `image` bytes. House straight→premul is
`(s8 * a8 + 127) div 255` (the PNG decode boundary); RGB input becomes
`a8 = 255`. Called via `Base.invokelatest`: the `N0f8 → Float64`
conversion is defined by FixedPointNumbers, which may be required (lazy
discovery, D028) by this very decode call.
"""
function _decodeWebPPixels!(image::Image, pixels, has_alpha::Bool, w::Int,
        h::Int)
    d = image.data
    for y in 1:h
        row = 4 * (y - 1) * w
        for x in 1:w
            c = pixels[y, x]
            r = UInt8(round(Float64(c.r) * 255))
            g = UInt8(round(Float64(c.g) * 255))
            b = UInt8(round(Float64(c.b) * 255))
            a = has_alpha ? UInt8(round(Float64(c.alpha) * 255)) : UInt8(255)
            o = row + 4 * (x - 1)
            d[o + 1] = UInt8((Int(r) * Int(a) + 127) ÷ 255)
            d[o + 2] = UInt8((Int(g) * Int(a) + 127) ÷ 255)
            d[o + 3] = UInt8((Int(b) * Int(a) + 127) ÷ 255)
            d[o + 4] = a
        end
    end
    return nothing
end

"""
WebP dimensions from the feature scan (upstream `decodeWebpDimensions`):
no pixel decode, and animation is not rejected here — the canvas
dimensions are still the file's, the named error binds on pixel decode
(`decodeWebP`).
"""
function decodeWebPDimensions(data::Vector{UInt8})
    m = _requireWebP()
    w, h, _, _ = Base.invokelatest(_webpFeatures, m, data)
    return (w, h)
end

"""Contract §3.3: premultiplied `p8` with alpha `a8` to straight.
`a8 = 0` → `0` (the format leaves color under full transparency
unspecified — unobservable in the premultiplied API, where the channel
is forced to 0); otherwise the half-rounded divide
`(p8*255 + a8 div 2) div a8`, clamped to 0..255 (exact for `a8 = 255`
→ `p8`)."""
function _webpUnpremul(p8::Int, a8::Int)
    if a8 == 0
        return 0
    end
    v = (p8 * 255 + a8 ÷ 2) ÷ a8
    return clamp(v, 0, 255)
end

"""
Kernel for `encodeWebP`: premultiplied `d` bytes into the straight
`RGBA{N0f8}` matrix `out` (contract §3.3); always RGBA. The channel type
is read once from the matrix eltype (function barrier, as in `toColors`);
call via `Base.invokelatest` (D028 world-age safety).
"""
function _encodeWebPMatrix!(out::Matrix{C}, d::Vector{UInt8}, w::Int, h::Int) where {C}
    T = C.parameters[1]
    for y in 1:h
        row = 4 * (y - 1) * w
        for x in 1:w
            i = row + 4 * (x - 1)
            a = Int(d[i + 4])
            out[y, x] = C(
                T(_webpUnpremul(Int(d[i + 1]), a) / 255),
                T(_webpUnpremul(Int(d[i + 2]), a) / 255),
                T(_webpUnpremul(Int(d[i + 3]), a) / 255),
                T(a / 255))
        end
    end
    return nothing
end

"""
Encode an `Image` as WebP bytes (T032, D032 — docs/JPEG_WEBP_CODECS.md
§3). Static subset only: `lossy` (default `true`) with `quality` 0..100
(default 75 — out of range raises the provider's named
`ArgumentError`), or lossless, which ignores `quality` (the provider API
has no lossless quality parameter). Always encoded as RGBA (Vetra images
always carry alpha; opaque images encode with `a = 255`). Dimensions must
be ≤ 16383 per side (the provider silently returns an empty vector at
16384 — rejected first). Without `WebP` the install hint applies.
"""
function encodeWebP(image::Image; lossy::Bool = true, quality::Int = 75)
    m = _requireWebP()
    (image.width <= _WEBP_MAX_DIMENSION &&
        image.height <= _WEBP_MAX_DIMENSION) ||
        throw(ArgumentError("WebP dimension exceeds 16383"))
    w = image.width
    h = image.height
    mat = Matrix{m.RGBA{m.N0f8}}(undef, h, w)
    Base.invokelatest(_encodeWebPMatrix!, mat, image.data, w, h)
    return Base.invokelatest(m.encode, mat; lossy = lossy, quality = quality)
end
