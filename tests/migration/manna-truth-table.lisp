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

(defun checked-in-fixture-evidence-p (derived-static-bindings)
  "Verify only mechanically checkable claims made by the migration fixture.

Semantic activation remains deliberately outside this test: it has no frozen
equivalence proof.  The source checkout supplied to MAIN is hash-verified
separately before these checked-in counts are considered evidence."
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
    (unless (= 52 (count-prefixed-lines layout "  (binding "))
      (error "Manna fixture no longer has exactly 52 static bindings."))
    (unless (= 29 (count-prefixed-lines layout "    (binding "))
      (error "Manna fixture no longer has the complete 29-entry primary function table."))
    (unless (search derived-static-bindings layout)
      (error "Manna fixture's 52x8 static tables differ from the frozen mechanical render."))
    (unless (and (search "(axis function (:states inactive active) (:resolution patch))" layout)
                 (search "(overlay primary-function" layout)
                 (search "(binding mode-key (command alt-mode))" layout))
      (error "Manna fixture lost the evidence-backed primary function patch."))
    (when (or (search "latch-latch" layout)
              (search "(:participants i o)" layout)
              (search "(interaction" layout))
      (error "A comment-only latch or old chord was reintroduced as active Manna behavior."))
    (when (some (lambda (escape)
                  (search escape layout :test #'char-equal))
                '("UE00" "arbitrary-code" "@sc-" "(keysym"))
      (error "Manna abstract layout contains a backend carrier or spelling escape hatch."))
    (unless (and (search "(position mode-key)" topology)
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
         (fixture-render (tool-output "fixture" root)))
    (unless (search "Manna Cadet frozen baseline verified" verification)
      (error "Frozen baseline verification did not report success: ~A" verification))
    (unless (search "3ef72eabdd26d2154481c1b8fd0becba50dfbb9a0ba50d0d37556930f92dc807"
                    verification)
      (error "Verification did not report the expected truth-table digest: ~A" verification))
    (unless (string= first-render second-render)
      (error "Truth-table rendering is not deterministic."))
    (unless (and (search "| `<AE01>` | `1` | `exclam` |" first-render)
                 (search "| `<LSGT>` | `less` | `greater` |" first-render))
      (error "Rendered table lost required frozen evidence."))
    (checked-in-fixture-evidence-p fixture-render)
    (format t "Manna Cadet frozen truth-table migration test passed.~%")
    t))

(main)
