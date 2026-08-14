;;;; SPDX-License-Identifier: GPL-3.0-or-later
;;;; Whole normalized-layout reference simulation regression tests.

(in-package #:ivory-key.tests)

(defun layout-simulation-assert (truth control &rest arguments)
  (unless truth
    (error (apply #'format nil control arguments))))

(defun layout-simulation-assert-equal (expected actual label)
  (layout-simulation-assert (equal expected actual)
                            "~A: expected ~S, got ~S" label expected actual))

(defun layout-simulation-event (time kind position)
  (ivory-key.simulate::make-timed-event time kind position))

(defun layout-simulation-result (layout events &key axes latches until)
  (ivory-key.simulate::simulate-normalized-layout-events
   layout events :axes axes :latches latches :until until))

(defun layout-simulation-topology (&rest positions)
  (ivory-key.model::make-topology
   "layout-simulation-topology"
   (mapcar #'ivory-key.model::make-logical-position positions)))

(defun layout-simulation-normalized-layout (axes bindings &key interactions overlays positions)
  (let ((topology (apply #'layout-simulation-topology
                         (or positions (mapcar #'car bindings)))))
    (ivory-key.model::normalize-layout
     (ivory-key.model::make-layout
      "layout-simulation" topology axes nil
      :bindings (mapcar (lambda (entry)
                          (ivory-key.model::make-binding (car entry) (cdr entry)))
                        bindings)
      :interactions interactions
      :overlays overlays))))

(defun layout-simulation-feature-from (thunk)
  (handler-case
      (progn (funcall thunk)
             (error "Expected a model simulation compilation error."))
    (ivory-key.simulate::model-simulation-compilation-error (condition)
      (ivory-key.simulate::model-simulation-compilation-error-feature condition))))

(deftest simulation-layout-dispatches-normalized-ordinary-bindings-with-context
  (let* ((case-axis (ivory-key.model::make-context-axis
                     "case" '("plain" "shifted")))
         (layout
           (layout-simulation-normalized-layout
            (list case-axis)
            (list
             (cons "q"
                   (ivory-key.model::make-axis-choice-behavior
                    "case"
                    (list (cons "plain" (ivory-key.model::make-text-output "q"))
                          (cons "shifted" (ivory-key.model::make-text-output "Q"))))))))
         (result (layout-simulation-result
                  layout
                  (list (layout-simulation-event 0 :down "q")
                        (layout-simulation-event 10 :up "q"))
                  :axes '(("case" . "shifted")))))
    (layout-simulation-assert-equal
     '((:text "Q")) (ivory-key.simulate::simulation-result-outputs result)
     "ordinary binding selects the normalized context entry")
    (let ((trace (ivory-key.simulate::simulation-result-trace result)))
      (layout-simulation-assert
       (member :candidate-start
               (mapcar #'ivory-key.simulate::simulation-trace-entry-kind trace))
       "ordinary dispatch must retain a candidate trace")
      (layout-simulation-assert
       (member :commit
               (mapcar #'ivory-key.simulate::simulation-trace-entry-kind trace))
       "ordinary dispatch must retain a commitment trace"))))

(deftest simulation-layout-ordinary-binding-latches-consume-only-on-consult
  (let* ((shift-latch (ivory-key.model::make-context-axis
                       "shift-latch" '("plain" "latch") :resolution :behavioral))
         (layout
           (layout-simulation-normalized-layout
            (list shift-latch)
            (list
             (cons "x" (ivory-key.model::make-text-output "x"))
             (cons "q"
                   (ivory-key.model::make-axis-choice-behavior
                    "shift-latch"
                    (list (cons "plain" (ivory-key.model::make-text-output "q"))
                          (cons "latch" (ivory-key.model::make-text-output "Q"))))))))
         (result
           (layout-simulation-result
            layout
            (list (layout-simulation-event 0 :down "x")
                  (layout-simulation-event 1 :up "x")
                  (layout-simulation-event 2 :down "q")
                  (layout-simulation-event 3 :up "q"))
            :latches '(("shift-latch" . "latch")))))
    (layout-simulation-assert-equal
     '((:text "x") (:text "Q"))
     (ivory-key.simulate::simulation-result-outputs result)
     "a non-consulting ordinary binding leaves a latch for a consulting binding")
    (layout-simulation-assert-equal
     nil (ivory-key.simulate::simulation-result-latches result)
     "the committed consulting binding consumes its captured latch")
    (layout-simulation-assert-equal
     1 (count :latch-consumed
              (mapcar #'ivory-key.simulate::simulation-trace-entry-kind
                      (ivory-key.simulate::simulation-result-trace result)))
     "only the consulting ordinary commitment records consumption")))

(deftest simulation-layout-combines-disjoint-bindings-and-compiled-interactions
  (let* ((latch-axis (ivory-key.model::make-context-axis
                      "shift-latch" '("plain" "latch") :resolution :behavioral))
         (latch-candidate
           (ivory-key.model::make-interaction-candidate
            "latch-on-tap"
            (ivory-key.model::pattern-sequence
             (ivory-key.model::pattern-down "l")
             (ivory-key.model::pattern-up "l"))
            :when-matched
            (ivory-key.model::make-axis-operation :latch "shift-latch" "latch")))
         (latch-interaction
           (ivory-key.model::make-interaction
            "latch-key" '("l") (list latch-candidate)))
         (layout
           (layout-simulation-normalized-layout
            (list latch-axis)
            (list
             (cons "q"
                   (ivory-key.model::make-axis-choice-behavior
                    "shift-latch"
                    (list (cons "plain" (ivory-key.model::make-text-output "q"))
                          (cons "latch" (ivory-key.model::make-text-output "Q"))))))
            :interactions (list latch-interaction)
            :positions '("l" "q")))
         (result
           (layout-simulation-result
            layout
            (list (layout-simulation-event 0 :down "l")
                  (layout-simulation-event 1 :up "l")
                  (layout-simulation-event 2 :down "q")
                  (layout-simulation-event 3 :up "q")))))
    (layout-simulation-assert-equal
     '((:text "Q"))
     (ivory-key.simulate::simulation-result-outputs result)
     "compiled interaction latch feeds the subsequent normalized ordinary binding")
    (layout-simulation-assert-equal
     nil (ivory-key.simulate::simulation-result-latches result)
     "the ordinary binding consumes the interaction-produced latch")
    (let ((trace (ivory-key.simulate::simulation-result-trace result)))
      (layout-simulation-assert
       (member :latch-set
               (mapcar #'ivory-key.simulate::simulation-trace-entry-kind trace))
       "the interaction latch action remains traceable")
      (layout-simulation-assert
       (member :latch-consumed
               (mapcar #'ivory-key.simulate::simulation-trace-entry-kind trace))
       "the ordinary binding consumption remains traceable"))))

(deftest simulation-layout-refuses-overlapping-binding-and-interaction-positions
  (let* ((candidate
           (ivory-key.model::make-interaction-candidate
            "tap"
            (ivory-key.model::pattern-sequence
             (ivory-key.model::pattern-down "a")
             (ivory-key.model::pattern-up "a"))
            :when-matched
            (ivory-key.model::make-text-output "tap")))
         (interaction (ivory-key.model::make-interaction "tap-a" '("a") (list candidate)))
         (layout
           (layout-simulation-normalized-layout
            nil
            (list (cons "a" (ivory-key.model::make-text-output "a")))
            :interactions (list interaction))))
    (layout-simulation-assert-equal
     :ordinary-binding-interaction-overlap
     (layout-simulation-feature-from
      (lambda () (ivory-key.simulate::compile-normalized-layout-simulation layout)))
     "undefined ordinary fallback timing must not be guessed")))

(deftest simulation-layout-refuses-overlays-and-invalid-explicit-context
  (let* ((patch-axis (ivory-key.model::make-context-axis
                      "overlay" '("base" "active") :resolution :patch))
         (overlay
           (ivory-key.model::make-overlay-patch
            "special" "overlay" "active"
            (list (ivory-key.model::make-patch-binding
                   "q" (ivory-key.model::make-text-output "Q")))
            :precedence 1))
         (overlay-layout
           (layout-simulation-normalized-layout
            (list patch-axis)
            (list (cons "q" (ivory-key.model::make-text-output "q")))
            :overlays (list overlay)))
         (plain-layout
           (layout-simulation-normalized-layout
            nil (list (cons "q" (ivory-key.model::make-text-output "q"))))))
    (layout-simulation-assert-equal
     :unsupported-normalized-overlays
     (layout-simulation-feature-from
      (lambda () (ivory-key.simulate::compile-normalized-layout-simulation overlay-layout)))
     "overlays need an activation contract rather than an implicit state guess")
    (layout-simulation-assert-equal
     :unknown-simulation-position
     (layout-simulation-feature-from
     (lambda ()
        (layout-simulation-result
         plain-layout (list (layout-simulation-event 0 :down "outside")))))
     "unknown input positions must not be silently ignored")))

(deftest simulation-layout-refuses-unsupported-ordinary-behavior-and-pattern
  (let* ((mode-axis (ivory-key.model::make-context-axis
                     "mode" '("plain" "other") :resolution :behavioral))
         (unsupported-binding-layout
           (layout-simulation-normalized-layout
            (list mode-axis)
            (list (cons "q"
                        (ivory-key.model::make-axis-operation :toggle "mode")))))
         (captured-candidate
           (ivory-key.model::make-interaction-candidate
            "captured"
            (ivory-key.model::pattern-capture
             "value" (ivory-key.model::pattern-down "l"))
            :when-matched
            (ivory-key.model::make-text-output "never")))
         (unsupported-pattern-layout
           (layout-simulation-normalized-layout
            nil
            (list (cons "q" (ivory-key.model::make-text-output "q")))
            :interactions
            (list (ivory-key.model::make-interaction
                   "captured" '("l") (list captured-candidate)))
            :positions '("l" "q"))))
    (layout-simulation-assert-equal
     :unsupported-axis-operation
     (layout-simulation-feature-from
      (lambda ()
        (ivory-key.simulate::compile-normalized-layout-simulation
         unsupported-binding-layout)))
     "an ordinary behavior with no exact machine transition must be refused")
    (layout-simulation-assert-equal
     :unsupported-contextual-temporal-pattern
     (layout-simulation-feature-from
      (lambda ()
        (ivory-key.simulate::compile-normalized-layout-simulation
         unsupported-pattern-layout)))
     "an interaction pattern outside the finite machine vocabulary must be refused")))
