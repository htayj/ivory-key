;;;; Frozen Manna Cadet baseline regression check.
;;;; SPDX-License-Identifier: GPL-3.0-or-later
;;;;
;;;; This is intentionally a separately invoked integration test: it requires
;;;; the read-only Manna Cadet checkout rather than making the normal Ivory Key
;;;; test system depend on a machine-local path.
;;;;
;;;; Run:
;;;;   sbcl --script tests/migration/manna-truth-table.lisp \
;;;;     /home/tay/src/dotfiles/keyboard/manna-cadet

(require :asdf)

(defun test-directory ()
  (uiop:pathname-directory-pathname
   (or *load-truename*
       (error "Cannot determine the migration-test path."))))

(defun repository-root ()
  (merge-pathnames "../../" (test-directory)))

(defun truth-table-tool ()
  (merge-pathnames "tools/manna-truth-table.lisp" (repository-root)))

(defun repository-file (relative)
  (merge-pathnames relative (repository-root)))

(defun tool-output (command root)
  (uiop:run-program (list "sbcl" "--script" (namestring (truth-table-tool)) command root)
                    :output :string :error-output :output))

(defun required-root (arguments)
  (or (first arguments)
      (error "Supply the frozen Manna Cadet checkout root as the only argument.")))

(defun line-list (text)
  (let ((lines nil)
        (start 0))
    (loop
      (let ((end (position #\Newline text :start start)))
        (push (subseq text start end) lines)
        (unless end
          (return (nreverse lines)))
        (setf start (1+ end))))))

(defun count-prefixed-lines (text prefix)
  (count-if (lambda (line)
              (and (<= (length prefix) (length line))
                   (string= prefix line :end2 (length prefix))))
            (line-list text)))

(defun count-substrings (text needle)
  (loop with start = 0
        for match = (search needle text :start2 start)
        while match
        count t
        do (setf start (+ match (length needle)))))

(defparameter +frozen-function-carriers+
  '(("named-symbol" "roman-one" "U2160" 218)
    ("named-symbol" "roman-two" "U2161" 219)
    ("named-symbol" "roman-three" "U2162" 220)
    ("named-symbol" "roman-four" "U2163" 221)
    ("named-symbol" "finger-left" "U261A" 222)
    ("named-symbol" "thumb-up" "U1F44D" 223)
    ("named-symbol" "thumb-down" "U1F44E" 224)
    ("named-symbol" "finger-right" "U261B" 225)
    ("command" "macro" "UE000" 183)
    ("command" "terminal" "UE001" 184)
    ("command" "quote" "UE002" 185)
    ("command" "over-strike" "UE003" 186)
    ("command" "clear-input" "UE004" 187)
    ("command" "clear-screen" "UE005" 188)
    ("command" "hold-output" "UE006" 189)
    ("command" "stop-output" "UE007" 190)
    ("command" "abort" "UE008" 191)
    ("command" "break" "UE009" 192)
    ("command" "resume" "UE011" 193)
    ("command" "call" "UE00C" 194)
    ("command" "system" "UE00A" 195)
    ("command" "network" "UE00B" 196)
    ("command" "status" "UE012" 197)
    ("command" "line" "UE013" 198)
    ("command" "help" "UE014" 199)
    ("command" "alt-mode" "UE00F" 211)
    ("command" "mode-lock" "UE010" 212)
    ("command" "repeat" "UE00E" 226)
    ("command" "end" "UE00D" 240)))

;; Each row records a semantic family, the alias selected by both primary
;; normal layers, its physical/tap source token, its literal hold action, then
;; Kanata's tap-repress and hold timeouts.  These are source facts only: this
;; migration test must not turn them into an Ivory Key lifecycle policy.
(defparameter +frozen-primary-tap-hold-rows+
  '(("case" "Sf" "f" "lshift" 200 200)
    ("case" "Sj" "j" "lshift" 200 200)
    ("control" "Cd" "d" "lctl" 200 200)
    ("control" "Ck" "k" "lctl" 200 200)
    ("meta" "Ms" "s" "lalt" 200 200)
    ("meta" "Ml" "l" "lalt" 200 200)
    ("super" "sa" "a" "lmet" 250 250)
    ("super" "s;" ";" "lmet" 200 200)
    ("hyper" "eoam" "esc" "rmet" 200 200)
    ("hyper" "qoam" "'" "rmet" 200 200)
    ("alt" "Hro" "bspc" "ralt" 200 200)
    ("alt" "Hsp" "spc" "ralt" 200 200)
    ("function" "HscL" "end" "(layer-while-held fun)" 200 200)
    ("function" "HscR" "pgdn" "(layer-while-held fun)" 200 200)))

(defparameter +frozen-primary-direct-case-holders+ '("lshift" "rshift"))
(defparameter +frozen-primary-tap-hold-policy+
  '("process-unmapped-keysyes" "concurrent-tap-holdyes"))

(defparameter +frozen-primary-kanata-files+
  '("kanata/kinesis.advantage2.layered.kanata.kbd"
    "kanata/kinesis.advantage360.layered.kanata.kbd"))

(defparameter +frozen-direct-case-xkb-rows+
  '(("LFSH" "Shift_L") ("RTSH" "Shift_R")))
(defparameter +frozen-direct-case-xkb-file+ "xkb/symbols/spacecadet")

(defun compact-source-line (line)
  "Remove comments and horizontal source formatting without reading code."
  (let ((end (or (search ";;" line) (length line))))
    (coerce (loop for character across (subseq line 0 end)
                  unless (member character '(#\Space #\Tab #\Return))
                    collect character)
            'string)))

(defun primary-normal-layer (source relative)
  "Return the finite primary normal-layer source slice, or signal clearly."
  (let ((start (search "(deflayer normal" source)))
    (unless start
      (error "Frozen primary source ~A has no normal layer." relative))
    (subseq source start
            (or (search "(deflayer" source
                        :start2 (+ start (length "(deflayer normal")))
                (length source)))))

(defun primary-defsrc (source relative)
  "Return the finite physical-source declaration, or signal clearly."
  (let* ((start (search "(defsrc" source))
         (end (and start (position #\) source :start start))))
    (unless (and start end (< start end))
      (error "Frozen primary source ~A has no finite defsrc declaration."
             relative))
    (subseq source start (1+ end))))

(defun physical-source-token-p (token defsrc)
  "Recognize TOKEN as one exact whitespace/parenthesis-delimited defsrc key."
  (loop with length = (length defsrc)
        for start = 0 then (1+ end)
        while (< start length)
        for end = (or (position-if
                       (lambda (character)
                         (member character
                                 '(#\Space #\Tab #\Newline #\Return #\( #\))))
                       defsrc :start start)
                      length)
        for candidate = (subseq defsrc start end)
        thereis (string= token candidate)))

(defun form-tokens (source)
  "Split one finite comment-free source form without reading it as Lisp."
  (loop with length = (length source)
        for start = 0 then (1+ end)
        while (< start length)
        for end = (or (position-if
                       (lambda (character)
                         (member character
                                 '(#\Space #\Tab #\Newline #\Return #\( #\))))
                       source :start start)
                      length)
        for candidate = (subseq source start end)
        unless (string= candidate "")
          collect candidate))

(defun normal-action-at-physical-source (position defsrc normal-layer relative)
  "Return the normal-layer action at POSITION's exact defsrc index."
  (let* ((physical-order (rest (form-tokens defsrc)))
         (normal-order (cddr (form-tokens normal-layer)))
         (index (position position physical-order :test #'string=)))
    (unless index
      (error "Frozen primary source ~A lost physical source ~A."
             relative position))
    (unless (= (length physical-order) (length normal-order))
      (error "Frozen primary source ~A changed defsrc/normal arity (~D/~D)."
             relative (length physical-order) (length normal-order)))
    (nth index normal-order)))

(defun frozen-primary-tap-hold-evidence-p (root)
  "Check raw primary source facts without executing or lowering them."
  (dolist (relative +frozen-primary-kanata-files+ t)
    (let* ((source (uiop:read-file-string
                    (merge-pathnames relative (uiop:ensure-directory-pathname root))))
           (lines (line-list source))
           (compact-lines (mapcar #'compact-source-line lines))
           (normal-layer (primary-normal-layer source relative))
           (defsrc (primary-defsrc source relative)))
      (dolist (policy +frozen-primary-tap-hold-policy+)
        (unless (some (lambda (line) (search policy line)) compact-lines)
          (error "Frozen primary source ~A lost policy ~A." relative policy)))
      (dolist (row +frozen-primary-tap-hold-rows+)
        (destructuring-bind (family alias position hold tap-repress hold-time) row
          (let ((definition
                  (compact-source-line
                   (format nil "~A(tap-hold-release~D~D~A~A)"
                           alias tap-repress hold-time position hold))))
            (unless (some (lambda (line) (search definition line)) compact-lines)
              (error "Frozen primary source ~A lost ~A tap-hold alias ~A."
                     relative family alias))
            (unless (physical-source-token-p position defsrc)
              (error "Frozen primary source ~A lost physical source ~A for ~A."
                     relative position alias))
            (unless (string= (format nil "@~A" alias)
                             (normal-action-at-physical-source
                              position defsrc normal-layer relative))
              (error "Frozen primary source ~A no longer maps ~A to @~A in normal."
                     relative position alias)))))
      (dolist (position +frozen-primary-direct-case-holders+)
        (unless (and (physical-source-token-p position defsrc)
                     (string= position
                              (normal-action-at-physical-source
                               position defsrc normal-layer relative)))
          (error "Frozen primary source ~A lost direct case holder ~A."
                 relative position))))))

(defun frozen-direct-case-xkb-evidence-p (root)
  "Check the two direct physical Shift mappings without parsing XKB."
  (let* ((relative +frozen-direct-case-xkb-file+)
         (source (uiop:read-file-string
                  (merge-pathnames relative (uiop:ensure-directory-pathname root))))
         (compact-lines (mapcar #'compact-source-line (line-list source))))
    (dolist (row +frozen-direct-case-xkb-rows+ t)
      (destructuring-bind (key keysym) row
        (let ((definition
                (compact-source-line
                 (format nil "key <~A> { type=\"ONE_LEVEL\", [ ~A ] };"
                         key keysym))))
          (unless (some (lambda (line) (search definition line)) compact-lines)
            (error "Frozen XKB source ~A lost direct Shift mapping ~A → ~A."
                   relative key keysym)))))
    (unless (some (lambda (line)
                    (search "modifier_mapShift{<LFSH>,<RTSH>};" line))
                  compact-lines)
      (error "Frozen XKB source ~A lost both direct Shift modifier members."
             relative))))

(defun checked-in-fixture-evidence-p (derived-static-bindings)
  "Verify only mechanically checkable claims made by the migration fixture.

The checked-in fixture covers direct single-key held lifecycles.  The raw
primary source aliases below preserve tap-hold parameters and usage without
claiming an Ivory Key activation policy or lifecycle equivalence.  The source
checkout supplied to MAIN is hash-verified before these checked-in counts and
raw rows are considered evidence."
  (let ((layout (uiop:read-file-string (repository-file "layouts/manna-cadet.ivory")))
        (topology (uiop:read-file-string
                   (repository-file "topologies/kinesis-advantage.ivory")))
        (advantage2 (uiop:read-file-string
                     (repository-file "devices/kinesis-advantage2.ivory")))
        (advantage360 (uiop:read-file-string
                       (repository-file "devices/kinesis-advantage360.ivory")))
        (realizations (uiop:read-file-string
                       (repository-file "realizations/manna-cadet-linux.ivory")))
        (vocabulary (uiop:read-file-string
                     (repository-file
                      "realizations/manna-cadet-output-vocabulary.ivory"))))
    (unless (= 52 (count-prefixed-lines layout "  (binding"))
      (error "Manna fixture no longer has exactly 52 static bindings."))
    (unless (= 29 (count-prefixed-lines layout "    (binding "))
      (error "Manna fixture no longer has the complete 29-entry primary function table."))
    (unless (search derived-static-bindings layout)
      (error "Manna fixture's 52x8 static tables differ from the frozen mechanical render."))
    (unless (and (search "(axis function (:states inactive active) (:resolution patch))" layout)
                 (search (format nil "(overlay~%    primary-function") layout)
                 (search "(binding mode-key (command alt-mode))" layout))
      (error "Manna fixture lost the evidence-backed primary function patch."))
    (unless (and (search (format nil "(interaction~%    hold-case-left-shift") layout)
                 (search "(:participants case-left-shift)" layout)
                 (search (format nil "(interaction~%    hold-case-right-shift") layout)
                 (search "(:participants case-right-shift)" layout)
                 (search "(hold-axis-state case shifted)" layout)
                 (search "(set-axis-state case plain)" layout)
                 (search (format nil "(interaction~%    hold-greek-selector") layout)
                 (search "(:participants greek)" layout)
                 (search "(hold-axis-state script greek)" layout)
                 (search "(set-axis-state script roman)" layout)
                 (search (format nil "(interaction~%    hold-top-selector") layout)
                 (search "(:participants top)" layout)
                 (search "(hold-axis-state plane top)" layout)
                 (search "(set-axis-state plane base)" layout))
      (error "Manna fixture lost an evidence-backed immediate held lifecycle."))
    (when (or (search "latch-latch" layout)
              (search "(:participants i o)" layout)
              (/= 4 (count-substrings layout "(interaction")))
      (error "A comment-only latch or old chord was reintroduced as active Manna behavior."))
    (when (some (lambda (escape)
                  (search escape layout :test #'char-equal))
                '("UE00" "arbitrary-code" "@sc-" "(keysym"))
      (error "Manna abstract layout contains a backend carrier or spelling escape hatch."))
    (unless (and (search "(position case-left-shift" topology)
                 (search "(position case-right-shift" topology)
                 (search "(position greek" topology)
                 (search "(position top" topology)
                 (search "(position mode-key)" topology)
                 (search "(place case-left-shift (:xkb \"LFSH\") (:kanata \"lshift\"))" advantage2)
                 (search "(place case-right-shift (:xkb \"RTSH\") (:kanata \"rshift\"))" advantage2)
                 (search "(place case-left-shift (:xkb \"LFSH\") (:kanata \"lshift\"))" advantage360)
                 (search "(place case-right-shift (:xkb \"RTSH\") (:kanata \"rshift\"))" advantage360)
                 (search "(place greek (:xkb \"ZEHA\") (:kanata \"lctl\"))" advantage2)
                 (search "(place greek (:xkb \"ZEHA\") (:kanata \"lctl\"))" advantage360)
                 (search "(place top (:xkb \"LVL3\") (:kanata \"rctl\"))" advantage2)
                 (search "(place top (:xkb \"LVL3\") (:kanata \"rctl\"))" advantage360)
                 (search "(place mode-key (:xkb \"MENU\") (:kanata \"menu\"))" advantage2)
                 (search "(place mode-key (:xkb \"CAPS\") (:kanata \"caps\"))" advantage360)
                 (search "manna-cadet-advantage360-linux" realizations))
      (error "Manna device-variant placement or Advantage 360 composition is missing."))
    (unless (= 29 (count-substrings vocabulary "(:kanata \"(arbitrary-code "))
      (error "Manna vocabulary no longer has exactly 29 carrier-backed outputs."))
    (dolist (row +frozen-function-carriers+)
      (destructuring-bind (kind identity keysym carrier) row
        (let ((mapping
                (format nil
                        "(map-output ~A ~A (:xkb ~S) (:kanata ~S))"
                        kind identity keysym
                        (format nil "(arbitrary-code ~D)" carrier)))
              (behavior (format nil "(~A ~A)" kind identity)))
          (unless (search mapping vocabulary)
            (error "Manna vocabulary lost frozen carrier mapping ~A." mapping))
          (unless (search behavior layout)
            (error "Manna function patch lost frozen behavior ~A." behavior)))))
    t))

(defun main (&optional (arguments (uiop:command-line-arguments)))
  (unless (= (length arguments) 1)
    (error "Usage: sbcl --script tests/migration/manna-truth-table.lisp ROOT"))
  (let* ((root (required-root arguments))
         (verification (tool-output "verify" root))
         (first-render (tool-output "render" root))
         (second-render (tool-output "render" root))
         (fixture-render (tool-output "fixture" root))
         (first-diff (tool-output "diff" root))
         (second-diff (tool-output "diff" root)))
    (unless (search "Manna Cadet frozen baseline verified" verification)
      (error "Frozen baseline verification did not report success: ~A" verification))
    (unless (search "3ef72eabdd26d2154481c1b8fd0becba50dfbb9a0ba50d0d37556930f92dc807"
                    verification)
      (error "Verification did not report the expected truth-table digest: ~A" verification))
    (frozen-primary-tap-hold-evidence-p root)
    (frozen-direct-case-xkb-evidence-p root)
    (unless (string= first-render second-render)
      (error "Truth-table rendering is not deterministic."))
    (unless (and (search "| `<AE01>` | `1` | `exclam` |" first-render)
                 (search "| `<LSGT>` | `less` | `greater` |" first-render))
      (error "Rendered table lost required frozen evidence."))
    (unless (string= first-diff second-diff)
      (error "Frozen Manna baseline diff report is not deterministic."))
    (unless (and (search "52 tables / 416 cells / 158 `NoSymbol` cells" first-diff)
                 (= 51 (count-substrings first-diff "static-table-and-placement-exact"))
                 (= 1 (count-substrings first-diff "static-table-exact; physical-placement-refused"))
                 (= 29 (count-prefixed-lines first-diff "| `@sc-"))
                 (= 16 (count-substrings first-diff "tap-hold-policy-refused"))
                 (= 8 (count-substrings first-diff "device-variant-refused"))
                 (search "| Primary aliases | 49 A2 + 57 360 declarations | 49 + 57 classified | no implicit alias meaning | 0 |" first-diff)
                 (search "| Advantage 2 | 68 | `normal` (68), `fun` (68) | 49 | 0 |" first-diff)
                 (search "| Advantage 360 | 72 | `normal` (72), `game` (72), `fun` (72) | 57 | 0 |" first-diff)
                 (= 49 (count-prefixed-lines first-diff "| A2 / 360 | `@"))
                 (= 8 (count-prefixed-lines first-diff "| 360 only | `@"))
                 (search "| `<LSGT>` physical placement | A2 and 360 | `physical-placement-refused` |" first-diff)
                 (search "| `mode-key` inactive result | A2 / 360 | `device-specific-inactive-output` |" first-diff)
                 (search "| `case-left-shift` | `lshift` → `lshift` |" first-diff)
                 (search "| `greek` | `lctl` → `@gr` |" first-diff)
                 (search "| `top` | `rctl` → `@top` |" first-diff)
                 (search "Unchecked differences: 0" first-diff))
      (error "Generated Manna diff report no longer classifies every frozen difference."))
    (checked-in-fixture-evidence-p fixture-render)
    (format t "Manna Cadet frozen truth-table migration test passed.~%")
    t))

(main)
