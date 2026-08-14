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

;; The two alternate selector aliases are not part of the selected direct
;; selector interactions.  Keep their source rows separate from the fourteen
;; primary modifier/function aliases so a proposed compatibility profile cannot
;; silently omit them or treat the direct holders as tap-holds.
(defparameter +frozen-primary-selector-tap-hold-rows+
  '(("script" "gdel" "del" "@gr" 200 200)
    ("plane" "rtop" "ent" "@top" 200 200)))

(defparameter +frozen-primary-direct-case-holders+ '("lshift" "rshift"))
(defparameter +frozen-primary-tap-hold-policy+
  '("process-unmapped-keysyes" "concurrent-tap-holdyes"))

(defun abstract-modern-release-trigger-inventory ()
  "Load the one test-owned abstract inventory without copying a third table.

The migration script remains separately tagged because its frozen source root
is machine-local.  The abstract fixture itself belongs to the normal ASDF test
system, so this bridge compares the frozen rows to the exact source fixture
rather than retyping a second target-neutral inventory here.
"
  (asdf:load-asd (repository-file "ivory-key.asd"))
  (asdf:load-system "ivory-key/tests")
  (let* ((package (or (find-package :ivory-key.tests)
                      (error "The Ivory Key test package did not load.")))
         (symbol (find-symbol "+MANNA-RELEASE-TRIGGER-V1-INVENTORY+" package)))
    (unless (and symbol (boundp symbol))
      (error "The abstract modern release-trigger inventory is unavailable."))
    (symbol-value symbol)))

(defun frozen-primary-logical-position (token)
  "Translate only the frozen source tokens used by the 14+2 evidence rows."
  (or (cdr (assoc token
                  '((";" . "semicolon")
                    ("esc" . "escape")
                    ("'" . "apostrophe")
                    ("bspc" . "backspace")
                    ("spc" . "space")
                    ("del" . "delete")
                    ("ent" . "enter"))
                  :test #'string=))
      token))

(defun frozen-primary-target-neutral-tap (position)
  "Derive the fixture tap name from its normalized frozen logical position."
  (if (string= position "pgdn") "page-down" position))

(defun frozen-primary-hold-semantics (hold)
  "Translate the frozen raw holder spelling to the closed abstract semantics."
  (or (cdr (assoc hold
                  '(("lshift" . (:axis "case" "shifted"))
                    ("lctl" . (:modifier "control"))
                    ("lalt" . (:modifier "meta"))
                    ("lmet" . (:modifier "super"))
                    ("rmet" . (:modifier "hyper"))
                    ("ralt" . (:modifier "alt"))
                    ("(layer-while-held fun)" . (:axis "function" "active"))
                    ("@gr" . (:axis "script" "greek"))
                    ("@top" . (:axis "plane" "top")))
                  :test #'string=))
      (error "Frozen 14+2 holder ~S has no closed abstract semantic mapping." hold)))

(defun frozen-primary-to-abstract-release-trigger-evidence-p ()
  "Prove the frozen 14+2 aliases/timeouts are the abstract fixture inventory.

Only the test fixture owns target-neutral positions/taps.  This bridge checks
the shared source facts--alias identity, equal timing pair, and semantic hold
family--without turning the migration script into another behavior table.
"
  (let ((frozen (append +frozen-primary-tap-hold-rows+
                        +frozen-primary-selector-tap-hold-rows+))
        (abstract (abstract-modern-release-trigger-inventory)))
    (unless (= (length frozen) (length abstract) 16)
      (error "Frozen and abstract release-trigger inventories must both be 14+2."))
    (loop for frozen-row in frozen
          for abstract-row in abstract do
            (destructuring-bind (family alias position hold tap-repress hold-time)
                frozen-row
              (destructuring-bind (instance abstract-alias abstract-position tap timeout kind
                                   identity &optional state)
                  abstract-row
                (declare (ignore instance))
                (let* ((logical-position (frozen-primary-logical-position position))
                       (expected-tap (frozen-primary-target-neutral-tap logical-position))
                       (semantics (frozen-primary-hold-semantics hold)))
                (unless (string= alias abstract-alias)
                  (error "Abstract release-trigger fixture alias ~A does not match frozen ~A."
                         abstract-alias alias))
                (unless (string= logical-position abstract-position)
                  (error "Abstract release-trigger fixture position ~A does not match frozen ~A."
                         abstract-position logical-position))
                (unless (string= expected-tap tap)
                  (error "Abstract release-trigger fixture tap ~A does not match frozen ~A."
                         tap expected-tap))
                (unless (and (= tap-repress hold-time) (= timeout tap-repress))
                  (error "Abstract release-trigger fixture timing for @~A is not frozen ~D/~D."
                         alias tap-repress hold-time))
                (unless (string= family identity)
                  (error "Abstract release-trigger fixture identity ~A does not match frozen family ~A."
                         identity family))
                (unless (and (eq kind (first semantics))
                             (string= identity (second semantics))
                             (equal state (third semantics)))
                  (error "Abstract release-trigger fixture hold for @~A does not match frozen ~A."
                         alias hold))))))
    t))

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
  (unless (= 16 (+ (length +frozen-primary-tap-hold-rows+)
                    (length +frozen-primary-selector-tap-hold-rows+)))
    (error "The Kanata-1.12 candidate inventory must remain exactly 14+2 aliases."))
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
      (dolist (row +frozen-primary-selector-tap-hold-rows+)
        (destructuring-bind (axis alias position hold tap-repress hold-time) row
          (let ((definition
                  (compact-source-line
                   (format nil "~A(tap-hold-release~D~D~A~A)"
                           alias tap-repress hold-time position hold))))
            (unless (some (lambda (line) (search definition line)) compact-lines)
              (error "Frozen primary source ~A lost ~A selector tap-hold alias ~A."
                     relative axis alias))
            (unless (physical-source-token-p position defsrc)
              (error "Frozen primary source ~A lost physical source ~A for @~A."
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

The checked-in fixture covers direct single-key held lifecycles and structurally
transcribes the selected source aliases without choosing an activation policy
or lifecycle equivalence.  The source checkout supplied to MAIN is hash-
verified before these checked-in counts and raw rows are considered evidence."
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
    (unless (= 56 (count-prefixed-lines layout "  (binding"))
      (error "Manna fixture no longer has 52 static plus four direct bindings."))
    (unless (= 29 (count-prefixed-lines layout "    (binding "))
      (error "Manna fixture no longer has the complete 29-entry primary function table."))
    (unless (search derived-static-bindings layout)
      (error "Manna fixture's 52x8 static tables differ from the frozen mechanical render."))
    (dolist (binding '("(binding escape (named-key escape))"
                       "(binding delete (named-key delete))"
                       "(binding end (command end))"
                       "(binding pgdn (named-key page-down))"))
      (unless (search binding layout)
        (error "Manna fixture lost direct frozen normal binding ~A." binding)))
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
              (/= 20 (count-substrings layout "(interaction")))
      (error "Manna fixture must have four direct and sixteen unselected source interactions."))
    (dolist (name '("tap-hold-case-f" "tap-hold-case-j"
                    "tap-hold-control-d" "tap-hold-control-k"
                    "tap-hold-meta-s" "tap-hold-meta-l"
                    "tap-hold-super-a" "tap-hold-super-semicolon"
                    "tap-hold-hyper-escape" "tap-hold-hyper-apostrophe"
                    "tap-hold-alt-backspace" "tap-hold-alt-space"
                    "tap-hold-function-end" "tap-hold-function-pgdn"
                    "tap-hold-script-delete" "tap-hold-plane-enter"))
      (unless (search (format nil "(interaction~%    ~A" name) layout)
        (error "Manna fixture lost source interaction ~A." name)))
    (when (some (lambda (escape)
                  (search escape layout :test #'char-equal))
                '("UE00" "arbitrary-code" "@sc-" "(keysym"))
      (error "Manna abstract layout contains a backend carrier or spelling escape hatch."))
    (unless (and (search "(position escape" topology)
                 (search "(position delete" topology)
                 (search "(position end" topology)
                 (search "(position pgdn" topology)
                 (not (search "(position enter" topology))
                 (search "(position case-left-shift" topology)
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
                 (search "(place escape (:xkb \"ESC\") (:kanata \"esc\"))" advantage2)
                 (search "(place delete (:xkb \"DELE\") (:kanata \"del\"))" advantage2)
                 (search "(place end (:xkb \"END\") (:kanata \"end\"))" advantage2)
                 (search "(place pgdn (:xkb \"PGDN\") (:kanata \"pgdn\"))" advantage2)
                 (search "(place escape (:xkb \"ESC\") (:kanata \"esc\"))" advantage360)
                 (search "(place delete (:xkb \"DELE\") (:kanata \"del\"))" advantage360)
                 (search "(place end (:xkb \"END\") (:kanata \"end\"))" advantage360)
                 (search "(place pgdn (:xkb \"PGDN\") (:kanata \"pgdn\"))" advantage360)
                 (search "(map-output named-key delete (:xkb \"Delete\") (:kanata \"del\"))" vocabulary)
                 (search "(map-output named-key escape (:xkb \"Escape\") (:kanata \"esc\"))" vocabulary)
                 (search "(map-output named-key page-down (:xkb \"Next\") (:kanata \"pgdn\"))" vocabulary)
                 (not (search "(map-output named-key end" vocabulary))
                 (search "manna-cadet-advantage360-linux" realizations))
      (error "Manna device-variant placement or Advantage 360 composition is missing."))
    (when (or (search "(interaction-compatibility" realizations)
              (search "(kanata-buffered-allocations" realizations))
      (error "Manna source transcription must not select timing policy or allocation."))
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
    (frozen-primary-to-abstract-release-trigger-evidence-p)
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
                 (= 1 (count-substrings first-diff "static-table-exact; typed-unreachable"))
                 ;; The primary function table and the regression-only chord
                 ;; inventory each render all 29 exact @sc carrier aliases.
                 (= 58 (count-prefixed-lines first-diff "| `@sc-"))
                 (= 16 (count-substrings first-diff "tap-hold-policy-refused"))
                 (= 8 (count-substrings first-diff "device-variant-refused"))
                 (search "| Timed / device variants | 14 primary aliases + 2 selector aliases + 8 game aliases | 16 source structures, no selected policy | all classified below | 0 |" first-diff)
                 (search "| Older chorded sources | 47 aliases + 29 chords per device | 0 active | regression-only structural inventory | 0 |" first-diff)
                 (search "| Advantage 2 chorded | `e4ce45dc6d5f265fbdef1de80e5792e2c7080d2a1c61705efe1b82a05401d4cd` | 68 | `normal` (complete) | 47 (16 tap-hold / 31 carrier) | 29 | 58 / 58 | none |" first-diff)
                 (search "| Advantage 360 chorded | `45ca3b2769b6d1686724f81e50401123a80216c888bcd8be7bb8ec19cb984cd7` | 72 | `normal` (complete) | 47 (16 tap-hold / 31 carrier) | 29 | 56 / 58; missing `menu`, `menu` | `K18=127`, `K19=130`, `K20=115`, `K21=142` |" first-diff)
                 (search "| `@osft` | `tap-hold-release` | `200` / `200` ms; tap `0`; hold `lshift` | not selected by normal/chord rows | regression-only |" first-diff)
                 (search "| chord | `i` + `o` | `@sc-stopoutput` | `45`, `first-release`, `()` | 2 / 2 | 2 / 2 | regression-only |" first-diff)
                 (search "| chord | `menu` + `left` | `@sc-altmode` | `45`, `first-release`, `()` | 2 / 2 | 1 / 2 | regression-only |" first-diff)
                 (= 29 (count-prefixed-lines first-diff "| chord |"))
                 (search "| Primary aliases | 49 A2 + 57 360 declarations | 49 + 57 classified | no implicit alias meaning | 0 |" first-diff)
                 (search "| Advantage 2 | 68 | `normal` (68), `fun` (68) | 49 | 0 |" first-diff)
                 (search "| Advantage 360 | 72 | `normal` (72), `game` (72), `fun` (72) | 57 | 0 |" first-diff)
                 (= 49 (count-prefixed-lines first-diff "| A2 / 360 | `@"))
                 (= 8 (count-prefixed-lines first-diff "| 360 only | `@"))
                 (search "| `<LSGT>` physical placement | A2 and 360 | `typed-unreachable` |" first-diff)
                 (search "| `mode-key` inactive result | A2 / 360 | `device-specific-inactive-output` |" first-diff)
                 (search "| `kanata-1-12-buffered` compatibility profile | 14 primary + 2 selector aliases | `typed-policy-unselected` |" first-diff)
                 (search "| `case-left-shift` | `lshift` → `lshift` |" first-diff)
                 (search "| `greek` | `lctl` → `@gr` |" first-diff)
                 (search "| `top` | `rctl` → `@top` |" first-diff)
                 (search "Unchecked differences: 0" first-diff))
      (error "Generated Manna diff report no longer classifies every frozen difference."))
    (checked-in-fixture-evidence-p fixture-render)
    (format t "Manna Cadet frozen truth-table migration test passed.~%")
    t))

(main)
