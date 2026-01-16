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
    (let ((contents (gethash ?" (evm-state-registers evm--state))))
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
  "Regions in cursor mode should resync to end of match."
  (evm-test-with-buffer "foo bar foo"
    (evm-find-word)
    (evm-find-next)
    ;; Switch to cursor mode - cursors collapse to end (4 and 12)
    (evm-toggle-mode)
    (should (evm-cursor-mode-p))
    (should (equal (evm-test-positions) '(4 12)))

    ;; Run resync
    (evm--resync-regions-to-pattern)

    ;; Should still be at end (4 and 12)
    ;; Prior to fix, this would move them to start (1 and 9)
    (should (equal (evm-test-positions) '(4 12)))))

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

(ert-deftest evm-test-add-cursor-at-click-moves-leader-if-exists ()
  "M-click on existing cursor should move leader."
  (evm-test-with-buffer "foo bar baz"
    (evm-activate)
    (evm--create-region 1 1)
    (evm--create-region 5 5)
    (should (= (evm-region-count) 2))
    ;; Click on position 5 (existing cursor)
    (let ((event `(mouse-1 (,(selected-window) 5 (0 . 0) 0))))
      (evm-add-cursor-at-click event))
    ;; Should still have 2 cursors, leader moved
    (should (= (evm-region-count) 2))
    (should (= (evm-test-leader-pos) 5))))

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

(provide 'evm-test)
;;; evm-test.el ends here