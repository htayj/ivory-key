;;;; SPDX-License-Identifier: GPL-3.0-or-later
;;;; Dependency-free tests for resource allocation and safe backend emission.

(in-package #:ivory-key.tests)

(defun backend-test-entry (&key (position "q")
                                (xkb-code "AD01")
                                (xkb-outputs '("q" "Q"))
                                (kanata-code "q")
                                (kanata-outputs '("q")))
  (make-instance 'ivory-key.backend:key-entry
                 :position position
                 :physical-code (list :xkb xkb-code :kanata kanata-code)
                 :outputs (list :xkb xkb-outputs :kanata kanata-outputs)))

(defun backend-test-request (&key (name "test-layout") entries interactions
                                  modifiers metadata)
  (make-instance 'ivory-key.backend:lowering-request
                 :name name :entries entries :interactions interactions
                 :modifiers modifiers :metadata metadata))

(defun backend-test-selector-context (case script plane)
  (ivory-key.model:make-context-tuple
   (list (cons "case" case) (cons "script" script) (cons "plane" plane))))

(defun backend-test-observed-selector-policy
    (&key (group-one-type :four-level-alphabetic))
  (ivory-key.model:make-realization-selector-policy
   (list (ivory-key.model:make-realization-static-type
          "q" group-one-type :two-level))
   (list
    (ivory-key.model:make-realization-context-selector
     "case" "shifted" :shift :consumed :core-shift)
    (ivory-key.model:make-realization-context-selector
     "script" "greek" :level-three :consumed :consumed-level-three)
    (ivory-key.model:make-realization-context-selector
     "plane" "top" :group-two :group-action
     :libxkbcommon-depressed-group-two-with-visible-level-three))
   (list
    (ivory-key.model:make-realization-direct-carrier
     "greek" "script" "greek" 85 :zeha)
    (ivory-key.model:make-realization-direct-carrier
     "top" "plane" "top" 84 :lvl3))))

(defun backend-test-observed-selector-entry
    (&key (position "q") (xkb-code "AD01")
          (outputs '("q" "Q" "Greek_theta" "Greek_THETA"
                     "upcaret" "NoSymbol" "upcaret" "NoSymbol")))
  (make-instance
   'ivory-key.backend:key-entry
   :position position
   :physical-code (list :xkb xkb-code)
   :outputs (list :xkb outputs)
   :sources
   (mapcar (lambda (states)
             (ivory-key.backend:make-key-entry-source
              (apply #'backend-test-selector-context states)))
           '(("plain" "roman" "base")
             ("shifted" "roman" "base")
             ("plain" "greek" "base")
             ("shifted" "greek" "base")
             ("plain" "roman" "top")
             ("shifted" "roman" "top")
             ("plain" "greek" "top")
             ("shifted" "greek" "top")))))

(defun backend-test-observed-selector-request
    (&key entries (group-one-type :four-level-alphabetic))
  (backend-test-request
   :name "observed-selectors"
   :entries (or entries (list (backend-test-observed-selector-entry)))
   :metadata
   (list :selector-policy
         (backend-test-observed-selector-policy :group-one-type group-one-type))))

(defun pipeline-artifact-of-kind (result kind)
  (find kind (ivory-key.backend:pipeline-result-artifacts result)
        :key #'ivory-key.backend:pipeline-artifact-kind))

(deftest backend-capabilities-describe-the-complete-planning-boundary
  (let ((xkb (ivory-key.backend:capabilities
              (ivory-key.backend:make-xkb-backend)))
        (kanata (ivory-key.backend:capabilities
                 (ivory-key.backend:make-kanata-backend)))
        (qmk (ivory-key.backend:capabilities
              (ivory-key.backend:make-qmk-backend))))
    (is (ivory-key.backend:capability-supports-p
         xkb :input :xkb-key-name))
    (is (ivory-key.backend:capability-supports-p
         xkb :carrier :xkb-keycode-input))
    (is (null (ivory-key.backend:capability-clock-semantics kanata)))
    (is (null (ivory-key.backend:capability-lifecycle-semantics kanata)))
    (is (null (ivory-key.backend:capability-interaction-features kanata)))
    (is (ivory-key.backend:capability-supports-p
         qmk :platform :qmk-firmware-checkout))
    ;; Empty structured categories are meaningful: no backend may gain an
    ;; abstract operation merely because its native platform has one.
    (is (null (ivory-key.backend:capability-context-axis-operations xkb)))
    (is (null (ivory-key.backend:capability-patch-operations kanata)))
    (is (null (ivory-key.backend:capability-arbitration-semantics qmk)))))

(deftest backend-resource-allocation-is-stable-and-exclusive
  (let ((pool (ivory-key.backend:make-resource-pool
               "carrier" '("C1" "C2" "C3") :reserved '("C2"))))
    (is-equal "C1" (ivory-key.backend:allocate-resource pool :first))
    (is-equal "C1" (ivory-key.backend:allocate-resource pool :first))
    (is-equal "C3" (ivory-key.backend:reserve-resource pool "C3"))
    (is-equal '((:first . "C1"))
              (ivory-key.backend:allocation-alist pool))
    (signals error
      (ivory-key.backend:reserve-resource pool "C1"))
    (signals error
      (ivory-key.backend:allocate-resource pool :second))))

(deftest backend-resource-pools-reject-duplicate-capacity
  (signals error
    (ivory-key.backend:make-resource-pool "carrier" '("C1" "C1"))))

(deftest backend-xkb-rejects-emission-injection-values
  (let ((backend (ivory-key.backend:make-xkb-backend)))
    (signals error
      (ivory-key.backend:lower-request
       backend
       (backend-test-request :name "safe\"; include \"evil")))
    (signals error
      (ivory-key.backend:lower-request
       backend
       (backend-test-request
        :entries (list (backend-test-entry :xkb-code "AD01> }; include \"evil")))))
    (signals error
      (ivory-key.backend:lower-request
       backend
       (backend-test-request
        :entries (list (backend-test-entry :xkb-outputs '("q] }; include \"evil"))))))))

(deftest backend-kanata-rejects-emission-injection-values
  (let ((backend (ivory-key.backend:make-kanata-backend)))
    ;; A layer name is emitted in DEFLAYER and must be validated just like
    ;; source and output tokens.
    (signals error
      (ivory-key.backend:lower-request
       backend
       (backend-test-request :name "safe) (deflayer injected")))
    (signals error
      (ivory-key.backend:lower-request
       backend
       (backend-test-request
        :entries (list (backend-test-entry :kanata-code "q) (deflayer injected")))))
    (signals error
      (ivory-key.backend:lower-request
       backend
       (backend-test-request
        :entries (list (backend-test-entry :kanata-outputs '("q) (deflayer injected"))))))))

(deftest backend-fidelity-refusal-requires-an-explicit-permitted-grade
  (is (ivory-key.backend:require-permitted-realizations
       (list (ivory-key.backend:make-realization-result :direct :exact))))
  (is (ivory-key.backend:require-permitted-realizations
       (list (ivory-key.backend:make-realization-result :workaround :emulated))))
  (signals error
    (ivory-key.backend:require-permitted-realizations
     (list (ivory-key.backend:make-realization-result :approximation :lossy))))
  (is (ivory-key.backend:require-permitted-realizations
       (list (ivory-key.backend:make-realization-result :approximation :lossy))
       :allow-lossy t))
  (signals error
    (ivory-key.backend:require-permitted-realizations
     (list (ivory-key.backend:make-realization-result :missing :unsupported))))
  (signals error
    (ivory-key.backend:compile-xkb-kanata-request
     (backend-test-request :interactions '(generic-tap-hold)))))

(deftest backend-kanata-interaction-compatibility-is-narrow-and-fails-closed
  "Only policy-named Manna/Kanata instances receive mode-specific refusals."
  (let ((backend (ivory-key.backend:make-kanata-backend)))
    ;; NIL remains the existing target-generic refusal.
    (let* ((plan (ivory-key.backend:lower-request
                  backend (backend-test-request :interactions '(ordinary-tap-hold))))
           (results (ivory-key.backend::kanata-plan-realizations plan))
           (interaction (find 'ordinary-tap-hold results
                              :key #'ivory-key.backend:realization-feature)))
      (is interaction)
      (is-equal :unsupported (ivory-key.backend:realization-grade interaction))
      (is (search "Generic interaction lowering"
                  (ivory-key.backend:realization-detail interaction)))
      (is (null (find :interaction-compatibility-policy results
                      :key #'ivory-key.backend:realization-feature))))
    (dolist (case
             '((:modern-no-delay . "modern no-delay")
               (:kanata-1-12-buffered . "inspection-only actions")))
      (let* ((policy
               (ivory-key.model::make-realization-interaction-compatibility-policy
                (car case) '("manna-tap-hold")))
             (plan
               (ivory-key.backend:lower-request
                backend
                (backend-test-request
                 :interactions '("manna-tap-hold" "ordinary-tap-hold")
                 :metadata (list :interaction-compatibility-policy policy))))
             (results (ivory-key.backend::kanata-plan-realizations plan))
             (selected
               (find "manna-tap-hold" results :test #'string=
                     :key #'ivory-key.backend:realization-feature))
             (unlisted
               (find "ordinary-tap-hold" results :test #'string=
                     :key #'ivory-key.backend:realization-feature)))
        (is selected)
        (is unlisted)
        (is-equal :unsupported
                  (ivory-key.backend:realization-grade selected))
        (is-equal :unsupported
                  (ivory-key.backend:realization-grade unlisted))
        (is (search (cdr case)
                    (ivory-key.backend:realization-detail selected)))
        (is (search "Generic interaction lowering"
                    (ivory-key.backend:realization-detail unlisted)))
        ;; An inspectable plan is still non-emittable, so neither mode can
        ;; accidentally become a parseable Kanata action claim.
        (signals error
          (ivory-key.backend:emit-plan-to-string backend plan)))
      ;; A raw host symbol is not coerced/interned into an intended source
      ;; instance.  It remains target-generic even when its spelling matches.
      (let* ((policy
               (ivory-key.model::make-realization-interaction-compatibility-policy
                (car case) '("manna-tap-hold")))
             (plan
               (ivory-key.backend:lower-request
                backend
                (backend-test-request
                 :interactions '(manna-tap-hold)
                 :metadata (list :interaction-compatibility-policy policy))))
             (result
               (find-if
                (lambda (candidate)
                  (search "Generic interaction lowering"
                          (ivory-key.backend:realization-detail candidate)))
                (ivory-key.backend::kanata-plan-realizations plan))))
        (is (search "Generic interaction lowering"
                    (ivory-key.backend:realization-detail result))))
      ;; A selected target absent from the direct request cannot be ignored.
      ;; In particular, a static-only request must not emit a Kanata artifact
      ;; merely because no interaction happened to be carried into its IR.
      (let* ((policy
               (ivory-key.model::make-realization-interaction-compatibility-policy
                (car case) '("z-missing-target" "a-missing-target")))
             (plan
               (ivory-key.backend:lower-request
                backend
                (backend-test-request
                 :entries (list (backend-test-entry))
                 :metadata (list :interaction-compatibility-policy policy))))
             (results (ivory-key.backend::kanata-plan-realizations plan))
             (missing-results
               (remove-if-not
                (lambda (result)
                  (member (ivory-key.backend:realization-feature result)
                          '("a-missing-target" "z-missing-target")
                          :test #'string=))
                results)))
        (is-equal '("a-missing-target" "z-missing-target")
                  (mapcar #'ivory-key.backend:realization-feature missing-results))
        (is (every (lambda (result)
                     (and (eq :unsupported
                              (ivory-key.backend:realization-grade result))
                          (search "no matching interaction"
                                  (ivory-key.backend:realization-detail result))))
                   missing-results))
        (signals error
          (ivory-key.backend:emit-plan-to-string backend plan))))
    (signals error
      (ivory-key.backend:lower-request
       backend
       (backend-test-request
        :interactions '("invalid-policy")
        :metadata
        (list :interaction-compatibility-policy "kanata-1-12-buffered"))))))

(defun backend-test-kanata-action-signals (code thunk)
  (handler-case
      (progn
        (funcall thunk)
        (error "Expected Kanata action validation error ~S, but none was signaled." code))
    (ivory-key.backend::kanata-action-validation-error (condition)
      (is-equal code
                (ivory-key.backend::kanata-action-validation-error-code condition)))))

(defun backend-test-buffered-contract-and-policy (&optional (name "tap-hold-case-f"))
  "Return one actual MODEL-derived evidence contract and its scoped policy."
  (let* ((layout (pending-input-normalized-layout))
         (policy (pending-input-policy :names (list name)))
         (contract
           (first (ivory-key.model:derive-interaction-compatibility-contracts
                   policy layout))))
    (values contract policy)))

(defun backend-test-buffered-action (contract &key (foreign-position "q")
                                              (foreign-token "q"))
  "Build one complete inert action from a real buffered evidence contract."
  (let* ((owner (ivory-key.model::interaction-compatibility-contract-owner contract))
         (tap (ivory-key.model::release-trigger-interaction-compatibility-contract-tap-key
               contract))
         (deadline
           (ivory-key.model::release-trigger-interaction-compatibility-contract-deadline
            contract))
         (signature
           (ivory-key.model::release-trigger-interaction-compatibility-contract-held-effect-signature
            contract))
         (owner-placement
           (ivory-key.backend::make-kanata-owner-placement owner
                                                            (ivory-key.model:identifier-name owner)
                                                            :origin
                                                            (ivory-key.model::interaction-compatibility-contract-origin
                                                             contract)))
         ;; The token is a deliberately explicit test allocation.  Compiler
         ;; inspection has no corresponding realization field and therefore
         ;; refuses rather than manufacturing this value.
         (hold (ivory-key.backend::make-kanata-modifier-hold-action
                (ivory-key.model::interaction-compatibility-held-effect-signature-identity
                 signature)
                "lshift"
                :state
                (ivory-key.model::interaction-compatibility-held-effect-signature-state
                 signature)))
         (tap-action (ivory-key.backend::make-kanata-key-action
                      tap (ivory-key.model:identifier-name tap)))
         (route
           (ivory-key.backend::make-kanata-direct-route-reference
            foreign-position foreign-token
            (ivory-key.backend::make-kanata-key-action foreign-position foreign-token)
            :origin (ivory-key.model::interaction-compatibility-contract-origin contract))))
    (ivory-key.backend::make-kanata-buffered-interaction-action
     contract
     (format nil "alias-~A"
             (ivory-key.model:identifier-name
              (ivory-key.model:normalized-interaction-name
               (ivory-key.model::interaction-compatibility-contract-interaction contract))))
     owner-placement
     (ivory-key.backend::make-kanata-tap-hold-release-action
      deadline deadline tap-action hold)
     (list route)
     (ivory-key.backend::make-kanata-defcfg-requirements
      :process-unmapped-keys t :concurrent-tap-hold :required)
     :provenance (ivory-key.model::interaction-compatibility-contract-origin contract))))

(defun backend-test-forged-buffered-contract
    (contract &key empty-candidates empty-role-references)
  "Return a public-CLOS counterfeit of CONTRACT without MODEL derivation.

This intentionally copies the old ledger-visible fields.  The action boundary
must nevertheless reject it: an empty candidate graph cannot be reconstructed
from the interaction name, and empty role references cannot be treated as the
three normalized candidates MODEL originally proved.
"
  (let* ((interaction
           (ivory-key.model::interaction-compatibility-contract-interaction contract))
         (forged-interaction
           (if empty-candidates
               (pending-input-clone-interaction interaction :candidates nil)
               interaction)))
    (make-instance
     'ivory-key.model::pending-foreign-interval-contract
     :mode :kanata-1-12-buffered
     :interaction forged-interaction
     :owner (ivory-key.model::interaction-compatibility-contract-owner contract)
     :origin (ivory-key.model::interaction-compatibility-contract-origin contract)
     :role-references
     (if empty-role-references
         nil
         (ivory-key.model::release-trigger-interaction-compatibility-contract-role-references
          contract))
     :deadline
     (ivory-key.model::release-trigger-interaction-compatibility-contract-deadline
      contract)
     :capture-name
     (ivory-key.model::release-trigger-interaction-compatibility-contract-capture-name
      contract)
     :held-effect-signature
     (ivory-key.model::release-trigger-interaction-compatibility-contract-held-effect-signature
      contract)
     :tap-key
     (ivory-key.model::release-trigger-interaction-compatibility-contract-tap-key
      contract)
     :provenance
     (ivory-key.model::release-trigger-interaction-compatibility-contract-provenance
      contract))))

(defun backend-test-buffered-plan (policy contracts actions)
  "Lower an inert direct protocol request without ever attempting emission."
  (let ((positions nil))
    (dolist (contract contracts)
      (push (ivory-key.model:identifier-name
             (ivory-key.model::interaction-compatibility-contract-owner contract))
            positions))
    (dolist (action actions)
      (dolist (route (ivory-key.backend::kanata-buffered-interaction-action-foreign-routes
                      action))
        (push (ivory-key.model:identifier-name
               (ivory-key.backend::kanata-direct-route-reference-position route))
              positions)))
    (setf positions (sort (remove-duplicates positions :test #'string=) #'string<))
    (ivory-key.backend:lower-request
     (ivory-key.backend:make-kanata-backend)
     (backend-test-request
      :entries (list (backend-test-entry))
      :interactions contracts
      :metadata (list :interaction-compatibility-policy policy
                      :kanata-buffered-actions actions
                      :kanata-source-order
                      (mapcar (lambda (position) (cons position position)) positions))))))

(defun backend-test-kanata-plan-dump (plan)
  "Return the compiler's inspection-only Kanata plan dump for PLAN."
  (with-output-to-string (stream)
    (ivory-key.cli::%write-kanata-plan-inspection stream plan)))

(deftest backend-kanata-buffered-action-handoff-is-typed-canonical-and-inert
  "A real evidence contract may be inspected but cannot make a Kanata artifact."
  (multiple-value-bind (contract policy)
      (backend-test-buffered-contract-and-policy)
    (let* ((action (backend-test-buffered-action contract))
           (data (ivory-key.backend::kanata-buffered-interaction-action-canonical-data
                  action))
           (backend (ivory-key.backend:make-kanata-backend))
           (plan
             (ivory-key.backend:lower-request
              backend
              (backend-test-request
               :entries (list (backend-test-entry))
               :interactions (list contract)
               :metadata
               (list :interaction-compatibility-policy policy
                     :kanata-buffered-actions (list action)
                     :kanata-source-order '(("f" . "f") ("q" . "q")))))))
      ;; Canonical data contains semantic identities and known/unknown
      ;; provenance disposition only: no object address, source pathname, or
      ;; raw parenthesized Kanata action text can leak through inspection.
      (is-equal data
                (ivory-key.backend::kanata-buffered-interaction-action-canonical-data
                 action))
      (is-equal "tap-hold-case-f" (getf data :interaction))
      (is-equal :known (getf data :provenance))
      (is (search "bounded deadline"
                  (ivory-key.backend:realization-detail
                   (first (remove-if-not
                           (lambda (result)
                             (search "bounded deadline"
                                     (ivory-key.backend:realization-detail result)))
                           (ivory-key.backend::kanata-plan-realizations plan))))))
      (is-equal (list action)
                (ivory-key.backend::kanata-plan-buffered-actions plan))
      ;; The direct row remains individually exact, but the handoff adds an
      ;; unsupported interaction result, so the shared emitter gate refuses.
      (signals error
        (ivory-key.backend:emit-plan-to-string backend plan)))))

(deftest backend-kanata-buffered-action-handoff-refuses-forged-partial-and-colliding-ir
  (multiple-value-bind (contract policy)
      (backend-test-buffered-contract-and-policy)
    (let* ((action (backend-test-buffered-action contract))
           (tap (ivory-key.backend::make-kanata-key-action "f" "f"))
           (hold (ivory-key.backend::make-kanata-modifier-hold-action
                  "case" "lshift" :state "shifted")))
      ;; Equal nonzero u16 timing and no nested holdtap are structural AST
      ;; invariants, not assumptions made by an eventual text emitter.
      (backend-test-kanata-action-signals
       :mismatched-kanata-tap-hold-time
       (lambda ()
         (ivory-key.backend::make-kanata-tap-hold-release-action
          200 201 tap hold)))
      (let ((inner (ivory-key.backend::make-kanata-tap-hold-release-action
                    200 200 tap hold)))
        (backend-test-kanata-action-signals
         :invalid-kanata-hold-action
         (lambda ()
           (ivory-key.backend::make-kanata-tap-hold-release-action
            200 200 tap inner))))
      (let ((carrier
              (ivory-key.backend::make-kanata-axis-carrier-hold-action
               "script" "greek" 85)))
        (is-equal '(:axis-carrier-hold :axis "script" :state "greek" :code 85)
                  (ivory-key.backend::kanata-action-canonical-data carrier))
        (is-equal "(arbitrary-code 85)"
                  (ivory-key.backend::kanata-action-emission-string carrier)))
      (backend-test-kanata-action-signals
       :unsupported-kanata-axis-carrier
       (lambda ()
         (ivory-key.backend::make-kanata-axis-carrier-hold-action
          "script" "greek" 86)))
      (backend-test-kanata-action-signals
       :invalid-kanata-defcfg-requirements
       (lambda ()
         (ivory-key.backend::make-kanata-defcfg-requirements
          :process-unmapped-keys t :concurrent-tap-hold nil)))
      (backend-test-kanata-action-signals
       :kanata-buffered-owner-route-collision
       (lambda ()
         (let ((owner (ivory-key.backend::make-kanata-owner-placement "f" "f")))
           (ivory-key.backend::make-kanata-buffered-interaction-action
            contract "alias-owner-collision" owner
            (ivory-key.backend::make-kanata-tap-hold-release-action
             200 200 tap hold)
            (list (ivory-key.backend::make-kanata-direct-route-reference
                   "f" "f" tap))
            (ivory-key.backend::make-kanata-defcfg-requirements
             :process-unmapped-keys t :concurrent-tap-hold :required)))))
      (backend-test-kanata-action-signals
       :unvalidated-kanata-action
       (lambda ()
         (ivory-key.backend::make-kanata-tap-hold-release-action
          200 200
          (make-instance 'ivory-key.backend::kanata-key-action
                         :key "f" :token "f") hold)))
      ;; LOWER-REQUEST repeats complete-set validation: an AST selected for a
      ;; direct call cannot omit its matching contract or smuggle an extra
      ;; target into an otherwise static plan.
      (backend-test-kanata-action-signals
       :incomplete-kanata-buffered-request-contracts
       (lambda ()
         (ivory-key.backend:lower-request
          (ivory-key.backend:make-kanata-backend)
          (backend-test-request
           :metadata (list :interaction-compatibility-policy policy
                           :kanata-buffered-actions (list action))))))
      (multiple-value-bind (other-contract ignored-policy)
          (backend-test-buffered-contract-and-policy "tap-hold-case-j")
        (declare (ignore ignored-policy))
        (backend-test-kanata-action-signals
         :incomplete-kanata-buffered-action-set
         (lambda ()
           (ivory-key.backend:lower-request
            (ivory-key.backend:make-kanata-backend)
            (backend-test-request
             :interactions (list other-contract)
             :metadata (list :interaction-compatibility-policy policy
                             :kanata-buffered-actions
                             (list (backend-test-buffered-action other-contract)))))))))))

(deftest backend-kanata-buffered-action-authority-is-rederived-from-model
  "A public contract object cannot mint buffered action authority by projection."
  (multiple-value-bind (contract ignored-policy)
      (backend-test-buffered-contract-and-policy)
    (declare (ignore ignored-policy))
    ;; Both counterfeits retain the same evidence-ledger interaction name and
    ;; deadline.  One erases the normalized candidate graph; the other erases
    ;; its authority-bearing role links.  Public action construction must
    ;; rederive and reject both before a direct LOWER-REQUEST can receive them.
    (dolist (forged
             (list (backend-test-forged-buffered-contract
                    contract :empty-candidates t)
                   (backend-test-forged-buffered-contract
                    contract :empty-role-references t)))
      (backend-test-kanata-action-signals
       :unvalidated-kanata-buffered-contract
       (lambda ()
         (backend-test-buffered-action forged))))))

(deftest backend-kanata-buffered-actions-are-canonical-and-cross-position-safe
  "Direct protocol calls retain a canonical, non-colliding inert action set."
  (let* ((layout (pending-input-normalized-layout))
         (policy (pending-input-policy
                  :names '("tap-hold-case-f" "tap-hold-case-j")))
         (contracts
           (ivory-key.model:derive-interaction-compatibility-contracts
            policy layout))
         (f-contract
           (find "tap-hold-case-f" contracts :test #'ivory-key.model:identifier=
                 :key (lambda (contract)
                        (ivory-key.model:normalized-interaction-name
                         (ivory-key.model::interaction-compatibility-contract-interaction
                          contract)))))
         (j-contract
           (find "tap-hold-case-j" contracts :test #'ivory-key.model:identifier=
                 :key (lambda (contract)
                        (ivory-key.model:normalized-interaction-name
                         (ivory-key.model::interaction-compatibility-contract-interaction
                          contract)))))
         (f-action (backend-test-buffered-action f-contract))
         (j-action (backend-test-buffered-action j-contract))
         (canonical-plan
           (backend-test-buffered-plan policy (list f-contract j-contract)
                                       (list f-action j-action)))
         (reversed-plan
           (backend-test-buffered-plan policy (list j-contract f-contract)
                                       (list j-action f-action))))
    ;; The stored handoff, its canonical data, and its inspection dump do not
    ;; depend on caller order.  These plans remain unsupported/non-emittable.
    (is-equal '("tap-hold-case-f" "tap-hold-case-j")
              (mapcar
               (lambda (action)
                 (ivory-key.model:identifier-name
                  (ivory-key.model:normalized-interaction-name
                   (ivory-key.model::interaction-compatibility-contract-interaction
                    (ivory-key.backend::kanata-buffered-interaction-action-contract
                     action)))))
               (ivory-key.backend::kanata-plan-buffered-actions reversed-plan)))
    (is-equal
     (mapcar #'ivory-key.backend::kanata-buffered-interaction-action-canonical-data
             (ivory-key.backend::kanata-plan-buffered-actions canonical-plan))
     (mapcar #'ivory-key.backend::kanata-buffered-interaction-action-canonical-data
             (ivory-key.backend::kanata-plan-buffered-actions reversed-plan)))
    (is-equal (backend-test-kanata-plan-dump canonical-plan)
              (backend-test-kanata-plan-dump reversed-plan))
    (signals error
      (ivory-key.backend:emit-plan-to-string
       (ivory-key.backend:make-kanata-backend) reversed-plan))
    ;; Duplicate interaction identities are rejected before the set equality
    ;; check could make (f f) appear to cover one selected policy target.
    (backend-test-kanata-action-signals
     :duplicate-kanata-buffered-request-interaction
     (lambda ()
       (backend-test-buffered-plan policy (list f-contract f-contract)
                                   (list f-action j-action))))
    ;; Token strings are distinct ("f" versus "q"), but F's foreign route
    ;; names J's owner *position*.  Cross-action validation must compare the
    ;; semantic positions too, rather than relying on realization tokens.
    (backend-test-kanata-action-signals
     :kanata-buffered-owner-foreign-position-collision
     (lambda ()
       (backend-test-buffered-plan
        policy (list f-contract j-contract)
        (list (backend-test-buffered-action f-contract
                                            :foreign-position "j"
                                            :foreign-token "q")
              j-action))))))

(deftest backend-pipeline-emits-deterministic-xkb-and-kanata-strings
  (let* ((result
           (ivory-key.backend:compile-xkb-kanata-request
            (backend-test-request
             :entries (list (backend-test-entry)))))
         (xkb (pipeline-artifact-of-kind result :xkb))
         (kanata (pipeline-artifact-of-kind result :kanata)))
    (is xkb)
    (is kanata)
    (is-equal
     (format nil
             "xkb_keymap {~%  xkb_keycodes { include \"evdev+aliases(qwerty)\" };~%  xkb_types { include \"complete\" };~%  xkb_compatibility { include \"complete\" };~%  xkb_symbols {~%    include \"pc+us\"~%    name[Group1] = \"test-layout\";~%    key <AD01> { type[Group1]=\"TWO_LEVEL\", symbols[Group1]=[ q, Q ] };~%  };~%  xkb_geometry { include \"pc(pc105)\" };~%};~%")
     (ivory-key.backend:pipeline-artifact-content xkb))
    (is-equal
     (format nil "(defcfg~%  process-unmapped-keys yes)~%~%(defsrc~%  q)~%~%(deflayer test-layout~%  q)~%")
     (ivory-key.backend:pipeline-artifact-content kanata))))

(deftest backend-pipeline-artifacts-cannot-escape-output-directory
  (dolist (relative-path '("../escape" "sub/../../escape" "/tmp/escape"))
    (let ((artifact (make-instance 'ivory-key.backend::pipeline-artifact
                                   :kind :xkb
                                   :relative-path relative-path
                                   :content "")))
      (signals error
        (ivory-key.backend::%artifact-output-pathname artifact #p"build/")))))

(deftest backend-xkb-preserves-eight-level-order-and-refuses-nine
  (let* ((backend (ivory-key.backend:make-xkb-backend))
         (outputs '("a" "A" "b" "B" "c" "C" "d" "D"))
         (request (backend-test-request
                   :entries (list (backend-test-entry :xkb-outputs outputs))))
         (text (ivory-key.backend:emit-plan-to-string
                backend (ivory-key.backend:lower-request backend request))))
    (is (search "type[Group1]=\"EIGHT_LEVEL\"" text))
    (is (search "symbols[Group1]=[ a, A, b, B, c, C, d, D ]" text))
    (signals error
      (ivory-key.backend:emit-plan-to-string
       backend
       (ivory-key.backend:lower-request
        backend
        (backend-test-request
         :entries
         (list (backend-test-entry
                :xkb-outputs '("a" "A" "b" "B" "c" "C" "d" "D" "e")))))))))

(deftest backend-xkb-emits-the-closed-observed-group-two-carriers-and-tables
  (let* ((backend (ivory-key.backend:make-xkb-backend))
         (plan (ivory-key.backend:lower-request
                backend (backend-test-observed-selector-request)))
         (text (ivory-key.backend:emit-plan-to-string backend plan)))
    (is (some (lambda (result)
                (and (eq (ivory-key.backend:realization-feature result)
                         :selector-policy)
                     (eq (ivory-key.backend:realization-grade result) :exact)))
              (ivory-key.backend:xkb-plan-realizations plan)))
    ;; These are separate carrier identities.  ZEHA must never be emitted as
    ;; an alias of LVL3/LVL5, which would overwrite one selector's state.
    (is (search "<LVL3> = 92;" text))
    (is (search "<ZEHA> = 93;" text))
    (is (search "type[Group1]=\"FOUR_LEVEL_ALPHABETIC\", symbols[Group1]=[ q, Q, Greek_theta, Greek_THETA ], type[Group2]=\"TWO_LEVEL\", symbols[Group2]=[ upcaret, NoSymbol ]" text))
    ;; pc+us normally maps LVL3 to Mod5.  The explicit None map must precede
    ;; the separate ZEHA/Mod5 carrier map, so Group2 does not consume Level3.
    (let ((none (search "modifier_map None { <LVL3> };" text))
          (mod5 (search "modifier_map Mod5 { <ZEHA> };" text)))
      (is none)
      (is mod5)
      (is (< none mod5)))
    ;; The closed model admits both source-evidenced Group1 table types.  The
    ;; external libxkbcommon probe executes both; this focused test preserves
    ;; deterministic type spelling at the emitter boundary.
    (let ((four-level
            (ivory-key.backend:emit-plan-to-string
             backend
             (ivory-key.backend:lower-request
              backend
              (backend-test-observed-selector-request
               :group-one-type :four-level)))))
      (is (search "type[Group1]=\"FOUR_LEVEL\"" four-level)))))

(deftest backend-xkb-observed-group-two-refuses-incomplete-or-colliding-tables
  (let ((backend (ivory-key.backend:make-xkb-backend)))
    ;; Group2 has two levels only: changing the Level3 bit in that group is a
    ;; mismatch rather than a reason to silently emit an eight-level table.
    (signals error
      (ivory-key.backend:lower-request
       backend
       (backend-test-observed-selector-request
        :entries
        (list (backend-test-observed-selector-entry
               :outputs '("q" "Q" "Greek_theta" "Greek_THETA"
                          "upcaret" "NoSymbol" "different" "NoSymbol"))))))
    ;; Eight outputs without their normalized source contexts cannot be
    ;; guessed as a selector table or fall through to generic EIGHT_LEVEL.
    (signals error
      (ivory-key.backend:lower-request
       backend
       (backend-test-observed-selector-request
        :entries
        (list (backend-test-entry
               :xkb-outputs '("q" "Q" "Greek_theta" "Greek_THETA"
                              "upcaret" "NoSymbol" "upcaret" "NoSymbol"))))))
    ;; A partial policy cannot let a second eight-context table fall through
    ;; to generic EIGHT_LEVEL emission without the three carrier selectors.
    (signals error
      (ivory-key.backend:lower-request
       backend
       (backend-test-observed-selector-request
        :entries
        (list (backend-test-observed-selector-entry)
              (backend-test-observed-selector-entry
               :position "w" :xkb-code "AD02")))))
    (signals error
      (ivory-key.backend:lower-request
       backend
       (backend-test-observed-selector-request
        :entries
        (list (backend-test-observed-selector-entry)
              (backend-test-entry :position "carrier-collision" :xkb-code "ZEHA")))))))

(deftest backend-xkb-semantic-modifier-map-is-closed-and-non-stringly
  (let* ((backend (ivory-key.backend:make-xkb-backend))
         (allocations
           '(("control" "lctl" "LCTL" "Control_L" "Control")
             ("meta" "lalt" "LALT" "Meta_L" "Mod1")
             ("hyper" "rmet" "RWIN" "Hyper_L" "Mod2")
             ("alt" "ralt" "RALT" "Alt_L" "Mod3")
             ("super" "lmet" "LWIN" "Super_L" "Mod4")))
         (request
           (backend-test-request
            :entries (list (backend-test-entry))
            :metadata (list :xkb-semantic-modifier-allocations allocations)))
         (text
           (ivory-key.backend:emit-plan-to-string
            backend (ivory-key.backend:lower-request backend request))))
    (is (search "modifier_map None { <RALT>, <LCTL>, <RWIN>, <LALT>, <LWIN> };"
                text))
    (is (search "replace key <RWIN>" text))
    (is (search "symbols[Group1]=[ Hyper_L ]" text))
    (dolist (bad
             (list (butlast allocations)
                   (substitute '("hyper" "rmet" "RWIN" "Super_R" "Mod4")
                               (third allocations) allocations :test #'equal)
                   (append allocations
                           '(("injected" "x" "ABCD" "x" "Mod5")))))
      (signals error
        (ivory-key.backend:lower-request
         backend
         (backend-test-request
          :entries (list (backend-test-entry))
          :metadata (list :xkb-semantic-modifier-allocations bad)))))))
