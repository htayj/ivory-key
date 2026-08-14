;;;; SPDX-License-Identifier: GPL-3.0-or-later
;;;; Model-to-simulator adapter regression tests.

(in-package #:ivory-key.tests)

(defun compile-simulation-assert (truth control &rest arguments)
  (unless truth
    (error (apply #'format nil control arguments))))

(defun compile-simulation-assert-equal (expected actual label)
  (compile-simulation-assert (equal expected actual)
                             "~A: expected ~S, got ~S" label expected actual))

(defun compile-simulation-event (time kind position)
  (ivory-key.simulate::make-timed-event time kind position))

(defun compile-simulation-result (interactions events &key latches axes until)
  (ivory-key.simulate::simulate-events interactions events
                                       :latches latches :axes axes :until until))

(defun compile-simulation-temporal-fixture ()
  (let* ((combo
           (ivory-key.model::make-interaction-candidate
            "combo"
            (ivory-key.model::pattern-conjunction
             (ivory-key.model::pattern-all
              (ivory-key.model::pattern-down "a")
              (ivory-key.model::pattern-down "b"))
             (ivory-key.model::pattern-within
              45 (ivory-key.model::pattern-down "a")
              (ivory-key.model::pattern-down "b"))
             (ivory-key.model::pattern-overlap "a" "b"))
            :when-matched
            (ivory-key.model::make-command-output "stop-output")))
         (interaction (ivory-key.model::make-interaction
                       "combo" '("a" "b") (list combo))))
    (ivory-key.simulate::compile-model-interaction interaction)))

(deftest simulation-compile-model-pattern-algebra-end-to-end
  (let ((result
          (compile-simulation-result
           (list (compile-simulation-temporal-fixture))
           (list (compile-simulation-event 0 :down "a")
                 (compile-simulation-event 40 :down "b")
                 (compile-simulation-event 50 :up "a")
                 (compile-simulation-event 60 :up "b")))))
    (compile-simulation-assert-equal
     '((:command "stop-output"))
     (ivory-key.simulate::simulation-result-outputs result)
     "all, within, overlap, and conjunction survive model-to-simulator lowering")))

(deftest simulation-compile-supports-each-simulator-pattern-node
  (let ((patterns
          (list
           (ivory-key.model::pattern-down "a")
           (ivory-key.model::pattern-up "a")
           (ivory-key.model::pattern-sequence
            (ivory-key.model::pattern-down "a")
            (ivory-key.model::pattern-up "a"))
           (ivory-key.model::pattern-all
            (ivory-key.model::pattern-down "a")
            (ivory-key.model::pattern-down "b"))
           (ivory-key.model::pattern-either
            (ivory-key.model::pattern-down "a")
            (ivory-key.model::pattern-down "b"))
           (ivory-key.model::pattern-conjunction
            (ivory-key.model::pattern-down "a")
            (ivory-key.model::pattern-up "a"))
           (ivory-key.model::pattern-duration "a" :less-than 200)
           (ivory-key.model::pattern-deadline 200 :after "a" :while-down "a")
           (ivory-key.model::pattern-within
            45 (ivory-key.model::pattern-down "a")
            (ivory-key.model::pattern-down "b"))
           (ivory-key.model::pattern-overlap "a" "b")
           (ivory-key.model::pattern-without
            (ivory-key.model::pattern-down
             (ivory-key.model::other-than-selector "a"))
            :between (list (ivory-key.model::pattern-down "a")
                           (ivory-key.model::pattern-up "a")))
           (ivory-key.model::pattern-repeat
            (ivory-key.model::pattern-down "a") :at-least 1 :at-most 2))))
    (dolist (pattern patterns)
      (compile-simulation-assert
       (typep (ivory-key.simulate::compile-model-temporal-pattern pattern)
              'ivory-key.simulate::event-pattern)
       "model pattern ~S should compile into simulator IR" pattern))))

(defun compile-simulation-tap-hold-fixture ()
  (let* ((effects
           (ivory-key.model::make-interaction-effects
            :while (list (ivory-key.model::make-held-modifier-operation "super"))))
         (candidate
           (ivory-key.model::make-interaction-candidate
            "hold"
            (ivory-key.model::pattern-deadline 100 :after "a" :while-down "a")
            :when-matched
            (ivory-key.model::make-sequence-behavior
             (list (ivory-key.model::make-text-output "H")
                   (ivory-key.model::make-named-key-output "return")))
            :effects effects))
         (interaction (ivory-key.model::make-interaction "hold-a" '("a") (list candidate))))
    (ivory-key.simulate::compile-model-interaction interaction)))

(deftest simulation-compile-model-deadline-effects-and-sequence
  (let ((result
          (compile-simulation-result
           (list (compile-simulation-tap-hold-fixture))
           (list (compile-simulation-event 0 :down "a")
                 (compile-simulation-event 150 :up "a")))))
    (compile-simulation-assert-equal
     '((:modifier :press "super") (:text "H") (:named-key "return")
       (:modifier :release "super"))
     (ivory-key.simulate::simulation-result-outputs result)
     "deadline commitment keeps source sequence and reversible effect lifetime")
    (compile-simulation-assert-equal
     nil (ivory-key.simulate::simulation-result-active-effects result)
     "compiled effect exits at the participant release")))

(deftest simulation-compile-normalized-interaction-uses-canonical-effects
  (let* ((topology (ivory-key.model::make-topology
                    "one" (list (ivory-key.model::make-logical-position "a"))))
         (effects (ivory-key.model::make-interaction-effects
                   :while (list (ivory-key.model::make-held-modifier-operation "super"))))
         (candidate (ivory-key.model::make-interaction-candidate
                     "hold"
                     (ivory-key.model::pattern-deadline 100 :after "a" :while-down "a")
                     :when-matched (ivory-key.model::make-text-output "H")
                     :effects effects))
         (interaction (ivory-key.model::make-interaction "hold-a" '("a") (list candidate)))
         (layout (ivory-key.model::make-layout
                  "normal" topology nil '("super") :interactions (list interaction)))
         (normalized (ivory-key.model::normalize-layout layout))
         (compiled (ivory-key.simulate::compile-normalized-interaction
                    (first (ivory-key.model::normalized-layout-interactions normalized))))
         (result (compile-simulation-result
                  (list compiled)
                  (list (compile-simulation-event 0 :down "a")
                        (compile-simulation-event 150 :up "a")))))
    (compile-simulation-assert-equal
     '((:modifier :press "super") (:text "H") (:modifier :release "super"))
     (ivory-key.simulate::simulation-result-outputs result)
     "normalized entries and lifecycle variants retain their selected behavior")))

(defun compile-simulation-shift-latch-fixture ()
  (let* ((latch-candidate
           (ivory-key.model::make-interaction-candidate
            "latch"
            (ivory-key.model::pattern-sequence
             (ivory-key.model::pattern-down "l")
             (ivory-key.model::pattern-up "l"))
            :when-matched
            (ivory-key.model::make-axis-operation :latch "shift-latch" "latch")))
         (plain-candidate
           (ivory-key.model::make-interaction-candidate
            "plain"
            (ivory-key.model::pattern-sequence
             (ivory-key.model::pattern-down "q")
             (ivory-key.model::pattern-up "q"))
            :when-matched
            (ivory-key.model::make-text-output "q")))
         (consulting-candidate
           (ivory-key.model::make-interaction-candidate
            "consulting"
            (ivory-key.model::pattern-sequence
             (ivory-key.model::pattern-down "p")
             (ivory-key.model::pattern-up "p"))
            :when-matched
            (ivory-key.model::make-axis-choice-behavior
             "shift-latch"
             (list (cons "plain" (ivory-key.model::make-text-output "p"))
                   (cons "latch" (ivory-key.model::make-text-output "P"))))))
         (interactions
           (list (ivory-key.model::make-interaction "latch" '("l") (list latch-candidate))
                 (ivory-key.model::make-interaction "plain" '("q") (list plain-candidate))
                 (ivory-key.model::make-interaction "consulting" '("p")
                                                   (list consulting-candidate)))))
    (ivory-key.simulate::compile-model-interactions interactions)))

(deftest simulation-compile-model-shift-latch-is-dependency-scoped
  (let ((result
          (compile-simulation-result
           (compile-simulation-shift-latch-fixture)
           (list (compile-simulation-event 0 :down "l")
                 (compile-simulation-event 10 :up "l")
                 (compile-simulation-event 20 :down "q")
                 (compile-simulation-event 30 :up "q")
                 (compile-simulation-event 40 :down "p")
                 (compile-simulation-event 50 :up "p"))
           :axes '(("shift-latch" . "plain")))))
    (compile-simulation-assert-equal
     '((:text "q") (:text "P"))
     (ivory-key.simulate::simulation-result-outputs result)
     "a non-consulting key leaves the latch for the next consulting candidate")
    (compile-simulation-assert-equal
     nil (ivory-key.simulate::simulation-result-latches result)
     "the consulting candidate consumes the captured latch at commitment")))

(deftest simulation-compile-rejects-nonrepresentable-model-patterns
  (let ((captured
          (ivory-key.model::pattern-capture
           "captured" (ivory-key.model::pattern-down "a"))))
    (compile-simulation-assert
     (handler-case
         (progn
           (ivory-key.simulate::compile-model-temporal-pattern captured)
           nil)
       (ivory-key.simulate::model-simulation-compilation-error () t))
     "capture must not be silently discarded by simulation lowering")))
