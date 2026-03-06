# Features: EVM

## Cursor Creation and Selection

### Search-Based Selection
**Description:** `C-n` starts EVM from the word under point or from the current visual selection. Repeated `C-n` or `n` adds the next match, `N` walks backward, `q` skips the current match, `Q` removes the current cursor, and `\ A` selects the rest.

**Example:**
```text
Input: point on `foo`, then `C-n`, `n`, `q`, `n`
Result: cursors are created only on the matches you keep
```

### Structural Cursor Creation
**Description:** EVM can create cursors without search: `C-Down` / `C-Up` add vertical cursors, and `\ c` converts the current visual selection into cursors.

**Example:**
```text
Input: visual-line on 4 lines, then `\ c`
Result: one cursor per selected line
```

### Restricted Search
**Description:** `\ r` limits `C-n` / `n` to a selected region so that matches outside the active block are ignored.

**Example:**
```text
Input: select one function with `V`, press `\ r`, then search `data`
Result: only the selected function receives cursors
```

## Modes and Navigation

### Cursor Mode vs Extend Mode
**Description:** EVM has two working modes. `cursor` mode is for point cursors and insert/operator workflows. `extend` mode is for selections that can be edited directly. `Tab` switches between them.

**Example:**
```text
Input: `C-n` on `name`, then `Tab`
Result: selected matches collapse into point cursors
```

### Shared Motions
**Description:** Evil motions move all cursors together. In `extend` mode the same motions grow or shrink selections. `]/[` moves the leader across existing cursors, and `o` flips the active end of a selection.

**Example:**
```text
Input: create 3 cursors, then `w`, `f=`, `]`
Result: all cursors move together and the leader changes
```

## Editing

### Insert Editing
**Description:** In `cursor` mode, `i/a/I/A/o/O` enter insert mode at every cursor. Typed text and backspace are replicated across all cursors.

**Example:**
```text
Input: vertical cursors on 3 lines, then `I`, type `const `, `Esc`
Result: every line gets the same prefix
```

### Quick Edits
**Description:** `x/X/r/~` and `J` apply immediately at all cursors without a separate selection step.

**Example:**
```text
Input: cursors on `;`, then `x`
Result: semicolons are removed on every line
```

### Operators, Motions, and Text Objects
**Description:** In `cursor` mode, `d/c/y`, `>`, `<`, `gu/gU/g~` combine with motions and text objects exactly once, then run at every cursor.

**Example:**
```text
Input: cursors inside quotes, then `ci"`, type `blue`, `Esc`
Result: text inside every quoted string is replaced
```

### Direct Selection Editing
**Description:** In `extend` mode, `d/c/y`, `U/u/~`, `p/P`, and `S` act directly on the selected regions.

**Example:**
```text
Input: matches selected with `C-n`, then `c`, type `result`, `Esc`
Result: every selection is replaced at once
```

## Registers, Layout, and Integrations

### VM Registers
**Description:** EVM stores per-cursor text as lists rather than flattening it into one string. This enables 1-to-1 paste, named registers, and broadcast when the register has fewer entries than cursors.

**Example:**
```text
Input: `yiw` on `Alice`, `Bob`, `Carol`; later paste onto 3 placeholders
Result: placeholder 1 gets `Alice`, 2 gets `Bob`, 3 gets `Carol`
```

### Surround Integration
**Description:** When `evil-surround` is available, EVM supports `S` in `extend` mode and `ys` / `ds` / `cs` in `cursor` mode.

**Example:**
```text
Input: select 3 words, then `S"`
Result: every word is wrapped in double quotes
```

### Alignment
**Description:** `\ a` inserts spaces before cursors or regions so they line up with the rightmost column.

**Example:**
```text
Input: cursors on `=` across uneven assignments, then `\ a`
Result: equal signs align vertically
```

### Fallback Execution
**Description:** `\ z`, `\ @`, and `\ :` execute a normal command, macro, or ex command at every cursor when a dedicated multi-cursor command does not exist.

**Example:**
```text
Input: cursors on values, then `\ z` + `gUiw`
Result: each value is uppercased by replaying normal-mode keys
```

## Recovery and History

### Undo / Redo
**Description:** `u` and `C-r` work in `cursor` mode and restore cursor positions after the buffer state changes.

**Example:**
```text
Input: replace a character at 3 cursors, then `u`
Result: text and cursor positions return together
```

### Reselect Last
**Description:** `\ g S` restores the most recent cursor/region set after leaving EVM.

**Example:**
```text
Input: finish one multi-cursor edit, leave EVM, then press `\ g S`
Result: the last cursor layout is recreated
```

## Tutorial Coverage Plan

### Core Tutorial
- `tutorial/00-start-here.txt` for one-time instructions
- `tutorial/01-03` for cursor creation, modes, and navigation
- `tutorial/04-08` for editing workflows
- `tutorial/09-11` for fallback execution, scoped search, and history/recovery
