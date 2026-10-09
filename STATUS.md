# На чём остановились (2026-10-09)

## Что работает

- Игра стартует через NotProton, OpenGL идёт по цепочке Zink → KosmicKrisp → Metal.
- Меню — 60 FPS, уровни загружаются, в игре 17–40 FPS.
- Больше не виснет на пулах запросов (occlusion/timestamp) и не падает при Cmd+Tab.

## Утечка видеопамяти — найдена и исправлена (2026-10-09)

- Причина: `MTL4CommandAllocator::reset` не возвращает память. Allocator навсегда держит
  объём самого большого буфера команд, записанного через него. Allocator'ов ~400–800,
  отдельные раздувались до ~940 МБ, в сумме 15+ ГБ. Это и были регионы по 768 КБ/1 МБ
  в `vmmap`. Воспроизведено в `mtl4test/al.m`: удаление allocator'а возвращает всю память.
- Исправление в `kk_cmd_buffer.c` (`kk_reset_encoder_state`): allocator больше 128 МБ
  пересоздаётся сразу, больше 32 МБ — раз в 64 сброса. Порог 16 МБ «каждый раз» ронял FPS до 6.
- Результат: видеопамять стабильно ~3 ГБ вместо роста до 20+ ГБ.
- Проверено и не виновато: heap'ы (все уничтожаются, `mtl4test/hc.m`), `VkBuffer` из Zink.

## Что не так

1. **Просадки FPS до 10–11** (в среднем ~30). Игра занимает ~1 ядро CPU, похоже на
   однопоточный упор: Zink → Wine → Rosetta → KosmicKrisp. Нужен профиль.
2. **Артефакты:** чёрные пятна на перчатках и руках (материал или формат текстуры).
   Возможные причины: нет `depth_clip_enable`, `custom_border_color`, геометрических шейдеров в KosmicKrisp.
3. Мелочь: `AGXG14XFamilyDepthStencilState` никогда не уничтожаются (241 тыс. за сессию),
   вероятно, это кэш Metal. Объекты `AGXG14XFamilyTexture`/`Buffer` частично переживают release.

## Следующий шаг

- Профиль просадок FPS (где тратится CPU).

## Потом

- Разобрать артефакты (чёрные перчатки).
- Убрать временную диагностику из KosmicKrisp: `kkbo`, `kkbridge2`, `kkobj`, `kkwsi`, `kkmem`, `kkbuf`, `kkcomp`, `kkleak` (уже отключён), `kkalloc`, логи образов в `vkshim`.
- Подумать, что из правок отправить в апстрим (Mesa: KosmicKrisp и Zink; NotProton — баг с `gs:[0x20]`).

## Полезное

- Лог игры: `…/compatdata/201810/pfx/drive_c/users/crossover/Saved Games/MachineGames/Wolfenstein The New Order/base/qconsole.log`
- Отчёты о падениях там же: `crash.*.html`.
- Запуск команд в префиксе игры: `bin/wolfwine reg query 'HKCU\Environment'`.
- Убить зависшую игру:
  `WINEPREFIX=…/compatdata/201810/pfx …/CrossOver/bin/wineserver -k; pkill -9 -f 'notproton-26.3/./run'`
- Игра при старте сама выставляет `vt_pageImageSizeUnique` в 8192. Поэтому переопределяются параметр запуска и `MESA_EXTENSION_OVERRIDE`.
