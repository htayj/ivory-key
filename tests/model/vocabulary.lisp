;;;; SPDX-License-Identifier: GPL-3.0-or-later
;;;; Target-neutral semantic output vocabulary invariants.

(in-package #:ivory-key.tests)

(defun vocabulary-test-entry (kind identity backend spelling)
  (ivory-key.model::make-output-vocabulary-entry
   kind identity backend spelling))

(defun vocabulary-test-registry ()
  ;; Deliberately unordered input makes the serialization contract observable.
  ;; The backend names and opaque spellings are synthetic: this model test does
  ;; not claim a spelling for XKB, Kanata, or any other real backend.
  (ivory-key.model::make-output-vocabulary
   '("backend-b" "backend-a")
   (list (vocabulary-test-entry "named-symbol" "greek-theta" "backend-b"
                                "symbol-theta")
         (vocabulary-test-entry "named-key" "return" "backend-a"
                                "key-return")
         (vocabulary-test-entry "command" "stop-output" "backend-a"
                                "command-stop")
         (vocabulary-test-entry "named-key" "return" "backend-b"
                                "b-key-return"))))

(defun vocabulary-signals-code (code thunk)
  (handler-case
      (progn
        (funcall thunk)
        (error "Expected semantic error ~S, but none was signaled." code))
    (ivory-key.model:semantic-error (condition)
      (is-equal code (ivory-key.model:semantic-error-code condition)))))

(deftest vocabulary-resolves-typed-outputs-and-serializes-deterministically
  (let ((vocabulary (vocabulary-test-registry)))
    (is-equal '("backend-a" "backend-b")
              (mapcar #'ivory-key.model:identifier-name
                      (ivory-key.model::output-vocabulary-backends vocabulary)))
    (is-equal '(("backend-a" "command" "stop-output" "command-stop")
                ("backend-a" "named-key" "return" "key-return")
                ("backend-b" "named-key" "return" "b-key-return")
                ("backend-b" "named-symbol" "greek-theta" "symbol-theta"))
              (ivory-key.model::output-vocabulary-canonical-data vocabulary))
    (is-equal "key-return"
              (ivory-key.model::output-vocabulary-spelling-for-output
               vocabulary (ivory-key.model:make-named-key-output "RETURN") "backend-a"))
    (is-equal "symbol-theta"
              (ivory-key.model::output-vocabulary-spelling-for-output
               vocabulary (ivory-key.model:make-named-symbol-output "greek-theta")
               "backend-b"))
    (is-equal "command-stop"
              (ivory-key.model::output-vocabulary-spelling-for-output
               vocabulary (ivory-key.model:make-command-output "stop-output")
               "backend-a"))
    (is (null (ivory-key.model::find-output-vocabulary-entry
               vocabulary "named-key" "escape" "backend-a")))))

(deftest vocabulary-rejects-unrepresentable-or-ambiguous-registries
  (vocabulary-signals-code
   :unknown-vocabulary-output-kind
   (lambda ()
     (vocabulary-test-entry "carrier-code" "return" "backend-a" "return-token")))
  (vocabulary-signals-code
   :invalid-vocabulary-identifier
   (lambda ()
     ;; Symbols remain a programmatic convenience elsewhere in the model, but
     ;; a registry boundary accepts only strings or already canonical values.
     (vocabulary-test-entry :named-key "return" "backend-a" "return-token")))
  (vocabulary-signals-code
   :invalid-vocabulary-spelling
   (lambda ()
     (vocabulary-test-entry "named-key" "return" "backend-a" "")))
  (vocabulary-signals-code
   :duplicate-vocabulary-backend
   (lambda ()
     (ivory-key.model::make-output-vocabulary '("backend-a" "BACKEND-A") nil)))
  (vocabulary-signals-code
   :unknown-vocabulary-backend
   (lambda ()
     (ivory-key.model::make-output-vocabulary
      '("backend-a")
      (list (vocabulary-test-entry "named-key" "return" "backend-b" "return-token")))))
  (vocabulary-signals-code
   :duplicate-vocabulary-entry
   (lambda ()
     (ivory-key.model::make-output-vocabulary
      '("backend-a")
      (list (vocabulary-test-entry "named-key" "return" "backend-a" "return-token")
            (vocabulary-test-entry "named-key" "RETURN" "backend-a" "other-token")))))
  (vocabulary-signals-code
   :ambiguous-vocabulary-spelling
   (lambda ()
     (ivory-key.model::make-output-vocabulary
      '("backend-a")
      (list (vocabulary-test-entry "named-key" "return" "backend-a" "same-token")
            (vocabulary-test-entry "named-symbol" "greek-rho" "backend-a" "same-token"))))))

(deftest vocabulary-fails-closed-for-unknown-and-missing-lookups
  (let ((vocabulary (vocabulary-test-registry)))
    (vocabulary-signals-code
     :unknown-vocabulary-backend
     (lambda ()
       (ivory-key.model::output-vocabulary-spelling
        vocabulary "named-key" "return" "backend-absent")))
    (vocabulary-signals-code
     :missing-vocabulary-mapping
     (lambda ()
       (ivory-key.model::output-vocabulary-spelling
        vocabulary "named-key" "escape" "backend-a")))
    (vocabulary-signals-code
     :unsupported-vocabulary-output
     (lambda ()
       (ivory-key.model::output-vocabulary-spelling-for-output
        vocabulary (ivory-key.model:make-text-output "x") "backend-a")))))

(deftest vocabulary-never-interns-opaque-source-or-backend-strings
  (let ((uninterned-identity "vocabulary-source-spelling-must-not-intern")
        (uninterned-backend "vocabulary-backend-must-not-intern"))
    (is (null (find-symbol (string-upcase uninterned-identity)
                           (find-package '#:ivory-key.model))))
    (is (null (find-symbol (string-upcase uninterned-backend)
                           (find-package '#:ivory-key.model))))
    (ivory-key.model::make-output-vocabulary
     (list uninterned-backend)
     (list (vocabulary-test-entry "named-key" uninterned-identity
                                  uninterned-backend "opaque-token")))
    (is (null (find-symbol (string-upcase uninterned-identity)
                           (find-package '#:ivory-key.model))))
    (is (null (find-symbol (string-upcase uninterned-backend)
                           (find-package '#:ivory-key.model))))))

(deftest realization-profile-owns-a-compatible-output-vocabulary
  (let* ((vocabulary
           (ivory-key.model::make-output-vocabulary
            '("backend-b" "backend-a")
            (list (vocabulary-test-entry "named-key" "return" "backend-a"
                                         "key-return"))))
         (profile
           (ivory-key.model:make-realization-profile
            "synthetic-profile" :pipeline '("backend-a" "backend-b")
            :vocabulary vocabulary)))
    (is (eq vocabulary
            (ivory-key.model:realization-profile-vocabulary profile)))
    ;; Pipeline order remains realization policy; vocabulary order is a
    ;; deterministic map representation and is not substituted for it.
    (is-equal '("backend-a" "backend-b")
              (ivory-key.model:realization-profile-pipeline profile)))
  (vocabulary-signals-code
   :duplicate-realization-backend
   (lambda ()
     (ivory-key.model:make-realization-profile
      "duplicate-pipeline" :pipeline '("backend-a" "BACKEND-A"))))
  (vocabulary-signals-code
   :unknown-realization-vocabulary-backend
   (lambda ()
     (ivory-key.model:make-realization-profile
     "incompatible-vocabulary" :pipeline '("backend-a")
      :vocabulary (ivory-key.model::make-output-vocabulary '("backend-b") nil))))
  (vocabulary-signals-code
   :invalid-realization-vocabulary
   (lambda ()
     (ivory-key.model:make-realization-profile
      "not-a-vocabulary" :pipeline '("backend-a") :vocabulary "backend-a"))))

(deftest realization-interaction-compatibility-policy-is-closed-scoped-and-unselected-by-default
  "The bounded V1 Manna/Kanata choice is typed, scoped, and not generic IR."
  (dolist (mode '(:modern-no-delay :kanata-1-12-buffered))
    (let ((policy
            (ivory-key.model::make-realization-interaction-compatibility-policy
             mode '("second-instance" "first-instance"))))
      (is (typep policy
                 'ivory-key.model::realization-interaction-compatibility-policy))
      (is-equal mode
                (ivory-key.model::realization-interaction-compatibility-policy-mode
                 policy))
      ;; Applicability is a set.  Canonical ordering preserves deterministic
      ;; inspection without making declaration order candidate priority.
      (is-equal '("first-instance" "second-instance")
                (mapcar #'ivory-key.model:identifier-name
                        (ivory-key.model::realization-interaction-compatibility-policy-interactions
                         policy)))
      (is (eq policy
              (ivory-key.model::validate-realization-interaction-compatibility-policy
               policy)))
      (let ((profile
              (ivory-key.model:make-realization-profile
               "selected-compatibility" :pipeline '("kanata" "xkb")
               :interaction-compatibility-policy policy)))
        (is (eq policy
                (ivory-key.model::realization-profile-interaction-compatibility-policy
                 profile))))))
  ;; Omission remains an explicit unselected state, not a modern/no-delay
  ;; default hidden in the profile constructor.
  (is (null
       (ivory-key.model::realization-profile-interaction-compatibility-policy
        (ivory-key.model:make-realization-profile
         "unselected-compatibility" :pipeline '("kanata" "xkb")))))
  (vocabulary-signals-code
   :unsupported-realization-interaction-compatibility-mode
   (lambda ()
     (ivory-key.model::make-realization-interaction-compatibility-policy
      :generic-tap-hold '("target"))))
  (vocabulary-signals-code
   :unsupported-realization-interaction-compatibility-mode
   (lambda ()
     (ivory-key.model::validate-realization-interaction-compatibility-policy
      (make-instance 'ivory-key.model::realization-interaction-compatibility-policy
                     :mode :generic-tap-hold :interactions
                     (list (ivory-key.model:make-identifier "target"))))))
  (vocabulary-signals-code
   :empty-realization-interaction-compatibility-instances
   (lambda ()
     (ivory-key.model::make-realization-interaction-compatibility-policy
      :modern-no-delay nil)))
  (vocabulary-signals-code
   :duplicate-realization-interaction-compatibility-instance
   (lambda ()
     (ivory-key.model::make-realization-interaction-compatibility-policy
      :modern-no-delay '("target" "TARGET"))))
  ;; Public MAKE-INSTANCE can bypass the canonical constructor.  Validation
  ;; must reject that alternate representation rather than leave inspection
  ;; metadata dependent on declaration order.
  (vocabulary-signals-code
   :noncanonical-realization-interaction-compatibility-instances
   (lambda ()
     (ivory-key.model::validate-realization-interaction-compatibility-policy
      (make-instance 'ivory-key.model::realization-interaction-compatibility-policy
                     :mode :modern-no-delay
                     :interactions
                     (list (ivory-key.model:make-identifier "z-target")
                           (ivory-key.model:make-identifier "a-target"))))))
  (vocabulary-signals-code
   :invalid-realization-interaction-compatibility-instance
   (lambda ()
     (ivory-key.model::validate-realization-interaction-compatibility-policy
      (make-instance 'ivory-key.model::realization-interaction-compatibility-policy
                     :mode :modern-no-delay :interactions '("target")))))
  (vocabulary-signals-code
   :invalid-realization-interaction-compatibility-policy
   (lambda ()
     (ivory-key.model:make-realization-profile
      "stringly-compatibility" :pipeline '("kanata" "xkb")
      :interaction-compatibility-policy "modern-no-delay"))))

(deftest device-coverage-programmatic-mappings-must-be-one-to-one-and-covered
  "Coverage-bearing placements cannot bypass DEFINE-DEVICE source invariants."
  (let* ((topology
           (ivory-key.model:make-topology
            "coverage-topology"
            (list (ivory-key.model:make-logical-position "q")
                  (ivory-key.model:make-logical-position "w"))))
         (physical-q
           (ivory-key.model:make-device-position-coverage "q" :physical))
         (physical-w
           (ivory-key.model:make-device-position-coverage "w" :physical))
         (unreachable-q
           (ivory-key.model:make-device-position-coverage "q" :unreachable)))
    ;; Existing no-coverage programmatic placements remain inspectable.  The
    ;; validator deliberately does not infer coverage or reject this legacy
    ;; partial envelope merely because one mapping names an absent position.
    (let ((legacy
            (ivory-key.model:make-device-placement
             "legacy" topology
             (list (cons "P01" "q") (cons "P02" "not-on-topology")))))
      (is (null (ivory-key.model:placement-position-coverage legacy)))
      (is (ivory-key.model:validate-device-placement-coverage legacy)))
    (vocabulary-signals-code
     :unknown-device-placement-position
     (lambda ()
       (ivory-key.model:make-device-placement
        "unknown-mapping" topology (list (cons "P01" "not-on-topology"))
        :position-coverage (list physical-q))))
    (vocabulary-signals-code
     :missing-device-coverage
     (lambda ()
       (ivory-key.model:make-device-placement
        "uncovered-mapping" topology
        (list (cons "P01" "q") (cons "P02" "w"))
        :position-coverage (list physical-q))))
    (vocabulary-signals-code
     :unreachable-device-coverage-with-placement
     (lambda ()
       (ivory-key.model:make-device-placement
        "unreachable-mapping" topology (list (cons "P01" "q"))
        :position-coverage (list unreachable-q))))
    (vocabulary-signals-code
     :duplicate-device-placement
     (lambda ()
       (ivory-key.model:make-device-placement
        "duplicate-logical-mapping" topology
        (list (cons "P01" "q") (cons "P02" "q"))
        :position-coverage (list physical-q))))
    (vocabulary-signals-code
     :physical-device-coverage-without-placement
     (lambda ()
       (ivory-key.model:make-device-placement
        "physical-without-map" topology nil
        :position-coverage (list physical-q))))
    (vocabulary-signals-code
     :duplicate-device-position-coverage
     (lambda ()
       (ivory-key.model:make-device-placement
        "conflicting-coverage" topology (list (cons "P01" "q"))
        :position-coverage
        (list physical-q unreachable-q))))
    ;; Supplying a different covered position does not permit a second map
    ;; for Q; the generic model has one physical input per logical position.
    (vocabulary-signals-code
     :duplicate-device-placement
     (lambda ()
       (ivory-key.model:make-device-placement
        "duplicate-with-complete-coverage" topology
        (list (cons "P01" "q") (cons "P02" "q") (cons "P03" "w"))
        :position-coverage (list physical-q physical-w))))))
