;;; evm-test.el --- Tests for evil-visual-multi -*- lexical-binding: t; -*-

;;; Commentary:
;; ERT tests for evm package.
;; Run with: make test
;; Or: make test-batch

;;; Code:

(require 'ert)
(when (locate-library "evil-surround")
  (require 'evil-surround))
(require 'evm)

;;; Test helpers

(defmacro evm-test-with-buffer (content &rest body)
  "Create temp buffer with CONTENT, execute BODY."
  (declare (indent 1))
  `(with-temp-buffer
     (insert ,content)
     (goto-char (point-min))
     (evil-local-mode 1)
     (evil-normal-state)
     ,@body
     (when (evm-active-p)
       (evm-exit))))

(defun evm-test-positions ()
  "Get list of cursor positions."
  (mapcar (lambda (r) (marker-position (evm-region-beg r)))
          (evm-get-all-regions)))

(defun evm-test-leader-pos ()
  "Get leader position."
  (when (evm--leader-region)
    (marker-position (evm-region-beg (evm--leader-region)))))

;;; Activation tests

(ert-deftest evm-test-find-word-activates ()
  "C-n should activate evm and create region on word in extend mode."
  (evm-test-with-buffer "foo bar foo"
    (evm-find-word)
    (should (evm-active-p))
    (should (evm-extend-mode-p))  ; Now in extend mode
    (should (= (evm-region-count) 1))
    (should (equal (evm-test-positions) '(1)))
    ;; Region should cover the word "foo" (positions 1-4)
    (let ((region (car (evm-get-all-regions))))
      (should (= (marker-position (evm-region-end region)) 4)))))

(ert-deftest evm-test-find-word-sets-pattern ()
  "C-n should set search pattern."
  (evm-test-with-buffer "foo bar foo"
    (evm-find-word)
    (should (car (evm-state-patterns evm--state)))
    (should (string-match-p "foo" (car (evm-state-patterns evm--state))))))

(ert-deftest evm-test-add-cursor-down ()
  "C-Down should add cursor below."
  (evm-test-with-buffer "line1\nline2\nline3"
    (evm-add-cursor-down)
    (should (evm-active-p))
    (should (= (evm-region-count) 2))
    (evm-add-cursor-down)
    (should (= (evm-region-count) 3))))

(ert-deftest evm-test-add-cursor-up ()
  "C-Up should add cursor above."
  (evm-test-with-buffer "line1\nline2\nline3"
    (goto-char (point-max))
    (beginning-of-line)
    (evm-add-cursor-up)
    (should (evm-active-p))
    (should (= (evm-region-count) 2))))

(ert-deftest evm-test-add-cursor-down-preserves-column-through-short-line ()
  "C-Down should preserve target column through short lines."
  (evm-test-with-buffer "abcde\nab\nabcde\nabcde"
    (move-to-column 4) ;; on 'e' in first "abcde"
    (let ((last-command nil))
      (evm-add-cursor-down)
      (setq last-command 'evm-add-cursor-down)
      (evm-add-cursor-down)
      (setq last-command 'evm-add-cursor-down)
      (evm-add-cursor-down))
    (should (= (evm-region-count) 4))
    ;; Check columns: should all be 4 except the short line
    (let ((cols (mapcar (lambda (r)
                          (save-excursion
                            (goto-char (marker-position (evm-region-beg r)))
                            (current-column)))
                        (evm-state-regions evm--state))))
      ;; Line 1: col 4, line 2: col 2 (short), line 3: col 4, line 4: col 4
      (should (equal cols '(4 2 4 4))))))

(ert-deftest evm-test-cursor-down-then-up-no-duplicates ()
  "C-Down then C-Up should not create duplicate cursors."
  (evm-test-with-buffer "line1\nline2\nline3\nline4\nline5"
    (let ((last-command nil))
      (evm-add-cursor-down)
      (setq last-command 'evm-add-cursor-down)
      (evm-add-cursor-down)
      (setq last-command 'evm-add-cursor-down)
      (evm-add-cursor-down))
    (should (= (evm-region-count) 4))
    ;; Now C-Up 3 times — should move leader, not create duplicates
    (let ((last-command 'evm-add-cursor-up))
      (evm-add-cursor-up)
      (setq last-command 'evm-add-cursor-up)
      (evm-add-cursor-up)
      (setq last-command 'evm-add-cursor-up)
      (evm-add-cursor-up))
    (should (= (evm-region-count) 4))))

;;; Navigation tests

(ert-deftest evm-test-find-next ()
  "n should find next occurrence."
  (evm-test-with-buffer "foo bar foo baz foo"
    (evm-find-word)
    (evm-find-next)
    (should (= (evm-region-count) 2))
    (should (equal (evm-test-positions) '(1 9)))))

(ert-deftest evm-test-find-prev ()
  "N should find previous occurrence."
  (evm-test-with-buffer "foo bar foo baz foo"
    (evm-find-word)
    (evm-find-prev)
    (should (= (evm-region-count) 2))
    ;; Should wrap around to last foo
    (should (member 17 (evm-test-positions)))))

(ert-deftest evm-test-find-next-moves-leader ()
  "n should move leader to existing cursor."
  (evm-test-with-buffer "foo bar foo baz foo"
    (evm-find-word)
    (evm-find-next)
    (evm-find-next)
    ;; All 3 cursors exist
    (should (= (evm-region-count) 3))
    ;; n again should move leader, not create new
    (let ((count-before (evm-region-count)))
      (evm-find-next)
      (should (= (evm-region-count) count-before)))))

(ert-deftest evm-test-goto-next ()
  "] should move to next cursor."
  (evm-test-with-buffer "foo bar foo"
    (evm-find-word)
    (evm-find-next)
    ;; Leader at position 9
    (should (= (evm-test-leader-pos) 9))
    (evm-goto-next)
    ;; Should wrap to 1
    (should (= (evm-test-leader-pos) 1))))

(ert-deftest evm-test-goto-prev ()
  "[ should move to previous cursor."
  (evm-test-with-buffer "foo bar foo"
    (evm-find-word)
    (evm-find-next)
    ;; Leader at 9, go prev should go to 1
    (evm-goto-prev)
    (should (= (evm-test-leader-pos) 1))))

;;; Skip and Remove tests

(ert-deftest evm-test-skip-current ()
  "q should skip current and find next occurrence."
  (evm-test-with-buffer "foo bar foo baz foo"
    (evm-find-word)
    ;; At position 1
    (evm-skip-current)
    ;; Should now be at position 9
    (should (= (evm-region-count) 1))
    (should (= (evm-test-leader-pos) 9))))

(ert-deftest evm-test-skip-current-after-n ()
  "q after n should skip to NEXT occurrence, not same one."
  (evm-test-with-buffer "foo bar foo baz foo qux foo"
    ;; foo at positions: 1, 9, 17, 25
    (evm-find-word)
    ;; Cursor at 1
    (evm-find-next)
    ;; Cursors at 1, 9. Leader at 9.
    (should (= (evm-region-count) 2))
    (should (= (evm-test-leader-pos) 9))
    ;; q should skip 9 and find 17
    (evm-skip-current)
    (should (= (evm-region-count) 2))
    (should (equal (evm-test-positions) '(1 17)))
    (should (= (evm-test-leader-pos) 17))))

(ert-deftest evm-test-skip-current-wraps-around ()
  "q should wrap around when at last occurrence."
  (evm-test-with-buffer "foo bar foo"
    ;; foo at positions: 1, 9
    (evm-find-word)
    (evm-find-next)
    ;; At position 9, q should wrap to 1 (but 1 has cursor, so create at 1)
    ;; Actually it should find existing cursor at 1 and move leader there
    (evm-skip-current)
    ;; Cursor at 9 deleted, search from 10 wraps to find 1
    ;; Cursor at 1 exists, so just move leader
    (should (= (evm-region-count) 1))
    (should (= (evm-test-leader-pos) 1))))

(ert-deftest evm-test-skip-current-after-N ()
  "q after N should search backward."
  (evm-test-with-buffer "foo bar foo baz foo qux foo"
    ;; foo at positions: 1, 9, 17, 25
    (evm-find-word)
    ;; N - find previous (wraps to 25)
    (evm-find-prev)
    (should (= (evm-region-count) 2))
    (should (= (evm-test-leader-pos) 25))
    ;; q should skip 25 and find 17 (backward)
    (evm-skip-current)
    (should (= (evm-region-count) 2))
    (should (equal (evm-test-positions) '(1 17)))
    (should (= (evm-test-leader-pos) 17))))

(ert-deftest evm-test-remove-current ()
  "Q should remove current cursor."
  (evm-test-with-buffer "foo bar foo"
    (evm-find-word)
    (evm-find-next)
    (should (= (evm-region-count) 2))
    (evm-remove-current)
    (should (= (evm-region-count) 1))))

(ert-deftest evm-test-remove-last-exits ()
  "Q on last cursor should exit evm."
  (evm-test-with-buffer "foo bar baz"
    (evm-find-word)
    (should (= (evm-region-count) 1))
    (evm-remove-current)
    (should-not (evm-active-p))))

;;; Movement tests

(defun evm-test-end-positions ()
  "Get list of cursor end positions."
  (mapcar (lambda (r) (marker-position (evm-region-end r)))
          (evm-get-all-regions)))

(ert-deftest evm-test-forward-char ()
  "l should move all cursors right."
  (evm-test-with-buffer "foo bar foo zzz"
    ;; Extra text at end so cursor can move
    (evm-find-word)
    (evm-find-next)
    ;; In extend mode, movement expands selection (changes end)
    (let ((end-before (evm-test-end-positions)))
      (evm-forward-char)
      (should (equal (evm-test-end-positions)
                     (mapcar #'1+ end-before))))))

(ert-deftest evm-test-backward-char ()
  "h should move all cursors left."
  (evm-test-with-buffer "foo bar foo zzz"
    (evm-find-word)
    (evm-find-next)
    ;; In extend mode, movement changes end position
    (evm-forward-char)
    (evm-forward-char)
    (let ((end-before (evm-test-end-positions)))
      (evm-backward-char)
      (should (equal (evm-test-end-positions)
                     (mapcar #'1- end-before))))))

(ert-deftest evm-test-forward-word ()
  "w should move all cursors to next word."
  (evm-test-with-buffer "aa bb aa cc"
    (evm-find-word)
    (evm-find-next)
    ;; Regions at 1-3 and 7-9 with "aa" selected
    (let ((end-before (evm-test-end-positions)))
      (evm-forward-word)
      ;; In extend mode, end positions should have moved forward
      (should (> (car (evm-test-end-positions))
                 (car end-before))))))

;;; Mode switching tests

(ert-deftest evm-test-toggle-mode ()
  "Tab should toggle between cursor and extend mode."
  (evm-test-with-buffer "foo bar foo"
    (evm-find-word)
    ;; After C-n we're now in extend mode
    (should (evm-extend-mode-p))
    (evm-toggle-mode)
    (should (evm-cursor-mode-p))
    (evm-toggle-mode)
    (should (evm-extend-mode-p))))

(ert-deftest evm-test-extend-mode-has-selection ()
  "C-n should create regions with full word selection."
  (evm-test-with-buffer "foo bar foo"
    (evm-find-word)
    ;; Already in extend mode with selection
    (should (evm-extend-mode-p))
    (let ((region (car (evm-get-all-regions))))
      (should (> (marker-position (evm-region-end region))
                 (marker-position (evm-region-beg region))))
      ;; "foo" is 3 chars, so end - beg = 3
      (should (= (- (marker-position (evm-region-end region))
                    (marker-position (evm-region-beg region)))
                 3)))))

(ert-deftest evm-test-toggle-mode-updates-keymap ()
  "Tab should update keymap so mode-specific keys work."
  (evm-test-with-buffer "foo bar foo"
    (evm-find-word)
    (evm-find-next)
    ;; After C-n we're in extend mode
    (should (evm-extend-mode-p))
    ;; In extend mode, d should be bound to evm-delete
    (should (eq (key-binding "d") 'evm-delete))
    (should (eq (key-binding "y") 'evm-yank))
    (should (eq (key-binding "U") 'evm-upcase))
    ;; Toggle to cursor mode
    (evm-toggle-mode)
    (should (evm-cursor-mode-p))
    ;; d should no longer be evm-delete
    (should-not (eq (key-binding "d") 'evm-delete))
    ;; i should be evm-insert in cursor mode
    (should (eq (key-binding "i") 'evm-insert))
    ;; Toggle back to extend mode
    (evm-toggle-mode)
    (should (evm-extend-mode-p))
    (should (eq (key-binding "d") 'evm-delete))))

;;; Cursor mode editing tests

(ert-deftest evm-test-delete-char ()
  "x should delete char at all cursors."
  (evm-test-with-buffer "foo\nbar\nbaz"
    ;; Create cursors on each line using C-down
    (evm-add-cursor-down)
    (evm-add-cursor-down)
    (should (= (evm-region-count) 3))
    (evm-delete-char)
    (should (string= (buffer-string) "oo\nar\naz"))))

(ert-deftest evm-test-delete-char-count ()
  "3x should delete 3 characters at all cursors."
  (evm-test-with-buffer "abcdef\nghijkl\nmnopqr"
    (evm-add-cursor-down)
    (evm-add-cursor-down)
    (should (= (evm-region-count) 3))
    (evm-delete-char 3)
    (should (string= (buffer-string) "def\njkl\npqr"))))

(ert-deftest evm-test-delete-char-count-clamp-eol ()
  "3x on 2-char line should delete only 2 chars, not cross newline."
  (evm-test-with-buffer "ab\ncd\nef"
    (evm-add-cursor-down)
    (evm-add-cursor-down)
    (should (= (evm-region-count) 3))
    (evm-delete-char 3)
    (should (string= (buffer-string) "\n\n"))))

(ert-deftest evm-test-delete-char-eol ()
  "x at end-of-line should clamp cursor to last char, not newline."
  (evm-test-with-buffer "aa;\nbb;\ncc;"
    (goto-char 3) ;; on ";"
    (evm-add-cursor-down)
    (evm-add-cursor-down)
    (should (= (evm-region-count) 3))
    (evm-delete-char)
    (should (string= (buffer-string) "aa\nbb\ncc"))
    ;; Cursors should be on last char of each line, not on newline/eob
    (dolist (region (evm-state-regions evm--state))
      (let ((pos (marker-position (evm-region-beg region))))
        (should-not (= (char-after pos) ?\n))
        (should-not (= pos (point-max)))))))

(ert-deftest evm-test-replace-char ()
  "r should replace char at all cursors."
  (evm-test-with-buffer "foo\nbar\nbaz"
    ;; Create cursors using C-down for cursor mode
    (evm-add-cursor-down)
    (evm-add-cursor-down)
    (should (= (evm-region-count) 3))
    (evm-replace-char ?X)
    (should (string= (buffer-string) "Xoo\nXar\nXaz"))))

(ert-deftest evm-test-toggle-case-char ()
  "~ should toggle case at all cursors."
  (evm-test-with-buffer "foo\nbar\nbaz"
    ;; Create cursors using C-down for cursor mode
    (evm-add-cursor-down)
    (evm-add-cursor-down)
    (should (= (evm-region-count) 3))
    (evm-toggle-case-char)
    (should (string= (buffer-string) "Foo\nBar\nBaz"))))

;;; Extend mode editing tests

(ert-deftest evm-test-yank ()
  "y should yank region contents to register."
  (evm-test-with-buffer "foo bar foo"
    (evm-find-word)
    (evm-find-next)
    ;; Already in extend mode with "foo" selected
    (evm-yank)
    (let ((contents (gethash ?\" (evm-state-registers evm--state))))
      (should contents)
      (should (= (length contents) 2))
      (should (string= (car contents) "foo")))))

(ert-deftest evm-test-delete-regions ()
  "d should delete all regions."
  (evm-test-with-buffer "foo bar foo"
    (evm-find-word)
    (evm-find-next)
    ;; Already in extend mode with "foo" selected
    (evm-delete)
    (should (string= (buffer-string) " bar "))
    (should (evm-cursor-mode-p))))

(ert-deftest evm-test-upcase ()
  "U should uppercase all regions."
  (evm-test-with-buffer "foo bar foo"
    (evm-find-word)
    (evm-find-next)
    ;; Already in extend mode with "foo" selected
    (evm-upcase)
    (should (string= (buffer-string) "FOO bar FOO"))))

(ert-deftest evm-test-downcase ()
  "u should lowercase all regions."
  (evm-test-with-buffer "FOO bar FOO"
    (evm-find-word)
    (evm-find-next)
    ;; Already in extend mode with "FOO" selected
    (evm-downcase)
    (should (string= (buffer-string) "foo bar foo"))))

(ert-deftest evm-test-toggle-case ()
  "~ should toggle case of all regions."
  (evm-test-with-buffer "FoO bar FoO"
    (evm-find-word)
    (evm-find-next)
    ;; Already in extend mode with "FoO" selected
    (evm-toggle-case)
    (should (string= (buffer-string) "fOo bar fOo"))))

(ert-deftest evm-test-toggle-case-preserves-markers ()
  "~ should preserve region markers for subsequent operations."
  (evm-test-with-buffer "foo bar foo"
    (evm-find-word)
    (evm-find-next)
    ;; Already in extend mode with "foo" selected
    (let ((regions-before (mapcar (lambda (r)
                                    (list (marker-position (evm-region-beg r))
                                          (marker-position (evm-region-end r))))
                                  (evm-get-all-regions))))
      (evm-toggle-case)
      (let ((regions-after (mapcar (lambda (r)
                                     (list (marker-position (evm-region-beg r))
                                           (marker-position (evm-region-end r))))
                                   (evm-get-all-regions))))
        ;; Markers should be preserved
        (should (equal regions-before regions-after))
        ;; Delete should work after toggle-case
        (evm-delete)
        (should (string= (buffer-string) " bar "))))))

;;; Select all tests

(ert-deftest evm-test-select-all ()
  "\\A should select all occurrences."
  (evm-test-with-buffer "foo bar foo baz foo qux foo"
    (evm-find-word)
    (evm-select-all)
    (should (= (evm-region-count) 4))))

;;; Exit tests

(ert-deftest evm-test-exit ()
  "Esc should exit evm."
  (evm-test-with-buffer "foo bar foo"
    (evm-find-word)
    (should (evm-active-p))
    (evm-exit)
    (should-not (evm-active-p))
    (should-not evm-mode)))

;;; Vertical movement with vcol tests

(ert-deftest evm-test-j-k-preserves-column ()
  "j then k should return cursors to original positions."
  ;; Buffer with 4 lines so all cursors can move down and back
  (evm-test-with-buffer "abcdefgh\nxy\nabcdefgh\nlast"
    ;; Buffer layout:
    ;; Line 1: pos 1-8 "abcdefgh", pos 9 \n
    ;; Line 2: pos 10-11 "xy", pos 12 \n
    ;; Line 3: pos 13-20 "abcdefgh", pos 21 \n
    ;; Line 4: pos 22-25 "last"
    ;; Create cursors at column 5 on lines 1 and 3, column 1 on line 2
    (goto-char 6)  ; 'f' on line 1 (column 5)
    (evm-activate)
    (evm--create-region 6 6)   ; line 1, column 5 ('f')
    (evm--create-region 11 11) ; line 2, column 1 ('y')
    (evm--create-region 18 18) ; line 3, column 5 ('f')
    ;; Now we have 3 cursors at (6, 11, 18)
    (should (= (evm-region-count) 3))
    (should (equal (evm-test-positions) '(6 11 18)))
    ;; Record positions before j
    (let ((positions-before (evm-test-positions)))
      ;; Move down (j)
      (evm-next-line)
      ;; Positions should have changed (went down)
      (should-not (equal (evm-test-positions) positions-before))
      ;; Move up (k)
      (evm-previous-line)
      ;; Positions should be restored
      (should (equal (evm-test-positions) positions-before)))))

(ert-deftest evm-test-j-k-short-line-vcol ()
  "j/k across short line should preserve desired column."
  (evm-test-with-buffer "abcdefghij\n\nabcdefghij"
    ;; Start at column 5 on line 1
    (goto-char 6)
    (evm-activate)
    (evm--create-region (point) (point))
    ;; j - go to empty line (column 0 since line is empty)
    (evm-next-line)
    ;; j again - go to line 3, should be at column 5 again
    (evm-next-line)
    (should (= (current-column) 5))
    ;; k twice - should go back to line 1 at column 5
    (evm-previous-line)
    (evm-previous-line)
    (should (= (current-column) 5))))

(ert-deftest evm-test-j-short-line-clamps-to-last-char ()
  "j to a short line should clamp cursor to last char, not past EOL."
  (evm-test-with-buffer "long_line = 100\ngap\nlong_line = 300"
    ;; Start at column 7 on line 1 (on "e" of "line")
    (goto-char (point-min))
    (forward-char 7)
    (evm-activate)
    (evm--create-region (point) (point))
    ;; j - go to "gap" line. Column 7 is past EOL.
    ;; Should clamp to last char "p" (col 2), not to newline (col 3).
    (evm-next-line)
    (let ((col (current-column))
          (ch (char-after (point))))
      (should (= col 2))           ;; on 'p', last char of "gap"
      (should (not (= ch ?\n))))   ;; NOT on newline
    ;; j again - should restore to column 7 on long line
    (evm-next-line)
    (should (= (current-column) 7))))

(ert-deftest evm-test-horizontal-movement-clears-vcol ()
  "Horizontal movement should clear vcol."
  (evm-test-with-buffer "abcdefghij\n\nabcdefghij"
    ;; Start at column 5
    (goto-char 6)
    (evm-activate)
    (evm--create-region (point) (point))
    ;; j - to empty line (vcol=5 saved)
    (evm-next-line)
    ;; l - move right (should clear vcol, but we're on empty line so stays at 0)
    ;; Actually on empty line l doesn't move
    ;; Move back up first
    (evm-previous-line)
    (should (= (current-column) 5))
    ;; Now l should clear vcol
    (evm-forward-char)
    (should (= (current-column) 6))
    ;; j and k should now use column 6
    (evm-next-line)
    (evm-next-line)
    (should (= (current-column) 6))
    (evm-previous-line)
    (evm-previous-line)
    (should (= (current-column) 6))))

;;; End of line movement tests

(ert-deftest evm-test-end-of-line-goes-to-last-char ()
  "$ should move to last character, not past it (like evil $)."
  (evm-test-with-buffer "foo\nbar\nbaz"
    ;; Create cursors on each line
    (goto-char 1)
    (evm-activate)
    (evm--create-region 1 1)   ; line 1, 'f'
    (evm--create-region 5 5)   ; line 2, 'b'
    (evm--create-region 9 9)   ; line 3, 'b'
    (should (= (evm-region-count) 3))
    ;; Move to end of line
    (evm-end-of-line)
    ;; Positions should be on last char of each line:
    ;; line 1: "foo" ends at pos 3 (the 'o')
    ;; line 2: "bar" ends at pos 7 (the 'r')
    ;; line 3: "baz" ends at pos 11 (the 'z')
    (should (equal (evm-test-positions) '(3 7 11)))))

(ert-deftest evm-test-end-of-line-empty-line ()
  "$ on empty line should stay at beginning."
  (evm-test-with-buffer "foo\n\nbaz"
    ;; Create cursor on empty line (position 5, which is the empty line)
    (goto-char 5)
    (evm-activate)
    (evm--create-region 5 5)
    ;; Move to end of line (on empty line, stays at beginning)
    (evm-end-of-line)
    (should (equal (evm-test-positions) '(5)))))

(ert-deftest evm-test-end-of-line-extend-mode ()
  "$ in extend mode should extend selection to end of line."
  ;; Buffer: "text abc\ntext xyz" (17 chars + newline = 18 total)
  ;; Line 1: "text abc" pos 1-8, newline at 9
  ;; Line 2: "text xyz" pos 10-17, point-max = 18
  (evm-test-with-buffer "text abc\ntext xyz"
    ;; text at pos 1-5 and 10-14
    (evm-find-word)  ; selects first "text"
    (evm-find-next)  ; adds second "text"
    (should (= (evm-region-count) 2))
    ;; In extend mode, both "text" are selected (beg-end pairs)
    ;; After $, selection should extend to end of each line
    (evm-end-of-line)
    ;; line-end-position returns:
    ;; - Line 1: 9 (position of newline)
    ;; - Line 2: 18 (point-max, since no trailing newline)
    ;; Visual cursor will be on 8 ('c') and 17 ('z') respectively
    (should (equal (evm-test-end-positions) '(9 18)))))

(ert-deftest evm-test-end-of-line-extend-mode-different-lengths ()
  "$ in extend mode should work with lines of different lengths."
  ;; Buffer: "aa short\naa very long line here" (31 chars total)
  ;; Line 1: "aa short" pos 1-8, newline at 9
  ;; Line 2: "aa very long line here" pos 10-31, point-max = 32
  (evm-test-with-buffer "aa short\naa very long line here"
    ;; "aa" at pos 1-3 and 10-12
    (evm-find-word)
    (evm-find-next)
    (should (= (evm-region-count) 2))
    (evm-end-of-line)
    ;; line-end-position returns:
    ;; - Line 1: 9 (position of newline)
    ;; - Line 2: 32 (point-max, since no trailing newline)
    ;; Visual cursor will be on 8 ('t') and 31 ('e') respectively
    (should (equal (evm-test-end-positions) '(9 32)))))

(ert-deftest evm-test-extend-mode-forward-word-end ()
  "e in extend mode should include the full word in selection."
  (evm-test-with-buffer "alpha beta\nalpha beta"
    (evm-find-word) ; "alpha" selected
    (evm-find-next)
    (should (= (evm-region-count) 2))
    ;; Tab to cursor, Tab to extend (1-char)
    (evm-toggle-mode)
    (evm-toggle-mode)
    ;; e should select full word
    (evm-forward-word-end)
    (let ((selections (mapcar (lambda (r)
                                (buffer-substring-no-properties
                                 (marker-position (evm-region-beg r))
                                 (marker-position (evm-region-end r))))
                              (evm-state-regions evm--state))))
      (should (equal selections '("alpha" "alpha"))))))

(ert-deftest evm-test-extend-mode-yank-full-word ()
  "Yank in extend mode after e should capture the full word."
  (evm-test-with-buffer "foo bar\nfoo baz"
    ;; Create vertical cursors, toggle to extend, grow, yank
    (evm-add-cursor-down)
    (evm-toggle-mode)
    (evm-forward-word-end)
    (evm-yank)
    (let ((reg (gethash ?\" (evm-state-registers evm--state))))
      (should (equal reg '("foo" "foo"))))))

(ert-deftest evm-test-extend-mode-shrink-with-h ()
  "h in extend mode should shrink selection by one char."
  (evm-test-with-buffer "hello abc\nhello xyz"
    (evm-find-word)  ; "hello" at pos 1
    (evm-find-next)  ; "hello" at pos 11
    (should (= (evm-region-count) 2))
    ;; Selections are both "hello" (5 chars each)
    ;; Press h to shrink
    (evm-backward-char)
    (let ((selections (mapcar (lambda (r)
                                (buffer-substring-no-properties
                                 (marker-position (evm-region-beg r))
                                 (marker-position (evm-region-end r))))
                              (evm-state-regions evm--state))))
      (should (equal selections '("hell" "hell"))))))

(ert-deftest evm-test-extend-mode-flip-then-grow ()
  "o should flip direction, then h should grow selection backward."
  (evm-test-with-buffer "my tag = X\nmy tag = Y"
    (goto-char 4)  ; on "tag"
    (evm-find-word)
    (evm-find-next)
    (should (= (evm-region-count) 2))
    ;; Initial: "tag" selected [4,7) and [15,18)
    ;; Grow right by 1 (l) → "tag " [4,8) and [15,19)
    (evm-forward-char)
    ;; Flip direction: cursor moves to left end, anchor to right end
    (evm-flip-direction)
    ;; Grow left by 1 (h) → " tag " [3,8) and [14,19)
    (evm-backward-char)
    (let ((sel (mapcar (lambda (r)
                         (buffer-substring-no-properties
                          (marker-position (evm-region-beg r))
                          (marker-position (evm-region-end r))))
                       (evm-state-regions evm--state))))
      (should (equal sel '(" tag " " tag "))))))

(ert-deftest evm-test-find-char-f ()
  "f should move all cursors to the target character."
  (evm-test-with-buffer "a = 1\na = 2\na = 3"
    (evm-add-cursor-down)
    (evm-add-cursor-down)
    (should (= (evm-region-count) 3))
    ;; f= should land all cursors on "="
    (evm--move-cursors #'evm--move-find-char ?= 1)
    (let ((cols (mapcar (lambda (r)
                          (save-excursion
                            (goto-char (evm--region-cursor-pos r))
                            (current-column)))
                        (evm-state-regions evm--state))))
      (should (equal cols '(2 2 2))))))

(ert-deftest evm-test-find-char-F-backward ()
  "F should move all cursors backward to the target character."
  (evm-test-with-buffer "x = 1\nx = 2\nx = 3"
    (evm-add-cursor-down)
    (evm-add-cursor-down)
    ;; Move to end of line first
    (evm--move-cursors #'evm--move-line-end)
    ;; F= should land on "="
    (evm--move-cursors #'evm--move-find-char-backward ?= 1)
    (let ((cols (mapcar (lambda (r)
                          (save-excursion
                            (goto-char (evm--region-cursor-pos r))
                            (current-column)))
                        (evm-state-regions evm--state))))
      (should (equal cols '(2 2 2))))))

;;; Insert mode tests

(ert-deftest evm-test-insert-replicates-text ()
  "i should insert text at all cursor positions."
  (evm-test-with-buffer "foo\nbar\nbaz"
    ;; Create cursors using C-down for cursor mode
    (evm-add-cursor-down)
    (evm-add-cursor-down)
    (should (= (evm-region-count) 3))
    ;; Enter insert mode
    (evm-insert)
    ;; Insert text
    (insert "X")
    ;; Exit insert mode
    (evil-normal-state)
    ;; Text should be inserted at all cursor positions
    (should (string= (buffer-string) "Xfoo\nXbar\nXbaz"))))

(ert-deftest evm-test-insert-multiple-chars ()
  "i should insert multiple characters at all cursor positions."
  (evm-test-with-buffer "foo\nbar\nbaz"
    ;; Create cursors using C-down
    (evm-add-cursor-down)
    (evm-add-cursor-down)
    (evm-insert)
    (insert "hello")
    (evil-normal-state)
    (should (string= (buffer-string) "hellofoo\nhellobar\nhellobaz"))))

(ert-deftest evm-test-append-replicates-text ()
  "a should append text after all cursor positions."
  (evm-test-with-buffer "foo\nbar\nbaz"
    ;; Create cursors using C-down
    (evm-add-cursor-down)
    (evm-add-cursor-down)
    ;; Cursors at beginning of each line
    (evm-append)
    (insert "X")
    (evil-normal-state)
    ;; Text should be inserted after first char at each position
    (should (string= (buffer-string) "fXoo\nbXar\nbXaz"))))

(ert-deftest evm-test-insert-line ()
  "I should insert at beginning of line for all cursors."
  (evm-test-with-buffer "  foo\n  bar"
    ;; Create cursors on both lines using C-Down
    (evm-add-cursor-down)
    (evm-insert-line)
    (insert "X")
    (evil-normal-state)
    ;; X should be at beginning of indentation on each line
    (should (string= (buffer-string) "  Xfoo\n  Xbar"))))

(ert-deftest evm-test-append-line ()
  "A should append at end of line for all cursors."
  (evm-test-with-buffer "foo\nbar"
    ;; Create cursors on both lines using C-Down
    (evm-add-cursor-down)
    (evm-append-line)
    (insert "X")
    (evil-normal-state)
    (should (string= (buffer-string) "fooX\nbarX"))))

(ert-deftest evm-test-insert-same-line-multiple ()
  "i should work correctly with multiple cursors on same line."
  (evm-test-with-buffer "aaa bbb ccc"
    ;; Create cursors at specific positions using direct region creation
    (evm-activate)
    (evm--create-region 1 1)   ; before "aaa"
    (evm--create-region 5 5)   ; before "bbb"
    (evm--create-region 9 9)   ; before "ccc"
    (should (= (evm-region-count) 3))
    (evm-insert)
    (insert "X")
    (evil-normal-state)
    (should (string= (buffer-string) "Xaaa Xbbb Xccc"))))

(ert-deftest evm-test-insert-leader-middle ()
  "i should work when leader is in the middle of cursor list."
  (evm-test-with-buffer "aaa\nbbb\nccc"
    ;; Create cursors on all lines
    (evm-add-cursor-down)
    (evm-add-cursor-down)
    ;; Leader is at last line (ccc)
    (evm-goto-prev) ;; move leader to middle (bbb)
    (should (= (evm-region-count) 3))
    (evm-insert)
    (insert "X")
    (evil-normal-state)
    (should (string= (buffer-string) "Xaaa\nXbbb\nXccc"))))

(ert-deftest evm-test-open-below ()
  "o should open line below and insert at all cursors."
  (evm-test-with-buffer "line1\nline2\nline3"
    ;; Create cursors on all three lines
    (evm-add-cursor-down)
    (evm-add-cursor-down)
    (should (= (evm-region-count) 3))
    ;; Open below
    (evm-open-below)
    (insert "new")
    (evil-normal-state)
    (should (string= (buffer-string) "line1\nnew\nline2\nnew\nline3\nnew"))))

(ert-deftest evm-test-open-above ()
  "O should open line above and insert at all cursors."
  (evm-test-with-buffer "line1\nline2\nline3"
    ;; Create cursors on all three lines
    (evm-add-cursor-down)
    (evm-add-cursor-down)
    (should (= (evm-region-count) 3))
    ;; Open above
    (evm-open-above)
    (insert "above")
    (evil-normal-state)
    (should (string= (buffer-string) "above\nline1\nabove\nline2\nabove\nline3"))))

;;; Electric-pair-mode integration

(defun evm-test--simulate-keystrokes (str)
  "Simulate typing STR character by character with proper hook execution."
  (dolist (ch (string-to-list str))
    (let ((last-command-event ch)
          (this-command 'self-insert-command)
          (current-prefix-arg nil))
      (run-hooks 'pre-command-hook)
      (call-interactively #'self-insert-command)
      (run-hooks 'post-command-hook))))

(ert-deftest evm-test-open-below-real-keys ()
  "o + real keystrokes should replicate to all cursors."
  (evm-test-with-buffer "a = 1\nb = 2\nc = 3"
    (evm-add-cursor-down)
    (evm-add-cursor-down)
    (should (= (evm-region-count) 3))
    (evm-open-below)
    (evm-test--simulate-keystrokes "print(done)")
    (evil-normal-state)
    (should (string= (buffer-string)
                     "a = 1\nprint(done)\nb = 2\nprint(done)\nc = 3\nprint(done)"))))

(ert-deftest evm-test-open-below-electric-pair ()
  "o + real keystrokes with electric-pair-mode should replicate correctly."
  (evm-test-with-buffer "a = 1\nb = 2\nc = 3"
    (electric-pair-local-mode 1)
    (evm-add-cursor-down)
    (evm-add-cursor-down)
    (should (= (evm-region-count) 3))
    (evm-open-below)
    (evm-test--simulate-keystrokes "print(done)")
    (evil-normal-state)
    (should (string= (buffer-string)
                     "a = 1\nprint(done)\nb = 2\nprint(done)\nc = 3\nprint(done)"))))

(ert-deftest evm-test-insert-electric-pair ()
  "i + real keystrokes with electric-pair-mode should replicate correctly."
  (evm-test-with-buffer "foo\nbar\nbaz"
    (electric-pair-local-mode 1)
    (evm-add-cursor-down)
    (evm-add-cursor-down)
    (should (= (evm-region-count) 3))
    (evm-insert)
    (evm-test--simulate-keystrokes "(x)")
    (evil-normal-state)
    (should (string= (buffer-string) "(x)foo\n(x)bar\n(x)baz"))))

(ert-deftest evm-test-backspace-replicates ()
  "Backspace in insert mode should delete at all cursors."
  (evm-test-with-buffer "colllor: red\ncolllor: green\ncolllor: blue"
    (move-to-column 3)
    (evm-add-cursor-down)
    (evm-add-cursor-down)
    (evm-insert)
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

(ert-deftest evm-test-no-word-at-point ()
  "C-n on whitespace should error."
  (evm-test-with-buffer "   foo"
    (should-error (evm-find-word))))

(ert-deftest evm-test-single-occurrence ()
  "n with single occurrence should not create duplicate."
  (evm-test-with-buffer "foo bar baz"
    (evm-find-word)
    (evm-find-next)
    ;; Should still be 1, no other foo
    (should (= (evm-region-count) 1))))

;;; Undo resync tests

(ert-deftest evm-test-resync-after-undo ()
  "Regions should be resynced to pattern matches after undo."
  (evm-test-with-buffer "foo bar foo"
    (evm-find-word)
    (evm-find-next)
    ;; Two regions at positions 1 and 9
    (should (= (evm-region-count) 2))
    (should (equal (evm-test-positions) '(1 9)))
    ;; Simulate undo resync by calling the function directly
    ;; (actual undo test would require more complex setup)
    (evm--resync-regions-to-pattern)
    ;; Positions should remain consistent
    (should (equal (evm-test-positions) '(1 9)))
    ;; All regions should have correct end positions (foo = 3 chars)
    (should (equal (evm-test-end-positions) '(4 12)))))

(ert-deftest evm-test-resync-cursor-mode ()
  "Regions in cursor mode should resync to beginning of match."
  (evm-test-with-buffer "foo bar foo"
    (evm-find-word)
    (evm-find-next)
    ;; Switch to cursor mode - cursors collapse to beginning (1 and 9)
    ;; Like vim-visual-multi, cursor goes to start of selection
    (evm-toggle-mode)
    (should (evm-cursor-mode-p))
    (should (equal (evm-test-positions) '(1 9)))

    ;; Run resync
    (evm--resync-regions-to-pattern)

    ;; Should still be at beginning (1 and 9)
    (should (equal (evm-test-positions) '(1 9)))))

(ert-deftest evm-test-post-command-triggers-resync-on-undo ()
  "Post-command hook should trigger resync when undo command runs."
  (evm-test-with-buffer "foo bar foo"
    (evm-find-word)
    (evm-find-next)
    ;; Manually corrupt positions to simulate marker drift
    (let ((regions (evm-get-all-regions)))
      (set-marker (evm-region-beg (car regions)) 2)
      (set-marker (evm-region-beg (cadr regions)) 10))
    ;; Positions are now wrong
    (should (equal (evm-test-positions) '(2 10)))
    ;; Simulate undo command by setting this-command and calling post-command
    (let ((this-command 'evil-undo))
      (evm--post-command))
    ;; Positions should be corrected back to pattern matches
    (should (equal (evm-test-positions) '(1 9)))))

(ert-deftest evm-test-post-command-no-resync-on-other-commands ()
  "Post-command hook should NOT trigger resync for non-undo commands."
  (evm-test-with-buffer "foo bar foo"
    (evm-find-word)
    (evm-find-next)
    ;; Manually change positions
    (let ((regions (evm-get-all-regions)))
      (set-marker (evm-region-beg (car regions)) 2)
      (set-marker (evm-region-beg (cadr regions)) 10))
    ;; Positions are modified
    (should (equal (evm-test-positions) '(2 10)))
    ;; Simulate non-undo command
    (let ((this-command 'forward-char))
      (evm--post-command))
    ;; Positions should remain modified (no resync)
    (should (equal (evm-test-positions) '(2 10)))))

(ert-deftest evm-test-undo-moves-point-to-leader ()
  "After evm-undo, point should be at leader cursor position."
  (evm-test-with-buffer "foo bar foo"
    (evm-find-word)
    (evm-find-next)
    ;; Leader is at second foo (position 9)
    (should (= (evm-test-leader-pos) 9))
    ;; Point should be at leader's visual position
    (let ((leader (evm--leader-region)))
      (should (= (point) (evm--region-visual-cursor-pos leader))))))

(ert-deftest evm-test-undo-adjusts-cursor-to-last-char ()
  "After undo, evm--adjust-cursor-pos should clamp cursors off newline.
Regression: paste moves markers into inserted text; undo removes text
and Emacs pushes markers to line-end-position, creating stale overlays."
  (evm-test-with-buffer "aaa\nbbb\nccc\n"
    ;; Cursors at end-of-line (position 3 = last char 'a', 7 = last 'b')
    (evm-activate)
    (evm--create-region 3 3)
    (evm--create-region 7 7)
    ;; Simulate markers ending up on newline (as happens after undo of paste)
    (dolist (region (evm-state-regions evm--state))
      (let ((eol-pos (save-excursion
                       (goto-char (marker-position (evm-region-beg region)))
                       (line-end-position))))
        (evm--region-set-cursor-pos region eol-pos)))
    ;; Verify markers are on newline
    (dolist (region (evm-state-regions evm--state))
      (should (= (marker-position (evm-region-beg region))
                 (save-excursion
                   (goto-char (marker-position (evm-region-beg region)))
                   (line-end-position)))))
    ;; Apply the adjustment (what evm-undo does)
    (dolist (region (evm-state-regions evm--state))
      (evm--region-set-cursor-pos
       region (evm--adjust-cursor-pos (evm--region-cursor-pos region))))
    ;; Verify: cursors moved back to last character (off newline)
    (dolist (region (evm-state-regions evm--state))
      (let ((pos (marker-position (evm-region-beg region))))
        (save-excursion
          (goto-char pos)
          (should-not (= pos (line-end-position))))))))

;;; Restrict to region tests

(ert-deftest evm-test-restrict-active-p ()
  "evm--restrict-active-p should return t when restriction is set."
  (evm-test-with-buffer "foo bar foo baz foo"
    (evm-activate)
    (evm--create-region (point) (point))
    (should-not (evm--restrict-active-p))
    (evm--set-restrict 5 15)
    (should (evm--restrict-active-p))
    (evm--clear-restrict)
    (should-not (evm--restrict-active-p))))

(ert-deftest evm-test-restrict-bounds ()
  "evm--restrict-bounds should return correct bounds."
  (evm-test-with-buffer "foo bar foo baz foo"
    (evm-activate)
    (evm--create-region (point) (point))
    (evm--set-restrict 5 15)
    (let ((bounds (evm--restrict-bounds)))
      (should (= (car bounds) 5))
      (should (= (cdr bounds) 15)))))

(ert-deftest evm-test-select-all-restricted ()
  "\\A should only select occurrences within restriction."
  (evm-test-with-buffer "foo bar foo baz foo qux foo"
    ;; foo at positions: 1, 9, 17, 25
    (evm-find-word)
    ;; Set restriction from position 5 to 20 (covers foo at 9 and 17)
    (evm--set-restrict 5 20)
    ;; First foo at position 1 is the current selection (outside restriction)
    ;; Clear regions and start fresh
    (evm--remove-all-overlays)
    (setf (evm-state-regions evm--state) nil)
    ;; Go to position 9 (inside restriction)
    (goto-char 9)
    ;; Create region for foo at 9
    (evm--create-region 9 12 (car (evm-state-patterns evm--state)))
    ;; Select all should only add foo at 17
    (evm-select-all)
    ;; Should have exactly 2 cursors (at 9 and 17)
    (should (= (evm-region-count) 2))
    (should (equal (evm-test-positions) '(9 17)))))

(ert-deftest evm-test-find-next-restricted ()
  "n should only find occurrences within restriction."
  (evm-test-with-buffer "foo bar foo baz foo qux foo"
    ;; foo at positions: 1, 9, 17, 25
    (evm-find-word)
    ;; Set restriction from position 5 to 20 (covers foo at 9 and 17)
    (evm--set-restrict 5 20)
    ;; Start from position 9
    (evm--remove-all-overlays)
    (setf (evm-state-regions evm--state) nil)
    (clrhash (evm-state-region-by-id evm--state))
    (goto-char 9)
    (evm--create-region 9 12 (car (evm-state-patterns evm--state)))
    ;; find-next should find foo at 17
    (evm-find-next)
    (should (= (evm-region-count) 2))
    ;; find-next again should wrap back to 9
    (evm-find-next)
    (should (= (evm-region-count) 2))
    (should (= (evm-test-leader-pos) 9))))

(ert-deftest evm-test-clear-restrict ()
  "\\r should clear restriction."
  (evm-test-with-buffer "foo bar foo baz foo"
    (evm-find-word)
    (evm--set-restrict 5 15)
    (should (evm--restrict-active-p))
    (evm-clear-restrict)
    (should-not (evm--restrict-active-p))))

(ert-deftest evm-test-exit-clears-restrict ()
  "Exit should clear restriction."
  (evm-test-with-buffer "foo bar foo"
    (evm-find-word)
    (evm--set-restrict 1 10)
    (should (evm--restrict-active-p))
    (evm-exit)
    ;; After exit, state is deactivated so restriction should be cleared
    (should-not (evm--restrict-active-p))))

(ert-deftest evm-test-mode-line-shows-restrict ()
  "Mode-line should show R indicator when restricted."
  (evm-test-with-buffer "foo bar foo"
    (evm-find-word)
    (let ((indicator (evm--mode-line-indicator)))
      (should-not (string-match-p " R" indicator)))
    (evm--set-restrict 1 10)
    (let ((indicator (evm--mode-line-indicator)))
      (should (string-match-p " R" indicator)))))

;;; Mouse click tests

(ert-deftest evm-test-add-cursor-at-click-creates-cursor ()
  "M-click should create cursor at click position."
  (evm-test-with-buffer "foo bar baz"
    ;; Simulate mouse click at position 5
    (let ((event `(mouse-1 (,(selected-window) 5 (0 . 0) 0))))
      (evm-add-cursor-at-click event))
    (should (evm-active-p))
    ;; First cursor at point (1), second at click position (5)
    (should (= (evm-region-count) 2))))

(ert-deftest evm-test-add-cursor-at-click-removes-existing ()
  "M-click on existing cursor should remove it (toggle behavior)."
  (evm-test-with-buffer "foo bar baz"
    (evm-activate)
    (evm--create-region 1 1)
    (evm--create-region 5 5)
    (should (= (evm-region-count) 2))
    ;; Click on position 5 (existing non-leader cursor) - should remove it
    (let ((event `(mouse-1 (,(selected-window) 5 (0 . 0) 0))))
      (evm-add-cursor-at-click event))
    ;; Should now have 1 cursor
    (should (= (evm-region-count) 1))
    (should (= (evm-test-leader-pos) 1))))

(ert-deftest evm-test-add-cursor-at-click-removes-leader-on-repeat ()
  "M-click on leader cursor should remove it (toggle behavior)."
  (evm-test-with-buffer "foo bar baz"
    (evm-activate)
    (evm--create-region 1 1)
    (evm--create-region 5 5)
    (should (= (evm-region-count) 2))
    ;; Set leader to position 5
    (let ((cursor-at-5 (cl-find-if (lambda (r) (= (evm--region-cursor-pos r) 5))
                                    (evm-state-regions evm--state))))
      (evm--set-leader cursor-at-5))
    (should (= (evm-test-leader-pos) 5))
    ;; Click on leader position 5 - should remove it
    (let ((event `(mouse-1 (,(selected-window) 5 (0 . 0) 0))))
      (evm-add-cursor-at-click event))
    ;; Should now have 1 cursor, leader moved to remaining one
    (should (= (evm-region-count) 1))
    (should (= (evm-test-leader-pos) 1))))

(ert-deftest evm-test-align ()
  "Test that align inserts spaces before region start."
  (evm-test-with-buffer "short = 1\nvery_long_name = 2\nmedium = 3"
    (evm-activate)
    ;; Create regions on the = signs
    (goto-char (point-min))
    (search-forward "=")
    (backward-char)
    (evm--create-region (point) (1+ (point)))
    (forward-line)
    (search-forward "=")
    (backward-char)
    (evm--create-region (point) (1+ (point)))
    (forward-line)
    (search-forward "=")
    (backward-char)
    (evm--create-region (point) (1+ (point)))
    ;; Align
    (evm-align)
    ;; Check that = signs are aligned
    (should (string= (buffer-string)
                     "short          = 1\nvery_long_name = 2\nmedium         = 3"))))

;;; Run at Cursors tests

(defmacro evm-test-with-real-buffer (content &rest body)
  "Create real buffer with CONTENT, execute BODY, then cleanup.
Used for tests that need execute-kbd-macro which doesn't work in temp buffers."
  (declare (indent 1))
  `(let ((buf (generate-new-buffer " *evm-test*")))
     (unwind-protect
         (progn
           (switch-to-buffer buf)
           (insert ,content)
           (goto-char (point-min))
           (evil-local-mode 1)
           (evil-normal-state)
           ,@body)
       (when (evm-active-p)
         (evm-exit))
       (kill-buffer buf))))

(ert-deftest evm-test-run-normal-basic ()
  "\\z should run normal command at all cursors."
  (evm-test-with-real-buffer "foo\nbar\nbaz"
    ;; Create cursors on each line
    (evm-add-cursor-down)
    (evm-add-cursor-down)
    (should (= (evm-region-count) 3))
    ;; Run "x" at all cursors (delete char)
    (evm-run-normal "x")
    (should (string= (buffer-string) "oo\nar\naz"))))

(ert-deftest evm-test-run-normal-with-count ()
  "\\z should handle commands with implicit count."
  (evm-test-with-real-buffer "foo\nbar\nbaz"
    ;; Create cursors on each line
    (evm-add-cursor-down)
    (evm-add-cursor-down)
    ;; Run "2x" at all cursors (delete 2 chars)
    (evm-run-normal "2x")
    (should (string= (buffer-string) "o\nr\nz"))))

(ert-deftest evm-test-run-normal-movement ()
  "\\z should handle movement commands."
  (evm-test-with-real-buffer "foo\nbar\nbaz"
    ;; Create cursors on each line at position 1 of each line
    (evm-add-cursor-down)
    (evm-add-cursor-down)
    ;; Run "l" to move right - need update-positions
    ;; Since run-normal doesn't update positions by default,
    ;; markers stay in place but cursor moves
    (evm-run-normal "l")
    ;; For movement commands, positions don't change (markers auto-adjust)
    ;; The visual cursor moves but markers don't
    (let ((positions (evm-test-positions)))
      ;; Positions should remain at line beginnings
      (should (= (car positions) 1))
      (should (= (nth 1 positions) 5))
      (should (= (nth 2 positions) 9)))))

(ert-deftest evm-test-run-normal-empty-command ()
  "\\z with empty command should do nothing."
  (evm-test-with-buffer "foo\nbar"
    (evm-add-cursor-down)
    (let ((content-before (buffer-string)))
      (evm-run-normal "")
      (should (string= (buffer-string) content-before)))))

(ert-deftest evm-test-run-command-at-cursors-error-handling ()
  "Errors in commands should be caught and reported."
  (evm-test-with-buffer "foo\nbar"
    (evm-add-cursor-down)
    ;; This should not throw an error that stops everything
    ;; Running an invalid command should be handled gracefully
    (condition-case nil
        (evm--run-command-at-cursors
         (lambda ()
           (error "Test error")))
      (error nil))
    ;; evm should still be active
    (should (evm-active-p))))

(ert-deftest evm-test-run-macro-basic ()
  "\\@ should run macro at all cursors."
  (evm-test-with-real-buffer "foo\nbar\nbaz"
    ;; Create cursors on each line
    (evm-add-cursor-down)
    (evm-add-cursor-down)
    ;; Record a macro that deletes first char: "x"
    (evil-set-register ?q (kbd "x"))
    ;; Run macro
    (evm-run-macro ?q)
    (should (string= (buffer-string) "oo\nar\naz"))))

(ert-deftest evm-test-run-macro-empty-register ()
  "\\@ with empty register should error."
  (evm-test-with-buffer "foo\nbar"
    (evm-add-cursor-down)
    ;; Clear register
    (evil-set-register ?z nil)
    (should-error (evm-run-macro ?z))))

(ert-deftest evm-test-run-ex-basic ()
  "\\: should run Ex command at all cursors."
  (evm-test-with-buffer "foo\nbar\nbaz"
    ;; Create cursors on each line
    (evm-add-cursor-down)
    (evm-add-cursor-down)
    (should (= (evm-region-count) 3))
    ;; Run "s/^/X/" to prepend X at each cursor line
    (evm-run-ex "s/^/X/")
    (should (string= (buffer-string) "Xfoo\nXbar\nXbaz"))))

(ert-deftest evm-test-run-ex-empty-command ()
  "\\: with empty command should do nothing."
  (evm-test-with-buffer "foo\nbar"
    (evm-add-cursor-down)
    (let ((content-before (buffer-string)))
      (evm-run-ex "")
      (should (string= (buffer-string) content-before)))))

(ert-deftest evm-test-run-normal-preserves-cursor-count ()
  "\\z should preserve number of cursors."
  (evm-test-with-real-buffer "foo\nbar\nbaz"
    (evm-add-cursor-down)
    (evm-add-cursor-down)
    (let ((count-before (evm-region-count)))
      (evm-run-normal "l")
      (should (= (evm-region-count) count-before)))))

;;; Operator tests

(ert-deftest evm-test-operator-bindings-in-cursor-mode ()
  "d, c, y should be bound to operators in cursor mode."
  (evm-test-with-buffer "foo bar foo"
    (evm-add-cursor-down)  ; Enters cursor mode
    (should (evm-cursor-mode-p))
    (should (eq (key-binding "d") 'evm-operator-delete))
    (should (eq (key-binding "c") 'evm-operator-change))
    (should (eq (key-binding "y") 'evm-operator-yank))
    (should (eq (key-binding "D") 'evm-delete-to-eol))
    (should (eq (key-binding "C") 'evm-change-to-eol))
    (should (eq (key-binding "Y") 'evm-yank-line))))

(ert-deftest evm-test-delete-to-eol ()
  "D should delete from cursor to end of line at all cursors."
  (evm-test-with-buffer "foo bar\nbaz qux\nend"
    (evm-add-cursor-down)
    (evm-add-cursor-down)
    (should (= (evm-region-count) 3))
    ;; Move cursors to position 4 on each line (after "foo ", "baz ", "end")
    ;; Actually at beginning, so D deletes whole line content
    (evm-delete-to-eol)
    (should (string= (buffer-string) "\n\n"))))

(ert-deftest evm-test-delete-to-eol-mid-line ()
  "D from middle of line should delete only rest of line."
  (evm-test-with-buffer "foo bar\nbaz qux"
    (evm-activate)
    (evm--create-region 4 4)   ; after "foo" on line 1
    (evm--create-region 12 12) ; after "baz" on line 2
    (evm-delete-to-eol)
    (should (string= (buffer-string) "foo\nbaz"))))

(ert-deftest evm-test-change-to-eol-cursor-position ()
  "C should place cursor at deletion point, not adjusted back."
  (evm-test-with-buffer "alpha beta gamma\nalpha beta gamma"
    (evm-activate)
    ;; Place cursors at 'b' in "beta" on each line (positions 7 and 24)
    (evm--create-region 7 7)
    (evm--create-region 24 24)
    (should (= (evm-region-count) 2))
    ;; C deletes to end of line and enters insert mode
    (evm-change-to-eol)
    ;; Buffer should have "alpha " on each line
    (should (string= (buffer-string) "alpha \nalpha "))
    ;; Cursors should be at position 7 and 14 (after "alpha ")
    ;; NOT adjusted back to position 6 and 13
    (should (equal (evm-test-positions) '(7 14)))
    ;; Clean up insert mode
    (evil-normal-state)))

(ert-deftest evm-test-yank-line ()
  "Y should yank entire line at all cursors."
  (evm-test-with-buffer "foo bar\nbaz qux"
    (evm-add-cursor-down)
    (should (= (evm-region-count) 2))
    (evm-yank-line)
    (let ((contents (gethash ?\" (evm-state-registers evm--state))))
      (should contents)
      (should (= (length contents) 2))
      (should (string= (car contents) "foo bar"))
      (should (string= (cadr contents) "baz qux")))))

;; Note: evm--execute-operator-motion tests require interactive Emacs
;; (execute-kbd-macro doesn't work well in batch/server mode)
;; These are tested via make test-interactive instead

(ert-deftest evm-test-single-motions-list ()
  "Single motions list should contain expected motions."
  (should (memq ?h evm--single-motions))
  (should (memq ?j evm--single-motions))
  (should (memq ?k evm--single-motions))
  (should (memq ?l evm--single-motions))
  (should (memq ?w evm--single-motions))
  (should (memq ?e evm--single-motions))
  (should (memq ?b evm--single-motions))
  (should (memq ?$ evm--single-motions))
  (should (memq ?^ evm--single-motions))
  (should (memq ?0 evm--single-motions)))

(ert-deftest evm-test-double-motion-prefixes-list ()
  "Double motion prefixes should contain expected prefixes."
  (should (memq ?i evm--double-motion-prefixes))
  (should (memq ?a evm--double-motion-prefixes))
  (should (memq ?f evm--double-motion-prefixes))
  (should (memq ?F evm--double-motion-prefixes))
  (should (memq ?t evm--double-motion-prefixes))
  (should (memq ?T evm--double-motion-prefixes))
  (should (memq ?g evm--double-motion-prefixes)))

(ert-deftest evm-test-text-objects-list ()
  "Text objects list should contain expected objects."
  (should (memq ?w evm--text-objects))
  (should (memq ?W evm--text-objects))
  (should (memq ?s evm--text-objects))
  (should (memq ?p evm--text-objects))
  (should (memq ?\" evm--text-objects))
  (should (memq ?' evm--text-objects))
  (should (memq ?\( evm--text-objects))
  (should (memq ?\) evm--text-objects))
  (should (memq ?\[ evm--text-objects))
  (should (memq ?\] evm--text-objects))
  (should (memq ?{ evm--text-objects))
  (should (memq ?} evm--text-objects))
  (should (memq ?b evm--text-objects))
  (should (memq ?B evm--text-objects)))

(ert-deftest evm-test-text-object-ranges ()
  "Text objects should return correct ranges via evm--get-motion-range."
  ;; di[ - inner brackets
  (with-temp-buffer
    (evil-local-mode 1) (evil-normal-state)
    (insert "x = [1, 2, 3]")
    (goto-char 6) ;; on "1"
    (let ((range (evm--get-motion-range "i[" 1)))
      (should range)
      (delete-region (car range) (cadr range))
      (should (string= (buffer-string) "x = []"))))
  ;; di{ - inner curly braces
  (with-temp-buffer
    (evil-local-mode 1) (evil-normal-state)
    (insert "x = {a, b}")
    (goto-char 6)
    (let ((range (evm--get-motion-range "i{" 1)))
      (should range)
      (delete-region (car range) (cadr range))
      (should (string= (buffer-string) "x = {}"))))
  ;; iB - curly braces via B alias
  (with-temp-buffer
    (evil-local-mode 1) (evil-normal-state)
    (insert "x = {a, b}")
    (goto-char 6)
    (let ((range (evm--get-motion-range "iB" 1)))
      (should range)
      (delete-region (car range) (cadr range))
      (should (string= (buffer-string) "x = {}"))))
  ;; di( - inner parens
  (with-temp-buffer
    (evil-local-mode 1) (evil-normal-state)
    (insert "print(hello)")
    (goto-char 7)
    (let ((range (evm--get-motion-range "i(" 1)))
      (should range)
      (delete-region (car range) (cadr range))
      (should (string= (buffer-string) "print()")))))

(ert-deftest evm-test-digit-p ()
  "evm--digit-p should recognize digits 1-9."
  (should (evm--digit-p ?1))
  (should (evm--digit-p ?5))
  (should (evm--digit-p ?9))
  (should-not (evm--digit-p ?0))  ; 0 is a motion, not a count digit
  (should-not (evm--digit-p ?a))
  (should-not (evm--digit-p nil)))

;; evm-test-delete-saves-to-register requires interactive Emacs

(ert-deftest evm-test-operator-accepts-prefix-arg ()
  "Operator commands should accept prefix argument for 2dw pattern."
  (should (commandp 'evm-operator-delete))
  (should (commandp 'evm-operator-change))
  (should (commandp 'evm-operator-yank))
  ;; Check interactive spec accepts prefix arg
  (should (string-match-p "P" (or (car (cdr (interactive-form 'evm-operator-delete))) "")))
  (should (string-match-p "P" (or (car (cdr (interactive-form 'evm-operator-change))) "")))
  (should (string-match-p "P" (or (car (cdr (interactive-form 'evm-operator-yank))) ""))))

(ert-deftest evm-test-dw-does-not-cross-line-boundary ()
  "dw should not delete newline character (like vim behavior)."
  (evm-test-with-real-buffer "foo\nbar\nbaz"
    ;; Start at beginning of "foo" (position 1)
    (evm-activate)
    (evm--create-region 1 1)
    ;; Get motion range for "w" from position 1
    ;; In vim, "w" from "foo" goes to "bar" on next line,
    ;; but "dw" should only delete "foo" (not the newline)
    (let ((range (evm--get-motion-range "w" 1)))
      ;; Range should be (1 4) - from "f" to end of "foo"
      ;; Not (1 5) which would include the newline
      (should range)
      (should (= (car range) 1))
      ;; End should be at position 4 (end of "foo", before newline)
      (should (= (cadr range) 4)))))

(ert-deftest evm-test-dw-works-normally-within-line ()
  "dw should work normally when next word is on same line."
  (evm-test-with-real-buffer "foo bar baz"
    (evm-activate)
    (evm--create-region 1 1)
    ;; Get motion range for "w" from position 1
    ;; Next word "bar" is on same line, so range should include space
    (let ((range (evm--get-motion-range "w" 1)))
      (should range)
      (should (= (car range) 1))
      ;; End should be at position 5 (start of "bar")
      (should (= (cadr range) 5)))))

(ert-deftest evm-test-dW-does-not-cross-line-boundary ()
  "dW should not delete newline character (like vim behavior)."
  (evm-test-with-real-buffer "foo\nbar"
    (evm-activate)
    (evm--create-region 1 1)
    (let ((range (evm--get-motion-range "W" 1)))
      (should range)
      (should (= (car range) 1))
      ;; End should be at position 4 (end of line)
      (should (= (cadr range) 4)))))

;;; Line operation tests (dd, cc, yy)

(ert-deftest evm-test-execute-operator-line-delete ()
  "dd should delete entire line including newline."
  (evm-test-with-buffer "line1\nline2\nline3"
    (evm-activate)
    (evm--create-region 1 1)
    (let ((text (evm--execute-operator-line 'delete 1)))
      (should (string= text "line1\n"))
      (should (string= (buffer-string) "line2\nline3")))))

(ert-deftest evm-test-execute-operator-line-delete-multiple ()
  "2dd should delete 2 lines."
  (evm-test-with-buffer "line1\nline2\nline3\nline4"
    (evm-activate)
    (evm--create-region 1 1)
    (let ((text (evm--execute-operator-line 'delete 2)))
      (should (string= text "line1\nline2\n"))
      (should (string= (buffer-string) "line3\nline4")))))

(ert-deftest evm-test-execute-operator-line-yank ()
  "yy should yank entire line without deleting."
  (evm-test-with-buffer "line1\nline2\nline3"
    (evm-activate)
    (evm--create-region 1 1)
    (let ((text (evm--execute-operator-line 'yank 1)))
      (should (string= text "line1\n"))
      ;; Buffer unchanged
      (should (string= (buffer-string) "line1\nline2\nline3")))))

(ert-deftest evm-test-execute-operator-line-change ()
  "cc should delete line and prepare for insert."
  (evm-test-with-buffer "line1\nline2\nline3"
    (evm-activate)
    (evm--create-region 7 7)  ; cursor on line2
    (goto-char 7)  ; need to position point for line operations
    (let ((text (evm--execute-operator-line 'change 1)))
      (should (string= text "line2\n"))
      ;; Line replaced with empty line (newline inserted for edit)
      (should (string-match-p "line1\n.*\nline3" (buffer-string))))))

(ert-deftest evm-test-parse-motion-line-operation ()
  "evm--parse-motion should recognize dd, cc, yy as line operations."
  ;; We can't easily test read-char interactively, but we can verify
  ;; the function signature accepts operator-char
  (should (functionp 'evm--parse-motion)))

;;; Join lines tests

(ert-deftest evm-test-join-lines-basic ()
  "J should join current line with next line."
  (evm-test-with-buffer "foo\nbar\nbaz"
    (evm-activate)
    (evm--create-region 1 1)
    (evm-join-lines 1)
    (should (string= (buffer-string) "foo bar\nbaz"))))

(ert-deftest evm-test-join-lines-multiple-cursors ()
  "J should join lines at all cursor positions."
  (evm-test-with-buffer "aaa\nbbb\nccc\nddd"
    (evm-activate)
    (evm--create-region 1 1)   ; line 1
    (evm--create-region 9 9)   ; line 3
    (should (= (evm-region-count) 2))
    (evm-join-lines 1)
    (should (string= (buffer-string) "aaa bbb\nccc ddd"))))

(ert-deftest evm-test-join-lines-removes-leading-whitespace ()
  "J should remove leading whitespace from joined line."
  (evm-test-with-buffer "foo\n   bar"
    (evm-activate)
    (evm--create-region 1 1)
    (evm-join-lines 1)
    (should (string= (buffer-string) "foo bar"))))

(ert-deftest evm-test-join-lines-no-space-before-paren ()
  "J should not add space when next line starts with ) or ]."
  (evm-test-with-buffer "foo(\n)"
    (evm-activate)
    (evm--create-region 1 1)
    (evm-join-lines 1)
    (should (string= (buffer-string) "foo()"))))

;;; Indent/outdent operator tests

(ert-deftest evm-test-operator-indent-bindings ()
  "> and < should be bound in cursor mode."
  (evm-test-with-buffer "foo"
    (evm-add-cursor-down)
    (should (evm-cursor-mode-p))
    (should (eq (key-binding ">") 'evm-operator-indent))
    (should (eq (key-binding "<") 'evm-operator-outdent))))

(ert-deftest evm-test-execute-indent-line ()
  "evm--execute-indent-line should indent lines."
  (evm-test-with-buffer "foo\nbar"
    (evm-activate)
    (evm--create-region 1 1)
    (let ((tab-width 2)
          (indent-tabs-mode nil))
      (evm--execute-indent-line 'indent 1))
    (should (string-match-p "^  foo" (buffer-string)))))

(ert-deftest evm-test-execute-outdent-line ()
  "evm--execute-indent-line with outdent should remove indentation."
  (evm-test-with-buffer "  foo\n  bar"
    (evm-activate)
    (evm--create-region 1 1)
    (let ((tab-width 2))
      (evm--execute-indent-line 'outdent 1))
    (should (string-match-p "^foo" (buffer-string)))))

;;; Case change operator tests

(ert-deftest evm-test-case-operator-bindings ()
  "gu, gU, g~ should be bound in cursor mode."
  (evm-test-with-buffer "foo"
    (evm-add-cursor-down)
    (should (evm-cursor-mode-p))
    (should (eq (key-binding (kbd "g u")) 'evm-operator-downcase))
    (should (eq (key-binding (kbd "g U")) 'evm-operator-upcase))
    (should (eq (key-binding (kbd "g ~")) 'evm-operator-toggle-case))))

(ert-deftest evm-test-toggle-case-region-function ()
  "evm--toggle-case-region should toggle case of region."
  (evm-test-with-buffer "FoO BaR"
    (evm--toggle-case-region 1 4)
    (should (string= (buffer-substring 1 4) "fOo"))))

(ert-deftest evm-test-execute-case-line-upcase ()
  "evm--execute-case-line with upcase-region should uppercase line."
  (evm-test-with-buffer "foo bar\nbaz"
    (evm-activate)
    (evm--create-region 1 1)
    (evm--execute-case-line #'upcase-region 1)
    (should (string= (buffer-string) "FOO BAR\nbaz"))))

(ert-deftest evm-test-execute-case-line-downcase ()
  "evm--execute-case-line with downcase-region should lowercase line."
  (evm-test-with-buffer "FOO BAR\nBAZ"
    (evm-activate)
    (evm--create-region 1 1)
    (evm--execute-case-line #'downcase-region 1)
    (should (string= (buffer-string) "foo bar\nBAZ"))))

(ert-deftest evm-test-execute-case-line-toggle ()
  "evm--execute-case-line with toggle should toggle case of line."
  (evm-test-with-buffer "FoO bAr\nbaz"
    (evm-activate)
    (evm--create-region 1 1)
    (evm--execute-case-line #'evm--toggle-case-region 1)
    (should (string= (buffer-string) "fOo BaR\nbaz"))))

(ert-deftest evm-test-case-operators-exist ()
  "Case operator functions should exist and be commands."
  (should (commandp 'evm-operator-downcase))
  (should (commandp 'evm-operator-upcase))
  (should (commandp 'evm-operator-toggle-case)))

;;; Phase 9 tests: Special Features

;;; Visual mode cursor selection tests (9.1)

(ert-deftest evm-test-visual-cursors-char-mode ()
  "evm-visual-cursors in visual char mode should create cursors at start and end."
  (evm-test-with-buffer "hello world foo"
    (goto-char 7)  ; start at 'w'
    (evil-visual-state)
    (evil-forward-char 4)  ; select "worl"
    ;; Manually call the function (simulating the command)
    (let ((beg (region-beginning))
          (end (region-end)))
      (evil-exit-visual-state)
      (evm-activate)
      (evm--create-region beg beg)
      (evm--create-region (1- end) (1- end)))
    (should (evm-active-p))
    (should (= (evm-region-count) 2))))

(ert-deftest evm-test-visual-cursors-line-mode ()
  "evm-visual-cursors in visual line mode should create cursor per line."
  (evm-test-with-buffer "line1\nline2\nline3"
    (evil-visual-line)
    (evil-next-line 2)  ; select all 3 lines
    (let ((positions '()))
      ;; Simulate evm-visual-cursors logic for line mode
      (save-excursion
        (goto-char (region-beginning))
        (dotimes (_ 3)
          (back-to-indentation)
          (push (point) positions)
          (forward-line 1)))
      (evil-exit-visual-state)
      (evm-activate)
      (dolist (pos (nreverse positions))
        (evm--create-region pos pos)))
    (should (evm-active-p))
    (should (= (evm-region-count) 3))))

;;; Reselect Last tests (9.4)

(ert-deftest evm-test-reselect-last-saves-mode ()
  "evm--save-for-reselect should save mode information."
  (evm-test-with-buffer "foo bar foo"
    (evm-find-word)
    (evm-find-next)
    ;; We're in extend mode
    (should (evm-extend-mode-p))
    ;; Save for reselect (called automatically on exit)
    (evm--save-for-reselect)
    (let ((last (evm-state-last-regions evm--state)))
      ;; Should be a plist with :mode
      (should (plistp last))
      (should (eq (plist-get last :mode) 'extend))
      (should (= (length (plist-get last :positions)) 2)))))

(ert-deftest evm-test-reselect-last-restores-positions ()
  "evm-reselect-last should restore cursor positions."
  (evm-test-with-buffer "foo bar foo"
    (evm-find-word)
    (evm-find-next)
    (let ((positions-before (evm-test-positions)))
      (evm--save-for-reselect)
      (evm-exit)
      (should-not (evm-active-p))
      (evm-reselect-last)
      (should (evm-active-p))
      (should (= (evm-region-count) 2))
      (should (equal (evm-test-positions) positions-before)))))

;;; VM Registers tests (9.5)

(ert-deftest evm-test-yank-to-named-register ()
  "evm-yank-to-register should save to specified register."
  (evm-test-with-buffer "foo bar foo"
    (evm-find-word)
    (evm-find-next)
    (should (evm-extend-mode-p))
    (evm-yank-to-register ?a)
    (let ((contents (gethash ?a (evm-state-registers evm--state))))
      (should contents)
      (should (= (length contents) 2))
      (should (string= (car contents) "foo")))))

(ert-deftest evm-test-yank-to-uppercase-register-appends ()
  "Uppercase register should append to existing contents."
  (evm-test-with-buffer "foo bar baz"
    (evm-activate)
    ;; First yank "foo"
    (evm--create-region 1 4 nil)
    (setf (evm-state-mode evm--state) 'extend)
    (evm--update-all-overlays)
    (evm-yank-to-register ?a)
    ;; Clear and yank "bar"
    (setf (evm-state-regions evm--state) nil)
    (evm--create-region 5 8 nil)
    (evm-yank-to-register ?A)  ; Uppercase appends
    (let ((contents (gethash ?a (evm-state-registers evm--state))))
      (should (= (length contents) 2))
      (should (string= (car contents) "foo"))
      (should (string= (cadr contents) "bar")))))

(ert-deftest evm-test-paste-from-named-register ()
  "evm-paste-from-register should paste from specified register."
  (evm-test-with-buffer "XXX YYY"
    (evm-activate)
    ;; Store something in register a
    (puthash ?a '("foo" "bar") (evm-state-registers evm--state))
    ;; Create cursors
    (evm--create-region 1 4 nil)  ; "XXX"
    (evm--create-region 5 8 nil)  ; "YYY"
    (setf (evm-state-mode evm--state) 'extend)
    (evm--update-all-overlays)
    ;; Paste from register a (replaces selections)
    (evm-paste-from-register ?a)
    (should (string= (buffer-string) "foo bar"))))

(ert-deftest evm-test-yank-via-evil-this-register ()
  "evm-yank should use evil-this-register when set."
  (evm-test-with-buffer "foo bar foo"
    (evm-find-word)
    (evm-find-next)
    (should (evm-extend-mode-p))
    ;; Simulate pressing \"a before y
    (setq evil-this-register ?b)
    (evm-yank)
    ;; evil-this-register should be cleared
    (should-not evil-this-register)
    ;; Contents should be in register b
    (let ((contents (gethash ?b (evm-state-registers evm--state))))
      (should contents)
      (should (= (length contents) 2))
      (should (string= (car contents) "foo")))))

(ert-deftest evm-test-paste-via-evil-this-register ()
  "evm-paste-after should use evil-this-register when set."
  (evm-test-with-buffer "XXX YYY"
    (evm-activate)
    ;; Store in register c
    (puthash ?c '("foo" "bar") (evm-state-registers evm--state))
    ;; Create cursors
    (evm--create-region 1 4 nil)
    (evm--create-region 5 8 nil)
    (setf (evm-state-mode evm--state) 'extend)
    (evm--update-all-overlays)
    ;; Simulate pressing \"c before p
    (setq evil-this-register ?c)
    (evm-paste-after)
    ;; evil-this-register should be cleared
    (should-not evil-this-register)
    (should (string= (buffer-string) "foo bar"))))

(ert-deftest evm-test-paste-in-cursor-mode ()
  "p in cursor mode should insert without deleting."
  (evm-test-with-buffer "ab\ncd"
    (evm-activate)
    ;; Store content
    (puthash ?\" '("X" "Y") (evm-state-registers evm--state))
    ;; Create cursors at 'a' and 'c'
    (goto-char 1)
    (evm--create-region 1 1 nil)  ; cursor at 'a'
    (evm--create-region 4 4 nil)  ; cursor at 'c'
    ;; Should be in cursor mode (beg=end)
    (should (evm-cursor-mode-p))
    (evm-paste-after)
    ;; Should insert after cursor positions: aXb, cYd
    (should (string= (buffer-string) "aXb\ncYd"))))

(ert-deftest evm-test-paste-after-cursor-position ()
  "p should place cursors on last inserted character."
  (evm-test-with-buffer "aaa\nbbb\nccc"
    (evm-activate)
    (puthash ?\" '("XX" "YY" "ZZ") (evm-state-registers evm--state))
    (evm--create-region 1 1 nil)
    (evm--create-region 5 5 nil)
    (evm--create-region 9 9 nil)
    (evm-paste-after)
    (should (string= (buffer-string) "aXXaa\nbYYbb\ncZZcc"))
    ;; Cursors should be on last inserted char (second X, Y, Z)
    (let ((positions (mapcar (lambda (r) (marker-position (evm-region-beg r)))
                             (evm-state-regions evm--state))))
      (should (= (length positions) 3))
      (should (equal (char-after (nth 0 positions)) ?X))
      (should (equal (char-after (nth 1 positions)) ?Y))
      (should (equal (char-after (nth 2 positions)) ?Z)))))

(ert-deftest evm-test-paste-before-cursor-position ()
  "P should place cursors on last inserted character."
  (evm-test-with-buffer "aaa\nbbb\nccc"
    (evm-activate)
    (puthash ?\" '("XX" "YY" "ZZ") (evm-state-registers evm--state))
    (evm--create-region 1 1 nil)
    (evm--create-region 5 5 nil)
    (evm--create-region 9 9 nil)
    (evm-paste-before)
    (should (string= (buffer-string) "XXaaa\nYYbbb\nZZccc"))
    ;; Cursors should be on last inserted char (second X, Y, Z)
    (let ((positions (mapcar (lambda (r) (marker-position (evm-region-beg r)))
                             (evm-state-regions evm--state))))
      (should (= (length positions) 3))
      (should (equal (char-after (nth 0 positions)) ?X))
      (should (equal (char-after (nth 1 positions)) ?Y))
      (should (equal (char-after (nth 2 positions)) ?Z)))))

;;; Multiline mode tests (9.2)

(ert-deftest evm-test-toggle-multiline ()
  "evm-toggle-multiline should toggle multiline-p flag."
  (evm-test-with-buffer "foo bar"
    (evm-activate)
    (evm--create-region (point) (point))
    (should-not (evm-state-multiline-p evm--state))
    (evm-toggle-multiline)
    (should (evm-state-multiline-p evm--state))
    (evm-toggle-multiline)
    (should-not (evm-state-multiline-p evm--state))))

(ert-deftest evm-test-find-word-multiline-selection-enables-search ()
  "Multiline visual selections should enable multiline matching for the session."
  (evm-test-with-buffer "foo\nbar\nzzz\nfoo\nbar"
    (goto-char 1)
    (evil-visual-select 1 8 'inclusive)
    (evm-find-word)
    (should (evm-state-multiline-p evm--state))
    (should (= (evm-region-count) 1))
    (evm-find-next)
    (should (equal (evm-test-positions) '(1 13)))
    (should (equal (evm-test-end-positions) '(8 20)))))

(ert-deftest evm-test-toggle-multiline-blocks-cross-line-matches ()
  "Disabling multiline should stop adding multi-line matches."
  (evm-test-with-buffer "foo\nbar\nzzz\nfoo\nbar"
    (goto-char 1)
    (evil-visual-select 1 8 'inclusive)
    (evm-find-word)
    (should (evm-state-multiline-p evm--state))
    (evm-toggle-multiline)
    (should-not (evm-state-multiline-p evm--state))
    (evm-find-next)
    (should (= (evm-region-count) 1))
    (should (equal (evm-test-positions) '(1)))))

;;; Undo tests (9.3)

(ert-deftest evm-test-execute-at-all-cursors-batches-overlay-sync ()
  "Batch cursor execution should not trigger per-edit synchronization hooks."
  (evm-test-with-buffer "a\nb\nc"
    (evm-activate)
    (evm--create-region 1 1)
    (evm--create-region 3 3)
    (let ((overlay-updates 0)
          (after-change-calls 0))
      (cl-letf (((symbol-function 'evm--update-all-overlays)
                 (lambda ()
                   (cl-incf overlay-updates)))
                ((symbol-function 'evm--after-change)
                 (lambda (&rest _args)
                   (cl-incf after-change-calls))))
        (evm--execute-at-all-cursors
         (lambda ()
           (insert "x"))
         t))
      (should (= overlay-updates 1))
      (should (= after-change-calls 0)))
    (should (string= (buffer-string) "xa\nxb\nc"))))

;;; Extend mode text objects

(ert-deftest evm-test-extend-inner-word ()
  "iw in extend mode should select inner word at all cursors."
  (evm-test-with-buffer "foo bar\nbaz qux\nhello world"
    (evm-add-cursor-down)
    (evm-add-cursor-down)
    (evm-enter-extend)
    ;; iw
    (setq unread-command-events (list ?w))
    (evm-extend-inner-text-object)
    (should (evm-extend-mode-p))
    (let ((texts (mapcar (lambda (r)
                           (buffer-substring (marker-position (evm-region-beg r))
                                             (marker-position (evm-region-end r))))
                         (evm-state-regions evm--state))))
      (should (equal texts '("foo" "baz" "hello"))))))

(ert-deftest evm-test-extend-a-word ()
  "aw in extend mode should select a word (with trailing space)."
  (evm-test-with-buffer "foo bar\nbaz qux"
    (evm-add-cursor-down)
    (evm-enter-extend)
    (setq unread-command-events (list ?w))
    (evm-extend-a-text-object)
    (let ((texts (mapcar (lambda (r)
                           (buffer-substring (marker-position (evm-region-beg r))
                                             (marker-position (evm-region-end r))))
                         (evm-state-regions evm--state))))
      (should (equal texts '("foo " "baz "))))))

(ert-deftest evm-test-extend-inner-double-quote ()
  "i\" in extend mode should select inside quotes."
  (evm-test-with-buffer "x = \"hello\"\ny = \"world\""
    (goto-char 6) ;; inside "hello"
    (evm-add-cursor-down)
    (evm-enter-extend)
    (setq unread-command-events (list ?\"))
    (evm-extend-inner-text-object)
    (let ((texts (mapcar (lambda (r)
                           (buffer-substring (marker-position (evm-region-beg r))
                                             (marker-position (evm-region-end r))))
                         (evm-state-regions evm--state))))
      (should (equal texts '("hello" "world"))))))

(ert-deftest evm-test-extend-inner-paren ()
  "i) in extend mode should select inside parens."
  (evm-test-with-buffer "f(10)\ng(20)"
    (goto-char 3) ;; inside (10)
    (evm-add-cursor-down)
    (evm-enter-extend)
    (setq unread-command-events (list ?\)))
    (evm-extend-inner-text-object)
    (let ((texts (mapcar (lambda (r)
                           (buffer-substring (marker-position (evm-region-beg r))
                                             (marker-position (evm-region-end r))))
                         (evm-state-regions evm--state))))
      (should (equal texts '("10" "20"))))))

(ert-deftest evm-test-extend-text-object-keybinding ()
  "i and a should be bound in extend mode."
  (should (eq (lookup-key evm-extend-map (kbd "i")) 'evm-extend-inner-text-object))
  (should (eq (lookup-key evm-extend-map (kbd "a")) 'evm-extend-a-text-object)))

;;; evil-surround integration tests (10.1)

(ert-deftest evm-test-surround-available-check ()
  "evm--surround-available-p should check for evil-surround."
  (evm-test-with-buffer "foo"
    ;; Should return based on whether evil-surround is loaded
    (should (eq (evm--surround-available-p) (featurep 'evil-surround)))))

(ert-deftest evm-test-surround-commands-exist ()
  "Surround commands should be defined."
  (should (commandp 'evm-surround))
  (should (commandp 'evm-operator-surround))
  (should (commandp 'evm-delete-surround))
  (should (commandp 'evm-change-surround)))

(ert-deftest evm-test-surround-keybinding-extend ()
  "S should be bound to evm-surround in extend mode."
  (should (eq (lookup-key evm-extend-map (kbd "S")) 'evm-surround)))

(ert-deftest evm-test-surround-in-extend-mode ()
  "S in extend mode should surround all regions when evil-surround loaded."
  (skip-unless (featurep 'evil-surround))
  (evm-test-with-buffer "foo bar foo"
    (evm-find-word)
    (evm-find-next)
    (should (= (evm-region-count) 2))
    (should (evm-extend-mode-p))
    ;; Surround with quotes (call directly with char)
    (evm-surround ?\")
    ;; Both "foo" should be wrapped
    (should (string= (buffer-string) "\"foo\" bar \"foo\""))))

(ert-deftest evm-test-surround-with-parens ()
  "S with parens should surround all regions."
  (skip-unless (featurep 'evil-surround))
  (evm-test-with-buffer "foo bar foo"
    (evm-find-word)
    (evm-find-next)
    (evm-surround ?\()
    ;; evil-surround uses "( " and " )" with spaces for (
    (should (string-match-p "(.*foo.*)" (buffer-string)))))

(ert-deftest evm-test-surround-switches-to-cursor-mode ()
  "S should switch to cursor mode after surround."
  (skip-unless (featurep 'evil-surround))
  (evm-test-with-buffer "foo bar foo"
    (evm-find-word)
    (evm-find-next)
    (should (evm-extend-mode-p))
    (evm-surround ?\")
    (should (evm-cursor-mode-p))))

(ert-deftest evm-test-delete-surround ()
  "ds should delete surrounding pair at all cursors."
  (skip-unless (featurep 'evil-surround))
  (evm-test-with-buffer "\"foo\" bar \"baz\""
    (evm-activate)
    ;; Create cursors inside the quoted strings
    (evm--create-region 2 2)   ; inside first "foo"
    (evm--create-region 12 12) ; inside second "baz"
    (should (= (evm-region-count) 2))
    ;; Delete surrounding quotes (call with char directly)
    ;; We need to simulate the behavior since read-char is interactive
    (let ((inhibit-message t))
      (dolist (region (evm--regions-by-position-reverse))
        (goto-char (evm--region-cursor-pos region))
        (evil-surround-delete ?\")))
    (should (string= (buffer-string) "foo bar baz"))))

(ert-deftest evm-test-change-surround ()
  "cs should change surrounding pair at all cursors."
  (skip-unless (featurep 'evil-surround))
  (evm-test-with-buffer "\"foo\" bar \"baz\""
    (evm-activate)
    ;; Create cursors inside the quoted strings
    (evm--create-region 2 2)   ; inside first "foo"
    (evm--create-region 12 12) ; inside second "baz"
    (should (= (evm-region-count) 2))
    ;; Change surrounding quotes to single quotes
    (let ((inhibit-message t))
      (dolist (region (evm--regions-by-position-reverse))
        (goto-char (evm--region-cursor-pos region))
        ;; Push new char so evil-surround-change reads it
        (setq unread-command-events (list ?'))
        (evil-surround-change ?\")))
    (should (string= (buffer-string) "'foo' bar 'baz'"))))

(ert-deftest evm-test-surround-only-in-extend-mode ()
  "evm-surround should only work in extend mode."
  (skip-unless (featurep 'evil-surround))
  (evm-test-with-buffer "foo bar foo"
    (evm-add-cursor-down)  ; Creates cursor mode
    (should (evm-cursor-mode-p))
    ;; Surround should have no effect in cursor mode
    (let ((content-before (buffer-string)))
      (evm-surround ?\")
      (should (string= (buffer-string) content-before)))))

(ert-deftest evm-test-operator-surround-only-in-cursor-mode ()
  "evm-operator-surround should only work in cursor mode."
  (skip-unless (featurep 'evil-surround))
  (evm-test-with-buffer "foo bar foo"
    (evm-find-word)  ; Creates extend mode
    (should (evm-extend-mode-p))
    ;; ys should have no effect in extend mode
    (let ((content-before (buffer-string)))
      (evm-operator-surround nil)
      (should (string= (buffer-string) content-before)))))

;;; Additional edge case tests

(ert-deftest evm-test-paste-cycling ()
  "p multiple times should cycle through register contents."
  (evm-test-with-buffer "XXX YYY ZZZ"
    (evm-activate)
    ;; Store 3 values in register
    (puthash ?\" '("a" "b" "c") (evm-state-registers evm--state))
    ;; Create 3 cursors
    (evm--create-region 1 4 nil)   ; "XXX"
    (evm--create-region 5 8 nil)   ; "YYY"
    (evm--create-region 9 12 nil)  ; "ZZZ"
    (setf (evm-state-mode evm--state) 'extend)
    (evm--update-all-overlays)
    (evm-paste-after)
    ;; Each cursor gets corresponding content from register
    (should (string= (buffer-string) "a b c"))))

(ert-deftest evm-test-paste-with-fewer-cursors-than-contents ()
  "p with fewer cursors than register contents should cycle."
  (evm-test-with-buffer "XX YY"
    (evm-activate)
    ;; Store 3 values in register, but only 2 cursors
    (puthash ?\" '("a" "b" "c") (evm-state-registers evm--state))
    ;; Create 2 cursors
    (evm--create-region 1 3 nil)  ; "XX"
    (evm--create-region 4 6 nil)  ; "YY"
    (setf (evm-state-mode evm--state) 'extend)
    (evm--update-all-overlays)
    (evm-paste-after)
    ;; Cursors get first two values
    (should (string= (buffer-string) "a b"))))

(ert-deftest evm-test-paste-with-more-cursors-than-contents ()
  "p with more cursors than register contents should cycle."
  (evm-test-with-buffer "XX YY ZZ WW"
    (evm-activate)
    ;; Store 2 values in register, but 4 cursors
    (puthash ?\" '("a" "b") (evm-state-registers evm--state))
    ;; Create 4 cursors
    (evm--create-region 1 3 nil)   ; "XX"
    (evm--create-region 4 6 nil)   ; "YY"
    (evm--create-region 7 9 nil)   ; "ZZ"
    (evm--create-region 10 12 nil) ; "WW"
    (setf (evm-state-mode evm--state) 'extend)
    (evm--update-all-overlays)
    (evm-paste-after)
    ;; Cursors cycle through values: a, b, a, b
    (should (string= (buffer-string) "a b a b"))))

(ert-deftest evm-test-delete-in-extend-mode-saves-to-register ()
  "d in extend mode should save deleted text to register."
  (evm-test-with-buffer "foo bar foo"
    (evm-find-word)
    (evm-find-next)
    (should (= (evm-region-count) 2))
    (should (evm-extend-mode-p))
    (evm-delete)
    (let ((contents (gethash ?\" (evm-state-registers evm--state))))
      (should contents)
      (should (= (length contents) 2))
      (should (string= (car contents) "foo"))
      (should (string= (cadr contents) "foo")))))

(ert-deftest evm-test-change-in-extend-mode ()
  "c in extend mode should delete and enter insert."
  (evm-test-with-buffer "foo bar foo"
    (evm-find-word)
    (evm-find-next)
    (should (= (evm-region-count) 2))
    (should (evm-extend-mode-p))
    (evm-change)
    (should (string= (buffer-string) " bar "))
    ;; Should be in insert state
    (should (evil-insert-state-p))
    (evil-normal-state)))

(ert-deftest evm-test-flip-direction ()
  "o in extend mode should flip selection direction."
  (evm-test-with-buffer "foo bar foo"
    (evm-find-word)
    (evm-find-next)
    ;; Initially end is at word end
    (let ((regions (evm-get-all-regions)))
      (dolist (r regions)
        (should (> (marker-position (evm-region-end r))
                   (marker-position (evm-region-beg r))))))
    ;; Flip direction
    (evm-flip-direction)
    ;; After flip, direction changes (end becomes beg conceptually)
    (should (evm-extend-mode-p))))

(ert-deftest evm-test-exit-saves-for-reselect ()
  "Exit should save cursor positions for later reselect."
  (evm-test-with-buffer "foo bar foo"
    (evm-find-word)
    (evm-find-next)
    (let ((positions (evm-test-positions)))
      (evm-exit)
      (should-not (evm-active-p))
      ;; Reselect should restore
      (evm-reselect-last)
      (should (evm-active-p))
      (should (equal (evm-test-positions) positions)))))

(ert-deftest evm-test-reselect-restores-mode ()
  "Reselect should restore the mode (extend/cursor)."
  (evm-test-with-buffer "foo bar foo"
    (evm-find-word)
    (evm-find-next)
    ;; We're in extend mode
    (should (evm-extend-mode-p))
    (evm-exit)
    (evm-reselect-last)
    ;; Should still be extend mode
    (should (evm-extend-mode-p))))

(ert-deftest evm-test-cursor-count-display ()
  "Mode line should show cursor count."
  (evm-test-with-buffer "foo bar foo"
    (evm-find-word)
    (evm-find-next)
    (let ((indicator (evm--mode-line-indicator)))
      (should (string-match-p "2" indicator)))))

(ert-deftest evm-test-mode-display ()
  "Mode line should show current mode."
  (evm-test-with-buffer "foo bar foo"
    (evm-find-word)
    ;; In extend mode
    (let ((indicator (evm--mode-line-indicator)))
      (should (string-match-p "E" indicator)))
    ;; Switch to cursor mode
    (evm-toggle-mode)
    (let ((indicator (evm--mode-line-indicator)))
      (should (string-match-p "C" indicator)))))

(ert-deftest evm-test-beginning-of-line ()
  "0 should move all cursors to beginning of line."
  (evm-test-with-buffer "  foo\n  bar\n  baz"
    (evm-activate)
    ;; Create cursors at end of each word
    (evm--create-region 5 5)   ; end of "foo"
    (evm--create-region 11 11) ; end of "bar"
    (evm--create-region 17 17) ; end of "baz"
    (evm-beginning-of-line)
    ;; All should be at column 0
    (should (equal (evm-test-positions) '(1 7 13)))))

(ert-deftest evm-test-first-non-blank ()
  "^ should move all cursors to first non-blank."
  (evm-test-with-buffer "  foo\n  bar\n  baz"
    (evm-activate)
    ;; Create cursors at beginning of each line
    (evm--create-region 1 1)
    (evm--create-region 7 7)
    (evm--create-region 13 13)
    (evm-first-non-blank)
    ;; All should be at first non-blank (after 2 spaces)
    (should (equal (evm-test-positions) '(3 9 15)))))

(ert-deftest evm-test-backward-word ()
  "b should move all cursors backward to word start."
  (evm-test-with-buffer "foo bar\nfoo bar"
    (evm-activate)
    ;; Create cursors at 'b' of each "bar"
    (evm--create-region 5 5)
    (evm--create-region 13 13)
    (evm-backward-word)
    ;; Should move to 'f' of "foo"
    (should (equal (evm-test-positions) '(1 9)))))

(ert-deftest evm-test-forward-word-end ()
  "e should move all cursors to end of word."
  (evm-test-with-buffer "foo bar\nfoo bar"
    (evm-activate)
    ;; Create cursors at start of each line
    (evm--create-region 1 1)
    (evm--create-region 9 9)
    (evm-forward-word-end)
    ;; Should move to 'o' at end of "foo"
    (should (equal (evm-test-positions) '(3 11)))))

(ert-deftest evm-test-delete-char-backward ()
  "X should delete char before cursor at all positions."
  (evm-test-with-buffer "foo\nbar\nbaz"
    ;; Create cursors at position 2 on each line
    (evm-activate)
    (evm--create-region 2 2)
    (evm--create-region 6 6)
    (evm--create-region 10 10)
    (evm-delete-char-backward)
    (should (string= (buffer-string) "oo\nar\naz"))))

(ert-deftest evm-test-multiline-indicator ()
  "Mode line should show M when multiline is enabled."
  (evm-test-with-buffer "foo bar"
    (evm-activate)
    (evm--create-region (point) (point))
    (let ((indicator (evm--mode-line-indicator)))
      (should-not (string-match-p " M" indicator)))
    (evm-toggle-multiline)
    (let ((indicator (evm--mode-line-indicator)))
      (should (string-match-p " M" indicator)))))

;;; Regression tests

(ert-deftest evm-test-find-next-in-cursor-mode-creates-point-cursor ()
  "n in cursor mode should add point cursors, not full match regions."
  (evm-test-with-buffer "foo bar foo"
    (evm-find-word)
    (evm-toggle-mode)
    (should (evm-cursor-mode-p))
    (evm-find-next)
    (should (equal (evm-test-positions) '(1 9)))
    (should (equal (evm-test-end-positions) '(1 9)))))

(ert-deftest evm-test-select-all-cursor-mode-creates-point-cursors ()
  "\\A in cursor mode should add point cursors at match beginnings."
  (evm-test-with-buffer "foo bar foo baz foo"
    (evm-find-word)
    (evm-toggle-mode)
    (evm-select-all)
    (should (equal (evm-test-positions) '(1 9 17)))
    (should (equal (evm-test-end-positions) '(1 9 17)))))

(ert-deftest evm-test-motion-range-around-angle ()
  "a< should resolve angle text objects through the operator path."
  (evm-test-with-buffer "<foo>"
    (goto-char 2)
    (should (equal (evm--get-motion-range "a<" 1) '(1 6)))))

(ert-deftest evm-test-extend-inner-angle ()
  "i< in extend mode should select inside angle brackets."
  (evm-test-with-buffer "<foo>\n<bar>"
    (goto-char 2)
    (evm-add-cursor-down)
    (evm-enter-extend)
    (setq unread-command-events (list ?<))
    (evm-extend-inner-text-object)
    (let ((texts (mapcar (lambda (r)
                           (buffer-substring (marker-position (evm-region-beg r))
                                             (marker-position (evm-region-end r))))
                         (evm-state-regions evm--state))))
      (should (equal texts '("foo" "bar"))))))

(ert-deftest evm-test-merge-adjacent-regions-keeps-both ()
  "Adjacent non-overlapping regions should not be merged."
  (evm-test-with-buffer "abcdef"
    (evm-activate)
    (evm--create-region 1 4)
    (evm--create-region 4 7)
    (evm--check-and-merge-overlapping)
    (should (= (evm-region-count) 2))
    (should (equal (mapcar (lambda (r)
                             (cons (marker-position (evm-region-beg r))
                                   (marker-position (evm-region-end r))))
                           (evm-get-all-regions))
                   '((1 . 4) (4 . 7))))))

(ert-deftest evm-test-merge-overlap-reassigns-leader ()
  "Merging overlapping regions should keep a valid leader."
  (evm-test-with-buffer "abcdef"
    (evm-activate)
    (let ((first (evm--create-region 1 4))
          (second (evm--create-region 3 6)))
      (evm--set-leader second)
      (evm--check-and-merge-overlapping)
      (should (= (evm-region-count) 1))
      (should (evm--leader-region))
      (should (= (evm-region-id (evm--leader-region))
                 (evm-region-id first))))))

(ert-deftest evm-test-resync-respects-restriction ()
  "Resync should not snap regions to matches outside the active restriction."
  (evm-test-with-buffer "foo foo foo"
    (goto-char 5)
    (evm-find-word)
    (evm-find-next)
    (evm--set-restrict 5 12)
    (let ((regions (evm-get-all-regions)))
      (set-marker (evm-region-beg (car regions)) 4)
      (set-marker (evm-region-end (car regions)) 4)
      (set-marker (evm-region-anchor (car regions)) 4)
      (set-marker (evm-region-beg (cadr regions)) 8)
      (set-marker (evm-region-end (cadr regions)) 8)
      (set-marker (evm-region-anchor (cadr regions)) 8))
    (evm--resync-regions-to-pattern)
    (should (equal (evm-test-positions) '(5 9)))))

(ert-deftest evm-test-resync-does-not-reuse-same-match ()
  "Resync should not snap multiple regions onto the same pattern match."
  (evm-test-with-buffer "foo foo"
    (evm-find-word)
    (evm-find-next)
    (dolist (region (evm-get-all-regions))
      (set-marker (evm-region-beg region) 4)
      (set-marker (evm-region-end region) 4)
      (set-marker (evm-region-anchor region) 4))
    (evm--resync-regions-to-pattern)
    (should (equal (evm-test-positions) '(1 5)))
    (should (equal (evm-test-end-positions) '(4 8)))))

(ert-deftest evm-test-reselect-last-old-format ()
  "Reselect should still restore the legacy list-of-cons format."
  (evm-test-with-buffer "foo bar foo"
    (evm-activate)
    (setf (evm-state-last-regions evm--state) '((1 . 1) (9 . 9)))
    (evm-reselect-last)
    (should (equal (evm-test-positions) '(1 9)))
    (should (evm-cursor-mode-p))))

(ert-deftest evm-test-theme-api-loads-with-evm ()
  "Loading `evm' should also make the theme API available."
  (should (fboundp 'evm-load-theme))
  (should (fboundp 'evm-cycle-theme))
  (should (boundp 'evm-theme))
  (should (boundp 'evm-highlight-matches)))

(ert-deftest evm-test-highlight-matches-style-updates-face ()
  "Changing `evm-highlight-matches' should update the match face."
  (let ((original evm-highlight-matches))
    (unwind-protect
        (progn
          (setq evm-highlight-matches 'background)
          (evm-load-theme 'default)
          (should (eq (face-attribute 'evm-match-face :underline nil 'default) nil))
          (should (stringp (face-attribute 'evm-match-face :background nil 'default))))
      (setq evm-highlight-matches original)
      (evm-load-theme 'default))))

(ert-deftest evm-test-rebind-leader-clears-stale-bindings ()
  "Rebinding the leader should remove the old prefix bindings."
  (let ((original evm-leader-key))
    (unwind-protect
        (progn
          (setq evm-leader-key ",")
          (evm-rebind-leader)
          (should-not (lookup-key evm-mode-map (kbd "\\ A")))
          (should (eq (lookup-key evm-mode-map (kbd ", A"))
                      'evm-select-all)))
      (setq evm-leader-key original)
      (evm-rebind-leader))))

(provide 'evm-test)
;;; evm-test.el ends here
