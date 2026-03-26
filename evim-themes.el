;;; evim-themes.el --- Theming system for evil-visual-multi -*- lexical-binding: t; -*-

;; Copyright (C) 2025 Vadim Pavlov <vadim198527@gmail.com>
;;
;; Permission is hereby granted, free of charge, to any person obtaining a copy
;; of this software and associated documentation files (the "Software"), to deal
;; in the Software without restriction, including without limitation the rights
;; to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
;; copies of the Software, and to permit persons to whom the Software is
;; furnished to do so, subject to the following conditions:
;;
;; The above copyright notice and this permission notice shall be included in all
;; copies or substantial portions of the Software.
;;
;; THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
;; IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
;; FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
;; AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
;; LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
;; OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
;; SOFTWARE.
;;
;; SPDX-License-Identifier: MIT

;;; Commentary:

;; Theming system for evil-visual-multi, inspired by vim-visual-multi.
;; Provides multiple color themes for cursor and region highlighting.
;;
;; Available themes:
;; Dark: iceblue, ocean, neon, purplegray, nord, codedark, spacegray, olive
;; Light: lightblue1, lightblue2, lightpurple1, lightpurple2, paper, sand
;;
;; Usage:
;;   (setq evim-theme 'iceblue)
;;   (evim-load-theme 'neon)

;;; Code:

(require 'evim-core)

;;; Theme definitions

(defvar evim-themes-alist
  '((iceblue . evim-theme-iceblue)
    (ocean . evim-theme-ocean)
    (neon . evim-theme-neon)
    (purplegray . evim-theme-purplegray)
    (nord . evim-theme-nord)
    (codedark . evim-theme-codedark)
    (spacegray . evim-theme-spacegray)
    (olive . evim-theme-olive)
    (sand . evim-theme-sand)
    (paper . evim-theme-paper)
    (lightblue1 . evim-theme-lightblue1)
    (lightblue2 . evim-theme-lightblue2)
    (lightpurple1 . evim-theme-lightpurple1)
    (lightpurple2 . evim-theme-lightpurple2))
  "Alist of theme names to theme functions.")

(defvar evim-dark-themes
  '(iceblue ocean neon purplegray nord codedark spacegray olive sand)
  "List of themes suitable for dark backgrounds.")

(defvar evim-light-themes
  '(lightblue1 lightblue2 lightpurple1 lightpurple2 paper sand)
  "List of themes suitable for light backgrounds.")

(defcustom evim-theme 'default
  "Color theme for evim cursors and regions.
Available themes: default, iceblue, ocean, neon, purplegray, nord,
codedark, spacegray, olive, sand, paper, lightblue1, lightblue2,
lightpurple1, lightpurple2.

Set to `default' to use the base face definitions."
  :type `(choice (const :tag "Default" default)
                 ,@(mapcar (lambda (th)
                             `(const :tag ,(capitalize (symbol-name (car th)))
                                     ,(car th)))
                           evim-themes-alist))
  :group 'evim
  :set (lambda (sym val)
         (set-default sym val)
         (when (fboundp 'evim-load-theme)
           (evim-load-theme val))))

(defcustom evim-highlight-matches 'underline
  "How to highlight pattern matches.
Can be `underline', `background', or nil to disable."
  :type '(choice (const :tag "Underline" underline)
                 (const :tag "Background" background)
                 (const :tag "None" nil))
  :group 'evim
  :set (lambda (sym val)
         (set-default sym val)
         (when (and (boundp 'evim-theme)
                    (fboundp 'evim-load-theme))
           (evim-load-theme evim-theme))))

;;; Theme loading

(defun evim-load-theme (theme)
  "Load the specified THEME for evim faces.
If THEME is `default', reset to default face definitions."
  (interactive
   (list (intern (completing-read "Theme: "
                                  (cons 'default (mapcar #'car evim-themes-alist))
                                  nil t))))
  (if (eq theme 'default)
      (evim-theme-default)
    (let ((theme-fn (alist-get theme evim-themes-alist)))
      (if theme-fn
          (funcall theme-fn)
        (message "Unknown theme: %s" theme)))))

(defun evim--set-match-face (match-bg &optional match-ul)
  "Apply match highlighting using MATCH-BG and MATCH-UL.
The exact style is controlled by `evim-highlight-matches'."
  (pcase evim-highlight-matches
    ('underline
     (set-face-attribute 'evim-match-face nil
                         :background 'unspecified
                         :foreground 'unspecified
                         :underline (or match-ul t)))
    ('background
     (set-face-attribute 'evim-match-face nil
                         :background (or match-bg 'unspecified)
                         :foreground 'unspecified
                         :underline nil))
    (_
     (set-face-attribute 'evim-match-face nil
                         :background 'unspecified
                         :foreground 'unspecified
                         :underline nil))))

(defun evim--set-faces (cursor-bg cursor-fg region-bg region-fg
                                  leader-cursor-bg leader-cursor-fg
                                  leader-region-bg leader-region-fg
                                  &optional match-bg match-ul)
  "Helper to set all evim faces at once.
CURSOR-BG, CURSOR-FG: cursor face colors.
REGION-BG, REGION-FG: region face colors.
LEADER-CURSOR-BG, LEADER-CURSOR-FG: leader cursor colors.
LEADER-REGION-BG, LEADER-REGION-FG: leader region colors.
MATCH-BG, MATCH-UL: match face background and underline."
  ;; Cursor face
  (set-face-attribute 'evim-cursor-face nil
                      :background cursor-bg
                      :foreground (or cursor-fg 'unspecified))
  ;; Region face
  (set-face-attribute 'evim-region-face nil
                      :background region-bg
                      :foreground (or region-fg 'unspecified))
  ;; Leader cursor
  (set-face-attribute 'evim-leader-cursor-face nil
                      :background leader-cursor-bg
                      :foreground (or leader-cursor-fg 'unspecified))
  ;; Leader region
  (set-face-attribute 'evim-leader-region-face nil
                      :background leader-region-bg
                      :foreground (or leader-region-fg 'unspecified))
  ;; Match face
  (evim--set-match-face match-bg match-ul))

;;; Theme definitions

(defun evim-theme-default ()
  "Reset to default evim faces."
  (set-face-attribute 'evim-cursor-face nil
                      :background (if (eq (frame-parameter nil 'background-mode) 'dark)
                                      "#3B82F6" "#2563EB")
                      :foreground "white")
  (set-face-attribute 'evim-region-face nil
                      :background (if (eq (frame-parameter nil 'background-mode) 'dark)
                                      "#166534" "#BBF7D0")
                      :foreground 'unspecified)
  (set-face-attribute 'evim-leader-cursor-face nil
                      :background (if (eq (frame-parameter nil 'background-mode) 'dark)
                                      "#F97316" "#EA580C")
                      :foreground (if (eq (frame-parameter nil 'background-mode) 'dark)
                                      "black" "white"))
  (set-face-attribute 'evim-leader-region-face nil
                      :background (if (eq (frame-parameter nil 'background-mode) 'dark)
                                      "#854D0E" "#FEF08A")
                      :foreground 'unspecified)
  (evim--set-match-face
   (if (eq (frame-parameter nil 'background-mode) 'dark)
       "#374151"
     "#E5E7EB")
   t))

;; Dark themes

(defun evim-theme-iceblue ()
  "Ice blue theme - cool blue tones."
  (evim--set-faces
   "#0087af" "#87dfff"   ; cursor: bright blue bg, light cyan fg
   "#005f87" nil         ; region: darker blue
   "#dfaf87" "#262626"   ; leader cursor: warm beige (stands out)
   "#00688B" nil         ; leader region: teal blue
   "#1a3a4a" t))         ; match: dark blue-gray, underlined

(defun evim-theme-ocean ()
  "Ocean theme - deep blue tones."
  (evim--set-faces
   "#87afff" "#4e4e4e"   ; cursor: soft blue, dark text
   "#005faf" nil         ; region: deep blue
   "#dfdf87" "#4e4e4e"   ; leader cursor: yellow
   "#004080" nil         ; leader region: navy
   "#1a2a4a" t))

(defun evim-theme-neon ()
  "Neon theme - vibrant colors."
  (evim--set-faces
   "#00afff" "#4e4e4e"   ; cursor: neon cyan
   "#005fdf" "#89afaf"   ; region: electric blue
   "#ffdf5f" "#4e4e4e"   ; leader cursor: neon yellow
   "#004a9f" nil         ; leader region: darker blue
   "#1a2a5a" t))

(defun evim-theme-purplegray ()
  "Purple gray theme - muted purple tones."
  (evim--set-faces
   "#8787af" "#5f0087"   ; cursor: lavender, dark purple fg
   "#544a65" nil         ; region: purple gray
   "#af87ff" "#262626"   ; leader cursor: bright purple
   "#443a55" nil         ; leader region: darker purple
   "#3a3545" t))

(defun evim-theme-nord ()
  "Nord theme - arctic, bluish colors."
  (evim--set-faces
   "#8a8a8a" "#005f87"   ; cursor: gray, blue text
   "#434C5E" nil         ; region: nord gray
   "#AF5F5F" "#262626"   ; leader cursor: muted red
   "#3B4252" nil         ; leader region: darker nord
   "#2E3440" t))

(defun evim-theme-codedark ()
  "Code dark theme - VS Code inspired."
  (evim--set-faces
   "#6A7D89" "#C5D4DD"   ; cursor: blue-gray
   "#264F78" nil         ; region: selection blue
   "#AF5F5F" "#262626"   ; leader cursor: muted red
   "#1E3A5F" nil         ; leader region: darker blue
   "#1E1E1E" t))

(defun evim-theme-spacegray ()
  "Space gray theme - neutral grays."
  (evim--set-faces
   "Grey50" "#4e4e4e"    ; cursor: medium gray
   "#404040" nil         ; region: dark gray
   "#AF5F5F" "#262626"   ; leader cursor: muted red
   "#353535" nil         ; leader region: darker gray
   "#2a2a2a" t))

(defun evim-theme-olive ()
  "Olive theme - earthy green tones."
  (evim--set-faces
   "olivedrab" "khaki"   ; cursor: olive with khaki text
   "olive" "black"       ; region: olive
   "#AF5F5F" "#262626"   ; leader cursor: muted red
   "#4a5a2a" nil         ; leader region: dark olive
   "#3a4520" t))

(defun evim-theme-sand ()
  "Sand theme - warm earthy tones (works for both dark/light)."
  (evim--set-faces
   "olivedrab" "khaki"   ; cursor
   "darkkhaki" "black"   ; region
   "#AF5F5F" "#262626"   ; leader cursor
   "#8B8668" nil         ; leader region
   "#6B6648" t))

;; Light themes

(defun evim-theme-paper ()
  "Paper theme - minimal light theme."
  (evim--set-faces
   "#4c4e50" "#d8d5c7"   ; cursor: dark gray, paper text
   "#bfbcaf" "black"     ; region: paper gray
   "#000000" "#d8d5c7"   ; leader cursor: black
   "#a5a295" nil         ; leader region: darker paper
   "#d5d2c5" t))

(defun evim-theme-lightblue1 ()
  "Light blue theme variant 1."
  (evim--set-faces
   "#87afff" "#4e4e4e"   ; cursor: soft blue
   "#afdfff" nil         ; region: light blue
   "#df5f5f" "#dadada"   ; leader cursor: coral red
   "#8fcfef" nil         ; leader region: medium blue
   "#cfe7f7" t))

(defun evim-theme-lightblue2 ()
  "Light blue theme variant 2."
  (evim--set-faces
   "#87afff" "#4e4e4e"   ; cursor
   "#87dfff" nil         ; region: cyan tint
   "#df5f5f" "#dadada"   ; leader cursor
   "#67bfdf" nil         ; leader region
   "#b7efff" t))

(defun evim-theme-lightpurple1 ()
  "Light purple theme variant 1."
  (evim--set-faces
   "#dfafff" "#5f0087"   ; cursor: light purple, dark purple text
   "#ffdfff" nil         ; region: pink-purple
   "#af5fff" "#ffdfff"   ; leader cursor: vivid purple
   "#efcfff" nil         ; leader region
   "#f5e5ff" t))

(defun evim-theme-lightpurple2 ()
  "Light purple theme variant 2."
  (evim--set-faces
   "#dfafff" "#5f0087"   ; cursor
   "#dfdfff" nil         ; region: lavender
   "#af5fff" "#ffdfff"   ; leader cursor
   "#cfcfef" nil         ; leader region
   "#efefff" t))

;;; Theme cycling

(defvar evim--theme-index 0
  "Current index in theme list for cycling.")

(defun evim-cycle-theme ()
  "Cycle to the next evim theme.
Useful for previewing themes interactively."
  (interactive)
  (let* ((themes (cons 'default (mapcar #'car evim-themes-alist)))
         (len (length themes)))
    (setq evim--theme-index (mod (1+ evim--theme-index) len))
    (let ((theme (nth evim--theme-index themes)))
      (setq evim-theme theme)
      (evim-load-theme theme)
      (message "EVIM theme: %s" theme))))

;;; Keep evim faces in sync with Emacs theme changes

(defun evim--after-theme-change (&rest _)
  "Reload `evim-theme' after an Emacs theme change."
  (when (and (boundp 'evim-theme) evim-theme)
    (evim-load-theme evim-theme)))

(unless (advice-member-p #'evim--after-theme-change 'load-theme)
  (advice-add 'load-theme :after #'evim--after-theme-change))

(unless (advice-member-p #'evim--after-theme-change 'enable-theme)
  (advice-add 'enable-theme :after #'evim--after-theme-change))

(unless (advice-member-p #'evim--after-theme-change 'disable-theme)
  (advice-add 'disable-theme :after #'evim--after-theme-change))

(provide 'evim-themes)
;; Local Variables:
;; package-lint-main-file: "evim.el"
;; End:
;;; evim-themes.el ends here
