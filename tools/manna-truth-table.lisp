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
  ;; classified unresolved difference, not an inferred device placement.
  (unless (and (search "(position less-greater)" topology)
               (not (search "(place less-greater" advantage2))
               (not (search "(place less-greater" advantage360)))
    (error "<LSGT> must remain an explicit unplaced static-table position."))
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

(defun render-diff-report (root stream)
  "Render the complete frozen static/function/direct-selector comparison.

Every record is either exact, deliberately unplaced/device-specific, or an
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
         (a360-source (uiop:read-file-string (pathname-at root a360-relative))))
    (checked-static-fixture-p root layout topology advantage2 advantage360)
    (checked-function-fixture-p root layout advantage2 advantage360 vocabulary)
    (checked-direct-selector-fixture-p root layout topology advantage2 advantage360)
    (no-active-unresolved-behavior-p layout)
    (format stream "# Manna Cadet frozen baseline diff report~%~%")
    (format stream "Commit: `~A`~%" +baseline-commit+)
    (format stream "Scope: the hash-verified static XKB tables, primary function table, and direct selectors for both frozen primary Kanata files.  This is a source/fixture classification, not a backend or live-input equivalence claim.~%~%")
    (format stream "## Completeness~%~%")
    (format stream "| Inventory | Baseline records | Exact fixture records | Explicit refusals / variants | Unchecked |~%")
    (format stream "|---|---:|---:|---:|---:|~%")
    (format stream "| Static tables | 52 tables / 416 cells / ~D `NoSymbol` cells | 52 | 1 unplaced physical table | 0 |~%"
            (static-nosymbol-count root))
    (format stream "| Function outputs | 29 A2 + 29 360 placements | 29 shared outputs | 2 activators | 0 |~%")
    (format stream "| Direct selectors | 4 A2 + 4 360 observations | 4 abstract held interactions | backend lowering refused | 0 |~%")
    (format stream "| Timed / device variants | 14 primary aliases + 2 selector aliases + 8 game aliases | 0 active | all classified below | 0 |~%~%")
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
                    "static-table-exact; physical-placement-refused"))))
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
    (format stream "| `<LSGT>` physical placement | A2 and 360 | `physical-placement-refused` | Static table is exact, but neither primary `defsrc` has a direct token; no placement is invented. |~%")
    (format stream "| `mode-key` inactive result | A2 / 360 | `device-specific-inactive-output` | Frozen source is `menu` / `caps`; only the common active `alt-mode` output is transcribed. |~%")
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
    (format stream "| Group-2 / selector visibility | Linux profile | `selector-lowering-refused` | XKB group/client visibility and exact Kanata/XKB selector lowering remain unproved. |~%")
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
