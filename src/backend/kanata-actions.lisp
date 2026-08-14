;;;; SPDX-License-Identifier: GPL-3.0-or-later
;;;; Closed, inert Kanata 1.12 buffered-interaction action handoff.

(in-package #:ivory-key.backend)

;;; This file is intentionally an action *description*, rather than an
;;; emitter extension.  The known Kanata 1.12 probe proves the bounded
;;; deadline-custody and selected multi-owner edge-order paths, but not
;;; cancellation or closure of the emitted configuration's wider input domain.
;;; Therefore a valid value below is useful for deterministic inspection and
;;; future review, but does not constitute a permitted backend realization.

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

(defun %kanata-action-alias-token (value label)
  "Validate a definition-position alias independently of input key tokens."
  (unless (and (stringp value)
               (plusp (length value))
               (let ((first (char value 0)))
                 (or (alpha-char-p first) (char= first #\_)))
               (every (lambda (character)
                        (or (alphanumericp character)
                            (find character "_-")))
                      value))
    (%kanata-action-error :unsafe-kanata-buffered-alias
                          "~A is not one closed Kanata alias identifier." label))
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

(defclass kanata-axis-carrier-hold-action (kanata-action)
  ((axis :initarg :axis :reader kanata-axis-carrier-hold-action-axis)
   (state :initarg :state :reader kanata-axis-carrier-hold-action-state)
   (code :initarg :code :reader kanata-axis-carrier-hold-action-code))
  (:documentation
   "One explicit semantic axis/state hold allocated to an evidenced carrier code."))

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
   ;; The realization allocation supplies the alias token.  It must never be
   ;; derived from the semantic interaction identity.
   (alias :initarg :alias :reader kanata-buffered-interaction-action-alias)
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

(defun make-kanata-axis-carrier-hold-action (axis state code)
  (unless (member code '(84 85))
    (%kanata-action-error :unsupported-kanata-axis-carrier
                          "Axis carrier code ~S is outside the evidenced 84/85 allocation."
                          code))
  (let ((action
          (make-instance 'kanata-axis-carrier-hold-action
                         :axis (%kanata-action-identifier axis "Carrier hold axis")
                         :state (%kanata-action-identifier state "Carrier hold state")
                         :code (%kanata-action-u16 code "Carrier hold code"))))
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
  (let* ((token (%kanata-action-alias-token alias "Alias reference"))
         (action (make-instance 'kanata-alias-ref-action
                                :alias (%kanata-action-identifier token "Alias reference"))))
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
    (kanata-axis-carrier-hold-action
     (%kanata-action-identifier (kanata-axis-carrier-hold-action-axis action)
                                "Carrier hold axis")
     (%kanata-action-identifier (kanata-axis-carrier-hold-action-state action)
                                "Carrier hold state")
     (unless (member (kanata-axis-carrier-hold-action-code action) '(84 85))
       (%kanata-action-error :unsupported-kanata-axis-carrier
                             "Axis carrier code is outside the evidenced 84/85 allocation.")))
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
     (%kanata-action-alias-token
      (ivory-key.model:identifier-name (kanata-alias-ref-action-alias action))
      "Alias reference"))
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
                         kanata-axis-carrier-hold-action
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
            (typep hold 'kanata-axis-carrier-hold-action)
            (%same-kanata-held-signature-p
             (kanata-axis-carrier-hold-action-axis hold)
             (kanata-axis-carrier-hold-action-state hold) signature))
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
    (contract alias owner tap-hold foreign-routes defcfg &key provenance)
  "Build one inert buffered action only from a closed evidence contract.

The returned object deliberately has no raw Kanata action string or emitted
alias.  Its validation covers allocation collisions and every structural fact
which a later exact emitter would need to prove again.
"
  (let ((action
          (make-instance 'kanata-buffered-interaction-action
                         :contract contract
                         :alias (%kanata-action-alias-token alias "Buffered action alias")
                         :owner owner :tap-hold tap-hold
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
         (alias (kanata-buffered-interaction-action-alias action))
         (owner (kanata-buffered-interaction-action-owner action))
         (tap-hold (kanata-buffered-interaction-action-tap-hold action))
         (routes (kanata-buffered-interaction-action-foreign-routes action))
         (provenance (kanata-buffered-interaction-action-provenance action)))
    (%validate-kanata-buffered-contract contract)
    (%kanata-action-alias-token alias "Buffered action alias")
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
    (kanata-axis-carrier-hold-action
     (list :axis-carrier-hold
           :axis (ivory-key.model:identifier-name
                  (kanata-axis-carrier-hold-action-axis action))
           :state (ivory-key.model:identifier-name
                   (kanata-axis-carrier-hold-action-state action))
           :code (kanata-axis-carrier-hold-action-code action)))
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
          :alias (kanata-buffered-interaction-action-alias action)
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

;;; Closed buffered configuration proposal ---------------------------------

;; This is deliberately a typed proposal AST, not a text configuration.  The
;; emitter below remains behind the normal unsupported-realization gate; these
;; values exist so a complete synthetic allocation can be reviewed without
;; giving a native Kanata domain any authority it has not proved.
(defclass kanata-buffered-layer-cell ()
  ((position :initarg :position :reader kanata-buffered-layer-cell-position)
   (input-token :initarg :input-token :reader kanata-buffered-layer-cell-input-token)
   (action :initarg :action :reader kanata-buffered-layer-cell-action)))

(defclass kanata-buffered-config ()
  ((defcfg :initarg :defcfg :reader kanata-buffered-config-defcfg)
   ;; Each member is a validated KANATA-BUFFERED-INTERACTION-ACTION whose
   ;; explicit alias token names the emitted alias definition.
   (aliases :initarg :aliases :reader kanata-buffered-config-aliases)
   ;; Only owner aliases and realization-owned direct named-key routes occur
   ;; here.  The ordinary plan supplies every other base layer cell.
   (layer-cells :initarg :layer-cells :reader kanata-buffered-config-layer-cells)
   (validated-p :initform nil :accessor %kanata-buffered-config-validated-p)))

(defun %kanata-buffered-action< (left right)
  (string< (kanata-buffered-interaction-action-alias left)
           (kanata-buffered-interaction-action-alias right)))

(defun %kanata-buffered-layer-cell< (left right)
  (ivory-key.model:identifier<
   (kanata-buffered-layer-cell-position left)
   (kanata-buffered-layer-cell-position right)))

(defun %kanata-buffered-source-row (row)
  "Return canonical POSITION and INPUT from one compiler-owned source row."
  (unless (and (consp row) (stringp (car row)) (stringp (cdr row)))
    (%kanata-action-error :invalid-kanata-buffered-source-row
                          "Buffered configuration source rows must be (position . token) pairs."))
  (values (%kanata-action-identifier (car row) "Buffered source position")
          (%kanata-action-token (cdr row) "Buffered source input token")))

(defun %kanata-buffered-source-table (source-rows)
  (unless (listp source-rows)
    (%kanata-action-error :invalid-kanata-buffered-source-row
                          "Buffered configuration source rows must be a proper list."))
  (let ((by-position (make-hash-table :test #'equal))
        (by-input (make-hash-table :test #'equal)))
    (dolist (row source-rows)
      (multiple-value-bind (position input) (%kanata-buffered-source-row row)
        (let ((name (ivory-key.model:identifier-name position)))
          (when (or (gethash name by-position) (gethash input by-input))
            (%kanata-action-error :duplicate-kanata-buffered-source-row
                                  "Buffered configuration source rows repeat ~A or ~A."
                                  name input))
          (setf (gethash name by-position) input
                (gethash input by-input) name))))
    (values by-position by-input)))

(defun %make-kanata-buffered-layer-cell (position input-token action)
  (unless (typep action '(or kanata-key-action kanata-alias-ref-action))
    (%kanata-action-error :invalid-kanata-buffered-layer-cell
                          "Buffered layer cells may contain only direct keys or alias references."))
  (%validate-kanata-action action)
  (make-instance 'kanata-buffered-layer-cell
                 :position (%kanata-action-identifier position "Buffered cell position")
                 :input-token (%kanata-action-token input-token "Buffered cell input token")
                 :action action))

(defun %validate-kanata-buffered-layer-cell (cell)
  (unless (typep cell 'kanata-buffered-layer-cell)
    (%kanata-action-error :invalid-kanata-buffered-layer-cell
                          "Buffered configuration layer cell is not typed."))
  (%kanata-action-identifier (kanata-buffered-layer-cell-position cell)
                             "Buffered cell position")
  (%kanata-action-token (kanata-buffered-layer-cell-input-token cell)
                        "Buffered cell input token")
  (%validate-kanata-action (kanata-buffered-layer-cell-action cell))
  cell)

(defun make-kanata-buffered-config (actions source-rows)
  "Build a complete typed alias/defcfg/layer-cell proposal from ACTIONS.

Every alias is explicit in its realization allocation; every owner and direct
foreign route must be present exactly once in compiler-owned SOURCE-ROWS.  The
result is non-emitting until the independent native-domain proof gate clears.
"
  (unless (and (listp actions) (consp actions))
    (%kanata-action-error :empty-kanata-buffered-config
                          "Buffered configuration requires one or more actions."))
  (dolist (action actions) (validate-kanata-buffered-interaction-action action))
  (%kanata-action-distinct actions #'kanata-buffered-interaction-action-alias
                           :duplicate-kanata-buffered-config-alias
                           "Buffered configuration alias")
  (multiple-value-bind (source-by-position ignored-source-by-input)
      (%kanata-buffered-source-table source-rows)
    (declare (ignore ignored-source-by-input))
    (let* ((ordered-actions (sort (copy-list actions) #'%kanata-buffered-action<))
           (defcfg (kanata-buffered-interaction-action-defcfg (first ordered-actions)))
           (cells nil)
           (cell-positions (make-hash-table :test #'equal)))
      (%validate-kanata-defcfg-requirements defcfg)
      (labels ((source-input-for (position role)
                 (let ((input (gethash (ivory-key.model:identifier-name position)
                                       source-by-position)))
                   (unless input
                     (%kanata-action-error :missing-kanata-buffered-source-position
                                           "Buffered ~A position ~A is absent from the source domain."
                                           role (ivory-key.model:identifier-name position)))
                   input))
               (add-cell (position input action)
                 (let ((name (ivory-key.model:identifier-name position)))
                   (when (gethash name cell-positions)
                     (%kanata-action-error :duplicate-kanata-buffered-layer-cell
                                           "Buffered configuration has conflicting cells for ~A." name))
                   (setf (gethash name cell-positions) t)
                   (push (%make-kanata-buffered-layer-cell position input action) cells))))
        (dolist (action ordered-actions)
          (unless (and (eq (kanata-defcfg-requirements-process-unmapped-keys
                            (kanata-buffered-interaction-action-defcfg action)) t)
                       (eq (kanata-defcfg-requirements-concurrent-tap-hold
                            (kanata-buffered-interaction-action-defcfg action)) :required))
            (%kanata-action-error :conflicting-kanata-buffered-defcfg
                                  "Buffered actions do not share the closed DEFCFG requirements."))
          (let* ((owner (kanata-buffered-interaction-action-owner action))
                 (position (kanata-owner-placement-position owner))
                 (input (source-input-for position "owner")))
            (unless (string= input (kanata-owner-placement-input-token owner))
              (%kanata-action-error :mismatched-kanata-buffered-owner-source
                                    "Buffered owner source token differs from its typed placement."))
            (add-cell position input
                      (make-kanata-alias-ref-action
                       (kanata-buffered-interaction-action-alias action))))
          (dolist (route (kanata-buffered-interaction-action-foreign-routes action))
            (let* ((position (kanata-direct-route-reference-position route))
                   (input (source-input-for position "foreign route")))
              (unless (string= input (kanata-direct-route-reference-input-token route))
                (%kanata-action-error :mismatched-kanata-buffered-route-source
                                      "Buffered foreign route source token differs from its typed placement."))
              ;; The global realization route may intentionally be used by
              ;; several interactions.  It yields one identical layer cell.
              (let ((existing (gethash (ivory-key.model:identifier-name position)
                                       cell-positions)))
                (if existing
                    (unless (and (typep existing 'kanata-key-action)
                                 (equal (kanata-action-canonical-data existing)
                                        (kanata-action-canonical-data
                                         (kanata-direct-route-reference-action route))))
                      (%kanata-action-error :conflicting-kanata-buffered-foreign-route
                                            "Buffered foreign routes disagree at one physical position."))
                    (let ((key-action (kanata-direct-route-reference-action route)))
                      (setf (gethash (ivory-key.model:identifier-name position)
                                     cell-positions) key-action)
                      (push (%make-kanata-buffered-layer-cell position input key-action)
                            cells))))))))
      ;; Replace marker T values by their key actions for the shared-route case.
      (setf cells
            (sort cells #'%kanata-buffered-layer-cell<))
      (let ((config (make-instance 'kanata-buffered-config
                                   :defcfg defcfg :aliases ordered-actions
                                   :layer-cells cells)))
        (setf (%kanata-buffered-config-validated-p config) t)
        (validate-kanata-buffered-config config)
        config))))

(defun validate-kanata-buffered-config (config)
  "Validate an inspection-only buffered configuration proposal."
  (unless (and (typep config 'kanata-buffered-config)
               (%kanata-buffered-config-validated-p config))
    (%kanata-action-error :unvalidated-kanata-buffered-config
                          "Buffered Kanata configuration was not built by its closed constructor."))
  (%validate-kanata-defcfg-requirements (kanata-buffered-config-defcfg config))
  (unless (consp (kanata-buffered-config-aliases config))
    (%kanata-action-error :empty-kanata-buffered-config
                          "Buffered configuration requires one or more aliases."))
  (dolist (action (kanata-buffered-config-aliases config))
    (validate-kanata-buffered-interaction-action action))
  (%kanata-action-distinct (kanata-buffered-config-aliases config)
                           #'kanata-buffered-interaction-action-alias
                           :duplicate-kanata-buffered-config-alias
                           "Buffered configuration alias")
  (unless (equal (kanata-buffered-config-aliases config)
                 (sort (copy-list (kanata-buffered-config-aliases config))
                       #'%kanata-buffered-action<))
    (%kanata-action-error :noncanonical-kanata-buffered-config-alias-order
                          "Buffered configuration aliases must be canonical."))
  (dolist (cell (kanata-buffered-config-layer-cells config))
    (%validate-kanata-buffered-layer-cell cell))
  (%kanata-action-distinct (kanata-buffered-config-layer-cells config)
                           (lambda (cell)
                             (ivory-key.model:identifier-name
                              (kanata-buffered-layer-cell-position cell)))
                           :duplicate-kanata-buffered-layer-cell
                           "Buffered configuration layer cell")
  (unless (equal (kanata-buffered-config-layer-cells config)
                 (sort (copy-list (kanata-buffered-config-layer-cells config))
                       #'%kanata-buffered-layer-cell<))
    (%kanata-action-error :noncanonical-kanata-buffered-config-layer-order
                          "Buffered configuration layer cells must be canonical."))
  config)

(defun kanata-buffered-config-canonical-data (config)
  "Return deterministic, non-pathname inspection data for CONFIG."
  (validate-kanata-buffered-config config)
  (list :defcfg (list :process-unmapped-keys t :concurrent-tap-hold :required)
        :aliases (mapcar #'kanata-buffered-interaction-action-canonical-data
                         (kanata-buffered-config-aliases config))
        :layer-cells
        (mapcar (lambda (cell)
                  (list :position
                        (ivory-key.model:identifier-name
                         (kanata-buffered-layer-cell-position cell))
                        :input (kanata-buffered-layer-cell-input-token cell)
                        :action (kanata-action-canonical-data
                                 (kanata-buffered-layer-cell-action cell))))
                (kanata-buffered-config-layer-cells config))))

(defun kanata-action-emission-string (action)
  "Render one already-validated closed action AST; never parse raw action text."
  (%validate-kanata-action action)
  (typecase action
    (kanata-key-action (kanata-key-action-token action))
    (kanata-arbitrary-code-action
     (format nil "(arbitrary-code ~D)" (kanata-arbitrary-code-action-code action)))
    (kanata-axis-carrier-hold-action
     (format nil "(arbitrary-code ~D)" (kanata-axis-carrier-hold-action-code action)))
    (kanata-modifier-hold-action (kanata-modifier-hold-action-token action))
    (kanata-layer-while-held-action
     (format nil "(layer-while-held ~A)"
             (kanata-layer-while-held-action-token action)))
    (kanata-alias-ref-action
     (format nil "@~A" (ivory-key.model:identifier-name
                         (kanata-alias-ref-action-alias action))))
    (kanata-tap-hold-release-action
     (format nil "(tap-hold-release ~D ~D ~A ~A)"
             (kanata-tap-hold-release-action-tap-time action)
             (kanata-tap-hold-release-action-hold-time action)
             (kanata-action-emission-string
              (kanata-tap-hold-release-action-tap-action action))
             (kanata-action-emission-string
              (kanata-tap-hold-release-action-hold-action action))))))
