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

(deftest simulation-reversible-effect-lifecycle
  (test-reversible-effect-lifecycle))
