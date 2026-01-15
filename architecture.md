# Architecture: evil-visual-multi (evm)

## Overview
Пакет для Emacs, реализующий множественные курсоры с двумя режимами работы (cursor/extend), интегрированный с evil-mode.

## File Structure
```
evil-visual-multi/
├── evm.el                 # Главный файл, entry point
├── evm-core.el            # Структуры данных, курсоры, overlays
├── evm-commands.el        # Команды (alignment, case conversion, etc.)
├── evm-navigation.el      # Навигация между курсорами
├── evm-registers.el       # VM Registers
├── evm-run.el             # Run Normal/Macro/Ex
├── evm-undo.el            # Undo/Redo с восстановлением курсоров
├── evm-integration.el     # Интеграция с evil-surround
└── test/
    └── evm-test.el        # ERT тесты
```

## Modules

### Module 1: evm-core
- Purpose: Базовые структуры данных и работа с курсорами
- Dependencies: evil, cl-lib
- Interface:
  - `evm-cursor` — структура курсора
  - `evm-region` — структура региона (для extend mode)
  - `evm-create-cursor (pos)` — создать курсор в позиции
  - `evm-delete-cursor (cursor)` — удалить курсор
  - `evm-get-all-cursors ()` — получить все курсоры
  - `evm-cursor-mode-p ()` — проверка режима cursor
  - `evm-extend-mode-p ()` — проверка режима extend
  - `evm-toggle-mode ()` — переключить режим

### Module 2: evm-commands
- Purpose: Продвинутые команды редактирования
- Dependencies: evm-core
- Interface:
  - `evm-align ()` — выравнивание курсоров
  - `evm-case-convert (type)` — конвертация регистра
  - `evm-replace-in-regions (from to)` — замена в регионах

### Module 3: evm-navigation
- Purpose: Навигация и создание курсоров
- Dependencies: evm-core
- Interface:
  - `evm-find-word ()` — найти слово под курсором (C-n)
  - `evm-find-next ()` — следующее вхождение (n)
  - `evm-find-prev ()` — предыдущее вхождение (N)
  - `evm-goto-next ()` — к следующему курсору (])
  - `evm-goto-prev ()` — к предыдущему курсору ([)
  - `evm-skip ()` — пропустить текущее (q)
  - `evm-remove-cursor ()` — удалить курсор (Q)
  - `evm-add-cursor-down ()` — курсор вниз (C-Down)
  - `evm-add-cursor-up ()` — курсор вверх (C-Up)
  - `evm-add-cursor-at-pos ()` — курсор в текущей позиции
  - `evm-select-all ()` — все вхождения
  - `evm-restrict-to-region ()` — ограничить поиск регионом

### Module 4: evm-registers
- Purpose: Собственные регистры для yank/paste
- Dependencies: evm-core
- Interface:
  - `evm-register` — структура регистра (список строк)
  - `evm-yank ()` — копировать в VM регистр
  - `evm-paste ()` — вставить из VM регистра
  - `evm-delete ()` — удалить в VM регистр

### Module 5: evm-run
- Purpose: Выполнение команд на всех курсорах
- Dependencies: evm-core, evil
- Interface:
  - `evm-run-normal (cmd)` — выполнить normal команду
  - `evm-run-macro (register)` — выполнить макрос
  - `evm-run-ex (cmd)` — выполнить Ex команду

### Module 6: evm-undo
- Purpose: Undo/Redo с восстановлением позиций курсоров
- Dependencies: evm-core
- Interface:
  - `evm-undo ()` — откат с восстановлением курсоров
  - `evm-redo ()` — повтор с восстановлением курсоров
  - `evm-save-state ()` — сохранить состояние перед изменением

### Module 7: evm-integration
- Purpose: Интеграция с внешними пакетами
- Dependencies: evm-core, evil-surround (optional)
- Interface:
  - `evm-surround (char)` — обернуть все регионы

## Data Structures

### evm-cursor
```elisp
(cl-defstruct evm-cursor
  id          ; уникальный идентификатор
  overlay     ; overlay для отображения
  point       ; позиция в буфере
  leader-p)   ; t если это курсор-лидер
```

### evm-region (для extend mode)
```elisp
(cl-defstruct evm-region
  id          ; уникальный идентификатор
  overlay     ; overlay для отображения
  beg         ; начало региона
  end         ; конец региона
  cursor)     ; связанный курсор
```

### evm-state (глобальное состояние)
```elisp
(cl-defstruct evm-state
  active-p          ; активен ли режим
  mode              ; 'cursor или 'extend
  cursors           ; список курсоров
  regions           ; список регионов (для extend)
  leader            ; курсор-лидер
  patterns          ; список паттернов для поиска
  registers         ; hash-table регистров
  undo-history      ; история для undo
  multiline-p       ; разрешено ли пересекать строки
  last-cursors)     ; последние позиции (для reselect)
```

### evm-register
```elisp
(cl-defstruct evm-register
  name        ; имя регистра (символ)
  contents)   ; список строк (по одной на курсор)
```

## Key Bindings (предварительно)

### Global (всегда активны)
| Key | Function |
|-----|----------|
| C-n | evm-find-word |
| C-Down | evm-add-cursor-down |
| C-Up | evm-add-cursor-up |
| M-click | evm-add-cursor-at-pos |

### Buffer (когда evm активен)
| Key | Function |
|-----|----------|
| n | evm-find-next |
| N | evm-find-prev |
| ] | evm-goto-next |
| [ | evm-goto-prev |
| q | evm-skip |
| Q | evm-remove-cursor |
| Tab | evm-toggle-mode |
| Esc | evm-exit |
| M | evm-toggle-multiline |

### Commands (с префиксом, например \\)
| Key | Function |
|-----|----------|
| \\a | evm-align |
| \\C | evm-case-convert |
| \\z | evm-run-normal |
| \\@ | evm-run-macro |
| \\x | evm-run-ex |
| \\A | evm-select-all |
| \\gS | evm-reselect-last |

## Faces (цвета)

```elisp
(defface evm-cursor-face
  '((t :background "deep sky blue"))
  "Face for cursors in cursor mode.")

(defface evm-region-face
  '((t :background "dark green"))
  "Face for regions in extend mode.")

(defface evm-leader-face
  '((t :background "orange red"))
  "Face for the leader cursor.")
```

## Key Design Decisions
- Используем overlays для отображения курсоров (стандартный подход в Emacs)
- Два режима как отдельные состояния, не как evil states
- Курсор-лидер визуально выделен отдельным face
- VM Registers реализованы как hash-table со списками строк
- Undo реализован через сохранение снапшотов состояния
