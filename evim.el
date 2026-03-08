;;; evim.el --- Evil Visual Multi - Multiple cursors for evil-mode -*- lexical-binding: t; -*-

;; Copyright (C) 2025
;; SPDX-License-Identifier: MIT

;; Author: Vadim Pavlov <vadim198527@gmail.com>
;; Version: 0.1.0
;; Package-Requires: ((emacs "27.1") (evil "1.14.0"))
;; Keywords: convenience, emulations
;; URL: https://github.com/chestnykh/evil-visual-multi

;;; Commentary:

;; Evil Visual Multi (evim) provides multiple cursors functionality
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
;; - Esc: Exit evim

;;; Code:

(require 'evim-core)
(require 'evim-themes)

;;; Internal macros

(defmacro evim--with-undo-amalgamate (&rest body)
  "Execute BODY with undo amalgamation.
All changes in BODY become a single undo entry."
  (declare (indent 0) (debug t))
  `(let ((undo-handle (prepare-change-group)))
     (unwind-protect
         (progn ,@body)
       (undo-amalgamate-change-group undo-handle))))

(defmacro evim--without-post-command-hook (&rest body)
  "Execute BODY with `post-command-hook' temporarily disabled."
  (declare (indent 0) (debug t))
  `(progn
     (remove-hook 'post-command-hook #'evim--post-command t)
     (unwind-protect
         (progn ,@body)
       (add-hook 'post-command-hook #'evim--post-command nil t))))

(defmacro evim--with-batched-changes (&rest body)
  "Execute BODY while suppressing per-edit synchronization hooks."
  (declare (indent 0) (debug t))
  `(let ((inhibit-modification-hooks t))
     (evim--without-post-command-hook
       (progn ,@body))))

;;; Customization

(defcustom evim-leader-key "\\"
  "Leader key for evim prefix commands.
Used for commands like select-all, align, restrict, etc.
Change this if `\\' conflicts with other packages.
Call `evim-rebind-leader' after changing to update all keymaps."
  :type 'string
  :group 'evim)

(defcustom evim-show-mode-line t
  "When non-nil, show EVIM indicator in the mode-line."
  :type 'boolean
  :group 'evim)

;;; Keymaps

(defvar evim-mode-map
  (let ((km (make-sparse-keymap)))
    (define-key km (kbd "<escape>") #'evim-exit)
    (define-key km (kbd "<tab>") #'evim-toggle-mode)
    (define-key km (kbd "n") #'evim-find-next)
    (define-key km (kbd "N") #'evim-find-prev)
    (define-key km (kbd "]") #'evim-goto-next)
    (define-key km (kbd "[") #'evim-goto-prev)
    (define-key km (kbd "q") #'evim-skip-current)
    (define-key km (kbd "Q") #'evim-remove-current)
    ;; Movement
    (define-key km (kbd "h") #'evim-backward-char)
    (define-key km (kbd "j") #'evim-next-line)
    (define-key km (kbd "k") #'evim-previous-line)
    (define-key km (kbd "l") #'evim-forward-char)
    (define-key km (kbd "w") #'evim-forward-word)
    (define-key km (kbd "b") #'evim-backward-word)
    (define-key km (kbd "e") #'evim-forward-word-end)
    (define-key km (kbd "0") #'evim-beginning-of-line)
    (define-key km (kbd "^") #'evim-first-non-blank)
    (define-key km (kbd "$") #'evim-end-of-line)
    (define-key km (kbd "f") #'evim-find-char)
    (define-key km (kbd "t") #'evim-find-char-to)
    (define-key km (kbd "F") #'evim-find-char-backward)
    (define-key km (kbd "T") #'evim-find-char-to-backward)
    (define-key km (kbd "M") #'evim-toggle-multiline)
    km)
  "Keymap for evim mode (common bindings).")

(defvar evim-cursor-map
  (let ((km (make-sparse-keymap)))
    (define-key km (kbd "i") #'evim-insert)
    (define-key km (kbd "a") #'evim-append)
    (define-key km (kbd "I") #'evim-insert-line)
    (define-key km (kbd "A") #'evim-append-line)
    (define-key km (kbd "o") #'evim-open-below)
    (define-key km (kbd "O") #'evim-open-above)
    (define-key km (kbd "x") #'evim-delete-char)
    (define-key km (kbd "X") #'evim-delete-char-backward)
    (define-key km (kbd "r") #'evim-replace-char)
    (define-key km (kbd "~") #'evim-toggle-case-char)
    (define-key km (kbd "v") #'evim-enter-extend)
    (define-key km (kbd "J") #'evim-join-lines)
    ;; Operators with motions
    (define-key km (kbd "d") #'evim-operator-delete)
    (define-key km (kbd "c") #'evim-operator-change)
    (define-key km (kbd "y") #'evim-operator-yank)
    (define-key km (kbd "D") #'evim-delete-to-eol)
    (define-key km (kbd "C") #'evim-change-to-eol)
    (define-key km (kbd "Y") #'evim-yank-line)
    ;; Indent/outdent operators
    (define-key km (kbd ">") #'evim-operator-indent)
    (define-key km (kbd "<") #'evim-operator-outdent)
    ;; Case change operators (g prefix)
    (define-key km (kbd "g u") #'evim-operator-downcase)
    (define-key km (kbd "g U") #'evim-operator-upcase)
    (define-key km (kbd "g ~") #'evim-operator-toggle-case)
    ;; Cursor creation
    (define-key km (kbd "C-n") #'evim-add-next-match)
    (define-key km (kbd "<C-down>") #'evim-add-cursor-down)
    (define-key km (kbd "<C-up>") #'evim-add-cursor-up)
    (define-key km (kbd "<s-down-mouse-1>") #'evim--mouse-down-save-point)
    (define-key km (kbd "<s-mouse-1>") #'evim-add-cursor-at-click)
    ;; Undo (only in cursor mode, extend mode uses u for downcase)
    (define-key km (kbd "u") #'evim-undo)
    (define-key km (kbd "C-r") #'evim-redo)
    ;; Paste in cursor mode
    (define-key km (kbd "p") #'evim-paste-after)
    (define-key km (kbd "P") #'evim-paste-before)
    ;; Pass " to evil for register selection (e.g. "ay, "ap)
    (define-key km (kbd "\"") #'evil-use-register)
    km)
  "Keymap for cursor mode specific bindings.")

(defvar evim-extend-map
  (let ((km (make-sparse-keymap)))
    (define-key km (kbd "y") #'evim-yank)
    (define-key km (kbd "d") #'evim-delete)
    (define-key km (kbd "c") #'evim-change)
    (define-key km (kbd "s") #'evim-change)
    (define-key km (kbd "p") #'evim-paste-after)
    (define-key km (kbd "P") #'evim-paste-before)
    (define-key km (kbd "o") #'evim-flip-direction)
    (define-key km (kbd "U") #'evim-upcase)
    (define-key km (kbd "u") #'evim-downcase)
    (define-key km (kbd "~") #'evim-toggle-case)
    (define-key km (kbd "C-n") #'evim-add-next-match)
    (define-key km (kbd "<s-down-mouse-1>") #'evim--mouse-down-save-point)
    (define-key km (kbd "<s-mouse-1>") #'evim-add-cursor-at-click)
    ;; Pass " to evil for register selection (e.g. "ay, "ap)
    (define-key km (kbd "\"") #'evil-use-register)
    ;; Text objects in extend mode (iw, a", etc.)
    (define-key km (kbd "i") #'evim-extend-inner-text-object)
    (define-key km (kbd "a") #'evim-extend-a-text-object)
    ;; Surround (evil-surround integration)
    (define-key km (kbd "S") #'evim-surround)
    km)
  "Keymap for extend mode specific bindings.")

(defconst evim--mode-leader-suffixes
  '("A" "a" "g S" "r" "z" "@" ":")
  "Leader suffixes bound in `evim-mode-map'.")

(defconst evim--normal-leader-suffixes
  '("g S")
  "Leader suffixes bound in `evil-normal-state-map'.")

(defconst evim--visual-leader-suffixes
  '("r" "c")
  "Leader suffixes bound in `evil-visual-state-map'.")

(defvar evim--previous-leader-key evim-leader-key
  "Most recently bound EVIM leader key.")

;; Leader-prefixed commands (defined via evim--bind-leader)
(defun evim--bind-leader (keymap suffix command)
  "Bind COMMAND to leader + SUFFIX in KEYMAP.
If the leader key is currently bound as a non-prefix key in KEYMAP,
it is unbound first to allow prefix bindings."
  (let ((leader-key (kbd evim-leader-key)))
    ;; If leader is bound as a command (not a prefix), unbind it
    (when (and (commandp (lookup-key keymap leader-key))
               (not (keymapp (lookup-key keymap leader-key))))
      (define-key keymap leader-key nil))
    (define-key keymap (kbd (concat evim-leader-key " " suffix)) command)))

(defun evim--unbind-leader-bindings (keymap leader-key suffixes)
  "Remove LEADER-KEY bindings for SUFFIXES from KEYMAP."
  (dolist (suffix suffixes)
    (define-key keymap (kbd (concat leader-key " " suffix)) nil)))

(defun evim--setup-leader-bindings (&optional old-leader-key)
  "Set up all leader-prefixed bindings in evim keymaps.
OLD-LEADER-KEY, if non-nil, is the previous leader key to unbind."
  (when (and old-leader-key
             (not (string= old-leader-key evim-leader-key)))
    (evim--unbind-leader-bindings evim-mode-map old-leader-key
                                 evim--mode-leader-suffixes))
  ;; Prefix commands in evim-mode-map
  (evim--bind-leader evim-mode-map "A" #'evim-select-all)
  (evim--bind-leader evim-mode-map "a" #'evim-align)
  (evim--bind-leader evim-mode-map "g S" #'evim-reselect-last)
  (evim--bind-leader evim-mode-map "r" #'evim-toggle-restrict)
  (evim--bind-leader evim-mode-map "z" #'evim-run-normal)
  (evim--bind-leader evim-mode-map "@" #'evim-run-macro)
  (evim--bind-leader evim-mode-map ":" #'evim-run-ex))

(evim--setup-leader-bindings)

;; Set parent keymaps
(set-keymap-parent evim-cursor-map evim-mode-map)
(set-keymap-parent evim-extend-map evim-mode-map)

;;; Minor mode

(defvar evim--emulation-alist nil
  "Alist for `emulation-mode-map-alists' to override evil keymaps.")

(defvar evim--saved-cursor nil
  "Saved cursor type before entering evim.")

;;;###autoload
(define-minor-mode evim-mode
  "Minor mode for evil-visual-multi."
  :lighter nil
  :keymap nil
  :group 'evim
  (if evim-mode
      (progn
        ;; Save original cursor
        (setq evim--saved-cursor cursor-type)
        ;; Update keymap based on mode
        (evim--update-keymap)
        ;; Add mode-line indicator
        (add-to-list 'mode-line-misc-info '(:eval (evim--mode-line-indicator))))
    ;; Remove from emulation-mode-map-alists
    (setq evim--emulation-alist nil)
    ;; Remove mode-line indicator
    (setq mode-line-misc-info
          (cl-remove-if (lambda (x) (and (listp x) (eq (car x) :eval)
                                         (eq (caadr x) 'evim--mode-line-indicator)))
                        mode-line-misc-info))
    ;; Restore cursor
    (when evim--saved-cursor
      (setq cursor-type evim--saved-cursor))))

(defun evim--update-keymap ()
  "Update keymap based on current evim mode.
Uses `emulation-mode-map-alists' to override evil bindings."
  (when evim-mode
    ;; Use emulation-mode-map-alists to get priority over evil
    (setq evim--emulation-alist
          (list (cons 'evim-mode
                      (if (evim-cursor-mode-p)
                          evim-cursor-map
                        evim-extend-map))))
    ;; Always remove and re-add to ensure we're at the front
    (setq emulation-mode-map-alists
          (delq 'evim--emulation-alist emulation-mode-map-alists))
    (push 'evim--emulation-alist emulation-mode-map-alists)))

;;; Region sorting helpers

(defun evim--regions-by-position ()
  "Return regions sorted by buffer position (beginning to end)."
  (sort (copy-sequence (evim-state-regions evim--state))
        (lambda (a b)
          (< (evim--region-cursor-pos a)
             (evim--region-cursor-pos b)))))

(defun evim--regions-by-position-reverse ()
  "Return regions sorted by buffer position (end to beginning).
Use this for buffer modifications to avoid position shifts
affecting earlier regions."
  (sort (copy-sequence (evim-state-regions evim--state))
        (lambda (a b)
          (> (evim--region-cursor-pos a)
             (evim--region-cursor-pos b)))))

;;; Activation/Deactivation

(defun evim-activate ()
  "Activate evim mode in current buffer."
  (interactive)
  (unless evim--state
    (setq evim--state (make-evim-state)))
  ;; Preserve registers across sessions
  (let ((existing-registers (evim-state-registers evim--state)))
    (setf (evim-state-active-p evim--state) t
          (evim-state-mode evim--state) 'cursor
          (evim-state-regions evim--state) nil
          (evim-state-region-by-id evim--state) (make-hash-table :test 'eq)
          (evim-state-id-counter evim--state) 0
          (evim-state-leader-id evim--state) nil
          (evim-state-patterns evim--state) nil
          (evim-state-search-direction evim--state) 1
          (evim-state-multiline-p evim--state) nil
          (evim-state-whole-word-p evim--state) t
          (evim-state-case-fold-p evim--state) nil
          ;; Keep existing registers or create new hash table
          (evim-state-registers evim--state) (or existing-registers
                                               (make-hash-table :test 'eq))))
  (evim-mode 1)
  (evil-normal-state)
  ;; Add hooks
  (add-hook 'pre-command-hook #'evim--pre-command nil t)
  (add-hook 'post-command-hook #'evim--post-command nil t)
  (add-hook 'before-change-functions #'evim--before-change nil t)
  (add-hook 'after-change-functions #'evim--after-change nil t)
  (force-mode-line-update))

(defun evim-exit ()
  "Exit evim mode, removing all cursors."
  (interactive)
  (when (evim-active-p)
    ;; Save for reselect
    (evim--save-for-reselect)
    ;; Sync registers
    (evim--sync-to-evil-registers)
    ;; Remove overlays (thorough cleanup to catch any orphans)
    (evim--remove-all-overlays-thorough)
    (evim--hide-match-preview)
    ;; Clear restriction
    (evim--clear-restrict)
    ;; Remove hooks
    (remove-hook 'pre-command-hook #'evim--pre-command t)
    (remove-hook 'post-command-hook #'evim--post-command t)
    (remove-hook 'before-change-functions #'evim--before-change t)
    (remove-hook 'after-change-functions #'evim--after-change t)
    ;; Reset state
    (setf (evim-state-active-p evim--state) nil
          (evim-state-regions evim--state) nil)
    (evim-mode -1)
    (force-mode-line-update)))

;; evim--save-for-reselect moved to Phase 9 section

(defun evim--sync-to-evil-registers ()
  "Sync VM register to evil registers on exit."
  (when-let ((contents (gethash ?\" (evim-state-registers evim--state))))
    (evil-set-register ?\" (string-join contents "\n"))))

;;; Hooks

(defvar evim--in-change nil
  "Flag to track when we're in the middle of a change.")

;;; Insert mode tracking (real-time replication)

(defvar-local evim--insert-active nil
  "Non-nil when evim insert mode is active.")

(defvar-local evim--insert-replicating nil
  "Non-nil when we are replicating changes to other cursors.
Used to prevent infinite recursion.")

(defvar-local evim--insert-start-markers nil
  "Alist of (region-id . marker) recording where each cursor was when insert began.
Markers have nil insertion type so they stay at the insert-start position.")

(defvar-local evim--insert-orig-positions nil
  "Alist of (region-id . integer) for original cursor positions.
Unlike `evim--insert-start-markers' (which adjust when text is deleted
before them), these stay fixed and allow detecting backward deletions
\(backspace past the insert point).")

(defvar-local evim--insert-replicated-len 0
  "Length of text currently replicated at non-leader cursors.
Used by `evim--insert-sync-cursors' to know how much old text to replace.")

(defvar-local evim--insert-pre-start-deleted 0
  "Number of characters deleted before the original start position.
Tracks backward deletions (backspace) so they can be replicated.")

(defvar-local evim--insert-leader-end-marker nil
  "Marker at the end of the leader's modified region during insert mode.
Has insertion type t so it advances when text is inserted at/before it.
Used to capture auto-inserted text after point (e.g. closing delimiters
from `electric-pair-mode').")

(defun evim--start-insert-mode ()
  "Start tracking for evim insert mode with real-time replication."
  (when (and (evim-active-p) (not evim--insert-active))
    (setq evim--insert-active t
          evim--insert-replicating nil
          evim--insert-replicated-len 0
          evim--insert-pre-start-deleted 0)
    ;; Record start markers for all cursors (nil insertion type so they
    ;; stay at the position where insert began, even as text is inserted).
    (let ((regions (evim-state-regions evim--state)))
      (setq evim--insert-start-markers
            (mapcar (lambda (r)
                      (let ((m (copy-marker (evim-region-beg r))))
                        (set-marker-insertion-type m nil)
                        (cons (evim-region-id r) m)))
                    regions))
      ;; Also record original positions as fixed integers for detecting
      ;; backward deletions (backspace past the insert point).
      (setq evim--insert-orig-positions
            (mapcar (lambda (r)
                      (cons (evim-region-id r)
                            (marker-position (evim-region-beg r))))
                    regions)))
    ;; Track end of leader's modified region (t insertion type so it
    ;; advances with text inserted at/after the leader position).
    (let ((leader (evim--leader-region)))
      (setq evim--insert-leader-end-marker
            (copy-marker (evim-region-beg leader)))
      (set-marker-insertion-type evim--insert-leader-end-marker t))
    ;; Disable evim keymaps during insert mode (let evil handle input)
    (setq evim--emulation-alist nil)
    (when-let ((entry (assq 'evim-mode minor-mode-map-alist)))
      (setcdr entry nil))
    ;; Use post-command-hook for replication — this runs AFTER all hooks
    ;; (including electric-pair-mode's post-self-insert-hook) have finished,
    ;; so the leader's buffer state is final and we can safely replicate.
    (add-hook 'post-command-hook #'evim--insert-post-command nil t)
    (add-hook 'evil-insert-state-exit-hook #'evim--stop-insert-mode nil t)
    ;; Update overlays to ensure they're positioned correctly for insert mode
    (evim--update-all-overlays)))

(defun evim--insert-sync-cursors ()
  "Sync non-leader cursors with leader's insert text.
Computes the leader's full modified text — including auto-inserted text
after point (electric-pair-mode) and backward deletions (backspace) —
then replaces the corresponding region at each non-leader cursor."
  (let* ((leader (evim--leader-region))
         (leader-start-entry (assq (evim-region-id leader)
                                   evim--insert-start-markers))
         (leader-start (when leader-start-entry
                         (marker-position (cdr leader-start-entry))))
         (leader-orig-entry (assq (evim-region-id leader)
                                  evim--insert-orig-positions))
         (leader-orig (when leader-orig-entry (cdr leader-orig-entry))))
    (when (and leader-start leader-orig)
      ;; How many chars were deleted before the original start position
      ;; (e.g. backspace).  The start marker (nil insertion type) shifts
      ;; backward when text before it is deleted.
      (let* ((pre-del (max 0 (- leader-orig leader-start)))
             ;; End of leader's modified region (captures auto-pairs)
             (leader-end (if evim--insert-leader-end-marker
                             (max (point)
                                  (marker-position evim--insert-leader-end-marker))
                           (point)))
             ;; Full text from (possibly shifted) start to end
             (leader-text (buffer-substring-no-properties
                           leader-start leader-end))
             ;; Point offset within the leader text
             (leader-point-off (- (point) leader-start))
             (evim--insert-replicating t)
             (inhibit-modification-hooks t)
             (other-regions (cl-remove-if #'evim--leader-p
                                          (evim-state-regions evim--state)))
             ;; Sort bottom-to-top so buffer modifications don't shift
             ;; positions of regions we haven't processed yet.
             (sorted (cl-sort (copy-sequence other-regions) #'>
                              :key (lambda (r)
                                     (let ((e (assq (evim-region-id r)
                                                    evim--insert-start-markers)))
                                       (if e (marker-position (cdr e)) 0))))))
        (dolist (region sorted)
          (let* ((start-entry (assq (evim-region-id region)
                                    evim--insert-start-markers))
                 (start-pos (when start-entry
                              (marker-position (cdr start-entry)))))
            (when start-pos
              (save-excursion
                ;; Compute the region to replace:
                ;; from (start - pre-del - previous-pre-del) to (start + prev-replicated)
                ;; But start marker already adjusted for previous pre-del,
                ;; so: from (start - new-backward-delta) to (start + prev-replicated)
                (let* ((del-start (max (point-min)
                                       (- start-pos
                                          (max 0 (- pre-del evim--insert-pre-start-deleted)))))
                       (del-end (min (point-max)
                                    (+ start-pos evim--insert-replicated-len))))
                  (delete-region del-start del-end)
                  ;; Insert leader text
                  (goto-char del-start)
                  (insert leader-text)
                  ;; Update cursor markers
                  (let ((new-pos (+ del-start leader-point-off)))
                    (set-marker (evim-region-beg region) new-pos)
                    (set-marker (evim-region-end region) new-pos)
                    (set-marker (evim-region-anchor region) new-pos)))))))
        ;; Update tracking state
        (setq evim--insert-replicated-len (length leader-text)
              evim--insert-pre-start-deleted 0)
        ;; Reset orig positions to current marker positions so that
        ;; the next sync only sees NEW changes (the shifts from this
        ;; sync's buffer modifications are absorbed).
        (setq evim--insert-orig-positions
              (mapcar (lambda (entry)
                        (let ((m (assq (car entry) evim--insert-start-markers)))
                          (cons (car entry)
                                (if m (marker-position (cdr m)) (cdr entry)))))
                      evim--insert-orig-positions))
        ;; Update leader markers
        (set-marker (evim-region-beg leader) (point))
        (set-marker (evim-region-end leader) (point))
        (set-marker (evim-region-anchor leader) (point))
        ;; Update overlays
        (evim--update-all-overlays)))))

(defun evim--insert-post-command ()
  "Replicate leader's insert text to all other cursors after each command.
Runs in `post-command-hook', after all other hooks (including
`electric-pair-mode') have finished modifying the buffer."
  (when (and evim--insert-active
             (not evim--insert-replicating)
             (evim-active-p)
             evim--insert-start-markers)
    (evim--insert-sync-cursors)))

(defun evim--stop-insert-mode ()
  "Handle exit from evim insert mode."
  (when (and evim--insert-active (evim-active-p))
    ;; Final sync — ensures replication even when text was inserted
    ;; outside the command loop (e.g. `(insert ...)' in tests).
    (evim--insert-sync-cursors)
    ;; Remove hooks
    (remove-hook 'post-command-hook #'evim--insert-post-command t)
    (remove-hook 'evil-insert-state-exit-hook #'evim--stop-insert-mode t)
    ;; Clean up markers
    (dolist (entry evim--insert-start-markers)
      (set-marker (cdr entry) nil))
    (when evim--insert-leader-end-marker
      (set-marker evim--insert-leader-end-marker nil))
    (setq evim--insert-active nil
          evim--insert-replicating nil
          evim--insert-start-markers nil
          evim--insert-orig-positions nil
          evim--insert-replicated-len 0
          evim--insert-pre-start-deleted 0
          evim--insert-leader-end-marker nil)
    ;; Add one-shot hook to sync after evil adjusts point in normal state
    (add-hook 'evil-normal-state-entry-hook #'evim--sync-after-insert-exit nil t)
    ;; Restore evim keymaps
    (when-let ((entry (assq 'evim-mode minor-mode-map-alist)))
      (setcdr entry evim-mode-map))
    (evim--update-keymap)))

(defun evim--sync-after-insert-exit ()
  "Sync cursors after exiting insert mode.
Evil moves point back by 1 when exiting insert (unless at bol).
We adjust all markers the same way."
  (remove-hook 'evil-normal-state-entry-hook #'evim--sync-after-insert-exit t)
  (when (evim-active-p)
    ;; Adjust all cursors like evil adjusts point on insert exit
    (dolist (region (evim-state-regions evim--state))
      (let ((pos (evim--region-cursor-pos region)))
        (evim--region-set-cursor-pos region (evim--adjust-cursor-pos pos))))
    (evim--update-all-overlays)))

(defun evim--before-change (_beg _end)
  "Called before buffer modification."
  (when (and (evim-active-p) (not evim--in-change))
    (setq evim--in-change t)))

(defun evim--after-change (_beg _end _len)
  "Called after buffer modification."
  (when (and (evim-active-p) evim--in-change)
    (setq evim--in-change nil)
    ;; Clamp markers to buffer bounds
    (evim--clamp-markers)
    (evim--check-and-merge-overlapping)
    (evim--update-all-overlays)))

(defun evim--clamp-markers ()
  "Clamp all region markers to buffer bounds."
  (let ((max-pos (point-max)))
    (dolist (region (evim-state-regions evim--state))
      (let ((beg (marker-position (evim-region-beg region)))
            (end (marker-position (evim-region-end region)))
            (anchor (marker-position (evim-region-anchor region))))
        (when (> beg max-pos)
          (set-marker (evim-region-beg region) max-pos))
        (when (> end max-pos)
          (set-marker (evim-region-end region) max-pos))
        (when (> anchor max-pos)
          (set-marker (evim-region-anchor region) max-pos))))))

(defun evim--pre-command ()
  "Called before each command."
  ;; Currently empty but kept for potential future use
  nil)

(defvar-local evim--last-buffer-tick nil
  "Last buffer modification tick, used to detect changes.")

(defun evim--post-command ()
  "Called after each command."
  (when (evim-active-p)
    (let ((is-undo-command (memq this-command
                                  '(undo evil-undo undo-tree-undo undo-fu-only-undo
                                    evim-undo evim-redo))))
      ;; After undo command, resync regions with pattern
      (when (and is-undo-command
                 (car (evim-state-patterns evim--state)))
        (evim--resync-regions-to-pattern))
      ;; Ensure overlays are in sync with markers after buffer modifications
      ;; (fixes visual glitches after undo where overlays drift from markers)
      (let ((current-tick (buffer-modified-tick)))
        (unless (eql current-tick evim--last-buffer-tick)
          (setq evim--last-buffer-tick current-tick)
          (evim--update-all-overlays)))
      ;; Keep real cursor at leader visual position
      (when-let ((leader (evim--leader-region)))
        (let ((leader-pos (evim--region-visual-cursor-pos leader)))
          (unless (= (point) leader-pos)
            (goto-char leader-pos)))))))

(defun evim--goto-leader ()
  "Move point to the leader's visual cursor position."
  (when-let ((leader (evim--leader-region)))
    (goto-char (evim--region-visual-cursor-pos leader))))

(defun evim--finalize-batch-edit (&optional update-keymap)
  "Finalize a batched buffer edit and resynchronize UI state.
When UPDATE-KEYMAP is non-nil, refresh the active EVIM keymap too."
  (evim--clamp-markers)
  (evim--check-and-merge-overlapping)
  (evim--update-all-overlays)
  (setq evim--last-buffer-tick (buffer-modified-tick))
  (when update-keymap
    (evim--update-keymap))
  (evim--goto-leader))

(defun evim--search-valid-match (pattern start-pos direction)
  "Return the next allowed PATTERN match from START-POS in DIRECTION.
DIRECTION is 1 for forward and -1 for backward.  Returns (BEG . END)
or nil if no allowed match exists."
  (let* ((bounds (evim--restrict-bounds))
         (forward-p (= direction 1))
         (min-pos (if bounds (car bounds) (point-min)))
         (max-pos (if bounds (cdr bounds) (point-max)))
         (search-fn (if forward-p #'re-search-forward #'re-search-backward))
         (search-limit (if forward-p max-pos min-pos))
         (first-start (if forward-p
                          (min start-pos max-pos)
                        (max start-pos min-pos)))
         (wrap-start (if forward-p min-pos max-pos)))
    (cl-labels ((scan-from (pos)
                  (save-excursion
                    (goto-char pos)
                    (catch 'match
                      (while (funcall search-fn pattern search-limit t)
                        (let ((beg (match-beginning 0))
                              (end (match-end 0)))
                          (when (evim--match-allowed-p beg end)
                            (throw 'match (cons beg end)))))))))
      (or (scan-from first-start)
          (unless (= first-start wrap-start)
            (scan-from wrap-start))))))

(defun evim--adjust-cursor-pos (pos)
  "Adjust POS like `evil-adjust-cursor' does.
In normal state, cursor can't be past the last character of a non-empty line."
  (save-excursion
    (goto-char pos)
    (if (and (= pos (line-end-position))
             (not (= (line-beginning-position) (line-end-position)))) ; non-empty line
        (1- pos)
      pos)))

(defun evim--region-match-distance (region match)
  "Return distance from REGION to MATCH, or nil if MATCH is too far away."
  (let* ((region-beg (marker-position (evim-region-beg region)))
         (region-end (marker-position (evim-region-end region)))
         (match-beg (car match))
         (match-end (cdr match))
         (match-len (- match-end match-beg))
         (gap (cond
               ((< region-end match-beg) (- match-beg region-end))
               ((< match-end region-beg) (- region-beg match-end))
               (t 0))))
    (when (<= gap match-len)
      gap)))

(defun evim--resync-regions-to-pattern ()
  "Resync region positions to match pattern occurrences in buffer.
Called after undo to fix marker drift.  Only moves a region if
there's a match very close to its current position (within the
length of the match pattern).  This prevents jumping to distant
matches when text hasn't been fully restored by undo."
  (let* ((pattern (car (evim-state-patterns evim--state)))
         (bounds (evim--restrict-bounds))
         (matches '())
         (used-matches (make-hash-table :test 'equal))
         (cursor-mode-p (evim-cursor-mode-p)))
    ;; Find all matches
    (save-excursion
      (goto-char (if bounds (car bounds) (point-min)))
      (while (re-search-forward pattern (when bounds (cdr bounds)) t)
        (let ((beg (match-beginning 0))
              (end (match-end 0)))
          (when (evim--match-allowed-p beg end)
            (push (cons beg end) matches)))))
    (setq matches (nreverse matches))
    (when matches
      ;; For each region, pick the closest unused nearby match.
      (dolist (region (evim--regions-by-position))
        (let (best-match best-distance)
          (dolist (match matches)
            (unless (gethash match used-matches)
              (when-let ((distance (evim--region-match-distance region match)))
                (when (or (null best-distance)
                          (< distance best-distance))
                  (setq best-distance distance
                        best-match match)))))
          (when best-match
            (let ((beg (car best-match))
                  (end (if cursor-mode-p (car best-match) (cdr best-match)))
                  (anchor (car best-match)))
              (set-marker (evim-region-beg region) beg)
              (set-marker (evim-region-end region) end)
              (set-marker (evim-region-anchor region) anchor)
              (setf (evim-region-dir region) 1
                    (evim-region-txt region)
                    (if cursor-mode-p
                        ""
                      (buffer-substring-no-properties beg end)))
              (puthash best-match t used-matches)))))
      (evim--sort-regions)
      (evim--check-and-merge-overlapping)
      (evim--update-all-overlays))))

;;; Movement commands

(defun evim-forward-char ()
  "Move all cursors forward one character."
  (interactive)
  (evim--move-cursors #'evim--move-char 1))

(defun evim-backward-char ()
  "Move all cursors backward one character."
  (interactive)
  (evim--move-cursors #'evim--move-char -1))

(defun evim-next-line ()
  "Move all cursors to next line, preserving column."
  (interactive)
  (evim--move-cursors-vertically 1))

(defun evim-previous-line ()
  "Move all cursors to previous line, preserving column."
  (interactive)
  (evim--move-cursors-vertically -1))

(defun evim-forward-word ()
  "Move all cursors forward one word."
  (interactive)
  (evim--move-cursors #'evim--move-word 1))

(defun evim-backward-word ()
  "Move all cursors backward one word."
  (interactive)
  (evim--move-cursors #'evim--move-word-back 1))

(defun evim-forward-word-end ()
  "Move all cursors to end of word."
  (interactive)
  (evim--move-cursors #'evim--move-word-end 1))

(defun evim-beginning-of-line ()
  "Move all cursors to beginning of line."
  (interactive)
  (evim--move-cursors #'evim--move-line-beg))

(defun evim-end-of-line ()
  "Move all cursors to end of line."
  (interactive)
  (evim--move-cursors #'evim--move-line-end))

(defun evim-first-non-blank ()
  "Move all cursors to first non-blank character."
  (interactive)
  (evim--move-cursors #'evim--move-first-non-blank))

(defun evim-find-char ()
  "Move all cursors to next occurrence of a character (like f)."
  (interactive)
  (let ((char (read-char "f ")))
    (evim--move-cursors #'evim--move-find-char char 1)))

(defun evim-find-char-to ()
  "Move all cursors to before next occurrence of a character (like t)."
  (interactive)
  (let ((char (read-char "t ")))
    (evim--move-cursors #'evim--move-find-char-to char 1)))

(defun evim-find-char-backward ()
  "Move all cursors to previous occurrence of a character (like F)."
  (interactive)
  (let ((char (read-char "F ")))
    (evim--move-cursors #'evim--move-find-char-backward char 1)))

(defun evim-find-char-to-backward ()
  "Move all cursors to after previous occurrence of a character (like T)."
  (interactive)
  (let ((char (read-char "T ")))
    (evim--move-cursors #'evim--move-find-char-to-backward char 1)))

;;; Cursor navigation

(defun evim-goto-next ()
  "Move leader to next cursor."
  (interactive)
  (when (evim-active-p)
    (let* ((regions (evim-state-regions evim--state))
           (leader-idx (evim--leader-index))
           (next-idx (mod (1+ leader-idx) (length regions)))
           (next-region (nth next-idx regions)))
      (evim--set-leader next-region)
      (goto-char (evim--region-cursor-pos next-region)))))

(defun evim-goto-prev ()
  "Move leader to previous cursor."
  (interactive)
  (when (evim-active-p)
    (let* ((regions (evim-state-regions evim--state))
           (leader-idx (evim--leader-index))
           (prev-idx (mod (1- leader-idx) (length regions)))
           (prev-region (nth prev-idx regions)))
      (evim--set-leader prev-region)
      (goto-char (evim--region-cursor-pos prev-region)))))

(defun evim-skip-current ()
  "Skip current match: delete it and find next occurrence in search direction."
  (interactive)
  (when (evim-active-p)
    (let* ((leader (evim--leader-region))
           (pattern (car (evim-state-patterns evim--state)))
           (direction (evim-state-search-direction evim--state))
           ;; Save position BEFORE deleting, so we search from correct place
           (search-from (if (= direction 1)
                            (1+ (marker-position (evim-region-end leader)))
                          (1- (marker-position (evim-region-beg leader))))))
      ;; Delete current cursor
      (evim--delete-region leader)
      ;; Find next occurrence starting from saved position in search direction
      (when pattern
        (evim--find-and-add-from pattern search-from direction))
      ;; If no cursors left and no new found, exit
      (when (= (evim-region-count) 0)
        (evim-exit)))))

(defun evim-remove-current ()
  "Remove current cursor and select the previous one.
If on the first cursor, select the new first cursor (was second)."
  (interactive)
  (when (evim-active-p)
    (let ((leader (evim--leader-region))
          (old-idx (evim--leader-index)))
      (if (= (evim-region-count) 1)
          (evim-exit)
        ;; Delete first, then select by index
        (evim--delete-region leader)
        ;; Select previous, or 0 if we were first
        (let* ((new-idx (max 0 (1- old-idx)))
               (regions (evim-state-regions evim--state))
               (new-region (nth new-idx regions)))
          (evim--set-leader new-region)
          (goto-char (evim--region-cursor-pos new-region)))))))

;;; Cursor creation

;;;###autoload
(defun evim-find-word ()
  "Start evim with word under cursor or visual selection.
In visual mode: uses selected text as search pattern (can be part of word).
In normal mode: uses word under cursor.
Like vim-visual-multi, immediately enters extend mode with the text highlighted."
  (interactive)
  (let (text beg end use-word-bounds selection-multiline-p)
    ;; Get text to search for
    (if (evil-visual-state-p)
        ;; Visual mode: use selected text (any text, not just whole words)
        ;; Use evil-visual-range which returns correct bounds before pre-command hooks
        ;; modify point. For inclusive selection, end is position of last char.
        (let* ((range (evil-visual-range))
               (range-beg (nth 0 range))
               (range-end (nth 1 range))
               (range-type (nth 2 range))
               (expanded (plist-get (nthcdr 3 range) :expanded)))
          (setq beg range-beg)
          ;; For inclusive selection, add 1 to include last char
          ;; BUT if range is already :expanded, it already accounts for inclusive
          (setq end (if (and (eq range-type 'inclusive) (not expanded))
                        (1+ range-end)
                      range-end))
          (setq text (buffer-substring-no-properties beg end))
          (setq selection-multiline-p (evim--match-spans-lines-p beg end))
          (evil-exit-visual-state))
      ;; Normal mode: use word at point
      (let ((bounds (bounds-of-thing-at-point 'symbol)))
        (unless bounds
          (user-error "No word at point"))
        (setq beg (car bounds)
              end (cdr bounds)
              text (buffer-substring-no-properties beg end)
              use-word-bounds t)))
    (unless (and text (not (string-empty-p text)))
      (user-error "No text to search"))
    (unless (evim-active-p)
      (evim-activate))
    ;; Apply pending restriction if any
    (when evim--pending-restrict
      (evim--set-restrict (car evim--pending-restrict) (cdr evim--pending-restrict))
      (setq evim--pending-restrict nil))
    (when selection-multiline-p
      (setf (evim-state-multiline-p evim--state) t))
    ;; Create pattern: whole word for normal mode, literal for visual selection
    (let ((pattern (if use-word-bounds
                       (concat "\\_<" (regexp-quote text) "\\_>")
                     (regexp-quote text))))
      ;; Add pattern
      (push pattern (evim-state-patterns evim--state))
      ;; Create first region with selection
      (evim--create-region beg end pattern)
      ;; Switch to extend mode immediately
      (setf (evim-state-mode evim--state) 'extend)
      ;; Update overlays and keymap for extend mode
      (evim--update-all-overlays)
      (evim--update-keymap)
      ;; Position cursor at end of selection
      (goto-char (1- end))
      ;; Show matches (respecting restriction)
      (evim--show-match-preview-restricted pattern))))

(defun evim-add-next-match ()
  "Add next match for current pattern."
  (interactive)
  (when (evim-active-p)
    (let ((pattern (car (evim-state-patterns evim--state))))
      (unless pattern
        (user-error "No search pattern"))
      (evim--find-and-add-next pattern))))

(defun evim--find-and-add-next (pattern)
  "Find next match for PATTERN and move/add cursor there."
  (let* ((leader (evim--leader-region))
         (start-pos (if leader
                        (1+ (if (evim-cursor-mode-p)
                                (evim--region-cursor-pos leader)
                              (marker-position (evim-region-end leader))))
                      (1+ (point)))))
    (evim--find-and-add-from pattern start-pos 1)))

(defun evim--find-and-add-from (pattern start-pos direction)
  "Find match for PATTERN starting from START-POS in DIRECTION.
DIRECTION is 1 for forward, -1 for backward.
Creates a point cursor in cursor mode and a full selection in extend
mode.  Respects current restriction if active."
  (when-let ((match (evim--search-valid-match pattern start-pos direction)))
    (let ((found-beg (car match))
          (found-end (cdr match)))
      (let* ((cursor-mode-p (evim-cursor-mode-p))
             (existing (cl-find-if
                        (lambda (r)
                          (= (if cursor-mode-p
                                 (evim--region-cursor-pos r)
                               (marker-position (evim-region-beg r)))
                             found-beg))
                        (evim-state-regions evim--state))))
        (if existing
            ;; Just move leader to existing cursor
            (progn
              (evim--set-leader existing)
              (goto-char (if cursor-mode-p
                             (evim--region-cursor-pos existing)
                           (1- (marker-position (evim-region-end existing))))))
          ;; Create a point cursor or a full selection depending on mode.
          (let ((new-region (evim--create-region
                             found-beg
                             (if cursor-mode-p found-beg found-end)
                             pattern)))
            (evim--set-leader new-region)
            (evim--update-all-overlays)
            (goto-char (if cursor-mode-p found-beg (1- found-end)))))))))

(defun evim-find-next ()
  "Find next occurrence, move leader there."
  (interactive)
  (when (evim-active-p)
    (let ((pattern (car (evim-state-patterns evim--state))))
      (when pattern
        (setf (evim-state-search-direction evim--state) 1)
        (evim--find-and-add-next pattern)))))

(defun evim-find-prev ()
  "Find previous occurrence, move leader there."
  (interactive)
  (when (evim-active-p)
    (let ((pattern (car (evim-state-patterns evim--state))))
      (when pattern
        (setf (evim-state-search-direction evim--state) -1)
        (evim--find-and-add-prev pattern)))))

(defun evim--find-and-add-prev (pattern)
  "Find previous match for PATTERN and move/add cursor there."
  (let* ((leader (evim--leader-region))
         (start-pos (if leader
                        (1- (marker-position (evim-region-beg leader)))
                      (1- (point)))))
    (evim--find-and-add-from pattern start-pos -1)))

(defvar-local evim--vertical-target-col nil
  "Target column for vertical cursor creation.
Remembered across consecutive C-Down/C-Up presses so that
short lines don't degrade the column.")

(defun evim--add-cursor-vertically (direction)
  "Add cursor on line in DIRECTION (1 for down, -1 for up)."
  (unless (evim-active-p)
    (evim-activate)
    (evim--create-region (point) (point)))
  ;; Remember target column on first press, reuse on consecutive presses
  (unless (memq last-command '(evim-add-cursor-down evim-add-cursor-up))
    (setq evim--vertical-target-col (current-column)))
  (let* ((leader (evim--leader-region))
         (col evim--vertical-target-col)
         new-pos)
    (save-excursion
      (forward-line direction)
      (move-to-column col)
      (setq new-pos (point)))
    (when (and new-pos (not (= new-pos (evim--region-cursor-pos leader))))
      ;; Check if a cursor already exists at this position
      (let ((existing (cl-find new-pos (evim-state-regions evim--state)
                               :key #'evim--region-cursor-pos)))
        (if existing
            ;; Move leader to existing cursor instead of creating duplicate
            (progn
              (evim--set-leader existing)
              (goto-char new-pos))
          (let ((new-region (evim--create-region new-pos new-pos)))
            (evim--set-leader new-region)
            (goto-char new-pos)))))))

(defun evim-add-cursor-down ()
  "Add cursor on line below."
  (interactive)
  (evim--add-cursor-vertically 1))

(defun evim-add-cursor-up ()
  "Add cursor on line above."
  (interactive)
  (evim--add-cursor-vertically -1))

(defvar evim--pre-click-point nil
  "Point position saved before mouse-down, used by click handler.")

(defvar evim--last-point nil
  "Last known point after each command, tracked via `post-command-hook'.
Used by `evim--mouse-down-save-point' to get the true cursor position
because Emacs mouse event dispatch can shift point before our handler runs.")

(defun evim--track-point ()
  "Save current point for use by mouse click handlers."
  (setq evim--last-point (point)))

(defun evim--mouse-down-save-point (_event)
  "Save the true cursor position before mouse event processing.
Emacs mouse event dispatch can move point before our handler runs,
so we use `evim--last-point' (saved in `post-command-hook') which
reflects the real cursor position before the click."
  (interactive "e")
  (setq evim--pre-click-point (or evim--last-point (point))))

;;;###autoload
(defun evim-add-cursor-at-click (event)
  "Add a cursor at mouse click position, or remove if clicking on existing cursor.
EVENT is the mouse event.
- Click on empty position: create new cursor
- Click on existing cursor (any): remove it"
  (interactive "e")
  (let ((pos (posn-point (event-start event))))
    (when pos
      (unless (evim-active-p)
        (evim-activate)
        ;; Create first cursor at the pre-click position (saved by
        ;; evim--mouse-down-save-point) rather than (point), because
        ;; Emacs mouse event processing may have moved point.
        (let ((orig (or evim--pre-click-point (point))))
          (evim--create-region orig orig)))
      (setq evim--pre-click-point nil)
      ;; Check if cursor already exists at this position
      (let ((existing (cl-find-if
                       (lambda (r)
                         (= (evim--region-cursor-pos r) pos))
                       (evim-state-regions evim--state))))
        (if existing
            ;; Cursor exists - remove it (toggle behavior)
            (if (= (evim-region-count) 1)
                ;; Last cursor - exit evim
                (evim-exit)
              ;; Remove cursor and select another if needed
              (let ((was-leader (eq existing (evim--leader-region))))
                (evim--delete-region existing)
                (when was-leader
                  ;; Select first remaining cursor as new leader
                  (let ((new-leader (car (evim-state-regions evim--state))))
                    (when new-leader
                      (evim--set-leader new-leader)
                      (goto-char (evim--region-cursor-pos new-leader)))))))
          ;; Create new cursor at click position
          (let ((new-region (evim--create-region pos pos)))
            (evim--set-leader new-region)
            (goto-char pos)))))))

(defun evim-select-all ()
  "Select all occurrences of current pattern.
In cursor mode: creates point cursors at beginning of each match.
In extend mode: creates full selections covering each match.
Respects current restriction if active."
  (interactive)
  (when (evim-active-p)
    (let ((pattern (car (evim-state-patterns evim--state)))
          (bounds (evim--restrict-bounds))
          (cursor-mode-p (evim-cursor-mode-p))
          (new-positions '())
          (existing-positions (make-hash-table :test 'eq)))
      (unless pattern
        (user-error "No search pattern"))
      ;; Build hash of existing positions for O(1) lookup
      (dolist (r (evim-state-regions evim--state))
        (puthash (if cursor-mode-p
                     (evim--region-cursor-pos r)
                   (marker-position (evim-region-beg r)))
                 t existing-positions))
      ;; Collect all new positions
      (save-excursion
        (goto-char (if bounds (car bounds) (point-min)))
        (while (re-search-forward pattern (when bounds (cdr bounds)) t)
          (let* ((beg (match-beginning 0))
                 (end (match-end 0))
                 (check-pos beg))
            (when (and (evim--match-allowed-p beg end)
                       (not (gethash check-pos existing-positions)))
              ;; In cursor mode: point cursor at beginning
              ;; In extend mode: full selection
              (push (if cursor-mode-p (cons beg beg) (cons beg end))
                    new-positions)
              ;; Mark as existing to avoid duplicates from overlapping matches
              (puthash check-pos t existing-positions)))))
      ;; Create all regions in batch
      (when new-positions
        (evim--create-regions-batch (nreverse new-positions) pattern))
      (evim--update-all-overlays))))

;;; Mode switching commands

(defun evim-enter-extend ()
  "Enter extend mode from cursor mode."
  (interactive)
  (when (evim-cursor-mode-p)
    (evim--enter-extend-mode)
    (evim--update-keymap)))

;;; Extend mode text objects

(defun evim--get-text-object-bounds (inner-p obj-char)
  "Get bounds of text object OBJ-CHAR at point.
INNER-P selects inner vs outer variant.  Returns (BEG END) or nil."
  (let ((bounds (pcase obj-char
                  (?w (if inner-p (evil-inner-word) (evil-a-word)))
                  (?W (if inner-p (evil-inner-WORD) (evil-a-WORD)))
                  (?s (if inner-p (evil-inner-sentence) (evil-a-sentence)))
                  (?p (if inner-p (evil-inner-paragraph) (evil-a-paragraph)))
                  ((or ?\( ?\) ?b) (if inner-p (evil-inner-paren) (evil-a-paren)))
                  ((or ?\[ ?\]) (if inner-p (evil-inner-bracket) (evil-a-bracket)))
                  ((or ?{ ?} ?B) (if inner-p (evil-inner-curly) (evil-a-curly)))
                  ((or ?< ?>) (if inner-p (evil-inner-angle) (evil-an-angle)))
                  (?\" (if inner-p (evil-inner-double-quote) (evil-a-double-quote)))
                  (?\' (if inner-p (evil-inner-single-quote) (evil-a-single-quote)))
                  (?\` (if inner-p (evil-inner-back-quote) (evil-a-back-quote)))
                  (?t (if inner-p (evil-inner-tag) (evil-a-tag)))
                  (?o (if inner-p (evil-inner-symbol) (evil-a-symbol)))
                  (_ nil))))
    (when bounds
      (list (nth 0 bounds) (nth 1 bounds)))))

(defun evim--extend-text-object (inner-p)
  "Apply text object to all regions in extend mode.
INNER-P selects inner variant when non-nil."
  (when (evim-extend-mode-p)
    (let ((obj-char (read-char (if inner-p "Inner: " "A: "))))
      (when (= obj-char 27) ; ESC
        (cl-return-from evim--extend-text-object nil))
      (dolist (region (evim-state-regions evim--state))
        (save-excursion
          (goto-char (evim--region-cursor-pos region))
          (let ((bounds (evim--get-text-object-bounds inner-p obj-char)))
            (when bounds
              (let ((beg (car bounds))
                    (end (cadr bounds)))
                (set-marker (evim-region-beg region) beg)
                (set-marker (evim-region-end region) end)
                (set-marker (evim-region-anchor region) beg)
                (setf (evim-region-dir region) 1))))))
      (when-let ((leader (evim--leader-region)))
        (goto-char (evim--region-visual-cursor-pos leader)))
      (evim--update-all-overlays))))

(defun evim-extend-inner-text-object ()
  "Select inner text object at all cursors in extend mode."
  (interactive)
  (evim--extend-text-object t))

(defun evim-extend-a-text-object ()
  "Select outer (a) text object at all cursors in extend mode."
  (interactive)
  (evim--extend-text-object nil))

;;; Cursor mode editing commands

(defun evim-insert ()
  "Enter insert mode at all cursor positions."
  (interactive)
  (when (evim-cursor-mode-p)
    (evim--start-insert-mode)
    (evil-insert-state)))

(defun evim-append ()
  "Enter insert mode after all cursor positions."
  (interactive)
  (when (evim-cursor-mode-p)
    (evim--move-cursors #'forward-char 1)
    (evim--start-insert-mode)
    (evil-insert-state)))

(defun evim-insert-line ()
  "Enter insert mode at beginning of lines."
  (interactive)
  (when (evim-cursor-mode-p)
    (evim--move-cursors #'back-to-indentation)
    (evim--start-insert-mode)
    (evil-insert-state)))

(defun evim-append-line ()
  "Enter insert mode at end of lines."
  (interactive)
  (when (evim-cursor-mode-p)
    (evim--move-cursors #'end-of-line)
    (evim--start-insert-mode)
    (evil-insert-state)))

(defun evim-open-below ()
  "Open line below and enter insert mode."
  (interactive)
  (when (evim-cursor-mode-p)
    (evim--with-undo-amalgamate
      (evim--execute-at-all-cursors
       (lambda ()
         (end-of-line)
         (newline-and-indent))
       t))
    (evim--start-insert-mode)
    (evil-insert-state)))

(defun evim-open-above ()
  "Open line above and enter insert mode."
  (interactive)
  (when (evim-cursor-mode-p)
    (evim--with-undo-amalgamate
      (evim--execute-at-all-cursors
       (lambda ()
         (beginning-of-line)
         (newline)
         (forward-line -1)
         (indent-according-to-mode))
       t))
    (evim--start-insert-mode)
    (evil-insert-state)))

(defun evim-delete-char (&optional count)
  "Delete COUNT characters at all cursors."
  (interactive "p")
  (setq count (or count 1))
  (when (evim-cursor-mode-p)
    (evim--with-undo-amalgamate
      (evim--execute-at-all-cursors
       (lambda ()
         (dotimes (_ count)
           (unless (or (eobp) (eolp))
             (delete-char 1)))
         (goto-char (evim--adjust-cursor-pos (point))))
       t))))

(defun evim-delete-char-backward ()
  "Delete character before all cursors."
  (interactive)
  (when (evim-cursor-mode-p)
    (evim--with-undo-amalgamate
      (evim--execute-at-all-cursors
       (lambda ()
         (unless (bobp)
           (delete-char -1)))))))

(defun evim-replace-char (char)
  "Replace character at all cursors with CHAR."
  (interactive "cReplace with: ")
  (when (evim-cursor-mode-p)
    (evim--with-undo-amalgamate
      (evim--execute-at-all-cursors
       (lambda ()
         (unless (eobp)
           (delete-char 1)
           (insert char)
           (backward-char 1)))
       t))))

(defun evim-toggle-case-char ()
  "Toggle case of character at all cursors."
  (interactive)
  (when (evim-cursor-mode-p)
    (evim--with-undo-amalgamate
      (evim--execute-at-all-cursors
       (lambda ()
         (unless (eobp)
           (let* ((char (char-after))
                  (new-char (if (eq (upcase char) char)
                                (downcase char)
                              (upcase char))))
             (delete-char 1)
             (insert new-char)
             (backward-char 1))))))))

;;; Extend mode editing commands

(defun evim-yank ()
  "Yank content of all regions to VM register.
Uses `evil-this-register' if set (via \"a prefix), otherwise default register.
Also syncs to evil registers for interoperability."
  (interactive)
  (when (evim-extend-mode-p)
    (let* ((register (or evil-this-register ?\"))
           (contents (mapcar (lambda (r)
                               (buffer-substring-no-properties
                                (marker-position (evim-region-beg r))
                                (marker-position (evim-region-end r))))
                             (evim-state-regions evim--state)))
           (combined (string-join contents "\n")))
      ;; Handle uppercase registers (append mode)
      (if (and (>= register ?A) (<= register ?Z))
          (let* ((lower (downcase register))
                 (existing (gethash lower (evim-state-registers evim--state))))
            (puthash lower (append existing contents)
                     (evim-state-registers evim--state))
            ;; Sync to evil register (append)
            (evil-set-register lower
                               (concat (or (evil-get-register lower t) "")
                                       "\n" combined))
            (message "Appended %d regions to register '%c'" (length contents) lower))
        (puthash register contents (evim-state-registers evim--state))
        ;; Sync to evil register
        (evil-set-register register combined)
        (message "Yanked %d regions to register '%c'" (length contents) register))
      (kill-new (car contents))
      ;; Clear evil-this-register after use
      (setq evil-this-register nil))))

(defun evim-delete ()
  "Delete content of all regions."
  (interactive)
  (when (evim-extend-mode-p)
    ;; First yank
    (evim-yank)
    ;; Delete from end to beginning (inhibit hooks during batch delete)
    (evim--with-batched-changes
      (dolist (region (evim--regions-by-position-reverse))
        (delete-region (marker-position (evim-region-beg region))
                       (marker-position (evim-region-end region)))))
    ;; Manually clamp and update after batch operation
    (evim--clamp-markers)
    (evim--check-and-merge-overlapping)
    ;; Switch to cursor mode
    (evim--enter-cursor-mode)
    (evim--update-keymap)))

(defun evim-change ()
  "Delete regions and enter insert mode."
  (interactive)
  (when (evim-extend-mode-p)
    (evim-delete)
    (evim--start-insert-mode)
    (evil-insert-state)))

(defun evim-paste-after ()
  "Paste VM register after cursor positions.
In extend mode, replaces selected regions.
In cursor mode, inserts after cursor."
  (interactive)
  (when (evim-active-p)
    (evim--paste-impl t)))

(defun evim-paste-before ()
  "Paste VM register before cursor positions.
In extend mode, replaces selected regions.
In cursor mode, inserts before cursor."
  (interactive)
  (when (evim-active-p)
    (evim--paste-impl nil)))

(defun evim--paste-impl (after)
  "Paste implementation.  AFTER determine position (t=after, nil=before).
Uses `evil-this-register' if set (via \\\"a prefix), otherwise default register.
Falls back to evil registers if VM register is empty.
In extend mode, replaces selected regions.  In cursor mode, inserts at cursor."
  (let* ((register (or evil-this-register ?\"))
         ;; Normalize uppercase to lowercase for lookup
         (lookup-reg (if (and (>= register ?A) (<= register ?Z))
                         (downcase register)
                       register))
         ;; Try VM register first, then fall back to evil register
         (contents (or (gethash lookup-reg (evim-state-registers evim--state))
                       ;; Fallback: get from evil register and wrap in list
                       (when-let ((evil-content (evil-get-register lookup-reg t)))
                         (list evil-content))))
         (sorted-regions (evim--regions-by-position))
         (num-regions (length sorted-regions))
         (num-contents (length contents))
         (extend-mode-p (evim-extend-mode-p)))
    ;; Clear evil-this-register after use
    (setq evil-this-register nil)
    (unless contents
      (user-error "Register '%c' is empty" register))
    (evim--with-batched-changes
      ;; In extend mode, delete current content first (from end to beginning)
      (when extend-mode-p
        (dolist (region (evim--regions-by-position-reverse))
          (delete-region (marker-position (evim-region-beg region))
                         (marker-position (evim-region-end region)))))
      ;; Insert new content (sorted by position, matching contents order)
      ;; After insert, set cursor on last inserted char (like evil p/P)
      (cl-loop for region in sorted-regions
               for idx from 0
               for content = (cond
                              ((= num-contents num-regions)
                               (nth idx contents))
                              ((= num-contents 1)
                               (car contents))
                              (t
                               (nth (mod idx num-contents) contents)))
               do (save-excursion
                    (goto-char (marker-position (evim-region-beg region)))
                    ;; In cursor mode with 'after', move past cursor char
                    (when (and after (not extend-mode-p))
                      (forward-char 1))
                    (insert content)
                    ;; Place cursor on last inserted char
                    (let ((cursor-pos (1- (point))))
                      (set-marker (evim-region-beg region) cursor-pos)
                      (set-marker (evim-region-end region) cursor-pos)
                      (set-marker (evim-region-anchor region) cursor-pos)))))
    (setf (evim-state-mode evim--state) 'cursor)
    (evim--finalize-batch-edit t)
    (message "Pasted from register '%c'" register)))

(defun evim-flip-direction ()
  "Flip direction of all regions (swap cursor and anchor).
Moves the anchor to the opposite end of the selection."
  (interactive)
  (when (evim-extend-mode-p)
    (dolist (region (evim-state-regions evim--state))
      (let* ((beg (marker-position (evim-region-beg region)))
             (end (marker-position (evim-region-end region)))
             (old-dir (evim-region-dir region))
             (new-dir (if (= old-dir 1) 0 1)))
        ;; Move anchor to the end the cursor is leaving.
        ;; dir=1→0: cursor was at end, now at beg; anchor moves to last char (1- end)
        ;; dir=0→1: cursor was at beg, now at end; anchor moves to beg
        (set-marker (evim-region-anchor region)
                    (if (= new-dir 0) (1- end) beg))
        (setf (evim-region-dir region) new-dir)))
    (evim--update-all-overlays)))

(defun evim-upcase ()
  "Uppercase content of all regions."
  (interactive)
  (when (evim-extend-mode-p)
    (evim--with-undo-amalgamate
      (evim--with-batched-changes
        (dolist (region (evim-state-regions evim--state))
          (upcase-region (marker-position (evim-region-beg region))
                         (marker-position (evim-region-end region))))))
    (evim--finalize-batch-edit)))

(defun evim-downcase ()
  "Lowercase content of all regions."
  (interactive)
  (when (evim-extend-mode-p)
    (evim--with-undo-amalgamate
      (evim--with-batched-changes
        (dolist (region (evim-state-regions evim--state))
          (downcase-region (marker-position (evim-region-beg region))
                           (marker-position (evim-region-end region))))))
    (evim--finalize-batch-edit)))

(defun evim-toggle-case ()
  "Toggle case of content in all regions."
  (interactive)
  (when (evim-extend-mode-p)
    (let ((saved-positions
           (mapcar (lambda (r)
                     (list r
                           (marker-position (evim-region-beg r))
                           (marker-position (evim-region-end r))
                           (marker-position (evim-region-anchor r))))
                   (evim-state-regions evim--state))))
      (evim--with-undo-amalgamate
        (evim--with-batched-changes
          (dolist (region (evim-state-regions evim--state))
            (let ((beg (marker-position (evim-region-beg region)))
                  (end (marker-position (evim-region-end region))))
              (save-excursion
                (goto-char beg)
                (while (< (point) end)
                  (let* ((char (char-after))
                         (new-char (if (eq (upcase char) char)
                                       (downcase char)
                                     (upcase char))))
                    (delete-char 1)
                    (insert new-char))))))))
      (dolist (saved saved-positions)
        (cl-destructuring-bind (region beg end anchor) saved
          (set-marker (evim-region-beg region) beg)
          (set-marker (evim-region-end region) end)
          (set-marker (evim-region-anchor region) anchor)))
      (evim--finalize-batch-edit))))

;;; Utility commands

(defun evim-align ()
  "Align all cursors vertically.
Spaces are inserted before the start of each region."
  (interactive)
  (when (evim-active-p)
    ;; Find max column based on region starts
    (let ((max-col 0))
      (dolist (region (evim-state-regions evim--state))
        (save-excursion
          (goto-char (marker-position (evim-region-beg region)))
          (setq max-col (max max-col (current-column)))))
      ;; Add spaces before region starts to align
      (evim--with-undo-amalgamate
        (evim--with-batched-changes
          (dolist (region (evim--regions-by-position-reverse))
            (save-excursion
              (goto-char (marker-position (evim-region-beg region)))
              (let ((spaces-needed (- max-col (current-column))))
                (when (> spaces-needed 0)
                  (insert (make-string spaces-needed ?\s))))))))
      (evim--finalize-batch-edit))))

;;; Run at Cursors commands

(defun evim-run-normal (cmd)
  "Run normal mode CMD at all cursor positions.
If CMD is nil, prompt for input."
  (interactive
   (list (read-string "Normal command: ")))
  (when (and (evim-active-p) (not (string-empty-p cmd)))
    ;; Temporarily disable evim keymaps to use original evil bindings
    (let ((saved-alist evim--emulation-alist))
      (setq evim--emulation-alist nil)
      (unwind-protect
          (evim--run-command-at-cursors
           (lambda ()
             (execute-kbd-macro cmd)))
        ;; Restore evim keymaps
        (setq evim--emulation-alist saved-alist)))))

(defun evim-run-macro (register)
  "Run macro from REGISTER at all cursor positions."
  (interactive
   (list (read-char "Register: ")))
  (when (evim-active-p)
    (let ((macro (evil-get-register register t)))
      (unless macro
        (user-error "Register '%c' is empty" register))
      ;; Temporarily disable evim keymaps to use original evil bindings
      (let ((saved-alist evim--emulation-alist))
        (setq evim--emulation-alist nil)
        (unwind-protect
            (evim--run-command-at-cursors
             (lambda ()
               (execute-kbd-macro macro)))
          ;; Restore evim keymaps
          (setq evim--emulation-alist saved-alist))))))

(defun evim-run-ex (cmd)
  "Run Ex command CMD at all cursor positions.
If CMD is nil, prompt for input."
  (interactive
   (list (read-string ": " nil 'evil-ex-history)))
  (when (and (evim-active-p) (not (string-empty-p cmd)))
    (evim--run-command-at-cursors
     (lambda ()
       (evil-ex-execute cmd)))))

(defun evim--run-command-at-cursors (fn &optional update-positions)
  "Execute FN at all cursor positions in buffer order.
Processes from end to beginning to preserve positions.
If UPDATE-POSITIONS is non-nil, update cursor positions to point after FN.
Updates overlays after execution."
  (let ((regions (evim--regions-by-position-reverse))
        (handle (prepare-change-group)))
    (evim--with-batched-changes
      (dolist (region regions)
        (goto-char (evim--region-cursor-pos region))
        (condition-case err
            (progn
              (funcall fn)
              ;; Only update position if explicitly requested (for movement commands)
              (when update-positions
                (evim--region-set-cursor-pos region (point))))
          (error
           (message "Error at cursor %d: %s"
                    (evim-region-index region) (error-message-string err))))))
    (undo-amalgamate-change-group handle))
  (evim--finalize-batch-edit))

(defun evim-toggle-restrict ()
  "Toggle restriction for evim search.
If in evil visual mode: set pending restriction for next activation.
If evim active with restriction: clear it."
  (interactive)
  (cond
   ;; In visual mode: save pending restriction (don't activate evim yet)
   ((evil-visual-state-p)
    (let* ((vtype (evil-visual-type))
           (beg (region-beginning))
           (end (region-end)))
      ;; For visual-line mode, expand to full lines
      (when (eq vtype 'line)
        (setq beg (save-excursion (goto-char beg) (line-beginning-position))
              end (save-excursion (goto-char end) (min (1+ (line-end-position)) (point-max)))))
      (evil-exit-visual-state)
      (if (evim-active-p)
          ;; evim already active - apply restriction immediately
          (progn
            (evim--set-restrict beg end)
            (when-let ((pattern (car (evim-state-patterns evim--state))))
              (evim--show-match-preview-restricted pattern))
            (message "Restriction set"))
        ;; evim not active - save for later
        (setq evim--pending-restrict (cons beg end))
        (message "Restriction set (will apply on C-n)"))))
   ;; evim active with restriction: clear it
   ((and (evim-active-p) (evim--restrict-active-p))
    (evim--clear-restrict)
    (when-let ((pattern (car (evim-state-patterns evim--state))))
      (evim--show-match-preview pattern))
    (message "Restriction cleared"))
   ;; Pending restriction exists: clear it
   (evim--pending-restrict
    (setq evim--pending-restrict nil)
    (message "Pending restriction cleared"))
   ;; Nothing to do
   (t
    (message "Select region in visual mode to set restriction"))))

(defun evim-clear-restrict ()
  "Clear current restriction, allowing search in entire buffer."
  (interactive)
  (when (evim-active-p)
    (evim--clear-restrict)
    ;; Update match preview if we have a pattern
    (when-let ((pattern (car (evim-state-patterns evim--state))))
      (evim--show-match-preview pattern))
    (message "Restriction cleared")))

;;; Helper functions

(defun evim--execute-at-all-cursors (fn &optional update-markers)
  "Execute FN at all cursor positions.
FN is called with point at each cursor, from end to beginning.
If UPDATE-MARKERS is non-nil, update each cursor's marker to point
after FN completes (useful for commands like o/O that move point)."
  (let ((regions (evim--regions-by-position-reverse)))
    (evim--with-batched-changes
      (dolist (region regions)
        (if update-markers
            ;; Don't use save-excursion - we want to capture the new position
            (progn
              (goto-char (evim--region-cursor-pos region))
              (funcall fn)
              ;; Update marker to new position
              (evim--region-set-cursor-pos region (point)))
          ;; Original behavior with save-excursion
          (save-excursion
            (goto-char (evim--region-cursor-pos region))
            (funcall fn))))))
  (evim--finalize-batch-edit))

;;; Operator infrastructure (d/c/y with motions)

;; Single character motions
(defconst evim--single-motions
  '(?h ?j ?k ?l ?w ?e ?b ?W ?E ?B ?$ ?^ ?0 ?{ ?} ?\( ?\) ?% ?n ?N ?_ ?H ?M ?L ?G)
  "Single character motions.")

;; Double character motion prefixes
(defconst evim--double-motion-prefixes
  '(?i ?a ?f ?F ?t ?T ?g ?\[ ?\])
  "Characters that start a two-character motion.")

;; Text objects for i/a
(defconst evim--text-objects
  '(?w ?W ?s ?p ?b ?B ?\( ?\) ?\[ ?\] ?{ ?} ?< ?> ?\" ?' ?` ?t)
  "Valid text objects for i/a prefix.")

;; g-motions
(defconst evim--g-motions
  '(?e ?E ?g ?_ ?j ?k ?0 ?^ ?$ ?m ?M)
  "Valid motions after g prefix.")

(defun evim--digit-p (char)
  "Return t if CHAR is a digit 1-9 (not 0, which is a motion)."
  (and char (>= char ?1) (<= char ?9)))

(defun evim--parse-count ()
  "Parse optional count from input.
Returns (count . next-char) where count is nil or a number."
  (let ((count nil)
        (char (read-char "Operator: ")))
    (when char
      ;; Collect digits
      (while (evim--digit-p char)
        (setq count (+ (* (or count 0) 10) (- char ?0)))
        (setq char (read-char)))
      (cons count char))))

(defun evim--parse-motion (&optional operator-char)
  "Parse a motion from user input.
Returns a plist (:keys STRING :count NUMBER :line BOOL) or nil on cancel.
:keys is the motion key sequence (e.g., \"w\", \"iw\", \"f(\")
:count is the motion count (e.g., 3 for 3w)
:line is t for line operations (dd, cc, yy)
OPERATOR-CHAR is the operator character (d, c, y) to detect line operations."
  (let* ((count-and-char (evim--parse-count))
         (count (car count-and-char))
         (char (cdr count-and-char)))
    (unless char
      (cl-return-from evim--parse-motion nil))
    (cond
     ;; ESC cancels
     ((= char 27)
      nil)
     ;; Line operation: dd, cc, yy
     ((and operator-char (= char operator-char))
      (list :keys nil :count count :line t))
     ;; Single motions
     ((memq char evim--single-motions)
      (list :keys (string char) :count count))
     ;; Double motion prefixes
     ((memq char evim--double-motion-prefixes)
      (let ((char2 (read-char)))
        (cond
         ((null char2) nil)
         ((= char2 27) nil)  ; ESC cancels
         ;; i/a + text object
         ((and (memq char '(?i ?a))
               (memq char2 evim--text-objects))
          (list :keys (string char char2) :count count))
         ;; f/F/t/T + any char
         ((memq char '(?f ?F ?t ?T))
          (list :keys (string char char2) :count count))
         ;; g + motion
         ((and (= char ?g)
               (memq char2 evim--g-motions))
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
           ;; Line operation with count: 3dd
           ((and operator-char (= next-char operator-char))
            (list :keys nil :count new-count :line t))
           ((memq next-char evim--single-motions)
            (list :keys (string next-char) :count new-count))
           ((memq next-char evim--double-motion-prefixes)
            (let ((char2 (read-char)))
              (when (and char2 (/= char2 27))
                (list :keys (string next-char char2) :count new-count))))
           (t nil)))))
     (t nil))))

;; Inclusive motions need +1 to end position for operators
(defconst evim--inclusive-motions
  '(?$ ?e ?E ?% ?G ?N ?n ?} ?{ ?\) ?\( ?` ?' ?g ?f ?F ?t ?T ?\] ?\[)
  "Motions that are inclusive (include the character at end position).")

(defun evim--get-motion-range (motion-keys count)
  "Get the range for MOTION-KEYS with COUNT from current position.
Returns (BEG END) or nil if motion failed."
  (let* ((count (or count 1))
         (beg (point))
         (beg-line (line-number-at-pos beg))
         end
         ;; Temporarily disable evim keymaps
         (saved-alist evim--emulation-alist)
         ;; Check if motion is inclusive
         (first-char (aref motion-keys 0))
         (inclusive-p (memq first-char evim--inclusive-motions))
         ;; Check if this is a word motion (w/W) that shouldn't cross line boundaries
         ;; for delete/change operators (like vim behavior)
         (word-motion-p (memq first-char '(?w ?W))))
    (setq evim--emulation-alist nil)
    ;; Remove post-command-hook temporarily to prevent cursor jumping during macro
    (remove-hook 'post-command-hook #'evim--post-command t)
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
                           ((or ?< ?>) (if inner-p (evil-inner-angle) (evil-an-angle)))
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
      ;; Restore evim keymaps and hook
      (setq evim--emulation-alist saved-alist)
      (add-hook 'post-command-hook #'evim--post-command nil t))
    ;; Ensure beg <= end
    (when (and beg end)
      (when (> beg end)
        (let ((tmp beg))
          (setq beg end
                end tmp)))
      ;; For word motions (w/W), don't cross line boundaries - like vim's dw behavior
      ;; If the motion crossed to a different line, limit end to end of original line
      (when (and word-motion-p
                 (> end beg)
                 (save-excursion
                   (goto-char end)
                   (/= (line-number-at-pos) beg-line)))
        (setq end (save-excursion
                    (goto-char beg)
                    (line-end-position))))
      (when (> end beg)
        (list beg end)))))

(defun evim--execute-operator-line (operator count)
  "Execute line OPERATOR (dd, cc, yy) at current position.
OPERATOR is one of \\='delete, \\='change, \\='yank.
COUNT is number of lines (default 1).
Returns the deleted/yanked text including newline, or nil."
  (let* ((count (or count 1))
         (beg (line-beginning-position))
         (end (save-excursion
                (forward-line (1- count))
                (if (eobp)
                    (point)  ; Last line without newline
                  (forward-line 1)
                  (point))))
         text)
    (when (> end beg)
      (setq text (buffer-substring-no-properties beg end))
      (pcase operator
        ('delete
         (delete-region beg end)
         ;; Position cursor at beginning of line (or previous line if at eob)
         (goto-char (min beg (point-max)))
         (when (and (eobp) (not (bobp)))
           (forward-line -1)))
        ('change
         (delete-region beg end)
         ;; For cc: insert newline and position for insert
         (unless (eobp)
           (forward-line -1))
         (end-of-line)
         (newline-and-indent))
        ('yank
         ;; Just copy, don't delete
         nil)))
    text))

(defun evim--execute-operator-motion (operator motion-keys count)
  "Execute OPERATOR with MOTION-KEYS at current position.
OPERATOR is one of \\='delete, \\='change, \\='yank.
MOTION-KEYS is a string like \"w\", \"iw\", \"f(\".
COUNT is the motion count or nil.
Returns the deleted/yanked text, or nil."
  (let* ((range (evim--get-motion-range motion-keys count))
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

(defun evim--run-operator-with-motion (operator &optional prefix-count operator-char)
  "Run OPERATOR with a motion parsed from user input.
OPERATOR is one of \\='delete, \\='change, \\='yank.
PREFIX-COUNT is an optional count from prefix argument (for 2dw pattern).
OPERATOR-CHAR is the operator key (d, c, y) for detecting line operations.
Applies the operator to all cursors."
  (let ((motion (evim--parse-motion operator-char)))
    (unless motion
      (message "Cancelled")
      (cl-return-from evim--run-operator-with-motion nil))
    (let ((keys (plist-get motion :keys))
          (line-p (plist-get motion :line))
          ;; Combine prefix count with motion count: 2d3w = delete 6 words
          (count (let ((motion-count (plist-get motion :count))
                       (pre (and prefix-count (prefix-numeric-value prefix-count))))
                   (cond
                    ((and pre motion-count) (* pre motion-count))
                    (pre pre)
                    (motion-count motion-count)
                    (t nil))))
          (texts '()))
      (evim--with-undo-amalgamate
        ;; Execute at all cursors (from end to beginning)
        (let ((regions (evim--regions-by-position-reverse))
              (inhibit-modification-hooks t))
          (evim--without-post-command-hook
            (dolist (region regions)
              (goto-char (evim--region-cursor-pos region))
              (let ((text (if line-p
                              (evim--execute-operator-line operator count)
                            (evim--execute-operator-motion operator keys count))))
                (when text
                  (push text texts))
                ;; Update cursor position
                ;; For line operations: cursor goes to first non-blank
                ;; For delete/yank: adjust like evil does
                ;; For change: keep at deletion point for insert mode
                (let ((new-pos (cond
                                (line-p
                                 (if (eq operator 'change)
                                     (point)
                                   (save-excursion
                                     (back-to-indentation)
                                     (point))))
                                ((eq operator 'change)
                                 (point))
                                (t
                                 (evim--adjust-cursor-pos (point))))))
                  (evim--region-set-cursor-pos region new-pos))))))
        ;; Save yanked/deleted text to VM register
        ;; texts is already in correct order (beginning to end) because we
        ;; iterated from end to beginning and used push
        (when texts
          (puthash ?\" texts (evim-state-registers evim--state))
          ;; Also to kill-ring
          (kill-new (car texts)))
        ;; Clamp and update
        (evim--clamp-markers)
        (evim--check-and-merge-overlapping)
        (evim--update-all-overlays)
        ;; Move to leader
        (when-let ((leader (evim--leader-region)))
          (goto-char (evim--region-cursor-pos leader))))
      ;; Return for change operator to know if we should enter insert mode
      (list :texts texts :motion motion))))

(defun evim-operator-delete (count)
  "Delete operator: wait for motion, then delete at all cursors.
COUNT is optional prefix argument for patterns like 2dw.
Examples: dw (delete word), d3w (delete 3 words), dd (delete line).
Special: ds + char deletes surround (evil-surround integration)."
  (interactive "P")
  (when (evim-cursor-mode-p)
    (message "[EVIM] d")
    ;; Peek next char - if 's', delegate to surround
    (let ((char (read-char)))
      (if (= char ?s)
          (evim-delete-surround)
        ;; Put char back for normal motion parsing
        (setq unread-command-events (list char))
        (evim--run-operator-with-motion 'delete count ?d)))))

(defun evim-operator-change (count)
  "Change operator: delete with motion, then enter insert mode.
COUNT is optional prefix argument for patterns like 2cw.
Examples: cw (change word), ciw (change inner word), cc (change line).
Special: cs + old + new changes surround (evil-surround integration)."
  (interactive "P")
  (when (evim-cursor-mode-p)
    (message "[EVIM] c")
    ;; Peek next char - if 's', delegate to surround
    (let ((char (read-char)))
      (if (= char ?s)
          (evim-change-surround)
        ;; Put char back for normal motion parsing
        (setq unread-command-events (list char))
        (let ((result (evim--run-operator-with-motion 'change count ?c)))
          (when (and result (plist-get result :texts))
            ;; Enter insert mode
            (evim--start-insert-mode)
            (evil-insert-state)))))))

(defun evim-operator-yank (count)
  "Yank operator: copy text defined by motion at all cursors.
COUNT is optional prefix argument for patterns like 2yw.
Examples: yw (yank word), yiw (yank inner word), yy (yank line).
Special: ys + motion + char adds surround (evil-surround integration)."
  (interactive "P")
  (when (evim-cursor-mode-p)
    (message "[EVIM] y")
    ;; Peek next char - if 's', delegate to surround
    (let ((char (read-char)))
      (if (= char ?s)
          (evim-operator-surround count)
        ;; Put char back for normal motion parsing
        (setq unread-command-events (list char))
        (let ((result (evim--run-operator-with-motion 'yank count ?y)))
          (when result
            (message "Yanked %d regions" (length (plist-get result :texts)))))))))

;; Shortcuts for common operations
(defun evim-delete-to-eol (&optional for-change)
  "Delete from cursor to end of line (D).
If FOR-CHANGE is non-nil, don't adjust cursor position (for C command)."
  (interactive)
  (when (evim-cursor-mode-p)
    (let ((texts '()))
      (evim--with-undo-amalgamate
        (let ((regions (evim--regions-by-position-reverse))
              (inhibit-modification-hooks t))
          (evim--without-post-command-hook
            (dolist (region regions)
              (goto-char (evim--region-cursor-pos region))
              (let ((beg (point))
                    (end (line-end-position)))
                (when (> end beg)
                  (push (buffer-substring-no-properties beg end) texts)
                  (delete-region beg end))
                ;; For D: adjust position like evil does in normal state
                ;; For C: keep cursor at deletion point for insert mode
                (evim--region-set-cursor-pos region
                                            (if for-change
                                                (point)
                                              (evim--adjust-cursor-pos (point))))))))
        ;; texts is already in correct order (beginning to end) because we
        ;; iterated from end to beginning and used push
        (when texts
          (puthash ?\" texts (evim-state-registers evim--state))
          (kill-new (car texts)))))
    (evim--clamp-markers)
    (evim--check-and-merge-overlapping)
    (evim--update-all-overlays)
    (when-let ((leader (evim--leader-region)))
      (goto-char (evim--region-cursor-pos leader)))))

(defun evim-change-to-eol ()
  "Change from cursor to end of line (C)."
  (interactive)
  (when (evim-cursor-mode-p)
    (evim-delete-to-eol t)  ; t = for-change, don't adjust cursor
    (evim--start-insert-mode)
    (evil-insert-state)))

(defun evim-yank-line ()
  "Yank entire line (Y)."
  (interactive)
  (when (evim-cursor-mode-p)
    (let ((texts '()))
      ;; Collect texts in position order (beginning to end)
      (dolist (region (evim--regions-by-position))
        (save-excursion
          (goto-char (evim--region-cursor-pos region))
          (let ((beg (line-beginning-position))
                (end (line-end-position)))
            (push (buffer-substring-no-properties beg end) texts))))
      (when texts
        (puthash ?\" (nreverse texts) (evim-state-registers evim--state))
        (kill-new (car texts))
        (message "Yanked %d lines" (length texts))))))

(defun evim-join-lines (count)
  "Join current line with next COUNT lines (J).
Replaces the newline and leading whitespace with a single space."
  (interactive "p")
  (when (evim-cursor-mode-p)
    (evim--with-undo-amalgamate
      (let ((regions (evim--regions-by-position-reverse))
            (inhibit-modification-hooks t))
        (evim--without-post-command-hook
          (dolist (region regions)
            (goto-char (evim--region-cursor-pos region))
            ;; Join count lines
            (dotimes (_ (or count 1))
              (end-of-line)
              (unless (eobp)
                (let ((join-pos (point)))
                  ;; Delete newline
                  (delete-char 1)
                  ;; Delete leading whitespace on next line
                  (while (and (not (eobp))
                              (memq (char-after) '(?\s ?\t)))
                    (delete-char 1))
                  ;; Insert single space unless at eob or next char is )
                  (unless (or (eobp)
                              (memq (char-after) '(?\) ?\])))
                    (insert " "))
                  ;; Position cursor at join point
                  (evim--region-set-cursor-pos region join-pos))))))))
    (evim--clamp-markers)
    (evim--check-and-merge-overlapping)
    (evim--update-all-overlays)
    (when-let ((leader (evim--leader-region)))
      (goto-char (evim--region-cursor-pos leader)))))

;;; Indent/outdent operators

(defun evim--execute-indent-line (direction count)
  "Indent or outdent COUNT lines starting from current position.
DIRECTION is \\='indent or \\='outdent."
  (let* ((count (or count 1))
         (beg (line-beginning-position))
         (end (save-excursion
                (forward-line (1- count))
                (line-end-position))))
    (pcase direction
      ('indent (indent-rigidly beg end tab-width))
      ('outdent (indent-rigidly beg end (- tab-width))))
    ;; Move cursor to first non-blank
    (back-to-indentation)
    (point)))

(defun evim--execute-indent-motion (direction motion-keys count)
  "Indent or outdent region defined by MOTION-KEYS with COUNT.
DIRECTION is \\='indent or \\='outdent."
  (let* ((range (evim--get-motion-range motion-keys count))
         (beg (car range))
         (end (cadr range)))
    (when (and beg end (> end beg))
      ;; Expand to full lines (end is inclusive like vim)
      (save-excursion
        (goto-char beg)
        (setq beg (line-beginning-position))
        (goto-char end)
        (setq end (line-end-position)))
      (pcase direction
        ('indent (indent-rigidly beg end tab-width))
        ('outdent (indent-rigidly beg end (- tab-width))))
      ;; Move cursor to first non-blank of first line
      (goto-char beg)
      (back-to-indentation)
      (point))))

(defun evim--run-indent-operator (direction &optional prefix-count operator-char)
  "Run indent/outdent operator with motion.
DIRECTION is \\='indent or \\='outdent.
PREFIX-COUNT is optional count from prefix argument.
OPERATOR-CHAR is > or < for detecting line operations (>> or <<)."
  (let ((motion (evim--parse-motion operator-char)))
    (unless motion
      (message "Cancelled")
      (cl-return-from evim--run-indent-operator nil))
    (let ((keys (plist-get motion :keys))
          (line-p (plist-get motion :line))
          (count (let ((motion-count (plist-get motion :count))
                       (pre (and prefix-count (prefix-numeric-value prefix-count))))
                   (cond
                    ((and pre motion-count) (* pre motion-count))
                    (pre pre)
                    (motion-count motion-count)
                    (t nil)))))
      (evim--with-undo-amalgamate
        (let ((regions (evim--regions-by-position-reverse))
              (inhibit-modification-hooks t))
          (evim--without-post-command-hook
            (dolist (region regions)
              (goto-char (evim--region-cursor-pos region))
              (let ((new-pos (if line-p
                                 (evim--execute-indent-line direction count)
                               (evim--execute-indent-motion direction keys count))))
                (when new-pos
                  (evim--region-set-cursor-pos region new-pos))))))))
    (evim--clamp-markers)
    (evim--check-and-merge-overlapping)
    (evim--update-all-overlays)
    (when-let ((leader (evim--leader-region)))
      (goto-char (evim--region-cursor-pos leader)))))

(defun evim-operator-indent (count)
  "Indent operator: wait for motion, then indent at all cursors.
COUNT is optional prefix argument.
Examples: >j (indent 2 lines), >> (indent current line), >ip (indent paragraph)."
  (interactive "P")
  (when (evim-cursor-mode-p)
    (message "[EVIM] >")
    (evim--run-indent-operator 'indent count ?>)))

(defun evim-operator-outdent (count)
  "Outdent operator: wait for motion, then outdent at all cursors.
COUNT is optional prefix argument.
Examples: <j (outdent 2 lines), << (outdent current line),
<ip (outdent paragraph)."
  (interactive "P")
  (when (evim-cursor-mode-p)
    (message "[EVIM] <")
    (evim--run-indent-operator 'outdent count ?<)))

;;; Case change operators (gu, gU, g~)

(defun evim--execute-case-line (case-fn count)
  "Apply CASE-FN to COUNT lines starting from current position.
CASE-FN is \\='upcase-region, \\='downcase-region, or \\='evim--toggle-case-region."
  (let* ((count (or count 1))
         (beg (line-beginning-position))
         (end (save-excursion
                (forward-line (1- count))
                (line-end-position))))
    (funcall case-fn beg end)
    ;; Move cursor to first non-blank
    (goto-char beg)
    (back-to-indentation)
    (point)))

(defun evim--execute-case-motion (case-fn motion-keys count)
  "Apply CASE-FN to region defined by MOTION-KEYS with COUNT.
CASE-FN is \\='upcase-region, \\='downcase-region, or \\='evim--toggle-case-region."
  (let* ((range (evim--get-motion-range motion-keys count))
         (beg (car range))
         (end (cadr range)))
    (when (and beg end (> end beg))
      (funcall case-fn beg end)
      ;; Move cursor to beginning of affected region
      (goto-char beg)
      (point))))

(defun evim--toggle-case-region (beg end)
  "Toggle case of text between BEG and END."
  (save-excursion
    (goto-char beg)
    (while (< (point) end)
      (let* ((char (char-after))
             (new-char (if (eq (upcase char) char)
                           (downcase char)
                         (upcase char))))
        (delete-char 1)
        (insert-char new-char)))))

(defun evim--run-case-operator (case-fn &optional prefix-count line-char)
  "Run case change operator with motion.
CASE-FN is the case function to apply.
PREFIX-COUNT is optional count from prefix argument.
LINE-CHAR is the character that triggers a line operation:
u for guu, U for gUU, and ~ for g~~."
  (let ((motion (evim--parse-motion line-char)))
    (unless motion
      (message "Cancelled")
      (cl-return-from evim--run-case-operator nil))
    (let ((keys (plist-get motion :keys))
          (line-p (plist-get motion :line))
          (count (let ((motion-count (plist-get motion :count))
                       (pre (and prefix-count (prefix-numeric-value prefix-count))))
                   (cond
                    ((and pre motion-count) (* pre motion-count))
                    (pre pre)
                    (motion-count motion-count)
                    (t nil)))))
      (evim--with-undo-amalgamate
        (let ((regions (evim--regions-by-position-reverse))
              (inhibit-modification-hooks t))
          (evim--without-post-command-hook
            (dolist (region regions)
              (goto-char (evim--region-cursor-pos region))
              (let ((new-pos (if line-p
                                 (evim--execute-case-line case-fn count)
                               (evim--execute-case-motion case-fn keys count))))
                (when new-pos
                  (evim--region-set-cursor-pos region new-pos))))))))
    (evim--clamp-markers)
    (evim--check-and-merge-overlapping)
    (evim--update-all-overlays)
    (when-let ((leader (evim--leader-region)))
      (goto-char (evim--region-cursor-pos leader)))))

(defun evim-operator-downcase (count)
  "Downcase operator: wait for motion, then lowercase at all cursors.
COUNT is optional prefix argument.
Examples: guw (lowercase word), guiw (lowercase inner word),
guu (lowercase line)."
  (interactive "P")
  (when (evim-cursor-mode-p)
    (message "[EVIM] gu")
    (evim--run-case-operator #'downcase-region count ?u)))

(defun evim-operator-upcase (count)
  "Upcase operator: wait for motion, then uppercase at all cursors.
COUNT is optional prefix argument.
Examples: gUw (uppercase word), gUiw (uppercase inner word),
gUU (uppercase line)."
  (interactive "P")
  (when (evim-cursor-mode-p)
    (message "[EVIM] gU")
    (evim--run-case-operator #'upcase-region count ?U)))

(defun evim-operator-toggle-case (count)
  "Toggle case operator: wait for motion, then toggle case at all cursors.
COUNT is optional prefix argument.
Examples: g~w (toggle case word), g~iw (toggle case inner word),
g~~ (toggle case line)."
  (interactive "P")
  (when (evim-cursor-mode-p)
    (message "[EVIM] g~")
    (evim--run-case-operator #'evim--toggle-case-region count ?~)))

;;; Visual mode cursor selection (Phase 9.1)

;;;###autoload
(defun evim-visual-cursors ()
  "Create cursors from current visual selection.
In visual-line mode: creates a cursor at beginning of each selected line.
In visual-block mode: creates a cursor at the block column on each line.
In visual-char mode: creates a cursor at start and end of selection."
  (interactive)
  (unless (evil-visual-state-p)
    (user-error "Must be in visual state"))
  (let* ((type (evil-visual-type))
         (beg (region-beginning))
         (end (region-end))
         (positions '()))
    ;; For visual-line mode, expand to full lines
    (when (eq type 'line)
      (setq beg (save-excursion (goto-char beg) (line-beginning-position))
            end (save-excursion (goto-char end) (min (1+ (line-end-position)) (point-max)))))
    (cond
     ;; Visual block: cursor at block column on each line
     ((eq type 'block)
      (let ((col (save-excursion
                   (goto-char beg)
                   (current-column))))
        (save-excursion
          (goto-char beg)
          (while (<= (point) end)
            (move-to-column col)
            (push (point) positions)
            (unless (zerop (forward-line 1))
              (cl-return))))))
     ;; Visual line: cursor at first non-blank of each line
     ((eq type 'line)
      (save-excursion
        (goto-char beg)
        (while (< (point) end)
          (back-to-indentation)
          (push (point) positions)
          (unless (= (forward-line 1) 0)
            (cl-return)))))
     ;; Visual char: cursors at start and end
     (t
      (push beg positions)
      (unless (= beg end)
        (push (1- end) positions))))
    ;; Exit visual state
    (evil-exit-visual-state)
    ;; Activate evim and create cursors
    (when positions
      (setq positions (nreverse positions))
      (evim-activate)
      ;; Create cursor at each position
      (dolist (pos positions)
        (evim--create-region pos pos))
      ;; Set leader to first cursor
      (when-let ((first (car (evim-state-regions evim--state))))
        (evim--set-leader first)
        (goto-char (evim--region-cursor-pos first)))
      (message "Created %d cursors" (length positions)))))

;;; Undo/Redo with cursor restoration (Phase 9.3)

(defun evim-undo ()
  "Undo last change and resync cursor positions to pattern.
Moves cursor to leader position after resync."
  (interactive)
  (when (evim-active-p)
    ;; Call evil-undo which handles undo-tree properly
    (evil-undo 1)
    ;; Resync regions to pattern matches
    (when (car (evim-state-patterns evim--state))
      (evim--resync-regions-to-pattern))
    ;; Adjust cursor positions: after undo, markers may land on newline
    ;; (e.g. paste moved markers into inserted text; undo removes text
    ;; and Emacs pushes markers to line-end-position).  Clamp them back
    ;; to the last character like evil-adjust-cursor does.
    (dolist (region (evim-state-regions evim--state))
      (evim--region-set-cursor-pos
       region (evim--adjust-cursor-pos (evim--region-cursor-pos region))))
    (evim--remove-all-overlays-thorough)
    (evim--update-all-overlays)
    ;; Move cursor to leader position (regions may have moved after resync)
    (when-let ((leader (evim--leader-region)))
      (goto-char (evim--region-visual-cursor-pos leader)))))

(defun evim-redo ()
  "Redo last undone change and resync cursor positions to pattern.
Moves cursor to leader position after resync."
  (interactive)
  (when (evim-active-p)
    ;; Call evil-redo which handles undo-tree properly
    (evil-redo 1)
    ;; Resync regions to pattern matches
    (when (car (evim-state-patterns evim--state))
      (evim--resync-regions-to-pattern))
    ;; Adjust cursor positions (same rationale as evim-undo)
    (dolist (region (evim-state-regions evim--state))
      (evim--region-set-cursor-pos
       region (evim--adjust-cursor-pos (evim--region-cursor-pos region))))
    (evim--remove-all-overlays-thorough)
    (evim--update-all-overlays)
    ;; Move cursor to leader position (regions may have moved after resync)
    (when-let ((leader (evim--leader-region)))
      (goto-char (evim--region-visual-cursor-pos leader)))))

;;; Improved Reselect Last (Phase 9.4)

(defun evim--save-for-reselect ()
  "Save current region positions and mode for later reselection."
  (when (evim-state-regions evim--state)
    (setf (evim-state-last-regions evim--state)
          (list :mode (evim-state-mode evim--state)
                :positions (mapcar (lambda (r)
                                     (list :beg (marker-position (evim-region-beg r))
                                           :end (marker-position (evim-region-end r))
                                           :anchor (marker-position (evim-region-anchor r))
                                           :dir (evim-region-dir r)))
                                   (evim-state-regions evim--state))))))

(defun evim-reselect-last ()
  "Reselect last cursors/regions with their original mode."
  (interactive)
  (let ((last (and evim--state (evim-state-last-regions evim--state))))
    (unless last
      (user-error "No previous selection to restore"))
    (unless (evim-active-p)
      (evim-activate))
    ;; Clear current regions
    (evim--remove-all-overlays)
    (dolist (region (evim-state-regions evim--state))
      (set-marker (evim-region-beg region) nil)
      (set-marker (evim-region-end region) nil)
      (set-marker (evim-region-anchor region) nil))
    (setf (evim-state-regions evim--state) nil)
    (clrhash (evim-state-region-by-id evim--state))
    ;; Handle both old format (list of cons) and new format (plist)
    (if (keywordp (car-safe last))
        ;; New format with mode
        (let ((mode (plist-get last :mode))
              (positions (plist-get last :positions))
              (ht (evim-state-region-by-id evim--state)))
          (dolist (pos positions)
            (let ((beg (plist-get pos :beg))
                  (end (plist-get pos :end))
                  (anchor (plist-get pos :anchor))
                  (dir (plist-get pos :dir)))
              (let* ((id (evim--generate-id))
                     (region (make-evim-region
                              :id id
                              :beg (evim--make-marker beg)
                              :end (evim--make-marker end)
                              :anchor (evim--make-marker (or anchor beg))
                              :dir (or dir 1))))
                (puthash id region ht)
                (push region (evim-state-regions evim--state)))))
          (setf (evim-state-mode evim--state) (or mode 'cursor)))
      ;; Old format: list of (beg . end) cons
      (dolist (pos-pair last)
        (evim--create-region (car pos-pair) (car pos-pair))))
    ;; Sort and setup
    (evim--sort-regions)
    (evim--update-region-indices)
    ;; Set leader
    (when-let ((first (car (evim-state-regions evim--state))))
      (setf (evim-state-leader-id evim--state) (evim-region-id first)))
    (evim--update-all-overlays)
    (evim--update-keymap)
    ;; Move to leader
    (when-let ((leader (evim--leader-region)))
      (goto-char (evim--region-visual-cursor-pos leader)))
    (message "Reselected %d regions" (length (evim-state-regions evim--state)))))

;;; Named VM Registers (Phase 9.5)

(defun evim-yank-to-register (register)
  "Yank content of all regions to REGISTER.
REGISTER is a character (a-z for named, \" for default).
Also syncs to evil registers for interoperability."
  (interactive "cYank to register: ")
  (when (evim-extend-mode-p)
    (let* ((contents (mapcar (lambda (r)
                               (buffer-substring-no-properties
                                (marker-position (evim-region-beg r))
                                (marker-position (evim-region-end r))))
                             (evim-state-regions evim--state)))
           (combined (string-join contents "\n")))
      ;; Uppercase register appends
      (if (and (>= register ?A) (<= register ?Z))
          (let* ((lower (downcase register))
                 (existing (gethash lower (evim-state-registers evim--state))))
            (puthash lower (append existing contents)
                     (evim-state-registers evim--state))
            ;; Sync to evil register (append)
            (evil-set-register lower
                               (concat (or (evil-get-register lower t) "")
                                       "\n" combined)))
        (puthash register contents (evim-state-registers evim--state))
        ;; Sync to evil register
        (evil-set-register register combined))
      (kill-new (car contents))
      (message "Yanked %d regions to register '%c'" (length contents) register))))

(defun evim-paste-from-register (register &optional after)
  "Paste from REGISTER at all cursor positions.
REGISTER is a character.  AFTER determines position."
  (interactive "cPaste from register: ")
  (when (evim-active-p)
    (let* ((reg (if (and (>= register ?A) (<= register ?Z))
                    (downcase register)
                  register))
           (contents (gethash reg (evim-state-registers evim--state))))
      (unless contents
        (user-error "Register '%c' is empty" register))
      (let* ((sorted-regions (evim--regions-by-position))
             (num-regions (length sorted-regions))
             (num-contents (length contents)))
        (evim--with-batched-changes
          ;; If in extend mode, delete first
          (when (evim-extend-mode-p)
            (dolist (region (evim--regions-by-position-reverse))
              (delete-region (marker-position (evim-region-beg region))
                             (marker-position (evim-region-end region)))))
          ;; Insert content
          (cl-loop for region in sorted-regions
                   for idx from 0
                   for content = (cond
                                  ((= num-contents num-regions)
                                   (nth idx contents))
                                  ((= num-contents 1)
                                   (car contents))
                                  (t
                                   (nth (mod idx num-contents) contents)))
                   do (save-excursion
                        (goto-char (marker-position (evim-region-beg region)))
                        (when after
                          (forward-char 1))
                        (insert content))))
        ;; After paste, cursor should be on last inserted char (like evil)
        ;; beg marker is now at end of inserted text, move back by 1
        (dolist (region sorted-regions)
          (let ((pos (marker-position (evim-region-beg region))))
            (when (> pos (point-min))
              (set-marker (evim-region-beg region) (1- pos))
              (set-marker (evim-region-end region) (1- pos))
              (set-marker (evim-region-anchor region) (1- pos))))))
      (setf (evim-state-mode evim--state) 'cursor)
      (evim--finalize-batch-edit t)
      (message "Pasted from register '%c'" register))))

(defun evim-delete-to-register (register)
  "Delete content of all regions and save to REGISTER."
  (interactive "cDelete to register: ")
  (when (evim-extend-mode-p)
    ;; First yank to register
    (evim-yank-to-register register)
    ;; Then delete
    (evim--with-batched-changes
      (dolist (region (evim--regions-by-position-reverse))
        (delete-region (marker-position (evim-region-beg region))
                       (marker-position (evim-region-end region)))))
    (evim--clamp-markers)
    (evim--check-and-merge-overlapping)
    (evim--enter-cursor-mode)
    (evim--update-keymap)))

;;; Multiline mode toggle (Phase 9.2)

(defun evim-toggle-multiline ()
  "Toggle multiline search mode.
When enabled, allows search patterns to span multiple lines."
  (interactive)
  (when evim--state
    (setf (evim-state-multiline-p evim--state)
          (not (evim-state-multiline-p evim--state)))
    (when-let ((pattern (car (evim-state-patterns evim--state))))
      (if (evim--restrict-active-p)
          (evim--show-match-preview-restricted pattern)
        (evim--show-match-preview pattern)))
    (message "Multiline mode: %s"
             (if (evim-state-multiline-p evim--state) "ON" "OFF"))))

;;; evil-surround integration (Phase 10.1)

;; Forward declarations for evil-surround functions
(declare-function evil-surround-region "evil-surround" (beg end type char &optional force-new-line))
(declare-function evil-surround-delete "evil-surround" (char &optional outer inner))
(declare-function evil-surround-change "evil-surround" (char &optional outer inner))

(defun evim--surround-available-p ()
  "Return t if evil-surround is available."
  (featurep 'evil-surround))

(defun evim-surround (char)
  "Surround all regions with CHAR.
Works in extend mode.  Reads a surround character and wraps all regions."
  (interactive (list (read-char "Surround with: ")))
  (unless (evim--surround-available-p)
    (user-error "Evil-surround is not loaded"))
  (when (evim-extend-mode-p)
    (evim--with-undo-amalgamate
      (let ((regions (evim--regions-by-position-reverse))
            (inhibit-modification-hooks t))
        (evim--without-post-command-hook
          (dolist (region regions)
            (let ((beg (marker-position (evim-region-beg region)))
                  (end (marker-position (evim-region-end region))))
              (evil-surround-region beg end 'inclusive char))))))
    (evim--clamp-markers)
    (evim--check-and-merge-overlapping)
    (evim--enter-cursor-mode)
    (evim--update-keymap)
    (message "Surrounded %d regions" (evim-region-count))))

(defun evim-operator-surround (count)
  "Surround operator: wait for motion, then surround at all cursors.
COUNT is optional prefix argument.
Examples: ysiw\" (surround word with \"), ys$) (surround to eol with parens)."
  (interactive "P")
  (unless (evim--surround-available-p)
    (user-error "Evil-surround is not loaded"))
  (when (evim-cursor-mode-p)
    (message "[EVIM] ys")
    (evim--run-surround-operator count)))

(defun evim--run-surround-operator (&optional prefix-count)
  "Run surround operator with a motion parsed from user input.
PREFIX-COUNT is an optional count from prefix argument."
  (let ((motion (evim--parse-motion ?s)))  ; ?s for ys+s = yss (line surround)
    (unless motion
      (message "Cancelled")
      (cl-return-from evim--run-surround-operator nil))
    ;; Read surround character
    (let ((char (read-char "Surround with: ")))
      (when (= char 27)  ; ESC
        (message "Cancelled")
        (cl-return-from evim--run-surround-operator nil))
      (let ((keys (plist-get motion :keys))
            (line-p (plist-get motion :line))
            (count (let ((motion-count (plist-get motion :count))
                         (pre (and prefix-count (prefix-numeric-value prefix-count))))
                     (cond
                      ((and pre motion-count) (* pre motion-count))
                      (pre pre)
                      (motion-count motion-count)
                      (t nil)))))
        (evim--with-undo-amalgamate
          (let ((regions (evim--regions-by-position-reverse))
                (inhibit-modification-hooks t))
            (evim--without-post-command-hook
              (dolist (region regions)
                (goto-char (evim--region-cursor-pos region))
                (let ((range (if line-p
                                 (evim--get-line-range count)
                               (evim--get-motion-range keys count))))
                  (when range
                    (let ((beg (car range))
                          (end (cadr range)))
                      (when (and beg end (> end beg))
                        (evil-surround-region beg end
                                             (if line-p 'line 'inclusive)
                                             char))))))))))
      (evim--clamp-markers)
      (evim--check-and-merge-overlapping)
      (evim--update-all-overlays)
      (when-let ((leader (evim--leader-region)))
        (goto-char (evim--region-cursor-pos leader)))
      (message "Surrounded %d regions" (evim-region-count)))))

(defun evim--get-line-range (&optional count)
  "Get range for COUNT lines starting from current position."
  (let* ((count (or count 1))
         (beg (line-beginning-position))
         (end (save-excursion
                (forward-line (1- count))
                (line-end-position))))
    (list beg end)))

(defun evim-delete-surround ()
  "Delete surrounding pair at all cursors.
Reads a surround character and deletes the pair around each cursor."
  (interactive)
  (unless (evim--surround-available-p)
    (user-error "Evil-surround is not loaded"))
  (when (evim-cursor-mode-p)
    (message "[EVIM] ds")
    (let ((char (read-char "Delete surround: ")))
      (when (= char 27)  ; ESC
        (message "Cancelled")
        (cl-return-from evim-delete-surround nil))
      (evim--with-undo-amalgamate
        (let ((regions (evim--regions-by-position-reverse))
              (inhibit-modification-hooks t))
          (evim--without-post-command-hook
            (dolist (region regions)
              (goto-char (evim--region-cursor-pos region))
              (evil-surround-delete char)
              ;; Update cursor position
              (evim--region-set-cursor-pos region (point))))))
      (evim--clamp-markers)
      (evim--check-and-merge-overlapping)
      (evim--update-all-overlays)
      (when-let ((leader (evim--leader-region)))
        (goto-char (evim--region-cursor-pos leader)))
      (message "Deleted surround at %d positions" (evim-region-count)))))

(defun evim-change-surround ()
  "Change surrounding pair at all cursors.
Reads old and new surround characters and changes the pair around each cursor."
  (interactive)
  (unless (evim--surround-available-p)
    (user-error "Evil-surround is not loaded"))
  (when (evim-cursor-mode-p)
    (message "[EVIM] cs")
    (let ((old-char (read-char "Change surround: ")))
      (when (= old-char 27)  ; ESC
        (message "Cancelled")
        (cl-return-from evim-change-surround nil))
      (let ((new-char (read-char (format "Change %c to: " old-char)))
            (num-regions (evim-region-count)))
        (when (= new-char 27)  ; ESC
          (message "Cancelled")
          (cl-return-from evim-change-surround nil))
        (evim--with-undo-amalgamate
          (let ((regions (evim--regions-by-position-reverse))
                (inhibit-modification-hooks t))
            (evim--without-post-command-hook
              (dolist (region regions)
                (goto-char (evim--region-cursor-pos region))
                ;; Push new-char to unread-command-events so
                ;; evil-surround-change will read it
                (setq unread-command-events (list new-char))
                (evil-surround-change old-char)
                (evim--region-set-cursor-pos region (point))))))
        (evim--clamp-markers)
        (evim--check-and-merge-overlapping)
        (evim--update-all-overlays)
        (when-let ((leader (evim--leader-region)))
          (goto-char (evim--region-cursor-pos leader)))
        (message "Changed surround at %d positions" num-regions)))))

;;; Global keybindings for activation

;;;###autoload
(defun evim-setup-global-keys (&optional old-leader-key)
  "Set up global keybindings for evim activation.
OLD-LEADER-KEY, if non-nil, is the previous leader key to unbind.
Uses `evim-leader-key' for prefix bindings."
  (when (and old-leader-key
             (not (string= old-leader-key evim-leader-key)))
    (evim--unbind-leader-bindings evil-normal-state-map old-leader-key
                                 evim--normal-leader-suffixes)
    (evim--unbind-leader-bindings evil-visual-state-map old-leader-key
                                 evim--visual-leader-suffixes))
  ;; Use define-key directly on evil state maps for reliable binding
  (define-key evil-normal-state-map (kbd "C-n") #'evim-find-word)
  (define-key evil-normal-state-map (kbd "<C-down>") #'evim-add-cursor-down)
  (define-key evil-normal-state-map (kbd "<C-up>") #'evim-add-cursor-up)
  (define-key evil-normal-state-map (kbd "<s-down-mouse-1>") #'evim--mouse-down-save-point)
  (define-key evil-normal-state-map (kbd "<s-mouse-1>") #'evim-add-cursor-at-click)
  ;; Reselect last (works when evim is not active)
  (evim--bind-leader evil-normal-state-map "g S" #'evim-reselect-last)
  ;; Visual mode bindings
  (define-key evil-visual-state-map (kbd "C-n") #'evim-find-word)
  (evim--bind-leader evil-visual-state-map "r" #'evim-toggle-restrict)
  (evim--bind-leader evil-visual-state-map "c" #'evim-visual-cursors)
  ;; Track point for mouse click handlers
  (add-hook 'post-command-hook #'evim--track-point))

(defun evim-rebind-leader ()
  "Rebind all leader-prefixed keys after changing `evim-leader-key'.
Call this after setting a new leader key."
  (interactive)
  (let ((old-leader-key evim--previous-leader-key))
    (evim--setup-leader-bindings old-leader-key)
    (evim-setup-global-keys old-leader-key)
    (setq evim--previous-leader-key evim-leader-key)))

(provide 'evim)
;;; evim.el ends here
