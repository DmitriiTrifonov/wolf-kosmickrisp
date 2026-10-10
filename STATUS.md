# Where things stand (2026-10-10)

[Русская версия](STATUS.ru.md)

## What works

- The game starts through NotProton; OpenGL goes through Zink → KosmicKrisp → Metal.
- Menus and pause run at 60–110 FPS; no more black screen.
- Combat: 44 FPS on average, 21% of the time at 27–35 (bound by a buffer wait in Zink, see below).
  Graphics settings: low.
- GPU memory stays at 2–3 GB, swap does not grow.

## Done on 2026-10-10

- **Found the main combat bottleneck, but the fix is off for now.** Every frame the game maps a
  256 KB buffer (apparently the bones for skeletal animation) in full, write-only and without
  `discard`, but writes only part of it. The GPU is still reading it, so Zink waits for the GPU
  (`zink_resource_usage_try_wait`): up to 380 ms per second, with the GPU busy only ~70% of the frame.
  Writing through a staging buffer gave 59 FPS in combat instead of 44, but with artifacts:
  - without preserving the old contents — black diamonds on the floor;
  - with a CPU copy of the previous contents (`kk_shadow`, write counter `kk_write_seq`) — an
    occasional diamond, more after opening the codex: the buffer is also written through other
    paths, and the full copy clobbers them;
  - copying only the changed runs against a "relaxed" copy — faces break (bones).
  Zink now waits by default, like upstream. Experiment: `ZINK_KK_MAP_STAGE=1` (strict copy check +
  copying only changed runs). Replacing the buffer with new memory from inside the driver is not
  allowed: the threaded context forbids it (`TC_TRANSFER_MAP_NO_INVALIDATE`).
  To do it properly, track every path that writes the buffer (direct unsynchronized maps, threaded
  context uploads via `resource_copy_region`, `buffer_subdata`) or rename the buffer at the
  threaded-context level.
- KosmicKrisp: `serial_commit` flag — each commit waits for the previous one on the GPU (an event).
  Tested the hypothesis that MTL4 barriers do not reach across commits; it did not affect the diamonds.
- Diagnostics (TEMP): `busy=` in `kkperf` — how long the GPU is actually busy; `zinkwait` — where
  Zink waits for the GPU, per call site.

## Done on 2026-10-09

- **MTL4 allocator leak.** `reset` does not return memory; grown allocators are recreated
  (`kk_reset_encoder_state`). This stopped GPU memory from climbing to 20+ GB.
- **Render pass merging** (`kk_cmd_buffer.c`, the main win). Every new MTL4 command buffer
  immediately takes ~2.4 MB from its allocator, and creating an encoder in a "cold" allocator costs
  ~130 µs versus ~12. Before, every pass had its own command buffer: ~120 command buffers and
  9–15 ms of CPU per frame. Now consecutive passes are encoders of one `gfx.cmd_buf`
  (`kk_seal_gfx`, `gfx_cb_encoders`). Work "before a pass" inside a merged command buffer splits
  the pass (`gfx_splits`, re-flush in `kk_draw`). ~24 command buffers per frame, pass begin
  0.9 ms per frame. Disable with `no_rp_merge`. Measurements: `mtl4test/rp.m`.
- **Query availability writes are deferred** (`kk_defer_avail_write`) to the next compute work
  outside a pass, otherwise there would be nothing to merge. Flag `no_defer_avail`.
- **Batched queries.** Resets, result copies and small writes go into one job (`kk_flush_batch`,
  `libkk_*_array` kernels). 200–800 jobs per frame became 25–35. Flag `no_query_batch`.
- **Barriers flush caches** (`MTL4VisibilityOptionDevice`) — needed now that passes share a command buffer.
- **Black screen in menus, pause and after death.** A drawable reference leaked in `kk_queue.c`:
  after ~15k frames macOS stopped showing frames. Plus NotProton's `overlay-shim`
  (disabled with `NO_STEAM_OVERLAY=1`, patch `notproton/run.patch`).
- **Zink: at most 32 batches in flight** (`ZINK_KK_MAX_BATCHES`, `zink_batch.c`). Without a cap
  hundreds piled up, each with its command buffers' memory, and GPU memory grew to 8–13 GB.
- **Zink: mode 2** `ZINK_KK_IMPLICIT_RP_SYNC=2` — depth reads do not break the pass.
- **Indices are scanned for restart markers** instead of being unrolled (`no_list_restart_unroll`).
- Periodic stutters with audio clicks came from my own monitor (`vmmap` every ~2 minutes), not the game.

## What is wrong

1. **Black faces and blotches on skin, hands and gloves.** Most visible in the train scene with Engel.
   Not the cause: render pass merging, Zink synchronization, texture compression, fast math
   (the `safe_math` flag almost helped, but not fully). Metal frame capture of gameplay frames
   crashes inside `GPUToolsCapture`.
2. Objects lag slightly when the camera turns (occlusion queries) — this was there before.
3. Loading sometimes stalls while the game window is not on screen: macOS barely hands out
   drawables to a background window.

## Next steps

- Make writes to a busy buffer wait-free, correctly (see above) — that is +15 FPS in combat.
- Remaining waits: reads of small query result buffers (`buf_r`, 128–256 bytes, up to 230 ms/s).
- Black faces: dump shaders (`MESA_KK_DEBUG=msl`) in the train scene and read the skin shader.

## Later

- Remove temporary diagnostics from KosmicKrisp and Zink: `kkperf*`, `kkbridge2`, `kkobj`, `kkwsi`,
  `kkbuf`, `kkalloc`, `zinkrp`, `zinkwait`, unroll reason counters, frame capture via `/tmp/kkcapture`.
- Decide what to send upstream (render pass merging, the drawable leak, query batching, the Zink batch cap).

## Useful

- KosmicKrisp flags and environment: `compatdata/201810/notproton-kosmickrisp` (`KEY=VALUE` lines, read by vkshim).
- Zink variables: in the prefix registry, `bin/wolfwine reg query 'HKCU\Environment'`.
- Launch the game: `open steam://rungameid/201810`.
- Kill a hung game: `pkill -9 -f WolfNewOrder_x64.exe; …/CrossOver/bin/wineserver -k`.
- Do not run `vmmap`/`sample` on the game periodically — they freeze it.
- The game sets `vt_pageImageSizeUnique` to 8192 on its own at startup, so both the launch option
  and `MESA_EXTENSION_OVERRIDE` override it.
