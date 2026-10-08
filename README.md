# Wolfenstein: The New Order on macOS via Zink + KosmicKrisp

Experiment (started 2026-10-08): run an OpenGL-only Windows game through
NotProton (CrossOver 26.3) on Apple Silicon:

    game (OpenGL) -> Mesa opengl32/Zink (Windows DLL) -> winevulkan
      -> vkshim (libMoltenVK.dylib stand-in) -> KosmicKrisp (x86_64, Rosetta) -> Metal

## Layout

- `mesa/mesa-mesa-26.2.4/` — Mesa 26.2.4 sources with all patches applied
- `mesa-patches.diff` — the patches (vs `mesa-26.2.4-pristine.tar.gz`)
- `build-kk-x64/` — KosmicKrisp x86_64 build (native build under Rosetta)
- `build-win/` — Mesa Zink WGL build for Windows (mingw)
- `build-clc/`, `clctools/` — native `mesa_clc` / `vtn_bindgen2` needed by KosmicKrisp
- `vkshim/` — `libMoltenVK.dylib` shim: picks KosmicKrisp per prefix, clamps API to 1.3,
  enables all instance exts, exports `vkCreateMetalSurfaceEXT`, re-exports MoltenVK
- `fiberfix/` — `dinput8.dll` proxy fixing inline `GetCurrentFiber()` (gs:[0x20]) on CrossOver/macOS
- `gltest/`, `mtl4test/` — small test programs
- `backup/` — original MoltenVK, original pal1000 Mesa DLLs, original zink/kk sources
- `sym/` — pal1000 libgallium_wgl.dll + PDB (for symbolizing the stock build)
- `py-x64/` — x86_64 Python 3.12 (python-build-standalone) for the Rosetta build
- `bin/` — helper scripts (`wolfwine`, cross files, memory monitors)

Note: meson build dirs and venvs contain absolute scratchpad paths; after the move
re-run `meson setup --reconfigure` (or set up fresh build dirs) and recreate venvs.

## Rebuild

KosmicKrisp (x86_64, under Rosetta):

    python3.12-x64 -m venv venv-x64 && venv-x64/bin/pip install mako packaging pyyaml meson
    arch -x86_64 env PATH="$PWD/clctools:$PWD/venv-x64/bin:/usr/bin:/bin:/opt/homebrew/bin" \
      CC="clang -arch x86_64" CXX="clang++ -arch x86_64" OBJC="clang -arch x86_64" OBJCXX="clang++ -arch x86_64" \
      PKG_CONFIG=/usr/bin/false MACOSX_DEPLOYMENT_TARGET=26.0 \
      meson setup build-kk-x64 mesa/mesa-mesa-26.2.4 --buildtype=release -Dplatforms=macos \
      -Dvulkan-drivers=kosmickrisp -Dgallium-drivers= -Dopengl=false -Dglx=disabled -Degl=disabled \
      -Dgbm=disabled -Dgles1=disabled -Dgles2=disabled -Dzstd=disabled -Dmesa-clc=system -Dllvm=disabled \
      -Dspirv-tools=disabled -Dxmlconfig=disabled -Dexpat=disabled --prefer-static
    arch -x86_64 ... ninja -C build-kk-x64
    # install: build-kk-x64/src/kosmickrisp/vulkan/libvulkan_kosmickrisp.dylib
    #   -> ~/Library/Application Support/notproton/runners/crossover-26.3.0.39832/CrossOver/lib64/kosmickrisp/

Mesa Zink for Windows (needs Homebrew bison/flex, mingw-w64):

    PATH="/opt/homebrew/opt/bison/bin:/opt/homebrew/opt/flex/bin:$PWD/venv/bin:/opt/homebrew/bin:/usr/bin:/bin" \
      meson setup build-win mesa/mesa-mesa-26.2.4 --cross-file bin/mingw64.ini --buildtype=release \
      -Dplatforms=windows -Dgallium-drivers=zink -Dvulkan-drivers= -Dllvm=disabled -Dopengl=true \
      -Degl=disabled -Dgles1=disabled -Dgles2=disabled -Dzstd=disabled -Dxmlconfig=disabled -Dexpat=disabled \
      -Dspirv-tools=disabled -Dgallium-wgl-dll-name=libgallium_wgl -Dmicrosoft-clc=disabled \
      -Dgallium-va=disabled -Dvideo-codecs= -Db_ndebug=true
    ninja -C build-win
    # install into the game folder: libgallium_wgl.dll, opengl32.dll, subprojects/zlib-1.3.1/libz-1.dll,
    #   plus mingw's libwinpthread-1.dll

## Status (2026-10-08)

Works: game starts, menus at 60 FPS, levels load, play is possible (17–40 FPS).
Open issues:
- GPU memory grows to ~20 GB over a session (swap, FPS drops to 1–8, eventually hangs).
  KosmicKrisp-level live allocations are only ~2 GB, so Metal objects retain freed heaps.
  Next step: read new `kkbuf:` counters (live VkBuffers vs bound) from
  `~/Library/Application Support/notproton/launchers/201810/notproton-wine.log`.
- Black patches on gloves/hands (material/format artifact).
- TEMP diagnostics in KosmicKrisp (kkbo, kkbridge2, kkobj, kkwsi, kkmem, kkbuf) should be removed
  once done.

## Fixes made so far

KosmicKrisp: zero-size texture/copy/dispatch guards (AGX divide-by-zero), explicit CATransaction
commit/flush, commit feedback handler registered once (was appended on every submit), occlusion
query overflow aliased to a spare slot, timestamp counter heaps recycled and optional, bounded
timestamp stage map.
Zink: smaller query pools (32), release stale vk queries on begin_query (pinned pools).
Other: fiberfix proxy, vkshim, `MESA_EXTENSION_OVERRIDE` hides GPU meminfo so the game doesn't
pick an 8192 virtual texture cache.
