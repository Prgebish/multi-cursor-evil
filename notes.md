# Notes: evil-visual-multi

## Error Log

### 2026-01-16: Keybindings не работают после перезагрузки Emacs
**Симптом:** `n` после `C-n` вызывает `evil-ex-search-next` вместо `evm-find-next`.
**Причина:** Устаревшие `.elc` файлы. Emacs загружает скомпилированную версию без последних исправлений.
**Решение:** `make clean` или `rm *.elc` перед перезагрузкой модулей.
**Исправление в коде:** `evm--update-keymap` теперь всегда удаляет и заново добавляет `evm--emulation-alist` в начало `emulation-mode-map-alists`, чтобы гарантировать приоритет над evil.

### 2026-01-16: Курсоры в неконсистентных позициях после undo
**Симптом:** После `C-n`, `n`, `c`, ввод текста, `Esc`, `u`, `u` — курсоры оказываются в разных частях слов (один в начале, другой в конце), хотя должны быть в одинаковых позициях.
**Причина 1:** Детекция undo через `buffer-modified-tick` не работала — tick всегда увеличивается, даже при undo.
**Решение 1:** Заменили на проверку `this-command`:
```elisp
(memq this-command '(undo evil-undo undo-tree-undo undo-fu-only-undo))
```

**Причина 2:** Функция `evm--resync-regions-to-pattern` требовала точного совпадения количества matches и регионов. Если в буфере 10 "text", а выделено 2 — resync не срабатывал.
**Решение 2:** Убрали проверку `(= (length matches) num-regions)`.

**Причина 3:** После первого undo (удаление вставленного текста, но до восстановления оригинала) resync находил ближайшие matches и прыгал на них — даже если это были совсем другие вхождения слова.
**Решение 3:** Resync теперь перемещает курсор только если match находится очень близко к текущей позиции (в пределах длины match). Если текст ещё не восстановлен — курсор остаётся на месте.

---

## Non-Obvious Decisions

### Убрали Regex Search
**Почему:** Для evil-пользователей есть `/` для обычного поиска. Отдельный regex search избыточен.

### Убрали Shift-Arrows
**Почему:** Посимвольное выделение — паттерн из обычных редакторов. Evil-пользователи используют text objects.

### Убрали Single region mode
**Почему:** Противоречит идее множественных курсоров (делать одно везде). Если курсор не там — проще удалить (Q) и создать новый.

### Убрали C-f/C-b навигацию
**Почему:** Постраничная навигация по курсорам редко нужна. Достаточно ]/[.

### Убрали Transpose, Duplicate, Shift
**Почему:** Редко используются. Можно добавить позже по запросу.

### Убрали Split regions, Filter regions, Transform, Numbering
**Почему:** Специфичные функции. Не критичны для MVP.

### Убрали Hydra/Transient меню
**Почему:** Можно добавить позже. Сначала базовый функционал.

### Добавили Курсор-"лидер"
**Почему:** Визуальная обратная связь — какой курсор "главный". Помогает ориентироваться.

### Добавили Restrict to region
**Почему:** Естественно для Emacs (как narrowing). Позволяет ограничить поиск выделенной областью.

---

## Unexpected Findings

(Пока пусто — будет заполняться по мере работы)

---

## Phase 1 Research Findings

### 1.1 Существующие решения

#### evil-mc (gabesoft/evil-mc)
- **Подход:** Fake cursors через overlays
- **Ключевые файлы:**
  - `evil-mc-cursor-make.el` — создание/удаление курсоров
  - `evil-mc-cursor-state.el` — состояние каждого курсора
  - `evil-mc-known-commands.el` — обработчики команд
- **Команды:** `C-n/C-p` создание, `M-n/M-p` навигация
- **Хранение:** Список `evil-mc-cursor-list`, отсортированный по позиции

#### multiple-cursors.el (magnars)
- **Подход:** Fake cursors через overlays + hooks
- **Механизм:** `pre-command-hook` захватывает команду, `post-command-hook` реплицирует на все курсоры
- **Классификация команд:** Два списка — run-once и run-for-all
- **Ограничения:** isearch не поддерживается, redo может сломать курсоры

#### evil-multiedit (hlissner)
- **Подход:** На базе iedit-mode
- **Отличие:** Редактирование совпадений интерактивно, другая ниша

### 1.2 evil-mc: Курсоры и Overlays

#### Структура курсора
```elisp
;; Свойства каждого fake cursor:
- overlay           ; overlay для отображения
- last-position     ; позиция в буфере
- order             ; хронологический порядок создания
- region            ; текущий регион/выделение
- mark-ring         ; кольцо меток
- mark-active       ; статус активности метки
- kill-ring         ; кольцо удалённого текста
- undo-stack        ; стек отмены
- evil-markers-alist ; маркеры Evil
- evil-jump-list    ; список переходов
- temporary-goal-column ; целевая колонка для j/k
```

#### Overlay свойства
```elisp
- type: 'evil-mc-cursor
- priority: evil-mc-cursor-overlay-priority
- face: evil-mc-cursor-face или evil-mc-cursor-bar-face
```

#### Типы курсоров
1. **Bar cursor** — вертикальная черта `"|"`
2. **Hbar cursor** — горизонтальная линия
3. **Block cursor** — стандартный блок

### 1.3 Undo/Redo в Emacs

#### Базовый механизм
- **buffer-undo-list** — линейный список изменений
- **primitive-undo** — низкоуровневая функция отмены
- **undo-equiv-table** — маппинг состояний для undo-tree

#### Стратегия для multiple-cursors
1. Перед командой: записать `(apply 'deactivate-cursor-after-undo id)` в buffer-undo-list
2. При undo: `activate-cursor-for-undo` восстанавливает fake cursor
3. После undo: `deactivate-cursor-after-undo` создаёт новый fake cursor

#### Рекомендация для evm
- Сохранять снапшоты состояния (позиции всех курсоров) перед изменениями
- При undo восстанавливать курсоры из снапшота
- Использовать `buffer-undo-list` для записи восстановительных функций

### 1.4 evil-surround API

#### Основная функция
```elisp
(evil-surround-region beg end type char &optional force-new-line)
;; beg, end — границы региона
;; type — тип выделения ('exclusive, 'inclusive, 'line, 'block)
;; char — символ окружения (?\(, ?\", etc.)
```

#### Вспомогательные функции
```elisp
(evil-surround-delete char)   ; удалить окружение
(evil-surround-change char)   ; изменить окружение
(evil-surround-pair char)     ; получить пару для символа
```

#### Конфигурация пар
```elisp
evil-surround-pairs-alist
;; '((?\( . ("( " . " )"))
;;   (?\[ . ("[ " . " ]"))
;;   ...)
```

#### Интеграция для evm
```elisp
(defun evm-surround (char)
  "Окружить все регионы символом CHAR."
  (dolist (region (evm-get-all-regions))
    (evil-surround-region
      (evm-region-beg region)
      (evm-region-end region)
      'inclusive
      char)))
```

### vim-visual-multi Reference

#### Структура регионов
- **Region** содержит: `l, L, a, b` (строки и колонки), `A, B` (byte offsets)
- **Cursor mode** — A == B (точка)
- **Extend mode** — A < B (выделение)

#### Ключевые переменные региона
```vim
R.id      ; уникальный ID
R.dir     ; направление (0/1)
R.txt     ; текстовое содержимое
R.pat     ; паттерн поиска
R.k, R.K  ; anchor (точка привязки)
R.w, R.h  ; ширина и высота
R.vcol    ; вертикальная колонка для j/k
```

#### Подсветка
- `matchaddpos('MultiCursor', ...)` — для курсоров
- `matchaddpos('VM_Extend', ...)` — для регионов

---

## Performance Optimizations (Phase 11.3)

### 2026-01-19: Overlay Updates Optimization
**Проблема:** `evm--update-all-overlays` вызывалась после каждого движения и пересоздавала все overlays.
**Решение:** Новая версия переиспользует существующие overlays через `move-overlay`, создаёт новые только когда нужно.
**Результат:** O(n) move vs O(n) delete + O(n) create.

### 2026-01-19: Buffer Scan Optimization
**Проблема:** `evm--remove-all-overlays` сканировала весь буфер `(overlays-in (point-min) (point-max))`.
**Решение:** Разделили на две функции:
- `evm--remove-all-overlays` — быстрая, работает только с tracked overlays
- `evm--remove-all-overlays-thorough` — полная очистка при exit

### 2026-01-19: Region Sorting Optimization
**Проблема:** При каждом `evm--create-region` вызывался полный sort O(n log n).
**Решение:** Добавили `evm--insert-region-sorted` — вставка в отсортированный список O(n).

### 2026-01-19: Batch Region Creation
**Проблема:** `evm-select-all` вызывала `evm--create-region` в цикле — каждый раз sort + overlay.
**Решение:** Добавили `evm--create-regions-batch` — собирает все позиции, сортирует один раз, создаёт overlays batch.

### 2026-01-19: O(1) Duplicate Check in Select All
**Проблема:** `evm-select-all` использовала `cl-find-if` O(n) для проверки дубликатов.
**Решение:** Используем hash-table для O(1) lookup.

---

## Sources

- [gabesoft/evil-mc](https://github.com/gabesoft/evil-mc)
- [magnars/multiple-cursors.el](https://github.com/magnars/multiple-cursors.el)
- [hlissner/evil-multiedit](https://github.com/hlissner/evil-multiedit)
- [emacs-evil/evil-surround](https://github.com/emacs-evil/evil-surround)
- [GNU ELPA - undo-tree](https://elpa.gnu.org/packages/undo-tree.html)
- [Emacs Undo Manual](https://www.gnu.org/software/emacs/manual/html_node/emacs/Undo.html)
