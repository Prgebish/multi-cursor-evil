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
(define-key evm-cursor-map (kbd "C-n") #'evm-add-next-match)
(define-key evm-cursor-map (kbd "<C-down>") #'evm-add-cursor-down)
(define-key evm-cursor-map (kbd "<C-up>") #'evm-add-cursor-up)

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
    ;; Remove hooks
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
    (add-hook 'evil-insert-state-exit-hook #'evm--stop-insert-mode nil t)))

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
    ;; Update overlays
    (evm--update-all-overlays)
    ;; Restore evm keymaps
    (when-let ((entry (assq 'evm-mode minor-mode-map-alist)))
      (setcdr entry evm-mode-map))
    (evm--update-keymap)))

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

(defun evm--post-command ()
  "Called after each command."
  (when (evm-active-p)
    ;; Keep real cursor at leader position
    (when-let ((leader (evm--leader-region)))
      (let ((leader-pos (evm--region-cursor-pos leader)))
        (unless (= (point) leader-pos)
          (goto-char leader-pos))))))

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
  "Remove current cursor."
  (interactive)
  (when (evm-active-p)
    (let ((leader (evm--leader-region)))
      (if (= (evm-region-count) 1)
          (evm-exit)
        (evm-goto-next)
        (evm--delete-region leader)))))

;;; Cursor creation

;;;###autoload
(defun evm-find-word ()
  "Start evm with word under cursor, find next occurrence."
  (interactive)
  (let* ((bounds (bounds-of-thing-at-point 'symbol))
         (word (when bounds
                 (buffer-substring-no-properties (car bounds) (cdr bounds)))))
    (unless word
      (user-error "No word at point"))
    (unless (evm-active-p)
      (evm-activate))
    (let ((pattern (concat "\\_<" (regexp-quote word) "\\_>")))
      ;; Add pattern
      (push pattern (evm-state-patterns evm--state))
      ;; Create first region on current word
      (evm--create-region (car bounds) (car bounds) pattern)
      ;; Show matches
      (evm--show-match-preview pattern))))

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
  "Find next match for PATTERN starting from START-POS and move/add cursor there."
  (let (found-pos)
    (save-excursion
      (goto-char (min start-pos (point-max)))
      (if (re-search-forward pattern nil t)
          (setq found-pos (match-beginning 0))
        ;; Wrap around
        (goto-char (point-min))
        (when (re-search-forward pattern nil t)
          (setq found-pos (match-beginning 0)))))
    (when found-pos
      ;; Check if cursor already exists at this position
      (let ((existing (cl-find-if
                       (lambda (r)
                         (= (marker-position (evm-region-beg r)) found-pos))
                       (evm-state-regions evm--state))))
        (if existing
            ;; Just move leader to existing cursor
            (progn
              (evm--set-leader existing)
              (goto-char found-pos))
          ;; Create new cursor
          (let ((new-region (evm--create-region found-pos found-pos pattern)))
            (evm--set-leader new-region)
            (goto-char found-pos)))))))

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
  "Find previous match for PATTERN starting from START-POS and move/add cursor there."
  (let (found-pos)
    (save-excursion
      (goto-char (max start-pos (point-min)))
      (if (re-search-backward pattern nil t)
          (setq found-pos (match-beginning 0))
        ;; Wrap around
        (goto-char (point-max))
        (when (re-search-backward pattern nil t)
          (setq found-pos (match-beginning 0)))))
    (when found-pos
      ;; Check if cursor already exists at this position
      (let ((existing (cl-find-if
                       (lambda (r)
                         (= (marker-position (evm-region-beg r)) found-pos))
                       (evm-state-regions evm--state))))
        (if existing
            ;; Just move leader to existing cursor
            (progn
              (evm--set-leader existing)
              (goto-char found-pos))
          ;; Create new cursor
          (let ((new-region (evm--create-region found-pos found-pos pattern)))
            (evm--set-leader new-region)
            (goto-char found-pos)))))))

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

(defun evm-select-all ()
  "Select all occurrences of current pattern."
  (interactive)
  (when (evm-active-p)
    (let ((pattern (car (evm-state-patterns evm--state))))
      (unless pattern
        (user-error "No search pattern"))
      (save-excursion
        (goto-char (point-min))
        (while (re-search-forward pattern nil t)
          (let ((pos (match-beginning 0)))
            (unless (cl-find-if
                     (lambda (r)
                       (= (marker-position (evm-region-beg r)) pos))
                     (evm-state-regions evm--state))
              (evm--create-region pos pos pattern))))))))

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
  "Align all cursors vertically."
  (interactive)
  (when (evm-active-p)
    (evm--push-undo-snapshot)
    ;; Find max column
    (let ((max-col 0))
      (dolist (region (evm-state-regions evm--state))
        (save-excursion
          (goto-char (evm--region-cursor-pos region))
          (setq max-col (max max-col (current-column)))))
      ;; Add spaces to align
      (dolist (region (reverse (evm-state-regions evm--state)))
        (save-excursion
          (goto-char (evm--region-cursor-pos region))
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

;;; Global keybindings for activation

;;;###autoload
(defun evm-setup-global-keys ()
  "Setup global keybindings for evm activation."
  (evil-define-key 'normal 'global (kbd "C-n") #'evm-find-word)
  (evil-define-key 'normal 'global (kbd "<C-down>") #'evm-add-cursor-down)
  (evil-define-key 'normal 'global (kbd "<C-up>") #'evm-add-cursor-up))

(provide 'evm)
;;; evm.el ends here
