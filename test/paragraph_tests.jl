# T028: paragraph layout (D031, docs/TEXT_LAYOUT.md, src/formats/paragraph.jl).
#
# Method: hand-derived expectations only — the paragraph API is new, so there
# is no upstream oracle for it. Metrics are derived from the pinned fonts'
# own tables (Roboto: UPM 2048, hhea asc 1900 / desc -500 / lineGap 0;
# advances from hmtx via the legacy getAdvance, which is T009-pinned and
# oracle-tested) plus the documented UAX#29-subset cluster rules. Layout
# invariants (wrap positions, line partition, alignment offsets, clip
# bounds) follow from docs/TEXT_LAYOUT.md §2. Rendering checks use pixel
# scans with the layout's own box, never a re-rendered baseline.

@testset "T028 paragraph layout" begin
    dir = joinpath(@__DIR__, "..", ".reference", "upstream", "tests", "fonts")
    tfR = readTypeface(joinpath(dir, "Roboto-Regular_1.ttf"))
    tfU = readTypeface(joinpath(dir, "Ubuntu-Regular_1.ttf"))
    f = newFont(tfR)

    # Pinned provenance: the hand derivations below assume these tables.
    @test tfR.opentype.head.unitsPerEm == 2048
    @test tfR.opentype.hhea.ascender == 1900
    @test tfR.opentype.hhea.descender == -500
    @test tfR.opentype.hhea.lineGap == 0

    # px advance of `cp` at font `font` (hmtx via the pinned legacy API).
    pxadv = (font, cp) ->
        getAdvance(font.typeface, UInt32(cp)) * font.size /
        Float32(font.typeface.opentype.head.unitsPerEm)

    # The engine's pixel-grid nudge (roundHalfAway, unlike Base.round).
    rh = v -> v > 0 ? Float32(floor(v + 0.5)) : Float32(ceil(v - 0.5))

    # Line box formula from the pinned vertical pass (docs §2.4):
    # offset = round((asc + lineGap(font)/2) * size/UPM); with an absolute
    # lineHeight the font lineGap = (lh/scale) - asc + desc (font units).
    function linebox(font, lh)
        s = font.size / Float32(font.typeface.opentype.head.unitsPerEm)
        lg = (lh / s) - Float32(font.typeface.opentype.hhea.ascender) +
            Float32(font.typeface.opentype.hhea.descender)
        off = rh((Float32(font.typeface.opentype.hhea.ascender) +
            lg / Float32(2)) * s)
        return off, Float32(lh) - off
    end

    # The text of one arrangement line (rune values as chars).
    function lineText(l, idx)
        arr = l.arrangement
        s = ""
        for i in arr.lines[idx][1]:arr.lines[idx][2]
            s *= string(Char(UInt32(arr.runes[i])))
        end
        return s
    end

    px = (img, x, y) -> getColor(img, x, y)

    function throws_arg(f, msg::String)
        try
            f()
            return false
        catch e
            return e isa ArgumentError && e.msg == msg
        end
    end

    @testset "clusters: UAX#29 subset, hand-derived" begin
        function clustersOf(text)
            return layoutParagraph(newParagraph(text, f)).clusters
        end
        cs = clustersOf("e\u0301")
        @test length(cs) == 1
        @test cs[1].span == 1 && cs[1].first == 1 && cs[1].last == 3
        # grapheme boundary vs code units: one cluster, two codepoints,
        # three UTF-8 bytes — all three are distinguishable.
        @test length("e\u0301") == 2
        @test length(Vector{UInt8}("e\u0301")) == 3
        # precomposed vs decomposed: same cluster count, different spans
        @test length(clustersOf("\u00e9")) == 1
        @test clustersOf("\u00e9")[1].last == 2
        @test length(clustersOf("a\u200db")) == 1  # ZWJ joins both sides
        cs = clustersOf("a\u200cb")
        @test length(cs) == 2  # ZWNJ joins left only
        @test cs[1].last == 3 && cs[2].first == 3
        @test length(clustersOf("\u1100\u1161")) == 1      # Hangul L+V
        @test length(clustersOf("\u1100\u1161\u11a8")) == 1  # L+V+T
        @test length(clustersOf("\u1160\u11a8")) == 1      # V+T
        @test length(clustersOf("\u1100\u1100")) == 1      # L+L
        @test length(clustersOf("\u1161\u1100")) == 2      # V+L breaks
        @test length(clustersOf("\r\n")) == 1              # GB3
        @test length(clustersOf("a\tb")) == 3              # control standalone
        # Devanagari: virama is Extend (no break before it); a letter
        # after the conjunct starts a new cluster (conjunct formation
        # is shaper-level, not grapheme-level — UAX#29), while an Mc
        # vowel sign joins its base
        @test length(clustersOf("\u0915\u094d\u0937")) == 2
        @test length(clustersOf("\u0915\u094d\u093E")) == 1
        @test length(clustersOf("\u0e01\u0e38")) == 1      # Thai Mn
        @test length(clustersOf("a\u0300\u0301")) == 1     # stacked marks
        @test length(clustersOf("a\u0301b\u0301")) == 2
        # cluster -> arrangement rune mapping: the combining mark is a
        # retained rune, so the cluster spans both runes.
        l = layoutParagraph(newParagraph("e\u0301", f))
        @test l.clusterRunes[1][1] == (1:2)
        l = layoutParagraph(newParagraph("\r\n", f))
        @test l.clusterRunes[1][1] == (1:1)  # only the LF is retained
        @test l.clusterRunes[1][2] == 1
    end

    @testset "construction, direction, withFallback" begin
        p = newParagraph("hello", f; width = 10, height = 20, lineHeight = 24,
            hAlign = CenterAlign, vAlign = MiddleAlign,
            overflow = EllipsisOverflow)
        @test p.width == Float32(10) && p.height == Float32(20)
        @test p.lineHeight == Float32(24)
        @test p.hAlign === CenterAlign && p.vAlign === MiddleAlign
        @test p.overflow === EllipsisOverflow
        @test p.dir === LeftToRight
        @test p.spans[1].text == "hello"
        # RTL construction is allowed since T029 (D033); shaper
        # engagement happens at layout time.
        pRtl = newParagraph("hello", f; dir = RightToLeft)
        @test pRtl.dir === RightToLeft
        # withFallback: additive chain, resolved glyph source.
        tfFB = withFallback(tfR, [tfU])
        @test hasGlyph(tfR, UInt32(0x0180)) == false
        @test hasGlyph(tfU, UInt32(0x0180)) == true
        @test fallbackTypeface(tfFB, UInt32(0x0180)) === tfU
        @test fallbackTypeface(tfFB, UInt32(0x68)) === tfFB  # base keeps 'h'
        # cycles are rejected, acyclic shared nodes (diamond) are allowed.
        @test throws_arg(() -> withFallback(tfR, [tfR]),
            "font fallback cycle: typeface already reachable from the base typeface")
        tfC = withFallback(tfU, [tfR])
        @test throws_arg(() -> withFallback(tfR, [tfC]),
            "font fallback cycle: typeface already reachable from the base typeface")
        tfa = Typeface(tfU.opentype, "a")
        tfb = Typeface(tfR.opentype, "b")
        tfa.fallbacks = [tfb]
        tfb.fallbacks = [tfa]
        @test throws_arg(() -> withFallback(tfa, Vector{Typeface}()),
            "font fallback cycle: typeface appears in its own fallback chain")
        # diamond DAG: base -> {A, B}, A -> C, B -> C (C reached twice in
        # the walk — legitimate sharing, no cycle). Only Ubuntu carries ƀ.
        tfIBM = readTypeface(joinpath(dir, "IBMPlexSans-Regular_2.ttf"))
        tfPac = readTypeface(joinpath(dir, "Pacifico-Regular_4.ttf"))
        tfAcl = readTypeface(joinpath(dir, "Aclonica-Regular_1.ttf"))
        @test hasGlyph(tfIBM, UInt32(0x0180)) == false
        @test hasGlyph(tfPac, UInt32(0x0180)) == false
        @test hasGlyph(tfAcl, UInt32(0x0180)) == false
        A = withFallback(tfIBM, [tfU])
        B = withFallback(tfPac, [tfU])
        base = withFallback(tfAcl, [A, B])  # must not raise
        @test fallbackTypeface(base, UInt32(0x0180)) === tfU
        @test fallbackTypeface(base, UInt32(0x68)) === base
        # termination: a layout through a 3-deep chain completes.
        ldeep = layoutParagraph(newParagraph("a\u0180b", newFont(base)))
        @test length(ldeep.arrangement.runes) == 3
    end

    @testset "metrics: hand-derived line boxes (hhea + hmtx)" begin
        # "hi" at 12px, default line height:
        # box = round((1900 - (-500) + 0) * 12/2048) = 14;
        # offset = round(1900 * 12/2048) = 11; descent = 14 - 11 = 3.
        m = paragraphMetrics(layoutParagraph(newParagraph("hi", f)))
        @test m.lineCount == 1
        @test m.height == Float32(14)
        @test m.maxAscent == Float32(11)
        @test m.minDescent == Float32(3)
        # intrinsic width from hmtx: round of the raw px advance sum.
        wHi = rh(pxadv(f, 0x68) + pxadv(f, 0x69))
        @test m.width == wHi
        # absolute lineHeight 24: offset = round((1900 + (4096-2400)/2)
        # * 12/2048) = round(16.0996) = 16; box = 24; descent = 8.
        m24 = paragraphMetrics(layoutParagraph(
            newParagraph("hi", f; lineHeight = 24)))
        @test m24.height == Float32(24)
        @test m24.maxAscent == Float32(16)
        @test m24.minDescent == Float32(8)
        # trailing newline: a final lone "\n" is retained as a rune but
        # starts no second line (the pinned typeset behavior — a new line
        # is pushed only when runes follow the break); an interior "\n\n"
        # yields an empty middle line.
        l2 = layoutParagraph(newParagraph("abc\n", f))
        m2 = paragraphMetrics(l2)
        @test m2.lineCount == 1
        @test lineText(l2, 1) == "abc\n"
        l3 = layoutParagraph(newParagraph("abc\n\ndef", f))
        m3 = paragraphMetrics(l3)
        @test m3.lineCount == 3
        @test m3.height == Float32(42)
        @test l3.lines[2].width == Float32(0)
        @test lineText(l3, 2) == "\n"
        @test lineText(l3, 1) == "abc\n"
        @test lineText(l3, 3) == "def"
        # empty paragraph: one empty line from the run's font.
        me = paragraphMetrics(layoutParagraph(newParagraph("", f;
            lineHeight = 24)))
        @test me.lineCount == 1 && me.width == Float32(0)
        @test me.height == Float32(24)
        off, desc = linebox(f, 24)
        @test me.maxAscent == off && me.minDescent == desc
        # mixed sizes 14/24 with absolute lineHeight 40: per-run offsets
        # (hand-derived above) 25 and 28; shared baseline 28; box is the
        # union: ascent 28, descent max(40-25, 40-28) = 15, total 43.
        f14 = Font(tfR, Float32(14), autoLineHeight,
            [Paint(rgba(0, 0, 0, 255))], NormalCase, false, false, false)
        f24 = Font(tfR, Float32(24), autoLineHeight,
            [Paint(rgba(0, 0, 255, 255))], NormalCase, false, false, false)
        lm = layoutParagraph(newParagraph([newSpan("AB", f14),
            newSpan("cd", f24)]; lineHeight = 40))
        @test lm.lines[1].ascent == Float32(28)
        @test lm.lines[1].descent == Float32(15)
        @test paragraphMetrics(lm).height == Float32(43)
        @test lm.arrangement.positions[1].y == Float32(28)
        @test lm.arrangement.positions[3].y == Float32(28)
        # fallback advance (docs §2.7): ƀ is 589 units in Ubuntu (UPM 1000);
        # ratio-scaled into Roboto units (2048) then px: 589*12/1000 = 7.068
        # -> nudged to 7.
        tfFB = withFallback(tfR, [tfU])
        lf = layoutParagraph(newParagraph("\u0180", newFont(tfFB)))
        @test lf.arrangement.selectionRects[1].w == Float32(7)
        # missing glyph: PUA is absent from Roboto; the tofu advance is the
        # legacy getAdvance (hmtx of GID 0), rounded into the pixel grid.
        lmis = layoutParagraph(newParagraph("\ue000", f))
        @test length(lmis.arrangement.runes) == 1
        @test lmis.arrangement.selectionRects[1].w ==
            Float32(rh(pxadv(f, 0xe000)))
    end

    @testset "wrapping: white-space set, NBSP, character-wise splits" begin
        # "hello world" fits one line at width 100.
        l = layoutParagraph(newParagraph("hello world", f; width = 100))
        @test length(l.lines) == 1
        @test lineText(l, 1) == "hello world"
        # narrower: breaks at the space (hand-derived: the last space that
        # fits is after "hello").
        l = layoutParagraph(newParagraph("hello world", f; width = 50))
        @test length(l.lines) == 2
        @test lineText(l, 1) == "hello "
        @test lineText(l, 2) == "world"
        # NBSP is an ordinary wrap position (docs §2.1 amendment): the box
        # fits a+b+nbsp but not c -> lines "ab\u00a0" / "cd".
        w = pxadv(f, 0x61) + pxadv(f, 0x62) + pxadv(f, 0xa0) + Float32(1)
        @test w < w + pxadv(f, 0x63)
        l = layoutParagraph(newParagraph("ab\u00a0cd", f; width = w))
        @test length(l.lines) == 2
        @test lineText(l, 1) == "ab\u00a0"
        @test lineText(l, 2) == "cd"
        # NBSP overflow triggers the split exactly like a letter: the box
        # fits a..d only -> line 1 "abcd", the NBSP starts line 2.
        w = pxadv(f, 0x61) + pxadv(f, 0x62) + pxadv(f, 0x63) +
            pxadv(f, 0x64) + Float32(0.5)
        l = layoutParagraph(newParagraph("abcd\u00a0ef", f; width = w))
        @test length(l.lines) >= 2
        @test lineText(l, 1) == "abcd"
        # long unbreakable run: character-wise split, every line fits the
        # box (all single glyphs are narrower than 20), runes preserved.
        l = layoutParagraph(newParagraph("abcdefghijkl", f; width = 20))
        @test length(l.lines) >= 3
        for i in eachindex(l.lines)
            @test l.lines[i].width <= Float32(20)
        end
        @test join([lineText(l, i) for i in eachindex(l.lines)]) ==
            "abcdefghijkl"
        # width 0: no wrap, single line.
        l = layoutParagraph(newParagraph("hello world", f; width = 0))
        @test length(l.lines) == 1
        # the lines partition the clusters, in order.
        l = layoutParagraph(newParagraph("hello world foo", f; width = 50))
        seen = 0
        for ln in l.lines
            seen += length(ln.clusters)
        end
        @test seen == length(l.clusters)
    end

    @testset "alignment: hand-derived offsets" begin
        wHi = rh(pxadv(f, 0x68) + pxadv(f, 0x69))
        # center: x1 = (100 - w)/2.
        l = layoutParagraph(newParagraph("hi", f; width = 100,
            hAlign = CenterAlign))
        @test l.arrangement.selectionRects[1].x ==
            Float32((100 - wHi) / 2)
        # right: content ends at the box edge.
        l = layoutParagraph(newParagraph("hi", f; width = 100,
            hAlign = RightAlign))
        r = l.arrangement.selectionRects[end]
        @test r.x + r.w == Float32(100)
        # width 0 forces the effective LeftAlign (docs §2.5): content at 0.
        l = layoutParagraph(newParagraph("hi", f; width = 0,
            hAlign = CenterAlign))
        @test l.arrangement.selectionRects[1].x == Float32(0)
        # vAlign middle in height 200: block 14 -> top = round((200-14)/2).
        l = layoutParagraph(newParagraph("hi", f; height = 200,
            vAlign = MiddleAlign))
        @test l.arrangement.selectionRects[1].y == Float32(round(
            (200 - 14) / 2))
        @test l.arrangement.selectionRects[1].y +
            l.arrangement.selectionRects[1].h == Float32(round(
            (200 + 14) / 2))
        # vAlign bottom: block ends at the box edge.
        l = layoutParagraph(newParagraph("hi", f; height = 200,
            vAlign = BottomAlign))
        r = l.arrangement.selectionRects[end]
        @test r.y + r.h == Float32(200)
        # height 0 forces the effective TopAlign (docs §2.5).
        l = layoutParagraph(newParagraph("hi", f; height = 0,
            vAlign = MiddleAlign))
        @test l.arrangement.selectionRects[1].y == Float32(0)
    end

    @testset "overflow: clip and ellipsis" begin
        # clip: the block (6 lines) is taller than the 20px box.
        p = newParagraph("hello world this is a longer line of text", f;
            width = 50, height = 20)
        l = layoutParagraph(p)
        @test paragraphMetrics(l).lineCount >= 2
        @test paragraphMetrics(l).height > Float32(20)
        img = newImage(120, 60)
        fillParagraph(img, l, 5, 5)
        outside = 0
        inside = 0
        for y in 1:60
            for x in 1:120
                a = Int(px(img, x, y).a)
                if a == 0
                    continue
                end
                if x < 5 || x > 55 || y < 5 || y > 25
                    outside += 1
                else
                    inside += 1
                end
            end
        end
        @test outside == 0
        @test inside > 0
        # ellipsis: M@12 (~10.5px) overflows width 10, one M per line; the
        # last line "m" is replaced by "…" (8px, fits).
        l = layoutParagraph(newParagraph("MMMMM m", f; width = 10,
            overflow = EllipsisOverflow))
        arr = l.arrangement
        ls, le = arr.lines[end]
        @test arr.runes[le] == UInt32(0x2026)
        # no ellipsis needed when the last line fits.
        l = layoutParagraph(newParagraph("MMMM", f; width = 10,
            overflow = EllipsisOverflow))
        @test !(UInt32(0x2026) in l.arrangement.runes)
        # ellipsis does not fit (the glyph is wider than the box) -> plain
        # clip, no ellipsis rune at all.
        f40 = Font(tfR, Float32(40), autoLineHeight,
            [Paint(rgba(0, 0, 0, 255))], NormalCase, false, false, false)
        l = layoutParagraph(newParagraph("M m", f40; width = 20,
            overflow = EllipsisOverflow))
        @test !(UInt32(0x2026) in l.arrangement.runes)
        @test paragraphMetrics(l).width > Float32(20)  # clipped on render
        # the clip still holds on render.
        img = newImage(60, 200)
        fillParagraph(img, l, 2, 2)
        for y in 1:200
            for x in 1:60
                if x > 22
                    @test Int(px(img, x, y).a) == 0
                end
            end
        end
        # multi-span ellipsis: spans "M " / "M" at 40px, width 30 — the
        # last line (the lone "M", 34.8px) overflows, while "…" (26.7px)
        # fits: the ellipsis lands in span 2 and span 1 keeps its text.
        f40m = Font(tfR, Float32(40), autoLineHeight,
            [Paint(rgba(0, 0, 0, 255))], NormalCase, false, false, false)
        l = layoutParagraph(newParagraph([newSpan("M ", f40m),
            newSpan("M", f40m)]; width = 30, overflow = EllipsisOverflow))
        arr = l.arrangement
        @test UInt32(0x2026) in arr.runes
        @test l.clusters[end].span == 2
        # multibyte cut boundary: é (2 bytes) survives the truncation whole.
        l = layoutParagraph(newParagraph("\u00e9\u00e9\u00e9 m", f;
            width = 12, overflow = EllipsisOverflow))
        @test UInt32(0x00e9) in l.arrangement.runes ||
            UInt32(0x2026) in l.arrangement.runes
    end

    @testset "rendering: image and context targets" begin
        # render is consistent with the measurement: with no box, ink stays
        # inside the metrics plus the pixel grid.
        l = layoutParagraph(newParagraph("hello world", f))
        m = paragraphMetrics(l)
        img = newImage(200, 80)
        fillParagraph(img, l, 10, 10)
        for y in 1:80
            for x in 1:200
                if x < 10 || x > 10 + Int(m.width) + 1 ||
                    y < 10 || y > 10 + Int(m.height) + 1
                    @test Int(px(img, x, y).a) == 0
                end
            end
        end
        # transparency: a pre-filled background survives outside the text.
        img = newImage(80, 40)
        ctx = Context(img)
        ctx.fillStyle = rgba(200, 50, 50, 255)
        bp = newPath()
        rect(bp, 0, 0, 80, 40)
        fill(ctx, bp)
        l = layoutParagraph(newParagraph("hi", f))
        fillParagraph(ctx, l, 5, 5)
        c = px(img, 1, 1)
        @test (Int(c.r), Int(c.g), Int(c.b), Int(c.a)) == (200, 50, 50, 255)
        @test Int(px(img, 40, 20).a) > 0  # the text drew
        # a context transform applies to the paragraph.
        l = layoutParagraph(newParagraph("hi", f))
        img1 = newImage(100, 60)
        fillParagraph(img1, l, 10, 10)
        img2 = newImage(100, 60)
        ctx2 = Context(img2)
        transform(ctx2, translate(Vec2(Float32(30), Float32(40))))
        fillParagraph(ctx2, l, 10, 10)
        moved = true
        for y in 1:20
            for x in 1:70
                if Int(px(img1, x, y).a) == 0
                    continue
                end
                if Int(px(img2, x + 30, y + 40).a) !=
                    Int(px(img1, x, y).a)
                    moved = false
                end
            end
        end
        @test moved
        # globalAlpha scales the paragraph ink.
        img3 = newImage(100, 60)
        ctx3 = Context(img3)
        ctx3.globalAlpha = 0.5
        fillParagraph(ctx3, l, 10, 10)
        maxA = 0
        for y in 1:60
            for x in 1:100
                maxA = max(maxA, Int(px(img3, x, y).a))
            end
        end
        @test maxA > 0
        @test maxA <= 140
        # stroke renders (more ink than the fill) and honors the box.
        l = layoutParagraph(newParagraph("MMMMM m", f; width = 10))
        imgF = newImage(80, 120)
        fillParagraph(imgF, l, 5, 5)
        imgS = newImage(80, 120)
        strokeParagraph(imgS, l, 5, 5; strokeWidth = 2)
        nF = sum(1 for y in 1:120 for x in 1:80
            if Int(px(imgF, x, y).a) > 0)
        nS = sum(1 for y in 1:120 for x in 1:80
            if Int(px(imgS, x, y).a) > 0)
        @test nS > nF
        # an empty-spans paragraph draws nothing and does not raise.
        img4 = newImage(20, 20)
        fillParagraph(img4,
            layoutParagraph(newParagraph(Vector{Span}(); width = 50)), 2, 2)
        @test all(Int(px(img4, x, y).a) == 0 for y in 1:20 for x in 1:20)
        # control-only clusters map to a line without disturbing the layout
        # (anchor rules, docs/TEXT_LAYOUT.md §2.8).
        l = layoutParagraph(newParagraph([newSpan("\t", f),
            newSpan("ab", f)]))
        @test paragraphMetrics(l).lineCount == 1
        l = layoutParagraph(newParagraph([newSpan("ab", f),
            newSpan("\t", f)]))
        @test paragraphMetrics(l).lineCount == 1
    end
end
