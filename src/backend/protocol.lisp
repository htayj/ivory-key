;;;; SPDX-License-Identifier: GPL-3.0-or-later

(in-package #:ivory-key.backend)

(defparameter +fidelity-grades+ '(:exact :emulated :lossy :unsupported))

(defclass backend ()
  ((name :initarg :name :reader backend-name)))

(defclass backend-capabilities ()
  ((native-level-limit
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
   (interaction-features
    :initarg :interaction-features
    :initform nil
    :reader capability-interaction-features)
   (output-features
    :initarg :output-features
    :initform nil
    :reader capability-output-features)
   (validation-program
    :initarg :validation-program
    :initform nil
    :reader capability-validation-program)))

(defclass realization-result ()
  ((feature :initarg :feature :reader realization-feature)
   (grade :initarg :grade :reader realization-grade)
   (detail :initarg :detail :initform "" :reader realization-detail)
   (source :initarg :source :initform nil :reader realization-source)))

(defclass key-entry ()
  ((position :initarg :position :reader key-entry-position)
   ;; A string is accepted for a single-backend request. A property list such
   ;; as (:xkb "AD01" :kanata "a") keeps physical naming in the realization.
   (physical-code :initarg :physical-code :reader key-entry-physical-code)
   (outputs :initarg :outputs :reader key-entry-outputs)))

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
            (:interaction
             (capability-interaction-features capabilities))
            (:output
             (capability-output-features capabilities)))
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
