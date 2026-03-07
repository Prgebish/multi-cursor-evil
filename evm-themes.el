;;; evm-themes.el --- Theming system for evil-visual-multi -*- lexical-binding: t; -*-

;; Copyright (C) 2025
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
;;   (setq evm-theme 'iceblue)
;;   (evm-load-theme 'neon)

;;; Code:

(require 'evm-core)

;;; Theme definitions

(defvar evm-themes-alist
  '((iceblue . evm-theme-iceblue)
    (ocean . evm-theme-ocean)
    (neon . evm-theme-neon)
    (purplegray . evm-theme-purplegray)
    (nord . evm-theme-nord)
    (codedark . evm-theme-codedark)
    (spacegray . evm-theme-spacegray)
    (olive . evm-theme-olive)
    (sand . evm-theme-sand)
    (paper . evm-theme-paper)
    (lightblue1 . evm-theme-lightblue1)
    (lightblue2 . evm-theme-lightblue2)
    (lightpurple1 . evm-theme-lightpurple1)
    (lightpurple2 . evm-theme-lightpurple2))
  "Alist of theme names to theme functions.")

(defvar evm-dark-themes
  '(iceblue ocean neon purplegray nord codedark spacegray olive sand)
  "List of themes suitable for dark backgrounds.")

(defvar evm-light-themes
  '(lightblue1 lightblue2 lightpurple1 lightpurple2 paper sand)
  "List of themes suitable for light backgrounds.")

(defcustom evm-theme 'default
  "Color theme for evm cursors and regions.
Available themes: default, iceblue, ocean, neon, purplegray, nord,
codedark, spacegray, olive, sand, paper, lightblue1, lightblue2,
lightpurple1, lightpurple2.

Set to `default' to use the base face definitions."
  :type `(choice (const :tag "Default" default)
                 ,@(mapcar (lambda (th)
                             `(const :tag ,(capitalize (symbol-name (car th)))
                                     ,(car th)))
                           evm-themes-alist))
  :group 'evm
  :set (lambda (sym val)
         (set-default sym val)
         (when (fboundp 'evm-load-theme)
           (evm-load-theme val))))

(defcustom evm-highlight-matches 'underline
  "How to highlight pattern matches.
Can be `underline', `background', or nil to disable."
  :type '(choice (const :tag "Underline" underline)
                 (const :tag "Background" background)
                 (const :tag "None" nil))
  :group 'evm
  :set (lambda (sym val)
         (set-default sym val)
         (when (and (boundp 'evm-theme)
                    (fboundp 'evm-load-theme))
           (evm-load-theme evm-theme))))

;;; Theme loading

(defun evm-load-theme (theme)
  "Load the specified THEME for evm faces.
If THEME is `default', reset to default face definitions."
  (interactive
   (list (intern (completing-read "Theme: "
                                  (cons 'default (mapcar #'car evm-themes-alist))
                                  nil t))))
  (if (eq theme 'default)
      (evm-theme-default)
    (let ((theme-fn (alist-get theme evm-themes-alist)))
      (if theme-fn
          (funcall theme-fn)
        (message "Unknown theme: %s" theme)))))

(defun evm--set-match-face (match-bg &optional match-ul)
  "Apply match highlighting using MATCH-BG and MATCH-UL.
The exact style is controlled by `evm-highlight-matches'."
  (pcase evm-highlight-matches
    ('underline
     (set-face-attribute 'evm-match-face nil
                         :background 'unspecified
                         :foreground 'unspecified
                         :underline (or match-ul t)))
    ('background
     (set-face-attribute 'evm-match-face nil
                         :background (or match-bg 'unspecified)
                         :foreground 'unspecified
                         :underline nil))
    (_
     (set-face-attribute 'evm-match-face nil
                         :background 'unspecified
                         :foreground 'unspecified
                         :underline nil))))

(defun evm--set-faces (cursor-bg cursor-fg region-bg region-fg
                                  leader-cursor-bg leader-cursor-fg
                                  leader-region-bg leader-region-fg
                                  &optional match-bg match-ul)
  "Helper to set all evm faces at once.
CURSOR-BG, CURSOR-FG: cursor face colors.
REGION-BG, REGION-FG: region face colors.
LEADER-CURSOR-BG, LEADER-CURSOR-FG: leader cursor colors.
LEADER-REGION-BG, LEADER-REGION-FG: leader region colors.
MATCH-BG, MATCH-UL: match face background and underline."
  ;; Cursor face
  (set-face-attribute 'evm-cursor-face nil
                      :background cursor-bg
                      :foreground (or cursor-fg 'unspecified))
  ;; Region face
  (set-face-attribute 'evm-region-face nil
                      :background region-bg
                      :foreground (or region-fg 'unspecified))
  ;; Leader cursor
  (set-face-attribute 'evm-leader-cursor-face nil
                      :background leader-cursor-bg
                      :foreground (or leader-cursor-fg 'unspecified))
  ;; Leader region
  (set-face-attribute 'evm-leader-region-face nil
                      :background leader-region-bg
                      :foreground (or leader-region-fg 'unspecified))
  ;; Match face
  (evm--set-match-face match-bg match-ul))

;;; Theme definitions

(defun evm-theme-default ()
  "Reset to default evm faces."
  (set-face-attribute 'evm-cursor-face nil
                      :background (if (eq (frame-parameter nil 'background-mode) 'dark)
                                      "#3B82F6" "#2563EB")
                      :foreground "white")
  (set-face-attribute 'evm-region-face nil
                      :background (if (eq (frame-parameter nil 'background-mode) 'dark)
                                      "#166534" "#BBF7D0")
                      :foreground 'unspecified)
  (set-face-attribute 'evm-leader-cursor-face nil
                      :background (if (eq (frame-parameter nil 'background-mode) 'dark)
                                      "#F97316" "#EA580C")
                      :foreground (if (eq (frame-parameter nil 'background-mode) 'dark)
                                      "black" "white"))
  (set-face-attribute 'evm-leader-region-face nil
                      :background (if (eq (frame-parameter nil 'background-mode) 'dark)
                                      "#854D0E" "#FEF08A")
                      :foreground 'unspecified)
  (evm--set-match-face
   (if (eq (frame-parameter nil 'background-mode) 'dark)
       "#374151"
     "#E5E7EB")
   t))

;; Dark themes

(defun evm-theme-iceblue ()
  "Ice blue theme - cool blue tones."
  (evm--set-faces
   "#0087af" "#87dfff"   ; cursor: bright blue bg, light cyan fg
   "#005f87" nil         ; region: darker blue
   "#dfaf87" "#262626"   ; leader cursor: warm beige (stands out)
   "#00688B" nil         ; leader region: teal blue
   "#1a3a4a" t))         ; match: dark blue-gray, underlined

(defun evm-theme-ocean ()
  "Ocean theme - deep blue tones."
  (evm--set-faces
   "#87afff" "#4e4e4e"   ; cursor: soft blue, dark text
   "#005faf" nil         ; region: deep blue
   "#dfdf87" "#4e4e4e"   ; leader cursor: yellow
   "#004080" nil         ; leader region: navy
   "#1a2a4a" t))

(defun evm-theme-neon ()
  "Neon theme - vibrant colors."
  (evm--set-faces
   "#00afff" "#4e4e4e"   ; cursor: neon cyan
   "#005fdf" "#89afaf"   ; region: electric blue
   "#ffdf5f" "#4e4e4e"   ; leader cursor: neon yellow
   "#004a9f" nil         ; leader region: darker blue
   "#1a2a5a" t))

(defun evm-theme-purplegray ()
  "Purple gray theme - muted purple tones."
  (evm--set-faces
   "#8787af" "#5f0087"   ; cursor: lavender, dark purple fg
   "#544a65" nil         ; region: purple gray
   "#af87ff" "#262626"   ; leader cursor: bright purple
   "#443a55" nil         ; leader region: darker purple
   "#3a3545" t))

(defun evm-theme-nord ()
  "Nord theme - arctic, bluish colors."
  (evm--set-faces
   "#8a8a8a" "#005f87"   ; cursor: gray, blue text
   "#434C5E" nil         ; region: nord gray
   "#AF5F5F" "#262626"   ; leader cursor: muted red
   "#3B4252" nil         ; leader region: darker nord
   "#2E3440" t))

(defun evm-theme-codedark ()
  "Code dark theme - VS Code inspired."
  (evm--set-faces
   "#6A7D89" "#C5D4DD"   ; cursor: blue-gray
   "#264F78" nil         ; region: selection blue
   "#AF5F5F" "#262626"   ; leader cursor: muted red
   "#1E3A5F" nil         ; leader region: darker blue
   "#1E1E1E" t))

(defun evm-theme-spacegray ()
  "Space gray theme - neutral grays."
  (evm--set-faces
   "Grey50" "#4e4e4e"    ; cursor: medium gray
   "#404040" nil         ; region: dark gray
   "#AF5F5F" "#262626"   ; leader cursor: muted red
   "#353535" nil         ; leader region: darker gray
   "#2a2a2a" t))

(defun evm-theme-olive ()
  "Olive theme - earthy green tones."
  (evm--set-faces
   "olivedrab" "khaki"   ; cursor: olive with khaki text
   "olive" "black"       ; region: olive
   "#AF5F5F" "#262626"   ; leader cursor: muted red
   "#4a5a2a" nil         ; leader region: dark olive
   "#3a4520" t))

(defun evm-theme-sand ()
  "Sand theme - warm earthy tones (works for both dark/light)."
  (evm--set-faces
   "olivedrab" "khaki"   ; cursor
   "darkkhaki" "black"   ; region
   "#AF5F5F" "#262626"   ; leader cursor
   "#8B8668" nil         ; leader region
   "#6B6648" t))

;; Light themes

(defun evm-theme-paper ()
  "Paper theme - minimal light theme."
  (evm--set-faces
   "#4c4e50" "#d8d5c7"   ; cursor: dark gray, paper text
   "#bfbcaf" "black"     ; region: paper gray
   "#000000" "#d8d5c7"   ; leader cursor: black
   "#a5a295" nil         ; leader region: darker paper
   "#d5d2c5" t))

(defun evm-theme-lightblue1 ()
  "Light blue theme variant 1."
  (evm--set-faces
   "#87afff" "#4e4e4e"   ; cursor: soft blue
   "#afdfff" nil         ; region: light blue
   "#df5f5f" "#dadada"   ; leader cursor: coral red
   "#8fcfef" nil         ; leader region: medium blue
   "#cfe7f7" t))

(defun evm-theme-lightblue2 ()
  "Light blue theme variant 2."
  (evm--set-faces
   "#87afff" "#4e4e4e"   ; cursor
   "#87dfff" nil         ; region: cyan tint
   "#df5f5f" "#dadada"   ; leader cursor
   "#67bfdf" nil         ; leader region
   "#b7efff" t))

(defun evm-theme-lightpurple1 ()
  "Light purple theme variant 1."
  (evm--set-faces
   "#dfafff" "#5f0087"   ; cursor: light purple, dark purple text
   "#ffdfff" nil         ; region: pink-purple
   "#af5fff" "#ffdfff"   ; leader cursor: vivid purple
   "#efcfff" nil         ; leader region
   "#f5e5ff" t))

(defun evm-theme-lightpurple2 ()
  "Light purple theme variant 2."
  (evm--set-faces
   "#dfafff" "#5f0087"   ; cursor
   "#dfdfff" nil         ; region: lavender
   "#af5fff" "#ffdfff"   ; leader cursor
   "#cfcfef" nil         ; leader region
   "#efefff" t))

;;; Theme cycling

(defvar evm--theme-index 0
  "Current index in theme list for cycling.")

(defun evm-cycle-theme ()
  "Cycle to the next evm theme.
Useful for previewing themes interactively."
  (interactive)
  (let* ((themes (cons 'default (mapcar #'car evm-themes-alist)))
         (len (length themes)))
    (setq evm--theme-index (mod (1+ evm--theme-index) len))
    (let ((theme (nth evm--theme-index themes)))
      (setq evm-theme theme)
      (evm-load-theme theme)
      (message "EVM theme: %s" theme))))

;;; Keep evm faces in sync with Emacs theme changes

(defun evm--after-theme-change (&rest _)
  "Reload `evm-theme' after an Emacs theme change."
  (when (and (boundp 'evm-theme) evm-theme)
    (evm-load-theme evm-theme)))

(unless (advice-member-p #'evm--after-theme-change 'load-theme)
  (advice-add 'load-theme :after #'evm--after-theme-change))

(unless (advice-member-p #'evm--after-theme-change 'enable-theme)
  (advice-add 'enable-theme :after #'evm--after-theme-change))

(unless (advice-member-p #'evm--after-theme-change 'disable-theme)
  (advice-add 'disable-theme :after #'evm--after-theme-change))

(provide 'evm-themes)
;; Local Variables:
;; package-lint-main-file: "evm.el"
;; End:
;;; evm-themes.el ends here
