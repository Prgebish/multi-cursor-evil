# Architecture: evil-visual-multi (evim)

## Overview
Пакет для Emacs, реализующий множественные курсоры с двумя режимами работы (cursor/extend), интегрированный с evil-mode.

## Documentation Architecture

### Tutorial Design Goals
- Базовый mental model нужно объяснять один раз, а не размазывать по нескольким вводным файлам.
- Команды следует группировать по workflow, а не по принципу "один файл на одну клавишу".
- Про внешние пакеты (`evil`, `evil-surround`) tutorial должен объяснять только EVM-specific поведение.
- Tutorial должен выглядеть как единственный официальный учебник пакета.

### Tutorial Structure
```text
tutorial/
├── 00-start-here.txt                  # единые правила tutorial и обозначения
├── 01-selection-with-search.txt       # C-n, n/N, q/Q, \A, visual C-n
├── 02-structural-cursors.txt          # C-Down/C-Up, \c from visual selections
├── 03-modes-and-navigation.txt        # cursor/extend, Tab, motions, ]/[ , o
├── 04-insert-and-quick-edits.txt      # i/a/I/A/o/O, x/X/r/~, J
├── 05-operators-and-text-objects.txt  # d/c, D, dd, ciw, ci", da(
├── 06-layout-and-case.txt             # indent, case operators, align
├── 07-registers.txt                   # p/P, named registers, broadcast
├── 08-surround.txt                    # EVM + evil-surround only
├── 09-run-at-cursors.txt              # fallback execution
├── 10-restrict.txt                    # scoped search
└── 11-history-and-reselect.txt        # history / recovery appendix
```

### Tutorial Editing Rules
- Повторяющийся текст (`Press Esc when done`, `Expected result`, пояснение leader key, ссылки на следующий файл) нужно вынести или сократить до минимума.
- В каждом файле должно быть 4-6 плотных уроков и один рабочий сценарий, а не длинный список однотипных микро-упражнений.
- Удачные упражнения из текущих файлов нужно сохранять, но с более коротким вводным текстом.
- `\ g S` имеет смысл держать рядом с `u` / `C-r` только если урок оформлен как recovery/history, а не как чистый undo reference.

## File Structure
```
evil-visual-multi/
├── evim.el                 # Главный файл, entry point
├── evim-core.el            # Структуры данных, курсоры, overlays
├── evim-commands.el        # Команды (alignment, case conversion, etc.)
├── evim-navigation.el      # Навигация между курсорами
├── evim-operators.el       # Операторы d/c/y с motions (основной механизм)
├── evim-registers.el       # VM Registers
├── evim-run.el             # Run Normal/Macro/Ex (fallback)
├── evim-undo.el            # Undo/Redo с восстановлением курсоров
├── evim-integration.el     # Интеграция с evil-surround
└── test/
    └── evim-test.el        # ERT тесты
```

## Modules

### Module 1: evim-core
- Purpose: Базовые структуры данных и работа с курсорами
- Dependencies: evil, cl-lib
- Interface:
  - `evim-cursor` — структура курсора
  - `evim-region` — структура региона (для extend mode)
  - `evim-create-cursor (pos)` — создать курсор в позиции
  - `evim-delete-cursor (cursor)` — удалить курсор
  - `evim-get-all-cursors ()` — получить все курсоры
  - `evim-cursor-mode-p ()` — проверка режима cursor
  - `evim-extend-mode-p ()` — проверка режима extend
  - `evim-toggle-mode ()` — переключить режим

### Module 2: evim-commands
- Purpose: Продвинутые команды редактирования
- Dependencies: evim-core
- Interface:
  - `evim-align ()` — выравнивание курсоров
  - `evim-case-convert (type)` — конвертация регистра
  - `evim-replace-in-regions (from to)` — замена в регионах

### Module 3: evim-navigation
- Purpose: Навигация и создание курсоров
- Dependencies: evim-core
- Interface:
  - `evim-find-word ()` — найти слово под курсором (C-n)
  - `evim-find-next ()` — следующее вхождение (n)
  - `evim-find-prev ()` — предыдущее вхождение (N)
  - `evim-goto-next ()` — к следующему курсору (])
  - `evim-goto-prev ()` — к предыдущему курсору ([)
  - `evim-skip ()` — пропустить текущее (q)
  - `evim-remove-cursor ()` — удалить курсор (Q)
  - `evim-add-cursor-down ()` — курсор вниз (C-Down)
  - `evim-add-cursor-up ()` — курсор вверх (C-Up)
  - `evim-add-cursor-at-pos ()` — курсор в текущей позиции
  - `evim-select-all ()` — все вхождения
  - `evim-restrict-to-region ()` — ограничить поиск регионом

### Module 4: evim-registers
- Purpose: Собственные регистры для yank/paste
- Dependencies: evim-core
- Interface:
  - `evim-register` — структура регистра (список строк)
  - `evim-yank ()` — копировать в VM регистр
  - `evim-paste ()` — вставить из VM регистра
  - `evim-delete ()` — удалить в VM регистр

### Module 5: evim-operators
- Purpose: Операторы d/c/y с motions (основной способ редактирования)
- Dependencies: evim-core, evil
- Interface:
  - `evim-operator-delete ()` — запустить delete operator (ждёт motion)
  - `evim-operator-change ()` — запустить change operator
  - `evim-operator-yank ()` — запустить yank operator
  - `evim--parse-motion ()` — парсинг motion (w, e, b, iw, aw, i", a", etc.)
  - `evim--execute-operator-at-cursors (op motion count)` — выполнить operator+motion на всех курсорах

#### Архитектура операторов (по образцу vim-visual-multi)

**Поток выполнения `dw`:**
```
1. Пользователь нажимает `d`
2. evim-operator-delete вызывается, показывает промпт "[EVM] d"
3. Ждёт ввод motion (getchar loop)
4. Парсит motion: "w" → single motion
5. Для каждого курсора:
   - goto cursor position
   - execute "dw" через evil
   - track buffer changes
6. Обновить позиции курсоров
7. Сохранить удалённый текст в VM register
```

**Парсер motions:**
```elisp
;; Single motions (один символ):
'(h j k l w e b W E B $ ^ 0 { } ( ) % n N _)

;; Double motions (два символа):
;; i/a + text object: iw, aw, i", a", i(, a(, ib, ab, it, at
;; f/F/t/T + char: fa, Fb, tx, Ty
;; g + motion: ge, gE, gg, g_

;; Counts: 3w, 2e, d3w, 2d3w
```

**Интеграция с VM Registers:**
- Delete → сохраняет в register (по умолчанию `"`)
- Yank → сохраняет в register
- Change → сохраняет + enter insert mode

### Module 6: evim-run
- Purpose: Fallback механизм для выполнения произвольных команд
- Dependencies: evim-core, evil
- Interface:
  - `evim-run-normal (cmd)` — выполнить normal команду (\\z)
  - `evim-run-macro (register)` — выполнить макрос (\\@)
  - `evim-run-ex (cmd)` — выполнить Ex команду (\\:)

### Module 7: evim-undo
- Purpose: Undo/Redo с восстановлением позиций курсоров
- Dependencies: evim-core
- Interface:
  - `evim-undo ()` — откат с восстановлением курсоров
  - `evim-redo ()` — повтор с восстановлением курсоров
  - `evim-save-state ()` — сохранить состояние перед изменением

### Module 8: evim-integration
- Purpose: Интеграция с внешними пакетами
- Dependencies: evim-core, evil-surround (optional)
- Interface:
  - `evim-surround (char)` — обернуть все регионы

## Data Structures

### evim-region (основная единица — объединяет курсор и регион)
```elisp
(cl-defstruct evim-region
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

### evim-state (buffer-local глобальное состояние)
```elisp
(cl-defstruct evim-state
  ;; Активация
  active-p            ; активен ли evim в буфере
  mode                ; 'cursor или 'extend

  ;; Регионы
  regions             ; список evim-region, отсортированный по позиции
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
(cl-defstruct evim-snapshot
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
;; (gethash ?a evim-registers) => ("foo" "bar" "baz")
;; Регион 0 содержал "foo", регион 1 — "bar", регион 2 — "baz"
```

### Пример работы структур

```elisp
;; Cursor mode: 3 курсора на слове "foo"
;;
;; До:  foo bar foo baz foo
;;       ^      ^       ^    (3 курсора)
;;
;; После evim-find-word на первом "foo":
;; regions = [
;;   (evim-region :id 1 :beg #<marker 1> :end #<marker 1> :anchor #<marker 1>)
;;   (evim-region :id 2 :beg #<marker 9> :end #<marker 9> :anchor #<marker 9>)
;;   (evim-region :id 3 :beg #<marker 17> :end #<marker 17> :anchor #<marker 17>)
;; ]

;; Extend mode: после Tab (переключения в extend)
;;
;; До:  [foo] bar [foo] baz [foo]
;;        ^        ^         ^    (3 региона)
;;
;; regions = [
;;   (evim-region :id 1 :beg #<marker 1> :end #<marker 3> ...)
;;   (evim-region :id 2 :beg #<marker 9> :end #<marker 11> ...)
;;   (evim-region :id 3 :beg #<marker 17> :end #<marker 19> ...)
;; ]
```

## VM Registers (детальный дизайн)

### Концепция
VM Registers — отдельное пространство регистров для операций с множественными курсорами.
Отличие от стандартных evil/Emacs регистров: хранят **список строк** (по одной на регион),
а не одну строку.

### Хранение
```elisp
;; В evim-state:
registers  ; hash-table, создаётся при активации evim

;; Инициализация:
(setf (evim-state-registers state)
      (make-hash-table :test 'eq))  ; ключи — символы
```

### Операции

#### evim-yank (y в VM)
```elisp
(defun evim-yank (&optional register)
  "Yank содержимое всех регионов в VM регистр.
Если REGISTER не указан, используется регистр по умолчанию (\\\")."
  ;; 1. Собрать текст из всех регионов (в порядке позиций)
  ;; 2. Сохранить как список в register
  ;; 3. Также сохранить в kill-ring первый элемент (для совместимости)
  )

;; Пример:
;; Регионы: "foo", "bar", "baz"
;; После (evim-yank ?a):
;; (gethash ?a registers) => ("foo" "bar" "baz")
```

#### evim-delete (d в VM)
```elisp
(defun evim-delete (&optional register)
  "Удалить содержимое всех регионов, сохранив в VM регистр."
  ;; 1. Сохранить содержимое как evim-yank
  ;; 2. Удалить текст из всех регионов
  ;; 3. Переключить в cursor mode (регионы стали пустыми)
  )
```

#### evim-paste (p/P в VM)
```elisp
(defun evim-paste (&optional register after)
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

#### evim-change (c в VM)
```elisp
(defun evim-change (&optional register)
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
;; При выходе из evim:
;; - Регистр \" копируется в evil \"
;; - Это позволяет paste после выхода из evim

(defun evim--sync-to-evil-registers ()
  "Синхронизировать VM регистр \" в evil."
  (let ((contents (gethash ?\" (evim-state-registers evim--state))))
    (when contents
      ;; Объединить все строки для evil
      (evil-set-register ?\" (string-join contents "\n")))))
```

## Mode System (cursor/extend)

### Обзор режимов

```
┌─────────────────────────────────────────────────────────────────┐
│                         EVM INACTIVE                             │
│  (обычный режим evil, evim не активен)                           │
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
- `(evim-state-mode state)` = `'cursor`
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
- `(evim-state-mode state)` = `'extend`
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
(defun evim-toggle-mode ()
  "Переключить между cursor и extend mode."
  (if (evim-cursor-mode-p)
      (evim--enter-extend-mode)
    (evim--enter-cursor-mode)))

(defun evim--enter-extend-mode ()
  "Перейти в extend mode."
  ;; 1. Для каждого региона: расширить до слова/паттерна под курсором
  ;;    или просто установить end = beg + 1 (один символ)
  ;; 2. Обновить overlays
  ;; 3. Установить mode = 'extend
  (setf (evim-state-mode evim--state) 'extend)
  (dolist (r (evim-state-regions evim--state))
    (evim--region-extend-to-pattern r))
  (evim--update-all-overlays))

(defun evim--enter-cursor-mode ()
  "Перейти в cursor mode."
  ;; 1. Для каждого региона: схлопнуть до позиции курсора
  ;;    beg = end = (если dir=1 то end, иначе beg)
  ;; 2. Обновить overlays
  ;; 3. Установить mode = 'cursor
  (setf (evim-state-mode evim--state) 'cursor)
  (dolist (r (evim-state-regions evim--state))
    (evim--region-collapse-to-cursor r))
  (evim--update-all-overlays))
```

### Поведение при редактировании

**Cursor Mode + Insert:**
```elisp
;; При нажатии 'i' в cursor mode:
;; 1. Сохранить снапшот для undo
;; 2. Войти в evil-insert-state
;; 3. Все набираемые символы вставляются во ВСЕ позиции курсоров
;; 4. При выходе из insert (Esc): вернуться в cursor mode

(defun evim--replicate-insert (char)
  "Вставить CHAR во все позиции курсоров."
  ;; Вставляем с конца буфера, чтобы не сдвигать позиции
  (let ((regions (reverse (evim-state-regions evim--state))))
    (dolist (r regions)
      (goto-char (marker-position (evim-region-end r)))
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
;; evim НЕ создаёт новый evil-state
;; Вместо этого работает как "надстройка" над существующими:

;; evil-normal-state + evim = перемещение курсоров
;; evil-insert-state + evim = синхронный ввод
;; evil-visual-state + evim = не используется (заменён extend mode)

;; При входе в evim:
(evil-normal-state)  ; принудительно выйти из других состояний

;; Keymap приоритет:
;; evim-mode-map > evil-normal-state-map > global-map
```

## Key Bindings (финальный дизайн)

### Keymaps структура

```elisp
;; 1. evim-global-map — привязки для активации evim (всегда активны)
;; 2. evim-mode-map — базовые привязки когда evim активен
;; 3. evim-cursor-map — дополнительные привязки в cursor mode
;; 4. evim-extend-map — дополнительные привязки в extend mode

;; Приоритет при активном evim:
;; evim-cursor-map/evim-extend-map > evim-mode-map > evil-normal-state-map
```

### Global Bindings (evim-global-map)
Привязки для активации evim (добавляются в evil-normal-state-map).

| Key | Function | Описание |
|-----|----------|----------|
| `C-n` | `evim-find-word` | Выделить слово под курсором, добавить следующее |
| `C-Down` | `evim-add-cursor-down` | Добавить курсор на строку ниже |
| `C-Up` | `evim-add-cursor-up` | Добавить курсор на строку выше |
| `<s-mouse-1>` | `evim-add-cursor-at-click` | Добавить курсор по клику мыши |

### Common Bindings (evim-mode-map)
Активны в обоих режимах (cursor и extend).

| Key | Function | Описание |
|-----|----------|----------|
| `Esc` | `evim-exit` | Выйти из evim |
| `Tab` | `evim-toggle-mode` | Переключить cursor/extend |
| `n` | `evim-find-next` | Следующее вхождение паттерна |
| `N` | `evim-find-prev` | Предыдущее вхождение паттерна |
| `]` | `evim-goto-next` | К следующему курсору (лидер) |
| `[` | `evim-goto-prev` | К предыдущему курсору (лидер) |
| `q` | `evim-skip-current` | Пропустить текущий, перейти дальше |
| `Q` | `evim-remove-current` | Удалить текущий курсор |
| `M` | `evim-toggle-multiline` | Включить/выключить multiline |
| `u` | `evim-undo` | Отменить последнее действие |
| `C-r` | `evim-redo` | Повторить отменённое |

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

### Cursor Mode Bindings (evim-cursor-map)

| Key | Function | Описание |
|-----|----------|----------|
| `d` + motion | `evim-operator-delete` | Delete с motion (dw, de, diw, etc.) |
| `c` + motion | `evim-operator-change` | Change с motion (cw, ciw, etc.) |
| `y` + motion | `evim-operator-yank` | Yank с motion (yw, yiw, etc.) |
| `D` | `evim-delete-to-eol` | Delete до конца строки |
| `C` | `evim-change-to-eol` | Change до конца строки |
| `Y` | `evim-yank-line` | Yank строку |
| `i` | `evim-insert` | Insert перед курсором |
| `a` | `evim-append` | Insert после курсора |
| `I` | `evim-insert-bol` | Insert в начале строки |
| `A` | `evim-append-eol` | Insert в конце строки |
| `o` | `evim-open-below` | Новая строка ниже + insert |
| `O` | `evim-open-above` | Новая строка выше + insert |
| `x` | `evim-delete-char` | Удалить символ под курсором |
| `X` | `evim-delete-char-before` | Удалить символ перед курсором |
| `r` + char | `evim-replace-char` | Заменить символ |
| `~` | `evim-toggle-case-char` | Toggle case символа |
| `J` | `evim-join-lines` | Объединить строки |
| `v` | `evim-enter-extend` | Войти в extend mode |
| `C-n` | `evim-add-next-word` | Добавить следующее вхождение |
| `C-Down` | `evim-add-cursor-down` | Курсор вниз |
| `C-Up` | `evim-add-cursor-up` | Курсор вверх |

### Extend Mode Bindings (evim-extend-map)

| Key | Function | Описание |
|-----|----------|----------|
| `y` | `evim-yank` | Yank регионов в VM регистр |
| `d` | `evim-delete` | Delete регионов в VM регистр |
| `c` | `evim-change` | Delete + enter insert |
| `p` | `evim-paste-after` | Paste после |
| `P` | `evim-paste-before` | Paste до |
| `s` | `evim-substitute` | Как `c` (синоним) |
| `>` | `evim-indent` | Indent регионов |
| `<` | `evim-outdent` | Outdent регионов |
| `U` | `evim-upcase` | UPPERCASE регионов |
| `u` | `evim-downcase` | lowercase регионов |
| `~` | `evim-toggle-case` | Toggle case регионов |
| `o` | `evim-flip-direction` | Flip cursor/anchor |
| `C-n` | `evim-add-next-occurrence` | Добавить следующее вхождение |

### Prefix Commands (\\)
Специальные команды с префиксом `\`.

| Key | Function | Описание |
|-----|----------|----------|
| `\a` | `evim-align` | Выровнять курсоры |
| `\A` | `evim-select-all` | Выбрать все вхождения |
| `\c` | `evim-case-menu` | Меню конвертации регистра |
| `\z` | `evim-run-normal` | Выполнить normal команду |
| `\@` + reg | `evim-run-macro` | Выполнить макрос из регистра |
| `\:` | `evim-run-ex` | Выполнить Ex команду |
| `\s` | `evim-surround` | Обернуть регионы (evil-surround) |
| `\r` | `evim-replace-pattern` | Заменить текст во всех регионах |
| `\gS` | `evim-reselect-last` | Восстановить последние курсоры |

### Register Access
Для доступа к именованным регистрам используется `"` + register перед командой.

```elisp
;; Примеры:
"ay   ; yank в регистр a
"ap   ; paste из регистра a
"Ad   ; delete и append в регистр A
```

### Insert Mode Bindings
Когда evim активен и мы в insert mode.

| Key | Function | Описание |
|-----|----------|----------|
| `Esc` | `evim-exit-insert` | Выйти из insert, остаться в evim |
| Любой символ | `evim--replicate-char` | Вставить во все позиции |
| `Backspace` | `evim--replicate-backspace` | Удалить во всех позициях |
| `C-w` | `evim--replicate-kill-word` | Удалить слово во всех позициях |

### Mouse Bindings

| Key | Function | Описание |
|-----|----------|----------|
| `<s-mouse-1>` | `evim-add-cursor-at-click` | Добавить курсор по клику |

## Visual Display (Faces & Overlays)

### Faces (цветовая схема)

```elisp
;; Основные faces
(defface evim-cursor-face
  '((((class color) (background dark))
     :background "#3B82F6" :foreground "white")  ; Blue-500
    (((class color) (background light))
     :background "#2563EB" :foreground "white")) ; Blue-600
  "Face for cursors in cursor mode.")

(defface evim-region-face
  '((((class color) (background dark))
     :background "#166534")  ; Green-800
    (((class color) (background light))
     :background "#BBF7D0")) ; Green-200
  "Face for selected regions in extend mode.")

(defface evim-leader-cursor-face
  '((((class color) (background dark))
     :background "#F97316" :foreground "black")  ; Orange-500
    (((class color) (background light))
     :background "#EA580C" :foreground "white")) ; Orange-600
  "Face for the leader cursor position.")

(defface evim-leader-region-face
  '((((class color) (background dark))
     :background "#854D0E")  ; Yellow-800
    (((class color) (background light))
     :background "#FEF08A")) ; Yellow-200
  "Face for the leader region in extend mode.")

;; Дополнительные faces для UI
(defface evim-mode-line-face
  '((t :foreground "#10B981" :weight bold))  ; Emerald-500
  "Face for evim indicator in mode-line.")

(defface evim-match-face
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
'evim-region    ; тип: 'region или 'cursor
'evim-id        ; ID связанного региона
'evim-leader-p  ; t если это лидер
```

#### Cursor Mode Overlay

```elisp
(defun evim--create-cursor-overlay (region)
  "Create cursor overlay for REGION."
  (let* ((pos (marker-position (evim-region-beg region)))
         (ov (make-overlay pos (1+ pos) nil t nil)))
    ;; Свойства
    (overlay-put ov 'evim-region 'cursor)
    (overlay-put ov 'evim-id (evim-region-id region))
    (overlay-put ov 'priority 100)  ; высокий приоритет

    ;; Face зависит от того, лидер это или нет
    (overlay-put ov 'face
                 (if (evim--leader-p region)
                     'evim-leader-cursor-face
                   'evim-cursor-face))

    ;; Для пустой строки или конца файла — показать как вертикальную черту
    (when (or (eolp) (= pos (point-max)))
      (overlay-put ov 'before-string
                   (propertize "|" 'face (overlay-get ov 'face))))

    (setf (evim-region-cursor-overlay region) ov)))
```

#### Extend Mode Overlays

```elisp
(defun evim--create-region-overlay (region)
  "Create region overlay for REGION in extend mode."
  (let* ((beg (marker-position (evim-region-beg region)))
         (end (marker-position (evim-region-end region)))
         (ov (make-overlay beg end nil t nil)))
    ;; Свойства региона
    (overlay-put ov 'evim-region 'region)
    (overlay-put ov 'evim-id (evim-region-id region))
    (overlay-put ov 'priority 90)

    ;; Face
    (overlay-put ov 'face
                 (if (evim--leader-p region)
                     'evim-leader-region-face
                   'evim-region-face))

    (setf (evim-region-overlay region) ov))

  ;; Также создаём cursor overlay внутри региона
  (evim--create-cursor-in-region-overlay region))

(defun evim--create-cursor-in-region-overlay (region)
  "Create cursor overlay within region (показывает активный конец)."
  (let* ((cursor-pos (if (= (evim-region-dir region) 1)
                         (marker-position (evim-region-end region))
                       (marker-position (evim-region-beg region))))
         (ov (make-overlay cursor-pos (1+ cursor-pos) nil t nil)))
    (overlay-put ov 'evim-region 'cursor)
    (overlay-put ov 'evim-id (evim-region-id region))
    (overlay-put ov 'priority 110)  ; выше чем region
    (overlay-put ov 'face
                 (if (evim--leader-p region)
                     'evim-leader-cursor-face
                   'evim-cursor-face))
    (setf (evim-region-cursor-overlay region) ov)))
```

#### Overlay Management

```elisp
(defun evim--update-all-overlays ()
  "Update all overlays based on current state."
  ;; 1. Удалить все старые overlays
  (evim--remove-all-overlays)

  ;; 2. Создать новые в зависимости от режима
  (dolist (region (evim-state-regions evim--state))
    (if (eq (evim-state-mode evim--state) 'extend)
        (evim--create-region-overlay region)
      (evim--create-cursor-overlay region))))

(defun evim--remove-all-overlays ()
  "Remove all evim overlays from buffer."
  (dolist (region (evim-state-regions evim--state))
    (when (evim-region-overlay region)
      (delete-overlay (evim-region-overlay region))
      (setf (evim-region-overlay region) nil))
    (when (evim-region-cursor-overlay region)
      (delete-overlay (evim-region-cursor-overlay region))
      (setf (evim-region-cursor-overlay region) nil))))

(defun evim--update-leader-overlays ()
  "Update overlays to reflect new leader."
  ;; Обновить face для всех overlays
  (dolist (region (evim-state-regions evim--state))
    (let ((is-leader (evim--leader-p region)))
      (when-let ((ov (evim-region-cursor-overlay region)))
        (overlay-put ov 'face
                     (if is-leader
                         'evim-leader-cursor-face
                       'evim-cursor-face)))
      (when-let ((ov (evim-region-overlay region)))
        (overlay-put ov 'face
                     (if is-leader
                         'evim-leader-region-face
                       'evim-region-face))))))
```

### Mode-Line Indicator

```elisp
(defun evim--mode-line-indicator ()
  "Return mode-line indicator string."
  (when (evim-state-active-p evim--state)
    (let* ((mode (evim-state-mode evim--state))
           (count (length (evim-state-regions evim--state)))
           (leader-idx (1+ (evim--leader-index))))
      (propertize
       (format " EVM[%s %d/%d]"
               (if (eq mode 'cursor) "C" "E")
               leader-idx
               count)
       'face 'evim-mode-line-face))))

;; Добавить в mode-line-format:
;; (:eval (evim--mode-line-indicator))
```

### Visual Feedback

```elisp
;; Показ потенциальных совпадений (при поиске)
(defvar evim--match-overlays nil
  "List of temporary overlays for match preview.")

(defun evim--show-match-preview (pattern)
  "Show preview of all matches for PATTERN."
  (evim--hide-match-preview)
  (save-excursion
    (goto-char (point-min))
    (while (re-search-forward pattern nil t)
      (let ((ov (make-overlay (match-beginning 0) (match-end 0))))
        (overlay-put ov 'face 'evim-match-face)
        (overlay-put ov 'evim-match t)
        (push ov evim--match-overlays)))))

(defun evim--hide-match-preview ()
  "Hide match preview overlays."
  (mapc #'delete-overlay evim--match-overlays)
  (setq evim--match-overlays nil))
```

### Cursor Blinking (опционально)

```elisp
(defcustom evim-cursor-blink nil
  "If non-nil, blink cursor overlays."
  :type 'boolean
  :group 'evim)

(defvar evim--blink-timer nil)

(defun evim--start-cursor-blink ()
  "Start blinking cursor overlays."
  (when evim-cursor-blink
    (setq evim--blink-timer
          (run-with-timer 0.5 0.5 #'evim--toggle-cursor-visibility))))

(defun evim--stop-cursor-blink ()
  "Stop blinking."
  (when evim--blink-timer
    (cancel-timer evim--blink-timer)
    (setq evim--blink-timer nil)))
```

## Lifecycle (Activation/Deactivation)

### Activation Flow

```elisp
(defun evim-activate ()
  "Activate evim mode in current buffer."
  (interactive)
  ;; 1. Создать или получить buffer-local state
  (unless evim--state
    (setq evim--state (make-evim-state)))

  ;; 2. Инициализировать состояние
  (setf (evim-state-active-p evim--state) t
        (evim-state-mode evim--state) 'cursor
        (evim-state-regions evim--state) nil
        (evim-state-id-counter evim--state) 0
        (evim-state-registers evim--state) (make-hash-table :test 'eq))

  ;; 3. Включить minor mode (keymaps)
  (evim-mode 1)

  ;; 4. Войти в evil-normal-state
  (evil-normal-state)

  ;; 5. Настроить hooks
  (add-hook 'post-command-hook #'evim--post-command nil t)
  (add-hook 'before-change-functions #'evim--before-change nil t)
  (add-hook 'after-change-functions #'evim--after-change nil t)

  ;; 6. Обновить mode-line
  (force-mode-line-update))
```

### Deactivation Flow

```elisp
(defun evim-exit ()
  "Exit evim mode, removing all cursors."
  (interactive)
  (when (evim-state-active-p evim--state)
    ;; 1. Сохранить позиции для reselect
    (evim--save-for-reselect)

    ;; 2. Синхронизировать регистры с evil
    (evim--sync-to-evil-registers)

    ;; 3. Удалить все overlays
    (evim--remove-all-overlays)

    ;; 4. Убрать hooks
    (remove-hook 'post-command-hook #'evim--post-command t)
    (remove-hook 'before-change-functions #'evim--before-change t)
    (remove-hook 'after-change-functions #'evim--after-change t)

    ;; 5. Сбросить состояние
    (setf (evim-state-active-p evim--state) nil
          (evim-state-regions evim--state) nil)

    ;; 6. Выключить minor mode
    (evim-mode -1)

    ;; 7. Обновить mode-line
    (force-mode-line-update)

    ;; 8. Переместить point к позиции бывшего лидера
    (when-let ((last-leader-pos (car (evim-state-last-regions evim--state))))
      (goto-char last-leader-pos))))
```

### First Cursor Creation

```elisp
(defun evim-find-word ()
  "Start evim with word under cursor, find next occurrence."
  (interactive)
  ;; 1. Активировать если не активен
  (unless (and evim--state (evim-state-active-p evim--state))
    (evim-activate))

  ;; 2. Получить слово под курсором
  (let* ((bounds (bounds-of-thing-at-point 'symbol))
         (word (buffer-substring-no-properties (car bounds) (cdr bounds)))
         (pattern (regexp-quote word)))

    ;; 3. Добавить паттерн
    (push pattern (evim-state-patterns evim--state))

    ;; 4. Создать первый регион на текущем слове
    (evim--create-region (car bounds) (cdr bounds))

    ;; 5. Найти и добавить следующее вхождение
    (evim--find-and-add-next pattern)))
```

### Hooks для отслеживания изменений

```elisp
(defun evim--before-change (beg end)
  "Called before buffer modification."
  (when (evim-state-active-p evim--state)
    ;; Сохранить снапшот для undo
    (evim--push-undo-snapshot)))

(defun evim--after-change (beg end len)
  "Called after buffer modification."
  (when (evim-state-active-p evim--state)
    ;; Markers автоматически обновляются, но нужно:
    ;; 1. Проверить на слияние регионов
    (evim--check-and-merge-overlapping)
    ;; 2. Обновить overlays
    (evim--update-all-overlays)))

(defun evim--post-command ()
  "Called after each command."
  (when (evim-state-active-p evim--state)
    ;; Обновить visual feedback если нужно
    (evim--update-match-preview-if-needed)))
```

### Buffer-local State

```elisp
;; Состояние хранится buffer-local
(defvar-local evim--state nil
  "Buffer-local evim state.")

;; Minor mode определение
(define-minor-mode evim-mode
  "Minor mode for evil-visual-multi."
  :lighter nil  ; mode-line через отдельную функцию
  :keymap evim-mode-map
  :group 'evim
  (if evim-mode
      (progn
        ;; При включении — добавить cursor/extend keymap
        (if (eq (evim-state-mode evim--state) 'cursor)
            (set-keymap-parent evim-cursor-map evim-mode-map)
          (set-keymap-parent evim-extend-map evim-mode-map)))
    ;; При выключении — очистить
    nil))
```

## Key Design Decisions
- Используем overlays для отображения курсоров (стандартный подход в Emacs)
- Два режима как отдельные состояния, не как evil states
- Курсор-лидер визуально выделен отдельным face
- VM Registers реализованы как hash-table со списками строк
- Undo реализован через сохранение снапшотов состояния
