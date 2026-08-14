;;;; SPDX-License-Identifier: GPL-3.0-or-later
;;;; Canonical target-neutral IR normalization.

(in-package #:ivory-key.model)

(defclass normalized-binding-entry ()
  ((tuple :initarg :tuple :reader normalized-entry-tuple)
   (behavior :initarg :behavior :reader normalized-entry-behavior)))

(defun make-normalized-binding-entry (tuple behavior)
  (make-instance 'normalized-binding-entry :tuple tuple :behavior behavior))

(defclass normalized-binding ()
  ((position :initarg :position :reader normalized-binding-position)
   ;; Context axes in LAYOUT declaration order, limited to actual dependencies.
   (axes :initarg :axes :reader normalized-binding-axes)
   (entries :initarg :entries :reader normalized-binding-entries)))

(defclass normalized-patch ()
  ((name :initarg :name :reader normalized-patch-name)
   (axis :initarg :axis :reader normalized-patch-axis)
   (state :initarg :state :reader normalized-patch-state)
   (precedence :initarg :precedence :reader normalized-patch-precedence)
   (bindings :initarg :bindings :reader normalized-patch-bindings)))

(defclass normalized-interaction-candidate ()
  ((name :initarg :name :reader normalized-candidate-name)
   (match :initarg :match :reader normalized-candidate-match)
   (commit :initarg :commit :reader normalized-candidate-commit)
   ;; Canonical variants of its complete commit-time behavior.
   (entries :initarg :entries :reader normalized-candidate-entries)
   (effects :initarg :effects :reader normalized-candidate-effects)
   (context-axes :initarg :context-axes :reader normalized-candidate-context-axes)
   (context-policy :initarg :context-policy :reader normalized-candidate-context-policy)))

(defclass normalized-interaction ()
  ((name :initarg :name :reader normalized-interaction-name)
   (participants :initarg :participants :reader normalized-interaction-participants)
   (observe :initarg :observe :reader normalized-interaction-observe)
   (anchor :initarg :anchor :reader normalized-interaction-anchor)
   (candidates :initarg :candidates :reader normalized-interaction-candidates)
   (arbitration :initarg :arbitration :reader normalized-interaction-arbitration)))

(defclass normalized-layout ()
  ((name :initarg :name :reader normalized-layout-name)
   (topology :initarg :topology :reader normalized-layout-topology)
   (axes :initarg :axes :reader normalized-layout-axes)
   (modifiers :initarg :modifiers :reader normalized-layout-modifiers)
   (bindings :initarg :bindings :reader normalized-layout-bindings)
   (patches :initarg :patches :reader normalized-layout-patches)
   (interactions :initarg :interactions :reader normalized-layout-interactions)))

(defun %normalization-error (code control &rest arguments)
  (apply #'signal-semantic-error 'semantic-normalization-error code control arguments))

(defun %tuple-merge (left right)
  "Merge two partial tuples, rejecting contradictory axis selections."
  (let ((pairs (copy-list (context-tuple-pairs left))))
    (dolist (pair (context-tuple-pairs right))
      (let ((old (assoc (car pair) pairs :test #'identifier=)))
        (cond ((null old) (push pair pairs))
              ((not (identifier= (cdr old) (cdr pair)))
               (%normalization-error :conflicting-context-selection
                                     "A behavior selects both ~A and ~A for axis ~A."
                                     (identifier-name (cdr old))
                                     (identifier-name (cdr pair))
                                     (identifier-name (car pair)))))))
    (make-context-tuple pairs)))

(defun %variant-product (variant-lists constructor)
  "Cartesian-compose behavior variants from component VARIANT-LISTS."
  (labels ((walk (remaining tuple children)
             (if (endp remaining)
                 (list (cons tuple (funcall constructor (nreverse children))))
                 (loop for variant in (first remaining) append
                   (walk (rest remaining)
                         (%tuple-merge tuple (car variant))
                         (cons (cdr variant) children))))))
    (walk variant-lists (make-context-tuple nil) nil)))

(defun %resolved-table-entry-behavior (entry table &optional seen)
  (let ((key (context-tuple-key (behavior-entry-tuple entry))))
    (when (member key seen :test #'string=)
      (%normalization-error :inheritance-cycle
                            "Behavior-table inheritance cycles at ~A." key))
    (case (behavior-entry-disposition entry)
      (:behavior (behavior-entry-behavior entry))
      (:none +no-output+)
      (:inherit (let ((source (find-behavior-entry (behavior-entry-inherit-tuple entry) table)))
                  (unless source
                    (%normalization-error :unknown-inheritance-source
                                          "No behavior-table entry exists for inherited tuple ~A."
                                          (context-tuple-key (behavior-entry-inherit-tuple entry))))
                  (%resolved-table-entry-behavior source table (cons key seen))))
      (:transparent (%normalization-error :transparent-base-entry
                                          "Transparency has no behavior to normalize in a base table.")))))

(defun %layout-axis-order-for (layout dependencies)
  (let ((dependency-keys (mapcar #'identifier-key dependencies)))
    (loop for axis in (layout-axes layout)
          when (member (identifier-key (axis-name axis)) dependency-keys :test #'string=)
            collect (axis-name axis))))

(defun %state-rank (axis state)
  (or (position (ensure-identifier state) (axis-states axis) :test #'identifier=)
      most-positive-fixnum))

(defun %tuple< (left right axes)
  "Canonical product order: the first declared dependency varies fastest."
  ;; Lexicographic comparison from the *last* axis yields first-axis-fastest.
  (loop for axis in (reverse axes)
        for left-state = (context-tuple-state left (axis-name axis)
                                              (axis-default-state axis))
        for right-state = (context-tuple-state right (axis-name axis)
                                               (axis-default-state axis))
        for left-rank = (%state-rank axis left-state)
        for right-rank = (%state-rank axis right-state)
        when (/= left-rank right-rank) do (return (< left-rank right-rank))
        finally (return nil)))

(defun %sort-variants (variants layout dependencies)
  (let ((axes (mapcar (lambda (name) (layout-axis layout name))
                      (%layout-axis-order-for layout dependencies))))
    (sort (copy-list variants)
          (lambda (left right) (%tuple< (car left) (car right) axes)))))

(defun %behavior-variants (behavior layout)
  "Return (TUPLE . COMPLETE-BEHAVIOR) variants of BEHAVIOR.

This is the central dependency-scoped expansion: only tables and behavioral
choices recursively introduce coordinates.  Ordinary symbols never acquire a
state just because some unrelated axis exists in the layout."
  (cond
    ((typep behavior 'behavior-table)
     (let ((axes (mapcar (lambda (name) (layout-axis layout name :errorp t))
                         (behavior-table-axes behavior)))
           (result nil))
       (dolist (tuple (or (behavior-table-allowed-tuples behavior)
                          (allowed-product-tuples axes)))
         (let ((entry (find-behavior-entry tuple behavior)))
           (unless entry
             (%normalization-error :incomplete-level-table
                                   "No table entry exists for context ~A."
                                   (context-tuple-key tuple)))
           (dolist (variant (%behavior-variants
                             (%resolved-table-entry-behavior entry behavior) layout))
             (push (cons (%tuple-merge tuple (car variant)) (cdr variant)) result))))
       (nreverse result)))
    ((typep behavior 'axis-choice-behavior)
     (let ((result nil) (axis (choice-axis behavior)))
       (dolist (choice (choice-behaviors behavior))
         (let ((selection (make-context-tuple (list (cons axis (car choice))))) )
           (dolist (variant (%behavior-variants (cdr choice) layout))
             (push (cons (%tuple-merge selection (car variant)) (cdr variant)) result))))
       (nreverse result)))
    ((typep behavior 'ordered-behavior)
     (%variant-product
      (mapcar (lambda (child) (%behavior-variants child layout))
              (ordered-behaviors behavior))
      #'make-sequence-behavior))
    ((typep behavior 'simultaneous-behavior)
     (%variant-product
      (mapcar (lambda (child) (%behavior-variants child layout))
              (simultaneous-behaviors behavior))
      #'make-simultaneous-behavior))
    ((complete-behavior-p behavior)
     (list (cons (make-context-tuple nil) behavior)))
    (t (%normalization-error :incomplete-behavior
                             "Cannot normalize incomplete behavior ~S." behavior))))

(defun %normalize-binding (binding layout)
  (let* ((variants (%behavior-variants (binding-behavior binding) layout))
         (dependencies (canonical-identifier-set
                        (mapcan (lambda (variant)
                                  (mapcar #'car (context-tuple-pairs (car variant))))
                                variants)))
         (ordered-dependencies (%layout-axis-order-for layout dependencies)))
    (make-instance 'normalized-binding
                   :position (binding-position binding)
                   :axes ordered-dependencies
                   :entries
                   (mapcar (lambda (variant)
                             (make-normalized-binding-entry (car variant) (cdr variant)))
                           (%sort-variants variants layout ordered-dependencies)))))

(defun %normalize-patch (patch layout)
  (make-instance 'normalized-patch
                 :name (overlay-patch-name patch)
                 :axis (overlay-patch-axis patch)
                 :state (overlay-patch-state patch)
                 :precedence (%overlay-precedence patch layout)
                 :bindings
                 (sort (loop for entry in (overlay-patch-bindings patch)
                             collect
                             (if (eq (patch-binding-disposition entry) :transparent)
                                 (cons (patch-binding-position entry) :transparent)
                                 (cons (patch-binding-position entry)
                                       (%normalize-binding
                                        (make-binding (patch-binding-position entry)
                                                      (patch-binding-behavior entry))
                                        layout))))
                       #'identifier< :key #'car)))

(defun %normalize-effects (effects layout)
  (labels ((variants (behaviors)
             ;; Effects themselves are declarations; normalize any embedded
             ;; behavior choices independently while retaining lifecycle slots.
             (mapcan (lambda (behavior) (%behavior-variants behavior layout)) behaviors)))
    (list :entry (variants (effect-entry-behaviors effects))
          :commit (variants (effect-commit-behaviors effects))
          :while (variants (effect-while-behaviors effects))
          :exit (variants (effect-exit-behaviors effects))
          :cancel (variants (effect-cancel-behaviors effects)))))

(defun %normalize-interaction (interaction layout)
  (make-instance
   'normalized-interaction
   :name (interaction-name interaction)
   :participants (copy-list (interaction-participants interaction))
   :observe (interaction-observe interaction) :anchor (interaction-anchor interaction)
   :arbitration (interaction-arbitration interaction)
   :candidates
   (mapcar (lambda (candidate)
             (let* ((entries (%behavior-variants (candidate-behavior candidate) layout))
                    (dependencies (candidate-axis-dependencies candidate))
                    (ordered (%layout-axis-order-for layout dependencies)))
               (make-instance 'normalized-interaction-candidate
                              :name (candidate-name candidate)
                              :match (candidate-match candidate)
                              :commit (candidate-commit candidate)
                              :entries
                              (mapcar (lambda (variant)
                                        (make-normalized-binding-entry (car variant) (cdr variant)))
                                      (%sort-variants entries layout ordered))
                              :effects (%normalize-effects (candidate-effects candidate) layout)
                              :context-axes ordered
                              :context-policy (candidate-context-policy candidate))))
           (sort (copy-list (interaction-candidates interaction)) #'identifier<
                 :key #'candidate-name))))

(defun normalize-layout (layout &key (validate t))
  "Resolve and normalize LAYOUT into a canonical backend-neutral IR.

When VALIDATE is true (the default), all ambiguity, incompleteness, template,
and finite-pattern checks run before expansion.  The result makes no XKB,
Kanata, keycode, group, or fixed-bit-width assumptions."
  (let ((resolved (resolve-layout layout)))
    (when validate (validate-layout resolved))
    (make-instance
     'normalized-layout
     :name (layout-name resolved)
     :topology (layout-topology resolved)
     :axes (copy-list (layout-axes resolved))
     :modifiers (layout-modifiers resolved)
     :bindings (sort (mapcar (lambda (binding) (%normalize-binding binding resolved))
                             (layout-bindings resolved))
                     #'identifier< :key #'normalized-binding-position)
     :patches (sort (mapcar (lambda (patch) (%normalize-patch patch resolved))
                            (layout-overlays resolved))
                    (lambda (left right)
                      (if (= (normalized-patch-precedence left)
                             (normalized-patch-precedence right))
                          (identifier< (normalized-patch-name left)
                                       (normalized-patch-name right))
                          (> (normalized-patch-precedence left)
                             (normalized-patch-precedence right)))))
     :interactions (sort (mapcar (lambda (interaction)
                                   (%normalize-interaction interaction resolved))
                                 (layout-interactions resolved))
                         #'identifier< :key #'normalized-interaction-name))))

(defun normalized-binding-entry-for-context (binding context)
  "Find BINDING's canonical entry matching a complete semantic CONTEXT.

The binding's tuple is partial by design; all its selected coordinates must
match CONTEXT, while irrelevant axes are ignored."
  (find-if (lambda (entry)
             (every (lambda (pair)
                      (identifier= (cdr pair)
                                   (semantic-context-state context (car pair))))
                    (context-tuple-pairs (normalized-entry-tuple entry))))
           (normalized-binding-entries binding)))

(defun normalized-layout-binding-for-context (normalized-layout position context
                                                &key active-patches)
  "Resolve POSITION under CONTEXT and explicitly active patch names/states.

ACTIVE-PATCHES is a sequence of patch names.  Patches are already sorted by
precedence; transparency falls through to the next patch then the base
binding."
  (let ((patches (remove-if-not
                  (lambda (patch)
                    (and (identifier-member-p (normalized-patch-name patch) active-patches)
                         (identifier= (normalized-patch-state patch)
                                      (semantic-context-state
                                       context (normalized-patch-axis patch)))))
                  (normalized-layout-patches normalized-layout))))
    (dolist (patch patches)
      (let ((entry (find (ensure-identifier position) (normalized-patch-bindings patch)
                         :test #'identifier= :key #'car)))
        (when entry
          (unless (eq (cdr entry) :transparent)
            (return-from normalized-layout-binding-for-context
              (normalized-binding-entry-for-context (cdr entry) context))))))
    (let ((binding (find (ensure-identifier position) (normalized-layout-bindings normalized-layout)
                         :test #'identifier= :key #'normalized-binding-position)))
      (and binding (normalized-binding-entry-for-context binding context)))))

(defun normalized-layout-key (normalized-layout)
  "A compact deterministic representation for equality/regression fixtures.

It intentionally contains semantic identifiers and behavior class names only;
backend resource allocation never affects the canonical abstract IR."
  (with-output-to-string (stream)
    (format stream "layout:~A|mods:" (identifier-name (normalized-layout-name normalized-layout)))
    (dolist (modifier (modifier-set-members (normalized-layout-modifiers normalized-layout)))
      (format stream "~A," (identifier-name modifier)))
    (dolist (binding (normalized-layout-bindings normalized-layout))
      (format stream "|~A=" (identifier-name (normalized-binding-position binding)))
      (dolist (entry (normalized-binding-entries binding))
        (format stream "[~A/~A]" (context-tuple-key (normalized-entry-tuple entry))
                (class-name (class-of (normalized-entry-behavior entry))))))))
