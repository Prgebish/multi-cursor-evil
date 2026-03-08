;;; evim-core.el --- Core data structures and cursor system -*- lexical-binding: t; -*-

;; Copyright (C) 2025
;; SPDX-License-Identifier: MIT

;;; Commentary:

;; Core module for evil-visual-multi.
;; Provides data structures (evim-region, evim-state),
;; cursor/overlay management, and basic operations.

;;; Code:

(require 'cl-lib)
(require 'evil)

;; Forward declaration for function defined in evim.el
(declare-function evim--update-keymap "evim" ())
(defvar evim--last-buffer-tick)

;;; Custom group

(defgroup evim nil
  "Multiple cursors for `evil-mode'."
  :group 'evil
  :prefix "evim-")

;;; Faces

(defface evim-cursor-face
  '((((class color) (background dark))
     :background "#3B82F6" :foreground "white")
    (((class color) (background light))
     :background "#2563EB" :foreground "white"))
  "Face for cursors in cursor mode."
  :group 'evim)

(defface evim-region-face
  '((((class color) (background dark))
     :background "#166534")
    (((class color) (background light))
     :background "#BBF7D0"))
  "Face for selected regions in extend mode."
  :group 'evim)

(defface evim-leader-cursor-face
  '((((class color) (background dark))
     :background "#F97316" :foreground "black")
    (((class color) (background light))
     :background "#EA580C" :foreground "white"))
  "Face for the leader cursor position."
  :group 'evim)

(defface evim-leader-region-face
  '((((class color) (background dark))
     :background "#854D0E")
    (((class color) (background light))
     :background "#FEF08A"))
  "Face for the leader region in extend mode."
  :group 'evim)

(defface evim-mode-line-face
  '((t nil))
  "Face for evim indicator in mode-line."
  :group 'evim)

(defface evim-match-face
  '((((class color) (background dark))
     :background "#374151" :underline t)
    (((class color) (background light))
     :background "#E5E7EB" :underline t))
  "Face for potential matches (pattern preview)."
  :group 'evim)

(defface evim-restrict-face
  '((((class color) (background dark))
     :background "#1E293B")
    (((class color) (background light))
     :background "#F1F5F9"))
  "Face for restricted region boundary."
  :group 'evim)

;;; Data Structures

(cl-defstruct evim-region
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

(cl-defstruct evim-state
  "Buffer-local global state for evim."
  active-p        ; is evim active in buffer
  mode            ; 'cursor or 'extend
  regions         ; list of evim-region, sorted by position
  region-by-id    ; hash-table: id -> evim-region for O(1) lookup
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

(defvar-local evim--state nil
  "Buffer-local evim state.")

(defvar-local evim--pending-restrict nil
  "Pending restriction bounds (beg . end) to apply on next evim activation.")

;;; State predicates

(defun evim-active-p ()
  "Return t if evim is active in current buffer."
  (and evim--state (evim-state-active-p evim--state)))

(defun evim-cursor-mode-p ()
  "Return t if in cursor mode."
  (and (evim-active-p)
       (eq (evim-state-mode evim--state) 'cursor)))

(defun evim-extend-mode-p ()
  "Return t if in extend mode."
  (and (evim-active-p)
       (eq (evim-state-mode evim--state) 'extend)))

;;; Region management

(defun evim--generate-id ()
  "Generate unique region ID."
  (cl-incf (evim-state-id-counter evim--state)))

(defun evim--make-marker (pos)
  "Create marker at POS."
  (let ((marker (make-marker)))
    (set-marker marker pos)
    (set-marker-insertion-type marker t)
    marker))

(defun evim--create-region (beg end &optional pattern)
  "Create new region from BEG to END with optional PATTERN.
Returns the created region."
  (let* ((id (evim--generate-id))
         (region (make-evim-region
                  :id id
                  :beg (evim--make-marker beg)
                  :end (evim--make-marker end)
                  :anchor (evim--make-marker beg)
                  :dir 1
                  :vcol nil
                  :txt (buffer-substring-no-properties beg end)
                  :pattern pattern)))
    ;; Add to hash-table for O(1) lookup
    (puthash id region (evim-state-region-by-id evim--state))
    ;; Insert into sorted list (more efficient than push + sort)
    (evim--insert-region-sorted region)
    ;; Update indices
    (evim--update-region-indices)
    ;; Set as leader if first region
    (unless (evim-state-leader-id evim--state)
      (setf (evim-state-leader-id evim--state) id))
    ;; Create overlay
    (evim--create-overlay-for-region region)
    region))

(defun evim--delete-region (region)
  "Delete REGION and its overlays."
  (when (evim-region-overlay region)
    (delete-overlay (evim-region-overlay region)))
  (when (evim-region-cursor-overlay region)
    (delete-overlay (evim-region-cursor-overlay region)))
  ;; Remove markers
  (set-marker (evim-region-beg region) nil)
  (set-marker (evim-region-end region) nil)
  (set-marker (evim-region-anchor region) nil)
  ;; Remove from hash-table
  (remhash (evim-region-id region) (evim-state-region-by-id evim--state))
  ;; Remove from list
  (setf (evim-state-regions evim--state)
        (cl-remove-if (lambda (r) (= (evim-region-id r) (evim-region-id region)))
                      (evim-state-regions evim--state)))
  ;; Update leader if needed
  (when (and (evim-state-leader-id evim--state)
             (= (evim-state-leader-id evim--state) (evim-region-id region)))
    (setf (evim-state-leader-id evim--state)
          (when-let ((first (car (evim-state-regions evim--state))))
            (evim-region-id first))))
  ;; Update indices
  (evim--update-region-indices))

(defun evim--sort-regions ()
  "Sort regions by position."
  (setf (evim-state-regions evim--state)
        (cl-sort (evim-state-regions evim--state)
                 #'<
                 :key (lambda (r) (marker-position (evim-region-beg r))))))

(defun evim--insert-region-sorted (region)
  "Insert REGION into the sorted regions list in correct position.
This is O(n) but avoids the O(n log n) cost of full sort."
  (let* ((regions (evim-state-regions evim--state))
         (pos (marker-position (evim-region-beg region))))
    (if (null regions)
        (setf (evim-state-regions evim--state) (list region))
      ;; Find insertion point
      (let ((prev nil)
            (curr regions))
        (while (and curr
                    (< (marker-position (evim-region-beg (car curr))) pos))
          (setq prev curr
                curr (cdr curr)))
        (if prev
            ;; Insert after prev
            (setcdr prev (cons region curr))
          ;; Insert at beginning
          (setf (evim-state-regions evim--state) (cons region regions)))))))

(defun evim--create-regions-batch (positions-list &optional pattern)
  "Create multiple regions at once from POSITIONS-LIST.
POSITIONS-LIST is a list of (BEG . END) cons cells.
PATTERN is the optional search pattern for all regions.
This is more efficient than calling `evim--create-region' in a loop
because it sorts once and creates overlays in batch."
  (let ((new-regions '())
        (ht (evim-state-region-by-id evim--state)))
    ;; Create all regions without sorting or overlays
    (dolist (pos positions-list)
      (let* ((beg (car pos))
             (end (cdr pos))
             (id (evim--generate-id))
             (region (make-evim-region
                      :id id
                      :beg (evim--make-marker beg)
                      :end (evim--make-marker end)
                      :anchor (evim--make-marker beg)
                      :dir 1
                      :vcol nil
                      :txt (buffer-substring-no-properties beg end)
                      :pattern pattern)))
        ;; Add to hash-table for O(1) lookup
        (puthash id region ht)
        (push region new-regions)))
    ;; Add all new regions to list
    (setf (evim-state-regions evim--state)
          (nconc (evim-state-regions evim--state) (nreverse new-regions)))
    ;; Sort once
    (evim--sort-regions)
    ;; Update all indices
    (evim--update-region-indices)
    ;; Set leader if not set
    (unless (evim-state-leader-id evim--state)
      (when-let ((first (car (evim-state-regions evim--state))))
        (setf (evim-state-leader-id evim--state) (evim-region-id first))))
    ;; Create all overlays
    (dolist (region new-regions)
      (evim--create-overlay-for-region region))
    new-regions))

(defun evim--update-region-indices ()
  "Update index field for all regions."
  (cl-loop for region in (evim-state-regions evim--state)
           for idx from 0
           do (setf (evim-region-index region) idx)))

(defun evim-get-all-regions ()
  "Return all regions."
  (when evim--state
    (evim-state-regions evim--state)))

(defun evim-region-count ()
  "Return number of regions."
  (length (evim-get-all-regions)))

(defun evim--get-region-by-id (id)
  "Find region by ID.  O(1) lookup using hash-table."
  (gethash id (evim-state-region-by-id evim--state)))

(defun evim--leader-region ()
  "Get the leader region."
  (when-let ((id (evim-state-leader-id evim--state)))
    (evim--get-region-by-id id)))

(defun evim--leader-p (region)
  "Return t if REGION is the leader."
  (and (evim-state-leader-id evim--state)
       (= (evim-region-id region) (evim-state-leader-id evim--state))))

(defun evim--leader-index ()
  "Return index of the leader region."
  (when-let ((leader (evim--leader-region)))
    (evim-region-index leader)))

(defun evim--set-leader (region)
  "Set REGION as the leader."
  (setf (evim-state-leader-id evim--state) (evim-region-id region))
  (evim--update-leader-overlays))

;;; Overlay management

(defvar evim--insert-active)  ; defined in evim.el

(defun evim--create-overlay-for-region (region)
  "Create overlay(s) for REGION based on current mode."
  (if (evim-extend-mode-p)
      (evim--create-region-overlay region)
    ;; Cursor mode: skip leader — the real Emacs cursor shows leader position.
    ;; This avoids the overlay face overriding the cursor display in GUI Emacs.
    (unless (evim--leader-p region)
      (evim--create-cursor-overlay region))))

(defun evim--create-cursor-overlay (region)
  "Create cursor overlay for REGION."
  (let* ((pos (marker-position (evim-region-beg region)))
         (at-eol (save-excursion
                   (goto-char pos)
                   (or (= pos (line-end-position))
                       (= pos (point-max)))))
         ;; At EOL, don't extend overlay past line end - just cover the position
         (end-pos (if at-eol pos (min (1+ pos) (point-max))))
         (ov (make-overlay pos end-pos nil t nil)))
    (overlay-put ov 'evim-type 'cursor)
    (overlay-put ov 'evim-id (evim-region-id region))
    (overlay-put ov 'priority 100)
    (overlay-put ov 'face
                 (if (evim--leader-p region)
                     'evim-leader-cursor-face
                   'evim-cursor-face))
    ;; For EOL or EOF - show as bar after the line
    (when at-eol
      (overlay-put ov 'after-string
                   (propertize " " 'face (overlay-get ov 'face)
                               'cursor t)))
    (setf (evim-region-cursor-overlay region) ov)))

(defun evim--create-region-overlay (region)
  "Create region overlay for REGION in extend mode."
  (let* ((beg (marker-position (evim-region-beg region)))
         (end (marker-position (evim-region-end region)))
         (ov (make-overlay beg end nil t nil)))
    (overlay-put ov 'evim-type 'region)
    (overlay-put ov 'evim-id (evim-region-id region))
    (overlay-put ov 'priority 90)
    (overlay-put ov 'face
                 (if (evim--leader-p region)
                     'evim-leader-region-face
                   'evim-region-face))
    (setf (evim-region-overlay region) ov))
  ;; Also create cursor overlay within region
  (evim--create-cursor-in-region-overlay region))

(defun evim--create-cursor-in-region-overlay (region)
  "Create cursor overlay within REGION to show the active end."
  (let* ((cursor-pos (if (= (evim-region-dir region) 1)
                         (1- (marker-position (evim-region-end region)))
                       (marker-position (evim-region-beg region))))
         (cursor-pos (max (point-min) cursor-pos))
         (end-pos (min (1+ cursor-pos) (point-max)))
         (ov (make-overlay cursor-pos end-pos nil t nil)))
    (overlay-put ov 'evim-type 'cursor)
    (overlay-put ov 'evim-id (evim-region-id region))
    (overlay-put ov 'priority 110)
    (overlay-put ov 'face
                 (if (evim--leader-p region)
                     'evim-leader-cursor-face
                   'evim-cursor-face))
    (setf (evim-region-cursor-overlay region) ov)))

(defun evim--update-all-overlays ()
  "Update all overlays based on current state.
Attempts to reuse existing overlays when possible for better performance."
  (let ((extend-mode-p (evim-extend-mode-p)))
    (dolist (region (evim-state-regions evim--state))
      (let* ((is-leader (evim--leader-p region))
             (cursor-ov (evim-region-cursor-overlay region))
             (region-ov (evim-region-overlay region)))
        (if extend-mode-p
            ;; Extend mode: need both region and cursor overlays
            (let ((beg (marker-position (evim-region-beg region)))
                  (end (marker-position (evim-region-end region))))
              ;; Update or create region overlay
              (if (and region-ov (overlay-buffer region-ov))
                  (progn
                    (move-overlay region-ov beg end)
                    (overlay-put region-ov 'face
                                 (if is-leader 'evim-leader-region-face 'evim-region-face)))
                ;; Need to create region overlay
                (when region-ov (delete-overlay region-ov))
                (let ((ov (make-overlay beg end nil t nil)))
                  (overlay-put ov 'evim-type 'region)
                  (overlay-put ov 'evim-id (evim-region-id region))
                  (overlay-put ov 'priority 90)
                  (overlay-put ov 'face (if is-leader 'evim-leader-region-face 'evim-region-face))
                  (setf (evim-region-overlay region) ov)))
              ;; Update or create cursor-in-region overlay
              (let* ((cursor-pos (if (= (evim-region-dir region) 1)
                                     (1- end)
                                   beg))
                     (cursor-pos (max (point-min) cursor-pos))
                     (end-pos (min (1+ cursor-pos) (point-max))))
                (if (and cursor-ov (overlay-buffer cursor-ov))
                    (progn
                      (move-overlay cursor-ov cursor-pos end-pos)
                      (overlay-put cursor-ov 'face
                                   (if is-leader 'evim-leader-cursor-face 'evim-cursor-face)))
                  (when cursor-ov (delete-overlay cursor-ov))
                  (let ((ov (make-overlay cursor-pos end-pos nil t nil)))
                    (overlay-put ov 'evim-type 'cursor)
                    (overlay-put ov 'evim-id (evim-region-id region))
                    (overlay-put ov 'priority 110)
                    (overlay-put ov 'face (if is-leader 'evim-leader-cursor-face 'evim-cursor-face))
                    (setf (evim-region-cursor-overlay region) ov)))))
          ;; Cursor mode: only need cursor overlay
          ;; Delete region overlay if it exists
          (when (and region-ov (overlay-buffer region-ov))
            (delete-overlay region-ov)
            (setf (evim-region-overlay region) nil))
          ;; Update or create cursor overlay
          (if is-leader
              ;; Hide leader cursor overlay — the real Emacs cursor shows leader position.
              ;; This avoids the overlay face overriding the cursor display in GUI Emacs.
              (when (and cursor-ov (overlay-buffer cursor-ov))
                (delete-overlay cursor-ov)
                (setf (evim-region-cursor-overlay region) nil))
            (let* ((pos (marker-position (evim-region-beg region)))
                   (at-eol (save-excursion
                             (goto-char pos)
                             (or (= pos (line-end-position))
                                 (= pos (point-max)))))
                   (end-pos (if at-eol pos (min (1+ pos) (point-max)))))
              (if (and cursor-ov (overlay-buffer cursor-ov))
                  (progn
                    (move-overlay cursor-ov pos end-pos)
                    (overlay-put cursor-ov 'face
                                 (if is-leader 'evim-leader-cursor-face 'evim-cursor-face))
                    ;; Update after-string for EOL
                    (if at-eol
                        (overlay-put cursor-ov 'after-string
                                     (propertize " " 'face (overlay-get cursor-ov 'face) 'cursor t))
                      (overlay-put cursor-ov 'after-string nil)))
                (when cursor-ov (delete-overlay cursor-ov))
                (let ((ov (make-overlay pos end-pos nil t nil)))
                  (overlay-put ov 'evim-type 'cursor)
                  (overlay-put ov 'evim-id (evim-region-id region))
                  (overlay-put ov 'priority 100)
                  (overlay-put ov 'face (if is-leader 'evim-leader-cursor-face 'evim-cursor-face))
                  (when at-eol
                    (overlay-put ov 'after-string
                                 (propertize " " 'face (overlay-get ov 'face) 'cursor t)))
                  (setf (evim-region-cursor-overlay region) ov))))))))))

(defun evim--update-all-overlays-full ()
  "Update all overlays by full recreation.
Use this when mode changes or overlays are corrupted."
  (evim--remove-all-overlays)
  (dolist (region (evim-state-regions evim--state))
    (evim--create-overlay-for-region region)))

(defun evim--remove-all-overlays ()
  "Remove all evim overlays from buffer.
Clears tracked overlay references from regions."
  ;; Clear tracked overlay references
  (dolist (region (evim-state-regions evim--state))
    (when-let ((ov (evim-region-overlay region)))
      (delete-overlay ov)
      (setf (evim-region-overlay region) nil))
    (when-let ((ov (evim-region-cursor-overlay region)))
      (delete-overlay ov)
      (setf (evim-region-cursor-overlay region) nil))))

(defun evim--remove-all-overlays-thorough ()
  "Remove all evim overlays including orphans.
Use this during cleanup when overlays might be inconsistent."
  (evim--remove-all-overlays)
  ;; Also scan for any orphan evim overlays (have evim-type property)
  (dolist (ov (overlays-in (point-min) (point-max)))
    (when (overlay-get ov 'evim-type)
      (delete-overlay ov))))

(defun evim--update-leader-overlays ()
  "Update overlays to reflect new leader.
In cursor mode, the leader has no cursor overlay (the real Emacs cursor
shows its position), so we must create/delete overlays when leader changes."
  (evim--update-all-overlays))

;;; Region position helpers

(defun evim--region-cursor-pos (region)
  "Get cursor position within REGION."
  (if (= (evim-region-dir region) 1)
      (marker-position (evim-region-end region))
    (marker-position (evim-region-beg region))))

(defun evim--region-visual-cursor-pos (region)
  "Get visual cursor position within REGION.
In extend mode with dir=1, cursor is ON the last char (end-1), not after.
This is used for positioning the actual Emacs point."
  (if (= (evim-region-dir region) 1)
      (if (evim-extend-mode-p)
          ;; In extend mode, cursor is ON the last character (like evil visual)
          (max (marker-position (evim-region-beg region))
               (1- (marker-position (evim-region-end region))))
        ;; In cursor mode, beg=end anyway
        (marker-position (evim-region-end region)))
    (marker-position (evim-region-beg region))))

(defun evim--region-set-cursor-pos (region pos)
  "Set cursor position in REGION to POS.
In cursor mode: moves the whole region.
In extend mode: moves the active end."
  (if (evim-cursor-mode-p)
      ;; Cursor mode: move everything
      (progn
        (set-marker (evim-region-beg region) pos)
        (set-marker (evim-region-end region) pos)
        (set-marker (evim-region-anchor region) pos))
    ;; Extend mode: move active end, adjust beg/end
    (let ((anchor-pos (marker-position (evim-region-anchor region))))
      (cond
       ((< pos anchor-pos)
        (set-marker (evim-region-beg region) pos)
        (set-marker (evim-region-end region) anchor-pos)
        (setf (evim-region-dir region) 0))
       (t
        (set-marker (evim-region-beg region) anchor-pos)
        (set-marker (evim-region-end region) pos)
        (setf (evim-region-dir region) 1))))))

(defun evim--region-empty-p (region)
  "Return t if REGION is empty (cursor mode)."
  (= (marker-position (evim-region-beg region))
     (marker-position (evim-region-end region))))

;;; Mode switching

(defun evim--enter-cursor-mode ()
  "Enter cursor mode - collapse all regions to beginning of selection.
Like vim-visual-multi: when direction is forward, cursor goes to beginning."
  (setf (evim-state-mode evim--state) 'cursor)
  (dolist (region (evim-state-regions evim--state))
    ;; Collapse to beginning (like vim-visual-multi with dir=1)
    ;; For backward selections (dir=-1), use end instead
    (let ((cursor-pos (if (= (evim-region-dir region) 1)
                          (marker-position (evim-region-beg region))
                        (1- (marker-position (evim-region-end region))))))
      (set-marker (evim-region-beg region) cursor-pos)
      (set-marker (evim-region-end region) cursor-pos)
      (set-marker (evim-region-anchor region) cursor-pos)))
  (evim--update-all-overlays)
  (setq evim--last-buffer-tick (buffer-modified-tick))
  (evim--update-keymap))

(defun evim--enter-extend-mode ()
  "Enter extend mode - extend regions from current positions."
  (setf (evim-state-mode evim--state) 'extend)
  ;; If regions are empty (from cursor mode), extend by 1 char
  (dolist (region (evim-state-regions evim--state))
    (when (evim--region-empty-p region)
      (let ((pos (marker-position (evim-region-beg region))))
        (set-marker (evim-region-end region)
                    (min (1+ pos) (point-max)))
        (setf (evim-region-dir region) 1))))
  (evim--update-all-overlays)
  (setq evim--last-buffer-tick (buffer-modified-tick))
  (evim--update-keymap))

(defun evim-toggle-mode ()
  "Toggle between cursor and extend mode."
  (interactive)
  (when (evim-active-p)
    (if (evim-cursor-mode-p)
        (evim--enter-extend-mode)
      (evim--enter-cursor-mode))))

;;; Cursor movement

(defun evim--move-cursors (motion-fn &rest args)
  "Move all cursors using MOTION-FN with ARGS.
MOTION-FN should move point and return new position.
This clears vcol for all regions (horizontal movement)."
  (let ((positions '())
        (extend-p (evim-extend-mode-p)))
    ;; Calculate new positions
    (dolist (region (evim-state-regions evim--state))
      ;; Clear vcol on horizontal movement
      (setf (evim-region-vcol region) nil)
      (save-excursion
        ;; In extend mode, start from visual cursor pos (ON the character),
        ;; not from the exclusive end marker
        (goto-char (if extend-p
                       (evim--region-visual-cursor-pos region)
                     (evim--region-cursor-pos region)))
        (apply motion-fn args)
        (push (cons region (point)) positions)))
    ;; Apply new positions
    (dolist (pos-pair (nreverse positions))
      (if extend-p
          ;; In extend mode, motion returns inclusive position (char cursor is ON).
          ;; Convert to exclusive end for region storage.
          (let* ((region (car pos-pair))
                 (new-pos (cdr pos-pair))
                 (anchor-pos (marker-position (evim-region-anchor region))))
            (cond
             ((< new-pos anchor-pos)
              (set-marker (evim-region-beg region) new-pos)
              (set-marker (evim-region-end region) (1+ anchor-pos))
              (setf (evim-region-dir region) 0))
             (t
              (set-marker (evim-region-beg region) anchor-pos)
              (set-marker (evim-region-end region) (1+ new-pos))
              (setf (evim-region-dir region) 1))))
        (evim--region-set-cursor-pos (car pos-pair) (cdr pos-pair)))))
  ;; Move real point to leader position
  (when-let ((leader (evim--leader-region)))
    (goto-char (evim--region-visual-cursor-pos leader)))
  (evim--update-all-overlays))

(defun evim--move-cursors-vertically (count)
  "Move all cursors COUNT lines vertically, preserving each cursor's column.
Uses vcol to remember the desired column across short lines."
  (let ((positions '())
        (extend-p (evim-extend-mode-p)))
    ;; Calculate new positions using each region's vcol
    (dolist (region (evim-state-regions evim--state))
      (save-excursion
        (goto-char (if extend-p
                       (evim--region-visual-cursor-pos region)
                     (evim--region-cursor-pos region)))
        (evim--move-line-for-region region count)
        (push (cons region (point)) positions)))
    ;; Apply new positions
    (dolist (pos-pair (nreverse positions))
      (if extend-p
          (let* ((region (car pos-pair))
                 (new-pos (cdr pos-pair))
                 (anchor-pos (marker-position (evim-region-anchor region))))
            (cond
             ((< new-pos anchor-pos)
              (set-marker (evim-region-beg region) new-pos)
              (set-marker (evim-region-end region) (1+ anchor-pos))
              (setf (evim-region-dir region) 0))
             (t
              (set-marker (evim-region-beg region) anchor-pos)
              (set-marker (evim-region-end region) (1+ new-pos))
              (setf (evim-region-dir region) 1))))
        (evim--region-set-cursor-pos (car pos-pair) (cdr pos-pair)))))
  ;; Move real point to leader position
  (when-let ((leader (evim--leader-region)))
    (goto-char (evim--region-visual-cursor-pos leader)))
  (evim--update-all-overlays))

(defun evim--move-char (count)
  "Move COUNT characters, respecting buffer bounds."
  (let ((target (+ (point) count)))
    (goto-char (max (point-min) (min target (point-max))))))

(defun evim--move-line-for-region (region count)
  "Move COUNT lines using REGION's vcol.
This function is called with point already at the region's cursor position."
  ;; Set vcol if not already set (first j/k in a sequence)
  (unless (evim-region-vcol region)
    (setf (evim-region-vcol region) (current-column)))
  (let ((col (evim-region-vcol region)))
    (forward-line count)
    (move-to-column col)
    ;; In cursor mode, clamp to last character like evil does
    ;; (vcol is preserved separately for column memory)
    (when (and (not (evim-extend-mode-p))
               (eolp) (not (bolp)))
      (backward-char 1))))

(defun evim--move-word (count)
  "Move forward COUNT words."
  (evil-forward-word-begin count))

(defun evim--move-word-end (count)
  "Move to end of COUNT words."
  (evil-forward-word-end count))

(defun evim--move-word-back (count)
  "Move backward COUNT words."
  (evil-backward-word-begin count))

(defun evim--move-line-beg ()
  "Move to beginning of line."
  (beginning-of-line))

(defun evim--move-line-end ()
  "Move to end of line (last character, like evil $)."
  (let ((eol (line-end-position))
        (bol (line-beginning-position)))
    (if (= bol eol)
        ;; Empty line - stay at beginning
        (goto-char bol)
      (goto-char (1- eol)))))

(defun evim--move-first-non-blank ()
  "Move to first non-blank character."
  (back-to-indentation))

(defun evim--move-find-char (char count)
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

(defun evim--move-find-char-to (char count)
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

(defun evim--move-find-char-backward (char count)
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

(defun evim--move-find-char-to-backward (char count)
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

(defvar-local evim--match-overlays nil
  "List of temporary overlays for match preview.")

(defun evim--match-spans-lines-p (beg end)
  "Return t when the match from BEG to END crosses a line boundary."
  (and (> end beg)
       (save-excursion
         (goto-char beg)
         (re-search-forward "\n" end t))))

(defun evim--match-allowed-p (beg end)
  "Return t if the match from BEG to END is allowed by current filters."
  (let ((bounds (evim--restrict-bounds))
        (multiline-p (and evim--state (evim-state-multiline-p evim--state))))
    (and (or (null bounds)
             (and (>= beg (car bounds))
                  (<= end (cdr bounds))))
         (or multiline-p
             (not (evim--match-spans-lines-p beg end))))))

(defun evim--show-match-preview (pattern)
  "Show preview of all matches for PATTERN."
  (evim--hide-match-preview)
  (save-excursion
    (goto-char (point-min))
    (while (re-search-forward pattern nil t)
      (let ((beg (match-beginning 0))
            (end (match-end 0)))
        (when (evim--match-allowed-p beg end)
          (let ((ov (make-overlay beg end)))
            (overlay-put ov 'face 'evim-match-face)
            (overlay-put ov 'evim-match t)
            (overlay-put ov 'priority 50)
            (push ov evim--match-overlays)))))))

(defun evim--show-match-preview-restricted (pattern)
  "Show preview of matches for PATTERN within current restriction."
  (evim--hide-match-preview)
  (let ((bounds (evim--restrict-bounds)))
    (save-excursion
      (goto-char (if bounds (car bounds) (point-min)))
      (while (re-search-forward pattern (when bounds (cdr bounds)) t)
        (let ((beg (match-beginning 0))
              (end (match-end 0)))
          (when (evim--match-allowed-p beg end)
            (let ((ov (make-overlay beg end)))
              (overlay-put ov 'face 'evim-match-face)
              (overlay-put ov 'evim-match t)
              (overlay-put ov 'priority 50)
              (push ov evim--match-overlays))))))))

(defun evim--hide-match-preview ()
  "Hide match preview overlays."
  (mapc #'delete-overlay evim--match-overlays)
  (setq evim--match-overlays nil))

;;; Mode-line

(defvar evim-show-mode-line)  ; defined in evim.el

(defun evim--mode-line-indicator ()
  "Return mode-line indicator string."
  (when (and (bound-and-true-p evim-show-mode-line)
             (evim-active-p))
    (let* ((mode (evim-state-mode evim--state))
           (count (evim-region-count))
           (leader-idx (1+ (or (evim--leader-index) 0)))
           (restricted (evim--restrict-active-p))
           (multiline (evim-state-multiline-p evim--state)))
      (propertize
       (format " EVM[%s %d/%d%s%s]"
               (if (eq mode 'cursor) "C" "E")
               leader-idx
               count
               (if restricted " R" "")
               (if multiline " M" ""))
       'face 'evim-mode-line-face))))

;;; Overlapping regions check

(defun evim--regions-overlap-p (r1 r2)
  "Check if regions R1 and R2 overlap."
  (let ((b1 (marker-position (evim-region-beg r1)))
        (e1 (marker-position (evim-region-end r1)))
        (b2 (marker-position (evim-region-beg r2)))
        (e2 (marker-position (evim-region-end r2))))
    (and (< b1 e2) (< b2 e1))))

(defun evim--regions-mergeable-p (r1 r2)
  "Return t if R1 and R2 should be merged.
This merges genuinely overlapping regions, plus duplicate point
cursors at the exact same position."
  (or (evim--regions-overlap-p r1 r2)
      (and (= (marker-position (evim-region-beg r1))
              (marker-position (evim-region-end r1)))
           (= (marker-position (evim-region-beg r2))
              (marker-position (evim-region-end r2)))
           (= (marker-position (evim-region-beg r1))
              (marker-position (evim-region-beg r2))))))

(defun evim--check-and-merge-overlapping ()
  "Check for overlapping regions and merge them.
Uses O(n) algorithm: sort first, then single-pass merge of adjacent regions."
  (let ((regions (evim-state-regions evim--state))
        (ht (evim-state-region-by-id evim--state)))
    (when (>= (length regions) 2)
      ;; Sort by beg position for single-pass merge
      (setq regions (sort regions
                          (lambda (a b)
                            (< (marker-position (evim-region-beg a))
                               (marker-position (evim-region-beg b))))))
      (let ((result nil)
            (current (car regions)))
        ;; Single pass: merge adjacent overlapping regions
        (dolist (next (cdr regions))
          (let ((cur-end (marker-position (evim-region-end current))))
            (if (evim--regions-mergeable-p current next)
                ;; Overlap: extend current, delete next
                (progn
                  (set-marker (evim-region-end current)
                              (max cur-end (marker-position (evim-region-end next))))
                  (when (and (evim-state-leader-id evim--state)
                             (= (evim-state-leader-id evim--state)
                                (evim-region-id next)))
                    (setf (evim-state-leader-id evim--state)
                          (evim-region-id current)))
                  (setf (evim-region-txt current)
                        (buffer-substring-no-properties
                         (marker-position (evim-region-beg current))
                         (marker-position (evim-region-end current))))
                  ;; Clean up next region
                  (remhash (evim-region-id next) ht)
                  (when (evim-region-overlay next)
                    (delete-overlay (evim-region-overlay next)))
                  (when (evim-region-cursor-overlay next)
                    (delete-overlay (evim-region-cursor-overlay next)))
                  (set-marker (evim-region-beg next) nil)
                  (set-marker (evim-region-end next) nil)
                  (set-marker (evim-region-anchor next) nil))
              ;; No overlap: finalize current, start new
              (push current result)
              (setq current next))))
        ;; Don't forget the last current
        (push current result)
        (setf (evim-state-regions evim--state) (nreverse result))))
    (evim--update-region-indices)))

;;; Restrict to region

(defun evim--restrict-active-p ()
  "Return t if a restriction is active."
  (and evim--state
       (evim-state-restrict-beg evim--state)
       (evim-state-restrict-end evim--state)))

(defun evim--set-restrict (beg end)
  "Set restriction to region from BEG to END."
  (evim--clear-restrict)
  (setf (evim-state-restrict-beg evim--state) (evim--make-marker beg))
  (setf (evim-state-restrict-end evim--state) (evim--make-marker end))
  ;; Create visual overlay for restriction
  (let ((ov (make-overlay beg end nil nil t)))
    (overlay-put ov 'face 'evim-restrict-face)
    (overlay-put ov 'evim-restrict t)
    (overlay-put ov 'priority 10)
    (setf (evim-state-restrict-overlay evim--state) ov)))

(defun evim--clear-restrict ()
  "Clear current restriction."
  (when evim--state
    (when-let ((ov (evim-state-restrict-overlay evim--state)))
      (delete-overlay ov))
    (when-let ((beg (evim-state-restrict-beg evim--state)))
      (set-marker beg nil))
    (when-let ((end (evim-state-restrict-end evim--state)))
      (set-marker end nil))
    (setf (evim-state-restrict-beg evim--state) nil
          (evim-state-restrict-end evim--state) nil
          (evim-state-restrict-overlay evim--state) nil)))

(defun evim--restrict-bounds ()
  "Return (BEG . END) of current restriction, or nil if none."
  (when (evim--restrict-active-p)
    (cons (marker-position (evim-state-restrict-beg evim--state))
          (marker-position (evim-state-restrict-end evim--state)))))

(defun evim--point-in-restrict-p (pos)
  "Return t if POS is within the current restriction (or no restriction)."
  (if-let ((bounds (evim--restrict-bounds)))
      (and (>= pos (car bounds))
           (<= pos (cdr bounds)))
    t))

(provide 'evim-core)
;; Local Variables:
;; package-lint-main-file: "evim.el"
;; End:
;;; evim-core.el ends here
