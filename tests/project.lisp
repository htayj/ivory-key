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
         (uiop:delete-directory-tree ,directory :validate t)))))

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

(defun write-complete-project (directory imports)
  (project-test-write directory "project.ivory"
                      (format nil "(ivory-key 1)~%~{(import \"~A\")~%~}" imports))
  (project-test-write directory "topology.ivory" +project-topology+)
  (project-test-write directory "layout.ivory" +project-layout+)
  (project-test-write directory "device.ivory" +project-device+)
  (project-test-write directory "realization.ivory" +project-realization+)
  (project-test-write directory "composition.ivory" +project-composition+)
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
