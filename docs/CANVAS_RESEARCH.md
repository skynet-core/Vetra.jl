# Canvas research and compatibility evidence

Status: R000 source review complete, **not backend acceptance**. Coordinator checked
the sources below on 2026-11-10. Limited Linux artifact inspection is labeled
separately below; complete implementation probes belong to R040/R064;
the architecture is [Canvas design](CANVAS_DESIGN.md), with ownership and gates
in [the roadmap](../tasks/CANVAS_ROADMAP.md).

## Vulkan: reviewed findings

The initial report was corrected after coordinator review. The revised source
findings below are accepted as R000 planning evidence, with the qualifications
recorded here. Compiler/package/platform decisions remain gated by R040 execution;
the revised report's proposed guarantees are not accepted runtime conclusions.

| Finding | Source evidence | Consequence |
| --- | --- | --- |
| Vulkan.jl 0.7.0 declares Julia 1.10 and VulkanCore 2 compatibility | [Pinned Project.toml](https://github.com/JuliaGPU/Vulkan.jl/blob/4f012468127314e99f079b5e8a5477b6db93c59d/Project.toml) | The wrapper alone need not raise Vetra core's Julia minimum; the complete shader stack still needs resolution/tests |
| Loader selection defaults to `:System`; `:Loader` selects the loader JLL through a preference and requires restart | [Pinned driver.jl](https://github.com/JuliaGPU/Vulkan.jl/blob/4f012468127314e99f079b5e8a5477b6db93c59d/src/driver.jl) | Probe the actual selected loader; do not describe the artifact loader as the default |
| Vulkan's `PRECOMPILE_DEVICE_FUNCTIONS` defaults to `"auto"`, attempts a device workload and catches failure; `"false"` skips it | [Pinned precompile.jl](https://github.com/JuliaGPU/Vulkan.jl/blob/4f012468127314e99f079b5e8a5477b6db93c59d/src/precompile.jl) | CPU-only loading and device-free initialization are distinct requirements; test the installation/preference/load path explicitly |
| That precompile workload asks for loader ≥1.1, a Vulkan 1.3 device and graphics+compute queue, and preserves resources through a queue wait | [Pinned workload](https://github.com/JuliaGPU/Vulkan.jl/blob/4f012468127314e99f079b5e8a5477b6db93c59d/src/precompile_workload.jl) | These are upstream precompile choices, not automatically Vetra's runtime minimum or resource-lifetime solution |
| SPIRV.jl exists and describes an experimental Julia→SPIR-V compiler that does not rely on LLVM | [Pinned README](https://github.com/serenity4/SPIRV.jl/blob/218b33b21e5b23d7c3c34bb07f6c114723a5e193/README.md) | A registry-only absence search does not establish absence of Julia shader tooling |
| The inspected SPIRV.jl project is 0.6.11, declares Julia 1.11 and Vulkan `0.6`, with `SPIRVVulkanExt` | [Pinned Project.toml](https://github.com/serenity4/SPIRV.jl/blob/218b33b21e5b23d7c3c34bb07f6c114723a5e193/Project.toml) | Vulkan 0.7 is outside that declared range. Probe a compatible pinned stack or review a compatibility fix; never silently widen compat |
| SPIRV.jl exports vertex, fragment and compute shader macros; its Vulkan extension maps those execution models to shader stages and constructs shader modules | [Exports](https://github.com/serenity4/SPIRV.jl/blob/218b33b21e5b23d7c3c34bb07f6c114723a5e193/src/SPIRV.jl), [shader extension](https://github.com/serenity4/SPIRV.jl/blob/218b33b21e5b23d7c3c34bb07f6c114723a5e193/ext/shader.jl) | Investigate graphics as well as compute; macro/API presence is not successful pipeline execution |
| Upstream's execution harness creates a Vulkan compute pipeline, requests BDA/variable pointers, Vulkan memory model, Float64/Int64 and several Vulkan 1.3 features, and leaves validation layers disabled with a Bool-related crash comment | [Execution harness](https://github.com/serenity4/SPIRV.jl/blob/218b33b21e5b23d7c3c34bb07f6c114723a5e193/test/execution/execute.jl) | Distinguish this test harness's feature set from Vetra's actual minimum; reproduce/investigate the validation concern rather than inherit disabled validation |
| Upstream basic tests include exact-value assertions but warn that some expressions may constant-fold before SPIR-V generation | [Basic tests](https://github.com/serenity4/SPIRV.jl/blob/218b33b21e5b23d7c3c34bb07f6c114723a5e193/test/execution/basic_tests.jl) | Vetra's probe must consume runtime buffer inputs so real device computation is demonstrated |
| The inspected CI definition targets Ubuntu with a Lavapipe action and Julia 1.11/stable/prerelease, plus allowed-failure nightly | [CI definition](https://github.com/serenity4/SPIRV.jl/blob/218b33b21e5b23d7c3c34bb07f6c114723a5e193/.github/workflows/Test.yml) | This is intended test coverage, not a verified successful run or Windows/macOS/hardware evidence |
| LLVM/SPIR-V Translator explicitly produces/consumes the OpenCL `Kernel` flavour | [Pinned translator README](https://github.com/KhronosGroup/SPIRV-LLVM-Translator/blob/20d69b2db2ed263d03a20fe534055e58a2353d1d/README.md) | This alone is not a Vulkan compute-shader route |
| Vulkan has its own SPIR-V capability/environment rules; compute shaders use `GLCompute` with shader semantics | [Khronos Vulkan SPIR-V environment](https://docs.vulkan.org/spec/latest/appendices/spirvenv.html) | Validate against the selected Vulkan target environment, not just generic SPIR-V or OpenCL rules |
| Runtime Vulkan validation checks API valid usage using runtime state | [Khronos validation overview](https://docs.vulkan.org/guide/latest/validation_overview.html) | `spirv-val` cannot replace descriptor, synchronization, object-lifetime or API validation |
| Timestamp measurements are written into timestamp query pools with `vkCmdWriteTimestamp` / its successor | [Khronos timestamp reference](https://docs.vulkan.org/refpages/latest/refpages/source/vkCmdWriteTimestamp.html) | Use timestamp writes, supported queue timestamp bits, period, availability and wrap handling; not begin/end timestamp queries |

### Shader decision remains open

Keep the Julia-authored-rendering policy and evaluate SPIRV.jl's actual shader
stages, Julia-version support and Vulkan integration from pinned source/tests.
An unregistered experimental dependency needs reproducible installation and an
explicit dependency decision. Its existence is not a successful compile/render
probe, nor evidence that every Julia construct is usable in shaders.

SPIRV.jl is the **first candidate to probe**, not a selected production compiler.
Existing Vulkan 0.7 symbol names do not prove signatures, behavior, generated
layouts or feature discovery remain compatible. A compat-range edit might be
sufficient, but that is a hypothesis until executed tests pass. Compare an
unmodified declared-compatible pinned stack with any candidate 0.7 stack in
isolated environments; record local source patches explicitly. Do not assume an
upstream PR is authorized or that removing a resolver constraint fixes behavior.

Likewise, the inspected SPIRV.jl Julia minimum informs a candidate companion
package, not a finalized VetraVulkan minimum. Resolve/test the complete selected
stack before freezing it. Core remains Julia 1.10-compatible.

For any candidate route, require all of:

1. Resolve a pinned Julia/compiler/Vulkan.jl/tool dependency environment.
2. Compile a Julia-authored representative kernel with runtime buffer inputs,
   branches and loops, appropriate entry point, storage classes and memory layout.
   Change input values without recompiling and verify independent results; a
   folded constant expression is insufficient execution evidence.
3. Validate the exact emitted bytes with `spirv-val --target-env vulkanX.Y`,
   replacing `X.Y` with the selected supported environment.
4. Create and execute the Vulkan pipeline, synchronize and compare readback to
   independent expected values; retain compiler/device/validation logs.
5. Demonstrate the chosen raster path and explain supported shader stages and
   restrictions. A compute-only renderer cannot rely on fixed-function blending
   for its dispatches; composition must be implemented on its actual path.

Generic SPIR-V validation, a `Kernel` capability module or a Vulkan clear/copy
command does not satisfy this shader gate. Do not propose entry-point attribute
injection as an established conversion from OpenCL to Vulkan memory semantics.
No new shader compiler project or non-Julia kernel-policy exception is authorized
by this research. If existing routes fail, report the evidence and decision needed.

### Software drivers and platform claims

The [reviewed Lavapipe build recipe](https://github.com/JuliaPackaging/Yggdrasil/blob/43774ee4d9d15317c67fb8487417835171e608e7/L/Lavapipe/build_tarballs.jl)
sets Mesa 26.2.2 / JLL build version 26.2.4, `gallium-drivers=llvmpipe` and
`vulkan-drivers=swrast`. It selects Windows WSI on Windows, no macOS WSI
(offscreen only), and X11 elsewhere. DirectX header build dependencies do not
make this a D3D12-rendered Vulkan backend.

The recipe explicitly excludes FreeBSD because the libdrm artifact lacks the
required pkg-config file. This blocks **that packaged Lavapipe CI route**, not
every possible system Vulkan driver on FreeBSD. System-loader/ICD support must
be investigated independently. An artifact recipe is not execution evidence on
Linux, Windows or macOS either.

Hardware macOS support depends on a tested MoltenVK/loader/device combination,
not on whether the distribution mechanism is a JLL. Software Vulkan correctness
on macOS does not demonstrate hardware GPU support. Record installation, OS,
architecture, loader, ICD, device and offscreen/presentation evidence separately.

### Required runtime/lifetime checks

- Keep Vetra CPU core free of Vulkan import/device creation. For optional provider
  installation/loading, explicitly test upstream device-precompile preferences;
  an `"auto"` failure being caught is not proof no device was initialized.
- Use both environment-specific SPIR-V validation and runtime validation layers.
  A debug callback only receives messages; it does not perform missing validation.
  A required layer unavailable in a lane is a named unmet check, not an equivalent
  pass from pixel comparison. The Khronos guide documents SDK distribution for
  Linux, Windows and macOS; actual CI installation still needs a probe.
- Preserve all submitted resources until their own completion, including wrapper
  parents and borrowed handles. Prove safe explicit release against the pinned
  wrapper API rather than mixing native destructors and finalizers arbitrarily.
- Use Vetra allocation/resource accounting for peak/live memory and optional
  supported driver budget/profiling extensions. There is no assumed portable
  `vkGetDeviceMemory` statistics call.
- Measure actual hardware for hardware-performance claims; identify software
  devices explicitly and select them deliberately in correctness CI.
- Derive required features from the selected Vetra shaders, not wholesale from
  the upstream test harness. In particular, Float64/Int64 and buffer-device-address
  requirements need justification; unsupported harness features alone do not prove
  a platform cannot run a smaller supported renderer.
- Keep the existing real-hardware correctness/performance gate for advertised
  hardware support. A manual protected run can supply evidence; a software ICD
  is neither guaranteed on an untested OS nor evidence of hardware acceleration.

Vulkan source review is complete for this planning record. Next: run the bounded
R040 probes after R000 approval and retain unresolved results as blockers to
their claims. No Vulkan/Julia shader runtime probe has been executed here.

## Browser and notebooks: reviewed findings

The corrected delegated report has been reviewed. The checked facts and
coordinator qualifications below are accepted as planning evidence; proposed
mapping formulas still require conformance tests. Source checks were performed
on 2026-11-10; no browser/kernel execution was performed in this research pass.

| Finding | Pinned source | Consequence |
| --- | --- | --- |
| OffscreenCanvas `convertToBlob` has both standard-name and alternative `toBlob` entries for Firefox 105 | [BCD OffscreenCanvas](https://github.com/mdn/browser-compat-data/blob/07c659514f0e1f528b16146f07778537d9178d5b/api/OffscreenCanvas.json) | Use feature detection; Firefox does not inherently require a nonstandard alias |
| `createConicGradient` has current unflagged entries for Chrome 99, Firefox 112 and Safari 16.1; older Firefox/Safari entries describe removed partial implementations with different starting-angle semantics | [BCD Canvas2D](https://github.com/mdn/browser-compat-data/blob/07c659514f0e1f528b16146f07778537d9178d5b/api/CanvasRenderingContext2D.json) | Do not classify current conic support as flagged or permanently exclude it from the required profile; verify angle/transform behavior in the supported engines |
| Safari's Canvas2D `filter` entry is version 18 **behind a preference flag** | [Same BCD file](https://github.com/mdn/browser-compat-data/blob/07c659514f0e1f528b16146f07778537d9178d5b/api/CanvasRenderingContext2D.json) | Safari ≥18 alone does not prove filter availability or Vetra effect equivalence |
| IJulia lists plain text, SVG, PNG/JPEG and Markdown/HTML MIME choices, and exposes MIME registration | [IJulia display source](https://github.com/JuliaLang/IJulia.jl/blob/0210ca2b9ffaea9a69161ce4e997c37b20dc2d6b/src/display.jl) | Use supported display hooks; a new MIME method does not prove frontend rendering or interaction |
| JupyterLab sanitizes untrusted HTML and explicitly refuses untrusted SVG in `renderSVG` | [JupyterLab renderers](https://github.com/jupyterlab/jupyterlab/blob/22a044e0dde10237f8c74988c03c2d42e0771394/packages/rendermime/src/renderers.ts) | SVG alone is not an untrusted-notebook fallback; retain PNG/plain text and a usable static fallback within HTML |
| JupyterLab's listed default factories include HTML, image formats and SVG, but no `video/mp4` factory; IJulia's default MIME list also omits it | [JupyterLab factories](https://github.com/jupyterlab/jupyterlab/blob/22a044e0dde10237f8c74988c03c2d42e0771394/packages/rendermime/src/factories.ts) | Do not claim native MP4 MIME support; test HTML video with poster/download fallback on each declared frontend |
| Canvas `arc` delegates to ellipse steps; a clockwise end−start span ≥2π (or the reverse span for counterclockwise) describes a full circumference | [WHATWG ellipse method steps](https://html.spec.whatwg.org/multipage/canvas.html#ellipse-method-steps) | Native Canvas can draw a full turn. Equal raw start/end angles do not encode one; preserve signed sweep and do not confuse coincident endpoints with a zero sweep |

BCD is compatibility documentation, not Vetra execution evidence. Record exact
browser versions in R051/R052/R070, including default settings; do not silently
enable a preference and claim baseline support.

### Contract corrections and required checks

- Browser execution consumes the reviewed **new Canvas** command contract.
  Legacy Picture semantics are translated explicitly. Clipped clear, dash phase,
  image source rectangles, compositing and angular paints cannot be removed from
  required conformance because a legacy adapter did not support them.
- A matching blend name is not sufficient semantic evidence. In particular,
  Porter–Duff `copy` and a legacy per-covered-pixel overwrite may differ in their
  effect outside the source shape. Compare whole destinations with independent
  expected pixels before approving any lowering.
- Gradient coordinates need independent affine tests, including nonuniform scale,
  shear and singular cases. Transforming a linear gradient's endpoints inversely
  is not a general proof that its scalar field stays fixed: the gradient direction
  transforms as a covector. Review creation/paint transforms against the Canvas
  specification rather than inheriting a historical exporter formula.
- Preserve elliptical arc radii/rotation or use a tested geometric lowering;
  a circular-arc wire tuple cannot represent every SVG-style elliptical arc.
  Test zero sweeps separately from full turns and both sweep directions; split
  arcs only where required by the selected representation. The revised report's
  claim that Canvas cannot draw a full turn is not adopted.
  Preserve canonical Float32 values when parsed as JS doubles: shortest decimal
  roundtrip *to Float32* alone does not guarantee the same double-valued coordinate.
  Widening the canonical Float32 to Float64 before shortest-roundtrip serialization
  is a candidate exact encoding; cross-language numeric fixtures must verify it.
- Outline text shares layout/geometry, not necessarily byte-identical browser
  rasterization. CPU-produced images and SVG rendered in the same browser are
  useful comparisons, not independent expected values by themselves. Retain the
  preapproved hand-derived/reference cases and feature-specific edge tolerances.
  Retain exact assertions for independently known integer-aligned opaque interiors,
  dimensions and ordering. Do not replace all pixel assertions with tolerances
  merely because glyph edges and filters vary across engines.
- There is no established present-day requirement to hand-write JSON or restrict
  the runtime to an arbitrary line count. Select the serializer under the existing
  dependency policy. Separately handle HTML raw-text embedding: a literal
  `</script>` closes a script element even when its type is `application/json`;
  JSON string quoting alone is insufficient. Escape `<` as a JSON Unicode escape
  or use an equally safe embedding, and encode HTML text/attributes separately.
- A co-bundled PNG is necessary but does not prove it will be selected over
  sanitized HTML. Put a meaningful static image/description in the HTML itself,
  then enhance after replay is ready. Test trusted, untrusted, reopened, exported
  and script-blocked states in the actual supported frontend; do not generalize
  JupyterLab results to Classic Notebook or VS Code without execution.
- Keep useful vector MIME output where supported; HTML's default rank is not a
  reason to prohibit SVG representations for other frontends or explicit display.
  Renderer-module unit tests supplement actual IJulia execution and browser-based
  saved-notebook/trust tests; they do not replace those acceptance gates. Verify
  the selected frontend's MIME preference policy rather than assuming one rank
  table governs all clients/configurations. Optional display providers retain
  ownership of their view types and avoid type piracy as required by R013.
- Treat network-free `file://` viewing separately from HTTPS Pages asset fetches.
  Both need tests. Same-origin assets remove one taint source, but do not guarantee
  decode success, nonzero size, supported encoding or successful `toBlob` output.
- A transferred HTML canvas is not assumed reusable for another worker transfer.
  Worker-loss recovery must use a supported reconnect path or replace only an
  adapter-owned node, with an explicit host callback when the host owns the node.
  Coordinate mappings must include element placement/CSS scale and backing-store
  scale; arbitrary CSS transforms require a tested inverse or a declared limit.

Browser/notebook source review is complete for this planning record. Actual
browser/kernel probes remain pending. These findings tighten existing R050–R052/
R070/R071/R099 tasks; they do not change the frozen-profile requirement or
authorize a smaller legacy-only browser milestone.

## Media: reviewed findings

Coordinator reviewed the delegated report against the pinned sources and local
artifacts below. The accepted findings refine R064–R069; the proposed F00–F05
replacement board, eager frame loading and implicit conversion policies are not
adopted. Provider selection remains an R064 decision.

### WebP ABI, ownership and encoder choice

- [WebP.jl 0.1.3 Wrapper.jl](https://github.com/stemann/WebP.jl/blob/435251e0a00c8e11987307f5908c34e3935e415a/src/Wrapper.jl)
  binds animation/demux/mux functions to the core `libwebp` product, including
  direct calls to `WebPAnimDecoderNew`, `WebPAnimEncoderNew` and `WebPMuxNew`.
  The [libwebp_jll 1.6.1+0 source record](https://github.com/JuliaBinaryWrappers/libwebp_jll.jl/blob/libwebp-v1.6.1+0/README.md)
  identifies upstream commit `4fa21912338357f89e4fd51cf2368325b59e9bd9` and separate
  core, decoder, demux and mux products. A missing upstream version tag is not
  missing provenance.
- At that exact revision, [demux.h](https://github.com/webmproject/libwebp/blob/4fa21912338357f89e4fd51cf2368325b59e9bd9/src/webp/demux.h)
  and [mux.h](https://github.com/webmproject/libwebp/blob/4fa21912338357f89e4fd51cf2368325b59e9bd9/src/webp/mux.h)
  define those constructors as **static inline helpers** calling exported
  `WebPAnimDecoderNewInternal`, `WebPAnimEncoderNewInternal` and `WebPNewInternal`
  with ABI versions. Changing only the library handle cannot fix a call to an
  unexported helper. Initialization helpers also need inspection.
- WebP.jl's mux ABI constant is `0x0108`; these upstream headers use `0x0109`
  (demux remains `0x0107`). This difference alone does not prove incompatibility:
  check the library's version checks and exact struct sizes, alignment, fields,
  integer widths and allocator pairing. Do not blindly change constants or assume
  a fixed line count for a safe FFI implementation. R064 owns that proof.
- `WebPAnimDecoderGetNext` returns the reconstructed canvas in decoder-owned
  storage, valid only until the next read/reset/delete. Retained public frames
  require owned copies; keep compressed source bytes alive for the decoder lifetime.
  Sequential raw-frame memory can be bounded even if compressed input is retained.
- `WebPAnimEncoderAdd` takes cumulative millisecond timestamps; the final NULL
  frame supplies the final duration. It remains a candidate for encoding edited
  **display frames**. Manual muxing is an option when encoded frame/delta control
  is needed, not a requirement to preserve display semantics. Both paths must
  disclose compressed buffering/assembly costs and validate timestamp limits.
- Keep the current static WebP animation rejection guard. A new animation path
  needs its own tested ABI/resource lifecycle before being exposed.

### VideoIO timing and conversion boundaries

The inspected version is VideoIO 1.10.1 at
`4787b63cd7d31f53214514f536fa98f5626e843e`:
[project](https://github.com/JuliaIO/VideoIO.jl/blob/4787b63cd7d31f53214514f536fa98f5626e843e/Project.toml),
[reader](https://github.com/JuliaIO/VideoIO.jl/blob/4787b63cd7d31f53214514f536fa98f5626e843e/src/avio.jl),
[writer](https://github.com/JuliaIO/VideoIO.jl/blob/4787b63cd7d31f53214514f536fa98f5626e843e/src/encoding.jl).

- Julia compat is `1.10`; FFMPEG `0.4.4` and FFMPEG_jll `8.0, 9.0` are compatible
  ranges, not an exact resolved environment. R064 pins the full environment.
- `frame_metadata` exposes integer PTS; `position(reader)` computes rational
  seconds from PTS and stream time base, or returns `nothing` when unavailable.
  `gettime` converts to Float64. Preserve rational timing through the adapter;
  metadata lacks a complete per-frame duration contract. Probe missing timestamps,
  duration lookahead/final-frame handling and reordered presentation explicitly.
- Writing sets codec time base to reciprocal framerate and frame PTS to `index`.
  Public `write(writer, img, index::Int)` permits explicit monotonically increasing
  indices, so the source does not justify declaring all VFR output impossible.
  It also fills zero packet durations from nominal framerate. Nonuniform PTS alone
  does not prove arbitrary frame durations, final hold time or muxed duration are
  preserved. R064/R067 must test them together before advertising VFR preservation.
- Reader seek trimming uses a nominal frame-period calculation in the inspected
  implementation. Exact VFR time selection needs sequential-versus-seek tests;
  keyframe status alone is not sufficient compositor/presentation state.
- The writer rejects odd dimensions and coerces RGBA matrices to RGB. Vetra must
  enforce its explicit matte policy **before** that conversion, with a tested
  codec/pixel-format profile and no silent resize, alpha loss or cadence change.
  Audio/subtitle inventory and explicit drop policy remain required.

### FFmpeg provenance and limited Linux observations

[FFMPEG_jll 9.0.2+0](https://github.com/JuliaBinaryWrappers/FFMPEG_jll.jl/blob/FFMPEG-v9.0.2+0/README.md)
records FFmpeg source archive SHA256
`8c3850283eb25fa026482078a04051e0be17347b09ef81a0849bec15a96e002e`
and its Yggdrasil build revision. Its artifact manifest lists Linux, Windows,
macOS and FreeBSD targets; these are availability records, not four-OS execution.

Coordinator hashed `/tmp/opencode/ffprobe/F.tar.gz`: SHA256
`73df0fe5f00c567f8f72c25bbe84485074766ca2710ab2cec5cf0da21d7e2ffc`, matching the
[x86_64 Linux glibc artifact manifest](https://github.com/JuliaBinaryWrappers/FFMPEG_jll.jl/blob/FFMPEG-v9.0.2+0/Artifacts.toml).
Running the extracted tools initially failed with missing `libiconv.so.2` (exit
127). They ran with `LD_LIBRARY_PATH` set to the extracted `lib`, `x264/lib`, then
the sorted installed `~/.julia/artifacts/*/lib` directories. This is an ad-hoc
inspection environment, **not** a resolved or validated VideoIO/JLL deployment.

Commands executed on those tools (all exit 0 with that environment):

```text
bin/ffmpeg -version
bin/ffmpeg -hide_banner -encoders
bin/ffmpeg -hide_banner -decoders
bin/ffprobe -v error -show_entries stream=codec_name,width,height,pix_fmt,time_base,color_range,color_space,color_transfer,color_primaries:frame=pts,duration -of json out_odd.mp4
```

The same ffprobe inspection, adding `r_frame_rate,nb_frames,duration` stream
fields, was run on `out_cfr.mp4`, `out_vfr.mp4`, `out_alpha.mp4`, `out_tagged.mp4`
and `out.gif`. Findings are limited to tool inventories and the existing files:

- Version reports 9.0.2, GIF/libx264/libx264rgb encoders and WebP/animated-WebP
  decoders; no WebP encoder was listed. A demuxer/muxer does not imply an encoder.
- The odd-size file is H.264 **YUV444**, 65×63. It proves neither YUV420 odd-size
  support nor that VideoIO's dimension guard can be removed.
- CFR sample: 30 frames, time base 1/15360, PTS increments 512. VFR sample:
  40 frames, time base 1/1000000, increments 33333/33334/100000; stream duration
  1.866667 differs from last PTS 1.9 plus reported duration 0.1. These samples
  do not establish an end-to-end timing-preservation contract.
- Alpha sample reports YUV420 without alpha; tagged sample reports TV range and
  BT.709 matrix but no primaries/transfer entries. Original generation commands
  and source pixels were not retained in these directories, so transformation,
  alpha-compositing and color correctness claims are not accepted from these files.
- GIF sample has five frames at 20-centisecond intervals; this is not disposal,
  transparency or loop conformance evidence.

Coordinator also used Python `ctypes.CDLL`/symbol lookup on installed libwebp
artifact `67fba63559df90be44da7873151be503a0cc8d8e`: the animation/mux symbols were
absent from core; `WebPAnimDecoderNewInternal`/`GetNext` were present in demux,
and `WebPNewInternal`/`WebPAnimEncoderNewInternal`/`WebPMuxPushFrame` in mux.
The inline constructor names were absent there too. This confirms symbol
placement only; no animation decode/encode or Julia wrapper call was validated.
The supplied `/tmp/opencode/webprobe/probe.jl` alone is not a reproducible record
of its author's broader runtime claims (no project/manifest or logs accompanied it).

The FFmpeg build reports `--enable-gpl --enable-nonfree --enable-libfdk-aac`.
Its [pinned license text](https://github.com/FFmpeg/FFmpeg/blob/n9.0.2/LICENSE.md)
states that enabling incompatible libraries with `--enable-nonfree` makes the
resulting binary unredistributable. A NOTICE entry alone does not settle selection
of this build for distribution. R064 must resolve a suitable provider/build and
record exact configuration before approval. The
[nogpl recipe](https://github.com/JuliaPackaging/Yggdrasil/blob/6c605cd74a98f797144a6a18f162891f5ca22ae1/F/FFMPEG/FFMPEG_nogpl/build_tarballs.jl)
omits x264/x265; that does **not** mean MP4 containers are impossible. MP4 muxing,
codec availability and target-player compatibility are distinct checks. No
provider dependency or redistributable binary is adopted by R000.

### Contract decisions retained and remaining probes

- Existing `Gif` eagerly stores frames with Float32 intervals; it is not the
  streaming rational-timing implementation. Reuse parsing only after independent
  disposal-2/restore-previous/palette/transparency cases pass. No decoder-generated
  expected pixels or generic lossless GIF/WebP block-splicing guarantee.
- Keep sequential reader and append-only writer interfaces independently usable;
  seek, random access and remuxing are optional capabilities. Finalization must
  support the declared IO/file sink rather than require a whole-output byte vector.
- Preserve original timing where representable; require explicit retiming, matte
  and unsupported-track policies otherwise. No default-black matte, silent CFR
  conversion or silently ignored audio. Concatenation remains decode/composite/
  edit/rebase/re-encode; compressed deltas may depend on preceding canvas state,
  palettes and background, even when dimensions match.
- R064 must execute exact package/ABI environments on the declared OS matrix,
  select an appropriate build and MP4 profile, and probe duration/seek/resource
  limits. R065–R069 own independent pixel/timeline fixtures, corrupt input,
  deterministic cleanup, bounded raw-frame memory and publication-failure tests.

Media source review is complete for R000 with these qualifications. Complete
provider execution, distribution choice and cross-platform support remain open
acceptance criteria of R064–R069, not evidence supplied by this planning task.
