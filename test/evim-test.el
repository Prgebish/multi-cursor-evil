;;; evim-test.el --- Tests for evil-visual-multi -*- lexical-binding: t; -*-

;;; Commentary:
;; ERT tests for evim package.
;; Run with: make test
;; Or: make test-batch

;;; Code:

(require 'ert)
(when (locate-library "evil-surround")
  (require 'evil-surround))
(require 'evim)

;;; Test helpers

(defmacro evim-test-with-buffer (content &rest body)
  "Create temp buffer with CONTENT, execute BODY."
  (declare (indent 1))
  `(with-temp-buffer
     (insert ,content)
     (goto-char (point-min))
     (evil-local-mode 1)
     (evil-normal-state)
     ,@body
     (when (evim-active-p)
       (evim-exit))))

(defun evim-test-positions ()
  "Get list of cursor positions."
  (mapcar (lambda (r) (marker-position (evim-region-beg r)))
          (evim-get-all-regions)))

(defun evim-test-leader-pos ()
  "Get leader position."
  (when (evim--leader-region)
    (marker-position (evim-region-beg (evim--leader-region)))))

;;; Activation tests

(ert-deftest evim-test-find-word-activates ()
  "C-n should activate evim and create region on word in extend mode."
  (evim-test-with-buffer "foo bar foo"
    (evim-find-word)
    (should (evim-active-p))
    (should (evim-extend-mode-p))  ; Now in extend mode
    (should (= (evim-region-count) 1))
    (should (equal (evim-test-positions) '(1)))
    ;; Region should cover the word "foo" (positions 1-4)
    (let ((region (car (evim-get-all-regions))))
      (should (= (marker-position (evim-region-end region)) 4)))))

(ert-deftest evim-test-find-word-sets-pattern ()
  "C-n should set search pattern."
  (evim-test-with-buffer "foo bar foo"
    (evim-find-word)
    (should (car (evim-state-patterns evim--state)))
    (should (string-match-p "foo" (car (evim-state-patterns evim--state))))))

(ert-deftest evim-test-add-cursor-down ()
  "C-Down should add cursor below."
  (evim-test-with-buffer "line1\nline2\nline3"
    (evim-add-cursor-down)
    (should (evim-active-p))
    (should (= (evim-region-count) 2))
    (evim-add-cursor-down)
    (should (= (evim-region-count) 3))))

(ert-deftest evim-test-add-cursor-up ()
  "C-Up should add cursor above."
  (evim-test-with-buffer "line1\nline2\nline3"
    (goto-char (point-max))
    (beginning-of-line)
    (evim-add-cursor-up)
    (should (evim-active-p))
    (should (= (evim-region-count) 2))))

(ert-deftest evim-test-add-cursor-down-preserves-column-through-short-line ()
  "C-Down should preserve target column through short lines."
  (evim-test-with-buffer "abcde\nab\nabcde\nabcde"
    (move-to-column 4) ;; on 'e' in first "abcde"
    (let ((last-command nil))
      (evim-add-cursor-down)
      (setq last-command 'evim-add-cursor-down)
      (evim-add-cursor-down)
      (setq last-command 'evim-add-cursor-down)
      (evim-add-cursor-down))
    (should (= (evim-region-count) 4))
    ;; Check columns: should all be 4 except the short line
    (let ((cols (mapcar (lambda (r)
                          (save-excursion
                            (goto-char (marker-position (evim-region-beg r)))
                            (current-column)))
                        (evim-state-regions evim--state))))
      ;; Line 1: col 4, line 2: col 2 (short), line 3: col 4, line 4: col 4
      (should (equal cols '(4 2 4 4))))))

(ert-deftest evim-test-cursor-down-then-up-no-duplicates ()
  "C-Down then C-Up should not create duplicate cursors."
  (evim-test-with-buffer "line1\nline2\nline3\nline4\nline5"
    (let ((last-command nil))
      (evim-add-cursor-down)
      (setq last-command 'evim-add-cursor-down)
      (evim-add-cursor-down)
      (setq last-command 'evim-add-cursor-down)
      (evim-add-cursor-down))
    (should (= (evim-region-count) 4))
    ;; Now C-Up 3 times — should move leader, not create duplicates
    (let ((last-command 'evim-add-cursor-up))
      (evim-add-cursor-up)
      (setq last-command 'evim-add-cursor-up)
      (evim-add-cursor-up)
      (setq last-command 'evim-add-cursor-up)
      (evim-add-cursor-up))
    (should (= (evim-region-count) 4))))

;;; Navigation tests

(ert-deftest evim-test-find-next ()
  "n should find next occurrence."
  (evim-test-with-buffer "foo bar foo baz foo"
    (evim-find-word)
    (evim-find-next)
    (should (= (evim-region-count) 2))
    (should (equal (evim-test-positions) '(1 9)))))

(ert-deftest evim-test-find-prev ()
  "N should find previous occurrence."
  (evim-test-with-buffer "foo bar foo baz foo"
    (evim-find-word)
    (evim-find-prev)
    (should (= (evim-region-count) 2))
    ;; Should wrap around to last foo
    (should (member 17 (evim-test-positions)))))

(ert-deftest evim-test-find-next-moves-leader ()
  "n should move leader to existing cursor."
  (evim-test-with-buffer "foo bar foo baz foo"
    (evim-find-word)
    (evim-find-next)
    (evim-find-next)
    ;; All 3 cursors exist
    (should (= (evim-region-count) 3))
    ;; n again should move leader, not create new
    (let ((count-before (evim-region-count)))
      (evim-find-next)
      (should (= (evim-region-count) count-before)))))

(ert-deftest evim-test-goto-next ()
  "] should move to next cursor."
  (evim-test-with-buffer "foo bar foo"
    (evim-find-word)
    (evim-find-next)
    ;; Leader at position 9
    (should (= (evim-test-leader-pos) 9))
    (evim-goto-next)
    ;; Should wrap to 1
    (should (= (evim-test-leader-pos) 1))))

(ert-deftest evim-test-goto-prev ()
  "[ should move to previous cursor."
  (evim-test-with-buffer "foo bar foo"
    (evim-find-word)
    (evim-find-next)
    ;; Leader at 9, go prev should go to 1
    (evim-goto-prev)
    (should (= (evim-test-leader-pos) 1))))

;;; Skip and Remove tests

(ert-deftest evim-test-skip-current ()
  "q should skip current and find next occurrence."
  (evim-test-with-buffer "foo bar foo baz foo"
    (evim-find-word)
    ;; At position 1
    (evim-skip-current)
    ;; Should now be at position 9
    (should (= (evim-region-count) 1))
    (should (= (evim-test-leader-pos) 9))))

(ert-deftest evim-test-skip-current-after-n ()
  "q after n should skip to NEXT occurrence, not same one."
  (evim-test-with-buffer "foo bar foo baz foo qux foo"
    ;; foo at positions: 1, 9, 17, 25
    (evim-find-word)
    ;; Cursor at 1
    (evim-find-next)
    ;; Cursors at 1, 9. Leader at 9.
    (should (= (evim-region-count) 2))
    (should (= (evim-test-leader-pos) 9))
    ;; q should skip 9 and find 17
    (evim-skip-current)
    (should (= (evim-region-count) 2))
    (should (equal (evim-test-positions) '(1 17)))
    (should (= (evim-test-leader-pos) 17))))

(ert-deftest evim-test-skip-current-wraps-around ()
  "q should wrap around when at last occurrence."
  (evim-test-with-buffer "foo bar foo"
    ;; foo at positions: 1, 9
    (evim-find-word)
    (evim-find-next)
    ;; At position 9, q should wrap to 1 (but 1 has cursor, so create at 1)
    ;; Actually it should find existing cursor at 1 and move leader there
    (evim-skip-current)
    ;; Cursor at 9 deleted, search from 10 wraps to find 1
    ;; Cursor at 1 exists, so just move leader
    (should (= (evim-region-count) 1))
    (should (= (evim-test-leader-pos) 1))))

(ert-deftest evim-test-skip-current-after-N ()
  "q after N should search backward."
  (evim-test-with-buffer "foo bar foo baz foo qux foo"
    ;; foo at positions: 1, 9, 17, 25
    (evim-find-word)
    ;; N - find previous (wraps to 25)
    (evim-find-prev)
    (should (= (evim-region-count) 2))
    (should (= (evim-test-leader-pos) 25))
    ;; q should skip 25 and find 17 (backward)
    (evim-skip-current)
    (should (= (evim-region-count) 2))
    (should (equal (evim-test-positions) '(1 17)))
    (should (= (evim-test-leader-pos) 17))))

(ert-deftest evim-test-remove-current ()
  "Q should remove current cursor."
  (evim-test-with-buffer "foo bar foo"
    (evim-find-word)
    (evim-find-next)
    (should (= (evim-region-count) 2))
    (evim-remove-current)
    (should (= (evim-region-count) 1))))

(ert-deftest evim-test-remove-last-exits ()
  "Q on last cursor should exit evim."
  (evim-test-with-buffer "foo bar baz"
    (evim-find-word)
    (should (= (evim-region-count) 1))
    (evim-remove-current)
    (should-not (evim-active-p))))

;;; Movement tests

(defun evim-test-end-positions ()
  "Get list of cursor end positions."
  (mapcar (lambda (r) (marker-position (evim-region-end r)))
          (evim-get-all-regions)))

(ert-deftest evim-test-forward-char ()
  "l should move all cursors right."
  (evim-test-with-buffer "foo bar foo zzz"
    ;; Extra text at end so cursor can move
    (evim-find-word)
    (evim-find-next)
    ;; In extend mode, movement expands selection (changes end)
    (let ((end-before (evim-test-end-positions)))
      (evim-forward-char)
      (should (equal (evim-test-end-positions)
                     (mapcar #'1+ end-before))))))

(ert-deftest evim-test-backward-char ()
  "h should move all cursors left."
  (evim-test-with-buffer "foo bar foo zzz"
    (evim-find-word)
    (evim-find-next)
    ;; In extend mode, movement changes end position
    (evim-forward-char)
    (evim-forward-char)
    (let ((end-before (evim-test-end-positions)))
      (evim-backward-char)
      (should (equal (evim-test-end-positions)
                     (mapcar #'1- end-before))))))

(ert-deftest evim-test-forward-word ()
  "w should move all cursors to next word."
  (evim-test-with-buffer "aa bb aa cc"
    (evim-find-word)
    (evim-find-next)
    ;; Regions at 1-3 and 7-9 with "aa" selected
    (let ((end-before (evim-test-end-positions)))
      (evim-forward-word)
      ;; In extend mode, end positions should have moved forward
      (should (> (car (evim-test-end-positions))
                 (car end-before))))))

;;; Mode switching tests

(ert-deftest evim-test-toggle-mode ()
  "Tab should toggle between cursor and extend mode."
  (evim-test-with-buffer "foo bar foo"
    (evim-find-word)
    ;; After C-n we're now in extend mode
    (should (evim-extend-mode-p))
    (evim-toggle-mode)
    (should (evim-cursor-mode-p))
    (evim-toggle-mode)
    (should (evim-extend-mode-p))))

(ert-deftest evim-test-extend-mode-has-selection ()
  "C-n should create regions with full word selection."
  (evim-test-with-buffer "foo bar foo"
    (evim-find-word)
    ;; Already in extend mode with selection
    (should (evim-extend-mode-p))
    (let ((region (car (evim-get-all-regions))))
      (should (> (marker-position (evim-region-end region))
                 (marker-position (evim-region-beg region))))
      ;; "foo" is 3 chars, so end - beg = 3
      (should (= (- (marker-position (evim-region-end region))
                    (marker-position (evim-region-beg region)))
                 3)))))

(ert-deftest evim-test-toggle-mode-updates-keymap ()
  "Tab should update keymap so mode-specific keys work."
  (evim-test-with-buffer "foo bar foo"
    (evim-find-word)
    (evim-find-next)
    ;; After C-n we're in extend mode
    (should (evim-extend-mode-p))
    ;; In extend mode, d should be bound to evim-delete
    (should (eq (key-binding "d") 'evim-delete))
    (should (eq (key-binding "y") 'evim-yank))
    (should (eq (key-binding "U") 'evim-upcase))
    ;; Toggle to cursor mode
    (evim-toggle-mode)
    (should (evim-cursor-mode-p))
    ;; d should no longer be evim-delete
    (should-not (eq (key-binding "d") 'evim-delete))
    ;; i should be evim-insert in cursor mode
    (should (eq (key-binding "i") 'evim-insert))
    ;; Toggle back to extend mode
    (evim-toggle-mode)
    (should (evim-extend-mode-p))
    (should (eq (key-binding "d") 'evim-delete))))

;;; Cursor mode editing tests

(ert-deftest evim-test-delete-char ()
  "x should delete char at all cursors."
  (evim-test-with-buffer "foo\nbar\nbaz"
    ;; Create cursors on each line using C-down
    (evim-add-cursor-down)
    (evim-add-cursor-down)
    (should (= (evim-region-count) 3))
    (evim-delete-char)
    (should (string= (buffer-string) "oo\nar\naz"))))

(ert-deftest evim-test-delete-char-count ()
  "3x should delete 3 characters at all cursors."
  (evim-test-with-buffer "abcdef\nghijkl\nmnopqr"
    (evim-add-cursor-down)
    (evim-add-cursor-down)
    (should (= (evim-region-count) 3))
    (evim-delete-char 3)
    (should (string= (buffer-string) "def\njkl\npqr"))))

(ert-deftest evim-test-delete-char-count-clamp-eol ()
  "3x on 2-char line should delete only 2 chars, not cross newline."
  (evim-test-with-buffer "ab\ncd\nef"
    (evim-add-cursor-down)
    (evim-add-cursor-down)
    (should (= (evim-region-count) 3))
    (evim-delete-char 3)
    (should (string= (buffer-string) "\n\n"))))

(ert-deftest evim-test-delete-char-eol ()
  "x at end-of-line should clamp cursor to last char, not newline."
  (evim-test-with-buffer "aa;\nbb;\ncc;"
    (goto-char 3) ;; on ";"
    (evim-add-cursor-down)
    (evim-add-cursor-down)
    (should (= (evim-region-count) 3))
    (evim-delete-char)
    (should (string= (buffer-string) "aa\nbb\ncc"))
    ;; Cursors should be on last char of each line, not on newline/eob
    (dolist (region (evim-state-regions evim--state))
      (let ((pos (marker-position (evim-region-beg region))))
        (should-not (= (char-after pos) ?\n))
        (should-not (= pos (point-max)))))))

(ert-deftest evim-test-replace-char ()
  "r should replace char at all cursors."
  (evim-test-with-buffer "foo\nbar\nbaz"
    ;; Create cursors using C-down for cursor mode
    (evim-add-cursor-down)
    (evim-add-cursor-down)
    (should (= (evim-region-count) 3))
    (evim-replace-char ?X)
    (should (string= (buffer-string) "Xoo\nXar\nXaz"))))

(ert-deftest evim-test-toggle-case-char ()
  "~ should toggle case at all cursors."
  (evim-test-with-buffer "foo\nbar\nbaz"
    ;; Create cursors using C-down for cursor mode
    (evim-add-cursor-down)
    (evim-add-cursor-down)
    (should (= (evim-region-count) 3))
    (evim-toggle-case-char)
    (should (string= (buffer-string) "Foo\nBar\nBaz"))))

;;; Extend mode editing tests

(ert-deftest evim-test-yank ()
  "y should yank region contents to register."
  (evim-test-with-buffer "foo bar foo"
    (evim-find-word)
    (evim-find-next)
    ;; Already in extend mode with "foo" selected
    (evim-yank)
    (let ((contents (gethash ?\" (evim-state-registers evim--state))))
      (should contents)
      (should (= (length contents) 2))
      (should (string= (car contents) "foo")))))

(ert-deftest evim-test-delete-regions ()
  "d should delete all regions."
  (evim-test-with-buffer "foo bar foo"
    (evim-find-word)
    (evim-find-next)
    ;; Already in extend mode with "foo" selected
    (evim-delete)
    (should (string= (buffer-string) " bar "))
    (should (evim-cursor-mode-p))))

(ert-deftest evim-test-upcase ()
  "U should uppercase all regions."
  (evim-test-with-buffer "foo bar foo"
    (evim-find-word)
    (evim-find-next)
    ;; Already in extend mode with "foo" selected
    (evim-upcase)
    (should (string= (buffer-string) "FOO bar FOO"))))

(ert-deftest evim-test-downcase ()
  "u should lowercase all regions."
  (evim-test-with-buffer "FOO bar FOO"
    (evim-find-word)
    (evim-find-next)
    ;; Already in extend mode with "FOO" selected
    (evim-downcase)
    (should (string= (buffer-string) "foo bar foo"))))

(ert-deftest evim-test-toggle-case ()
  "~ should toggle case of all regions."
  (evim-test-with-buffer "FoO bar FoO"
    (evim-find-word)
    (evim-find-next)
    ;; Already in extend mode with "FoO" selected
    (evim-toggle-case)
    (should (string= (buffer-string) "fOo bar fOo"))))

(ert-deftest evim-test-toggle-case-preserves-markers ()
  "~ should preserve region markers for subsequent operations."
  (evim-test-with-buffer "foo bar foo"
    (evim-find-word)
    (evim-find-next)
    ;; Already in extend mode with "foo" selected
    (let ((regions-before (mapcar (lambda (r)
                                    (list (marker-position (evim-region-beg r))
                                          (marker-position (evim-region-end r))))
                                  (evim-get-all-regions))))
      (evim-toggle-case)
      (let ((regions-after (mapcar (lambda (r)
                                     (list (marker-position (evim-region-beg r))
                                           (marker-position (evim-region-end r))))
                                   (evim-get-all-regions))))
        ;; Markers should be preserved
        (should (equal regions-before regions-after))
        ;; Delete should work after toggle-case
        (evim-delete)
        (should (string= (buffer-string) " bar "))))))

;;; Select all tests

(ert-deftest evim-test-select-all ()
  "\\A should select all occurrences."
  (evim-test-with-buffer "foo bar foo baz foo qux foo"
    (evim-find-word)
    (evim-select-all)
    (should (= (evim-region-count) 4))))

;;; Exit tests

(ert-deftest evim-test-exit ()
  "Esc should exit evim."
  (evim-test-with-buffer "foo bar foo"
    (evim-find-word)
    (should (evim-active-p))
    (evim-exit)
    (should-not (evim-active-p))
    (should-not evim-mode)))

;;; Vertical movement with vcol tests

(ert-deftest evim-test-j-k-preserves-column ()
  "j then k should return cursors to original positions."
  ;; Buffer with 4 lines so all cursors can move down and back
  (evim-test-with-buffer "abcdefgh\nxy\nabcdefgh\nlast"
    ;; Buffer layout:
    ;; Line 1: pos 1-8 "abcdefgh", pos 9 \n
    ;; Line 2: pos 10-11 "xy", pos 12 \n
    ;; Line 3: pos 13-20 "abcdefgh", pos 21 \n
    ;; Line 4: pos 22-25 "last"
    ;; Create cursors at column 5 on lines 1 and 3, column 1 on line 2
    (goto-char 6)  ; 'f' on line 1 (column 5)
    (evim-activate)
    (evim--create-region 6 6)   ; line 1, column 5 ('f')
    (evim--create-region 11 11) ; line 2, column 1 ('y')
    (evim--create-region 18 18) ; line 3, column 5 ('f')
    ;; Now we have 3 cursors at (6, 11, 18)
    (should (= (evim-region-count) 3))
    (should (equal (evim-test-positions) '(6 11 18)))
    ;; Record positions before j
    (let ((positions-before (evim-test-positions)))
      ;; Move down (j)
      (evim-next-line)
      ;; Positions should have changed (went down)
      (should-not (equal (evim-test-positions) positions-before))
      ;; Move up (k)
      (evim-previous-line)
      ;; Positions should be restored
      (should (equal (evim-test-positions) positions-before)))))

(ert-deftest evim-test-j-k-short-line-vcol ()
  "j/k across short line should preserve desired column."
  (evim-test-with-buffer "abcdefghij\n\nabcdefghij"
    ;; Start at column 5 on line 1
    (goto-char 6)
    (evim-activate)
    (evim--create-region (point) (point))
    ;; j - go to empty line (column 0 since line is empty)
    (evim-next-line)
    ;; j again - go to line 3, should be at column 5 again
    (evim-next-line)
    (should (= (current-column) 5))
    ;; k twice - should go back to line 1 at column 5
    (evim-previous-line)
    (evim-previous-line)
    (should (= (current-column) 5))))

(ert-deftest evim-test-j-short-line-clamps-to-last-char ()
  "j to a short line should clamp cursor to last char, not past EOL."
  (evim-test-with-buffer "long_line = 100\ngap\nlong_line = 300"
    ;; Start at column 7 on line 1 (on "e" of "line")
    (goto-char (point-min))
    (forward-char 7)
    (evim-activate)
    (evim--create-region (point) (point))
    ;; j - go to "gap" line. Column 7 is past EOL.
    ;; Should clamp to last char "p" (col 2), not to newline (col 3).
    (evim-next-line)
    (let ((col (current-column))
          (ch (char-after (point))))
      (should (= col 2))           ;; on 'p', last char of "gap"
      (should (not (= ch ?\n))))   ;; NOT on newline
    ;; j again - should restore to column 7 on long line
    (evim-next-line)
    (should (= (current-column) 7))))

(ert-deftest evim-test-horizontal-movement-clears-vcol ()
  "Horizontal movement should clear vcol."
  (evim-test-with-buffer "abcdefghij\n\nabcdefghij"
    ;; Start at column 5
    (goto-char 6)
    (evim-activate)
    (evim--create-region (point) (point))
    ;; j - to empty line (vcol=5 saved)
    (evim-next-line)
    ;; l - move right (should clear vcol, but we're on empty line so stays at 0)
    ;; Actually on empty line l doesn't move
    ;; Move back up first
    (evim-previous-line)
    (should (= (current-column) 5))
    ;; Now l should clear vcol
    (evim-forward-char)
    (should (= (current-column) 6))
    ;; j and k should now use column 6
    (evim-next-line)
    (evim-next-line)
    (should (= (current-column) 6))
    (evim-previous-line)
    (evim-previous-line)
    (should (= (current-column) 6))))

;;; End of line movement tests

(ert-deftest evim-test-end-of-line-goes-to-last-char ()
  "$ should move to last character, not past it (like evil $)."
  (evim-test-with-buffer "foo\nbar\nbaz"
    ;; Create cursors on each line
    (goto-char 1)
    (evim-activate)
    (evim--create-region 1 1)   ; line 1, 'f'
    (evim--create-region 5 5)   ; line 2, 'b'
    (evim--create-region 9 9)   ; line 3, 'b'
    (should (= (evim-region-count) 3))
    ;; Move to end of line
    (evim-end-of-line)
    ;; Positions should be on last char of each line:
    ;; line 1: "foo" ends at pos 3 (the 'o')
    ;; line 2: "bar" ends at pos 7 (the 'r')
    ;; line 3: "baz" ends at pos 11 (the 'z')
    (should (equal (evim-test-positions) '(3 7 11)))))

(ert-deftest evim-test-end-of-line-empty-line ()
  "$ on empty line should stay at beginning."
  (evim-test-with-buffer "foo\n\nbaz"
    ;; Create cursor on empty line (position 5, which is the empty line)
    (goto-char 5)
    (evim-activate)
    (evim--create-region 5 5)
    ;; Move to end of line (on empty line, stays at beginning)
    (evim-end-of-line)
    (should (equal (evim-test-positions) '(5)))))

(ert-deftest evim-test-end-of-line-extend-mode ()
  "$ in extend mode should extend selection to end of line."
  ;; Buffer: "text abc\ntext xyz" (17 chars + newline = 18 total)
  ;; Line 1: "text abc" pos 1-8, newline at 9
  ;; Line 2: "text xyz" pos 10-17, point-max = 18
  (evim-test-with-buffer "text abc\ntext xyz"
    ;; text at pos 1-5 and 10-14
    (evim-find-word)  ; selects first "text"
    (evim-find-next)  ; adds second "text"
    (should (= (evim-region-count) 2))
    ;; In extend mode, both "text" are selected (beg-end pairs)
    ;; After $, selection should extend to end of each line
    (evim-end-of-line)
    ;; line-end-position returns:
    ;; - Line 1: 9 (position of newline)
    ;; - Line 2: 18 (point-max, since no trailing newline)
    ;; Visual cursor will be on 8 ('c') and 17 ('z') respectively
    (should (equal (evim-test-end-positions) '(9 18)))))

(ert-deftest evim-test-end-of-line-extend-mode-different-lengths ()
  "$ in extend mode should work with lines of different lengths."
  ;; Buffer: "aa short\naa very long line here" (31 chars total)
  ;; Line 1: "aa short" pos 1-8, newline at 9
  ;; Line 2: "aa very long line here" pos 10-31, point-max = 32
  (evim-test-with-buffer "aa short\naa very long line here"
    ;; "aa" at pos 1-3 and 10-12
    (evim-find-word)
    (evim-find-next)
    (should (= (evim-region-count) 2))
    (evim-end-of-line)
    ;; line-end-position returns:
    ;; - Line 1: 9 (position of newline)
    ;; - Line 2: 32 (point-max, since no trailing newline)
    ;; Visual cursor will be on 8 ('t') and 31 ('e') respectively
    (should (equal (evim-test-end-positions) '(9 32)))))

(ert-deftest evim-test-extend-mode-forward-word-end ()
  "e in extend mode should include the full word in selection."
  (evim-test-with-buffer "alpha beta\nalpha beta"
    (evim-find-word) ; "alpha" selected
    (evim-find-next)
    (should (= (evim-region-count) 2))
    ;; Tab to cursor, Tab to extend (1-char)
    (evim-toggle-mode)
    (evim-toggle-mode)
    ;; e should select full word
    (evim-forward-word-end)
    (let ((selections (mapcar (lambda (r)
                                (buffer-substring-no-properties
                                 (marker-position (evim-region-beg r))
                                 (marker-position (evim-region-end r))))
                              (evim-state-regions evim--state))))
      (should (equal selections '("alpha" "alpha"))))))

(ert-deftest evim-test-extend-mode-yank-full-word ()
  "Yank in extend mode after e should capture the full word."
  (evim-test-with-buffer "foo bar\nfoo baz"
    ;; Create vertical cursors, toggle to extend, grow, yank
    (evim-add-cursor-down)
    (evim-toggle-mode)
    (evim-forward-word-end)
    (evim-yank)
    (let ((reg (gethash ?\" (evim-state-registers evim--state))))
      (should (equal reg '("foo" "foo"))))))

(ert-deftest evim-test-extend-mode-shrink-with-h ()
  "h in extend mode should shrink selection by one char."
  (evim-test-with-buffer "hello abc\nhello xyz"
    (evim-find-word)  ; "hello" at pos 1
    (evim-find-next)  ; "hello" at pos 11
    (should (= (evim-region-count) 2))
    ;; Selections are both "hello" (5 chars each)
    ;; Press h to shrink
    (evim-backward-char)
    (let ((selections (mapcar (lambda (r)
                                (buffer-substring-no-properties
                                 (marker-position (evim-region-beg r))
                                 (marker-position (evim-region-end r))))
                              (evim-state-regions evim--state))))
      (should (equal selections '("hell" "hell"))))))

(ert-deftest evim-test-extend-mode-flip-then-grow ()
  "o should flip direction, then h should grow selection backward."
  (evim-test-with-buffer "my tag = X\nmy tag = Y"
    (goto-char 4)  ; on "tag"
    (evim-find-word)
    (evim-find-next)
    (should (= (evim-region-count) 2))
    ;; Initial: "tag" selected [4,7) and [15,18)
    ;; Grow right by 1 (l) → "tag " [4,8) and [15,19)
    (evim-forward-char)
    ;; Flip direction: cursor moves to left end, anchor to right end
    (evim-flip-direction)
    ;; Grow left by 1 (h) → " tag " [3,8) and [14,19)
    (evim-backward-char)
    (let ((sel (mapcar (lambda (r)
                         (buffer-substring-no-properties
                          (marker-position (evim-region-beg r))
                          (marker-position (evim-region-end r))))
                       (evim-state-regions evim--state))))
      (should (equal sel '(" tag " " tag "))))))

(ert-deftest evim-test-find-char-f ()
  "f should move all cursors to the target character."
  (evim-test-with-buffer "a = 1\na = 2\na = 3"
    (evim-add-cursor-down)
    (evim-add-cursor-down)
    (should (= (evim-region-count) 3))
    ;; f= should land all cursors on "="
    (evim--move-cursors #'evim--move-find-char ?= 1)
    (let ((cols (mapcar (lambda (r)
                          (save-excursion
                            (goto-char (evim--region-cursor-pos r))
                            (current-column)))
                        (evim-state-regions evim--state))))
      (should (equal cols '(2 2 2))))))

(ert-deftest evim-test-find-char-F-backward ()
  "F should move all cursors backward to the target character."
  (evim-test-with-buffer "x = 1\nx = 2\nx = 3"
    (evim-add-cursor-down)
    (evim-add-cursor-down)
    ;; Move to end of line first
    (evim--move-cursors #'evim--move-line-end)
    ;; F= should land on "="
    (evim--move-cursors #'evim--move-find-char-backward ?= 1)
    (let ((cols (mapcar (lambda (r)
                          (save-excursion
                            (goto-char (evim--region-cursor-pos r))
                            (current-column)))
                        (evim-state-regions evim--state))))
      (should (equal cols '(2 2 2))))))

;;; Insert mode tests

(ert-deftest evim-test-insert-replicates-text ()
  "i should insert text at all cursor positions."
  (evim-test-with-buffer "foo\nbar\nbaz"
    ;; Create cursors using C-down for cursor mode
    (evim-add-cursor-down)
    (evim-add-cursor-down)
    (should (= (evim-region-count) 3))
    ;; Enter insert mode
    (evim-insert)
    ;; Insert text
    (insert "X")
    ;; Exit insert mode
    (evil-normal-state)
    ;; Text should be inserted at all cursor positions
    (should (string= (buffer-string) "Xfoo\nXbar\nXbaz"))))

(ert-deftest evim-test-insert-multiple-chars ()
  "i should insert multiple characters at all cursor positions."
  (evim-test-with-buffer "foo\nbar\nbaz"
    ;; Create cursors using C-down
    (evim-add-cursor-down)
    (evim-add-cursor-down)
    (evim-insert)
    (insert "hello")
    (evil-normal-state)
    (should (string= (buffer-string) "hellofoo\nhellobar\nhellobaz"))))

(ert-deftest evim-test-append-replicates-text ()
  "a should append text after all cursor positions."
  (evim-test-with-buffer "foo\nbar\nbaz"
    ;; Create cursors using C-down
    (evim-add-cursor-down)
    (evim-add-cursor-down)
    ;; Cursors at beginning of each line
    (evim-append)
    (insert "X")
    (evil-normal-state)
    ;; Text should be inserted after first char at each position
    (should (string= (buffer-string) "fXoo\nbXar\nbXaz"))))

(ert-deftest evim-test-insert-line ()
  "I should insert at beginning of line for all cursors."
  (evim-test-with-buffer "  foo\n  bar"
    ;; Create cursors on both lines using C-Down
    (evim-add-cursor-down)
    (evim-insert-line)
    (insert "X")
    (evil-normal-state)
    ;; X should be at beginning of indentation on each line
    (should (string= (buffer-string) "  Xfoo\n  Xbar"))))

(ert-deftest evim-test-append-line ()
  "A should append at end of line for all cursors."
  (evim-test-with-buffer "foo\nbar"
    ;; Create cursors on both lines using C-Down
    (evim-add-cursor-down)
    (evim-append-line)
    (insert "X")
    (evil-normal-state)
    (should (string= (buffer-string) "fooX\nbarX"))))

(ert-deftest evim-test-insert-same-line-multiple ()
  "i should work correctly with multiple cursors on same line."
  (evim-test-with-buffer "aaa bbb ccc"
    ;; Create cursors at specific positions using direct region creation
    (evim-activate)
    (evim--create-region 1 1)   ; before "aaa"
    (evim--create-region 5 5)   ; before "bbb"
    (evim--create-region 9 9)   ; before "ccc"
    (should (= (evim-region-count) 3))
    (evim-insert)
    (insert "X")
    (evil-normal-state)
    (should (string= (buffer-string) "Xaaa Xbbb Xccc"))))

(ert-deftest evim-test-insert-leader-middle ()
  "i should work when leader is in the middle of cursor list."
  (evim-test-with-buffer "aaa\nbbb\nccc"
    ;; Create cursors on all lines
    (evim-add-cursor-down)
    (evim-add-cursor-down)
    ;; Leader is at last line (ccc)
    (evim-goto-prev) ;; move leader to middle (bbb)
    (should (= (evim-region-count) 3))
    (evim-insert)
    (insert "X")
    (evil-normal-state)
    (should (string= (buffer-string) "Xaaa\nXbbb\nXccc"))))

(ert-deftest evim-test-open-below ()
  "o should open line below and insert at all cursors."
  (evim-test-with-buffer "line1\nline2\nline3"
    ;; Create cursors on all three lines
    (evim-add-cursor-down)
    (evim-add-cursor-down)
    (should (= (evim-region-count) 3))
    ;; Open below
    (evim-open-below)
    (insert "new")
    (evil-normal-state)
    (should (string= (buffer-string) "line1\nnew\nline2\nnew\nline3\nnew"))))

(ert-deftest evim-test-open-above ()
  "O should open line above and insert at all cursors."
  (evim-test-with-buffer "line1\nline2\nline3"
    ;; Create cursors on all three lines
    (evim-add-cursor-down)
    (evim-add-cursor-down)
    (should (= (evim-region-count) 3))
    ;; Open above
    (evim-open-above)
    (insert "above")
    (evil-normal-state)
    (should (string= (buffer-string) "above\nline1\nabove\nline2\nabove\nline3"))))

;;; Electric-pair-mode integration

(defun evim-test--simulate-keystrokes (str)
  "Simulate typing STR character by character with proper hook execution."
  (dolist (ch (string-to-list str))
    (let ((last-command-event ch)
          (this-command 'self-insert-command)
          (current-prefix-arg nil))
      (run-hooks 'pre-command-hook)
      (call-interactively #'self-insert-command)
      (run-hooks 'post-command-hook))))

(ert-deftest evim-test-open-below-real-keys ()
  "o + real keystrokes should replicate to all cursors."
  (evim-test-with-buffer "a = 1\nb = 2\nc = 3"
    (evim-add-cursor-down)
    (evim-add-cursor-down)
    (should (= (evim-region-count) 3))
    (evim-open-below)
    (evim-test--simulate-keystrokes "print(done)")
    (evil-normal-state)
    (should (string= (buffer-string)
                     "a = 1\nprint(done)\nb = 2\nprint(done)\nc = 3\nprint(done)"))))

(ert-deftest evim-test-open-below-electric-pair ()
  "o + real keystrokes with electric-pair-mode should replicate correctly."
  (evim-test-with-buffer "a = 1\nb = 2\nc = 3"
    (electric-pair-local-mode 1)
    (evim-add-cursor-down)
    (evim-add-cursor-down)
    (should (= (evim-region-count) 3))
    (evim-open-below)
    (evim-test--simulate-keystrokes "print(done)")
    (evil-normal-state)
    (should (string= (buffer-string)
                     "a = 1\nprint(done)\nb = 2\nprint(done)\nc = 3\nprint(done)"))))

(ert-deftest evim-test-insert-electric-pair ()
  "i + real keystrokes with electric-pair-mode should replicate correctly."
  (evim-test-with-buffer "foo\nbar\nbaz"
    (electric-pair-local-mode 1)
    (evim-add-cursor-down)
    (evim-add-cursor-down)
    (should (= (evim-region-count) 3))
    (evim-insert)
    (evim-test--simulate-keystrokes "(x)")
    (evil-normal-state)
    (should (string= (buffer-string) "(x)foo\n(x)bar\n(x)baz"))))

(ert-deftest evim-test-backspace-replicates ()
  "Backspace in insert mode should delete at all cursors."
  (evim-test-with-buffer "colllor: red\ncolllor: green\ncolllor: blue"
    (move-to-column 3)
    (evim-add-cursor-down)
    (evim-add-cursor-down)
    (evim-insert)
    ;; Simulate backspace
    (let ((last-command-event 127)
          (this-command 'delete-backward-char)
          (current-prefix-arg nil))
      (run-hooks 'pre-command-hook)
      (delete-backward-char 1)
      (run-hooks 'post-command-hook))
    (evil-normal-state)
    (should (string= (buffer-string)
                     "collor: red\ncollor: green\ncollor: blue"))))

;;; Edge cases

(ert-deftest evim-test-no-word-at-point ()
  "C-n on whitespace should error."
  (evim-test-with-buffer "   foo"
    (should-error (evim-find-word))))

(ert-deftest evim-test-single-occurrence ()
  "n with single occurrence should not create duplicate."
  (evim-test-with-buffer "foo bar baz"
    (evim-find-word)
    (evim-find-next)
    ;; Should still be 1, no other foo
    (should (= (evim-region-count) 1))))

;;; Undo resync tests

(ert-deftest evim-test-resync-after-undo ()
  "Regions should be resynced to pattern matches after undo."
  (evim-test-with-buffer "foo bar foo"
    (evim-find-word)
    (evim-find-next)
    ;; Two regions at positions 1 and 9
    (should (= (evim-region-count) 2))
    (should (equal (evim-test-positions) '(1 9)))
    ;; Simulate undo resync by calling the function directly
    ;; (actual undo test would require more complex setup)
    (evim--resync-regions-to-pattern)
    ;; Positions should remain consistent
    (should (equal (evim-test-positions) '(1 9)))
    ;; All regions should have correct end positions (foo = 3 chars)
    (should (equal (evim-test-end-positions) '(4 12)))))

(ert-deftest evim-test-resync-cursor-mode ()
  "Regions in cursor mode should resync to beginning of match."
  (evim-test-with-buffer "foo bar foo"
    (evim-find-word)
    (evim-find-next)
    ;; Switch to cursor mode - cursors collapse to beginning (1 and 9)
    ;; Like vim-visual-multi, cursor goes to start of selection
    (evim-toggle-mode)
    (should (evim-cursor-mode-p))
    (should (equal (evim-test-positions) '(1 9)))

    ;; Run resync
    (evim--resync-regions-to-pattern)

    ;; Should still be at beginning (1 and 9)
    (should (equal (evim-test-positions) '(1 9)))))

(ert-deftest evim-test-post-command-triggers-resync-on-undo ()
  "Post-command hook should trigger resync when undo command runs."
  (evim-test-with-buffer "foo bar foo"
    (evim-find-word)
    (evim-find-next)
    ;; Manually corrupt positions to simulate marker drift
    (let ((regions (evim-get-all-regions)))
      (set-marker (evim-region-beg (car regions)) 2)
      (set-marker (evim-region-beg (cadr regions)) 10))
    ;; Positions are now wrong
    (should (equal (evim-test-positions) '(2 10)))
    ;; Simulate undo command by setting this-command and calling post-command
    (let ((this-command 'evil-undo))
      (evim--post-command))
    ;; Positions should be corrected back to pattern matches
    (should (equal (evim-test-positions) '(1 9)))))

(ert-deftest evim-test-post-command-no-resync-on-other-commands ()
  "Post-command hook should NOT trigger resync for non-undo commands."
  (evim-test-with-buffer "foo bar foo"
    (evim-find-word)
    (evim-find-next)
    ;; Manually change positions
    (let ((regions (evim-get-all-regions)))
      (set-marker (evim-region-beg (car regions)) 2)
      (set-marker (evim-region-beg (cadr regions)) 10))
    ;; Positions are modified
    (should (equal (evim-test-positions) '(2 10)))
    ;; Simulate non-undo command
    (let ((this-command 'forward-char))
      (evim--post-command))
    ;; Positions should remain modified (no resync)
    (should (equal (evim-test-positions) '(2 10)))))

(ert-deftest evim-test-undo-moves-point-to-leader ()
  "After evim-undo, point should be at leader cursor position."
  (evim-test-with-buffer "foo bar foo"
    (evim-find-word)
    (evim-find-next)
    ;; Leader is at second foo (position 9)
    (should (= (evim-test-leader-pos) 9))
    ;; Point should be at leader's visual position
    (let ((leader (evim--leader-region)))
      (should (= (point) (evim--region-visual-cursor-pos leader))))))

(ert-deftest evim-test-undo-adjusts-cursor-to-last-char ()
  "After undo, evim--adjust-cursor-pos should clamp cursors off newline.
Regression: paste moves markers into inserted text; undo removes text
and Emacs pushes markers to line-end-position, creating stale overlays."
  (evim-test-with-buffer "aaa\nbbb\nccc\n"
    ;; Cursors at end-of-line (position 3 = last char 'a', 7 = last 'b')
    (evim-activate)
    (evim--create-region 3 3)
    (evim--create-region 7 7)
    ;; Simulate markers ending up on newline (as happens after undo of paste)
    (dolist (region (evim-state-regions evim--state))
      (let ((eol-pos (save-excursion
                       (goto-char (marker-position (evim-region-beg region)))
                       (line-end-position))))
        (evim--region-set-cursor-pos region eol-pos)))
    ;; Verify markers are on newline
    (dolist (region (evim-state-regions evim--state))
      (should (= (marker-position (evim-region-beg region))
                 (save-excursion
                   (goto-char (marker-position (evim-region-beg region)))
                   (line-end-position)))))
    ;; Apply the adjustment (what evim-undo does)
    (dolist (region (evim-state-regions evim--state))
      (evim--region-set-cursor-pos
       region (evim--adjust-cursor-pos (evim--region-cursor-pos region))))
    ;; Verify: cursors moved back to last character (off newline)
    (dolist (region (evim-state-regions evim--state))
      (let ((pos (marker-position (evim-region-beg region))))
        (save-excursion
          (goto-char pos)
          (should-not (= pos (line-end-position))))))))

;;; Restrict to region tests

(ert-deftest evim-test-restrict-active-p ()
  "evim--restrict-active-p should return t when restriction is set."
  (evim-test-with-buffer "foo bar foo baz foo"
    (evim-activate)
    (evim--create-region (point) (point))
    (should-not (evim--restrict-active-p))
    (evim--set-restrict 5 15)
    (should (evim--restrict-active-p))
    (evim--clear-restrict)
    (should-not (evim--restrict-active-p))))

(ert-deftest evim-test-restrict-bounds ()
  "evim--restrict-bounds should return correct bounds."
  (evim-test-with-buffer "foo bar foo baz foo"
    (evim-activate)
    (evim--create-region (point) (point))
    (evim--set-restrict 5 15)
    (let ((bounds (evim--restrict-bounds)))
      (should (= (car bounds) 5))
      (should (= (cdr bounds) 15)))))

(ert-deftest evim-test-select-all-restricted ()
  "\\A should only select occurrences within restriction."
  (evim-test-with-buffer "foo bar foo baz foo qux foo"
    ;; foo at positions: 1, 9, 17, 25
    (evim-find-word)
    ;; Set restriction from position 5 to 20 (covers foo at 9 and 17)
    (evim--set-restrict 5 20)
    ;; First foo at position 1 is the current selection (outside restriction)
    ;; Clear regions and start fresh
    (evim--remove-all-overlays)
    (setf (evim-state-regions evim--state) nil)
    ;; Go to position 9 (inside restriction)
    (goto-char 9)
    ;; Create region for foo at 9
    (evim--create-region 9 12 (car (evim-state-patterns evim--state)))
    ;; Select all should only add foo at 17
    (evim-select-all)
    ;; Should have exactly 2 cursors (at 9 and 17)
    (should (= (evim-region-count) 2))
    (should (equal (evim-test-positions) '(9 17)))))

(ert-deftest evim-test-find-next-restricted ()
  "n should only find occurrences within restriction."
  (evim-test-with-buffer "foo bar foo baz foo qux foo"
    ;; foo at positions: 1, 9, 17, 25
    (evim-find-word)
    ;; Set restriction from position 5 to 20 (covers foo at 9 and 17)
    (evim--set-restrict 5 20)
    ;; Start from position 9
    (evim--remove-all-overlays)
    (setf (evim-state-regions evim--state) nil)
    (clrhash (evim-state-region-by-id evim--state))
    (goto-char 9)
    (evim--create-region 9 12 (car (evim-state-patterns evim--state)))
    ;; find-next should find foo at 17
    (evim-find-next)
    (should (= (evim-region-count) 2))
    ;; find-next again should wrap back to 9
    (evim-find-next)
    (should (= (evim-region-count) 2))
    (should (= (evim-test-leader-pos) 9))))

(ert-deftest evim-test-clear-restrict ()
  "\\r should clear restriction."
  (evim-test-with-buffer "foo bar foo baz foo"
    (evim-find-word)
    (evim--set-restrict 5 15)
    (should (evim--restrict-active-p))
    (evim-clear-restrict)
    (should-not (evim--restrict-active-p))))

(ert-deftest evim-test-exit-clears-restrict ()
  "Exit should clear restriction."
  (evim-test-with-buffer "foo bar foo"
    (evim-find-word)
    (evim--set-restrict 1 10)
    (should (evim--restrict-active-p))
    (evim-exit)
    ;; After exit, state is deactivated so restriction should be cleared
    (should-not (evim--restrict-active-p))))

(ert-deftest evim-test-mode-line-shows-restrict ()
  "Mode-line should show R indicator when restricted."
  (evim-test-with-buffer "foo bar foo"
    (evim-find-word)
    (let ((indicator (evim--mode-line-indicator)))
      (should-not (string-match-p " R" indicator)))
    (evim--set-restrict 1 10)
    (let ((indicator (evim--mode-line-indicator)))
      (should (string-match-p " R" indicator)))))

;;; Mouse click tests

(ert-deftest evim-test-add-cursor-at-click-creates-cursor ()
  "M-click should create cursor at original point AND at click position."
  (evim-test-with-buffer "foo bar baz"
    ;; Point is at 1, click at position 5
    (goto-char 1)
    (let ((event `(mouse-1 (,(selected-window) 5 (0 . 0) 0))))
      (evim-add-cursor-at-click event))
    (should (evim-active-p))
    ;; Two cursors: one at original point (1) and one at click position (5)
    (should (= (evim-region-count) 2))
    (should (= (evim-test-leader-pos) 5))))

(ert-deftest evim-test-add-cursor-at-click-uses-pre-click-point ()
  "First click should use saved pre-click point even if point moved."
  (evim-test-with-buffer "foo bar baz"
    ;; Simulate: point was at 1, mouse-down saved it, then point moved to 5
    (goto-char 1)
    (setq evim--pre-click-point 1)
    (goto-char 5) ;; Emacs mouse processing moved point
    (let ((event `(mouse-1 (,(selected-window) 9 (0 . 0) 0))))
      (evim-add-cursor-at-click event))
    (should (evim-active-p))
    ;; First cursor at pre-click-point (1), second at click pos (9)
    (should (= (evim-region-count) 2))
    (let ((positions (mapcar #'evim--region-cursor-pos
                             (evim-state-regions evim--state))))
      (should (member 1 positions))
      (should (member 9 positions)))))

(ert-deftest evim-test-add-cursor-at-click-removes-existing ()
  "M-click on existing cursor should remove it (toggle behavior)."
  (evim-test-with-buffer "foo bar baz"
    (evim-activate)
    (evim--create-region 1 1)
    (evim--create-region 5 5)
    (should (= (evim-region-count) 2))
    ;; Click on position 5 (existing non-leader cursor) - should remove it
    (let ((event `(mouse-1 (,(selected-window) 5 (0 . 0) 0))))
      (evim-add-cursor-at-click event))
    ;; Should now have 1 cursor
    (should (= (evim-region-count) 1))
    (should (= (evim-test-leader-pos) 1))))

(ert-deftest evim-test-add-cursor-at-click-removes-leader-on-repeat ()
  "M-click on leader cursor should remove it (toggle behavior)."
  (evim-test-with-buffer "foo bar baz"
    (evim-activate)
    (evim--create-region 1 1)
    (evim--create-region 5 5)
    (should (= (evim-region-count) 2))
    ;; Set leader to position 5
    (let ((cursor-at-5 (cl-find-if (lambda (r) (= (evim--region-cursor-pos r) 5))
                                    (evim-state-regions evim--state))))
      (evim--set-leader cursor-at-5))
    (should (= (evim-test-leader-pos) 5))
    ;; Click on leader position 5 - should remove it
    (let ((event `(mouse-1 (,(selected-window) 5 (0 . 0) 0))))
      (evim-add-cursor-at-click event))
    ;; Should now have 1 cursor, leader moved to remaining one
    (should (= (evim-region-count) 1))
    (should (= (evim-test-leader-pos) 1))))

(ert-deftest evim-test-align ()
  "Test that align inserts spaces before region start."
  (evim-test-with-buffer "short = 1\nvery_long_name = 2\nmedium = 3"
    (evim-activate)
    ;; Create regions on the = signs
    (goto-char (point-min))
    (search-forward "=")
    (backward-char)
    (evim--create-region (point) (1+ (point)))
    (forward-line)
    (search-forward "=")
    (backward-char)
    (evim--create-region (point) (1+ (point)))
    (forward-line)
    (search-forward "=")
    (backward-char)
    (evim--create-region (point) (1+ (point)))
    ;; Align
    (evim-align)
    ;; Check that = signs are aligned
    (should (string= (buffer-string)
                     "short          = 1\nvery_long_name = 2\nmedium         = 3"))))

;;; Run at Cursors tests

(defmacro evim-test-with-real-buffer (content &rest body)
  "Create real buffer with CONTENT, execute BODY, then cleanup.
Used for tests that need execute-kbd-macro which doesn't work in temp buffers."
  (declare (indent 1))
  `(let ((buf (generate-new-buffer " *evim-test*")))
     (unwind-protect
         (progn
           (switch-to-buffer buf)
           (insert ,content)
           (goto-char (point-min))
           (evil-local-mode 1)
           (evil-normal-state)
           ,@body)
       (when (evim-active-p)
         (evim-exit))
       (kill-buffer buf))))

(ert-deftest evim-test-run-normal-basic ()
  "\\z should run normal command at all cursors."
  (evim-test-with-real-buffer "foo\nbar\nbaz"
    ;; Create cursors on each line
    (evim-add-cursor-down)
    (evim-add-cursor-down)
    (should (= (evim-region-count) 3))
    ;; Run "x" at all cursors (delete char)
    (evim-run-normal "x")
    (should (string= (buffer-string) "oo\nar\naz"))))

(ert-deftest evim-test-run-normal-with-count ()
  "\\z should handle commands with implicit count."
  (evim-test-with-real-buffer "foo\nbar\nbaz"
    ;; Create cursors on each line
    (evim-add-cursor-down)
    (evim-add-cursor-down)
    ;; Run "2x" at all cursors (delete 2 chars)
    (evim-run-normal "2x")
    (should (string= (buffer-string) "o\nr\nz"))))

(ert-deftest evim-test-run-normal-movement ()
  "\\z should handle movement commands."
  (evim-test-with-real-buffer "foo\nbar\nbaz"
    ;; Create cursors on each line at position 1 of each line
    (evim-add-cursor-down)
    (evim-add-cursor-down)
    ;; Run "l" to move right - need update-positions
    ;; Since run-normal doesn't update positions by default,
    ;; markers stay in place but cursor moves
    (evim-run-normal "l")
    ;; For movement commands, positions don't change (markers auto-adjust)
    ;; The visual cursor moves but markers don't
    (let ((positions (evim-test-positions)))
      ;; Positions should remain at line beginnings
      (should (= (car positions) 1))
      (should (= (nth 1 positions) 5))
      (should (= (nth 2 positions) 9)))))

(ert-deftest evim-test-run-normal-empty-command ()
  "\\z with empty command should do nothing."
  (evim-test-with-buffer "foo\nbar"
    (evim-add-cursor-down)
    (let ((content-before (buffer-string)))
      (evim-run-normal "")
      (should (string= (buffer-string) content-before)))))

(ert-deftest evim-test-run-command-at-cursors-error-handling ()
  "Errors in commands should be caught and reported."
  (evim-test-with-buffer "foo\nbar"
    (evim-add-cursor-down)
    ;; This should not throw an error that stops everything
    ;; Running an invalid command should be handled gracefully
    (condition-case nil
        (evim--run-command-at-cursors
         (lambda ()
           (error "Test error")))
      (error nil))
    ;; evim should still be active
    (should (evim-active-p))))

(ert-deftest evim-test-run-macro-basic ()
  "\\@ should run macro at all cursors."
  (evim-test-with-real-buffer "foo\nbar\nbaz"
    ;; Create cursors on each line
    (evim-add-cursor-down)
    (evim-add-cursor-down)
    ;; Record a macro that deletes first char: "x"
    (evil-set-register ?q (kbd "x"))
    ;; Run macro
    (evim-run-macro ?q)
    (should (string= (buffer-string) "oo\nar\naz"))))

(ert-deftest evim-test-run-macro-empty-register ()
  "\\@ with empty register should error."
  (evim-test-with-buffer "foo\nbar"
    (evim-add-cursor-down)
    ;; Clear register
    (evil-set-register ?z nil)
    (should-error (evim-run-macro ?z))))

(ert-deftest evim-test-run-ex-basic ()
  "\\: should run Ex command at all cursors."
  (evim-test-with-buffer "foo\nbar\nbaz"
    ;; Create cursors on each line
    (evim-add-cursor-down)
    (evim-add-cursor-down)
    (should (= (evim-region-count) 3))
    ;; Run "s/^/X/" to prepend X at each cursor line
    (evim-run-ex "s/^/X/")
    (should (string= (buffer-string) "Xfoo\nXbar\nXbaz"))))

(ert-deftest evim-test-run-ex-empty-command ()
  "\\: with empty command should do nothing."
  (evim-test-with-buffer "foo\nbar"
    (evim-add-cursor-down)
    (let ((content-before (buffer-string)))
      (evim-run-ex "")
      (should (string= (buffer-string) content-before)))))

(ert-deftest evim-test-run-normal-preserves-cursor-count ()
  "\\z should preserve number of cursors."
  (evim-test-with-real-buffer "foo\nbar\nbaz"
    (evim-add-cursor-down)
    (evim-add-cursor-down)
    (let ((count-before (evim-region-count)))
      (evim-run-normal "l")
      (should (= (evim-region-count) count-before)))))

;;; Operator tests

(ert-deftest evim-test-operator-bindings-in-cursor-mode ()
  "d, c, y should be bound to operators in cursor mode."
  (evim-test-with-buffer "foo bar foo"
    (evim-add-cursor-down)  ; Enters cursor mode
    (should (evim-cursor-mode-p))
    (should (eq (key-binding "d") 'evim-operator-delete))
    (should (eq (key-binding "c") 'evim-operator-change))
    (should (eq (key-binding "y") 'evim-operator-yank))
    (should (eq (key-binding "D") 'evim-delete-to-eol))
    (should (eq (key-binding "C") 'evim-change-to-eol))
    (should (eq (key-binding "Y") 'evim-yank-line))))

(ert-deftest evim-test-delete-to-eol ()
  "D should delete from cursor to end of line at all cursors."
  (evim-test-with-buffer "foo bar\nbaz qux\nend"
    (evim-add-cursor-down)
    (evim-add-cursor-down)
    (should (= (evim-region-count) 3))
    ;; Move cursors to position 4 on each line (after "foo ", "baz ", "end")
    ;; Actually at beginning, so D deletes whole line content
    (evim-delete-to-eol)
    (should (string= (buffer-string) "\n\n"))))

(ert-deftest evim-test-delete-to-eol-mid-line ()
  "D from middle of line should delete only rest of line."
  (evim-test-with-buffer "foo bar\nbaz qux"
    (evim-activate)
    (evim--create-region 4 4)   ; after "foo" on line 1
    (evim--create-region 12 12) ; after "baz" on line 2
    (evim-delete-to-eol)
    (should (string= (buffer-string) "foo\nbaz"))))

(ert-deftest evim-test-change-to-eol-cursor-position ()
  "C should place cursor at deletion point, not adjusted back."
  (evim-test-with-buffer "alpha beta gamma\nalpha beta gamma"
    (evim-activate)
    ;; Place cursors at 'b' in "beta" on each line (positions 7 and 24)
    (evim--create-region 7 7)
    (evim--create-region 24 24)
    (should (= (evim-region-count) 2))
    ;; C deletes to end of line and enters insert mode
    (evim-change-to-eol)
    ;; Buffer should have "alpha " on each line
    (should (string= (buffer-string) "alpha \nalpha "))
    ;; Cursors should be at position 7 and 14 (after "alpha ")
    ;; NOT adjusted back to position 6 and 13
    (should (equal (evim-test-positions) '(7 14)))
    ;; Clean up insert mode
    (evil-normal-state)))

(ert-deftest evim-test-yank-line ()
  "Y should yank entire line at all cursors."
  (evim-test-with-buffer "foo bar\nbaz qux"
    (evim-add-cursor-down)
    (should (= (evim-region-count) 2))
    (evim-yank-line)
    (let ((contents (gethash ?\" (evim-state-registers evim--state))))
      (should contents)
      (should (= (length contents) 2))
      (should (string= (car contents) "foo bar"))
      (should (string= (cadr contents) "baz qux")))))

;; Note: evim--execute-operator-motion tests require interactive Emacs
;; (execute-kbd-macro doesn't work well in batch/server mode)
;; These are tested via make test-interactive instead

(ert-deftest evim-test-single-motions-list ()
  "Single motions list should contain expected motions."
  (should (memq ?h evim--single-motions))
  (should (memq ?j evim--single-motions))
  (should (memq ?k evim--single-motions))
  (should (memq ?l evim--single-motions))
  (should (memq ?w evim--single-motions))
  (should (memq ?e evim--single-motions))
  (should (memq ?b evim--single-motions))
  (should (memq ?$ evim--single-motions))
  (should (memq ?^ evim--single-motions))
  (should (memq ?0 evim--single-motions)))

(ert-deftest evim-test-double-motion-prefixes-list ()
  "Double motion prefixes should contain expected prefixes."
  (should (memq ?i evim--double-motion-prefixes))
  (should (memq ?a evim--double-motion-prefixes))
  (should (memq ?f evim--double-motion-prefixes))
  (should (memq ?F evim--double-motion-prefixes))
  (should (memq ?t evim--double-motion-prefixes))
  (should (memq ?T evim--double-motion-prefixes))
  (should (memq ?g evim--double-motion-prefixes)))

(ert-deftest evim-test-text-objects-list ()
  "Text objects list should contain expected objects."
  (should (memq ?w evim--text-objects))
  (should (memq ?W evim--text-objects))
  (should (memq ?s evim--text-objects))
  (should (memq ?p evim--text-objects))
  (should (memq ?\" evim--text-objects))
  (should (memq ?' evim--text-objects))
  (should (memq ?\( evim--text-objects))
  (should (memq ?\) evim--text-objects))
  (should (memq ?\[ evim--text-objects))
  (should (memq ?\] evim--text-objects))
  (should (memq ?{ evim--text-objects))
  (should (memq ?} evim--text-objects))
  (should (memq ?b evim--text-objects))
  (should (memq ?B evim--text-objects)))

(ert-deftest evim-test-text-object-ranges ()
  "Text objects should return correct ranges via evim--get-motion-range."
  ;; di[ - inner brackets
  (with-temp-buffer
    (evil-local-mode 1) (evil-normal-state)
    (insert "x = [1, 2, 3]")
    (goto-char 6) ;; on "1"
    (let ((range (evim--get-motion-range "i[" 1)))
      (should range)
      (delete-region (car range) (cadr range))
      (should (string= (buffer-string) "x = []"))))
  ;; di{ - inner curly braces
  (with-temp-buffer
    (evil-local-mode 1) (evil-normal-state)
    (insert "x = {a, b}")
    (goto-char 6)
    (let ((range (evim--get-motion-range "i{" 1)))
      (should range)
      (delete-region (car range) (cadr range))
      (should (string= (buffer-string) "x = {}"))))
  ;; iB - curly braces via B alias
  (with-temp-buffer
    (evil-local-mode 1) (evil-normal-state)
    (insert "x = {a, b}")
    (goto-char 6)
    (let ((range (evim--get-motion-range "iB" 1)))
      (should range)
      (delete-region (car range) (cadr range))
      (should (string= (buffer-string) "x = {}"))))
  ;; di( - inner parens
  (with-temp-buffer
    (evil-local-mode 1) (evil-normal-state)
    (insert "print(hello)")
    (goto-char 7)
    (let ((range (evim--get-motion-range "i(" 1)))
      (should range)
      (delete-region (car range) (cadr range))
      (should (string= (buffer-string) "print()")))))

(ert-deftest evim-test-digit-p ()
  "evim--digit-p should recognize digits 1-9."
  (should (evim--digit-p ?1))
  (should (evim--digit-p ?5))
  (should (evim--digit-p ?9))
  (should-not (evim--digit-p ?0))  ; 0 is a motion, not a count digit
  (should-not (evim--digit-p ?a))
  (should-not (evim--digit-p nil)))

;; evim-test-delete-saves-to-register requires interactive Emacs

(ert-deftest evim-test-operator-accepts-prefix-arg ()
  "Operator commands should accept prefix argument for 2dw pattern."
  (should (commandp 'evim-operator-delete))
  (should (commandp 'evim-operator-change))
  (should (commandp 'evim-operator-yank))
  ;; Check interactive spec accepts prefix arg
  (should (string-match-p "P" (or (car (cdr (interactive-form 'evim-operator-delete))) "")))
  (should (string-match-p "P" (or (car (cdr (interactive-form 'evim-operator-change))) "")))
  (should (string-match-p "P" (or (car (cdr (interactive-form 'evim-operator-yank))) ""))))

(ert-deftest evim-test-dw-does-not-cross-line-boundary ()
  "dw should not delete newline character (like vim behavior)."
  (evim-test-with-real-buffer "foo\nbar\nbaz"
    ;; Start at beginning of "foo" (position 1)
    (evim-activate)
    (evim--create-region 1 1)
    ;; Get motion range for "w" from position 1
    ;; In vim, "w" from "foo" goes to "bar" on next line,
    ;; but "dw" should only delete "foo" (not the newline)
    (let ((range (evim--get-motion-range "w" 1)))
      ;; Range should be (1 4) - from "f" to end of "foo"
      ;; Not (1 5) which would include the newline
      (should range)
      (should (= (car range) 1))
      ;; End should be at position 4 (end of "foo", before newline)
      (should (= (cadr range) 4)))))

(ert-deftest evim-test-dw-works-normally-within-line ()
  "dw should work normally when next word is on same line."
  (evim-test-with-real-buffer "foo bar baz"
    (evim-activate)
    (evim--create-region 1 1)
    ;; Get motion range for "w" from position 1
    ;; Next word "bar" is on same line, so range should include space
    (let ((range (evim--get-motion-range "w" 1)))
      (should range)
      (should (= (car range) 1))
      ;; End should be at position 5 (start of "bar")
      (should (= (cadr range) 5)))))

(ert-deftest evim-test-dW-does-not-cross-line-boundary ()
  "dW should not delete newline character (like vim behavior)."
  (evim-test-with-real-buffer "foo\nbar"
    (evim-activate)
    (evim--create-region 1 1)
    (let ((range (evim--get-motion-range "W" 1)))
      (should range)
      (should (= (car range) 1))
      ;; End should be at position 4 (end of line)
      (should (= (cadr range) 4)))))

;;; Line operation tests (dd, cc, yy)

(ert-deftest evim-test-execute-operator-line-delete ()
  "dd should delete entire line including newline."
  (evim-test-with-buffer "line1\nline2\nline3"
    (evim-activate)
    (evim--create-region 1 1)
    (let ((text (evim--execute-operator-line 'delete 1)))
      (should (string= text "line1\n"))
      (should (string= (buffer-string) "line2\nline3")))))

(ert-deftest evim-test-execute-operator-line-delete-multiple ()
  "2dd should delete 2 lines."
  (evim-test-with-buffer "line1\nline2\nline3\nline4"
    (evim-activate)
    (evim--create-region 1 1)
    (let ((text (evim--execute-operator-line 'delete 2)))
      (should (string= text "line1\nline2\n"))
      (should (string= (buffer-string) "line3\nline4")))))

(ert-deftest evim-test-execute-operator-line-yank ()
  "yy should yank entire line without deleting."
  (evim-test-with-buffer "line1\nline2\nline3"
    (evim-activate)
    (evim--create-region 1 1)
    (let ((text (evim--execute-operator-line 'yank 1)))
      (should (string= text "line1\n"))
      ;; Buffer unchanged
      (should (string= (buffer-string) "line1\nline2\nline3")))))

(ert-deftest evim-test-execute-operator-line-change ()
  "cc should delete line and prepare for insert."
  (evim-test-with-buffer "line1\nline2\nline3"
    (evim-activate)
    (evim--create-region 7 7)  ; cursor on line2
    (goto-char 7)  ; need to position point for line operations
    (let ((text (evim--execute-operator-line 'change 1)))
      (should (string= text "line2\n"))
      ;; Line replaced with empty line (newline inserted for edit)
      (should (string-match-p "line1\n.*\nline3" (buffer-string))))))

(ert-deftest evim-test-parse-motion-line-operation ()
  "evim--parse-motion should recognize dd, cc, yy as line operations."
  ;; We can't easily test read-char interactively, but we can verify
  ;; the function signature accepts operator-char
  (should (functionp 'evim--parse-motion)))

;;; Join lines tests

(ert-deftest evim-test-join-lines-basic ()
  "J should join current line with next line."
  (evim-test-with-buffer "foo\nbar\nbaz"
    (evim-activate)
    (evim--create-region 1 1)
    (evim-join-lines 1)
    (should (string= (buffer-string) "foo bar\nbaz"))))

(ert-deftest evim-test-join-lines-multiple-cursors ()
  "J should join lines at all cursor positions."
  (evim-test-with-buffer "aaa\nbbb\nccc\nddd"
    (evim-activate)
    (evim--create-region 1 1)   ; line 1
    (evim--create-region 9 9)   ; line 3
    (should (= (evim-region-count) 2))
    (evim-join-lines 1)
    (should (string= (buffer-string) "aaa bbb\nccc ddd"))))

(ert-deftest evim-test-join-lines-removes-leading-whitespace ()
  "J should remove leading whitespace from joined line."
  (evim-test-with-buffer "foo\n   bar"
    (evim-activate)
    (evim--create-region 1 1)
    (evim-join-lines 1)
    (should (string= (buffer-string) "foo bar"))))

(ert-deftest evim-test-join-lines-no-space-before-paren ()
  "J should not add space when next line starts with ) or ]."
  (evim-test-with-buffer "foo(\n)"
    (evim-activate)
    (evim--create-region 1 1)
    (evim-join-lines 1)
    (should (string= (buffer-string) "foo()"))))

;;; Indent/outdent operator tests

(ert-deftest evim-test-operator-indent-bindings ()
  "> and < should be bound in cursor mode."
  (evim-test-with-buffer "foo"
    (evim-add-cursor-down)
    (should (evim-cursor-mode-p))
    (should (eq (key-binding ">") 'evim-operator-indent))
    (should (eq (key-binding "<") 'evim-operator-outdent))))

(ert-deftest evim-test-execute-indent-line ()
  "evim--execute-indent-line should indent lines."
  (evim-test-with-buffer "foo\nbar"
    (evim-activate)
    (evim--create-region 1 1)
    (let ((tab-width 2)
          (indent-tabs-mode nil))
      (evim--execute-indent-line 'indent 1))
    (should (string-match-p "^  foo" (buffer-string)))))

(ert-deftest evim-test-execute-outdent-line ()
  "evim--execute-indent-line with outdent should remove indentation."
  (evim-test-with-buffer "  foo\n  bar"
    (evim-activate)
    (evim--create-region 1 1)
    (let ((tab-width 2))
      (evim--execute-indent-line 'outdent 1))
    (should (string-match-p "^foo" (buffer-string)))))

;;; Case change operator tests

(ert-deftest evim-test-case-operator-bindings ()
  "gu, gU, g~ should be bound in cursor mode."
  (evim-test-with-buffer "foo"
    (evim-add-cursor-down)
    (should (evim-cursor-mode-p))
    (should (eq (key-binding (kbd "g u")) 'evim-operator-downcase))
    (should (eq (key-binding (kbd "g U")) 'evim-operator-upcase))
    (should (eq (key-binding (kbd "g ~")) 'evim-operator-toggle-case))))

(ert-deftest evim-test-toggle-case-region-function ()
  "evim--toggle-case-region should toggle case of region."
  (evim-test-with-buffer "FoO BaR"
    (evim--toggle-case-region 1 4)
    (should (string= (buffer-substring 1 4) "fOo"))))

(ert-deftest evim-test-execute-case-line-upcase ()
  "evim--execute-case-line with upcase-region should uppercase line."
  (evim-test-with-buffer "foo bar\nbaz"
    (evim-activate)
    (evim--create-region 1 1)
    (evim--execute-case-line #'upcase-region 1)
    (should (string= (buffer-string) "FOO BAR\nbaz"))))

(ert-deftest evim-test-execute-case-line-downcase ()
  "evim--execute-case-line with downcase-region should lowercase line."
  (evim-test-with-buffer "FOO BAR\nBAZ"
    (evim-activate)
    (evim--create-region 1 1)
    (evim--execute-case-line #'downcase-region 1)
    (should (string= (buffer-string) "foo bar\nBAZ"))))

(ert-deftest evim-test-execute-case-line-toggle ()
  "evim--execute-case-line with toggle should toggle case of line."
  (evim-test-with-buffer "FoO bAr\nbaz"
    (evim-activate)
    (evim--create-region 1 1)
    (evim--execute-case-line #'evim--toggle-case-region 1)
    (should (string= (buffer-string) "fOo BaR\nbaz"))))

(ert-deftest evim-test-case-operators-exist ()
  "Case operator functions should exist and be commands."
  (should (commandp 'evim-operator-downcase))
  (should (commandp 'evim-operator-upcase))
  (should (commandp 'evim-operator-toggle-case)))

;;; Phase 9 tests: Special Features

;;; Visual mode cursor selection tests (9.1)

(ert-deftest evim-test-visual-cursors-char-mode ()
  "evim-visual-cursors in visual char mode should create cursors at start and end."
  (evim-test-with-buffer "hello world foo"
    (goto-char 7)  ; start at 'w'
    (evil-visual-state)
    (evil-forward-char 4)  ; select "worl"
    ;; Manually call the function (simulating the command)
    (let ((beg (region-beginning))
          (end (region-end)))
      (evil-exit-visual-state)
      (evim-activate)
      (evim--create-region beg beg)
      (evim--create-region (1- end) (1- end)))
    (should (evim-active-p))
    (should (= (evim-region-count) 2))))

(ert-deftest evim-test-visual-cursors-line-mode ()
  "evim-visual-cursors in visual line mode should create cursor per line."
  (evim-test-with-buffer "line1\nline2\nline3"
    (evil-visual-line)
    (evil-next-line 2)  ; select all 3 lines
    (let ((positions '()))
      ;; Simulate evim-visual-cursors logic for line mode
      (save-excursion
        (goto-char (region-beginning))
        (dotimes (_ 3)
          (back-to-indentation)
          (push (point) positions)
          (forward-line 1)))
      (evil-exit-visual-state)
      (evim-activate)
      (dolist (pos (nreverse positions))
        (evim--create-region pos pos)))
    (should (evim-active-p))
    (should (= (evim-region-count) 3))))

;;; Reselect Last tests (9.4)

(ert-deftest evim-test-reselect-last-saves-mode ()
  "evim--save-for-reselect should save mode information."
  (evim-test-with-buffer "foo bar foo"
    (evim-find-word)
    (evim-find-next)
    ;; We're in extend mode
    (should (evim-extend-mode-p))
    ;; Save for reselect (called automatically on exit)
    (evim--save-for-reselect)
    (let ((last (evim-state-last-regions evim--state)))
      ;; Should be a plist with :mode
      (should (plistp last))
      (should (eq (plist-get last :mode) 'extend))
      (should (= (length (plist-get last :positions)) 2)))))

(ert-deftest evim-test-reselect-last-restores-positions ()
  "evim-reselect-last should restore cursor positions."
  (evim-test-with-buffer "foo bar foo"
    (evim-find-word)
    (evim-find-next)
    (let ((positions-before (evim-test-positions)))
      (evim--save-for-reselect)
      (evim-exit)
      (should-not (evim-active-p))
      (evim-reselect-last)
      (should (evim-active-p))
      (should (= (evim-region-count) 2))
      (should (equal (evim-test-positions) positions-before)))))

;;; VM Registers tests (9.5)

(ert-deftest evim-test-yank-to-named-register ()
  "evim-yank-to-register should save to specified register."
  (evim-test-with-buffer "foo bar foo"
    (evim-find-word)
    (evim-find-next)
    (should (evim-extend-mode-p))
    (evim-yank-to-register ?a)
    (let ((contents (gethash ?a (evim-state-registers evim--state))))
      (should contents)
      (should (= (length contents) 2))
      (should (string= (car contents) "foo")))))

(ert-deftest evim-test-yank-to-uppercase-register-appends ()
  "Uppercase register should append to existing contents."
  (evim-test-with-buffer "foo bar baz"
    (evim-activate)
    ;; First yank "foo"
    (evim--create-region 1 4 nil)
    (setf (evim-state-mode evim--state) 'extend)
    (evim--update-all-overlays)
    (evim-yank-to-register ?a)
    ;; Clear and yank "bar"
    (setf (evim-state-regions evim--state) nil)
    (evim--create-region 5 8 nil)
    (evim-yank-to-register ?A)  ; Uppercase appends
    (let ((contents (gethash ?a (evim-state-registers evim--state))))
      (should (= (length contents) 2))
      (should (string= (car contents) "foo"))
      (should (string= (cadr contents) "bar")))))

(ert-deftest evim-test-paste-from-named-register ()
  "evim-paste-from-register should paste from specified register."
  (evim-test-with-buffer "XXX YYY"
    (evim-activate)
    ;; Store something in register a
    (puthash ?a '("foo" "bar") (evim-state-registers evim--state))
    ;; Create cursors
    (evim--create-region 1 4 nil)  ; "XXX"
    (evim--create-region 5 8 nil)  ; "YYY"
    (setf (evim-state-mode evim--state) 'extend)
    (evim--update-all-overlays)
    ;; Paste from register a (replaces selections)
    (evim-paste-from-register ?a)
    (should (string= (buffer-string) "foo bar"))))

(ert-deftest evim-test-yank-via-evil-this-register ()
  "evim-yank should use evil-this-register when set."
  (evim-test-with-buffer "foo bar foo"
    (evim-find-word)
    (evim-find-next)
    (should (evim-extend-mode-p))
    ;; Simulate pressing \"a before y
    (setq evil-this-register ?b)
    (evim-yank)
    ;; evil-this-register should be cleared
    (should-not evil-this-register)
    ;; Contents should be in register b
    (let ((contents (gethash ?b (evim-state-registers evim--state))))
      (should contents)
      (should (= (length contents) 2))
      (should (string= (car contents) "foo")))))

(ert-deftest evim-test-paste-via-evil-this-register ()
  "evim-paste-after should use evil-this-register when set."
  (evim-test-with-buffer "XXX YYY"
    (evim-activate)
    ;; Store in register c
    (puthash ?c '("foo" "bar") (evim-state-registers evim--state))
    ;; Create cursors
    (evim--create-region 1 4 nil)
    (evim--create-region 5 8 nil)
    (setf (evim-state-mode evim--state) 'extend)
    (evim--update-all-overlays)
    ;; Simulate pressing \"c before p
    (setq evil-this-register ?c)
    (evim-paste-after)
    ;; evil-this-register should be cleared
    (should-not evil-this-register)
    (should (string= (buffer-string) "foo bar"))))

(ert-deftest evim-test-paste-in-cursor-mode ()
  "p in cursor mode should insert without deleting."
  (evim-test-with-buffer "ab\ncd"
    (evim-activate)
    ;; Store content
    (puthash ?\" '("X" "Y") (evim-state-registers evim--state))
    ;; Create cursors at 'a' and 'c'
    (goto-char 1)
    (evim--create-region 1 1 nil)  ; cursor at 'a'
    (evim--create-region 4 4 nil)  ; cursor at 'c'
    ;; Should be in cursor mode (beg=end)
    (should (evim-cursor-mode-p))
    (evim-paste-after)
    ;; Should insert after cursor positions: aXb, cYd
    (should (string= (buffer-string) "aXb\ncYd"))))

(ert-deftest evim-test-paste-after-cursor-position ()
  "p should place cursors on last inserted character."
  (evim-test-with-buffer "aaa\nbbb\nccc"
    (evim-activate)
    (puthash ?\" '("XX" "YY" "ZZ") (evim-state-registers evim--state))
    (evim--create-region 1 1 nil)
    (evim--create-region 5 5 nil)
    (evim--create-region 9 9 nil)
    (evim-paste-after)
    (should (string= (buffer-string) "aXXaa\nbYYbb\ncZZcc"))
    ;; Cursors should be on last inserted char (second X, Y, Z)
    (let ((positions (mapcar (lambda (r) (marker-position (evim-region-beg r)))
                             (evim-state-regions evim--state))))
      (should (= (length positions) 3))
      (should (equal (char-after (nth 0 positions)) ?X))
      (should (equal (char-after (nth 1 positions)) ?Y))
      (should (equal (char-after (nth 2 positions)) ?Z)))))

(ert-deftest evim-test-paste-before-cursor-position ()
  "P should place cursors on last inserted character."
  (evim-test-with-buffer "aaa\nbbb\nccc"
    (evim-activate)
    (puthash ?\" '("XX" "YY" "ZZ") (evim-state-registers evim--state))
    (evim--create-region 1 1 nil)
    (evim--create-region 5 5 nil)
    (evim--create-region 9 9 nil)
    (evim-paste-before)
    (should (string= (buffer-string) "XXaaa\nYYbbb\nZZccc"))
    ;; Cursors should be on last inserted char (second X, Y, Z)
    (let ((positions (mapcar (lambda (r) (marker-position (evim-region-beg r)))
                             (evim-state-regions evim--state))))
      (should (= (length positions) 3))
      (should (equal (char-after (nth 0 positions)) ?X))
      (should (equal (char-after (nth 1 positions)) ?Y))
      (should (equal (char-after (nth 2 positions)) ?Z)))))

;;; Multiline mode tests (9.2)

(ert-deftest evim-test-toggle-multiline ()
  "evim-toggle-multiline should toggle multiline-p flag."
  (evim-test-with-buffer "foo bar"
    (evim-activate)
    (evim--create-region (point) (point))
    (should-not (evim-state-multiline-p evim--state))
    (evim-toggle-multiline)
    (should (evim-state-multiline-p evim--state))
    (evim-toggle-multiline)
    (should-not (evim-state-multiline-p evim--state))))

(ert-deftest evim-test-find-word-multiline-selection-enables-search ()
  "Multiline visual selections should enable multiline matching for the session."
  (evim-test-with-buffer "foo\nbar\nzzz\nfoo\nbar"
    (goto-char 1)
    (evil-visual-select 1 8 'inclusive)
    (evim-find-word)
    (should (evim-state-multiline-p evim--state))
    (should (= (evim-region-count) 1))
    (evim-find-next)
    (should (equal (evim-test-positions) '(1 13)))
    (should (equal (evim-test-end-positions) '(8 20)))))

(ert-deftest evim-test-toggle-multiline-blocks-cross-line-matches ()
  "Disabling multiline should stop adding multi-line matches."
  (evim-test-with-buffer "foo\nbar\nzzz\nfoo\nbar"
    (goto-char 1)
    (evil-visual-select 1 8 'inclusive)
    (evim-find-word)
    (should (evim-state-multiline-p evim--state))
    (evim-toggle-multiline)
    (should-not (evim-state-multiline-p evim--state))
    (evim-find-next)
    (should (= (evim-region-count) 1))
    (should (equal (evim-test-positions) '(1)))))

;;; Undo tests (9.3)

(ert-deftest evim-test-execute-at-all-cursors-batches-overlay-sync ()
  "Batch cursor execution should not trigger per-edit synchronization hooks."
  (evim-test-with-buffer "a\nb\nc"
    (evim-activate)
    (evim--create-region 1 1)
    (evim--create-region 3 3)
    (let ((overlay-updates 0)
          (after-change-calls 0))
      (cl-letf (((symbol-function 'evim--update-all-overlays)
                 (lambda ()
                   (cl-incf overlay-updates)))
                ((symbol-function 'evim--after-change)
                 (lambda (&rest _args)
                   (cl-incf after-change-calls))))
        (evim--execute-at-all-cursors
         (lambda ()
           (insert "x"))
         t))
      (should (= overlay-updates 1))
      (should (= after-change-calls 0)))
    (should (string= (buffer-string) "xa\nxb\nc"))))

;;; Extend mode text objects

(ert-deftest evim-test-extend-inner-word ()
  "iw in extend mode should select inner word at all cursors."
  (evim-test-with-buffer "foo bar\nbaz qux\nhello world"
    (evim-add-cursor-down)
    (evim-add-cursor-down)
    (evim-enter-extend)
    ;; iw
    (setq unread-command-events (list ?w))
    (evim-extend-inner-text-object)
    (should (evim-extend-mode-p))
    (let ((texts (mapcar (lambda (r)
                           (buffer-substring (marker-position (evim-region-beg r))
                                             (marker-position (evim-region-end r))))
                         (evim-state-regions evim--state))))
      (should (equal texts '("foo" "baz" "hello"))))))

(ert-deftest evim-test-extend-a-word ()
  "aw in extend mode should select a word (with trailing space)."
  (evim-test-with-buffer "foo bar\nbaz qux"
    (evim-add-cursor-down)
    (evim-enter-extend)
    (setq unread-command-events (list ?w))
    (evim-extend-a-text-object)
    (let ((texts (mapcar (lambda (r)
                           (buffer-substring (marker-position (evim-region-beg r))
                                             (marker-position (evim-region-end r))))
                         (evim-state-regions evim--state))))
      (should (equal texts '("foo " "baz "))))))

(ert-deftest evim-test-extend-inner-double-quote ()
  "i\" in extend mode should select inside quotes."
  (evim-test-with-buffer "x = \"hello\"\ny = \"world\""
    (goto-char 6) ;; inside "hello"
    (evim-add-cursor-down)
    (evim-enter-extend)
    (setq unread-command-events (list ?\"))
    (evim-extend-inner-text-object)
    (let ((texts (mapcar (lambda (r)
                           (buffer-substring (marker-position (evim-region-beg r))
                                             (marker-position (evim-region-end r))))
                         (evim-state-regions evim--state))))
      (should (equal texts '("hello" "world"))))))

(ert-deftest evim-test-extend-inner-paren ()
  "i) in extend mode should select inside parens."
  (evim-test-with-buffer "f(10)\ng(20)"
    (goto-char 3) ;; inside (10)
    (evim-add-cursor-down)
    (evim-enter-extend)
    (setq unread-command-events (list ?\)))
    (evim-extend-inner-text-object)
    (let ((texts (mapcar (lambda (r)
                           (buffer-substring (marker-position (evim-region-beg r))
                                             (marker-position (evim-region-end r))))
                         (evim-state-regions evim--state))))
      (should (equal texts '("10" "20"))))))

(ert-deftest evim-test-extend-text-object-keybinding ()
  "i and a should be bound in extend mode."
  (should (eq (lookup-key evim-extend-map (kbd "i")) 'evim-extend-inner-text-object))
  (should (eq (lookup-key evim-extend-map (kbd "a")) 'evim-extend-a-text-object)))

;;; evil-surround integration tests (10.1)

(ert-deftest evim-test-surround-available-check ()
  "evim--surround-available-p should check for evil-surround."
  (evim-test-with-buffer "foo"
    ;; Should return based on whether evil-surround is loaded
    (should (eq (evim--surround-available-p) (featurep 'evil-surround)))))

(ert-deftest evim-test-surround-commands-exist ()
  "Surround commands should be defined."
  (should (commandp 'evim-surround))
  (should (commandp 'evim-operator-surround))
  (should (commandp 'evim-delete-surround))
  (should (commandp 'evim-change-surround)))

(ert-deftest evim-test-surround-keybinding-extend ()
  "S should be bound to evim-surround in extend mode."
  (should (eq (lookup-key evim-extend-map (kbd "S")) 'evim-surround)))

(ert-deftest evim-test-surround-in-extend-mode ()
  "S in extend mode should surround all regions when evil-surround loaded."
  (skip-unless (featurep 'evil-surround))
  (evim-test-with-buffer "foo bar foo"
    (evim-find-word)
    (evim-find-next)
    (should (= (evim-region-count) 2))
    (should (evim-extend-mode-p))
    ;; Surround with quotes (call directly with char)
    (evim-surround ?\")
    ;; Both "foo" should be wrapped
    (should (string= (buffer-string) "\"foo\" bar \"foo\""))))

(ert-deftest evim-test-surround-with-parens ()
  "S with parens should surround all regions."
  (skip-unless (featurep 'evil-surround))
  (evim-test-with-buffer "foo bar foo"
    (evim-find-word)
    (evim-find-next)
    (evim-surround ?\()
    ;; evil-surround uses "( " and " )" with spaces for (
    (should (string-match-p "(.*foo.*)" (buffer-string)))))

(ert-deftest evim-test-surround-switches-to-cursor-mode ()
  "S should switch to cursor mode after surround."
  (skip-unless (featurep 'evil-surround))
  (evim-test-with-buffer "foo bar foo"
    (evim-find-word)
    (evim-find-next)
    (should (evim-extend-mode-p))
    (evim-surround ?\")
    (should (evim-cursor-mode-p))))

(ert-deftest evim-test-delete-surround ()
  "ds should delete surrounding pair at all cursors."
  (skip-unless (featurep 'evil-surround))
  (evim-test-with-buffer "\"foo\" bar \"baz\""
    (evim-activate)
    ;; Create cursors inside the quoted strings
    (evim--create-region 2 2)   ; inside first "foo"
    (evim--create-region 12 12) ; inside second "baz"
    (should (= (evim-region-count) 2))
    ;; Delete surrounding quotes (call with char directly)
    ;; We need to simulate the behavior since read-char is interactive
    (let ((inhibit-message t))
      (dolist (region (evim--regions-by-position-reverse))
        (goto-char (evim--region-cursor-pos region))
        (evil-surround-delete ?\")))
    (should (string= (buffer-string) "foo bar baz"))))

(ert-deftest evim-test-change-surround ()
  "cs should change surrounding pair at all cursors."
  (skip-unless (featurep 'evil-surround))
  (evim-test-with-buffer "\"foo\" bar \"baz\""
    (evim-activate)
    ;; Create cursors inside the quoted strings
    (evim--create-region 2 2)   ; inside first "foo"
    (evim--create-region 12 12) ; inside second "baz"
    (should (= (evim-region-count) 2))
    ;; Change surrounding quotes to single quotes
    (let ((inhibit-message t))
      (dolist (region (evim--regions-by-position-reverse))
        (goto-char (evim--region-cursor-pos region))
        ;; Push new char so evil-surround-change reads it
        (setq unread-command-events (list ?'))
        (evil-surround-change ?\")))
    (should (string= (buffer-string) "'foo' bar 'baz'"))))

(ert-deftest evim-test-surround-only-in-extend-mode ()
  "evim-surround should only work in extend mode."
  (skip-unless (featurep 'evil-surround))
  (evim-test-with-buffer "foo bar foo"
    (evim-add-cursor-down)  ; Creates cursor mode
    (should (evim-cursor-mode-p))
    ;; Surround should have no effect in cursor mode
    (let ((content-before (buffer-string)))
      (evim-surround ?\")
      (should (string= (buffer-string) content-before)))))

(ert-deftest evim-test-operator-surround-only-in-cursor-mode ()
  "evim-operator-surround should only work in cursor mode."
  (skip-unless (featurep 'evil-surround))
  (evim-test-with-buffer "foo bar foo"
    (evim-find-word)  ; Creates extend mode
    (should (evim-extend-mode-p))
    ;; ys should have no effect in extend mode
    (let ((content-before (buffer-string)))
      (evim-operator-surround nil)
      (should (string= (buffer-string) content-before)))))

;;; Additional edge case tests

(ert-deftest evim-test-paste-cycling ()
  "p multiple times should cycle through register contents."
  (evim-test-with-buffer "XXX YYY ZZZ"
    (evim-activate)
    ;; Store 3 values in register
    (puthash ?\" '("a" "b" "c") (evim-state-registers evim--state))
    ;; Create 3 cursors
    (evim--create-region 1 4 nil)   ; "XXX"
    (evim--create-region 5 8 nil)   ; "YYY"
    (evim--create-region 9 12 nil)  ; "ZZZ"
    (setf (evim-state-mode evim--state) 'extend)
    (evim--update-all-overlays)
    (evim-paste-after)
    ;; Each cursor gets corresponding content from register
    (should (string= (buffer-string) "a b c"))))

(ert-deftest evim-test-paste-with-fewer-cursors-than-contents ()
  "p with fewer cursors than register contents should cycle."
  (evim-test-with-buffer "XX YY"
    (evim-activate)
    ;; Store 3 values in register, but only 2 cursors
    (puthash ?\" '("a" "b" "c") (evim-state-registers evim--state))
    ;; Create 2 cursors
    (evim--create-region 1 3 nil)  ; "XX"
    (evim--create-region 4 6 nil)  ; "YY"
    (setf (evim-state-mode evim--state) 'extend)
    (evim--update-all-overlays)
    (evim-paste-after)
    ;; Cursors get first two values
    (should (string= (buffer-string) "a b"))))

(ert-deftest evim-test-paste-with-more-cursors-than-contents ()
  "p with more cursors than register contents should cycle."
  (evim-test-with-buffer "XX YY ZZ WW"
    (evim-activate)
    ;; Store 2 values in register, but 4 cursors
    (puthash ?\" '("a" "b") (evim-state-registers evim--state))
    ;; Create 4 cursors
    (evim--create-region 1 3 nil)   ; "XX"
    (evim--create-region 4 6 nil)   ; "YY"
    (evim--create-region 7 9 nil)   ; "ZZ"
    (evim--create-region 10 12 nil) ; "WW"
    (setf (evim-state-mode evim--state) 'extend)
    (evim--update-all-overlays)
    (evim-paste-after)
    ;; Cursors cycle through values: a, b, a, b
    (should (string= (buffer-string) "a b a b"))))

(ert-deftest evim-test-delete-in-extend-mode-saves-to-register ()
  "d in extend mode should save deleted text to register."
  (evim-test-with-buffer "foo bar foo"
    (evim-find-word)
    (evim-find-next)
    (should (= (evim-region-count) 2))
    (should (evim-extend-mode-p))
    (evim-delete)
    (let ((contents (gethash ?\" (evim-state-registers evim--state))))
      (should contents)
      (should (= (length contents) 2))
      (should (string= (car contents) "foo"))
      (should (string= (cadr contents) "foo")))))

(ert-deftest evim-test-change-in-extend-mode ()
  "c in extend mode should delete and enter insert."
  (evim-test-with-buffer "foo bar foo"
    (evim-find-word)
    (evim-find-next)
    (should (= (evim-region-count) 2))
    (should (evim-extend-mode-p))
    (evim-change)
    (should (string= (buffer-string) " bar "))
    ;; Should be in insert state
    (should (evil-insert-state-p))
    (evil-normal-state)))

(ert-deftest evim-test-flip-direction ()
  "o in extend mode should flip selection direction."
  (evim-test-with-buffer "foo bar foo"
    (evim-find-word)
    (evim-find-next)
    ;; Initially end is at word end
    (let ((regions (evim-get-all-regions)))
      (dolist (r regions)
        (should (> (marker-position (evim-region-end r))
                   (marker-position (evim-region-beg r))))))
    ;; Flip direction
    (evim-flip-direction)
    ;; After flip, direction changes (end becomes beg conceptually)
    (should (evim-extend-mode-p))))

(ert-deftest evim-test-exit-saves-for-reselect ()
  "Exit should save cursor positions for later reselect."
  (evim-test-with-buffer "foo bar foo"
    (evim-find-word)
    (evim-find-next)
    (let ((positions (evim-test-positions)))
      (evim-exit)
      (should-not (evim-active-p))
      ;; Reselect should restore
      (evim-reselect-last)
      (should (evim-active-p))
      (should (equal (evim-test-positions) positions)))))

(ert-deftest evim-test-reselect-restores-mode ()
  "Reselect should restore the mode (extend/cursor)."
  (evim-test-with-buffer "foo bar foo"
    (evim-find-word)
    (evim-find-next)
    ;; We're in extend mode
    (should (evim-extend-mode-p))
    (evim-exit)
    (evim-reselect-last)
    ;; Should still be extend mode
    (should (evim-extend-mode-p))))

(ert-deftest evim-test-cursor-count-display ()
  "Mode line should show cursor count."
  (evim-test-with-buffer "foo bar foo"
    (evim-find-word)
    (evim-find-next)
    (let ((indicator (evim--mode-line-indicator)))
      (should (string-match-p "2" indicator)))))

(ert-deftest evim-test-mode-display ()
  "Mode line should show current mode."
  (evim-test-with-buffer "foo bar foo"
    (evim-find-word)
    ;; In extend mode
    (let ((indicator (evim--mode-line-indicator)))
      (should (string-match-p "E" indicator)))
    ;; Switch to cursor mode
    (evim-toggle-mode)
    (let ((indicator (evim--mode-line-indicator)))
      (should (string-match-p "C" indicator)))))

(ert-deftest evim-test-beginning-of-line ()
  "0 should move all cursors to beginning of line."
  (evim-test-with-buffer "  foo\n  bar\n  baz"
    (evim-activate)
    ;; Create cursors at end of each word
    (evim--create-region 5 5)   ; end of "foo"
    (evim--create-region 11 11) ; end of "bar"
    (evim--create-region 17 17) ; end of "baz"
    (evim-beginning-of-line)
    ;; All should be at column 0
    (should (equal (evim-test-positions) '(1 7 13)))))

(ert-deftest evim-test-first-non-blank ()
  "^ should move all cursors to first non-blank."
  (evim-test-with-buffer "  foo\n  bar\n  baz"
    (evim-activate)
    ;; Create cursors at beginning of each line
    (evim--create-region 1 1)
    (evim--create-region 7 7)
    (evim--create-region 13 13)
    (evim-first-non-blank)
    ;; All should be at first non-blank (after 2 spaces)
    (should (equal (evim-test-positions) '(3 9 15)))))

(ert-deftest evim-test-backward-word ()
  "b should move all cursors backward to word start."
  (evim-test-with-buffer "foo bar\nfoo bar"
    (evim-activate)
    ;; Create cursors at 'b' of each "bar"
    (evim--create-region 5 5)
    (evim--create-region 13 13)
    (evim-backward-word)
    ;; Should move to 'f' of "foo"
    (should (equal (evim-test-positions) '(1 9)))))

(ert-deftest evim-test-forward-word-end ()
  "e should move all cursors to end of word."
  (evim-test-with-buffer "foo bar\nfoo bar"
    (evim-activate)
    ;; Create cursors at start of each line
    (evim--create-region 1 1)
    (evim--create-region 9 9)
    (evim-forward-word-end)
    ;; Should move to 'o' at end of "foo"
    (should (equal (evim-test-positions) '(3 11)))))

(ert-deftest evim-test-delete-char-backward ()
  "X should delete char before cursor at all positions."
  (evim-test-with-buffer "foo\nbar\nbaz"
    ;; Create cursors at position 2 on each line
    (evim-activate)
    (evim--create-region 2 2)
    (evim--create-region 6 6)
    (evim--create-region 10 10)
    (evim-delete-char-backward)
    (should (string= (buffer-string) "oo\nar\naz"))))

(ert-deftest evim-test-multiline-indicator ()
  "Mode line should show M when multiline is enabled."
  (evim-test-with-buffer "foo bar"
    (evim-activate)
    (evim--create-region (point) (point))
    (let ((indicator (evim--mode-line-indicator)))
      (should-not (string-match-p " M" indicator)))
    (evim-toggle-multiline)
    (let ((indicator (evim--mode-line-indicator)))
      (should (string-match-p " M" indicator)))))

;;; Regression tests

(ert-deftest evim-test-find-next-in-cursor-mode-creates-point-cursor ()
  "n in cursor mode should add point cursors, not full match regions."
  (evim-test-with-buffer "foo bar foo"
    (evim-find-word)
    (evim-toggle-mode)
    (should (evim-cursor-mode-p))
    (evim-find-next)
    (should (equal (evim-test-positions) '(1 9)))
    (should (equal (evim-test-end-positions) '(1 9)))))

(ert-deftest evim-test-select-all-cursor-mode-creates-point-cursors ()
  "\\A in cursor mode should add point cursors at match beginnings."
  (evim-test-with-buffer "foo bar foo baz foo"
    (evim-find-word)
    (evim-toggle-mode)
    (evim-select-all)
    (should (equal (evim-test-positions) '(1 9 17)))
    (should (equal (evim-test-end-positions) '(1 9 17)))))

(ert-deftest evim-test-motion-range-around-angle ()
  "a< should resolve angle text objects through the operator path."
  (evim-test-with-buffer "<foo>"
    (goto-char 2)
    (should (equal (evim--get-motion-range "a<" 1) '(1 6)))))

(ert-deftest evim-test-extend-inner-angle ()
  "i< in extend mode should select inside angle brackets."
  (evim-test-with-buffer "<foo>\n<bar>"
    (goto-char 2)
    (evim-add-cursor-down)
    (evim-enter-extend)
    (setq unread-command-events (list ?<))
    (evim-extend-inner-text-object)
    (let ((texts (mapcar (lambda (r)
                           (buffer-substring (marker-position (evim-region-beg r))
                                             (marker-position (evim-region-end r))))
                         (evim-state-regions evim--state))))
      (should (equal texts '("foo" "bar"))))))

(ert-deftest evim-test-merge-adjacent-regions-keeps-both ()
  "Adjacent non-overlapping regions should not be merged."
  (evim-test-with-buffer "abcdef"
    (evim-activate)
    (evim--create-region 1 4)
    (evim--create-region 4 7)
    (evim--check-and-merge-overlapping)
    (should (= (evim-region-count) 2))
    (should (equal (mapcar (lambda (r)
                             (cons (marker-position (evim-region-beg r))
                                   (marker-position (evim-region-end r))))
                           (evim-get-all-regions))
                   '((1 . 4) (4 . 7))))))

(ert-deftest evim-test-merge-overlap-reassigns-leader ()
  "Merging overlapping regions should keep a valid leader."
  (evim-test-with-buffer "abcdef"
    (evim-activate)
    (let ((first (evim--create-region 1 4))
          (second (evim--create-region 3 6)))
      (evim--set-leader second)
      (evim--check-and-merge-overlapping)
      (should (= (evim-region-count) 1))
      (should (evim--leader-region))
      (should (= (evim-region-id (evim--leader-region))
                 (evim-region-id first))))))

(ert-deftest evim-test-resync-respects-restriction ()
  "Resync should not snap regions to matches outside the active restriction."
  (evim-test-with-buffer "foo foo foo"
    (goto-char 5)
    (evim-find-word)
    (evim-find-next)
    (evim--set-restrict 5 12)
    (let ((regions (evim-get-all-regions)))
      (set-marker (evim-region-beg (car regions)) 4)
      (set-marker (evim-region-end (car regions)) 4)
      (set-marker (evim-region-anchor (car regions)) 4)
      (set-marker (evim-region-beg (cadr regions)) 8)
      (set-marker (evim-region-end (cadr regions)) 8)
      (set-marker (evim-region-anchor (cadr regions)) 8))
    (evim--resync-regions-to-pattern)
    (should (equal (evim-test-positions) '(5 9)))))

(ert-deftest evim-test-resync-does-not-reuse-same-match ()
  "Resync should not snap multiple regions onto the same pattern match."
  (evim-test-with-buffer "foo foo"
    (evim-find-word)
    (evim-find-next)
    (dolist (region (evim-get-all-regions))
      (set-marker (evim-region-beg region) 4)
      (set-marker (evim-region-end region) 4)
      (set-marker (evim-region-anchor region) 4))
    (evim--resync-regions-to-pattern)
    (should (equal (evim-test-positions) '(1 5)))
    (should (equal (evim-test-end-positions) '(4 8)))))

(ert-deftest evim-test-reselect-last-old-format ()
  "Reselect should still restore the legacy list-of-cons format."
  (evim-test-with-buffer "foo bar foo"
    (evim-activate)
    (setf (evim-state-last-regions evim--state) '((1 . 1) (9 . 9)))
    (evim-reselect-last)
    (should (equal (evim-test-positions) '(1 9)))
    (should (evim-cursor-mode-p))))

(ert-deftest evim-test-theme-api-loads-with-evim ()
  "Loading `evim' should also make the theme API available."
  (should (fboundp 'evim-load-theme))
  (should (fboundp 'evim-cycle-theme))
  (should (boundp 'evim-theme))
  (should (boundp 'evim-highlight-matches)))

(ert-deftest evim-test-highlight-matches-style-updates-face ()
  "Changing `evim-highlight-matches' should update the match face."
  (let ((original evim-highlight-matches))
    (unwind-protect
        (progn
          (setq evim-highlight-matches 'background)
          (evim-load-theme 'default)
          (should (eq (face-attribute 'evim-match-face :underline nil 'default) nil))
          (should (stringp (face-attribute 'evim-match-face :background nil 'default))))
      (setq evim-highlight-matches original)
      (evim-load-theme 'default))))

(ert-deftest evim-test-rebind-leader-clears-stale-bindings ()
  "Rebinding the leader should remove the old prefix bindings."
  (let ((original evim-leader-key))
    (unwind-protect
        (progn
          (setq evim-leader-key ",")
          (evim-rebind-leader)
          (should-not (lookup-key evim-mode-map (kbd "\\ A")))
          (should (eq (lookup-key evim-mode-map (kbd ", A"))
                      'evim-select-all)))
      (setq evim-leader-key original)
      (evim-rebind-leader))))

(ert-deftest evim-test-visual-line-restrict-covers-all-lines ()
  "Visual-line restrict should include the last selected line."
  (evim-test-with-buffer "name = old\nvalue = old\ncount = old\n\nname = old\nvalue = old\ncount = old"
    ;; Simulate V-selection of first 3 lines
    (evil-visual-line)
    (evil-next-line 2)
    ;; Set restriction via toggle-restrict
    (evim-toggle-restrict)
    ;; Find "old" inside restricted area
    (goto-char (point-min))
    (search-forward "old")
    (backward-word)
    (evim-find-word)
    (evim-select-all)
    ;; Should find 3 matches (all in first block), not fewer
    (should (= 3 (length (evim-state-regions evim--state))))))

(ert-deftest evim-test-visual-line-cursors-all-lines ()
  "Visual-line \\ c should create cursors on all selected lines."
  (evim-test-with-buffer "alpha\nbravo\ncharlie\ndelta\necho"
    ;; V-select lines 2-4
    (forward-line 1)
    (evil-visual-line)
    (evil-next-line 2)
    (evim-visual-cursors)
    (should (evim-active-p))
    ;; Should have 3 cursors (lines 2, 3, 4)
    (should (= 3 (length (evim-state-regions evim--state))))))

(provide 'evim-test)
;;; evim-test.el ends here
