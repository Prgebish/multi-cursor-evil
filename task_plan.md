# Task Plan: evil-visual-multi — Multiple Cursors for Emacs/Evil

## Goal
Создать пакет для Emacs с множественными курсорами, вдохновлённый vim-visual-multi, с полной интеграцией в evil-mode.

## Phases

- [ ] Phase 1: Research
  - [ ] 1.1 Изучить существующие решения (evil-mc, multiple-cursors.el)
  - [ ] 1.2 Изучить как evil-mc реализует курсоры и overlays
  - [ ] 1.3 Понять как работает undo/redo в Emacs для интеграции
  - [ ] 1.4 Изучить API evil-surround для интеграции

- [ ] Phase 2: Design
  - [ ] 2.1 Спроектировать структуру данных для курсоров и регионов
  - [ ] 2.2 Спроектировать VM Registers
  - [ ] 2.3 Спроектировать систему режимов (cursor/extend)
  - [ ] 2.4 Определить keybindings
  - [ ] 2.5 Спроектировать визуальное отображение (faces, overlays)

- [ ] Phase 3: Core Implementation
  - [ ] 3.1 Базовая структура пакета (evm.el — evil-visual-multi)
  - [ ] 3.2 Система курсоров и overlays
  - [ ] 3.3 Cursor mode — базовые операции
  - [ ] 3.4 Extend mode — базовые операции
  - [ ] 3.5 Переключение между режимами

- [ ] Phase 4: Cursor Creation
  - [ ] 4.1 Find Word (C-n)
  - [ ] 4.2 Add Cursor Down/Up (C-Down/C-Up)
  - [ ] 4.3 Add Cursor At Pos (клавиша + M-click)
  - [ ] 4.4 Select All
  - [ ] 4.5 Restrict to region

- [ ] Phase 5: Navigation
  - [ ] 5.1 n/N — следующее/предыдущее вхождение
  - [ ] 5.2 ]/[ — навигация между курсорами
  - [ ] 5.3 q — пропустить текущее
  - [ ] 5.4 Q — удалить курсор
  - [ ] 5.5 Курсор-"лидер" с отдельным face

- [ ] Phase 6: Advanced Commands
  - [ ] 6.1 Alignment
  - [ ] 6.2 Case conversion
  - [ ] 6.3 Replace in regions

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
**Phase 1** — Готовимся к исследованию существующих решений

## Files
- `task_plan.md` — этот файл
- `architecture.md` — структура решения
- `notes.md` — лог ошибок и решений
