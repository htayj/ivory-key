;;;; SPDX-License-Identifier: GPL-3.0-or-later
;;;; Identifier and small canonical-collection utilities.

(in-package #:ivory-key.model)

(define-condition semantic-error (error)
  ((message :initarg :message :reader semantic-error-message)
   (code :initarg :code :initform :semantic-error :reader semantic-error-code)
   (object :initarg :object :initform nil :reader semantic-error-object))
  (:report (lambda (condition stream)
             (format stream "~A" (semantic-error-message condition)))))

(define-condition semantic-resolution-error (semantic-error) ())
(define-condition semantic-validation-error (semantic-error) ())
(define-condition semantic-normalization-error (semantic-error) ())

(defun signal-semantic-error (class code control &rest arguments)
  "Signal a structured model diagnostic without depending on host debugger use."
  (error class :code code :message (apply #'format nil control arguments)))

(defstruct (identifier
            (:constructor %make-identifier (name))
            (:copier nil))
  "A source-language identifier.

The source language deliberately has no relationship to Common Lisp symbols:
identifiers are retained as strings and are never INTERNed.  NAME is stored in
canonical case so it is safe to use as a deterministic map key."
  (name "" :type string :read-only t))

(defun canonical-identifier-name (value)
  "Return VALUE's canonical source-language identifier spelling.

The v1 grammar is case-insensitive.  Keeping this rule here, rather than at
every lookup site, also prevents accidental package/symbol dependence."
  (let ((name (etypecase value
                (identifier (identifier-name value))
                (string value)
                (symbol (symbol-name value)))))
    (when (zerop (length name))
      (error "An Ivory Key identifier must not be empty."))
    (string-downcase name)))

(defun make-identifier (value)
  "Construct an identifier from a string, symbol, or identifier.

Symbols are accepted only as a convenience for programmatic construction; no
symbol is ever placed in the model."
  (if (typep value 'identifier)
      value
      (%make-identifier (canonical-identifier-name value))))

(defun ensure-identifier (value)
  "Coerce VALUE to an IDENTIFIER, signaling on an invalid value."
  (make-identifier value))

(defun identifier= (left right)
  "Whether LEFT and RIGHT denote the same source-language identifier."
  (string= (canonical-identifier-name left)
           (canonical-identifier-name right)))

(defun identifier< (left right)
  "The canonical total ordering used for unordered semantic collections."
  (string< (canonical-identifier-name left)
           (canonical-identifier-name right)))

(defun identifier-key (value)
  "A string map key for VALUE."
  (canonical-identifier-name value))

(defun copy-identifier-list (identifiers)
  "Return a fresh list of canonical identifiers, preserving declaration order."
  (mapcar #'ensure-identifier identifiers))

(defun unique-identifiers-p (identifiers)
  "Whether IDENTIFIERS has no duplicate names."
  (let ((seen (make-hash-table :test #'equal)))
    (loop for identifier in identifiers
          for key = (identifier-key identifier)
          always (prog1 (not (gethash key seen))
                   (setf (gethash key seen) t)))))

(defun canonical-identifier-set (identifiers)
  "Canonicalize an unordered identifier collection.

Unlike a backend modifier mask this is an ordinary, unbounded list.  It is
used for semantic modifiers and for deterministic IR serialization."
  (let ((seen (make-hash-table :test #'equal))
        (result nil))
    (dolist (identifier identifiers)
      (let* ((canonical (ensure-identifier identifier))
             (key (identifier-key canonical)))
        (unless (gethash key seen)
          (setf (gethash key seen) t)
          (push canonical result))))
    (sort result #'identifier<)))

(defun identifier-member-p (identifier identifiers)
  "Membership predicate which accepts either strings or IDENTIFIER values."
  (member (ensure-identifier identifier) identifiers :test #'identifier=))

(defun lookup-identifier (identifier associations &key (key #'car))
  "Find IDENTIFIER in an association sequence by source-language identity."
  (find (ensure-identifier identifier) associations
        :test #'identifier=
        :key key))
