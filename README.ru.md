# Wolfenstein: The New Order на macOS через Zink + KosmicKrisp

[English version](README.md)

Эксперимент: запустить Windows-игру, которая умеет только OpenGL, на Mac с Apple Silicon
через NotProton (CrossOver 26.3), без MoltenVK. Цепочка такая:

    игра (OpenGL) -> Mesa opengl32 / Zink (Windows DLL) -> winevulkan
      -> vkshim (подменяет libMoltenVK.dylib) -> KosmicKrisp (x86_64 под Rosetta) -> Metal 4

KosmicKrisp — Vulkan-драйвер из Mesa поверх Metal 4. Zink — OpenGL поверх Vulkan.

Проверялось на MacBook Pro M2 Pro, 16 ГБ, macOS 26.5, Mesa 26.2.4.

## Что сейчас работает

- Игра запускается, меню и пауза идут на 60–110 FPS.
- Уровни грузятся, играть можно от начала до конца.
- Бои — в среднем около 44 FPS на низких настройках, в тяжёлых местах проседает до 27–35.
- Видеопамять держится на 2–3 ГБ, без утечек.

Подробности, замеры и открытые проблемы — в [STATUS.ru.md](STATUS.ru.md).

## Известные проблемы

- Чёрные лица и пятна на коже, руках, перчатках. Сильнее всего видно в катсцене в поезде.
- Объекты иногда появляются с запозданием при повороте камеры (проверки видимости).
- Загрузка может зависнуть, пока окно игры не на экране.
- В бою Zink каждый кадр ждёт видеокарту при записи в один буфер — это примерно 15 FPS.
  Экспериментальное исправление есть (`ZINK_KK_MAP_STAGE=1`), но оно даёт артефакты.

## Что исправлено

KosmicKrisp (Vulkan из Mesa поверх Metal 4):

- **Утечка памяти из allocator'ов команд Metal 4.** `reset` не возвращает память, поэтому
  разросшиеся allocator'ы пересоздаются. Раньше видеопамять за сессию доходила до 20+ ГБ.
- **Склейка проходов рендера.** Соседние проходы — энкодеры одного буфера команд Metal, а не
  отдельные буферы (новый стоит ~2,4 МБ и в ~10 раз более медленный энкодер): ~120 → ~24 буфера
  на кадр, FPS в тяжёлых сценах ~20 → 45–50. Отметки готовности запросов откладываются,
  иначе склеивать было бы нечего.
- **Пачки для запросов.** Сброс, копирование результатов и мелкие записи идут одной задачей
  (ядра `libkk_*_array`): 200–800 → 25–35 мелких задач на кадр.
- **Барьеры сбрасывают кэши** до уровня всего устройства — это нужно, раз проходы делят буфер.
- **Утечка drawable.** Ссылка, взятая при показе кадра, не освобождалась; через ~15 тыс. кадров
  macOS переставал показывать кадры (чёрный экран в меню, на паузе и после смерти).
- **Разрывы примитивов:** маркеры разрыва ищутся в индексах вместо развёртки.
- **Защиты:** от нулевых размеров текстур, копий и dispatch'ей (деление на ноль в AGX),
  переполнение запросов видимости уходит в запасной слот, кучи счётчиков времени переиспользуются
  и необязательны, обработчик завершения регистрируется один раз (раньше добавлялся на каждую
  отправку), явный commit/flush CATransaction.
- Временная диагностика: `kkperf` в логе (FPS, время CPU по этапам, реальная занятость видеокарты).

Zink (OpenGL из Mesa поверх Vulkan):

- **Не больше 32 пакетов команд в работе** (`ZINK_KK_MAX_BATCHES`). Без лимита их копились сотни,
  каждый со своей памятью буферов команд, и видеопамять росла до 8–13 ГБ.
- **`ZINK_KK_IMPLICIT_RP_SYNC=2`:** чтение глубины не рвёт проход рендера.
- Пулы запросов меньше (32), устаревшие запросы освобождаются при начале нового.
- Экспериментально, по умолчанию выключено: запись в занятый буфер через промежуточный буфер
  вместо ожидания видеокарты (`ZINK_KK_MAP_STAGE=1`, +15 FPS в бою, но с артефактами).
- Временная диагностика: `zinkwait` — где Zink ждёт видеокарту, по месту вызова.

Вне Mesa:

- `vkshim` — чтобы winevulkan из CrossOver грузил KosmicKrisp вместо MoltenVK.
- `fiberfix` чинит встроенный в игру `GetCurrentFiber()` в CrossOver на macOS.
- NotProton: выключен shim оверлея Steam (`NO_STEAM_OVERLAY=1`), он тоже давал чёрные кадры.
- `MESA_EXTENSION_OVERRIDE` прячет от игры объём видеопамяти, чтобы она не выбирала кэш
  виртуальных текстур 8192.

Все изменения Mesa — в одном файле `mesa-patches.diff` (относительно Mesa 26.2.4).

## Что в репозитории

- `mesa-patches.diff` — патчи Mesa 26.2.4 (KosmicKrisp и Zink).
- `vkshim/` — подмена `libMoltenVK.dylib`: подключает KosmicKrisp для нужного префикса,
  ограничивает API версией 1.3, экспортирует `vkCreateMetalSurfaceEXT`, остальное отдаёт MoltenVK.
  Переменные из файла `compatdata/<appid>/notproton-kosmickrisp` (строки `KEY=VALUE`)
  выставляются до загрузки драйвера.
- `fiberfix/` — прокси `dinput8.dll`, чинит встроенный `GetCurrentFiber()` (`gs:[0x20]`)
  в CrossOver на macOS.
- `notproton/run.patch` — патч скрипта запуска NotProton: запись кадров Metal
  (`MTL_CAPTURE_ENABLED=1`) и отключение оверлея Steam (`NO_STEAM_OVERLAY=1`).
- `mtl4test/` — маленькие тесты Metal 4. Например, `rp.m` меряет цену проходов рендера
  и буферов команд.
- `gltest/` — тесты OpenGL и fiber'ов.
- `bin/` — вспомогательные скрипты: `wolfwine` (wine для префикса игры), cross-файлы meson,
  мониторы памяти.
- `backup/` — исходные версии пары файлов Mesa для сравнения.
- `STATUS.ru.md` (`STATUS.md` на английском) — где остановились, замеры, следующие шаги.

Исходники и сборки Mesa в репозиторий не входят, их нужно собрать самому (см. ниже).

## Сборка

Скачайте архив Mesa 26.2.4 с GitLab (тег `mesa-26.2.4`, он распаковывается в `mesa-mesa-26.2.4`)
и наложите патчи:

    curl -LO https://gitlab.freedesktop.org/mesa/mesa/-/archive/mesa-26.2.4/mesa-mesa-26.2.4.tar.gz
    mkdir -p mesa && tar -xzf mesa-mesa-26.2.4.tar.gz -C mesa
    patch -d mesa -p0 < mesa-patches.diff

KosmicKrisp (x86_64, собирается под Rosetta, нужен x86_64 Python 3.12):

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

`clctools/` — нативные `mesa_clc` и `vtn_bindgen2` из той же версии Mesa (собираются отдельно,
в `build-clc/`). Готовый `libvulkan_kosmickrisp.dylib` кладётся в
`~/Library/Application Support/notproton/runners/crossover-26.3.0.39832/CrossOver/lib64/kosmickrisp/`
и подписывается `codesign -f -s -`.

Zink для Windows (нужны bison и flex из Homebrew и mingw-w64):

    PATH="/opt/homebrew/opt/bison/bin:/opt/homebrew/opt/flex/bin:$PWD/venv/bin:/opt/homebrew/bin:/usr/bin:/bin" \
      meson setup build-win mesa/mesa-mesa-26.2.4 --cross-file bin/mingw64.ini --buildtype=release \
      -Dplatforms=windows -Dgallium-drivers=zink -Dvulkan-drivers= -Dllvm=disabled -Dopengl=true \
      -Degl=disabled -Dgles1=disabled -Dgles2=disabled -Dzstd=disabled -Dxmlconfig=disabled -Dexpat=disabled \
      -Dspirv-tools=disabled -Dgallium-wgl-dll-name=libgallium_wgl -Dmicrosoft-clc=disabled \
      -Dgallium-va=disabled -Dvideo-codecs= -Db_ndebug=true
    ninja -C build-win

В папку игры кладутся `libgallium_wgl.dll`, `opengl32.dll`, `libz-1.dll` (из `subprojects/zlib-1.3.1`)
и `libwinpthread-1.dll` из mingw.

## Настройки

Флаги KosmicKrisp задаются через `MESA_KK_DEBUG` (через запятую) в файле
`compatdata/201810/notproton-kosmickrisp`:

| флаг | что делает |
|---|---|
| `no_list_restart_unroll` | искать маркеры разрыва в индексах вместо развёртки (сейчас включён) |
| `no_rp_merge` | не склеивать проходы рендера |
| `no_query_batch` | не собирать запросы в пачки |
| `no_defer_avail` | не откладывать отметки готовности запросов |
| `safe_math` | точная математика в шейдерах вместо быстрой |
| `serial_commit` | каждая отправка на видеокарте ждёт предыдущую |
| `no_robustness` | выключить robustness |

Переменные Zink задаются в реестре префикса (`HKCU\Environment`):
`GALLIUM_DRIVER=zink`, `ZINK_KK_IMPLICIT_RP_SYNC=2`, по желанию `ZINK_KK_MAX_BATCHES`
и `ZINK_KK_MAP_STAGE=1` (эксперимент, с артефактами).

Параметры запуска игры: `+com_skipIntroVideo 1 +vt_pageImageSizeUnique 4096`.
Игра сама выставляет кэш виртуальных текстур в 8192, поэтому размер переопределяется
и параметром запуска, и через `MESA_EXTENSION_OVERRIDE` (прячет от игры объём видеопамяти).

## Лицензия

Патчи Mesa распространяются под лицензией Mesa (MIT). Игра и CrossOver сюда не входят.
