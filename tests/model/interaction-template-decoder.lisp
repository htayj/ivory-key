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
  ;; Only this top-level call materializes an interaction identity.  The
  ;; wrapper's nested call delegates without a second instance name.
  (instantiate-interaction source-tap tap-wrapper (:position a)))")

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
    (is-equal "source-tap"
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
                 (instantiate-interaction absent-instance absent))")
        (cons :unknown-interaction-template-argument
              "(ivory-key 1) (define-layout bad
                 (define-interaction-template tap (position)
                   (interaction tap-body
                     (:participants position)
                     (:match (down position)) (:commit (down position))
                     (:do (unicode \"x\"))))
                 (instantiate-interaction tap-instance tap (:other a)))")
        (cons :duplicate-interaction-template-argument
              "(ivory-key 1) (define-layout bad
                 (define-interaction-template tap (position)
                   (interaction tap-body
                     (:participants position)
                     (:match (down position)) (:commit (down position))
                     (:do (unicode \"x\"))))
                 (instantiate-interaction tap-instance tap (:position a) (:position b)))")
        (cons :template-arity
              "(ivory-key 1) (define-layout bad
                 (define-interaction-template tap (position)
                   (interaction tap-body
                     (:participants position)
                     (:match (down position)) (:commit (down position))
                     (:do (unicode \"x\"))))
                 (instantiate-interaction tap-instance tap))")
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
                 (define-interaction-template tap () (unknown-body x)))")
        (cons :nested-interaction-template-instance-name
              "(ivory-key 1) (define-layout bad
                 (define-interaction-template wrapper (position)
                   (instantiate-interaction forbidden-instance target
                     (:position position)))
                 (define-interaction-template target (position)
                   (interaction target-body
                     (:participants position)
                     (:match (down position)) (:commit (down position))
                     (:do (unicode \"x\"))))))")))
    (interaction-template-decoder-signals-code
     (car fixture)
     (lambda () (interaction-template-decoder-layout (cdr fixture))))))

(deftest interaction-template-decoder-rejects-cycles-and-invalid-instances
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
  ;; A public instantiation names its concrete result, so one template can
  ;; safely expand more than once with different resolved participants.
  (let ((layout
          (interaction-template-decoder-layout
           "(ivory-key 1) (define-layout two-instances
              (define-interaction-template tap (position)
                (interaction template-body-name
                  (:participants position) (:anchor position)
                  (:match (sequence (down position) (up position)))
                  (:commit (up position)) (:do (unicode \"x\"))))
              (instantiate-interaction first-tap tap (:position a))
              (instantiate-interaction second-tap tap (:position b)))")))
    (let* ((normalized (ivory-key.model:normalize-layout layout))
           ;; This layout intentionally has no ordinary bindings: interaction
           ;; positions must not acquire an unspecified ordinary fallback.
           (result
             (ivory-key.simulate:simulate-normalized-layout-events
              normalized
              (list (ivory-key.simulate:make-timed-event 0 :down "a")
                    (ivory-key.simulate:make-timed-event 1 :up "a")
                    (ivory-key.simulate:make-timed-event 2 :down "b")
                    (ivory-key.simulate:make-timed-event 3 :up "b")))))
      (is-equal '("first-tap" "second-tap")
                (mapcar (lambda (interaction)
                          (ivory-key.model:identifier-name
                           (ivory-key.model:interaction-name interaction)))
                        (ivory-key.model:layout-interactions layout)))
      (is-equal '(("a") ("b"))
                (mapcar (lambda (interaction)
                          (mapcar #'ivory-key.model:identifier-name
                                  (ivory-key.model:interaction-participants interaction)))
                        (ivory-key.model:layout-interactions layout)))
      (is-equal '("first-tap" "second-tap")
                (mapcar (lambda (interaction)
                          (ivory-key.model:identifier-name
                           (ivory-key.model:normalized-interaction-name interaction)))
                        (ivory-key.model:normalized-layout-interactions normalized)))
      (is-equal '((:text "x") (:text "x"))
                (ivory-key.simulate:simulation-result-outputs result))
      (is-equal '("first-tap" "second-tap")
                (mapcar
                 (lambda (entry)
                   (ivory-key.simulate::sim-interaction-name
                    (ivory-key.simulate:simulation-trace-entry-interaction entry)))
                 (remove-if-not
                  (lambda (entry)
                    (eq :commit (ivory-key.simulate::simulation-trace-entry-kind entry)))
                  (ivory-key.simulate:simulation-result-trace result))))
      (ivory-key.model:validate-layout layout)))
  ;; All source interaction declarations and instances share one name space.
  ;; Duplicate public instance names are rejected before expansion.
  (interaction-template-decoder-signals-code
   :duplicate-interaction
   (lambda ()
     (interaction-template-decoder-layout
      "(ivory-key 1) (define-layout duplicate-instance
         (binding a (unicode \"a\"))
         (binding b (unicode \"b\"))
         (define-interaction-template tap (position)
           (interaction tap-result
             (:participants position) (:anchor position)
             (:match (sequence (down position) (up position)))
             (:commit (up position)) (:do (unicode \"x\"))))
         (instantiate-interaction tap-instance tap (:position a))
         (instantiate-interaction tap-instance tap (:position b)))")))
  ;; A direct interaction cannot claim an explicit template-instance name
  ;; either; it receives the same source-level duplicate diagnostic.
  (interaction-template-decoder-signals-code
   :duplicate-interaction
   (lambda ()
     (interaction-template-decoder-layout
      "(ivory-key 1) (define-layout direct-instance-collision
         (interaction shared
           (:participants a) (:match (down a)) (:commit (down a))
           (:do (unicode \"d\")))
         (define-interaction-template tap ()
           (interaction template-body
             (:participants a) (:match (down a)) (:commit (down a))
             (:do (unicode \"t\"))))
         (instantiate-interaction shared tap))")))
  ;; The old top-level spelling remains valid only as a nested delegation.  At
  ;; layout scope it has no concrete identity and gets a stable diagnostic.
  (interaction-template-decoder-signals-code
   :missing-interaction-template-instance-name
   (lambda ()
     (interaction-template-decoder-layout
      "(ivory-key 1) (define-layout legacy-instance
         (define-interaction-template tap (position)
           (interaction tap-result
             (:participants position) (:anchor position)
             (:match (down position)) (:commit (down position))
             (:do (unicode \"x\"))))
         (instantiate-interaction tap (:position a)))"))))

(deftest interaction-template-decoder-never-interns-source-identifiers
  (let ((name "interaction-template-source-must-not-intern")
        (instance-name "interaction-template-instance-must-not-intern")
        (package (find-package :ivory-key.model)))
    (is (null (find-symbol (string-upcase name) package)))
    (is (null (find-symbol (string-upcase instance-name) package)))
    (interaction-template-decoder-layout
     "(ivory-key 1) (define-layout no-intern
        (binding q (unicode \"q\"))
        (define-interaction-template interaction-template-source-must-not-intern (position)
          (interaction resolved-name
            (:participants position) (:anchor position)
            (:match (down position)) (:commit (down position))
            (:do (unicode \"x\"))))
        (instantiate-interaction interaction-template-instance-must-not-intern
          interaction-template-source-must-not-intern (:position q)))")
    (is (null (find-symbol (string-upcase name) package)))
    (is (null (find-symbol (string-upcase instance-name) package)))))
