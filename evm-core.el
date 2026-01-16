;;; evm-core.el --- Core data structures and cursor system -*- lexical-binding: t; -*-

;; Copyright (C) 2025
;; SPDX-License-Identifier: GPL-3.0-or-later

;;; Commentary:

;; Core module for evil-visual-multi.
;; Provides data structures (evm-region, evm-state, evm-snapshot),
;; cursor/overlay management, and basic operations.

;;; Code:

(require 'cl-lib)
(require 'evil)

;; Forward declaration for function defined in evm.el
(declare-function evm--update-keymap "evm" ())

;;; Custom group

(defgroup evm nil
  "Multiple cursors for evil-mode."
  :group 'evil
  :prefix "evm-")

;;; Faces

(defface evm-cursor-face
  '((((class color) (background dark))
     :background "#3B82F6" :foreground "white")
    (((class color) (background light))
     :background "#2563EB" :foreground "white"))
  "Face for cursors in cursor mode."
  :group 'evm)

(defface evm-region-face
  '((((class color) (background dark))
     :background "#166534")
    (((class color) (background light))
     :background "#BBF7D0"))
  "Face for selected regions in extend mode."
  :group 'evm)

(defface evm-leader-cursor-face
  '((((class color) (background dark))
     :background "#F97316" :foreground "black")
    (((class color) (background light))
     :background "#EA580C" :foreground "white"))
  "Face for the leader cursor position."
  :group 'evm)

(defface evm-leader-region-face
  '((((class color) (background dark))
     :background "#854D0E")
    (((class color) (background light))
     :background "#FEF08A"))
  "Face for the leader region in extend mode."
  :group 'evm)

(defface evm-mode-line-face
  '((t :foreground "#10B981" :weight bold))
  "Face for evm indicator in mode-line."
  :group 'evm)

(defface evm-match-face
  '((((class color) (background dark))
     :background "#374151" :underline t)
    (((class color) (background light))
     :background "#E5E7EB" :underline t))
  "Face for potential matches (pattern preview)."
  :group 'evm)

;;; Data Structures

(cl-defstruct evm-region
  "Structure representing a cursor/region.
In cursor mode: beg = end = anchor (point).
In extend mode: beg <= end, anchor is fixed."
  id              ; unique ID (integer)
  index           ; position in regions list (updated on sort)
  beg             ; start of region (marker)
  end             ; end of region (marker)
  overlay         ; overlay for region display
  cursor-overlay  ; overlay for cursor position
  dir             ; direction: 0 = cursor at beg, 1 = cursor at end
  anchor          ; anchor point (marker) - fixed during extend
  vcol            ; virtual column for j/k navigation
  txt             ; text content (updated after changes)
  pattern)        ; search pattern associated with region

(cl-defstruct evm-state
  "Buffer-local global state for evm."
  active-p        ; is evm active in buffer
  mode            ; 'cursor or 'extend
  regions         ; list of evm-region, sorted by position
  leader-id       ; ID of current leader
  id-counter      ; counter for ID generation
  patterns        ; list of search patterns (strings)
  search-direction ; 1 = forward, -1 = backward
  multiline-p     ; allow multiline regions
  whole-word-p    ; search whole words
  case-fold-p     ; ignore case in search
  undo-snapshots  ; list of snapshots for undo
  last-regions    ; saved positions for reselect
  registers       ; hash-table: char -> list of strings
  column-positions) ; hash-table for column caching

(cl-defstruct evm-snapshot
  "Snapshot for undo/redo."
  regions-data    ; list of (id beg-pos end-pos anchor-pos dir)
  leader-id       ; leader ID at snapshot time
  mode            ; mode at snapshot time
  buffer-tick)    ; buffer-modified-tick for validation

;;; Buffer-local state

(defvar-local evm--state nil
  "Buffer-local evm state.")

;;; State predicates

(defun evm-active-p ()
  "Return t if evm is active in current buffer."
  (and evm--state (evm-state-active-p evm--state)))

(defun evm-cursor-mode-p ()
  "Return t if in cursor mode."
  (and (evm-active-p)
       (eq (evm-state-mode evm--state) 'cursor)))

(defun evm-extend-mode-p ()
  "Return t if in extend mode."
  (and (evm-active-p)
       (eq (evm-state-mode evm--state) 'extend)))

;;; Region management

(defun evm--generate-id ()
  "Generate unique region ID."
  (cl-incf (evm-state-id-counter evm--state)))

(defun evm--make-marker (pos)
  "Create marker at POS."
  (let ((marker (make-marker)))
    (set-marker marker pos)
    (set-marker-insertion-type marker t)
    marker))

(defun evm--create-region (beg end &optional pattern)
  "Create new region from BEG to END with optional PATTERN.
Returns the created region."
  (let* ((id (evm--generate-id))
         (region (make-evm-region
                  :id id
                  :beg (evm--make-marker beg)
                  :end (evm--make-marker end)
                  :anchor (evm--make-marker beg)
                  :dir 1
                  :vcol nil
                  :txt (buffer-substring-no-properties beg end)
                  :pattern pattern)))
    ;; Add to regions list
    (push region (evm-state-regions evm--state))
    ;; Sort by position
    (evm--sort-regions)
    ;; Update indices
    (evm--update-region-indices)
    ;; Set as leader if first region
    (unless (evm-state-leader-id evm--state)
      (setf (evm-state-leader-id evm--state) id))
    ;; Create overlay
    (evm--create-overlay-for-region region)
    region))

(defun evm--delete-region (region)
  "Delete REGION and its overlays."
  (when (evm-region-overlay region)
    (delete-overlay (evm-region-overlay region)))
  (when (evm-region-cursor-overlay region)
    (delete-overlay (evm-region-cursor-overlay region)))
  ;; Remove markers
  (set-marker (evm-region-beg region) nil)
  (set-marker (evm-region-end region) nil)
  (set-marker (evm-region-anchor region) nil)
  ;; Remove from list
  (setf (evm-state-regions evm--state)
        (cl-remove-if (lambda (r) (= (evm-region-id r) (evm-region-id region)))
                      (evm-state-regions evm--state)))
  ;; Update leader if needed
  (when (and (evm-state-leader-id evm--state)
             (= (evm-state-leader-id evm--state) (evm-region-id region)))
    (setf (evm-state-leader-id evm--state)
          (when-let ((first (car (evm-state-regions evm--state))))
            (evm-region-id first))))
  ;; Update indices
  (evm--update-region-indices))

(defun evm--sort-regions ()
  "Sort regions by position."
  (setf (evm-state-regions evm--state)
        (cl-sort (evm-state-regions evm--state)
                 #'<
                 :key (lambda (r) (marker-position (evm-region-beg r))))))

(defun evm--update-region-indices ()
  "Update index field for all regions."
  (cl-loop for region in (evm-state-regions evm--state)
           for idx from 0
           do (setf (evm-region-index region) idx)))

(defun evm-get-all-regions ()
  "Return all regions."
  (when evm--state
    (evm-state-regions evm--state)))

(defun evm-region-count ()
  "Return number of regions."
  (length (evm-get-all-regions)))

(defun evm--get-region-by-id (id)
  "Find region by ID."
  (cl-find-if (lambda (r) (= (evm-region-id r) id))
              (evm-state-regions evm--state)))

(defun evm--leader-region ()
  "Get the leader region."
  (when-let ((id (evm-state-leader-id evm--state)))
    (evm--get-region-by-id id)))

(defun evm--leader-p (region)
  "Return t if REGION is the leader."
  (and (evm-state-leader-id evm--state)
       (= (evm-region-id region) (evm-state-leader-id evm--state))))

(defun evm--leader-index ()
  "Return index of the leader region."
  (when-let ((leader (evm--leader-region)))
    (evm-region-index leader)))

(defun evm--set-leader (region)
  "Set REGION as the leader."
  (setf (evm-state-leader-id evm--state) (evm-region-id region))
  (evm--update-leader-overlays))

;;; Overlay management

(defun evm--create-overlay-for-region (region)
  "Create overlay(s) for REGION based on current mode."
  (if (evm-extend-mode-p)
      (evm--create-region-overlay region)
    (evm--create-cursor-overlay region)))

(defun evm--create-cursor-overlay (region)
  "Create cursor overlay for REGION."
  (let* ((pos (marker-position (evm-region-beg region)))
         (at-eol (save-excursion
                   (goto-char pos)
                   (or (= pos (line-end-position))
                       (= pos (point-max)))))
         ;; At EOL, don't extend overlay past line end - just cover the position
         (end-pos (if at-eol pos (min (1+ pos) (point-max))))
         (ov (make-overlay pos end-pos nil t nil)))
    (overlay-put ov 'evm-type 'cursor)
    (overlay-put ov 'evm-id (evm-region-id region))
    (overlay-put ov 'priority 100)
    (overlay-put ov 'face
                 (if (evm--leader-p region)
                     'evm-leader-cursor-face
                   'evm-cursor-face))
    ;; For EOL or EOF - show as bar after the line
    (when at-eol
      (overlay-put ov 'after-string
                   (propertize " " 'face (overlay-get ov 'face)
                               'cursor t)))
    (setf (evm-region-cursor-overlay region) ov)))

(defun evm--create-region-overlay (region)
  "Create region overlay for REGION in extend mode."
  (let* ((beg (marker-position (evm-region-beg region)))
         (end (marker-position (evm-region-end region)))
         (ov (make-overlay beg end nil t nil)))
    (overlay-put ov 'evm-type 'region)
    (overlay-put ov 'evm-id (evm-region-id region))
    (overlay-put ov 'priority 90)
    (overlay-put ov 'face
                 (if (evm--leader-p region)
                     'evm-leader-region-face
                   'evm-region-face))
    (setf (evm-region-overlay region) ov))
  ;; Also create cursor overlay within region
  (evm--create-cursor-in-region-overlay region))

(defun evm--create-cursor-in-region-overlay (region)
  "Create cursor overlay within region (shows active end)."
  (let* ((cursor-pos (if (= (evm-region-dir region) 1)
                         (1- (marker-position (evm-region-end region)))
                       (marker-position (evm-region-beg region))))
         (cursor-pos (max (point-min) cursor-pos))
         (end-pos (min (1+ cursor-pos) (point-max)))
         (ov (make-overlay cursor-pos end-pos nil t nil)))
    (overlay-put ov 'evm-type 'cursor)
    (overlay-put ov 'evm-id (evm-region-id region))
    (overlay-put ov 'priority 110)
    (overlay-put ov 'face
                 (if (evm--leader-p region)
                     'evm-leader-cursor-face
                   'evm-cursor-face))
    (setf (evm-region-cursor-overlay region) ov)))

(defun evm--update-all-overlays ()
  "Update all overlays based on current state."
  (evm--remove-all-overlays)
  (dolist (region (evm-state-regions evm--state))
    (evm--create-overlay-for-region region)))

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

;;; Region position helpers

(defun evm--region-cursor-pos (region)
  "Get cursor position within REGION."
  (if (= (evm-region-dir region) 1)
      (marker-position (evm-region-end region))
    (marker-position (evm-region-beg region))))

(defun evm--region-visual-cursor-pos (region)
  "Get visual cursor position within REGION.
In extend mode with dir=1, cursor is ON the last char (end-1), not after.
This is used for positioning the actual Emacs point."
  (if (= (evm-region-dir region) 1)
      (if (evm-extend-mode-p)
          ;; In extend mode, cursor is ON the last character (like evil visual)
          (max (marker-position (evm-region-beg region))
               (1- (marker-position (evm-region-end region))))
        ;; In cursor mode, beg=end anyway
        (marker-position (evm-region-end region)))
    (marker-position (evm-region-beg region))))

(defun evm--region-set-cursor-pos (region pos)
  "Set cursor position in REGION to POS.
In cursor mode: moves the whole region.
In extend mode: moves the active end."
  (if (evm-cursor-mode-p)
      ;; Cursor mode: move everything
      (progn
        (set-marker (evm-region-beg region) pos)
        (set-marker (evm-region-end region) pos)
        (set-marker (evm-region-anchor region) pos))
    ;; Extend mode: move active end, adjust beg/end
    (let ((anchor-pos (marker-position (evm-region-anchor region))))
      (cond
       ((< pos anchor-pos)
        (set-marker (evm-region-beg region) pos)
        (set-marker (evm-region-end region) anchor-pos)
        (setf (evm-region-dir region) 0))
       (t
        (set-marker (evm-region-beg region) anchor-pos)
        (set-marker (evm-region-end region) pos)
        (setf (evm-region-dir region) 1))))))

(defun evm--region-empty-p (region)
  "Return t if REGION is empty (cursor mode)."
  (= (marker-position (evm-region-beg region))
     (marker-position (evm-region-end region))))

;;; Mode switching

(defun evm--enter-cursor-mode ()
  "Enter cursor mode - collapse all regions to cursor position."
  (setf (evm-state-mode evm--state) 'cursor)
  (dolist (region (evm-state-regions evm--state))
    (let ((cursor-pos (evm--region-cursor-pos region)))
      (set-marker (evm-region-beg region) cursor-pos)
      (set-marker (evm-region-end region) cursor-pos)
      (set-marker (evm-region-anchor region) cursor-pos)))
  (evm--update-all-overlays)
  (evm--update-keymap))

(defun evm--enter-extend-mode ()
  "Enter extend mode - extend regions from current positions."
  (setf (evm-state-mode evm--state) 'extend)
  ;; If regions are empty (from cursor mode), extend by 1 char
  (dolist (region (evm-state-regions evm--state))
    (when (evm--region-empty-p region)
      (let ((pos (marker-position (evm-region-beg region))))
        (set-marker (evm-region-end region)
                    (min (1+ pos) (point-max)))
        (setf (evm-region-dir region) 1))))
  (evm--update-all-overlays)
  (evm--update-keymap))

(defun evm-toggle-mode ()
  "Toggle between cursor and extend mode."
  (interactive)
  (when (evm-active-p)
    (if (evm-cursor-mode-p)
        (evm--enter-extend-mode)
      (evm--enter-cursor-mode))))

;;; Cursor movement

(defun evm--move-cursors (motion-fn &rest args)
  "Move all cursors using MOTION-FN with ARGS.
MOTION-FN should move point and return new position.
This clears vcol for all regions (horizontal movement)."
  (let ((positions '()))
    ;; Calculate new positions
    (dolist (region (evm-state-regions evm--state))
      ;; Clear vcol on horizontal movement
      (setf (evm-region-vcol region) nil)
      (save-excursion
        (goto-char (evm--region-cursor-pos region))
        (apply motion-fn args)
        (push (cons region (point)) positions)))
    ;; Apply new positions (in reverse to not affect markers)
    (dolist (pos-pair (nreverse positions))
      (evm--region-set-cursor-pos (car pos-pair) (cdr pos-pair))))
  ;; Move real point to leader position
  (when-let ((leader (evm--leader-region)))
    (goto-char (evm--region-cursor-pos leader)))
  (evm--update-all-overlays))

(defun evm--move-cursors-vertically (count)
  "Move all cursors COUNT lines vertically, preserving each cursor's column.
Uses vcol to remember the desired column across short lines."
  (let ((positions '()))
    ;; Calculate new positions using each region's vcol
    (dolist (region (evm-state-regions evm--state))
      (save-excursion
        (goto-char (evm--region-cursor-pos region))
        (evm--move-line-for-region region count)
        (push (cons region (point)) positions)))
    ;; Apply new positions (in reverse to not affect markers)
    (dolist (pos-pair (nreverse positions))
      (evm--region-set-cursor-pos (car pos-pair) (cdr pos-pair))))
  ;; Move real point to leader position
  (when-let ((leader (evm--leader-region)))
    (goto-char (evm--region-cursor-pos leader)))
  (evm--update-all-overlays))

(defun evm--move-char (count)
  "Move COUNT characters, respecting buffer bounds."
  (let ((target (+ (point) count)))
    (goto-char (max (point-min) (min target (point-max))))))

(defun evm--move-line-for-region (region count)
  "Move COUNT lines using REGION's vcol.
This function is called with point already at the region's cursor position."
  ;; Set vcol if not already set (first j/k in a sequence)
  (unless (evm-region-vcol region)
    (setf (evm-region-vcol region) (current-column)))
  (let ((col (evm-region-vcol region)))
    (forward-line count)
    (move-to-column col)))

(defun evm--move-word (count)
  "Move forward COUNT words."
  (evil-forward-word-begin count))

(defun evm--move-word-end (count)
  "Move to end of COUNT words."
  (evil-forward-word-end count))

(defun evm--move-word-back (count)
  "Move backward COUNT words."
  (evil-backward-word-begin count))

(defun evm--move-line-beg ()
  "Move to beginning of line."
  (beginning-of-line))

(defun evm--move-line-end ()
  "Move to end of line (last character, like evil $)."
  (let ((eol (line-end-position))
        (bol (line-beginning-position)))
    (if (= bol eol)
        ;; Empty line - go to beginning of line
        (goto-char bol)
      ;; Go to last character (not past it), like evil normal state $
      (goto-char (1- eol)))))

(defun evm--move-first-non-blank ()
  "Move to first non-blank character."
  (back-to-indentation))

;;; Undo support

(defun evm--push-undo-snapshot ()
  "Save current state for undo."
  (let ((snapshot (make-evm-snapshot
                   :regions-data
                   (mapcar (lambda (r)
                             (list (evm-region-id r)
                                   (marker-position (evm-region-beg r))
                                   (marker-position (evm-region-end r))
                                   (marker-position (evm-region-anchor r))
                                   (evm-region-dir r)))
                           (evm-state-regions evm--state))
                   :leader-id (evm-state-leader-id evm--state)
                   :mode (evm-state-mode evm--state)
                   :buffer-tick (buffer-modified-tick))))
    (push snapshot (evm-state-undo-snapshots evm--state))))

(defun evm--restore-from-snapshot (snapshot)
  "Restore state from SNAPSHOT."
  (evm--remove-all-overlays)
  ;; Clear current regions
  (dolist (region (evm-state-regions evm--state))
    (set-marker (evm-region-beg region) nil)
    (set-marker (evm-region-end region) nil)
    (set-marker (evm-region-anchor region) nil))
  (setf (evm-state-regions evm--state) nil)
  ;; Restore from snapshot
  (dolist (data (evm-snapshot-regions-data snapshot))
    (cl-destructuring-bind (id beg end anchor dir) data
      (let ((region (make-evm-region
                     :id id
                     :beg (evm--make-marker beg)
                     :end (evm--make-marker end)
                     :anchor (evm--make-marker anchor)
                     :dir dir)))
        (push region (evm-state-regions evm--state)))))
  (setf (evm-state-leader-id evm--state) (evm-snapshot-leader-id snapshot))
  (setf (evm-state-mode evm--state) (evm-snapshot-mode snapshot))
  (evm--sort-regions)
  (evm--update-region-indices)
  (evm--update-all-overlays))

;;; Match preview (for pattern search)

(defvar-local evm--match-overlays nil
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
        (overlay-put ov 'priority 50)
        (push ov evm--match-overlays)))))

(defun evm--hide-match-preview ()
  "Hide match preview overlays."
  (mapc #'delete-overlay evm--match-overlays)
  (setq evm--match-overlays nil))

;;; Mode-line

(defun evm--mode-line-indicator ()
  "Return mode-line indicator string."
  (when (evm-active-p)
    (let* ((mode (evm-state-mode evm--state))
           (count (evm-region-count))
           (leader-idx (1+ (or (evm--leader-index) 0))))
      (propertize
       (format " EVM[%s %d/%d]"
               (if (eq mode 'cursor) "C" "E")
               leader-idx
               count)
       'face 'evm-mode-line-face))))

;;; Overlapping regions check

(defun evm--regions-overlap-p (r1 r2)
  "Check if regions R1 and R2 overlap."
  (let ((b1 (marker-position (evm-region-beg r1)))
        (e1 (marker-position (evm-region-end r1)))
        (b2 (marker-position (evm-region-beg r2)))
        (e2 (marker-position (evm-region-end r2))))
    (and (< b1 e2) (< b2 e1))))

(defun evm--check-and-merge-overlapping ()
  "Check for overlapping regions and merge them."
  (let ((regions (evm-state-regions evm--state))
        (merged nil))
    (while regions
      (let ((current (car regions))
            (rest (cdr regions)))
        (setq regions rest)
        ;; Check if current overlaps with any in merged
        (let ((overlapping (cl-find-if (lambda (r) (evm--regions-overlap-p current r))
                                       merged)))
          (if overlapping
              ;; Merge: extend overlapping region
              (let ((new-beg (min (marker-position (evm-region-beg current))
                                  (marker-position (evm-region-beg overlapping))))
                    (new-end (max (marker-position (evm-region-end current))
                                  (marker-position (evm-region-end overlapping)))))
                (set-marker (evm-region-beg overlapping) new-beg)
                (set-marker (evm-region-end overlapping) new-end)
                ;; Clean up current
                (when (evm-region-overlay current)
                  (delete-overlay (evm-region-overlay current)))
                (when (evm-region-cursor-overlay current)
                  (delete-overlay (evm-region-cursor-overlay current)))
                (set-marker (evm-region-beg current) nil)
                (set-marker (evm-region-end current) nil)
                (set-marker (evm-region-anchor current) nil))
            ;; No overlap, add to merged
            (push current merged)))))
    (setf (evm-state-regions evm--state) (nreverse merged))
    (evm--sort-regions)
    (evm--update-region-indices)))

(provide 'evm-core)
;;; evm-core.el ends here
