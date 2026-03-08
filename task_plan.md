# Task Plan: evil-visual-multi — Multiple Cursors for Emacs/Evil

## Goal
Создать пакет для Emacs с множественными курсорами, вдохновлённый vim-visual-multi, с полной интеграцией в evil-mode.

## Phases

- [x] Phase 1: Research
  - [x] 1.1 Изучить существующие решения (evil-mc, multiple-cursors.el)
  - [x] 1.2 Изучить как evil-mc реализует курсоры и overlays
  - [x] 1.3 Понять как работает undo/redo в Emacs для интеграции
  - [x] 1.4 Изучить API evil-surround для интеграции

- [x] Phase 2: Design
  - [x] 2.1 Спроектировать структуру данных для курсоров и регионов
  - [x] 2.2 Спроектировать VM Registers
  - [x] 2.3 Спроектировать систему режимов (cursor/extend)
  - [x] 2.4 Определить keybindings
  - [x] 2.5 Спроектировать визуальное отображение (faces, overlays)

- [x] Phase 3: Core Implementation
  - [x] 3.1 Базовая структура пакета (evim.el — evil-visual-multi)
  - [x] 3.2 Система курсоров и overlays
  - [x] 3.3 Cursor mode — базовые операции
  - [x] 3.4 Extend mode — базовые операции
  - [x] 3.5 Переключение между режимами

- [x] Phase 4: Cursor Creation
  - [x] 4.1 Find Word (C-n)
  - [x] 4.2 Add Cursor Down/Up (C-Down/C-Up)
  - [x] 4.3 Add Cursor At Pos (M-click)
  - [x] 4.4 Select All
  - [x] 4.5 Restrict to region (visual selection + C-n)

- [x] Phase 5: Navigation
  - [x] 5.1 n/N — следующее/предыдущее вхождение
  - [x] 5.2 ]/[ — навигация между курсорами
  - [x] 5.3 q — пропустить текущее
  - [x] 5.4 Q — удалить курсор
  - [x] 5.5 Курсор-"лидер" с отдельным face

- [x] Phase 6: Advanced Commands
  - [x] 6.1 Alignment (\\a)
  - [x] 6.2 Case conversion (U/u/~ in extend mode)
  - [ ] 6.3 Replace in regions (отложено)

- [x] Phase 7: Run at Cursors (fallback механизм)
  - [x] 7.1 Run Normal (\\z)
  - [x] 7.2 Run Macro (\\@)
  - [x] 7.3 Run Ex (\\:)

- [x] Phase 8: Operators with Motions
  Реализация операторов d, c, y с motions напрямую (как в vim-visual-multi).
  Это основной способ работы — \\z остаётся как fallback для редких команд.

  - [x] 8.1 Инфраструктура операторов
    - [x] Парсер motions (single: h,j,k,l,w,e,b,$,^,0; double: i,a,f,t,g + char)
    - [x] Функция `evim--run-operator-with-motion` — выполнить оператор на всех курсорах
    - [x] Поддержка counts (d3w, 2dw)

  - [x] 8.2 Delete operator (d)
    - [x] `d` в cursor mode → ждёт motion, выполняет delete
    - [x] `dw`, `de`, `db` — delete word motions
    - [x] `d$`, `d^`, `d0` — delete to line boundaries
    - [x] `dd` — delete line
    - [x] `diw`, `daw` — delete inner/a word (text objects)
    - [x] `di"`, `da"`, `di(`, `da(` — delete in/around quotes/parens
    - [x] `D` — delete to end of line
    - [x] `dw` не удаляет newline (vim-like behavior)

  - [x] 8.3 Change operator (c)
    - [x] `c` в cursor mode → delete + enter insert
    - [x] `cw`, `ce`, `cb` — change word motions
    - [x] `c$`, `c^`, `c0` — change to line boundaries
    - [x] `cc` — change line
    - [x] `ciw`, `caw` — change inner/a word
    - [x] `ci"`, `ca"`, `ci(`, `ca(` — change in/around
    - [x] `C` — change to end of line (с правильной позицией курсора)

  - [x] 8.4 Yank operator (y)
    - [x] `y` в cursor mode → ждёт motion, выполняет yank
    - [x] `yw`, `ye`, `yb` — yank word motions
    - [x] `y$`, `y^`, `y0` — yank to line boundaries
    - [x] `yy` — yank line
    - [x] `yiw`, `yaw` — yank inner/a word
    - [x] `Y` — yank line

  - [x] 8.5 Дополнительные операторы
    - [x] `J` — join lines
    - [x] `>`, `<` — indent/outdent с motion (>>, <<, >j, >ip)
    - [x] `gu`, `gU` — case change с motion (guu, gUU, guw)
    - [x] `g~` — toggle case с motion (g~~, g~w)

- [x] Phase 9: Special Features
  - [x] 9.1 Visual mode cursor selection (создание курсоров из visual selection)
  - [x] 9.2 Multiline mode
  - [x] 9.3 Undo/Redo с восстановлением курсоров
  - [x] 9.4 Reselect Last
  - [x] 9.5 VM Registers (интеграция с evil registers)

- [x] Phase 10: Integration
  - [x] 10.1 Интеграция с evil-surround

- [ ] Phase 11: Testing and Polish
  - [x] 11.1 Написать тесты (ERT) — 146 тестов
  - [x] 11.2 Тестирование на реальных сценариях
  - [x] 11.3 Оптимизация производительности
  - [ ] 11.4 Финальная документация

- [x] Phase 12: Manual Verification Assets
  - [x] Собран набор интерактивных упражнений для ручной проверки
  - [x] Покрыты создание курсоров, режимы, редактирование, регистры, surround, restriction и history/recovery

- [ ] Phase 13: Package Tutorial (`tutorial/`)
  Цель: собрать официальный tutorial пакета в директории `tutorial/`.

  - [x] 13.1 Аудит имеющихся упражнений и сценариев
    - [x] Найти повторы базовых объяснений и служебного текста
    - [x] Отметить сильные практические примеры, которые стоит сохранить
    - [x] Выделить темы, которые можно оставить отдельными файлами


## Blocked / Open Questions
- [ ] Название пакета: evil-visual-multi? evim? multi-cursor-evil?
- [ ] Лицензия: GPL-3+?
- [ ] Держать ли VM registers и surround в основной части tutorial или сделать их "advanced editing" appendix?

## Decisions Made
- Два режима (cursor/extend) — да
- Regex Search — нет (убрали)
- Shift-Arrows — нет (убрали)
- Single region mode — нет (отложили)
- C-f/C-b навигация — нет (отложили)
- Transpose, Duplicate, Shift, Split, Filter, Transform, Numbering — нет (отложили)
- Hydra/Transient меню — нет (отложили)
- Tutorial должен быть организован по workflows, а не по принципу "одна команда = один файл"
- Повторяющиеся инструкции tutorial нужно вынести в отдельный стартовый файл
- `\ g S` уместен рядом с undo/redo только если файл оформлен как history/recovery, а не как чистый undo reference
- `tutorial/` — единственный официальный tutorial пакета

## Status
**Phase 13.6** — Tutorial записан в `tutorial/`; дальше нужна ручная проверка и правка по результатам прохода.

### Planned Tutorial Structure
- Part 0 — `tutorial/00-start-here.txt`
  Общие правила tutorial: как запускать упражнения, как выходить из EVM, как читать записи вроде `\ a` и `\ g S`, какие зависимости опциональны.
- Part I — создание курсоров и навигация
  `tutorial/01-03`: search-based creation, structural creation, переключение `cursor/extend`, motions и навигация по существующим курсорам.
- Part II — редактирование
  `tutorial/04-08`: insert/quick edits, operators/text objects, layout/case, registers, surround.
- Part III — appendix / advanced workflows
  `tutorial/09-11`: fallback execution, scoped search, history/recovery.

### Оптимизации производительности (11.3)
- Overlay updates: переиспользование через `move-overlay` вместо пересоздания
- Buffer scan: убрано сканирование всего буфера в обычных операциях
- Region sorting: binary insert O(n) вместо full sort O(n log n)
- Batch creation: `evim--create-regions-batch` для Select All
- O(1) duplicate check: hash-table вместо cl-find-if

### Результаты тестирования (11.2)
- Все 146 ERT тестов проходят успешно
- Протестированы реальные сценарии:
  - Variable renaming (C-n, select-all, change) — OK
  - Multi-line cursor creation (C-Down) — OK
  - Toggle mode (Tab) — OK
  - Case conversion (U/u/~) — OK
  - Skip/Remove cursors (q/Q) — OK
  - Join lines (J) — OK
  - Surround integration (S, ys, ds, cs) — OK
  - Visual cursor selection (\\c) — OK
  - Reselect last (\\gS) — OK
  - Delete to EOL (D) — OK
  - Yank/Paste with VM registers — OK
  - Undo/Redo — работает в интерактивном режиме

Реализовано:
- `evim-core.el` — структуры данных, overlays, базовые операции, restrict to region
- `evim.el` — entry point, keymaps, minor mode, команды
- `test/evim-test.el` — 146 ERT тестов
- Cursor mode: движение, i/a/I/A/o/O, x/X/r/~
- Extend mode: y/d/c/p/P, U/u/~, o (flip)
- Переключение режимов: Tab
- Navigation: ]/[ между курсорами, q/Q удаление
- Поиск: C-n (find word), n/N, \\A (select all)
- Cursor creation: C-Down/C-Up, s-click (с toggle)
- Restrict to region: visual selection + C-n, \\r (clear)
- Run at cursors: \\z (normal), \\@ (macro), \\: (ex)
- Operators: d/c/y с motions, text objects, counts
- Shortcuts: D, C (с правильной позицией курсора), Y
- Fix: dw/dW не удаляют newline (vim-like behavior)
- J — join lines
- >, < — indent/outdent с motion (>>, <<, >j, >ip)
- gu, gU, g~ — case change с motion
- Visual mode cursor selection: \\c в visual mode
- Multiline mode: M toggle (флаг-заготовка, логика поиска не реализована)
- Undo/Redo: u/C-r с восстановлением позиций курсоров
- Reselect Last: \\gS восстанавливает последние курсоры с режимом
- VM Registers: именованные регистры с интеграцией в evil ("ay, "ap)
- evil-surround интеграция: S (extend), ys+motion (cursor), ds, cs
- Mode-line: EVM[C/E idx/count R M] — показывает режим, restrict, multiline

## Files
- `task_plan.md` — этот файл
- `architecture.md` — структура решения
- `features.md` — живое описание возможностей пакета и tutorial coverage
- `AGENTS.md` — инструкции для следующих сессий и verification commands
- `tutorial/` — новая компактная версия tutorial
- `notes.md` — лог ошибок и решений
