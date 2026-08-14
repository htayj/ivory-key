;;;; SPDX-License-Identifier: GPL-3.0-or-later
;;;; Target-neutral capability planning for normalized Ivory Key layouts.

(in-package #:ivory-key.backend)

;;; The planner deliberately stops before target lowering.  It records the
;;; complete normalized table and the semantic resources a lowering must
;;; satisfy; XKB, Kanata, and a future firmware backend may then choose a
;;; concrete spelling without changing layout meaning.

(define-condition planner-refusal (error)
  ((code :initarg :code :reader planner-refusal-code)
   (feature :initarg :feature :initform nil :reader planner-refusal-feature)
   (detail :initarg :detail :reader planner-refusal-detail)
   (plan :initarg :plan :initform nil :reader planner-refusal-plan))
  (:report (lambda (condition stream)
             (format stream "Planner refusal~@[ for ~A~] [~A]: ~A"
                     (planner-refusal-feature condition)
                     (planner-refusal-code condition)
                     (planner-refusal-detail condition)))))

(defclass static-table-requirement ()
  ((position :initarg :position :reader static-table-requirement-position)
   ;; The physical input is deliberately opaque.  A device profile, not the
   ;; layout, decides whether this later spells an evdev code or a firmware
   ;; switch identity.
   (physical-input :initarg :physical-input
                   :reader static-table-requirement-physical-input)
   ;; Normalization has already established this declaration-order list.  Its
   ;; entries must therefore never be sorted by a backend or hash table.
   (axes :initarg :axes :reader static-table-requirement-axes)
   (entries :initarg :entries :reader static-table-requirement-entries)
   (state-count :initarg :state-count
                :reader static-table-requirement-state-count)
   (static-p :initarg :static-p :reader static-table-requirement-static-p)))

(defun make-static-table-requirement (position physical-input axes entries
                                      &key (static-p t))
  "Make an immutable-by-convention request for one normalized binding table.

ENTRIES stay in normalized order: the first declared axis varies fastest.
No fixed-width selector or modifier representation is introduced here.
"
  (make-instance 'static-table-requirement
                 :position (ensure-identifier position)
                 :physical-input physical-input
                 :axes (copy-list axes)
                 :entries (copy-list entries)
                 :state-count (length entries)
                 :static-p static-p))

(defclass planned-binding (static-table-requirement) ())

(defun make-planned-binding (position physical-input axes entries &key (static-p t))
  "Construct the binding-table form retained in a LOWERING-PLAN."
  (make-instance 'planned-binding
                 :position (ensure-identifier position)
                 :physical-input physical-input
                 :axes (copy-list axes)
                 :entries (copy-list entries)
                 :state-count (length entries)
                 :static-p static-p))

(defclass selector-requirement ()
  ((axis :initarg :axis :reader selector-requirement-axis)
   (resolution :initarg :resolution :reader selector-requirement-resolution)
   (states :initarg :states :reader selector-requirement-states)
   (default-state :initarg :default-state
                  :reader selector-requirement-default-state)
   ;; Logical positions whose normalized behavior actually depends on AXIS.
   (positions :initarg :positions :reader selector-requirement-positions)))

(defun make-selector-requirement (axis resolution states default-state positions)
  "Describe a semantic context selector without assigning a backend resource."
  (make-instance 'selector-requirement
                 :axis (ensure-identifier axis) :resolution resolution
                 :states (copy-identifier-list states)
                 :default-state (ensure-identifier default-state)
                 :positions (copy-identifier-list positions)))

(defclass modifier-requirement ()
  ((modifier :initarg :modifier :reader modifier-requirement-modifier)))

(defun make-modifier-requirement (modifier)
  "Describe one application-visible semantic modifier, never a modifier mask."
  (make-instance 'modifier-requirement :modifier (ensure-identifier modifier)))

(defclass planner-resource-requirement ()
  ((kind :initarg :kind :reader planner-resource-requirement-kind)
   ;; OWNER is a stable semantic label, not a resource spelling.
   (owner :initarg :owner :reader planner-resource-requirement-owner)
   (cardinality :initarg :cardinality :initform 1
                :reader planner-resource-requirement-cardinality)
   (detail :initarg :detail :initform "" :reader planner-resource-requirement-detail)
   ;; The current normalized model has no source-span slot.  Keep this field
   ;; now so a decoder can attach the source authority without changing the
   ;; planner IR later.
   (source :initarg :source :initform nil :reader planner-resource-requirement-source)))

(defun make-planner-resource-requirement (kind owner
                                           &key (cardinality 1) (detail "") source)
  "Make one target-independent finite-resource obligation."
  (check-type cardinality (integer 1 *))
  (make-instance 'planner-resource-requirement
                 :kind kind :owner owner :cardinality cardinality
                 :detail detail :source source))

(defclass planner-allocation ()
  ((requirement :initarg :requirement :reader planner-allocation-requirement)
   (pool-kind :initarg :pool-kind :reader planner-allocation-pool-kind)
   (value :initarg :value :reader planner-allocation-value)))

(defun make-planner-allocation (requirement pool-kind value)
  "Record one deterministic concrete allocation made during capability planning."
  (make-instance 'planner-allocation :requirement requirement
                 :pool-kind pool-kind :value value))

(defclass lowering-plan ()
  ((layout :initarg :layout :reader lowering-plan-layout)
   (placement :initarg :placement :reader lowering-plan-placement)
   (bindings :initarg :bindings :reader lowering-plan-bindings)
   (selector-requirements :initarg :selector-requirements
                          :reader lowering-plan-selector-requirements)
   (modifier-requirements :initarg :modifier-requirements
                          :reader lowering-plan-modifier-requirements)
   (resource-requirements :initarg :resource-requirements
                          :reader lowering-plan-resource-requirements)
   (allocations :initarg :allocations :reader lowering-plan-allocations)
   (realizations :initarg :realizations :reader lowering-plan-realizations)
   (diagnostics :initarg :diagnostics :reader lowering-plan-diagnostics)))

(defun make-lowering-plan (layout placement bindings selector-requirements
                           modifier-requirements resource-requirements
                           allocations realizations diagnostics)
  "Construct an immutable-by-convention, backend-neutral lowering plan."
  (make-instance 'lowering-plan
                 :layout layout :placement placement :bindings (copy-list bindings)
                 :selector-requirements (copy-list selector-requirements)
                 :modifier-requirements (copy-list modifier-requirements)
                 :resource-requirements (copy-list resource-requirements)
                 :allocations (copy-list allocations)
                 :realizations (copy-list realizations)
                 :diagnostics (copy-list diagnostics)))

;;; Canonical inspection -----------------------------------------------------

(defun %planner-name (value)
  (typecase value
    (identifier (identifier-name value))
    (string value)
    (symbol (string-downcase (symbol-name value))
    )
    (t (princ-to-string value))))

(defun %planner-key (kind owner)
  (format nil "~A/~A" (%planner-name kind) (%planner-name owner)))

(defun %planner-resource-requirement< (left right)
  (string< (%planner-key (planner-resource-requirement-kind left)
                         (planner-resource-requirement-owner left))
           (%planner-key (planner-resource-requirement-kind right)
                         (planner-resource-requirement-owner right))))

(defun %planner-binding< (left right)
  (identifier< (static-table-requirement-position left)
               (static-table-requirement-position right)))

(defun %planner-placement-inputs (placement)
  "Return canonical (logical-position . physical-input) associations.

MODEL:DEVICE-PLACEMENT stores the inverse association because it preserves a
physical device's input inventory.  A lowering plan needs the logical lookup.
"
  (unless (typep placement 'device-placement)
    (error 'planner-refusal :code :invalid-device-placement
           :detail "Capability planning requires a MODEL:DEVICE-PLACEMENT."))
  (let ((seen-inputs (make-hash-table :test #'equal))
        (seen-positions (make-hash-table :test #'equal))
        (result nil))
    (dolist (mapping (placement-mappings placement))
      (let ((input (car mapping))
            (position (cdr mapping)))
        (unless (and (stringp input) (plusp (length input)))
          (error 'planner-refusal :code :invalid-physical-input
                 :feature position
                 :detail "Device placement physical inputs must be non-empty strings."))
        (when (gethash input seen-inputs)
          (error 'planner-refusal :code :duplicate-physical-input
                 :feature input
                 :detail "A physical input may map to only one logical position."))
        (when (gethash (identifier-key position) seen-positions)
          (error 'planner-refusal :code :duplicate-logical-placement
                 :feature position
                 :detail "A device placement may not make one logical position ambiguous."))
        (setf (gethash input seen-inputs) t
              (gethash (identifier-key position) seen-positions) t)
        (push (cons position input) result)))
    (sort result #'identifier< :key #'car)))

(defun %planner-check-compatible-placement (layout placement)
  (unless (identifier= (topology-name (normalized-layout-topology layout))
                        (topology-name (placement-topology placement)))
    (error 'planner-refusal :code :placement-topology-mismatch
           :detail (format nil "Layout topology ~A does not match placement topology ~A."
                           (identifier-name
                            (topology-name (normalized-layout-topology layout)))
                           (identifier-name
                            (topology-name (placement-topology placement)))))))

(defun %planner-input-for-position (position input-mappings)
  (cdr (find position input-mappings :key #'car :test #'identifier=)))

(defun %planner-static-p (axes)
  "Whether AXES describe a product table rather than a behavioral lowering."
  (every (lambda (axis) (eq (axis-resolution axis) :product)) axes))

(defun %planner-binding-requirements (layout placement)
  (let ((inputs (%planner-placement-inputs placement))
        (requirements nil))
    (dolist (binding (normalized-layout-bindings layout))
      (let* ((position (normalized-binding-position binding))
             (input (%planner-input-for-position position inputs))
             (axes (mapcar (lambda (axis-name)
                             (find-axis axis-name (normalized-layout-axes layout)
                                        :errorp t))
                           (normalized-binding-axes binding))))
        (unless input
          (error 'planner-refusal :code :missing-device-placement
                 :feature position
                 :detail "No physical input is assigned to this logical binding."))
        (push (make-planned-binding position input axes
                                    (normalized-binding-entries binding)
                                    :static-p (%planner-static-p axes))
              requirements)))
    (sort requirements #'%planner-binding<)))

(defun %planner-selector-requirements (bindings)
  (let ((by-axis (make-hash-table :test #'equal)))
    (dolist (binding bindings)
      (dolist (axis (static-table-requirement-axes binding))
        (let* ((key (identifier-key (axis-name axis)))
               (previous (gethash key by-axis)))
          (setf (gethash key by-axis)
                (cons axis
                      (cons (static-table-requirement-position binding)
                            (cdr previous)))))))
    (sort
     (loop for pair being the hash-values of by-axis
           for axis = (car pair)
           collect
           (make-selector-requirement
            (axis-name axis) (axis-resolution axis) (axis-states axis)
            (axis-default-state axis)
            (sort (remove-duplicates (copy-list (cdr pair)) :test #'identifier=)
                  #'identifier<)))
     #'identifier< :key #'selector-requirement-axis)))

(defun %planner-modifier-requirements (layout)
  (mapcar #'make-modifier-requirement
          (sort (copy-list (modifier-set-members (normalized-layout-modifiers layout)))
                #'identifier<)))

(defun %planner-output-resource-requirements (behavior)
  "Describe resources implied by a complete abstract output recursively."
  (cond
    ((typep behavior 'command-output)
     (list (make-planner-resource-requirement
            :command (command-name behavior)
            :detail "Application-visible command identity.")))
    ((typep behavior 'named-symbol-output)
     (list (make-planner-resource-requirement
            :named-symbol (named-symbol-name behavior)
            :detail "Backend spelling for an abstract named symbol.")))
    ((typep behavior 'named-key-output)
     (list (make-planner-resource-requirement
            :named-key (named-key-name behavior)
            :detail "Backend spelling for an abstract named key.")))
    ((typep behavior 'axis-operation-behavior)
     (list (make-planner-resource-requirement
            :axis-operation (axis-operation-axis behavior)
            :detail "A realization for a semantic context-axis operation.")))
    ((typep behavior 'modifier-operation-behavior)
     (list (make-planner-resource-requirement
            :semantic-modifier (modifier-operation-modifier behavior)
            :detail "Application-visible semantic modifier operation.")))
    (t (mapcan #'%planner-output-resource-requirements
               (behavior-children behavior)))))

(defun %planner-deduplicate-resource-requirements (requirements)
  (let ((seen (make-hash-table :test #'equal))
        (result nil))
    (dolist (requirement requirements)
      (let ((key (%planner-key (planner-resource-requirement-kind requirement)
                               (planner-resource-requirement-owner requirement))))
        (unless (gethash key seen)
          (setf (gethash key seen) t)
          (push requirement result))))
    (sort result #'%planner-resource-requirement<)))

(defun %planner-resource-requirements (bindings selectors modifiers)
  (let ((requirements
          (append
           (loop for selector in selectors collect
             (make-planner-resource-requirement
              :selector (selector-requirement-axis selector)
              :detail (format nil "Selector for ~A with states ~{~A~^, ~}."
                              (identifier-name (selector-requirement-axis selector))
                              (mapcar #'identifier-name
                                      (selector-requirement-states selector)))))
           (loop for modifier in modifiers collect
             (make-planner-resource-requirement
              :semantic-modifier (modifier-requirement-modifier modifier)
              :detail "Application-visible semantic modifier."))
           (loop for binding in bindings append
             (loop for entry in (static-table-requirement-entries binding) append
               (%planner-output-resource-requirements
                (normalized-entry-behavior entry)))))))
    (%planner-deduplicate-resource-requirements requirements)))

;;; Capability grading -------------------------------------------------------

(defun %planner-native-static-level-limit (backends)
  "Return the best declared finite native static-table capacity, if any.

This is capability-based rather than a dispatch on a backend class or name.
In the bootstrap pipeline XKB advertises :KEYSYM output and a limit of eight.
Kanata's unbounded layer model is deliberately not treated as evidence that it
can realize arbitrary static semantic products: it does not advertise a native
keysym table capacity.
"
  (loop for backend in backends
        for advertised = (capabilities backend)
        for limit = (capability-native-level-limit advertised)
        when (and (integerp limit) (plusp limit)
                  (capability-supports-p advertised :output :keysym))
          maximize limit))

(defun %planner-binding-realization (binding xkb-level-limit)
  (let ((feature (identifier-name (static-table-requirement-position binding))))
    (cond
      ((not (static-table-requirement-static-p binding))
       (make-realization-result
        feature :unsupported
        :detail "This binding depends on non-product behavior and requires a separately declared lowering."))
      ((null xkb-level-limit)
       (make-realization-result
        feature :unsupported
        :detail "No selected XKB native-level capability can realize this static product table."))
      ((<= (static-table-requirement-state-count binding) xkb-level-limit)
       (make-realization-result
        feature :exact
        :detail (format nil "Static product table has ~D states within the selected XKB capacity of ~D."
                        (static-table-requirement-state-count binding)
                        xkb-level-limit)))
      (t
       ;; This is intentionally unsupported, rather than pretending a
       ;; future Kanata/QMK scheme is an emulation that we have not proved.
       (make-realization-result
        feature :unsupported
        :detail (format nil
                        "Static product table has ~D states; selected XKB capacity is ~D. It requires a separately proven emulation or another target."
                        (static-table-requirement-state-count binding)
                        xkb-level-limit))))))

;;; Deterministic resource allocation ---------------------------------------

(defun %planner-resource-pool (resource-pools kind)
  "Accept either a keyword plist or an alist keyed by resource kind."
  (cond ((null resource-pools) nil)
        ((and (listp resource-pools) (keywordp (first resource-pools)))
         (getf resource-pools kind))
        (t (cdr (assoc kind resource-pools :test #'eq)))))

(defun %planner-copy-pool (pool)
  (unless (typep pool 'resource-pool)
    (error 'planner-refusal :code :invalid-resource-pool
           :detail "Planner resource inventories must contain BACKEND:RESOURCE-POOL objects."))
  (make-resource-pool (resource-pool-name pool)
                      (copy-list (resource-pool-available pool))
                      :reserved (copy-list (resource-pool-reserved pool))))

(defun %planner-copy-resource-pools (resource-pools requirements)
  (let ((kinds (remove-duplicates
                (mapcar #'planner-resource-requirement-kind requirements)
                :test #'eq)))
    (loop for kind in kinds
          for pool = (%planner-resource-pool resource-pools kind)
          when pool collect (cons kind (%planner-copy-pool pool)))))

(defun %planner-reserve-physical-inputs (pools bindings)
  "Keep any resource spellings that are physical inputs out of every pool.

This conservative check catches an incorrectly configured carrier/selector
inventory before allocation.  The original caller-owned pools stay untouched.
"
  (dolist (pair pools)
    (let ((pool (cdr pair)))
      (dolist (binding bindings)
        (let ((input (static-table-requirement-physical-input binding)))
          (when (and (member input (resource-pool-available pool) :test #'equal)
                     (not (resource-used-p pool input)))
            (reserve-resource pool input)))))))

(defun %planner-allocate-resources (requirements pools)
  (let ((allocations nil)
        (results nil)
        (diagnostics nil))
    (dolist (requirement requirements)
      (let ((pool (cdr (assoc (planner-resource-requirement-kind requirement)
                              pools :test #'eq))))
        (when pool
          (handler-case
              (loop for ordinal below (planner-resource-requirement-cardinality requirement)
                    for owner = (if (zerop ordinal)
                                    (%planner-key
                                     (planner-resource-requirement-kind requirement)
                                     (planner-resource-requirement-owner requirement))
                                    (format nil "~A#~D"
                                            (%planner-key
                                             (planner-resource-requirement-kind requirement)
                                             (planner-resource-requirement-owner requirement))
                                            ordinal))
                    for value = (allocate-resource pool owner)
                    do (push (make-planner-allocation
                              requirement
                              (planner-resource-requirement-kind requirement)
                              value)
                             allocations))
            (error (condition)
              (let ((detail (princ-to-string condition)))
                (push detail diagnostics)
                (push (make-realization-result
                       (planner-resource-requirement-owner requirement)
                       :unsupported
                       :detail (format nil "Resource ~A is unavailable: ~A"
                                       (planner-resource-requirement-kind requirement)
                                       detail))
                      results)))))))
    (values (nreverse allocations) (nreverse results) (nreverse diagnostics))))

;;; Public planning protocol -------------------------------------------------

(defun plan-normalized-layout (layout placement &key backends resource-pools)
  "Plan a normalized abstract layout against explicit target capabilities.

LAYOUT and PLACEMENT are semantic model values.  BACKENDS supplies selected
backend capability objects, while RESOURCE-POOLS is an optional, explicit
keyword plist or alist of finite inventories.  Planning copies pools before
reserving inputs or allocating resources, so it is deterministic and cannot
mutate a profile's reusable inventory.

The returned LOWERING-PLAN preserves every normalized table entry.  Tables
over the selected XKB conventional capacity are marked unsupported with an
emulation obligation; no state is truncated, replaced with NoSymbol, or
silently assigned to Kanata/QMK.
"
  (unless (typep layout 'normalized-layout)
    (error 'planner-refusal :code :invalid-normalized-layout
           :detail "Capability planning requires a MODEL:NORMALIZED-LAYOUT."))
  (%planner-check-compatible-placement layout placement)
  (let* ((bindings (%planner-binding-requirements layout placement))
         (selectors (%planner-selector-requirements bindings))
         (modifiers (%planner-modifier-requirements layout))
         (resources (%planner-resource-requirements bindings selectors modifiers))
         (pools (%planner-copy-resource-pools resource-pools resources)))
    (%planner-reserve-physical-inputs pools bindings)
    (multiple-value-bind (allocations resource-results diagnostics)
        (%planner-allocate-resources resources pools)
      (let ((binding-results
              (mapcar (lambda (binding)
                        (%planner-binding-realization
                         binding (%planner-native-static-level-limit backends)))
                      bindings))
            (interaction-results
              (mapcar (lambda (interaction)
                        (make-realization-result
                         (identifier-name (normalized-interaction-name interaction))
                         :unsupported
                         :detail "No target-neutral timed-interaction lowering is claimed by this planner."))
                      (normalized-layout-interactions layout))))
        (make-lowering-plan layout placement bindings selectors modifiers resources
                            allocations
                            (append binding-results resource-results interaction-results)
                            diagnostics)))))

(defun require-planned-realizations (plan &key allow-lossy)
  "Refuse a plan containing any unproved or unapproved realization grade."
  (unless (typep plan 'lowering-plan)
    (error 'planner-refusal :code :invalid-lowering-plan
           :detail "Expected a BACKEND:LOWERING-PLAN."))
  (dolist (result (lowering-plan-realizations plan) plan)
    (case (realization-grade result)
      (:unsupported
       (error 'planner-refusal :code :unsupported-realization
              :feature (realization-feature result)
              :detail (realization-detail result) :plan plan))
      (:lossy
       (unless allow-lossy
         (error 'planner-refusal :code :unapproved-lossy-realization
                :feature (realization-feature result)
                :detail (realization-detail result) :plan plan))))))
