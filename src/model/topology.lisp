;;;; SPDX-License-Identifier: GPL-3.0-or-later
;;;; Logical keyboard topology and deliberately non-semantic placement data.

(in-package #:ivory-key.model)

(defclass logical-position ()
  ((name :initarg :name :reader position-name)
   (label :initarg :label :initform nil :reader position-label)
   (coordinates :initarg :coordinates :initform nil :reader position-coordinates)
   (hand :initarg :hand :initform nil :reader position-hand)
   (finger :initarg :finger :initform nil :reader position-finger)
   (metadata :initarg :metadata :initform nil :reader position-metadata)))

(defun make-logical-position (name &key label coordinates hand finger metadata)
  "Create a topology position.  Geometry is descriptive only."
  (make-instance 'logical-position :name (ensure-identifier name)
                 :label label :coordinates coordinates :hand hand
                 :finger finger :metadata metadata))

(defclass topology ()
  ((name :initarg :name :reader topology-name)
   (positions :initarg :positions :reader topology-positions)
   (metadata :initarg :metadata :initform nil :reader topology-metadata)))

(defun make-topology (name positions &key metadata)
  (make-instance 'topology :name (ensure-identifier name)
                 :positions (copy-list positions) :metadata metadata))

(defun find-position (name topology &key (errorp nil))
  "Find NAME as a logical position in TOPOLOGY."
  (or (find (ensure-identifier name) (topology-positions topology)
            :test #'identifier= :key #'position-name)
      (when errorp
        (error "Unknown logical position ~A in topology ~A."
               (canonical-identifier-name name)
               (identifier-name (topology-name topology))))))

(defclass device-placement ()
  ((name :initarg :name :reader placement-name)
   (topology :initarg :topology :reader placement-topology)
   ;; Association list of physical input identities to logical positions.  The
   ;; physical side is opaque to the semantic model.
   (mappings :initarg :mappings :reader placement-mappings)
   (metadata :initarg :metadata :initform nil :reader placement-metadata)))

(defun make-device-placement (name topology mappings &key metadata)
  "Create a descriptive physical-device placement.

Physical inputs deliberately remain strings; realizing them as evdev or
firmware codes belongs to a selected realization profile."
  (make-instance 'device-placement :name (ensure-identifier name)
                 :topology topology
                 :mappings (mapcar (lambda (entry)
                                     (cons (car entry) (ensure-identifier (cdr entry))))
                                   mappings)
                 :metadata metadata))
