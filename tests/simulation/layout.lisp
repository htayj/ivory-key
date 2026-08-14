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

(deftest simulation-layout-dispatches-sparse-overlays-by-precedence-and-transparency
  (let* ((patch-axis (ivory-key.model::make-context-axis
                      "fun" '("base" "active") :resolution :patch))
         (game-axis (ivory-key.model::make-context-axis
                     "game" '("base" "active") :resolution :patch))
         (fun-overlay
           (ivory-key.model::make-overlay-patch
            "fun-overlay" "fun" "active"
            (list (ivory-key.model::make-patch-binding
                   "q" (ivory-key.model::make-text-output "F"))
                  (ivory-key.model::make-transparent-patch-binding "t"))
            :precedence 10))
         (game-overlay
           (ivory-key.model::make-overlay-patch
            "game-overlay" "game" "active"
            (list (ivory-key.model::make-patch-binding
                   "q" (ivory-key.model::make-text-output "G"))
                  (ivory-key.model::make-patch-binding
                   "t" (ivory-key.model::make-text-output "T")))
            :precedence 5))
         (overlay-layout
           (layout-simulation-normalized-layout
            (list patch-axis game-axis)
            (list (cons "q" (ivory-key.model::make-text-output "q"))
                  (cons "t" (ivory-key.model::make-text-output "t")))
            :overlays (list fun-overlay game-overlay)))
         (plain-layout
           (layout-simulation-normalized-layout
            nil (list (cons "q" (ivory-key.model::make-text-output "q")))))
         (result
           (layout-simulation-result
            overlay-layout
            (list (layout-simulation-event 0 :down "q")
                  (layout-simulation-event 1 :up "q")
                  (layout-simulation-event 2 :down "t")
                  (layout-simulation-event 3 :up "t"))
            :axes '(("fun" . "active") ("game" . "active")))))
    (layout-simulation-assert-equal
     '((:text "F") (:text "T"))
     (ivory-key.simulate::simulation-result-outputs result)
     "higher-precedence opaque patch wins and transparency falls through")
    (layout-simulation-assert
     (some (lambda (entry)
             (equal '(:overlay-selection "fun-overlay" :position "q")
                    (ivory-key.simulate::simulation-trace-entry-details entry)))
           (ivory-key.simulate::simulation-result-trace result))
     "the trace records the selected higher-precedence patch")
    (layout-simulation-assert
     (some (lambda (entry)
             (equal '(:overlay-selection "game-overlay" :position "t")
                    (ivory-key.simulate::simulation-trace-entry-details entry)))
           (ivory-key.simulate::simulation-result-trace result))
     "the trace records transparent fall-through to the lower patch")
    (layout-simulation-assert-equal
     :unknown-simulation-position
     (layout-simulation-feature-from
     (lambda ()
        (layout-simulation-result
         plain-layout (list (layout-simulation-event 0 :down "outside")))))
     "unknown input positions must not be silently ignored")))

(deftest simulation-layout-overlay-observes-dynamic-set-axis-state
  (let* ((patch-axis (ivory-key.model::make-context-axis
                      "fun" '("base" "active") :resolution :patch))
         (overlay
           (ivory-key.model::make-overlay-patch
            "fun-overlay" "fun" "active"
            (list (ivory-key.model::make-patch-binding
                   "q" (ivory-key.model::make-text-output "F")))
            :precedence 10))
         (layout
           (layout-simulation-normalized-layout
            (list patch-axis)
            (list (cons "f"
                        (ivory-key.model::make-axis-operation :set "fun" "active"))
                  (cons "q" (ivory-key.model::make-text-output "q")))
            :overlays (list overlay)))
         (result
           (layout-simulation-result
            layout
            (list (layout-simulation-event 0 :down "f")
                  (layout-simulation-event 1 :up "f")
                  (layout-simulation-event 2 :down "q")
                  (layout-simulation-event 3 :up "q")))))
    (layout-simulation-assert-equal
     '((:text "F")) (ivory-key.simulate::simulation-result-outputs result)
     "a subsequent ordinary candidate reads the dynamically set patch-axis state")
    (layout-simulation-assert-equal
     '(("fun" . "active")) (ivory-key.simulate::simulation-result-axes result)
     "the state transition remains in the common simulator context")
    (layout-simulation-assert
     (some (lambda (entry)
             (equal '(:overlay-selection "fun-overlay" :position "q")
                    (ivory-key.simulate::simulation-trace-entry-details entry)))
           (ivory-key.simulate::simulation-result-trace result))
     "dynamic overlay dispatch remains explainable in the shared trace")))

(deftest simulation-layout-overlay-observes-timed-interaction-state-transition
  (let* ((patch-axis (ivory-key.model::make-context-axis
                      "fun" '("base" "active") :resolution :patch))
         (overlay
           (ivory-key.model::make-overlay-patch
            "fun-overlay" "fun" "active"
            (list (ivory-key.model::make-patch-binding
                   "q" (ivory-key.model::make-text-output "F")))
            :precedence 10))
         (candidate
           (ivory-key.model::make-interaction-candidate
            "activate-fun"
            (ivory-key.model::pattern-sequence
             (ivory-key.model::pattern-down "l")
             (ivory-key.model::pattern-up "l"))
            :when-matched
            (ivory-key.model::make-axis-operation :set "fun" "active")))
         (interaction
           (ivory-key.model::make-interaction
            "activate-fun" '("l") (list candidate)))
         (layout
           (layout-simulation-normalized-layout
            (list patch-axis)
            (list (cons "q" (ivory-key.model::make-text-output "q")))
            :interactions (list interaction)
            :overlays (list overlay)
            :positions '("l" "q")))
         (result
           (layout-simulation-result
            layout
            (list (layout-simulation-event 0 :down "l")
                  (layout-simulation-event 1 :up "l")
                  (layout-simulation-event 2 :down "q")
                  (layout-simulation-event 3 :up "q")))))
    (layout-simulation-assert-equal
     '((:text "F")) (ivory-key.simulate::simulation-result-outputs result)
     "the disjoint compiled interaction updates the shared patch-axis state")
    (let ((kinds (mapcar #'ivory-key.simulate::simulation-trace-entry-kind
                         (ivory-key.simulate::simulation-result-trace result))))
      (layout-simulation-assert
       (member :axis-set kinds)
       "the timed interaction state transition remains traceable")
      (layout-simulation-assert
       (member :commit kinds)
       "timed interaction commitment remains in the common event machine"))))

(deftest simulation-layout-refuses-overlay-latch-dependent-dispatch
  (let* ((patch-axis (ivory-key.model::make-context-axis
                      "fun" '("base" "active") :resolution :patch))
         (overlay
           (ivory-key.model::make-overlay-patch
            "fun-overlay" "fun" "active"
            (list (ivory-key.model::make-patch-binding
                   "q" (ivory-key.model::make-text-output "F")))
            :precedence 10))
         (initial-latch-layout
           (layout-simulation-normalized-layout
            (list patch-axis)
            (list (cons "q" (ivory-key.model::make-text-output "q")))
            :overlays (list overlay)))
         (dynamic-latch-layout
           (layout-simulation-normalized-layout
            (list patch-axis)
            (list (cons "f"
                        (ivory-key.model::make-axis-operation :latch "fun" "active"))
                  (cons "q" (ivory-key.model::make-text-output "q")))
            :overlays (list overlay))))
    (layout-simulation-assert-equal
     :unsupported-overlay-latch-context
     (layout-simulation-feature-from
      (lambda ()
        (layout-simulation-result
         initial-latch-layout (list (layout-simulation-event 0 :down "q"))
         :latches '(("fun" . "active")))))
     "an initial latch must not be over-consumed by conditional patch selection")
    (layout-simulation-assert-equal
     :unsupported-overlay-latch-transition
     (layout-simulation-feature-from
      (lambda ()
        (ivory-key.simulate::compile-normalized-layout-simulation dynamic-latch-layout)))
     "a generated latch for a conditionally inspected axis must fail before events")))

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
