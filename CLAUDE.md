# CLAUDE.md

This file provides guidance to Claude Code when working with this repository.

## Project Overview

**evil-visual-multi (evim)** — пакет для Emacs, реализующий множественные курсоры с двумя режимами работы, интегрированный с evil-mode. Вдохновлён vim-visual-multi.

## Architecture

Пакет разделён на модули:
- `evim.el` — entry point, команды, keymaps
- `evim-core.el` — курсоры, overlays, базовые операции

Подробности в `architecture.md`.

## Verification Commands

После изменений кода **ОБЯЗАТЕЛЬНО** запускать тесты:

```bash
# Запуск всех тестов (ОБЯЗАТЕЛЬНО после любых изменений!)
make test

# Или напрямую:
emacs -Q --batch -L . -l ert -l test/evim-test.el -f ert-run-tests-batch-and-exit
```

**CRITICAL:** Все тесты должны проходить (`make test`) перед завершением работы над кодом. Не заканчивать редактирование пока тесты не зелёные!

**IMPORTANT:** После каждого успешного исправления бага или добавления фичи — ОБЯЗАТЕЛЬНО писать тесты, покрывающие новое поведение.

Дополнительные команды:

```bash
# Byte-compile (проверка синтаксиса)
make compile

# Загрузить в работающий Emacs (через emacs server)
emacsclient -e "(load-file \"evim.el\")"

# Перезагрузить модуль после изменений
emacsclient -e "(progn (unload-feature 'evim t) (unload-feature 'evim-core t) (require 'evim))"

# Интерактивное тестирование в реальном Emacs
make test-interactive
```

Предпочтительный способ разработки:
1. Редактировать код
2. `make test` — убедиться что тесты проходят
3. `emacsclient` — проверить в реальном окружении с evil

## Planning Files

При работе над задачами проверять:
- `task_plan.md` — фазы и текущий статус
- `architecture.md` — структура модулей
- `notes.md` — **ВСЕГДА ПРОВЕРЯТЬ** на историю ошибок и принятые решения

## Code Style

- Elisp code style: стандартный Emacs Lisp
- Префикс для всех публичных символов: `evim-`
- Приватные функции: `evim--` (два дефиса)
- Документировать все публичные функции
- **Все изменения должны быть изящными и структурными — никаких костылей.** Если решение выглядит как хак или workaround, нужно найти правильный архитектурный подход

## Reference

Оригинальный плагин vim-visual-multi находится в `vim-visual-multi/` для справки.

## User Environment

Конфигурация Emacs пользователя: `~/.emacs.d/init.el` — можно смотреть для понимания как загружается evim и какие другие пакеты установлены.
