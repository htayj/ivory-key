;;;; SPDX-License-Identifier: GPL-3.0-or-later
;;;; Realization-profile declarations.  No backend spelling enters this model.

(in-package #:ivory-key.model)

(defclass realization-profile ()
  ((name :initarg :name :reader realization-profile-name)
   ;; Ordered opaque backend identities.  Their concrete protocols live
   ;; outside the semantic model.
   (pipeline :initarg :pipeline :initform nil :reader realization-profile-pipeline)
   (placement :initarg :placement :initform nil :reader realization-profile-placement)
   ;; A selected OUTPUT-VOCABULARY is part of the realization contract.  It
   ;; describes only opaque backend spellings, never layout meaning.
   (vocabulary :initarg :vocabulary :initform nil :reader realization-profile-vocabulary)
   (permitted-losses :initarg :permitted-losses :initform nil
                     :reader realization-profile-permitted-losses)
   ;; Selector allocation is realization policy rather than layout meaning.
   ;; It remains a closed, typed value so compiler/backends never need to
   ;; interpret an opaque profile plist or a backend snippet.
   (selector-policy :initarg :selector-policy :initform nil
                    :reader realization-profile-selector-policy)
   ;; A deliberately narrow selection for the one currently disputed
   ;; Manna/Kanata timed-interaction boundary.  NIL means no route has been
   ;; selected; it must never be interpreted as a modern or versioned-runtime
   ;; default by a compiler or backend.  A selected policy identifies its
   ;; finite interaction-instance set, so it cannot relabel unrelated timed
   ;; interactions as Manna-specific obligations.
   (interaction-compatibility-policy
    :initarg :interaction-compatibility-policy :initform nil
    :reader realization-profile-interaction-compatibility-policy)
   ;; Kanata 1.12 buffered action spellings are realization-owned, not layout
   ;; behavior.  NIL remains meaningful: selected compatibility evidence does
   ;; not authorize the compiler to invent the token/layer allocation.
   (kanata-buffered-allocation-policy
    :initarg :kanata-buffered-allocation-policy :initform nil
    :reader realization-profile-kanata-buffered-allocation-policy)
   (metadata :initarg :metadata :initform nil :reader realization-profile-metadata)))

(defun %realization-error (code control &rest arguments)
  (apply #'signal-semantic-error 'semantic-validation-error code control arguments))

(defun %realization-pipeline-identifiers (pipeline)
  "Validate PIPELINE enough to bind an output vocabulary without reordering it."
  (unless (listp pipeline)
    (%realization-error :malformed-realization-pipeline
                        "A realization pipeline must be a list, got ~S." pipeline))
  (let ((identifiers
          (mapcar (lambda (backend)
                    (handler-case
                        (ensure-identifier backend)
                      (error ()
                        (%realization-error
                         :invalid-realization-backend
                         "Realization backend must be an identifier, got ~S." backend))))
                  pipeline)))
    (unless (unique-identifiers-p identifiers)
      (%realization-error :duplicate-realization-backend
                          "A realization pipeline repeats a backend identity."))
    identifiers))

(defun %validate-realization-vocabulary (pipeline vocabulary)
  "Require every declared vocabulary backend to belong to PIPELINE.

The converse is intentionally not required: a pipeline stage need not itself
spell every application-visible output.  This leaves a later lowering free to
prove a carrier/pass-through stage without inventing a backend token here.
"
  (cond
    ((null vocabulary) nil)
    ((not (typep vocabulary 'output-vocabulary))
     (%realization-error :invalid-realization-vocabulary
                         "A realization vocabulary must be an OUTPUT-VOCABULARY, got ~S."
                         vocabulary))
    (t
     (dolist (backend (output-vocabulary-backends vocabulary))
       (unless (identifier-member-p backend pipeline)
         (%realization-error
          :unknown-realization-vocabulary-backend
          "Vocabulary backend ~A is not part of the realization pipeline."
          (identifier-name backend)))))))

;;; Closed selector/carrier allocation --------------------------------------

;; These values deliberately express only the bounded native allocation that
;; has source evidence for the bootstrap XKB + Kanata bridge.  They are model
;; values, not source snippets: backend emitters choose their own grammar.
(defparameter +realization-static-types+
  '(:four-level :four-level-alphabetic))

(defparameter +realization-group-two-types+
  '(:two-level))

(defparameter +realization-selector-controls+
  '(:shift :level-three :group-two))

(defparameter +realization-selector-consumptions+
  '(:consumed :group-action))

(defparameter +realization-selector-client-semantics+
  '(:core-shift :consumed-level-three
    :libxkbcommon-depressed-group-two-with-visible-level-three
    :unproved-group-two))

(defparameter +realization-carrier-xkb-keys+
  '(:zeha :lvl3))

;; This is intentionally not a general interaction taxonomy.  It names the
;; only two V1 Manna/Kanata foreign-event routes presently under review: the
;; proposed modern no-delay rule and the versioned Kanata 1.12 buffering rule.
;; No realization receives either by default.
(defparameter +realization-interaction-compatibility-modes+
  '(:modern-no-delay :kanata-1-12-buffered))

(defclass realization-interaction-compatibility-policy ()
  ((mode :initarg :mode :reader realization-interaction-compatibility-policy-mode)
   ;; Canonical, nonempty set of concrete normalized interaction identities.
   ;; Template body names are not eligible: the compiler validates these
   ;; identifiers only after top-level instance materialization/normalization.
   (interactions :initarg :interactions
                 :reader realization-interaction-compatibility-policy-interactions)))

;;; Closed Kanata 1.12 buffered allocation ---------------------------------

;; This is intentionally a realization value rather than a generic Kanata
;; configuration language.  It can describe exactly the atoms consumed by the
;; inert typed action handoff, including an explicit *alias name*, but never
;; arbitrary parenthesized actions, queue rules, or an emitted configuration.
(defparameter +realization-kanata-buffered-hold-kinds+
  '(:modifier :axis-modifier :axis-layer))

(defclass realization-kanata-buffered-hold-allocation ()
  ((kind :initarg :kind :reader realization-kanata-buffered-hold-kind)
   (identity :initarg :identity
             :reader realization-kanata-buffered-hold-identity)
   (state :initarg :state :initform nil
          :reader realization-kanata-buffered-hold-state)
   (layer :initarg :layer :initform nil
          :reader realization-kanata-buffered-hold-layer)
   (token :initarg :token :reader realization-kanata-buffered-hold-token))
  (:documentation
   "One explicit modifier or axis-held Kanata atom/layer allocation."))

(defclass realization-kanata-buffered-foreign-route ()
  ((position :initarg :position
             :reader realization-kanata-buffered-foreign-route-position)
   ;; The semantic named-key identity is recovered from the normalized direct
   ;; binding.  TOKEN is its realization-owned Kanata spelling.
   (token :initarg :token
          :reader realization-kanata-buffered-foreign-route-token))
  (:documentation
   "One explicitly admitted direct named-key foreign route allocation."))

(defclass realization-kanata-buffered-action-allocation ()
  ((interaction :initarg :interaction
                :reader realization-kanata-buffered-action-interaction)
   ;; Alias spelling is realization-owned.  Deriving it from the interaction
   ;; identifier would turn an inspection-only semantic name into backend
   ;; grammar and create an unreviewed collision surface.
   (alias-token :initarg :alias-token
                :reader realization-kanata-buffered-action-alias-token)
   (tap-token :initarg :tap-token
              :reader realization-kanata-buffered-action-tap-token)
   (hold :initarg :hold :reader realization-kanata-buffered-action-hold)
   ;; Canonical references into the parent policy's route table.  The action
   ;; constructor requires at least one: a buffered policy without any
   ;; admitted foreign route is not an actionable handoff.
   (foreign-route-positions :initarg :foreign-route-positions
                            :reader realization-kanata-buffered-action-foreign-route-positions))
  (:documentation
   "One selected interaction's typed, non-emitting Kanata allocation row."))

(defclass realization-kanata-buffered-allocation-policy ()
  ((actions :initarg :actions
            :reader realization-kanata-buffered-allocation-policy-actions)
   (foreign-routes :initarg :foreign-routes
                   :reader realization-kanata-buffered-allocation-policy-foreign-routes))
  (:documentation
   "Closed allocation table for an explicitly selected buffered policy."))

(defun %realization-kanata-buffered-safe-token-p (value)
  "Recognize one opaque Kanata atom, never an action/configuration fragment."
  (and (stringp value)
       (plusp (length value))
       (or (every (lambda (character)
                    (let ((code (char-code character)))
                      (or (<= (char-code #\A) code (char-code #\Z))
                          (<= (char-code #\a) code (char-code #\z))
                          (<= (char-code #\0) code (char-code #\9))
                          (find character "_-"))))
                  value)
           (member value '("=" "[" "]" ";" "'" "\\" "," "." "/")
                   :test #'string=))))

(defun %realization-kanata-buffered-token (value role)
  (unless (%realization-kanata-buffered-safe-token-p value)
    (%realization-error :unsafe-realization-kanata-buffered-token
                        "~A must be one closed Kanata atom." role))
  (string-downcase value))

(defun %realization-kanata-buffered-alias-token (value role)
  "Validate one identifier-shaped alias name, never an input punctuation atom.

The input vocabulary above intentionally permits tokens such as `;` because
they can be physical Kanata source keys.  An alias is emitted in a definition
position, so it has a strictly narrower grammar and cannot be a comment,
delimiter, or action fragment.
"
  (unless (and (stringp value)
               (plusp (length value))
               (let ((first (char value 0)))
                 (or (alpha-char-p first) (char= first #\_)))
               (every (lambda (character)
                        (or (alphanumericp character)
                            (find character "_-")))
                      value))
    (%realization-error :unsafe-realization-kanata-buffered-alias
                        "~A must be one closed Kanata alias identifier." role))
  (string-downcase value))

(defun %realization-kanata-buffered-identifiers (values code role &key nonempty)
  (unless (listp values)
    (%realization-error code "~A must be a list, got ~S." role values))
  (when (and nonempty (null values))
    (%realization-error code "~A must not be empty." role))
  (let ((identifiers
          (mapcar (lambda (value)
                    (handler-case
                        (ensure-identifier value)
                      (error ()
                        (%realization-error code
                                            "~A contains a non-identifier value ~S."
                                            role value))))
                  values)))
    (unless (unique-identifiers-p identifiers)
      (%realization-error code "~A repeats an identifier." role))
    (sort identifiers #'identifier<)))

(defun make-realization-kanata-buffered-hold-allocation
    (kind identity token &key state layer)
  "Create one closed semantic-held-effect to Kanata allocation.

The three forms are :MODIFIER (identity/token), :AXIS-MODIFIER
(axis/state/token), and :AXIS-LAYER (axis/state/layer/token).  Tokens remain
opaque atoms in the realization policy; this constructor admits no raw action
syntax.
"
  (%realization-closed-value kind +realization-kanata-buffered-hold-kinds+
                             :unsupported-realization-kanata-buffered-hold-kind
                             "Kanata buffered hold kind")
  (let ((identifier (ensure-identifier identity))
        (canonical-token (%realization-kanata-buffered-token token
                                                               "Kanata buffered hold token"))
        (canonical-state (and state (ensure-identifier state)))
        (canonical-layer (and layer (ensure-identifier layer))))
    (unless (ecase kind
              (:modifier (and (null canonical-state) (null canonical-layer)))
              (:axis-modifier (and canonical-state (null canonical-layer)))
              (:axis-layer (and canonical-state canonical-layer)))
      (%realization-error :invalid-realization-kanata-buffered-hold
                          "Kanata buffered hold kind ~S has incompatible state/layer fields."
                          kind))
    (make-instance 'realization-kanata-buffered-hold-allocation
                   :kind kind :identity identifier :state canonical-state
                   :layer canonical-layer :token canonical-token)))

(defun make-realization-kanata-buffered-foreign-route (position token)
  "Allocate one physical direct-named-key foreign route without a raw action."
  (make-instance 'realization-kanata-buffered-foreign-route
                 :position (ensure-identifier position)
                 :token (%realization-kanata-buffered-token
                         token "Kanata buffered foreign route token")))

(defun make-realization-kanata-buffered-action-allocation
    (interaction alias-token tap-token hold foreign-route-positions)
  "Allocate one selected buffered interaction's alias, tap, hold, and routes.

ALIAS-TOKEN is deliberately explicit: this semantic model never turns an
interaction identity into a backend alias spelling on its own.
"
  (unless (typep hold 'realization-kanata-buffered-hold-allocation)
    (%realization-error :invalid-realization-kanata-buffered-hold
                        "Buffered action hold must be a typed hold allocation."))
  ;; Reconstructing it closes programmatic MAKE-INSTANCE field bypasses; retain
  ;; the canonical copy rather than the caller's mutable object.
  (let ((canonical-hold
          (make-realization-kanata-buffered-hold-allocation
           (realization-kanata-buffered-hold-kind hold)
           (realization-kanata-buffered-hold-identity hold)
           (realization-kanata-buffered-hold-token hold)
           :state (realization-kanata-buffered-hold-state hold)
           :layer (realization-kanata-buffered-hold-layer hold))))
    (make-instance 'realization-kanata-buffered-action-allocation
                   :interaction (ensure-identifier interaction)
                   :alias-token (%realization-kanata-buffered-alias-token
                                 alias-token "Kanata buffered alias token")
                   :tap-token (%realization-kanata-buffered-token
                               tap-token "Kanata buffered tap token")
                   :hold canonical-hold
                   :foreign-route-positions
                   (%realization-kanata-buffered-identifiers
                    foreign-route-positions
                    :invalid-realization-kanata-buffered-action-routes
                    "Kanata buffered action routes" :nonempty t))))

(defun %validate-realization-kanata-buffered-hold-allocation (hold)
  (unless (typep hold 'realization-kanata-buffered-hold-allocation)
    (%realization-error :invalid-realization-kanata-buffered-hold
                        "Buffered hold allocation is not typed."))
  (let ((canonical
          (make-realization-kanata-buffered-hold-allocation
           (realization-kanata-buffered-hold-kind hold)
           (realization-kanata-buffered-hold-identity hold)
           (realization-kanata-buffered-hold-token hold)
           :state (realization-kanata-buffered-hold-state hold)
           :layer (realization-kanata-buffered-hold-layer hold))))
    (unless (and (eq (realization-kanata-buffered-hold-kind hold)
                     (realization-kanata-buffered-hold-kind canonical))
                 (identifier= (realization-kanata-buffered-hold-identity hold)
                              (realization-kanata-buffered-hold-identity canonical))
                 (equal (realization-kanata-buffered-hold-state hold)
                        (realization-kanata-buffered-hold-state canonical))
                 (equal (realization-kanata-buffered-hold-layer hold)
                        (realization-kanata-buffered-hold-layer canonical))
                 (string= (realization-kanata-buffered-hold-token hold)
                          (realization-kanata-buffered-hold-token canonical)))
      (%realization-error :noncanonical-realization-kanata-buffered-hold
                          "Buffered hold allocation fields must be canonical.")))
  hold)

(defun %validate-realization-kanata-buffered-route (route)
  (unless (typep route 'realization-kanata-buffered-foreign-route)
    (%realization-error :invalid-realization-kanata-buffered-route
                        "Buffered foreign route allocation is not typed."))
  (let ((canonical
          (make-realization-kanata-buffered-foreign-route
           (realization-kanata-buffered-foreign-route-position route)
           (realization-kanata-buffered-foreign-route-token route))))
    (unless (and (identifier=
                  (realization-kanata-buffered-foreign-route-position route)
                  (realization-kanata-buffered-foreign-route-position canonical))
                 (string= (realization-kanata-buffered-foreign-route-token route)
                          (realization-kanata-buffered-foreign-route-token canonical)))
      (%realization-error :noncanonical-realization-kanata-buffered-route
                          "Buffered foreign route fields must be canonical.")))
  route)

(defun %validate-realization-kanata-buffered-action-allocation (action)
  (unless (typep action 'realization-kanata-buffered-action-allocation)
    (%realization-error :invalid-realization-kanata-buffered-action
                        "Buffered action allocation is not typed."))
  (%validate-realization-kanata-buffered-hold-allocation
   (realization-kanata-buffered-action-hold action))
  (let ((canonical
          (make-realization-kanata-buffered-action-allocation
           (realization-kanata-buffered-action-interaction action)
           (realization-kanata-buffered-action-alias-token action)
           (realization-kanata-buffered-action-tap-token action)
           (realization-kanata-buffered-action-hold action)
           (realization-kanata-buffered-action-foreign-route-positions action))))
    (unless (and (identifier=
                  (realization-kanata-buffered-action-interaction action)
                  (realization-kanata-buffered-action-interaction canonical))
                 (string= (realization-kanata-buffered-action-alias-token action)
                          (realization-kanata-buffered-action-alias-token canonical))
                 (string= (realization-kanata-buffered-action-tap-token action)
                          (realization-kanata-buffered-action-tap-token canonical))
                 (every #'identifier=
                        (realization-kanata-buffered-action-foreign-route-positions action)
                        (realization-kanata-buffered-action-foreign-route-positions canonical))
                 (= (length (realization-kanata-buffered-action-foreign-route-positions action))
                    (length (realization-kanata-buffered-action-foreign-route-positions canonical))))
      (%realization-error :noncanonical-realization-kanata-buffered-action
                          "Buffered action allocation fields must be canonical.")))
  action)

(defun make-realization-kanata-buffered-allocation-policy (actions foreign-routes)
  "Create a canonical finite allocation table for inert buffered Kanata ASTs."
  (unless (and (listp actions) (listp foreign-routes))
    (%realization-error :invalid-realization-kanata-buffered-allocation-policy
                        "Buffered action and foreign-route allocations must be lists."))
  (when (null actions)
    (%realization-error :empty-realization-kanata-buffered-actions
                        "Buffered allocation policy needs at least one action row."))
  (mapc #'%validate-realization-kanata-buffered-action-allocation actions)
  (mapc #'%validate-realization-kanata-buffered-route foreign-routes)
  (%ensure-realization-policy-unique
   actions (lambda (action)
             (identifier-key (realization-kanata-buffered-action-interaction action)))
   :duplicate-realization-kanata-buffered-action "Buffered action allocations")
  (%ensure-realization-policy-unique
   actions #'realization-kanata-buffered-action-alias-token
   :duplicate-realization-kanata-buffered-alias "Buffered action aliases")
  (%ensure-realization-policy-unique
   foreign-routes (lambda (route)
                    (identifier-key
                     (realization-kanata-buffered-foreign-route-position route)))
   :duplicate-realization-kanata-buffered-route "Buffered foreign routes")
  (let ((route-positions
          (mapcar #'realization-kanata-buffered-foreign-route-position foreign-routes)))
    (dolist (action actions)
      (dolist (position
               (realization-kanata-buffered-action-foreign-route-positions action))
        (unless (identifier-member-p position route-positions)
          (%realization-error :unknown-realization-kanata-buffered-route
                              "Buffered action ~A refers to undeclared route ~A."
                              (identifier-name
                               (realization-kanata-buffered-action-interaction action))
                              (identifier-name position))))))
  (make-instance 'realization-kanata-buffered-allocation-policy
                 :actions (sort (copy-list actions) #'identifier<
                                :key #'realization-kanata-buffered-action-interaction)
                 :foreign-routes
                 (sort (copy-list foreign-routes) #'identifier<
                       :key #'realization-kanata-buffered-foreign-route-position)))

(defun validate-realization-kanata-buffered-allocation-policy (policy)
  "Validate POLICY and reject noncanonical programmatic list order."
  (unless (typep policy 'realization-kanata-buffered-allocation-policy)
    (%realization-error :invalid-realization-kanata-buffered-allocation-policy
                        "Expected a REALIZATION-KANATA-BUFFERED-ALLOCATION-POLICY."))
  (let ((canonical
          (make-realization-kanata-buffered-allocation-policy
           (realization-kanata-buffered-allocation-policy-actions policy)
           (realization-kanata-buffered-allocation-policy-foreign-routes policy))))
    (unless (and (= (length (realization-kanata-buffered-allocation-policy-actions policy))
                    (length (realization-kanata-buffered-allocation-policy-actions canonical)))
                 (= (length (realization-kanata-buffered-allocation-policy-foreign-routes policy))
                    (length (realization-kanata-buffered-allocation-policy-foreign-routes canonical)))
                 (every #'identifier=
                        (mapcar #'realization-kanata-buffered-action-interaction
                                (realization-kanata-buffered-allocation-policy-actions policy))
                        (mapcar #'realization-kanata-buffered-action-interaction
                                (realization-kanata-buffered-allocation-policy-actions canonical)))
                 (every #'identifier=
                        (mapcar #'realization-kanata-buffered-foreign-route-position
                                (realization-kanata-buffered-allocation-policy-foreign-routes policy))
                        (mapcar #'realization-kanata-buffered-foreign-route-position
                                (realization-kanata-buffered-allocation-policy-foreign-routes canonical))))
      (%realization-error :noncanonical-realization-kanata-buffered-allocation-policy
                          "Buffered allocation policy rows must be canonical.")))
  policy)

(defclass realization-static-type ()
  ((position :initarg :position :reader realization-static-type-position)
   ;; The two values are deliberately separate: a Group1 four-level table
   ;; does not imply any Group2 behavior or type shape.
   (type :initarg :type :reader realization-static-type-type)
   (group-two-type :initarg :group-two-type
                   :reader realization-static-type-group-two-type)))

(defclass realization-context-selector ()
  ((axis :initarg :axis :reader realization-selector-axis)
   (state :initarg :state :reader realization-selector-state)
   (control :initarg :control :reader realization-selector-control)
   (consumption :initarg :consumption
                :reader realization-selector-consumption)
   ;; This names the *observable client boundary*, not merely the XKB action
   ;; mechanism above.  Group2 has one explicit refusal and one separately
   ;; evidence-named generated-XKB state contract; no profile may silently
   ;; turn SetGroup into an exact claim.
   (client-semantics :initarg :client-semantics
                     :reader realization-selector-client-semantics)))

(defclass realization-direct-carrier ()
  ((position :initarg :position :reader realization-carrier-position)
   (axis :initarg :axis :reader realization-carrier-axis)
   (state :initarg :state :reader realization-carrier-state)
   (linux-code :initarg :linux-code :reader realization-carrier-linux-code)
   (xkb-key :initarg :xkb-key :reader realization-carrier-xkb-key)))

(defclass realization-selector-policy ()
  ((static-types :initarg :static-types
                 :reader realization-selector-policy-static-types)
   (selectors :initarg :selectors
              :reader realization-selector-policy-selectors)
   (carriers :initarg :carriers
             :reader realization-selector-policy-carriers)))

(defun %realization-closed-value (value permitted code role)
  (unless (member value permitted)
    (%realization-error code "~A has unsupported value ~S." role value))
  value)

(defun %realization-interaction-compatibility-instances (interactions)
  "Validate and canonically order the policy's concrete interaction instances."
  (unless (listp interactions)
    (%realization-error
     :invalid-realization-interaction-compatibility-instances
     "Realization interaction compatibility instances must be a list, got ~S."
     interactions))
  (when (null interactions)
    (%realization-error
     :empty-realization-interaction-compatibility-instances
     "Realization interaction compatibility requires at least one instance."))
  (let ((canonical
          (mapcar (lambda (interaction)
                    (handler-case
                        (ensure-identifier interaction)
                      (error ()
                        (%realization-error
                         :invalid-realization-interaction-compatibility-instance
                         "Realization interaction compatibility instance must be an identifier, got ~S."
                         interaction))))
                  interactions)))
    (unless (unique-identifiers-p canonical)
      (%realization-error
       :duplicate-realization-interaction-compatibility-instance
       "Realization interaction compatibility repeats an instance identity."))
    (sort canonical #'identifier<)))

(defun make-realization-interaction-compatibility-policy (mode interactions)
  "Select one closed V1 Manna/Kanata timed-interaction compatibility route.

MODE is either :MODERN-NO-DELAY, the proposed `manna-release-trigger-v1`
foreign-event rule, or :KANATA-1-12-BUFFERED, the bounded versioned Kanata
1.12 buffer/replay observation.  INTERACTIONS is a nonempty, canonical set of
concrete interaction-instance identities to which this narrow refusal route
applies.  This model value selects neither a generic interaction meaning nor a
backend action.  A NIL profile slot is deliberately unselected rather than a
default MODE.
"
  (%realization-closed-value
   mode +realization-interaction-compatibility-modes+
   :unsupported-realization-interaction-compatibility-mode
   "Realization interaction compatibility mode")
  (make-instance 'realization-interaction-compatibility-policy
                 :mode mode
                 :interactions
                 (%realization-interaction-compatibility-instances interactions)))

(defun validate-realization-interaction-compatibility-policy (policy)
  "Validate POLICY as one closed, selected V1 compatibility route."
  (unless (typep policy 'realization-interaction-compatibility-policy)
    (%realization-error
     :invalid-realization-interaction-compatibility-policy
     "Expected a REALIZATION-INTERACTION-COMPATIBILITY-POLICY, got ~S."
     policy))
  (let* ((stored
           (realization-interaction-compatibility-policy-interactions policy))
         ;; Reuse the public constructor so programmatically assembled values
         ;; receive the same closed-enum, nonempty, and duplicate validation as
         ;; decoded source.  Do not replace POLICY: realization/profile objects
         ;; preserve their identity across compiler boundaries.
         (canonical-policy
           (make-realization-interaction-compatibility-policy
            (realization-interaction-compatibility-policy-mode policy)
            stored))
         (canonical
           (realization-interaction-compatibility-policy-interactions
            canonical-policy)))
    ;; A raw MAKE-INSTANCE may bypass the constructor.  Permit no alternative
    ;; representation here: inspection, metadata, and backend matching all
    ;; require actual identifier objects in canonical set order.  Silently
    ;; replacing the slot would make an identity-bearing realization mutable at
    ;; validation time; refusing leaves that programmatic error explicit.
    (unless (every (lambda (interaction)
                     (typep interaction 'identifier))
                   stored)
      (%realization-error
       :invalid-realization-interaction-compatibility-instance
       "Programmatic interaction compatibility instances must be IDENTIFIER objects."))
    (unless (and (= (length stored) (length canonical))
                 (every #'identifier= stored canonical))
      (%realization-error
       :noncanonical-realization-interaction-compatibility-instances
       "Programmatic interaction compatibility instances must be in canonical set order.")))
  policy)

(defun make-realization-static-type (position type group-two-type)
  "Allocate a source-derived conventional XKB static-table type to POSITION.

TYPE is a closed Group1 keyword, currently :FOUR-LEVEL or
:FOUR-LEVEL-ALPHABETIC.  GROUP-TWO-TYPE is independently closed to
:TWO-LEVEL.  The backend owns the spellings of both types.
"
  (%realization-closed-value type +realization-static-types+
                             :unsupported-realization-static-type
                             "Realization static type")
  (%realization-closed-value group-two-type +realization-group-two-types+
                             :unsupported-realization-group-two-type
                             "Realization Group2 static type")
  (make-instance 'realization-static-type :position (ensure-identifier position)
                 :type type :group-two-type group-two-type))

(defun make-realization-context-selector (axis state control consumption
                                          client-semantics)
  "Describe one native selector allocation without embedding backend text."
  (%realization-closed-value control +realization-selector-controls+
                             :unsupported-realization-selector-control
                             "Realization selector control")
  (%realization-closed-value consumption +realization-selector-consumptions+
                             :unsupported-realization-selector-consumption
                             "Realization selector consumption")
  (%realization-closed-value client-semantics
                             +realization-selector-client-semantics+
                             :unsupported-realization-selector-client-semantics
                             "Realization selector client semantics")
  ;; A group action is deliberately distinct from a consumed modifier.  The
  ;; constraint is structural, so no backend can silently reinterpret it.
  (unless (if (eq control :group-two)
              (eq consumption :group-action)
              (eq consumption :consumed))
    (%realization-error :incompatible-realization-selector-consumption
                        "Selector control ~S is incompatible with consumption ~S."
                        control consumption))
  (unless (or (and (eq control :shift) (eq client-semantics :core-shift))
              (and (eq control :level-three)
                   (eq client-semantics :consumed-level-three))
              (and (eq control :group-two)
                   (member client-semantics
                           '(:libxkbcommon-depressed-group-two-with-visible-level-three
                             :unproved-group-two))))
    (%realization-error :incompatible-realization-selector-client-semantics
                        "Selector control ~S is incompatible with client semantics ~S."
                        control client-semantics))
  (make-instance 'realization-context-selector
                 :axis (ensure-identifier axis) :state (ensure-identifier state)
                 :control control :consumption consumption
                 :client-semantics client-semantics))

(defun make-realization-direct-carrier (position axis state linux-code xkb-key)
  "Allocate one of the two evidenced Linux carrier paths to a logical owner.

The policy stores the carrier numerically and its closed XKB identity; Kanata
syntax is formed only by the backend emitter.  Keeping this bounded prevents
an arbitrary profile string from becoming generated configuration.
"
  (unless (member linux-code '(84 85))
    (%realization-error :unsupported-realization-carrier
                        "Linux carrier code ~S is outside the evidenced 84/85 allocation."
                        linux-code))
  (%realization-closed-value xkb-key +realization-carrier-xkb-keys+
                             :unsupported-realization-carrier-key
                             "Realization carrier XKB key")
  (unless (or (and (= linux-code 85) (eq xkb-key :zeha))
              (and (= linux-code 84) (eq xkb-key :lvl3)))
    (%realization-error :incompatible-realization-carrier
                        "Carrier code ~D is not the evidenced allocation for ~S."
                        linux-code xkb-key))
  (make-instance 'realization-direct-carrier
                 :position (ensure-identifier position)
                 :axis (ensure-identifier axis) :state (ensure-identifier state)
                 :linux-code linux-code :xkb-key xkb-key))

(defun %ensure-realization-policy-list (value class code role)
  (unless (and (listp value) (every (lambda (entry) (typep entry class)) value))
    (%realization-error code "~A must be a list of ~A values." role class))
  value)

(defun %ensure-realization-policy-unique (entries key code role)
  (let ((seen (make-hash-table :test #'equal)))
    (dolist (entry entries)
      (let ((identity (funcall key entry)))
        (when (gethash identity seen)
          (%realization-error code "~A repeats allocation ~S." role identity))
        (setf (gethash identity seen) t)))))

(defun %validate-realization-static-type (entry)
  (unless (typep (realization-static-type-position entry) 'identifier)
    (%realization-error :invalid-realization-static-type-position
                        "A realization static type position must be an IDENTIFIER."))
  (%realization-closed-value (realization-static-type-type entry)
                             +realization-static-types+
                             :unsupported-realization-static-type
                             "Realization static type")
  (%realization-closed-value (realization-static-type-group-two-type entry)
                             +realization-group-two-types+
                             :unsupported-realization-group-two-type
                             "Realization Group2 static type")
  entry)

(defun %validate-realization-selector (entry)
  (unless (and (typep (realization-selector-axis entry) 'identifier)
               (typep (realization-selector-state entry) 'identifier))
    (%realization-error :invalid-realization-selector-identity
                        "A realization selector axis and state must be IDENTIFIER values."))
  ;; Reconstruct through the closed public constructor, which validates both
  ;; the individual enum values and their mechanism/client pairing.
  (make-realization-context-selector
   (realization-selector-axis entry) (realization-selector-state entry)
   (realization-selector-control entry) (realization-selector-consumption entry)
   (realization-selector-client-semantics entry))
  entry)

(defun %validate-realization-carrier (entry)
  (unless (and (typep (realization-carrier-position entry) 'identifier)
               (typep (realization-carrier-axis entry) 'identifier)
               (typep (realization-carrier-state entry) 'identifier))
    (%realization-error :invalid-realization-carrier-identity
                        "A realization carrier position, axis, and state must be IDENTIFIER values."))
  (make-realization-direct-carrier
   (realization-carrier-position entry) (realization-carrier-axis entry)
   (realization-carrier-state entry) (realization-carrier-linux-code entry)
   (realization-carrier-xkb-key entry))
  entry)

(defun make-realization-selector-policy (static-types selectors carriers)
  "Create an immutable, backend-neutral selector/carrier allocation policy.

Completeness depends on the selected normalized layout and is therefore
checked at the compiler boundary.  This constructor establishes the closed
value domain and rejects duplicate resource owners up front.
"
  (%ensure-realization-policy-list static-types 'realization-static-type
                                   :invalid-realization-static-types
                                   "Realization static types")
  (%ensure-realization-policy-list selectors 'realization-context-selector
                                   :invalid-realization-selectors
                                   "Realization selectors")
  (%ensure-realization-policy-list carriers 'realization-direct-carrier
                                   :invalid-realization-carriers
                                   "Realization carriers")
  (mapc #'%validate-realization-static-type static-types)
  (mapc #'%validate-realization-selector selectors)
  (mapc #'%validate-realization-carrier carriers)
  (%ensure-realization-policy-unique
   static-types
   (lambda (entry) (identifier-key (realization-static-type-position entry)))
   :duplicate-realization-static-type "Realization static types")
  (%ensure-realization-policy-unique
   selectors
   (lambda (entry) (identifier-key (realization-selector-axis entry)))
   :duplicate-realization-selector "Realization selectors")
  (%ensure-realization-policy-unique
   carriers
   (lambda (entry) (identifier-key (realization-carrier-position entry)))
   :duplicate-realization-carrier-position "Realization carriers")
  (%ensure-realization-policy-unique
   carriers #'realization-carrier-linux-code
   :duplicate-realization-carrier-code "Realization carriers")
  (make-instance 'realization-selector-policy
                 :static-types (sort (copy-list static-types) #'identifier<
                                     :key #'realization-static-type-position)
                 :selectors (sort (copy-list selectors) #'identifier<
                                  :key #'realization-selector-axis)
                 :carriers (sort (copy-list carriers) #'identifier<
                                 :key #'realization-carrier-position)))

(defun validate-realization-selector-policy (policy)
  "Validate POLICY as a closed allocation and return the same policy.

This is useful at a compiler/backend boundary receiving programmatically
constructed model objects.  It establishes representation safety only;
layout-specific completeness and runtime-client proof remain explicit later
obligations.
"
  (unless (typep policy 'realization-selector-policy)
    (%realization-error :invalid-realization-selector-policy
                        "Expected a REALIZATION-SELECTOR-POLICY, got ~S." policy))
  ;; Re-run the public constructor's complete validation without replacing the
  ;; caller's identity-bearing realization value.
  (make-realization-selector-policy
   (realization-selector-policy-static-types policy)
   (realization-selector-policy-selectors policy)
   (realization-selector-policy-carriers policy))
  policy)

(defun realization-policy-static-type-for-position (policy position)
  (and policy
       (find (ensure-identifier position)
             (realization-selector-policy-static-types policy)
             :test #'identifier=
             :key #'realization-static-type-position)))

(defun realization-policy-selector-for-axis (policy axis)
  (and policy
       (find (ensure-identifier axis)
             (realization-selector-policy-selectors policy)
             :test #'identifier=
             :key #'realization-selector-axis)))

(defun realization-policy-carrier-for-position (policy position)
  (and policy
       (find (ensure-identifier position)
             (realization-selector-policy-carriers policy)
             :test #'identifier=
             :key #'realization-carrier-position)))

(defun make-realization-profile (name &key pipeline placement vocabulary
                                      permitted-losses selector-policy
                                      interaction-compatibility-policy
                                      kanata-buffered-allocation-policy metadata)
  "Create a profile describing permitted lowering policy, not keyboard meaning.

When VOCABULARY is supplied, each of its backend identities must be selected
by PIPELINE.  The profile retains pipeline order and opaque spellings without
interpreting either as a backend grammar.
"
  (let ((pipeline-identifiers (%realization-pipeline-identifiers pipeline)))
    (%validate-realization-vocabulary pipeline-identifiers vocabulary))
  (when (and selector-policy
             (not (typep selector-policy 'realization-selector-policy)))
    (%realization-error :invalid-realization-selector-policy
                        "A realization selector policy must be a REALIZATION-SELECTOR-POLICY, got ~S."
                        selector-policy))
  (when selector-policy
    (validate-realization-selector-policy selector-policy))
  (when (and interaction-compatibility-policy
             (not (typep interaction-compatibility-policy
                         'realization-interaction-compatibility-policy)))
    (%realization-error
     :invalid-realization-interaction-compatibility-policy
     "A realization interaction compatibility policy must be a REALIZATION-INTERACTION-COMPATIBILITY-POLICY, got ~S."
     interaction-compatibility-policy))
  (when interaction-compatibility-policy
    (validate-realization-interaction-compatibility-policy
     interaction-compatibility-policy))
  (when (and kanata-buffered-allocation-policy
             (not (typep kanata-buffered-allocation-policy
                         'realization-kanata-buffered-allocation-policy)))
    (%realization-error :invalid-realization-kanata-buffered-allocation-policy
                        "A realization buffered allocation must be a typed policy."))
  (when kanata-buffered-allocation-policy
    (validate-realization-kanata-buffered-allocation-policy
     kanata-buffered-allocation-policy)
    (unless (and interaction-compatibility-policy
                 (eq (realization-interaction-compatibility-policy-mode
                      interaction-compatibility-policy)
                     :kanata-1-12-buffered))
      (%realization-error :kanata-buffered-allocation-without-buffered-policy
                          "Kanata buffered allocation requires selected :KANATA-1-12-BUFFERED compatibility."))
    (unless (and (= (length
                     (realization-kanata-buffered-allocation-policy-actions
                      kanata-buffered-allocation-policy))
                    (length
                     (realization-interaction-compatibility-policy-interactions
                      interaction-compatibility-policy)))
                 (every #'identifier=
                        (mapcar #'realization-kanata-buffered-action-interaction
                                (realization-kanata-buffered-allocation-policy-actions
                                 kanata-buffered-allocation-policy))
                        (realization-interaction-compatibility-policy-interactions
                         interaction-compatibility-policy)))
      (%realization-error :incomplete-realization-kanata-buffered-allocation
                          "Buffered allocation rows must cover exactly the selected interaction instances.")))
  (make-instance 'realization-profile :name (ensure-identifier name)
                 :pipeline (copy-list pipeline) :placement placement
                 :vocabulary vocabulary :permitted-losses (copy-list permitted-losses)
                 :selector-policy selector-policy
                 :interaction-compatibility-policy interaction-compatibility-policy
                 :kanata-buffered-allocation-policy
                 kanata-buffered-allocation-policy
                 :metadata metadata))
