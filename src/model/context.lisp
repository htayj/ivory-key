;;;; SPDX-License-Identifier: GPL-3.0-or-later
;;;; Context axes, state tuples, and semantic modifier collections.

(in-package #:ivory-key.model)

(defparameter +axis-resolution-kinds+ '(:product :behavioral :patch)
  "The three normalization policies for context axes.")

(defclass context-axis ()
  ((name :initarg :name :reader axis-name)
   (states :initarg :states :reader axis-states)
   (default-state :initarg :default-state :reader axis-default-state)
   (resolution :initarg :resolution :reader axis-resolution)
   ;; Patch precedence is meaningful only for patch axes.  It remains a model
   ;; property rather than an accidental source-order convention.
   (precedence :initarg :precedence :initform 0 :reader axis-precedence)
   ;; NIL means the normal Cartesian product.  A list contains allowed tuples
   ;; expressed in this axis set's declaration order.
   (valid-tuples :initarg :valid-tuples :initform nil :reader axis-valid-tuples)
   (metadata :initarg :metadata :initform nil :reader axis-metadata)))

(defun make-context-axis (name states &key default-state (resolution :product)
                                       (precedence 0) valid-tuples metadata)
  "Create a typed, ordered context axis.

STATES preserve source declaration order; the first is the default unless
DEFAULT-STATE is supplied.  Validation performs cross-layout checks later."
  (let* ((canonical-states (copy-identifier-list states))
         (default (ensure-identifier (or default-state (first canonical-states)))))
    (unless (member resolution +axis-resolution-kinds+)
      (error "Unknown context-axis resolution style ~S." resolution))
    (unless (member default canonical-states :test #'identifier=)
      (error "The default state ~A is not a state of axis ~A."
             (identifier-name default) name))
    (make-instance 'context-axis
                   :name (ensure-identifier name)
                   :states canonical-states
                   :default-state default
                   :resolution resolution
                   :precedence precedence
                   :valid-tuples (when valid-tuples
                                   (mapcar #'copy-identifier-list valid-tuples))
                   :metadata metadata)))

(defun axis-state-p (axis state)
  "Whether STATE belongs to AXIS."
  (member (ensure-identifier state) (axis-states axis) :test #'identifier=))

(defun find-axis (name axes &key (errorp nil))
  "Find a context axis by name in AXES."
  (or (find (ensure-identifier name) axes :test #'identifier= :key #'axis-name)
      (when errorp
        (error "Unknown context axis ~A." (canonical-identifier-name name)))))

(defstruct (context-tuple
            (:constructor %make-context-tuple (pairs))
            (:copier nil))
  "An immutable-by-convention canonical axis/state association list.

PAIRS are sorted by axis identifier.  A tuple never encodes a state set in a
host integer, so finite layouts are limited only by available memory."
  (pairs nil :type list :read-only t))

(defun make-context-tuple (pairs)
  "Create a canonical context tuple from (AXIS . STATE) associations.

Pairs may use strings, symbols, or identifiers.  The tuple is intentionally
partial: a binding only needs to mention axes that it consults."
  (let ((normalized
          (mapcar (lambda (pair)
                    (unless (consp pair)
                      (error "A context tuple entry must be an (axis . state) pair: ~S" pair))
                    (cons (ensure-identifier (car pair))
                          (ensure-identifier (cdr pair))))
                  pairs)))
    (unless (unique-identifiers-p (mapcar #'car normalized))
      (error "A context tuple mentions an axis more than once: ~S" pairs))
    (%make-context-tuple (sort normalized #'identifier< :key #'car))))

(defun context-tuple-state (tuple axis &optional default)
  "Return TUPLE's state for AXIS, or DEFAULT when the tuple is partial."
  (let ((pair (lookup-identifier axis (context-tuple-pairs tuple))))
    (if pair (cdr pair) default)))

(defun context-tuple= (left right)
  "Structural equality over semantic identifier pairs."
  (let ((left-pairs (context-tuple-pairs left))
        (right-pairs (context-tuple-pairs right)))
    (and (= (length left-pairs) (length right-pairs))
         (every (lambda (left-pair right-pair)
                  (and (identifier= (car left-pair) (car right-pair))
                       (identifier= (cdr left-pair) (cdr right-pair))))
                left-pairs right-pairs))))

(defun context-tuple-key (tuple)
  "A deterministic printable key, useful only for canonical model maps."
  (with-output-to-string (stream)
    (loop for (axis . state) in (context-tuple-pairs tuple)
          for firstp = t then nil
          do (unless firstp (write-char #\; stream))
             (write-string (identifier-name axis) stream)
             (write-char #\= stream)
             (write-string (identifier-name state) stream))))

(defun product-axes (axes)
  "The product axes in declaration order."
  (remove :product axes :key #'axis-resolution :test-not #'eq))

(defun axes-cartesian-tuples (axes)
  "Enumerate AXES' tuples with the first declared axis varying fastest.

For CASE, SCRIPT, PLANE this yields plain/roman/base, shifted/roman/base,
plain/greek/base, ... exactly matching Ivory Key's level convention."
  (labels ((walk (remaining)
             (if (endp remaining)
                 (list nil)
                 (let ((axis (first remaining))
                       (tail-tuples (walk (rest remaining))))
                   (loop for tail in tail-tuples append
                     (loop for state in (axis-states axis)
                           collect (cons (cons (axis-name axis) state) tail)))))))
    (mapcar #'make-context-tuple (walk axes))))

(defun allowed-product-tuples (axes)
  "Return canonical tuples permitted by AXES' declared restricted products.

At present a restriction is permitted when exactly one of the participating
axes carries it; inconsistent multiple declarations are reported by semantic
validation.  Normalization remains deterministic either way."
  (let ((restrictions (remove-if-not #'axis-valid-tuples axes)))
    (if (endp restrictions)
        (axes-cartesian-tuples axes)
        (mapcar (lambda (states)
                  (unless (= (length states) (length axes))
                    (error "Restricted product tuple has ~D states for ~D axes."
                           (length states) (length axes)))
                  (make-context-tuple
                   (mapcar #'cons (mapcar #'axis-name axes) states)))
                (axis-valid-tuples (first restrictions))))))

(defclass semantic-modifier-set ()
  ((members :initarg :members :reader modifier-set-members)))

(defun make-semantic-modifier-set (members)
  "Create an unbounded canonical set of semantic modifier identifiers."
  (let ((canonical (copy-identifier-list members)))
    (unless (unique-identifiers-p canonical)
      (error "A semantic modifier set contains duplicate identifiers: ~S" members))
    (make-instance 'semantic-modifier-set
                   :members (sort canonical #'identifier<))))

(defun modifier-set-contains-p (modifier modifier-set)
  (identifier-member-p modifier (modifier-set-members modifier-set)))

(defun modifier-set= (left right)
  (equal (mapcar #'identifier-name (modifier-set-members left))
         (mapcar #'identifier-name (modifier-set-members right))))

(defun modifier-set-union (&rest sets)
  "Set union without imposing a representation-width ceiling."
  (make-semantic-modifier-set
   (loop for set in sets append (modifier-set-members set))))
