;;;; SPDX-License-Identifier: GPL-3.0-or-later

(in-package #:ivory-key.backend)

(defclass resource-pool ()
  ((name :initarg :name :reader resource-pool-name)
   (available
    :initarg :available
    :reader resource-pool-available)
   (reserved
    :initarg :reserved
    :initform nil
    :accessor resource-pool-reserved)
   (allocations
    :initform (make-hash-table :test #'equal)
    :reader resource-pool-allocations)))

(defun make-resource-pool (name available &key reserved)
  (let ((duplicates (remove-duplicates available :test #'equal)))
    (unless (= (length duplicates) (length available))
      (error "Resource pool ~A contains duplicate resources." name))
    (make-instance 'resource-pool
                   :name name
                   :available (copy-list available)
                   :reserved (copy-list reserved))))

(defun resource-used-p (pool resource)
  (or (member resource (resource-pool-reserved pool) :test #'equal)
      (loop for allocated being the hash-values
              of (resource-pool-allocations pool)
            thereis (equal allocated resource))))

(defun reserve-resource (pool resource)
  (unless (member resource (resource-pool-available pool) :test #'equal)
    (error "Resource ~S is not in pool ~A." resource (resource-pool-name pool)))
  (when (resource-used-p pool resource)
    (error "Resource ~S is already reserved or allocated in pool ~A."
           resource (resource-pool-name pool)))
  (push resource (resource-pool-reserved pool))
  resource)

(defun allocate-resource (pool semantic-name)
  (multiple-value-bind (existing present-p)
      (gethash semantic-name (resource-pool-allocations pool))
    (when present-p
      (return-from allocate-resource existing)))
  (let ((resource
          (find-if-not (lambda (candidate) (resource-used-p pool candidate))
                       (resource-pool-available pool))))
    (unless resource
      (error "Resource pool ~A is exhausted while allocating ~A."
             (resource-pool-name pool) semantic-name))
    (setf (gethash semantic-name (resource-pool-allocations pool)) resource)
    resource))

(defun allocation-alist (pool)
  (sort (loop for name being the hash-keys
                of (resource-pool-allocations pool)
              using (hash-value resource)
              collect (cons name resource))
        #'string< :key (lambda (entry) (string (car entry)))))
