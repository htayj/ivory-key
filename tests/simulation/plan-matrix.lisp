;;;; SPDX-License-Identifier: GPL-3.0-or-later
;;;; Executable Phase 4 reference-simulator matrix.

(in-package #:ivory-key.tests)

;;; These tests deliberately use the public model constructors plus the small
;;; simulator IR.  Where the model adapter has an explicit refusal (notably
;;; LONGEST-MATCH scheduling), the regression asserts that refusal rather than
;;; treating a plausible direct-machine fixture as a source-semantic success.

(defun plan-matrix-assert (truth control &rest arguments)
  (unless truth
    (error (apply #'format nil control arguments))))

(defun plan-matrix-assert-equal (expected actual label)
  (plan-matrix-assert (equal expected actual)
                      "~A: expected ~S, got ~S" label expected actual))

(defun plan-matrix-event (time kind position)
  (ivory-key.simulate:make-timed-event time kind position))

(defun plan-matrix-outputs (result)
  (ivory-key.simulate:simulation-result-outputs result))

(defun plan-matrix-trace (result)
  (ivory-key.simulate:simulation-result-trace result))

(defun plan-matrix-trace-entries (result kind)
  (remove kind (plan-matrix-trace result)
          :test-not #'eq
          :key #'ivory-key.simulate::simulation-trace-entry-kind))

(defun plan-matrix-candidate-name (entry)
  (let ((candidate (ivory-key.simulate::simulation-trace-entry-candidate entry)))
    (and candidate
         (ivory-key.simulate::sim-case-name
          (ivory-key.simulate::simulation-candidate-case candidate)))))

(defun plan-matrix-assert-trace-responsibility (result kind interaction case label)
  "Assert that KIND retains the interaction/case/candidate responsible for it."
  (let ((entry
          (find-if
           (lambda (entry)
             (and (eq kind (ivory-key.simulate::simulation-trace-entry-kind entry))
                  (equal interaction
                         (ivory-key.simulate::sim-interaction-name
                          (ivory-key.simulate::simulation-trace-entry-interaction entry)))
                  (equal case
                         (ivory-key.simulate::sim-case-name
                          (ivory-key.simulate::simulation-trace-entry-case entry)))
                  (equal case (plan-matrix-candidate-name entry))))
           (plan-matrix-trace result))))
    (plan-matrix-assert entry
                        "~A: ~S trace must retain interaction ~S, case ~S, and candidate identity."
                        label kind interaction case)
    entry))

(defun plan-matrix-simulation-feature (thunk)
  (handler-case
      (progn (funcall thunk)
             (error "Expected MODEL-SIMULATION-COMPILATION-ERROR."))
    (ivory-key.simulate::model-simulation-compilation-error (condition)
      (ivory-key.simulate::model-simulation-compilation-error-feature condition))))

;;; Eight product states and five semantic modifiers -------------------------

(defparameter +plan-matrix-modifiers+
  '("control" "meta" "super" "hyper" "alt"))

(defun plan-matrix-eight-state-layout ()
  (let* ((axes
           (list (ivory-key.model:make-context-axis "case" '("plain" "shifted"))
                 (ivory-key.model:make-context-axis "script" '("roman" "greek"))
                 (ivory-key.model:make-context-axis "plane" '("base" "top"))))
         (tuples (ivory-key.model:allowed-product-tuples axes))
         (table
           (ivory-key.model:make-behavior-table
            '("case" "script" "plane")
            (loop for tuple in tuples
                  for index from 0
                  collect
                  (ivory-key.model:make-behavior-entry
                   tuple
                   (ivory-key.model::make-simultaneous-behavior
                    (append
                     (mapcar (lambda (modifier)
                               (ivory-key.model:make-modifier-operation :press modifier))
                             +plan-matrix-modifiers+)
                     (list (ivory-key.model:make-text-output
                            (format nil "level-~D" index)))))))))
         (topology
           (ivory-key.model:make-topology
            "plan-matrix-eight-topology"
            (list (ivory-key.model:make-logical-position "q"))))
         (layout
           (ivory-key.model:make-layout
            "plan-matrix-eight" topology axes +plan-matrix-modifiers+
            :bindings (list (ivory-key.model:make-binding "q" table)))))
    (values (ivory-key.model:normalize-layout layout) tuples)))

(defun plan-matrix-tuple-axes (tuple)
  (mapcar (lambda (pair)
            (cons (ivory-key.model:identifier-name (car pair))
                  (ivory-key.model:identifier-name (cdr pair))))
          (ivory-key.model::context-tuple-pairs tuple)))

(deftest simulation-plan-matrix-eight-contexts-and-five-semantic-modifiers
  (multiple-value-bind (layout tuples)
      (plan-matrix-eight-state-layout)
    (plan-matrix-assert-equal 8 (length tuples)
                              "three binary product axes enumerate eight contexts")
    (loop for tuple in tuples
          for index from 0
          for result =
            (ivory-key.simulate:simulate-normalized-layout-events
             layout
             (list (plan-matrix-event 0 :down "q")
                   (plan-matrix-event 1 :up "q"))
             :axes (plan-matrix-tuple-axes tuple))
          do
             (plan-matrix-assert-equal
              (append
               (mapcar (lambda (modifier) (list :modifier :press modifier))
                       +plan-matrix-modifiers+)
               (list (list :text (format nil "level-~D" index))))
              (plan-matrix-outputs result)
              (format nil "all five semantic modifiers and level ~D share one ordinary commitment"
                      index))
             (plan-matrix-assert-trace-responsibility
              result :action '(:ordinary-binding "q") '(:ordinary-binding "q")
              "ordinary eight-state dispatch"))))

;;; Context capture and tap/hold boundaries ----------------------------------

(defun plan-matrix-context-capture-interaction ()
  (ivory-key.simulate::compile-model-interaction
   (ivory-key.model::make-interaction
    "captured-letter" '("letter")
    (list
     (ivory-key.model::make-interaction-candidate
      "release-letter"
      (ivory-key.model::pattern-sequence
       (ivory-key.model::pattern-down "letter")
       (ivory-key.model::pattern-up "letter"))
      :when-matched
      (ivory-key.model::make-axis-choice-behavior
       "script"
       (list (cons "roman" (ivory-key.model:make-text-output "t"))
             (cons "greek" (ivory-key.model:make-text-output "τ")))))))))

(defun plan-matrix-selector-release-interaction ()
  (ivory-key.simulate::make-sim-interaction
   :name "release-greek-selector"
   :participants '("greek")
   :cases
   (list
    (ivory-key.simulate::make-sim-case
     :name "release-selector"
     :pattern (ivory-key.simulate::sequence-pattern
               (ivory-key.simulate::down-pattern "greek")
               (ivory-key.simulate::up-pattern "greek"))
     :actions (list (ivory-key.simulate::set-axis-action "script" "roman"))))))

(deftest simulation-plan-matrix-captures-context-before-selector-release
  (let ((result
          (ivory-key.simulate::simulate-events
           (list (plan-matrix-context-capture-interaction)
                 (plan-matrix-selector-release-interaction))
           (list (plan-matrix-event 0 :down "greek")
                 (plan-matrix-event 1 :down "letter")
                 (plan-matrix-event 2 :up "greek")
                 (plan-matrix-event 3 :up "letter"))
           :axes '(("script" . "greek")))))
    (plan-matrix-assert-equal '((:text "τ")) (plan-matrix-outputs result)
                              "letter uses its anchor-time Greek context")
    (plan-matrix-assert-equal '(("script" . "roman"))
                              (ivory-key.simulate:simulation-result-axes result)
                              "selector release changed later context only")
    (plan-matrix-assert-trace-responsibility
     result :commit "captured-letter" "release-letter"
     "captured delayed letter")))

(defun plan-matrix-tap-hold-interaction ()
  (ivory-key.simulate::make-sim-interaction
   :name "tap-hold" :participants '("a")
   :cases
   (list
    (ivory-key.simulate::make-sim-case
     :name "tap" :priority 1
     :pattern
     (ivory-key.simulate::and-pattern
      (ivory-key.simulate::sequence-pattern
       (ivory-key.simulate::down-pattern "a")
       (ivory-key.simulate::up-pattern "a"))
      (ivory-key.simulate::duration-pattern "a" :less-than 200))
     :actions (list (ivory-key.simulate::emit-action :tap)))
    (ivory-key.simulate::make-sim-case
     :name "hold" :priority 2
     :pattern (ivory-key.simulate::deadline-pattern 200
                                                     :after-position "a"
                                                     :while-down "a")
     :actions (list (ivory-key.simulate::emit-action :hold))))))

(deftest simulation-plan-matrix-tap-hold-threshold-and-deadline-trace
  (dolist (fixture '((199 :tap "tap") (200 :hold "hold")))
    (destructuring-bind (release expected case) fixture
      (let ((result
              (ivory-key.simulate::simulate-events
               (list (plan-matrix-tap-hold-interaction))
               (list (plan-matrix-event 0 :down "a")
                     (plan-matrix-event release :up "a")))))
        (plan-matrix-assert-equal (list expected) (plan-matrix-outputs result)
                                  "tap/hold exact threshold")
        (when (= release 200)
          (plan-matrix-assert
           (plan-matrix-trace-entries result :deadline)
           "the equal-time deadline must be visible before physical release"))
        (plan-matrix-assert-trace-responsibility
         result :commit "tap-hold" case "tap/hold commitment")))))

;;; Isolation, release order, rolling, and supported refusal ----------------

(defun plan-matrix-isolated-interaction (foreign-kind)
  (ivory-key.simulate::make-sim-interaction
   :name (list :isolated foreign-kind) :participants '("a")
   :consulted-latches '("shift-latch")
   :cases
   (list
    (ivory-key.simulate::make-sim-case
     :name "isolated"
     :pattern
     (ivory-key.simulate::and-pattern
      (ivory-key.simulate::sequence-pattern
       (ivory-key.simulate::down-pattern "a")
       (ivory-key.simulate::up-pattern "a"))
      (ivory-key.simulate::without-pattern
       (ivory-key.simulate::event-pattern foreign-kind '(:other-than "a"))
       :between (list (ivory-key.simulate::down-pattern "a")
                      (ivory-key.simulate::up-pattern "a"))))
     :actions (list (ivory-key.simulate::emit-action :isolated))
     :consulted-latches '("shift-latch")))))

(deftest simulation-plan-matrix-isolated-and-foreign-press-release-interruption
  (let ((success
          (ivory-key.simulate::simulate-events
           (list (plan-matrix-isolated-interaction :down))
           (list (plan-matrix-event 0 :down "a")
                 (plan-matrix-event 10 :up "a"))
           :latches '(("shift-latch" . "latched")))))
    (plan-matrix-assert-equal '(:isolated) (plan-matrix-outputs success)
                              "isolated release commits")
    (plan-matrix-assert-equal nil (ivory-key.simulate:simulation-result-latches success)
                              "committed isolated candidate consumes consulted latch"))
  (dolist (foreign-kind '(:down :up))
    (let* ((events (if (eq foreign-kind :down)
                       (list (plan-matrix-event 0 :down "a")
                             (plan-matrix-event 1 :down "b")
                             (plan-matrix-event 2 :up "b")
                             (plan-matrix-event 3 :up "a"))
                       (list (plan-matrix-event 0 :down "a")
                             (plan-matrix-event 1 :down "b")
                             (plan-matrix-event 2 :up "b")
                             (plan-matrix-event 3 :up "a"))))
           (result (ivory-key.simulate::simulate-events
                    (list (plan-matrix-isolated-interaction foreign-kind)) events
                    :latches '(("shift-latch" . "latched")))))
      (plan-matrix-assert-equal nil (plan-matrix-outputs result)
                                "foreign interruption cancels isolated candidate")
      (plan-matrix-assert-equal '(("shift-latch" . "latched"))
                                (ivory-key.simulate:simulation-result-latches result)
                                "cancelled isolated candidate leaves latch intact")
      (plan-matrix-assert-trace-responsibility
       result :cancel (list :isolated foreign-kind) "isolated"
       "foreign interruption cancellation"))))

(defun plan-matrix-release-order-interaction ()
  (ivory-key.simulate::make-sim-interaction
   :name "release-order" :participants '("a" "b")
   :cases
   (list
    (ivory-key.simulate::make-sim-case
     :name "a-first"
     :pattern (ivory-key.simulate::sequence-pattern
               (ivory-key.simulate::down-pattern "a")
               (ivory-key.simulate::down-pattern "b")
               (ivory-key.simulate::up-pattern "a")
               (ivory-key.simulate::up-pattern "b"))
     :actions (list (ivory-key.simulate::emit-action :a-first)))
    (ivory-key.simulate::make-sim-case
     :name "b-first"
     :pattern (ivory-key.simulate::sequence-pattern
               (ivory-key.simulate::down-pattern "a")
               (ivory-key.simulate::down-pattern "b")
               (ivory-key.simulate::up-pattern "b")
               (ivory-key.simulate::up-pattern "a"))
     :actions (list (ivory-key.simulate::emit-action :b-first))))))

(deftest simulation-plan-matrix-both-release-orders-and-rolling-sequence
  (dolist (fixture
           (list
            (list "a-first"
                  (list (plan-matrix-event 0 :down "a")
                        (plan-matrix-event 1 :down "b")
                        (plan-matrix-event 2 :up "a")
                        (plan-matrix-event 3 :up "b"))
                  :a-first)
            (list "b-first"
                  (list (plan-matrix-event 0 :down "a")
                        (plan-matrix-event 1 :down "b")
                        (plan-matrix-event 2 :up "b")
                        (plan-matrix-event 3 :up "a"))
                  :b-first)))
    (destructuring-bind (case events output) fixture
      (let ((result (ivory-key.simulate::simulate-events
                     (list (plan-matrix-release-order-interaction)) events)))
        (plan-matrix-assert-equal (list output) (plan-matrix-outputs result)
                                  "release order remains observable")
        (plan-matrix-assert-trace-responsibility
         result :commit "release-order" case "release-order commitment"))))
  (let* ((roll
           (ivory-key.simulate::make-sim-interaction
            :name "roll" :participants '("a" "b")
            :cases
            (list
             (ivory-key.simulate::make-sim-case
              :name "rolling-a-b"
              :pattern (ivory-key.simulate::sequence-pattern
                        (ivory-key.simulate::down-pattern "a")
                        (ivory-key.simulate::up-pattern "a")
                        (ivory-key.simulate::down-pattern "b")
                        (ivory-key.simulate::up-pattern "b"))
              :actions (list (ivory-key.simulate::emit-action :roll))))))
         (result (ivory-key.simulate::simulate-events
                  (list roll)
                  (list (plan-matrix-event 0 :down "a")
                        (plan-matrix-event 1 :up "a")
                        (plan-matrix-event 2 :down "b")
                        (plan-matrix-event 3 :up "b")))))
    (plan-matrix-assert-equal '(:roll) (plan-matrix-outputs result)
                              "one finite rolling sequence commits")
    (plan-matrix-assert-trace-responsibility
     result :commit "roll" "rolling-a-b" "rolling interaction")))

(deftest simulation-plan-matrix-refuses-unproved-model-longest-match-scheduling
  (let* ((candidate
           (ivory-key.model::make-interaction-candidate
            "short" (ivory-key.model::pattern-down "a") :when-matched
            (ivory-key.model:make-text-output "a")))
         (interaction
           (ivory-key.model::make-interaction
            "longest" '("a") (list candidate)
            :arbitration (ivory-key.model::longest-match-arbitration :deadline 100))))
    (plan-matrix-assert-equal
     :unsupported-arbitration
     (plan-matrix-simulation-feature
      (lambda () (ivory-key.simulate::compile-model-interaction interaction)))
     "model longest-match remains an explicit simulator refusal")))

;;; Effect timing, ownership, repetition, and malformed input ----------------

(defun plan-matrix-effect-interactions ()
  (let ((effect
          (ivory-key.simulate::make-sim-effect
           :name "reversible"
           :enter-actions (list (ivory-key.simulate::emit-action :enter))
           :exit-actions (list (ivory-key.simulate::emit-action :exit)))) )
    (list
     (ivory-key.simulate::make-sim-interaction
      :name "delayed" :participants '("d")
      :cases
      (list
       (ivory-key.simulate::make-sim-case
        :name "deadline-output"
        :pattern (ivory-key.simulate::deadline-pattern 100
                                                        :after-position "d"
                                                        :while-down "d")
        :actions (list (ivory-key.simulate::emit-action :delayed)))) )
     (ivory-key.simulate::make-sim-interaction
      :name "cumulative" :participants '("c")
      :cases
      (list
       (ivory-key.simulate::make-sim-case
        :name "immediate-and-held"
        :pattern (ivory-key.simulate::down-pattern "c")
        :enter-at (ivory-key.simulate::deadline-pattern 100
                                                         :after-position "c"
                                                         :while-down "c")
        :exit-at (ivory-key.simulate::up-pattern "c")
        :actions (list (ivory-key.simulate::emit-action :immediate))
        :effects (list effect)))))))

(deftest simulation-plan-matrix-delayed-cumulative-and-reversible-effects
  (let* ((result
           (ivory-key.simulate::simulate-events
            (plan-matrix-effect-interactions)
            (list (plan-matrix-event 0 :down "d")
                  (plan-matrix-event 0 :down "c")
                  (plan-matrix-event 150 :up "d")
                  (plan-matrix-event 150 :up "c"))))
         (effects (ivory-key.simulate:simulation-result-active-effects result)))
    (plan-matrix-assert-equal '(:immediate :enter :delayed :exit)
                              (plan-matrix-outputs result)
                              "delayed output differs from cumulative irreversible and reversible effects")
    (plan-matrix-assert-equal nil effects
                              "paired effect exits rather than remaining held")
    (plan-matrix-assert-trace-responsibility
     result :commit "delayed" "deadline-output" "delayed output commitment")
    (plan-matrix-assert-trace-responsibility
     result :effect-enter "cumulative" "immediate-and-held" "effect entry")
    (plan-matrix-assert-trace-responsibility
     result :effect-exit "cumulative" "immediate-and-held" "effect exit")))

(deftest simulation-plan-matrix-ownership-cancellation-and-latch-nonconsumption
  (let* ((short
           (ivory-key.simulate::make-sim-interaction
            :name "short" :participants '("a") :priority 2
            :cases
            (list (ivory-key.simulate::make-sim-case
                   :name "short-down"
                   :pattern (ivory-key.simulate::down-pattern "a")
                   :actions (list (ivory-key.simulate::emit-action :short))))))
         (long
           (ivory-key.simulate::make-sim-interaction
            :name "long" :participants '("a" "b") :priority 1
            :consulted-latches '("shift-latch")
            :cases
            (list (ivory-key.simulate::make-sim-case
                   :name "long-a-b"
                   :pattern (ivory-key.simulate::sequence-pattern
                             (ivory-key.simulate::down-pattern "a")
                             (ivory-key.simulate::down-pattern "b"))
                   :actions (list (ivory-key.simulate::emit-action :long))
                   :consulted-latches '("shift-latch")))))
         (result
           (ivory-key.simulate::simulate-events
            (list short long) (list (plan-matrix-event 0 :down "a"))
            :latches '(("shift-latch" . "latched"))))
         (candidates (ivory-key.simulate:simulation-result-candidates result))
         (short-candidate
           (find "short" candidates
                 :key (lambda (candidate)
                        (ivory-key.simulate::sim-interaction-name
                         (ivory-key.simulate::simulation-candidate-interaction candidate)))
                 :test #'equal))
         (long-candidate
           (find "long" candidates
                 :key (lambda (candidate)
                        (ivory-key.simulate::sim-interaction-name
                         (ivory-key.simulate::simulation-candidate-interaction candidate)))
                 :test #'equal)))
    (plan-matrix-assert-equal '(:short) (plan-matrix-outputs result)
                              "higher-priority short candidate is the only output")
    (plan-matrix-assert-equal :committed
                              (ivory-key.simulate::simulation-candidate-status short-candidate)
                              "winner commits")
    (plan-matrix-assert-equal '(0)
                              (ivory-key.simulate::simulation-candidate-claimed-event-indices
                               short-candidate)
                              "winner claims its participant event")
    (plan-matrix-assert-equal :cancelled
                              (ivory-key.simulate::simulation-candidate-status long-candidate)
                              "losing candidate is explicitly cancelled")
    (plan-matrix-assert-equal nil
                              (ivory-key.simulate::simulation-candidate-claimed-event-indices
                               long-candidate)
                              "cancelled candidate claims no events")
    (plan-matrix-assert-equal '(("shift-latch" . "latched"))
                              (ivory-key.simulate:simulation-result-latches result)
                              "uncommitted latch-dependent candidate consumes nothing")
    (plan-matrix-assert-trace-responsibility
     result :cancel "long" "long-a-b" "lost arbitration cancellation")))

(defun plan-matrix-repeat-interaction ()
  (ivory-key.simulate::make-sim-interaction
   :name "repeat" :participants '("a")
   :cases
   (list
    (ivory-key.simulate::make-sim-case
     :name "two-releases"
     :pattern (ivory-key.simulate::repeat-pattern
               (ivory-key.simulate::up-pattern "a") :at-least 2 :at-most 2)
     :actions (list (ivory-key.simulate::emit-action :repeat-two))))) )

(deftest simulation-plan-matrix-bounded-repeat-and-malformed-stream-recovery
  (let ((result
          (ivory-key.simulate::simulate-events
           (list (plan-matrix-repeat-interaction))
           (list (plan-matrix-event 0 :down "a")
                 (plan-matrix-event 1 :up "a")
                 (plan-matrix-event 2 :down "a")
                 (plan-matrix-event 3 :up "a")))))
    (plan-matrix-assert-equal '(:repeat-two) (plan-matrix-outputs result)
                              "bounded repetition commits only at its second release")
    (plan-matrix-assert-trace-responsibility
     result :commit "repeat" "two-releases" "bounded repeat commitment"))
  (let* ((effect
           (ivory-key.simulate::make-sim-effect
            :name "held"
            :enter-actions (list (ivory-key.simulate::emit-action :enter))
            :exit-actions (list (ivory-key.simulate::emit-action :exit))) )
         (interaction
           (ivory-key.simulate::make-sim-interaction
            :name "recover" :participants '("a")
            :cases
            (list (ivory-key.simulate::make-sim-case
                   :name "held-a"
                   :pattern (ivory-key.simulate::down-pattern "a")
                   :enter-at (ivory-key.simulate::down-pattern "a")
                   :exit-at (ivory-key.simulate::up-pattern "a")
                   :effects (list effect)))) )
         (machine (ivory-key.simulate::make-simulator :interactions (list interaction))))
    (ivory-key.simulate::simulator-feed-event machine (plan-matrix-event 0 :down "a"))
    (let ((trace-length (length (ivory-key.simulate::simulator-trace machine))))
      (handler-case
          (progn
            (ivory-key.simulate::simulator-feed-event machine (plan-matrix-event 1 :down "a"))
            (error "Expected malformed duplicate DOWN refusal."))
        (ivory-key.simulate::malformed-event-stream () t))
      (plan-matrix-assert-equal trace-length
                                (length (ivory-key.simulate::simulator-trace machine))
                                "rejected malformed event does not mutate the valid prefix"))
    (ivory-key.simulate::simulator-feed-event machine (plan-matrix-event 2 :up "a"))
    (let ((result (ivory-key.simulate::simulator-result machine)))
      (plan-matrix-assert-equal '(:enter :exit) (plan-matrix-outputs result)
                                "valid closing event clears held state after malformed refusal")
      (plan-matrix-assert-equal nil
                                (ivory-key.simulate:simulation-result-active-effects result)
                                "no stuck effect remains after recovery")
      (plan-matrix-assert-trace-responsibility
       result :effect-exit "recover" "held-a" "malformed-stream recovery exit"))))

;;; Dependency-scoped LATCHLATCH sequences ----------------------------------

(defun plan-matrix-latch-layout ()
  (let* ((shift-latch
           (ivory-key.model:make-context-axis
            "shift-latch" '("plain" "latch") :resolution :behavioral))
         (script (ivory-key.model:make-context-axis "script" '("roman" "greek")))
         (topology
           (ivory-key.model:make-topology
            "plan-matrix-latch-topology"
            (mapcar #'ivory-key.model:make-logical-position
                    '("latch-latch" "a" "greek" "t"))))
         (greek-behavior
           (ivory-key.model::make-axis-choice-behavior
            "shift-latch"
            (list
             (cons "plain" (ivory-key.model::make-axis-operation :set "script" "greek"))
             (cons "latch" (ivory-key.model::make-axis-operation :latch "script" "greek")))))
         (t-behavior
           (ivory-key.model::make-axis-choice-behavior
            "script"
            (list (cons "roman" (ivory-key.model:make-text-output "t"))
                  (cons "greek" (ivory-key.model:make-text-output "τ")))))
         (layout
           (ivory-key.model:make-layout
            "plan-matrix-latch" topology (list shift-latch script) nil
            :bindings
            (list
             (ivory-key.model:make-binding
              "latch-latch"
              (ivory-key.model::make-axis-operation :latch "shift-latch" "latch"))
             (ivory-key.model:make-binding "a" (ivory-key.model:make-text-output "a"))
             (ivory-key.model:make-binding "greek" greek-behavior)
             (ivory-key.model:make-binding "t" t-behavior)))))
    (ivory-key.model:normalize-layout layout)))

(defun plan-matrix-down-up-events (&rest positions)
  (loop for position in positions
        for time from 0 by 2
        append (list (plan-matrix-event time :down position)
                     (plan-matrix-event (1+ time) :up position))))

(deftest simulation-plan-matrix-latch-latch-greek-t-and-nonconsulting-a
  (let ((layout (plan-matrix-latch-layout)))
    (dolist (fixture
             (list
              (list '("latch-latch" "greek" "t") '((:text "τ"))
                    "LATCHLATCH GREEK T")
              (list '("latch-latch" "a" "greek" "t")
                    '((:text "a") (:text "τ"))
                    "LATCHLATCH A GREEK T")))
      (destructuring-bind (positions expected label) fixture
        (let ((result
                (ivory-key.simulate:simulate-normalized-layout-events
                 layout (apply #'plan-matrix-down-up-events positions))))
          (plan-matrix-assert-equal expected (plan-matrix-outputs result) label)
          (plan-matrix-assert-equal nil
                                    (ivory-key.simulate:simulation-result-latches result)
                                    "both successive consulting commitments consume their latches")
          (plan-matrix-assert-equal 2
                                    (length (plan-matrix-trace-entries result :latch-consumed))
                                    "exactly shift-latch then script latch are consumed")
          (plan-matrix-assert
           (some (lambda (entry)
                   (and (eq :latch-consumed
                            (ivory-key.simulate::simulation-trace-entry-kind entry))
                        (equal '("shift-latch" "latch" 1)
                               (ivory-key.simulate::simulation-trace-entry-details entry))))
                 (plan-matrix-trace result))
           "Greek consumes the shift-latch generation, not ordinary A"))))))
