;;;; SPDX-License-Identifier: GPL-3.0-or-later
;;;; Safe whole-normalized-layout adapter for the reference event simulator.

(in-package #:ivory-key.simulate)

;;; This adapter deliberately lowers only the part of a normalized layout that
;;; has an exact representation in the existing finite state machine.  An
;;; ordinary binding becomes a one-position, down-commit SIM-INTERACTION, so
;;; it shares the machine's context snapshot, committed-only latch consumption,
;;; candidate ownership, and trace records with timed interactions.  Binding
;;; positions that also participate in a timed interaction are refused: their
;;; fallback timing is not yet a defined part of the model-to-machine contract.

(defun %normalized-layout-simulation-error (code object control &rest arguments)
  (apply #'%simulation-compilation-error code object control arguments))

(defun %require-normalized-layout (layout)
  (unless (typep layout 'ivory-key.model::normalized-layout)
    (%normalized-layout-simulation-error
     :invalid-normalized-layout layout
     "Expected a normalized layout, got ~S." layout))
  layout)

(defun %normalized-layout-axis-name (axis)
  (model-identifier->simulation-value (ivory-key.model::axis-name axis)))

(defun %normalized-layout-default-axes (layout)
  "Return LAYOUT's declared default context as canonical simulator pairs."
  (mapcar (lambda (axis)
            (cons (%normalized-layout-axis-name axis)
                  (model-identifier->simulation-value
                   (ivory-key.model::axis-default-state axis))))
          (ivory-key.model::normalized-layout-axes layout)))

(defun %normalized-layout-position-names (layout)
  (mapcar (lambda (position)
            (model-identifier->simulation-value
             (ivory-key.model::position-name position)))
          (ivory-key.model::topology-positions
           (ivory-key.model::normalized-layout-topology layout))))

(defun %find-normalized-layout-axis (layout axis-name)
  (find axis-name (ivory-key.model::normalized-layout-axes layout)
        :test #'string=
        :key #'%normalized-layout-axis-name))

(defun %canonical-layout-context-entries (layout entries kind)
  "Validate ENTRIES as named axis/state pairs and canonicalize their strings."
  (unless (listp entries)
    (%normalized-layout-simulation-error
     :invalid-simulation-context entries
     "~A context must be a list of (axis . state) pairs." kind))
  (let ((seen nil)
        (result nil))
    (dolist (entry entries (nreverse result))
      (unless (consp entry)
        (%normalized-layout-simulation-error
         :invalid-simulation-context entry
         "~A context entry must be an (axis . state) pair." kind))
      (let* ((axis-name (model-identifier->simulation-value (car entry)))
             (state-name (model-identifier->simulation-value (cdr entry)))
             (axis (%find-normalized-layout-axis layout axis-name)))
        (unless axis
          (%normalized-layout-simulation-error
           :unknown-simulation-axis entry
           "~A context names undeclared axis ~A." kind axis-name))
        (unless (find state-name (ivory-key.model::axis-states axis)
                      :test #'string=
                      :key #'model-identifier->simulation-value)
          (%normalized-layout-simulation-error
           :unknown-simulation-axis-state entry
           "~A context state ~A is not declared by axis ~A."
           kind state-name axis-name))
        (when (member axis-name seen :test #'string=)
          (%normalized-layout-simulation-error
           :duplicate-simulation-context-axis entries
           "~A context names axis ~A more than once." kind axis-name))
        (push axis-name seen)
        (push (cons axis-name state-name) result)))))

(defun %merged-normalized-layout-axes (layout axes)
  "Overlay validated AXES on the declared defaults without dropping defaults."
  (let ((result (%normalized-layout-default-axes layout)))
    (dolist (entry (%canonical-layout-context-entries layout axes :axis))
      (let ((default (assoc (car entry) result :test #'string=)))
        ;; The context validation above guarantees DEFAULT exists.
        (setf (cdr default) (cdr entry))))
    result))

(defun %normalized-layout-latches (layout latches)
  "Validate initial latches for the one-value-per-axis machine representation."
  (%canonical-layout-context-entries layout latches :latch))

(defun %exact-normalized-entry-actions (entries source)
  "Compile normalized entries into a one-and-only-one context dispatch action.

All variant behavior is compiled before simulation begins.  This prevents an
unsupported branch from being silently absent merely because a particular
event fixture did not reach it.  The callback uses the candidate's anchor-time
axis and latch snapshot, exactly as compiled interaction entries do.
"
  (unless (and (listp entries) entries)
    (%normalized-layout-simulation-error
     :missing-normalized-binding-entry source
     "Normalized binding ~S has no dispatch entries." source))
  (let ((compiled
          (mapcar
           (lambda (entry)
             (unless (typep entry 'ivory-key.model::normalized-binding-entry)
               (%normalized-layout-simulation-error
                :invalid-normalized-binding-entry entry
                "Binding ~S contains an invalid normalized entry ~S." source entry))
             (cons entry
                   (compile-model-behavior
                    (ivory-key.model::normalized-entry-behavior entry))))
           entries)))
    (list
     (make-sim-action
      :kind :callback
      :value
      (lambda (candidate machine)
        (let ((selected nil))
          (dolist (entry compiled)
            (when (%tuple-matches-candidate-p
                   (ivory-key.model::normalized-entry-tuple (car entry)) candidate)
              (when selected
                (%normalized-layout-simulation-error
                 :ambiguous-normalized-binding-context source
                 "Binding ~S has multiple entries for one captured context."
                 source))
              (setf selected entry)))
          (unless selected
            (%normalized-layout-simulation-error
             :unresolved-normalized-binding-context source
             "Binding ~S has no entry for the captured context." source))
          (%apply-compiled-actions machine candidate (cdr selected))))))))

(defun %direct-buffered-route-entry (binding)
  "Return BINDING's sole context-free named-key entry, or NIL.

This remains a small lowering fast path.  Buffered routing itself may use a
validated output-only context table through the ordinary binding callback.
"
  (let ((entries (ivory-key.model::normalized-binding-entries binding)))
    (when (and (null (ivory-key.model::normalized-binding-axes binding))
               (= (length entries) 1))
      (let ((entry (first entries)))
        (when (and (null (ivory-key.model::context-tuple-pairs
                          (ivory-key.model::normalized-entry-tuple entry)))
                   (typep (ivory-key.model::normalized-entry-behavior entry)
                          'ivory-key.model::named-key-output))
          entry)))))

(defun %buffered-output-route-binding-p (binding)
  "Whether BINDING is safe for the finite buffered dispatch boundary.

The route may consult its normalized context table at the eventual dispatch
frontier, but every possible selected behavior must be a closed output or
NONE.  Effects, state operations, commands, and arbitrary callbacks remain
outside this reference-only route contract.
"
  (let ((entries (ivory-key.model::normalized-binding-entries binding)))
    (and entries
         (every (lambda (entry)
                  (typep (ivory-key.model::normalized-entry-behavior entry)
                         '(or ivory-key.model::text-output
                           ivory-key.model::named-key-output
                           ivory-key.model::named-symbol-output
                           ivory-key.model::command-output
                           ivory-key.model::no-output-behavior)))
                entries))))

(defun %compile-normalized-ordinary-binding
    (binding routed-binding dispatch-plan-token)
  "Compile one disjoint normalized ordinary BINDING into exact simulator IR.

The synthetic interaction commits on the position's DOWN event.  This is the
defined activation point for an ordinary binding in this slice; bindings that
need interaction arbitration are rejected by
COMPILE-NORMALIZED-LAYOUT-SIMULATION rather than being given an invented
fallback timing.
"
  (unless (typep binding 'ivory-key.model::normalized-binding)
    (%normalized-layout-simulation-error
     :invalid-normalized-binding binding
     "Expected a normalized binding, got ~S." binding))
  (when (and routed-binding (not (eq routed-binding binding)))
    (%normalized-layout-simulation-error
     :forged-routed-dispatch-binding binding
     "Routed dispatch authority does not retain this exact normalized binding."))
  (when (and routed-binding (null dispatch-plan-token))
    (%normalized-layout-simulation-error
     :missing-routed-dispatch-plan-token binding
     "Routed dispatch binding has no whole-layout plan token."))
  (let* ((position (model-identifier->simulation-value
                    (ivory-key.model::normalized-binding-position binding)))
         (axes (mapcar #'model-identifier->simulation-value
                       (ivory-key.model::normalized-binding-axes binding)))
         (entries (ivory-key.model::normalized-binding-entries binding))
         (name (list :ordinary-binding position)))
    (apply (if routed-binding
               #'make-routed-dispatch-ordinary-interaction
               #'make-sim-interaction)
           (append
            (list :name name
                  :participants (list position)
                  :route-kind :ordinary-binding
                  :consulted-latches axes
                  :arbitration :priority
                  :cases
                  (list
                   (make-sim-case
       :name name
       :pattern (down-pattern position)
       :commit :when-matched
       ;; Direct named keys use a compact emit action.  Other validated
       ;; output-only context tables retain the callback needed to select from
       ;; the axes at a later buffered dispatch frontier.
       :actions
       (let ((entry (%direct-buffered-route-entry binding)))
         (if entry
             (compile-model-behavior
              (ivory-key.model::normalized-entry-behavior entry))
             (%exact-normalized-entry-actions entries binding)))
       :consulted-latches axes)))
            (and routed-binding
                 (list :dispatch-plan-token dispatch-plan-token))))))

(defun compile-normalized-ordinary-binding (binding)
  "Compile BINDING without buffered foreign-route authority."
  (%compile-normalized-ordinary-binding binding nil nil))

(defun %compile-normalized-ordinary-binding-with-route
    (binding routed-binding dispatch-plan-token)
  "Internally compile an identity-proven direct ordinary foreign route."
  (%compile-normalized-ordinary-binding binding routed-binding dispatch-plan-token))

(defun %compile-normalized-ordinary-bindings-with-routes
    (bindings routed-bindings dispatch-plan-token)
  "Internal complete-layout compiler for exact routed binding objects."
  (mapcar (lambda (binding)
            (let ((routed (find binding routed-bindings :test #'eq)))
              (if routed
                  (%compile-normalized-ordinary-binding-with-route
                   binding routed dispatch-plan-token)
                  (compile-normalized-ordinary-binding binding))))
          bindings))

(defun compile-normalized-ordinary-bindings (bindings)
  "Compile ordinary normalized BINDINGS in canonical layout order."
  (%compile-normalized-ordinary-bindings-with-routes bindings nil nil))

(defun %interaction-participant-names (interaction)
  (mapcar #'model-identifier->simulation-value
          (ivory-key.model::normalized-interaction-participants interaction)))

(defun %normalized-layout-binding-at (layout position)
  (find position (ivory-key.model::normalized-layout-bindings layout)
        :test #'ivory-key.model::identifier=
        :key #'ivory-key.model::normalized-binding-position))

(defun %normalized-patch-binding-at (patch position)
  (find position (ivory-key.model::normalized-patch-bindings patch)
        :test #'ivory-key.model::identifier= :key #'car))

(defun %normalized-overlay-ordinary-positions (layout)
  "Return every ordinary position whose resolution can involve a patch.

An overlay-only position is intentionally included: it has a defined behavior
while an appropriate patch is active, but an inactive unresolved position must
still refuse at event execution rather than silently produce no output.
"
  (sort
   (remove-duplicates
    (mapcan (lambda (patch)
              (mapcar #'car (ivory-key.model::normalized-patch-bindings patch)))
            (ivory-key.model::normalized-layout-patches layout))
    :test #'ivory-key.model::identifier=)
   #'ivory-key.model::identifier<))

(defun %normalized-layout-ordinary-positions (layout)
  "Return the canonical union of base and potentially patched positions."
  (sort
   (remove-duplicates
    (append
     (mapcar #'ivory-key.model::normalized-binding-position
             (ivory-key.model::normalized-layout-bindings layout))
     (%normalized-overlay-ordinary-positions layout))
    :test #'ivory-key.model::identifier=)
   #'ivory-key.model::identifier<))

(defun %assert-disjoint-normalized-binding-positions
    (positions interactions buffered-contracts)
  "Refuse ordinary/timed overlap except a selected buffered owner's tap route."
  (dolist (position-identifier positions)
    (let ((position (model-identifier->simulation-value position-identifier)))
      (dolist (interaction interactions)
        (when (member position (%interaction-participant-names interaction)
                      :test #'string=)
          (unless
              (some (lambda (contract)
                      (and (eq interaction
                               (ivory-key.model:interaction-compatibility-contract-interaction
                                contract))
                           (string=
                            position
                            (model-identifier->simulation-value
                             (ivory-key.model:interaction-compatibility-contract-owner
                              contract)))))
                    buffered-contracts)
            (%normalized-layout-simulation-error
             :ordinary-binding-interaction-overlap position-identifier
             "Binding position ~A also participates in interaction ~A; its fallback timing is unsupported."
             position
             (model-identifier->simulation-value
              (ivory-key.model::normalized-interaction-name interaction)))))))))

(defun %normalized-binding-axis-names (binding)
  (unless (typep binding 'ivory-key.model::normalized-binding)
    (%normalized-layout-simulation-error
     :invalid-normalized-binding binding
     "Expected a normalized binding, got ~S." binding))
  (mapcar #'model-identifier->simulation-value
          (ivory-key.model::normalized-binding-axes binding)))

(defun %normalized-overlay-position-bindings (layout position)
  "Return every possible non-transparent binding for patched POSITION.

The result retains normalized patch precedence order.  It contains the base
binding last, when present, because sparse transparent patches fall through to
it under the model's existing normalized resolution rule.
"
  (let ((bindings nil))
    (dolist (patch (ivory-key.model::normalized-layout-patches layout))
      (let ((entry (%normalized-patch-binding-at patch position)))
        (when (and entry (not (eq (cdr entry) :transparent)))
          (unless (typep (cdr entry) 'ivory-key.model::normalized-binding)
            (%normalized-layout-simulation-error
             :invalid-normalized-patch-binding entry
             "Patch ~S has an invalid normalized binding at position ~A."
             patch (model-identifier->simulation-value position)))
          (push (cdr entry) bindings))))
    (let ((base (%normalized-layout-binding-at layout position)))
      (when base (push base bindings)))
    (nreverse bindings)))

(defun %normalized-overlay-position-axis-names (layout position)
  "Return every context axis a patched POSITION could inspect.

Patch activation itself is an axis-state selection, so its patch axis is a
dependency even when the selected patch is transparent.  The result is kept in
declared layout-axis order instead of depending on patch source order.
"
  (let ((needed nil))
    (dolist (patch (ivory-key.model::normalized-layout-patches layout))
      (when (%normalized-patch-binding-at patch position)
        (push (model-identifier->simulation-value
               (ivory-key.model::normalized-patch-axis patch))
              needed)))
    (dolist (binding (%normalized-overlay-position-bindings layout position))
      (setf needed (append (%normalized-binding-axis-names binding) needed)))
    (loop for axis in (ivory-key.model::normalized-layout-axes layout)
          for name = (%normalized-layout-axis-name axis)
          when (member name needed :test #'string=)
            collect name)))

(defun %normalized-overlay-sensitive-axis-names (layout)
  "Return every latch-sensitive axis used by any patched-position dispatch."
  (remove-duplicates
   (mapcan (lambda (position)
             (%normalized-overlay-position-axis-names layout position))
           (%normalized-overlay-ordinary-positions layout))
   :test #'string=))

(defun %normalized-entry-behaviors (entries source)
  (mapcar
   (lambda (entry)
     (unless (typep entry 'ivory-key.model::normalized-binding-entry)
       (%normalized-layout-simulation-error
        :invalid-normalized-binding-entry entry
        "~S contains an invalid normalized binding entry ~S." source entry))
     (ivory-key.model::normalized-entry-behavior entry))
   entries))

(defun %normalized-variant-behaviors (variants source)
  "Extract behavior values from normalized effect variants.

Effects normalize to (context-tuple . behavior) pairs rather than to
NORMALIZED-BINDING-ENTRY objects.  Retain that distinction here so malformed
programmatically constructed IR fails closed.
"
  (mapcar
   (lambda (variant)
     (unless (and (consp variant)
                  (typep (cdr variant) 'ivory-key.model::behavior))
       (%normalized-layout-simulation-error
        :invalid-normalized-effect-entry variant
        "~S contains an invalid normalized effect variant ~S." source variant))
     (cdr variant))
   variants))

(defun %normalized-layout-behaviors (layout)
  "Collect every already-normalized behavior before overlay simulation starts."
  (append
   (mapcan (lambda (binding)
             (%normalized-entry-behaviors
              (ivory-key.model::normalized-binding-entries binding) binding))
           (ivory-key.model::normalized-layout-bindings layout))
   (mapcan (lambda (patch)
             (mapcan (lambda (entry)
                       (if (eq (cdr entry) :transparent)
                           nil
                           (%normalized-entry-behaviors
                            (ivory-key.model::normalized-binding-entries (cdr entry))
                            entry)))
                     (ivory-key.model::normalized-patch-bindings patch)))
           (ivory-key.model::normalized-layout-patches layout))
   (mapcan
    (lambda (interaction)
      (mapcan
       (lambda (candidate)
         (append
          (%normalized-entry-behaviors
           (ivory-key.model::normalized-candidate-entries candidate) candidate)
          (mapcan (lambda (kind)
                    (%normalized-variant-behaviors
                     (getf (ivory-key.model::normalized-candidate-effects candidate) kind)
                     candidate))
                  '(:entry :commit :while :exit :cancel))))
       (ivory-key.model::normalized-interaction-candidates interaction)))
    (ivory-key.model::normalized-layout-interactions layout))))

(defun %behavior-latches-one-of-p (behavior axis-names)
  (unless (typep behavior 'ivory-key.model::behavior)
    (%normalized-layout-simulation-error
     :invalid-normalized-behavior behavior
     "Expected a complete normalized behavior, got ~S." behavior))
  (or (and (typep behavior 'ivory-key.model::axis-operation-behavior)
           (eq (ivory-key.model::axis-operation behavior) :latch)
           (member (model-identifier->simulation-value
                    (ivory-key.model::axis-operation-axis behavior))
                   axis-names :test #'string=))
      (some (lambda (child) (%behavior-latches-one-of-p child axis-names))
            (ivory-key.model::behavior-children behavior))))

(defun %assert-overlay-latch-transitions-safe (layout)
  "Reject dynamic latches that the finite dispatch IR cannot consume exactly.

The machine records one static consulted-latch set per candidate.  An overlay
dispatch chooses a binding only after reading its captured patch state, so a
latch for an axis used only by an unselected lower-precedence patch would be
over-consumed by that static set.  State-setting operations remain executable;
latch transitions on these conditionally inspected axes are refused instead of
being given a false exact interpretation.
"
  (let ((sensitive-axes (%normalized-overlay-sensitive-axis-names layout)))
    (when (and sensitive-axes
               (some (lambda (behavior)
                       (%behavior-latches-one-of-p behavior sensitive-axes))
                     (%normalized-layout-behaviors layout)))
      (%normalized-layout-simulation-error
       :unsupported-overlay-latch-transition layout
       "An overlay dispatch can conditionally inspect latch-sensitive axis ~{~A~^, ~}; dynamic latch transitions are unsupported."
       sensitive-axes))))

(defun %assert-overlay-input-latches-safe (layout latches)
  "Reject initial latches whose conditional overlay use would over-consume."
  (let ((sensitive-axes (%normalized-overlay-sensitive-axis-names layout)))
    (dolist (latch latches)
      (when (member (car latch) sensitive-axes :test #'string=)
        (%normalized-layout-simulation-error
         :unsupported-overlay-latch-context latch
         "Initial latch for axis ~A cannot be simulated through conditional overlay dispatch."
         (car latch))))))

(defun %normalized-patch-active-for-candidate-p (patch candidate)
  "Whether PATCH's declared selector state is present in CANDIDATE's snapshot."
  (let ((actual (%candidate-context-value
                 candidate
                 (model-identifier->simulation-value
                  (ivory-key.model::normalized-patch-axis patch)))))
    (and actual
         (string= actual
                  (model-identifier->simulation-value
                   (ivory-key.model::normalized-patch-state patch))))))

(defun %compile-normalized-overlay-ordinary-binding
    (layout position &optional dispatch-plan-token)
  "Compile one potentially patched ordinary binding into exact simulator IR.

All behavior variants are compiled before execution.  At each candidate's
anchor snapshot, the callback walks the normalizer's already precedence-sorted
patches, skips absent and transparent entries, and otherwise dispatches the
first active binding.  It then falls through to the base binding.  This is the
same sparse-patch rule as NORMALIZED-LAYOUT-BINDING-FOR-CONTEXT, expressed in
the simulator's string-valued candidate context without backend lowering.
"
  (let* ((patches
           (remove-if-not (lambda (patch)
                            (%normalized-patch-binding-at patch position))
                          (ivory-key.model::normalized-layout-patches layout)))
         (compiled-patches
           (mapcar
            (lambda (patch)
              (let ((entry (%normalized-patch-binding-at patch position)))
                (cond
                  ((eq (cdr entry) :transparent)
                   (list patch :transparent nil))
                  ((typep (cdr entry) 'ivory-key.model::normalized-binding)
                   (list patch :binding
                         (%exact-normalized-entry-actions
                          (ivory-key.model::normalized-binding-entries (cdr entry))
                          entry)))
                  (t
                   (%normalized-layout-simulation-error
                    :invalid-normalized-patch-binding entry
                    "Patch ~S has an invalid normalized binding at position ~A."
                    patch (model-identifier->simulation-value position))))))
            patches))
         (base (%normalized-layout-binding-at layout position))
         (base-actions
           (and base
                (%exact-normalized-entry-actions
                 (ivory-key.model::normalized-binding-entries base) base)))
         (position-name (model-identifier->simulation-value position))
         (name (list :ordinary-overlay-binding position-name))
         (consulted-latches (%normalized-overlay-position-axis-names layout position)))
    (apply
     (if dispatch-plan-token
         #'make-routed-dispatch-ordinary-interaction
         #'make-sim-interaction)
     (append
      (list
       :name name
       :participants (list position-name)
       :route-kind :overlay-binding
       :consulted-latches consulted-latches
       :arbitration :priority
       :cases
       (list
      (make-sim-case
       :name name
       :pattern (down-pattern position-name)
       :commit :when-matched
       :actions
       (list
        (make-sim-action
         :kind :callback
         :value
         (lambda (candidate machine)
           (let ((selected nil)
                 (selected-name :base))
             (dolist (descriptor compiled-patches)
               (when (and (null selected)
                          (%normalized-patch-active-for-candidate-p
                           (first descriptor) candidate)
                          (eq (second descriptor) :binding))
                 (setf selected (third descriptor)
                       selected-name
                       (model-identifier->simulation-value
                        (ivory-key.model::normalized-patch-name (first descriptor))))))
             (unless selected
               (setf selected base-actions))
             (unless selected
               (%normalized-layout-simulation-error
                :unresolved-normalized-overlay-context position
                "Position ~A has no active overlay or base binding for its captured context."
                position-name))
             ;; Reuse the normalizer's deterministic precedence rule but make
             ;; the selected semantic source explicit in the shared event trace.
             (trace-entry machine :action
                          :interaction (simulation-candidate-interaction candidate)
                          :case (simulation-candidate-case candidate)
                          :candidate candidate
                          :details (list :overlay-selection selected-name
                                         :position position-name))
             (%apply-compiled-actions machine candidate selected)))))
       :consulted-latches consulted-latches)))
      (and dispatch-plan-token
           (list
            :dispatch-plan-token dispatch-plan-token
            :route-active-p
            (lambda (machine)
              (some
               (lambda (descriptor)
                 (and (eq (second descriptor) :binding)
                      (string=
                       (simulator-axis-value
                        machine
                        (model-identifier->simulation-value
                         (ivory-key.model:normalized-patch-axis
                          (first descriptor))))
                       (model-identifier->simulation-value
                        (ivory-key.model:normalized-patch-state
                         (first descriptor))))))
               compiled-patches))))))))

(defun compile-normalized-overlay-ordinary-bindings
    (layout &key dispatch-plan-token)
  "Compile canonical ordinary bindings with sparse normalized patch dispatch."
  (mapcar
   (lambda (position)
     (if (some (lambda (patch)
                 (%normalized-patch-binding-at patch position))
               (ivory-key.model::normalized-layout-patches layout))
         (%compile-normalized-overlay-ordinary-binding
          layout position dispatch-plan-token)
         (if dispatch-plan-token
             (%compile-normalized-ordinary-binding-with-route
              (%normalized-layout-binding-at layout position)
              (%normalized-layout-binding-at layout position)
              dispatch-plan-token)
             (compile-normalized-ordinary-binding
              (%normalized-layout-binding-at layout position)))))
   (%normalized-layout-ordinary-positions layout)))

(defun %assert-buffered-route-bindings-safe (layout)
  "Prove every possible base/patch route is one closed output context table."
  (dolist (position (%normalized-layout-ordinary-positions layout))
    (dolist (patch (ivory-key.model::normalized-layout-patches layout))
      (let ((entry (%normalized-patch-binding-at patch position)))
        (when (and entry
                   (not (eq (cdr entry) :transparent))
                   (not (and (typep (cdr entry) 'ivory-key.model::normalized-binding)
                             (%buffered-output-route-binding-p (cdr entry)))))
          (%normalized-layout-simulation-error
           :unsupported-buffered-foreign-overlay entry
           "Buffered patch route at ~A must contain only closed output behaviors."
           (model-identifier->simulation-value position)))))
    (let ((base (%normalized-layout-binding-at layout position)))
      (unless (or base
                  (some (lambda (patch)
                          (let ((entry (%normalized-patch-binding-at patch position)))
                            (and entry (not (eq (cdr entry) :transparent)))))
                        (ivory-key.model::normalized-layout-patches layout)))
        (%normalized-layout-simulation-error
         :unsupported-buffered-overlay-without-fallback position
         "Buffered dispatch position ~A has neither a base nor concrete patch binding."
         (model-identifier->simulation-value position)))
      (when (and base (not (%buffered-output-route-binding-p base)))
        (%normalized-layout-simulation-error
         :unsupported-buffered-foreign-route base
         "Buffered dispatch requires every behavior at position ~A to be text, named-key, named-symbol, command, or none."
         (model-identifier->simulation-value position))))))

(defun %assert-buffered-owner-routes-safe (layout contracts)
  "Require every selected owner to retain one explicit safe ordinary tap route."
  (dolist (contract (%buffered-contracts contracts))
    (let* ((owner (ivory-key.model:interaction-compatibility-contract-owner contract))
           (position (model-identifier->simulation-value owner))
           (binding (%normalized-layout-binding-at layout owner)))
      (unless binding
        (%normalized-layout-simulation-error
         :missing-buffered-owner-tap-route owner
         "Selected buffered owner ~A has no ordinary binding for its tap route."
         position))
      (unless (%buffered-output-route-binding-p binding)
        (%normalized-layout-simulation-error
         :unsupported-buffered-owner-tap-route binding
         "Selected buffered owner ~A must have only closed output tap behaviors."
         position)))))

(defun %buffered-route-axis-names (layout)
  (remove-duplicates
   (mapcan (lambda (position)
             (%normalized-overlay-position-axis-names layout position))
           (%normalized-layout-ordinary-positions layout))
   :test #'string=))

(defun %assert-buffered-route-latch-transitions-safe (layout)
  (let ((axes (%buffered-route-axis-names layout)))
    (when (some (lambda (behavior)
                  (%behavior-latches-one-of-p behavior axes))
                (%normalized-layout-behaviors layout))
      (%normalized-layout-simulation-error
       :unsupported-buffered-route-latch-transition layout
       "Buffered foreign routing cannot inspect dynamically latched axes ~{~A~^, ~}."
       axes))))

(defun %interaction-compatibility-contracts (layout policy)
  (and policy
       (ivory-key.model:derive-interaction-compatibility-contracts policy layout)))

(defun %buffered-contracts (contracts)
  (remove-if-not
   (lambda (contract)
     (typep contract 'ivory-key.model:pending-foreign-interval-contract))
   contracts))

(defun %assert-buffered-contract-owner-disjoint (contracts interactions)
  "Refuse a selected pending owner shared by any other timed interaction.

The raw machine keeps the same guard for hand-built IR.  Whole-layout
compilation can prove the overlap earlier, before publishing partial simulator
IR or allowing one selected owner to be observed as another's foreign key.
"
  (dolist (contract (%buffered-contracts contracts))
    (let* ((selected (ivory-key.model:interaction-compatibility-contract-interaction
                      contract))
           (owner (model-identifier->simulation-value
                   (ivory-key.model:interaction-compatibility-contract-owner contract))))
      (dolist (interaction interactions)
        (when (and (not (eq interaction selected))
                   (member owner (%interaction-participant-names interaction)
                           :test #'string=))
          (%normalized-layout-simulation-error
           :selected-owner-interaction-overlap interaction
           "Selected buffered owner ~A also participates in interaction ~A; pending routing has no multi-owner semantics."
           owner
           (model-identifier->simulation-value
            (ivory-key.model::normalized-interaction-name interaction))))))))

(defun compile-normalized-layout-simulation
    (layout &key interaction-compatibility-policy)
  "Compile a safe whole-layout slice into simulator interactions and defaults.

The first value is the unified list of synthetic ordinary-binding and compiled
timed interactions.  The second value is the complete declared default axis
alist.  Sparse normalized overlays select their active patch binding against a
candidate's anchor-time axis snapshot using the normalizer's declared
precedence and transparent fall-through rule.  Dynamic latches for axes that
such a conditional dispatch could inspect remain a refusal; ordinary binding
positions that participate in timed interactions remain refused because their
fallback ownership is not specified.
"
  (%require-normalized-layout layout)
  (let* ((interactions (ivory-key.model::normalized-layout-interactions layout))
         (contracts (%interaction-compatibility-contracts
                     layout interaction-compatibility-policy))
         (buffered-contracts (%buffered-contracts contracts))
         (dispatch-plan-token (and buffered-contracts
                                   (make-symbol "BUFFERED-DISPATCH-PLAN"))))
    (%assert-overlay-latch-transitions-safe layout)
    (when buffered-contracts
      (%assert-buffered-route-bindings-safe layout)
      (%assert-buffered-owner-routes-safe layout contracts)
      (%assert-buffered-route-latch-transitions-safe layout)
      (%assert-buffered-contract-owner-disjoint contracts interactions))
    (%assert-disjoint-normalized-binding-positions
     (%normalized-layout-ordinary-positions layout) interactions buffered-contracts)
    (values (append (if buffered-contracts
                       (compile-normalized-overlay-ordinary-bindings
                        layout :dispatch-plan-token dispatch-plan-token)
                       (compile-normalized-overlay-ordinary-bindings layout))
                    (%compile-normalized-interactions-with-contracts
                     interactions
                     :interaction-compatibility-contracts contracts
                     :dispatch-plan-token dispatch-plan-token))
            (%normalized-layout-default-axes layout))))

(defun %normalized-layout-event (layout event active-positions)
  "Validate EVENT belongs to LAYOUT and use canonical position spelling."
  (unless (typep event 'timed-event)
    (%normalized-layout-simulation-error
     :invalid-simulation-event event "Expected a timed event, got ~S." event))
  (when (eq (timed-event-kind event) :deadline)
    (%normalized-layout-simulation-error
     :generated-deadline-input event
     "Deadline events are generated by the simulator, not supplied by a layout fixture."))
  (let ((position (model-identifier->simulation-value (timed-event-position event))))
    (unless (member position (%normalized-layout-position-names layout) :test #'string=)
      (%normalized-layout-simulation-error
       :unknown-simulation-position event
       "Event position ~A is not present in the layout topology." position))
    (unless (member position active-positions :test #'string=)
      (%normalized-layout-simulation-error
       :unbound-simulation-position event
       "Event position ~A has neither an ordinary binding nor an interaction participant."
       position))
    (make-timed-event (timed-event-time event) (timed-event-kind event) position
                      :data (timed-event-data event))))

(defun %layout-simulation-active-positions (interactions)
  (remove-duplicates
   (mapcan (lambda (interaction)
             (copy-list (sim-interaction-participants interaction)))
           interactions)
   :test #'string=))

(defun simulate-normalized-layout-events
    (layout events &key axes latches until interaction-compatibility-policy)
  "Simulate normalized LAYOUT against explicit timed EVENTS and semantic context.

AXES overrides declared defaults only for named, declared axis states; LATCHES
uses the same validation and supplies at most one current latch per axis.  All
ordinary-binding and timed-interaction transitions use the existing simulator,
so candidate ownership, commitment-only latch consumption, and full trace
records are preserved.  Sparse overlays use the normalized patch activation,
precedence, and transparent fall-through rules.  Latches on axes conditionally
inspected by an overlay remain a refusal, as do ordinary/interaction position
overlap, unknown input positions, unsupported model behavior, and unsupported
temporal patterns.
"
  (%require-normalized-layout layout)
  (let ((normalized-latches (%normalized-layout-latches layout latches)))
    (%assert-overlay-input-latches-safe layout normalized-latches)
    (when (and interaction-compatibility-policy
               (eq (ivory-key.model:realization-interaction-compatibility-policy-mode
                    interaction-compatibility-policy)
                   :kanata-1-12-buffered))
      (dolist (latch normalized-latches)
        (when (member (car latch) (%buffered-route-axis-names layout) :test #'string=)
          (%normalized-layout-simulation-error
           :unsupported-buffered-route-latch-context latch
           "Buffered foreign routing cannot inspect initial latch for axis ~A."
           (car latch)))))
    (multiple-value-bind (interactions defaults)
      (compile-normalized-layout-simulation
       layout :interaction-compatibility-policy interaction-compatibility-policy)
      (declare (ignore defaults))
      (let ((active-positions (%layout-simulation-active-positions interactions)))
        (simulate-events interactions
                         (mapcar (lambda (event)
                                   (%normalized-layout-event
                                    layout event active-positions))
                                 events)
                         :axes (%merged-normalized-layout-axes layout axes)
                         :latches normalized-latches
                         :until until)))))

(defun simulate-model-layout-events
    (layout events &key axes latches until interaction-compatibility-policy)
  "Normalize a decoded model LAYOUT, then simulate its supported whole-layout slice.

This is the decoded-layout convenience entry point.  It does not reparse
source, lower a backend, deploy, or weaken any refusal from normalization or
SIMULATE-NORMALIZED-LAYOUT-EVENTS.
"
  (unless (typep layout 'ivory-key.model::layout)
    (%normalized-layout-simulation-error
     :invalid-layout layout "Expected a model layout, got ~S." layout))
  (simulate-normalized-layout-events
   (ivory-key.model::normalize-layout layout) events
   :axes axes :latches latches :until until
   :interaction-compatibility-policy interaction-compatibility-policy))
