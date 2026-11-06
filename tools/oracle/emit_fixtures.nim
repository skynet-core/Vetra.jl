# Oracle fixture generator for the Vetra.jl port (T001).
#
# Builds against the pinned upstream treeform/pixie source (upstream.toml)
# and emits canonical pixel buffers plus arithmetic tables used as
# independent expected values by the Julia test suite.
#
# See tools/oracle/README.md for the exact build command, toolchain,
# dependency revisions, and provenance rules.
#
# Usage: emit_fixtures <examples|rotation|primitives|formats|svg|fonts|all>
# Outputs into artifacts/oracle/ (run from the project root; see build.sh).

import pixie, pixie/blends, pixie/internal,
    pixie/fileformats/[bmp, gif, jpeg, qoi, svg],
    pixie/fontformats/opentype
import std/[os, strutils, unicode]

const
  outRoot = "artifacts/oracle"
  upstreamRepo = "https://github.com/treeform/pixie"
  upstreamRev = "30bb510877f02cbf9643e4f904e33d1c90f7910f"
  depsPin =
    "vmath@1b6080f4dc8114d2becaeb5f0944694f7e45794f; " &
    "chroma@08b0d65590221bb964544fd9badf29a146b9091a; " &
    "zippy@cd562ba43ae8904a4d1ba55611b8a521ef4a179e; " &
    "flatty@9c3f14cc287890b742196b4f0f74f0b9faab29cb; " &
    "nimsimd@ba71ac4e2927ba61e6d1bf75d0d124eacc714d1c; " &
    "bumpy@93583f6f8056a6259aaa96c89f4c143ba55bc6f0; " &
    "crunchy@98eb6526982bb8aae8eec6e8781f4539fa19e049"

proc metaHeader(tag, extra: string): string =
  "fixture=" & tag & "\n" &
    "upstream_repo=" & upstreamRepo & "\n" &
    "upstream_revision=" & upstreamRev & "\n" &
    "deps=" & depsPin & "\n" &
    "toolchain=nim-2.2.12 (c backend, default flags, checks on)\n" &
    "os=linux x86_64\n" &
    "build_flags=-d:pixieNoSimd\n" &
    "generator=tools/oracle/emit_fixtures.nim\n" &
    extra

# Checksums are appended by build.sh (sha256sum) over the finished files.

proc writeFixture(name, content, extra = "", header = "") =
  createDir(outRoot)
  writeFile(outRoot & "/" & name, metaHeader(name, extra) & header & "\n" & content)
  echo "emitted " & name

# ---------- image fixtures ----------

proc dump(tag: string, image: Image, example: string, extra = "") =
  createDir(outRoot)
  var bytes: seq[uint8]
  bytes.setLen(image.data.len * 4)
  for i, c in image.data:
    bytes[4 * i + 0] = c.r
    bytes[4 * i + 1] = c.g
    bytes[4 * i + 2] = c.b
    bytes[4 * i + 3] = c.a
  var raw: string
  for b in bytes:
    raw.add(cast[char](b))
  writeFile(outRoot & "/" & tag & ".raw", raw)
  image.writeFile(outRoot & "/" & tag & ".png")
  var meta = metaHeader(
    tag,
    "width=" & $image.width & "\n" &
      "height=" & $image.height & "\n" &
      "pixels=" & $image.data.len & "\n" &
      "layout=row-major, R,G,B,A byte order per pixel\n" &
      "alpha=premultiplied\n" &
      "byte_length=" & $bytes.len & "\n" &
      "example=" & example & "\n" &
      extra
  )
  writeFile(outRoot & "/" & tag & ".meta", meta)
  echo "emitted " & tag & " (" & $image.width & "x" & $image.height & ")"

proc emitExamples() =
  # ---- square: upstream examples/square.nim, construction mirrored ----
  let image1 = newImage(200, 200)
  image1.fill(rgba(255, 255, 255, 255))
  let ctx1 = newContext(image1)
  ctx1.fillStyle = rgba(255, 0, 0, 255)
  let
    pos1 = vec2(50, 50)
    wh1 = vec2(100, 100)
  ctx1.fillRect(rect(pos1, wh1))
  dump("square", image1, "examples/square.nim")

  # ---- line: upstream examples/line.nim, construction mirrored ----
  let image2 = newImage(200, 200)
  image2.fill(rgba(255, 255, 255, 255))
  let ctx2 = newContext(image2)
  ctx2.strokeStyle = "#FF5C00"
  ctx2.lineWidth = 10
  let
    start2 = vec2(25, 25)
    stop2 = vec2(175, 175)
  ctx2.strokeSegment(segment(start2, stop2))
  dump("line", image2, "examples/line.nim")

  # ---- heart: upstream examples/heart.nim, construction mirrored ----
  let image3 = newImage(200, 200)
  image3.fill(rgba(255, 255, 255, 255))
  image3.fillPath(
    """
      M 20 60
      A 40 40 90 0 1 100 60
      A 40 40 90 0 1 180 60
      Q 180 120 100 180
      Q 20 120 20 60
      z
    """,
    parseHtmlColor("#FC427B").rgba
  )
  dump("heart", image3, "examples/heart.nim")

 # ---------- T011 regression: context fill/stroke under translate + rotate ----------
 # The exact quick-start case: the port's `leftRectArea` sign bug (upstream
 # vmath `fract` is abs-based) and the uint8 wrap of `*(ColorRGBX, float32)`
 # only surface here, where the rotated trapezoid coverage leaves a negative
 # pen before truncation.

proc emitContextRotation() =
  let image = newImage(320, 240)
  image.fill(rgba(245, 244, 250, 255))
  var ctx = newContext(image)
  ctx.fillStyle = "#FF5C00"
  ctx.fillRect(12, 12, 90, 60)
  ctx.translate(10, 40)
  ctx.rotate(0.3)
  ctx.strokeStyle = rgba(0, 128, 255, 255)
  ctx.lineWidth = 4
  ctx.strokeRect(0, 0, 60, 60)
  dump("ctx_rot", image, "T011 quick-start regression: fill + rotated stroke")

# ---------- arithmetic tables ----------

const validPremul = [
  rgbx(0, 0, 0, 0),
  rgbx(1, 1, 1, 1),
  rgbx(5, 3, 2, 10),
  rgbx(255, 255, 255, 255),
  rgbx(0, 0, 0, 255),
  rgbx(255, 255, 255, 254),
  rgbx(200, 100, 50, 255),
  rgbx(100, 50, 25, 100),
  rgbx(64, 128, 64, 128),
  rgbx(128, 0, 128, 128),
  rgbx(255, 128, 64, 192),
]

func rgb(c: ColorRGBX): string =
  $c.r & "," & $c.g & "," & $c.b & "," & $c.a

proc emitPrimitives() =
  # -- premul->straight: chroma rgba() path and pixie internal table path --
  var body = ""
  for a in 0 .. 255:
    for c in 0 .. 255:
      if c > a:
        # Outside the premultiplied domain (channels may exceed alpha).
        body &= $a & "," & $c & ",invalid,invalid\n"
      else:
        let premul = rgbx(c.uint8, 0, 0, a.uint8)
        let chromaPath = premul.rgba().r
        var seq = @[premul]
        toStraightAlpha(seq)
        body &= $a & "," & $c & "," & $chromaPath & "," & $seq[0].r & "\n"
  writeFixture(
    "straight_alpha.tsv",
    body,
    "source=chroma rgba() (pixie.nim autoStraightAlpha) and pixie internal.nim toStraightAlpha\n",
    "backdrop_a,channel,chroma_rgba_path,pixie_toStraightAlpha_path\n"
  )

  # -- straight->premul: chroma rgbx() and pixie toPremultipliedAlpha agree --
  body = ""
  for a in 0 .. 255:
    for c in 0 .. 255:
      let viaChroma = rgba(c.uint8, 0, 0, a.uint8).rgbx().r
      var seq = @[rgbx(c.uint8, 0, 0, a.uint8)]
      toPremultipliedAlpha(seq)
      if viaChroma != seq[0].r:
        raise newException(
          Exception, "premul mismatch at a=" & $a & " c=" & $c
        )
      body &= $a & "," & $c & "," & $seq[0].r & "\n"
  writeFixture(
    "premultiplied_alpha.tsv",
    body,
    "source=chroma rgbx() and pixie internal.nim toPremultipliedAlpha (verified identical)\n",
    "straight_c,channel_a,result\n"
  )

  # -- mix(a, b, t) --
  body = ""
  for (a, b) in
    [
      (rgbx(0, 0, 0, 0), rgbx(255, 255, 255, 255)),
      (rgbx(200, 100, 50, 255), rgbx(50, 200, 100, 128)),
      (rgbx(1, 2, 3, 4), rgbx(254, 253, 252, 251)),
    ]:
    for i in 0 .. 255:
      let t = (i.float32 / 255).float32
      body &= rgb(a) & "," & rgb(b) & "," & $t & "," & rgb(mix(a, b, t)) & "\n"
  writeFixture(
    "mix.tsv",
    body,
    "source=pixie common.nim mix\n",
    "backdrop,source,t,result\n"
  )

  # -- color * opacity (float32) --
  body = ""
  for a in validPremul:
    for i in 0 .. 255:
      let opacity = (i.float32 / 255).float32
      body &= rgb(a) & "," & $opacity & "," & rgb(a * opacity) & "\n"
  writeFixture(
    "color_opacity.tsv",
    body,
    "source=pixie common.nim `*`(ColorRGBX, float32)\n",
    "color,opacity,result\n"
  )

  # -- rgbx * coverage (uint8) --
  body = ""
  for c in [0, 1, 64, 127, 128, 200, 254, 255]:
    let color = rgbx(uint8(c), uint8(255 - c), uint8(c div 2), 255)
    for o in 0 .. 255:
      body &= rgb(color) & "," & $o & "," & rgb(color * o.uint8) & "\n"
  writeFixture(
    "rgbx_coverage.tsv",
    body,
    "source=pixie common.nim `*`(ColorRGBX, uint8)\n",
    "color,coverage,result\n"
  )

  # -- blendAlpha --
  body = ""
  for ba in 0 .. 255:
    for sa in 0 .. 255:
      body &= $ba & "," & $sa & "," & $blendAlpha(ba.uint8, sa.uint8) & "\n"
  writeFixture(
    "blend_alpha.tsv",
    body,
    "source=pixie blends.nim blendAlpha\n",
    "backdrop_alpha,source_alpha,result\n"
  )

  # -- every blend mode over a curated valid-premultiplied pair grid --
  let modes: array[0 .. 19, (string, BlendMode)] = [
    ("normal", NormalBlend),
    ("darken", DarkenBlend),
    ("multiply", MultiplyBlend),
    ("color_burn", ColorBurnBlend),
    ("lighten", LightenBlend),
    ("screen", ScreenBlend),
    ("color_dodge", ColorDodgeBlend),
    ("overlay", OverlayBlend),
    ("soft_light", SoftLightBlend),
    ("hard_light", HardLightBlend),
    ("difference", DifferenceBlend),
    ("exclusion", ExclusionBlend),
    ("hue", HueBlend),
    ("saturation", SaturationBlend),
    ("color", ColorBlend),
    ("luminosity", LuminosityBlend),
    ("mask", MaskBlend),
    ("overwrite", OverwriteBlend),
    ("subtract_mask", SubtractMaskBlend),
    ("exclude_mask", ExcludeMaskBlend),
  ]
  for (name, mode) in modes:
    var bodyMode = ""
    for b in validPremul:
      for s in validPremul:
        bodyMode &= rgb(b) & "," & rgb(s) & "," & rgb(blender(mode)(b, s)) & "\n"
    writeFixture(
      "blend_" & name & ".tsv",
      bodyMode,
      "source=pixie blends.nim (" & name & ")\n",
      "backdrop,source,result\n"
    )

  # -- gaussian kernel weights --
  body = ""
  for radius in 1 .. 16:
    var line = $radius
    for w in gaussianKernel(radius):
      line &= "," & $w
    body &= line & "\n"
  writeFixture(
    "gaussian_kernel.tsv",
    body,
    "source=pixie internal.nim gaussianKernel\n",
    "radius,weights...\n"
  )

  # -- snapToPixels --
  body = ""
  for x in [5.0.float32, 5.5, 10, 10.5, 19.9]:
    for y in [0.0.float32, 5.5, 9.1]:
      for w in [1.0.float32, 10, 10.5]:
        for h in [1.0.float32, 10, 10.5]:
          let snapped = rect(x, y, w, h).snapToPixels()
          body &=
            $x & "," & $y & "," & $w & "," & $h & "," &
            $snapped.x & "," & $snapped.y & "," & $snapped.w & "," & $snapped.h & "\n"
  writeFixture(
    "snap_to_pixels.tsv",
    body,
    "source=pixie common.nim snapToPixels\n",
    "x,y,w,h,snap_x,snap_y,snap_w,snap_h\n"
  )

  # -- draw: fast (translated) and smooth (scaled/blended) path fixtures --
  # Valid premultiplied channel (r<=a) so upstream debug-mode range checks pass.
  let dst1 = newImage(8, 6)
  dst1.fill(rgbx(255, 255, 255, 255))
  let src1 = newImage(4, 3)
  src1.fill(rgbx(100, 50, 25, 128))
  dst1.draw(src1, translate(vec2(2, 1)), NormalBlend)
  dump("draw_translate", dst1, "synthetic: 4x3 (100,50,25,128) at (2,1) over white 8x6")

  let dst2 = newImage(16, 12)
  dst2.fill(rgbx(255, 255, 255, 255))
  let src2 = newImage(2, 2)
  src2.fill(rgbx(255, 0, 0, 255))
  dst2.draw(src2, translate(vec2(6, 8)) * scale(vec2(2, 2)), NormalBlend)
  dump(
    "draw_scale2",
    dst2,
    "synthetic: 2x2 red scaled 2x translated to (6,8) over white 16x12 (smooth path)"
  )

proc emitFormats() =
  # Decode the upstream test fixtures with the upstream codecs; the dumped
  # raw buffers are the pixel truth for the Julia ports (T008 formats).
  let fixtures = ".reference/upstream/tests/fileformats"

  for name in ["bmp/knight.32.master.bmp", "bmp/knight.24.master.bmp",
               "bmp/rgb.24.master.bmp", "bmp/test4x2.bmp", "bmp/test16x16.bmp"]:
    let
      path = fixtures / name
      tag = "bmp_" & path.split("/")[^1].replace(".", "_")
    dump(tag, decodeBmp(readFile(path)), "tests/" & path)

  for name in ["qoi/testcard.qoi", "qoi/testcard_rgba.qoi"]:
    let
      path = fixtures / name
      tag = "qoi_" & name.split("/")[^1].replace(".", "_")
    dump(tag, decodeQoi(readFile(path)).convertToImage(), "tests/" & path)

  for name in ["gif/3x5.gif", "gif/audrey.gif", "gif/sunflower.gif",
               "gif/newtons_cradle.gif"]:
    let
      path = fixtures / name
      tag = "gif_" & name.split("/")[^1].replace(".", "_")
    let gif = decodeGif(readFile(path))
    echo "  ", name, ": frames=", $gif.frames.len, " duration=", $gif.duration
    dump(tag, newImage(gif), "tests/" & path)

  for name in ["jpeg/masters/mandrill.jpg",
               "jpeg/masters/grayscale_test.jpg",
               "jpeg/masters/progressive.jpg",
               "jpeg/masters/exif_overrun.jpg"]:
    let
      path = fixtures / name
      tag = "jpeg_" & name.split("/")[^1].replace(".", "_")
    dump(tag, decodeJpeg(readFile(path)), "tests/" & path)

proc emitSvg() =
  # Render the upstream SVG test fixtures with upstream's parser/renderer;
  # the dumped raw buffers are the pixel truth for the Julia port (T008).
  # accessibility-outline is rendered at explicit 512x512, as upstream's
  # test_svg.nim does; the others use the viewBox defaults.
  let dir = ".reference/upstream/tests/fileformats/svg"
  for name in ["line01", "circle01", "ellipse01", "rect01", "polygon01",
               "polyline01", "triangle01", "quad01", "scale", "dashes",
               "miterlimit", "Ghostscript_Tiger", "dragon2"]:
    let
      path = dir / (name & ".svg")
      svg = parseSvg(readFile(path))
    echo "  ", name, ": ", $svg.width, "x", $svg.height
    dump("svg_" & name, newImage(svg), "tests/" & path)
  let
    path = dir / "accessibility-outline.svg"
    svg = parseSvg(readFile(path), 512, 512)
  echo "  accessibility-outline: ", $svg.width, "x", $svg.height
  dump("svg_accessibility_outline", newImage(svg), "tests/" & path)

proc emitFonts() =
  # T009: font metrics and text layout oracle fixtures, run against the
  # pinned upstream fonts (glyf/TTF subset per D015). Floats are dumped as
  # IEEE-754 hex bit patterns so the Julia suite can compare bit-exactly.
  const hexDigits = "0123456789abcdef"
  func hex32(x: float32): string =
    let v = cast[uint32](x)
    for i in countdown(7, 0):
      result.add(hexDigits[(v shr (i * 4)) and 15])

  # SHA-256 of the pinned reference fonts, recorded from the .reference
  # checkout (upstream rev above); the test suite verifies the on-disk
  # files against these.
  const
    robotoSha =
      "79e851404657dac2106b3d22ad256d47824a9a5765458edb72c9102a45816d95"
    ubuntuSha =
      "3128df86a31805618436d0ae5651ba4285d0c9de0a39057d025f64ee33bceb64"

  let
    roboto = ".reference/upstream/tests/fonts/Roboto-Regular_1.ttf"
    ubuntu = ".reference/upstream/tests/fonts/Ubuntu-Regular_1.ttf"
    robotoLicense = "Apache License 2.0"
    ubuntuLicense = "Ubuntu Font License 1.0"

  proc fontMeta(path, sha, license: string): string =
    "font=" & path & "\n" &
      "font_sha256=" & sha & "\n" &
      "font_license=" & license & "\n"

  # Runes used by the image scenarios, deduplicated, in first-seen order.
  let probeText =
    "Word fill stroke asdf A cow A bit of text HERE Line height First " &
    "Second Wrapping text to new line Long words: " &
    "Supercalifragilisticexpialidocious Antidisestablishmentarianism " &
    "Hello world Centered Right Vmid Vbot Te Wo Ve Av Pf Yo Fi Lt Ra Wh"

  var probeRunes: seq[Rune]
  for r in probeText:
    let rr = r.Rune
    if rr notin probeRunes:
      probeRunes.add(rr)

  # -- per-rune glyph ids and advances (font units) --
  for (path, sha, license, tag) in
    [(roboto, robotoSha, robotoLicense, "roboto"),
     (ubuntu, ubuntuSha, ubuntuLicense, "ubuntu")]:
    let
      ot = parseOpenType(readFile(path))
      n = ot.head.unitsPerEm
    var body = ""
    for r in probeRunes:
      if r in ot.cmap.runeToGlyphId:
        body &=
          $r.int & "," & $ot.cmap.runeToGlyphId[r].int & "," &
          hex32(ot.getAdvance(r)) & "\n"
    writeFixture(
      "font_" & tag & "_metrics.tsv",
      body,
      "units=font units (unitsPerEm=" & $n & "); advance=IEEE754 hex\n" &
        fontMeta(path, sha, license),
      "rune_cp,glyph_id,advance\n"
    )

  # -- kerning adjustments (typeface level, font units) --
  var pairs: seq[(Rune, Rune)]
  proc addPair(a, b: char) =
    let p = (a.Rune, b.Rune)
    if p notin pairs:
      pairs.add(p)
  for i in 0 ..< probeText.len - 1:
    addPair(probeText[i], probeText[i + 1])
  # Fixed probes (incl. pairs the layout does not exercise and a missing
  # rune -- the emoji has no glyph in either fixture font).
  for (a, b) in [('T', 'e'), ('W', 'o'), ('V', 'e'), ('A', 'V'),
                 ('P', 'f'), ('Y', 'o'), ('f', 'i'), ('L', 'T'),
                 ('r', 'a'), ('W', 'h'), (cast[char](0xFFFD), 'e')]:
    addPair(a, b)

  for (path, sha, license, tag) in
    [(roboto, robotoSha, robotoLicense, "roboto"),
     (ubuntu, ubuntuSha, ubuntuLicense, "ubuntu")]:
    let tf = readFont(path).typeface
    var body = ""
    for (a, b) in pairs:
      body &= $a.int & "," & $b.int & "," &
        hex32(tf.getKerningAdjustment(a, b)) & "\n"
    writeFixture(
      "font_" & tag & "_kerning.tsv",
      body,
      "units=font units; GPOS preferred over kern table when present\n" &
        fontMeta(path, sha, license),
      "left_cp,right_cp,kerning\n"
    )

  # -- typeset positions and selection rects --
  let scenarios: seq[(string, string, float32, string, float32, float32,
                      HorizontalAlignment, VerticalAlignment, bool,
                      float32)] = @[
    # id, font path, size, text, bounds x/y, hAlign, vAlign, wrap, lineHeight
    ("basic1", roboto, 72, "asdf", 0, 0, LeftAlign, TopAlign, true, -1),
    ("basic2", roboto, 72, "A cow", 0, 0, LeftAlign, TopAlign, true, -1),
    ("basic3", roboto, 24, "A bit of text HERE", 0, 0, LeftAlign, TopAlign,
      true, -1),
    ("basic4", roboto, 24, "Line height", 0, 0, LeftAlign, TopAlign, true,
      100),
    ("basic7", roboto, 24, "First line\nSecond line", 0, 0, LeftAlign,
      TopAlign, true, -1),
    ("basic8", roboto, 24, "Wrapping text to new line", 200, 0, LeftAlign,
      TopAlign, true, -1),
    ("basic8b", roboto, 24, "Long words: " &
      "Supercalifragilisticexpialidocious\n" &
      "Antidisestablishmentarianism", 100, 0, LeftAlign, TopAlign, true, -1),
    ("word", roboto, 24, "Word", 0, 0, LeftAlign, TopAlign, true, -1),
    ("word_lf", roboto, 24, "Word\n", 0, 0, LeftAlign, TopAlign, true, -1),
    ("ctx_fill1", roboto, 50, "Hello world", 0, 0, LeftAlign, TopAlign, true,
      -1),
    ("synth_center", roboto, 24, "Centered text", 200, 0, CenterAlign,
      TopAlign, true, -1),
    ("synth_right", roboto, 24, "Right aligned", 200, 0, RightAlign,
      TopAlign, true, -1),
    ("synth_vmid", roboto, 24, "Vmid", 0, 100, LeftAlign, MiddleAlign, true,
      -1),
    ("synth_vbot", roboto, 24, "Vbot", 0, 100, LeftAlign, BottomAlign, true,
      -1),
    ("synth_nowrap", roboto, 24, "No wrap here", 200, 0, LeftAlign, TopAlign,
      false, -1),
    ("ubuntu1", ubuntu, 24, "Word", 0, 0, LeftAlign, TopAlign, true, -1),
    ("ubuntu2", ubuntu, 24, "Wrapping text to new line", 200, 0, LeftAlign,
      TopAlign, true, -1),
  ]

  var body = ""
  var boundsBody = ""
  for (id, path, size, text, bx, by, ha, va, wrap, lh) in scenarios:
    var font = readFont(path)
    font.size = size.float32
    if lh > 0:
      font.lineHeight = lh
    let arr = font.typeset(text, vec2(bx.float32, by.float32), ha, va, wrap)
    for i in 0 ..< arr.runes.len:
      let
        p = arr.positions[i]
        r = arr.selectionRects[i]
      body &=
        id & "," & $arr.runes[i].int & "," & hex32(p.x) & "," &
        hex32(p.y) & "," & hex32(r.x) & "," & hex32(r.y) & "," &
        hex32(r.w) & "," & hex32(r.h) & "\n"
    let b = arr.layoutBounds()
    boundsBody &= id & "," & hex32(b.x) & "," & hex32(b.y) & "\n"
  writeFixture(
    "font_layouts.tsv",
    body,
    "floats=IEEE754 hex; scenario table: T009 layout fixture matrix\n",
    "scenario,rune_cp,pos_x,pos_y,rect_x,rect_y,rect_w,rect_h\n"
  )
  writeFixture(
    "font_layout_bounds.tsv",
    boundsBody,
    "floats=IEEE754 hex\n",
    "scenario,width,height\n"
  )

  # -- rendered images (upstream test_fonts.nim blocks, mirrored) --
  proc render(tag, id: string, size, lh: float32, text: string,
              bx, by: float32, ha = LeftAlign, va = TopAlign,
              underline = false, strike = false, example = "") =
    var font = readFont(roboto)
    font.size = size
    if lh > 0:
      font.lineHeight = lh
    font.underline = underline
    font.strikethrough = strike
    let image = newImage(200, 100)
    image.fill(rgba(255, 255, 255, 255))
    image.fillText(font, text, bounds = vec2(bx, by), hAlign = ha,
      vAlign = va)
    dump(tag, image, "tests/test_fonts.nim " & id & " block" & example,
      fontMeta(roboto, robotoSha, robotoLicense))

  render("font_image_fill", "image_fill", 64, -1, "fill", 0, 0)
  render("font_basic1", "basic1", 72, -1, "asdf", 0, 0)
  render("font_basic2", "basic2", 72, -1, "A cow", 0, 0)
  render("font_basic3", "basic3", 24, -1, "A bit of text HERE", 0, 0)
  render("font_basic4", "basic4", 24, 100, "Line height", 0, 0)
  render("font_basic8", "basic8", 24, -1, "Wrapping text to new line", 200,
    0)
  render("font_basic8b", "basic8b", 24, -1, "Long words: " &
    "Supercalifragilisticexpialidocious\n" &
    "Antidisestablishmentarianism", 100, 0)
  render("font_underline1", "underline1", 24, -1, "Wrapping text to new " &
    "line", 200, 0, underline = true)
  render("font_strikethrough1", "strikethrough1", 24, -1,
    "Wrapping text to new line", 200, 0, strike = true)

  # basic7: two fillText calls, the second translated by defaultLineHeight.
  block:
    var font = readFont(roboto)
    font.size = 24
    let image = newImage(200, 100)
    image.fill(rgba(255, 255, 255, 255))
    image.fillText(font, "First line")
    image.fillText(font, "Second line",
      transform = translate(vec2(0, font.defaultLineHeight)))
    dump("font_basic7", image, "tests/test_fonts.nim basic7 block",
      fontMeta(roboto, robotoSha, robotoLicense))

  # image_stroke: strokeText with default stroke settings.
  block:
    var font = readFont(roboto)
    font.size = 64
    let image = newImage(200, 100)
    image.fill(rgba(255, 255, 255, 255))
    image.strokeText(font, "stroke")
    dump("font_image_stroke", image, "tests/test_fonts.nim image_stroke " &
      "block", fontMeta(roboto, robotoSha, robotoLicense))

  # ctx.fillText / ctx.strokeText (tests/test_contexts.nim blocks):
  # transparent 300x150, Roboto size 50, save/restore round trip keeps 50.
  block:
    let ctx = newContext(newImage(300, 150))
    ctx.font = roboto
    ctx.fontSize = 50
    ctx.save()
    ctx.fontSize = 30
    ctx.restore()
    ctx.fillText("Hello world", 50, 90)
    dump("font_ctx_fill1", ctx.image,
      "tests/test_contexts.nim fillText_1 block",
      fontMeta(roboto, robotoSha, robotoLicense))

  block:
    let ctx = newContext(newImage(300, 150))
    ctx.font = roboto
    ctx.fontSize = 50
    ctx.strokeText("Hello world", 50, 90)
    dump("font_ctx_stroke1", ctx.image,
      "tests/test_contexts.nim strokeText_1 block",
      fontMeta(roboto, robotoSha, robotoLicense))

  # Ubuntu end-to-end render (legacy font; GPOS present, kern present).
  block:
    var font = readFont(ubuntu)
    font.size = 24
    let image = newImage(200, 100)
    image.fill(rgba(255, 255, 255, 255))
    image.fillText(font, "Word")
    dump("font_ubuntu1", image, "synthetic: Ubuntu 24 'Word' 200x100 white",
      fontMeta(ubuntu, ubuntuSha, ubuntuLicense))

let mode = if paramCount() > 0: paramStr(1) else: "all"
case mode
of "examples":
  emitExamples()
of "rotation":
  emitContextRotation()
of "primitives":
  emitPrimitives()
of "formats":
  emitFormats()
of "svg":
  emitSvg()
of "fonts":
  emitFonts()
of "all":
  emitExamples()
  emitContextRotation()
  emitPrimitives()
  emitFormats()
  emitSvg()
  emitFonts()
else:
  echo "usage: emit_fixtures <examples|rotation|primitives|formats|svg|fonts|all>"
  quit(1)
