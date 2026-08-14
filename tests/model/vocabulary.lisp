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
