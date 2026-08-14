;;;; SPDX-License-Identifier: GPL-3.0-or-later
;;;; Focused v1 surface-decoder contracts registered in ivory-key/tests.

(in-package #:ivory-key.tests)

(defun decoder-layout-from-string (source)
  (ivory-key.model:decode-layout-forms (ivory-key.syntax:parse-string source)))

(defun decoder-signals-code (code thunk)
  (handler-case
      (progn (funcall thunk)
             (error "Expected decoder error ~S, but no condition was signaled." code))
    (ivory-key.model:semantic-error (condition)
      (is-equal code (ivory-key.model:semantic-error-code condition)))))

(deftest decoder-checked-layout-fixtures-validate-and-normalize
  (dolist (pathname '("layouts/manna-cadet.ivory" "layouts/twenty-level.ivory"))
    (let* ((layout (ivory-key.model:decode-layout-forms
                    (ivory-key.syntax:parse-file pathname)))
           (normalized (ivory-key.model:normalize-layout layout)))
      ;; This is intentionally a separate direct validation: source template
      ;; calls must not remain unresolved until normalization.
      (ivory-key.model:validate-layout layout)
      (is (typep normalized 'ivory-key.model:normalized-layout))))
  (let* ((layout (ivory-key.model:decode-layout-forms
                  (ivory-key.syntax:parse-file "layouts/manna-cadet.ivory")))
         (t-binding (find "t" (ivory-key.model:layout-bindings layout)
                          :test #'ivory-key.model:identifier=
                          :key #'ivory-key.model:binding-position))
         (t-table (ivory-key.model:binding-behavior t-binding))
         (interactions (ivory-key.model:layout-interactions layout))
         (overlays (ivory-key.model:layout-overlays layout))
         (function-overlay (find "primary-function" overlays
                                 :test #'ivory-key.model:identifier=
                                 :key #'ivory-key.model:overlay-patch-name))
         (mode-key (find "mode-key"
                         (ivory-key.model:overlay-patch-bindings function-overlay)
                         :test #'ivory-key.model:identifier=
                         :key #'ivory-key.model:patch-binding-position))
         (normalized (ivory-key.model:normalize-layout layout))
         (function-context
           (ivory-key.model:make-semantic-context
            (ivory-key.model:layout-axes layout)
            :values '(("case" . "plain") ("script" . "roman")
                      ("plane" . "base") ("function" . "active"))))
         (function-q
           (ivory-key.model:normalized-layout-binding-for-context
            normalized "q" function-context :active-patches '("primary-function"))))
    ;; The mechanically frozen table covers exactly 52 static XKB positions.
    ;; The primary layered function table is a sparse patch; its two tap-hold
    ;; activators and older 45 ms chord behavior are intentionally absent.
    ;; Direct physical Shift holders and the Greek/Top selectors are separate,
    ;; exact single-key held interactions, not ordinary bindings or inferred
    ;; tap-holds.
    (is-equal 52 (length (ivory-key.model:layout-bindings layout)))
    (is-equal '("hold-case-left-shift" "hold-case-right-shift"
                "hold-greek-selector" "hold-top-selector")
              (mapcar (lambda (interaction)
                        (ivory-key.model:identifier-name
                         (ivory-key.model:interaction-name interaction)))
                      interactions))
    (is-equal '(("case-left-shift") ("case-right-shift")
                ("greek") ("top"))
              (mapcar (lambda (interaction)
                        (mapcar #'ivory-key.model:identifier-name
                                (ivory-key.model:interaction-participants interaction)))
                      interactions))
    (is-equal 1 (length overlays))
    (is-equal 29 (length (ivory-key.model:overlay-patch-bindings function-overlay)))
    (is (typep (ivory-key.model:patch-binding-behavior mode-key)
               'ivory-key.model:command-output))
    (is-equal "alt-mode"
              (ivory-key.model:identifier-name
               (ivory-key.model:command-name
                (ivory-key.model:patch-binding-behavior mode-key))))
    (is (typep (ivory-key.model:normalized-entry-behavior function-q)
               'ivory-key.model:command-output))
    (is-equal "quote"
              (ivory-key.model:identifier-name
               (ivory-key.model:command-name
                (ivory-key.model:normalized-entry-behavior function-q))))
    ;; FALLBACK has materialized the two genuinely absent T cells as NONE;
    ;; the other six cells come directly from the frozen XKB baseline.
    (is-equal 8 (length (ivory-key.model:behavior-table-entries t-table)))
    (is-equal 2 (count :none (ivory-key.model:behavior-table-entries t-table)
                        :key #'ivory-key.model:behavior-entry-disposition))
    ;; The old `i`+`o` chord and a comment-only latch hypothesis are regression
    ;; evidence, not active primary-layer semantics.
    (is (null (find "greek" (ivory-key.model:layout-bindings layout)
                    :test #'ivory-key.model:identifier=
                    :key #'ivory-key.model:binding-position)))))

(defun decoder-normalized-layout-dump-string (normalized)
  (with-output-to-string (stream)
    (ivory-key.cli:dump-normalized-layout normalized stream)))

(deftest decoder-twenty-level-fixture-formats-normalizes-dumps-and-simulates
  "The checked-in four-by-five fixture is an executable 20-context conformance case."
  (let* ((pathname "layouts/twenty-level.ivory")
         (parsed (ivory-key.syntax:parse-file pathname))
         (formatted (ivory-key.syntax:format-parse-result parsed))
         (reparsed (ivory-key.syntax:parse-string formatted :name pathname))
         (layout (ivory-key.model:decode-layout-forms parsed))
         (reparsed-layout (ivory-key.model:decode-layout-forms reparsed))
         (normalized (ivory-key.model:normalize-layout layout))
         (reparsed-normalized (ivory-key.model:normalize-layout reparsed-layout))
         (binding (first (ivory-key.model::normalized-layout-bindings normalized))))
    (is (ivory-key.syntax:syntax-parse-result-complete-p parsed))
    (is (ivory-key.syntax:syntax-parse-result-complete-p reparsed))
    (is (every #'ivory-key.syntax:syntax-node-equal-p
               (ivory-key.syntax:syntax-parse-result-forms parsed)
               (ivory-key.syntax:syntax-parse-result-forms reparsed)))
    (ivory-key.model:validate-layout layout)
    (ivory-key.model:validate-layout reparsed-layout)
    (is-equal 20 (length (ivory-key.model::normalized-binding-entries binding)))
    (is-equal (decoder-normalized-layout-dump-string normalized)
              (decoder-normalized-layout-dump-string reparsed-normalized))
    ;; CASE is the first product axis and therefore varies fastest.  Every
    ;; tuple must execute; the fixture's explicit FALLBACK supplies NONE away
    ;; from the four BASE outputs rather than permitting a simulation refusal.
    (let ((checked 0)
          (base-outputs '( ("plain" . "a") ("shifted" . "A")
                          ("alternate" . "á") ("titlecase" . "ǅ"))))
      (dolist (plane '("base" "greek" "math" "navigation" "symbols"))
        (dolist (case-output base-outputs)
          (let* ((case-state (car case-output))
                 (result
                   (ivory-key.simulate:simulate-normalized-layout-events
                    normalized
                    (list (ivory-key.simulate::make-timed-event 0 :down "key")
                          (ivory-key.simulate::make-timed-event 1 :up "key"))
                    :axes (list (cons "case" case-state)
                                (cons "plane" plane))))
                 (expected (if (string= plane "base")
                               (list (list :text (cdr case-output)))
                               nil)))
            (incf checked)
            (is-equal expected (ivory-key.simulate:simulation-result-outputs result)))))
      (is-equal 20 checked))))

(deftest decoder-normalized-dump-is-independent-of-source-declaration-order
  "Normalization sorts equivalent bindings and context rows before IR dumping."
  (flet ((normalized-dump (source)
           (decoder-normalized-layout-dump-string
            (ivory-key.model:normalize-layout
             (decoder-layout-from-string source)))))
    (is-equal
     (normalized-dump
      "(ivory-key 1)
(define-layout canonical
  (axis case (:states plain shifted) (:resolution product))
  (binding q (at (plain) (unicode \"q\")) (at (shifted) (unicode \"Q\")))
  (binding w (at (plain) (unicode \"w\")) (at (shifted) (unicode \"W\"))))")
     (normalized-dump
      "(ivory-key 1)
(define-layout canonical
  (axis case (:states plain shifted) (:resolution product))
  (binding w (at (shifted) (unicode \"W\")) (at (plain) (unicode \"w\")))
  (binding q (at (shifted) (unicode \"Q\")) (at (plain) (unicode \"q\"))))"))))

(deftest decoder-template-arguments-are-resolved-without-evaluation
  (let* ((layout
           (decoder-layout-from-string
            "(ivory-key 1)
(define-layout template-arguments
  (axis latch (:states plain latch) (:resolution behavioral))
  (define-behavior select-axis (axis state)
    (by-axis latch
      (plain (set-axis-state axis state))
      (latch (latch-axis-state axis state))))
  (define-behavior forward-axis (axis state)
    (select-axis axis state))
  (binding selector (forward-axis latch latch)))"))
         (binding (first (ivory-key.model:layout-bindings layout)))
         (behavior (ivory-key.model:binding-behavior binding)))
    (ivory-key.model:validate-layout layout)
    (is (typep behavior 'ivory-key.model:axis-choice-behavior))
    (is-equal '("latch")
              (mapcar #'ivory-key.model:identifier-name
                      (ivory-key.model:behavior-axis-dependencies behavior)))))

(deftest decoder-rejects-unknown-and-duplicate-surface-declarations
  (decoder-signals-code
   :unknown-form
   (lambda ()
     (decoder-layout-from-string
      "(ivory-key 1) (define-layout bad (unknown-option x))")))
  (decoder-signals-code
   :duplicate-context-entry
   (lambda ()
     (decoder-layout-from-string
      "(ivory-key 1)
(define-layout duplicate
  (axis case (:states plain shifted) (:resolution product))
  (binding q (at (plain) (unicode \"q\")) (at (plain) (unicode \"Q\"))))")))
  (decoder-signals-code
   :unsupported-top-level-form
   (lambda ()
     (decoder-layout-from-string
      "(ivory-key 1) (unsupported x) (define-layout bad (binding q (unicode \"q\")))"))))

(deftest decoder-rejects-template-cycles-and-interaction-ambiguity
  (decoder-signals-code
   :recursive-behavior-template
   (lambda ()
     (decoder-layout-from-string
      "(ivory-key 1)
(define-layout recursive
  (define-behavior first () (second))
  (define-behavior second () (first))
  (binding q (first)))")))
  (decoder-signals-code
   :ambiguous-interaction-commit
   (lambda ()
     (let ((layout (decoder-layout-from-string
                    "(ivory-key 1)
(define-layout ambiguous
  (interaction a-tap
    (:participants a)
    (case first (:match (sequence (down a) (up a))) (:commit (up a)) (:do (unicode \"a\")))
    (case second (:match (sequence (down a) (up a))) (:commit (up a)) (:do (unicode \"b\")))))")))
       (ivory-key.model:validate-layout layout)))))

(deftest decoder-capture-selector-and-effect-start-are-closed
  (let* ((layout
           (decoder-layout-from-string
            "(ivory-key 1)
(define-layout capture-slice
  (binding a (unicode \"a\"))
  (binding b (unicode \"b\"))
  (interaction foreign-release
    (:participants a)
    (:observe any-position)
    (:anchor a)
    (case release
      (:match (sequence (down a)
                        (capture foreign (down (other-than a)))
                        (up (captured foreign))))
      (:commit when-matched)
      (:do none)
      (:effect-start on-commit))))"))
         (candidate (first (ivory-key.model::interaction-candidates
                            (first (ivory-key.model:layout-interactions layout)))))
         (match (ivory-key.model::candidate-match candidate))
         (up (third (ivory-key.model::temporal-pattern-arguments match)))
         (selector (first (ivory-key.model::temporal-pattern-arguments up))))
    (ivory-key.model:validate-layout layout)
    (is-equal :on-commit (ivory-key.model::candidate-effect-start candidate))
    (is-equal :captured (ivory-key.model::position-selector-kind selector))
    (is-equal '("foreign")
              (mapcar #'ivory-key.model::identifier-name
                      (ivory-key.model::position-selector-positions selector))))
  (decoder-signals-code
   :unknown-effect-start
   (lambda ()
     (decoder-layout-from-string
      "(ivory-key 1)
(define-layout bad-effect-start
  (interaction a
    (:participants a)
    (:match (down a)) (:commit when-matched) (:do none)
    (:effect-start later)))")))
  (decoder-signals-code
   :malformed-position-selector
   (lambda ()
     (decoder-layout-from-string
      "(ivory-key 1)
(define-layout bad-captured
  (interaction a
    (:participants a)
    (:match (up (captured foreign extra))) (:commit when-matched) (:do none)))"))))

(deftest decoder-keeps-kanata-1-12-buffering-and-replay-unencoded
  "CAPTURE recognizes a foreign interval; it does not make it a delayed input.

The proposed non-default KANATA-1-12-BUFFERED policy needs a typed pending
foreign event and ordered redispatch.  Until that model exists, source forms
that purport to buffer/replay must fail closed, and the existing capture slice
must retain its ordinary-binding dispatch rather than falsely claiming the
Kanata ordering.
"
  (dolist (form '("(buffer-foreign-event foreign)"
                  "(replay-buffered-event foreign)"))
    (decoder-signals-code
     :unknown-behavior-form
     (lambda ()
       (decoder-layout-from-string
        (format nil
                "(ivory-key 1)
(define-layout proposed-buffering
  (interaction owner
    (:participants a)
    (:observe any-position)
    (:anchor a)
    (case foreign-release
      (:match (sequence (down a)
                        (capture foreign (down (other-than a)))
                        (up (captured foreign))))
      (:commit when-matched)
      (:do ~A)
      (:effect-start on-commit))))"
                form)))))
  ;; The supported CAPTURE slice is matching-only.  With an ordinary B
  ;; binding, B dispatches at its physical DOWN (time 10), before the foreign
  ;; release commits the capture candidate at time 20.  Kanata 1.12 instead
  ;; delays that B interval, so this is a direct representability boundary,
  ;; not an attempted compatibility simulation.
  (let* ((layout
           (decoder-layout-from-string
            "(ivory-key 1)
(define-layout capture-is-not-buffering
  (binding b (unicode \"b\"))
  (interaction owner
    (:participants a)
    (:observe any-position)
    (:anchor a)
    (case foreign-release
      (:match (sequence (down a)
                        (capture foreign (down (other-than a)))
                        (up (captured foreign))))
      (:commit when-matched)
      (:do none)
      (:effect-start on-commit))))"))
         (result
           (ivory-key.simulate:simulate-normalized-layout-events
            (ivory-key.model:normalize-layout layout)
            (list (ivory-key.simulate::make-timed-event 0 :down "a")
                  (ivory-key.simulate::make-timed-event 10 :down "b")
                  (ivory-key.simulate::make-timed-event 20 :up "b")
                  (ivory-key.simulate::make-timed-event 30 :up "a"))))
         (ordinary-b-action
           (find :action (ivory-key.simulate::simulation-result-trace result)
                 :key #'ivory-key.simulate::simulation-trace-entry-kind)))
    (is-equal '((:text "b"))
              (ivory-key.simulate:simulation-result-outputs result))
    (is-equal 10
              (ivory-key.simulate::simulation-trace-entry-time ordinary-b-action))
    (is-equal '(:emit (:text "b"))
              (ivory-key.simulate::simulation-trace-entry-details ordinary-b-action))))

(deftest decoder-never-interns-source-identifiers
  (let ((name "surface-decoder-must-not-intern-this")
        (package (find-package :ivory-key.model)))
    (is (null (find-symbol "SURFACE-DECODER-MUST-NOT-INTERN-THIS" package)))
    (decoder-layout-from-string
     "(ivory-key 1)
(define-layout surface-decoder-must-not-intern-this
  (binding surface-decoder-must-not-intern-this (unicode \"q\")))")
    (is (null (find-symbol (string-upcase name) package)))))
