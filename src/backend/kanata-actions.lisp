;;;; SPDX-License-Identifier: GPL-3.0-or-later
;;;; Closed, inert Kanata 1.12 buffered-interaction action handoff.

(in-package #:ivory-key.backend)

;;; This file is intentionally an action *description*, rather than an
;;; emitter extension.  The known Kanata 1.12 probe does not prove deadline
;;; custody, cancellation, or bounded replay of a foreign event.  Therefore a
;;; valid value below is useful for deterministic inspection and future
;;; review, but does not constitute a permitted backend realization.

(define-condition kanata-action-validation-error (error)
  ((code :initarg :code :reader kanata-action-validation-error-code)
   (message :initarg :message :reader kanata-action-validation-error-message))
  (:report (lambda (condition stream)
             (format stream "~A" (kanata-action-validation-error-message condition)))))

(defun %kanata-action-error (code control &rest arguments)
  (error 'kanata-action-validation-error :code code
         :message (apply #'format nil control arguments)))

(defun %kanata-action-identifier (value label)
  "Accept a model identity but never a reader/evaluator value."
  (unless (or (stringp value) (typep value 'ivory-key.model:identifier))
    (%kanata-action-error :invalid-kanata-action-identifier
                          "~A must be an Ivory identifier, got ~S." label value))
  (handler-case
      (ivory-key.model:make-identifier value)
    (error ()
      (%kanata-action-error :invalid-kanata-action-identifier
                            "~A is not an Ivory identifier." label))))

(defun %kanata-action-origin (value label)
  (unless (or (null value) (typep value 'ivory-key.source:source-origin))
    (%kanata-action-error :invalid-kanata-action-provenance
                          "~A must be NIL or a SOURCE-ORIGIN." label))
  value)

(defun %kanata-action-token (value label)
  "Validate an input/layer token, never an arbitrary Kanata action fragment."
  (unless (and (stringp value) (%kanata-action-safe-token-p value))
    (%kanata-action-error :unsafe-kanata-action-token
                          "~A is not one closed Kanata token." label))
  (string-downcase value))

(defun %kanata-action-safe-token-p (value)
  "The closed atom vocabulary duplicated before KANATA's text emitter loads."
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

(defun %kanata-action-u16 (value label)
  (unless (and (integerp value) (<= 1 value #xffff))
    (%kanata-action-error :invalid-kanata-action-time
                          "~A must be a nonzero unsigned 16-bit integer." label))
  value)

(defun %kanata-action-proper-list (value label)
  (unless (listp value)
    (%kanata-action-error :invalid-kanata-action-list
                          "~A must be a proper list." label))
  value)

(defun %kanata-action-distinct (values key code label)
  (let ((seen (make-hash-table :test #'equal)))
    (dolist (value values)
      (let ((value-key (funcall key value)))
        (when (gethash value-key seen)
          (%kanata-action-error code "~A repeats ~S." label value-key))
        (setf (gethash value-key seen) t))))
  values)

(defclass kanata-action ()
  ((validated-p :initform nil :accessor %kanata-action-validated-p))
  (:documentation
   "Base class for a closed Kanata action AST; construct only through MAKERs."))

(defclass kanata-key-action (kanata-action)
  ((key :initarg :key :reader kanata-key-action-key)
   ;; The semantic key identity and realization-owned Kanata token are kept
   ;; distinct.  A later emitter must not infer one from the other.
   (token :initarg :token :reader kanata-key-action-token))
  (:documentation
   "One semantic named-key reference plus one validated realization-owned token."))

(defclass kanata-arbitrary-code-action (kanata-action)
  ((code :initarg :code :reader kanata-arbitrary-code-action-code))
  (:documentation "One typed Linux input-event carrier code."))

(defclass kanata-layer-while-held-action (kanata-action)
  ((axis :initarg :axis :reader kanata-layer-while-held-action-axis)
   (state :initarg :state :reader kanata-layer-while-held-action-state)
   (layer :initarg :layer :reader kanata-layer-while-held-action-layer)
   (token :initarg :token :reader kanata-layer-while-held-action-token))
  (:documentation
   "One explicit semantic axis/state allocation to a validated Kanata layer token."))

(defclass kanata-alias-ref-action (kanata-action)
  ((alias :initarg :alias :reader kanata-alias-ref-action-alias))
  (:documentation "One canonical reference to a separately allocated alias."))

(defclass kanata-modifier-hold-action (kanata-action)
  ((identity :initarg :identity :reader kanata-modifier-hold-action-identity)
   (state :initarg :state :initform nil :reader kanata-modifier-hold-action-state)
   (token :initarg :token :reader kanata-modifier-hold-action-token))
  (:documentation
   "One explicit semantic hold allocation to a validated Kanata modifier token."))

(defclass kanata-tap-hold-release-action (kanata-action)
  ((tap-time :initarg :tap-time :reader kanata-tap-hold-release-action-tap-time)
   (hold-time :initarg :hold-time :reader kanata-tap-hold-release-action-hold-time)
   (tap-action :initarg :tap-action :reader kanata-tap-hold-release-action-tap-action)
   (hold-action :initarg :hold-action :reader kanata-tap-hold-release-action-hold-action))
  (:documentation
   "One bounded release-triggered tap-hold shape with no nested hold-tap."))

(defclass kanata-owner-placement ()
  ((position :initarg :position :reader kanata-owner-placement-position)
   (input-token :initarg :input-token :reader kanata-owner-placement-input-token)
   (origin :initarg :origin :reader kanata-owner-placement-origin)
   (validated-p :initform nil :accessor %kanata-owner-placement-validated-p))
  (:documentation "One typed physical input placement for a buffered owner."))

(defclass kanata-direct-route-reference ()
  ((position :initarg :position :reader kanata-direct-route-reference-position)
   (input-token :initarg :input-token :reader kanata-direct-route-reference-input-token)
   (action :initarg :action :reader kanata-direct-route-reference-action)
   (origin :initarg :origin :reader kanata-direct-route-reference-origin)
   (validated-p :initform nil :accessor %kanata-direct-route-reference-validated-p))
  (:documentation
   "A direct ordinary named-key route that can be queued as a foreign input."))

(defclass kanata-defcfg-requirements ()
  ((process-unmapped-keys :initarg :process-unmapped-keys
                           :reader kanata-defcfg-requirements-process-unmapped-keys)
   (concurrent-tap-hold :initarg :concurrent-tap-hold
                        :reader kanata-defcfg-requirements-concurrent-tap-hold)
   (validated-p :initform nil :accessor %kanata-defcfg-requirements-validated-p))
  (:documentation
   "Typed DEFCFG prerequisites, never an arbitrary DEFCFG source fragment."))

(defclass kanata-buffered-interaction-action ()
  ((contract :initarg :contract :reader kanata-buffered-interaction-action-contract)
   (owner :initarg :owner :reader kanata-buffered-interaction-action-owner)
   (tap-hold :initarg :tap-hold :reader kanata-buffered-interaction-action-tap-hold)
   (foreign-routes :initarg :foreign-routes
                   :reader kanata-buffered-interaction-action-foreign-routes)
   (defcfg :initarg :defcfg :reader kanata-buffered-interaction-action-defcfg)
   (provenance :initarg :provenance
               :reader kanata-buffered-interaction-action-provenance)
   (validated-p :initform nil :accessor %kanata-buffered-interaction-action-validated-p))
  (:documentation
   "A typed, inspectable Kanata 1.12 buffered handoff which remains inert."))

(defun make-kanata-key-action (key token)
  (let ((action (make-instance 'kanata-key-action
                               :key (%kanata-action-identifier key "Key action key")
                               :token (%kanata-action-token token "Key action token"))))
    (setf (%kanata-action-validated-p action) t)
    action))

(defun make-kanata-arbitrary-code-action (code)
  (let ((action (make-instance 'kanata-arbitrary-code-action
                               :code (%kanata-action-u16 code "Arbitrary code"))))
    (setf (%kanata-action-validated-p action) t)
    action))

(defun make-kanata-layer-while-held-action (axis state layer token)
  (let ((action (make-instance 'kanata-layer-while-held-action
                               :axis (%kanata-action-identifier axis "Held layer axis")
                               :state (%kanata-action-identifier state "Held layer state")
                               :layer (%kanata-action-identifier layer "Held layer")
                               :token (%kanata-action-token token "Held layer token"))))
    (setf (%kanata-action-validated-p action) t)
    action))

(defun make-kanata-alias-ref-action (alias)
  (let ((action (make-instance 'kanata-alias-ref-action
                               :alias (%kanata-action-identifier alias "Alias reference"))))
    (setf (%kanata-action-validated-p action) t)
    action))

(defun make-kanata-modifier-hold-action (identity token &key state)
  (let ((action
          (make-instance 'kanata-modifier-hold-action
                         :identity (%kanata-action-identifier identity "Modifier hold identity")
                         :state (and state
                                     (%kanata-action-identifier state "Modifier hold state"))
                         :token (%kanata-action-token token "Modifier hold token"))))
    (setf (%kanata-action-validated-p action) t)
    action))

(defun %validate-kanata-action (action)
  (unless (and (typep action 'kanata-action)
               (%kanata-action-validated-p action))
    (%kanata-action-error :unvalidated-kanata-action
                          "Kanata action ~S was not built by a closed constructor." action))
  (typecase action
    (kanata-key-action
     (%kanata-action-identifier (kanata-key-action-key action) "Key action key")
     (%kanata-action-token (kanata-key-action-token action) "Key action token"))
    (kanata-arbitrary-code-action
     (%kanata-action-u16 (kanata-arbitrary-code-action-code action) "Arbitrary code"))
    (kanata-layer-while-held-action
     (%kanata-action-identifier (kanata-layer-while-held-action-axis action)
                                "Held layer axis")
     (%kanata-action-identifier (kanata-layer-while-held-action-state action)
                                "Held layer state")
     (%kanata-action-identifier (kanata-layer-while-held-action-layer action)
                                "Held layer")
     (%kanata-action-token (kanata-layer-while-held-action-token action)
                           "Held layer token"))
    (kanata-alias-ref-action
     (%kanata-action-identifier (kanata-alias-ref-action-alias action) "Alias reference"))
    (kanata-modifier-hold-action
     (%kanata-action-identifier (kanata-modifier-hold-action-identity action)
                                "Modifier hold identity")
     (let ((state (kanata-modifier-hold-action-state action)))
       (when state
         (%kanata-action-identifier state "Modifier hold state")))
     (%kanata-action-token (kanata-modifier-hold-action-token action)
                           "Modifier hold token"))
    (kanata-tap-hold-release-action
     (%kanata-action-u16 (kanata-tap-hold-release-action-tap-time action) "Tap time")
     (%kanata-action-u16 (kanata-tap-hold-release-action-hold-time action) "Hold time")
     (unless (= (kanata-tap-hold-release-action-tap-time action)
                (kanata-tap-hold-release-action-hold-time action))
       (%kanata-action-error :mismatched-kanata-tap-hold-time
                             "Tap-hold release action must have equal tap and hold times."))
     (%validate-kanata-action (kanata-tap-hold-release-action-tap-action action))
     (%validate-kanata-action (kanata-tap-hold-release-action-hold-action action))
     (unless (typep (kanata-tap-hold-release-action-tap-action action)
                    'kanata-key-action)
       (%kanata-action-error :invalid-kanata-tap-action
                             "Tap-hold release action requires a direct named-key tap."))
     (unless (typep (kanata-tap-hold-release-action-hold-action action)
                    '(or kanata-modifier-hold-action
                         kanata-layer-while-held-action))
       (%kanata-action-error :invalid-kanata-hold-action
                             "Tap-hold release action requires one modifier or layer hold."))))
  action)

(defun make-kanata-tap-hold-release-action (tap-time hold-time tap-action hold-action)
  (let ((action (make-instance 'kanata-tap-hold-release-action
                               :tap-time (%kanata-action-u16 tap-time "Tap time")
                               :hold-time (%kanata-action-u16 hold-time "Hold time")
                               :tap-action tap-action :hold-action hold-action)))
    (setf (%kanata-action-validated-p action) t)
    (%validate-kanata-action action)
    action))

(defun make-kanata-owner-placement (position input-token &key origin)
  (let ((placement
          (make-instance 'kanata-owner-placement
                         :position (%kanata-action-identifier position "Owner position")
                         :input-token (%kanata-action-token input-token "Owner input token")
                         :origin (%kanata-action-origin origin "Owner provenance"))))
    (setf (%kanata-owner-placement-validated-p placement) t)
    placement))

(defun %validate-kanata-owner-placement (placement)
  (unless (and (typep placement 'kanata-owner-placement)
               (%kanata-owner-placement-validated-p placement))
    (%kanata-action-error :unvalidated-kanata-owner-placement
                          "Owner placement was not built by a closed constructor."))
  (%kanata-action-identifier (kanata-owner-placement-position placement) "Owner position")
  (%kanata-action-token (kanata-owner-placement-input-token placement) "Owner input token")
  (%kanata-action-origin (kanata-owner-placement-origin placement) "Owner provenance")
  placement)

(defun make-kanata-direct-route-reference (position input-token action &key origin)
  (let ((route
          (make-instance 'kanata-direct-route-reference
                         :position (%kanata-action-identifier position "Direct route position")
                         :input-token (%kanata-action-token input-token "Direct route input token")
                         :action action
                         :origin (%kanata-action-origin origin "Direct route provenance"))))
    (setf (%kanata-direct-route-reference-validated-p route) t)
    (%validate-kanata-direct-route-reference route)
    route))

(defun %validate-kanata-direct-route-reference (route)
  (unless (and (typep route 'kanata-direct-route-reference)
               (%kanata-direct-route-reference-validated-p route))
    (%kanata-action-error :unvalidated-kanata-direct-route
                          "Direct route was not built by a closed constructor."))
  (%kanata-action-identifier (kanata-direct-route-reference-position route)
                             "Direct route position")
  (%kanata-action-token (kanata-direct-route-reference-input-token route)
                        "Direct route input token")
  (%kanata-action-origin (kanata-direct-route-reference-origin route)
                         "Direct route provenance")
  (%validate-kanata-action (kanata-direct-route-reference-action route))
  (unless (typep (kanata-direct-route-reference-action route) 'kanata-key-action)
    (%kanata-action-error :invalid-kanata-direct-route-action
                          "A buffered foreign route requires one direct named-key action."))
  route)

(defun make-kanata-defcfg-requirements (&key process-unmapped-keys concurrent-tap-hold)
  (unless (and (eq process-unmapped-keys t)
               (eq concurrent-tap-hold :required))
    (%kanata-action-error
     :invalid-kanata-defcfg-requirements
     "Buffered Kanata actions require explicit PROCESS-UNMAPPED-KEYS T and CONCURRENT-TAP-HOLD :REQUIRED."))
  (let ((requirements
          (make-instance 'kanata-defcfg-requirements
                         :process-unmapped-keys process-unmapped-keys
                         :concurrent-tap-hold concurrent-tap-hold)))
    (setf (%kanata-defcfg-requirements-validated-p requirements) t)
    requirements))

(defun %validate-kanata-defcfg-requirements (requirements)
  (unless (and (typep requirements 'kanata-defcfg-requirements)
               (%kanata-defcfg-requirements-validated-p requirements)
               (eq (kanata-defcfg-requirements-process-unmapped-keys requirements) t)
               (eq (kanata-defcfg-requirements-concurrent-tap-hold requirements)
                   :required))
    (%kanata-action-error :invalid-kanata-defcfg-requirements
                          "Buffered Kanata action has no closed DEFCFG requirements."))
  requirements)

(defun %same-kanata-held-signature-p (identity state signature)
  (and (typep identity 'ivory-key.model:identifier)
       (ivory-key.model:identifier=
        identity
        (ivory-key.model::interaction-compatibility-held-effect-signature-identity
         signature))
       (let ((expected
               (ivory-key.model::interaction-compatibility-held-effect-signature-state
                signature)))
         (if expected
             (and state
                  (typep state 'ivory-key.model:identifier)
                  (ivory-key.model:identifier= state expected))
             (null state)))))

(defun %validate-kanata-buffered-held-allocation (hold signature)
  "Require an explicit typed allocation; never infer one from a semantic hold."
  (let ((kind
          (ivory-key.model::interaction-compatibility-held-effect-signature-kind signature)))
    (cond
      ((and (eq kind :modifier)
            (typep hold 'kanata-modifier-hold-action)
            (%same-kanata-held-signature-p
             (kanata-modifier-hold-action-identity hold)
             (kanata-modifier-hold-action-state hold) signature))
       t)
      ((and (eq kind :axis-state)
            (typep hold 'kanata-modifier-hold-action)
            (%same-kanata-held-signature-p
             (kanata-modifier-hold-action-identity hold)
             (kanata-modifier-hold-action-state hold) signature))
       t)
      ((and (eq kind :axis-state)
            (typep hold 'kanata-layer-while-held-action)
            (%same-kanata-held-signature-p
             (kanata-layer-while-held-action-axis hold)
             (kanata-layer-while-held-action-state hold) signature))
       t)
      (t
       (%kanata-action-error :mismatched-kanata-buffered-hold
                             "Buffered action has no explicit allocation matching its held-effect signature.")))))

(defun %kanata-action-origin= (left right)
  (if left
      (and right (ivory-key.source:source-origin= left right))
      (null right)))

(defun %kanata-action-identifier= (left right)
  (and (typep left 'ivory-key.model:identifier)
       (typep right 'ivory-key.model:identifier)
       (ivory-key.model:identifier= left right)))

(defun %kanata-held-signature= (left right)
  (and (typep left 'ivory-key.model::interaction-compatibility-held-effect-signature)
       (typep right 'ivory-key.model::interaction-compatibility-held-effect-signature)
       (eq (ivory-key.model::interaction-compatibility-held-effect-signature-kind left)
           (ivory-key.model::interaction-compatibility-held-effect-signature-kind right))
       (%kanata-action-identifier=
        (ivory-key.model::interaction-compatibility-held-effect-signature-identity left)
        (ivory-key.model::interaction-compatibility-held-effect-signature-identity right))
       (let ((left-state
               (ivory-key.model::interaction-compatibility-held-effect-signature-state left))
             (right-state
               (ivory-key.model::interaction-compatibility-held-effect-signature-state right)))
         (if left-state
             (%kanata-action-identifier= left-state right-state)
             (null right-state)))
       (eq (ivory-key.model::interaction-compatibility-held-effect-signature-release left)
           (ivory-key.model::interaction-compatibility-held-effect-signature-release right))))

(defun %kanata-role-references= (left right)
  "Require the exact normalized candidates re-derived from the held interaction."
  (and (listp left) (listp right) (= (length left) (length right))
       (every
        (lambda (left-reference right-reference)
          (and (typep left-reference
                      'ivory-key.model::interaction-compatibility-role-reference)
               (typep right-reference
                      'ivory-key.model::interaction-compatibility-role-reference)
               (eq (ivory-key.model::interaction-compatibility-role-reference-role
                    left-reference)
                   (ivory-key.model::interaction-compatibility-role-reference-role
                    right-reference))
               ;; The source MODEL derivation retains the original normalized
               ;; candidate object.  A name/table projection cannot supply it.
               (eq (ivory-key.model::interaction-compatibility-role-reference-candidate
                    left-reference)
                   (ivory-key.model::interaction-compatibility-role-reference-candidate
                    right-reference))
               (%kanata-action-origin=
                (ivory-key.model::interaction-compatibility-role-reference-origin
                 left-reference)
                (ivory-key.model::interaction-compatibility-role-reference-origin
                 right-reference))))
        left right)))

(defun %kanata-contract-provenance= (left right)
  (and (typep left 'ivory-key.model::interaction-compatibility-contract-provenance)
       (typep right 'ivory-key.model::interaction-compatibility-contract-provenance)
       (%kanata-action-origin=
        (ivory-key.model::interaction-compatibility-provenance-interaction-origin left)
        (ivory-key.model::interaction-compatibility-provenance-interaction-origin right))
       (%kanata-action-origin=
        (ivory-key.model::interaction-compatibility-provenance-timeout-origin left)
        (ivory-key.model::interaction-compatibility-provenance-timeout-origin right))
       (%kanata-action-origin=
        (ivory-key.model::interaction-compatibility-provenance-foreign-release-origin left)
        (ivory-key.model::interaction-compatibility-provenance-foreign-release-origin right))
       (%kanata-action-origin=
        (ivory-key.model::interaction-compatibility-provenance-tap-origin left)
        (ivory-key.model::interaction-compatibility-provenance-tap-origin right))))

(defun %kanata-derived-buffered-contract= (supplied derived)
  "Compare all authority-bearing facts to MODEL's fresh structural derivation."
  (and (eq (ivory-key.model::interaction-compatibility-contract-mode supplied)
           :kanata-1-12-buffered)
       ;; Both values must point at the same normalized interaction object;
       ;; structural re-derivation then proves its candidates/effects/order.
       (eq (ivory-key.model::interaction-compatibility-contract-interaction supplied)
           (ivory-key.model::interaction-compatibility-contract-interaction derived))
       (%kanata-action-identifier=
        (ivory-key.model::interaction-compatibility-contract-owner supplied)
        (ivory-key.model::interaction-compatibility-contract-owner derived))
       (= (ivory-key.model::release-trigger-interaction-compatibility-contract-deadline supplied)
          (ivory-key.model::release-trigger-interaction-compatibility-contract-deadline derived))
       (%kanata-action-identifier=
        (ivory-key.model::release-trigger-interaction-compatibility-contract-capture-name supplied)
        (ivory-key.model::release-trigger-interaction-compatibility-contract-capture-name derived))
       (%kanata-action-identifier=
        (ivory-key.model::release-trigger-interaction-compatibility-contract-tap-key supplied)
        (ivory-key.model::release-trigger-interaction-compatibility-contract-tap-key derived))
       (%kanata-held-signature=
        (ivory-key.model::release-trigger-interaction-compatibility-contract-held-effect-signature supplied)
        (ivory-key.model::release-trigger-interaction-compatibility-contract-held-effect-signature derived))
       (%kanata-role-references=
        (ivory-key.model::release-trigger-interaction-compatibility-contract-role-references supplied)
        (ivory-key.model::release-trigger-interaction-compatibility-contract-role-references derived))
       (%kanata-action-origin=
        (ivory-key.model::interaction-compatibility-contract-origin supplied)
        (ivory-key.model::interaction-compatibility-contract-origin derived))
       (%kanata-contract-provenance=
        (ivory-key.model::release-trigger-interaction-compatibility-contract-provenance supplied)
        (ivory-key.model::release-trigger-interaction-compatibility-contract-provenance derived))))

(defun %validate-kanata-buffered-contract (contract)
  "Bind action authority to a fresh MODEL derivation of the exact interaction.

Public CLOS construction can project a ledger name/deadline into a pending
contract object.  It cannot supply the normalized candidate/role graph which
MODEL derives.  Re-deriving from the same interaction and requiring every
candidate reference/provenance record to agree keeps public action constructors
from minting buffered authority from a name/content projection.
"
  (unless (and (typep contract 'ivory-key.model:pending-foreign-interval-contract)
               (eq (ivory-key.model::interaction-compatibility-contract-mode contract)
                   :kanata-1-12-buffered))
    (%kanata-action-error :invalid-kanata-buffered-contract
                          "Buffered Kanata action requires a pending buffered MODEL contract."))
  (let ((interaction
          (ivory-key.model::interaction-compatibility-contract-interaction contract)))
    (unless (typep interaction 'ivory-key.model:normalized-interaction)
      (%kanata-action-error :invalid-kanata-buffered-contract
                            "Buffered Kanata contract has no normalized interaction."))
    (let ((derived
            (handler-case
                (ivory-key.model::%derive-release-trigger-contract
                 :kanata-1-12-buffered interaction)
              (ivory-key.model:semantic-error (condition)
                (%kanata-action-error
                 :unvalidated-kanata-buffered-contract
                 "Buffered Kanata contract is not reproducible from MODEL derivation: ~A"
                 (ivory-key.model:semantic-error-message condition))))))
      (unless (%kanata-derived-buffered-contract= contract derived)
        (%kanata-action-error
         :unvalidated-kanata-buffered-contract
         "Buffered Kanata contract does not retain MODEL's canonical candidate/role authority."))))
  contract)

(defun make-kanata-buffered-interaction-action
    (contract owner tap-hold foreign-routes defcfg &key provenance)
  "Build one inert buffered action only from a closed evidence contract.

The returned object deliberately has no raw Kanata action string or emitted
alias.  Its validation covers allocation collisions and every structural fact
which a later exact emitter would need to prove again.
"
  (let ((action
          (make-instance 'kanata-buffered-interaction-action
                         :contract contract :owner owner :tap-hold tap-hold
                         :foreign-routes (copy-list (%kanata-action-proper-list
                                                     foreign-routes "Foreign routes"))
                         :defcfg defcfg
                         :provenance (%kanata-action-origin provenance
                                                             "Buffered action provenance"))))
    (setf (%kanata-buffered-interaction-action-validated-p action) t)
    (validate-kanata-buffered-interaction-action action)
    action))

(defun validate-kanata-buffered-interaction-action (action)
  "Validate ACTION and return it, refusing forged, partial, or colliding ASTs."
  (unless (and (typep action 'kanata-buffered-interaction-action)
               (%kanata-buffered-interaction-action-validated-p action))
    (%kanata-action-error :unvalidated-kanata-buffered-action
                          "Buffered Kanata action was not built by a closed constructor."))
  (let* ((contract (kanata-buffered-interaction-action-contract action))
         (owner (kanata-buffered-interaction-action-owner action))
         (tap-hold (kanata-buffered-interaction-action-tap-hold action))
         (routes (kanata-buffered-interaction-action-foreign-routes action))
         (provenance (kanata-buffered-interaction-action-provenance action)))
    (%validate-kanata-buffered-contract contract)
    (%validate-kanata-owner-placement owner)
    (%validate-kanata-action tap-hold)
    (%validate-kanata-defcfg-requirements
     (kanata-buffered-interaction-action-defcfg action))
    (%kanata-action-origin provenance "Buffered action provenance")
    (unless (or (null provenance)
                (ivory-key.source:source-origin=
                 provenance
                 (ivory-key.model::interaction-compatibility-contract-origin contract)))
      (%kanata-action-error :mismatched-kanata-buffered-provenance
                            "Buffered action provenance differs from its contract provenance."))
    (unless (ivory-key.model:identifier=
             (kanata-owner-placement-position owner)
             (ivory-key.model::interaction-compatibility-contract-owner contract))
      (%kanata-action-error :mismatched-kanata-buffered-owner
                            "Buffered action owner does not match its contract."))
    (unless (= (kanata-tap-hold-release-action-tap-time tap-hold)
               (ivory-key.model::release-trigger-interaction-compatibility-contract-deadline
                contract))
      (%kanata-action-error :mismatched-kanata-buffered-deadline
                            "Buffered action tap-hold time does not match contract D."))
    (unless (ivory-key.model:identifier=
             (kanata-key-action-key
              (kanata-tap-hold-release-action-tap-action tap-hold))
             (ivory-key.model::release-trigger-interaction-compatibility-contract-tap-key
              contract))
      (%kanata-action-error :mismatched-kanata-buffered-tap
                            "Buffered action tap key does not match its contract."))
    (%validate-kanata-buffered-held-allocation
     (kanata-tap-hold-release-action-hold-action tap-hold)
     (ivory-key.model::release-trigger-interaction-compatibility-contract-held-effect-signature
      contract))
    (unless (and (consp routes)
                 (every (lambda (route)
                          (typep route 'kanata-direct-route-reference))
                        routes))
      (%kanata-action-error :missing-kanata-buffered-foreign-routes
                            "Buffered action requires one or more typed direct foreign routes."))
    (dolist (route routes)
      (%validate-kanata-direct-route-reference route))
    (%kanata-action-distinct routes
                             (lambda (route)
                               (ivory-key.model:identifier-name
                                (kanata-direct-route-reference-position route)))
                             :duplicate-kanata-buffered-route-position
                             "Buffered direct route position")
    (%kanata-action-distinct routes #'kanata-direct-route-reference-input-token
                             :duplicate-kanata-buffered-route-input
                             "Buffered direct route input")
    (when (or (some (lambda (route)
                      (ivory-key.model:identifier=
                       (kanata-direct-route-reference-position route)
                       (kanata-owner-placement-position owner)))
                    routes)
              (some (lambda (route)
                      (string= (kanata-direct-route-reference-input-token route)
                               (kanata-owner-placement-input-token owner)))
                    routes))
      (%kanata-action-error :kanata-buffered-owner-route-collision
                            "Buffered owner cannot also be a foreign route.")))
  action)

(defun kanata-action-canonical-data (action)
  "Return deterministic, printer-safe AST data after closed validation."
  (%validate-kanata-action action)
  (typecase action
    (kanata-key-action
     (list :key (ivory-key.model:identifier-name (kanata-key-action-key action))
           :token (kanata-key-action-token action)))
    (kanata-arbitrary-code-action
     (list :arbitrary-code (kanata-arbitrary-code-action-code action)))
    (kanata-layer-while-held-action
     (list :layer-while-held
           :axis (ivory-key.model:identifier-name
                  (kanata-layer-while-held-action-axis action))
           :state (ivory-key.model:identifier-name
                   (kanata-layer-while-held-action-state action))
           :layer (ivory-key.model:identifier-name
                   (kanata-layer-while-held-action-layer action))
           :token (kanata-layer-while-held-action-token action)))
    (kanata-alias-ref-action
     (list :alias-ref
           (ivory-key.model:identifier-name (kanata-alias-ref-action-alias action))))
    (kanata-modifier-hold-action
     (list :modifier-hold
           :identity (ivory-key.model:identifier-name
                      (kanata-modifier-hold-action-identity action))
           :state (let ((state (kanata-modifier-hold-action-state action)))
                    (and state (ivory-key.model:identifier-name state)))
           :token (kanata-modifier-hold-action-token action)))
    (kanata-tap-hold-release-action
     (list :tap-hold-release
           :tap-time (kanata-tap-hold-release-action-tap-time action)
           :hold-time (kanata-tap-hold-release-action-hold-time action)
           :tap (kanata-action-canonical-data
                 (kanata-tap-hold-release-action-tap-action action))
           :hold (kanata-action-canonical-data
                  (kanata-tap-hold-release-action-hold-action action))))))

(defun %kanata-action-origin-data (origin)
  ;; Source origins remain typed on the action.  The generic dump intentionally
  ;; exposes only known/unknown here: mapping a SOURCE-FILE identity to a
  ;; relocatable filename is BUILD-CONTRACT's responsibility, and this backend
  ;; must never serialize a host pathname or an object printer address.
  (if origin :known :unknown))

(defun kanata-buffered-interaction-action-canonical-data (action)
  "Return canonical inspection data for an inert buffered action handoff."
  (validate-kanata-buffered-interaction-action action)
  (let ((contract (kanata-buffered-interaction-action-contract action))
        (owner (kanata-buffered-interaction-action-owner action)))
    (list :interaction
          (ivory-key.model:identifier-name
           (ivory-key.model:normalized-interaction-name
            (ivory-key.model::interaction-compatibility-contract-interaction contract)))
          :owner
          (list :position (ivory-key.model:identifier-name
                           (kanata-owner-placement-position owner))
                :input (kanata-owner-placement-input-token owner)
                :provenance (%kanata-action-origin-data
                             (kanata-owner-placement-origin owner)))
          :tap-hold
          (kanata-action-canonical-data
           (kanata-buffered-interaction-action-tap-hold action))
          :foreign-routes
          (mapcar
           (lambda (route)
             (list :position
                   (ivory-key.model:identifier-name
                    (kanata-direct-route-reference-position route))
                   :input (kanata-direct-route-reference-input-token route)
                   :action (kanata-action-canonical-data
                            (kanata-direct-route-reference-action route))
                   :provenance (%kanata-action-origin-data
                                (kanata-direct-route-reference-origin route))))
           (sort (copy-list (kanata-buffered-interaction-action-foreign-routes action))
                 #'string< :key (lambda (route)
                                  (ivory-key.model:identifier-name
                                   (kanata-direct-route-reference-position route)))))
          :defcfg
          (list :process-unmapped-keys
                (kanata-defcfg-requirements-process-unmapped-keys
                 (kanata-buffered-interaction-action-defcfg action))
                :concurrent-tap-hold
                (kanata-defcfg-requirements-concurrent-tap-hold
                 (kanata-buffered-interaction-action-defcfg action)))
          :provenance (%kanata-action-origin-data
                       (kanata-buffered-interaction-action-provenance action)))))
