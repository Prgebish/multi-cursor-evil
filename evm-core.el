;;; evm-core.el --- Core data structures and cursor system -*- lexical-binding: t; -*-

;; Copyright (C) 2025
;; SPDX-License-Identifier: MIT

;;; Commentary:

;; Core module for evil-visual-multi.
;; Provides data structures (evm-region, evm-state),
;; cursor/overlay management, and basic operations.

;;; Code:

(require 'cl-lib)
(require 'evil)

;; Forward declaration for function defined in evm.el
(declare-function evm--update-keymap "evm" ())
(defvar evm--last-buffer-tick)

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
  '((t nil))
  "Face for evm indicator in mode-line."
  :group 'evm)

(defface evm-match-face
  '((((class color) (background dark))
     :background "#374151" :underline t)
    (((class color) (background light))
     :background "#E5E7EB" :underline t))
  "Face for potential matches (pattern preview)."
  :group 'evm)

(defface evm-restrict-face
  '((((class color) (background dark))
     :background "#1E293B")
    (((class color) (background light))
     :background "#F1F5F9"))
  "Face for restricted region boundary."
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
  region-by-id    ; hash-table: id -> evm-region for O(1) lookup
  leader-id       ; ID of current leader
  id-counter      ; counter for ID generation
  patterns        ; list of search patterns (strings)
  search-direction ; 1 = forward, -1 = backward
  multiline-p     ; allow multiline regions
  whole-word-p    ; search whole words
  case-fold-p     ; ignore case in search
  last-regions    ; saved positions for reselect
  registers       ; hash-table: char -> list of strings
  restrict-beg    ; start of restricted region (marker or nil)
  restrict-end    ; end of restricted region (marker or nil)
  restrict-overlay) ; overlay for restricted region visualization

;;; Buffer-local state

(defvar-local evm--state nil
  "Buffer-local evm state.")

(defvar-local evm--pending-restrict nil
  "Pending restriction bounds (beg . end) to apply on next evm activation.")

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
    ;; Add to hash-table for O(1) lookup
    (puthash id region (evm-state-region-by-id evm--state))
    ;; Insert into sorted list (more efficient than push + sort)
    (evm--insert-region-sorted region)
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
  ;; Remove from hash-table
  (remhash (evm-region-id region) (evm-state-region-by-id evm--state))
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

(defun evm--insert-region-sorted (region)
  "Insert REGION into the sorted regions list in correct position.
This is O(n) but avoids the O(n log n) cost of full sort."
  (let* ((regions (evm-state-regions evm--state))
         (pos (marker-position (evm-region-beg region))))
    (if (null regions)
        (setf (evm-state-regions evm--state) (list region))
      ;; Find insertion point
      (let ((prev nil)
            (curr regions))
        (while (and curr
                    (< (marker-position (evm-region-beg (car curr))) pos))
          (setq prev curr
                curr (cdr curr)))
        (if prev
            ;; Insert after prev
            (setcdr prev (cons region curr))
          ;; Insert at beginning
          (setf (evm-state-regions evm--state) (cons region regions)))))))

(defun evm--create-regions-batch (positions-list &optional pattern)
  "Create multiple regions at once from POSITIONS-LIST.
POSITIONS-LIST is a list of (BEG . END) cons cells.
PATTERN is the optional search pattern for all regions.
This is more efficient than calling evm--create-region in a loop
because it sorts once and creates overlays in batch."
  (let ((new-regions '())
        (ht (evm-state-region-by-id evm--state)))
    ;; Create all regions without sorting or overlays
    (dolist (pos positions-list)
      (let* ((beg (car pos))
             (end (cdr pos))
             (id (evm--generate-id))
             (region (make-evm-region
                      :id id
                      :beg (evm--make-marker beg)
                      :end (evm--make-marker end)
                      :anchor (evm--make-marker beg)
                      :dir 1
                      :vcol nil
                      :txt (buffer-substring-no-properties beg end)
                      :pattern pattern)))
        ;; Add to hash-table for O(1) lookup
        (puthash id region ht)
        (push region new-regions)))
    ;; Add all new regions to list
    (setf (evm-state-regions evm--state)
          (nconc (evm-state-regions evm--state) (nreverse new-regions)))
    ;; Sort once
    (evm--sort-regions)
    ;; Update all indices
    (evm--update-region-indices)
    ;; Set leader if not set
    (unless (evm-state-leader-id evm--state)
      (when-let ((first (car (evm-state-regions evm--state))))
        (setf (evm-state-leader-id evm--state) (evm-region-id first))))
    ;; Create all overlays
    (dolist (region new-regions)
      (evm--create-overlay-for-region region))
    new-regions))

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
  "Find region by ID.  O(1) lookup using hash-table."
  (gethash id (evm-state-region-by-id evm--state)))

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

(defvar evm--insert-active)  ; defined in evm.el

(defun evm--create-overlay-for-region (region)
  "Create overlay(s) for REGION based on current mode."
  (if (evm-extend-mode-p)
      (evm--create-region-overlay region)
    ;; Cursor mode: skip leader — the real Emacs cursor shows leader position.
    ;; This avoids the overlay face overriding the cursor display in GUI Emacs.
    (unless (evm--leader-p region)
      (evm--create-cursor-overlay region))))

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
  "Create cursor overlay within REGION to show the active end."
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
  "Update all overlays based on current state.
Attempts to reuse existing overlays when possible for better performance."
  (let ((extend-mode-p (evm-extend-mode-p)))
    (dolist (region (evm-state-regions evm--state))
      (let* ((is-leader (evm--leader-p region))
             (cursor-ov (evm-region-cursor-overlay region))
             (region-ov (evm-region-overlay region)))
        (if extend-mode-p
            ;; Extend mode: need both region and cursor overlays
            (let ((beg (marker-position (evm-region-beg region)))
                  (end (marker-position (evm-region-end region))))
              ;; Update or create region overlay
              (if (and region-ov (overlay-buffer region-ov))
                  (progn
                    (move-overlay region-ov beg end)
                    (overlay-put region-ov 'face
                                 (if is-leader 'evm-leader-region-face 'evm-region-face)))
                ;; Need to create region overlay
                (when region-ov (delete-overlay region-ov))
                (let ((ov (make-overlay beg end nil t nil)))
                  (overlay-put ov 'evm-type 'region)
                  (overlay-put ov 'evm-id (evm-region-id region))
                  (overlay-put ov 'priority 90)
                  (overlay-put ov 'face (if is-leader 'evm-leader-region-face 'evm-region-face))
                  (setf (evm-region-overlay region) ov)))
              ;; Update or create cursor-in-region overlay
              (let* ((cursor-pos (if (= (evm-region-dir region) 1)
                                     (1- end)
                                   beg))
                     (cursor-pos (max (point-min) cursor-pos))
                     (end-pos (min (1+ cursor-pos) (point-max))))
                (if (and cursor-ov (overlay-buffer cursor-ov))
                    (progn
                      (move-overlay cursor-ov cursor-pos end-pos)
                      (overlay-put cursor-ov 'face
                                   (if is-leader 'evm-leader-cursor-face 'evm-cursor-face)))
                  (when cursor-ov (delete-overlay cursor-ov))
                  (let ((ov (make-overlay cursor-pos end-pos nil t nil)))
                    (overlay-put ov 'evm-type 'cursor)
                    (overlay-put ov 'evm-id (evm-region-id region))
                    (overlay-put ov 'priority 110)
                    (overlay-put ov 'face (if is-leader 'evm-leader-cursor-face 'evm-cursor-face))
                    (setf (evm-region-cursor-overlay region) ov)))))
          ;; Cursor mode: only need cursor overlay
          ;; Delete region overlay if it exists
          (when (and region-ov (overlay-buffer region-ov))
            (delete-overlay region-ov)
            (setf (evm-region-overlay region) nil))
          ;; Update or create cursor overlay
          (if is-leader
              ;; Hide leader cursor overlay — the real Emacs cursor shows leader position.
              ;; This avoids the overlay face overriding the cursor display in GUI Emacs.
              (when (and cursor-ov (overlay-buffer cursor-ov))
                (delete-overlay cursor-ov)
                (setf (evm-region-cursor-overlay region) nil))
            (let* ((pos (marker-position (evm-region-beg region)))
                   (at-eol (save-excursion
                             (goto-char pos)
                             (or (= pos (line-end-position))
                                 (= pos (point-max)))))
                   (end-pos (if at-eol pos (min (1+ pos) (point-max)))))
              (if (and cursor-ov (overlay-buffer cursor-ov))
                  (progn
                    (move-overlay cursor-ov pos end-pos)
                    (overlay-put cursor-ov 'face
                                 (if is-leader 'evm-leader-cursor-face 'evm-cursor-face))
                    ;; Update after-string for EOL
                    (if at-eol
                        (overlay-put cursor-ov 'after-string
                                     (propertize " " 'face (overlay-get cursor-ov 'face) 'cursor t))
                      (overlay-put cursor-ov 'after-string nil)))
                (when cursor-ov (delete-overlay cursor-ov))
                (let ((ov (make-overlay pos end-pos nil t nil)))
                  (overlay-put ov 'evm-type 'cursor)
                  (overlay-put ov 'evm-id (evm-region-id region))
                  (overlay-put ov 'priority 100)
                  (overlay-put ov 'face (if is-leader 'evm-leader-cursor-face 'evm-cursor-face))
                  (when at-eol
                    (overlay-put ov 'after-string
                                 (propertize " " 'face (overlay-get ov 'face) 'cursor t)))
                  (setf (evm-region-cursor-overlay region) ov))))))))))

(defun evm--update-all-overlays-full ()
  "Update all overlays by full recreation.
Use this when mode changes or overlays are corrupted."
  (evm--remove-all-overlays)
  (dolist (region (evm-state-regions evm--state))
    (evm--create-overlay-for-region region)))

(defun evm--remove-all-overlays ()
  "Remove all evm overlays from buffer.
Clears tracked overlay references from regions."
  ;; Clear tracked overlay references
  (dolist (region (evm-state-regions evm--state))
    (when-let ((ov (evm-region-overlay region)))
      (delete-overlay ov)
      (setf (evm-region-overlay region) nil))
    (when-let ((ov (evm-region-cursor-overlay region)))
      (delete-overlay ov)
      (setf (evm-region-cursor-overlay region) nil))))

(defun evm--remove-all-overlays-thorough ()
  "Remove all evm overlays including orphans.
Use this during cleanup when overlays might be inconsistent."
  (evm--remove-all-overlays)
  ;; Also scan for any orphan evm overlays (have evm-type property)
  (dolist (ov (overlays-in (point-min) (point-max)))
    (when (overlay-get ov 'evm-type)
      (delete-overlay ov))))

(defun evm--update-leader-overlays ()
  "Update overlays to reflect new leader.
In cursor mode, the leader has no cursor overlay (the real Emacs cursor
shows its position), so we must create/delete overlays when leader changes."
  (evm--update-all-overlays))

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
  "Enter cursor mode - collapse all regions to beginning of selection.
Like vim-visual-multi: when direction is forward, cursor goes to beginning."
  (setf (evm-state-mode evm--state) 'cursor)
  (dolist (region (evm-state-regions evm--state))
    ;; Collapse to beginning (like vim-visual-multi with dir=1)
    ;; For backward selections (dir=-1), use end instead
    (let ((cursor-pos (if (= (evm-region-dir region) 1)
                          (marker-position (evm-region-beg region))
                        (1- (marker-position (evm-region-end region))))))
      (set-marker (evm-region-beg region) cursor-pos)
      (set-marker (evm-region-end region) cursor-pos)
      (set-marker (evm-region-anchor region) cursor-pos)))
  (evm--update-all-overlays)
  (setq evm--last-buffer-tick (buffer-modified-tick))
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
  (setq evm--last-buffer-tick (buffer-modified-tick))
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
  (let ((positions '())
        (extend-p (evm-extend-mode-p)))
    ;; Calculate new positions
    (dolist (region (evm-state-regions evm--state))
      ;; Clear vcol on horizontal movement
      (setf (evm-region-vcol region) nil)
      (save-excursion
        ;; In extend mode, start from visual cursor pos (ON the character),
        ;; not from the exclusive end marker
        (goto-char (if extend-p
                       (evm--region-visual-cursor-pos region)
                     (evm--region-cursor-pos region)))
        (apply motion-fn args)
        (push (cons region (point)) positions)))
    ;; Apply new positions
    (dolist (pos-pair (nreverse positions))
      (if extend-p
          ;; In extend mode, motion returns inclusive position (char cursor is ON).
          ;; Convert to exclusive end for region storage.
          (let* ((region (car pos-pair))
                 (new-pos (cdr pos-pair))
                 (anchor-pos (marker-position (evm-region-anchor region))))
            (cond
             ((< new-pos anchor-pos)
              (set-marker (evm-region-beg region) new-pos)
              (set-marker (evm-region-end region) (1+ anchor-pos))
              (setf (evm-region-dir region) 0))
             (t
              (set-marker (evm-region-beg region) anchor-pos)
              (set-marker (evm-region-end region) (1+ new-pos))
              (setf (evm-region-dir region) 1))))
        (evm--region-set-cursor-pos (car pos-pair) (cdr pos-pair)))))
  ;; Move real point to leader position
  (when-let ((leader (evm--leader-region)))
    (goto-char (evm--region-visual-cursor-pos leader)))
  (evm--update-all-overlays))

(defun evm--move-cursors-vertically (count)
  "Move all cursors COUNT lines vertically, preserving each cursor's column.
Uses vcol to remember the desired column across short lines."
  (let ((positions '())
        (extend-p (evm-extend-mode-p)))
    ;; Calculate new positions using each region's vcol
    (dolist (region (evm-state-regions evm--state))
      (save-excursion
        (goto-char (if extend-p
                       (evm--region-visual-cursor-pos region)
                     (evm--region-cursor-pos region)))
        (evm--move-line-for-region region count)
        (push (cons region (point)) positions)))
    ;; Apply new positions
    (dolist (pos-pair (nreverse positions))
      (if extend-p
          (let* ((region (car pos-pair))
                 (new-pos (cdr pos-pair))
                 (anchor-pos (marker-position (evm-region-anchor region))))
            (cond
             ((< new-pos anchor-pos)
              (set-marker (evm-region-beg region) new-pos)
              (set-marker (evm-region-end region) (1+ anchor-pos))
              (setf (evm-region-dir region) 0))
             (t
              (set-marker (evm-region-beg region) anchor-pos)
              (set-marker (evm-region-end region) (1+ new-pos))
              (setf (evm-region-dir region) 1))))
        (evm--region-set-cursor-pos (car pos-pair) (cdr pos-pair)))))
  ;; Move real point to leader position
  (when-let ((leader (evm--leader-region)))
    (goto-char (evm--region-visual-cursor-pos leader)))
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
    (move-to-column col)
    ;; In cursor mode, clamp to last character like evil does
    ;; (vcol is preserved separately for column memory)
    (when (and (not (evm-extend-mode-p))
               (eolp) (not (bolp)))
      (backward-char 1))))

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
        ;; Empty line - stay at beginning
        (goto-char bol)
      (goto-char (1- eol)))))

(defun evm--move-first-non-blank ()
  "Move to first non-blank character."
  (back-to-indentation))

(defun evm--move-find-char (char count)
  "Move to COUNT-th occurrence of CHAR on current line (like evil f).
COUNT defaults to 1.  Cursor lands ON the character."
  (let ((case-fold-search nil)
        (target (char-to-string char))
        (start (point)))
    (forward-char 1)  ; skip current position
    (let ((found nil))
      (dotimes (_ count)
        (setq found (search-forward target (line-end-position) t)))
      (if found
          (backward-char 1)  ; search-forward lands after match, go back to ON char
        (goto-char start)))))

(defun evm--move-find-char-to (char count)
  "Move to one before COUNT-th occurrence of CHAR (like evil t).
COUNT defaults to 1.  Cursor lands one position before the character."
  (let ((case-fold-search nil)
        (target (char-to-string char))
        (start (point)))
    (forward-char 1)  ; skip current position
    (let ((found nil))
      (dotimes (_ count)
        (setq found (search-forward target (line-end-position) t)))
      (if found
          (backward-char 2)  ; land one before the match
        (goto-char start)))))

(defun evm--move-find-char-backward (char count)
  "Move backward to COUNT-th occurrence of CHAR (like evil F).
COUNT defaults to 1.  Cursor lands ON the character."
  (let ((case-fold-search nil)
        (target (char-to-string char))
        (start (point)))
    (let ((found nil))
      (dotimes (_ count)
        (setq found (search-backward target (line-beginning-position) t)))
      (unless found
        (goto-char start)))))

(defun evm--move-find-char-to-backward (char count)
  "Move to one after COUNT-th occurrence of CHAR backward (like evil T).
COUNT defaults to 1.  Cursor lands one position after the character."
  (let ((case-fold-search nil)
        (target (char-to-string char))
        (start (point)))
    (let ((found nil))
      (dotimes (_ count)
        (setq found (search-backward target (line-beginning-position) t)))
      (if found
          (forward-char 1)  ; land one after the match
        (goto-char start)))))

;;; Match preview (for pattern search)

(defvar-local evm--match-overlays nil
  "List of temporary overlays for match preview.")

(defun evm--match-spans-lines-p (beg end)
  "Return t when the match from BEG to END crosses a line boundary."
  (and (> end beg)
       (save-excursion
         (goto-char beg)
         (re-search-forward "\n" end t))))

(defun evm--match-allowed-p (beg end)
  "Return t if the match from BEG to END is allowed by current filters."
  (let ((bounds (evm--restrict-bounds))
        (multiline-p (and evm--state (evm-state-multiline-p evm--state))))
    (and (or (null bounds)
             (and (>= beg (car bounds))
                  (<= end (cdr bounds))))
         (or multiline-p
             (not (evm--match-spans-lines-p beg end))))))

(defun evm--show-match-preview (pattern)
  "Show preview of all matches for PATTERN."
  (evm--hide-match-preview)
  (save-excursion
    (goto-char (point-min))
    (while (re-search-forward pattern nil t)
      (let ((beg (match-beginning 0))
            (end (match-end 0)))
        (when (evm--match-allowed-p beg end)
          (let ((ov (make-overlay beg end)))
            (overlay-put ov 'face 'evm-match-face)
            (overlay-put ov 'evm-match t)
            (overlay-put ov 'priority 50)
            (push ov evm--match-overlays)))))))

(defun evm--show-match-preview-restricted (pattern)
  "Show preview of matches for PATTERN within current restriction."
  (evm--hide-match-preview)
  (let ((bounds (evm--restrict-bounds)))
    (save-excursion
      (goto-char (if bounds (car bounds) (point-min)))
      (while (re-search-forward pattern (when bounds (cdr bounds)) t)
        (let ((beg (match-beginning 0))
              (end (match-end 0)))
          (when (evm--match-allowed-p beg end)
            (let ((ov (make-overlay beg end)))
              (overlay-put ov 'face 'evm-match-face)
              (overlay-put ov 'evm-match t)
              (overlay-put ov 'priority 50)
              (push ov evm--match-overlays))))))))

(defun evm--hide-match-preview ()
  "Hide match preview overlays."
  (mapc #'delete-overlay evm--match-overlays)
  (setq evm--match-overlays nil))

;;; Mode-line

(defvar evm-show-mode-line)  ; defined in evm.el

(defun evm--mode-line-indicator ()
  "Return mode-line indicator string."
  (when (and (bound-and-true-p evm-show-mode-line)
             (evm-active-p))
    (let* ((mode (evm-state-mode evm--state))
           (count (evm-region-count))
           (leader-idx (1+ (or (evm--leader-index) 0)))
           (restricted (evm--restrict-active-p))
           (multiline (evm-state-multiline-p evm--state)))
      (propertize
       (format " EVM[%s %d/%d%s%s]"
               (if (eq mode 'cursor) "C" "E")
               leader-idx
               count
               (if restricted " R" "")
               (if multiline " M" ""))
       'face 'evm-mode-line-face))))

;;; Overlapping regions check

(defun evm--regions-overlap-p (r1 r2)
  "Check if regions R1 and R2 overlap."
  (let ((b1 (marker-position (evm-region-beg r1)))
        (e1 (marker-position (evm-region-end r1)))
        (b2 (marker-position (evm-region-beg r2)))
        (e2 (marker-position (evm-region-end r2))))
    (and (< b1 e2) (< b2 e1))))

(defun evm--regions-mergeable-p (r1 r2)
  "Return t if R1 and R2 should be merged.
This merges genuinely overlapping regions, plus duplicate point
cursors at the exact same position."
  (or (evm--regions-overlap-p r1 r2)
      (and (= (marker-position (evm-region-beg r1))
              (marker-position (evm-region-end r1)))
           (= (marker-position (evm-region-beg r2))
              (marker-position (evm-region-end r2)))
           (= (marker-position (evm-region-beg r1))
              (marker-position (evm-region-beg r2))))))

(defun evm--check-and-merge-overlapping ()
  "Check for overlapping regions and merge them.
Uses O(n) algorithm: sort first, then single-pass merge of adjacent regions."
  (let ((regions (evm-state-regions evm--state))
        (ht (evm-state-region-by-id evm--state)))
    (when (>= (length regions) 2)
      ;; Sort by beg position for single-pass merge
      (setq regions (sort regions
                          (lambda (a b)
                            (< (marker-position (evm-region-beg a))
                               (marker-position (evm-region-beg b))))))
      (let ((result nil)
            (current (car regions)))
        ;; Single pass: merge adjacent overlapping regions
        (dolist (next (cdr regions))
          (let ((cur-end (marker-position (evm-region-end current))))
            (if (evm--regions-mergeable-p current next)
                ;; Overlap: extend current, delete next
                (progn
                  (set-marker (evm-region-end current)
                              (max cur-end (marker-position (evm-region-end next))))
                  (when (and (evm-state-leader-id evm--state)
                             (= (evm-state-leader-id evm--state)
                                (evm-region-id next)))
                    (setf (evm-state-leader-id evm--state)
                          (evm-region-id current)))
                  (setf (evm-region-txt current)
                        (buffer-substring-no-properties
                         (marker-position (evm-region-beg current))
                         (marker-position (evm-region-end current))))
                  ;; Clean up next region
                  (remhash (evm-region-id next) ht)
                  (when (evm-region-overlay next)
                    (delete-overlay (evm-region-overlay next)))
                  (when (evm-region-cursor-overlay next)
                    (delete-overlay (evm-region-cursor-overlay next)))
                  (set-marker (evm-region-beg next) nil)
                  (set-marker (evm-region-end next) nil)
                  (set-marker (evm-region-anchor next) nil))
              ;; No overlap: finalize current, start new
              (push current result)
              (setq current next))))
        ;; Don't forget the last current
        (push current result)
        (setf (evm-state-regions evm--state) (nreverse result))))
    (evm--update-region-indices)))

;;; Restrict to region

(defun evm--restrict-active-p ()
  "Return t if a restriction is active."
  (and evm--state
       (evm-state-restrict-beg evm--state)
       (evm-state-restrict-end evm--state)))

(defun evm--set-restrict (beg end)
  "Set restriction to region from BEG to END."
  (evm--clear-restrict)
  (setf (evm-state-restrict-beg evm--state) (evm--make-marker beg))
  (setf (evm-state-restrict-end evm--state) (evm--make-marker end))
  ;; Create visual overlay for restriction
  (let ((ov (make-overlay beg end nil nil t)))
    (overlay-put ov 'face 'evm-restrict-face)
    (overlay-put ov 'evm-restrict t)
    (overlay-put ov 'priority 10)
    (setf (evm-state-restrict-overlay evm--state) ov)))

(defun evm--clear-restrict ()
  "Clear current restriction."
  (when evm--state
    (when-let ((ov (evm-state-restrict-overlay evm--state)))
      (delete-overlay ov))
    (when-let ((beg (evm-state-restrict-beg evm--state)))
      (set-marker beg nil))
    (when-let ((end (evm-state-restrict-end evm--state)))
      (set-marker end nil))
    (setf (evm-state-restrict-beg evm--state) nil
          (evm-state-restrict-end evm--state) nil
          (evm-state-restrict-overlay evm--state) nil)))

(defun evm--restrict-bounds ()
  "Return (BEG . END) of current restriction, or nil if none."
  (when (evm--restrict-active-p)
    (cons (marker-position (evm-state-restrict-beg evm--state))
          (marker-position (evm-state-restrict-end evm--state)))))

(defun evm--point-in-restrict-p (pos)
  "Return t if POS is within the current restriction (or no restriction)."
  (if-let ((bounds (evm--restrict-bounds)))
      (and (>= pos (car bounds))
           (<= pos (cdr bounds)))
    t))

(provide 'evm-core)
;; Local Variables:
;; package-lint-main-file: "evm.el"
;; End:
;;; evm-core.el ends here
