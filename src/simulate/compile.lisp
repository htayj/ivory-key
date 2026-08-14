;;;; SPDX-License-Identifier: GPL-3.0-or-later
;;;; Adapter from the declarative model into the reference simulator IR.

(in-package #:ivory-key.simulate)

(declaim (ftype function compile-model-position-selector
                        %execute-model-behavior))

;;; The simulator deliberately has a smaller executable vocabulary than the
;;; model.  In particular, it has no capture store, no context predicate in an
;;; EVENT-PATTERN, and no representation for a multi-position exclusion.  This
;;; adapter refuses those constructs instead of making the reference oracle
;;; silently less precise than the source model.

(define-condition model-simulation-compilation-error
    (ivory-key.model::semantic-error)
  ((feature :initarg :feature :reader model-simulation-compilation-error-feature))
  (:report (lambda (condition stream)
             (format stream "Cannot compile model object for simulation (~A): ~A"
                     (model-simulation-compilation-error-feature condition)
                     (ivory-key.model::semantic-error-message condition)))))

(defun %simulation-compilation-error (code object control &rest arguments)
  (error 'model-simulation-compilation-error
         :feature code
         :code code
         :object object
         :message (apply #'format nil control arguments)))

(defun model-identifier->simulation-value (identifier)
  "Return IDENTIFIER's package-independent simulator spelling.

Logical positions, axes, states, and abstract named outputs remain canonical
strings.  This prevents simulation fixtures from accidentally depending on a
Common Lisp package or on keyword interning."
  (ivory-key.model::identifier-name
   (ivory-key.model::ensure-identifier identifier)))

(defun %exact-simulation-position (selector object purpose)
  "Translate SELECTOR only when the simulator needs one exact position."
  (let ((compiled (compile-model-position-selector selector)))
    (if (stringp compiled)
        compiled
        (%simulation-compilation-error
         :unsupported-position-selector object
         "~A needs one exact logical position; received ~S."
         purpose selector))))

(defun compile-model-position-selector (selector)
  "Compile a model POSITION-SELECTOR to the simulator's finite selector IR."
  (unless (typep selector 'ivory-key.model::position-selector)
    ;; Model deadline/while-down fields historically accepted a bare position.
    ;; Treat that convenience spelling as an exact selector at this boundary.
    (return-from compile-model-position-selector
      (model-identifier->simulation-value selector)))
  (let ((positions (ivory-key.model::position-selector-positions selector)))
    (ecase (ivory-key.model::position-selector-kind selector)
      (:position
       (unless (= (length positions) 1)
         (%simulation-compilation-error
          :malformed-position-selector selector
          "An exact position selector must contain one position, not ~S." positions))
       (model-identifier->simulation-value (first positions)))
      (:any-position
       (unless (null positions)
         (%simulation-compilation-error
          :malformed-position-selector selector
          "An any-position selector must not name positions: ~S." positions))
       :any)
      (:other-than
       (unless (= (length positions) 1)
         (%simulation-compilation-error
          :unsupported-position-selector selector
          "The simulator can exclude one position, not ~D positions."
          (length positions)))
       (list :other-than (model-identifier->simulation-value (first positions)))))))

(defun %model-pattern-arguments (pattern expected)
  (let ((arguments (ivory-key.model::temporal-pattern-arguments pattern)))
    (unless (= (length arguments) expected)
      (%simulation-compilation-error
       :malformed-temporal-pattern pattern
       "~A requires ~D argument~:P, not ~D."
       (ivory-key.model::temporal-pattern-kind pattern) expected (length arguments)))
    arguments))

(defun %atomic-simulator-pattern-p (pattern)
  (eq (event-pattern-kind pattern) :event))

(defun %require-atomic-simulator-patterns (patterns source purpose)
  (unless (every #'%atomic-simulator-pattern-p patterns)
    (%simulation-compilation-error
     :unsupported-nested-temporal-pattern source
     "The simulator supports only event occurrences inside ~A; use AND or ALL for composite predicates."
     purpose))
  patterns)

(defun %deadline-after-position (value pattern)
  (cond
    ((typep value 'ivory-key.model::temporal-pattern)
     (unless (eq (ivory-key.model::temporal-pattern-kind value) :down)
       (%simulation-compilation-error
        :unsupported-deadline-anchor pattern
        "A simulator deadline can be anchored only by a DOWN event, not ~S."
        (ivory-key.model::temporal-pattern-kind value)))
     (%exact-simulation-position
      (first (%model-pattern-arguments value 1)) value "a deadline anchor"))
    (t (%exact-simulation-position value pattern "a deadline anchor"))))

(defun compile-model-temporal-pattern (pattern)
  "Compile one finite model TEMPORAL-PATTERN into an EVENT-PATTERN.

Every supported translation maps directly to the reference simulator's
matching semantics.  Unsupported source nodes signal
MODEL-SIMULATION-COMPILATION-ERROR rather than being weakened or ignored."
  (unless (typep pattern 'ivory-key.model::temporal-pattern)
    (%simulation-compilation-error
     :invalid-temporal-pattern pattern "Expected a model temporal pattern, got ~S." pattern))
  (let ((kind (ivory-key.model::temporal-pattern-kind pattern))
        (arguments (ivory-key.model::temporal-pattern-arguments pattern)))
    (case kind
      (:down
       (down-pattern
        (compile-model-position-selector (first (%model-pattern-arguments pattern 1)))))
      (:up
       (up-pattern
        (compile-model-position-selector (first (%model-pattern-arguments pattern 1)))))
      (:sequence
       (let ((children (mapcar #'compile-model-temporal-pattern arguments)))
         (%require-atomic-simulator-patterns children pattern "SEQUENCE")
         (apply #'sequence-pattern children)))
      (:all
       (apply #'all-pattern (mapcar #'compile-model-temporal-pattern arguments)))
      (:either
       (apply #'either-pattern (mapcar #'compile-model-temporal-pattern arguments)))
      (:and
       (apply #'and-pattern (mapcar #'compile-model-temporal-pattern arguments)))
      (:duration
       (duration-pattern
        (compile-model-position-selector (first (%model-pattern-arguments pattern 1)))
        :at-least (ivory-key.model::temporal-pattern-option pattern :at-least)
        :less-than (ivory-key.model::temporal-pattern-option pattern :less-than)))
      (:deadline
       (destructuring-bind (milliseconds after) (%model-pattern-arguments pattern 2)
         (let ((while-down (ivory-key.model::temporal-pattern-option pattern :while-down)))
           (deadline-pattern
            milliseconds
            :after-position (%deadline-after-position after pattern)
            :while-down (and while-down
                             (%exact-simulation-position while-down pattern
                                                         "a deadline :WHILE-DOWN guard"))))))
      (:within
       (let ((children (mapcar #'compile-model-temporal-pattern arguments)))
         (unless (= (length children) 2)
           (%simulation-compilation-error
            :malformed-temporal-pattern pattern
            "WITHIN requires two event occurrences, not ~D." (length children)))
         (%require-atomic-simulator-patterns children pattern "WITHIN")
         (apply #'within-pattern
                (ivory-key.model::temporal-pattern-option pattern :duration)
                children)))
      (:overlap
       (apply #'overlap-pattern
              (mapcar #'compile-model-position-selector arguments)))
      (:without
       (let* ((forbidden (compile-model-temporal-pattern
                          (first (%model-pattern-arguments pattern 1))))
              (between (ivory-key.model::temporal-pattern-option pattern :between)))
         (unless (and (listp between) (= (length between) 2))
           (%simulation-compilation-error
            :malformed-temporal-pattern pattern
            "WITHOUT needs exactly two closing-boundary patterns."))
         (let ((boundaries (mapcar #'compile-model-temporal-pattern between)))
           (%require-atomic-simulator-patterns
            (cons forbidden boundaries) pattern "WITHOUT")
           (without-pattern forbidden :between boundaries))))
      (:repeat
       (let ((child (compile-model-temporal-pattern
                     (first (%model-pattern-arguments pattern 1)))))
         (%require-atomic-simulator-patterns (list child) pattern "REPEAT")
         (repeat-pattern child
                         :at-least (ivory-key.model::temporal-pattern-option pattern
                                                                              :at-least 0)
                         :at-most (ivory-key.model::temporal-pattern-option pattern
                                                                             :at-most))))
      ((:capture :context-is)
       (%simulation-compilation-error
        :unsupported-contextual-temporal-pattern pattern
        "The reference simulator has no capture store or context predicate for ~A."
        kind))
      (otherwise
       (%simulation-compilation-error
        :unknown-temporal-pattern-kind pattern
        "No simulator translation exists for temporal pattern kind ~S." kind)))))

(defun %context-latch-value (candidate axis)
  (let ((snapshot (assoc axis (simulation-candidate-latch-snapshot candidate)
                        :test #'equal)))
    (and snapshot (second snapshot))))

(defun %candidate-context-value (candidate axis)
  "Read the anchor-time context selected for a compiled candidate.

A captured latch shadows the ordinary axis value.  The simulator consumes the
latch before commit actions run, so consulting the candidate snapshot is what
preserves the model's atomic latch-consumption rule."
  (or (%context-latch-value candidate axis)
      (cdr (assoc axis (simulation-candidate-context candidate) :test #'equal))))

(defun %tuple-matches-candidate-p (tuple candidate)
  (every (lambda (pair)
           (let ((actual (%candidate-context-value candidate
                                                   (model-identifier->simulation-value
                                                    (car pair)))))
             (and actual
                  (string= (model-identifier->simulation-value (cdr pair)) actual))))
         (ivory-key.model::context-tuple-pairs tuple)))

(defun %resolved-model-table-entry-behavior (entry table &optional seen)
  (let ((key (ivory-key.model::context-tuple-key
              (ivory-key.model::behavior-entry-tuple entry))))
    (when (member key seen :test #'string=)
      (%simulation-compilation-error
       :behavior-table-inheritance-cycle table
       "Behavior-table inheritance cycles at context ~A." key))
    (case (ivory-key.model::behavior-entry-disposition entry)
      (:behavior (ivory-key.model::behavior-entry-behavior entry))
      (:none (ivory-key.model::make-no-output-behavior))
      (:inherit
       (let ((source (ivory-key.model::find-behavior-entry
                      (ivory-key.model::behavior-entry-inherit-tuple entry) table)))
         (unless source
           (%simulation-compilation-error
            :unknown-behavior-table-inheritance table
            "No source entry exists for inherited context ~A."
            (ivory-key.model::context-tuple-key
             (ivory-key.model::behavior-entry-inherit-tuple entry))))
         (%resolved-model-table-entry-behavior source table (cons key seen))))
      (:transparent
       (%simulation-compilation-error
        :transparent-base-behavior table
        "A transparent behavior-table entry cannot be simulated without a patch base.")))))

(defun %apply-compiled-actions (machine candidate actions)
  (dolist (action actions)
    (apply-sim-action machine candidate action))
  machine)

(defun %model-behavior-callback (behavior &key effect-phase)
  (make-sim-action
   :kind :callback
   :value (lambda (candidate machine)
            (%execute-model-behavior behavior candidate machine
                                     :effect-phase effect-phase))))

(defun %select-model-table-behavior (table candidate)
  (let ((entry (find-if (lambda (candidate-entry)
                          (%tuple-matches-candidate-p
                           (ivory-key.model::behavior-entry-tuple candidate-entry)
                           candidate))
                        (ivory-key.model::behavior-table-entries table))))
    (unless entry
      (%simulation-compilation-error
       :unresolved-behavior-table-context table
       "No behavior-table entry matches the captured simulator context."))
    (%resolved-model-table-entry-behavior entry table)))

(defun %select-model-axis-choice (behavior candidate)
  (let* ((axis (model-identifier->simulation-value
                (ivory-key.model::choice-axis behavior)))
         (state (%candidate-context-value candidate axis))
         (choice (and state
                      (find state (ivory-key.model::choice-behaviors behavior)
                            :test #'string=
                            :key (lambda (pair)
                                   (model-identifier->simulation-value (car pair)))))))
    (unless choice
      (%simulation-compilation-error
       :unresolved-axis-choice behavior
       "No behavior choice for axis ~A matches captured state ~S." axis state))
    (cdr choice)))

(defun %axis-operation-actions (behavior &key effect-phase)
  (let ((operation (ivory-key.model::axis-operation behavior))
        (axis (model-identifier->simulation-value
               (ivory-key.model::axis-operation-axis behavior)))
        (state (ivory-key.model::axis-operation-state behavior)))
    (case operation
      (:latch
       (unless state
         (%simulation-compilation-error
          :malformed-axis-operation behavior "LATCH requires an axis state."))
       (list (latch-action axis (model-identifier->simulation-value state))))
      (:hold
       (unless state
         (%simulation-compilation-error
          :malformed-axis-operation behavior "HOLD requires an axis state."))
       (unless (eq effect-phase :while)
         (%simulation-compilation-error
          :held-axis-outside-while behavior
          "HOLD-AXIS-STATE requires a :WHILE lifecycle effect."))
       (list (hold-axis-action axis (model-identifier->simulation-value state))))
      ((:set :lock)
       (unless state
         (%simulation-compilation-error
          :malformed-axis-operation behavior "~A requires an axis state." operation))
       (list (set-axis-action axis (model-identifier->simulation-value state))))
      ((:unlock :toggle :cycle)
       (%simulation-compilation-error
        :unsupported-axis-operation behavior
        "The simulator has no exact state transition for axis operation ~A."
        operation))
      (otherwise
       (%simulation-compilation-error
        :unknown-axis-operation behavior "Unknown axis operation ~S." operation)))))

(defun compile-model-behavior (behavior &key effect-phase)
  "Compile a complete model behavior into ordered simulator actions.

Structured output values are intentionally abstract: (:TEXT string),
(:NAMED-KEY name), (:NAMED-SYMBOL name), (:COMMAND name), and (:MODIFIER
operation name).  They are simulator observations, never backend tokens."
  (cond
    ((typep behavior 'ivory-key.model::text-output)
     (list (emit-action (list :text (ivory-key.model::output-text behavior)))))
    ((typep behavior 'ivory-key.model::named-key-output)
     (list (emit-action
            (list :named-key
                  (model-identifier->simulation-value
                   (ivory-key.model::named-key-name behavior))))))
    ((typep behavior 'ivory-key.model::named-symbol-output)
     (list (emit-action
            (list :named-symbol
                  (model-identifier->simulation-value
                   (ivory-key.model::named-symbol-name behavior))))))
    ((typep behavior 'ivory-key.model::command-output)
     (list (emit-action
            (list :command
                  (model-identifier->simulation-value
                   (ivory-key.model::command-name behavior))))))
    ((typep behavior 'ivory-key.model::no-output-behavior) nil)
    ((typep behavior 'ivory-key.model::held-modifier-behavior)
     (unless (eq effect-phase :while)
       (%simulation-compilation-error
        :held-modifier-outside-while behavior
        "HOLD-MODIFIER requires a :WHILE lifecycle effect."))
     (list (hold-modifier-action
            (model-identifier->simulation-value
             (ivory-key.model::modifier-operation-modifier behavior)))))
    ((typep behavior 'ivory-key.model::modifier-operation-behavior)
     (let ((operation (ivory-key.model::modifier-operation behavior))
           (modifier (model-identifier->simulation-value
                      (ivory-key.model::modifier-operation-modifier behavior))))
       (list (emit-action (list :modifier operation modifier)))))
    ((typep behavior 'ivory-key.model::axis-operation-behavior)
     (%axis-operation-actions behavior :effect-phase effect-phase))
    ((typep behavior 'ivory-key.model::ordered-behavior)
     (mapcan (lambda (child)
               (compile-model-behavior child :effect-phase effect-phase))
             (ivory-key.model::ordered-behaviors behavior)))
    ((typep behavior 'ivory-key.model::simultaneous-behavior)
     ;; SIM-ACTIONs execute in a single simulator transition.  The trace is
     ;; source ordered solely to make otherwise simultaneous observations
     ;; deterministic and inspectable.
     (mapcan (lambda (child)
               (compile-model-behavior child :effect-phase effect-phase))
             (ivory-key.model::simultaneous-behaviors behavior)))
    ((or (typep behavior 'ivory-key.model::axis-choice-behavior)
         (typep behavior 'ivory-key.model::behavior-table))
     (list (%model-behavior-callback behavior :effect-phase effect-phase)))
    ((or (typep behavior 'ivory-key.model::behavior-template-parameter)
         (typep behavior 'ivory-key.model::behavior-template-reference))
     (%simulation-compilation-error
      :unresolved-behavior-template behavior
      "Resolve behavior templates before compiling simulation IR."))
    ((typep behavior 'ivory-key.model::behavior)
     (%simulation-compilation-error
      :unsupported-behavior behavior
      "No simulator action translation exists for behavior class ~S."
      (class-name (class-of behavior))))
    (t
     (%simulation-compilation-error
      :invalid-behavior behavior "Expected a model behavior, got ~S." behavior))))

(defun %execute-model-behavior (behavior candidate machine &key effect-phase)
  "Execute a context-selected behavior from a simulator callback action."
  (cond
    ((typep behavior 'ivory-key.model::axis-choice-behavior)
     (%apply-compiled-actions
      machine candidate
      (compile-model-behavior (%select-model-axis-choice behavior candidate)
                              :effect-phase effect-phase)))
    ((typep behavior 'ivory-key.model::behavior-table)
     (%apply-compiled-actions
      machine candidate
      (compile-model-behavior (%select-model-table-behavior behavior candidate)
                              :effect-phase effect-phase)))
    (t
     (%apply-compiled-actions machine candidate
                              (compile-model-behavior behavior :effect-phase effect-phase)))))

(defun %normalized-entry-actions (entries &key effect-phase)
  "Compile normalized (tuple . behavior) entries as a runtime context choice."
  (list
   (make-sim-action
    :kind :callback
    :value
    (lambda (candidate machine)
      (let ((matched nil))
        (dolist (entry entries)
          (let ((tuple (if (typep entry 'ivory-key.model::normalized-binding-entry)
                           (ivory-key.model::normalized-entry-tuple entry)
                           (car entry)))
                (behavior (if (typep entry 'ivory-key.model::normalized-binding-entry)
                              (ivory-key.model::normalized-entry-behavior entry)
                              (cdr entry))))
            (when (%tuple-matches-candidate-p tuple candidate)
            (setf matched t)
            (%apply-compiled-actions
             machine candidate
             (compile-model-behavior behavior :effect-phase effect-phase)))))
        (unless matched
          (%simulation-compilation-error
           :unresolved-normalized-context entries
           "No normalized behavior variant matches the captured simulator context.")))))))

(defun %single-participant-effect-boundaries (participants effects)
  (when effects
    (unless (= (length participants) 1)
      (%simulation-compilation-error
       :unsupported-effect-lifetime effects
       "Lifecycle effects require one participant because this simulator IR has no per-candidate anchor pattern."))
    (let ((position (model-identifier->simulation-value (first participants))))
      (values (down-pattern position) (up-pattern position)))))

(defun %compile-raw-effects (interaction candidate)
  (let* ((effects (ivory-key.model::candidate-effects candidate))
         (entry (ivory-key.model::effect-entry-behaviors effects))
         (while (ivory-key.model::effect-while-behaviors effects))
         (exit (ivory-key.model::effect-exit-behaviors effects))
         (cancel (ivory-key.model::effect-cancel-behaviors effects))
         (active (or entry while exit cancel)))
    (when active
      (make-sim-effect
       :name (list :model-effect
                   (model-identifier->simulation-value
                    (ivory-key.model::interaction-name interaction))
                   (model-identifier->simulation-value
                    (ivory-key.model::candidate-name candidate)))
       :enter-actions (append (mapcan #'compile-model-behavior entry)
                              (mapcan (lambda (behavior)
                                        (compile-model-behavior behavior :effect-phase :while))
                                      while))
       :exit-actions (mapcan #'compile-model-behavior exit)
       :cancel-actions (mapcan #'compile-model-behavior cancel)))))

(defun %normalized-effect-actions (variants &key effect-phase)
  (and variants (%normalized-entry-actions variants :effect-phase effect-phase)))

(defun %compile-normalized-effects (interaction candidate)
  (let* ((effects (ivory-key.model::normalized-candidate-effects candidate))
         (entry (getf effects :entry))
         (while (getf effects :while))
         (while-release (getf effects :while-release))
         (exit (getf effects :exit))
         (cancel (getf effects :cancel))
         (active (or entry while exit cancel)))
    (when active
      (unless (eq while-release :owner-terminal)
        (%simulation-compilation-error
         :invalid-normalized-held-lifecycle candidate
         "Normalized :WHILE effects must declare :OWNER-TERMINAL release."))
      (make-sim-effect
       :name (list :normalized-model-effect
                   (model-identifier->simulation-value
                    (ivory-key.model::normalized-interaction-name interaction))
                   (model-identifier->simulation-value
                    (ivory-key.model::normalized-candidate-name candidate)))
       :enter-actions (append (%normalized-effect-actions entry)
                              (%normalized-effect-actions while :effect-phase :while))
       :exit-actions (%normalized-effect-actions exit)
       :cancel-actions (%normalized-effect-actions cancel)))))

(defun %commit-pattern (commit candidate)
  (cond
    ((eq commit :when-matched) :when-matched)
    ((eq commit :when-unambiguous)
     (%simulation-compilation-error
      :unsupported-commit-policy candidate
      "The simulator has no WHEN-UNAMBIGUOUS commit scheduler."))
    ((typep commit 'ivory-key.model::temporal-pattern)
     (compile-model-temporal-pattern commit))
    (t
     (%simulation-compilation-error
      :invalid-commit-point candidate
      "A simulator commit point must be :WHEN-MATCHED or a temporal pattern, not ~S."
      commit))))

(defun %candidate-priority (candidate-name arbitration)
  (cond
    ((null arbitration) 0)
    ((eq (first arbitration) :priority)
     (let* ((ordered (second arbitration))
            (position (position candidate-name ordered :test #'ivory-key.model::identifier=)))
       (if position (- (length ordered) position) 0)))
    ((eq (first arbitration) :longest-match)
     (%simulation-compilation-error
      :unsupported-arbitration arbitration
      "The simulator's longest-match comparison cannot implement model longest-match arbitration."))
    (t
     (%simulation-compilation-error
      :unknown-arbitration arbitration "Unknown model arbitration declaration ~S." arbitration))))

(defun %validate-simulation-interaction-scope (participants observe anchor object)
  (unless (member observe '(:participants :any-position) :test #'eq)
    (%simulation-compilation-error
     :unknown-observation-scope object "Unknown interaction observation scope ~S." observe))
  (when anchor
    ;; The machine starts a candidate for every participant DOWN.  With one
    ;; participant that is equivalent to a declared anchor; with several it is
    ;; observably broader than the source declaration.
    (unless (and (= (length participants) 1)
                 (ivory-key.model::identifier=
                  anchor (first participants)))
      (%simulation-compilation-error
       :unsupported-interaction-anchor object
       "The simulator can honor an explicit anchor only for a one-participant interaction."))))

(defun compile-model-interaction-candidate (candidate interaction &key priority)
  "Compile one raw model candidate into a SIM-CASE."
  (unless (eq (ivory-key.model::candidate-context-policy candidate) :anchor-down)
    (%simulation-compilation-error
     :unsupported-context-policy candidate
     "The simulator captures context at candidate anchor-down, not at ~S."
     (ivory-key.model::candidate-context-policy candidate)))
  (let* ((effect (%compile-raw-effects interaction candidate))
         (active-effects (and effect (list effect))))
    (multiple-value-bind (enter-at exit-at)
        (%single-participant-effect-boundaries
         (ivory-key.model::interaction-participants interaction) active-effects)
      (make-sim-case
       :name (model-identifier->simulation-value (ivory-key.model::candidate-name candidate))
       :pattern (compile-model-temporal-pattern
                 (ivory-key.model::candidate-match candidate))
       :commit (%commit-pattern (ivory-key.model::candidate-commit candidate) candidate)
       :enter-at enter-at
       :exit-at exit-at
       :effects active-effects
       :actions
       (compile-model-behavior (ivory-key.model::candidate-behavior candidate))
       :commit-actions
       (mapcan #'compile-model-behavior
               (ivory-key.model::effect-commit-behaviors
                (ivory-key.model::candidate-effects candidate)))
       :priority (or priority 0)
       :consulted-latches
       (mapcar #'model-identifier->simulation-value
               (ivory-key.model::candidate-axis-dependencies candidate))))))

(defun compile-model-interaction (interaction)
  "Compile one raw model INTERACTION into a simulator interaction."
  (unless (typep interaction 'ivory-key.model::interaction)
    (%simulation-compilation-error
     :invalid-interaction interaction "Expected a model interaction, got ~S." interaction))
  (let* ((participants (ivory-key.model::interaction-participants interaction))
         (arbitration (ivory-key.model::interaction-arbitration interaction)))
    (%validate-simulation-interaction-scope
     participants (ivory-key.model::interaction-observe interaction)
     (ivory-key.model::interaction-anchor interaction) interaction)
    (make-sim-interaction
     :name (model-identifier->simulation-value (ivory-key.model::interaction-name interaction))
     :participants (mapcar #'model-identifier->simulation-value participants)
     :arbitration :priority
     :cases
     (mapcar (lambda (candidate)
               (compile-model-interaction-candidate
                candidate interaction
                :priority (%candidate-priority
                           (ivory-key.model::candidate-name candidate) arbitration)))
             (ivory-key.model::interaction-candidates interaction)))))

(defun compile-model-interactions (interactions)
  "Compile raw model interactions in source order into simulator IR."
  (mapcar #'compile-model-interaction interactions))

(defun compile-normalized-interaction-candidate (candidate interaction &key priority)
  "Compile one normalized model candidate into a SIM-CASE."
  (unless (eq (ivory-key.model::normalized-candidate-context-policy candidate)
              :anchor-down)
    (%simulation-compilation-error
     :unsupported-context-policy candidate
     "The simulator captures context at candidate anchor-down, not at ~S."
     (ivory-key.model::normalized-candidate-context-policy candidate)))
  (let* ((effect (%compile-normalized-effects interaction candidate))
         (active-effects (and effect (list effect))))
    (multiple-value-bind (enter-at exit-at)
        (%single-participant-effect-boundaries
         (ivory-key.model::normalized-interaction-participants interaction) active-effects)
      (make-sim-case
       :name (model-identifier->simulation-value
              (ivory-key.model::normalized-candidate-name candidate))
       :pattern (compile-model-temporal-pattern
                 (ivory-key.model::normalized-candidate-match candidate))
       :commit (%commit-pattern (ivory-key.model::normalized-candidate-commit candidate)
                                candidate)
       :enter-at enter-at
       :exit-at exit-at
       :effects active-effects
       :actions
       (%normalized-entry-actions
        (ivory-key.model::normalized-candidate-entries candidate))
       :commit-actions
       (%normalized-effect-actions
        (getf (ivory-key.model::normalized-candidate-effects candidate) :commit))
       :priority (or priority 0)
       :consulted-latches
       (mapcar #'model-identifier->simulation-value
               (ivory-key.model::normalized-candidate-context-axes candidate))))))

(defun compile-normalized-interaction (interaction)
  "Compile a normalized interaction into a simulator interaction."
  (unless (typep interaction 'ivory-key.model::normalized-interaction)
    (%simulation-compilation-error
     :invalid-normalized-interaction interaction
     "Expected a normalized model interaction, got ~S." interaction))
  (let* ((participants (ivory-key.model::normalized-interaction-participants interaction))
         (arbitration (ivory-key.model::normalized-interaction-arbitration interaction)))
    (%validate-simulation-interaction-scope
     participants (ivory-key.model::normalized-interaction-observe interaction)
     (ivory-key.model::normalized-interaction-anchor interaction) interaction)
    (make-sim-interaction
     :name (model-identifier->simulation-value
            (ivory-key.model::normalized-interaction-name interaction))
     :participants (mapcar #'model-identifier->simulation-value participants)
     :arbitration :priority
     :cases
     (mapcar (lambda (candidate)
               (compile-normalized-interaction-candidate
                candidate interaction
                :priority (%candidate-priority
                           (ivory-key.model::normalized-candidate-name candidate) arbitration)))
             (ivory-key.model::normalized-interaction-candidates interaction)))))

(defun compile-normalized-interactions (interactions)
  "Compile normalized model interactions in canonical order into simulator IR."
  (mapcar #'compile-normalized-interaction interactions))

(defun model-layout-simulator-axes (layout)
  "Return LAYOUT's default axis state as simulator (axis . state) pairs."
  (mapcar (lambda (axis)
            (cons (model-identifier->simulation-value
                   (ivory-key.model::axis-name axis))
                  (model-identifier->simulation-value
                   (ivory-key.model::axis-default-state axis))))
          (ivory-key.model::layout-axes layout)))

(defun compile-model-layout-interactions (layout &key (normalize t))
  "Compile LAYOUT's declared interactions and return interactions plus defaults.

The first value is a list of SIM-INTERACTION objects.  The second is the
default simulator axis alist.  Ordinary bindings and overlay resolution are
intentionally outside this adapter: the present simulator IR has no binding
dispatch node, whereas interaction compilation is a direct semantic lowering.
When NORMALIZE is true, use the canonical normalized interaction variants."
  (unless (typep layout 'ivory-key.model::layout)
    (%simulation-compilation-error
     :invalid-layout layout "Expected a model layout, got ~S." layout))
  (let ((defaults (model-layout-simulator-axes layout)))
    (if normalize
        (let ((normalized (ivory-key.model::normalize-layout layout)))
          (values (compile-normalized-interactions
                   (ivory-key.model::normalized-layout-interactions normalized))
                  defaults))
        (values (compile-model-interactions
                 (ivory-key.model::layout-interactions layout))
                defaults))))
