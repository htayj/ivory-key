;;;; SPDX-License-Identifier: GPL-3.0-or-later
;;;; Reference finite timed-event transducer.

(in-package #:ivory-key.simulate)

(define-condition simulation-error (error) ())

(define-condition malformed-event-stream (simulation-error)
  ((event :initarg :event :reader malformed-event-stream-event)
   (reason :initarg :reason :reader malformed-event-stream-reason))
  (:report (lambda (condition stream)
             (format stream "Malformed event stream at ~S: ~A"
                     (malformed-event-stream-event condition)
                     (malformed-event-stream-reason condition)))))

(define-condition simulation-ambiguity (simulation-error)
  ((left :initarg :left :reader simulation-ambiguity-left)
   (right :initarg :right :reader simulation-ambiguity-right))
  (:report (lambda (condition stream)
             (format stream "Incompatible candidates ~S and ~S commit without arbitration."
                     (simulation-ambiguity-left condition)
                     (simulation-ambiguity-right condition)))))

(define-condition held-action-outside-effect (simulation-error)
  ((candidate :initarg :candidate :reader held-action-outside-effect-candidate))
  (:report (lambda (condition stream)
             (format stream "Held simulator action has no active lifecycle effect~@[ for candidate ~S~]."
                     (held-action-outside-effect-candidate condition)))))

(define-condition held-axis-state-conflict (simulation-error)
  ((axis :initarg :axis :reader held-axis-state-conflict-axis)
   (existing-state :initarg :existing-state
                   :reader held-axis-state-conflict-existing-state)
   (requested-state :initarg :requested-state
                    :reader held-axis-state-conflict-requested-state)
   (existing-owners :initarg :existing-owners
                    :reader held-axis-state-conflict-existing-owners)
   (requested-owner :initarg :requested-owner
                    :reader held-axis-state-conflict-requested-owner))
  (:report (lambda (condition stream)
             (format stream "Conflicting held states for axis ~S: ~S is active; ~S was requested."
                     (held-axis-state-conflict-axis condition)
                     (held-axis-state-conflict-existing-state condition)
                     (held-axis-state-conflict-requested-state condition)))))

(defstruct (sim-action
             (:constructor %make-sim-action (&key kind target value resolver)))
  "A backend-neutral action used by a normalized simulator fixture or IR.

Only :EMIT is irreversible.  :LATCH and :SET-AXIS mutate abstract context;
their application is visible in the trace and never happens speculatively.
The :HOLD-AXIS and :HOLD-MODIFIER actions are owner-scoped reversible
contributions; they may run only while a SIM-EFFECT is active."
  kind
  target
  value
  resolver)

(defun make-sim-action (&key kind target value resolver)
  (unless (member kind '(:emit :latch :set-axis :clear-latch :callback
                        :hold-axis :hold-modifier)
                  :test #'eq)
    (error "Unknown simulator action kind ~S." kind))
  (when (and resolver (not (functionp resolver)))
    (error "An action resolver must be a function."))
  (%make-sim-action :kind kind :target target :value value :resolver resolver))

(defun emit-action (value &key resolver)
  (make-sim-action :kind :emit :value value :resolver resolver))

(defun latch-action (axis value)
  (make-sim-action :kind :latch :target axis :value value))

(defun set-axis-action (axis value)
  (make-sim-action :kind :set-axis :target axis :value value))

(defun clear-latch-action (axis)
  (make-sim-action :kind :clear-latch :target axis))

(defun hold-axis-action (axis state)
  "Acquire STATE of AXIS for the current lifecycle effect.

This is intentionally simulator-internal IR: source holds obtain their owner
identity from the effect that contains a :WHILE behavior, not from a backend
token or an application-visible reference count."
  (make-sim-action :kind :hold-axis :target axis :value state))

(defun hold-modifier-action (modifier)
  "Acquire MODIFIER for the current lifecycle effect."
  (make-sim-action :kind :hold-modifier :target modifier))

(defstruct (sim-effect
             (:constructor make-sim-effect
                 (&key name enter-actions exit-actions cancel-actions)))
  "A reversible effect with explicit lifecycle actions.

An effect's identity remains active between its enter and exit transitions;
it is not represented as a premature irreversible keyboard output."
  name
  (enter-actions nil :type list)
  (exit-actions nil :type list)
  (cancel-actions nil :type list))

(defstruct (sim-case
             (:constructor make-sim-case
                 (&key name pattern (commit :when-matched) enter-at exit-at cancel-at
                       effects actions commit-actions (priority 0) consulted-latches)))
  "One finite interpretation of an interaction.

PATTERN determines validity.  COMMIT is either :WHEN-MATCHED or another
pattern.  ENTER-AT and EXIT-AT allow a held effect to have an independently
observable reversible lifetime."
  name
  pattern
  (commit :when-matched)
  enter-at
  exit-at
  cancel-at
  (effects nil :type list)
  (actions nil :type list)
  ;; Commit effects remain distinct from ordinary :DO actions so their trace
  ;; provenance does not mislabel them as ordinary candidate output.
  (commit-actions nil :type list)
  (priority 0 :type integer)
  (consulted-latches nil :type list))

(defstruct (sim-interaction
             (:constructor make-sim-interaction
                 (&key name participants cases (priority 0) (arbitration :priority)
                       consulted-latches)))
  "A declarative interaction and its mutually competing cases.

ARBITRATION is :PRIORITY or :LONGEST-MATCH.  A priority is never inferred
from host iteration order."
  name
  (participants nil :type list)
  (cases nil :type list)
  (priority 0 :type integer)
  (arbitration :priority)
  (consulted-latches nil :type list))

(defstruct (latch-cell (:constructor make-latch-cell (value generation)))
  value
  (generation 0 :type integer))

(defstruct (held-axis-cell (:constructor make-held-axis-cell (state owners)))
  "One effective held state and the effect owners currently contributing it."
  state
  (owners nil :type list))

(defstruct (held-modifier-cell (:constructor make-held-modifier-cell (owners)))
  "The effect owners currently contributing one semantic modifier."
  (owners nil :type list))

(defstruct (simulation-candidate
             (:constructor %make-simulation-candidate
                 (&key id interaction case anchor-index context latch-snapshot deadlines)))
  id
  interaction
  case
  (anchor-index 0 :type fixnum)
  context
  (latch-snapshot nil :type list)
  (deadlines nil :type list)
  (status :viable :type keyword)
  (effect-state (make-hash-table :test #'eq))
  (claimed-event-indices nil :type list))

(defstruct (simulation-result
             (:constructor make-simulation-result
                 (&key outputs trace latches axes active-effects candidates)))
  (outputs nil :type list)
  (trace nil :type list)
  (latches nil :type list)
  (axes nil :type list)
  (active-effects nil :type list)
  (candidates nil :type list))

(defstruct (simulator
             (:constructor %make-simulator
                 (&key interactions now events-reversed trace-reversed outputs-reversed
                       candidates pressed latches axes active-effects claimed-events
                       held-axis-contributions held-modifier-contributions
                       next-candidate-id next-latch-generation)))
  (interactions nil :type list)
  (now 0 :type timestamp)
  (events-reversed nil :type list)
  (trace-reversed nil :type list)
  (outputs-reversed nil :type list)
  (candidates nil :type list)
  (pressed (make-hash-table :test #'equal))
  (latches (make-hash-table :test #'equal))
  ;; AXES contains direct SET-AXIS state.  Held-axis contributions overlay it
  ;; while one or more owners remain active, so a reset in one owner's EXIT
  ;; cannot switch away from a state held by another owner.
  (axes (make-hash-table :test #'equal))
  (held-axis-contributions (make-hash-table :test #'equal))
  (held-modifier-contributions (make-hash-table :test #'equal))
  ;; Each entry is (candidate . effect), preserving per-candidate lifetime.
  (active-effects nil :type list)
  (claimed-events (make-hash-table :test #'eql))
  (next-candidate-id 0 :type integer)
  (next-latch-generation 0 :type integer))

(defvar *simulation-execution-provenance* nil
  "Dynamically bound while a candidate or lifecycle effect performs actions.

Simulator callbacks can expand a selected model behavior into further
SIM-ACTIONs.  The binding makes those nested, otherwise ordinary actions retain
the same source interpretation without adding an implementation-specific
callback protocol.")

(defvar *simulation-active-effect* nil
  "The lifecycle effect currently applying simulator actions.

Only an active effect may own a held axis or modifier contribution.  Binding
this dynamically keeps SIM-ACTION compact while preserving identity through
callbacks selected from normalized behavior tables.")

(defun canonical-pattern-provenance (pattern)
  "Return a closed canonical representation of a compiled source PATTERN.

The reference machine intentionally records pattern semantics rather than a
host object address or a reader form.  This representation is suitable for the
deterministic simulation dump and is the same for direct simulator IR and
model-compiled IR."
  (when pattern
    (ecase (event-pattern-kind pattern)
      (:event
       (list :event (event-pattern-event-kind pattern)
             (event-pattern-position pattern)))
      ((:sequence :all :either :and)
       (cons (event-pattern-kind pattern)
             (mapcar #'canonical-pattern-provenance
                     (event-pattern-children pattern))))
      (:duration
       (list :duration (event-pattern-position pattern)
             :at-least (event-pattern-at-least pattern)
             :less-than (event-pattern-less-than pattern)))
      (:deadline
       (list :deadline (event-pattern-milliseconds pattern)
             :after-position (event-pattern-after-position pattern)
             :while-down (event-pattern-while-down pattern)))
      (:within
       (list :within (event-pattern-milliseconds pattern)
             (canonical-pattern-provenance (first (event-pattern-children pattern)))
             (canonical-pattern-provenance (second (event-pattern-children pattern)))))
      (:overlap
       (cons :overlap
             (mapcar (lambda (child)
                       ;; Direct simulator IR stores logical overlap positions,
                       ;; while compiled/extended IR may retain event-pattern
                       ;; children.  Canonicalize either representation; never
                       ;; leave a host EVENT-PATTERN struct in provenance.
                       (if (typep child 'event-pattern)
                           (canonical-pattern-provenance child)
                           (list :position child)))
                     (event-pattern-children pattern))))
      (:without
       (list :without
             :forbidden (canonical-pattern-provenance (event-pattern-forbidden pattern))
             :between (list (canonical-pattern-provenance
                             (event-pattern-start-pattern pattern))
                            (canonical-pattern-provenance
                             (event-pattern-end-pattern pattern)))))
      (:repeat
       (list :repeat
             (canonical-pattern-provenance (first (event-pattern-children pattern)))
             :at-least (event-pattern-repeat-min pattern)
             :at-most (event-pattern-repeat-max pattern))))))

(defun candidate-commit-point-provenance (candidate)
  (let ((commit (sim-case-commit (simulation-candidate-case candidate))))
    (if (eq commit :when-matched)
        :when-matched
        (canonical-pattern-provenance commit))))

(defun candidate-provenance (candidate transition &key source-pattern
                                                   (responsible-effect :candidate-do))
  "Build the stable trace origin for one CANDIDATE transition.

SOURCE-PATTERN defaults to the candidate's match pattern.  Lifecycle callers
substitute their ENTER-AT, EXIT-AT, or CANCEL-AT trigger.  RESPONSIBLE-EFFECT
is :CANDIDATE-DO for ordinary actions, or a structured lifecycle identity."
  (let ((case (simulation-candidate-case candidate)))
    (list :source-pattern
          (canonical-pattern-provenance (or source-pattern (sim-case-pattern case)))
          :candidate-transition transition
          :commit-point (candidate-commit-point-provenance candidate)
          :responsible-effect responsible-effect)))

(defun effect-provenance (effect phase)
  (list :effect (sim-effect-name effect) :phase phase))

(defun trace-entry (machine kind &key event interaction case candidate details provenance)
  "Append one explainable transition at the machine's monotonic clock time."
  (push (make-simulation-trace-entry
         :time (simulator-now machine)
         :kind kind
         :event event
         :interaction interaction
         :case case
         :candidate candidate
         :details details
         :provenance (or provenance *simulation-execution-provenance*))
        (simulator-trace-reversed machine)))

(defun make-simulator (&key interactions latches axes)
  "Create an empty reference machine.  LATCHES and AXES are (name . value) lists."
  (let ((machine (%make-simulator :interactions interactions)))
    (dolist (entry latches)
      (setf (gethash (car entry) (simulator-latches machine))
            (make-latch-cell (cdr entry)
                             (incf (simulator-next-latch-generation machine)))))
    (dolist (entry axes)
      (setf (gethash (car entry) (simulator-axes machine)) (cdr entry)))
    machine))

(defun hash-table-alist (table)
  (let ((entries nil))
    (maphash (lambda (key value) (push (cons key value) entries)) table)
    (sort entries #'string< :key (lambda (entry) (princ-to-string (car entry))))))

(defun simulator-events (machine)
  (nreverse (copy-list (simulator-events-reversed machine))))

(defun simulator-trace (machine)
  (nreverse (copy-list (simulator-trace-reversed machine))))

(defun simulator-outputs (machine)
  (nreverse (copy-list (simulator-outputs-reversed machine))))

(defun simulator-latches-alist (machine)
  (mapcar (lambda (entry) (cons (car entry) (latch-cell-value (cdr entry))))
          (hash-table-alist (simulator-latches machine))))

(defun simulator-axes-alist (machine)
  "Return effective axis states: held values overlay direct SET-AXIS values."
  (let ((keys nil))
    (maphash (lambda (axis value)
               (declare (ignore value))
               (pushnew axis keys :test #'equal))
             (simulator-axes machine))
    (maphash (lambda (axis cell)
               (declare (ignore cell))
               (pushnew axis keys :test #'equal))
             (simulator-held-axis-contributions machine))
    (mapcar (lambda (axis) (cons axis (simulator-axis-value machine axis)))
            (sort keys #'string< :key #'princ-to-string))))

(defun simulator-active-effect-names (machine)
  (mapcar (lambda (entry) (sim-effect-name (cdr entry)))
          (reverse (simulator-active-effects machine))))

(defun simulator-latch-axis (machine axis value &key interaction case candidate)
  "Set AXIS's latch as a fresh generation.  Capture/consume compares this
generation, so a candidate cannot consume a later latch of the same name.

The optional provenance owner arguments preserve the candidate identity for a
latch action reached through APPLY-SIM-ACTION; direct simulator control calls
remain valid and deliberately have no candidate owner."
  (let ((generation (incf (simulator-next-latch-generation machine))))
    (setf (gethash axis (simulator-latches machine))
          (make-latch-cell value generation))
    (trace-entry machine :latch-set
                 :interaction interaction :case case :candidate candidate
                 :details (list axis value generation))
    value))

(defun simulator-latched-value (machine axis &optional default)
  (let ((cell (gethash axis (simulator-latches machine))))
    (if cell (latch-cell-value cell) default)))

(defun simulator-set-axis (machine axis value &key interaction case candidate)
  "Set AXIS's direct/base state, retaining a candidate owner when supplied.

An active held contribution overlays this value in SIMULATOR-AXES-ALIST.  SET
is deliberately not a held contribution and therefore neither acquires nor
releases another effect's owner-scoped state."
  (setf (gethash axis (simulator-axes machine)) value)
  (trace-entry machine :axis-set
               :interaction interaction :case case :candidate candidate
               :details (list axis value))
  value)

(defun simulator-axis-value (machine axis &optional default)
  "Return AXIS's effective value, preferring an active held contribution."
  (let ((held (gethash axis (simulator-held-axis-contributions machine))))
    (if held
        (held-axis-cell-state held)
        (gethash axis (simulator-axes machine) default))))

(defun held-owner (candidate)
  (unless *simulation-active-effect*
    (error 'held-action-outside-effect :candidate candidate))
  (cons candidate *simulation-active-effect*))

(defun held-owner= (left right)
  (and (eq (car left) (car right)) (eq (cdr left) (cdr right))))

(defun held-owner-description (owner)
  (list :candidate (simulation-candidate-id (car owner))
        :effect (sim-effect-name (cdr owner))))

(defun %record-held-modifier-output (machine candidate operation modifier)
  (let ((value (list :modifier operation modifier)))
    (push value (simulator-outputs-reversed machine))
    (trace-entry machine :action
                 :interaction (simulation-candidate-interaction candidate)
                 :case (simulation-candidate-case candidate) :candidate candidate
                 :details (list :emit value))))

(defun simulator-acquire-held-axis (machine candidate axis state)
  "Add the current effect as an owner of AXIS=STATE, or fail on a conflict."
  (let* ((owner (held-owner candidate))
         (cell (gethash axis (simulator-held-axis-contributions machine))))
    (cond
      ((null cell)
       (setf cell (make-held-axis-cell state (list owner))
             (gethash axis (simulator-held-axis-contributions machine)) cell)
       (trace-entry machine :held-axis-acquire
                    :interaction (simulation-candidate-interaction candidate)
                    :case (simulation-candidate-case candidate) :candidate candidate
                    :details (list axis state :owner (held-owner-description owner)
                                   :first t)))
      ((not (equal state (held-axis-cell-state cell)))
       (error 'held-axis-state-conflict
              :axis axis
              :existing-state (held-axis-cell-state cell)
              :requested-state state
              :existing-owners (mapcar #'held-owner-description
                                        (held-axis-cell-owners cell))
              :requested-owner (held-owner-description owner)))
      ((not (member owner (held-axis-cell-owners cell) :test #'held-owner=))
       (push owner (held-axis-cell-owners cell))
       (trace-entry machine :held-axis-acquire
                    :interaction (simulation-candidate-interaction candidate)
                    :case (simulation-candidate-case candidate) :candidate candidate
                    :details (list axis state :owner (held-owner-description owner)
                                   :first nil))))
  state))

(defun simulator-acquire-held-modifier (machine candidate modifier)
  "Add the current effect as an owner of MODIFIER and press on first acquire."
  (let* ((owner (held-owner candidate))
         (cell (gethash modifier (simulator-held-modifier-contributions machine))))
    (cond
      ((null cell)
       (setf cell (make-held-modifier-cell (list owner))
             (gethash modifier (simulator-held-modifier-contributions machine)) cell)
       (%record-held-modifier-output machine candidate :press modifier)
       (trace-entry machine :held-modifier-acquire
                    :interaction (simulation-candidate-interaction candidate)
                    :case (simulation-candidate-case candidate) :candidate candidate
                    :details (list modifier :owner (held-owner-description owner)
                                   :first t)))
      ((not (member owner (held-modifier-cell-owners cell) :test #'held-owner=))
       (push owner (held-modifier-cell-owners cell))
       (trace-entry machine :held-modifier-acquire
                    :interaction (simulation-candidate-interaction candidate)
                    :case (simulation-candidate-case candidate) :candidate candidate
                    :details (list modifier :owner (held-owner-description owner)
                                   :first nil))))
  modifier))

(defun simulator-release-held-contributions (machine candidate effect)
  "Remove exactly EFFECT's contributions for CANDIDATE.

Every matching axis and modifier is visited in canonical order.  The final
release reveals an axis's direct/base value and emits a semantic modifier
release; intermediate releases only reduce ownership."
  (let ((owner (cons candidate effect)))
    (dolist (axis (sort (loop for key being the hash-keys of
                                  (simulator-held-axis-contributions machine)
                              collect key)
                        #'string< :key #'princ-to-string))
      (let ((cell (gethash axis (simulator-held-axis-contributions machine))))
        (when (member owner (held-axis-cell-owners cell) :test #'held-owner=)
          (setf (held-axis-cell-owners cell)
                (remove owner (held-axis-cell-owners cell) :test #'held-owner=))
          (let ((last (endp (held-axis-cell-owners cell))))
            (when last
              (remhash axis (simulator-held-axis-contributions machine)))
            (trace-entry machine :held-axis-release
                         :interaction (simulation-candidate-interaction candidate)
                         :case (simulation-candidate-case candidate) :candidate candidate
                         :details (list axis (held-axis-cell-state cell)
                                        :owner (held-owner-description owner)
                                        :last last))))))
    (dolist (modifier (sort (loop for key being the hash-keys of
                                      (simulator-held-modifier-contributions machine)
                                  collect key)
                            #'string< :key #'princ-to-string))
      (let ((cell (gethash modifier (simulator-held-modifier-contributions machine))))
        (when (member owner (held-modifier-cell-owners cell) :test #'held-owner=)
          (setf (held-modifier-cell-owners cell)
                (remove owner (held-modifier-cell-owners cell) :test #'held-owner=))
          (let ((last (endp (held-modifier-cell-owners cell))))
            (when last
              (remhash modifier (simulator-held-modifier-contributions machine))
              (%record-held-modifier-output machine candidate :release modifier))
            (trace-entry machine :held-modifier-release
                         :interaction (simulation-candidate-interaction candidate)
                         :case (simulation-candidate-case candidate) :candidate candidate
                         :details (list modifier :owner (held-owner-description owner)
                                        :last last)))))))
  machine)

(defun simulator-event-vector (machine)
  (coerce (simulator-events machine) 'vector))

(defun candidate-pattern-context (machine candidate)
  (let ((events (simulator-event-vector machine)))
    (make-pattern-match-context :events events
                                :start-index (simulation-candidate-anchor-index candidate)
                                :anchor-index (simulation-candidate-anchor-index candidate))))

(defun candidate-all-deadline-patterns (case)
  (remove-duplicates
   (append (collect-deadline-patterns (sim-case-pattern case))
           (and (typep (sim-case-commit case) 'event-pattern)
                (collect-deadline-patterns (sim-case-commit case)))
           (collect-deadline-patterns (sim-case-enter-at case))
           (collect-deadline-patterns (sim-case-exit-at case))
           (collect-deadline-patterns (sim-case-cancel-at case)))
   :test #'eq))

(defun deadline-time-for-candidate (machine candidate pattern)
  (let* ((events (simulator-event-vector machine))
         (anchor (aref events (simulation-candidate-anchor-index candidate)))
         (after (or (event-pattern-after-position pattern) (timed-event-position anchor))))
    ;; Candidate starts are physical down events.  An unrelated AFTER position
    ;; must occur after its start to arm the finite clock.
    (when (equal after (timed-event-position anchor))
      (+ (timed-event-time anchor) (event-pattern-milliseconds pattern)))))

(defun snapshot-latches (machine axes)
  (loop for axis in axes
        for cell = (gethash axis (simulator-latches machine))
        when cell collect (list axis (latch-cell-value cell) (latch-cell-generation cell))))

(defun candidate-consulted-latches (candidate)
  (remove-duplicates
   (append (sim-interaction-consulted-latches (simulation-candidate-interaction candidate))
           (sim-case-consulted-latches (simulation-candidate-case candidate)))
   :test #'equal))

(defun start-candidate (machine interaction case anchor-index)
  (let* ((id (incf (simulator-next-candidate-id machine)))
         (candidate (%make-simulation-candidate
                     :id id :interaction interaction :case case
                     :anchor-index anchor-index
                     :context (simulator-axes-alist machine)
                     :latch-snapshot
                     (snapshot-latches machine
                                      (remove-duplicates
                                       (append (sim-interaction-consulted-latches interaction)
                                               (sim-case-consulted-latches case))
                                       :test #'equal)))))
    (setf (simulation-candidate-deadlines candidate)
          (remove nil (mapcar (lambda (pattern)
                                (deadline-time-for-candidate machine candidate pattern))
                              (candidate-all-deadline-patterns case))))
    (push candidate (simulator-candidates machine))
    (trace-entry machine :candidate-start :interaction interaction :case case
                 :candidate candidate
                 :details (list :anchor-index anchor-index
                                :context (simulation-candidate-context candidate))
                 :provenance (candidate-provenance candidate :started
                                                   :responsible-effect :none))
    candidate))

(defun candidate-effect-entered-p (candidate effect)
  (eq (gethash effect (simulation-candidate-effect-state candidate)) :active))

(defun candidate-effect-terminal-p (candidate effect)
  "Whether EFFECT has completed a one-way exit or cancellation for CANDIDATE."
  (member (gethash effect (simulation-candidate-effect-state candidate))
          '(:exited :cancelled)
          :test #'eq))

(defun action-value (action machine candidate)
  (if (sim-action-resolver action)
      (funcall (sim-action-resolver action) candidate machine)
      (sim-action-value action)))

(defun apply-sim-action (machine candidate action)
  (let ((value (action-value action machine candidate)))
    (ecase (sim-action-kind action)
      (:emit
       (push value (simulator-outputs-reversed machine))
       (trace-entry machine :action :interaction (simulation-candidate-interaction candidate)
                    :case (simulation-candidate-case candidate) :candidate candidate
                    :details (list :emit value)))
      (:latch
       (simulator-latch-axis
        machine (sim-action-target action) value
        :interaction (simulation-candidate-interaction candidate)
        :case (simulation-candidate-case candidate)
        :candidate candidate))
      (:set-axis
       (simulator-set-axis
        machine (sim-action-target action) value
        :interaction (simulation-candidate-interaction candidate)
        :case (simulation-candidate-case candidate)
        :candidate candidate))
      (:hold-axis
       (simulator-acquire-held-axis
        machine candidate (sim-action-target action) value))
      (:hold-modifier
       (simulator-acquire-held-modifier
        machine candidate (sim-action-target action)))
      (:clear-latch
       (remhash (sim-action-target action) (simulator-latches machine))
       (trace-entry machine :latch-cleared
                    :interaction (simulation-candidate-interaction candidate)
                    :case (simulation-candidate-case candidate)
                    :candidate candidate
                    :details (sim-action-target action)))
      (:callback
       ;; A callback is an integration hook for normalized behavior objects.
       ;; It receives the candidate and machine and owns no hidden commit path.
       (when (functionp value) (funcall value candidate machine)))))
  machine)

(defun enter-effect (machine candidate effect)
  ;; Entry predicates remain matched in an ever-growing event prefix.  An
  ;; exited or cancelled effect must therefore retain a terminal marker rather
  ;; than being removed from EFFECT-STATE, or an unrelated later event would
  ;; re-enter a lifecycle that has already ended.
  (unless (or (candidate-effect-entered-p candidate effect)
              (candidate-effect-terminal-p candidate effect))
    (setf (gethash effect (simulation-candidate-effect-state candidate)) :active)
    (push (cons candidate effect) (simulator-active-effects machine))
    (let ((*simulation-execution-provenance*
            (candidate-provenance
             candidate :effect-entered
             :source-pattern (or (sim-case-enter-at (simulation-candidate-case candidate))
                                 (sim-case-pattern (simulation-candidate-case candidate)))
             :responsible-effect (effect-provenance effect :entry)))
          (*simulation-active-effect* effect))
      (dolist (action (sim-effect-enter-actions effect))
        (apply-sim-action machine candidate action))
      (trace-entry machine :effect-enter
                   :interaction (simulation-candidate-interaction candidate)
                   :case (simulation-candidate-case candidate) :candidate candidate
                   :details (sim-effect-name effect))))
  candidate)

(defun leave-effect (machine candidate effect transition)
  (when (candidate-effect-entered-p candidate effect)
    (let* ((case (simulation-candidate-case candidate))
           (source-pattern (ecase transition
                             (:exit (or (sim-case-exit-at case) (sim-case-pattern case)))
                             (:cancel (or (sim-case-cancel-at case) (sim-case-pattern case)))))
           (*simulation-execution-provenance*
             (candidate-provenance
              candidate (ecase transition (:exit :effect-exited) (:cancel :effect-cancelled))
              :source-pattern source-pattern
              :responsible-effect (effect-provenance effect transition)))
           (*simulation-active-effect* effect))
      (dolist (action (ecase transition
                        (:exit (sim-effect-exit-actions effect))
                        (:cancel (sim-effect-cancel-actions effect))))
        (apply-sim-action machine candidate action))
      ;; A source :WHILE hold has an exact release at every terminal effect
      ;; boundary.  Explicit EXIT/CANCEL actions above may set a base axis but
      ;; cannot remove another active effect's contribution.
      (simulator-release-held-contributions machine candidate effect)
      (setf (gethash effect (simulation-candidate-effect-state candidate))
            (ecase transition
              (:exit :exited)
              (:cancel :cancelled)))
      (setf (simulator-active-effects machine)
            (remove-if (lambda (entry)
                         (and (eq (car entry) candidate) (eq (cdr entry) effect)))
                       (simulator-active-effects machine)))
      (trace-entry machine (ecase transition (:exit :effect-exit) (:cancel :effect-cancel))
                   :interaction (simulation-candidate-interaction candidate)
                   :case (simulation-candidate-case candidate) :candidate candidate
                   :details (sim-effect-name effect))))
  candidate)

(defun candidate-enter-effects (machine candidate)
  (dolist (effect (sim-case-effects (simulation-candidate-case candidate)))
    (enter-effect machine candidate effect)))

(defun candidate-exit-effects (machine candidate transition)
  (dolist (effect (sim-case-effects (simulation-candidate-case candidate)))
    (leave-effect machine candidate effect transition)))

(defun candidate-main-status (machine candidate)
  (pattern-status (sim-case-pattern (simulation-candidate-case candidate))
                  (candidate-pattern-context machine candidate)))

(defun candidate-commit-ready-p (machine candidate)
  (let ((commit (sim-case-commit (simulation-candidate-case candidate)))
        (context (candidate-pattern-context machine candidate)))
    (if (eq commit :when-matched)
        (eq (candidate-main-status machine candidate) :matched)
        (eq (pattern-status commit context) :matched))))

(defun candidate-pattern-matched-p (machine candidate pattern)
  (and pattern
       (eq (pattern-status pattern (candidate-pattern-context machine candidate)) :matched)))

(defun cancel-candidate (machine candidate reason)
  (when (eq (simulation-candidate-status candidate) :viable)
    (setf (simulation-candidate-status candidate) :cancelled)
    (candidate-exit-effects machine candidate :cancel)
    (trace-entry machine :cancel
                 :interaction (simulation-candidate-interaction candidate)
                 :case (simulation-candidate-case candidate) :candidate candidate
                 :details reason
                 :provenance
                 (candidate-provenance
                  candidate :cancelled
                  :source-pattern
                  (if (eq reason :cancel-pattern)
                      (sim-case-cancel-at (simulation-candidate-case candidate))
                      (sim-case-pattern (simulation-candidate-case candidate)))
                  :responsible-effect :none)))
  candidate)

(defun candidate-priority (candidate)
  (+ (sim-interaction-priority (simulation-candidate-interaction candidate))
     (sim-case-priority (simulation-candidate-case candidate))))

(defun candidate-overlaps-p (left right)
  (not (null (intersection
              (sim-interaction-participants (simulation-candidate-interaction left))
              (sim-interaction-participants (simulation-candidate-interaction right))
              :test #'equal))))

(defun candidate-longer-p (left right)
  (> (length (sim-interaction-participants (simulation-candidate-interaction left)))
     (length (sim-interaction-participants (simulation-candidate-interaction right)))))

(defun priority-compare (left right)
  (cond ((> (candidate-priority left) (candidate-priority right)) :left)
        ((< (candidate-priority left) (candidate-priority right)) :right)
        ((and (eq (sim-interaction-arbitration (simulation-candidate-interaction left))
              :longest-match)
              (candidate-longer-p left right)) :left)
        ((and (eq (sim-interaction-arbitration (simulation-candidate-interaction right))
              :longest-match)
              (candidate-longer-p right left)) :right)
        (t :ambiguous)))

(defun arbitrate-candidates (candidates)
  "Choose a deterministic non-overlapping commitment set or signal ambiguity."
  (let ((winners nil))
    (dolist (candidate candidates)
      (let ((conflict (find-if (lambda (winner) (candidate-overlaps-p candidate winner)) winners)))
        (cond
          ((null conflict) (push candidate winners))
          ((eq (priority-compare candidate conflict) :left)
           (setf winners (cons candidate (remove conflict winners :test #'eq))))
          ((eq (priority-compare candidate conflict) :right))
          (t (error 'simulation-ambiguity :left candidate :right conflict)))))
    (nreverse winners)))

(defun consume-candidate-latches (machine candidate)
  (dolist (axis (candidate-consulted-latches candidate))
    (let ((snapshot (assoc axis (simulation-candidate-latch-snapshot candidate) :test #'equal))
          (current (gethash axis (simulator-latches machine))))
      (when (and snapshot current
                 (= (third snapshot) (latch-cell-generation current)))
        (remhash axis (simulator-latches machine))
        (trace-entry machine :latch-consumed
                     :interaction (simulation-candidate-interaction candidate)
                     :case (simulation-candidate-case candidate) :candidate candidate
                     :details (list axis (second snapshot) (third snapshot)))))))

(defun candidate-event-indices (machine candidate)
  (let ((events (simulator-event-vector machine))
        (participants (sim-interaction-participants (simulation-candidate-interaction candidate)))
        (indices nil))
    (loop for index from (simulation-candidate-anchor-index candidate) below (length events)
          for event = (aref events index)
          when (and (member (timed-event-kind event) '(:down :up) :test #'eq)
                    (member (timed-event-position event) participants :test #'equal))
            do (push index indices))
    (nreverse indices)))

(defun commit-candidate (machine candidate)
  (when (eq (simulation-candidate-status candidate) :viable)
    (setf (simulation-candidate-status candidate) :committed
          (simulation-candidate-claimed-event-indices candidate)
          (candidate-event-indices machine candidate))
    (dolist (index (simulation-candidate-claimed-event-indices candidate))
      (setf (gethash index (simulator-claimed-events machine)) candidate))
    ;; Consumption happens before actions so an interaction can atomically
    ;; consume one latch and set a replacement latch of the same axis.
    (let ((*simulation-execution-provenance*
            (candidate-provenance candidate :committed
                                  :responsible-effect :candidate-do)))
      (consume-candidate-latches machine candidate)
      (dolist (action (sim-case-actions (simulation-candidate-case candidate)))
        (apply-sim-action machine candidate action)))
    (let ((*simulation-execution-provenance*
            (candidate-provenance candidate :committed
                                  :responsible-effect :candidate-commit-effect)))
      (dolist (action (sim-case-commit-actions (simulation-candidate-case candidate)))
        (apply-sim-action machine candidate action)))
    (when (null (sim-case-enter-at (simulation-candidate-case candidate)))
      (candidate-enter-effects machine candidate))
    (trace-entry machine :commit
                 :interaction (simulation-candidate-interaction candidate)
                 :case (simulation-candidate-case candidate) :candidate candidate
                 :details (simulation-candidate-claimed-event-indices candidate)
                 :provenance (candidate-provenance candidate :committed
                                                   :responsible-effect :none)))
  candidate)

(defun update-candidate-effects (machine candidate)
  (let ((case (simulation-candidate-case candidate)))
    (when (candidate-pattern-matched-p machine candidate (sim-case-enter-at case))
      (candidate-enter-effects machine candidate))
    (when (candidate-pattern-matched-p machine candidate (sim-case-exit-at case))
      (candidate-exit-effects machine candidate :exit))))

(defun update-candidates-for-current-prefix (machine)
  (let ((ready nil))
    (dolist (candidate (simulator-candidates machine))
      (case (simulation-candidate-status candidate)
        (:viable
         (let ((case (simulation-candidate-case candidate))
               (main-status (candidate-main-status machine candidate)))
           (cond
             ((or (eq main-status :failed)
                  (candidate-pattern-matched-p machine candidate (sim-case-cancel-at case)))
              (cancel-candidate machine candidate
                                (if (eq main-status :failed) :pattern-failed :cancel-pattern)))
             (t
              (update-candidate-effects machine candidate)
              (when (candidate-commit-ready-p machine candidate)
                (push candidate ready))))))
        (:committed (update-candidate-effects machine candidate))))
    (when ready
      (let ((winners (arbitrate-candidates (nreverse ready))))
        ;; A committed candidate defeats every still-viable incompatible
        ;; interpretation, including an incomplete longer candidate.
        (dolist (winner winners)
          (dolist (candidate (simulator-candidates machine))
            (when (and (not (eq candidate winner))
                       (eq (simulation-candidate-status candidate) :viable)
                       (candidate-overlaps-p candidate winner))
              (cancel-candidate machine candidate :lost-arbitration)))
          (commit-candidate machine winner))))
  machine))

(defun append-event (machine event)
  (push event (simulator-events-reversed machine))
  (trace-entry machine (if (eq (timed-event-kind event) :deadline) :deadline :event)
               :event event))

(defun process-physical-event (machine event)
  (let ((position (timed-event-position event)))
    (ecase (timed-event-kind event)
      (:down
       (when (gethash position (simulator-pressed machine))
         (error 'malformed-event-stream :event event :reason "duplicate down"))
       (setf (gethash position (simulator-pressed machine)) event))
      (:up
       (unless (gethash position (simulator-pressed machine))
         (error 'malformed-event-stream :event event :reason "up without matching down"))
       (remhash position (simulator-pressed machine)))))
  (append-event machine event)
  (when (eq (timed-event-kind event) :down)
    (let ((anchor-index (1- (length (simulator-events machine)))))
      (dolist (interaction (simulator-interactions machine))
        (when (member (timed-event-position event)
                      (sim-interaction-participants interaction) :test #'equal)
          (dolist (case (sim-interaction-cases interaction))
            (start-candidate machine interaction case anchor-index))))))
  (update-candidates-for-current-prefix machine))

(defun process-deadline (machine time)
  (setf (simulator-now machine) time)
  (let ((event (make-deadline-event time)))
    (append-event machine event)
    (update-candidates-for-current-prefix machine)))

(defun next-deadline-through (machine limit)
  (let ((times nil))
    (dolist (candidate (simulator-candidates machine))
      (when (member (simulation-candidate-status candidate) '(:viable :committed) :test #'eq)
        (dolist (time (simulation-candidate-deadlines candidate))
          (when (and (> time (simulator-now machine)) (<= time limit))
            (push time times)))))
    (and times (apply #'min times))))

(defun simulator-advance-to (machine time)
  "Advance abstract time, processing all generated deadlines up to TIME.

At an equal timestamp this function processes deadlines before a subsequently
fed physical event.  Thus a key released exactly at a one-second deadline is
still held at that deadline, a deliberate and testable boundary rule."
  (unless (typep time 'timestamp)
    (error "Simulator time must be a non-negative integer millisecond."))
  (when (< time (simulator-now machine))
    (error 'malformed-event-stream :event time :reason "time moved backwards"))
  (loop for deadline = (next-deadline-through machine time)
        while deadline do (process-deadline machine deadline))
  (setf (simulator-now machine) time)
  machine)

(defun simulator-feed-event (machine event)
  "Feed one physical timestamped event and update the full candidate set."
  (unless (typep event 'timed-event)
    (error "Expected a TIMED-EVENT, not ~S." event))
  (when (eq (timed-event-kind event) :deadline)
    (error "Deadline events are generated by SIMULATOR-ADVANCE-TO only."))
  (simulator-advance-to machine (timed-event-time event))
  (process-physical-event machine event)
  machine)

(defun simulator-result (machine)
  (make-simulation-result
   :outputs (simulator-outputs machine)
   :trace (simulator-trace machine)
   :latches (simulator-latches-alist machine)
   :axes (simulator-axes-alist machine)
   :active-effects (simulator-active-effect-names machine)
   :candidates (reverse (copy-list (simulator-candidates machine)))))

(defun simulate-events (interactions events &key latches axes until)
  "Run EVENTS through a fresh reference machine and return a SIMULATION-RESULT.

EVENTS must be supplied in nondecreasing timestamp order.  UNTIL optionally
advances clocks after the final physical input, useful for a held interaction."
  (let ((machine (make-simulator :interactions interactions :latches latches :axes axes)))
    (dolist (event events)
      (simulator-feed-event machine event))
    (when until (simulator-advance-to machine until))
    (simulator-result machine)))
