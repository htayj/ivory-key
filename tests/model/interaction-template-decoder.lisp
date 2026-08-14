;;;; SPDX-License-Identifier: GPL-3.0-or-later
;;;; Closed source interaction-template declarations and instantiation.

(in-package #:ivory-key.tests)

(defun interaction-template-decoder-layout (source)
  (ivory-key.model:decode-layout-forms (ivory-key.syntax:parse-string source)))

(defun interaction-template-decoder-signals-code (code thunk)
  (handler-case
      (progn
        (funcall thunk)
        (error "Expected semantic error ~S, but none was signaled." code))
    (ivory-key.model:semantic-error (condition)
      (is-equal code (ivory-key.model:semantic-error-code condition)))))

(defparameter +interaction-template-decoder-layout+
  "(ivory-key 1)
(define-layout source-interaction-templates
  (binding a (unicode \"a\"))
  ;; The wrapper intentionally precedes its target, proving source definitions
  ;; may forward-reference a known declaration without reader evaluation.
  (define-interaction-template tap-wrapper (position)
    (instantiate-interaction tap-core (:position position)))
  (define-interaction-template tap-core (position)
    (interaction tap-core-result
      (:participants position)
      (:anchor position)
      (:match (sequence (down position) (up position)))
      (:commit (up position))
      (:do (unicode \"x\"))))
  (instantiate-interaction tap-wrapper (:position a)))")

(deftest interaction-template-decoder-expands-forward-named-arguments
  (let* ((layout (interaction-template-decoder-layout
                  +interaction-template-decoder-layout+))
         (templates (ivory-key.model:layout-interaction-templates layout))
         (interaction (first (ivory-key.model:layout-interactions layout)))
         (candidate (first (ivory-key.model:interaction-candidates interaction)))
         (first-selector
           (first (ivory-key.model:temporal-pattern-arguments
                  (first (ivory-key.model:temporal-pattern-arguments
                          (ivory-key.model:candidate-match candidate)))))))
    ;; The decoder returns expanded interactions, so callers never need to
    ;; choose a template by source order or validate an unresolved reference.
    (is-equal '("tap-wrapper" "tap-core")
              (mapcar (lambda (template)
                        (ivory-key.model:identifier-name
                         (ivory-key.model:interaction-template-name template)))
                      templates))
    (is (typep interaction 'ivory-key.model:interaction))
    (is-equal "tap-core-result"
              (ivory-key.model:identifier-name
               (ivory-key.model:interaction-name interaction)))
    (is-equal '("a")
              (mapcar #'ivory-key.model:identifier-name
                      (ivory-key.model:interaction-participants interaction)))
    (is-equal "a"
              (ivory-key.model:identifier-name
               (ivory-key.model:interaction-anchor interaction)))
    (is-equal :position (ivory-key.model:position-selector-kind first-selector))
    (is-equal '("a")
              (mapcar #'ivory-key.model:identifier-name
                      (ivory-key.model:position-selector-positions first-selector)))
    (ivory-key.model:validate-layout layout)))

(deftest interaction-template-decoder-rejects-closed-argument-failures
  (dolist
      (fixture
       (list
        (cons :unknown-interaction-template
              "(ivory-key 1) (define-layout bad
                 (instantiate-interaction absent))")
        (cons :unknown-interaction-template-argument
              "(ivory-key 1) (define-layout bad
                 (define-interaction-template tap (position)
                   (interaction tap-body
                     (:participants position)
                     (:match (down position)) (:commit (down position))
                     (:do (unicode \"x\"))))
                 (instantiate-interaction tap (:other a)))")
        (cons :duplicate-interaction-template-argument
              "(ivory-key 1) (define-layout bad
                 (define-interaction-template tap (position)
                   (interaction tap-body
                     (:participants position)
                     (:match (down position)) (:commit (down position))
                     (:do (unicode \"x\"))))
                 (instantiate-interaction tap (:position a) (:position b)))")
        (cons :template-arity
              "(ivory-key 1) (define-layout bad
                 (define-interaction-template tap (position)
                   (interaction tap-body
                     (:participants position)
                     (:match (down position)) (:commit (down position))
                     (:do (unicode \"x\"))))
                 (instantiate-interaction tap))")
        (cons :duplicate-interaction-template-parameter
              "(ivory-key 1) (define-layout bad
                 (define-interaction-template tap (position position)
                   (interaction tap-body
                     (:participants position)
                     (:match (down position)) (:commit (down position))
                     (:do (unicode \"x\")))))")
        (cons :duplicate-interaction-template
              "(ivory-key 1) (define-layout bad
                 (define-interaction-template tap ()
                   (interaction one (:participants a) (:match (down a))
                     (:commit (down a)) (:do (unicode \"x\"))))
                 (define-interaction-template TAP ()
                   (interaction two (:participants b) (:match (down b))
                     (:commit (down b)) (:do (unicode \"x\")))))")
        (cons :invalid-interaction-template-body
              "(ivory-key 1) (define-layout bad
                 (define-interaction-template tap () (unknown-body x)))")))
    (interaction-template-decoder-signals-code
     (car fixture)
     (lambda () (interaction-template-decoder-layout (cdr fixture))))))

(deftest interaction-template-decoder-rejects-cycles-and-ambiguous-expansions
  ;; The cycle is rejected even though no top-level instantiation reaches it.
  (interaction-template-decoder-signals-code
   :recursive-interaction-template
   (lambda ()
     (interaction-template-decoder-layout
      "(ivory-key 1) (define-layout recursive
         (define-interaction-template first ()
           (instantiate-interaction second))
         (define-interaction-template second ()
           (instantiate-interaction first)))")))
  ;; References have no implicit second instance name.  Expanding this template
  ;; twice would produce two interaction declarations named TAP-RESULT, so the
  ;; resolver refuses instead of selecting one based on source order.
  (interaction-template-decoder-signals-code
   :ambiguous-interaction-template-expansion
   (lambda ()
     (interaction-template-decoder-layout
      "(ivory-key 1) (define-layout ambiguous
         (binding a (unicode \"a\"))
         (binding b (unicode \"b\"))
         (define-interaction-template tap (position)
           (interaction tap-result
             (:participants position) (:anchor position)
             (:match (sequence (down position) (up position)))
             (:commit (up position)) (:do (unicode \"x\"))))
         (instantiate-interaction tap (:position a))
         (instantiate-interaction tap (:position b)))"))))

(deftest interaction-template-decoder-never-interns-source-identifiers
  (let ((name "interaction-template-source-must-not-intern")
        (package (find-package :ivory-key.model)))
    (is (null (find-symbol (string-upcase name) package)))
    (interaction-template-decoder-layout
     "(ivory-key 1) (define-layout no-intern
        (binding q (unicode \"q\"))
        (define-interaction-template interaction-template-source-must-not-intern (position)
          (interaction resolved-name
            (:participants position) (:anchor position)
            (:match (down position)) (:commit (down position))
            (:do (unicode \"x\"))))
        (instantiate-interaction interaction-template-source-must-not-intern
          (:position q)))")
    (is (null (find-symbol (string-upcase name) package)))))
