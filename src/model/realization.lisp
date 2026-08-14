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

(defun make-realization-profile (name &key pipeline placement vocabulary
                                      permitted-losses metadata)
  "Create a profile describing permitted lowering policy, not keyboard meaning.

When VOCABULARY is supplied, each of its backend identities must be selected
by PIPELINE.  The profile retains pipeline order and opaque spellings without
interpreting either as a backend grammar.
"
  (let ((pipeline-identifiers (%realization-pipeline-identifiers pipeline)))
    (%validate-realization-vocabulary pipeline-identifiers vocabulary))
  (make-instance 'realization-profile :name (ensure-identifier name)
                 :pipeline (copy-list pipeline) :placement placement
                 :vocabulary vocabulary :permitted-losses (copy-list permitted-losses)
                 :metadata metadata))
