;;;; SPDX-License-Identifier: GPL-3.0-or-later
;;;; Static semantic validation for the finite Ivory Key model.

(in-package #:ivory-key.model)

(defstruct (semantic-diagnostic
            (:constructor make-semantic-diagnostic (code message &optional object))
            (:copier nil))
  code message object)

(defun %diagnostic (diagnostics code control &rest arguments)
  (cons (make-semantic-diagnostic code (apply #'format nil control arguments))
        diagnostics))

(defun %validation-error (diagnostics)
  (let ((first (first (last diagnostics))))
    (error 'semantic-validation-error
           :code (semantic-diagnostic-code first)
           :message (semantic-diagnostic-message first)
           :object (semantic-diagnostic-object first))))

(defun %duplicates (objects key)
  (let ((seen (make-hash-table :test #'equal))
        (duplicates nil))
    (dolist (object objects)
      (let ((value (funcall key object)))
        (if (gethash value seen)
            (push object duplicates)
            (setf (gethash value seen) t))))
    (nreverse duplicates)))

(defun %check-unique-identifiers (objects key label diagnostics)
  (dolist (object (%duplicates objects (lambda (object)
                                         (identifier-key (funcall key object)))))
    (setf diagnostics
          (%diagnostic diagnostics :duplicate-identifier
                       "Duplicate ~A identifier ~A."
                       label (identifier-name (funcall key object)))))
  diagnostics)

(defun %valid-duration-p (duration)
  (and (numberp duration) (<= 0 duration)))

(defun %validate-position-selector (selector layout diagnostics)
  (unless (typep selector 'position-selector)
    (return-from %validate-position-selector
      (%diagnostic diagnostics :invalid-position-selector
                   "A temporal position selector is malformed: ~S." selector)))
  (dolist (position (position-selector-positions selector))
    (unless (find-position position (layout-topology layout))
      (setf diagnostics
            (%diagnostic diagnostics :unknown-position
                         "Unknown logical position ~A in temporal pattern."
                         (identifier-name position)))))
  diagnostics)

(defun %validate-temporal-pattern (pattern layout diagnostics)
  (unless (typep pattern 'temporal-pattern)
    (return-from %validate-temporal-pattern
      (%diagnostic diagnostics :invalid-pattern "Expected a temporal pattern, got ~S." pattern)))
  (let ((kind (temporal-pattern-kind pattern))
        (arguments (temporal-pattern-arguments pattern)))
    (unless (member kind '(:down :up :sequence :all :either :and :duration
                          :deadline :within :overlap :without :repeat :capture
                          :context-is))
      (setf diagnostics (%diagnostic diagnostics :unknown-pattern-kind
                                     "Unknown temporal pattern kind ~S." kind)))
    (case kind
      ((:down :up)
       (unless (= (length arguments) 1)
         (setf diagnostics (%diagnostic diagnostics :invalid-pattern-arity
                                        "~A requires exactly one position selector." kind)))
       (when arguments
         (setf diagnostics (%validate-position-selector (first arguments) layout diagnostics))))
      ((:sequence :all :either :and)
       (when (endp arguments)
         (setf diagnostics (%diagnostic diagnostics :empty-pattern-composition
                                        "~A requires at least one subpattern." kind))))
      (:duration
       (when arguments
         (setf diagnostics (%validate-position-selector (first arguments) layout diagnostics)))
       (let ((minimum (temporal-pattern-option pattern :at-least))
             (maximum (temporal-pattern-option pattern :less-than)))
         (unless (or minimum maximum)
           (setf diagnostics (%diagnostic diagnostics :unbounded-duration
                                          "A duration pattern requires :AT-LEAST or :LESS-THAN.")))
         (unless (and (or (null minimum) (%valid-duration-p minimum))
                      (or (null maximum) (%valid-duration-p maximum))
                      (or (null minimum) (null maximum) (< minimum maximum)))
           (setf diagnostics (%diagnostic diagnostics :invalid-duration-range
                                          "Invalid duration range ~S .. ~S." minimum maximum)))))
      (:deadline
       (let ((duration (first arguments)))
         (unless (%valid-duration-p duration)
           (setf diagnostics (%diagnostic diagnostics :invalid-deadline
                                          "A deadline requires a non-negative duration."))))
       (unless (second arguments)
         (setf diagnostics (%diagnostic diagnostics :unanchored-deadline
                                        "A deadline requires an :AFTER anchor.")))
       (let ((while-down (temporal-pattern-option pattern :while-down)))
         (when while-down
           (setf diagnostics (%validate-position-selector
                              (if (typep while-down 'position-selector) while-down
                                  (position-selector while-down)) layout diagnostics)))))
      (:within
       (unless (%valid-duration-p (temporal-pattern-option pattern :duration))
         (setf diagnostics (%diagnostic diagnostics :invalid-within-window
                                        "WITHIN requires a non-negative finite :DURATION."))))
      (:overlap
       (when (< (length arguments) 2)
         (setf diagnostics (%diagnostic diagnostics :invalid-overlap
                                        "OVERLAP requires at least two participants.")))
       (dolist (selector arguments)
         (setf diagnostics (%validate-position-selector selector layout diagnostics))))
      (:without
       (unless (temporal-pattern-option pattern :between)
         (setf diagnostics (%diagnostic diagnostics :unclosed-absence
                                        "WITHOUT requires explicit closing :BETWEEN boundaries."))))
      (:repeat
       (let ((maximum (temporal-pattern-option pattern :at-most)))
         (unless (and (integerp maximum) (<= 0 maximum))
           (setf diagnostics (%diagnostic diagnostics :unbounded-repeat
                                          "REPEAT requires a non-negative finite :AT-MOST bound.")))))
      (:capture
       (unless (and (= (length arguments) 2) (typep (first arguments) 'identifier))
         (setf diagnostics (%diagnostic diagnostics :invalid-capture
                                        "CAPTURE requires an identifier and one subpattern."))))
      (:context-is
       (let ((axis (first arguments)) (state (second arguments)))
         (unless (and axis (layout-axis layout axis))
           (setf diagnostics (%diagnostic diagnostics :unknown-context-axis
                                          "Temporal predicate refers to unknown axis ~A." axis)))
         (when (and axis state (layout-axis layout axis))
           (unless (axis-state-p (layout-axis layout axis) state)
             (setf diagnostics (%diagnostic diagnostics :unknown-axis-state
                                            "Unknown state ~A for axis ~A."
                                            state axis))))))))
  (dolist (child (temporal-pattern-children pattern))
    (setf diagnostics (%validate-temporal-pattern child layout diagnostics)))
  diagnostics)

(defun %validate-axis-operation (behavior layout diagnostics)
  (let ((axis (layout-axis layout (axis-operation-axis behavior))))
    (unless axis
      (setf diagnostics (%diagnostic diagnostics :unknown-context-axis
                                     "Axis operation uses unknown axis ~A."
                                     (identifier-name (axis-operation-axis behavior)))))
    (when (and axis (axis-operation-state behavior)
               (not (axis-state-p axis (axis-operation-state behavior))))
      (setf diagnostics (%diagnostic diagnostics :unknown-axis-state
                                     "State ~A is not a state of axis ~A."
                                     (identifier-name (axis-operation-state behavior))
                                     (identifier-name (axis-name axis))))))
  diagnostics)

(defun %validate-behavior (behavior layout diagnostics &key (base-table-p t))
  (cond
    ((not (typep behavior 'behavior))
     (%diagnostic diagnostics :incomplete-behavior "Expected a complete behavior, got ~S." behavior))
    ((or (typep behavior 'behavior-template-parameter)
         (typep behavior 'behavior-template-reference))
     (%diagnostic diagnostics :unresolved-template
                  "Template placeholder/reference remains after resolution."))
    ((typep behavior 'modifier-operation-behavior)
     (if (modifier-set-contains-p (modifier-operation-modifier behavior)
                                  (layout-modifiers layout))
         diagnostics
         (%diagnostic diagnostics :unknown-semantic-modifier
                      "Unknown semantic modifier ~A."
                      (identifier-name (modifier-operation-modifier behavior)))))
    ((typep behavior 'axis-operation-behavior)
     (%validate-axis-operation behavior layout diagnostics))
    ((typep behavior 'axis-choice-behavior)
     (let ((axis (layout-axis layout (choice-axis behavior))))
       (unless axis
         (setf diagnostics (%diagnostic diagnostics :unknown-context-axis
                                        "Behavioral choice uses unknown axis ~A."
                                        (identifier-name (choice-axis behavior)))))
       (when (and axis (not (eq (axis-resolution axis) :behavioral)))
         (setf diagnostics (%diagnostic diagnostics :wrong-axis-resolution
                                        "Axis choice ~A must use a behavioral axis."
                                        (identifier-name (choice-axis behavior)))))
       (setf diagnostics
             (%check-unique-identifiers (choice-behaviors behavior) #'car
                                        "behavioral-choice state" diagnostics))
       (when axis
         (dolist (state (axis-states axis))
           (unless (find state (choice-behaviors behavior)
                         :test #'identifier= :key #'car)
             (setf diagnostics
                   (%diagnostic diagnostics :incomplete-behavioral-choice
                                "Behavioral choice for axis ~A lacks state ~A."
                                (identifier-name (axis-name axis))
                                (identifier-name state))))))
       (dolist (choice (choice-behaviors behavior))
         (when (and axis (not (axis-state-p axis (car choice))))
           (setf diagnostics (%diagnostic diagnostics :unknown-axis-state
                                          "Unknown choice state ~A for axis ~A."
                                          (identifier-name (car choice))
                                          (identifier-name (axis-name axis)))))
         (setf diagnostics (%validate-behavior (cdr choice) layout diagnostics))))
       )
    ((typep behavior 'behavior-table)
     (%validate-behavior-table behavior layout diagnostics :base-table-p base-table-p))
    (t
     (dolist (child (behavior-children behavior))
       (setf diagnostics (%validate-behavior child layout diagnostics)))
     diagnostics)))

(defun %contains-held-lifecycle-behavior-p (behavior)
  "Whether BEHAVIOR contains a source hold that needs an owning :WHILE effect."
  (or (typep behavior 'held-modifier-behavior)
      (and (typep behavior 'axis-operation-behavior)
           (eq (axis-operation behavior) :hold))
      (some #'%contains-held-lifecycle-behavior-p (behavior-children behavior))))

(defun %self-reversing-held-behavior-p (behavior)
  "Whether BEHAVIOR is wholly an owner-scoped, automatically released hold.

The V1 surface admits source holds only in :WHILE.  Compositions and resolved
context choices are allowed when every possible child is itself a hold; this
keeps the lifecycle contract exact without inventing a release action for a
different safe-but-non-held behavior."
  (cond
    ((typep behavior 'held-modifier-behavior) t)
    ((typep behavior 'axis-operation-behavior)
     (eq (axis-operation behavior) :hold))
    ((or (typep behavior 'ordered-behavior)
         (typep behavior 'simultaneous-behavior)
         (typep behavior 'axis-choice-behavior)
         (typep behavior 'behavior-table))
     (let ((children (behavior-children behavior)))
       (and children (every #'%self-reversing-held-behavior-p children))))
    (t nil)))

(defun %validate-held-lifecycle-placement (candidate effects diagnostics)
  "Validate the one exact V1 release contract for source-level holds."
  (dolist (phase (list (cons :entry (effect-entry-behaviors effects))
                       (cons :commit-effect (effect-commit-behaviors effects))
                       (cons :exit (effect-exit-behaviors effects))
                       (cons :cancel (effect-cancel-behaviors effects))))
    (when (some #'%contains-held-lifecycle-behavior-p (cdr phase))
      (setf diagnostics
            (%diagnostic diagnostics :held-behavior-outside-while
                         "Candidate ~A places a source hold in ~A; holds require :WHILE ownership."
                         (identifier-name (candidate-name candidate)) (car phase)))))
  (dolist (behavior (effect-while-behaviors effects))
    (unless (%self-reversing-held-behavior-p behavior)
      (setf diagnostics
            (%diagnostic diagnostics :nonheld-while-effect
                         "Candidate ~A has a :WHILE behavior without an exact owner-scoped hold release."
                         (identifier-name (candidate-name candidate))))))
  diagnostics)

(defun %tuple-matches-axes-p (tuple axes)
  (and (= (length (context-tuple-pairs tuple)) (length axes))
       (every (lambda (axis)
                (let ((state (context-tuple-state tuple (axis-name axis))))
                  (and state (axis-state-p axis state))))
              axes)))

(defun %table-expected-tuples (table layout)
  (let ((axes (mapcar (lambda (name) (layout-axis layout name))
                      (behavior-table-axes table))))
    (if (some #'null axes)
        nil
        (or (behavior-table-allowed-tuples table)
            (allowed-product-tuples axes)))))

(defun %inheritance-cycle-p (entry table seen)
  (let ((key (context-tuple-key (behavior-entry-tuple entry))))
    (cond ((member key seen :test #'string=) t)
          ((not (eq (behavior-entry-disposition entry) :inherit)) nil)
          (t (let ((source (find-behavior-entry (behavior-entry-inherit-tuple entry) table)))
               (and source (%inheritance-cycle-p source table (cons key seen))))))))

(defun %validate-behavior-table (table layout diagnostics &key (base-table-p t))
  (let* ((axis-names (behavior-table-axes table))
         (axes (mapcar (lambda (name) (layout-axis layout name)) axis-names))
         (entries (behavior-table-entries table)))
    (setf diagnostics (%check-unique-identifiers axis-names #'identity "table axis" diagnostics))
    (dolist (axis axes)
      (unless axis
        (setf diagnostics (%diagnostic diagnostics :unknown-context-axis
                                       "A behavior table references an unknown axis."))))
    (when (every #'identity axes)
      (dolist (entry entries)
        (unless (%tuple-matches-axes-p (behavior-entry-tuple entry) axes)
          (setf diagnostics (%diagnostic diagnostics :invalid-context-tuple
                                         "Table tuple ~A does not match its declared axes."
                                         (context-tuple-key (behavior-entry-tuple entry)))))
        (case (behavior-entry-disposition entry)
          (:behavior (setf diagnostics (%validate-behavior (behavior-entry-behavior entry)
                                                          layout diagnostics)))
          (:none nil)
          (:transparent
           (when base-table-p
             (setf diagnostics (%diagnostic diagnostics :transparent-base-entry
                                            "A base behavior table cannot be transparent."))))
          (:inherit
           (unless (find-behavior-entry (behavior-entry-inherit-tuple entry) table)
             (setf diagnostics (%diagnostic diagnostics :unknown-inheritance-source
                                            "Table inheritance source ~A does not exist."
                                            (context-tuple-key
                                             (behavior-entry-inherit-tuple entry))))))
          (otherwise
           (setf diagnostics (%diagnostic diagnostics :unknown-entry-disposition
                                          "Unknown behavior-table disposition ~S."
                                          (behavior-entry-disposition entry))))))
      (dolist (entry (%duplicates entries
                                  (lambda (entry)
                                    (context-tuple-key (behavior-entry-tuple entry)))))
        (declare (ignore entry))
        (setf diagnostics (%diagnostic diagnostics :duplicate-context-entry
                                       "A behavior table defines the same context tuple twice.")))
      (dolist (expected (%table-expected-tuples table layout))
        (unless (find-behavior-entry expected table)
          (setf diagnostics (%diagnostic diagnostics :incomplete-level-table
                                         "Missing explicit behavior, NONE, or INHERIT for tuple ~A."
                                         (context-tuple-key expected)))))
      (dolist (entry entries)
        (when (%inheritance-cycle-p entry table nil)
          (setf diagnostics (%diagnostic diagnostics :inheritance-cycle
                                         "Behavior-table inheritance contains a cycle at ~A."
                                         (context-tuple-key (behavior-entry-tuple entry)))))))
    diagnostics))

(defun %pattern-equivalent-p (left right)
  (labels ((equivalent (left right)
             (cond ((and (typep left 'temporal-pattern)
                         (typep right 'temporal-pattern))
                    (and (eq (temporal-pattern-kind left) (temporal-pattern-kind right))
                         (equivalent (temporal-pattern-arguments left)
                                     (temporal-pattern-arguments right))
                         (equivalent (temporal-pattern-options left)
                                     (temporal-pattern-options right))))
                   ((and (typep left 'position-selector)
                         (typep right 'position-selector))
                    (and (eq (position-selector-kind left) (position-selector-kind right))
                         (equivalent (position-selector-positions left)
                                     (position-selector-positions right))))
                   ((and (typep left 'identifier) (typep right 'identifier))
                    (identifier= left right))
                   ((and (consp left) (consp right))
                    (and (equivalent (car left) (car right))
                         (equivalent (cdr left) (cdr right))))
                   (t (eql left right)))))
    (equivalent left right)))

(defun %arbitration-resolves-p (arbitration left right)
  (cond ((null arbitration) nil)
        ((eq (first arbitration) :longest-match)
         (%valid-duration-p (getf (rest arbitration) :deadline)))
        ((eq (first arbitration) :priority)
         (let ((priority (second arbitration)))
           (and (identifier-member-p (candidate-name left) priority)
                (identifier-member-p (candidate-name right) priority)
                (/= (position (candidate-name left) priority :test #'identifier=)
                    (position (candidate-name right) priority :test #'identifier=)))))
        (t nil)))

(defun %validate-candidate (candidate interaction layout diagnostics)
  (declare (ignore interaction))
  (unless (temporal-pattern-finite-p (candidate-match candidate))
    (setf diagnostics (%diagnostic diagnostics :nonfinite-interaction-pattern
                                   "Candidate ~A has an unbounded or unknown temporal pattern."
                                   (identifier-name (candidate-name candidate)))))
  (setf diagnostics (%validate-temporal-pattern (candidate-match candidate) layout diagnostics))
  (unless (candidate-commit candidate)
    (setf diagnostics (%diagnostic diagnostics :missing-commit
                                   "Candidate ~A has no explicit commit point."
                                   (identifier-name (candidate-name candidate)))))
  (setf diagnostics (%validate-behavior (candidate-behavior candidate) layout diagnostics))
  (when (%contains-held-lifecycle-behavior-p (candidate-behavior candidate))
    (setf diagnostics
          (%diagnostic diagnostics :held-behavior-outside-while
                       "Candidate ~A places a source hold in :DO; holds require :WHILE ownership."
                       (identifier-name (candidate-name candidate)))))
  (let ((effects (candidate-effects candidate)))
    (dolist (behavior (interaction-effects-behaviors effects))
      (setf diagnostics (%validate-behavior behavior layout diagnostics)))
    (when (some #'behavior-irreversible-p (effect-entry-behaviors effects))
      (setf diagnostics (%diagnostic diagnostics :irreversible-entry-effect
                                     "Candidate ~A emits irreversible output before commitment."
                                     (identifier-name (candidate-name candidate)))))
    (when (some #'behavior-irreversible-p (effect-while-behaviors effects))
      (setf diagnostics (%diagnostic diagnostics :irreversible-while-effect
                                     "Candidate ~A emits irreversible output while speculative."
                                     (identifier-name (candidate-name candidate)))))
    (setf diagnostics (%validate-held-lifecycle-placement candidate effects diagnostics)))
  (dolist (axis (candidate-axis-dependencies candidate))
    (unless (layout-axis layout axis)
      (setf diagnostics (%diagnostic diagnostics :unknown-context-axis
                                     "Candidate ~A consults unknown axis ~A."
                                     (identifier-name (candidate-name candidate))
                                     (identifier-name axis)))))
  diagnostics)

(defun %validate-interaction (interaction layout diagnostics)
  (let ((participants (interaction-participants interaction))
        (candidates (interaction-candidates interaction)))
    (when (endp participants)
      (setf diagnostics (%diagnostic diagnostics :empty-interaction-participants
                                     "Interaction ~A has no finite participants."
                                     (identifier-name (interaction-name interaction)))))
    (setf diagnostics (%check-unique-identifiers participants #'identity "interaction participant" diagnostics))
    (dolist (position participants)
      (unless (find-position position (layout-topology layout))
        (setf diagnostics (%diagnostic diagnostics :unknown-position
                                       "Interaction ~A names unknown position ~A."
                                       (identifier-name (interaction-name interaction))
                                       (identifier-name position)))))
    (setf diagnostics (%check-unique-identifiers candidates #'candidate-name "interaction candidate" diagnostics))
    (dolist (candidate candidates)
      (setf diagnostics (%validate-candidate candidate interaction layout diagnostics)))
    ;; Identical patterns with the same commitment can commit on the same
    ;; trace.  This conservative proof is enough to reject actual ambiguity
    ;; without guessing at a policy for merely similar patterns.
    (loop for tail on candidates
          for left = (first tail)
          do (dolist (right (rest tail))
               (when (and (%pattern-equivalent-p (candidate-match left)
                                                 (candidate-match right))
                          (%pattern-equivalent-p (candidate-commit left)
                                                 (candidate-commit right))
                          (not (%arbitration-resolves-p (interaction-arbitration interaction)
                                                        left right)))
                 (setf diagnostics
                       (%diagnostic diagnostics :ambiguous-interaction-commit
                                    "Candidates ~A and ~A can commit on the same trace without arbitration."
                                    (identifier-name (candidate-name left))
                                    (identifier-name (candidate-name right)))))))
    diagnostics))

(defun %behavior-template-references (behavior)
  (append (when (typep behavior 'behavior-template-reference)
            (list (behavior-reference-name behavior)))
          (mapcan #'%behavior-template-references (behavior-children behavior))))

(defun %validate-template-graph (layout diagnostics)
  (let ((templates (layout-behavior-templates layout))
        (visiting (make-hash-table :test #'equal))
        (visited (make-hash-table :test #'equal)))
    (labels ((walk (template)
               (let ((key (identifier-key (behavior-template-name template))))
                 (cond ((gethash key visiting)
                        (setf diagnostics (%diagnostic diagnostics :recursive-behavior-template
                                                       "Behavior template cycle includes ~A."
                                                       (identifier-name (behavior-template-name template)))))
                       ((not (gethash key visited))
                        (setf (gethash key visiting) t)
                        (dolist (reference (%behavior-template-references
                                            (behavior-template-body template)))
                          (let ((target (layout-behavior-template layout reference)))
                            (if target
                                (walk target)
                                (setf diagnostics
                                      (%diagnostic diagnostics :unknown-behavior-template
                                                   "Template ~A refers to unknown template ~A."
                                                   (identifier-name (behavior-template-name template))
                                                   (identifier-name reference))))))
                        (remhash key visiting)
                        (setf (gethash key visited) t))))))
      (setf diagnostics (%check-unique-identifiers templates #'behavior-template-name
                                                   "behavior-template" diagnostics))
      (dolist (template templates) (walk template))))
  diagnostics)

(defun %validate-interaction-template-graph (layout diagnostics)
  "Validate the finite named-reference graph independently of instantiation.

This catches an unused recursive interaction template rather than leaving a
future caller to discover it through unbounded resolver recursion."
  (let ((templates (layout-interaction-templates layout))
        (visiting (make-hash-table :test #'equal))
        (visited (make-hash-table :test #'equal)))
    (labels ((walk (template)
               (let ((key (identifier-key (interaction-template-name template))))
                 (cond ((gethash key visiting)
                        (setf diagnostics
                              (%diagnostic diagnostics :recursive-interaction-template
                                           "Interaction template cycle includes ~A."
                                           (identifier-name (interaction-template-name template)))))
                       ((not (gethash key visited))
                        (setf (gethash key visiting) t)
                        (let ((body (interaction-template-body template)))
                          (cond ((typep body 'interaction-template-reference)
                                 (let ((target (layout-interaction-template
                                               layout (interaction-reference-name body))))
                                   (if target
                                       (walk target)
                                       (setf diagnostics
                                             (%diagnostic diagnostics :unknown-interaction-template
                                                          "Interaction template ~A refers to unknown template ~A."
                                                          (identifier-name
                                                           (interaction-template-name template))
                                                          (identifier-name
                                                           (interaction-reference-name body)))))))
                                ((not (typep body 'interaction))
                                 (setf diagnostics
                                       (%diagnostic diagnostics :invalid-interaction-template
                                                    "Interaction template ~A has no interaction body."
                                                    (identifier-name
                                                     (interaction-template-name template)))))))
                        (remhash key visiting)
                        (setf (gethash key visited) t))))))
      (setf diagnostics (%check-unique-identifiers templates #'interaction-template-name
                                                   "interaction-template" diagnostics))
      (dolist (template templates)
        (setf diagnostics (%check-unique-identifiers
                           (interaction-template-parameters template) #'identity
                           "interaction-template parameter" diagnostics))
        (walk template))))
  diagnostics)

(defun %validate-overlay (overlay layout diagnostics)
  (let ((axis (layout-axis layout (overlay-patch-axis overlay))))
    (unless axis
      (setf diagnostics (%diagnostic diagnostics :unknown-context-axis
                                     "Overlay ~A uses unknown axis ~A."
                                     (identifier-name (overlay-patch-name overlay))
                                     (identifier-name (overlay-patch-axis overlay)))))
    (when (and axis (not (eq (axis-resolution axis) :patch)))
      (setf diagnostics (%diagnostic diagnostics :wrong-axis-resolution
                                     "Overlay ~A must be selected by a patch axis."
                                     (identifier-name (overlay-patch-name overlay)))))
    (when (and axis (not (axis-state-p axis (overlay-patch-state overlay))))
      (setf diagnostics (%diagnostic diagnostics :unknown-axis-state
                                     "Overlay ~A selects unknown state ~A."
                                     (identifier-name (overlay-patch-name overlay))
                                     (identifier-name (overlay-patch-state overlay)))))
    (setf diagnostics (%check-unique-identifiers (overlay-patch-bindings overlay)
                                                 #'patch-binding-position
                                                 "overlay binding" diagnostics))
    (dolist (patch-binding (overlay-patch-bindings overlay))
      (unless (find-position (patch-binding-position patch-binding) (layout-topology layout))
        (setf diagnostics (%diagnostic diagnostics :unknown-position
                                       "Overlay ~A refers to unknown position ~A."
                                       (identifier-name (overlay-patch-name overlay))
                                       (identifier-name (patch-binding-position patch-binding)))))
      (when (eq (patch-binding-disposition patch-binding) :behavior)
        (setf diagnostics (%validate-behavior (patch-binding-behavior patch-binding)
                                              layout diagnostics))))
    diagnostics))

(defun %overlay-precedence (overlay layout)
  (or (overlay-patch-precedence overlay)
      (let ((axis (layout-axis layout (overlay-patch-axis overlay))))
        (and axis (axis-precedence axis)))))

(defun %validate-patch-ambiguity (layout diagnostics)
  (let ((overlays (layout-overlays layout)))
    (loop for tail on overlays
          for left = (first tail)
          do (dolist (right (rest tail))
               (when (= (%overlay-precedence left layout) (%overlay-precedence right layout))
                 (dolist (left-binding (overlay-patch-bindings left))
                   (let ((right-binding
                           (find (patch-binding-position left-binding)
                                 (overlay-patch-bindings right)
                                 :test #'identifier= :key #'patch-binding-position)))
                     (when (and right-binding
                                (eq (patch-binding-disposition left-binding) :behavior)
                                (eq (patch-binding-disposition right-binding) :behavior))
                       (setf diagnostics
                             (%diagnostic diagnostics :ambiguous-patch-precedence
                                          "Patches ~A and ~A override ~A at equal precedence."
                                          (identifier-name (overlay-patch-name left))
                                          (identifier-name (overlay-patch-name right))
                                          (identifier-name (patch-binding-position left-binding))))))))))
  diagnostics))

(defun validate-layout (layout &key (signal-on-error t))
  "Validate LAYOUT's finite, target-neutral semantics.

Returns two values: LAYOUT and diagnostics in source order.  With the default
SIGNAL-ON-ERROR, the first diagnostic is also signaled as a
SEMANTIC-VALIDATION-ERROR."
  (let ((diagnostics nil))
    (unless (typep layout 'layout)
      (error 'semantic-validation-error :code :not-a-layout
             :message "Expected an Ivory Key LAYOUT object."))
    (let ((axes (layout-axes layout))
          (topology (layout-topology layout)))
      (setf diagnostics (%check-unique-identifiers axes #'axis-name "axis" diagnostics))
      (dolist (axis axes)
        (when (< (length (axis-states axis)) 2)
          (setf diagnostics (%diagnostic diagnostics :axis-too-small
                                         "Axis ~A needs at least two states."
                                         (identifier-name (axis-name axis)))))
        (setf diagnostics (%check-unique-identifiers (axis-states axis) #'identity
                                                     "axis state" diagnostics))
        (unless (member (axis-resolution axis) +axis-resolution-kinds+)
          (setf diagnostics (%diagnostic diagnostics :unknown-axis-resolution
                                         "Axis ~A has unknown resolution ~S."
                                         (identifier-name (axis-name axis))
                                         (axis-resolution axis))))
        )
      (let* ((products (layout-product-axes layout))
             (restrictions (remove-if-not #'axis-valid-tuples products))
             (expected-length (length products)))
        (dolist (axis restrictions)
          (dolist (tuple (axis-valid-tuples axis))
            (unless (= (length tuple) expected-length)
              (setf diagnostics (%diagnostic diagnostics :invalid-restricted-product
                                             "Restricted tuple on axis ~A has ~D states; expected ~D."
                                             (identifier-name (axis-name axis))
                                             (length tuple) expected-length)))
            (loop for product-axis in products
                  for state in tuple
                  unless (axis-state-p product-axis state)
                    do (setf diagnostics
                             (%diagnostic diagnostics :invalid-restricted-product
                                          "Restricted tuple state ~A is invalid for product axis ~A."
                                          (identifier-name state)
                                          (identifier-name (axis-name product-axis)))))))
        (when (rest restrictions)
          (let ((first-restriction
                  (mapcar (lambda (tuple) (mapcar #'identifier-name tuple))
                          (axis-valid-tuples (first restrictions)))))
            (dolist (axis (rest restrictions))
              (unless (equal first-restriction
                             (mapcar (lambda (tuple)
                                       (mapcar #'identifier-name tuple))
                                     (axis-valid-tuples axis)))
                (setf diagnostics
                      (%diagnostic diagnostics :inconsistent-restricted-product
                                   "Product axes declare inconsistent restricted tuple sets.")))))))
      (unless (typep topology 'topology)
        (setf diagnostics (%diagnostic diagnostics :invalid-topology
                                       "Layout ~A has no topology object."
                                       (identifier-name (layout-name layout)))))
      (when (typep topology 'topology)
        (setf diagnostics (%check-unique-identifiers (topology-positions topology)
                                                     #'position-name "topology position" diagnostics)))
      (setf diagnostics (%check-unique-identifiers (layout-bindings layout)
                                                   #'binding-position "binding position" diagnostics))
      (dolist (binding (layout-bindings layout))
        (when (and (typep topology 'topology)
                   (not (find-position (binding-position binding) topology)))
          (setf diagnostics (%diagnostic diagnostics :unknown-position
                                         "Binding uses unknown logical position ~A."
                                         (identifier-name (binding-position binding)))))
        (setf diagnostics (%validate-behavior (binding-behavior binding) layout diagnostics))
        (when (%contains-held-lifecycle-behavior-p (binding-behavior binding))
          (setf diagnostics
                (%diagnostic diagnostics :held-behavior-outside-while
                             "Binding ~A places a source hold outside an interaction :WHILE."
                             (identifier-name (binding-position binding))))))
      (setf diagnostics (%validate-template-graph layout diagnostics))
      (setf diagnostics (%validate-interaction-template-graph layout diagnostics))
      (setf diagnostics (%check-unique-identifiers (layout-overlays layout)
                                                   #'overlay-patch-name "overlay" diagnostics))
      (dolist (overlay (layout-overlays layout))
        (setf diagnostics (%validate-overlay overlay layout diagnostics)))
      (setf diagnostics (%validate-patch-ambiguity layout diagnostics))
      (setf diagnostics (%check-unique-identifiers (layout-interactions layout)
                                                   #'interaction-name "interaction" diagnostics))
      (dolist (interaction (layout-interactions layout))
        (if (typep interaction 'interaction)
            (setf diagnostics (%validate-interaction interaction layout diagnostics))
            (setf diagnostics
                  (%diagnostic diagnostics :unresolved-interaction-template
                               "Interaction template reference must be resolved before validation.")))))
    (setf diagnostics (nreverse diagnostics))
    (when (and signal-on-error diagnostics) (%validation-error diagnostics))
    (values layout diagnostics)))
