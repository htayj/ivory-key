;;;; SPDX-License-Identifier: GPL-3.0-or-later
;;;; Backend-neutral output behaviors, binding tables, patches, and templates.

(in-package #:ivory-key.model)

(defclass behavior () ()
  (:documentation "The abstract superclass of every complete keyboard behavior."))

(defgeneric behavior-axis-dependencies (behavior)
  (:documentation "Return context axes whose values select BEHAVIOR."))

(defmethod behavior-axis-dependencies ((behavior behavior))
  (declare (ignore behavior))
  nil)

(defgeneric behavior-children (behavior)
  (:documentation "Return directly nested behavior objects, in source order."))

(defmethod behavior-children ((behavior behavior))
  (declare (ignore behavior))
  nil)

(defclass text-output (behavior)
  ((text :initarg :text :reader output-text)))

(defun make-text-output (text)
  "Emit TEXT at commitment.  TEXT may contain one Unicode scalar or short text."
  (check-type text string)
  (make-instance 'text-output :text text))

(defclass named-key-output (behavior)
  ((name :initarg :name :reader named-key-name)))

(defun make-named-key-output (name)
  "Emit an abstract named key, never a backend keysym or input code."
  (make-instance 'named-key-output :name (ensure-identifier name)))

(defclass named-symbol-output (behavior)
  ((name :initarg :name :reader named-symbol-name)))

(defun make-named-symbol-output (name)
  "Emit a documented abstract non-Unicode symbol identity."
  (make-instance 'named-symbol-output :name (ensure-identifier name)))

(defclass command-output (behavior)
  ((name :initarg :name :reader command-name)))

(defun make-command-output (name)
  "Emit an abstract semantic command such as STOP-OUTPUT."
  (make-instance 'command-output :name (ensure-identifier name)))

(defclass no-output-behavior (behavior) ())

(defparameter +no-output+ (make-instance 'no-output-behavior)
  "The unique explicit no-output behavior.  Missing is never implicitly none.")

(defun make-no-output-behavior () +no-output+)

(defclass modifier-operation-behavior (behavior)
  ((operation :initarg :operation :reader modifier-operation)
   (modifier :initarg :modifier :reader modifier-operation-modifier)))

(defun make-modifier-operation (operation modifier)
  "Make a semantic modifier press/release operation.

OPERATION is one of :PRESS, :RELEASE, or :TOGGLE.  Held lifetime is specified
by an interaction effect lifecycle rather than encoded in this object."
  (unless (member operation '(:press :release :toggle))
    (error "Unknown semantic modifier operation ~S." operation))
  (make-instance 'modifier-operation-behavior :operation operation
                 :modifier (ensure-identifier modifier)))

(defclass held-modifier-behavior (modifier-operation-behavior) ()
  (:documentation
   "The source-level HOLD-MODIFIER behavior.

Its effect owner and release boundary are supplied by a containing :WHILE
lifecycle effect.  It is distinct from a raw modifier-operation-behavior so
validation can refuse a source hold placed where no exact release exists."))

(defun make-held-modifier-operation (modifier)
  "Make the source-level semantic hold for MODIFIER.

This constructor is intentionally internal until the public model API adopts a
separate lifecycle builder.  The decoder and resolver preserve the subtype."
  (make-instance 'held-modifier-behavior :operation :press
                 :modifier (ensure-identifier modifier)))

(defclass axis-operation-behavior (behavior)
  ((operation :initarg :operation :reader axis-operation)
   (axis :initarg :axis :reader axis-operation-axis)
   (state :initarg :state :initform nil :reader axis-operation-state)))

(defun make-axis-operation (operation axis &optional state)
  "Make a semantic context-axis operation.

Operations are :HOLD, :LATCH, :LOCK, :UNLOCK, :SET, :TOGGLE, and :CYCLE.
The activation mode is intentionally distinct from the state spelling."
  (unless (member operation '(:hold :latch :lock :unlock :set :toggle :cycle))
    (error "Unknown axis operation ~S." operation))
  (make-instance 'axis-operation-behavior :operation operation
                 :axis (ensure-identifier axis)
                 :state (and state (ensure-identifier state))))

(defclass ordered-behavior (behavior)
  ((behaviors :initarg :behaviors :reader ordered-behaviors)))

(defun make-sequence-behavior (behaviors)
  "Emit or apply BEHAVIORS in the declared order."
  (make-instance 'ordered-behavior :behaviors (copy-list behaviors)))

(defmethod behavior-children ((behavior ordered-behavior))
  (ordered-behaviors behavior))

(defclass simultaneous-behavior (behavior)
  ((behaviors :initarg :behaviors :reader simultaneous-behaviors)))

(defun make-simultaneous-behavior (behaviors)
  "Apply a finite set of behaviors simultaneously."
  (make-instance 'simultaneous-behavior :behaviors (copy-list behaviors)))

(defmethod behavior-children ((behavior simultaneous-behavior))
  (simultaneous-behaviors behavior))

(defclass axis-choice-behavior (behavior)
  ((axis :initarg :axis :reader choice-axis)
   ;; Ordered state/behavior pairs; behavioral state selection never adds an
   ;; unrelated product dimension to ordinary symbol bindings.
   (choices :initarg :choices :reader choice-behaviors)))

(defun make-axis-choice-behavior (axis choices)
  "Choose a complete behavior from STATE -> BEHAVIOR CHOICES."
  (make-instance 'axis-choice-behavior
                 :axis (ensure-identifier axis)
                 :choices (mapcar (lambda (choice)
                                    (cons (ensure-identifier (car choice)) (cdr choice)))
                                  choices)))

(defmethod behavior-axis-dependencies ((behavior axis-choice-behavior))
  (canonical-identifier-set
   (cons (choice-axis behavior)
         (loop for pair in (choice-behaviors behavior)
               append (behavior-axis-dependencies (cdr pair))))))

(defmethod behavior-children ((behavior axis-choice-behavior))
  (mapcar #'cdr (choice-behaviors behavior)))

;;; Context tables -----------------------------------------------------------

(defclass behavior-entry ()
  ((tuple :initarg :tuple :reader behavior-entry-tuple)
   (disposition :initarg :disposition :reader behavior-entry-disposition)
   (behavior :initarg :behavior :initform nil :reader behavior-entry-behavior)
   (inherit-tuple :initarg :inherit-tuple :initform nil
                  :reader behavior-entry-inherit-tuple)))

(defun make-behavior-entry (tuple behavior)
  "A table entry with an explicit behavior (including +NO-OUTPUT+)."
  (make-instance 'behavior-entry :tuple (if (typep tuple 'context-tuple)
                                             tuple
                                             (make-context-tuple tuple))
                 :disposition :behavior :behavior behavior))

(defun make-none-entry (tuple)
  (make-instance 'behavior-entry :tuple (if (typep tuple 'context-tuple)
                                             tuple
                                             (make-context-tuple tuple))
                 :disposition :none :behavior +no-output+))

(defun make-transparent-entry (tuple)
  "An explicit patch-table fall-through entry.  Base tables reject it."
  (make-instance 'behavior-entry :tuple (if (typep tuple 'context-tuple)
                                             tuple
                                             (make-context-tuple tuple))
                 :disposition :transparent))

(defun make-inherit-entry (tuple source-tuple)
  "An explicit table inheritance edge from TUPLE to SOURCE-TUPLE."
  (make-instance 'behavior-entry
                 :tuple (if (typep tuple 'context-tuple) tuple
                            (make-context-tuple tuple))
                 :disposition :inherit
                 :inherit-tuple (if (typep source-tuple 'context-tuple) source-tuple
                                    (make-context-tuple source-tuple))))

(defclass behavior-table (behavior)
  ((axes :initarg :axes :reader behavior-table-axes)
   (entries :initarg :entries :reader behavior-table-entries)
   ;; Explicitly chosen source tuples make non-Cartesian products possible.
   (allowed-tuples :initarg :allowed-tuples :initform nil
                   :reader behavior-table-allowed-tuples)))

(defun make-behavior-table (axes entries &key allowed-tuples)
  "Make a dependency-scoped context table.

Only AXES participate in expansion; adding a behavioral axis elsewhere in a
layout therefore does not alter this table's cardinality."
  (make-instance 'behavior-table :axes (copy-identifier-list axes)
                 :entries (copy-list entries)
                 :allowed-tuples (when allowed-tuples
                                   (mapcar (lambda (tuple)
                                             (if (typep tuple 'context-tuple) tuple
                                                 (make-context-tuple tuple)))
                                           allowed-tuples))))

(defmethod behavior-axis-dependencies ((behavior behavior-table))
  (canonical-identifier-set
   (append (behavior-table-axes behavior)
           (loop for entry in (behavior-table-entries behavior)
                 for child = (behavior-entry-behavior entry)
                 when child append (behavior-axis-dependencies child)))))

(defmethod behavior-children ((behavior behavior-table))
  (loop for entry in (behavior-table-entries behavior)
        for child = (behavior-entry-behavior entry)
        when child collect child))

(defun find-behavior-entry (tuple table)
  (find tuple (behavior-table-entries table) :test #'context-tuple=
        :key #'behavior-entry-tuple))

;;; Named finite templates ---------------------------------------------------

(defclass behavior-template ()
  ((name :initarg :name :reader behavior-template-name)
   (parameters :initarg :parameters :reader behavior-template-parameters)
   (body :initarg :body :reader behavior-template-body)))

(defun make-behavior-template (name parameters body)
  "Create a declarative, non-evaluating behavior template."
  (make-instance 'behavior-template :name (ensure-identifier name)
                 :parameters (copy-identifier-list parameters) :body body))

(defclass behavior-template-parameter (behavior)
  ((name :initarg :name :reader behavior-parameter-name)))

(defun make-behavior-template-parameter (name)
  (make-instance 'behavior-template-parameter :name (ensure-identifier name)))

(defclass behavior-template-reference (behavior)
  ((name :initarg :name :reader behavior-reference-name)
   (arguments :initarg :arguments :reader behavior-reference-arguments)))

(defun make-behavior-template-reference (name arguments)
  (make-instance 'behavior-template-reference :name (ensure-identifier name)
                 :arguments (copy-list arguments)))

(defmethod behavior-children ((behavior behavior-template-reference))
  (behavior-reference-arguments behavior))

(defclass binding ()
  ((position :initarg :position :reader binding-position)
   (behavior :initarg :behavior :reader binding-behavior)
   (metadata :initarg :metadata :initform nil :reader binding-metadata)))

(defun make-binding (position behavior &key metadata)
  "Bind a complete behavior to a logical position."
  (make-instance 'binding :position (ensure-identifier position)
                 :behavior behavior :metadata metadata))

;;; Sparse overlay patches ---------------------------------------------------

(defclass patch-binding ()
  ((position :initarg :position :reader patch-binding-position)
   ;; A transparent behavior is represented by the :TRANSPARENT disposition,
   ;; not by an absent patch entry.
   (disposition :initarg :disposition :reader patch-binding-disposition)
   (behavior :initarg :behavior :initform nil :reader patch-binding-behavior)))

(defun make-patch-binding (position behavior)
  (make-instance 'patch-binding :position (ensure-identifier position)
                 :disposition :behavior :behavior behavior))

(defun make-transparent-patch-binding (position)
  (make-instance 'patch-binding :position (ensure-identifier position)
                 :disposition :transparent))

(defclass overlay-patch ()
  ((name :initarg :name :reader overlay-patch-name)
   (axis :initarg :axis :reader overlay-patch-axis)
   (state :initarg :state :reader overlay-patch-state)
   (precedence :initarg :precedence :initform nil :reader overlay-patch-precedence)
   (bindings :initarg :bindings :reader overlay-patch-bindings)))

(defun make-overlay-patch (name axis state bindings &key precedence)
  "Create a sparse patch activated by a patch-axis state."
  (make-instance 'overlay-patch :name (ensure-identifier name)
                 :axis (ensure-identifier axis) :state (ensure-identifier state)
                 :precedence precedence :bindings (copy-list bindings)))

(defun complete-behavior-p (behavior)
  "Whether BEHAVIOR is a complete, executable semantic behavior.

Table inheritance and transparency are intentionally entries rather than
behaviors, so a candidate or binding can never accidentally carry a missing
branch."
  (and (typep behavior 'behavior)
       (not (typep behavior 'behavior-template-parameter))
       (not (typep behavior 'behavior-template-reference))
       (every #'complete-behavior-p (behavior-children behavior))))

(defun behavior-irreversible-p (behavior)
  "Whether BEHAVIOR can produce application-visible irreversible output."
  (or (typep behavior '(or text-output named-key-output named-symbol-output
                         command-output))
      (some #'behavior-irreversible-p (behavior-children behavior))))
