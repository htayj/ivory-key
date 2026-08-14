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
            (ivory-key.model::pattern-down "a") :at-least 1 :at-most 2)
           (ivory-key.model::pattern-context-is "script" "greek"))))
    (dolist (pattern patterns)
      (compile-simulation-assert
       (typep (ivory-key.simulate::compile-model-temporal-pattern pattern)
              'ivory-key.simulate::event-pattern)
       "model pattern ~S should compile into simulator IR" pattern))))

(defun compile-simulation-context-interaction ()
  (let* ((candidate
           (ivory-key.model::make-interaction-candidate
            "greek-release"
            (ivory-key.model::pattern-conjunction
             (ivory-key.model::pattern-sequence
              (ivory-key.model::pattern-down "a")
              (ivory-key.model::pattern-up "a"))
             (ivory-key.model::pattern-context-is "script" "greek"))
            :when-matched
            (ivory-key.model::make-text-output "alpha")))
         (interaction
           (ivory-key.model::make-interaction
            "context-a" '("a") (list candidate))))
    (ivory-key.simulate::compile-model-interaction interaction)))

(deftest simulation-compile-context-is-uses-anchor-snapshot-and-latch-shadow
  (let* ((interaction (compile-simulation-context-interaction))
         (machine
           (ivory-key.simulate::make-simulator
            :interactions (list interaction)
            :axes '(("script" . "greek")))))
    (ivory-key.simulate::simulator-feed-event
     machine (compile-simulation-event 0 :down "a"))
    ;; Context predicates observe the dependency-scoped anchor snapshot, not
    ;; mutable commit-time state.
    (ivory-key.simulate::simulator-set-axis machine "script" "roman")
    (ivory-key.simulate::simulator-feed-event
     machine (compile-simulation-event 10 :up "a"))
    (let* ((result (ivory-key.simulate::simulator-result machine))
           (commit
             (find :commit (ivory-key.simulate::simulation-result-trace result)
                   :key #'ivory-key.simulate::simulation-trace-entry-kind)))
      (compile-simulation-assert-equal
       '((:text "alpha"))
       (ivory-key.simulate::simulation-result-outputs result)
       "CONTEXT-IS retains the anchor-down state")
      (compile-simulation-assert
       (search ":CONTEXT-IS"
               (prin1-to-string
                (ivory-key.simulate::simulation-trace-entry-provenance commit)))
       "CONTEXT-IS is retained in canonical commit provenance")))
  (let ((result
          (compile-simulation-result
           (list (compile-simulation-context-interaction))
           (list (compile-simulation-event 0 :down "a")
                 (compile-simulation-event 10 :up "a"))
           :axes '(("script" . "roman"))
           :latches '(("script" . "greek")))))
    (compile-simulation-assert-equal
     '((:text "alpha"))
     (ivory-key.simulate::simulation-result-outputs result)
     "a captured latch shadows the ordinary axis value for CONTEXT-IS")
    (compile-simulation-assert-equal
     nil (ivory-key.simulate::simulation-result-latches result)
     "the committed contextual candidate consumes its consulted latch")))

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

(defun compile-simulation-capture-release-fixture ()
  (let* ((effects
           (ivory-key.model::make-interaction-effects
            :while (list (ivory-key.model::make-held-modifier-operation "super"))))
         (candidate
           (ivory-key.model::make-interaction-candidate
            "foreign-release"
            (ivory-key.model::pattern-sequence
             (ivory-key.model::pattern-down "a")
             (ivory-key.model::pattern-capture
              "foreign"
              (ivory-key.model::pattern-down
               (ivory-key.model::other-than-selector "a")))
             (ivory-key.model::pattern-up
              (ivory-key.model::captured-position-selector "foreign")))
            :when-matched (ivory-key.model::make-no-output-behavior)
            :effects effects :effect-start :on-commit))
         (interaction
           (ivory-key.model::make-interaction
            "foreign-release" '("a") (list candidate)
            :observe :any-position :anchor "a")))
    (ivory-key.simulate::compile-model-interaction interaction)))

(deftest simulation-compile-capture-is-immutable-and-effect-starts-at-commit
  ;; The held modifier cannot acquire merely because the anchor and foreign
  ;; DOWNs matched; it begins only when the captured physical key releases.
  (let ((partial
          (compile-simulation-result
           (list (compile-simulation-capture-release-fixture))
           (list (compile-simulation-event 0 :down "a")
                 (compile-simulation-event 1 :down "b")
                 (compile-simulation-event 2 :down "c")
                 (compile-simulation-event 3 :up "c")))))
    (compile-simulation-assert-equal
     nil (ivory-key.simulate::simulation-result-outputs partial)
     "on-commit effect is not speculative before the captured release"))
  (let* ((result
           (compile-simulation-result
            (list (compile-simulation-capture-release-fixture))
            (list (compile-simulation-event 0 :down "a")
                  (compile-simulation-event 1 :down "b")
                  (compile-simulation-event 2 :down "c")
                  (compile-simulation-event 3 :up "c")
                  (compile-simulation-event 4 :up "b")
                  (compile-simulation-event 5 :up "a"))))
         (commit
           (find :commit (ivory-key.simulate::simulation-result-trace result)
                 :key #'ivory-key.simulate::simulation-trace-entry-kind))
         (provenance (ivory-key.simulate::simulation-trace-entry-provenance commit))
         (dump (ivory-key.simulate::simulation-result-dump-string result)))
    (compile-simulation-assert-equal
     '((:modifier :press "super") (:modifier :release "super"))
     (ivory-key.simulate::simulation-result-outputs result)
     "captured foreign release commits then participant release ends the owner")
    ;; C's early release cannot steal the immutable first binding for B.
    (compile-simulation-assert-equal
     '(("foreign" :position "b" :down-index 1))
     (getf provenance :captures)
     "capture provenance records the one immutable physical binding")
    (compile-simulation-assert
     (search "(:capture \"foreign\"" dump)
     "capture source provenance remains in the closed deterministic dump vocabulary")))

(deftest simulation-compile-on-commit-cancels-at-owner-up-before-foreign-release
  (let* ((result
           (compile-simulation-result
            (list (compile-simulation-capture-release-fixture))
            (list (compile-simulation-event 0 :down "a")
                  (compile-simulation-event 1 :down "b")
                  (compile-simulation-event 2 :up "a")
                  (compile-simulation-event 3 :up "b"))))
         (cancel (find :cancel (ivory-key.simulate::simulation-result-trace result)
                       :key #'ivory-key.simulate::simulation-trace-entry-kind))
         (provenance (ivory-key.simulate::simulation-trace-entry-provenance cancel)))
    (compile-simulation-assert-equal
     nil (ivory-key.simulate::simulation-result-outputs result)
     "owner release before the captured foreign release cannot create a zero-lifetime press")
    (compile-simulation-assert-equal
     nil (ivory-key.simulate::simulation-result-active-effects result)
     "a cancelled on-commit candidate has no stuck effect owner")
    (compile-simulation-assert-equal
     :participant-exited-before-commit
     (ivory-key.simulate::simulation-trace-entry-details cancel)
     "the cancellation explains the terminal owner boundary")
    (compile-simulation-assert-equal
     :cancelled (getf provenance :candidate-transition)
     "the trace records cancellation rather than a later commitment")
    (compile-simulation-assert-equal
     '(:event :up "a") (getf provenance :source-pattern)
     "cancellation provenance names the participant exit boundary")))

(deftest simulation-compile-on-commit-keeps-deadline-before-equal-time-owner-up
  (let* ((effects
           (ivory-key.model::make-interaction-effects
            :while (list (ivory-key.model::make-held-modifier-operation "super"))))
         (candidate
           (ivory-key.model::make-interaction-candidate
            "deadline-hold"
            (ivory-key.model::pattern-deadline 100 :after "a" :while-down "a")
            :when-matched (ivory-key.model::make-no-output-behavior)
            :effects effects :effect-start :on-commit))
         (interaction (ivory-key.model::make-interaction "deadline-hold" '("a")
                                                        (list candidate)))
         (result
           (compile-simulation-result
            (list (ivory-key.simulate::compile-model-interaction interaction))
            (list (compile-simulation-event 0 :down "a")
                  (compile-simulation-event 100 :up "a")))))
    (compile-simulation-assert-equal
     '((:modifier :press "super") (:modifier :release "super"))
     (ivory-key.simulate::simulation-result-outputs result)
     "the generated deadline commits before its equal-time physical owner release")))

;;; Proposed modern Manna release-trigger fixture ---------------------------

(defun modern-release-trigger-source-layout ()
  "Decode the explicit proposed source fixture without selecting any backend."
  (interaction-template-decoder-layout +manna-release-trigger-v1-source+))

(defun modern-release-trigger-source-interaction (name)
  (let* ((layout (modern-release-trigger-source-layout))
         (normalized (ivory-key.model:normalize-layout layout))
         (interaction
           (find name (ivory-key.model:normalized-layout-interactions normalized)
                 :test #'ivory-key.model:identifier=
                 :key #'ivory-key.model:normalized-interaction-name)))
    (values (ivory-key.simulate::compile-normalized-interaction interaction)
            (ivory-key.simulate::model-layout-simulator-axes layout))))

(defun modern-release-trigger-source-result (interaction-names events &key until)
  (let ((interactions nil) (axes nil))
    (dolist (name interaction-names)
      (multiple-value-bind (interaction defaults)
          (modern-release-trigger-source-interaction name)
        (push interaction interactions)
        (unless axes (setf axes defaults))))
    (ivory-key.simulate::simulate-events (nreverse interactions) events
                                         :axes axes :until until)))

(defun modern-release-trigger-source-candidate (result interaction-name case-name)
  (find-if
   (lambda (candidate)
     (and (string= interaction-name
                   (ivory-key.simulate::sim-interaction-name
                    (ivory-key.simulate::simulation-candidate-interaction candidate)))
          (string= case-name
                   (ivory-key.simulate::sim-case-name
                    (ivory-key.simulate::simulation-candidate-case candidate)))))
   (ivory-key.simulate:simulation-result-candidates result)))

(defun modern-release-trigger-physical-positions (result)
  (mapcar (lambda (entry)
            (ivory-key.simulate::timed-event-position
             (ivory-key.simulate::simulation-trace-entry-event entry)))
          (remove-if-not
           (lambda (entry)
             (eq :event (ivory-key.simulate::simulation-trace-entry-kind entry)))
           (ivory-key.simulate::simulation-result-trace result))))

(deftest simulation-compile-source-modern-release-trigger-v1-triad
  "The proposed no-delay profile has three concrete source candidates only.

This proves the chosen abstract event contract, not Kanata or historical Manna
equivalence.  In particular, the observed foreign key is not claimed by the
interaction and no synthetic replay event is introduced."
  ;; A short owner press reaches only TAP; neither on-commit hold acquires.
  (let* ((result
           (modern-release-trigger-source-result
            '("tap-hold-super-semicolon")
            (list (compile-simulation-event 0 :down "semicolon")
                  (compile-simulation-event 199 :up "semicolon"))))
         (tap (modern-release-trigger-source-candidate
               result "tap-hold-super-semicolon" "tap")))
    (compile-simulation-assert-equal
     '((:named-key "semicolon"))
     (ivory-key.simulate::simulation-result-outputs result)
     "the sub-deadline release commits the tap candidate")
    (compile-simulation-assert-equal
     :committed (ivory-key.simulate::simulation-candidate-status tap)
     "the source tap candidate is the deterministic winner")
    (compile-simulation-assert-equal
     nil (ivory-key.simulate:simulation-result-active-effects result)
     "a tap never leaves a held modifier owner"))
  ;; The deadline is generated before an equal-time physical owner release.
  (let* ((result
           (modern-release-trigger-source-result
            '("tap-hold-super-semicolon")
            (list (compile-simulation-event 0 :down "semicolon")
                  (compile-simulation-event 200 :up "semicolon"))))
         (trace (ivory-key.simulate::simulation-result-trace result))
         (timeout (modern-release-trigger-source-candidate
                   result "tap-hold-super-semicolon" "hold-timeout")))
    (compile-simulation-assert-equal
     '((:modifier :press "super") (:modifier :release "super"))
     (ivory-key.simulate::simulation-result-outputs result)
     "the deadline hold starts then releases at its owner's same-time UP")
    (compile-simulation-assert-equal
     :committed (ivory-key.simulate::simulation-candidate-status timeout)
     "the fixed priority makes timeout win at its own boundary")
    (compile-simulation-assert
     (< (position :deadline trace
                  :key #'ivory-key.simulate::simulation-trace-entry-kind)
        (position-if
         (lambda (entry)
           (let ((event (ivory-key.simulate::simulation-trace-entry-event entry)))
             (and event (eq :up (ivory-key.simulate::timed-event-kind event))
                  (string= "semicolon" (ivory-key.simulate::timed-event-position event)))))
         trace))
     "a generated deadline precedes the equal-time physical release"))
  ;; The first eligible foreign DOWN is immutable.  Its UP commits the hold,
  ;; but the foreign event remains observed/unowned and is never replayed.
  (let* ((partial
           (modern-release-trigger-source-result
            '("tap-hold-super-semicolon")
            (list (compile-simulation-event 0 :down "semicolon")
                  (compile-simulation-event 1 :down "b")
                  (compile-simulation-event 2 :down "c")
                  (compile-simulation-event 3 :up "c")
                  (compile-simulation-event 4 :up "b"))))
         (foreign (modern-release-trigger-source-candidate
                   partial "tap-hold-super-semicolon" "hold-after-foreign-release"))
         (commit
           (find-if
            (lambda (entry)
              (and (eq :commit (ivory-key.simulate::simulation-trace-entry-kind entry))
                   (eq foreign (ivory-key.simulate::simulation-trace-entry-candidate entry))))
            (ivory-key.simulate::simulation-result-trace partial))))
    (compile-simulation-assert-equal
     '((:modifier :press "super"))
     (ivory-key.simulate::simulation-result-outputs partial)
     "foreign release starts the non-speculative hold while its owner remains down")
    (compile-simulation-assert-equal
     '("semicolon" "b" "c" "c" "b")
     (modern-release-trigger-physical-positions partial)
     "foreign physical events preserve their supplied order without delayed replay")
    (compile-simulation-assert-equal
     '(0) (ivory-key.simulate::simulation-candidate-claimed-event-indices foreign)
     "the committed interaction owns only its participant, not the foreign key")
    (compile-simulation-assert-equal
     '(("foreign" :position "b" :down-index 1))
     (getf (ivory-key.simulate::simulation-trace-entry-provenance commit) :captures)
     "capture retains the first foreign position and physical down index")
    (compile-simulation-assert
     (ivory-key.simulate:simulation-result-active-effects partial)
     "the foreign-release hold remains active until its own participant UP"))
  ;; Releasing the owner first selects TAP and cancels the uncommitted foreign
  ;; candidate before it can create a zero-lifetime modifier press.
  (let* ((result
           (modern-release-trigger-source-result
            '("tap-hold-super-semicolon")
            (list (compile-simulation-event 0 :down "semicolon")
                  (compile-simulation-event 1 :down "b")
                  (compile-simulation-event 2 :up "semicolon")
                  (compile-simulation-event 3 :up "b"))))
         (foreign (modern-release-trigger-source-candidate
                   result "tap-hold-super-semicolon" "hold-after-foreign-release")))
    (compile-simulation-assert-equal
     '((:named-key "semicolon"))
     (ivory-key.simulate::simulation-result-outputs result)
     "early owner UP falls back to tap rather than a delayed foreign hold")
    (compile-simulation-assert-equal
     :cancelled (ivory-key.simulate::simulation-candidate-status foreign)
     "the losing captured candidate has a terminal cancellation")
    (compile-simulation-assert-equal
     nil (ivory-key.simulate:simulation-result-active-effects result)
     "early owner UP cannot leave a stuck hold")))

(deftest simulation-whole-layout-modern-release-trigger-does-not-delay-foreign-binding
  "The proposed modern route dispatches an ordinary foreign key immediately."
  (let* ((layout (modern-release-trigger-source-layout))
         (result
           (ivory-key.simulate:simulate-normalized-layout-events
            (ivory-key.model:normalize-layout layout)
            (list (compile-simulation-event 0 :down "semicolon")
                  (compile-simulation-event 1 :down "b")
                  (compile-simulation-event 2 :up "semicolon")
                  (compile-simulation-event 3 :up "b"))))
         (actions
           (remove-if-not
            (lambda (entry)
              (eq :action
                  (ivory-key.simulate:simulation-trace-entry-kind entry)))
            (ivory-key.simulate:simulation-result-trace result))))
    (compile-simulation-assert-equal
     '((:text "b") (:named-key "semicolon"))
     (ivory-key.simulate:simulation-result-outputs result)
     "foreign B dispatch precedes the later owner-UP tap commitment")
    (compile-simulation-assert-equal
     '(1 2)
     (mapcar #'ivory-key.simulate:simulation-trace-entry-time actions)
     "the ordinary foreign action remains at physical DOWN with no replay")))

(deftest simulation-compile-source-modern-release-trigger-v1-complete-inventory
  "Every frozen 14+2 row has its literal tap and closed deadline hold trace.

This remains a reference contract for the unselected proposed route, not a
claim that the checked-in Manna layout or a backend realizes these rows."
  (dolist (row +manna-release-trigger-v1-inventory+)
    (destructuring-bind (name alias position tap timeout kind identity &optional state) row
      (declare (ignore alias))
      (let ((tap-result
              (modern-release-trigger-source-result
               (list name)
               (list (compile-simulation-event 0 :down position)
                     (compile-simulation-event (1- timeout) :up position)))))
        (compile-simulation-assert-equal
         (list (list :named-key tap))
         (ivory-key.simulate::simulation-result-outputs tap-result)
         (format nil "~A preserves its exact target-neutral tap" name)))
      (let* ((held-result
               (modern-release-trigger-source-result
                (list name) (list (compile-simulation-event 0 :down position))
                :until timeout))
             (timeout-candidate
               (modern-release-trigger-source-candidate held-result name "hold-timeout")))
        (compile-simulation-assert-equal
         :committed (ivory-key.simulate::simulation-candidate-status timeout-candidate)
         (format nil "~A commits at its literal deadline" name))
        (ecase kind
          (:modifier
           (compile-simulation-assert-equal
            (list (list :modifier :press identity))
            (ivory-key.simulate::simulation-result-outputs held-result)
            (format nil "~A holds semantic modifier ~A" name identity)))
          (:axis
           (compile-simulation-assert-equal
            state
            (cdr (assoc identity (ivory-key.simulate:simulation-result-axes held-result)
                        :test #'string=))
            (format nil "~A holds axis ~A at ~A" name identity state))))))))

(deftest simulation-compile-source-modern-release-trigger-v1-shared-owner-families
  "Each two-owner frozen family remains held after either first release and clears last."
  (dolist (fixture
           '((:axis "case" "shifted" "plain"
              "tap-hold-case-f" "f" "tap-hold-case-j" "j")
             (:modifier "control" nil nil
              "tap-hold-control-d" "d" "tap-hold-control-k" "k")
             (:modifier "meta" nil nil
              "tap-hold-meta-s" "s" "tap-hold-meta-l" "l")
             (:modifier "super" nil nil
              "tap-hold-super-semicolon" "semicolon" "tap-hold-super-a" "a")
             (:modifier "hyper" nil nil
              "tap-hold-hyper-escape" "escape" "tap-hold-hyper-apostrophe" "apostrophe")
             (:modifier "alt" nil nil
              "tap-hold-alt-backspace" "backspace" "tap-hold-alt-space" "space")))
    (destructuring-bind (kind identity active default first-name first-position second-name second-position)
        fixture
      (dolist (release-order
               (list (list first-name first-position second-name second-position)
                     (list second-name second-position first-name first-position)))
        (destructuring-bind (released-name released-position retained-name retained-position)
            release-order
          (declare (ignore released-name retained-name))
          (let ((first-release
                  (modern-release-trigger-source-result
                   (list first-name second-name)
                   (list (compile-simulation-event 0 :down first-position)
                         (compile-simulation-event 0 :down second-position)
                         (compile-simulation-event 260 :up released-position)))))
            (ecase kind
              (:modifier
               (compile-simulation-assert-equal
                (list (list :modifier :press identity))
                (ivory-key.simulate::simulation-result-outputs first-release)
                (format nil "first ~A owner release cannot release the second (~A first)"
                        identity released-position)))
              (:axis
               (compile-simulation-assert-equal
                active
                (cdr (assoc identity (ivory-key.simulate:simulation-result-axes first-release)
                            :test #'string=))
                (format nil "first ~A axis owner release retains the second (~A first)"
                        identity released-position)))))
          (let ((final-release
                  (modern-release-trigger-source-result
                   (list first-name second-name)
                   (list (compile-simulation-event 0 :down first-position)
                         (compile-simulation-event 0 :down second-position)
                         (compile-simulation-event 260 :up released-position)
                         (compile-simulation-event 270 :up retained-position)))))
            (ecase kind
              (:modifier
               (compile-simulation-assert-equal
                (list (list :modifier :press identity) (list :modifier :release identity))
                (ivory-key.simulate::simulation-result-outputs final-release)
                (format nil "final ~A owner release is exact (~A last)"
                        identity retained-position)))
              (:axis
               (compile-simulation-assert-equal
                default
                (cdr (assoc identity (ivory-key.simulate:simulation-result-axes final-release)
                            :test #'string=))
                (format nil "final ~A axis owner release restores default (~A last)"
                        identity retained-position))))))))))

(deftest simulation-whole-layout-modern-release-trigger-foreign-timed-interaction-is-unowned
  "A captured foreign interaction runs its own no-delay candidate lifecycle.

The proposed fixture is intentionally whole-layout here: D is another member
of the frozen 14+2 inventory, not an ordinary binding.  Its tap resolves on
its own UP after the outer owner has released.  The outer uncommitted
foreign-release candidate is terminally cancelled at that owner UP, so this
test deliberately avoids assigning an unselected ordering policy to a shared
foreign-UP commitment boundary.  Neither candidate claims, buffers, or
replays the other interaction."
  (let* ((layout (modern-release-trigger-source-layout))
         (result
           (ivory-key.simulate:simulate-normalized-layout-events
            (ivory-key.model:normalize-layout layout)
            (list (compile-simulation-event 0 :down "semicolon")
                  (compile-simulation-event 1 :down "d")
                  (compile-simulation-event 2 :up "semicolon")
                  (compile-simulation-event 3 :up "d"))))
         (d-tap (modern-release-trigger-source-candidate
                 result "tap-hold-control-d" "tap"))
         (semicolon-foreign (modern-release-trigger-source-candidate
                             result "tap-hold-super-semicolon"
                             "hold-after-foreign-release")))
    (compile-simulation-assert-equal
     '((:named-key "semicolon") (:named-key "d"))
     (ivory-key.simulate::simulation-result-outputs result)
     "both timed interactions tap on their own physical UP boundaries")
    (compile-simulation-assert-equal
     '(:committed :cancelled)
     (list (ivory-key.simulate::simulation-candidate-status d-tap)
           (ivory-key.simulate::simulation-candidate-status semicolon-foreign))
     "the outer release terminally cancels its still-uncommitted foreign hold")
    (compile-simulation-assert-equal
     '((1 3) nil)
     (list (ivory-key.simulate::simulation-candidate-claimed-event-indices d-tap)
           (ivory-key.simulate::simulation-candidate-claimed-event-indices semicolon-foreign))
     "the timed foreign candidate owns its own DOWN/UP; the cancelled observer owns none")
    (compile-simulation-assert-equal
     '("semicolon" "d" "semicolon" "d")
     (modern-release-trigger-physical-positions result)
     "the foreign timed interaction is observed in supplied physical order")
    (compile-simulation-assert-equal
     nil (ivory-key.simulate:simulation-result-active-effects result)
     "both owner releases leave no held contribution")))

(deftest simulation-compile-source-modern-release-trigger-v1-selector-capture-and-release
  "Script and plane retain captured foreign provenance and self-release."
  (dolist (fixture
           '(("tap-hold-script-delete" "delete" "script" "greek" "roman")
             ("tap-hold-plane-enter" "return" "plane" "top" "base")))
    (destructuring-bind (name position axis active default) fixture
      (let* ((held
               (modern-release-trigger-source-result
                (list name)
                (list (compile-simulation-event 0 :down position)
                      (compile-simulation-event 1 :down "b")
                      (compile-simulation-event 2 :up "b"))))
             (foreign (modern-release-trigger-source-candidate
                       held name "hold-after-foreign-release"))
             (commit
               (find-if
                (lambda (entry)
                  (and (eq :commit (ivory-key.simulate::simulation-trace-entry-kind entry))
                       (eq foreign
                           (ivory-key.simulate::simulation-trace-entry-candidate entry))))
                (ivory-key.simulate::simulation-result-trace held))))
        (compile-simulation-assert-equal
         :committed (ivory-key.simulate::simulation-candidate-status foreign)
         (format nil "~A commits only on its captured foreign UP" name))
        (compile-simulation-assert-equal
         '(("foreign" :position "b" :down-index 1))
         (getf (ivory-key.simulate::simulation-trace-entry-provenance commit) :captures)
         (format nil "~A exposes its immutable foreign capture" name))
        (compile-simulation-assert-equal
         active
         (cdr (assoc axis (ivory-key.simulate:simulation-result-axes held)
                     :test #'string=))
         (format nil "~A stays held until its owner UP" name)))
      (let ((released
              (modern-release-trigger-source-result
               (list name)
               (list (compile-simulation-event 0 :down position)
                     (compile-simulation-event 1 :down "b")
                     (compile-simulation-event 2 :up "b")
                     (compile-simulation-event 3 :up position)))))
        (compile-simulation-assert-equal
         default
         (cdr (assoc axis (ivory-key.simulate:simulation-result-axes released)
                     :test #'string=))
         (format nil "~A owner release restores its declared default" name))))))

(deftest simulation-compile-source-modern-release-trigger-v1-250-and-function-owners
  ;; The second admitted timer pair keeps the same deadline-before-UP rule.
  (dolist (fixture '((249 ((:named-key "a")))
                     (250 ((:modifier :press "super")
                           (:modifier :release "super")))))
    (destructuring-bind (release expected) fixture
      (let ((result
              (modern-release-trigger-source-result
               '("tap-hold-super-a")
               (list (compile-simulation-event 0 :down "a")
                     (compile-simulation-event release :up "a")))))
        (compile-simulation-assert-equal
         expected (ivory-key.simulate::simulation-result-outputs result)
         "the explicit 250/250 fixture preserves its boundary"))))
  ;; End and Page-Down are independent owners of the same abstract function
  ;; state.  Their state has no backend token and remains active after either
  ;; single owner leaves, then restores the default after the final release.
  (flet ((function-result (events &key until)
           (modern-release-trigger-source-result
            '("tap-hold-function-end" "tap-hold-function-pgdn") events :until until)))
    (let ((both-held
            (function-result
             (list (compile-simulation-event 0 :down "end")
                  (compile-simulation-event 0 :down "pgdn")) :until 200)))
      (compile-simulation-assert-equal
       "active"
       (cdr (assoc "function" (ivory-key.simulate:simulation-result-axes both-held)
                   :test #'string=))
       "both committed function holds contribute the same effective state"))
    (let ((one-held
            (function-result
             (list (compile-simulation-event 0 :down "end")
                  (compile-simulation-event 0 :down "pgdn")
                   (compile-simulation-event 210 :up "end")))))
      (compile-simulation-assert-equal
       "active"
       (cdr (assoc "function" (ivory-key.simulate:simulation-result-axes one-held)
                   :test #'string=))
       "releasing the first function owner cannot clear the second"))
    (let ((released
            (function-result
             (list (compile-simulation-event 0 :down "end")
                  (compile-simulation-event 0 :down "pgdn")
                   (compile-simulation-event 210 :up "end")
                  (compile-simulation-event 220 :up "pgdn")))))
      (compile-simulation-assert-equal
       "inactive"
       (cdr (assoc "function" (ivory-key.simulate:simulation-result-axes released)
                   :test #'string=))
       "the final function owner release restores the declared default"))
    ;; The reverse release order is separately observable: Page-Down may
    ;; leave first without clearing End's still-owned function contribution.
    (let ((one-held
            (function-result
             (list (compile-simulation-event 0 :down "end")
                  (compile-simulation-event 0 :down "pgdn")
                  (compile-simulation-event 210 :up "pgdn")))))
      (compile-simulation-assert-equal
       "active"
       (cdr (assoc "function" (ivory-key.simulate:simulation-result-axes one-held)
                   :test #'string=))
       "releasing Page-Down first cannot clear End's function hold"))
    (let ((released
            (function-result
             (list (compile-simulation-event 0 :down "end")
                  (compile-simulation-event 0 :down "pgdn")
                  (compile-simulation-event 210 :up "pgdn")
                   (compile-simulation-event 220 :up "end")))))
      (compile-simulation-assert-equal
       "inactive"
       (cdr (assoc "function" (ivory-key.simulate:simulation-result-axes released)
                   :test #'string=))
       "End's final release restores the declared function default"))))
