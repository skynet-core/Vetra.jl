# T003: geometry and affine transforms.
# Expectations are hand-derived from the pinned upstream formulas (vmath
# GVec2/GMat3, bumpy Rect operators, pixie/common.nim snapToPixels) and the
# approved fixture test/reference/snap_to_pixels.tsv -- never from the code
# under test. Purely algebraic values are compared exactly (they are binary
# exact); sin/cos-touching values use atol 1e-6 (Float32 eps 1.19e-07).

@testset "T003 geometry" begin
    V(x, y) = Vec2(Float32(x), Float32(y))
    R(x, y, w, h) = rect(Float32(x), Float32(y), Float32(w), Float32(h))
    # isapprox has no method for these structs -- plain per-component abs
    near(a, b, tol) = abs(a - b) ≤ tol
    Vnear(a, b, tol) = near(a.x, b.x, tol) && near(a.y, b.y, tol)
    # (this build mis-parses `i in 1:3, j in 1:3 -> f` as a 2-arg closure)
    function Mnear(a, b, tol)
        for i in 1:3
            for j in 1:3
                near(a[i, j], b[i, j], tol) || return false
            end
        end
        return true
    end

    @testset "Vec2 constructors and arithmetic" begin
        z = Vec2()
        @test z == V(0, 0)
        @test z.x isa Float32 && z.y isa Float32
        a = V(1.5, 0.75)
        b = V(0.25, -0.25)

        @test a + b == V(1.75, 0.5)
        @test a - b == V(1.25, 1.0)
        @test -a == V(-1.5, -0.75)
        @test a + Float32(1) == V(2.5, 1.75)
        @test Float32(1) + a == V(2.5, 1.75)
        @test a - Float32(2) == V(-0.5, -1.25)
        @test Float32(2) - a == V(0.5, 1.25)
        @test a * Float32(4) == V(6, 3)
        @test Float32(4) * a == V(6, 3)
        @test a / Float32(4) == V(0.375, 0.1875)
        @test Float32(1) / V(4, 0.5) == V(0.25, 2)
        @test a == V(1.5, 0.75)
        @test a != b
        @test dot(a, b) == Float32(0.1875)
        @test dot(V(1, 2), V(3, 4)) == Float32(11)
        @test lengthSq(V(3, 4)) == Float32(25)
        @test length(V(3, 4)) == Float32(5)
        @test length(z) == Float32(0)
        n = normalize(V(3, 4))
        @test n == V(0.6, 0.8)
        # normalize of zero: upstream has no guard, 0/0 gives NaN, no throw
        zn = normalize(Vec2())
        @test isnan(zn.x) && isnan(zn.y)
        @test perpendicular(V(1, 0)) == V(0, 1)
        @test perpendicular(V(0, 1)) == V(-1, 0)
        @test perpendicular(V(2, -3)) == V(3, 2)
    end

    @testset "Rect constructors, scaling, offset, union, intersection" begin
        r = R(1, 2, 3, 4)
        @test (r.x, r.y, r.w, r.h) == (Float32(1), Float32(2), Float32(3), Float32(4))
        @test rect(V(1, 2), V(3, 4)) == r
        @test xy(r) == V(1, 2)
        @test wh(r) == V(3, 4)
        @test left(r) == Float32(1)
        @test top(r) == Float32(2)
        @test right(r) == Float32(4)
        @test bottom(r) == Float32(6)

        @test R(1, 2, 3, 4) * Float32(2) == R(2, 4, 6, 8)
        @test R(2, 4, 6, 8) / Float32(2) == R(1, 2, 3, 4)
        # bumpy `+`: offset, and the size stays the LEFT rect's
        @test r + R(5, 6, 9, 9) == R(6, 8, 3, 4)

        a = R(0, 0, 4, 4)
        b = R(2, 1, 3, 3)
        @test a | b == R(0, 0, 5, 4)   # union
        @test a & b == R(2, 1, 2, 3)   # intersection

        # touching edges
        @test R(0, 0, 1, 1) | R(1, 0, 1, 1) == R(0, 0, 2, 1)
        @test R(0, 0, 1, 1) & R(1, 0, 1, 1) == R(1, 0, 0, 1)
        # disjoint: bumpy `and` does NOT clamp, w/h may go non-positive
        @test R(0, 0, 1, 1) | R(5, 6, 2, 3) == R(0, 0, 7, 9)
        @test R(0, 0, 1, 1) & R(2, 0, 1, 1) == R(2, 0, -1, 1)
        @test R(0, 0, 1, 1) & R(0, 2, 1, 1) == R(0, 2, 1, -1)

        # negative-origin rect, binary-exact inputs
        u = R(-0.75, -0.5, 2.25, 1.25)
        c = R(0.25, -0.75, 0.5, 0.25)
        @test u | c == R(-0.75, -0.75, 2.25, 1.5)
        @test u & c == R(0.25, -0.5, 0.5, 0)
    end

    @testset "Circle, Segment, Line, Polygon" begin
        cir = circle(V(1, -2), Float32(2.5))
        @test cir.pos == V(1, -2)
        @test cir.radius == Float32(2.5)
        seg = segment(V(0, 0), V(1, 1))
        @test seg.at == V(0, 0)
        @test seg.to == V(1, 1)
        ln = line(V(0, 1), V(-1, 2))
        @test ln.a == V(0, 1)
        @test ln.b == V(-1, 2)
        poly = Polygon()
        push!(poly, V(0, 0))
        push!(poly, V(1, 1))
        @test length(poly) == 2
        @test poly[1] == V(0, 0)
        @test poly[2] == V(1, 1)
    end

    @testset "Mat3 constructors and element layout" begin
        I = mat3()
        for i in 1:3
            for j in 1:3
                @test I[i, j] == Float32(i == j)
            end
        end
        @test_throws BoundsError I[0, 1]
        @test_throws BoundsError I[1, 0]
        @test_throws BoundsError I[1, 4]
        @test_throws BoundsError I[4, 1]
        @test I[1, 1] == mat3()[1, 1]   # == via elements

        # translation components sit in column 3, rows 1..2 (upstream layout)
        t = translate(V(5, -2))
        @test (t[1, 1], t[2, 1], t[3, 1]) == (Float32(1), Float32(0), Float32(5))
        @test (t[1, 2], t[2, 2], t[3, 2]) == (Float32(0), Float32(1), Float32(-2))
        @test (t[1, 3], t[2, 3], t[3, 3]) == (Float32(0), Float32(0), Float32(1))

        s = scale(V(2, 3))
        @test (s[1, 1], s[2, 1], s[3, 1]) == (Float32(2), Float32(0), Float32(0))
        @test (s[1, 2], s[2, 2], s[3, 2]) == (Float32(0), Float32(3), Float32(0))
        @test (s[1, 3], s[2, 3], s[3, 3]) == (Float32(0), Float32(0), Float32(1))
        @test scale(V(2, 1)) != scale(V(2, 3))

        # rotate(pi/2) by hand math: cos=0, sin=1 (Float32 eps tolerates 1e-6)
        r90 = rotate(Float32(π) / 2)
        @test (r90[1, 3], r90[2, 3], r90[3, 3]) == (Float32(0), Float32(0), Float32(1))
        @test (r90[3, 1], r90[3, 2]) == (Float32(0), Float32(0))
        @test near(r90[1, 1], Float32(0), 1e-6)
        @test near(r90[2, 1], Float32(-1), 1e-6)
        @test near(r90[1, 2], Float32(1), 1e-6)
        @test near(r90[2, 2], Float32(0), 1e-6)
        # rotate(pi/4) by hand math: cos = sin = sqrt(2)/2
        r45 = rotate(Float32(π) / 4)
        @test near(r45[1, 1], sqrt(2) / 2, 1e-5)
        @test near(r45[2, 1], -sqrt(2) / 2, 1e-5)
        @test near(r45[1, 2], sqrt(2) / 2, 1e-5)
        @test near(r45[2, 2], sqrt(2) / 2, 1e-5)
    end

    @testset "Mat3 * Vec2 affine point transform" begin
        @test mat3() * V(1.25, -3.5) == V(1.25, -3.5)
        @test translate(V(5, -2)) * V(1, 2) == V(6, 0)
        @test translate(V(0, 7)) * V(4, 2) == V(4, 9)
        @test scale(V(2, 3)) * V(1.5, -0.25) == V(3, -0.75)
        # rotate(pi/2) maps (1,0) -> (0,1) and (0,1) -> (-1,0)
        r90 = rotate(Float32(π) / 2)
        @test Vnear(r90 * V(1, 0), V(0, 1), 1e-6)
        @test Vnear(r90 * V(0, 1), V(-1, 0), 1e-6)
        # transform(m, v) helper matches m * v exactly
        t2 = translate(V(5, -2))
        @test transform(t2, V(1, 2)) == t2 * V(1, 2)
        @test transform(r90, V(1, 0)) == r90 * V(1, 0)
    end

    @testset "transform(m, rect) bounding box" begin
        t2 = translate(V(1, 2))
        @test transform(t2, R(0.5, 1.5, 2, 3)) == R(1.5, 3.5, 2, 3)
        @test transform(mat3(), R(-2.5, 1.5, 4, 6)) == R(-2.5, 1.5, 4, 6)
        # 45-degree rotation of the unit square: bbox = [-s, 0] + [0, s+c]
        # with s = c = sqrt(2)/2 (hand math, atol covers Float32 rounding)
        g = transform(rotate(Float32(π) / 4), R(0, 0, 1, 1))
        @test near(g.x, -sqrt(2) / 2, 1e-5)
        @test near(g.y, Float32(0), 1e-6)
        @test near(g.w, sqrt(2), 1e-5)
        @test near(g.h, sqrt(2), 1e-5)
    end

    @testset "composition order (upstream: m * n applies n first to the point)" begin
        T = translate(V(5, 0))
        S = scale(V(2, 3))
        p = V(1, 0)
        # exact algebra; two readings, same result -- and the two orders
        # differ, so this pins the multiplication direction
        @test (T * S) * p == T * (S * p)
        @test (T * S) * p == V(7, 0)
        @test (S * T) * p == S * (T * p)
        @test (S * T) * p == V(12, 0)
        @test (T * S) * p != (S * T) * p
        # triple composition, exact: (1,2)∘(3,4)∘scale(2,3) on (0.5,0.5)
        T1 = translate(V(1, 2))
        T2 = translate(V(3, 4))
        P = V(0.5, 0.5)
        @test (T1 * (T2 * S)) * P == V(5, 7.5)
        @test (T1 * (T2 * S)) * P == T1 * (T2 * (S * P))
        # rotation mixing (sin/cos: tolerate Float32 rounding on both sides)
        R90 = rotate(Float32(π) / 2)
        TT = translate(V(2, 0))
        q = V(1, 1)
        @test Vnear((R90 * TT) * q, R90 * (TT * q), 1e-5)
        @test Vnear((R90 * TT) * q, V(-1, 3), 1e-5)
        @test Vnear((TT * R90) * q, V(1, 1), 1e-5)
    end

    @testset "determinant, transpose, inverse" begin
        @test determinant(mat3()) == Float32(1)
        @test determinant(translate(V(5, 2))) == Float32(1)
        @test determinant(scale(V(2, 3))) == Float32(6)
        @test near(determinant(rotate(Float32(0.5))), Float32(1), 1e-6)

        # hand values for translate(5,0) * scale(2,3)
        ts = translate(V(5, 0)) * scale(V(2, 3))
        @test (ts[1, 1], ts[2, 1], ts[3, 1]) == (2, 0, 5)
        @test (ts[1, 2], ts[2, 2], ts[3, 2]) == (0, 3, 0)
        @test (ts[1, 3], ts[2, 3], ts[3, 3]) == (0, 0, 1)
        @test determinant(ts) == Float32(6)

        tr = transpose(ts)
        @test (tr[1, 1], tr[2, 1], tr[3, 1]) == (2, 0, 0)
        @test (tr[1, 2], tr[2, 2], tr[3, 2]) == (0, 3, 0)
        @test (tr[1, 3], tr[2, 3], tr[3, 3]) == (5, 0, 1)
        @test transpose(transpose(ts)) == ts

        # round trip within 1e-5 (Float32), both composition orders
        m = translate(V(5.5, -2)) *
            (rotate(Float32(0.5)) * scale(V(2.5, 1.5)))
        @test near(determinant(m), Float32(3.75), 1e-5)
        @test near(determinant(transpose(m)), determinant(m), 1e-5)
        p0 = V(1.75, -3.25)
        @test Vnear((m * inverse(m)) * p0, p0, 1e-5)
        @test Vnear((inverse(m) * m) * p0, p0, 1e-5)
        # inverse of a translation is the negated translation (exact)
        @test inverse(translate(V(5, -2))) == translate(V(-5, 2))
        # inverse of a pure rotation equals the negated rotation (approx)
        @test Mnear(inverse(rotate(Float32(0.5))), rotate(-Float32(0.5)), 1e-5)

        # singular matrix: upstream has no guard; 1/0 yields Inf/NaN,
        # not an exception
        z = scale(V(0, 2))
        @test determinant(z) == Float32(0)
        zi = inverse(z)
        @test any(!isfinite, [zi[i, j] for i in 1:3 for j in 1:3])
    end

    @testset "snapToPixels vs snap_to_pixels.tsv (135 rows, exact Float32)" begin
        meta, _, rows = VetraRef.read_table("snap_to_pixels")
        @test meta["source"] == "pixie common.nim snapToPixels"
        @test length(rows) == 135
        f32(s) = parse(Float32, s)
        function row_ok(row)
            g = snapToPixels(rect(f32(row[1]), f32(row[2]),
                f32(row[3]), f32(row[4])))
            return g.x == f32(row[5]) && g.y == f32(row[6]) &&
                g.w == f32(row[7]) && g.h == f32(row[8])
        end
        @test all(row_ok, rows)
        # one row checked by hand: (5, 0, 1, 10.5) -> (5, 0, 1, 11)
        @test snapToPixels(R(5, 0, 1, 10.5)) == R(5, 0, 1, 11)
    end
end
