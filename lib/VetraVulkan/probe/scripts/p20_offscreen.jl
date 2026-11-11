#!/usr/bin/env julia
# R040 probe p20: offscreen RGBA upload / clear / sync / readback (wrapper API only).
#
# - creates a 64x32 R8G8B8A8_UNORM offscreen image (optimal tiling, GENERAL layout)
# - uploads a hand-derived per-pixel pattern through a host-coherent staging
#   buffer (vkCmdCopyBufferToImage) with an explicit HOST->TRANSFER barrier,
#   reads it back (vkCmdCopyImageToBuffer) with a TRANSFER->HOST barrier and
#   compares byte-exactly
# - clears the image with vkCmdClearColorImage to a hand-derived value and
#   compares the readback byte-exactly
# - runs under the KHRONOS layer WITH synchronization validation enabled
#   (VkValidationFeaturesEXT); device-side ordering is expressed with explicit
#   barriers, never assumed from queue idleness
# - asserts no validation-layer ERROR/WARNING messages through cleanup + GC
# - destroys all resources deterministically (Base.finalize), in reverse
#   dependency order, with a refcount-underflow check
#
# The expected pixels are computed here (independent of any device code);
# nothing is derived from the code under test.
using Vulkan
include(joinpath(@__DIR__, "probe_common.jl"))
using .ProbeCommon: check, write_evidence, reset_checks, make_instance, pick_device, make_device,
                    queue_family, plain_buffer, write_mem, read_mem, with_commands, offscreen_image,
                    to_general_layout, memory_barrier!, release, refcount_ok, sync_hazard_control,
                    validation_errors, validation_warnings, validation_messages, validation_clean,
                    validation_evidence, CHECKS

import Vulkan:
  FORMAT_R8G8B8A8_UNORM, IMAGE_TYPE_2D, IMAGE_TILING_OPTIMAL,
  IMAGE_LAYOUT_GENERAL, IMAGE_LAYOUT_UNDEFINED,
  IMAGE_USAGE_TRANSFER_SRC_BIT, IMAGE_USAGE_TRANSFER_DST_BIT, IMAGE_USAGE_COLOR_ATTACHMENT_BIT,
  IMAGE_ASPECT_COLOR_BIT, QUEUE_GRAPHICS_BIT, QUEUE_COMPUTE_BIT,
  PIPELINE_STAGE_HOST_BIT, PIPELINE_STAGE_TRANSFER_BIT,
  ACCESS_HOST_WRITE_BIT, ACCESS_HOST_READ_BIT, ACCESS_TRANSFER_READ_BIT, ACCESS_TRANSFER_WRITE_BIT,
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

  inst = nothing; msg = nothing; dev = nothing; view = nothing
  img = nothing; img_mem = nothing; staging = nothing; staging_mem = nothing
  try
  inst, msg, layers_used = make_instance(; validation = true, sync_validation = true, api = v"1.3")
  ph, props = pick_device(inst; name_substring = "NVIDIA GeForce")
  ev["device"] = props.device_name
  ev["validation_layer"] = layers_used
  ev["sync_validation_requested"] = true
  check("validation layer actually enabled (no silent downgrade)", layers_used == ["VK_LAYER_KHRONOS_validation"], "enabled=$(layers_used)")
  qi = queue_family(ph, QUEUE_GRAPHICS_BIT | QUEUE_COMPUTE_BIT)
  dev = make_device(inst, ph; qi = qi)

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
  # explicit host->device ordering: the GPU transfer reads a host-written buffer
  with_commands(dev, qi, (cb) -> begin
    memory_barrier!(cb, PIPELINE_STAGE_HOST_BIT, PIPELINE_STAGE_TRANSFER_BIT, ACCESS_HOST_WRITE_BIT, ACCESS_TRANSFER_READ_BIT)
    Vulkan.cmd_copy_buffer_to_image(cb, staging, img, IMAGE_LAYOUT_GENERAL, [image_copy_region(W, H)])
    nothing
  end)
  # explicit device->host ordering before the host maps the result
  with_commands(dev, qi, (cb) -> begin
    Vulkan.cmd_copy_image_to_buffer(cb, img, IMAGE_LAYOUT_GENERAL, staging, [image_copy_region(W, H)])
    memory_barrier!(cb, PIPELINE_STAGE_TRANSFER_BIT, PIPELINE_STAGE_HOST_BIT, ACCESS_TRANSFER_WRITE_BIT, ACCESS_HOST_READ_BIT)
    nothing
  end)
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
  with_commands(dev, qi, (cb) -> begin
    Vulkan.cmd_copy_image_to_buffer(cb, img, IMAGE_LAYOUT_GENERAL, staging, [image_copy_region(W, H)])
    memory_barrier!(cb, PIPELINE_STAGE_TRANSFER_BIT, PIPELINE_STAGE_HOST_BIT, ACCESS_TRANSFER_WRITE_BIT, ACCESS_HOST_READ_BIT)
    nothing
  end)
  cleared = read_mem(dev, staging_mem, npx * 4)
  ok_clear = all(i -> cleared[i] == CLEAR_RGBA[((i - 1) % 4) + 1], 1:length(cleared))
  ev["clear_readback"] = Dict("expected" => collect(CLEAR_RGBA),
                              "first_pixel" => collect(cleared[1:4]),
                              "last_pixel" => collect(cleared[end - 3:end]),
                              "all_exact" => ok_clear)
  check("clear/readback byte-exact vs hand-derived clear value", ok_clear,
        "first=$(cleared[1:4]) last=$(cleared[end - 3:end])")

  # --- sync-validation control (positive + negative) ------------------------------
  # A real hazard (two fills, no barrier) must be flagged ONLY when sync
  # validation is actually active — proves the feature is on, not merely
  # requested. Each control runs on its own instance/device.
  waw_on = sync_hazard_control(; sync_validation = true)
  waw_off = sync_hazard_control(; sync_validation = false)
  ev["sync_validation_control"] = Dict("waw_detected_sync_on" => waw_on,
                                       "waw_detected_sync_off" => waw_off)
  check("sync validation ON: no-barrier WAW hazard flagged (WRITE_AFTER_WRITE)", waw_on >= 1, "waw=$waw_on")
  check("sync validation OFF (negative control): no WAW flagged", waw_off == 0, "waw=$waw_off")

  # --- deterministic cleanup (runs on EVERY path incl. mid-probe errors) -------
  # Capture lifetime, precisely: workload resources are released first (reverse
  # dependency order, buffer before memory where practical) while the messenger
  # is still alive, so destruction-time messages are captured; GC then runs
  # (finalizers, still under the live messenger); the validation evidence is
  # classified BEFORE the messenger and instance are released — after that the
  # capture is closed. Nothing is released twice.
  finally
    if view !== nothing
      release(view)
      release(img)
      release(img_mem)
    end
    if staging !== nothing
      release(staging)
      release(staging_mem)
    end
    dev !== nothing && release(dev)
    GC.gc()
    check("refcount clean after release (no underflow)", refcount_ok(dev) && refcount_ok(img) && refcount_ok(inst), "")
    ev["validation"] = validation_evidence()
    check("no validation-layer ERROR/WARNING messages through workload cleanup + GC", validation_clean(),
          "$(length(validation_errors())) errors, $(length(validation_warnings())) warnings, $(length(validation_messages())) total")
    msg !== nothing && release(msg)
    inst !== nothing && release(inst)
    GC.gc()
  end
  ev["cleanup"] = "Base.finalize in reverse dependency order; refcount underflow checked; GC + validation classification run while the messenger is still alive; messenger and instance released last, once"

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
