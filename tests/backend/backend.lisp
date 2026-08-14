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
  "Only selected Manna/Kanata modes affect the generic interaction refusal."
  (let ((backend (ivory-key.backend:make-kanata-backend)))
    ;; NIL remains the existing target-generic refusal.  It neither assigns a
    ;; Manna compatibility mode nor adds a policy realization result.
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
               (:kanata-1-12-buffered . "buffered policy lacks")))
      (let* ((policy
               (ivory-key.model::make-realization-interaction-compatibility-policy
                (car case)))
             (plan
               (ivory-key.backend:lower-request
                backend
                (backend-test-request
                 :interactions '(manna-tap-hold)
                 :metadata (list :interaction-compatibility-policy policy))))
             (results (ivory-key.backend::kanata-plan-realizations plan))
             (policy-result
               (find :interaction-compatibility-policy results
                     :key #'ivory-key.backend:realization-feature))
             (interaction
               (find 'manna-tap-hold results
                     :key #'ivory-key.backend:realization-feature)))
        (is policy-result)
        (is interaction)
        (is-equal :unsupported
                  (ivory-key.backend:realization-grade policy-result))
        (is-equal :unsupported
                  (ivory-key.backend:realization-grade interaction))
        (is (search (cdr case)
                    (ivory-key.backend:realization-detail policy-result)))
        (is-equal (ivory-key.backend:realization-detail policy-result)
                  (ivory-key.backend:realization-detail interaction))
        ;; An inspectable plan is still non-emittable, so neither mode can
        ;; accidentally become a parseable Kanata action claim.
        (signals error
          (ivory-key.backend:emit-plan-to-string backend plan))))
    (signals error
      (ivory-key.backend:lower-request
       backend
       (backend-test-request
        :interactions '(invalid-policy)
        :metadata
        (list :interaction-compatibility-policy "kanata-1-12-buffered"))))))

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
