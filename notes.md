# Notes: evil-visual-multi

## Error Log

(Пока пусто — будет заполняться по мере работы)

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

## Sources

- [gabesoft/evil-mc](https://github.com/gabesoft/evil-mc)
- [magnars/multiple-cursors.el](https://github.com/magnars/multiple-cursors.el)
- [hlissner/evil-multiedit](https://github.com/hlissner/evil-multiedit)
- [emacs-evil/evil-surround](https://github.com/emacs-evil/evil-surround)
- [GNU ELPA - undo-tree](https://elpa.gnu.org/packages/undo-tree.html)
- [Emacs Undo Manual](https://www.gnu.org/software/emacs/manual/html_node/emacs/Undo.html)
