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

(define-condition simulation-latch-reservation-conflict (simulation-error)
  ((axis :initarg :axis :reader simulation-latch-reservation-conflict-axis)
   (generation :initarg :generation
               :reader simulation-latch-reservation-conflict-generation)
   (existing-candidate :initarg :existing-candidate
                       :reader simulation-latch-reservation-conflict-existing-candidate)
   (requested-candidate :initarg :requested-candidate
                        :reader simulation-latch-reservation-conflict-requested-candidate))
  (:report
   (lambda (condition stream)
     (format stream
             "Latch ~S generation ~D is already reserved by pending candidate ~S; candidate ~S cannot also capture it."
             (simulation-latch-reservation-conflict-axis condition)
             (simulation-latch-reservation-conflict-generation condition)
             (simulation-latch-reservation-conflict-existing-candidate condition)
             (simulation-latch-reservation-conflict-requested-candidate condition)))))

(define-condition unproved-simulation-arbitration (simulation-error)
  ((arbitration :initarg :arbitration
                :reader unproved-simulation-arbitration-kind))
  (:report (lambda (condition stream)
             (format stream "Reference simulation has no proven ~S arbitration scheduler."
                     (unproved-simulation-arbitration-kind condition)))))

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

(define-condition buffered-dispatch-refusal (simulation-error)
  ((code :initarg :code :reader buffered-dispatch-refusal-code)
   (transaction :initarg :transaction :reader buffered-dispatch-refusal-transaction)
   (event :initarg :event :reader buffered-dispatch-refusal-event))
  (:report (lambda (condition stream)
             (format stream "Buffered dispatch refuses ~S for transaction ~S at ~S."
                     (buffered-dispatch-refusal-code condition)
                     (buffered-dispatch-refusal-transaction condition)
                     (buffered-dispatch-refusal-event condition)))))

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
  (when (and (eq kind :emit) (consp value) (eq (first value) :named-key)
             (not (and (stringp (second value)) (null (cddr value)))))
    (error "A :NAMED-KEY simulator output must contain exactly one string name."))
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
             (:constructor %make-sim-interaction
                 (&key name participants cases (priority 0) (arbitration :priority)
                       consulted-latches (route-kind :timed)
                       buffered-dispatch-contract dispatch-plan-token)))
  "A declarative interaction and its mutually competing cases.

ARBITRATION is :PRIORITY or :LONGEST-MATCH.  A priority is never inferred
from host iteration order."
  name
  (participants nil :type list)
  (cases nil :type list)
  (priority 0 :type integer)
  (arbitration :priority)
  (consulted-latches nil :type list)
  ;; :TIMED remains the historical/default route.  Only routed DOWN notices
  ;; may start :ORDINARY-BINDING or :OVERLAY-BINDING interactions.
  (route-kind :timed :type keyword)
  ;; Internal selected finite contract.  NIL is conservative: no buffering.
  buffered-dispatch-contract
  ;; Opaque, per-whole-layout identity shared only by selected timed and
  ;; eligible ordinary IR.  It prevents capability splicing across plans.
  dispatch-plan-token)

(defun make-sim-interaction
    (&key name participants cases (priority 0) (arbitration :priority)
       consulted-latches (route-kind :timed) buffered-dispatch-contract)
  "Construct raw simulator IR without selected buffered-dispatch authority."
  (when buffered-dispatch-contract
    (error "Raw SIM-INTERACTION construction cannot attach a buffered dispatch contract."))
  (%make-sim-interaction :name name :participants participants :cases cases
                         :priority priority :arbitration arbitration
                         :consulted-latches consulted-latches :route-kind route-kind))

(defun make-routed-dispatch-ordinary-interaction
    (&key name participants cases (priority 0) (arbitration :priority)
       consulted-latches (route-kind :ordinary-binding) dispatch-plan-token)
  "Internal complete-layout constructor for one eligible ordinary route."
  (unless (eq route-kind :ordinary-binding)
    (error "Routed dispatch capability is limited to an ordinary binding."))
  (unless dispatch-plan-token
    (error "Routed dispatch requires an opaque whole-layout plan token."))
  (%make-sim-interaction
   :name name :participants participants :cases cases :priority priority
   :arbitration arbitration :consulted-latches consulted-latches
   :route-kind :ordinary-binding :dispatch-plan-token dispatch-plan-token))

(defun make-buffered-sim-interaction
    (&key name participants cases (priority 0) (arbitration :priority)
       consulted-latches (route-kind :timed) buffered-dispatch-contract dispatch-plan-token)
  "Internal compiler constructor for a derived pending-input contract."
  (unless dispatch-plan-token
    (error "Buffered dispatch requires an opaque whole-layout plan token."))
  (%make-sim-interaction
   :name name :participants participants :cases cases :priority priority
   :arbitration arbitration :consulted-latches consulted-latches
   :route-kind route-kind :buffered-dispatch-contract buffered-dispatch-contract
   :dispatch-plan-token dispatch-plan-token))

(defstruct (buffered-dispatch-transaction
             (:constructor make-buffered-dispatch-transaction
                 (&key id interaction owner-position owner-index state
                       contract withheld-event withheld-index origin deferred-key
                       committed-role committed-candidate disposition
                       terminal-foreign-position terminal-foreign-index
                       terminal-foreign-time)))
  "Finite, one-foreign-key routing state; never a second physical stream."
  id interaction owner-position owner-index
  contract
  (state :armed :type keyword)
  withheld-event withheld-index origin deferred-key committed-role committed-candidate
  disposition terminal-foreign-position terminal-foreign-index terminal-foreign-time)

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
                 (&key id interaction case anchor-index context latch-snapshot deadlines
                       captures)))
  id
  interaction
  case
  (anchor-index 0 :type fixnum)
  context
  (latch-snapshot nil :type list)
  (deadlines nil :type list)
  ;; Candidate-local immutable bindings created by the deliberately small
  ;; CAPTURE pattern slice.  This is not a global pressed-key lookup: a later
  ;; physical event cannot reassign a name once it has been captured.
  (captures (make-hash-table :test #'equal))
  (status :viable :type keyword)
  (effect-state (make-hash-table :test #'eq))
  (claimed-event-indices nil :type list))

(defstruct (simulation-result
             (:constructor make-simulation-result
                 (&key outputs trace latches axes active-effects candidates
                       semantic-transitions dispatch-transactions)))
  (outputs nil :type list)
  (trace nil :type list)
  (latches nil :type list)
  (axes nil :type list)
  (active-effects nil :type list)
  (candidates nil :type list)
  (semantic-transitions nil :type list)
  (dispatch-transactions nil :type list))

(defstruct (simulator
             (:constructor %make-simulator
                 (&key interactions now events-reversed trace-reversed outputs-reversed
                       candidates pressed latches axes active-effects claimed-events
                       held-axis-contributions held-modifier-contributions
                       next-candidate-id next-latch-generation
                       transactions-reversed next-transaction-id
                       semantic-transitions-reversed)))
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
  (next-latch-generation 0 :type integer)
  (transactions-reversed nil :type list)
  (next-transaction-id 0 :type integer)
  (semantic-transitions-reversed nil :type list))

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

(defvar *deferred-semantic-key-releases* :inactive
  "Either :INACTIVE or the explicitly selected transaction's release list.")

(defvar *semantic-key-transition-transaction* nil
  "The validated buffered transaction currently authorizing named-key edges.")

(defvar *semantic-key-transition-origin* nil)
(defvar *semantic-key-transition-original-index* nil)

(defun canonical-pattern-position (position)
  "Return POSITION in the closed deterministic pattern-dump vocabulary."
  (if (captured-position-reference-p position)
      (list :captured (second position))
      position))

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
             (canonical-pattern-position (event-pattern-position pattern))))
      (:capture
       (list :capture (event-pattern-capture-name pattern)
             (canonical-pattern-provenance (first (event-pattern-children pattern)))))
      (:context-is
       (list :context-is (event-pattern-context-axis pattern)
             (event-pattern-context-state pattern)))
      ((:sequence :all :either :and)
       (cons (event-pattern-kind pattern)
             (mapcar #'canonical-pattern-provenance
                     (event-pattern-children pattern))))
      (:duration
       (list :duration (canonical-pattern-position (event-pattern-position pattern))
             :at-least (event-pattern-at-least pattern)
             :less-than (event-pattern-less-than pattern)))
      (:deadline
       (list :deadline (event-pattern-milliseconds pattern)
             :after-position (canonical-pattern-position
                              (event-pattern-after-position pattern))
             :while-down (canonical-pattern-position
                          (event-pattern-while-down pattern))))
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
                           (list :position (canonical-pattern-position child))))
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
  (let ((case (simulation-candidate-case candidate))
        (bindings nil))
    (maphash (lambda (name binding)
               (push (list name
                           :position (capture-binding-position binding)
                           :down-index (capture-binding-down-index binding))
                     bindings))
             (simulation-candidate-captures candidate))
    (let ((base
            (list :source-pattern
                  (canonical-pattern-provenance
                   (or source-pattern (sim-case-pattern case)))
                  :candidate-transition transition
                  :commit-point (candidate-commit-point-provenance candidate)
                  :responsible-effect responsible-effect)))
      (if bindings
          (append base (list :captures (sort bindings #'string< :key #'first)))
          base))))

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
  (dolist (interaction interactions)
    (unless (eq (sim-interaction-arbitration interaction) :priority)
      (error 'unproved-simulation-arbitration
             :arbitration (sim-interaction-arbitration interaction)))
    (unless (member (sim-interaction-route-kind interaction)
                    '(:timed :ordinary-binding :overlay-binding) :test #'eq)
      (error "Unknown simulator route kind ~S."
             (sim-interaction-route-kind interaction)))
    (when (and (sim-interaction-buffered-dispatch-contract interaction)
               (not (eq (sim-interaction-route-kind interaction) :timed)))
      (error "Only a :TIMED interaction may select buffered dispatch."))
    (let ((contract (sim-interaction-buffered-dispatch-contract interaction)))
      (when contract
        (unless (typep contract 'ivory-key.model:pending-foreign-interval-contract)
          (error "Buffered dispatch requires a derived pending-foreign contract, not ~S."
                 contract))
        ;; A contract identity is a logical source string.  Do not accept a
        ;; host symbol merely because its printer happens to spell the same:
        ;; that would reintroduce package/interning-dependent routing.
        (unless (and (stringp (sim-interaction-name interaction))
                     (string=
                      (sim-interaction-name interaction)
                      (ivory-key.model:identifier-name
                       (ivory-key.model:normalized-interaction-name
                        (ivory-key.model:interaction-compatibility-contract-interaction
                         contract)))))
          (error "Buffered dispatch contract does not name simulator interaction ~S."
                 (sim-interaction-name interaction)))
        (unless (sim-interaction-dispatch-plan-token interaction)
          (error "Buffered dispatch contract was not attached by complete layout compilation.")))))
  (let ((selected-tokens
          (remove nil
                  (mapcar #'sim-interaction-dispatch-plan-token
                          (remove-if-not #'sim-interaction-buffered-dispatch-contract
                                         interactions)))))
    (when (and selected-tokens
               (not (every (lambda (token) (eq token (first selected-tokens)))
                           (rest selected-tokens))))
      (error "Selected buffered interactions belong to different dispatch plans."))
    (let ((plan-token (first selected-tokens)))
      (dolist (interaction interactions)
        (let ((token (sim-interaction-dispatch-plan-token interaction)))
          (when (and token (not (eq token plan-token)))
            (error "Privileged ordinary route belongs to a different dispatch plan."))
          (when (and (null plan-token) token)
            (error "Privileged ordinary route has no selected buffered dispatch plan."))))))
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

(defun simulator-semantic-transitions (machine)
  (nreverse (copy-list (simulator-semantic-transitions-reversed machine))))

(defun record-semantic-key-transition (machine kind key &key transaction origin original-index)
  (push (make-semantic-key-transition
         :time (simulator-now machine) :kind kind :key key
         :transaction-id (and transaction (buffered-dispatch-transaction-id transaction))
         :origin origin :original-index original-index)
        (simulator-semantic-transitions-reversed machine))
  (trace-entry machine :semantic-key-transition
               :details (list :kind kind :key key
                              :transaction (and transaction
                                                (buffered-dispatch-transaction-id transaction))
                              :origin origin :original-index original-index)
               :provenance (list :route-kind :semantic-key-transition
                                 :origin origin
                                 :transaction (and transaction
                                                   (buffered-dispatch-transaction-id transaction))))
  key)

(defun named-key-output-p (value)
  (and (consp value) (eq (first value) :named-key) (stringp (second value))
       (null (cddr value))))

(defun buffered-route-output-value-p (value)
  "Whether VALUE is one closed non-stateful buffered-route output."
  (and (consp value)
       (member (first value) '(:text :named-key :named-symbol) :test #'eq)
       (stringp (second value))
       (null (cddr value))))

(defun record-named-key-output (machine value &key transaction origin original-index)
  "Preserve legacy VALUE while adding normative press/release edges.

The bounded transaction contract may defer exactly the selected owner's
release; all non-transactional named key actions remain atomic for legacy
callers and add an adjacent semantic pair."
  (push value (simulator-outputs-reversed machine))
  ;; Legacy named-key outputs predate this selected contract and deliberately
  ;; remain projection-only.  No semantic edge is inferred from them.
  (when transaction
    (let ((key (second value)))
      (record-semantic-key-transition machine :press key
                                      :transaction transaction :origin origin
                                      :original-index original-index)
      (if (eq *deferred-semantic-key-releases* :inactive)
          (record-semantic-key-transition machine :release key
                                          :transaction transaction :origin origin
                                          :original-index original-index)
          (push (list key transaction origin original-index)
                *deferred-semantic-key-releases*)))))

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

(defun selected-buffered-owner-positions (machine)
  "Return every selected pending owner's logical position in stable IR order."
  (remove-duplicates
   (mapcan (lambda (interaction)
             (if (sim-interaction-buffered-dispatch-contract interaction)
                 (copy-list (sim-interaction-participants interaction))
                 nil))
           (simulator-interactions machine))
   :test #'equal))

(defun candidate-pattern-context (machine candidate)
  (let ((events (simulator-event-vector machine)))
    (make-pattern-match-context :events events
                                :start-index (simulation-candidate-anchor-index candidate)
                                :anchor-index (simulation-candidate-anchor-index candidate)
                                :captures (simulation-candidate-captures candidate)
                                :context (simulation-candidate-context candidate)
                                :latch-snapshot
                                (simulation-candidate-latch-snapshot candidate)
                                :excluded-foreign-positions
                                (and (sim-interaction-buffered-dispatch-contract
                                      (simulation-candidate-interaction candidate))
                                     (selected-buffered-owner-positions machine)))))

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

(defun candidate-reservation-scope= (left right)
  "Whether LEFT and RIGHT are alternatives from one anchor-time candidate set.

All cases of one interaction started by one physical anchor compete through the
existing arbitration rule, so they may share one latch snapshot.  A distinct
interaction or a later anchor is independently pending and must not observe
the same latch generation without an explicit reservation/arbitration policy.
"
  (and (eq (simulation-candidate-interaction left)
           (simulation-candidate-interaction right))
       (= (simulation-candidate-anchor-index left)
          (simulation-candidate-anchor-index right))))

(defun candidate-latch-snapshot-for-axis (candidate axis)
  (assoc axis (simulation-candidate-latch-snapshot candidate) :test #'equal))

(defun assert-candidate-latch-reservations (machine candidate)
  "Refuse independent pending consumers of one captured latch generation.

This is deliberately a pre-commit check.  Comparing generations only at
consumption prevents a double delete, but still lets two independent candidate
sets observe and act on the same latch snapshot.  Version 1 instead fails
closed before the second snapshot becomes viable.
"
  (dolist (snapshot (simulation-candidate-latch-snapshot candidate))
    (destructuring-bind (axis value generation) snapshot
      (declare (ignore value))
      (let ((existing
              (find-if
               (lambda (other)
                 (let ((other-snapshot
                         (candidate-latch-snapshot-for-axis other axis)))
                   (and (not (eq other candidate))
                        (eq (simulation-candidate-status other) :viable)
                        (not (candidate-reservation-scope= other candidate))
                        other-snapshot
                        (= generation (third other-snapshot)))))
               (simulator-candidates machine))))
        (when existing
          (error 'simulation-latch-reservation-conflict
                 :axis axis :generation generation
                 :existing-candidate existing :requested-candidate candidate)))))
  candidate)

(defun start-candidate (machine interaction case anchor-index)
  (let* ((id (incf (simulator-next-candidate-id machine)))
         (candidate (%make-simulation-candidate
                     :id id :interaction interaction :case case
                     :anchor-index anchor-index
                     :context (simulator-axes-alist machine)
                     :captures (make-hash-table :test #'equal)
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
    ;; A latch snapshot is an observation with semantic consequences, not a
    ;; best-effort cache.  Check its exclusive pending-consumer boundary before
    ;; the candidate can reach pattern evaluation or commitment.
    (assert-candidate-latch-reservations machine candidate)
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
       (if (named-key-output-p value)
           (record-named-key-output
            machine value :transaction *semantic-key-transition-transaction*
            :origin (and *semantic-key-transition-transaction*
                         *semantic-key-transition-origin*)
            :original-index (and *semantic-key-transition-transaction*
                                 *semantic-key-transition-original-index*))
           (push value (simulator-outputs-reversed machine)))
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
                  (case reason
                    (:cancel-pattern
                     (sim-case-cancel-at (simulation-candidate-case candidate)))
                    ;; An ON-COMMIT effect has no speculative entry.  If its
                    ;; owner has already released, that candidate cannot
                    ;; subsequently commit and acquire a zero-lifetime hold.
                    (:participant-exited-before-commit
                     (sim-case-exit-at (simulation-candidate-case candidate)))
                    (otherwise
                     (sim-case-pattern (simulation-candidate-case candidate))))
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

(defun priority-compare (left right)
  (cond ((> (candidate-priority left) (candidate-priority right)) :left)
        ((< (candidate-priority left) (candidate-priority right)) :right)
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
      ;; A selected buffered owner's TAP result is the ordinary binding at the
      ;; owner position, resolved later at the transaction frontier.  Do not
      ;; emit the interaction candidate's baked-in tap behavior as well.
      (unless (selected-buffered-owner-tap-candidate-p machine candidate)
        (dolist (action (sim-case-actions (simulation-candidate-case candidate)))
          (apply-sim-action machine candidate action))))
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
             ;; A NIL ENTER-AT is the compiled ON-COMMIT lifecycle contract.
             ;; Its owner UP wins while the candidate is still viable: no
             ;; later foreign event may commit an interaction whose held
             ;; lifetime has already ended.  Committed candidates continue to
             ;; process the same EXIT-AT normally, including a deadline just
             ;; before an equal-time physical release.
             ((and (null (sim-case-enter-at case))
                   (sim-case-exit-at case)
                   (candidate-pattern-matched-p machine candidate
                                                (sim-case-exit-at case)))
              (cancel-candidate machine candidate :participant-exited-before-commit))
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

(defun buffered-dispatch-transactions (machine)
  (reverse (copy-list (simulator-transactions-reversed machine))))

(defun active-buffered-transaction (machine)
  (find-if (lambda (transaction)
             (member (buffered-dispatch-transaction-state transaction)
                     '(:withheld-down :down-redispatched-awaiting-up)
                     :test #'eq))
           (simulator-transactions-reversed machine)))

(defun armed-buffered-transactions (machine)
  (remove-if-not (lambda (transaction)
                   (eq (buffered-dispatch-transaction-state transaction) :armed))
                 (simulator-transactions-reversed machine)))

(defun buffered-owner-transaction-for-event (machine event)
  (and (eq (timed-event-kind event) :up)
       (find-if
        (lambda (transaction)
          (and (member (buffered-dispatch-transaction-state transaction)
                       '(:armed :withheld-down) :test #'eq)
               (equal (timed-event-position event)
                      (buffered-dispatch-transaction-owner-position transaction))))
        (simulator-transactions-reversed machine))))

(defun buffered-contract-role-for-candidate (transaction candidate)
  "Resolve a simulator case through the derived normalized-role evidence."
  (find-if
   (lambda (reference)
     (equal (model-identifier->simulation-value
             (ivory-key.model:normalized-candidate-name
              (ivory-key.model:interaction-compatibility-role-reference-candidate reference)))
            (sim-case-name (simulation-candidate-case candidate))))
   (ivory-key.model:release-trigger-interaction-compatibility-contract-role-references
    (buffered-dispatch-transaction-contract transaction))))

(defun buffered-transaction-committed-candidate (machine transaction)
  (find-if
   (lambda (candidate)
     (and (eq (simulation-candidate-status candidate) :committed)
          (eq (simulation-candidate-interaction candidate)
              (buffered-dispatch-transaction-interaction transaction))
          (= (simulation-candidate-anchor-index candidate)
             (buffered-dispatch-transaction-owner-index transaction))))
   (simulator-candidates machine)))

(defun resolve-withheld-buffered-deadline (machine transaction event)
  "Resolve the one proven timeout path for a withheld direct foreign route.

EVENT is the generated owner deadline.  The physical foreign DOWN was already
published exactly once; this function only emits its bounded routed-dispatch
notice after the timeout candidate has committed its held result.
"
  (let* ((candidate (buffered-transaction-committed-candidate machine transaction))
         (role (and candidate
                    (buffered-contract-role-for-candidate transaction candidate))))
    (unless (and role
                 (eq (ivory-key.model:interaction-compatibility-role-reference-role role)
                     :timeout))
      (buffered-dispatch-refuse :unproved-deadline-role transaction event))
    (setf (buffered-dispatch-transaction-committed-candidate transaction) candidate
          (buffered-dispatch-transaction-committed-role transaction) :timeout
          (buffered-dispatch-transaction-disposition transaction) :deadline-hold)
    (trace-entry
     machine :dispatch-resolved :event event
     :interaction (buffered-dispatch-transaction-interaction transaction)
     :case (simulation-candidate-case candidate) :candidate candidate
     :details
     (list :transaction (buffered-dispatch-transaction-id transaction)
           :disposition :deadline-hold :role :timeout
           :foreign-down-index (buffered-dispatch-transaction-withheld-index transaction)
           :origin (buffered-dispatch-transaction-origin transaction))
     :provenance
     (list :route-kind :timed
           :transaction (buffered-dispatch-transaction-id transaction)
           :origin (buffered-dispatch-transaction-origin transaction)))
    ;; The timeout candidate's held effect was acquired by
    ;; UPDATE-CANDIDATES-FOR-CURRENT-PREFIX before this call.  Only then may
    ;; the validated ordinary B route receive its logical DOWN notice.
    (routed-dispatch-down machine transaction)))

(defun complete-armed-buffered-transactions (machine event)
  (dolist (transaction (armed-buffered-transactions machine))
    (let ((candidate (buffered-transaction-committed-candidate machine transaction)))
      (when candidate
        (let ((role (buffered-contract-role-for-candidate transaction candidate)))
          (unless role
            (buffered-dispatch-refuse :unproved-committed-role transaction event))
          (let ((role-name
                  (ivory-key.model:interaction-compatibility-role-reference-role role)))
            (when (eq role-name :tap)
              (unless (and (eq (timed-event-kind event) :up)
                           (equal (timed-event-position event)
                                  (buffered-dispatch-transaction-owner-position transaction)))
                (buffered-dispatch-refuse :unproved-tap-resolution transaction event))
              (let ((releases (routed-dispatch-owner-tap machine transaction event)))
                (dolist (release releases)
                  (destructuring-bind (key ignored-transaction origin original-index) release
                    (declare (ignore ignored-transaction))
                    (record-semantic-key-transition
                     machine :release key :transaction transaction
                     :origin origin :original-index original-index)))))
            (setf (buffered-dispatch-transaction-state transaction) :complete
                (buffered-dispatch-transaction-committed-candidate transaction) candidate
                (buffered-dispatch-transaction-committed-role transaction)
                role-name
                (buffered-dispatch-transaction-disposition transaction)
                (if (eq role-name :tap) :tap :no-foreign-custody))
          (trace-entry machine :dispatch-resolved :event event
                       :interaction (buffered-dispatch-transaction-interaction transaction)
                       :case (simulation-candidate-case candidate) :candidate candidate
                       :details (list :transaction
                                      (buffered-dispatch-transaction-id transaction)
                                      :disposition
                                      (buffered-dispatch-transaction-disposition transaction)
                                      :role (buffered-dispatch-transaction-committed-role transaction)
                                      :origin :selected-timed-owner)
                       :provenance (list :route-kind :timed
                                         :transaction
                                         (buffered-dispatch-transaction-id transaction)
                                         :origin :selected-timed-owner))))))))

(defun selected-buffered-owner-tap-candidate-p (machine candidate)
  "Whether CANDIDATE's tap output is delegated to its owner ordinary route."
  (find-if
   (lambda (transaction)
     (and (member (buffered-dispatch-transaction-state transaction)
                  '(:armed :withheld-down) :test #'eq)
          (eq candidate (buffered-transaction-committed-candidate machine transaction))
          (let ((role (buffered-contract-role-for-candidate transaction candidate)))
            (and role
                 (eq (ivory-key.model:interaction-compatibility-role-reference-role role)
                     :tap)))))
   (simulator-transactions-reversed machine)))

(defun selected-buffered-interactions-at (machine position)
  (remove-if-not
   (lambda (interaction)
     (and (eq (sim-interaction-route-kind interaction) :timed)
          (sim-interaction-buffered-dispatch-contract interaction)
          (member position (sim-interaction-participants interaction) :test #'equal)))
   (simulator-interactions machine)))

(defun timed-interactions-at (machine position)
  (remove-if-not (lambda (interaction)
                   (and (eq (sim-interaction-route-kind interaction) :timed)
                        (member position (sim-interaction-participants interaction) :test #'equal)))
                 (simulator-interactions machine)))

(defun start-buffered-transaction (machine interaction event index)
  (let ((transaction
          (make-buffered-dispatch-transaction
           :id (incf (simulator-next-transaction-id machine))
           :interaction interaction :owner-position (timed-event-position event)
           :owner-index index
           :contract (sim-interaction-buffered-dispatch-contract interaction)
           :origin :selected-timed-owner)))
    (push transaction (simulator-transactions-reversed machine))
    (trace-entry machine :dispatch-armed :event event :interaction interaction
                 :details (list :transaction (buffered-dispatch-transaction-id transaction)
                                :owner-index index :origin :selected-timed-owner)
                 :provenance (list :route-kind :timed
                                   :transaction (buffered-dispatch-transaction-id transaction)
                                   :origin :selected-timed-owner))
    transaction))

(defun buffered-dispatch-refuse (code transaction event)
  (error 'buffered-dispatch-refusal :code code :transaction transaction :event event))

(defun buffered-dispatch-before-physical-event (machine event)
  "Check the closed one-owner/one-foreign transaction boundary before append.

The physical stream remains immutable: refusal happens before we publish an
ambiguous event, and accepted events are appended exactly once by the caller."
  (let* ((position (timed-event-position event))
         (selected (and (eq (timed-event-kind event) :down)
                        (selected-buffered-interactions-at machine position)))
         (armed (and (eq (timed-event-kind event) :down)
                     (armed-buffered-transactions machine)))
         (transaction (active-buffered-transaction machine)))
    (when (> (length selected) 1)
      (buffered-dispatch-refuse :multiple-eligible-owners nil event))
    (when (and selected
               (some (lambda (interaction)
                       (not (member interaction selected :test #'eq)))
                     (timed-interactions-at machine position)))
      (buffered-dispatch-refuse :selected-owner-overlap nil event))
    ;; Establish the complete custody boundary before pressed state, the
    ;; physical evidence vector, or trace is mutated. A caller that catches a
    ;; refusal may therefore inspect the unchanged simulator safely.
    (when (and armed (null selected))
      ;; An unselected raw TIMED route at B would otherwise observe the
      ;; physical event while it is still eligible for foreign custody.  The
      ;; bounded contract has no arbitration semantics for that splice, so
      ;; reject before publishing B to the event frontier.
      (when (timed-interactions-at machine position)
        (buffered-dispatch-refuse :foreign-timed-interaction (first armed) event))
      (let ((routes (routed-interactions-at machine position)))
        (cond ((null routes)
               (buffered-dispatch-refuse :unroutable-foreign (first armed) event))
              ((> (length routes) 1)
               (buffered-dispatch-refuse :multiple-routed-bindings
                                         (first armed) event))
              ((not (buffered-output-routed-case (first routes) position (first armed)))
               (buffered-dispatch-refuse :unsupported-buffered-foreign-route
                                         (first armed) event))
              ((> (length armed) 1)
               (buffered-dispatch-refuse :multiple-eligible-owners nil event)))))
    (when transaction
      (let ((owner (buffered-dispatch-transaction-owner-position transaction))
            (withheld (buffered-dispatch-transaction-withheld-event transaction)))
        (case (buffered-dispatch-transaction-state transaction)
          (:armed
           (when (and (eq (timed-event-kind event) :down)
                      (not (equal position owner)))
             (when (selected-buffered-interactions-at machine position)
               (buffered-dispatch-refuse :new-owner transaction event))))
          (:withheld-down
           (cond
             ((and (eq (timed-event-kind event) :down)
                   (not (equal position owner)))
              (buffered-dispatch-refuse :second-foreign transaction event))
             ((and (eq (timed-event-kind event) :up)
                   (not (or (equal position owner)
                            (equal position (timed-event-position withheld)))))
              (buffered-dispatch-refuse :mismatched-terminal transaction event))))
          (:down-redispatched-awaiting-up
           ;; Once the deadline has routed B-DOWN, either physical terminal
           ;; order is proven: B-UP may arrive before P-UP, or P-UP may end
           ;; the held owner while B remains physically down.  No new DOWN or
           ;; unrelated UP joins this bounded transaction.
           (unless (and (eq (timed-event-kind event) :up)
                        (or (equal position owner)
                            (equal position (timed-event-position withheld))))
             (buffered-dispatch-refuse :nested-or-mismatched-terminal
                                       transaction event))))))))

(defun maybe-withhold-buffered-down (machine event index)
  (when (eq (timed-event-kind event) :down)
    (let* ((position (timed-event-position event))
           (selected (selected-buffered-interactions-at machine position))
           (routes (routed-interactions-at machine position))
           (armed (armed-buffered-transactions machine)))
      ;; A second selected owner is another independently armed candidate set,
      ;; not foreign input.  Custody begins only for one output-only B route.
      (when (and armed (null selected))
        (cond
          ;; Defense in depth for callers that invoke this helper through a
          ;; future processing path after the pre-append check above.
          ((timed-interactions-at machine position)
           (buffered-dispatch-refuse :foreign-timed-interaction (first armed) event))
          ((null routes)
           (buffered-dispatch-refuse :unroutable-foreign (first armed) event))
          ((> (length routes) 1)
           (buffered-dispatch-refuse :multiple-routed-bindings (first armed) event))
          ((not (buffered-output-routed-case (first routes) position (first armed)))
           (buffered-dispatch-refuse :unsupported-buffered-foreign-route
                                     (first armed) event))
          ((> (length armed) 1)
           (buffered-dispatch-refuse :multiple-eligible-owners nil event))
          (t
           (let ((transaction (first armed)))
      (setf (buffered-dispatch-transaction-state transaction) :withheld-down
            (buffered-dispatch-transaction-withheld-event transaction) event
            (buffered-dispatch-transaction-withheld-index transaction) index
            (buffered-dispatch-transaction-origin transaction) :withheld-foreign-down)
      (trace-entry machine :dispatch-withheld :event event
                   :interaction (buffered-dispatch-transaction-interaction transaction)
                   :details (list :transaction (buffered-dispatch-transaction-id transaction)
                                  :original-index index :original-time (timed-event-time event)
                                  :origin :withheld-foreign-down)
                   :provenance (list :route-kind :timed
                                     :transaction (buffered-dispatch-transaction-id transaction)
                                     :origin :withheld-foreign-down))
      transaction)))))))

(defun routed-interactions-at (machine position)
  (remove-if-not
   (lambda (interaction)
     (and (member (sim-interaction-route-kind interaction)
                  '(:ordinary-binding :overlay-binding) :test #'eq)
          (member position (sim-interaction-participants interaction) :test #'equal)))
   (simulator-interactions machine)))

(defun buffered-output-routed-case (interaction position transaction)
  "Return one token-authorized output-only ordinary route case, or NIL.

The whole-layout compiler proves that a callback route selects only closed
output behaviors.  Raw and cross-layout IR cannot acquire its per-plan token.
"
  (let ((cases (sim-interaction-cases interaction)))
    (and (eq (sim-interaction-route-kind interaction) :ordinary-binding)
         (eq (sim-interaction-dispatch-plan-token interaction)
             (sim-interaction-dispatch-plan-token
              (buffered-dispatch-transaction-interaction transaction)))
         (= (length cases) 1)
         (let ((case (first cases)))
           (and (eq (sim-case-commit case) :when-matched)
                (null (sim-case-effects case))
                (null (sim-case-commit-actions case))
                (or (null (sim-case-actions case))
                    (and (= (length (sim-case-actions case)) 1)
                         (let ((action (first (sim-case-actions case))))
                           (or (and (eq (sim-action-kind action) :emit)
                                    (null (sim-action-resolver action))
                                    (buffered-route-output-value-p
                                     (sim-action-value action)))
                               (and (eq (sim-action-kind action) :callback)
                                    (functionp (sim-action-value action)))))))
                (let ((pattern (sim-case-pattern case)))
                  (and (eq (event-pattern-kind pattern) :event)
                       (eq (event-pattern-event-kind pattern) :down)
                       (equal (event-pattern-position pattern) position)))
                case)))))

(defun routed-dispatch-output
    (machine transaction event index position kind origin)
  "Execute one token-authorized logical ordinary route at its current frontier.

EVENT remains physical evidence; this function never appends or re-feeds it.
The candidate snapshots effective axes when the route is resolved, which is
deliberately later than a withheld DOWN for this bounded contract.
"
  (let ((routes (routed-interactions-at machine position)))
    (when (> (length routes) 1)
      (buffered-dispatch-refuse :multiple-routed-bindings transaction event))
    (when routes
      (let* ((interaction (first routes))
             (case (or (buffered-output-routed-case interaction position transaction)
                       (buffered-dispatch-refuse :unsupported-buffered-foreign-route
                                                 transaction event)))
             (candidate
               (%make-simulation-candidate
                :id 0 :interaction interaction :case case :anchor-index index
                :context (simulator-axes-alist machine)
                :latch-snapshot nil :captures (make-hash-table :test #'equal))))
        (trace-entry machine :redispatch :event event :interaction interaction :case case
                     :details (list :kind kind
                                    :transaction (buffered-dispatch-transaction-id transaction)
                                    :original-index index :original-time (timed-event-time event)
                                    :dispatch-frontier (1- (length (simulator-events machine)))
                                    :origin origin)
                     :provenance (list :route-kind (sim-interaction-route-kind interaction)
                                       :transaction (buffered-dispatch-transaction-id transaction)
                                       :origin origin))
        (let ((*semantic-key-transition-transaction* transaction)
              (*semantic-key-transition-origin* origin)
              (*semantic-key-transition-original-index* index)
              (*deferred-semantic-key-releases* nil))
          (%apply-compiled-actions machine candidate (sim-case-actions case))
          (nreverse *deferred-semantic-key-releases*))))))

(defun routed-dispatch-down (machine transaction)
  "Execute the bounded foreign logical DOWN without cloning physical input."
  (let* ((event (buffered-dispatch-transaction-withheld-event transaction))
         (index (buffered-dispatch-transaction-withheld-index transaction))
         (position (timed-event-position event)))
    (setf (buffered-dispatch-transaction-deferred-key transaction)
          (routed-dispatch-output machine transaction event index position :down :routed-down))
    (setf (buffered-dispatch-transaction-state transaction)
          :down-redispatched-awaiting-up)))

(defun routed-dispatch-owner-tap (machine transaction event)
  "Resolve a selected owner's tap through its ordinary binding at this frontier."
  (routed-dispatch-output
   machine transaction event
   (buffered-dispatch-transaction-owner-index transaction)
   (buffered-dispatch-transaction-owner-position transaction)
   :tap :routed-owner-tap))

(defun routed-dispatch-up (machine transaction event)
  (let ((withheld (buffered-dispatch-transaction-withheld-event transaction)))
    (setf (buffered-dispatch-transaction-terminal-foreign-position transaction)
          (timed-event-position event)
          (buffered-dispatch-transaction-terminal-foreign-index transaction)
          (1- (length (simulator-events machine)))
          (buffered-dispatch-transaction-terminal-foreign-time transaction)
          (timed-event-time event))
    (trace-entry machine :redispatch :event event
                 :details (list :kind :up :transaction (buffered-dispatch-transaction-id transaction)
                                :original-index (1- (length (simulator-events machine)))
                                :original-time (timed-event-time event)
                                :withheld-down-index (buffered-dispatch-transaction-withheld-index transaction)
                                :withheld-down-time (timed-event-time withheld)
                                :dispatch-frontier (1- (length (simulator-events machine)))
                                :origin :routed-physical-up)
                 :provenance (list :route-kind :routed-up
                                   :transaction (buffered-dispatch-transaction-id transaction)
                                   :origin :routed-physical-up))
    (let ((up-index (1- (length (simulator-events machine)))))
      (dolist (release (buffered-dispatch-transaction-deferred-key transaction))
      (destructuring-bind (key ignored-transaction origin original-index) release
        (declare (ignore ignored-transaction origin original-index))
        (record-semantic-key-transition machine :release key :transaction transaction
                                        :origin :routed-up :original-index up-index)))
    (setf (buffered-dispatch-transaction-deferred-key transaction) nil
          (buffered-dispatch-transaction-state transaction) :complete))))

(defun buffered-dispatch-after-prefix (machine event deferred-releases)
  "Advance the finite transaction only after normal timed candidate selection."
  (let ((transaction (active-buffered-transaction machine)))
    (when transaction
      (case (buffered-dispatch-transaction-state transaction)
        (:withheld-down
         (when (or (and (eq (timed-event-kind event) :up)
                        (equal (timed-event-position event)
                               (buffered-dispatch-transaction-owner-position transaction)))
                   (and (eq (timed-event-kind event) :up)
                        (equal (timed-event-position event)
                               (timed-event-position
                                (buffered-dispatch-transaction-withheld-event transaction)))))
           (let* ((candidate (buffered-transaction-committed-candidate machine transaction))
                  (role (and candidate
                             (buffered-contract-role-for-candidate transaction candidate))))
             (unless role
               (buffered-dispatch-refuse :unproved-committed-role transaction event))
             (setf (buffered-dispatch-transaction-committed-candidate transaction) candidate
                   (buffered-dispatch-transaction-committed-role transaction)
                   (ivory-key.model:interaction-compatibility-role-reference-role role)))
           (let ((disposition
                   (if (equal (timed-event-position event)
                              (buffered-dispatch-transaction-owner-position transaction))
                       :tap
                       :foreign-release-hold)))
             (setf (buffered-dispatch-transaction-disposition transaction)
                   disposition)
           (trace-entry
            machine :dispatch-resolved :event event
            :interaction (buffered-dispatch-transaction-interaction transaction)
            :details
            (list :transaction (buffered-dispatch-transaction-id transaction)
                  :disposition
                  disposition
                  :role (buffered-dispatch-transaction-committed-role transaction)
                  :foreign-down-index
                  (buffered-dispatch-transaction-withheld-index transaction)
                  :origin (buffered-dispatch-transaction-origin transaction))
            :provenance
            (list :route-kind :timed
                  :transaction (buffered-dispatch-transaction-id transaction)
                  :origin (buffered-dispatch-transaction-origin transaction)))
           (let ((owner-tap-releases
                   (and (eq disposition :tap)
                        (routed-dispatch-owner-tap machine transaction event))))
             ;; The selected tap press precedes the routed foreign DOWN; its
             ;; release follows that notice while the foreign release remains
             ;; deferred to its own physical UP.
             (routed-dispatch-down machine transaction)
             (dolist (release owner-tap-releases)
               (destructuring-bind (key ignored-transaction origin original-index) release
                 (declare (ignore ignored-transaction))
                 (record-semantic-key-transition machine :release key :transaction transaction
                                                 :origin origin :original-index original-index)))
             ;; Kept as a defensive compatibility path for a future selected
             ;; candidate that itself intentionally deferred a semantic edge.
             (unless (eq deferred-releases :inactive)
               (dolist (release (nreverse deferred-releases))
                 (destructuring-bind (key ignored-transaction origin original-index) release
                   (declare (ignore ignored-transaction))
                   (record-semantic-key-transition machine :release key :transaction transaction
                                                   :origin origin :original-index original-index)))))
           (when (and (eq (timed-event-kind event) :up)
                      (equal (timed-event-position event)
                             (timed-event-position
                              (buffered-dispatch-transaction-withheld-event transaction))))
             (routed-dispatch-up machine transaction event)))))
        (:down-redispatched-awaiting-up
         (when (and (eq (timed-event-kind event) :up)
                    (equal (timed-event-position event)
                           (timed-event-position
                            (buffered-dispatch-transaction-withheld-event transaction))))
           (routed-dispatch-up machine transaction event)))))))

(defun process-physical-event (machine event)
  (buffered-dispatch-before-physical-event machine event)
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
  (let ((index (1- (length (simulator-events machine)))))
    (when (eq (timed-event-kind event) :down)
      (let ((selected (selected-buffered-interactions-at machine
                                                          (timed-event-position event))))
        (when (> (length selected) 1)
          (buffered-dispatch-refuse :multiple-eligible-owners nil event))
        (when selected
          (start-buffered-transaction machine (first selected) event index)))
      ;; Raw physical DOWN starts TIMED routes only.  Ordinary/overlay routes
      ;; enter solely through ROUTED-DISPATCH-DOWN, preserving one physical
      ;; stream and preventing redispatch from starting timed candidates.
      (dolist (interaction (simulator-interactions machine))
        (when (and (eq (sim-interaction-route-kind interaction) :timed)
                   (member (timed-event-position event)
                           (sim-interaction-participants interaction) :test #'equal))
          (dolist (case (sim-interaction-cases interaction))
            (start-candidate machine interaction case index))))
      (let ((withheld (maybe-withhold-buffered-down machine event index)))
        ;; Outside selected custody, ordinary and overlay interactions retain
        ;; the historical candidate path, including latch snapshots and
        ;; context commitment.  Custody suppresses only this one routed DOWN.
        (unless (or withheld
                    ;; A selected buffered owner's ordinary binding is its tap
                    ;; route and resolves only when the tap disposition wins.
                    (selected-buffered-interactions-at
                     machine (timed-event-position event)))
          (dolist (interaction (simulator-interactions machine))
            (when (and (member (sim-interaction-route-kind interaction)
                               '(:ordinary-binding :overlay-binding) :test #'eq)
                       (member (timed-event-position event)
                               (sim-interaction-participants interaction) :test #'equal))
              (dolist (case (sim-interaction-cases interaction))
                (start-candidate machine interaction case index)))))))
    (let* ((owner-transaction (buffered-owner-transaction-for-event machine event))
           (selected-owner-up-p
             (not (null owner-transaction)))
           (*semantic-key-transition-transaction*
             (and selected-owner-up-p owner-transaction))
           (*semantic-key-transition-origin*
             (and selected-owner-up-p :selected-timed-action))
           (*semantic-key-transition-original-index*
             (and selected-owner-up-p
                  (buffered-dispatch-transaction-owner-index owner-transaction)))
           (*deferred-semantic-key-releases*
             (if (and selected-owner-up-p
                      (eq (buffered-dispatch-transaction-state owner-transaction)
                          :withheld-down))
                 nil
                 :inactive)))
      (update-candidates-for-current-prefix machine)
      (buffered-dispatch-after-prefix machine event *deferred-semantic-key-releases*)
      (complete-armed-buffered-transactions machine event))))

(defun process-deadline (machine time)
  (setf (simulator-now machine) time)
  (let ((event (make-deadline-event time)))
    (append-event machine event)
    (update-candidates-for-current-prefix machine)
    (let ((transaction (active-buffered-transaction machine)))
      (when (and transaction
                 (eq (buffered-dispatch-transaction-state transaction) :withheld-down))
        (resolve-withheld-buffered-deadline machine transaction event)))
    (complete-armed-buffered-transactions machine event)))

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

(defun %canonical-source-span-projection (span)
  "Project source provenance without retaining a source-file host object."
  (when span
    (list :source
          (let ((source (ivory-key.source:source-span-source span)))
            (and source (ivory-key.source:source-file-name source)))
          :start-byte (ivory-key.source:source-span-start-byte span)
          :end-byte (ivory-key.source:source-span-end-byte span)
          :start-line (ivory-key.source:source-span-start-line span)
          :start-column (ivory-key.source:source-span-start-column span)
          :end-line (ivory-key.source:source-span-end-line span)
          :end-column (ivory-key.source:source-span-end-column span)
          :import-stack
          (mapcar #'%canonical-source-span-projection
                  (ivory-key.source:source-span-import-stack span)))))

(defun %canonical-source-origin-projection (origin)
  "Return a closed logical-name/span projection of ORIGIN, or NIL."
  (when origin
    (list :definition
          (%canonical-source-span-projection
           (ivory-key.source:source-origin-definition-span origin))
          :uses
          (mapcar #'%canonical-source-span-projection
                  (ivory-key.source:source-origin-use-spans origin)))))

(defun %canonical-held-effect-signature (signature)
  "Project one model-held signature into the result dump vocabulary."
  (list :kind (ivory-key.model:interaction-compatibility-held-effect-signature-kind
               signature)
        :identity
        (model-identifier->simulation-value
         (ivory-key.model:interaction-compatibility-held-effect-signature-identity
          signature))
        :state
        (let ((state (ivory-key.model:interaction-compatibility-held-effect-signature-state
                      signature)))
          (and state (model-identifier->simulation-value state)))
        :release (ivory-key.model:interaction-compatibility-held-effect-signature-release
                  signature)))

(defun %canonical-buffered-contract-projection (contract)
  "Return CONTRACT as closed, deterministic evidence rather than CLOS IR.

The result boundary deliberately carries only the facts that authorized a
bounded dispatch transaction.  Source files, normalized objects, and pathname
identity remain on the model side of this projection.
"
  (let ((provenance
          (ivory-key.model:release-trigger-interaction-compatibility-contract-provenance
           contract)))
    (list :mode (ivory-key.model:interaction-compatibility-contract-mode contract)
          :interaction
          (model-identifier->simulation-value
           (ivory-key.model:normalized-interaction-name
            (ivory-key.model:interaction-compatibility-contract-interaction contract)))
          :owner
          (model-identifier->simulation-value
           (ivory-key.model:interaction-compatibility-contract-owner contract))
          :deadline
          (ivory-key.model:release-trigger-interaction-compatibility-contract-deadline
           contract)
          :capture
          (model-identifier->simulation-value
           (ivory-key.model:release-trigger-interaction-compatibility-contract-capture-name
            contract))
          :held-signature
          (%canonical-held-effect-signature
           (ivory-key.model:release-trigger-interaction-compatibility-contract-held-effect-signature
            contract))
          :tap-key
          (model-identifier->simulation-value
           (ivory-key.model:release-trigger-interaction-compatibility-contract-tap-key
            contract))
          :roles
          (mapcar
           (lambda (reference)
             (list :role (ivory-key.model:interaction-compatibility-role-reference-role
                          reference)
                   :candidate
                   (model-identifier->simulation-value
                    (ivory-key.model:normalized-candidate-name
                     (ivory-key.model:interaction-compatibility-role-reference-candidate
                      reference)))
                   :origin
                   (%canonical-source-origin-projection
                    (ivory-key.model:interaction-compatibility-role-reference-origin
                     reference))))
           (ivory-key.model:release-trigger-interaction-compatibility-contract-role-references
            contract))
          :origin
          (%canonical-source-origin-projection
           (ivory-key.model:interaction-compatibility-contract-origin contract))
          :provenance
          (list :interaction
                (%canonical-source-origin-projection
                 (ivory-key.model:interaction-compatibility-provenance-interaction-origin
                  provenance))
                :timeout
                (%canonical-source-origin-projection
                 (ivory-key.model:interaction-compatibility-provenance-timeout-origin
                  provenance))
                :foreign-release
                (%canonical-source-origin-projection
                 (ivory-key.model:interaction-compatibility-provenance-foreign-release-origin
                  provenance))
                :tap
                (%canonical-source-origin-projection
                 (ivory-key.model:interaction-compatibility-provenance-tap-origin
                  provenance))))))

(defun simulator-result (machine)
  (make-simulation-result
   :outputs (simulator-outputs machine)
   :trace (simulator-trace machine)
   :latches (simulator-latches-alist machine)
   :axes (simulator-axes-alist machine)
   :active-effects (simulator-active-effect-names machine)
   :candidates (reverse (copy-list (simulator-candidates machine)))
   :semantic-transitions (simulator-semantic-transitions machine)
   :dispatch-transactions
   (mapcar
    (lambda (transaction)
      (let ((withheld (buffered-dispatch-transaction-withheld-event transaction)))
        (list :id (buffered-dispatch-transaction-id transaction)
              :state (buffered-dispatch-transaction-state transaction)
              :owner (buffered-dispatch-transaction-owner-position transaction)
              :owner-index (buffered-dispatch-transaction-owner-index transaction)
              :foreign-position (and withheld (timed-event-position withheld))
              :foreign-down-index
              (buffered-dispatch-transaction-withheld-index transaction)
              :foreign-down-time (and withheld (timed-event-time withheld))
              :terminal-foreign-position
              (buffered-dispatch-transaction-terminal-foreign-position transaction)
              :terminal-foreign-index
              (buffered-dispatch-transaction-terminal-foreign-index transaction)
              :terminal-foreign-time
              (buffered-dispatch-transaction-terminal-foreign-time transaction)
              :disposition (buffered-dispatch-transaction-disposition transaction)
              :committed-role (buffered-dispatch-transaction-committed-role transaction)
              ;; Result/dump output has a deliberately closed value vocabulary:
              ;; retain evidence as canonical data, never as CLOS references.
              :contract
              (%canonical-buffered-contract-projection
               (buffered-dispatch-transaction-contract transaction))
              :origin (buffered-dispatch-transaction-origin transaction))))
    (buffered-dispatch-transactions machine))))

(defun simulate-events (interactions events &key latches axes until)
  "Run EVENTS through a fresh reference machine and return a SIMULATION-RESULT.

EVENTS must be supplied in nondecreasing timestamp order.  UNTIL optionally
advances clocks after the final physical input, useful for a held interaction."
  (let ((machine (make-simulator :interactions interactions :latches latches :axes axes)))
    (dolist (event events)
      (simulator-feed-event machine event))
    (when until (simulator-advance-to machine until))
    (simulator-result machine)))
