;;;; SPDX-License-Identifier: GPL-3.0-or-later
;;;; Structural compatibility contracts over the 14+2 normalized fixture.

(in-package #:ivory-key.tests)

(defun pending-input-normalized-layout ()
  (ivory-key.model:normalize-layout
   (interaction-template-decoder-layout +manna-release-trigger-v1-source+)))

(defun pending-input-policy (&key (mode :kanata-1-12-buffered) names)
  (ivory-key.model:make-realization-interaction-compatibility-policy
   mode
   (or names (mapcar #'first +manna-release-trigger-v1-inventory+))))

(defun pending-input-signals-code (code thunk)
  (handler-case
      (progn
        (funcall thunk)
        (error "Expected semantic error ~S, but none was signaled." code))
    (ivory-key.model:semantic-error (condition)
      (is-equal code (ivory-key.model:semantic-error-code condition)))))

(defun pending-input-interaction (layout name)
  (find name (ivory-key.model:normalized-layout-interactions layout)
        :test #'ivory-key.model:identifier=
        :key #'ivory-key.model:normalized-interaction-name))

(defun pending-input-candidate-for-role (interaction role)
  (find role (ivory-key.model:normalized-interaction-candidates interaction)
        :test #'eq
        :key (lambda (candidate)
               (ivory-key.model:temporal-pattern-kind
                (ivory-key.model:normalized-candidate-match candidate)))))

(defun pending-input-clone-candidate
    (candidate &key (name nil namep) (match nil matchp) (entries nil entriesp)
                    (effects nil effectsp) (context-axes nil context-axesp)
                    (origin nil originp))
  (make-instance
   'ivory-key.model::normalized-interaction-candidate
   :name (if namep (ivory-key.model:ensure-identifier name)
             (ivory-key.model:normalized-candidate-name candidate))
   :match (if matchp match (ivory-key.model:normalized-candidate-match candidate))
   :commit (ivory-key.model:normalized-candidate-commit candidate)
   :entries (if entriesp entries (ivory-key.model:normalized-candidate-entries candidate))
   :effects (if effectsp effects (ivory-key.model:normalized-candidate-effects candidate))
   :context-axes (if context-axesp context-axes
                     (ivory-key.model:normalized-candidate-context-axes candidate))
   :context-policy (ivory-key.model:normalized-candidate-context-policy candidate)
   :effect-start (ivory-key.model:normalized-candidate-effect-start candidate)
   :origin (if originp origin (ivory-key.model:normalized-candidate-origin candidate))))

(defun pending-input-clone-interaction
    (interaction &key (name nil namep) (participants nil participantsp) (observe nil observep)
                       (anchor nil anchorp) (candidates nil candidatesp)
                       (arbitration nil arbitrationp) (origin nil originp))
  (make-instance
   'ivory-key.model::normalized-interaction
   :name (if namep (ivory-key.model:ensure-identifier name)
             (ivory-key.model:normalized-interaction-name interaction))
   :participants (if participantsp participants
                     (ivory-key.model:normalized-interaction-participants interaction))
   :observe (if observep observe (ivory-key.model:normalized-interaction-observe interaction))
   :anchor (if anchorp anchor (ivory-key.model:normalized-interaction-anchor interaction))
   :candidates (if candidatesp candidates
                   (ivory-key.model:normalized-interaction-candidates interaction))
   :arbitration (if arbitrationp arbitration
                    (ivory-key.model:normalized-interaction-arbitration interaction))
   :origin (if originp origin (ivory-key.model:normalized-interaction-origin interaction))))

(defun pending-input-layout-replacing-interaction (layout replacement &key original-name)
  (make-instance
   'ivory-key.model::normalized-layout
   :name (ivory-key.model:normalized-layout-name layout)
   :topology (ivory-key.model:normalized-layout-topology layout)
   :axes (ivory-key.model:normalized-layout-axes layout)
   :modifiers (ivory-key.model:normalized-layout-modifiers layout)
   :bindings (ivory-key.model:normalized-layout-bindings layout)
   :patches (ivory-key.model:normalized-layout-patches layout)
   :interactions
   (cons replacement
         (remove (pending-input-interaction
                  layout
                  (or original-name
                      (ivory-key.model:identifier-name
                       (ivory-key.model:normalized-interaction-name replacement))))
                 (ivory-key.model:normalized-layout-interactions layout)
                 :count 1))
   :origin (ivory-key.model:normalized-layout-origin layout)))

(defun pending-input-contract-for (contracts name)
  (find name contracts
        :test #'ivory-key.model:identifier=
        :key (lambda (contract)
               (ivory-key.model:normalized-interaction-name
                (ivory-key.model::interaction-compatibility-contract-interaction
                 contract)))))

(defun pending-input-row (name)
  (or (find name +manna-release-trigger-v1-inventory+ :test #'string=
            :key #'first)
      (error "No Manna inventory row named ~S." name)))

(defparameter +pending-input-buffered-evidence-names+
  '("tap-hold-case-f" "tap-hold-case-j"
    "tap-hold-control-d" "tap-hold-control-k"
    "tap-hold-meta-s" "tap-hold-meta-l"
    "tap-hold-super-a" "tap-hold-super-semicolon"
    "tap-hold-hyper-escape" "tap-hold-hyper-apostrophe"
    "tap-hold-alt-backspace" "tap-hold-alt-space"
    "tap-hold-function-end" "tap-hold-function-pgdn"))

(defparameter +pending-input-buffered-refused-names+
  '("tap-hold-script-delete" "tap-hold-plane-enter"))

(defun pending-input-buffered-evidence-rows ()
  (remove-if-not (lambda (row)
                   (member (first row) +pending-input-buffered-evidence-names+
                           :test #'string=))
                 +manna-release-trigger-v1-inventory+))

(deftest pending-input-derives-evidenced-buffered-contracts
  "The buffered route accepts exactly its current 14-instance evidence scope."
  (let* ((layout (pending-input-normalized-layout))
         (contracts
           (ivory-key.model::derive-interaction-compatibility-contracts
            (pending-input-policy
             :names (mapcar #'first (pending-input-buffered-evidence-rows)))
            layout)))
    (is-equal 14 (length contracts))
    ;; The independent fixture inventory must cover exactly the closed 14-row
    ;; buffered table—not a name blacklist plus an accidental extra entry.
    (is-equal +pending-input-buffered-evidence-names+
              (mapcar #'first (pending-input-buffered-evidence-rows)))
    (is-equal (sort (copy-list +pending-input-buffered-evidence-names+) #'string<)
              (mapcar (lambda (contract)
                        (ivory-key.model:identifier-name
                         (ivory-key.model:normalized-interaction-name
                          (ivory-key.model::interaction-compatibility-contract-interaction
                           contract))))
                      contracts))
    (dolist (row (pending-input-buffered-evidence-rows))
      (destructuring-bind (name ignored-alias position tap deadline kind identity
                            &optional state)
          row
        (declare (ignore ignored-alias))
        (let* ((contract (pending-input-contract-for contracts name))
               (interaction
                 (ivory-key.model::interaction-compatibility-contract-interaction contract))
               (roles
                 (ivory-key.model::release-trigger-interaction-compatibility-contract-role-references
                  contract))
               (signature
                 (ivory-key.model::release-trigger-interaction-compatibility-contract-held-effect-signature
                  contract))
               (provenance
                 (ivory-key.model::release-trigger-interaction-compatibility-contract-provenance
                  contract)))
          (is (typep contract 'ivory-key.model::pending-foreign-interval-contract))
          (is-equal :kanata-1-12-buffered
                    (ivory-key.model::interaction-compatibility-contract-mode contract))
          (is-equal position
                    (ivory-key.model:identifier-name
                     (ivory-key.model::interaction-compatibility-contract-owner contract)))
          (is-equal deadline
                    (ivory-key.model::release-trigger-interaction-compatibility-contract-deadline
                     contract))
          (is-equal tap
                    (ivory-key.model:identifier-name
                     (ivory-key.model::release-trigger-interaction-compatibility-contract-tap-key
                      contract)))
          (is-equal '(:timeout :foreign-release :tap)
                    (mapcar #'ivory-key.model::interaction-compatibility-role-reference-role
                            roles))
          (is-equal (ecase kind (:modifier :modifier) (:axis :axis-state))
                    (ivory-key.model::interaction-compatibility-held-effect-signature-kind
                     signature))
          (is-equal identity
                    (ivory-key.model:identifier-name
                     (ivory-key.model::interaction-compatibility-held-effect-signature-identity
                      signature)))
          (is-equal state
                    (let ((value
                            (ivory-key.model::interaction-compatibility-held-effect-signature-state
                             signature)))
                      (and value (ivory-key.model:identifier-name value))))
          (is (typep (ivory-key.model::interaction-compatibility-contract-origin contract)
                     'ivory-key.source:source-origin))
          (is (eq (ivory-key.model::interaction-compatibility-contract-origin contract)
                  (ivory-key.model:normalized-interaction-origin interaction)))
          (is (eq (ivory-key.model::interaction-compatibility-provenance-interaction-origin
                   provenance)
                  (ivory-key.model:normalized-interaction-origin interaction)))
          (dolist (reference roles)
            (is (eq (ivory-key.model::interaction-compatibility-role-reference-origin
                     reference)
                    (ivory-key.model:normalized-candidate-origin
                     (ivory-key.model::interaction-compatibility-role-reference-candidate
                      reference))))))))))

(deftest pending-input-modern-contract-is-explicitly-non-pending
  (let* ((layout (pending-input-normalized-layout))
         (contracts
           (ivory-key.model::derive-interaction-compatibility-contracts
            (pending-input-policy :mode :modern-no-delay)
            layout)))
    ;; The full 14+2 fixture is structurally derivable for modern mode.  This
    ;; proves the buffered GDEL/RTOP refusal is an evidence boundary rather
    ;; than an accidental model-shape failure.
    (is-equal 16 (length contracts))
    (dolist (contract contracts)
      (is (typep contract
                 'ivory-key.model::modern-no-delay-interaction-compatibility-contract))
      (is (not (typep contract 'ivory-key.model::pending-foreign-interval-contract))))
    (dolist (name +pending-input-buffered-refused-names+)
      (is (pending-input-contract-for contracts name)))))

(deftest pending-input-buffered-refuses-script-and-plane-with-stable-code
  (let ((layout (pending-input-normalized-layout)))
    (dolist (name +pending-input-buffered-refused-names+)
      (pending-input-signals-code
       :unsupported-kanata-1-12-buffered-interaction
       (lambda ()
         (ivory-key.model::derive-interaction-compatibility-contracts
          (pending-input-policy :names (list name)) layout))))))

(deftest pending-input-buffered-refuses-renamed-gdel-and-primary-instances
  (let ((layout (pending-input-normalized-layout)))
    (dolist (fixture
             '(("tap-hold-script-delete" "renamed-gdel")
               ("tap-hold-case-f" "renamed-primary")))
      (destructuring-bind (original-name renamed-name) fixture
        (let* ((original (pending-input-interaction layout original-name))
               (renamed (pending-input-clone-interaction original :name renamed-name)))
          (pending-input-signals-code
           :unsupported-kanata-1-12-buffered-interaction
           (lambda ()
             (ivory-key.model::derive-interaction-compatibility-contracts
             (pending-input-policy :names (list renamed-name))
             (pending-input-layout-replacing-interaction
               layout renamed :original-name original-name)))))))))

(deftest pending-input-buffered-refuses-primary-evidence-content-mismatch
  (let* ((layout (pending-input-normalized-layout))
         (original (pending-input-interaction layout "tap-hold-case-f"))
         (tap (pending-input-candidate-for-role original :and))
         (entry (first (ivory-key.model:normalized-candidate-entries tap)))
         (wrong-tap-entry
           (ivory-key.model:make-normalized-binding-entry
            (ivory-key.model:normalized-entry-tuple entry)
            (ivory-key.model:make-named-key-output "not-evidenced"
                                                    :origin
                                                    (ivory-key.model:behavior-origin
                                                     (ivory-key.model:normalized-entry-behavior entry)))
            :origin (ivory-key.model:normalized-entry-origin entry)))
         (wrong-tap (pending-input-clone-candidate tap :entries (list wrong-tap-entry)))
         (replacement
           (pending-input-clone-interaction
            original
            :candidates
            (cons wrong-tap
                  (remove tap (ivory-key.model:normalized-interaction-candidates original)
                          :count 1)))))
    (pending-input-signals-code
     :unsupported-kanata-1-12-buffered-interaction
     (lambda ()
       (ivory-key.model::derive-interaction-compatibility-contracts
        (pending-input-policy :names '("tap-hold-case-f"))
        (pending-input-layout-replacing-interaction layout replacement))))))

(deftest pending-input-recognizes-roles-without-candidate-names-or-list-order
  (let* ((layout (pending-input-normalized-layout))
         (original (pending-input-interaction layout "tap-hold-case-f"))
         (timeout (pending-input-candidate-for-role original :deadline))
         (foreign (pending-input-candidate-for-role original :sequence))
         (tap (pending-input-candidate-for-role original :and))
         ;; The source candidate spellings and input list order carry no role
         ;; semantics.  The priority references the renamed actual candidates.
         (renamed-timeout (pending-input-clone-candidate timeout :name "z-timeout"))
         (renamed-foreign (pending-input-clone-candidate foreign :name "a-foreign"))
         (renamed-tap (pending-input-clone-candidate tap :name "m-tap"))
         (replacement
           (pending-input-clone-interaction
            original
            :candidates (list renamed-tap renamed-timeout renamed-foreign)
            :arbitration
            (list :priority
                  (mapcar #'ivory-key.model:ensure-identifier
                          '("z-timeout" "a-foreign" "m-tap")))))
         (contracts
           (ivory-key.model::derive-interaction-compatibility-contracts
            (pending-input-policy :names '("tap-hold-case-f"))
            (pending-input-layout-replacing-interaction layout replacement))))
    (is-equal '(:timeout :foreign-release :tap)
              (mapcar #'ivory-key.model::interaction-compatibility-role-reference-role
                      (ivory-key.model::release-trigger-interaction-compatibility-contract-role-references
                       (first contracts))))))

(deftest pending-input-programmatic-nil-origins-remain-explicitly-unknown
  (let* ((layout (pending-input-normalized-layout))
         (original (pending-input-interaction layout "tap-hold-case-f"))
         (replacement
           (pending-input-clone-interaction
            original :origin nil
            :candidates
            (mapcar (lambda (candidate)
                      (pending-input-clone-candidate candidate :origin nil))
                    (ivory-key.model:normalized-interaction-candidates original))))
         (contract
           (first
            (ivory-key.model::derive-interaction-compatibility-contracts
             (pending-input-policy :names '("tap-hold-case-f"))
             (pending-input-layout-replacing-interaction layout replacement)))))
    (is (null (ivory-key.model::interaction-compatibility-contract-origin contract)))
    (let ((provenance
            (ivory-key.model::release-trigger-interaction-compatibility-contract-provenance
             contract)))
      (is (null (ivory-key.model::interaction-compatibility-provenance-interaction-origin
                 provenance)))
      (is (null (ivory-key.model::interaction-compatibility-provenance-timeout-origin
                 provenance)))
      (is (null (ivory-key.model::interaction-compatibility-provenance-foreign-release-origin
                 provenance)))
      (is (null (ivory-key.model::interaction-compatibility-provenance-tap-origin
                 provenance))))))

(deftest pending-input-refuses-unknown-policy-target-and-incomplete-shape
  (let ((layout (pending-input-normalized-layout)))
    (pending-input-signals-code
     :unknown-interaction-compatibility-contract-interaction
     (lambda ()
       (ivory-key.model::derive-interaction-compatibility-contracts
        (pending-input-policy :names '("absent-instance")) layout)))
    (let* ((original (pending-input-interaction layout "tap-hold-case-f"))
           (replacement
             (pending-input-clone-interaction
              original
              :candidates (subseq (ivory-key.model:normalized-interaction-candidates original)
                                  0 2))))
      (pending-input-signals-code
       :incomplete-interaction-compatibility-contract
       (lambda ()
         (ivory-key.model::derive-interaction-compatibility-contracts
          (pending-input-policy :names '("tap-hold-case-f"))
          (pending-input-layout-replacing-interaction layout replacement)))))))

(deftest pending-input-refuses-duplicate-role-and-unrecognized-deadline
  (let* ((layout (pending-input-normalized-layout))
         (original (pending-input-interaction layout "tap-hold-case-f"))
         (timeout (pending-input-candidate-for-role original :deadline))
         (tap (pending-input-candidate-for-role original :and))
         (duplicate
           (pending-input-clone-candidate
            tap :match (ivory-key.model:normalized-candidate-match timeout)))
         (replacement
           (pending-input-clone-interaction
            original
            :candidates
            (cons duplicate
                  (remove tap (ivory-key.model:normalized-interaction-candidates original)
                          :count 1))))
         (policy (pending-input-policy :names '("tap-hold-case-f"))))
    (pending-input-signals-code
     :duplicate-interaction-compatibility-contract-role
     (lambda ()
       (ivory-key.model::derive-interaction-compatibility-contracts
        policy (pending-input-layout-replacing-interaction layout replacement))))
    (let* ((arguments
             (copy-list (ivory-key.model:temporal-pattern-arguments
                         (ivory-key.model:normalized-candidate-match timeout))))
           (bad-match
             (progn
               (setf (first arguments) 201)
               (apply #'ivory-key.model:make-temporal-pattern :deadline arguments
                      (ivory-key.model:temporal-pattern-options
                       (ivory-key.model:normalized-candidate-match timeout)))))
           (bad-timeout (pending-input-clone-candidate timeout :match bad-match))
           (bad-interaction
             (pending-input-clone-interaction
              original
              :candidates
              (cons bad-timeout
                    (remove timeout
                            (ivory-key.model:normalized-interaction-candidates original)
                            :count 1)))))
      (pending-input-signals-code
       :invalid-interaction-compatibility-contract-timeout
       (lambda ()
         (ivory-key.model::derive-interaction-compatibility-contracts
          policy (pending-input-layout-replacing-interaction layout bad-interaction)))))))

(deftest pending-input-refuses-reference-before-capture-and-mismatched-holds
  (let* ((layout (pending-input-normalized-layout))
         (original (pending-input-interaction layout "tap-hold-super-semicolon"))
         (foreign (pending-input-candidate-for-role original :sequence))
         (foreign-match (ivory-key.model:normalized-candidate-match foreign))
         (foreign-arguments (ivory-key.model:temporal-pattern-arguments foreign-match))
         (reversed-match
           (ivory-key.model:make-temporal-pattern
            :sequence (list (third foreign-arguments) (second foreign-arguments)
                            (first foreign-arguments))))
         (bad-foreign (pending-input-clone-candidate foreign :match reversed-match))
         (policy (pending-input-policy :names '("tap-hold-super-semicolon"))))
    (pending-input-signals-code
     :invalid-interaction-compatibility-contract-foreign-release
     (lambda ()
       (ivory-key.model::derive-interaction-compatibility-contracts
        policy
        (pending-input-layout-replacing-interaction
         layout
         (pending-input-clone-interaction
          original
          :candidates
          (cons bad-foreign
                (remove foreign
                        (ivory-key.model:normalized-interaction-candidates original)
                        :count 1)))))))
    (let* ((effects (copy-list (ivory-key.model:normalized-candidate-effects foreign)))
           (while (copy-list (getf effects :while)))
           (variant (first while)))
      (setf (getf effects :while)
            (list (cons (car variant)
                        (ivory-key.model::make-held-modifier-operation "meta"))))
      (let ((mismatched (pending-input-clone-candidate foreign :effects effects)))
        (pending-input-signals-code
         :mismatched-interaction-compatibility-contract-held-effects
         (lambda ()
           (ivory-key.model::derive-interaction-compatibility-contracts
            policy
            (pending-input-layout-replacing-interaction
             layout
             (pending-input-clone-interaction
              original
              :candidates
              (cons mismatched
                    (remove foreign
                            (ivory-key.model:normalized-interaction-candidates original)
                            :count 1)))))))))))

(deftest pending-input-refuses-dynamic-hold-and-malformed-tap
  (let* ((layout (pending-input-normalized-layout))
         (original (pending-input-interaction layout "tap-hold-case-f"))
         (timeout (pending-input-candidate-for-role original :deadline))
         (tap (pending-input-candidate-for-role original :and))
         (policy (pending-input-policy :names '("tap-hold-case-f"))))
    (pending-input-signals-code
     :invalid-interaction-compatibility-contract-held-effect
     (lambda ()
       (ivory-key.model::derive-interaction-compatibility-contracts
        policy
        (pending-input-layout-replacing-interaction
         layout
         (pending-input-clone-interaction
          original
          :candidates
          (cons (pending-input-clone-candidate
                 timeout :context-axes
                 (list (ivory-key.model:ensure-identifier "case")))
                (remove timeout
                        (ivory-key.model:normalized-interaction-candidates original)
                        :count 1)))))))
    (pending-input-signals-code
     :invalid-interaction-compatibility-contract-tap
     (lambda ()
       (ivory-key.model::derive-interaction-compatibility-contracts
        policy
        (pending-input-layout-replacing-interaction
         layout
         (pending-input-clone-interaction
          original
          :candidates
          (cons (pending-input-clone-candidate tap :entries nil)
                (remove tap
                        (ivory-key.model:normalized-interaction-candidates original)
                        :count 1)))))))))
