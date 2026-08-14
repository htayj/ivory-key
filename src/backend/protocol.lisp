;;;; SPDX-License-Identifier: GPL-3.0-or-later

(in-package #:ivory-key.backend)

(defparameter +fidelity-grades+ '(:exact :emulated :lossy :unsupported))

(defclass backend ()
  ((name :initarg :name :reader backend-name)))

(defclass backend-capabilities ()
  ((input-identities
    :initarg :input-identities
    :initform nil
    :reader capability-input-identities)
   (native-level-limit
    :initarg :native-level-limit
    :initform nil
    :reader capability-native-level-limit)
   (native-group-limit
    :initarg :native-group-limit
    :initform nil
    :reader capability-native-group-limit)
   (modifier-slots
    :initarg :modifier-slots
    :initform nil
    :reader capability-modifier-slots)
   (virtual-modifier-resources
    :initarg :virtual-modifier-resources
    :initform nil
    :reader capability-virtual-modifier-resources)
   (context-axis-operations
    :initarg :context-axis-operations
    :initform nil
    :reader capability-context-axis-operations)
   (resolution-styles
    :initarg :resolution-styles
    :initform nil
    :reader capability-resolution-styles)
   (patch-operations
    :initarg :patch-operations
    :initform nil
    :reader capability-patch-operations)
   (interaction-features
    :initarg :interaction-features
    :initform nil
    :reader capability-interaction-features)
   (clock-semantics
    :initarg :clock-semantics
    :initform nil
    :reader capability-clock-semantics)
   (lifecycle-semantics
    :initarg :lifecycle-semantics
    :initform nil
    :reader capability-lifecycle-semantics)
   (arbitration-semantics
    :initarg :arbitration-semantics
    :initform nil
    :reader capability-arbitration-semantics)
   (output-features
    :initarg :output-features
    :initform nil
    :reader capability-output-features)
   (carrier-channels
    :initarg :carrier-channels
    :initform nil
    :reader capability-carrier-channels)
   (validation-program
    :initarg :validation-program
    :initform nil
    :reader capability-validation-program)
   (platform-assumptions
    :initarg :platform-assumptions
    :initform nil
    :reader capability-platform-assumptions)))

(defclass realization-result ()
  ((feature :initarg :feature :reader realization-feature)
   (grade :initarg :grade :reader realization-grade)
   (detail :initarg :detail :initform "" :reader realization-detail)
   (source :initarg :source :initform nil :reader realization-source)))

(defclass key-entry-source ()
  ((context :initarg :context :initform nil :reader key-entry-source-context)
   ;; ORIGIN is the typed semantic provenance of one normalized table entry.
   ;; It intentionally remains target-neutral: the build-contract layer is
   ;; the only place which maps its parser source name to a relocatable build
   ;; input identity.
   (origin :initarg :origin :initform nil :reader key-entry-source-origin)))

(defun make-key-entry-source (context &key origin)
  "Record the canonical normalized CONTEXT and optional semantic ORIGIN.

The order of these records on a KEY-ENTRY is normalized-entry order.  A NIL
ORIGIN is meaningful: it records a programmatic source-free entry rather than
asking a backend or report writer to invent a source location.
"
  (unless (or (null origin)
              (typep origin 'ivory-key.source:source-origin))
    (error "KEY-ENTRY source origin must be a SOURCE:SOURCE-ORIGIN or NIL, got ~S."
           origin))
  (make-instance 'key-entry-source :context context :origin origin))

(defclass key-entry ()
  ((position :initarg :position :reader key-entry-position)
   ;; A string is accepted for a single-backend request. A property list such
   ;; as (:xkb "AD01" :kanata "a") keeps physical naming in the realization.
   (physical-code :initarg :physical-code :reader key-entry-physical-code)
   (outputs :initarg :outputs :reader key-entry-outputs)
   ;; One record per normalized direct mapping.  Backends do not inspect
   ;; provenance; retaining it here prevents the lowering request from
   ;; severing the model-to-contract traceability chain.
   (sources :initarg :sources :initform nil :reader key-entry-sources)))

(defun key-entry-code-for (entry backend-key)
  (let ((code (key-entry-physical-code entry)))
    (if (stringp code)
        code
        (or (getf code backend-key)
            (error "No ~A physical code for position ~A."
                   backend-key (key-entry-position entry))))))

(defun key-entry-outputs-for (entry backend-key)
  (let ((outputs (key-entry-outputs entry)))
    (if (or (null outputs) (stringp (first outputs)))
        outputs
        (or (getf outputs backend-key)
            (error "No ~A outputs for position ~A."
                   backend-key (key-entry-position entry))))))

(defclass lowering-request ()
  ((name :initarg :name :reader lowering-request-name)
   (entries :initarg :entries :initform nil :reader lowering-request-entries)
   (modifiers :initarg :modifiers :initform nil :reader lowering-request-modifiers)
   (interactions
    :initarg :interactions :initform nil :reader lowering-request-interactions)
   (metadata :initarg :metadata :initform nil :reader lowering-request-metadata)))

(defgeneric capabilities (backend)
  (:documentation "Return the structured capabilities advertised by BACKEND."))

(defgeneric lower-request (backend request)
  (:documentation "Lower a backend-neutral REQUEST into a backend plan."))

(defgeneric emit-plan (backend plan stream)
  (:documentation "Emit PLAN deterministically to STREAM."))

(defgeneric validate-artifact (backend pathname)
  (:documentation "Return success, output, and an argument-vector description."))

(defun make-realization-result (feature grade &key (detail "") source)
  (unless (member grade +fidelity-grades+)
    (error "Unknown fidelity grade ~S." grade))
  (make-instance 'realization-result
                 :feature feature :grade grade :detail detail :source source))

(defun capability-supports-p (capabilities category feature)
  (member feature
          (ecase category
            (:input
             (capability-input-identities capabilities))
            (:interaction
             (capability-interaction-features capabilities))
            (:output
             (capability-output-features capabilities))
            (:virtual-modifier
             (capability-virtual-modifier-resources capabilities))
            (:context-axis-operation
             (capability-context-axis-operations capabilities))
            (:resolution
             (capability-resolution-styles capabilities))
            (:patch
             (capability-patch-operations capabilities))
            (:clock
             (capability-clock-semantics capabilities))
            (:lifecycle
             (capability-lifecycle-semantics capabilities))
            (:arbitration
             (capability-arbitration-semantics capabilities))
            (:carrier
             (capability-carrier-channels capabilities))
            (:platform
             (capability-platform-assumptions capabilities)))
          :test #'equal))

(defun emit-plan-to-string (backend plan)
  (with-output-to-string (stream)
    (emit-plan backend plan stream)))

(defun require-permitted-realizations (results &key allow-lossy)
  (dolist (result results results)
    (case (realization-grade result)
      (:unsupported
       (error "Unsupported realization for ~A: ~A"
              (realization-feature result)
              (realization-detail result)))
      (:lossy
       (unless allow-lossy
         (error "Lossy realization for ~A requires explicit permission: ~A"
                (realization-feature result)
                (realization-detail result)))))))
