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
  - [x] 3.1 Базовая структура пакета (evm.el — evil-visual-multi)
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
    - [x] Функция `evm--run-operator-with-motion` — выполнить оператор на всех курсорах
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

- [ ] Phase 12: Interactive Tutorial (demo/)
  Интерактивный учебник: каждый файл — самодостаточный урок.
  Пользователь открывает файл в Emacs, читает объяснения и практикуется
  прямо в нём на подготовленных текстовых примерах.

  - [x] 12.1  `demo/01-find-word.txt` — C-n, visual C-n, add next, n/N, q/Q, \ A, сценарий переименования
  - [x] 12.2  `demo/02-cursors-vertical.txt` — C-Down / C-Up, создание колонки курсоров
  - [x] 12.3  `demo/03-visual-cursors.txt` — \ c из visual-line, visual-block, visual-char
  - [x] 12.4  `demo/04-cursor-extend-modes.txt` — Tab переключение, extend y/d/c, flip (o)
  - [x] 12.5  `demo/05-movements.txt` — h/j/k/l, w/b/e, 0/^/$ во всех курсорах
  - [x] 12.6  `demo/06-insert-mode.txt` — i/a/I/A/o/O с real-time replication
  - [x] 12.7  `demo/07-delete-change-yank.txt` — d/c/y + motions, dd/cc/yy, D/C/Y
  - [x] 12.8  `demo/08-text-objects.txt` — diw, ci", da), ya>, dit и т.д.
  - [x] 12.9  `demo/09-quick-edits.txt` — x/X, r, ~, J (join lines)
  - [x] 12.10 `demo/10-indent.txt` — >>/<< , >j, >ip, <ip
  - [x] 12.11 `demo/11-case-operators.txt` — gu/gU/g~ + motions, extend U/u/~
  - [x] 12.12 `demo/12-registers.txt` — VM registers, "a prefix, p/P, распределение по курсорам
  - [x] 12.13 `demo/13-surround.txt` — S (extend), ys+motion, ds, cs
  - [x] 12.14 `demo/14-align.txt` — \ a (align cursors)
  - [x] 12.15 `demo/15-run-at-cursors.txt` — \ z (normal cmd), \ @ (macro), \ : (ex cmd)
  - [x] 12.16 `demo/16-restrict.txt` — \ r (restrict search to visual region)
  - [x] 12.17 `demo/17-undo-redo.txt` — u / C-r, \ g S (reselect last)

## Blocked / Open Questions
- [ ] Название пакета: evil-visual-multi? evm? multi-cursor-evil?
- [ ] Лицензия: GPL-3+?

## Decisions Made
- Два режима (cursor/extend) — да
- Regex Search — нет (убрали)
- Shift-Arrows — нет (убрали)
- Single region mode — нет (отложили)
- C-f/C-b навигация — нет (отложили)
- Transpose, Duplicate, Shift, Split, Filter, Transform, Numbering — нет (отложили)
- Hydra/Transient меню — нет (отложили)

## Status
**Phase 11.3** — Оптимизация производительности завершена.

### Оптимизации производительности (11.3)
- Overlay updates: переиспользование через `move-overlay` вместо пересоздания
- Buffer scan: убрано сканирование всего буфера в обычных операциях
- Region sorting: binary insert O(n) вместо full sort O(n log n)
- Batch creation: `evm--create-regions-batch` для Select All
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
- `evm-core.el` — структуры данных, overlays, базовые операции, restrict to region
- `evm.el` — entry point, keymaps, minor mode, команды
- `test/evm-test.el` — 146 ERT тестов
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
- `notes.md` — лог ошибок и решений
