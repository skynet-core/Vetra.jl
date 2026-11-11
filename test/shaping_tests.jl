# T029: optional shaping and bidirectional text (D033, docs/TEXT_LAYOUT.md §5).
#
# Expected values per the §8 reference protocol (option 2: maintained
# external layout engine with recorded version): the system libharfbuzz
# 12.3.2 through the C driver tools/oracle/hb_refshape.c, pinned in
# test/reference/shaping_reference.tsv over the pinned OFL fonts in
# test/fixtures/ (sha256 sidecars + meta lines). The provider under test
# is HarfBuzz_jll (harfbuzz 15.1.0) — the two libraries agree on all 9
# pinned cases (T029 probe, task record). Bidi permutations and
# engagement are hand-derived (UAX#9 simplified, §5.3; §7.6).

using Test
using SHA
using .VetraRef

const FIX = joinpath(@__DIR__, "fixtures")
const AR = joinpath(FIX, "NotoSansArabic-Regular.ttf")
const DV = joinpath(FIX, "NotoSansDevanagari-Regular.ttf")
const REF = joinpath(@__DIR__, "reference")
const UPSTREAM_FONTS = joinpath(dirname(@__DIR__), ".reference",
    "upstream", "tests", "fonts")

"""4-byte UAX#24 script tag from a 4-char string."""
function scriptTag(s::String)
    t = UInt32(0)
    for c in s
        t = (t << 8) | UInt32(c)
    end
    return t
end

"""1-based x columns that contain any non-zero alpha in the row-major
premultiplied buffer."""
function _inkColumns(img::Image, w::Int)
    cols = Int[]
    h = height(img)
    for x in 1:w
        anynz = false
        for y in 1:h
            if img.data[((y - 1) * w + (x - 1)) * 4 + 4] != 0x00
                anynz = true
                break
            end
        end
        if anynz
            push!(cols, x)
        end
    end
    return cols
end

@testset "T029 shaping and bidi" begin

    tfA = readTypeface(AR)
    tfD = readTypeface(DV)
    tfR = readTypeface(joinpath(UPSTREAM_FONTS, "Roboto-Regular_1.ttf"))
    fA = newFont(tfA)
    fA.size = Float32(16)
    sA = scale(fA) # 16 / 1000 (font units -> px)

    @testset "fixture provenance (sha256 pins)" begin
        meta, cols, rows = VetraRef.read_table("shaping_reference")
        @test meta["font_arabic_sha256"] ==
            VetraRef.hexdigest(sha256(read(AR)))
        @test meta["font_devanagari_sha256"] ==
            VetraRef.hexdigest(sha256(read(DV)))
        @test meta["font_arabic_license"] == "SIL Open Font License 1.1"
        @test meta["font_devanagari_license"] ==
            "SIL Open Font License 1.1"
        @test meta["font_roboto_sha256"] ==
            VetraRef.hexdigest(sha256(read(joinpath(UPSTREAM_FONTS,
                "Roboto-Regular_1.ttf"))))
        @test meta["font_roboto_license"] == "Apache License 2.0"
        @test meta["reference_version"] == "12.3.2"
        @test occursin("hb_refshape.c", meta["generator"])
        # sidecars
        @test strip(read(joinpath(REF, "shaping_reference.tsv.sha256"),
            String)) ==
            VetraRef.hexdigest(
                sha256(read(joinpath(REF, "shaping_reference.tsv")))) *
            "  shaping_reference.tsv"
        for (path, name) in [(AR, "NotoSansArabic-Regular.ttf"),
            (DV, "NotoSansDevanagari-Regular.ttf")]
            @test strip(read(path * ".sha256", String)) ==
                VetraRef.hexdigest(sha256(read(path))) * "  " * name
        end
        # fonts load: glyf TTFs, the pin's glyph counts
        @test length(tfA.opentype.glyf.offsets) == 1631
        @test length(tfD.opentype.glyf.offsets) == 967
    end

    @testset "bindings vs the pinned reference (libharfbuzz 12.3.2)" begin
        meta, cols, rows = VetraRef.read_table("shaping_reference")
        @test cols == ["case", "font", "script", "direction", "language",
            "codepoints", "gid", "cluster", "x_advance", "x_offset",
            "y_offset"]
        cases = Dict{String, Vector{Vector{String}}}()
        for row in rows
            r = String.(row)
            if haskey(cases, r[1])
                push!(cases[r[1]], r)
            else
                cases[r[1]] = [r]
            end
        end
        @test length(cases) == 10
        for (tag, crows) in sort(collect(cases), by = x -> x[1])
            r1 = crows[1]
            font = r1[2] == "NotoSansArabic-Regular" ? tfA :
                (r1[2] == "NotoSansDevanagari-Regular" ? tfD : tfR)
            script = scriptTag(r1[3])
            dir = r1[4] == "RTL" ? RightToLeft : LeftToRight
            lang = r1[5]
            cps = UInt32[parse(UInt32, c; base = 16) for c in split(r1[6],
                ";")]
            out = shapeText(font, cps; script = script, direction = dir,
                language = lang)
            # the reference rows are buffer order (visual for RTL runs) —
            # reconstruct it from the logical per-cluster output
            buf = Vector{ShapedGlyph}()
            if dir === RightToLeft
                for cl in reverse(out)
                    append!(buf, reverse(cl))
                end
            else
                for cl in out
                    append!(buf, cl)
                end
            end
            @test length(buf) == length(crows)
            for (i, g) in enumerate(buf)
                exp = crows[i]
                @test g.gid == parse(Int, exp[7])
                @test g.advance == Float32(parse(Int, exp[9]))
                @test g.xOffset == Float32(parse(Int, exp[10]))
                @test g.yOffset == Float32(parse(Int, exp[11]))
            end
            # the reference's cluster column is monotone in buffer order
            # (ascending for LTR, descending for RTL) — the assumption
            # behind the reconstruction
            cls = [parse(Int, r[8]) for r in crows]
            if length(cls) > 1
                if dir === RightToLeft
                    @test all(cls[i] >= cls[i + 1] for i in 1:length(cls) - 1)
                else
                    @test all(cls[i] <= cls[i + 1] for i in 1:length(cls) - 1)
                end
            end
            # per-cluster grouping: one entry per contiguous cluster run
            groups = length(cls) == 0 ? 0 :
                1 + count(cls[i] != cls[i + 1] for i in 1:length(cls) - 1)
            @test length(out) == groups
        end
        # script matters (hand-derived from the pinned rows): the same
        # codepoints shape differently under Arab vs Zinh
        katabAr = shapeText(tfA, UInt32[0x0643, 0x062a, 0x0628];
            script = scriptTag("Arab"), direction = RightToLeft,
            language = "ar")
        katabZin = shapeText(tfA, UInt32[0x0643, 0x062a, 0x0628];
            script = scriptTag("Zinh"), direction = RightToLeft,
            language = "ar")
        @test katabAr != katabZin
        @test [katabAr[i][1].gid for i in eachindex(katabAr)] ==
            [424, 59, 36] # logical cluster order (kaf, ta, beh)
        @test [katabZin[i][1].gid for i in eachindex(katabZin)] ==
            [420, 56, 34]
        # auto script detection (§5.4: first non-neutral) matches the
        # explicit one where the run's first non-neutral is unambiguous
        @test shapeText(tfA, UInt32[0x0643, 0x062a, 0x0628];
            direction = RightToLeft, language = "ar") == katabAr
        @test shapeText(tfD, UInt32[0x0915, 0x094d, 0x0937];
            direction = LeftToRight, language = "hi") ==
            shapeText(tfD, UInt32[0x0915, 0x094d, 0x0937];
                script = scriptTag("Deva"), direction = LeftToRight,
                language = "hi")
        # empty run
        @test shapeText(tfA, UInt32[]) == Vector{Vector{ShapedGlyph}}()
    end

    @testset "glyphPathByGid (GID -> outline, no cmap)" begin
        # digits are not substituted: the shaped GID is the cmap GID, so
        # the by-GID path must equal the pinned T009 by-rune path
        g1 = shapeText(tfA, UInt32[0x0661]; script = scriptTag("Arab"),
            language = "ar")[1][1].gid
        @test g1 == 1420 # pinned reference (arab-arabic-digits, c0)
        @test glyphPathByGid(tfA, g1).commands ==
            getGlyphPath(tfA, UInt32(0x0661)).commands
        # .notdef and out-of-range all map to GID 0
        n0 = glyphPathByGid(tfA, 0)
        @test n0.commands == glyphPathByGid(tfA, -1).commands
        @test n0.commands ==
            glyphPathByGid(tfA, length(tfA.opentype.glyf.offsets)).commands
        @test n0.commands == glyphPathByGid(tfA, 10_000_000).commands
        # the missing-GID case of the reference shapes GID 0 with the
        # font's .notdef advance (600 — pinned row missing-han)
        oh = shapeText(tfA, UInt32[0x4e00]; script = scriptTag("Hani"),
            language = "en")
        @test oh[1][1].gid == 0
        @test oh[1][1].advance == Float32(600)
        @test n0.commands == glyphPathByGid(tfA, oh[1][1].gid).commands
    end

    @testset "punctuation mirroring (UAX#9 L2)" begin
        # in an RTL-resolved run, the codepoint is mirrored before
        # shaping, so e.g. [ shapes exactly as ] does in LTR
        # (NotoSansDevanagari carries both mirror sides — the pinned
        # cmap gids: ( ) 798/799, < > 818/820, [ ] 822/824, { } 827/829)
        for (a, b, ga, gb) in [(0x0028, 0x0029, 798, 799),
            (0x003c, 0x003e, 818, 820), (0x005b, 0x005d, 822, 824),
            (0x007b, 0x007d, 827, 829)]
            @test shapeText(tfD, UInt32[a]; script = scriptTag("Zyyy"),
                direction = RightToLeft, language = "hi")[1][1].gid ==
                gb # mirrored to the partner's LTR glyph
            @test shapeText(tfD, UInt32[a]; script = scriptTag("Zyyy"),
                direction = LeftToRight, language = "hi")[1][1].gid ==
                ga # an LTR run does not mirror
        end
    end

    @testset "bidi permutations (hand-derived, UAX#9 simplified §5.3)" begin
        # RTL: an all-strong line reverses the cluster order
        l = layoutParagraph(newParagraph("كتب", fA; dir = RightToLeft))
        @test l.shaped[1] == [3, 2, 1]
        @test length(l.lines) == 1
        # line width = the pinned advances in logical entry order
        # (kaf 412, ta 373, beh 1093 font units)
        m = paragraphMetrics(l)
        @test m.width == Float32(412) * sA + Float32(373) * sA +
            Float32(1093) * sA
        @test m.lineCount == 1
        # LTR with an embedded RTL run: the run reverses in place, the
        # rest stays
        l2 = layoutParagraph(newParagraph("ab كتب cd", fA))
        @test l2.shaped[1] == [1, 2, 3, 6, 5, 4, 7, 8, 9]
        @test l2.lines[1].clusters == (1:9)
        # RTL base with an embedded digit run (L2E): digits keep LTR
        # order, the rest reverses (§7.6); wraps at the space
        l3 = layoutParagraph(newParagraph("كتب 123", fA; width = 60,
            dir = RightToLeft))
        @test length(l3.lines) == 2
        @test [collect(ln.clusters) for ln in l3.lines] == [1:4, 5:7]
        @test l3.shaped[1] == [4, 3, 2, 1] # trailing space leftmost
        @test l3.shaped[2] == [5, 6, 7] # digits LTR under RTL base
        # styled runs: the span boundary is a run boundary; the RTL
        # segment (kaf, ta) reverses internally and sits right of the
        # LTR segment (a, b)
        l5 = layoutParagraph(newParagraph([newSpan("ab", fA),
            newSpan("كت", fA)]; dir = RightToLeft))
        @test l5.shaped[1] == [4, 3, 1, 2]
        # pure LTR: identity permutation
        fR = newFont(tfR)
        l4 = layoutParagraph(newParagraph("hello", fR))
        @test l4.shaped[1] == [1, 2, 3, 4, 5]
        # permutations are always bijections over the line's clusters
        for (perm, ln) in zip(l3.shaped, l3.lines)
            @test sort(perm) == collect(ln.clusters)
        end
    end

    @testset "RTL placement (harfbuzz cairo-bridge pen model)" begin
        # "كتب" drawn at (10, 6): the RTL buffer is visual order
        # (beh, ta, kaf); advances 1093/373/412 font units
        l = layoutParagraph(newParagraph("كتب", fA; dir = RightToLeft))
        slp = l.shapedPos[1]
        @test slp.order == [3, 2, 1]
        @test slp.pos[1].glyphs[1][2] == Float32(0) # beh at the origin
        @test slp.pos[2].glyphs[1][2] == Float32(1093) * sA # ta
        @test slp.pos[3].glyphs[1][2] == Float32(1093) * sA +
            Float32(373) * sA # kaf
        # selection rects cover the advance extents
        @test slp.pos[1].rectX0 == Float32(0)
        @test slp.pos[1].rectX1 == Float32(1093) * sA
        @test slp.pos[3].rectX1 == Float32(1093) * sA + Float32(373) *
            sA + Float32(412) * sA
        # render: ink stays inside the line extent [10, 10 + W]
        img = newImage(64, 48)
        fillParagraph(img, l, 10, 6)
        cols = _inkColumns(img, 64)
        @test !isempty(cols)
        @test minimum(cols) >= 10
        @test maximum(cols) <= Int(ceil(10 + Float32(1093) * sA +
            Float32(373) * sA + Float32(412) * sA))
        # ink exists at both ends of the line (beh left, kaf right)
        @test minimum(cols) <= 27
        @test maximum(cols) >= 33
        # RightAlign: the line's right edge sits on the box width
        lR = layoutParagraph(newParagraph("كتب", fA; width = 120,
            hAlign = RightAlign, dir = RightToLeft))
        pr = lR.shapedPos[1]
        @test pr.pos[3].glyphs[1][2] + pr.pos[3].glyphs[1][4] ≈
            Float32(120) # kaf's right edge on the box edge
        imgR = newImage(160, 48)
        fillParagraph(imgR, lR, 0, 6)
        colsR = _inkColumns(imgR, 160)
        @test maximum(colsR) >= 118
        @test minimum(colsR) >= Int(ceil(120 - Float32(1093) * sA -
            Float32(373) * sA - Float32(412) * sA)) - 1
    end

    # M004: the LTR-base engagement case ("ab katab cd") was previously
    # permutation-pinned only; its placement is now pinned against the
    # independent C oracle (hb_refshape over NotoSansArabic, 12.3.2):
    # Latin a/b/c/d -> .notdef advance 600 (script Latn, en), space ->
    # 260 (both scripts), katab -> 412/373/1093 (pinned TSV). Pen model:
    # forward in visual order, x = pen + sum of earlier advances (xoff 0).
    @testset "LTR-base mixed placement (cairo-bridge pen model)" begin
        l = layoutParagraph(newParagraph("ab \u0643\u062a\u0628 cd", fA))
        @test !isempty(l.shapedPos)
        @test l.shaped[1] == [1, 2, 3, 6, 5, 4, 7, 8, 9]
        slp = l.shapedPos[1]
        x(e) = slp.pos[findfirst(==(e), slp.order)].glyphs[1][2]
        # font-unit pen sums (entry -> expected units before it)
        for (e, fu) in [(1, 0), (2, 600), (3, 1200), (6, 1460),
            (5, 2553), (4, 2926), (7, 3338), (8, 3598), (9, 4198)]
            @test abs(x(e) / sA - fu) < Float32(0.001)
        end
        # content width = the non-wrap entries' advances in line order
        @test l.lines[1].width == Float32(600) * sA + Float32(600) * sA +
            Float32(412) * sA + Float32(373) * sA + Float32(1093) * sA +
            Float32(600) * sA + Float32(600) * sA
        # render: the RTL block's ink sits right of the Latin lead
        img = newImage(96, 40)
        fillParagraph(img, l, 2, 4)
        cols = _inkColumns(img, 96)
        @test !isempty(cols)
        @test minimum(cols) >= 2
        @test maximum(cols) <= 2 + Int(ceil(4198 * sA + 600 * sA))
    end

    @testset "shaped render: joined vs isolated forms (§7.4)" begin
        # contextual forms: the shaped GIDs differ from the isolated
        # cmap mapping (420/56/34)
        gids = shapeText(tfA, UInt32[0x0643, 0x062a, 0x0628];
            script = scriptTag("Arab"), direction = RightToLeft,
            language = "ar")
        shapedGids = [g.gid for cl in gids for g in cl]
        isoGids = [Int(tfA.opentype.cmap.runeToGlyphId[c]) for c in
            (UInt32[0x0643, 0x062a, 0x0628])]
        @test isoGids == [420, 56, 34]
        @test shapedGids == [424, 59, 36]
        @test shapedGids != isoGids
        # the shaped render is non-empty and differs from the legacy
        # (isolated) render of the same text
        fIsolated = copy(fA)
        imgShaped = newImage(80, 40)
        fillParagraph(imgShaped,
            layoutParagraph(newParagraph("كتب", fA;
                dir = RightToLeft)), 4, 4)
        # legacy path: same text forced through typeset (isolated
        # forms) — LTR arrangement, cmap GIDs 420/56/34
        arr = typeset(fIsolated, "كتب")
        imgLegacy = newImage(80, 40)
        fillText(imgLegacy, arr)
        @test imgShaped.data != imgLegacy.data
        @test count(!iszero, imgShaped.data) > 0
        @test count(!iszero, imgLegacy.data) > 0
    end

    @testset "Indic conjuncts (§7.5)" begin
        # क + ् + ṣṣa (0915 094d 0937) shapes to the single conjunct
        # GID 179 (pinned)
        ksha = shapeText(tfD, UInt32[0x0915, 0x094d, 0x0937];
            script = scriptTag("Deva"), language = "hi")
        @test length(ksha) == 1
        @test ksha[1][1].gid == 179
        @test ksha[1][1].advance == Float32(712)
        # अ+क्+ष+र (the reference word deva-akshara): the conjunct
        # absorbs the vowel-sign cluster (pinned clusters 0, 1, 4 —
        # cluster 2 has no separate glyph)
        ak = shapeText(tfD,
            UInt32[0x0905, 0x0915, 0x094d, 0x0936, 0x0930];
            script = scriptTag("Deva"), language = "hi")
        @test length(ak) == 3
        @test [ak[1][1].gid, ak[2][1].gid, ak[3][1].gid] == [9, 495, 52]
        # LTR Indic paragraphs stay on the legacy (unshaped) path by
        # engagement (D033): grapheme clusters per UAX#29 (virama is
        # Extend — no break before it; 0936/0930 are letters — breaks
        # between them): अ | क् | ष | र = 4 clusters, identity order
        fD = newFont(tfD)
        l = layoutParagraph(newParagraph("\u0905\u0915\u094d\u0936\u0930", fD))
        @test length(l.clusters) == 4
        @test l.shaped[1] == [1, 2, 3, 4]
        @test isempty(l.shapedPos)
        # legacy width = the sum of the per-codepoint selection-rect
        # widths, each integer-rounded (T028 pin): 9 + 9 + 0 + 8 + 5
        # (764/762/0/680/409 units at 12 px; the virama's cmap glyph
        # has hmtx advance 0)
        m = paragraphMetrics(l)
        @test m.width == Float32(31)
        img = newImage(160, 40)
        fillParagraph(img, l, 2, 4)
        @test count(!iszero, img.data) > 0
    end

    @testset "ligatures (GSUB type 4, §5.2)" begin
        # "fi" in Roboto (pinned reference case roboto-fi): the two
        # codepoints become one ligature glyph (cluster 0) with the
        # ligature advance — not the sum of the single glyphs
        fR = newFont(tfR)
        fi = shapeText(tfR, UInt32[0x0066, 0x0069]; script =
            scriptTag("Latn"), language = "en")
        @test length(fi) == 1
        @test fi[1][1].gid == 444 # pinned reference row
        @test fi[1][1].advance == Float32(1134)
        # "ff" is not ligated in Roboto: two separate glyphs
        ff = shapeText(tfR, UInt32[0x0066, 0x0066]; script =
            scriptTag("Latn"), language = "en")
        @test length(ff) == 2
        # the ligature renders through glyphPathByGid (outline exists)
        @test !isempty(glyphPathByGid(tfR, 444).commands)
    end

    @testset "combining marks and missing glyphs (§5.2)" begin
        # missing base + missing mark: the pinned reference attributes
        # both .notdef glyphs to the base's cluster (harfbuzz merges the
        # clusters — no silent cluster drop at the layout level: both
        # grapheme entries remain)
        lc = shapeText(tfA, UInt32[0x0065, 0x0301]; script =
            scriptTag("Latn"), language = "en")
        @test length(lc) == 1
        @test length(lc[1]) == 2
        @test all(g.gid == 0 for cl in lc for g in cl)
        # no strong RTL here, so the paragraph stays on the legacy
        # path. "e\u0301" is one grapheme cluster (GB9: no break
        # before the combining mark) with the identity permutation
        lMix = layoutParagraph(newParagraph("e\u0301", fA))
        @test length(lMix.clusters) == 1
        @test isempty(lMix.shapedPos)
        @test lMix.shaped[1] == [1]
        # missing glyph on the shaped path: the cluster is kept with
        # the .notdef advance (pinned row missing-han: 600 units) and
        # the .notdef outline (gid 0) is drawn — not a hole
        l = layoutParagraph(newParagraph("\u4e00", fA; dir = RightToLeft))
        @test length(l.clusters) == 1
        @test l.shapedPos[1].pos[1].glyphs[1][1] == 0
        @test l.shapedPos[1].pos[1].glyphs[1][4] == Float32(600) * sA
        img = newImage(32, 32)
        fillParagraph(img, l, 4, 4)
        @test count(!iszero, img.data) > 0
        # missing glyph on the legacy path (T009 pin): advance kept
        # (600 units -> 9.6 px, rect-rounded to 10), outline empty
        lg = layoutParagraph(newParagraph("\u4e00", fA))
        @test length(lg.clusters) == 1
        @test isempty(lg.shapedPos)
        @test lg.lines[1].width == Float32(10)
        imgL = newImage(32, 32)
        fillParagraph(imgL, lg, 4, 4)
        @test count(!iszero, imgL.data) == 0
    end

    @testset "engagement and legacy behavior" begin
        # RTL always shapes (provider present in this environment)
        l = layoutParagraph(newParagraph("كتب", fA; dir = RightToLeft))
        @test !isempty(l.shapedPos)
        @test isempty(l.arrangement.runes)
        # LTR with strong RTL content shapes too
        l2 = layoutParagraph(newParagraph("ab كتب cd", fA))
        @test !isempty(l2.shapedPos)
        # pure LTR stays on the legacy typeset path (byte-unchanged
        # machinery: the arrangement carries the runes)
        fR = newFont(tfR)
        l3 = layoutParagraph(newParagraph("hello", fR))
        @test isempty(l3.shapedPos)
        @test !isempty(l3.arrangement.runes)
        # construction is fine for RTL; layout engages the shaper. A
        # strong-LTR word keeps its internal order even in an RTL
        # paragraph (UAX#9 L2 — the whole run is one LTR segment)
        p = newParagraph("hello", fR; dir = RightToLeft)
        @test p.dir === RightToLeft
        @test layoutParagraph(p).shaped[1] == [1, 2, 3, 4, 5]
    end

    # M004 FFI lifecycle: the previous `_hbFace` used `get` with a
    # default block, so its cache was never populated and every shaping
    # call leaked a fresh native (blob, face, font) triple. Now: one
    # triple per live font object, reused across calls, kept rooted with
    # GC.@preserve for the duration of each shape, destroyed by a
    # finalizer when the font is collected, and the shape buffer is freed
    # on every exit path (success and error).
    @testset "FFI lifecycle (face reuse, bounded retention, cleanup)" begin
        # The cache is populated and reused (the `get` bug left it
        # empty: every call built and leaked a fresh triple).
        st1 = Vetra._hbFace(tfA.opentype)
        st2 = Vetra._hbFace(tfA.opentype)
        @test st1 == st2
        n0 = length(Vetra._HB_FACES)
        for _ in 1:10
            shapeText(tfA, UInt32[0x0643]; script = scriptTag("Arab"),
                language = "ar")
        end
        @test Vetra._hbFace(tfA.opentype) == st1
        @test length(Vetra._HB_FACES) == n0 # no growth while live

        # GC pressure on ephemeral fonts: each font is shaped from its
        # own frame (a top-level `let` local would not be reliably dead
        # at GC time — the interpreter conservatively marks the stale
        # slot of its still-active frame), the GIDs must stay correct
        # (the native triple must not be destroyed mid-use), and once
        # the font is collected the cache returns to its previous size.
        # The finalizer flag observes the collection directly; dict
        # length alone would not prove the font was reclaimed.
        finalized = Ref(false)
        function _m004ephemeralGids()
            fresh = parseOpenType(Vector{UInt8}(read(AR)))
            finalizer(fresh) do _
                finalized[] = true
            end
            return [g.gid for cl in shapeText(
                Typeface(fresh, ""), UInt32[0x0643, 0x062a, 0x0628];
                script = scriptTag("Arab"), direction = RightToLeft,
                language = "ar") for g in cl]
        end
        @test _m004ephemeralGids() == [424, 59, 36]
        @test !finalized[]
        GC.gc()
        @test finalized[]
        @test length(Vetra._HB_FACES) == n0
        for _ in 1:50
            @test _m004ephemeralGids() == [424, 59, 36]
            GC.gc()
        end
        @test length(Vetra._HB_FACES) == n0

        # Language interop: a valid tag longer than 4 bytes reaches
        # harfbuzz intact and is interned (ar-EG shapes this run as ar —
        # oracle-checked), not truncated or misread.
        @test [g.gid for cl in shapeText(
            tfA, UInt32[0x0643, 0x062a, 0x0628];
            script = scriptTag("Arab"), direction = RightToLeft,
            language = "ar-EG") for g in cl] == [424, 59, 36]
        # Invalid input: BCP47 tags are ASCII; empty/non-ASCII tags are
        # rejected with a clear error (harfbuzz would otherwise silently
        # sanitize, e.g. "é" -> empty language). The error is thrown
        # inside the buffer's lifetime, and the cached face still shapes
        # correctly after.
        for bad in ("", "\u00e9")
            try
                shapeText(tfA, UInt32[0x0643];
                    script = scriptTag("Arab"), language = bad)
                @test false
            catch e
                @test e isa ArgumentError &&
                    e.msg == "Invalid language tag: $(bad)"
            end
        end
        @test length(Vetra._HB_FACES) == n0
        # RTL direction: the pinned katab values (Arab LTR shapes the
        # other contextual forms — oracle-checked).
        @test [g.gid for cl in shapeText(
            tfA, UInt32[0x0643, 0x062a, 0x0628];
            script = scriptTag("Arab"), direction = RightToLeft,
            language = "ar") for g in cl] ==
            [424, 59, 36]
    end
end
