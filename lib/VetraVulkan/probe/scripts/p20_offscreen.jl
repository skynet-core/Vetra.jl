#!/usr/bin/env julia
# R040 probe p20: offscreen RGBA upload / clear / sync / readback (wrapper API only).
#
# - creates a 64x32 R8G8B8A8_UNORM offscreen image (optimal tiling, GENERAL layout)
# - uploads a hand-derived per-pixel pattern through a host-coherent staging
#   buffer (vkCmdCopyBufferToImage), synchronizes (queue_wait_idle), reads it
#   back (vkCmdCopyImageToBuffer) and compares byte-exactly
# - clears the image with vkCmdClearColorImage to a hand-derived value,
#   synchronizes and compares the readback byte-exactly
# - asserts zero validation-layer ERROR messages at the end
# - destroys all resources explicitly, in dependency order
#
# The expected pixels are computed here (independent of any device code);
# nothing is derived from the code under test.
using Vulkan
include(joinpath(@__DIR__, "probe_common.jl"))
using .ProbeCommon: check, write_evidence, reset_checks, make_instance, pick_device, make_device,
                    queue_family, bda_buffer, plain_buffer, write_mem, read_mem, with_commands, offscreen_image,
                    to_general_layout,
                    validation_errors, validation_messages, CHECKS

import Vulkan:
  FORMAT_R8G8B8A8_UNORM, IMAGE_TYPE_2D, IMAGE_TILING_OPTIMAL,
  IMAGE_LAYOUT_GENERAL, IMAGE_LAYOUT_UNDEFINED,
  IMAGE_USAGE_TRANSFER_SRC_BIT, IMAGE_USAGE_TRANSFER_DST_BIT, IMAGE_USAGE_COLOR_ATTACHMENT_BIT,
  IMAGE_ASPECT_COLOR_BIT, QUEUE_GRAPHICS_BIT, QUEUE_COMPUTE_BIT,
  Offset3D, Extent3D, BufferImageCopy, ImageSubresourceLayers, ClearColorValue

const PROBE_ROOT = dirname(@__DIR__)
const EVIDENCE = joinpath(PROBE_ROOT, "evidence")

const W = 64
const H = 32

"""Hand-derived pixel pattern (row-major, 1 pixel = 4 bytes R,G,B,A)."""
function expected_pattern(w, h)
  data = Vector{UInt8}(undef, w * h * 4)
  for y in 0:h - 1
    for x in 0:w - 1
      idx = y * w + x
      i4 = idx * 4
      data[i4 + 1] = UInt8((idx * 13) % 256)
      data[i4 + 2] = UInt8((idx * 29) % 256)
      data[i4 + 3] = UInt8((idx * 41) % 256)
      data[i4 + 4] = idx % 2 == 0 ? 255 : 0
    end
  end
  data
end

const CLEAR_RGBA = (255, 0, 255, 255) # magenta, opaque (R,G,B,A)

function image_copy_region(w, h)
  BufferImageCopy(
    0, 0, 0,
    ImageSubresourceLayers(IMAGE_ASPECT_COLOR_BIT, 0, 0, 1),
    Offset3D(0, 0, 0),
    Extent3D(UInt32(w), UInt32(h), UInt32(1)))
end

function main()
  reset_checks()
  ev = Dict{String, Any}()

  inst, msg, layers_used = make_instance(; validation = true, api = v"1.3")
  ph, props = pick_device(inst; name_substring = "NVIDIA GeForce")
  ev["device"] = props.device_name
  ev["validation_layer"] = layers_used
  qi = queue_family(ph, QUEUE_GRAPHICS_BIT | QUEUE_COMPUTE_BIT)
  dev = make_device(inst, ph; f10 = Symbol[], f11 = Symbol[], f12 = Symbol[], f13 = Symbol[],
                    layers = layers_used, extensions = String[], qi = qi)

  npx = W * H
  pattern = expected_pattern(W, H)

  # --- upload + readback ------------------------------------------------------
  img_res = offscreen_image(dev, ph, W, H;
                            usage = IMAGE_USAGE_TRANSFER_SRC_BIT | IMAGE_USAGE_TRANSFER_DST_BIT | IMAGE_USAGE_COLOR_ATTACHMENT_BIT)
  img = img_res.image
  view = img_res.view
  img_mem = img_res.memory
  to_general_layout(dev, qi, img, W, H)
  sres = plain_buffer(dev, ph, npx * 4)
  staging = sres.buffer
  staging_mem = sres.memory
  write_mem(dev, staging_mem, pattern)
  with_commands(dev, qi, (cb) -> Vulkan.cmd_copy_buffer_to_image(cb, staging, img, IMAGE_LAYOUT_GENERAL, [image_copy_region(W, H)]))
  with_commands(dev, qi, (cb) -> Vulkan.cmd_copy_image_to_buffer(cb, img, IMAGE_LAYOUT_GENERAL, staging, [image_copy_region(W, H)]))
  readback = read_mem(dev, staging_mem, npx * 4)
  nmatch = count(readback .== pattern)
  ev["upload_readback"] = Dict("pixels" => npx, "bytes_compared" => length(pattern),
                               "bytes_exact" => nmatch, "all_exact" => nmatch == length(pattern))
  check("upload/readback byte-exact vs hand-derived pattern", nmatch == length(pattern),
        "$nmatch/$(length(pattern)) bytes exact")

  # --- clear + readback ---------------------------------------------------------
  with_commands(dev, qi, (cb) -> Vulkan.cmd_clear_color_image(cb, img, IMAGE_LAYOUT_GENERAL,
                                 ClearColorValue((Float32(CLEAR_RGBA[1]) / 255, Float32(CLEAR_RGBA[2]) / 255, Float32(CLEAR_RGBA[3]) / 255, Float32(CLEAR_RGBA[4]) / 255)),
                                 [ImageSubresourceRange(IMAGE_ASPECT_COLOR_BIT, 0, 1, 0, 1)]))
  with_commands(dev, qi, (cb) -> Vulkan.cmd_copy_image_to_buffer(cb, img, IMAGE_LAYOUT_GENERAL, staging, [image_copy_region(W, H)]))
  cleared = read_mem(dev, staging_mem, npx * 4)
  ok_clear = all(i -> cleared[i] == CLEAR_RGBA[((i - 1) % 4) + 1], 1:length(cleared))
  ev["clear_readback"] = Dict("expected" => collect(CLEAR_RGBA),
                              "first_pixel" => collect(cleared[1:4]),
                              "last_pixel" => collect(cleared[end - 3:end]),
                              "all_exact" => ok_clear)
  check("clear/readback byte-exact vs hand-derived clear value", ok_clear,
        "first=$(cleared[1:4]) last=$(cleared[end - 3:end])")

  # --- validation layer cleanliness ----------------------------------------------
  errs = validation_errors()
  ev["validation"] = Dict("errors" => [m[3] for m in errs],
                          "n_messages" => length(validation_messages()))
  check("no validation-layer ERROR messages", isempty(errs), "errors=$(length(errs))")

  # --- deterministic cleanup -------------------------------------------------------
  # The wrapper owns native handles through a refcount model: `h.destructor()`
  # destroys the handle when its refcount hits zero and decrements the parent.
  # Destroying leaves first; never call the raw vk free/destroy on a live handle
  # (the finalizer would free it a second time and segfault at exit).
  view.destructor()
  img.destructor()
  img_mem.destructor()
  staging_mem.destructor()
  staging.destructor()
  dev.destructor()
  if !isnothing(msg)
    msg.destructor()
  end
  inst.destructor()
  ev["cleanup"] = "explicit .destructor() in reverse dependency order after queue_wait_idle; no finalizer double-free at exit"
  check("destroyed device/image/buffer without error", true)

  npass, nfail = count(x -> x[2], CHECKS), count(x -> !x[2], CHECKS)
  ev["summary"] = Dict("pass" => npass, "fail" => nfail)
  ev["checks"] = [Dict("name" => c[1], "ok" => c[2], "detail" => c[3]) for c in CHECKS]
  path = write_evidence(joinpath(EVIDENCE, "p20_offscreen.json"), ev)
  println("evidence: ", path, " | pass=", npass, " fail=", nfail)
  nfail > 0 && exit(1)
  ev
end

const _here = @__MODULE__
if _here == Main
  main()
end
