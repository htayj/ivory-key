;;;; SPDX-License-Identifier: GPL-3.0-or-later
;;;; The aggregate abstract layout and context-latch state records.

(in-package #:ivory-key.model)

(defclass layout ()
  ((name :initarg :name :reader layout-name)
   (topology :initarg :topology :reader layout-topology)
   ;; Declaration order is semantic for product-level display/enumeration.
   (axes :initarg :axes :reader layout-axes)
   (modifiers :initarg :modifiers :reader layout-modifiers)
   (bindings :initarg :bindings :initform nil :reader layout-bindings)
   (overlays :initarg :overlays :initform nil :reader layout-overlays)
   (interactions :initarg :interactions :initform nil :reader layout-interactions)
   (behavior-templates :initarg :behavior-templates :initform nil
                       :reader layout-behavior-templates)
   (interaction-templates :initarg :interaction-templates :initform nil
                          :reader layout-interaction-templates)
   (metadata :initarg :metadata :initform nil :reader layout-metadata)
   (origin :initarg :origin :initform nil :reader layout-origin)))

(defun make-layout (name topology axes modifiers
                    &key bindings overlays interactions behavior-templates
                      interaction-templates metadata origin)
  "Create the target-neutral abstract definition of a keyboard layout."
  (make-instance 'layout :name (ensure-identifier name) :topology topology
                 :axes (copy-list axes)
                 :modifiers (if (typep modifiers 'semantic-modifier-set)
                                modifiers
                                (make-semantic-modifier-set modifiers))
                 :bindings (copy-list bindings) :overlays (copy-list overlays)
                 :interactions (copy-list interactions)
                 :behavior-templates (copy-list behavior-templates)
                 :interaction-templates (copy-list interaction-templates)
                 :metadata metadata :origin origin))

(defun layout-axis (layout name &key (errorp nil))
  (find-axis name (layout-axes layout) :errorp errorp))

(defun layout-binding (layout position &key (errorp nil))
  (or (find (ensure-identifier position) (layout-bindings layout)
            :test #'identifier= :key #'binding-position)
      (when errorp
        (error "Layout ~A has no binding for position ~A."
               (identifier-name (layout-name layout))
               (canonical-identifier-name position)))))

(defun layout-behavior-template (layout name &key (errorp nil))
  (or (find (ensure-identifier name) (layout-behavior-templates layout)
            :test #'identifier= :key #'behavior-template-name)
      (when errorp
        (error "Unknown behavior template ~A." (canonical-identifier-name name)))))

(defun layout-interaction-template (layout name &key (errorp nil))
  (or (find (ensure-identifier name) (layout-interaction-templates layout)
            :test #'identifier= :key #'interaction-template-name)
      (when errorp
        (error "Unknown interaction template ~A." (canonical-identifier-name name)))))

(defun layout-product-axes (layout)
  (product-axes (layout-axes layout)))

(defun binding-axis-dependencies (binding)
  "The exact context axes that can affect BINDING."
  (behavior-axis-dependencies (binding-behavior binding)))

(defclass context-latch ()
  ((axis :initarg :axis :reader context-latch-axis)
   (state :initarg :state :reader context-latch-state)))

(defun make-context-latch (axis state)
  (make-instance 'context-latch :axis (ensure-identifier axis)
                 :state (ensure-identifier state)))

(defclass semantic-context ()
  ((values :initarg :values :reader semantic-context-values)
   ;; Latches are ordered by commitment time.  Their consumption rule depends
   ;; only on declared candidate dependencies, never on the next raw key event.
   (latches :initarg :latches :initform nil :reader semantic-context-latches)
   (locked-axes :initarg :locked-axes :initform nil :reader semantic-context-locked-axes)))

(defun make-semantic-context (axes &key values latches locked-axes)
  "Create a context snapshot, filling omitted values with each axis default."
  (let ((specified (if (typep values 'context-tuple) values
                       (make-context-tuple values))))
    (make-instance 'semantic-context
                   :values (make-context-tuple
                            (loop for axis in axes
                                  collect (cons (axis-name axis)
                                                (or (context-tuple-state specified (axis-name axis))
                                                    (axis-default-state axis)))))
                   :latches (copy-list latches)
                   :locked-axes (canonical-identifier-set locked-axes))))

(defun semantic-context-state (context axis &optional default)
  (context-tuple-state (semantic-context-values context) axis default))

(defun consume-context-latches (context consulted-axes)
  "Return two values: a new context and the latches consumed by a commitment.

Only an interaction interpretation that *commits* calls this operation.  Its
CONSULTED-AXES are dependency-scoped, which is the essential `shift-latch`
rule: a key that does not consult shift-latch leaves it intact."
  (let ((consulted (canonical-identifier-set consulted-axes))
        (remaining nil)
        (consumed nil))
    (dolist (latch (semantic-context-latches context))
      (if (identifier-member-p (context-latch-axis latch) consulted)
          (push latch consumed)
          (push latch remaining)))
    (values (make-instance 'semantic-context
                           :values (semantic-context-values context)
                           :latches (nreverse remaining)
                           :locked-axes (semantic-context-locked-axes context))
            (nreverse consumed))))

(defun context-with-latch (context axis state)
  "Return a context with AXIS/STATE latched for the next consulting commitment."
  (make-instance 'semantic-context
                 :values (semantic-context-values context)
                 :latches (append (semantic-context-latches context)
                                  (list (make-context-latch axis state)))
                 :locked-axes (semantic-context-locked-axes context)))
