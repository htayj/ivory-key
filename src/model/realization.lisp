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
                                      permitted-losses selector-policy metadata)
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
  (make-instance 'realization-profile :name (ensure-identifier name)
                 :pipeline (copy-list pipeline) :placement placement
                 :vocabulary vocabulary :permitted-losses (copy-list permitted-losses)
                 :selector-policy selector-policy
                 :metadata metadata))
