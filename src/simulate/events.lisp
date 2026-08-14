;;;; SPDX-License-Identifier: GPL-3.0-or-later
;;;; Timestamped input and observable simulator trace records.

(in-package #:ivory-key.simulate)

(deftype timestamp ()
  "The reference clock unit.  Version 1 uses non-negative integer milliseconds."
  '(integer 0 *))

(defstruct (timed-event
             (:constructor %make-timed-event (time kind position data)))
  "An immutable event in the abstract logical-position stream.

KIND is :DOWN, :UP, or the simulator-generated :DEADLINE.  POSITION is a
logical position identifier for physical events and is NIL for a deadline.
DATA is reserved for a named clock or source annotation; matching never uses
backend keycodes or physical-device identities."
  (time 0 :type timestamp :read-only t)
  (kind :down :type keyword :read-only t)
  (position nil :read-only t)
  (data nil :read-only t))

(defun make-timed-event (time kind position &key data)
  "Construct a physical logical-position event.

The public constructor deliberately refuses generated deadline events: only
the machine creates them, which prevents fixtures from claiming a timeout
without allowing the reference clock to advance."
  (unless (typep time 'timestamp)
    (error "Event time must be a non-negative integer millisecond, not ~S." time))
  (unless (member kind '(:down :up) :test #'eq)
    (error "Physical event kind must be :DOWN or :UP, not ~S." kind))
  (when (null position)
    (error "A physical event needs a logical position."))
  (%make-timed-event time kind position data))

(defun make-deadline-event (time &key data)
  "Internal constructor for a deterministic clock tick."
  (unless (typep time 'timestamp)
    (error "Deadline time must be a non-negative integer millisecond, not ~S." time))
  (%make-timed-event time :deadline nil data))

(defstruct (simulation-trace-entry
             (:constructor make-simulation-trace-entry
                 (&key time kind event interaction case candidate details provenance)))
  "One explainable transition of the reference machine.

KIND is one of :EVENT, :CANDIDATE-START, :DEADLINE, :COMMIT, :CANCEL,
:EFFECT-ENTER, :EFFECT-EXIT, :EFFECT-CANCEL, :ACTION, or :LATCH-CONSUMED.
The retained interaction/case/candidate references identify the interpretation
that caused a transition.  PROVENANCE is a closed, deterministic plist for
observable transitions.  It names the canonical source pattern, candidate
transition, commit point, and responsible effect (or :CANDIDATE-DO when no
lifecycle effect caused the observation)."
  (time 0 :type timestamp :read-only t)
  (kind :event :type keyword :read-only t)
  (event nil :read-only t)
  (interaction nil :read-only t)
  (case nil :read-only t)
  (candidate nil :read-only t)
  (details nil :read-only t)
  (provenance nil :read-only t))
