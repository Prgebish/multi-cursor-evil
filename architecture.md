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

### evm-region (основная единица — объединяет курсор и регион)
```elisp
(cl-defstruct evm-region
  ;; Идентификация
  id              ; уникальный ID (integer, автоинкремент)
  index           ; позиция в списке регионов (обновляется при сортировке)

  ;; Позиционирование (в cursor mode: beg = end)
  beg             ; начало региона (marker)
  end             ; конец региона (marker)

  ;; Визуализация
  overlay         ; overlay для отображения региона
  cursor-overlay  ; overlay для позиции курсора (внутри региона)

  ;; Состояние
  dir             ; направление: 0 = курсор в начале, 1 = курсор в конце
  anchor          ; точка привязки (marker) — не меняется при расширении
  vcol            ; вертикальная колонка для j/k навигации

  ;; Содержимое
  txt             ; текст региона (обновляется после изменений)
  pattern)        ; паттерн поиска, связанный с регионом
```

**Примечания:**
- Используем markers вместо integers для позиций — они автоматически обновляются при изменении буфера
- В cursor mode: `beg = end = anchor`, регион пуст
- В extend mode: `anchor` фиксирован, `beg` или `end` двигается в зависимости от `dir`

### evm-state (buffer-local глобальное состояние)
```elisp
(cl-defstruct evm-state
  ;; Активация
  active-p            ; активен ли evm в буфере
  mode                ; 'cursor или 'extend

  ;; Регионы
  regions             ; список evm-region, отсортированный по позиции
  leader-id           ; ID текущего лидера
  id-counter          ; счётчик для генерации ID

  ;; Поиск
  patterns            ; список паттернов для поиска (strings)
  search-direction    ; 1 = вперёд, -1 = назад

  ;; Опции
  multiline-p         ; разрешены ли многострочные регионы
  whole-word-p        ; искать целые слова
  case-fold-p         ; игнорировать регистр при поиске

  ;; История
  undo-snapshots      ; список снапшотов для undo
  last-regions        ; сохранённые позиции для reselect

  ;; VM Registers
  registers           ; hash-table: char -> список строк

  ;; Кеширование
  column-positions)   ; hash-table для быстрого доступа к колонкам
```

### Undo Snapshot
```elisp
(cl-defstruct evm-snapshot
  regions-data      ; список (id beg-pos end-pos anchor-pos dir)
  leader-id         ; ID лидера на момент снапшота
  mode              ; режим на момент снапшота
  buffer-tick)      ; buffer-modified-tick для валидации
```

### VM Register Entry
```elisp
;; VM Registers хранятся в hash-table:
;; key: character (например ?a, ?b, ?\")
;; value: список строк (по одной на каждый регион, в порядке регионов)
;;
;; Пример:
;; (gethash ?a evm-registers) => ("foo" "bar" "baz")
;; Регион 0 содержал "foo", регион 1 — "bar", регион 2 — "baz"
```

### Пример работы структур

```elisp
;; Cursor mode: 3 курсора на слове "foo"
;;
;; До:  foo bar foo baz foo
;;       ^      ^       ^    (3 курсора)
;;
;; После evm-find-word на первом "foo":
;; regions = [
;;   (evm-region :id 1 :beg #<marker 1> :end #<marker 1> :anchor #<marker 1>)
;;   (evm-region :id 2 :beg #<marker 9> :end #<marker 9> :anchor #<marker 9>)
;;   (evm-region :id 3 :beg #<marker 17> :end #<marker 17> :anchor #<marker 17>)
;; ]

;; Extend mode: после Tab (переключения в extend)
;;
;; До:  [foo] bar [foo] baz [foo]
;;        ^        ^         ^    (3 региона)
;;
;; regions = [
;;   (evm-region :id 1 :beg #<marker 1> :end #<marker 3> ...)
;;   (evm-region :id 2 :beg #<marker 9> :end #<marker 11> ...)
;;   (evm-region :id 3 :beg #<marker 17> :end #<marker 19> ...)
;; ]
```

## VM Registers (детальный дизайн)

### Концепция
VM Registers — отдельное пространство регистров для операций с множественными курсорами.
Отличие от стандартных evil/Emacs регистров: хранят **список строк** (по одной на регион),
а не одну строку.

### Хранение
```elisp
;; В evm-state:
registers  ; hash-table, создаётся при активации evm

;; Инициализация:
(setf (evm-state-registers state)
      (make-hash-table :test 'eq))  ; ключи — символы
```

### Операции

#### evm-yank (y в VM)
```elisp
(defun evm-yank (&optional register)
  "Yank содержимое всех регионов в VM регистр.
Если REGISTER не указан, используется регистр по умолчанию (\\\")."
  ;; 1. Собрать текст из всех регионов (в порядке позиций)
  ;; 2. Сохранить как список в register
  ;; 3. Также сохранить в kill-ring первый элемент (для совместимости)
  )

;; Пример:
;; Регионы: "foo", "bar", "baz"
;; После (evm-yank ?a):
;; (gethash ?a registers) => ("foo" "bar" "baz")
```

#### evm-delete (d в VM)
```elisp
(defun evm-delete (&optional register)
  "Удалить содержимое всех регионов, сохранив в VM регистр."
  ;; 1. Сохранить содержимое как evm-yank
  ;; 2. Удалить текст из всех регионов
  ;; 3. Переключить в cursor mode (регионы стали пустыми)
  )
```

#### evm-paste (p/P в VM)
```elisp
(defun evm-paste (&optional register after)
  "Вставить из VM регистра.
AFTER — если t, вставить после курсора (p), иначе до (P).

Поведение зависит от количества элементов в регистре:
- Если кол-во элементов = кол-во регионов: вставить 1-к-1
- Если 1 элемент: вставить один и тот же текст во все позиции
- Иначе: вставить с cycling (1->1, 2->2, 3->1, 4->2...)"
  )

;; Пример 1: 3 региона, 3 элемента в регистре
;; Регистр: ("foo" "bar" "baz")
;; Результат: первый регион получает "foo", второй "bar", третий "baz"

;; Пример 2: 3 региона, 1 элемент
;; Регистр: ("text")
;; Результат: все 3 региона получают "text"

;; Пример 3: 3 региона, 2 элемента
;; Регистр: ("A" "B")
;; Результат: регион 1 -> "A", регион 2 -> "B", регион 3 -> "A"
```

#### evm-change (c в VM)
```elisp
(defun evm-change (&optional register)
  "Удалить содержимое регионов и войти в insert mode."
  ;; 1. Сохранить в регистр
  ;; 2. Удалить текст
  ;; 3. Войти в evil-insert-state
  )
```

### Специальные регистры
```elisp
;; \"  — регистр по умолчанию (автоматически используется)
;; 0   — последний yank (без delete)
;; -   — последний small delete (< 1 строки)
;; 1-9 — не используем (слишком сложно для множественных курсоров)
;; a-z — именованные регистры
;; A-Z — append к именованным регистрам
```

### Интеграция с evil registers
```elisp
;; При выходе из evm:
;; - Регистр \" копируется в evil \"
;; - Это позволяет paste после выхода из evm

(defun evm--sync-to-evil-registers ()
  "Синхронизировать VM регистр \" в evil."
  (let ((contents (gethash ?\" (evm-state-registers evm--state))))
    (when contents
      ;; Объединить все строки для evil
      (evil-set-register ?\" (string-join contents "\n")))))
```

## Mode System (cursor/extend)

### Обзор режимов

```
┌─────────────────────────────────────────────────────────────────┐
│                         EVM INACTIVE                             │
│  (обычный режим evil, evm не активен)                           │
└─────────────────────────────────────────────────────────────────┘
         │                                      ▲
         │ C-n / C-Down / C-Up / M-click        │ Esc (exit)
         ▼                                      │
┌─────────────────────────────────────────────────────────────────┐
│                         CURSOR MODE                              │
│  - Регионы пусты (beg = end)                                    │
│  - Отображаются как точки/блоки                                  │
│  - Можно: перемещать, добавлять, удалять курсоры                │
│  - Ввод текста: одновременная вставка во все позиции            │
└─────────────────────────────────────────────────────────────────┘
         │                                      ▲
         │ Tab (toggle)                         │ Tab (toggle)
         │ или визуальный выбор (v/V)           │ или после delete/change
         ▼                                      │
┌─────────────────────────────────────────────────────────────────┐
│                         EXTEND MODE                              │
│  - Регионы имеют ширину (beg < end)                             │
│  - Отображаются как выделения                                    │
│  - Можно: расширять, сужать, трансформировать текст             │
│  - Ввод текста: заменяет выделенное                              │
└─────────────────────────────────────────────────────────────────┘
```

### Cursor Mode

**Состояние:**
- `(evm-state-mode state)` = `'cursor`
- Для каждого региона: `beg = end = anchor`
- Overlays показывают только позицию курсора

**Доступные операции:**
```elisp
;; Перемещение (применяется ко всем курсорам)
h, j, k, l    ; базовые движения
w, b, e       ; по словам
0, ^, $       ; начало/конец строки
gg, G         ; начало/конец буфера
f, t, F, T    ; find char
;, ,          ; повтор find

;; Создание курсоров
n, N          ; следующее/предыдущее вхождение паттерна
C-n           ; добавить слово под курсором
C-Down/C-Up   ; курсор вниз/вверх
\\A           ; все вхождения

;; Навигация между курсорами
], [          ; к следующему/предыдущему курсору

;; Удаление курсоров
q             ; пропустить текущий, перейти к следующему
Q             ; удалить текущий курсор

;; Редактирование
i, a, I, A    ; войти в insert mode
o, O          ; новая строка
x, X          ; удалить символ
r             ; replace char
~             ; toggle case

;; Переключение
Tab           ; перейти в extend mode
v             ; выделить от курсора (visual char)
```

### Extend Mode

**Состояние:**
- `(evm-state-mode state)` = `'extend`
- Для каждого региона: `beg <= end`, `anchor` зафиксирован
- Overlays показывают выделение и позицию курсора внутри

**Доступные операции:**
```elisp
;; Расширение/сужение (двигается активный конец)
h, j, k, l    ; посимвольно/построчно
w, b, e       ; по словам
0, ^, $       ; до начала/конца строки
gg, G         ; до начала/конца буфера

;; Действия над регионами
y             ; yank в VM регистр
d             ; delete в VM регистр, -> cursor mode
c             ; change: delete + insert
p, P          ; paste (заменяет содержимое)
>>, <<        ; indent/outdent
u, U          ; lowercase/uppercase
~             ; toggle case

;; Трансформации
\\a           ; align
\\C           ; case conversion menu

;; Переключение
Tab           ; вернуться в cursor mode (сбросить выделения)
o             ; flip direction (поменять anchor и cursor местами)
```

### Переходы между режимами

```elisp
(defun evm-toggle-mode ()
  "Переключить между cursor и extend mode."
  (if (evm-cursor-mode-p)
      (evm--enter-extend-mode)
    (evm--enter-cursor-mode)))

(defun evm--enter-extend-mode ()
  "Перейти в extend mode."
  ;; 1. Для каждого региона: расширить до слова/паттерна под курсором
  ;;    или просто установить end = beg + 1 (один символ)
  ;; 2. Обновить overlays
  ;; 3. Установить mode = 'extend
  (setf (evm-state-mode evm--state) 'extend)
  (dolist (r (evm-state-regions evm--state))
    (evm--region-extend-to-pattern r))
  (evm--update-all-overlays))

(defun evm--enter-cursor-mode ()
  "Перейти в cursor mode."
  ;; 1. Для каждого региона: схлопнуть до позиции курсора
  ;;    beg = end = (если dir=1 то end, иначе beg)
  ;; 2. Обновить overlays
  ;; 3. Установить mode = 'cursor
  (setf (evm-state-mode evm--state) 'cursor)
  (dolist (r (evm-state-regions evm--state))
    (evm--region-collapse-to-cursor r))
  (evm--update-all-overlays))
```

### Поведение при редактировании

**Cursor Mode + Insert:**
```elisp
;; При нажатии 'i' в cursor mode:
;; 1. Сохранить снапшот для undo
;; 2. Войти в evil-insert-state
;; 3. Все набираемые символы вставляются во ВСЕ позиции курсоров
;; 4. При выходе из insert (Esc): вернуться в cursor mode

(defun evm--replicate-insert (char)
  "Вставить CHAR во все позиции курсоров."
  ;; Вставляем с конца буфера, чтобы не сдвигать позиции
  (let ((regions (reverse (evm-state-regions evm--state))))
    (dolist (r regions)
      (goto-char (marker-position (evm-region-end r)))
      (insert char))))
```

**Extend Mode + Delete/Change:**
```elisp
;; При нажатии 'd' в extend mode:
;; 1. Сохранить содержимое в VM регистр
;; 2. Удалить текст всех регионов (с конца буфера)
;; 3. Автоматически перейти в cursor mode

;; При нажатии 'c' в extend mode:
;; 1. Как 'd', но затем войти в insert mode
```

### Интеграция с Evil States

```elisp
;; evm НЕ создаёт новый evil-state
;; Вместо этого работает как "надстройка" над существующими:

;; evil-normal-state + evm = перемещение курсоров
;; evil-insert-state + evm = синхронный ввод
;; evil-visual-state + evm = не используется (заменён extend mode)

;; При входе в evm:
(evil-normal-state)  ; принудительно выйти из других состояний

;; Keymap приоритет:
;; evm-mode-map > evil-normal-state-map > global-map
```

## Key Bindings (финальный дизайн)

### Keymaps структура

```elisp
;; 1. evm-global-map — привязки для активации evm (всегда активны)
;; 2. evm-mode-map — базовые привязки когда evm активен
;; 3. evm-cursor-map — дополнительные привязки в cursor mode
;; 4. evm-extend-map — дополнительные привязки в extend mode

;; Приоритет при активном evm:
;; evm-cursor-map/evm-extend-map > evm-mode-map > evil-normal-state-map
```

### Global Bindings (evm-global-map)
Привязки для активации evm (добавляются в evil-normal-state-map).

| Key | Function | Описание |
|-----|----------|----------|
| `C-n` | `evm-find-word` | Выделить слово под курсором, добавить следующее |
| `C-Down` | `evm-add-cursor-down` | Добавить курсор на строку ниже |
| `C-Up` | `evm-add-cursor-up` | Добавить курсор на строку выше |
| `M-<mouse-1>` | `evm-add-cursor-at-click` | Добавить курсор по клику мыши |

### Common Bindings (evm-mode-map)
Активны в обоих режимах (cursor и extend).

| Key | Function | Описание |
|-----|----------|----------|
| `Esc` | `evm-exit` | Выйти из evm |
| `Tab` | `evm-toggle-mode` | Переключить cursor/extend |
| `n` | `evm-find-next` | Следующее вхождение паттерна |
| `N` | `evm-find-prev` | Предыдущее вхождение паттерна |
| `]` | `evm-goto-next` | К следующему курсору (лидер) |
| `[` | `evm-goto-prev` | К предыдущему курсору (лидер) |
| `q` | `evm-skip-current` | Пропустить текущий, перейти дальше |
| `Q` | `evm-remove-current` | Удалить текущий курсор |
| `M` | `evm-toggle-multiline` | Включить/выключить multiline |
| `u` | `evm-undo` | Отменить последнее действие |
| `C-r` | `evm-redo` | Повторить отменённое |

#### Movement (в обоих режимах)
Evil движения работают, но применяются ко всем курсорам/регионам.

| Key | Действие |
|-----|----------|
| `h/j/k/l` | Базовые движения |
| `w/b/e/W/B/E` | По словам |
| `0/^/$` | Начало/первый символ/конец строки |
| `gg/G` | Начало/конец буфера |
| `f/t/F/T` + char | Find character |
| `;/,` | Повтор find |
| `%` | Matching bracket |

### Cursor Mode Bindings (evm-cursor-map)

| Key | Function | Описание |
|-----|----------|----------|
| `i` | `evm-insert` | Insert перед курсором |
| `a` | `evm-append` | Insert после курсора |
| `I` | `evm-insert-bol` | Insert в начале строки |
| `A` | `evm-append-eol` | Insert в конце строки |
| `o` | `evm-open-below` | Новая строка ниже + insert |
| `O` | `evm-open-above` | Новая строка выше + insert |
| `x` | `evm-delete-char` | Удалить символ под курсором |
| `X` | `evm-delete-char-before` | Удалить символ перед курсором |
| `r` + char | `evm-replace-char` | Заменить символ |
| `~` | `evm-toggle-case-char` | Toggle case символа |
| `v` | `evm-enter-extend` | Войти в extend mode |
| `C-n` | `evm-add-next-word` | Добавить следующее вхождение |
| `C-Down` | `evm-add-cursor-down` | Курсор вниз |
| `C-Up` | `evm-add-cursor-up` | Курсор вверх |

### Extend Mode Bindings (evm-extend-map)

| Key | Function | Описание |
|-----|----------|----------|
| `y` | `evm-yank` | Yank регионов в VM регистр |
| `d` | `evm-delete` | Delete регионов в VM регистр |
| `c` | `evm-change` | Delete + enter insert |
| `p` | `evm-paste-after` | Paste после |
| `P` | `evm-paste-before` | Paste до |
| `s` | `evm-substitute` | Как `c` (синоним) |
| `>` | `evm-indent` | Indent регионов |
| `<` | `evm-outdent` | Outdent регионов |
| `U` | `evm-upcase` | UPPERCASE регионов |
| `u` | `evm-downcase` | lowercase регионов |
| `~` | `evm-toggle-case` | Toggle case регионов |
| `o` | `evm-flip-direction` | Flip cursor/anchor |
| `C-n` | `evm-add-next-occurrence` | Добавить следующее вхождение |

### Prefix Commands (\\)
Специальные команды с префиксом `\`.

| Key | Function | Описание |
|-----|----------|----------|
| `\a` | `evm-align` | Выровнять курсоры |
| `\A` | `evm-select-all` | Выбрать все вхождения |
| `\c` | `evm-case-menu` | Меню конвертации регистра |
| `\z` | `evm-run-normal` | Выполнить normal команду |
| `\@` + reg | `evm-run-macro` | Выполнить макрос из регистра |
| `\:` | `evm-run-ex` | Выполнить Ex команду |
| `\s` | `evm-surround` | Обернуть регионы (evil-surround) |
| `\r` | `evm-replace-pattern` | Заменить текст во всех регионах |
| `\gS` | `evm-reselect-last` | Восстановить последние курсоры |

### Register Access
Для доступа к именованным регистрам используется `"` + register перед командой.

```elisp
;; Примеры:
"ay   ; yank в регистр a
"ap   ; paste из регистра a
"Ad   ; delete и append в регистр A
```

### Insert Mode Bindings
Когда evm активен и мы в insert mode.

| Key | Function | Описание |
|-----|----------|----------|
| `Esc` | `evm-exit-insert` | Выйти из insert, остаться в evm |
| Любой символ | `evm--replicate-char` | Вставить во все позиции |
| `Backspace` | `evm--replicate-backspace` | Удалить во всех позициях |
| `C-w` | `evm--replicate-kill-word` | Удалить слово во всех позициях |

### Mouse Bindings

| Key | Function | Описание |
|-----|----------|----------|
| `M-<mouse-1>` | `evm-add-cursor-at-click` | Добавить курсор по клику |
| `M-<drag-mouse-1>` | `evm-add-region-by-drag` | Выделить регион drag |

## Visual Display (Faces & Overlays)

### Faces (цветовая схема)

```elisp
;; Основные faces
(defface evm-cursor-face
  '((((class color) (background dark))
     :background "#3B82F6" :foreground "white")  ; Blue-500
    (((class color) (background light))
     :background "#2563EB" :foreground "white")) ; Blue-600
  "Face for cursors in cursor mode.")

(defface evm-region-face
  '((((class color) (background dark))
     :background "#166534")  ; Green-800
    (((class color) (background light))
     :background "#BBF7D0")) ; Green-200
  "Face for selected regions in extend mode.")

(defface evm-leader-cursor-face
  '((((class color) (background dark))
     :background "#F97316" :foreground "black")  ; Orange-500
    (((class color) (background light))
     :background "#EA580C" :foreground "white")) ; Orange-600
  "Face for the leader cursor position.")

(defface evm-leader-region-face
  '((((class color) (background dark))
     :background "#854D0E")  ; Yellow-800
    (((class color) (background light))
     :background "#FEF08A")) ; Yellow-200
  "Face for the leader region in extend mode.")

;; Дополнительные faces для UI
(defface evm-mode-line-face
  '((t :foreground "#10B981" :weight bold))  ; Emerald-500
  "Face for evm indicator in mode-line.")

(defface evm-match-face
  '((((class color) (background dark))
     :background "#374151" :underline t)  ; Gray-700
    (((class color) (background light))
     :background "#E5E7EB" :underline t)) ; Gray-200
  "Face for potential matches (pattern preview).")
```

### Overlay System

#### Overlay Types

```elisp
;; Каждый регион имеет до 2 overlays:
;; 1. region-overlay — для выделения области (только в extend mode)
;; 2. cursor-overlay — для позиции курсора (всегда)

;; Свойства overlay:
'evm-region    ; тип: 'region или 'cursor
'evm-id        ; ID связанного региона
'evm-leader-p  ; t если это лидер
```

#### Cursor Mode Overlay

```elisp
(defun evm--create-cursor-overlay (region)
  "Create cursor overlay for REGION."
  (let* ((pos (marker-position (evm-region-beg region)))
         (ov (make-overlay pos (1+ pos) nil t nil)))
    ;; Свойства
    (overlay-put ov 'evm-region 'cursor)
    (overlay-put ov 'evm-id (evm-region-id region))
    (overlay-put ov 'priority 100)  ; высокий приоритет

    ;; Face зависит от того, лидер это или нет
    (overlay-put ov 'face
                 (if (evm--leader-p region)
                     'evm-leader-cursor-face
                   'evm-cursor-face))

    ;; Для пустой строки или конца файла — показать как вертикальную черту
    (when (or (eolp) (= pos (point-max)))
      (overlay-put ov 'before-string
                   (propertize "|" 'face (overlay-get ov 'face))))

    (setf (evm-region-cursor-overlay region) ov)))
```

#### Extend Mode Overlays

```elisp
(defun evm--create-region-overlay (region)
  "Create region overlay for REGION in extend mode."
  (let* ((beg (marker-position (evm-region-beg region)))
         (end (marker-position (evm-region-end region)))
         (ov (make-overlay beg end nil t nil)))
    ;; Свойства региона
    (overlay-put ov 'evm-region 'region)
    (overlay-put ov 'evm-id (evm-region-id region))
    (overlay-put ov 'priority 90)

    ;; Face
    (overlay-put ov 'face
                 (if (evm--leader-p region)
                     'evm-leader-region-face
                   'evm-region-face))

    (setf (evm-region-overlay region) ov))

  ;; Также создаём cursor overlay внутри региона
  (evm--create-cursor-in-region-overlay region))

(defun evm--create-cursor-in-region-overlay (region)
  "Create cursor overlay within region (показывает активный конец)."
  (let* ((cursor-pos (if (= (evm-region-dir region) 1)
                         (marker-position (evm-region-end region))
                       (marker-position (evm-region-beg region))))
         (ov (make-overlay cursor-pos (1+ cursor-pos) nil t nil)))
    (overlay-put ov 'evm-region 'cursor)
    (overlay-put ov 'evm-id (evm-region-id region))
    (overlay-put ov 'priority 110)  ; выше чем region
    (overlay-put ov 'face
                 (if (evm--leader-p region)
                     'evm-leader-cursor-face
                   'evm-cursor-face))
    (setf (evm-region-cursor-overlay region) ov)))
```

#### Overlay Management

```elisp
(defun evm--update-all-overlays ()
  "Update all overlays based on current state."
  ;; 1. Удалить все старые overlays
  (evm--remove-all-overlays)

  ;; 2. Создать новые в зависимости от режима
  (dolist (region (evm-state-regions evm--state))
    (if (eq (evm-state-mode evm--state) 'extend)
        (evm--create-region-overlay region)
      (evm--create-cursor-overlay region))))

(defun evm--remove-all-overlays ()
  "Remove all evm overlays from buffer."
  (dolist (region (evm-state-regions evm--state))
    (when (evm-region-overlay region)
      (delete-overlay (evm-region-overlay region))
      (setf (evm-region-overlay region) nil))
    (when (evm-region-cursor-overlay region)
      (delete-overlay (evm-region-cursor-overlay region))
      (setf (evm-region-cursor-overlay region) nil))))

(defun evm--update-leader-overlays ()
  "Update overlays to reflect new leader."
  ;; Обновить face для всех overlays
  (dolist (region (evm-state-regions evm--state))
    (let ((is-leader (evm--leader-p region)))
      (when-let ((ov (evm-region-cursor-overlay region)))
        (overlay-put ov 'face
                     (if is-leader
                         'evm-leader-cursor-face
                       'evm-cursor-face)))
      (when-let ((ov (evm-region-overlay region)))
        (overlay-put ov 'face
                     (if is-leader
                         'evm-leader-region-face
                       'evm-region-face))))))
```

### Mode-Line Indicator

```elisp
(defun evm--mode-line-indicator ()
  "Return mode-line indicator string."
  (when (evm-state-active-p evm--state)
    (let* ((mode (evm-state-mode evm--state))
           (count (length (evm-state-regions evm--state)))
           (leader-idx (1+ (evm--leader-index))))
      (propertize
       (format " EVM[%s %d/%d]"
               (if (eq mode 'cursor) "C" "E")
               leader-idx
               count)
       'face 'evm-mode-line-face))))

;; Добавить в mode-line-format:
;; (:eval (evm--mode-line-indicator))
```

### Visual Feedback

```elisp
;; Показ потенциальных совпадений (при поиске)
(defvar evm--match-overlays nil
  "List of temporary overlays for match preview.")

(defun evm--show-match-preview (pattern)
  "Show preview of all matches for PATTERN."
  (evm--hide-match-preview)
  (save-excursion
    (goto-char (point-min))
    (while (re-search-forward pattern nil t)
      (let ((ov (make-overlay (match-beginning 0) (match-end 0))))
        (overlay-put ov 'face 'evm-match-face)
        (overlay-put ov 'evm-match t)
        (push ov evm--match-overlays)))))

(defun evm--hide-match-preview ()
  "Hide match preview overlays."
  (mapc #'delete-overlay evm--match-overlays)
  (setq evm--match-overlays nil))
```

### Cursor Blinking (опционально)

```elisp
(defcustom evm-cursor-blink nil
  "If non-nil, blink cursor overlays."
  :type 'boolean
  :group 'evm)

(defvar evm--blink-timer nil)

(defun evm--start-cursor-blink ()
  "Start blinking cursor overlays."
  (when evm-cursor-blink
    (setq evm--blink-timer
          (run-with-timer 0.5 0.5 #'evm--toggle-cursor-visibility))))

(defun evm--stop-cursor-blink ()
  "Stop blinking."
  (when evm--blink-timer
    (cancel-timer evm--blink-timer)
    (setq evm--blink-timer nil)))
```

## Lifecycle (Activation/Deactivation)

### Activation Flow

```elisp
(defun evm-activate ()
  "Activate evm mode in current buffer."
  (interactive)
  ;; 1. Создать или получить buffer-local state
  (unless evm--state
    (setq evm--state (make-evm-state)))

  ;; 2. Инициализировать состояние
  (setf (evm-state-active-p evm--state) t
        (evm-state-mode evm--state) 'cursor
        (evm-state-regions evm--state) nil
        (evm-state-id-counter evm--state) 0
        (evm-state-registers evm--state) (make-hash-table :test 'eq))

  ;; 3. Включить minor mode (keymaps)
  (evm-mode 1)

  ;; 4. Войти в evil-normal-state
  (evil-normal-state)

  ;; 5. Настроить hooks
  (add-hook 'post-command-hook #'evm--post-command nil t)
  (add-hook 'before-change-functions #'evm--before-change nil t)
  (add-hook 'after-change-functions #'evm--after-change nil t)

  ;; 6. Обновить mode-line
  (force-mode-line-update))
```

### Deactivation Flow

```elisp
(defun evm-exit ()
  "Exit evm mode, removing all cursors."
  (interactive)
  (when (evm-state-active-p evm--state)
    ;; 1. Сохранить позиции для reselect
    (evm--save-for-reselect)

    ;; 2. Синхронизировать регистры с evil
    (evm--sync-to-evil-registers)

    ;; 3. Удалить все overlays
    (evm--remove-all-overlays)

    ;; 4. Убрать hooks
    (remove-hook 'post-command-hook #'evm--post-command t)
    (remove-hook 'before-change-functions #'evm--before-change t)
    (remove-hook 'after-change-functions #'evm--after-change t)

    ;; 5. Сбросить состояние
    (setf (evm-state-active-p evm--state) nil
          (evm-state-regions evm--state) nil)

    ;; 6. Выключить minor mode
    (evm-mode -1)

    ;; 7. Обновить mode-line
    (force-mode-line-update)

    ;; 8. Переместить point к позиции бывшего лидера
    (when-let ((last-leader-pos (car (evm-state-last-regions evm--state))))
      (goto-char last-leader-pos))))
```

### First Cursor Creation

```elisp
(defun evm-find-word ()
  "Start evm with word under cursor, find next occurrence."
  (interactive)
  ;; 1. Активировать если не активен
  (unless (and evm--state (evm-state-active-p evm--state))
    (evm-activate))

  ;; 2. Получить слово под курсором
  (let* ((bounds (bounds-of-thing-at-point 'symbol))
         (word (buffer-substring-no-properties (car bounds) (cdr bounds)))
         (pattern (regexp-quote word)))

    ;; 3. Добавить паттерн
    (push pattern (evm-state-patterns evm--state))

    ;; 4. Создать первый регион на текущем слове
    (evm--create-region (car bounds) (cdr bounds))

    ;; 5. Найти и добавить следующее вхождение
    (evm--find-and-add-next pattern)))
```

### Hooks для отслеживания изменений

```elisp
(defun evm--before-change (beg end)
  "Called before buffer modification."
  (when (evm-state-active-p evm--state)
    ;; Сохранить снапшот для undo
    (evm--push-undo-snapshot)))

(defun evm--after-change (beg end len)
  "Called after buffer modification."
  (when (evm-state-active-p evm--state)
    ;; Markers автоматически обновляются, но нужно:
    ;; 1. Проверить на слияние регионов
    (evm--check-and-merge-overlapping)
    ;; 2. Обновить overlays
    (evm--update-all-overlays)))

(defun evm--post-command ()
  "Called after each command."
  (when (evm-state-active-p evm--state)
    ;; Обновить visual feedback если нужно
    (evm--update-match-preview-if-needed)))
```

### Buffer-local State

```elisp
;; Состояние хранится buffer-local
(defvar-local evm--state nil
  "Buffer-local evm state.")

;; Minor mode определение
(define-minor-mode evm-mode
  "Minor mode for evil-visual-multi."
  :lighter nil  ; mode-line через отдельную функцию
  :keymap evm-mode-map
  :group 'evm
  (if evm-mode
      (progn
        ;; При включении — добавить cursor/extend keymap
        (if (eq (evm-state-mode evm--state) 'cursor)
            (set-keymap-parent evm-cursor-map evm-mode-map)
          (set-keymap-parent evm-extend-map evm-mode-map)))
    ;; При выключении — очистить
    nil))
```

## Key Design Decisions
- Используем overlays для отображения курсоров (стандартный подход в Emacs)
- Два режима как отдельные состояния, не как evil states
- Курсор-лидер визуально выделен отдельным face
- VM Registers реализованы как hash-table со списками строк
- Undo реализован через сохранение снапшотов состояния
