;;;; SPDX-License-Identifier: GPL-3.0-or-later
;;;; Focused v1 surface-decoder contracts.  Loaded manually until the test
;;;; system's component list is extended by the bootstrap owner.

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
         (greek-binding (find "greek" (ivory-key.model:layout-bindings layout)
                             :test #'ivory-key.model:identifier=
                             :key #'ivory-key.model:binding-position))
         (interactions (ivory-key.model:layout-interactions layout))
         (stop-output (find "stop-output" interactions :test #'ivory-key.model:identifier=
                            :key #'ivory-key.model:interaction-name))
         (tap (find "on-tap-latch-latch" interactions :test #'ivory-key.model:identifier=
                    :key #'ivory-key.model:interaction-name)))
    ;; FALLBACK has materialized every omitted product tuple as explicit NONE.
    (is-equal 8 (length (ivory-key.model:behavior-table-entries t-table)))
    (is-equal 4 (count :none (ivory-key.model:behavior-table-entries t-table)
                        :key #'ivory-key.model:behavior-entry-disposition))
    ;; The source template call has been expanded before direct validation.
    (is (typep (ivory-key.model:binding-behavior greek-binding)
               'ivory-key.model:axis-choice-behavior))
    ;; Historical direct interaction spelling becomes one ordinary candidate.
    (is-equal '("default")
              (mapcar (lambda (candidate)
                        (ivory-key.model:identifier-name
                         (ivory-key.model:candidate-name candidate)))
                      (ivory-key.model:interaction-candidates stop-output)))
    ;; ON-TAP has no private behavior class: it is a finite down/up interaction.
    (is-equal 1 (length (ivory-key.model:interaction-candidates tap)))
    (is-equal :sequence
              (ivory-key.model:temporal-pattern-kind
               (ivory-key.model:candidate-match
                (first (ivory-key.model:interaction-candidates tap)))))))

(deftest decoder-template-arguments-are-resolved-without-evaluation
  (let* ((layout
           (decoder-layout-from-string
            "(ivory-key 1)
(define-layout template-arguments
  (axis latch (:states plain latch) (:resolution behavioral))
  (define-behavior select-axis (axis state)
    (by-axis latch
      (plain (hold-axis-state axis state))
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

(deftest decoder-never-interns-source-identifiers
  (let ((name "surface-decoder-must-not-intern-this")
        (package (find-package :ivory-key.model)))
    (is (null (find-symbol "SURFACE-DECODER-MUST-NOT-INTERN-THIS" package)))
    (decoder-layout-from-string
     "(ivory-key 1)
(define-layout surface-decoder-must-not-intern-this
  (binding surface-decoder-must-not-intern-this (unicode \"q\")))")
    (is (null (find-symbol (string-upcase name) package)))))
