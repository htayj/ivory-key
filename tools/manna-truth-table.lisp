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

;; These older files are not part of the selected layered profile or the
;; canonical static-table digest.  They are separately frozen so their
;; regression-only chord evidence remains mechanically reviewable.
(defparameter +chorded-baseline-files+
  '(("kanata/kinesis.advantage2.kanata.kbd" .
     "e4ce45dc6d5f265fbdef1de80e5792e2c7080d2a1c61705efe1b82a05401d4cd")
    ("kanata/kinesis.advantage360.kanata.kbd" .
     "45ca3b2769b6d1686724f81e50401123a80216c888bcd8be7bb8ec19cb984cd7")))

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
  (dolist (file (append +baseline-files+ +chorded-baseline-files+))
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
      ;; Match Ivory Key's canonical formatter.  Keeping the mechanically
      ;; rendered comparison canonical prevents harmless source reflow from
      ;; masquerading as a truth-table difference.
      (format stream "  (binding~%    ~A~%" position)
      (loop for context in '((plain roman base) (shifted roman base)
                             (plain greek base) (shifted greek base)
                             (plain roman top) (shifted roman top)
                             (plain greek top) (shifted greek top))
            for keysym in (second entry)
            do (format stream "    (at (~{~(~A~)~^ ~}) ~A)~%"
                       context (fixture-output keysym)))
      (format stream "  )~%"))))

;;; Frozen-to-fixture comparison --------------------------------------------

;; This comparison is intentionally a closed inventory for the hash-verified
;; frozen source.  It does not READ either Kanata or Ivory Key source: the
;; small token readers below only inspect the finite defsrc/deflayer and
;; reserve-carriers forms needed to compare recorded evidence.

(defparameter +static-kanata-tokens+
  '(("AE01" . "1") ("AE02" . "2") ("AE03" . "3")
    ("AE04" . "4") ("AE05" . "5") ("AE06" . "6")
    ("AE07" . "7") ("AE08" . "8") ("AE09" . "9")
    ("AE10" . "0") ("AE11" . "-") ("AE12" . "=")
    ("BKSP" . "bspc") ("TAB" . "tab")
    ("AD01" . "q") ("AD02" . "w") ("AD03" . "e")
    ("AD04" . "r") ("AD05" . "t") ("AD06" . "y")
    ("AD07" . "u") ("AD08" . "i") ("AD09" . "o")
    ("AD10" . "p") ("AD11" . "[") ("AD12" . "]")
    ("RTRN" . "ent")
    ("AC01" . "a") ("AC02" . "s") ("AC03" . "d")
    ("AC04" . "f") ("AC05" . "g") ("AC06" . "h")
    ("AC07" . "j") ("AC08" . "k") ("AC09" . "l")
    ("AC10" . ";") ("AC11" . "'")
    ("TLDE" . "grv") ("BKSL" . "\\")
    ("AB01" . "z") ("AB02" . "x") ("AB03" . "c")
    ("AB04" . "v") ("AB05" . "b") ("AB06" . "n")
    ("AB07" . "m") ("AB08" . ",") ("AB09" . ".")
    ("AB10" . "/") ("SPCE" . "spc")))

;; Alias, shared logical position, typed Ivory Key output, frozen XKB keysym,
;; and the exact Linux input carrier.  The function layer itself determines
;; the physical source token for each device; the table below deliberately
;; does not hide the Advantage 2 Menu / Advantage 360 Caps distinction.
(defparameter +function-output-rows+
  '(("sc-i" "number-1" "named-symbol" "roman-one" "U2160" 218)
    ("sc-ii" "number-2" "named-symbol" "roman-two" "U2161" 219)
    ("sc-iii" "number-3" "named-symbol" "roman-three" "U2162" 220)
    ("sc-iv" "number-4" "named-symbol" "roman-four" "U2163" 221)
    ("sc-fingerleft" "number-7" "named-symbol" "finger-left" "U261A" 222)
    ("sc-thumbup" "number-8" "named-symbol" "thumb-up" "U1F44D" 223)
    ("sc-thumbdown" "number-9" "named-symbol" "thumb-down" "U1F44E" 224)
    ("sc-fingerright" "number-0" "named-symbol" "finger-right" "U261B" 225)
    ("sc-quote" "q" "command" "quote" "UE002" 185)
    ("sc-terminal" "w" "command" "terminal" "UE001" 184)
    ("sc-macro" "e" "command" "macro" "UE000" 183)
    ("sc-overstrike" "t" "command" "over-strike" "UE003" 186)
    ("sc-status" "u" "command" "status" "UE012" 197)
    ("sc-call" "i" "command" "call" "UE00C" 194)
    ("sc-stopoutput" "o" "command" "stop-output" "UE007" 190)
    ("sc-system" "s" "command" "system" "UE00A" 195)
    ("sc-abort" "g" "command" "abort" "UE008" 191)
    ("sc-help" "h" "command" "help" "UE014" 199)
    ("sc-line" "j" "command" "line" "UE013" 198)
    ("sc-clearinput" "k" "command" "clear-input" "UE004" 187)
    ("sc-clearscreen" "l" "command" "clear-screen" "UE005" 188)
    ("sc-end" "semicolon" "command" "end" "UE00D" 240)
    ("sc-holdoutput" "z" "command" "hold-output" "UE006" 189)
    ("sc-network" "x" "command" "network" "UE00B" 196)
    ("sc-break" "c" "command" "break" "UE009" 192)
    ("sc-resume" "m" "command" "resume" "UE011" 193)
    ("sc-repeat" "period" "command" "repeat" "UE00E" 226)
    ("sc-modelock" "grave" "command" "mode-lock" "UE010" 212)
    ("sc-altmode" "mode-key" "command" "alt-mode" "UE00F" 211)))

;; All selected primary normal-layer tap-holds remain source evidence, not
;; active fixture behavior.  Listing every alias makes this refusal inventory
;; reviewable rather than a vague claim about "home-row mods".
(defparameter +unresolved-primary-tap-holds+
  '(("Sf" "f" "case") ("Sj" "j" "case")
    ("Cd" "d" "control") ("Ck" "k" "control")
    ("Ms" "s" "meta") ("Ml" "l" "meta")
    ("sa" "a" "super") ("s;" ";" "super")
    ("eoam" "esc" "hyper") ("qoam" "'" "hyper")
    ("Hro" "bspc" "alt") ("Hsp" "spc" "alt")
    ("HscL" "end" "function") ("HscR" "pgdn" "function")))

(defparameter +unresolved-selector-tap-holds+
  '(("gdel" "del" "script") ("rtop" "ent" "plane")))

(defparameter +direct-selector-rows+
  '(("case-left-shift" "lshift" "lshift" "LFSH" "Shift_L"
     "hold-case-left-shift" "case" "shifted" "plain")
    ("case-right-shift" "rshift" "rshift" "RTSH" "Shift_R"
     "hold-case-right-shift" "case" "shifted" "plain")
    ("greek" "lctl" "@gr" "ZEHA" "ISO_Level3_Shift"
     "hold-greek-selector" "script" "greek" "roman")
    ("top" "rctl" "@top" "LVL3" "Mode_switch"
     "hold-top-selector" "plane" "top" "base")))

(defparameter +advantage360-game-aliases+
  '("GoGame" "ExitGame" "Gjmp" "Ghop" "Gnp7" "Gctl" "Galt" "Gsup"))

;; The two non-layered source files are not executable migration profiles.
;; These rows preserve only their literal structural facts for P-04 review.
(defparameter +chorded-variant-specifications+
  '(("Advantage 2 chorded" "kanata/kinesis.advantage2.kanata.kbd" 68)
    ("Advantage 360 chorded" "kanata/kinesis.advantage360.kanata.kbd" 72)))

;; Alias, tap-repress timeout, hold timeout, literal tap action, literal hold
;; action.  Unlike the selected layered sources, the old chorded files do not
;; contain the two function-layer aliases and retain 200/200 for osft/csft.
(defparameter +chorded-tap-hold-rows+
  '(("Sf" "200" "200" "f" "lshift")
    ("Cd" "200" "200" "d" "lctl")
    ("Ms" "200" "200" "s" "lalt")
    ("sa" "250" "250" "a" "lmet")
    ("Sj" "200" "200" "j" "lshift")
    ("Ck" "200" "200" "k" "lctl")
    ("Ml" "200" "200" "l" "lalt")
    ("s;" "200" "200" ";" "lmet")
    ("Hro" "200" "200" "bspc" "ralt")
    ("Hsp" "200" "200" "spc" "ralt")
    ("eoam" "200" "200" "esc" "rmet")
    ("qoam" "200" "200" "'" "rmet")
    ("osft" "200" "200" "0" "lshift")
    ("csft" "200" "200" "0" "rshift")
    ("rtop" "200" "200" "ent" "@top")
    ("gdel" "200" "200" "del" "@gr")))

(defparameter +chorded-normal-alias-placement-rows+
  '(("esc" "eoam") ("a" "sa") ("s" "Ms") ("d" "Cd")
    ("f" "Sf") ("j" "Sj") ("k" "Ck") ("l" "Ml")
    (";" "s;") ("'" "qoam") ("lctl" "gr") ("rctl" "top")
    ("bspc" "Hro") ("del" "gdel") ("ent" "rtop") ("spc" "Hsp")))

(defparameter +chorded-normal-non-source-actions+
  '(("Advantage 2 chorded" ("lalt" "lrld"))
    ("Advantage 360 chorded" ("K18" "F18") ("K20" "F20")
     ("K19" "F19") ("K21" "F21") ("lalt" "lrld"))))

(defparameter +chorded-advantage360-local-keys+
  '(("K18" "127") ("K19" "130") ("K20" "115") ("K21" "142")))

;; First participant, second participant, and carrier alias.  Every source row
;; uses the same literal fields: 45, first-release, and ().  This list records
;; no commitment, replay, arbitration, or output semantics.
(defparameter +chorded-combo-rows+
  (list
   '("1" "2" "sc-i")
   '("2" "3" "sc-ii")
   '("3" "4" "sc-iii")
   '("4" "5" "sc-iv")
   '("6" "7" "sc-fingerleft")
   '("7" "8" "sc-thumbup")
   '("8" "9" "sc-thumbdown")
   '("9" "0" "sc-fingerright")
   '("q" "w" "sc-macro")
   '("w" "e" "sc-terminal")
   '("e" "r" "sc-quote")
   '("r" "t" "sc-overstrike")
   '("t" "y" "sc-clearinput")
   '("y" "u" "sc-clearscreen")
   '("u" "i" "sc-holdoutput")
   '("i" "o" "sc-stopoutput")
   '("o" "p" "sc-abort")
   (list "p" (string #\\) "sc-break")
   '("s" "d" "sc-system")
   '("x" "c" "sc-network")
   '("menu" "left" "sc-altmode")
   '("grv" "menu" "sc-modelock")
   '("down" "[" "sc-end")
   '("j" "k" "sc-call")
   '("g" "h" "sc-help")
   '("k" "l" "sc-resume")
   '("m" "," "sc-repeat")
   '("," "." "sc-status")
   '("h" "j" "sc-line")))

(defun tool-directory ()
  (uiop:pathname-directory-pathname
   (or *load-truename*
       (error "Cannot determine the Manna truth-table tool path."))))

(defun ivory-key-root ()
  (merge-pathnames "../" (tool-directory)))

(defun fixture-pathname (relative)
  (merge-pathnames relative (ivory-key-root)))

(defun fixture-text (relative)
  (uiop:read-file-string (fixture-pathname relative)))

(defun string-prefix-p (prefix value)
  (and (<= (length prefix) (length value))
       (string= prefix value :end2 (length prefix))))

(defun count-prefixed-lines (text prefix)
  (count-if (lambda (line) (string-prefix-p prefix line))
            (line-list text)))

(defun compact-source-line (line)
  "Drop a Kanata line comment and formatting without reading source code."
  (let ((end (or (search ";;" line) (length line))))
    (coerce (loop for character across (subseq line 0 end)
                  unless (member character '(#\Space #\Tab #\Return))
                    collect character)
            'string)))

(defun named-parenthesized-form (source marker)
  "Extract the balanced form beginning at exact MARKER, without evaluating it."
  (let ((start (search marker source)))
    (unless start
      (error "Frozen source lacks required form marker ~S." marker))
    (let ((depth 0)
          (in-string nil)
          (escaped nil)
          (in-comment nil))
      (loop for index from start below (length source)
            for character = (char source index)
            for next = (and (< (1+ index) (length source))
                            (char source (1+ index)))
            do (cond
                 (in-comment
                  (when (char= character #\Newline)
                    (setf in-comment nil)))
                 (in-string
                  (cond (escaped (setf escaped nil))
                        ((char= character #\\) (setf escaped t))
                        ((char= character #\") (setf in-string nil))))
                 ((and (char= character #\;) (char= next #\;))
                  (setf in-comment t))
                 ((char= character #\") (setf in-string t))
                 ((char= character #\() (incf depth))
                 ((char= character #\))
                  (decf depth)
                  (when (minusp depth)
                    (error "Malformed parenthesized form beginning ~S." marker))
                  (when (zerop depth)
                    (return (subseq source start (1+ index))))))))))

(defun form-tokens (source)
  "Split a known finite source form into atoms; source is never READ."
  (loop with length = (length source)
        for start = 0 then (1+ end)
        while (< start length)
        for end = (or (position-if
                       (lambda (character)
                         (member character '(#\Space #\Tab #\Newline #\Return #\( #\))))
                       source :start start)
                      length)
        for candidate = (subseq source start end)
        unless (string= candidate "")
          collect candidate))

(defun source-form-tokens (source marker expected-head)
  (let ((tokens (form-tokens (named-parenthesized-form source marker))))
    (unless (and tokens (string= expected-head (first tokens)))
      (error "Malformed frozen form ~S." marker))
    tokens))

(defun source-line-without-comment (line)
  "Return LINE's non-comment text without interpreting Kanata syntax."
  (trim (subseq line 0 (or (search ";;" line) (length line)))))

(defun source-atoms (source)
  "Split a finite, already-selected source fragment without READ or EVAL."
  (labels ((delimiter-p (character)
             (member character '(#\Space #\Tab #\Newline #\Return #\( #\)))))
    (loop with cursor = 0
          for start = (position-if-not #'delimiter-p source :start cursor)
          while start
          for end = (or (position-if #'delimiter-p source :start start)
                        (length source))
          collect (subseq source start end)
          do (setf cursor end))))

(defun active-kanata-text (source)
  "Mask Kanata comments and strings before structural marker inspection.

This is deliberately a small text scanner, not a Kanata evaluator.  It keeps
the code's parentheses and atoms while making commented templates and strings
incapable of contributing a form marker.
"
  (with-output-to-string (stream)
    (loop with length = (length source)
          with index = 0
          with line-comment = nil
          with block-comment-depth = 0
          with in-string = nil
          with escaped = nil
          while (< index length)
          for character = (char source index)
          for next = (and (< (1+ index) length) (char source (1+ index)))
          do (cond
               (line-comment
                (if (char= character #\Newline)
                    (progn
                      (write-char character stream)
                      (setf line-comment nil))
                    (write-char #\Space stream))
                (incf index))
               ((plusp block-comment-depth)
                (cond ((and (char= character #\#) (char= next #\|))
                       (write-string "  " stream)
                       (incf block-comment-depth)
                       (incf index 2))
                      ((and (char= character #\|) (char= next #\#))
                       (write-string "  " stream)
                       (decf block-comment-depth)
                       (incf index 2))
                      (t
                       (write-char (if (char= character #\Newline)
                                       #\Newline
                                       #\Space)
                                   stream)
                       (incf index))))
               (in-string
                (cond (escaped (setf escaped nil))
                      ((char= character #\\) (setf escaped t))
                      ((char= character #\") (setf in-string nil)))
                (write-char (if (char= character #\Newline) #\Newline #\Space)
                            stream)
                (incf index))
               ((and (char= character #\;) (char= next #\;))
                (write-string "  " stream)
                (setf line-comment t)
                (incf index 2))
               ((and (char= character #\#) (char= next #\|))
                (write-string "  " stream)
                (setf block-comment-depth 1)
                (incf index 2))
               ((char= character #\")
                (write-char #\Space stream)
                (setf in-string t)
                (incf index))
               (t
                (write-char character stream)
                (incf index))))))

(defun active-form-marker-count (source marker)
  (loop with active = (active-kanata-text source)
        with start = 0
        for match = (search marker active :start2 start)
        while match
        count t
        do (setf start (+ match (length marker)))))

(defun active-deflayer-names (source)
  "Return every active deflayer name in textual source order."
  (let ((active (active-kanata-text source))
        (names nil)
        (start 0)
        (marker "(deflayer"))
    (loop for match = (search marker active :start2 start)
          while match
          do (let ((atoms (source-atoms (subseq active match))))
               (unless (and (>= (length atoms) 2)
                            (string= "deflayer" (first atoms)))
                 (error "Malformed active deflayer marker in frozen source."))
               (push (second atoms) names)
               (setf start (+ match (length marker)))))
    (nreverse names)))

(defun sorted-row-keys (rows)
  (sort (mapcar (lambda (row) (format nil "~{~A~^|~}" row)) rows) #'string<))

(defun chorded-expected-alias-rows ()
  (append
   (mapcar (lambda (row)
             (list (first row) "tap-hold-release"
                   (second row) (third row) (fourth row) (fifth row)))
           +chorded-tap-hold-rows+)
   '(("gr" "arbitrary-code" "85") ("top" "arbitrary-code" "84"))
   (mapcar (lambda (row)
             (list (first row) "arbitrary-code" (write-to-string (sixth row))))
           +function-output-rows+)))

(defun chorded-alias-rows (source relative)
  "Parse the closed, one-line old defalias block without evaluating it."
  (let ((rows nil)
        (form (named-parenthesized-form (active-kanata-text source) "(defalias")))
    (dolist (line (line-list form))
      (let ((atoms (source-atoms (source-line-without-comment line))))
        (cond ((null atoms))
              ((string= "defalias" (first atoms)))
              ((and (= (length atoms) 6)
                    (string= "tap-hold-release" (second atoms)))
               (push atoms rows))
              ((and (= (length atoms) 3)
                    (string= "arbitrary-code" (second atoms)))
               (push atoms rows))
              (t
               (error "Frozen source ~A has an unsupported chorded alias row ~S."
                      relative line)))))
    (nreverse rows)))

(defun check-chorded-alias-inventory (source relative)
  "Require exact old alias spellings while retaining them as evidence only."
  (let* ((rows (chorded-alias-rows source relative))
         (names (mapcar #'first rows))
         (expected (chorded-expected-alias-rows)))
    (unless (= (length names) (length (remove-duplicates names :test #'string=)))
      (error "Frozen source ~A declares duplicate chorded aliases." relative))
    (unless (equal (sorted-row-keys rows) (sorted-row-keys expected))
      (error "Frozen source ~A has a stale or unclassified chorded alias inventory."
             relative))
    rows))

(defun chorded-combo-row (line relative)
  "Parse one old defchordsv2 row as fixed structural evidence."
  (let ((trimmed (source-line-without-comment line)))
    (unless (and (plusp (length trimmed)) (char= #\( (char trimmed 0)))
      (error "Frozen source ~A has a malformed chord row ~S." relative line))
    (let ((close (position #\) trimmed)))
      (unless close
        (error "Frozen source ~A has an unterminated chord pair ~S." relative line))
      (let* ((participants (source-atoms (subseq trimmed 1 close)))
             (tail (trim (subseq trimmed (1+ close))))
             (tail-atoms (source-atoms tail)))
        (unless (and (= (length participants) 2)
                     (= (length tail-atoms) 3)
                     (string-prefix-p "@" (first tail-atoms))
                     (string= "45" (second tail-atoms))
                     (string= "first-release" (third tail-atoms))
                     (string= (compact-source-line tail)
                              (format nil "~A45first-release()" (first tail-atoms))))
          (error "Frozen source ~A has a non-canonical chord row ~S."
                 relative line))
        (list (first participants) (second participants)
              (subseq (first tail-atoms) 1))))))

(defun chorded-combo-rows (source relative)
  "Return all active fixed-format old chord rows in source order."
  (let ((rows nil)
        (form (named-parenthesized-form (active-kanata-text source)
                                        "(defchordsv2")))
    (dolist (line (line-list form))
      (let ((trimmed (source-line-without-comment line)))
        (unless (or (string= trimmed "")
                    (string-prefix-p "(defchordsv2" trimmed)
                    (string= trimmed ")"))
          (push (chorded-combo-row line relative) rows))))
    (nreverse rows)))

(defun chord-pair-key (row)
  (format nil "~{~A~^|~}" (sort (list (first row) (second row)) #'string<)))

(defun check-chorded-combo-inventory (source relative)
  "Require every old pair/output/field row without selecting its semantics."
  (let ((rows (chorded-combo-rows source relative)))
    (unless (equal rows +chorded-combo-rows+)
      (error "Frozen source ~A has a stale or unclassified chord inventory."
             relative))
    (unless (= (length rows)
               (length (remove-duplicates (mapcar #'chord-pair-key rows)
                                           :test #'string=)))
      (error "Frozen source ~A declares duplicate unordered chord pairs." relative))
    (unless (equal (sorted-strings (mapcar #'third rows))
                   (sorted-strings (mapcar #'first +function-output-rows+)))
      (error "Frozen source ~A does not map every old chord to one function carrier alias."
             relative))
    rows))

(defun primary-alias-names (source relative)
  "Return every active one-line defalias name without evaluating Kanata text.

The frozen primary files keep each active alias definition on one source line.
Comments are removed before inspection, so the historical commented Tr/Tu
examples cannot become active evidence by accident.  A non-empty unrecognized
line is rejected rather than silently omitted from the coverage inventory.
"
  (let ((names nil)
        (form (named-parenthesized-form source "(defalias")))
    (dolist (line (line-list form))
      (let ((compact (compact-source-line line)))
        (cond ((or (string= compact "")
                   (string-prefix-p "(defalias" compact)
                   (string= compact ")")))
              (t
               (let ((separator (position #\( compact)))
                 (unless (and separator (plusp separator))
                   (error "Frozen source ~A has an unclassified defalias line ~A."
                          relative line))
                 (let ((name (subseq compact 0 separator)))
                   (when (member name names :test #'string=)
                     (error "Frozen source ~A declares duplicate alias ~A."
                            relative name))
                   (push name names)))))))
    (nreverse names)))

(defun sorted-strings (strings)
  (sort (copy-list strings) #'string<))

(defun primary-alias-classification-rows ()
  "The closed disposition of every active alias in the frozen primary files."
  (append
   (mapcar (lambda (row) (list (first row) "timing-refusal"))
           +unresolved-primary-tap-holds+)
   (mapcar (lambda (row) (list (first row) "timing-refusal"))
           +unresolved-selector-tap-holds+)
   (mapcar (lambda (row) (list (first row) "direct-selector"))
           '(("gr") ("top")))
   (mapcar (lambda (row) (list (first row) "function-output"))
           +function-output-rows+)
   '(("osft" "inactive-alias") ("csft" "inactive-alias"))
   (mapcar (lambda (name) (list name "advantage360-game"))
           +advantage360-game-aliases+)))

(defun alias-classification-rows-for-device (device)
  (let ((rows (primary-alias-classification-rows)))
    (if (string= device "Advantage 2")
        (remove "advantage360-game" rows :key #'second :test #'string=)
        rows)))

(defun check-primary-alias-classification (source device relative)
  "Verify that every declared alias has exactly one explicit disposition."
  (let* ((declared (primary-alias-names source relative))
         (rows (alias-classification-rows-for-device device))
         (classified (mapcar #'first rows)))
    (unless (= (length classified)
               (length (remove-duplicates classified :test #'string=)))
      (error "Manna alias classification contains a duplicate identity for ~A."
             device))
    (unless (equal (sorted-strings declared) (sorted-strings classified))
      (error "Manna alias classification for ~A is incomplete or has stale aliases: declared ~S, classified ~S."
             device (sorted-strings declared) (sorted-strings classified)))
    rows))

(defun primary-layer-inventory (source device relative)
  "Return checked primary layer names and their complete defsrc arities.

This is deliberately structural evidence only.  It establishes that every
active layer has a finite physical-source table, while semantic interpretation
continues to be controlled by the individual classified rows.
"
  (let ((layers (if (string= device "Advantage 2")
                    '("normal" "fun")
                    '("normal" "game" "fun")))
        (source-count (length (source-defsrc-tokens source)))
        (expected-source-count (if (string= device "Advantage 2") 68 72)))
    (unless (= source-count expected-source-count)
      (error "Frozen source ~A has ~D rather than ~D defsrc positions."
             relative source-count expected-source-count))
    (mapcar (lambda (name)
              (let ((actions (source-layer-action-map source name relative)))
                (unless (= source-count (length actions))
                  (error "Frozen source ~A layer ~A does not cover defsrc."
                         relative name))
                (list name (length actions))))
            layers)))

(defun source-defsrc-tokens (source)
  (rest (source-form-tokens source "(defsrc" "defsrc")))

(defun source-layer-tokens (source name)
  (let ((tokens (source-form-tokens source
                                    (format nil "(deflayer ~A" name)
                                    "deflayer")))
    (unless (and (second tokens) (string= name (second tokens)))
      (error "Malformed frozen deflayer ~A." name))
    (cddr tokens)))

(defun source-layer-action-map (source name relative)
  (let ((defsrc (source-defsrc-tokens source))
        (layer (source-layer-tokens source name)))
    (unless (= (length defsrc) (length layer))
      (error "Frozen source ~A has defsrc/~A arity ~D/~D."
             relative name (length defsrc) (length layer)))
    (mapcar #'cons defsrc layer)))

(defun chorded-expected-non-source-actions (device)
  (cdr (assoc device +chorded-normal-non-source-actions+ :test #'string=)))

(defun chorded-normal-layer-inventory (source device relative alias-rows)
  "Classify every old normal-layer action structurally, never semantically."
  (let* ((map (source-layer-action-map source "normal" relative))
         (defsrc (mapcar #'car map))
         (aliases (mapcar #'first alias-rows))
         (alias-placements nil)
         (non-source-actions nil)
         (direct-count 0))
    (dolist (entry map)
      (let ((physical (car entry))
            (action (cdr entry)))
        (cond ((string-prefix-p "@" action)
               (let ((alias (subseq action 1)))
                 (unless (member alias aliases :test #'string=)
                   (error "Frozen source ~A selects unknown normal-layer alias ~A."
                          relative action))
                 (push (list physical alias) alias-placements)))
              ((member action defsrc :test #'string=)
               (incf direct-count))
              (t
               (push (list physical action) non-source-actions)))))
    (setf alias-placements (nreverse alias-placements)
          non-source-actions (nreverse non-source-actions))
    (unless (equal alias-placements +chorded-normal-alias-placement-rows+)
      (error "Frozen source ~A has a stale or unclassified normal alias placement."
             relative))
    (unless (equal non-source-actions (chorded-expected-non-source-actions device))
      (error "Frozen source ~A has a stale or unclassified non-defsrc normal action."
             relative))
    (unless (= direct-count 51)
      (error "Frozen source ~A has ~D direct defsrc-preserving normal actions, expected 51."
             relative direct-count))
    (list alias-placements non-source-actions direct-count)))

(defun active-chorded-local-key-rows (source relative)
  "Return active deflocalkeys-linux rows as raw name/code pairs."
  (let ((active (active-kanata-text source)))
    (if (search "(deflocalkeys-linux" active)
        (let ((tokens (source-form-tokens active "(deflocalkeys-linux"
                                          "deflocalkeys-linux")))
          (unless (evenp (length (rest tokens)))
            (error "Frozen source ~A has malformed deflocalkeys-linux pairs."
                   relative))
          (loop for (name code) on (rest tokens) by #'cddr
                collect (list name code)))
        nil)))

(defun check-chorded-local-keys (source device relative)
  (let ((rows (active-chorded-local-key-rows source relative))
        (expected (if (string= device "Advantage 360 chorded")
                      +chorded-advantage360-local-keys+
                      nil)))
    (unless (equal rows expected)
      (error "Frozen source ~A has a stale or unclassified local-key inventory."
             relative))
    rows))

(defun chorded-combo-membership (rows defsrc)
  "Return the exact count and source tokens absent from an old combo's defsrc."
  (let ((present-count 0)
        (missing nil))
    (dolist (row rows)
      (dolist (participant (subseq row 0 2))
        (if (member participant defsrc :test #'string=)
            (incf present-count)
            (push participant missing))))
    (list present-count (nreverse missing))))

(defun expected-chorded-combo-missing-tokens (device)
  (if (string= device "Advantage 360 chorded")
      '("menu" "menu")
      nil))

(defun chorded-variant-inventory (root specification)
  "Verify one hash-pinned regression-only source file without lowering it."
  (destructuring-bind (device relative expected-defsrc-count) specification
    (let* ((source (uiop:read-file-string (pathname-at root relative)))
           (defsrc (source-defsrc-tokens source))
           (aliases (check-chorded-alias-inventory source relative))
           (combos (check-chorded-combo-inventory source relative))
           (normal (chorded-normal-layer-inventory source device relative aliases))
           (local-keys (check-chorded-local-keys source device relative))
           (membership (chorded-combo-membership combos defsrc)))
      (unless (= (length defsrc) expected-defsrc-count)
        (error "Frozen source ~A has ~D defsrc positions, expected ~D."
               relative (length defsrc) expected-defsrc-count))
      (unless (equal (active-deflayer-names source) '("normal"))
        (error "Frozen source ~A has an unclassified active deflayer set ~S."
               relative (active-deflayer-names source)))
      (dolist (marker '("(defsrc" "(defalias" "(defchordsv2" "(defcfg"))
        (unless (= 1 (active-form-marker-count source marker))
          (error "Frozen source ~A has an unexpected active count for ~A."
                 relative marker)))
      (unless (= (if (string= device "Advantage 360 chorded") 1 0)
                 (active-form-marker-count source "(deflocalkeys-linux"))
        (error "Frozen source ~A has an unexpected active deflocalkeys-linux count."
               relative))
      (unless (equal (second membership)
                     (expected-chorded-combo-missing-tokens device))
        (error "Frozen source ~A has unclassified old chord participants outside defsrc: ~S."
               relative (second membership)))
      (list device relative defsrc aliases normal combos local-keys membership))))

(defun checked-chorded-variant-inventories (root)
  "Return both complete regression-only structural inventories.

The source rows may be compared and reported, but this function intentionally
does not create a layout interaction, select a profile, or interpret Kanata's
runtime behavior.
"
  (let ((inventories
          (mapcar (lambda (specification)
                    (chorded-variant-inventory root specification))
                  +chorded-variant-specifications+)))
    (destructuring-bind (a2 a360) inventories
      (unless (equal (fourth a2) (fourth a360))
        (error "Frozen chorded variants disagree on their closed alias inventory."))
      (unless (equal (sixth a2) (sixth a360))
        (error "Frozen chorded variants disagree on their closed chord inventory.")))
    inventories))

(defun mapped-action (map token relative layer)
  (or (cdr (assoc token map :test #'string=))
      (error "Frozen source ~A lacks ~A source token ~A."
             relative layer token)))

(defun exact-source-line-p (source expected)
  (some (lambda (line)
          (search (compact-source-line expected) (compact-source-line line)))
        (line-list source)))

(defun source-arbitrary-code-p (source alias carrier)
  (exact-source-line-p source
                       (format nil "~A (arbitrary-code ~D)" alias carrier)))

(defun static-placement-rows ()
  (loop for (xkb . logical) in +xkb-position-names+
        for token = (cdr (assoc xkb +static-kanata-tokens+ :test #'string=))
        when token
          collect (list logical xkb token)))

(defun logical-position-for-kanata-token (token)
  (or (loop for (logical ignored-xkb source-token) in (static-placement-rows)
            when (string= token source-token)
              return logical)
      (cond ((member token '("menu" "caps") :test #'string=) "mode-key")
            (t nil))))

(defun function-layer-entries (source relative)
  "Return physical-token/alias pairs, refusing an unclassified function cell."
  (let ((map (source-layer-action-map source "fun" relative))
        (entries nil))
    (dolist (entry map (nreverse entries))
      (let ((physical (car entry))
            (action (cdr entry)))
        (cond ((string= action "_"))
              ((string-prefix-p "@sc-" action)
               (push (list physical (subseq action 1)) entries))
              (t
               (error "Frozen source ~A has unclassified function action ~A at ~A."
                      relative action physical)))))))

(defun function-entry (entries alias relative)
  (let ((matches (remove-if-not (lambda (entry)
                                  (string= alias (second entry)))
                                entries)))
    (unless (= (length matches) 1)
      (error "Frozen source ~A has ~D function entries for @~A."
             relative (length matches) alias))
    (first matches)))

(defun xkb-function-carrier-p (xkb-source carrier keysym)
  (exact-source-line-p
   xkb-source
   (format nil "key <I~D> { type=\"ONE_LEVEL\", [ ~A ] };"
           (+ carrier 8) keysym)))

(defun fixture-placement-p (device logical xkb kanata)
  (search (format nil "(place ~A (:xkb ~S) (:kanata ~S))"
                  logical xkb kanata)
          device))

(defun fixture-reserves-carrier-p (device carrier)
  (let ((tokens (source-form-tokens device "(reserve-carriers" "reserve-carriers")))
    (member (write-to-string carrier) (rest tokens) :test #'string=)))

(defun checked-static-fixture-p (root layout topology advantage2 advantage360)
  (let ((fixture (with-output-to-string (stream)
                   (render-fixture-bindings root stream))))
    (unless (search fixture layout)
      (error "Manna fixture's 52 static tables differ from the frozen mechanical render.")))
  (unless (= 52 (count-prefixed-lines layout "  (binding"))
    (error "Manna fixture must contain exactly 52 static bindings."))
  (unless (= 57 (count-prefixed-lines topology "  (position "))
    (error "Manna topology must contain exactly 52 static and 5 control positions."))
  (dolist (row (static-placement-rows))
    (destructuring-bind (logical xkb kanata) row
      (unless (and (search (format nil "(position ~A" logical) topology)
                   (fixture-placement-p advantage2 logical xkb kanata)
                   (fixture-placement-p advantage360 logical xkb kanata))
        (error "Manna static placement ~A is not exact on both devices." logical))))
  ;; <LSGT> is a static XKB table only.  Its deliberate physical absence is a
  ;; typed device fact, not an inferred device placement.
  (unless (and (search "(position less-greater)" topology)
               (not (search "(place less-greater" advantage2))
               (not (search "(place less-greater" advantage360))
               (search "(unreachable less-greater)" advantage2)
               (search "(unreachable less-greater)" advantage360))
    (error "<LSGT> must remain explicitly unreachable without an invented placement."))
  (unless (and (= 56 (count-prefixed-lines advantage2 "  (place "))
               (= 56 (count-prefixed-lines advantage360 "  (place ")))
    (error "Each Manna device fixture must contain exactly 56 classified placements."))
  t)

(defun checked-function-fixture-p (root layout advantage2 advantage360 vocabulary)
  (unless (and (search "(axis function (:states inactive active) (:resolution patch))" layout)
               (search (format nil "(overlay~%    primary-function") layout)
               (= 29 (count-prefixed-lines layout "    (binding ")))
    (error "Manna fixture lost the complete 29-entry primary function table."))
  (let ((a2-source (uiop:read-file-string
                    (pathname-at root
                                 "kanata/kinesis.advantage2.layered.kanata.kbd")))
        (a360-source (uiop:read-file-string
                      (pathname-at root
                                   "kanata/kinesis.advantage360.layered.kanata.kbd")))
        (xkb-source (uiop:read-file-string
                     (pathname-at root "xkb/symbols/spacecadet"))))
    (dolist (device-data `(("Advantage 2" ,a2-source
                            "kanata/kinesis.advantage2.layered.kanata.kbd")
                           ("Advantage 360" ,a360-source
                            "kanata/kinesis.advantage360.layered.kanata.kbd")))
      (destructuring-bind (device-name source relative) device-data
        (let ((entries (function-layer-entries source relative)))
          (unless (= 29 (length entries))
            (error "Frozen ~A function layer has ~D rather than 29 outputs."
                   device-name (length entries)))
          (dolist (row +function-output-rows+)
            (destructuring-bind (alias logical kind identity keysym carrier) row
              (let* ((entry (function-entry entries alias relative))
                     (actual-logical
                       (logical-position-for-kanata-token (first entry))))
                (unless (and actual-logical (string= logical actual-logical))
                  (error "Frozen ~A function alias @~A is at ~A, not logical ~A."
                         device-name alias (first entry) logical))
                (unless (source-arbitrary-code-p source alias carrier)
                  (error "Frozen ~A lost exact @~A arbitrary carrier ~D."
                         device-name alias carrier))
                (unless (xkb-function-carrier-p xkb-source carrier keysym)
                  (error "Frozen XKB lost carrier ~D → ~A." carrier keysym))
                (unless (search (format nil "(binding ~A (~A ~A))"
                                        logical kind identity)
                                layout)
                  (error "Manna function patch lost ~A output ~A."
                         logical identity))
                (unless (search (format nil
                                        "(map-output ~A ~A (:xkb ~S) (:kanata ~S))"
                                        kind identity keysym
                                        (format nil "(arbitrary-code ~D)" carrier))
                                vocabulary)
                  (error "Manna vocabulary lost exact @~A mapping." alias))))))))
    ;; Static source-derived vocabulary entries precede the function rows, so
    ;; count the carrier action itself rather than every map-output form.
    (unless (= 29 (loop with start = 0
                         for found = (search "(:kanata \"(arbitrary-code "
                                             vocabulary :start2 start)
                         while found
                         count t
                         do (setf start (+ found 1))))
      (error "Manna vocabulary must contain exactly 29 carrier-backed outputs."))
    (dolist (row +function-output-rows+)
      (let ((carrier (sixth row)))
        (unless (and (fixture-reserves-carrier-p advantage2 carrier)
                     (fixture-reserves-carrier-p advantage360 carrier))
          (error "Manna devices must reserve frozen function carrier ~D." carrier))))
  t))

(defun checked-direct-selector-fixture-p (root layout topology advantage2 advantage360)
  (let ((xkb-source (uiop:read-file-string
                     (pathname-at root "xkb/symbols/spacecadet"))))
    (dolist (device-data
             `((,advantage2 "kanata/kinesis.advantage2.layered.kanata.kbd")
               (,advantage360 "kanata/kinesis.advantage360.layered.kanata.kbd")))
      (destructuring-bind (device relative) device-data
        (let* ((source (uiop:read-file-string (pathname-at root relative)))
               (normal (source-layer-action-map source "normal" relative)))
          (dolist (row +direct-selector-rows+)
            (destructuring-bind (logical physical action xkb keysym interaction
                                 axis active base)
                row
              (declare (ignore keysym))
              (unless (string= action (mapped-action normal physical relative "normal"))
                (error "Frozen source ~A changed direct selector ~A." relative logical))
              (unless (and (search (format nil "(position ~A" logical) topology)
                           (fixture-placement-p device logical xkb physical)
                           (search (format nil "(interaction~%    ~A" interaction) layout)
                           (search (format nil "(hold-axis-state ~A ~A)" axis active)
                                   layout)
                           (search (format nil "(set-axis-state ~A ~A)" axis base)
                                   layout))
                (error "Manna fixture lost direct selector transcription ~A." logical)))))))
    (unless (and (exact-source-line-p xkb-source
                                      "key <LFSH> { type=\"ONE_LEVEL\", [ Shift_L ] };")
                 (exact-source-line-p xkb-source
                                      "key <RTSH> { type=\"ONE_LEVEL\", [ Shift_R ] };")
                 (exact-source-line-p xkb-source
                                      "replace key <LVL3> { type=\"ONE_LEVEL\", [ Mode_switch ] };")
                 (exact-source-line-p xkb-source
                                      "override key <ZEHA> { type[Group1]=\"ONE_LEVEL\", symbols[Group1]=[ ISO_Level3_Shift ] };"))
      (error "Frozen XKB direct selector definitions changed.")))
  (unless (= 4 (count-prefixed-lines layout "  (interaction"))
    (error "Manna fixture must contain exactly four direct held interactions."))
  t)

(defun no-active-unresolved-behavior-p (layout)
  (when (or (search (format nil "(interaction~%    tap-hold-") layout)
            (search (format nil "(interaction~%    latch-latch") layout)
            (search "(:participants i o)" layout)
            (search (format nil "(interaction~%    game") layout))
    (error "A refused Manna timing/chord/game behavior was made active."))
  t)

(defun static-nosymbol-count (root)
  (loop for entry in (parsed-truth-table root)
        sum (count "NoSymbol" (second entry) :test #'string=)))

(defun report-function-physical (source relative alias)
  (first (function-entry (function-layer-entries source relative) alias relative)))

(defun chorded-row-source-member-count (row defsrc)
  (count-if (lambda (participant) (member participant defsrc :test #'string=))
            (subseq row 0 2)))

(defun chorded-pair-summary (row)
  (format nil "`~A` + `~A`" (first row) (second row)))

(defun chorded-local-key-summary (rows)
  (if rows
      (format nil "~{`~A=~A`~^, ~}"
              (loop for (name code) in rows append (list name code)))
      "none"))

(defun chorded-non-source-action-summary (rows)
  (if rows
      (format nil "~{`~A` → `~A`~^, ~}"
              (loop for (physical action) in rows append (list physical action)))
      "none"))

(defun render-chorded-structural-inventory (inventories stream)
  "Render the two old source files as closed regression-only evidence."
  (destructuring-bind (a2 a360) inventories
    (destructuring-bind (a2-device a2-relative a2-defsrc a2-aliases a2-normal
                         a2-combos a2-local-keys a2-membership) a2
      (declare (ignore a2-relative))
      (destructuring-bind (a360-device a360-relative a360-defsrc a360-aliases
                           a360-normal a360-combos a360-local-keys a360-membership) a360
        (declare (ignore a360-relative a360-aliases))
        (format stream "## Older chorded Kanata structural inventory (regression-only)~%~%")
        (format stream "Both hash-pinned source files are inventoried as text only.  No row below selects a chord profile, timing policy, output semantics, or lowering path.  `first-release` and `()` are literal source fields, not Ivory Key behavior.~%~%")
        (format stream "| Variant | SHA-256 | `defsrc` | Active layers | Aliases | Chords | Chord participant source-membership | Local keys |~%")
        (format stream "|---|---|---:|---|---:|---:|---|---|~%")
        (dolist (inventory inventories)
          (destructuring-bind (device relative defsrc aliases normal combos local-keys membership)
              inventory
            (declare (ignore normal))
            (let ((missing (second membership)))
              (format stream "| ~A | `~A` | ~D | `normal` (complete) | ~D (16 tap-hold / 31 carrier) | ~D | ~D / 58~@[; missing `~{~A~^`, `~}`~] | ~A |~%"
                      device
                      (cdr (assoc relative +chorded-baseline-files+ :test #'string=))
                      (length defsrc) (length aliases) (length combos)
                      (first membership) missing
                      (chorded-local-key-summary local-keys)))))
        (format stream "~%")
        (format stream "The two `menu` occurrences in the Advantage 360 chord rows are not members of that file's `defsrc`, which instead has `caps`.  This is a closed source-token mismatch only; this report does not infer Kanata acceptance, reachability, or an equivalent `caps` rewrite.~%~%")
        (format stream "### Normal-layer structural placement~%~%")
        (format stream "| Physical `defsrc` token | Literal normal action | Source files | Classification |~%")
        (format stream "|---|---|---|---|~%")
        (dolist (row (first a2-normal))
          (format stream "| `~A` | `@~A` | A2 + 360 chorded | regression-only alias reference |~%"
                  (first row) (second row)))
        (format stream "~%")
        (format stream "| Variant | Non-identical normal action | Structural classification |~%")
        (format stream "|---|---|---|~%")
        (dolist (inventory inventories)
          (destructuring-bind (device ignored-relative ignored-defsrc ignored-aliases normal
                               ignored-combos ignored-local ignored-membership) inventory
            (declare (ignore ignored-relative ignored-defsrc ignored-aliases
                             ignored-combos ignored-local ignored-membership))
            (format stream "| ~A | ~A | literal action is not an identical `defsrc` token; no abstract meaning inferred |~%"
                    device (chorded-non-source-action-summary (second normal)))))
        (format stream "~%")
        (format stream "### Old alias and carrier rows~%~%")
        (format stream "| Alias | Source form | Literal fields | Structural reference | Classification |~%")
        (format stream "|---|---|---|---|---|~%")
        (dolist (row a2-aliases)
          (let* ((alias (first row))
                 (normal-reference (find alias (first a2-normal) :key #'second
                                         :test #'string=))
                 (combo-reference (find alias a2-combos :key #'third :test #'string=)))
            (format stream "| `@~A` | `~A` | ~A | ~A | regression-only |~%"
                    alias (second row)
                    (if (string= "tap-hold-release" (second row))
                        (format nil "`~A` / `~A` ms; tap `~A`; hold `~A`"
                                (third row) (fourth row) (fifth row) (sixth row))
                        (format nil "carrier `~A`" (third row)))
                    (cond (normal-reference "normal layer")
                          (combo-reference "one chord row")
                          (t "not selected by normal/chord rows")))))
        (format stream "~%")
        (format stream "### Old chord rows~%~%")
        (format stream "| Row kind | Participants | Carrier alias | Literal fields | A2 `defsrc` members | 360 `defsrc` members | Classification |~%")
        (format stream "|---|---|---|---|---:|---:|---|~%")
        (loop for row in a2-combos
              for a360-row in a360-combos
              do (format stream "| chord | ~A | `@~A` | `45`, `first-release`, `()` | ~D / 2 | ~D / 2 | regression-only |~%"
                         (chorded-pair-summary row) (third row)
                         (chorded-row-source-member-count row a2-defsrc)
                         (chorded-row-source-member-count a360-row a360-defsrc)))
        (format stream "~%")))))

(defun render-diff-report (root stream)
  "Render the complete frozen static/function/direct-selector comparison.

Every record is either exact, explicitly unreachable/device-specific, or an
explicit refusal.  An unexpected input causes an error before this report can
claim zero unchecked differences.
"
  (verify-baseline root)
  (let* ((layout (fixture-text "layouts/manna-cadet.ivory"))
         (topology (fixture-text "topologies/kinesis-advantage.ivory"))
         (advantage2 (fixture-text "devices/kinesis-advantage2.ivory"))
         (advantage360 (fixture-text "devices/kinesis-advantage360.ivory"))
         (vocabulary (fixture-text "realizations/manna-cadet-output-vocabulary.ivory"))
         (a2-relative "kanata/kinesis.advantage2.layered.kanata.kbd")
         (a360-relative "kanata/kinesis.advantage360.layered.kanata.kbd")
         (a2-source (uiop:read-file-string (pathname-at root a2-relative)))
         (a360-source (uiop:read-file-string (pathname-at root a360-relative)))
         (a2-aliases (check-primary-alias-classification
                      a2-source "Advantage 2" a2-relative))
         (a360-aliases (check-primary-alias-classification
                        a360-source "Advantage 360" a360-relative))
         (a2-layers (primary-layer-inventory a2-source "Advantage 2" a2-relative))
         (a360-layers (primary-layer-inventory
                       a360-source "Advantage 360" a360-relative))
         (chorded-inventories (checked-chorded-variant-inventories root)))
    (checked-static-fixture-p root layout topology advantage2 advantage360)
    (checked-function-fixture-p root layout advantage2 advantage360 vocabulary)
    (checked-direct-selector-fixture-p root layout topology advantage2 advantage360)
    (no-active-unresolved-behavior-p layout)
    (format stream "# Manna Cadet frozen baseline diff report~%~%")
    (format stream "Commit: `~A`~%" +baseline-commit+)
    (format stream "Scope: the hash-verified static XKB tables, primary function table, direct selectors, and regression-only structural chord inventory for the frozen Kanata files.  This is a source/fixture classification, not a backend or live-input equivalence claim.~%~%")
    (format stream "## Completeness~%~%")
    (format stream "| Inventory | Baseline records | Exact fixture records | Explicit refusals / variants | Unchecked |~%")
    (format stream "|---|---:|---:|---:|---:|~%")
    (format stream "| Static tables | 52 tables / 416 cells / ~D `NoSymbol` cells | 52 | 1 explicitly unreachable input | 0 |~%"
            (static-nosymbol-count root))
    (format stream "| Function outputs | 29 A2 + 29 360 placements | 29 shared outputs | 2 activators | 0 |~%")
    (format stream "| Direct selectors | 4 A2 + 4 360 observations | 4 abstract held interactions | backend lowering refused | 0 |~%")
    (format stream "| Timed / device variants | 14 primary aliases + 2 selector aliases + 8 game aliases | 0 active | all classified below | 0 |~%")
    (format stream "| Older chorded sources | 47 aliases + 29 chords per device | 0 active | regression-only structural inventory | 0 |~%~%")
    (format stream "| Primary aliases | ~D A2 + ~D 360 declarations | ~D + ~D classified | no implicit alias meaning | 0 |~%~%"
            (length a2-aliases) (length a360-aliases)
            (length a2-aliases) (length a360-aliases))
    (format stream "## Primary alias and layer coverage~%~%")
    (format stream "| Primary file | defsrc positions | Layers (each complete) | Declared aliases | Unclassified aliases |~%")
    (format stream "|---|---:|---|---:|---:|~%")
    (flet ((layer-summary (layers)
             (format nil "~{`~A` (~D)~^, ~}"
                     (loop for (name count) in layers
                           append (list name count)))))
      (format stream "| Advantage 2 | 68 | ~A | ~D | 0 |~%"
              (layer-summary a2-layers) (length a2-aliases))
      (format stream "| Advantage 360 | 72 | ~A | ~D | 0 |~%~%"
              (layer-summary a360-layers) (length a360-aliases)))
    (format stream "| Alias scope | Alias | Closed source/fixture disposition |~%")
    (format stream "|---|---|---|~%")
    (dolist (row a2-aliases)
      (format stream "| A2 / 360 | `@~A` | `~A` |~%" (first row) (second row)))
    (dolist (row a360-aliases)
      (when (string= "advantage360-game" (second row))
        (format stream "| 360 only | `@~A` | `~A` |~%" (first row) (second row))))
    (format stream "~%")
    (render-chorded-structural-inventory chorded-inventories stream)
    (format stream "## Static XKB tables and physical disposition~%~%")
    (format stream "| XKB key | Logical position | Cells | A2 / 360 disposition | Classification |~%")
    (format stream "|---|---|---:|---|---|~%")
    (dolist (entry (parsed-truth-table root))
      (let* ((xkb (first entry))
             (logical (cdr (assoc xkb +xkb-position-names+ :test #'string=)))
             (token (cdr (assoc xkb +static-kanata-tokens+ :test #'string=))))
        (format stream "| `<~A>` | `~A` | 8 | ~A | ~A |~%"
                xkb logical
                (if token
                    (format nil "`~A` / `~A`" token token)
                    "no direct `defsrc` token / no direct `defsrc` token")
                (if token "static-table-and-placement-exact"
                    "static-table-exact; typed-unreachable"))))
    (format stream "~%## Primary function output table~%~%")
    (format stream "| Alias | Logical position | XKB | Carrier | A2 source | 360 source | Classification |~%")
    (format stream "|---|---|---|---:|---|---|---|~%")
    (dolist (row +function-output-rows+)
      (destructuring-bind (alias logical kind identity keysym carrier) row
        (declare (ignore kind identity))
        (format stream "| `@~A` | `~A` | `~A` | ~D | `~A` | `~A` | output-and-carrier-exact; activation-refused |~%"
                alias logical keysym carrier
                (report-function-physical a2-source a2-relative alias)
                (report-function-physical a360-source a360-relative alias))))
    (format stream "~%## Direct selectors and physical case holders~%~%")
    (format stream "| Logical position | Frozen A2/360 normal action | XKB result | Fixture interaction | Classification |~%")
    (format stream "|---|---|---|---|---|~%")
    (dolist (row +direct-selector-rows+)
      (destructuring-bind (logical physical action xkb keysym interaction
                           axis active base)
          row
        (declare (ignore axis active base))
        (format stream "| `~A` | `~A` → `~A` | `<~A>` → `~A` | `~A` | semantic-transcription-exact; backend-lowering-refused |~%"
                logical physical action xkb keysym interaction)))
    (format stream "~%## Explicitly classified differences and refusals~%~%")
    (format stream "| Evidence item | Device scope | Fixture disposition | Why it remains non-equivalent |~%")
    (format stream "|---|---|---|---|~%")
    (format stream "| `<LSGT>` physical placement | A2 and 360 | `typed-unreachable` | Static table is exact, but neither primary `defsrc` has a direct token; both device records refuse a placement. |~%")
    (format stream "| `mode-key` inactive result | A2 / 360 | `device-specific-inactive-output` | Frozen source is `menu` / `caps`; only the common active `alt-mode` output is transcribed. |~%")
    (format stream "| `kanata-1-12-buffered` compatibility profile | 14 primary + 2 selector aliases | `proposed-profile-unencoded` | The hash-pinned Kanata-1.12 oracle records delayed foreign-event ordering, and the model has a bounded single-owner pending-input transaction. Native queue closure, realization-owned allocation/lowering, whole-pipeline proof, and a selected `.ivory` profile remain absent. |~%")
    (dolist (row +unresolved-primary-tap-holds+)
      (destructuring-bind (alias position family) row
        (format stream "| `@~A` at `~A` (~A) | A2 and 360 | `tap-hold-policy-refused` | Timeout, interruption, commitment, owner release, and lowerer semantics are not selected. |~%"
                alias position family)))
    (dolist (row +unresolved-selector-tap-holds+)
      (destructuring-bind (alias position axis) row
        (format stream "| `@~A` at `~A` (~A) | A2 and 360 | `tap-hold-policy-refused` | This alternate selector path is not the direct physical selector interaction. |~%"
                alias position axis)))
    (format stream "| `@osft`, `@csft` | A2 and 360 | `inactive-alias-excluded` | Declared aliases are not selected by either primary normal layer. |~%")
    (dolist (alias +advantage360-game-aliases+)
      (format stream "| `@~A` / `game` | Advantage 360 only | `device-variant-refused` | The 360-only game layer is not a common Manna layout fact or selected composition behavior. |~%"
              alias))
    (format stream "| Group-2 / selector visibility | Linux profile | `selector-lowering-refused` | The selected generated-XKB/libxkbcommon state contract is proven; frozen Kanata carrier delivery, Kanata action/lifetime lowering, the combined pipeline, and client/compositor/live-device behavior remain unproved. |~%")
    (format stream "~%Unchecked differences: 0~%")
    t))

(defun usage (stream)
  (format stream "Usage: sbcl --script tools/manna-truth-table.lisp {render|verify|fixture|diff} ROOT~%"))

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
              ((string= command "diff")
               (render-diff-report root *standard-output*))
              ((string= command "verify")
               (format t "Manna Cadet frozen baseline verified; truth-table SHA-256: ~A~%"
                       (verify-baseline root)))
              (t (usage *error-output*) (uiop:quit 2)))
      (error (condition)
        (format *error-output* "manna-truth-table: ~A~%" condition)
        (uiop:quit 1)))))

(main)
