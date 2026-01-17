;;; evm.el --- Evil Visual Multi - Multiple cursors for evil-mode -*- lexical-binding: t; -*-

;; Copyright (C) 2025
;; SPDX-License-Identifier: GPL-3.0-or-later

;; Author: Your Name
;; Version: 0.1.0
;; Package-Requires: ((emacs "27.1") (evil "1.14.0"))
;; Keywords: evil, multiple-cursors, editing
;; URL: https://github.com/yourname/evil-visual-multi

;;; Commentary:

;; Evil Visual Multi (evm) provides multiple cursors functionality
;; for evil-mode, inspired by vim-visual-multi.
;;
;; Features:
;; - Two modes: cursor mode (points) and extend mode (selections)
;; - Leader cursor with distinct highlighting
;; - VM Registers for multi-cursor yank/paste
;; - Integration with evil movements and text objects
;;
;; Quick start:
;; - C-n: Start with word under cursor, find next
;; - C-Down/C-Up: Add cursor below/above
;; - Tab: Toggle between cursor and extend mode
;; - Esc: Exit evm

;;; Code:

(require 'evm-core)

;;; Keymaps

(defvar evm-mode-map (make-sparse-keymap)
  "Keymap for evm mode (common bindings).")

(defvar evm-cursor-map (make-sparse-keymap)
  "Keymap for cursor mode specific bindings.")

(defvar evm-extend-map (make-sparse-keymap)
  "Keymap for extend mode specific bindings.")

;; Common bindings (both modes)
(define-key evm-mode-map (kbd "<escape>") #'evm-exit)
(define-key evm-mode-map (kbd "<tab>") #'evm-toggle-mode)
(define-key evm-mode-map (kbd "n") #'evm-find-next)
(define-key evm-mode-map (kbd "N") #'evm-find-prev)
(define-key evm-mode-map (kbd "]") #'evm-goto-next)
(define-key evm-mode-map (kbd "[") #'evm-goto-prev)
(define-key evm-mode-map (kbd "q") #'evm-skip-current)
(define-key evm-mode-map (kbd "Q") #'evm-remove-current)

;; Movement (common)
(define-key evm-mode-map (kbd "h") #'evm-backward-char)
(define-key evm-mode-map (kbd "j") #'evm-next-line)
(define-key evm-mode-map (kbd "k") #'evm-previous-line)
(define-key evm-mode-map (kbd "l") #'evm-forward-char)
(define-key evm-mode-map (kbd "w") #'evm-forward-word)
(define-key evm-mode-map (kbd "b") #'evm-backward-word)
(define-key evm-mode-map (kbd "e") #'evm-forward-word-end)
(define-key evm-mode-map (kbd "0") #'evm-beginning-of-line)
(define-key evm-mode-map (kbd "^") #'evm-first-non-blank)
(define-key evm-mode-map (kbd "$") #'evm-end-of-line)

;; Prefix commands
(define-key evm-mode-map (kbd "\\ A") #'evm-select-all)
(define-key evm-mode-map (kbd "\\ a") #'evm-align)
(define-key evm-mode-map (kbd "\\ g S") #'evm-reselect-last)
(define-key evm-mode-map (kbd "\\ r") #'evm-toggle-restrict)
(define-key evm-mode-map (kbd "\\ z") #'evm-run-normal)
(define-key evm-mode-map (kbd "\\ @") #'evm-run-macro)
(define-key evm-mode-map (kbd "\\ :") #'evm-run-ex)

;; Cursor mode specific
(define-key evm-cursor-map (kbd "i") #'evm-insert)
(define-key evm-cursor-map (kbd "a") #'evm-append)
(define-key evm-cursor-map (kbd "I") #'evm-insert-line)
(define-key evm-cursor-map (kbd "A") #'evm-append-line)
(define-key evm-cursor-map (kbd "o") #'evm-open-below)
(define-key evm-cursor-map (kbd "O") #'evm-open-above)
(define-key evm-cursor-map (kbd "x") #'evm-delete-char)
(define-key evm-cursor-map (kbd "X") #'evm-delete-char-backward)
(define-key evm-cursor-map (kbd "r") #'evm-replace-char)
(define-key evm-cursor-map (kbd "~") #'evm-toggle-case-char)
(define-key evm-cursor-map (kbd "v") #'evm-enter-extend)
;; Operators with motions
(define-key evm-cursor-map (kbd "d") #'evm-operator-delete)
(define-key evm-cursor-map (kbd "c") #'evm-operator-change)
(define-key evm-cursor-map (kbd "y") #'evm-operator-yank)
(define-key evm-cursor-map (kbd "D") #'evm-delete-to-eol)
(define-key evm-cursor-map (kbd "C") #'evm-change-to-eol)
(define-key evm-cursor-map (kbd "Y") #'evm-yank-line)
(define-key evm-cursor-map (kbd "C-n") #'evm-add-next-match)
(define-key evm-cursor-map (kbd "<C-down>") #'evm-add-cursor-down)
(define-key evm-cursor-map (kbd "<C-up>") #'evm-add-cursor-up)
(define-key evm-cursor-map (kbd "<s-mouse-1>") #'evm-add-cursor-at-click)

;; Extend mode specific
(define-key evm-extend-map (kbd "y") #'evm-yank)
(define-key evm-extend-map (kbd "d") #'evm-delete)
(define-key evm-extend-map (kbd "c") #'evm-change)
(define-key evm-extend-map (kbd "s") #'evm-change)
(define-key evm-extend-map (kbd "p") #'evm-paste-after)
(define-key evm-extend-map (kbd "P") #'evm-paste-before)
(define-key evm-extend-map (kbd "o") #'evm-flip-direction)
(define-key evm-extend-map (kbd "U") #'evm-upcase)
(define-key evm-extend-map (kbd "u") #'evm-downcase)
(define-key evm-extend-map (kbd "~") #'evm-toggle-case)
(define-key evm-extend-map (kbd "C-n") #'evm-add-next-match)
(define-key evm-extend-map (kbd "<s-mouse-1>") #'evm-add-cursor-at-click)

;; Set parent keymaps
(set-keymap-parent evm-cursor-map evm-mode-map)
(set-keymap-parent evm-extend-map evm-mode-map)

;;; Minor mode

(defvar evm--saved-cursor nil
  "Saved cursor type before entering evm.")

;;;###autoload
(define-minor-mode evm-mode
  "Minor mode for evil-visual-multi."
  :lighter nil
  :keymap nil
  :group 'evm
  (if evm-mode
      (progn
        ;; Save original cursor
        (setq evm--saved-cursor cursor-type)
        ;; Update keymap based on mode
        (evm--update-keymap)
        ;; Add mode-line indicator
        (add-to-list 'mode-line-misc-info '(:eval (evm--mode-line-indicator))))
    ;; Remove from emulation-mode-map-alists
    (setq evm--emulation-alist nil)
    ;; Remove mode-line indicator
    (setq mode-line-misc-info
          (cl-remove-if (lambda (x) (and (listp x) (eq (car x) :eval)
                                         (eq (caadr x) 'evm--mode-line-indicator)))
                        mode-line-misc-info))
    ;; Restore cursor
    (when evm--saved-cursor
      (setq cursor-type evm--saved-cursor))))

(defvar evm--emulation-alist nil
  "Alist for `emulation-mode-map-alists' to override evil keymaps.")

(defun evm--update-keymap ()
  "Update keymap based on current evm mode.
Uses `emulation-mode-map-alists' to override evil bindings."
  (when evm-mode
    ;; Use emulation-mode-map-alists to get priority over evil
    (setq evm--emulation-alist
          (list (cons 'evm-mode
                      (if (evm-cursor-mode-p)
                          evm-cursor-map
                        evm-extend-map))))
    ;; Always remove and re-add to ensure we're at the front
    (setq emulation-mode-map-alists
          (delq 'evm--emulation-alist emulation-mode-map-alists))
    (push 'evm--emulation-alist emulation-mode-map-alists)))

;;; Activation/Deactivation

(defun evm-activate ()
  "Activate evm mode in current buffer."
  (interactive)
  (unless evm--state
    (setq evm--state (make-evm-state)))
  (setf (evm-state-active-p evm--state) t
        (evm-state-mode evm--state) 'cursor
        (evm-state-regions evm--state) nil
        (evm-state-id-counter evm--state) 0
        (evm-state-leader-id evm--state) nil
        (evm-state-patterns evm--state) nil
        (evm-state-search-direction evm--state) 1
        (evm-state-multiline-p evm--state) nil
        (evm-state-whole-word-p evm--state) t
        (evm-state-case-fold-p evm--state) nil
        (evm-state-undo-snapshots evm--state) nil
        (evm-state-registers evm--state) (make-hash-table :test 'eq))
  (evm-mode 1)
  (evil-normal-state)
  ;; Add hooks
  (add-hook 'pre-command-hook #'evm--pre-command nil t)
  (add-hook 'post-command-hook #'evm--post-command nil t)
  (add-hook 'before-change-functions #'evm--before-change nil t)
  (add-hook 'after-change-functions #'evm--after-change nil t)
  (force-mode-line-update))

(defun evm-exit ()
  "Exit evm mode, removing all cursors."
  (interactive)
  (when (evm-active-p)
    ;; Save for reselect
    (evm--save-for-reselect)
    ;; Sync registers
    (evm--sync-to-evil-registers)
    ;; Remove overlays
    (evm--remove-all-overlays)
    (evm--hide-match-preview)
    ;; Clear restriction
    (evm--clear-restrict)
    ;; Remove hooks
    (remove-hook 'pre-command-hook #'evm--pre-command t)
    (remove-hook 'post-command-hook #'evm--post-command t)
    (remove-hook 'before-change-functions #'evm--before-change t)
    (remove-hook 'after-change-functions #'evm--after-change t)
    ;; Reset state
    (setf (evm-state-active-p evm--state) nil
          (evm-state-regions evm--state) nil)
    (evm-mode -1)
    (force-mode-line-update)))

(defun evm--save-for-reselect ()
  "Save current region positions for later reselection."
  (when (evm-state-regions evm--state)
    (setf (evm-state-last-regions evm--state)
          (mapcar (lambda (r)
                    (cons (marker-position (evm-region-beg r))
                          (marker-position (evm-region-end r))))
                  (evm-state-regions evm--state)))))

(defun evm--sync-to-evil-registers ()
  "Sync VM register to evil registers on exit."
  (when-let ((contents (gethash ?\" (evm-state-registers evm--state))))
    (evil-set-register ?\" (string-join contents "\n"))))

;;; Hooks

(defvar evm--in-change nil
  "Flag to track when we're in the middle of a change.")

;;; Insert mode tracking (real-time replication)

(defvar-local evm--insert-active nil
  "Non-nil when evm insert mode is active.")

(defvar-local evm--insert-replicating nil
  "Non-nil when we are replicating changes to other cursors.
Used to prevent infinite recursion.")

(defvar-local evm--insert-last-point nil
  "Last known point position during insert mode.")

(defun evm--start-insert-mode ()
  "Start tracking for evm insert mode with real-time replication."
  (when (and (evm-active-p) (not evm--insert-active))
    (setq evm--insert-active t
          evm--insert-replicating nil
          evm--insert-last-point (point))
    ;; Disable evm keymaps during insert mode (let evil handle input)
    (setq evm--emulation-alist nil)
    (when-let ((entry (assq 'evm-mode minor-mode-map-alist)))
      (setcdr entry nil))
    ;; Add hooks for real-time replication
    (add-hook 'after-change-functions #'evm--insert-after-change nil t)
    (add-hook 'evil-insert-state-exit-hook #'evm--stop-insert-mode nil t)
    ;; Update overlays to ensure they're positioned correctly for insert mode
    (evm--update-all-overlays)))

(defun evm--insert-after-change (beg end old-len)
  "Replicate changes at leader to all other cursors in real-time.
BEG and END are the changed region, OLD-LEN is length of replaced text."
  (when (and evm--insert-active
             (not evm--insert-replicating)
             (evm-active-p))
    (let* ((leader (evm--leader-region))
           (leader-pos (when leader (marker-position (evm-region-beg leader))))
           (new-len (- end beg))
           (delta (- new-len old-len)))
      ;; Only replicate if the change is near the leader cursor
      (when (and leader-pos
                 ;; Change must be at or before current leader position
                 (<= beg (+ leader-pos (max 0 (- old-len)))))
        (let ((evm--insert-replicating t)
              (inhibit-modification-hooks t))
          ;; Get the inserted/changed text (or nil for pure deletion)
          (let ((new-text (when (> new-len 0)
                            (buffer-substring-no-properties beg end)))
                (other-regions (cl-remove-if #'evm--leader-p
                                             (evm-state-regions evm--state))))
            ;; Apply to other regions from end to beginning
            (dolist (region (cl-sort (copy-sequence other-regions) #'>
                                     :key (lambda (r) (marker-position (evm-region-beg r)))))
              (let ((region-pos (marker-position (evm-region-beg region))))
                (save-excursion
                  (goto-char region-pos)
                  ;; Delete old text if any
                  (when (> old-len 0)
                    (delete-char (- (min old-len (- (point-max) (point))))))
                  ;; Insert new text if any
                  (when new-text
                    (insert new-text))
                  ;; Update marker to current position
                  (set-marker (evm-region-beg region) (point))
                  (set-marker (evm-region-end region) (point))
                  (set-marker (evm-region-anchor region) (point))))))
          ;; Update leader marker position too
          (set-marker (evm-region-beg leader) (point))
          (set-marker (evm-region-end leader) (point))
          (set-marker (evm-region-anchor leader) (point))
          ;; Update overlays to show new positions
          (evm--update-all-overlays))
        ;; Update last point
        (setq evm--insert-last-point (point))))))

(defun evm--stop-insert-mode ()
  "Handle exit from evm insert mode."
  (when (and evm--insert-active (evm-active-p))
    ;; Remove hooks
    (remove-hook 'after-change-functions #'evm--insert-after-change t)
    (remove-hook 'evil-insert-state-exit-hook #'evm--stop-insert-mode t)
    (setq evm--insert-active nil
          evm--insert-replicating nil
          evm--insert-last-point nil)
    ;; Add one-shot hook to sync after evil adjusts point in normal state
    (add-hook 'evil-normal-state-entry-hook #'evm--sync-after-insert-exit nil t)
    ;; Restore evm keymaps
    (when-let ((entry (assq 'evm-mode minor-mode-map-alist)))
      (setcdr entry evm-mode-map))
    (evm--update-keymap)))

(defun evm--sync-after-insert-exit ()
  "Sync cursors after exiting insert mode.
Evil moves point back by 1 when exiting insert (unless at bol).
We adjust all markers the same way."
  (remove-hook 'evil-normal-state-entry-hook #'evm--sync-after-insert-exit t)
  (when (evm-active-p)
    ;; Adjust all cursors like evil adjusts point on insert exit
    (dolist (region (evm-state-regions evm--state))
      (let ((pos (evm--region-cursor-pos region)))
        (evm--region-set-cursor-pos region (evm--adjust-cursor-pos pos))))
    (evm--update-all-overlays)))

(defun evm--before-change (_beg _end)
  "Called before buffer modification."
  (when (and (evm-active-p) (not evm--in-change))
    (setq evm--in-change t)
    (evm--push-undo-snapshot)))

(defun evm--after-change (_beg _end _len)
  "Called after buffer modification."
  (when (and (evm-active-p) evm--in-change)
    (setq evm--in-change nil)
    ;; Clamp markers to buffer bounds
    (evm--clamp-markers)
    (evm--check-and-merge-overlapping)
    (evm--update-all-overlays)))

(defun evm--clamp-markers ()
  "Clamp all region markers to buffer bounds."
  (let ((max-pos (point-max)))
    (dolist (region (evm-state-regions evm--state))
      (let ((beg (marker-position (evm-region-beg region)))
            (end (marker-position (evm-region-end region)))
            (anchor (marker-position (evm-region-anchor region))))
        (when (> beg max-pos)
          (set-marker (evm-region-beg region) max-pos))
        (when (> end max-pos)
          (set-marker (evm-region-end region) max-pos))
        (when (> anchor max-pos)
          (set-marker (evm-region-anchor region) max-pos))))))

(defun evm--pre-command ()
  "Called before each command."
  ;; Currently empty but kept for potential future use
  nil)

(defvar-local evm--last-buffer-tick nil
  "Last buffer modification tick, used to detect changes.")

(defun evm--post-command ()
  "Called after each command."
  (when (evm-active-p)
    ;; After undo command, resync regions with pattern
    (when (and (memq this-command '(undo evil-undo undo-tree-undo undo-fu-only-undo))
               (car (evm-state-patterns evm--state)))
      (evm--resync-regions-to-pattern))
    ;; Ensure overlays are in sync with markers after buffer modifications
    ;; (fixes visual glitches after undo where overlays drift from markers)
    (let ((current-tick (buffer-modified-tick)))
      (unless (eql current-tick evm--last-buffer-tick)
        (setq evm--last-buffer-tick current-tick)
        (evm--update-all-overlays)))
    ;; Keep real cursor at leader visual position
    ;; In extend mode, this is on the last selected char (end-1), not after
    (when-let ((leader (evm--leader-region)))
      (let ((leader-pos (evm--region-visual-cursor-pos leader)))
        (unless (= (point) leader-pos)
          (goto-char leader-pos))))))

(defun evm--adjust-cursor-pos (pos)
  "Adjust POS like evil-adjust-cursor does.
In normal state, cursor can't be past the last character of a non-empty line."
  (save-excursion
    (goto-char pos)
    (if (and (= pos (line-end-position))
             (not (= (line-beginning-position) (line-end-position)))) ; non-empty line
        (1- pos)
      pos)))

(defun evm--resync-regions-to-pattern ()
  "Resync region positions to match pattern occurrences in buffer.
Called after undo to fix marker drift.
Only moves a region if there's a match very close to its current position
\(within the length of the match pattern). This prevents jumping to distant
matches when text hasn't been fully restored by undo."
  (let* ((pattern (car (evm-state-patterns evm--state)))
         (matches '())
         (cursor-mode-p (evm-cursor-mode-p)))
    ;; Find all matches
    (save-excursion
      (goto-char (point-min))
      (while (re-search-forward pattern nil t)
        (push (cons (match-beginning 0) (match-end 0)) matches)))
    (setq matches (nreverse matches))
    (when matches
      ;; For each region, find a match that contains or is adjacent to current position
      (dolist (region (evm-state-regions evm--state))
        (let* ((region-beg (marker-position (evm-region-beg region)))
               (region-end (marker-position (evm-region-end region)))
               (found-match nil))
          ;; Find match that overlaps with region or is very close (within match length)
          (dolist (match matches)
            (let* ((match-beg (car match))
                   (match-end (cdr match))
                   (match-len (- match-end match-beg)))
              ;; Check if region position is within or very close to match
              (when (or
                     ;; Region beg is inside match
                     (and (>= region-beg match-beg) (<= region-beg match-end))
                     ;; Region end is inside match
                     (and (>= region-end match-beg) (<= region-end match-end))
                     ;; Region beg is just before match (within match-len)
                     (and (< region-beg match-beg) (>= region-beg (- match-beg match-len)))
                     ;; Region beg is just after match (within match-len)
                     (and (> region-beg match-end) (<= region-beg (+ match-end match-len))))
                (setq found-match match))))
          ;; Only update if we found a nearby match
          (when found-match
            (let ((beg (if cursor-mode-p (cdr found-match) (car found-match)))
                  (end (cdr found-match))
                  (anchor (if cursor-mode-p (cdr found-match) (car found-match))))
              (set-marker (evm-region-beg region) beg)
              (set-marker (evm-region-end region) end)
              (set-marker (evm-region-anchor region) anchor)
              (setf (evm-region-dir region) 1)))))
      (evm--update-all-overlays))))

;;; Movement commands

(defun evm-forward-char ()
  "Move all cursors forward one character."
  (interactive)
  (evm--move-cursors #'evm--move-char 1))

(defun evm-backward-char ()
  "Move all cursors backward one character."
  (interactive)
  (evm--move-cursors #'evm--move-char -1))

(defun evm-next-line ()
  "Move all cursors to next line, preserving column."
  (interactive)
  (evm--move-cursors-vertically 1))

(defun evm-previous-line ()
  "Move all cursors to previous line, preserving column."
  (interactive)
  (evm--move-cursors-vertically -1))

(defun evm-forward-word ()
  "Move all cursors forward one word."
  (interactive)
  (evm--move-cursors #'evm--move-word 1))

(defun evm-backward-word ()
  "Move all cursors backward one word."
  (interactive)
  (evm--move-cursors #'evm--move-word-back 1))

(defun evm-forward-word-end ()
  "Move all cursors to end of word."
  (interactive)
  (evm--move-cursors #'evm--move-word-end 1))

(defun evm-beginning-of-line ()
  "Move all cursors to beginning of line."
  (interactive)
  (evm--move-cursors #'evm--move-line-beg))

(defun evm-end-of-line ()
  "Move all cursors to end of line."
  (interactive)
  (evm--move-cursors #'evm--move-line-end))

(defun evm-first-non-blank ()
  "Move all cursors to first non-blank character."
  (interactive)
  (evm--move-cursors #'evm--move-first-non-blank))

;;; Cursor navigation

(defun evm-goto-next ()
  "Move leader to next cursor."
  (interactive)
  (when (evm-active-p)
    (let* ((regions (evm-state-regions evm--state))
           (leader-idx (evm--leader-index))
           (next-idx (mod (1+ leader-idx) (length regions)))
           (next-region (nth next-idx regions)))
      (evm--set-leader next-region)
      (goto-char (evm--region-cursor-pos next-region)))))

(defun evm-goto-prev ()
  "Move leader to previous cursor."
  (interactive)
  (when (evm-active-p)
    (let* ((regions (evm-state-regions evm--state))
           (leader-idx (evm--leader-index))
           (prev-idx (mod (1- leader-idx) (length regions)))
           (prev-region (nth prev-idx regions)))
      (evm--set-leader prev-region)
      (goto-char (evm--region-cursor-pos prev-region)))))

(defun evm-skip-current ()
  "Skip current match: delete it and find next occurrence in search direction."
  (interactive)
  (when (evm-active-p)
    (let* ((leader (evm--leader-region))
           (pattern (car (evm-state-patterns evm--state)))
           (direction (evm-state-search-direction evm--state))
           ;; Save position BEFORE deleting, so we search from correct place
           (search-from (if (= direction 1)
                            (1+ (marker-position (evm-region-end leader)))
                          (1- (marker-position (evm-region-beg leader))))))
      ;; Delete current cursor
      (evm--delete-region leader)
      ;; Find next occurrence starting from saved position in search direction
      (when pattern
        (if (= direction 1)
            (evm--find-and-add-next-from pattern search-from)
          (evm--find-and-add-prev-from pattern search-from)))
      ;; If no cursors left and no new found, exit
      (when (= (evm-region-count) 0)
        (evm-exit)))))

(defun evm-remove-current ()
  "Remove current cursor and select the previous one.
If on the first cursor, select the new first cursor (was second)."
  (interactive)
  (when (evm-active-p)
    (let ((leader (evm--leader-region))
          (old-idx (evm--leader-index)))
      (if (= (evm-region-count) 1)
          (evm-exit)
        ;; Delete first, then select by index
        (evm--delete-region leader)
        ;; Select previous, or 0 if we were first
        (let* ((new-idx (max 0 (1- old-idx)))
               (regions (evm-state-regions evm--state))
               (new-region (nth new-idx regions)))
          (evm--set-leader new-region)
          (goto-char (evm--region-cursor-pos new-region)))))))

;;; Cursor creation

;;;###autoload
(defun evm-find-word ()
  "Start evm with word under cursor in extend mode with word selected.
Like vim-visual-multi, immediately enters extend mode with the word highlighted."
  (interactive)
  ;; Exit visual state if active
  (when (evil-visual-state-p)
    (evil-exit-visual-state))
  (let* ((bounds (bounds-of-thing-at-point 'symbol))
         (word (when bounds
                 (buffer-substring-no-properties (car bounds) (cdr bounds)))))
    (unless word
      (user-error "No word at point"))
    (unless (evm-active-p)
      (evm-activate))
    ;; Apply pending restriction if any
    (when evm--pending-restrict
      (evm--set-restrict (car evm--pending-restrict) (cdr evm--pending-restrict))
      (setq evm--pending-restrict nil))
    (let ((pattern (concat "\\_<" (regexp-quote word) "\\_>")))
      ;; Add pattern
      (push pattern (evm-state-patterns evm--state))
      ;; Create first region with full word selection
      (evm--create-region (car bounds) (cdr bounds) pattern)
      ;; Switch to extend mode immediately
      (setf (evm-state-mode evm--state) 'extend)
      ;; Update overlays and keymap for extend mode
      (evm--update-all-overlays)
      (evm--update-keymap)
      ;; Position cursor at end of word
      (goto-char (1- (cdr bounds)))
      ;; Show matches (respecting restriction)
      (evm--show-match-preview-restricted pattern))))

(defun evm-add-next-match ()
  "Add next match for current pattern."
  (interactive)
  (when (evm-active-p)
    (let ((pattern (car (evm-state-patterns evm--state))))
      (unless pattern
        (user-error "No search pattern"))
      (evm--find-and-add-next pattern))))

(defun evm--find-and-add-next (pattern)
  "Find next match for PATTERN and move/add cursor there."
  (let* ((leader (evm--leader-region))
         (start-pos (if leader
                        (1+ (marker-position (evm-region-end leader)))
                      (1+ (point)))))
    (evm--find-and-add-next-from pattern start-pos)))

(defun evm--find-and-add-next-from (pattern start-pos)
  "Find next match for PATTERN starting from START-POS and move/add cursor there.
Creates region with full match selection in extend mode.
Respects current restriction if active."
  (let ((bounds (evm--restrict-bounds))
        found-beg found-end)
    (save-excursion
      (goto-char (min start-pos (if bounds (cdr bounds) (point-max))))
      (if (and (re-search-forward pattern (when bounds (cdr bounds)) t)
               (evm--point-in-restrict-p (match-beginning 0)))
          (setq found-beg (match-beginning 0)
                found-end (match-end 0))
        ;; Wrap around (to restriction start or buffer start)
        (goto-char (if bounds (car bounds) (point-min)))
        (when (and (re-search-forward pattern (when bounds (cdr bounds)) t)
                   (evm--point-in-restrict-p (match-beginning 0)))
          (setq found-beg (match-beginning 0)
                found-end (match-end 0)))))
    (when found-beg
      ;; Check if cursor already exists at this position
      (let ((existing (cl-find-if
                       (lambda (r)
                         (= (marker-position (evm-region-beg r)) found-beg))
                       (evm-state-regions evm--state))))
        (if existing
            ;; Just move leader to existing cursor
            (progn
              (evm--set-leader existing)
              (goto-char (1- found-end)))
          ;; Create new region with full selection
          (let ((new-region (evm--create-region found-beg found-end pattern)))
            (evm--set-leader new-region)
            (evm--update-all-overlays)
            (goto-char (1- found-end))))))))

(defun evm-find-next ()
  "Find next occurrence, move leader there."
  (interactive)
  (when (evm-active-p)
    (let ((pattern (car (evm-state-patterns evm--state))))
      (when pattern
        (setf (evm-state-search-direction evm--state) 1)
        (evm--find-and-add-next pattern)))))

(defun evm-find-prev ()
  "Find previous occurrence, move leader there."
  (interactive)
  (when (evm-active-p)
    (let ((pattern (car (evm-state-patterns evm--state))))
      (when pattern
        (setf (evm-state-search-direction evm--state) -1)
        (evm--find-and-add-prev pattern)))))

(defun evm--find-and-add-prev (pattern)
  "Find previous match for PATTERN and move/add cursor there."
  (let* ((leader (evm--leader-region))
         (start-pos (if leader
                        (1- (marker-position (evm-region-beg leader)))
                      (1- (point)))))
    (evm--find-and-add-prev-from pattern start-pos)))

(defun evm--find-and-add-prev-from (pattern start-pos)
  "Find previous match for PATTERN starting from START-POS and move/add cursor there.
Creates region with full match selection in extend mode.
Respects current restriction if active."
  (let ((bounds (evm--restrict-bounds))
        found-beg found-end)
    (save-excursion
      (goto-char (max start-pos (if bounds (car bounds) (point-min))))
      (if (and (re-search-backward pattern (when bounds (car bounds)) t)
               (evm--point-in-restrict-p (match-beginning 0)))
          (setq found-beg (match-beginning 0)
                found-end (match-end 0))
        ;; Wrap around (to restriction end or buffer end)
        (goto-char (if bounds (cdr bounds) (point-max)))
        (when (and (re-search-backward pattern (when bounds (car bounds)) t)
                   (evm--point-in-restrict-p (match-beginning 0)))
          (setq found-beg (match-beginning 0)
                found-end (match-end 0)))))
    (when found-beg
      ;; Check if cursor already exists at this position
      (let ((existing (cl-find-if
                       (lambda (r)
                         (= (marker-position (evm-region-beg r)) found-beg))
                       (evm-state-regions evm--state))))
        (if existing
            ;; Just move leader to existing cursor
            (progn
              (evm--set-leader existing)
              (goto-char (1- found-end)))
          ;; Create new region with full selection
          (let ((new-region (evm--create-region found-beg found-end pattern)))
            (evm--set-leader new-region)
            (evm--update-all-overlays)
            (goto-char (1- found-end))))))))

(defun evm-add-cursor-down ()
  "Add cursor on line below."
  (interactive)
  (unless (evm-active-p)
    (evm-activate)
    (evm--create-region (point) (point)))
  (let* ((leader (evm--leader-region))
         (col (current-column))
         new-pos)
    (save-excursion
      (forward-line 1)
      (move-to-column col)
      (setq new-pos (point)))
    (when (and new-pos (not (= new-pos (evm--region-cursor-pos leader))))
      (let ((new-region (evm--create-region new-pos new-pos)))
        (evm--set-leader new-region)
        (goto-char new-pos)))))

(defun evm-add-cursor-up ()
  "Add cursor on line above."
  (interactive)
  (unless (evm-active-p)
    (evm-activate)
    (evm--create-region (point) (point)))
  (let* ((leader (evm--leader-region))
         (col (current-column))
         new-pos)
    (save-excursion
      (forward-line -1)
      (move-to-column col)
      (setq new-pos (point)))
    (when (and new-pos (not (= new-pos (evm--region-cursor-pos leader))))
      (let ((new-region (evm--create-region new-pos new-pos)))
        (evm--set-leader new-region)
        (goto-char new-pos)))))

;;;###autoload
(defun evm-add-cursor-at-click (event)
  "Add a cursor at mouse click position, or remove if clicking on existing cursor.
EVENT is the mouse event.
- Click on empty position: create new cursor
- Click on existing cursor (any): remove it"
  (interactive "e")
  (let ((pos (posn-point (event-start event))))
    (when pos
      (unless (evm-active-p)
        (evm-activate)
        ;; Create first cursor at current point
        (evm--create-region (point) (point)))
      ;; Check if cursor already exists at this position
      (let ((existing (cl-find-if
                       (lambda (r)
                         (= (evm--region-cursor-pos r) pos))
                       (evm-state-regions evm--state))))
        (if existing
            ;; Cursor exists - remove it (toggle behavior)
            (if (= (evm-region-count) 1)
                ;; Last cursor - exit evm
                (evm-exit)
              ;; Remove cursor and select another if needed
              (let ((was-leader (eq existing (evm--leader-region))))
                (evm--delete-region existing)
                (when was-leader
                  ;; Select first remaining cursor as new leader
                  (let ((new-leader (car (evm-state-regions evm--state))))
                    (when new-leader
                      (evm--set-leader new-leader)
                      (goto-char (evm--region-cursor-pos new-leader)))))))
          ;; Create new cursor at click position
          (let ((new-region (evm--create-region pos pos)))
            (evm--set-leader new-region)
            (goto-char pos)))))))

(defun evm-select-all ()
  "Select all occurrences of current pattern.
In cursor mode: creates point cursors at end of each match.
In extend mode: creates full selections covering each match.
Respects current restriction if active."
  (interactive)
  (when (evm-active-p)
    (let ((pattern (car (evm-state-patterns evm--state)))
          (bounds (evm--restrict-bounds))
          (cursor-mode-p (evm-cursor-mode-p)))
      (unless pattern
        (user-error "No search pattern"))
      (save-excursion
        (goto-char (if bounds (car bounds) (point-min)))
        (while (re-search-forward pattern (when bounds (cdr bounds)) t)
          (let* ((beg (match-beginning 0))
                 (end (match-end 0)))
            (when (evm--point-in-restrict-p beg)
              (unless (cl-find-if
                       (lambda (r)
                         ;; In cursor mode: check by cursor position (end)
                         ;; In extend mode: check by region start (beg)
                         (if cursor-mode-p
                             (= (evm--region-cursor-pos r) end)
                           (= (marker-position (evm-region-beg r)) beg)))
                       (evm-state-regions evm--state))
                ;; In cursor mode: point cursor at end
                ;; In extend mode: full selection
                (if cursor-mode-p
                    (evm--create-region end end pattern)
                  (evm--create-region beg end pattern)))))))
      (evm--update-all-overlays))))

;;; Mode switching commands

(defun evm-enter-extend ()
  "Enter extend mode from cursor mode."
  (interactive)
  (when (evm-cursor-mode-p)
    (evm--enter-extend-mode)
    (evm--update-keymap)))

;;; Cursor mode editing commands

(defun evm-insert ()
  "Enter insert mode at all cursor positions."
  (interactive)
  (when (evm-cursor-mode-p)
    (evm--push-undo-snapshot)
    (evm--start-insert-mode)
    (evil-insert-state)))

(defun evm-append ()
  "Enter insert mode after all cursor positions."
  (interactive)
  (when (evm-cursor-mode-p)
    (evm--push-undo-snapshot)
    (evm--move-cursors #'forward-char 1)
    (evm--start-insert-mode)
    (evil-insert-state)))

(defun evm-insert-line ()
  "Enter insert mode at beginning of lines."
  (interactive)
  (when (evm-cursor-mode-p)
    (evm--push-undo-snapshot)
    (evm--move-cursors #'back-to-indentation)
    (evm--start-insert-mode)
    (evil-insert-state)))

(defun evm-append-line ()
  "Enter insert mode at end of lines."
  (interactive)
  (when (evm-cursor-mode-p)
    (evm--push-undo-snapshot)
    (evm--move-cursors #'end-of-line)
    (evm--start-insert-mode)
    (evil-insert-state)))

(defun evm-open-below ()
  "Open line below and enter insert mode."
  (interactive)
  (when (evm-cursor-mode-p)
    (evm--push-undo-snapshot)
    (evm--execute-at-all-cursors
     (lambda ()
       (end-of-line)
       (newline-and-indent))
     t)  ; update-markers = t
    (evm--start-insert-mode)
    (evil-insert-state)))

(defun evm-open-above ()
  "Open line above and enter insert mode."
  (interactive)
  (when (evm-cursor-mode-p)
    (evm--push-undo-snapshot)
    (evm--execute-at-all-cursors
     (lambda ()
       (beginning-of-line)
       (newline)
       (forward-line -1)
       (indent-according-to-mode))
     t)  ; update-markers = t
    (evm--start-insert-mode)
    (evil-insert-state)))

(defun evm-delete-char ()
  "Delete character at all cursors."
  (interactive)
  (when (evm-cursor-mode-p)
    (evm--push-undo-snapshot)
    (evm--execute-at-all-cursors
     (lambda ()
       (unless (eobp)
         (delete-char 1))))))

(defun evm-delete-char-backward ()
  "Delete character before all cursors."
  (interactive)
  (when (evm-cursor-mode-p)
    (evm--push-undo-snapshot)
    (evm--execute-at-all-cursors
     (lambda ()
       (unless (bobp)
         (delete-char -1))))))

(defun evm-replace-char (char)
  "Replace character at all cursors with CHAR."
  (interactive "cReplace with: ")
  (when (evm-cursor-mode-p)
    (evm--push-undo-snapshot)
    (evm--execute-at-all-cursors
     (lambda ()
       (unless (eobp)
         (delete-char 1)
         (insert char)
         (backward-char 1))))))

(defun evm-toggle-case-char ()
  "Toggle case of character at all cursors."
  (interactive)
  (when (evm-cursor-mode-p)
    (evm--push-undo-snapshot)
    (evm--execute-at-all-cursors
     (lambda ()
       (unless (eobp)
         (let* ((char (char-after))
                (new-char (if (eq (upcase char) char)
                              (downcase char)
                            (upcase char))))
           (delete-char 1)
           (insert new-char)
           (backward-char 1)))))))

;;; Extend mode editing commands

(defun evm-yank ()
  "Yank content of all regions to VM register."
  (interactive)
  (when (evm-extend-mode-p)
    (let ((contents (mapcar (lambda (r)
                              (buffer-substring-no-properties
                               (marker-position (evm-region-beg r))
                               (marker-position (evm-region-end r))))
                            (evm-state-regions evm--state))))
      (puthash ?\" contents (evm-state-registers evm--state))
      (kill-new (car contents))
      (message "Yanked %d regions" (length contents)))))

(defun evm-delete ()
  "Delete content of all regions."
  (interactive)
  (when (evm-extend-mode-p)
    (evm--push-undo-snapshot)
    ;; First yank
    (evm-yank)
    ;; Delete from end to beginning (inhibit hooks during batch delete)
    (let ((inhibit-modification-hooks t)
          (regions (reverse (evm-state-regions evm--state))))
      (dolist (region regions)
        (delete-region (marker-position (evm-region-beg region))
                       (marker-position (evm-region-end region)))))
    ;; Manually clamp and update after batch operation
    (evm--clamp-markers)
    (evm--check-and-merge-overlapping)
    ;; Switch to cursor mode
    (evm--enter-cursor-mode)
    (evm--update-keymap)))

(defun evm-change ()
  "Delete regions and enter insert mode."
  (interactive)
  (when (evm-extend-mode-p)
    (evm-delete)
    (evm--start-insert-mode)
    (evil-insert-state)))

(defun evm-paste-after ()
  "Paste VM register after regions."
  (interactive)
  (when (evm-extend-mode-p)
    (evm--paste-impl t)))

(defun evm-paste-before ()
  "Paste VM register before regions."
  (interactive)
  (when (evm-extend-mode-p)
    (evm--paste-impl nil)))

(defun evm--paste-impl (_after)
  "Paste implementation. _AFTER determines position (not yet used)."
  (evm--push-undo-snapshot)
  (let* ((contents (gethash ?\" (evm-state-registers evm--state)))
         (regions (evm-state-regions evm--state))
         (num-regions (length regions))
         (num-contents (length contents)))
    (unless contents
      (user-error "Nothing to paste"))
    ;; Delete current content first
    (let ((reversed (reverse regions)))
      (dolist (region reversed)
        (delete-region (marker-position (evm-region-beg region))
                       (marker-position (evm-region-end region)))))
    ;; Insert new content
    (cl-loop for region in (evm-state-regions evm--state)
             for idx from 0
             for content = (cond
                            ((= num-contents num-regions)
                             (nth idx contents))
                            ((= num-contents 1)
                             (car contents))
                            (t
                             (nth (mod idx num-contents) contents)))
             do (save-excursion
                  (goto-char (marker-position (evm-region-beg region)))
                  (insert content)))
    (evm--enter-cursor-mode)
    (evm--update-keymap)))

(defun evm-flip-direction ()
  "Flip direction of all regions (swap cursor and anchor)."
  (interactive)
  (when (evm-extend-mode-p)
    (dolist (region (evm-state-regions evm--state))
      (setf (evm-region-dir region)
            (if (= (evm-region-dir region) 1) 0 1)))
    (evm--update-all-overlays)))

(defun evm-upcase ()
  "Uppercase content of all regions."
  (interactive)
  (when (evm-extend-mode-p)
    (evm--push-undo-snapshot)
    (dolist (region (evm-state-regions evm--state))
      (upcase-region (marker-position (evm-region-beg region))
                     (marker-position (evm-region-end region))))))

(defun evm-downcase ()
  "Lowercase content of all regions."
  (interactive)
  (when (evm-extend-mode-p)
    (evm--push-undo-snapshot)
    (dolist (region (evm-state-regions evm--state))
      (downcase-region (marker-position (evm-region-beg region))
                       (marker-position (evm-region-end region))))))

(defun evm-toggle-case ()
  "Toggle case of content in all regions."
  (interactive)
  (when (evm-extend-mode-p)
    (evm--push-undo-snapshot)
    ;; Save positions before modification (markers will shift)
    (let ((saved-positions
           (mapcar (lambda (r)
                     (list r
                           (marker-position (evm-region-beg r))
                           (marker-position (evm-region-end r))
                           (marker-position (evm-region-anchor r))))
                   (evm-state-regions evm--state))))
      ;; Toggle case using delete/insert
      (dolist (region (evm-state-regions evm--state))
        (let ((beg (marker-position (evm-region-beg region)))
              (end (marker-position (evm-region-end region))))
          (save-excursion
            (goto-char beg)
            (while (< (point) end)
              (let* ((char (char-after))
                     (new-char (if (eq (upcase char) char)
                                   (downcase char)
                                 (upcase char))))
                (delete-char 1)
                (insert new-char))))))
      ;; Restore marker positions
      (dolist (saved saved-positions)
        (cl-destructuring-bind (region beg end anchor) saved
          (set-marker (evm-region-beg region) beg)
          (set-marker (evm-region-end region) end)
          (set-marker (evm-region-anchor region) anchor))))))

;;; Utility commands

(defun evm-align ()
  "Align all cursors vertically.
Spaces are inserted before the start of each region."
  (interactive)
  (when (evm-active-p)
    (evm--push-undo-snapshot)
    ;; Find max column based on region starts
    (let ((max-col 0))
      (dolist (region (evm-state-regions evm--state))
        (save-excursion
          (goto-char (marker-position (evm-region-beg region)))
          (setq max-col (max max-col (current-column)))))
      ;; Add spaces before region starts to align
      (dolist (region (reverse (evm-state-regions evm--state)))
        (save-excursion
          (goto-char (marker-position (evm-region-beg region)))
          (let ((spaces-needed (- max-col (current-column))))
            (when (> spaces-needed 0)
              (insert (make-string spaces-needed ?\s)))))))
    (evm--update-all-overlays)))

(defun evm-reselect-last ()
  "Reselect last cursors."
  (interactive)
  (when-let ((last (and evm--state (evm-state-last-regions evm--state))))
    (unless (evm-active-p)
      (evm-activate))
    (dolist (pos-pair last)
      (evm--create-region (car pos-pair) (car pos-pair)))))

;;; Run at Cursors commands

(defun evm-run-normal (cmd)
  "Run normal mode CMD at all cursor positions.
If CMD is nil, prompt for input."
  (interactive
   (list (read-string "Normal command: ")))
  (when (and (evm-active-p) (not (string-empty-p cmd)))
    (evm--push-undo-snapshot)
    ;; Temporarily disable evm keymaps to use original evil bindings
    (let ((saved-alist evm--emulation-alist))
      (setq evm--emulation-alist nil)
      (unwind-protect
          (evm--run-command-at-cursors
           (lambda ()
             (execute-kbd-macro cmd)))
        ;; Restore evm keymaps
        (setq evm--emulation-alist saved-alist)))))

(defun evm-run-macro (register)
  "Run macro from REGISTER at all cursor positions."
  (interactive
   (list (read-char "Register: ")))
  (when (evm-active-p)
    (let ((macro (evil-get-register register t)))
      (unless macro
        (user-error "Register '%c' is empty" register))
      (evm--push-undo-snapshot)
      ;; Temporarily disable evm keymaps to use original evil bindings
      (let ((saved-alist evm--emulation-alist))
        (setq evm--emulation-alist nil)
        (unwind-protect
            (evm--run-command-at-cursors
             (lambda ()
               (execute-kbd-macro macro)))
          ;; Restore evm keymaps
          (setq evm--emulation-alist saved-alist))))))

(defun evm-run-ex (cmd)
  "Run Ex command CMD at all cursor positions.
If CMD is nil, prompt for input."
  (interactive
   (list (read-string ": " nil 'evil-ex-history)))
  (when (and (evm-active-p) (not (string-empty-p cmd)))
    (evm--push-undo-snapshot)
    (evm--run-command-at-cursors
     (lambda ()
       (evil-ex-execute cmd)))))

(defun evm--run-command-at-cursors (fn &optional update-positions)
  "Execute FN at all cursor positions in buffer order.
Processes from end to beginning to preserve positions.
If UPDATE-POSITIONS is non-nil, update cursor positions to point after FN.
Updates overlays after execution."
  (let* ((regions (reverse (evm-state-regions evm--state)))
         (inhibit-modification-hooks t))
    ;; Temporarily disable post-command-hook to prevent cursor jumping to leader
    (remove-hook 'post-command-hook #'evm--post-command t)
    (unwind-protect
        (dolist (region regions)
          (goto-char (evm--region-cursor-pos region))
          (condition-case err
              (progn
                (funcall fn)
                ;; Only update position if explicitly requested (for movement commands)
                (when update-positions
                  (evm--region-set-cursor-pos region (point))))
            (error
             (message "Error at cursor %d: %s"
                      (evm-region-index region) (error-message-string err)))))
      ;; Re-enable post-command-hook
      (add-hook 'post-command-hook #'evm--post-command nil t)))
  ;; Clamp and update after all changes
  (evm--clamp-markers)
  (evm--check-and-merge-overlapping)
  (evm--update-all-overlays)
  ;; Move to leader
  (when-let ((leader (evm--leader-region)))
    (goto-char (evm--region-cursor-pos leader))))

(defun evm-toggle-restrict ()
  "Toggle restriction for evm search.
If in evil visual mode: set pending restriction for next C-n.
If evm active with restriction: clear it."
  (interactive)
  (cond
   ;; In visual mode: save pending restriction (don't activate evm yet)
   ((evil-visual-state-p)
    (let ((beg (region-beginning))
          (end (region-end)))
      (evil-exit-visual-state)
      (if (evm-active-p)
          ;; evm already active - apply restriction immediately
          (progn
            (evm--set-restrict beg end)
            (when-let ((pattern (car (evm-state-patterns evm--state))))
              (evm--show-match-preview-restricted pattern))
            (message "Restriction set"))
        ;; evm not active - save for later
        (setq evm--pending-restrict (cons beg end))
        (message "Restriction set (will apply on C-n)"))))
   ;; evm active with restriction: clear it
   ((and (evm-active-p) (evm--restrict-active-p))
    (evm--clear-restrict)
    (when-let ((pattern (car (evm-state-patterns evm--state))))
      (evm--show-match-preview pattern))
    (message "Restriction cleared"))
   ;; Pending restriction exists: clear it
   (evm--pending-restrict
    (setq evm--pending-restrict nil)
    (message "Pending restriction cleared"))
   ;; Nothing to do
   (t
    (message "Select region in visual mode to set restriction"))))

(defun evm-clear-restrict ()
  "Clear current restriction, allowing search in entire buffer."
  (interactive)
  (when (evm-active-p)
    (evm--clear-restrict)
    ;; Update match preview if we have a pattern
    (when-let ((pattern (car (evm-state-patterns evm--state))))
      (evm--show-match-preview pattern))
    (message "Restriction cleared")))

;;; Helper functions

(defun evm--execute-at-all-cursors (fn &optional update-markers)
  "Execute FN at all cursor positions.
FN is called with point at each cursor, from end to beginning.
If UPDATE-MARKERS is non-nil, update each cursor's marker to point
after FN completes (useful for commands like o/O that move point)."
  (let ((regions (reverse (evm-state-regions evm--state))))
    (dolist (region regions)
      (if update-markers
          ;; Don't use save-excursion - we want to capture the new position
          (progn
            (goto-char (evm--region-cursor-pos region))
            (funcall fn)
            ;; Update marker to new position
            (evm--region-set-cursor-pos region (point)))
        ;; Original behavior with save-excursion
        (save-excursion
          (goto-char (evm--region-cursor-pos region))
          (funcall fn)))))
  (evm--update-all-overlays)
  ;; Move to leader
  (when-let ((leader (evm--leader-region)))
    (goto-char (evm--region-cursor-pos leader))))

;;; Operator infrastructure (d/c/y with motions)

;; Single character motions
(defconst evm--single-motions
  '(?h ?j ?k ?l ?w ?e ?b ?W ?E ?B ?$ ?^ ?0 ?{ ?} ?\( ?\) ?% ?n ?N ?_ ?H ?M ?L ?G)
  "Single character motions.")

;; Double character motion prefixes
(defconst evm--double-motion-prefixes
  '(?i ?a ?f ?F ?t ?T ?g ?\[ ?\])
  "Characters that start a two-character motion.")

;; Text objects for i/a
(defconst evm--text-objects
  '(?w ?W ?s ?p ?b ?\( ?\) ?\[ ?\] ?{ ?} ?< ?> ?\" ?' ?` ?t)
  "Valid text objects for i/a prefix.")

;; g-motions
(defconst evm--g-motions
  '(?e ?E ?g ?_ ?j ?k ?0 ?^ ?$ ?m ?M)
  "Valid motions after g prefix.")

(defun evm--digit-p (char)
  "Return t if CHAR is a digit 1-9 (not 0, which is a motion)."
  (and char (>= char ?1) (<= char ?9)))

(defun evm--parse-count ()
  "Parse optional count from input.
Returns (count . next-char) where count is nil or a number."
  (let ((count nil)
        (char (read-char "Operator: ")))
    (when char
      ;; Collect digits
      (while (evm--digit-p char)
        (setq count (+ (* (or count 0) 10) (- char ?0)))
        (setq char (read-char)))
      (cons count char))))

(defun evm--parse-motion ()
  "Parse a motion from user input.
Returns a plist (:keys STRING :count NUMBER) or nil on cancel.
:keys is the motion key sequence (e.g., \"w\", \"iw\", \"f(\")
:count is the motion count (e.g., 3 for 3w)"
  (let* ((count-and-char (evm--parse-count))
         (count (car count-and-char))
         (char (cdr count-and-char)))
    (unless char
      (cl-return-from evm--parse-motion nil))
    (cond
     ;; ESC cancels
     ((= char 27)
      nil)
     ;; Single motions
     ((memq char evm--single-motions)
      (list :keys (string char) :count count))
     ;; Double motion prefixes
     ((memq char evm--double-motion-prefixes)
      (let ((char2 (read-char)))
        (cond
         ((null char2) nil)
         ((= char2 27) nil)  ; ESC cancels
         ;; i/a + text object
         ((and (memq char '(?i ?a))
               (memq char2 evm--text-objects))
          (list :keys (string char char2) :count count))
         ;; f/F/t/T + any char
         ((memq char '(?f ?F ?t ?T))
          (list :keys (string char char2) :count count))
         ;; g + motion
         ((and (= char ?g)
               (memq char2 evm--g-motions))
          (list :keys (string char char2) :count count))
         ;; [/] + motion (for navigation)
         ((memq char '(?\[ ?\]))
          (list :keys (string char char2) :count count))
         (t nil))))
     ;; Numbers after operator (d3w pattern)
     ((and (null count) (>= char ?1) (<= char ?9))
      ;; Re-parse with this char as start of count
      (let ((new-count (- char ?0))
            (next-char (read-char)))
        (while (and next-char (>= next-char ?0) (<= next-char ?9))
          (setq new-count (+ (* new-count 10) (- next-char ?0)))
          (setq next-char (read-char)))
        (when next-char
          ;; Now parse the actual motion
          (cond
           ((= next-char 27) nil)
           ((memq next-char evm--single-motions)
            (list :keys (string next-char) :count new-count))
           ((memq next-char evm--double-motion-prefixes)
            (let ((char2 (read-char)))
              (when (and char2 (/= char2 27))
                (list :keys (string next-char char2) :count new-count))))
           (t nil)))))
     (t nil))))

;; Inclusive motions need +1 to end position for operators
(defconst evm--inclusive-motions
  '(?$ ?e ?E ?% ?G ?N ?n ?} ?{ ?\) ?\( ?` ?' ?g ?f ?F ?t ?T ?\] ?\[)
  "Motions that are inclusive (include the character at end position).")

(defun evm--get-motion-range (motion-keys count)
  "Get the range for MOTION-KEYS with COUNT from current position.
Returns (BEG END) or nil if motion failed."
  (let* ((count (or count 1))
         (beg (point))
         end
         ;; Temporarily disable evm keymaps
         (saved-alist evm--emulation-alist)
         ;; Check if motion is inclusive
         (first-char (aref motion-keys 0))
         (inclusive-p (memq first-char evm--inclusive-motions)))
    (setq evm--emulation-alist nil)
    ;; Remove post-command-hook temporarily to prevent cursor jumping during macro
    (remove-hook 'post-command-hook #'evm--post-command t)
    (unwind-protect
        (cond
         ;; Text objects: iw, aw, is, as, ip, ap, i", a", etc.
         ((and (= (length motion-keys) 2)
               (memq first-char '(?i ?a)))
          (let* ((inner-p (= first-char ?i))
                 (obj-char (aref motion-keys 1))
                 (bounds (pcase obj-char
                           (?w (if inner-p (evil-inner-word) (evil-a-word)))
                           (?W (if inner-p (evil-inner-WORD) (evil-a-WORD)))
                           (?s (if inner-p (evil-inner-sentence) (evil-a-sentence)))
                           (?p (if inner-p (evil-inner-paragraph) (evil-a-paragraph)))
                           ((or ?\( ?\) ?b) (if inner-p (evil-inner-paren) (evil-a-paren)))
                           ((or ?\[ ?\]) (if inner-p (evil-inner-bracket) (evil-a-bracket)))
                           ((or ?{ ?} ?B) (if inner-p (evil-inner-curly) (evil-a-curly)))
                           ((or ?< ?>) (if inner-p (evil-inner-angle) (evil-a-angle)))
                           (?\" (if inner-p (evil-inner-double-quote) (evil-a-double-quote)))
                           (?\' (if inner-p (evil-inner-single-quote) (evil-a-single-quote)))
                           (?\` (if inner-p (evil-inner-back-quote) (evil-a-back-quote)))
                           (?t (if inner-p (evil-inner-tag) (evil-a-tag)))
                           (_ nil))))
            (when bounds
              (setq beg (nth 0 bounds)
                    end (nth 1 bounds)))))
         ;; Regular motions
         (t
          (let ((keys (concat (when (> count 1) (number-to-string count))
                              motion-keys)))
            (save-excursion
              (condition-case nil
                  (execute-kbd-macro keys)
                (error nil))
              (setq end (point))
              ;; For inclusive motions, include the character at end
              (when (and inclusive-p (not (eobp)))
                (setq end (1+ end)))))))
      ;; Restore evm keymaps and hook
      (setq evm--emulation-alist saved-alist)
      (add-hook 'post-command-hook #'evm--post-command nil t))
    ;; Ensure beg <= end
    (when (and beg end)
      (when (> beg end)
        (let ((tmp beg))
          (setq beg end
                end tmp)))
      (when (> end beg)
        (list beg end)))))

(defun evm--execute-operator-motion (operator motion-keys count)
  "Execute OPERATOR with MOTION-KEYS at current position.
OPERATOR is one of \\='delete, \\='change, \\='yank.
MOTION-KEYS is a string like \"w\", \"iw\", \"f(\".
COUNT is the motion count or nil.
Returns the deleted/yanked text, or nil."
  (let* ((range (evm--get-motion-range motion-keys count))
         (beg (car range))
         (end (cadr range))
         text)
    (when (and beg end (> end beg))
      (setq text (buffer-substring-no-properties beg end))
      ;; Perform the operation
      (pcase operator
        ('delete
         (delete-region beg end))
        ('change
         (delete-region beg end))
        ('yank
         ;; Just copy, don't delete
         nil)))
    text))

(defun evm--run-operator-with-motion (operator &optional prefix-count)
  "Run OPERATOR with a motion parsed from user input.
OPERATOR is one of \\='delete, \\='change, \\='yank.
PREFIX-COUNT is an optional count from prefix argument (for 2dw pattern).
Applies the operator to all cursors."
  (let ((motion (evm--parse-motion)))
    (unless motion
      (message "Cancelled")
      (cl-return-from evm--run-operator-with-motion nil))
    (let ((keys (plist-get motion :keys))
          ;; Combine prefix count with motion count: 2d3w = delete 6 words
          (count (let ((motion-count (plist-get motion :count))
                       (pre (and prefix-count (prefix-numeric-value prefix-count))))
                   (cond
                    ((and pre motion-count) (* pre motion-count))
                    (pre pre)
                    (motion-count motion-count)
                    (t nil))))
          (texts '())
          ;; Create undo boundary so all changes are undone together
          (undo-handle (prepare-change-group)))
      (evm--push-undo-snapshot)
      (unwind-protect
          (progn
            ;; Execute at all cursors (from end to beginning)
            (let ((regions (reverse (evm-state-regions evm--state)))
                  (inhibit-modification-hooks t))
              (remove-hook 'post-command-hook #'evm--post-command t)
              (unwind-protect
                  (dolist (region regions)
                    (goto-char (evm--region-cursor-pos region))
                    (let ((text (evm--execute-operator-motion operator keys count)))
                      (when text
                        (push text texts))
                      ;; Update cursor position
                      ;; For delete/yank (staying in normal mode), adjust like evil does
                      ;; For change (entering insert mode), don't adjust
                      (let ((new-pos (if (eq operator 'change)
                                         (point)
                                       (evm--adjust-cursor-pos (point)))))
                        (evm--region-set-cursor-pos region new-pos))))
                (add-hook 'post-command-hook #'evm--post-command nil t)))
            ;; Save yanked/deleted text to VM register
            (when texts
              (puthash ?\" (nreverse texts) (evm-state-registers evm--state))
              ;; Also to kill-ring
              (kill-new (car texts)))
            ;; Clamp and update
            (evm--clamp-markers)
            (evm--check-and-merge-overlapping)
            (evm--update-all-overlays)
            ;; Move to leader
            (when-let ((leader (evm--leader-region)))
              (goto-char (evm--region-cursor-pos leader))))
        ;; Amalgamate all changes into single undo entry
        (undo-amalgamate-change-group undo-handle))
      ;; Return for change operator to know if we should enter insert mode
      (list :texts texts :motion motion))))

(defun evm-operator-delete (count)
  "Delete operator: wait for motion, then delete at all cursors.
COUNT is optional prefix argument for patterns like 2dw.
Examples: dw (delete word), d3w (delete 3 words), 2dw (delete 2 words)."
  (interactive "P")
  (when (evm-cursor-mode-p)
    (message "[EVM] d")
    (evm--run-operator-with-motion 'delete count)))

(defun evm-operator-change (count)
  "Change operator: delete with motion, then enter insert mode.
COUNT is optional prefix argument for patterns like 2cw.
Examples: cw (change word), ciw (change inner word), 2cw (change 2 words)."
  (interactive "P")
  (when (evm-cursor-mode-p)
    (message "[EVM] c")
    (let ((result (evm--run-operator-with-motion 'change count)))
      (when (and result (plist-get result :texts))
        ;; Enter insert mode
        (evm--start-insert-mode)
        (evil-insert-state)))))

(defun evm-operator-yank (count)
  "Yank operator: copy text defined by motion at all cursors.
COUNT is optional prefix argument for patterns like 2yw.
Examples: yw (yank word), yiw (yank inner word), 2yw (yank 2 words)."
  (interactive "P")
  (when (evm-cursor-mode-p)
    (message "[EVM] y")
    (let ((result (evm--run-operator-with-motion 'yank count)))
      (when result
        (message "Yanked %d regions" (length (plist-get result :texts)))))))

;; Shortcuts for common operations
(defun evm-delete-to-eol ()
  "Delete from cursor to end of line (D)."
  (interactive)
  (when (evm-cursor-mode-p)
    (let ((texts '())
          (undo-handle (prepare-change-group)))
      (evm--push-undo-snapshot)
      (unwind-protect
          (progn
            (let ((regions (reverse (evm-state-regions evm--state)))
                  (inhibit-modification-hooks t))
              (remove-hook 'post-command-hook #'evm--post-command t)
              (unwind-protect
                  (dolist (region regions)
                    (goto-char (evm--region-cursor-pos region))
                    (let ((beg (point))
                          (end (line-end-position)))
                      (when (> end beg)
                        (push (buffer-substring-no-properties beg end) texts)
                        (delete-region beg end))
                      ;; Adjust position like evil does in normal state
                      (evm--region-set-cursor-pos region (evm--adjust-cursor-pos (point)))))
                (add-hook 'post-command-hook #'evm--post-command nil t)))
            (when texts
              (puthash ?\" (nreverse texts) (evm-state-registers evm--state))
              (kill-new (car texts))))
        (undo-amalgamate-change-group undo-handle)))
    (evm--clamp-markers)
    (evm--check-and-merge-overlapping)
    (evm--update-all-overlays)
    (when-let ((leader (evm--leader-region)))
      (goto-char (evm--region-cursor-pos leader)))))

(defun evm-change-to-eol ()
  "Change from cursor to end of line (C)."
  (interactive)
  (when (evm-cursor-mode-p)
    (evm-delete-to-eol)
    (evm--start-insert-mode)
    (evil-insert-state)))

(defun evm-yank-line ()
  "Yank entire line (Y)."
  (interactive)
  (when (evm-cursor-mode-p)
    (let ((texts '()))
      (dolist (region (evm-state-regions evm--state))
        (save-excursion
          (goto-char (evm--region-cursor-pos region))
          (let ((beg (line-beginning-position))
                (end (line-end-position)))
            (push (buffer-substring-no-properties beg end) texts))))
      (when texts
        (puthash ?\" (nreverse texts) (evm-state-registers evm--state))
        (kill-new (car texts))
        (message "Yanked %d lines" (length texts))))))

;;; Global keybindings for activation

;;;###autoload
(defun evm-setup-global-keys ()
  "Setup global keybindings for evm activation."
  (evil-define-key 'normal 'global (kbd "C-n") #'evm-find-word)
  (evil-define-key 'normal 'global (kbd "<C-down>") #'evm-add-cursor-down)
  (evil-define-key 'normal 'global (kbd "<C-up>") #'evm-add-cursor-up)
  ;; Mouse bindings need direct definition in state map
  (define-key evil-normal-state-map (kbd "<s-mouse-1>") #'evm-add-cursor-at-click)
  ;; Visual mode bindings
  (evil-define-key 'visual 'global (kbd "C-n") #'evm-find-word)
  (evil-define-key 'visual 'global (kbd "\\ r") #'evm-toggle-restrict))

(provide 'evm)
;;; evm.el ends here
