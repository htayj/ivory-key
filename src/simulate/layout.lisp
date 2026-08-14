;;;; SPDX-License-Identifier: GPL-3.0-or-later
;;;; Safe whole-normalized-layout adapter for the reference event simulator.

(in-package #:ivory-key.simulate)

;;; This adapter deliberately lowers only the part of a normalized layout that
;;; has an exact representation in the existing finite state machine.  An
;;; ordinary binding becomes a one-position, down-commit SIM-INTERACTION, so
;;; it shares the machine's context snapshot, committed-only latch consumption,
;;; candidate ownership, and trace records with timed interactions.  Binding
;;; positions that also participate in a timed interaction are refused: their
;;; fallback timing is not yet a defined part of the model-to-machine contract.

(defun %normalized-layout-simulation-error (code object control &rest arguments)
  (apply #'%simulation-compilation-error code object control arguments))

(defun %require-normalized-layout (layout)
  (unless (typep layout 'ivory-key.model::normalized-layout)
    (%normalized-layout-simulation-error
     :invalid-normalized-layout layout
     "Expected a normalized layout, got ~S." layout))
  layout)

(defun %normalized-layout-axis-name (axis)
  (model-identifier->simulation-value (ivory-key.model::axis-name axis)))

(defun %normalized-layout-default-axes (layout)
  "Return LAYOUT's declared default context as canonical simulator pairs."
  (mapcar (lambda (axis)
            (cons (%normalized-layout-axis-name axis)
                  (model-identifier->simulation-value
                   (ivory-key.model::axis-default-state axis))))
          (ivory-key.model::normalized-layout-axes layout)))

(defun %normalized-layout-position-names (layout)
  (mapcar (lambda (position)
            (model-identifier->simulation-value
             (ivory-key.model::position-name position)))
          (ivory-key.model::topology-positions
           (ivory-key.model::normalized-layout-topology layout))))

(defun %find-normalized-layout-axis (layout axis-name)
  (find axis-name (ivory-key.model::normalized-layout-axes layout)
        :test #'string=
        :key #'%normalized-layout-axis-name))

(defun %canonical-layout-context-entries (layout entries kind)
  "Validate ENTRIES as named axis/state pairs and canonicalize their strings."
  (unless (listp entries)
    (%normalized-layout-simulation-error
     :invalid-simulation-context entries
     "~A context must be a list of (axis . state) pairs." kind))
  (let ((seen nil)
        (result nil))
    (dolist (entry entries (nreverse result))
      (unless (consp entry)
        (%normalized-layout-simulation-error
         :invalid-simulation-context entry
         "~A context entry must be an (axis . state) pair." kind))
      (let* ((axis-name (model-identifier->simulation-value (car entry)))
             (state-name (model-identifier->simulation-value (cdr entry)))
             (axis (%find-normalized-layout-axis layout axis-name)))
        (unless axis
          (%normalized-layout-simulation-error
           :unknown-simulation-axis entry
           "~A context names undeclared axis ~A." kind axis-name))
        (unless (find state-name (ivory-key.model::axis-states axis)
                      :test #'string=
                      :key #'model-identifier->simulation-value)
          (%normalized-layout-simulation-error
           :unknown-simulation-axis-state entry
           "~A context state ~A is not declared by axis ~A."
           kind state-name axis-name))
        (when (member axis-name seen :test #'string=)
          (%normalized-layout-simulation-error
           :duplicate-simulation-context-axis entries
           "~A context names axis ~A more than once." kind axis-name))
        (push axis-name seen)
        (push (cons axis-name state-name) result)))))

(defun %merged-normalized-layout-axes (layout axes)
  "Overlay validated AXES on the declared defaults without dropping defaults."
  (let ((result (%normalized-layout-default-axes layout)))
    (dolist (entry (%canonical-layout-context-entries layout axes :axis))
      (let ((default (assoc (car entry) result :test #'string=)))
        ;; The context validation above guarantees DEFAULT exists.
        (setf (cdr default) (cdr entry))))
    result))

(defun %normalized-layout-latches (layout latches)
  "Validate initial latches for the one-value-per-axis machine representation."
  (%canonical-layout-context-entries layout latches :latch))

(defun %exact-normalized-entry-actions (entries source)
  "Compile normalized entries into a one-and-only-one context dispatch action.

All variant behavior is compiled before simulation begins.  This prevents an
unsupported branch from being silently absent merely because a particular
event fixture did not reach it.  The callback uses the candidate's anchor-time
axis and latch snapshot, exactly as compiled interaction entries do.
"
  (unless (and (listp entries) entries)
    (%normalized-layout-simulation-error
     :missing-normalized-binding-entry source
     "Normalized binding ~S has no dispatch entries." source))
  (let ((compiled
          (mapcar
           (lambda (entry)
             (unless (typep entry 'ivory-key.model::normalized-binding-entry)
               (%normalized-layout-simulation-error
                :invalid-normalized-binding-entry entry
                "Binding ~S contains an invalid normalized entry ~S." source entry))
             (cons entry
                   (compile-model-behavior
                    (ivory-key.model::normalized-entry-behavior entry))))
           entries)))
    (list
     (make-sim-action
      :kind :callback
      :value
      (lambda (candidate machine)
        (let ((selected nil))
          (dolist (entry compiled)
            (when (%tuple-matches-candidate-p
                   (ivory-key.model::normalized-entry-tuple (car entry)) candidate)
              (when selected
                (%normalized-layout-simulation-error
                 :ambiguous-normalized-binding-context source
                 "Binding ~S has multiple entries for one captured context."
                 source))
              (setf selected entry)))
          (unless selected
            (%normalized-layout-simulation-error
             :unresolved-normalized-binding-context source
             "Binding ~S has no entry for the captured context." source))
          (%apply-compiled-actions machine candidate (cdr selected))))))))

(defun compile-normalized-ordinary-binding (binding)
  "Compile one disjoint normalized ordinary BINDING into exact simulator IR.

The synthetic interaction commits on the position's DOWN event.  This is the
defined activation point for an ordinary binding in this slice; bindings that
need interaction arbitration are rejected by
COMPILE-NORMALIZED-LAYOUT-SIMULATION rather than being given an invented
fallback timing.
"
  (unless (typep binding 'ivory-key.model::normalized-binding)
    (%normalized-layout-simulation-error
     :invalid-normalized-binding binding
     "Expected a normalized binding, got ~S." binding))
  (let* ((position (model-identifier->simulation-value
                    (ivory-key.model::normalized-binding-position binding)))
         (axes (mapcar #'model-identifier->simulation-value
                       (ivory-key.model::normalized-binding-axes binding)))
         (name (list :ordinary-binding position)))
    (make-sim-interaction
     :name name
     :participants (list position)
     :consulted-latches axes
     :arbitration :priority
     :cases
     (list
      (make-sim-case
       :name name
       :pattern (down-pattern position)
       :commit :when-matched
       :actions (%exact-normalized-entry-actions
                 (ivory-key.model::normalized-binding-entries binding) binding)
       :consulted-latches axes)))))

(defun compile-normalized-ordinary-bindings (bindings)
  "Compile ordinary normalized BINDINGS in canonical layout order."
  (mapcar #'compile-normalized-ordinary-binding bindings))

(defun %interaction-participant-names (interaction)
  (mapcar #'model-identifier->simulation-value
          (ivory-key.model::normalized-interaction-participants interaction)))

(defun %assert-disjoint-normalized-binding-positions (bindings interactions)
  "Refuse ordinary/interaction overlap until fallback ownership is specified."
  (dolist (binding bindings)
    (let ((position (model-identifier->simulation-value
                     (ivory-key.model::normalized-binding-position binding))))
      (dolist (interaction interactions)
        (when (member position (%interaction-participant-names interaction)
                      :test #'string=)
          (%normalized-layout-simulation-error
           :ordinary-binding-interaction-overlap binding
           "Binding position ~A also participates in interaction ~A; its fallback timing is unsupported."
           position
           (model-identifier->simulation-value
            (ivory-key.model::normalized-interaction-name interaction))))))))

(defun %reject-normalized-layout-patches (layout)
  (when (ivory-key.model::normalized-layout-patches layout)
    (%normalized-layout-simulation-error
     :unsupported-normalized-overlays layout
     "Normalized overlay patches need an explicit dynamic activation contract; this adapter refuses them.")))

(defun compile-normalized-layout-simulation (layout)
  "Compile a safe whole-layout slice into simulator interactions and defaults.

The first value is the unified list of synthetic ordinary-binding and compiled
timed interactions.  The second value is the complete declared default axis
alist.  This accepts no normalized overlays and no ordinary binding whose
position is an interaction participant, because neither has a fully specified
fallback/activation semantics in the present finite machine.
"
  (%require-normalized-layout layout)
  (%reject-normalized-layout-patches layout)
  (let ((bindings (ivory-key.model::normalized-layout-bindings layout))
        (interactions (ivory-key.model::normalized-layout-interactions layout)))
    (%assert-disjoint-normalized-binding-positions bindings interactions)
    (values (append (compile-normalized-ordinary-bindings bindings)
                    (compile-normalized-interactions interactions))
            (%normalized-layout-default-axes layout))))

(defun %normalized-layout-event (layout event active-positions)
  "Validate EVENT belongs to LAYOUT and use canonical position spelling."
  (unless (typep event 'timed-event)
    (%normalized-layout-simulation-error
     :invalid-simulation-event event "Expected a timed event, got ~S." event))
  (when (eq (timed-event-kind event) :deadline)
    (%normalized-layout-simulation-error
     :generated-deadline-input event
     "Deadline events are generated by the simulator, not supplied by a layout fixture."))
  (let ((position (model-identifier->simulation-value (timed-event-position event))))
    (unless (member position (%normalized-layout-position-names layout) :test #'string=)
      (%normalized-layout-simulation-error
       :unknown-simulation-position event
       "Event position ~A is not present in the layout topology." position))
    (unless (member position active-positions :test #'string=)
      (%normalized-layout-simulation-error
       :unbound-simulation-position event
       "Event position ~A has neither an ordinary binding nor an interaction participant."
       position))
    (make-timed-event (timed-event-time event) (timed-event-kind event) position
                      :data (timed-event-data event))))

(defun %layout-simulation-active-positions (interactions)
  (remove-duplicates
   (mapcan (lambda (interaction)
             (copy-list (sim-interaction-participants interaction)))
           interactions)
   :test #'string=))

(defun simulate-normalized-layout-events (layout events &key axes latches until)
  "Simulate normalized LAYOUT against explicit timed EVENTS and semantic context.

AXES overrides declared defaults only for named, declared axis states; LATCHES
uses the same validation and supplies at most one current latch per axis.  All
ordinary-binding and timed-interaction transitions use the existing simulator,
so candidate ownership, commitment-only latch consumption, and full trace
records are preserved.  Unsupported overlays, ordinary/interaction position
overlap, unknown input positions, unsupported model behavior, and unsupported
temporal patterns signal a compilation error rather than being approximated.
"
  (%require-normalized-layout layout)
  (multiple-value-bind (interactions defaults)
      (compile-normalized-layout-simulation layout)
    (declare (ignore defaults))
    (let ((active-positions (%layout-simulation-active-positions interactions)))
      (simulate-events interactions
                       (mapcar (lambda (event)
                                 (%normalized-layout-event
                                  layout event active-positions))
                               events)
                       :axes (%merged-normalized-layout-axes layout axes)
                       :latches (%normalized-layout-latches layout latches)
                       :until until))))

(defun simulate-model-layout-events (layout events &key axes latches until)
  "Normalize a decoded model LAYOUT, then simulate its supported whole-layout slice.

This is the decoded-layout convenience entry point.  It does not reparse
source, lower a backend, deploy, or weaken any refusal from normalization or
SIMULATE-NORMALIZED-LAYOUT-EVENTS.
"
  (unless (typep layout 'ivory-key.model::layout)
    (%normalized-layout-simulation-error
     :invalid-layout layout "Expected a model layout, got ~S." layout))
  (simulate-normalized-layout-events
   (ivory-key.model::normalize-layout layout) events
   :axes axes :latches latches :until until))
