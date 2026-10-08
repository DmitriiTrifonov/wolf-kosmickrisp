# На чём остановились (2026-10-08, ночь)

## Что работает

- Игра стартует через NotProton, OpenGL идёт по цепочке Zink → KosmicKrisp → Metal.
- Меню — 60 FPS, уровни загружаются, в игре 17–40 FPS.
- Больше не виснет на пулах запросов (occlusion/timestamp) и не падает при Cmd+Tab.

## Что не так

1. **Утечка видеопамяти.** За сессию видеопамять (`IOAccelerator (graphics)` в `footprint`) растёт до ~20 ГБ. Мак уходит в своп, FPS падает до 1–8, потом игра виснет. Сильнее всего растёт при перезагрузке уровня (после смерти).
   - На уровне KosmicKrisp живых выделений всего ~2 ГБ (лог `kkbo:`). Значит, освобождённые heap'ы держат какие-то Metal-объекты.
   - Главная версия: Zink оставляет живыми `VkBuffer` после `vkFreeMemory`, а `MTLBuffer` из heap удерживает весь `MTLHeap`.
   - Проверено и **не** виновато: буферы команд MTL4, depth-stencil state, буферы и текстуры в heap'ах, линейные текстуры (buffer views), счётчиковые heap'ы (теперь переиспользуются), лимит Metal под Rosetta (его нет).
2. **Артефакты:** чёрные пятна на перчатках и руках (материал или формат текстуры). Вероятные причины: нет `depth_clip_enable`, `custom_border_color`, геометрических шейдеров в KosmicKrisp.

## Следующий шаг

1. Запустить игру и поиграть ~5 минут до тормозов. Параметры запуска в Steam:
   `%command% +com_skipIntroVideo 1 +vt_pageImageSizeUnique 4096`
2. Посмотреть строки `kkbuf:` в
   `~/Library/Application Support/notproton/launchers/201810/notproton-wine.log`.
   Там `live` — живые `VkBuffer`, `bound_live` — привязанные к памяти.
   - Если `bound_live` растёт вместе с видеопамятью, виноваты `VkBuffer`. Тогда ищем в Zink, почему они переживают свою память (кэш буферов или slab).
   - Если нет, ищем дальше среди Metal-объектов, которые держат heap.
3. Параллельно мониторить память: `bin/memmon.sh <файл>`.

## Потом

- Разобрать артефакты (чёрные перчатки).
- Убрать временную диагностику из KosmicKrisp: `kkbo`, `kkbridge2`, `kkobj`, `kkwsi`, `kkmem`, `kkbuf`, `kkcomp`, логи образов в `vkshim`.
- Подумать, что из правок отправить в апстрим (Mesa: KosmicKrisp и Zink; NotProton — баг с `gs:[0x20]`).

## Полезное

- Лог игры: `…/compatdata/201810/pfx/drive_c/users/crossover/Saved Games/MachineGames/Wolfenstein The New Order/base/qconsole.log`
- Отчёты о падениях там же: `crash.*.html`.
- Запуск команд в префиксе игры: `bin/wolfwine reg query 'HKCU\Environment'`.
- Убить зависшую игру:
  `WINEPREFIX=…/compatdata/201810/pfx …/CrossOver/bin/wineserver -k; pkill -9 -f 'notproton-26.3/./run'`
- Игра при старте сама выставляет `vt_pageImageSizeUnique` в 8192. Поэтому переопределяются параметр запуска и `MESA_EXTENSION_OVERRIDE`.
