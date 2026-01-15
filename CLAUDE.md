# CLAUDE.md

This file provides guidance to Claude Code when working with this repository.

## Project Overview

**evil-visual-multi (evm)** — пакет для Emacs, реализующий множественные курсоры с двумя режимами работы, интегрированный с evil-mode. Вдохновлён vim-visual-multi.

## Architecture

Пакет разделён на модули:
- `evm.el` — entry point
- `evm-core.el` — курсоры, overlays, базовые операции
- `evm-commands.el` — alignment, case conversion, replace
- `evm-navigation.el` — создание курсоров, навигация
- `evm-registers.el` — VM Registers
- `evm-run.el` — Run Normal/Macro/Ex
- `evm-undo.el` — Undo/Redo с восстановлением
- `evm-integration.el` — интеграция с evil-surround

Подробности в `architecture.md`.

## Verification Commands

После изменений кода запускать:

```bash
# Проверка синтаксиса elisp (batch mode)
emacs -Q --batch -f batch-byte-compile *.el

# Запуск тестов (когда будут)
emacs -Q --batch -l ert -l test/evm-test.el -f ert-run-tests-batch-and-exit

# Загрузить в работающий Emacs (через emacs server)
emacsclient -e "(load-file \"evm.el\")"

# Перезагрузить модуль после изменений
emacsclient -e "(progn (unload-feature 'evm t) (require 'evm))"

# Проверить что пакет загружен
emacsclient -e "(featurep 'evm)"
```

**IMPORTANT:** Всегда запускать верификацию после изменений кода.

Предпочтительный способ — через `emacsclient`, так как тестирование происходит в реальном окружении с evil и другими пакетами.

## Planning Files

При работе над задачами проверять:
- `task_plan.md` — фазы и текущий статус
- `architecture.md` — структура модулей
- `notes.md` — **ВСЕГДА ПРОВЕРЯТЬ** на историю ошибок и принятые решения

## Code Style

- Elisp code style: стандартный Emacs Lisp
- Префикс для всех публичных символов: `evm-`
- Приватные функции: `evm--` (два дефиса)
- Документировать все публичные функции

## Reference

Оригинальный плагин vim-visual-multi находится в `vim-visual-multi/` для справки.
