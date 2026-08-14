;;;; SPDX-License-Identifier: GPL-3.0-or-later
;;;; Reference simulator temporal-interaction matrix.

(in-package #:ivory-key.tests)

;;; These helpers intentionally stay dependency-free, matching the project's
;;; hermetic test-system contract.

(defun simulation-assert (truth control &rest arguments)
  (unless truth
    (error (apply #'format nil control arguments))))

(defun simulation-assert-equal (expected actual label)
  (simulation-assert (equal expected actual)
                     "~A: expected ~S, got ~S" label expected actual))

(defun sim-event (time kind position)
  (ivory-key.simulate::make-timed-event time kind position))

(defun simulator-outputs-for (interactions events &key latches until)
  (ivory-key.simulate::simulation-result-outputs
   (ivory-key.simulate::simulate-events interactions events
                                        :latches latches :until until)))

(defun make-tap-or-hold-interaction ()
  (ivory-key.simulate::make-sim-interaction
   :name :tap-or-hold
   :participants '(:a)
   :cases
   (list
    (ivory-key.simulate::make-sim-case
     :name :tap
     :priority 1
     :pattern
     (ivory-key.simulate::and-pattern
      (ivory-key.simulate::sequence-pattern
       (ivory-key.simulate::down-pattern :a)
       (ivory-key.simulate::up-pattern :a))
      (ivory-key.simulate::duration-pattern :a :less-than 200))
     :actions (list (ivory-key.simulate::emit-action :tap)))
    (ivory-key.simulate::make-sim-case
     :name :hold
     :priority 2
     :pattern (ivory-key.simulate::deadline-pattern 200
                                                     :after-position :a
                                                     :while-down :a)
     :actions (list (ivory-key.simulate::emit-action :hold))))))

(defun test-tap-versus-hold-boundary ()
  (let ((interaction (make-tap-or-hold-interaction)))
    (simulation-assert-equal
     '(:tap)
     (simulator-outputs-for (list interaction)
                            (list (sim-event 0 :down :a) (sim-event 199 :up :a)))
     "release before hold deadline is a tap")
    ;; A deadline at an equal timestamp is processed before the physical up.
    (simulation-assert-equal
     '(:hold)
     (simulator-outputs-for (list interaction)
                            (list (sim-event 0 :down :a) (sim-event 200 :up :a)))
     "release exactly at hold deadline is a hold")))

(defun make-staged-duration-interaction ()
  (ivory-key.simulate::make-sim-interaction
   :name :staged-duration
   :participants '(:a)
   :cases
   (list
    (ivory-key.simulate::make-sim-case
     :name :short :priority 1
     :pattern (ivory-key.simulate::duration-pattern :a :less-than 1000)
     :actions (list (ivory-key.simulate::emit-action :short)))
    (ivory-key.simulate::make-sim-case
     :name :medium :priority 2
     :pattern (ivory-key.simulate::duration-pattern :a :at-least 1000 :less-than 2000)
     :actions (list (ivory-key.simulate::emit-action :medium)))
    (ivory-key.simulate::make-sim-case
     :name :long :priority 3
     :pattern (ivory-key.simulate::deadline-pattern 2000
                                                     :after-position :a
                                                     :while-down :a)
     :actions (list (ivory-key.simulate::emit-action :long))))))

(defun staged-duration-output (release-time)
  (simulator-outputs-for
   (list (make-staged-duration-interaction))
   (list (sim-event 0 :down :a) (sim-event release-time :up :a))))

(defun test-one-and-two-second-duration-regions ()
  (simulation-assert-equal '(:short) (staged-duration-output 999)
                           "sub-one-second stage")
  (simulation-assert-equal '(:medium) (staged-duration-output 1000)
                           "one-second boundary begins medium stage")
  (simulation-assert-equal '(:medium) (staged-duration-output 1999)
                           "medium stage remains below two seconds")
  (simulation-assert-equal '(:long) (staged-duration-output 2000)
                           "two-second deadline commits long stage"))

(defun make-isolated-a-interaction (&key consulted-latches)
  (ivory-key.simulate::make-sim-interaction
   :name :isolated-a
   :participants '(:a)
   :consulted-latches consulted-latches
   :cases
   (list
    (ivory-key.simulate::make-sim-case
     :name :isolated-tap
     :pattern
     (ivory-key.simulate::and-pattern
      (ivory-key.simulate::sequence-pattern
       (ivory-key.simulate::down-pattern :a)
       (ivory-key.simulate::up-pattern :a))
      (ivory-key.simulate::without-pattern
       (ivory-key.simulate::down-pattern '(:other-than :a))
       :between (list (ivory-key.simulate::down-pattern :a)
                      (ivory-key.simulate::up-pattern :a))))
     :actions (list (ivory-key.simulate::emit-action :isolated))))))

(defun test-isolated-release ()
  (simulation-assert-equal
   '(:isolated)
   (simulator-outputs-for (list (make-isolated-a-interaction))
                          (list (sim-event 0 :down :a) (sim-event 50 :up :a)))
   "isolated A release commits"))

(defun make-release-order-interaction ()
  (ivory-key.simulate::make-sim-interaction
   :name :ab-release-order
   :participants '(:a :b)
   :cases
   (list
    (ivory-key.simulate::make-sim-case
     :name :a-first :priority 2
     :pattern (ivory-key.simulate::sequence-pattern
               (ivory-key.simulate::down-pattern :a)
               (ivory-key.simulate::down-pattern :b)
               (ivory-key.simulate::up-pattern :a)
               (ivory-key.simulate::up-pattern :b))
     :actions (list (ivory-key.simulate::emit-action :a-first)))
    (ivory-key.simulate::make-sim-case
     :name :b-first :priority 1
     :pattern (ivory-key.simulate::sequence-pattern
               (ivory-key.simulate::down-pattern :a)
               (ivory-key.simulate::down-pattern :b)
               (ivory-key.simulate::up-pattern :b)
               (ivory-key.simulate::up-pattern :a))
     :actions (list (ivory-key.simulate::emit-action :b-first))))))

(defun test-both-release-orders ()
  (let ((interaction (make-release-order-interaction)))
    (simulation-assert-equal
     '(:a-first)
     (simulator-outputs-for (list interaction)
                            (list (sim-event 0 :down :a) (sim-event 10 :down :b)
                                  (sim-event 20 :up :a) (sim-event 30 :up :b)))
     "A then B release order")
    (simulation-assert-equal
     '(:b-first)
     (simulator-outputs-for (list interaction)
                            (list (sim-event 0 :down :a) (sim-event 10 :down :b)
                                  (sim-event 20 :up :b) (sim-event 30 :up :a)))
     "B then A release order")))

(defun test-finite-pattern-algebra ()
  (let ((combo
          (ivory-key.simulate::make-sim-interaction
           :name :combo :participants '(:a :b)
           :cases
           (list
            (ivory-key.simulate::make-sim-case
             :name :combo
             :pattern
             (ivory-key.simulate::and-pattern
              (ivory-key.simulate::all-pattern
               (ivory-key.simulate::down-pattern :a)
               (ivory-key.simulate::down-pattern :b))
              (ivory-key.simulate::within-pattern
               45 (ivory-key.simulate::down-pattern :a)
               (ivory-key.simulate::down-pattern :b))
              (ivory-key.simulate::overlap-pattern :a :b))
             :actions (list (ivory-key.simulate::emit-action :combo))))))
        (alternative
          (ivory-key.simulate::make-sim-interaction
           :name :alternate :participants '(:a :b)
           :cases
           (list
            (ivory-key.simulate::make-sim-case
             :name :alternate
             :pattern
             (ivory-key.simulate::either-pattern
              (ivory-key.simulate::sequence-pattern
               (ivory-key.simulate::down-pattern :a)
               (ivory-key.simulate::up-pattern :a))
              (ivory-key.simulate::sequence-pattern
               (ivory-key.simulate::down-pattern :b)
               (ivory-key.simulate::up-pattern :b)))
             :actions (list (ivory-key.simulate::emit-action :either)))))))
    (simulation-assert-equal
     '(:combo)
     (simulator-outputs-for (list combo)
                            (list (sim-event 0 :down :a) (sim-event 40 :down :b)
                                  (sim-event 50 :up :a) (sim-event 60 :up :b)))
     "all, within, and overlap recognize an unordered combo")
    (simulation-assert-equal
     '(:either)
     (simulator-outputs-for (list alternative)
                            (list (sim-event 0 :down :b) (sim-event 20 :up :b)))
     "either selects a finite alternative")))

(defun single-a-output-interaction (name output priority)
  (ivory-key.simulate::make-sim-interaction
   :name name :participants '(:a) :priority priority
   :cases
   (list (ivory-key.simulate::make-sim-case
          :name name
          :pattern (ivory-key.simulate::sequence-pattern
                    (ivory-key.simulate::down-pattern :a)
                    (ivory-key.simulate::up-pattern :a))
          :actions (list (ivory-key.simulate::emit-action output))))))

(defun test-priority-and-ambiguity ()
  (simulation-assert-equal
   '(:high)
   (simulator-outputs-for
    (list (single-a-output-interaction :low :low 1)
          (single-a-output-interaction :high :high 2))
    (list (sim-event 0 :down :a) (sim-event 10 :up :a)))
   "higher-priority candidate owns overlapping events")
  (let ((signalled nil))
    (handler-case
        (simulator-outputs-for
         (list (single-a-output-interaction :left :left 0)
               (single-a-output-interaction :right :right 0))
         (list (sim-event 0 :down :a) (sim-event 10 :up :a)))
      (ivory-key.simulate::simulation-ambiguity ()
        (setf signalled t)))
    (simulation-assert signalled
                       "equal-priority incompatible candidates must be ambiguous")))

(defun test-cancellation-and-latch-nonconsumption ()
  (let* ((result (ivory-key.simulate::simulate-events
                  (list (make-isolated-a-interaction :consulted-latches '(:shift-latch)))
                  (list (sim-event 0 :down :a) (sim-event 10 :down :b)
                        (sim-event 20 :up :b) (sim-event 30 :up :a))
                  :latches '((:shift-latch . :latch))))
         (trace (ivory-key.simulate::simulation-result-trace result)))
    (simulation-assert-equal nil (ivory-key.simulate::simulation-result-outputs result)
                             "foreign down cancels isolated candidate")
    (simulation-assert-equal '((:shift-latch . :latch))
                             (ivory-key.simulate::simulation-result-latches result)
                             "rejected candidate does not consume latch")
    (simulation-assert
     (member :cancel (mapcar #'ivory-key.simulate::simulation-trace-entry-kind trace))
     "cancellation must be explicit in trace")
    (simulation-assert
     (not (member :latch-consumed
                  (mapcar #'ivory-key.simulate::simulation-trace-entry-kind trace)))
     "only committed candidate may consume latch")))

(defun make-latch-reserving-interaction (name position)
  (ivory-key.simulate::make-sim-interaction
   :name name :participants (list position) :consulted-latches '(:shift-latch)
   :cases
   (list
    (ivory-key.simulate::make-sim-case
     :name :release
     :pattern (ivory-key.simulate::sequence-pattern
               (ivory-key.simulate::down-pattern position)
               (ivory-key.simulate::up-pattern position))
     :actions (list (ivory-key.simulate::emit-action name))))))

(defun test-concurrent-latch-consumers-refused-before-commit ()
  (let ((first (make-latch-reserving-interaction :first :a))
        (second (make-latch-reserving-interaction :second :b))
        (conflict nil))
    (handler-case
        (ivory-key.simulate::simulate-events
         (list first second)
         (list (sim-event 0 :down :a) (sim-event 1 :down :b))
         :latches '((:shift-latch . :latched)))
      (ivory-key.simulate:simulation-latch-reservation-conflict (condition)
        (setf conflict condition)))
    (simulation-assert conflict
                       "independently pending consumers must fail closed at snapshot time")
    (simulation-assert-equal :shift-latch
                             (ivory-key.simulate:simulation-latch-reservation-conflict-axis
                              conflict)
                             "the conflict identifies the consulted latch axis")
    (simulation-assert-equal 1
                             (ivory-key.simulate:simulation-latch-reservation-conflict-generation
                              conflict)
                             "the conflict identifies the captured latch generation")
    (simulation-assert
     (not (eq (ivory-key.simulate:simulation-latch-reservation-conflict-existing-candidate
               conflict)
              (ivory-key.simulate:simulation-latch-reservation-conflict-requested-candidate
               conflict)))
     "the conflict identifies distinct pending candidate sets")))

(defun test-one-candidate-set-may-share-one-latch-snapshot ()
  (let* ((interaction
           (ivory-key.simulate::make-sim-interaction
            :name :one-set :participants '(:a) :consulted-latches '(:shift-latch)
            :cases
            (list
             (ivory-key.simulate::make-sim-case
              :name :tap :priority 1
              :pattern (ivory-key.simulate::sequence-pattern
                        (ivory-key.simulate::down-pattern :a)
                        (ivory-key.simulate::up-pattern :a))
              :actions (list (ivory-key.simulate::emit-action :tap)))
             (ivory-key.simulate::make-sim-case
              :name :hold :priority 2
              :pattern (ivory-key.simulate::deadline-pattern 100
                                                              :after-position :a
                                                              :while-down :a)
              :actions (list (ivory-key.simulate::emit-action :hold))))))
         (result
           (ivory-key.simulate::simulate-events
            (list interaction)
            (list (sim-event 0 :down :a) (sim-event 10 :up :a))
            :latches '((:shift-latch . :latched)))))
    (simulation-assert-equal '(:tap)
                             (ivory-key.simulate::simulation-result-outputs result)
                             "arbitrated alternatives from one anchor remain allowed")
    (simulation-assert-equal nil
                             (ivory-key.simulate::simulation-result-latches result)
                             "the winning alternative consumes the shared snapshot once")))

(defun test-reversible-effect-lifecycle ()
  (let* ((effect (ivory-key.simulate::make-sim-effect
                  :name :meta-held
                  :enter-actions (list (ivory-key.simulate::emit-action :meta-enter))
                  :exit-actions (list (ivory-key.simulate::emit-action :meta-exit))))
         (interaction
           (ivory-key.simulate::make-sim-interaction
            :name :held-meta :participants '(:a)
            :cases
            (list (ivory-key.simulate::make-sim-case
                   :name :hold
                   :pattern (ivory-key.simulate::deadline-pattern 100
                                                                   :after-position :a
                                                                   :while-down :a)
                   :enter-at (ivory-key.simulate::deadline-pattern 100
                                                                     :after-position :a
                                                                     :while-down :a)
                   :exit-at (ivory-key.simulate::up-pattern :a)
                   :effects (list effect)))))
         (result (ivory-key.simulate::simulate-events
                  (list interaction)
                  (list (sim-event 0 :down :a) (sim-event 150 :up :a)))))
    (simulation-assert-equal '(:meta-enter :meta-exit)
                             (ivory-key.simulate::simulation-result-outputs result)
                             "held effect has paired enter and exit")
    (simulation-assert-equal nil
                             (ivory-key.simulate::simulation-result-active-effects result)
                             "no held state remains after exit")))

(defun test-terminal-effect-does-not-reenter-after-unrelated-event ()
  "An ever-growing prefix must not re-satisfy a completed effect's entry rule."
  (let* ((effect (ivory-key.simulate::make-sim-effect
                  :name :one-shot-held
                  :enter-actions (list (ivory-key.simulate::emit-action :enter))
                  :exit-actions (list (ivory-key.simulate::emit-action :exit))))
         (interaction
           (ivory-key.simulate::make-sim-interaction
            :name :one-shot :participants '(:a)
            :cases
            (list (ivory-key.simulate::make-sim-case
                   :name :hold-a
                   :pattern (ivory-key.simulate::down-pattern :a)
                   :enter-at (ivory-key.simulate::down-pattern :a)
                   :exit-at (ivory-key.simulate::up-pattern :a)
                   :effects (list effect)))))
         (result
           (ivory-key.simulate::simulate-events
            (list interaction)
            (list (sim-event 0 :down :a)
                  (sim-event 1 :up :a)
                  (sim-event 2 :down :b)
                  (sim-event 3 :up :b))))
         (kinds
           (mapcar #'ivory-key.simulate::simulation-trace-entry-kind
                   (ivory-key.simulate::simulation-result-trace result))))
    (simulation-assert-equal '(:enter :exit)
                             (ivory-key.simulate::simulation-result-outputs result)
                             "effect enters and exits exactly once")
    (simulation-assert-equal 1 (count :effect-enter kinds)
                             "unrelated events do not re-enter an exited effect")
    (simulation-assert-equal 1 (count :effect-exit kinds)
                             "unrelated events do not repeat an exited effect")
    (simulation-assert-equal nil
                             (ivory-key.simulate::simulation-result-active-effects result)
                             "terminal exit leaves no held effect")))

(defun held-owner-test-interaction (name position &key cancel-at (state :greek))
  "One speculative holder with an explicit base-state reset at both boundaries."
  (let ((effect
          (ivory-key.simulate::make-sim-effect
           :name (list :holder name)
           :enter-actions
           (list (ivory-key.simulate::hold-axis-action :script state)
                 (ivory-key.simulate::hold-modifier-action :super))
           ;; These direct SET actions intentionally do not own a hold.  The
           ;; regression checks that they become visible only after the final
           ;; contributor releases SCRIPT=GREEK.
           :exit-actions (list (ivory-key.simulate::set-axis-action :script :roman))
           :cancel-actions (list (ivory-key.simulate::set-axis-action :script :roman)))))
    (ivory-key.simulate::make-sim-interaction
     :name name :participants (list position)
     :cases
     (list
      (ivory-key.simulate::make-sim-case
       :name name
       :pattern (ivory-key.simulate::deadline-pattern 100
                                                       :after-position position
                                                       :while-down position)
       :enter-at (ivory-key.simulate::down-pattern position)
       :exit-at (ivory-key.simulate::up-pattern position)
       :cancel-at cancel-at
       :effects (list effect))))))

(defun test-held-contributions-are-owner-scoped-and-reference-counted ()
  (let* ((machine
           (ivory-key.simulate::make-simulator
            :interactions
            (list (held-owner-test-interaction :first :a)
                  ;; The second holder is cancelled before its deadline.  Its
                  ;; base reset must not clear FIRST's identical contribution.
                  (held-owner-test-interaction :second :b
                                                :cancel-at
                                                (ivory-key.simulate::down-pattern :x)))
            :axes '((:script . :roman))))
         (feed (lambda (time kind position)
                 (ivory-key.simulate::simulator-feed-event
                  machine (sim-event time kind position)))))
    (funcall feed 0 :down :a)
    (simulation-assert-equal '((:script . :greek))
                             (ivory-key.simulate::simulator-axes-alist machine)
                             "first held owner overlays the direct axis state")
    (funcall feed 1 :down :b)
    (simulation-assert-equal '((:modifier :press :super))
                             (ivory-key.simulate::simulator-outputs machine)
                             "second identical modifier holder does not press twice")
    (funcall feed 2 :down :x)
    (simulation-assert-equal '((:script . :greek))
                             (ivory-key.simulate::simulator-axes-alist machine)
                             "cancelled holder's direct reset cannot defeat another hold")
    ;; Advance through FIRST's deadline so it commits, then take its normal
    ;; release path.  This must release the final contribution exactly once.
    (funcall feed 101 :up :a)
    (let* ((result (ivory-key.simulate::simulator-result machine))
           (trace (ivory-key.simulate::simulation-result-trace result))
           (entries (lambda (kind)
                      (remove kind trace :test-not #'eq
                              :key #'ivory-key.simulate::simulation-trace-entry-kind)))
           (axis-acquires (funcall entries :held-axis-acquire))
           (axis-releases (funcall entries :held-axis-release))
           (modifier-acquires (funcall entries :held-modifier-acquire))
           (modifier-releases (funcall entries :held-modifier-release)))
      (simulation-assert-equal '((:modifier :press :super) (:modifier :release :super))
                               (ivory-key.simulate::simulation-result-outputs result)
                               "modifier releases only at the final owner's terminal exit")
      (simulation-assert-equal '((:script . :roman))
                               (ivory-key.simulate::simulation-result-axes result)
                               "final release reveals the direct base reset")
      (simulation-assert-equal nil
                               (ivory-key.simulate::simulation-result-active-effects result)
                               "all terminal owners are removed without stuck held state")
      (simulation-assert-equal '(t nil)
                               (mapcar (lambda (entry)
                                         (second (member :first
                                                         (ivory-key.simulate::simulation-trace-entry-details entry))))
                                       axis-acquires)
                               "axis acquisition identifies first then shared owner")
      (simulation-assert-equal '(nil t)
                               (mapcar (lambda (entry)
                                         (second (member :last
                                                         (ivory-key.simulate::simulation-trace-entry-details entry))))
                                       axis-releases)
                               "cancellation releases one owner and normal exit releases the last")
      (simulation-assert-equal '(t nil)
                               (mapcar (lambda (entry)
                                         (second (member :first
                                                         (ivory-key.simulate::simulation-trace-entry-details entry))))
                                       modifier-acquires)
                               "modifier acquisition retains both physical owners")
      (simulation-assert-equal '(nil t)
                               (mapcar (lambda (entry)
                                         (second (member :last
                                                         (ivory-key.simulate::simulation-trace-entry-details entry))))
                                       modifier-releases)
                               "modifier release occurs only after the last owner"))))

(defun test-held-axis-conflicts-and-unowned-actions-refuse ()
  (let ((machine (ivory-key.simulate::make-simulator))
        (refused nil))
    (handler-case
        (ivory-key.simulate::simulator-acquire-held-axis machine nil :script :greek)
      (ivory-key.simulate::held-action-outside-effect (condition)
        (setf refused t)
        (simulation-assert-equal nil
                                 (ivory-key.simulate::held-action-outside-effect-candidate condition)
                                 "unowned held action reports its absent candidate"))
      (condition (condition)
        (error "Expected HELD-ACTION-OUTSIDE-EFFECT, got ~S." condition)))
    (simulation-assert refused "unowned held action must be refused"))
  (let ((machine
          (ivory-key.simulate::make-simulator
           :interactions
           (list (held-owner-test-interaction :greek :a :state :greek)
                 (held-owner-test-interaction :roman :b :state :roman))))
        (refused nil))
    (ivory-key.simulate::simulator-feed-event machine (sim-event 0 :down :a))
    (handler-case
        (ivory-key.simulate::simulator-feed-event machine (sim-event 1 :down :b))
      (ivory-key.simulate::held-axis-state-conflict (condition)
        (setf refused t)
        (simulation-assert-equal :script
                                 (ivory-key.simulate::held-axis-state-conflict-axis condition)
                                 "conflict reports the axis")
        (simulation-assert-equal :greek
                                 (ivory-key.simulate::held-axis-state-conflict-existing-state condition)
                                 "conflict reports the already held state")
        (simulation-assert-equal :roman
                                 (ivory-key.simulate::held-axis-state-conflict-requested-state condition)
                                 "conflict reports the requested state")
        (simulation-assert
         (and (ivory-key.simulate::held-axis-state-conflict-existing-owners condition)
              (ivory-key.simulate::held-axis-state-conflict-requested-owner condition))
         "conflict reports both existing and requested owners"))
      (condition (condition)
        (error "Expected HELD-AXIS-STATE-CONFLICT, got ~S." condition)))
    (simulation-assert refused "conflicting held axis states must be refused")))

(defun test-overlap-provenance-is-recursive-and-dump-safe ()
  ;; Extended/direct simulator IR can carry overlap children as nested event
  ;; patterns.  The provenance serializer must recursively canonicalize them,
  ;; never leaving host EVENT-PATTERN structs in the dump.
  (let* ((pattern
           (ivory-key.simulate::%make-event-pattern
            :kind :overlap
            :children (list (ivory-key.simulate::down-pattern "a")
                            (ivory-key.simulate::down-pattern "b"))))
         (source (ivory-key.simulate::canonical-pattern-provenance pattern))
         (result
           (ivory-key.simulate::make-simulation-result
            :trace
            (list
             (ivory-key.simulate::make-simulation-trace-entry
              :time 0 :kind :action
              :provenance
              (list :source-pattern source :candidate-transition :committed
                    :commit-point :when-matched :responsible-effect :candidate-do)))))
         (dump (ivory-key.simulate::simulation-result-dump-string result)))
    (simulation-assert-equal '(:overlap (:event :down "a") (:event :down "b"))
                             source
                             "overlap provenance recursively canonicalizes children")
    (simulation-assert (search "(:overlap (:event :down \"a\") (:event :down \"b\"))" dump)
                       "recursive overlap provenance remains in the closed dump vocabulary")))

(deftest simulation-tap-versus-hold-boundary
  (test-tap-versus-hold-boundary))

(deftest simulation-one-and-two-second-duration-regions
  (test-one-and-two-second-duration-regions))

(deftest simulation-isolated-release
  (test-isolated-release))

(deftest simulation-both-release-orders
  (test-both-release-orders))

(deftest simulation-finite-pattern-algebra
  (test-finite-pattern-algebra))

(deftest simulation-priority-and-ambiguity
  (test-priority-and-ambiguity))

(deftest simulation-cancellation-and-latch-nonconsumption
  (test-cancellation-and-latch-nonconsumption))

(deftest simulation-concurrent-latch-consumers-refused-before-commit
  (test-concurrent-latch-consumers-refused-before-commit))

(deftest simulation-one-candidate-set-may-share-one-latch-snapshot
  (test-one-candidate-set-may-share-one-latch-snapshot))

(deftest simulation-reversible-effect-lifecycle
  (test-reversible-effect-lifecycle))

(deftest simulation-terminal-effect-does-not-reenter-after-unrelated-event
  (test-terminal-effect-does-not-reenter-after-unrelated-event))

(deftest simulation-held-contributions-are-owner-scoped-and-reference-counted
  (test-held-contributions-are-owner-scoped-and-reference-counted))

(deftest simulation-held-axis-conflicts-and-unowned-actions-refuse
  (test-held-axis-conflicts-and-unowned-actions-refuse))

(deftest simulation-overlap-provenance-is-recursive-and-dump-safe
  (test-overlap-provenance-is-recursive-and-dump-safe))
