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

- [ ] Phase 8: Operators with Motions
  Реализация операторов d, c, y с motions напрямую (как в vim-visual-multi).
  Это основной способ работы — \\z остаётся как fallback для редких команд.

  - [ ] 8.1 Инфраструктура операторов
    - [ ] Парсер motions (single: h,j,k,l,w,e,b,$,^,0; double: i,a,f,t,g + char)
    - [ ] Функция `evm--run-operator-with-motion` — выполнить оператор на всех курсорах
    - [ ] Поддержка counts (d3w, 2dw)

  - [ ] 8.2 Delete operator (d)
    - [ ] `d` в cursor mode → ждёт motion, выполняет delete
    - [ ] `dw`, `de`, `db` — delete word motions
    - [ ] `d$`, `d^`, `d0` — delete to line boundaries
    - [ ] `dd` — delete line
    - [ ] `diw`, `daw` — delete inner/a word (text objects)
    - [ ] `di"`, `da"`, `di(`, `da(` — delete in/around quotes/parens
    - [ ] `D` — delete to end of line (уже есть как `d$`)

  - [ ] 8.3 Change operator (c)
    - [ ] `c` в cursor mode → delete + enter insert
    - [ ] `cw`, `ce`, `cb` — change word motions
    - [ ] `c$`, `c^`, `c0` — change to line boundaries
    - [ ] `cc` — change line
    - [ ] `ciw`, `caw` — change inner/a word
    - [ ] `ci"`, `ca"`, `ci(`, `ca(` — change in/around
    - [ ] `C` — change to end of line

  - [ ] 8.4 Yank operator (y)
    - [ ] `y` в cursor mode → ждёт motion, выполняет yank
    - [ ] `yw`, `ye`, `yb` — yank word motions
    - [ ] `y$`, `y^`, `y0` — yank to line boundaries
    - [ ] `yy` — yank line
    - [ ] `yiw`, `yaw` — yank inner/a word
    - [ ] `Y` — yank line (или yank to eol, настраиваемо)

  - [ ] 8.5 Дополнительные операторы
    - [ ] `J` — join lines (уже работает через run_normal)
    - [ ] `>`, `<` — indent/outdent с motion (>>. <<)
    - [ ] `gu`, `gU` — case change с motion
    - [ ] `g~` — toggle case с motion

- [ ] Phase 9: Special Features
  - [ ] 9.1 Multiline mode
  - [ ] 9.2 Undo/Redo с восстановлением курсоров
  - [ ] 9.3 Reselect Last
  - [ ] 9.4 VM Registers

- [ ] Phase 10: Integration
  - [ ] 10.1 Интеграция с evil-surround

- [ ] Phase 11: Testing and Polish
  - [ ] 11.1 Написать тесты (ERT)
  - [ ] 11.2 Тестирование на реальных сценариях
  - [ ] 11.3 Оптимизация производительности
  - [ ] 11.4 Финальная документация

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
**Phase 7** — ЗАВЕРШЕНО. **Phase 8** (Operators with Motions) — СЛЕДУЮЩАЯ.

Реализовано:
- `evm-core.el` — структуры данных, overlays, базовые операции, restrict to region
- `evm.el` — entry point, keymaps, minor mode, команды
- Cursor mode: движение, i/a/I/A/o/O, x/X/r/~
- Extend mode: y/d/c/p/P, U/u/~, o (flip)
- Переключение режимов: Tab
- Navigation: ]/[ между курсорами, q/Q удаление
- Поиск: C-n (find word), n/N, \\A (select all)
- Cursor creation: C-Down/C-Up, M-click
- Restrict to region: visual selection + C-n, \\r (clear)
- Run at cursors: \\z (normal), \\@ (macro), \\: (ex)

## Files
- `task_plan.md` — этот файл
- `architecture.md` — структура решения
- `notes.md` — лог ошибок и решений
