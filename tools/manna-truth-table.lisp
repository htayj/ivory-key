;;;; Manna Cadet static XKB truth-table inventory.
;;;; SPDX-License-Identifier: GPL-3.0-or-later
;;;;
;;;; Usage:
;;;;   sbcl --script tools/manna-truth-table.lisp render ROOT
;;;;   sbcl --script tools/manna-truth-table.lisp verify ROOT
;;;;   sbcl --script tools/manna-truth-table.lisp fixture ROOT
;;;;
;;;; This script is deliberately read-only.  It accepts only the frozen Manna
;;;; Cadet checkout recorded below; VERIFY also checks the canonical table
;;;; digest after parsing the static Group 1 and Top symbol arrays.

(require :asdf)

(defpackage #:ivory-key.manna-truth-table
  (:use #:cl)
  (:export #:main))

(in-package #:ivory-key.manna-truth-table)

(defparameter +baseline-commit+
  "e5f7e81cdb6e30a7735cdcab622ede29007e379b")

(defparameter +baseline-files+
  '(("xkb/symbols/spacecadet" .
     "b559d8832462556f990bee273b53a91ab2c6c81fc7e2fa9c9bb0cdfce739f3a0")
    ("xkb/keymap/spacecadet.xkb" .
     "68dcb0f3c77fa2b88cfc2db04347b07089efad25a2bcf8b86324a5f283539fba")
    ("kanata/kinesis.advantage2.layered.kanata.kbd" .
     "d36a93eab6e2355707f7a6bfbcfac2a4e3b0ea361cc399d388543f51e1f5226b")
    ("kanata/kinesis.advantage360.layered.kanata.kbd" .
     "632a7574938b535a8d4b1d2e3ce1c5f711d0486298d2ce4d98adda702496df5a")
    ("space-cadet-layered-mnemonics.md" .
     "8c4c975e0acee03f96f51ae144f2c12c1efc249672b4ef50e39a781e8f27bc7b")))

;; Filled from the canonical render of the frozen source.  Keeping this apart
;; from the source-file hashes catches accidental parser/ordering regressions.
(defparameter +expected-truth-table-sha256+
  "3ef72eabdd26d2154481c1b8fd0becba50dfbb9a0ba50d0d37556930f92dc807")

(defparameter +static-xkb-keys+
  '("AE01" "AE02" "AE03" "AE04" "AE05" "AE06" "AE07" "AE08" "AE09" "AE10"
    "AE11" "AE12" "BKSP" "TAB" "AD01" "AD02" "AD03" "AD04" "AD05" "AD06"
    "AD07" "AD08" "AD09" "AD10" "AD11" "AD12" "RTRN" "AC01" "AC02" "AC03"
    "AC04" "AC05" "AC06" "AC07" "AC08" "AC09" "AC10" "AC11" "TLDE" "BKSL"
    "AB01" "AB02" "AB03" "AB04" "AB05" "AB06" "AB07" "AB08" "AB09" "AB10"
    "SPCE" "LSGT"))

(defparameter +xkb-position-names+
  '(("AE01" . "number-1") ("AE02" . "number-2")
    ("AE03" . "number-3") ("AE04" . "number-4")
    ("AE05" . "number-5") ("AE06" . "number-6")
    ("AE07" . "number-7") ("AE08" . "number-8")
    ("AE09" . "number-9") ("AE10" . "number-0")
    ("AE11" . "number-minus") ("AE12" . "number-equals")
    ("BKSP" . "backspace") ("TAB" . "tab")
    ("AD01" . "q") ("AD02" . "w") ("AD03" . "e")
    ("AD04" . "r") ("AD05" . "t") ("AD06" . "y")
    ("AD07" . "u") ("AD08" . "i") ("AD09" . "o")
    ("AD10" . "p") ("AD11" . "left-bracket")
    ("AD12" . "right-bracket") ("RTRN" . "return")
    ("AC01" . "a") ("AC02" . "s") ("AC03" . "d")
    ("AC04" . "f") ("AC05" . "g") ("AC06" . "h")
    ("AC07" . "j") ("AC08" . "k") ("AC09" . "l")
    ("AC10" . "semicolon") ("AC11" . "apostrophe")
    ("TLDE" . "grave") ("BKSL" . "backslash")
    ("AB01" . "z") ("AB02" . "x") ("AB03" . "c")
    ("AB04" . "v") ("AB05" . "b") ("AB06" . "n")
    ("AB07" . "m") ("AB08" . "comma") ("AB09" . "period")
    ("AB10" . "slash") ("SPCE" . "space")
    ("LSGT" . "less-greater")))

(defparameter +contexts+
  '("plain/roman/base" "shifted/roman/base"
    "plain/greek/base" "shifted/greek/base"
    "plain/roman/top" "shifted/roman/top"
    "plain/greek/top" "shifted/greek/top"))

(defun trim (string)
  (string-trim '(#\Space #\Tab #\Newline #\Return) string))

(defun command-output (arguments &key directory input)
  (trim (uiop:run-program arguments :directory directory :input input
                          :output :string :error-output :string)))

(defun line-list (text)
  (let ((lines nil)
        (start 0))
    (loop
      (let ((end (position #\Newline text :start start)))
        (push (subseq text start end) lines)
        (unless end
          (return (nreverse lines)))
        (setf start (1+ end))))))

(defun split-on-comma (text)
  (let ((parts nil)
        (start 0))
    (loop
      (let ((end (position #\, text :start start)))
        (push (trim (subseq text start end)) parts)
        (unless end
          (return (nreverse parts)))
        (setf start (1+ end))))))

(defun pathname-at (root relative)
  (merge-pathnames relative (uiop:ensure-directory-pathname root)))

(defun sha256 (pathname)
  (let* ((output (command-output (list "sha256sum" (namestring pathname))))
         (separator (position-if (lambda (character)
                                   (member character '(#\Space #\Tab))) output)))
    (if separator (subseq output 0 separator) output)))

(defun section (text start-marker end-marker)
  (let ((start (search start-marker text)))
    (unless start
      (error "Could not find XKB section ~S." start-marker))
    (let ((end (search end-marker text :start2 (+ start (length start-marker)))))
      (unless end
        (error "Could not find end marker ~S after ~S." end-marker start-marker))
      (subseq text start end))))

(defun xkb-key-name (line)
  (let ((start (search "key <" line)))
    (when start
      (let* ((name-start (+ start (length "key <")))
             (end (position #\> line :start name-start)))
        (and end (subseq line name-start end))))))

(defun xkb-symbol-list (line)
  (let ((marker (search "symbols[Group1]=[" line)))
    (when marker
      (let* ((start (+ marker (length "symbols[Group1]=[")))
             (end (position #\] line :start start)))
        (unless end
          (error "Unterminated symbols array: ~A" line))
        (split-on-comma (subseq line start end))))))

(defun parse-static-section (text expected-level-count)
  "Extract the single-line static symbols arrays in one frozen XKB section."
  (let ((current-key nil)
        (tables nil))
    (dolist (line (line-list text))
      (let ((key (xkb-key-name line)))
        (when key (setf current-key key)))
      (let ((symbols (and current-key (xkb-symbol-list line))))
        (when symbols
          (when (= (length symbols) expected-level-count)
            (push (cons current-key symbols) tables))
          (setf current-key nil))))
    (sort tables #'string< :key #'car)))

(defun table-entry (tables key)
  (or (cdr (assoc key tables :test #'string=))
      (error "Frozen XKB table lacks key <~A>." key)))

(defun parsed-truth-table (root)
  (let* ((symbols-path (pathname-at root "xkb/symbols/spacecadet"))
         (text (uiop:read-file-string symbols-path))
         (g1 (parse-static-section
              (section text "xkb_symbols \"g1\"" "xkb_symbols \"top\"") 4))
         (top (parse-static-section
               (section text "xkb_symbols \"top\"" "xkb_symbols \"base\"") 2)))
    (let ((expected (sort (copy-list +static-xkb-keys+) #'string<)))
      (unless (and (equal expected (mapcar #'car (sort (copy-list g1) #'string< :key #'car)))
                   (equal expected (mapcar #'car (sort (copy-list top) #'string< :key #'car))))
        (error "Static XKB key set changed; refusing to invent a transcription.")))
    (mapcar (lambda (key)
              (let ((base (table-entry g1 key))
                    (top-levels (table-entry top key)))
                (list key (append base
                                  (list (first top-levels) (second top-levels)
                                        (first top-levels) (second top-levels))))))
            +static-xkb-keys+)))

(defun canonical-truth-table (root)
  (with-output-to-string (stream)
    (format stream "manna-cadet-static-xkb-truth-table-v1~%")
    (format stream "commit ~A~%" (command-output '("git" "rev-parse" "HEAD") :directory root))
    (dolist (file +baseline-files+)
      (format stream "sha256 ~A ~A~%" (cdr file) (car file)))
    (dolist (entry (parsed-truth-table root))
      (format stream "~A|~{~A~^|~}~%" (first entry) (second entry)))))

(defun string-sha256 (text)
  (let ((output (command-output '("sha256sum") :input (make-string-input-stream text))))
    (subseq output 0 (position-if (lambda (character)
                                    (member character '(#\Space #\Tab))) output))))

(defun verify-baseline (root)
  (let ((commit (command-output '("git" "rev-parse" "HEAD") :directory root)))
    (unless (string= commit +baseline-commit+)
      (error "Expected frozen Manna Cadet commit ~A, got ~A."
             +baseline-commit+ commit)))
  (dolist (file +baseline-files+)
    (let ((actual (sha256 (pathname-at root (car file)))))
      (unless (string= actual (cdr file))
        (error "Frozen hash mismatch for ~A: expected ~A, got ~A."
               (car file) (cdr file) actual))))
  (let ((actual (string-sha256 (canonical-truth-table root))))
    (when (and +expected-truth-table-sha256+
               (not (string= actual +expected-truth-table-sha256+)))
      (error "Canonical truth-table digest mismatch: expected ~A, got ~A."
             +expected-truth-table-sha256+ actual))
    actual))

(defun render-markdown (root stream)
  (format stream "# Frozen Manna Cadet static XKB truth table~%~%")
  (format stream "Commit: `~A`~%~%" (command-output '("git" "rev-parse" "HEAD") :directory root))
  (format stream "| XKB key |")
  (dolist (context +contexts+)
    (format stream " ~A |" context))
  (terpri stream)
  (format stream "|---|")
  (dolist (context +contexts+)
    (declare (ignore context))
    (write-string "---|" stream))
  (terpri stream)
  (dolist (entry (parsed-truth-table root))
    (format stream "| `<~A>` |" (first entry))
    (dolist (keysym (second entry))
      (format stream " `~A` |" keysym))
    (terpri stream)))

(defun abstract-symbol-name (keysym)
  (let ((lower (string-downcase keysym)))
    (with-output-to-string (stream)
      (cond ((and (<= 6 (length keysym))
                  (string= "Greek_" keysym :end2 6))
             (write-string (if (every #'upper-case-p (subseq keysym 6))
                               "greek-capital-"
                               "greek-small-")
                           stream)
             (setf lower (subseq lower 6)))
            ((not (alpha-char-p (char lower 0)))
             (write-string "symbol-" stream)))
      (loop for character across lower
            do (write-char (if (char= character #\_) #\- character) stream)))))

(defun unicode-keysym-p (keysym)
  (and (> (length keysym) 1)
       (char-equal (char keysym 0) #\U)
       (every (lambda (character) (digit-char-p character 16)) (subseq keysym 1))))

(defun unicode-keysym-string (keysym)
  (string (code-char (parse-integer keysym :start 1 :radix 16))))

(defparameter +named-key-keysyms+
  '(("BackSpace" . "backspace") ("Tab" . "tab")
    ("ISO_Left_Tab" . "iso-left-tab") ("Return" . "return")
    ("Linefeed" . "linefeed")))

(defun fixture-output (keysym)
  (cond ((string= keysym "NoSymbol") "none")
        ((= (length keysym) 1) (format nil "(unicode ~S)" keysym))
        ((unicode-keysym-p keysym)
         (format nil "(unicode ~S)" (unicode-keysym-string keysym)))
        ((assoc keysym +named-key-keysyms+ :test #'string=)
         (format nil "(named-key ~A)"
                 (cdr (assoc keysym +named-key-keysyms+ :test #'string=))))
        (t (format nil "(named-symbol ~A)" (abstract-symbol-name keysym)))))

(defun render-fixture-bindings (root stream)
  "Print only mechanically-derived static binding tables for review/patching."
  (dolist (entry (parsed-truth-table root))
    (let ((position (cdr (assoc (first entry) +xkb-position-names+ :test #'string=))))
      (unless position
        (error "No logical-position spelling for XKB key <~A>." (first entry)))
      (format stream "  (binding ~A~%" position)
      (loop for context in '((plain roman base) (shifted roman base)
                             (plain greek base) (shifted greek base)
                             (plain roman top) (shifted roman top)
                             (plain greek top) (shifted greek top))
            for keysym in (second entry)
            do (format stream "    (at (~{~(~A~)~^ ~}) ~A)~%"
                       context (fixture-output keysym)))
      (format stream "  )~%"))))

(defun usage (stream)
  (format stream "Usage: sbcl --script tools/manna-truth-table.lisp {render|verify|fixture} ROOT~%"))

(defun main (&optional (arguments (uiop:command-line-arguments)))
  (destructuring-bind (command root &rest extra) arguments
    (when (or extra (null root))
      (usage *error-output*)
      (uiop:quit 2))
    (handler-case
        (cond ((string= command "render")
               (render-markdown root *standard-output*))
              ((string= command "fixture")
               (render-fixture-bindings root *standard-output*))
              ((string= command "verify")
               (format t "Manna Cadet frozen baseline verified; truth-table SHA-256: ~A~%"
                       (verify-baseline root)))
              (t (usage *error-output*) (uiop:quit 2)))
      (error (condition)
        (format *error-output* "manna-truth-table: ~A~%" condition)
        (uiop:quit 1)))))

(main)
