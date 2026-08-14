;;;; SPDX-License-Identifier: GPL-3.0-or-later
;;;; Declarative finite temporal patterns and interaction declarations.

(in-package #:ivory-key.model)

;;; These are specifications, not simulator events, candidate states, or
;;; executable recognizers.  The simulator translates validated specifications
;;; into its own timed transducer representation.

(defclass interaction-template-parameter ()
  ((name :initarg :name :reader interaction-parameter-name)))

(defun make-interaction-template-parameter (name)
  "A declarative placeholder accepted only while constructing a template body."
  (make-instance 'interaction-template-parameter :name (ensure-identifier name)))

(defun %interaction-identifier-or-parameter (value)
  (if (typep value 'interaction-template-parameter)
      value
      (ensure-identifier value)))

(defstruct (position-selector
            (:constructor %make-position-selector (kind positions))
            (:copier nil))
  "A finite selector over logical positions in a temporal pattern."
  kind
  positions)

(defun make-position-selector (kind &rest positions)
  (unless (member kind '(:position :any-position :other-than :captured))
    (error "Unknown position-selector kind ~S." kind))
  (%make-position-selector kind (mapcar #'%interaction-identifier-or-parameter positions)))

(defun position-selector (position)
  (make-position-selector :position position))

(defun any-position-selector ()
  (make-position-selector :any-position))

(defun other-than-selector (&rest positions)
  (apply #'make-position-selector :other-than positions))

(defun captured-position-selector (name)
  "Refer to NAME's earlier CAPTURE binding in the same finite candidate slice.

The selector remains declarative: it names neither an event object nor a host
callback.  Validation decides whether NAME is lexically available and whether
the surrounding capture shape is one the reference machine can execute."
  (make-position-selector :captured name))

(defstruct (temporal-pattern
            (:constructor %make-temporal-pattern (kind arguments options))
            (:copier nil))
  "A finite declarative pattern node.

KIND is one of the pattern algebra operations.  ARGUMENTS and OPTIONS contain
only source values or nested TEMPORAL-PATTERNs; no host callback can enter this
IR."
  kind
  arguments
  options)

(defun make-temporal-pattern (kind arguments &rest options)
  (%make-temporal-pattern kind (copy-list arguments) (copy-list options)))

(defun temporal-pattern-option (pattern option &optional default)
  (getf (temporal-pattern-options pattern) option default))

(defun pattern-down (position)
  (make-temporal-pattern :down (list (if (typep position 'position-selector)
                                         position (position-selector position)))))

(defun pattern-up (position)
  (make-temporal-pattern :up (list (if (typep position 'position-selector)
                                       position (position-selector position)))))

(defun pattern-sequence (&rest patterns)
  (make-temporal-pattern :sequence patterns))

(defun pattern-all (&rest patterns)
  (make-temporal-pattern :all patterns))

(defun pattern-either (&rest patterns)
  (make-temporal-pattern :either patterns))

(defun pattern-conjunction (&rest patterns)
  (make-temporal-pattern :and patterns))

(defun pattern-duration (position &key at-least less-than)
  (make-temporal-pattern :duration
                         (list (if (typep position 'position-selector) position
                                   (position-selector position)))
                         :at-least at-least :less-than less-than))

(defun pattern-deadline (duration &key after while-down)
  "A finite deadline clock anchored by AFTER, optionally while a key is down."
  (make-temporal-pattern :deadline (list duration after)
                         :while-down while-down))

(defun pattern-within (duration &rest patterns)
  (make-temporal-pattern :within patterns :duration duration))

(defun pattern-overlap (&rest positions)
  (make-temporal-pattern :overlap
                         (mapcar (lambda (position)
                                   (if (typep position 'position-selector) position
                                       (position-selector position)))
                                 positions)))

(defun pattern-without (forbidden &key between)
  "Require FORBIDDEN not to occur between a pair of closing-boundary patterns."
  (make-temporal-pattern :without (list forbidden) :between between))

(defun pattern-repeat (pattern &key at-most (at-least 0))
  "Finite repetition.  AT-MOST is mandatory and preserves static analyzability."
  (make-temporal-pattern :repeat (list pattern) :at-most at-most
                         :at-least at-least))

(defun pattern-capture (name pattern)
  (make-temporal-pattern :capture (list (ensure-identifier name) pattern)))

(defun pattern-context-is (axis state)
  "Observe a captured context axis value in a temporal pattern."
  (make-temporal-pattern :context-is
                         (list (ensure-identifier axis) (ensure-identifier state))))

(defun temporal-pattern-children (pattern)
  "Nested pattern nodes in PATTERN, including boundary options."
  (labels ((collect (value)
             (cond ((typep value 'temporal-pattern) (list value))
                   ((consp value) (mapcan #'collect value))
                   (t nil))))
    (mapcan #'collect
            (append (temporal-pattern-arguments pattern)
                    (temporal-pattern-options pattern)))))

(defun temporal-pattern-axis-dependencies (pattern)
  "Axes inspected by a context predicate anywhere in PATTERN."
  (remove-duplicates
   (append (when (eq (temporal-pattern-kind pattern) :context-is)
             (list (first (temporal-pattern-arguments pattern))))
           (mapcan #'temporal-pattern-axis-dependencies
                   (temporal-pattern-children pattern)))
   :test #'identifier=))

(defun temporal-pattern-position-selectors (pattern)
  "All finite position selectors named by PATTERN."
  (labels ((collect (object)
             (cond ((typep object 'position-selector) (list object))
                   ((typep object 'temporal-pattern)
                    (append (mapcan #'collect (temporal-pattern-arguments object))
                            (mapcan #'collect (temporal-pattern-options object))))
                   ((consp object) (mapcan #'collect object))
                   (t nil))))
    (collect pattern)))

(defclass interaction-effects ()
  ((entry :initarg :entry :initform nil :reader effect-entry-behaviors)
   (commit :initarg :commit :initform nil :reader effect-commit-behaviors)
   (while :initarg :while :initform nil :reader effect-while-behaviors)
   (exit :initarg :exit :initform nil :reader effect-exit-behaviors)
   (cancel :initarg :cancel :initform nil :reader effect-cancel-behaviors)
   (origin :initarg :origin :initform nil :reader interaction-effects-origin)))

(defun make-interaction-effects (&key entry commit while exit cancel origin)
  "Create explicit lifecycle effects for one candidate.

All values are lists of complete model behaviors.  The semantic validator
rejects unsafe irreversible entry/while effects.  Source HOLD-MODIFIER and
HOLD-AXIS-STATE are valid only in :WHILE and release automatically when their
owning effect exits or is cancelled."
  (make-instance 'interaction-effects :entry (copy-list entry)
                 :commit (copy-list commit) :while (copy-list while)
                 :exit (copy-list exit) :cancel (copy-list cancel) :origin origin))

(defun interaction-effects-behaviors (effects)
  (append (effect-entry-behaviors effects)
          (effect-commit-behaviors effects)
          (effect-while-behaviors effects)
          (effect-exit-behaviors effects)
          (effect-cancel-behaviors effects)))

(defclass interaction-candidate ()
  ((name :initarg :name :reader candidate-name)
   (match :initarg :match :reader candidate-match)
   ;; A commitment is either a temporal event/pattern, :WHEN-MATCHED, or
   ;; :WHEN-UNAMBIGUOUS.  The simulator owns executable commitment handling.
   (commit :initarg :commit :reader candidate-commit)
   ;; The normal irreversible behavior, emitted only after commitment.
   (behavior :initarg :behavior :reader candidate-behavior)
   (effects :initarg :effects :initform (make-interaction-effects)
            :reader candidate-effects)
   ;; NIL means discover dependencies from behavior/effects/pattern.
   (context-axes :initarg :context-axes :initform nil :reader candidate-context-axes)
   (context-policy :initarg :context-policy :initform :anchor-down
                   :reader candidate-context-policy)
   ;; :ON-MATCH preserves the original speculative effect timing.  :ON-COMMIT
   ;; is the explicit non-speculative variant for a candidate whose held
   ;; effect must not acquire until arbitration has selected the commitment.
   (effect-start :initarg :effect-start :initform :on-match
                 :reader candidate-effect-start)
   (metadata :initarg :metadata :initform nil :reader candidate-metadata)
   (origin :initarg :origin :initform nil :reader candidate-origin)))

(defun make-interaction-candidate (name match commit behavior
                                    &key effects context-axes
                                      (context-policy :anchor-down)
                                        (effect-start :on-match) metadata origin)
  "Create a candidate with an explicit match, commitment, behavior, lifecycle."
  (unless (member context-policy '(:anchor-down :commit))
    (error "Unknown context observation policy ~S." context-policy))
  (unless (member effect-start '(:on-match :on-commit))
    (error "Unknown candidate effect start policy ~S." effect-start))
  (make-instance 'interaction-candidate
                 :name (ensure-identifier name) :match match :commit commit
                 :behavior behavior :effects (or effects (make-interaction-effects))
                 :context-axes (and context-axes (copy-identifier-list context-axes))
                 :context-policy context-policy :effect-start effect-start
                 :metadata metadata :origin origin))

(defun candidate-axis-dependencies (candidate)
  "The exact dependency scope for a candidate's captured context."
  (or (candidate-context-axes candidate)
      (canonical-identifier-set
       (append (behavior-axis-dependencies (candidate-behavior candidate))
               (mapcan #'behavior-axis-dependencies
                       (interaction-effects-behaviors (candidate-effects candidate)))
               (temporal-pattern-axis-dependencies (candidate-match candidate))))))

(defclass interaction ()
  ((name :initarg :name :reader interaction-name)
   (participants :initarg :participants :reader interaction-participants)
   ;; :PARTICIPANTS is the normal finite scope.  :ANY-POSITION is allowed when
   ;; the interaction has a finite participant anchor and explicitly declares
   ;; the broader observation need.
   (observe :initarg :observe :initform :participants :reader interaction-observe)
   (anchor :initarg :anchor :initform nil :reader interaction-anchor)
   (candidates :initarg :candidates :reader interaction-candidates)
   ;; NIL deliberately means no implicit policy; conflicts then fail.
   (arbitration :initarg :arbitration :initform nil :reader interaction-arbitration)
   (metadata :initarg :metadata :initform nil :reader interaction-metadata)
   (origin :initarg :origin :initform nil :reader interaction-origin)))

(defun make-interaction (name participants candidates
                          &key (observe :participants) anchor arbitration metadata origin)
  "Create a finite interaction over logical press intervals."
  (make-instance 'interaction :name (ensure-identifier name)
                 :participants (mapcar #'%interaction-identifier-or-parameter participants)
                 :observe observe :anchor (and anchor (%interaction-identifier-or-parameter anchor))
                 :candidates (copy-list candidates) :arbitration arbitration
                 :metadata metadata :origin origin))

(defun priority-arbitration (&rest candidate-names)
  "A deterministic priority order, highest priority first."
  (list :priority (copy-identifier-list candidate-names)))

(defun longest-match-arbitration (&key deadline)
  "An explicit longest-match policy.  DEADLINE makes latency inspectable."
  (list :longest-match :deadline deadline))

(defclass interaction-template ()
  ((name :initarg :name :reader interaction-template-name)
   (parameters :initarg :parameters :reader interaction-template-parameters)
   (body :initarg :body :reader interaction-template-body)
   (origin :initarg :origin :initform nil :reader interaction-template-origin)))

(defun make-interaction-template (name parameters body &key origin)
  "Create a declarative interaction template; no arbitrary Lisp is evaluated."
  (make-instance 'interaction-template :name (ensure-identifier name)
                 :parameters (copy-identifier-list parameters) :body body
                 :origin origin))

(defclass interaction-template-reference ()
  ((name :initarg :name :reader interaction-reference-name)
   (arguments :initarg :arguments :reader interaction-reference-arguments)
   (origin :initarg :origin :initform nil :reader interaction-reference-origin)))

(defun make-interaction-template-reference (name arguments &key origin)
  (make-instance 'interaction-template-reference :name (ensure-identifier name)
                 :arguments (copy-list arguments) :origin origin))

(defun temporal-pattern-finite-p (pattern)
  "Cheap structural finiteness predicate used before detailed diagnostics.

Semantic validation supplies precise repair messages and position/clock checks.
This function stays deliberately conservative: an unfamiliar kind is not
finite merely because it happens to be represented by a small Lisp object."
  (and (typep pattern 'temporal-pattern)
       (member (temporal-pattern-kind pattern)
               '(:down :up :sequence :all :either :and :duration :deadline
                 :within :overlap :without :repeat :capture :context-is))
       (case (temporal-pattern-kind pattern)
         (:repeat (let ((maximum (temporal-pattern-option pattern :at-most)))
                    (and (integerp maximum) (<= 0 maximum))))
         (:deadline (let ((duration (first (temporal-pattern-arguments pattern))))
                      (and (numberp duration) (<= 0 duration))))
         (:duration (let ((minimum (temporal-pattern-option pattern :at-least))
                          (maximum (temporal-pattern-option pattern :less-than)))
                      (and (or (null minimum) (and (numberp minimum) (<= 0 minimum)))
                           (or (null maximum) (and (numberp maximum) (<= 0 maximum)))
                           (or (null minimum) (null maximum) (< minimum maximum)))))
         (otherwise t))
       (every #'temporal-pattern-finite-p (temporal-pattern-children pattern))))

(defun %captured-position-selector-p (selector)
  (and (typep selector 'position-selector)
       (eq (position-selector-kind selector) :captured)))

(defun temporal-pattern-capture-feature-p (pattern)
  "Whether PATTERN contains a CAPTURE binding or CAPTURED selector reference."
  (and (typep pattern 'temporal-pattern)
       (or (eq (temporal-pattern-kind pattern) :capture)
           (some #'%captured-position-selector-p
                 (temporal-pattern-position-selectors pattern)))))

(defun %direct-event-pattern-p (pattern kind &key captured-name)
  (and (typep pattern 'temporal-pattern)
       (eq (temporal-pattern-kind pattern) kind)
       (= (length (temporal-pattern-arguments pattern)) 1)
       (let ((selector (first (temporal-pattern-arguments pattern))))
         (if captured-name
             (and (%captured-position-selector-p selector)
                  (= (length (position-selector-positions selector)) 1)
                  (identifier= (first (position-selector-positions selector))
                               captured-name))
             (and (typep selector 'position-selector)
                  (not (%captured-position-selector-p selector)))))))

(defun temporal-pattern-capture-slice-p (pattern)
  "Recognize the first executable capture slice.

The reference simulator presently admits one immutable binding only in the
three-event sequence DOWN, CAPTURE(DOWN), UP(CAPTURED).  This deliberately
excludes nested, repeated, unordered, and alternative capture forms until
their binding search and cancellation semantics have been specified."
  (and (typep pattern 'temporal-pattern)
       (eq (temporal-pattern-kind pattern) :sequence)
       (= (length (temporal-pattern-arguments pattern)) 3)
       (let* ((children (temporal-pattern-arguments pattern))
              (first (first children))
              (capture (second children))
              (last (third children)))
         (and (%direct-event-pattern-p first :down)
              (typep capture 'temporal-pattern)
              (eq (temporal-pattern-kind capture) :capture)
              (= (length (temporal-pattern-arguments capture)) 2)
              (let ((name (first (temporal-pattern-arguments capture)))
                    (captured-pattern (second (temporal-pattern-arguments capture))))
                (and (typep name 'identifier)
                     (%direct-event-pattern-p captured-pattern :down)
                     (%direct-event-pattern-p last :up :captured-name name)))))))
