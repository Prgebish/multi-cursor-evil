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

- [ ] Phase 7: Run at Cursors
  - [ ] 7.1 Run Normal
  - [ ] 7.2 Run Macro
  - [ ] 7.3 Run Ex

- [ ] Phase 8: Special Features
  - [ ] 8.1 Multiline mode
  - [ ] 8.2 Undo/Redo с восстановлением курсоров
  - [ ] 8.3 Reselect Last
  - [ ] 8.4 VM Registers

- [ ] Phase 9: Integration
  - [ ] 9.1 Интеграция с evil-surround

- [ ] Phase 10: Testing and Polish
  - [ ] 10.1 Написать тесты (ERT)
  - [ ] 10.2 Тестирование на реальных сценариях
  - [ ] 10.3 Оптимизация производительности
  - [ ] 10.4 Финальная документация

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
**Phase 4** — ЗАВЕРШЕНО. Реализовано:
- `evm-core.el` — структуры данных, overlays, базовые операции, restrict to region
- `evm.el` — entry point, keymaps, minor mode, команды
- Cursor mode: движение, i/a/I/A/o/O, x/X/r/~
- Extend mode: y/d/c/p/P, U/u/~, o (flip)
- Переключение режимов: Tab
- Navigation: ]/[ между курсорами, q/Q удаление
- Поиск: C-n (find word), n/N, \\A (select all)
- Cursor creation: C-Down/C-Up, M-click
- Restrict to region: visual selection + C-n, \\r (clear)

## Files
- `task_plan.md` — этот файл
- `architecture.md` — структура решения
- `notes.md` — лог ошибок и решений
