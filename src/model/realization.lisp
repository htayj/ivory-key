;;;; SPDX-License-Identifier: GPL-3.0-or-later
;;;; Realization-profile declarations.  No backend spelling enters this model.

(in-package #:ivory-key.model)

(defclass realization-profile ()
  ((name :initarg :name :reader realization-profile-name)
   ;; Ordered opaque backend identities, e.g. (:kanata :xkb).  Their concrete
   ;; protocols live outside the semantic model.
   (pipeline :initarg :pipeline :initform nil :reader realization-profile-pipeline)
   (placement :initarg :placement :initform nil :reader realization-profile-placement)
   ;; Abstract named-key/command/symbol mappings may be declared here, but
   ;; target vocabulary is validated only by the backend planner.
   (vocabulary :initarg :vocabulary :initform nil :reader realization-profile-vocabulary)
   (permitted-losses :initarg :permitted-losses :initform nil
                     :reader realization-profile-permitted-losses)
   (metadata :initarg :metadata :initform nil :reader realization-profile-metadata)))

(defun make-realization-profile (name &key pipeline placement vocabulary
                                      permitted-losses metadata)
  "Create a profile describing permitted lowering policy, not keyboard meaning."
  (make-instance 'realization-profile :name (ensure-identifier name)
                 :pipeline (copy-list pipeline) :placement placement
                 :vocabulary vocabulary :permitted-losses (copy-list permitted-losses)
                 :metadata metadata))
