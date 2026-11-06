# T011 benchmark reference (pinned upstream Nim side).
#
# Workloads are defined identically in benchmark/run_benchmarks.jl (the
# Julia port) -- keep the two in lockstep if either changes.
#
# Build with the pinned toolchain and the oracle paths, in RELEASE mode
# (scalar parity via -d:pixieNoSimd; checks stay on in release):
#   export PATH=/tmp/opencode/conda-nim/nim/bin:$PATH
#   nim c -d:release -d:pixieNoSimd \
#     --path:.reference/upstream/src --path:.reference/pkgs/vmath/src \
#     --path:.reference/pkgs/chroma/src --path:.reference/pkgs/zippy/src \
#     --path:.reference/pkgs/flatty/src --path:.reference/pkgs/nimsimd/src \
#     --path:.reference/pkgs/bumpy/src --path:.reference/pkgs/crunchy/src \
#     -o:artifacts/benchmarks/pixie_ref benchmark/bench_reference.nim
#   artifacts/benchmarks/pixie_ref
#
# Per workload: first (cold) call, 3 warm-up iterations (discarded), 21
# steady-state iterations (mean/min wall time). Nim has no per-call
# allocation counter here, so alloc columns are "n/a".

import pixie, pixie/fileformats/png, pixie/fonts, std/[algorithm, os, times, monotimes]

const N_STEADY = 21
const N_WARMUP = 3

type BenchResult = object
  firstMs, meanMs, minMs, medianMs: float

var results: seq[tuple[name: string, r: BenchResult]]

template bench*(name: string, f: untyped) =
  let t0 = getMonoTime()
  f() # first (cold) call
  let firstMs = inNanoseconds(getMonoTime() - t0).float / 1e6
  for _ in 0 ..< N_WARMUP:
    f()
  var samples: seq[float]
  samples.setLen(N_STEADY)
  for k in 0 ..< N_STEADY:
    let u0 = getMonoTime()
    f()
    samples[k] = inNanoseconds(getMonoTime() - u0).float / 1e6
  let total = samples.sum()
  let mn = samples.min()
  var sorted = samples
  sorted.sort()
  let median = sorted[N_STEADY div 2]
  results.add((name, BenchResult(
    firstMs: firstMs, meanMs: total / N_STEADY, minMs: mn,
    medianMs: median)))
  echo name, "\tfirst_call_ms=", round(firstMs, 3),
      "\tsteady_mean_ms=", round(total / N_STEADY, 3),
      "\tsteady_min_ms=", round(mn, 3),
      "\tsteady_median_ms=", round(median, 3),
      "\talloc_bytes=n/a"

const W = 256

proc freshCanvas(): Context =
  let img = newImage(W, W)
  img.fill(color(0, 0, 0, 1))
  result = newContext(img)
  result.fillStyle = color(1, 0, 0, 1)

proc fillRectsWork() =
  var ctx = freshCanvas()
  for i in 0 ..< 1000:
    ctx.fillRect(rect(float32((37 * i) mod 246), float32((71 * i) mod 246),
        10.0, 10.0))

proc strokeLinesWork() =
  var ctx = freshCanvas()
  ctx.strokeStyle = color(1, 1, 0, 1)
  ctx.lineWidth = 2
  for i in 0 ..< 1000:
    ctx.strokeSegment(float32((7 * i) mod 249), 0.0,
        float32((13 * i) mod 249), 255.0)

proc blurWork() =
  var img = newImage(128, 128)
  img.fill(color(1, 1, 1, 1))
  img.blur(3)

proc shadowWork() =
  var img = newImage(128, 128)
  img.fill(color(1, 0, 0, 1))
  discard img.shadow(vec2(4, 4), 2, 4, color(0, 0, 0, 128 / 255))

proc drawWork() =
  var dst = newImage(W, W)
  dst.fill(color(1, 1, 1, 1))
  var src = newImage(128, 128)
  src.fill(color(1, 0, 0, 1))
  for i in 0 ..< 10:
    dst.draw(src, translate(vec2(float32((13 * i) mod 128),
        float32((29 * i) mod 128))))

proc gradientImage(): Image =
  result = newImage(W, W)
  for y in 0 ..< W:
    for x in 0 ..< W:
      result[x, y] = color(float32((x + y) mod 256), 0.0,
          float32((x - y + 256) mod 256), 1.0)

proc pngEncodeWork() =
  let img = gradientImage()
  for _ in 0 ..< 10:
    discard encodePng(img)

proc pngDecodeWork() =
  let data = readFile("test/reference/font_basic1.png")
  for _ in 0 ..< 10:
    let png = decodePng(data)
    discard newImage(png)

const TEXT = "The quick brown fox jumps over the lazy dog 0123456789"

proc textWork() =
  let tf = readTypeface(
    joinPath(".reference", "upstream", "tests", "fonts",
    "Roboto-Regular_1.ttf"))
  var font = newFont(tf)
  font.size = 24
  var ctx = newContext(16, 16)
  ctx.font = joinPath(".reference", "upstream", "tests", "fonts",
      "Roboto-Regular_1.ttf")
  ctx.fontSize = 24
  for _ in 0 ..< 100:
    discard layoutBounds(font, TEXT)
  for _ in 0 ..< 20:
    discard ctx.measureText(TEXT)

echo "pixie (nim reference) benchmarks"
echo "workloads: W=256 canvas, 1000 fills/strokes, blur r3 @128, " &
    "shadow(4,4,s2,b4) @128, 10 draws @128src, png 10x, text x100+20"

bench("fill_rects_1000", fillRectsWork)
bench("stroke_lines_1000", strokeLinesWork)
bench("blur_128_r3", blurWork)
bench("shadow_128", shadowWork)
bench("draw_10", drawWork)
bench("png_encode_256_x10", pngEncodeWork)
bench("png_decode_basic1_x10", pngDecodeWork)
bench("text_parse_layout_x100_measure_x20", textWork)

let outfile = joinPath("benchmark", "results",
    "nim_" & $now().format("yyyy-MM-dd") & ".tsv")
createDir("benchmark/results")
var f: File
discard f.open(outfile, fmWrite)
f.writeLine("workload\tfirst_call_ms\tsteady_mean_ms\tsteady_min_ms\t" &
    "steady_median_ms\talloc_bytes_total")
for (name, r) in results:
  f.writeLine(name & "\t" & $round(r.firstMs, 3) & "\t" &
      $round(r.meanMs, 3) & "\t" & $round(r.minMs, 3) &
      "\t" & $round(r.medianMs, 3) & "\tn/a")
f.close()
echo "wrote ", outfile
