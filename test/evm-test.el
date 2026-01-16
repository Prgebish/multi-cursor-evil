;;; evm-test.el --- Tests for evil-visual-multi -*- lexical-binding: t; -*-

;;; Commentary:
;; ERT tests for evm package.
;; Run with: make test
;; Or: emacs -Q --batch -L . -l ert -l test/evm-test.el -f ert-run-tests-batch-and-exit

;;; Code:

(require 'ert)
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
  "C-n should activate evm and create cursor on word."
  (evm-test-with-buffer "foo bar foo"
    (evm-find-word)
    (should (evm-active-p))
    (should (= (evm-region-count) 1))
    (should (equal (evm-test-positions) '(1)))))

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

(ert-deftest evm-test-forward-char ()
  "l should move all cursors right."
  (evm-test-with-buffer "foo bar foo"
    (evm-find-word)
    (evm-find-next)
    (let ((pos-before (evm-test-positions)))
      (evm-forward-char)
      (should (equal (evm-test-positions)
                     (mapcar #'1+ pos-before))))))

(ert-deftest evm-test-backward-char ()
  "h should move all cursors left."
  (evm-test-with-buffer "foo bar foo"
    (evm-find-word)
    (evm-find-next)
    (evm-forward-char)
    (evm-forward-char)
    (let ((pos-before (evm-test-positions)))
      (evm-backward-char)
      (should (equal (evm-test-positions)
                     (mapcar #'1- pos-before))))))

(ert-deftest evm-test-forward-word ()
  "w should move all cursors to next word."
  (evm-test-with-buffer "aa bb aa"
    (evm-find-word)
    (evm-find-next)
    ;; Cursors at 1 and 7
    (evm-forward-word)
    ;; Should be at 4 and beyond
    (should (> (car (evm-test-positions)) 1))))

;;; Mode switching tests

(ert-deftest evm-test-toggle-mode ()
  "Tab should toggle between cursor and extend mode."
  (evm-test-with-buffer "foo bar foo"
    (evm-find-word)
    (should (evm-cursor-mode-p))
    (evm-toggle-mode)
    (should (evm-extend-mode-p))
    (evm-toggle-mode)
    (should (evm-cursor-mode-p))))

(ert-deftest evm-test-extend-mode-expands-region ()
  "Extend mode should make regions non-empty."
  (evm-test-with-buffer "foo bar foo"
    (evm-find-word)
    (evm-toggle-mode)
    (let ((region (car (evm-get-all-regions))))
      (should (> (marker-position (evm-region-end region))
                 (marker-position (evm-region-beg region)))))))

;;; Cursor mode editing tests

(ert-deftest evm-test-delete-char ()
  "x should delete char at all cursors."
  (evm-test-with-buffer "foo bar foo"
    (evm-find-word)
    (evm-find-next)
    (evm-delete-char)
    (should (string= (buffer-string) "oo bar oo"))))

(ert-deftest evm-test-replace-char ()
  "r should replace char at all cursors."
  (evm-test-with-buffer "foo bar foo"
    (evm-find-word)
    (evm-find-next)
    (evm-replace-char ?X)
    (should (string= (buffer-string) "Xoo bar Xoo"))))

(ert-deftest evm-test-toggle-case-char ()
  "~ should toggle case at all cursors."
  (evm-test-with-buffer "foo bar foo"
    (evm-find-word)
    (evm-find-next)
    (evm-toggle-case-char)
    (should (string= (buffer-string) "Foo bar Foo"))))

;;; Extend mode editing tests

(ert-deftest evm-test-yank ()
  "y should yank region contents to register."
  (evm-test-with-buffer "foo bar foo"
    (evm-find-word)
    (evm-find-next)
    (evm-toggle-mode)
    (evm-forward-char)
    (evm-forward-char)
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
    (evm-toggle-mode)
    (evm-forward-char)
    (evm-forward-char)
    (evm-delete)
    (should (string= (buffer-string) " bar "))
    (should (evm-cursor-mode-p))))

(ert-deftest evm-test-upcase ()
  "U should uppercase all regions."
  (evm-test-with-buffer "foo bar foo"
    (evm-find-word)
    (evm-find-next)
    (evm-toggle-mode)
    (evm-forward-char)
    (evm-forward-char)
    (evm-upcase)
    (should (string= (buffer-string) "FOO bar FOO"))))

(ert-deftest evm-test-downcase ()
  "u should lowercase all regions."
  (evm-test-with-buffer "FOO bar FOO"
    (evm-find-word)
    (evm-find-next)
    (evm-toggle-mode)
    (evm-forward-char)
    (evm-forward-char)
    (evm-downcase)
    (should (string= (buffer-string) "foo bar foo"))))

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

(provide 'evm-test)
;;; evm-test.el ends here
