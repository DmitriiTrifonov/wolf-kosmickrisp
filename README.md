# Wolfenstein: The New Order on macOS via Zink + KosmicKrisp

[Русская версия](README.ru.md)

An experiment: run an OpenGL-only Windows game on an Apple Silicon Mac through NotProton
(CrossOver 26.3), without MoltenVK. The chain:

    game (OpenGL) -> Mesa opengl32 / Zink (Windows DLL) -> winevulkan
      -> vkshim (stands in for libMoltenVK.dylib) -> KosmicKrisp (x86_64 under Rosetta) -> Metal 4

KosmicKrisp is Mesa's Vulkan driver on top of Metal 4. Zink is OpenGL on top of Vulkan.

Tested on a MacBook Pro M2 Pro, 16 GB, macOS 26.5, Mesa 26.2.4.

## What works

- The game starts; menus and pause run at 60–110 FPS.
- Levels load and the game is playable start to finish.
- Combat averages about 44 FPS on low settings and drops to 27–35 in heavy scenes.
- GPU memory stays at 2–3 GB, no leaks.

Details, measurements and open issues are in [STATUS.md](STATUS.md).

## Known issues

- Black faces and blotches on skin, hands and gloves. Worst in the train cutscene.
- Objects sometimes pop in late when the camera turns (occlusion queries).
- Loading can stall while the game window is not on screen.
- In combat Zink waits for the GPU every frame when writing one buffer, which costs about 15 FPS.
  An experimental fix exists (`ZINK_KK_MAP_STAGE=1`) but it causes artifacts.

## What was fixed

KosmicKrisp (Mesa Vulkan over Metal 4):

- **Memory leak from Metal 4 command allocators.** `reset` does not give memory back, so grown
  allocators are recreated. GPU memory used to climb to 20+ GB over a session.
- **Render pass merging.** Consecutive render passes are encoders of one Metal command buffer
  instead of one command buffer each (a fresh one costs ~2.4 MB and a ~10x slower encoder):
  ~120 → ~24 command buffers per frame, FPS in heavy scenes ~20 → 45–50. Query availability
  writes are deferred so that passes can actually be merged.
- **Batched query operations.** Resets, result copies and small writes go into one dispatch
  (`libkk_*_array` kernels): 200–800 → 25–35 tiny jobs per frame.
- **Barriers flush caches** to the device coherence point, needed once passes share a command buffer.
- **Drawable leak.** A reference taken at present was never released; after ~15k frames macOS
  stopped showing frames (black screen in menus, pause and after death).
- **Primitive restart:** indices are scanned for restart markers instead of being unrolled.
- **Robustness fixes:** guards against zero-sized textures, copies and dispatches (AGX
  divide-by-zero), occlusion query overflow aliased to a spare slot, timestamp counter heaps
  recycled and optional, commit feedback handler registered once (was appended every submit),
  explicit CATransaction commit/flush.
- Temporary diagnostics: `kkperf` (FPS, CPU time per stage, real GPU busy time) in the log.

Zink (Mesa OpenGL over Vulkan):

- **At most 32 batches in flight** (`ZINK_KK_MAX_BATCHES`). Without a cap hundreds piled up,
  each keeping its command buffers' memory, and GPU memory grew to 8–13 GB.
- **`ZINK_KK_IMPLICIT_RP_SYNC=2`:** depth reads do not break the render pass.
- Smaller query pools (32), stale queries released on begin.
- Experimental, off by default: write-only maps of a busy buffer go through a staging buffer
  instead of waiting for the GPU (`ZINK_KK_MAP_STAGE=1`, +15 FPS in combat but with artifacts).
- Temporary diagnostics: `zinkwait` — where Zink waits for the GPU, per call site.

Outside Mesa:

- `vkshim` lets CrossOver's winevulkan load KosmicKrisp instead of MoltenVK.
- `fiberfix` fixes the game's inlined `GetCurrentFiber()` on CrossOver/macOS.
- NotProton: the Steam overlay shim is disabled (`NO_STEAM_OVERLAY=1`); it also caused black frames.
- `MESA_EXTENSION_OVERRIDE` hides GPU memory info so the game does not pick an 8192 virtual
  texture cache.

All Mesa changes are in a single file, `mesa-patches.diff` (against Mesa 26.2.4).

## Repository layout

- `mesa-patches.diff` — Mesa 26.2.4 patches (KosmicKrisp and Zink).
- `vkshim/` — `libMoltenVK.dylib` stand-in: loads KosmicKrisp for the configured prefix,
  clamps the API to 1.3, exports `vkCreateMetalSurfaceEXT` and forwards the rest to MoltenVK.
  Variables from `compatdata/<appid>/notproton-kosmickrisp` (`KEY=VALUE` lines) are set
  before the driver loads.
- `fiberfix/` — `dinput8.dll` proxy that fixes the inlined `GetCurrentFiber()` (`gs:[0x20]`)
  on CrossOver/macOS.
- `notproton/run.patch` — patch for the NotProton launch script: Metal frame capture
  (`MTL_CAPTURE_ENABLED=1`) and disabling the Steam overlay (`NO_STEAM_OVERLAY=1`).
- `mtl4test/` — small Metal 4 tests, e.g. `rp.m` measures the cost of render passes
  and command buffers.
- `gltest/` — OpenGL and fiber tests.
- `bin/` — helper scripts: `wolfwine` (wine for the game prefix), meson cross files,
  memory monitors.
- `backup/` — original versions of a couple of Mesa files for comparison.
- `STATUS.md` (`STATUS.ru.md` in Russian) — where things stand, measurements, next steps.

Mesa sources and builds are not included; build them yourself (see below).

## Building

Download the Mesa 26.2.4 archive from GitLab (tag `mesa-26.2.4`, it unpacks to `mesa-mesa-26.2.4`)
and apply the patches:

    curl -LO https://gitlab.freedesktop.org/mesa/mesa/-/archive/mesa-26.2.4/mesa-mesa-26.2.4.tar.gz
    mkdir -p mesa && tar -xzf mesa-mesa-26.2.4.tar.gz -C mesa
    patch -d mesa -p0 < mesa-patches.diff

KosmicKrisp (x86_64, built under Rosetta, needs an x86_64 Python 3.12):

    python3.12-x64 -m venv venv-x64 && venv-x64/bin/pip install mako packaging pyyaml meson
    arch -x86_64 env PATH="$PWD/clctools:$PWD/venv-x64/bin:/usr/bin:/bin:/opt/homebrew/bin" \
      CC="clang -arch x86_64" CXX="clang++ -arch x86_64" OBJC="clang -arch x86_64" OBJCXX="clang++ -arch x86_64" \
      PKG_CONFIG=/usr/bin/false MACOSX_DEPLOYMENT_TARGET=26.0 \
      meson setup build-kk-x64 mesa/mesa-mesa-26.2.4 --buildtype=release -Dplatforms=macos \
      -Dvulkan-drivers=kosmickrisp -Dgallium-drivers= -Dopengl=false -Dglx=disabled -Degl=disabled \
      -Dgbm=disabled -Dgles1=disabled -Dgles2=disabled -Dzstd=disabled -Dmesa-clc=system -Dllvm=disabled \
      -Dspirv-tools=disabled -Dxmlconfig=disabled -Dexpat=disabled --prefer-static
    arch -x86_64 env PATH="$PWD/clctools:$PWD/venv-x64/bin:/usr/bin:/bin:/opt/homebrew/bin" \
      MACOSX_DEPLOYMENT_TARGET=26.0 ninja -C build-kk-x64 src/kosmickrisp/vulkan/libvulkan_kosmickrisp.dylib

`clctools/` holds native `mesa_clc` and `vtn_bindgen2` from the same Mesa version (built separately
in `build-clc/`). The resulting `libvulkan_kosmickrisp.dylib` goes into
`~/Library/Application Support/notproton/runners/crossover-26.3.0.39832/CrossOver/lib64/kosmickrisp/`
and is signed with `codesign -f -s -`.

Zink for Windows (needs Homebrew bison and flex, and mingw-w64):

    PATH="/opt/homebrew/opt/bison/bin:/opt/homebrew/opt/flex/bin:$PWD/venv/bin:/opt/homebrew/bin:/usr/bin:/bin" \
      meson setup build-win mesa/mesa-mesa-26.2.4 --cross-file bin/mingw64.ini --buildtype=release \
      -Dplatforms=windows -Dgallium-drivers=zink -Dvulkan-drivers= -Dllvm=disabled -Dopengl=true \
      -Degl=disabled -Dgles1=disabled -Dgles2=disabled -Dzstd=disabled -Dxmlconfig=disabled -Dexpat=disabled \
      -Dspirv-tools=disabled -Dgallium-wgl-dll-name=libgallium_wgl -Dmicrosoft-clc=disabled \
      -Dgallium-va=disabled -Dvideo-codecs= -Db_ndebug=true
    ninja -C build-win

Copy `libgallium_wgl.dll`, `opengl32.dll`, `libz-1.dll` (from `subprojects/zlib-1.3.1`)
and mingw's `libwinpthread-1.dll` into the game folder.

## Settings

KosmicKrisp flags go into `MESA_KK_DEBUG` (comma-separated) in
`compatdata/201810/notproton-kosmickrisp`:

| flag | effect |
|---|---|
| `no_list_restart_unroll` | scan indices for restart markers instead of unrolling (currently on) |
| `no_rp_merge` | do not merge render passes |
| `no_query_batch` | do not batch query operations |
| `no_defer_avail` | do not defer query availability writes |
| `safe_math` | precise shader math instead of fast math |
| `serial_commit` | make each GPU submission wait for the previous one |
| `no_robustness` | disable robustness |

Zink variables are set in the prefix registry (`HKCU\Environment`):
`GALLIUM_DRIVER=zink`, `ZINK_KK_IMPLICIT_RP_SYNC=2`, optionally `ZINK_KK_MAX_BATCHES`
and `ZINK_KK_MAP_STAGE=1` (experimental, causes artifacts).

Game launch options: `+com_skipIntroVideo 1 +vt_pageImageSizeUnique 4096`.
The game sets its virtual texture cache to 8192 on its own, so the size is overridden both
with the launch option and with `MESA_EXTENSION_OVERRIDE` (hides GPU memory info from the game).

## License

The Mesa patches are under the Mesa license (MIT). The game and CrossOver are not included.
