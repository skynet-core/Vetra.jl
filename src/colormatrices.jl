# ---------- color matrix interop (T015, D024) ----------
# Boundary conversions between Vetra's premultiplied `Image` and standard
# Julia color matrices (ColorTypes `RGB`/`RGBA`, opt-in per D024):
# - export `toColors`: stored premultiplied -> straight `RGBA{N0f8}` via
#   `toStraightAlpha` (the same boundary as PNG export, so the matrix bytes
#   equal the PNG payload bytes, [y, x] indexing);
# - import `fromColors`: straight `RGB{...}`/`RGBA{...}` matrices
#   (N0f8 bytes or 0..1 floats, clamped) -> premultiplied via `rgbx`
#   (the same boundary as PNG decode).
#
# ColorTypes is opt-in (D024): `Vetra.__init__` loads it when available in
# the active environment; a missing package makes the entry points raise an
# install hint on use, as with the other codecs (D014/D019).

const _COLORTYPES_PKGID = Base.PkgId(
    Base.UUID("3da002f7-5984-5a60-b8a6-cbb66c0b333f"), "ColorTypes")

"""
The `ColorTypes` module, loaded on first use (lazy discovery, D028), or a
clear install hint (D024). Environments without ColorTypes load normally
and get this error only on use.
"""
function _requireColorTypes()
    if Base.locate_package(_COLORTYPES_PKGID) === nothing
        throw(ErrorException(
            "Color-matrix interop is opt-in: add the ColorTypes package to " *
            "your environment (Pkg.add(\"ColorTypes\")) and retry"))
    end
    return Base.require(_COLORTYPES_PKGID)
end

"""
Export `image` as a `Matrix{RGBA{N0f8}}` of straight-alpha colors, indexed
`[row, col]` with row 1 = the top scanline (D024). Straight channels use
`toStraightAlpha` — the PNG export boundary — so the matrix's bytes equal
the PNG payload bytes.
"""
function toColors(image::Image)
    CT = _requireColorTypes()
    n8 = CT.N0f8
    w = image.width
    h = image.height
    out = Matrix{CT.RGBA{n8}}(undef, h, w)
    # `_requireColorTypes` returns `Any`; the kernel is specialized on the
    # concrete eltype (function-barrier pattern, as in decodePNG).
    # invokelatest: ColorTypes may be required (lazy discovery, D028) by
    # this very call, so the specialized kernel can be newer than this
    # method instance.
    Base.invokelatest(_toColorsPixels!, out, image.data, w, h)
    return out
end

"""
Kernel for `toColors`: premultiplied `d` bytes to straight `RGBA{N0f8}`.
The channel type `T` (N0f8) is read once from the eltype parameters;
`reinterpret(T, byte)` is the exact fixed-point byte (verified equal to
`T(k // 255)`) and avoids the per-channel rational construction.
"""
function _toColorsPixels!(out::Matrix{C}, d::Vector{UInt8}, w::Int, h::Int) where {C}
    T = C.parameters[1]
    # (y, x) ranges over the matrix; every d[..] access stays in range.
    @inbounds for y in 1:h
        row = 4 * (y - 1) * w
        for x in 1:w
            i = row + 4 * (x - 1)
            c = toStraightAlpha(ColorRGBX(d[i + 1], d[i + 2], d[i + 3], d[i + 4]))
            out[y, x] = C(reinterpret(T, c.r), reinterpret(T, c.g),
                reinterpret(T, c.b), reinterpret(T, c.a))
        end
    end
    return nothing
end

"""
Import a 2-D color matrix as an `Image` (D024): `RGB`/`RGBA` of `N0f8`
(bytes) or of `Float64`/`Float32` (0..1 values, clamped) are supported;
`[1, 1]` is the top-left pixel. Straight channels are premultiplied with
`rgbx` — the PNG decode boundary.

Inputs (M003): any one-based `AbstractMatrix` of colors — plain matrices,
`view`s (contiguous or strided, no copy), and top-level `transpose`s
(materialized via `permutedims`). Inputs with non-one-based axes, views
selected by index arrays, adjoints, and views built over a transpose raise
an explicit `ArgumentError`; `copy` them first. 3-D plane layouts raise a
pointing `ArgumentError`.
"""
function fromColors(m::AbstractMatrix{C}) where {C}
    CT = _requireColorTypes()
    T = C
    if T === Union{}
        # A lazy transpose of a color matrix resolves to a bottom eltype
        # under standard Transpose semantics (the color elements define no
        # element transpose); resolve the real color type from the base.
        base = m
        while base isa SubArray || base isa LinearAlgebra.Transpose ||
            base isa LinearAlgebra.Adjoint
            base = base.parent
        end
        T = eltype(base)
    end
    (T <: CT.AbstractRGB || T <: CT.AbstractRGBA) ||
        throw(ArgumentError(
            "fromColors: expected a matrix of ColorTypes RGB/RGBA colors, " *
            "got $T"))
    # One-based axes are required before any element access; unsupported
    # indexing raises Base's own ArgumentError.
    Base.require_one_based_indexing(m)
    _fromColorsReadableWithoutCopy(m) ||
        throw(ArgumentError(
            "fromColors: views selected by index arrays, adjoints, and " *
            "views over transposes are not supported; copy the matrix " *
            "first"))
    # A top-level transpose is peeled (odd count flips the orientation) and
    # materialized as a permuted matrix.
    base = m
    ntrans = 0
    while base isa LinearAlgebra.Transpose
        ntrans += 1
        base = base.parent
    end
    if ntrans % 2 == 1
        m = permutedims(base, (2, 1))
    else
        m = base
    end
    h = size(m, 1)
    w = size(m, 2)
    image = newImage(w, h)
    # invokelatest: ColorTypes may be required (lazy discovery, D028) by
    # this very call, so the specialized kernel can be newer than this
    # method instance.
    if T.parameters[1] <: AbstractFloat
        Base.invokelatest(_fromColorsFloat!, m, T, image.data, w, h)
    else
        Base.invokelatest(_fromColorsFixed!, m, T, image.data, w, h)
    end
    return image
end

"""3-D plane layouts (e.g. `(x, y, channel)`) are not supported."""
function fromColors(m::AbstractArray{C,3}) where {C}
    throw(ArgumentError(
        "fromColors: 3-D plane matrices are not supported; reshape to a " *
        "2-D Matrix of RGB/RGBA colors instead"))
end

"""True when the kernel's logical `m[row, column]` reads are valid without
a copy: every `SubArray` layer selects its parent by ranges, there is no
adjoint, and no transpose sits under a view."""
function _fromColorsReadableWithoutCopy(m)
    inView = false
    while true
        if m isa SubArray
            inView = true
            for idx in m.indices
                idx isa AbstractRange || return false
            end
            m = m.parent
        elseif m isa LinearAlgebra.Adjoint
            return false
        elseif m isa LinearAlgebra.Transpose
            inView && return false
            m = m.parent
        else
            return true
        end
    end
end

"""Kernel for `fromColors` (N0f8 channels): the raw `.i` byte is exact."""
function _fromColorsFixed!(m, T, d::Vector{UInt8}, w::Int, h::Int)
    hasA = :alpha ∈ fieldnames(T)
    @inbounds for y in 1:h
        row = 4 * (y - 1) * w
        for x in 1:w
            c = m[y, x]
            r = c.r.i
            g = c.g.i
            b = c.b.i
            a = hasA ? c.alpha.i : UInt8(0xff)
            p = rgbx(ColorRGBA(r, g, b, a))
            o = row + 4 * (x - 1)
            d[o + 1] = p.r
            d[o + 2] = p.g
            d[o + 3] = p.b
            d[o + 4] = p.a
        end
    end
    return nothing
end

"""Kernel for `fromColors` (float channels): clamp to [0, 1], round to byte."""
function _fromColorsFloat!(m, T, d::Vector{UInt8}, w::Int, h::Int)
    hasA = :alpha ∈ fieldnames(T)
    chan(v) = UInt8(round(clamp(Float64(v), 0.0, 1.0) * 255))
    @inbounds for y in 1:h
        row = 4 * (y - 1) * w
        for x in 1:w
            c = m[y, x]
            p = rgbx(ColorRGBA(chan(c.r), chan(c.g), chan(c.b),
                hasA ? chan(c.alpha) : 0xff))
            o = row + 4 * (x - 1)
            d[o + 1] = p.r
            d[o + 2] = p.g
            d[o + 3] = p.b
            d[o + 4] = p.a
        end
    end
    return nothing
end
