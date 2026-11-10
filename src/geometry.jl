# ---------- geometry (T003) ----------
# Upstream: pkgs/vmath/src/vmath.nim (GVec2 and GMat3 storage/operators,
# determinant/inverse/transpose, scale/translate/rotate at ~lines 1291-1590),
# pkgs/bumpy/src/bumpy.nim (Rect/Circle/Segment/Line/Polygon; rect, xy/wh,
# `*`//`, `+`, `or`=union, `and`=intersection, circle, line, segment), and
# pixie/common.nim lines 92-101 (snapToPixels).
#
# This toolchain shadows Base arithmetic instead of extending it when an
# operator is defined locally (the reason `*` is imported at the top of the
# module), so import the Base generics whose methods are added here.
# `|`, `&` and `transpose` are Base globals in this build (bitwise ops and
# linear algebra); importing extends their shared generic instead of creating
# an ambiguous same-named local one. `&` needs the qualified form in a
# `function` definition because infix `&(...)` parses as address-of.
import Base: +, -, /, transpose, length, ==, |

# ---- Vec2 (vmath GVec2[float32]) ----

struct Vec2
    x::Float32
    y::Float32
end

"""Zero vector (upstream `vec2()`)."""
Vec2() = Vec2(Float32(0), Float32(0))

"""
Construct from ordinary Julia numbers (T014): one `Float32` conversion per
component, then the specialized constructor. Dispatch prefers the `Float32`
constructor when both components are already `Float32`, so existing callers
pay nothing.
"""
Vec2(x::Real, y::Real) = Vec2(Float32(x), Float32(y))

function +(a::Vec2, b::Vec2)
    return Vec2(a.x + b.x, a.y + b.y)
end

function +(a::Vec2, s::Float32)
    return Vec2(a.x + s, a.y + s)
end

function +(s::Float32, a::Vec2)
    return Vec2(s + a.x, s + a.y)
end

function -(a::Vec2, b::Vec2)
    return Vec2(a.x - b.x, a.y - b.y)
end

function -(a::Vec2, s::Float32)
    return Vec2(a.x - s, a.y - s)
end

function -(s::Float32, a::Vec2)
    return Vec2(s - a.x, s - a.y)
end

"""Component negation (vmath unary `-(vec)`)."""
function -(a::Vec2)
    return Vec2(-a.x, -a.y)
end

function *(a::Vec2, s::Float32)
    return Vec2(a.x * s, a.y * s)
end

function *(s::Float32, a::Vec2)
    return Vec2(s * a.x, s * a.y)
end

function /(a::Vec2, s::Float32)
    return Vec2(a.x / s, a.y / s)
end

function /(s::Float32, a::Vec2)
    return Vec2(s / a.x, s / a.y)
end

"""`(a) == (b)` component equality (both components; mirrors vmath `==`)."""
function ==(a::Vec2, b::Vec2)
    return a.x == b.x && a.y == b.y
end

"""Dot product (vmath `dot`)."""
function dot(a::Vec2, b::Vec2)
    return a.x * b.x + a.y * b.y
end

"""`sqrt(x^2 + y^2)` (vmath `length`, Float32 arithmetic).

Legacy Euclidean entry point (upstream vmath's name): `LinearAlgebra.norm`
is the idiomatic Julia name for the same quantity. `Vec2` deliberately
is not an `AbstractVector`, so `length` here is not an element count.
"""
function length(v::Vec2)
    return sqrt(v.x * v.x + v.y * v.y)
end

"""`x^2 + y^2` (vmath `lengthSq`)."""
function lengthSq(v::Vec2)
    return v.x * v.x + v.y * v.y
end

"""
`v / length(v)` (vmath `normalize`). Zero vector yields NaN components,
no guard -- mirrors upstream. `dot` and `normalize` extend the actual
LinearAlgebra generics (imported in Vetra.jl), so `using Vetra,
LinearAlgebra` resolves both to the identical binding.
"""
normalize(v::Vec2) = v / length(v)

# LinearAlgebra entry point (M003): the Euclidean norm through the
# standard-library generic (same formula as legacy `length`).
LinearAlgebra.norm(v::Vec2) = length(v)

"""
90-degree counter-clockwise perpendicular: `(x, y) -> (-y, x)`. Equals
`rotate(pi/2) * v` for a unit vector (hand-derived; consistent with the
matrix layout below).
"""
perpendicular(v::Vec2) = Vec2(-v.y, v.x)

# ---- Rect and friends (bumpy) ----

"""`bumpy.Rect`: origin (x, y) and size (w, h) -- the upstream field layout."""
struct Rect
    x::Float32
    y::Float32
    w::Float32
    h::Float32
end

rect(x::Float32, y::Float32, w::Float32, h::Float32) = Rect(x, y, w, h)
rect(pos::Vec2, size::Vec2) = Rect(pos.x, pos.y, size.x, size.y)
"""Component-wise number form (T014): converts once, then dispatches."""
rect(x::Real, y::Real, w::Real, h::Real) =
    Rect(Float32(x), Float32(y), Float32(w), Float32(h))

xy(r::Rect) = Vec2(r.x, r.y)
wh(r::Rect) = Vec2(r.w, r.h)

"""Derived (Flutter-style sugar, not bumpy) edge accessors."""
left(r::Rect) = r.x
top(r::Rect) = r.y
right(r::Rect) = r.x + r.w
bottom(r::Rect) = r.y + r.h

"""All four components scaled (bumpy `*`(Rect, float), here Float32)."""
*(r::Rect, s::Float32) = Rect(r.x * s, r.y * s, r.w * s, r.h * s)

"""All four components divided (bumpy `/`(Rect, float), here Float32)."""
/(r::Rect, s::Float32) = Rect(r.x / s, r.y / s, r.w / s, r.h / s)

"""Offset positions, keeps the left rect's size (bumpy `+`)."""
+(a::Rect, b::Rect) = Rect(a.x + b.x, a.y + b.y, a.w, a.h)

"""Union, exact bumpy `or` formula."""
function |(a::Rect, b::Rect)
    x = min(a.x, b.x)
    y = min(a.y, b.y)
    return Rect(x, y, max(a.x + a.w, b.x + b.w) - x,
        max(a.y + a.h, b.y + b.h) - y)
end

"""
Intersection, exact bumpy `and` formula: touching/disjoint rects may yield
zero or negative w/h -- deliberately not clamped (mirrors upstream).
"""
function Base.:&(a::Rect, b::Rect)
    x = max(a.x, b.x)
    y = max(a.y, b.y)
    return Rect(x, y, min(a.x + a.w, b.x + b.w) - x,
        min(a.y + a.h, b.y + b.h) - y)
end

"""`bumpy.Circle` (center + radius); used by circle path/stroke commands."""
struct Circle
    pos::Vec2
    radius::Float32
end

circle(pos::Vec2, radius::Float32) = Circle(pos, radius)
"""Number form (T014): converts the radius once, then dispatches."""
circle(pos::Vec2, radius::Real) = Circle(pos, Float32(radius))

"""`bumpy.Segment` (stroke geometry)."""
struct Segment
    at::Vec2
    to::Vec2
end

segment(at::Vec2, to::Vec2) = Segment(at, to)

"""`bumpy.Line` (clipping/infinite line)."""
struct Line
    a::Vec2
    b::Vec2
end

line(a::Vec2, b::Vec2) = Line(a, b)

"""`bumpy.Polygon = seq[Vec2]`."""
const Polygon = Vector{Vec2}

# ---- Mat3 (vmath GMat3[float32]) ----

"""
Affine 3x3 matrix, 9 Float32 values in vmath's own flat order (gmat3's
m00, m01, m02, m10, ... -- element k is `m[k div 3 + 1, k mod 3 + 1]`).
`m[i, j]` reads column `i`, row `j`, 1-based.
"""
struct Mat3
    data::NTuple{9,Float32}
end

"""
Element access: `m[i, j]` = column `i`, row `j` (each 1..3). The x
translation lives at `m[3, 1]`; the point transform is
`x' = m[1,1]x + m[2,1]y + m[3,1]`, `y' = m[1,2]x + m[2,2]y + m[3,2]`.
"""
function Base.getindex(m::Mat3, i::Int, j::Int)
    (1 <= i <= 3 && 1 <= j <= 3) ||
        throw(BoundsError("Mat3 index ($i, $j) outside 1..3"))
    return m.data[(i - 1) * 3 + j]
end

"""`(a) == (b)` element equality (vmath `==`, used by upstream paths)."""
function ==(a::Mat3, b::Mat3)
    return a.data == b.data
end

"""Identity matrix (upstream `mat3()`)."""
mat3() = Mat3(
    (Float32(1), Float32(0), Float32(0),
     Float32(0), Float32(1), Float32(0),
     Float32(0), Float32(0), Float32(1)))

"""Translation matrix (upstream `translate(GVec2)`)."""
function translate(v::Vec2)
    z = Float32(0)
    return Mat3((Float32(1), z, z, z, Float32(1), z, v.x, v.y, Float32(1)))
end

"""Scale matrix (upstream `scale(GVec2)`)."""
function scale(v::Vec2)
    z = Float32(0)
    return Mat3((v.x, z, z, z, v.y, z, z, z, Float32(1)))
end

"""Rotation matrix (upstream `rotate(angle)`; angle in radians, Float32)."""
function rotate(angle::Float32)
    c = cos(angle)
    s = sin(angle)
    z = Float32(0)
    return Mat3((c, s, z, -s, c, z, z, z, Float32(1)))
end

"""Rotation matrix from an ordinary number (T014; radians)."""
rotate(angle::Real) = rotate(Float32(angle))

"""
Composition with upstream order (vmath `*`, ~line 1291): the *second*
operand is applied to the point first, i.e.
`((a * b) * p) == a * (b * p)` -- the same order pixie uses for
`ctx.mat = ctx.mat * transform`.
"""
function *(a::Mat3, b::Mat3)
    r = zeros(Float32, 9)
    for i in 1:3
        for j in 1:3
            r[(i - 1) * 3 + j] =
                b[i, 1] * a[1, j] + b[i, 2] * a[2, j] + b[i, 3] * a[3, j]
        end
    end
    return Mat3(Tuple(r))
end

"""Affine point transform (vmath `*`(GMat3, GVec2))."""
function *(m::Mat3, v::Vec2)
    return Vec2(m[1, 1] * v.x + m[2, 1] * v.y + m[3, 1],
        m[1, 2] * v.x + m[2, 2] * v.y + m[3, 2])
end

"""Determinant (vmath formula, ~line 1423)."""
function determinant(m::Mat3)
    return m[1, 1] * (m[2, 2] * m[3, 3] - m[3, 2] * m[2, 3]) -
        m[1, 2] * (m[2, 1] * m[3, 3] - m[2, 3] * m[3, 1]) +
        m[1, 3] * (m[2, 1] * m[3, 2] - m[2, 2] * m[3, 1])
end

"""
Inverse (vmath formula, ~line 1467). Upstream has no singular guard: for a
zero determinant `1/det` yields ±Inf/NaN elements instead of throwing.
"""
function inverse(m::Mat3)
    invdet = 1 / determinant(m)
    return Mat3((
        +(m[2, 2] * m[3, 3] - m[3, 2] * m[2, 3]) * invdet,
        -(m[1, 2] * m[3, 3] - m[1, 3] * m[3, 2]) * invdet,
        +(m[1, 2] * m[2, 3] - m[1, 3] * m[2, 2]) * invdet,
        -(m[2, 1] * m[3, 3] - m[2, 3] * m[3, 1]) * invdet,
        +(m[1, 1] * m[3, 3] - m[1, 3] * m[3, 1]) * invdet,
        -(m[1, 1] * m[2, 3] - m[2, 1] * m[1, 3]) * invdet,
        +(m[2, 1] * m[3, 2] - m[3, 1] * m[2, 2]) * invdet,
        -(m[1, 1] * m[3, 2] - m[3, 1] * m[1, 2]) * invdet,
        +(m[1, 1] * m[2, 2] - m[2, 1] * m[1, 2]) * invdet))
end

# Standard-library entry points (M003): same formulas, no singular guard
# (a singular `Mat3` yields ±Inf/NaN elements, as upstream).
LinearAlgebra.det(m::Mat3) = determinant(m)
Base.inv(m::Mat3) = inverse(m)

"""Transpose (vmath ~line 1402): swaps i,j components."""
function transpose(m::Mat3)
    r = zeros(Float32, 9)
    for i in 1:3
        for j in 1:3
            r[(i - 1) * 3 + j] = m.data[(j - 1) * 3 + i]
        end
    end
    return Mat3(Tuple(r))
end

"""Apply the matrix to a point (explicit form of `m * v`)."""
function transform(m::Mat3, v::Vec2)
    return m * v
end

"""
Transform the rect's four corners and return their axis-aligned bounding box
(a rotated rect grows; the returned box encloses all corners).
"""
function transform(m::Mat3, r::Rect)
    p1 = m * Vec2(r.x, r.y)
    p2 = m * Vec2(r.x + r.w, r.y)
    p3 = m * Vec2(r.x, r.y + r.h)
    p4 = m * Vec2(r.x + r.w, r.y + r.h)
    xmin = min(p1.x, min(p2.x, min(p3.x, p4.x)))
    xmax = max(p1.x, max(p2.x, max(p3.x, p4.x)))
    ymin = min(p1.y, min(p2.y, min(p3.y, p4.y)))
    ymax = max(p1.y, max(p2.y, max(p3.y, p4.y)))
    return Rect(xmin, ymin, xmax - xmin, ymax - ymin)
end

"""`atan2(y, x)` angle of a Vec2 (vmath `angle`, ~line 1852).

`atan(y, x)` is the same two-argument form used by strokes.jl `_angle`;
bare `atan2` is not in Base's export surface in this Julia build.
"""
angle(v::Vec2) = atan(v.y, v.x)

# `fixAngle` (vmath L595) is defined in strokes.jl: in the pinned build the
# PI literal adapts to the Float32 generic context (pinned behavior:
# fixAngle(PI_F) == PI_F), so the loop compares with Float32 PI_F/TAU_F.

"""
`pixie/common.nim snapToPixels` (lines 92-101):
`x = floor(xMin)`, `w = ceil(xMax) - x`, same for y/h; Float32 throughout.
"""
function snapToPixels(r::Rect)
    x = floor(r.x)
    w = ceil(r.x + r.w) - x
    y = floor(r.y)
    h = ceil(r.y + r.h) - y
    return Rect(x, y, w, h)
end
