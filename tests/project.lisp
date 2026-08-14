;;;; SPDX-License-Identifier: GPL-3.0-or-later
;;;; Focused project/module loader contracts.

(in-package #:ivory-key.tests)

(defun project-test-directory ()
  (let ((directory
          (merge-pathnames
           (format nil "ivory-key-project-~A/" (symbol-name (gensym "TEST-")))
           (uiop:temporary-directory))))
    (ensure-directories-exist (merge-pathnames "placeholder" directory))
    directory))

(defun project-test-write (directory name content)
  (let ((pathname (merge-pathnames name directory)))
    (ensure-directories-exist pathname)
    (with-open-file (stream pathname :direction :output :if-exists :supersede
                                     :if-does-not-exist :create
                                     :external-format :utf-8)
      (write-string content stream))
    pathname))

(defmacro with-project-test-directory ((directory) &body body)
  `(let ((,directory (project-test-directory)))
     (unwind-protect
          (progn ,@body)
       (when (probe-file ,directory)
         (delete-test-directory-tree ,directory)))))

(defun project-error-code-from (thunk)
  (handler-case
      (progn (funcall thunk)
             (error "Expected IVORY-KEY.PROJECT:PROJECT-ERROR."))
    (ivory-key.project:project-error (condition)
      (ivory-key.project:project-error-code condition))))

(defparameter +project-topology+
  "(ivory-key 1)
(define-topology keyboard (position q (:row 1) (:column 1) (:hand left) (:finger pinky)))")

(defparameter +project-layout+
  "(ivory-key 1)
(define-layout basic (uses-topology keyboard) (binding q (unicode \"q\")))")

(defparameter +project-device+
  "(ivory-key 1)
(define-device board (uses-topology keyboard) (place q (:xkb AD01) (:kanata q)))")

(defparameter +project-realization+
  "(ivory-key 1)
(define-realization linux (pipeline kanata xkb) (allow-grades exact emulated)
  (forbid-shell-actions yes))")

(defparameter +project-composition+
  "(ivory-key 1)
(realize basic-linux (:layout basic) (:device board) (:profile linux))")

(defparameter +project-output-vocabulary+
  "(ivory-key 1)
(define-output-vocabulary synthetic-output
  (backends backend-b backend-a)
  (map-output named-key return
    (:backend-a \"key-return\")
    (:backend-b \"b-key-return\"))
  (map-output command stop-output
    (:backend-a \"command-stop\")))")

(defparameter +project-realization-with-output-vocabulary+
  "(ivory-key 1)
(define-realization synthetic-linux
  (pipeline backend-a backend-b)
  (uses-output-vocabulary synthetic-output)
  (forbid-shell-actions yes))")

(defun write-complete-project (directory imports)
  (project-test-write directory "project.ivory"
                      (format nil "(ivory-key 1)~%~{(import \"~A\")~%~}" imports))
  (project-test-write directory "topology.ivory" +project-topology+)
  (project-test-write directory "layout.ivory" +project-layout+)
  (project-test-write directory "device.ivory" +project-device+)
  (project-test-write directory "realization.ivory" +project-realization+)
  (project-test-write directory "composition.ivory" +project-composition+)
  (merge-pathnames "project.ivory" directory))

(defun write-output-vocabulary-project (directory vocabulary-source realization-source
                                         &key (imports '("realization.ivory"
                                                         "vocabulary.ivory")))
  "Write a minimal project whose profile may refer forward to a vocabulary."
  (project-test-write directory "project.ivory"
                      (format nil "(ivory-key 1)~%~{(import \"~A\")~%~}" imports))
  (project-test-write directory "vocabulary.ivory" vocabulary-source)
  (project-test-write directory "realization.ivory" realization-source)
  (merge-pathnames "project.ivory" directory))

(deftest project-loader-loads-a-complete-explicit-module-graph
  (with-project-test-directory (directory)
    (let* ((entry (write-complete-project
                   directory '("topology.ivory" "layout.ivory" "device.ivory"
                               "realization.ivory" "composition.ivory")))
           (result (ivory-key.project:load-project entry :source-roots (list directory)))
           (layout (ivory-key.project:project-layout result "basic" :errorp t))
           (topology (ivory-key.project:project-topology result "keyboard" :errorp t))
           (device (ivory-key.project:project-device result "board" :errorp t))
           (composition (ivory-key.project:project-composition result "basic-linux" :errorp t))
           (definition (ivory-key.project:project-definition-by-name result :layout "basic"
                                                                      :errorp t)))
      (is (typep layout 'ivory-key.model:layout))
      (is (eq topology (ivory-key.model:layout-topology layout)))
      (is (eq topology (ivory-key.model:placement-topology device)))
      (is-equal :physical
                (ivory-key.model::device-position-coverage-disposition
                 (ivory-key.model::placement-coverage-for-position device "q")))
      (is composition)
      ;; Imported declarations carry the exact import site as provenance.
      (is-equal 1 (length (ivory-key.source:source-span-import-stack
                           (ivory-key.project:project-definition-span definition))))
      (is-equal '((:topology "keyboard") (:layout "basic") (:device "board")
                  (:realization "linux") (:composition "basic-linux"))
                        (mapcar (lambda (item)
                          (list (ivory-key.project:project-definition-kind item)
                                (ivory-key.project:project-definition-name item)))
                        (ivory-key.project:project-load-result-definitions result))))))

(deftest project-manna-source-transcribes-primary-tap-holds-without-selecting-policy
  "The checked-in project remains inspectable while its timing behavior is
unselected.  This covers the real graph rather than a decoder-only fixture."
  (let* ((project (ivory-key.project:load-project
                   (truename "manna-cadet-project.ivory")
                   :source-roots (list (truename "./"))))
         (layout (ivory-key.project:project-layout project "manna-cadet" :errorp t)))
    (is-equal 56 (length (ivory-key.model:layout-bindings layout)))
    (is-equal 20 (length (ivory-key.model:layout-interactions layout)))
    (dolist (device-name '("kinesis-advantage2" "kinesis-advantage360"))
      (let ((device (ivory-key.project:project-device project device-name :errorp t)))
        (dolist (position '("escape" "delete" "end" "pgdn"))
          (is-equal :physical
                    (ivory-key.model:device-position-coverage-disposition
                     (ivory-key.model:placement-coverage-for-position
                      device position))))))
    ;; The physical Enter token reuses RETURN; no duplicate topology identity
    ;; is invented for the rtop alias.
    (is (null (find "enter"
                    (ivory-key.model:topology-positions
                     (ivory-key.model:layout-topology layout))
                    :test #'ivory-key.model:identifier=
                    :key #'ivory-key.model:position-name)))))

(deftest project-device-coverage-rejects-duplicate-and-unknown-declarations
  (with-project-test-directory (directory)
    (let ((entry (write-complete-project
                  directory '("topology.ivory" "layout.ivory" "device.ivory"
                              "realization.ivory" "composition.ivory"))))
      (project-test-write
       directory "device.ivory"
       "(ivory-key 1)
(define-device board (uses-topology keyboard)
  (place q (:xkb AD01) (:kanata q))
  (unreachable q))")
      (is-equal :duplicate-device-position-coverage
                (project-error-code-from
                 (lambda ()
                   (ivory-key.project:load-project entry :source-roots (list directory)))))))
  (with-project-test-directory (directory)
    (let ((entry (write-complete-project
                  directory '("topology.ivory" "layout.ivory" "device.ivory"
                              "realization.ivory" "composition.ivory"))))
      (project-test-write
       directory "device.ivory"
       "(ivory-key 1)
(define-device board (uses-topology keyboard) (unreachable not-on-topology))")
      (is-equal :unknown-device-position
                (project-error-code-from
                 (lambda ()
                   (ivory-key.project:load-project entry :source-roots (list directory))))))))

(deftest project-loader-rejects-import-cycles-and-root-escapes
  (with-project-test-directory (directory)
    (let ((a (project-test-write directory "a.ivory"
                                 "(ivory-key 1) (import \"b.ivory\")")))
      (project-test-write directory "b.ivory"
                          "(ivory-key 1) (import \"a.ivory\")")
      (is-equal :import-cycle
                (project-error-code-from
                 (lambda () (ivory-key.project:load-project a :source-roots (list directory))))))
  (with-project-test-directory (directory)
    (let* ((root (merge-pathnames "root/" directory))
           (entry (project-test-write root "entry.ivory"
                                      "(ivory-key 1) (import \"../outside.ivory\")")))
      (project-test-write directory "outside.ivory" "(ivory-key 1)")
      (is-equal :import-outside-source-root
                (project-error-code-from
                 (lambda () (ivory-key.project:load-project entry :source-roots (list root)))))))
  (with-project-test-directory (directory)
    (let ((entry (project-test-write directory "entry.ivory"
                                     "(ivory-key 1) (import \"/tmp/nope.ivory\")")))
      (is-equal :absolute-import
                (project-error-code-from
                 (lambda () (ivory-key.project:load-project entry :source-roots (list directory)))))))))

(deftest project-loader-rejects-cross-module-duplicate-definitions
  (with-project-test-directory (directory)
    (let ((entry (project-test-write directory "entry.ivory"
                                     "(ivory-key 1) (import \"one.ivory\") (import \"two.ivory\")")))
      (project-test-write directory "one.ivory"
                          "(ivory-key 1) (define-layout duplicate (binding q (unicode \"q\")))")
      (project-test-write directory "two.ivory"
                          "(ivory-key 1) (define-layout duplicate (binding q (unicode \"Q\")))")
      (is-equal :duplicate-definition
                (project-error-code-from
                 (lambda () (ivory-key.project:load-project entry :source-roots (list directory))))))))

(deftest project-loader-registry-order-is-independent-of-import-order
  (with-project-test-directory (directory)
    (let* ((first (write-complete-project
                   directory '("layout.ivory" "topology.ivory" "composition.ivory"
                               "realization.ivory" "device.ivory")))
           (first-result (ivory-key.project:load-project first :source-roots (list directory)))
           (second (project-test-write directory "second.ivory"
                                       "(ivory-key 1) (import \"device.ivory\") (import \"realization.ivory\") (import \"topology.ivory\") (import \"composition.ivory\") (import \"layout.ivory\")"))
           (second-result (ivory-key.project:load-project second :source-roots (list directory))))
      (is-equal
       (mapcar (lambda (definition)
                 (list (ivory-key.project:project-definition-kind definition)
                       (ivory-key.project:project-definition-name definition)))
               (ivory-key.project:project-load-result-definitions first-result))
       (mapcar (lambda (definition)
                 (list (ivory-key.project:project-definition-kind definition)
                       (ivory-key.project:project-definition-name definition)))
               (ivory-key.project:project-load-result-definitions second-result))))))

(deftest project-loader-never-interns-source-identifiers
  (with-project-test-directory (directory)
    (let* ((name "project-loader-must-not-intern-this")
           (package (find-package :ivory-key.project))
           (entry (project-test-write
                   directory "entry.ivory"
                   "(ivory-key 1) (define-topology project-loader-must-not-intern-this (position project-loader-position))")))
      (is (null (find-symbol (string-upcase name) package)))
      (ivory-key.project:load-project entry :source-roots (list directory))
      (is (null (find-symbol (string-upcase name) package))))))

(deftest project-loader-resolves-named-output-vocabularies-before-profiles
  (with-project-test-directory (directory)
    ;; REALIZATION is deliberately imported first.  Registry construction
    ;; happens after the entire import graph is collected and kind-sorted.
    (let* ((entry (write-output-vocabulary-project
                   directory +project-output-vocabulary+
                   +project-realization-with-output-vocabulary+))
           (result (ivory-key.project:load-project entry :source-roots (list directory)))
           (vocabulary (ivory-key.project::project-output-vocabulary
                        result "synthetic-output" :errorp t))
           (profile (ivory-key.project:project-realization
                     result "synthetic-linux" :errorp t)))
      (is (eq vocabulary (ivory-key.model:realization-profile-vocabulary profile)))
      (is-equal '(("backend-a" "command" "stop-output" "command-stop")
                  ("backend-a" "named-key" "return" "key-return")
                  ("backend-b" "named-key" "return" "b-key-return"))
                (ivory-key.model:output-vocabulary-canonical-data vocabulary))
      (is-equal '((:output-vocabulary "synthetic-output")
                  (:realization "synthetic-linux"))
                (mapcar (lambda (definition)
                          (list (ivory-key.project:project-definition-kind definition)
                                (ivory-key.project:project-definition-name definition)))
                        (ivory-key.project:project-load-result-definitions result))))))

(deftest project-output-vocabulary-surface-fails-closed
  (with-project-test-directory (directory)
    (labels ((load-sources (vocabulary realization)
               (ivory-key.project:load-project
                (write-output-vocabulary-project directory vocabulary realization)
                :source-roots (list directory))))
      (is-equal
       :unknown-output-vocabulary
       (project-error-code-from
        (lambda ()
          (load-sources
           "(ivory-key 1)"
           "(ivory-key 1)
(define-realization missing-vocabulary
  (pipeline backend-a)
  (uses-output-vocabulary absent))"))))
      (is-equal
       :duplicate-vocabulary-backend
       (project-error-code-from
        (lambda ()
          (load-sources
           "(ivory-key 1)
(define-output-vocabulary duplicate-backend
  (backends backend-a BACKEND-A))"
           "(ivory-key 1)"))))
      (is-equal
       :unknown-vocabulary-backend
       (project-error-code-from
        (lambda ()
          (load-sources
           "(ivory-key 1)
(define-output-vocabulary unknown-backend
  (backends backend-a)
  (map-output named-key return (:backend-b \"b-key-return\")))"
           "(ivory-key 1)"))))
      (is-equal
       :unknown-vocabulary-output-kind
       (project-error-code-from
        (lambda ()
          (load-sources
           "(ivory-key 1)
(define-output-vocabulary unknown-kind
  (backends backend-a)
  (map-output carrier-code return (:backend-a \"carrier-return\")))"
           "(ivory-key 1)"))))
      (is-equal
       :duplicate-vocabulary-identity
       (project-error-code-from
        (lambda ()
          (load-sources
           "(ivory-key 1)
(define-output-vocabulary duplicate-identity
  (backends backend-a)
  (map-output named-key return (:backend-a \"key-return\"))
  (map-output named-key RETURN (:backend-a \"other-return\")))"
           "(ivory-key 1)"))))
      (is-equal
       :ambiguous-vocabulary-spelling
       (project-error-code-from
        (lambda ()
          (load-sources
           "(ivory-key 1)
(define-output-vocabulary ambiguous-spelling
  (backends backend-a)
  (map-output named-key return (:backend-a \"same-token\"))
  (map-output named-symbol greek-rho (:backend-a \"same-token\")))"
           "(ivory-key 1)"))))
      (is-equal
       :duplicate-realization-clause
       (project-error-code-from
        (lambda ()
          (load-sources
           +project-output-vocabulary+
           "(ivory-key 1)
(define-realization duplicate-reference
  (pipeline backend-a backend-b)
  (uses-output-vocabulary synthetic-output)
  (uses-output-vocabulary synthetic-output))"))))
      (is-equal
       :missing-vocabulary-entry-spelling
       (project-error-code-from
        (lambda ()
          (load-sources
           "(ivory-key 1)
(define-output-vocabulary missing-spelling
  (backends backend-a)
  (map-output named-key return))"
           "(ivory-key 1)")))))))

(deftest project-output-vocabulary-definitions-reject-duplicate-names
  (with-project-test-directory (directory)
    (let ((entry (project-test-write
                  directory "entry.ivory"
                  "(ivory-key 1) (import \"one.ivory\") (import \"two.ivory\")"))
          (source
            "(ivory-key 1)
(define-output-vocabulary duplicate-vocabulary (backends backend-a))"))
      (project-test-write directory "one.ivory" source)
      (project-test-write directory "two.ivory" source)
      (is-equal :duplicate-definition
                (project-error-code-from
                 (lambda () (ivory-key.project:load-project
                             entry :source-roots (list directory))))))))

(deftest project-output-vocabulary-source-never-interns-identifiers
  (with-project-test-directory (directory)
    (let* ((vocabulary-name "project-vocabulary-must-not-intern")
           (backend-name "project-vocabulary-backend-must-not-intern")
           (identity-name "project-vocabulary-identity-must-not-intern")
           (project-package (find-package :ivory-key.project))
           (model-package (find-package :ivory-key.model))
           (vocabulary-source
             (format nil
                     "(ivory-key 1)
(define-output-vocabulary ~A
  (backends ~A)
  (map-output named-key ~A (:~A \"opaque-token\")))"
                     vocabulary-name backend-name identity-name backend-name))
           (entry (write-output-vocabulary-project directory vocabulary-source
                                                    "(ivory-key 1)")))
      (dolist (name (list vocabulary-name backend-name identity-name))
        (is (null (find-symbol (string-upcase name) project-package)))
        (is (null (find-symbol (string-upcase name) model-package))))
      (ivory-key.project:load-project entry :source-roots (list directory))
      (dolist (name (list vocabulary-name backend-name identity-name))
        (is (null (find-symbol (string-upcase name) project-package)))
        (is (null (find-symbol (string-upcase name) model-package)))))))

(deftest project-realization-interaction-compatibility-is-closed-scoped-and-optional
  "Project source retains no default and accepts only closed target sets."
  (with-project-test-directory (directory)
    (labels ((load-realization (source)
               (let ((entry
                       (write-complete-project
                        directory '("topology.ivory" "layout.ivory" "device.ivory"
                                    "realization.ivory" "composition.ivory"))))
                 (project-test-write directory "realization.ivory" source)
                 (ivory-key.project:project-realization
                  (ivory-key.project:load-project entry :source-roots (list directory))
                  "linux" :errorp t)))
             (source (suffix)
               (format nil
                       "(ivory-key 1)~%(define-realization linux~%  (pipeline kanata xkb)~%  (allow-grades exact emulated)~%  (forbid-shell-actions yes)~%  ~A)"
                       suffix)))
      (dolist (case '(("modern-no-delay" . :modern-no-delay)
                      ("kanata-1-12-buffered" . :kanata-1-12-buffered)))
        (let* ((profile
                 (load-realization
                  (source (format nil "(interaction-compatibility ~A (instances later first))"
                                  (car case)))))
               (policy
                (ivory-key.model::realization-profile-interaction-compatibility-policy
                 profile)))
          (is (typep policy
                     'ivory-key.model::realization-interaction-compatibility-policy))
          (is-equal (cdr case)
                    (ivory-key.model::realization-interaction-compatibility-policy-mode
                     policy))
          (is-equal '("first" "later")
                    (mapcar #'ivory-key.model:identifier-name
                            (ivory-key.model::realization-interaction-compatibility-policy-interactions
                             policy)))))
      (is (null
           (ivory-key.model::realization-profile-interaction-compatibility-policy
            (load-realization (source "")))))
      (let ((uninterned "project-compatibility-mode-must-not-intern")
            (uninterned-target "project-compatibility-target-must-not-intern")
            (package (find-package :ivory-key.project)))
        (is (null (find-symbol (string-upcase uninterned) package)))
        (is (null (find-symbol (string-upcase uninterned-target) package)))
        (is-equal
         :unknown-realization-interaction-compatibility-mode
         (project-error-code-from
          (lambda ()
            (load-realization
             (source (format nil "(interaction-compatibility ~A (instances ~A))"
                             uninterned uninterned-target))))))
        (is (null (find-symbol (string-upcase uninterned) package)))
        (is (null (find-symbol (string-upcase uninterned-target) package))))
      (is-equal
       :duplicate-realization-clause
       (project-error-code-from
        (lambda ()
          (load-realization
           (source "(interaction-compatibility modern-no-delay (instances one)) (interaction-compatibility kanata-1-12-buffered (instances two))")))))
      (is-equal
       :invalid-realization-interaction-compatibility-policy
       (project-error-code-from
        (lambda ()
          ;; Migration checkpoint: the former profile-wide spelling is not an
          ;; implicit all-interactions compatibility selection.
          (load-realization (source "(interaction-compatibility modern-no-delay)")))))
      (is-equal
       :empty-realization-interaction-compatibility-instances
       (project-error-code-from
        (lambda ()
          (load-realization
           (source "(interaction-compatibility modern-no-delay (instances))")))))
      (is-equal
       :duplicate-realization-interaction-compatibility-instance
       (project-error-code-from
        (lambda ()
          (load-realization
           (source "(interaction-compatibility modern-no-delay (instances one ONE))")))))
      (is-equal
       :invalid-realization-interaction-compatibility-policy
       (project-error-code-from
        (lambda ()
          (load-realization
           (source "(interaction-compatibility \"modern-no-delay\" (instances one))"))))))))

(deftest project-realization-buffered-allocation-is-typed-and-policy-scoped
  (with-project-test-directory (directory)
    (labels ((load-realization (source)
               (let ((entry
                       (write-complete-project
                        directory '("topology.ivory" "layout.ivory" "device.ivory"
                                    "realization.ivory" "composition.ivory"))))
                 (project-test-write directory "realization.ivory" source)
                 (ivory-key.project:project-realization
                  (ivory-key.project:load-project entry :source-roots (list directory))
                  "linux" :errorp t)))
             (source (suffix)
               (format nil
                       "(ivory-key 1)~%(define-realization linux~%  (pipeline kanata xkb)~%  (allow-grades exact emulated)~%  (forbid-shell-actions yes)~%  ~A)"
                       suffix)))
      (let* ((profile
               (load-realization
                (source
                 "(interaction-compatibility kanata-1-12-buffered (instances q-tap))
  (kanata-buffered-allocations
    (route q q)
    (action q-tap (tap q) (hold modifier control lctl) (routes q)))")))
             (allocation
               (ivory-key.model::realization-profile-kanata-buffered-allocation-policy
                profile)))
        (is (typep allocation
                   'ivory-key.model::realization-kanata-buffered-allocation-policy))
        (is-equal '("q-tap")
                  (mapcar #'ivory-key.model:identifier-name
                          (mapcar
                           #'ivory-key.model::realization-kanata-buffered-action-interaction
                           (ivory-key.model::realization-kanata-buffered-allocation-policy-actions
                            allocation)))))
      (is-equal
       :kanata-buffered-allocation-without-buffered-policy
       (project-error-code-from
        (lambda ()
          (load-realization
           (source
            "(kanata-buffered-allocations
  (route q q)
  (action q-tap (tap q) (hold modifier control lctl) (routes q)))"))))))))
